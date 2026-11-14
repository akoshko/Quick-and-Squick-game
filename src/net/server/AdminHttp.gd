class_name AdminHttp
extends Node
## Admin HTTP API (§6.8) on 9081: one request per connection, `Connection: close`, JSON bodies.
## Every route needs the `X-Admin-Token` header. Caddy does not proxy this port.

const PORT := 9081
const MAX_REQUEST := 8192
const READ_TIMEOUT := 2.0
const COTURN_POLL_SECONDS := 5.0
## Одновременных соединений не больше: лишние закрываются сразу (защита от залипших сокетов).
const MAX_CLIENTS := 8
## coturn 4.6 prometheus gauge: current number of allocations (checked against a live coturn).
const COTURN_METRIC := "turn_total_allocations"

const _REASONS := {
	200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed",
	408: "Request Timeout", 413: "Payload Too Large", 501: "Not Implemented", 503: "Service Unavailable",
}

var token := ""
var server: NetServer
var coturn_metrics := "127.0.0.1:9641"

var _tcp := TCPServer.new()
var _clients: Array = []  # {peer: StreamPeerTCP, buf: PackedByteArray, age: float}
var _http: HTTPRequest
var _coturn: Variant = null  # int or null
var _coturn_acc := COTURN_POLL_SECONDS  # poll right away
var _coturn_busy := false


## bind "0.0.0.0" явно: двойной стек ("*") падает на VDS с выключенным IPv6.
func listen(port: int = PORT, bind_address := "0.0.0.0") -> Error:
	return _tcp.listen(port, bind_address)


func get_port() -> int:
	return _tcp.get_local_port()


func _ready() -> void:
	var env := OS.get_environment("COTURN_METRICS")
	if env != "":
		coturn_metrics = env
	_http = HTTPRequest.new()
	_http.timeout = 2.0
	add_child(_http)
	_http.request_completed.connect(_on_coturn_done)


# --- request parsing ---

## `{method, path, headers}` (header names lower-cased) or `{}` when the request line is invalid.
static func parse_request(raw: String) -> Dictionary:
	var head := raw.split("\r\n\r\n", true, 1)[0]
	var lines := head.split("\r\n")
	var parts := lines[0].split(" ")
	if parts.size() != 3 or not parts[2].begins_with("HTTP/"):
		return {}
	var method := parts[0]
	if method == "" or method != method.to_upper():
		return {}
	var path := parts[1]
	if not path.begins_with("/"):
		return {}
	var q := path.find("?")
	if q >= 0:
		path = path.substr(0, q)
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon <= 0:
			continue
		headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	return {"method": method, "path": path, "headers": headers}


# --- routing ---

func route(method: String, path: String, headers: Dictionary) -> Dictionary:
	if token == "" or not _same(str(headers.get("x-admin-token", "")), token):
		return _resp(401, {"error": "unauthorized"})
	var segs := path.trim_prefix("/").trim_suffix("/").split("/")
	var key := ""
	var allowed := "POST"
	var player_id := ""
	if segs.size() == 1 and segs[0] == "stats":
		key = "stats"
		allowed = "GET"
	elif segs.size() == 2 and segs[0] == "world" and segs[1] == "restart":
		key = "world_restart"
	elif segs.size() == 2 and segs[0] == "progress" and segs[1] == "reset":
		key = "progress_reset"
	elif segs.size() == 2 and segs[0] == "boss" and segs[1] == "restart":
		key = "boss_restart"
	elif segs.size() == 2 and segs[0] == "achievements" and segs[1] == "reset":
		key = "not_impl"
	elif segs.size() == 3 and segs[0] == "players" and segs[2] == "kick":
		key = "kick"
		player_id = segs[1]
	elif segs.size() == 3 and segs[0] == "players" and segs[2] == "unban":
		key = "unban"
		player_id = segs[1]
	elif segs.size() == 4 and segs[0] == "players" and segs[2] == "achievements" and segs[3] == "reset":
		key = "not_impl"
	else:
		return _resp(404, {"error": "not found"})
	if method != allowed:
		return _resp(405, {"error": "method not allowed"})
	match key:
		"stats":
			return _resp(200, _stats())
		"world_restart":
			var world := _net_world()
			if world == null:
				return _resp(503, {"error": "world not ready"})
			world.restart_world()
			return _resp(200, {"ok": true})
		"progress_reset":
			var tree := get_tree()
			if tree == null:
				return _resp(503, {"error": "no tree"})
			tree.root.get_node("GameManager").reset()
			tree.root.get_node("Quests").reset()
			return _resp(200, {"ok": true})
		"boss_restart":
			var director := _boss_director()
			if director == null:
				return _resp(503, {"error": "boss director not ready"})
			director.restart_boss()
			return _resp(200, {"ok": true})
		"kick":
			if server == null or not server.kick(player_id):
				return _resp(404, {"error": "no such player"})
			return _resp(200, {"ok": true})
		"unban":
			if server == null or not server.unban(player_id):
				return _resp(404, {"error": "not banned"})
			return _resp(200, {"ok": true})
	return _resp(501, {"error": "not implemented"})


static func _resp(status: int, body: Dictionary) -> Dictionary:
	return {"status": status, "body": body}


## Compare without bailing out at the first differing byte.
static func _same(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	var diff := x.size() ^ y.size()
	for i in mini(x.size(), y.size()):
		diff |= x[i] ^ y[i]
	return diff == 0


func _scene() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


func _net_world() -> Node:
	var scene := _scene()
	return scene.get_node_or_null("NetWorld") if scene != null else null


func _boss_director() -> Node:
	var scene := _scene()
	return scene.get_node_or_null("BossDirector") if scene != null else null


func _stats() -> Dictionary:
	var loop := Engine.get_main_loop() as SceneTree
	var net: Node = loop.root.get_node_or_null("Net") if loop != null else null
	var now_s := Time.get_ticks_msec() / 1000.0
	var list: Array = []
	var banned: Array = []
	var world := _net_world()
	var players := 0
	var held := 0
	var screens := 0
	var started := 0.0
	if server != null:
		started = server.started_at
		screens = server.screen_count()
		for rec in server.registry.records():
			if rec.state == "connected":
				players += 1
			elif rec.state == "held":
				held += 1
			var node: Node = world._player(rec.player_id) if world != null else null
			list.append({
				"player_id": rec.player_id,
				"name": node.display_name() if node != null else "Игрок %d" % rec.number,
				"skin": node.skin_id() if node != null else "",
				"number": rec.number,
				"state": rec.state,
				"rtt_ms": server.rtt_ms(rec.peer_id) if rec.state == "connected" else -1,
				"online_s": int(now_s - rec.joined_at),
				"reconnects": rec.reconnects,
				"candidate_types": Array(server.candidate_types(rec.player_id)),
			})
		for b in server.registry.banned():
			banned.append({
				"player_id": b.player_id, "number": b.number, "name": b.name,
				"kicked_at_s": maxi(0, int(now_s - b.at)),  # секунды назад
			})
	return {
		"uptime_s": int(Time.get_unix_time_from_system() - started) if started > 0.0 else 0,
		"version": net.version if net != null else "dev",
		"transport": net.config.transport if net != null and net.config != null else "",
		"players": players,
		"screens": screens,
		"held": held,
		"coturn_allocations": _coturn,
		"list": list,
		"banned": banned,
	}


# --- coturn metrics (polled in the background, at most every 5 s) ---

func _poll_coturn(delta: float) -> void:
	_coturn_acc += delta
	if _coturn_busy or _coturn_acc < COTURN_POLL_SECONDS or not is_inside_tree():
		return
	_coturn_acc = 0.0
	if _http.request("http://%s/metrics" % coturn_metrics) == OK:
		_coturn_busy = true
	else:
		_coturn = null


func _on_coturn_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_coturn_busy = false
	_coturn = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	_coturn = parse_allocations(body.get_string_from_utf8())


## Sum of the allocation gauge over all label sets, or null when the metric is absent.
static func parse_allocations(text: String) -> Variant:
	var total := 0
	var found := false
	for line in text.split("\n"):
		if not line.begins_with(COTURN_METRIC):
			continue
		var rest := line.substr(COTURN_METRIC.length())
		if rest != "" and not rest.begins_with("{") and not rest.begins_with(" "):
			continue  # a longer metric name sharing the prefix
		var val := line.strip_edges().get_slice(" ", line.strip_edges().get_slice_count(" ") - 1)
		if val.is_valid_float():
			total += int(val.to_float())
			found = true
	return total if found else null


# --- transport ---

func _process(delta: float) -> void:
	_poll_coturn(delta)
	while _tcp.is_listening() and _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		_clients.append({"peer": peer, "buf": PackedByteArray(), "age": 0.0})
	for c: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		c.age += delta
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_data(n)
			if got[0] == OK:
				c.buf.append_array(got[1])
		var text: String = c.buf.get_string_from_utf8()
		if text.contains("\r\n\r\n"):
			_finish(c, text)
		elif c.buf.size() > MAX_REQUEST:
			_send(c, 413, {"error": "request too large"})
		elif c.age > READ_TIMEOUT:
			_send(c, 408, {"error": "request timeout"})


func _finish(c: Dictionary, text: String) -> void:
	var req := parse_request(text)
	if req.is_empty():
		_send(c, 400, {"error": "bad request"})
		return
	var res := route(req.method, req.path, req.headers)
	_send(c, res.status, res.body)


func _send(c: Dictionary, status: int, body: Dictionary) -> void:
	var payload := JSON.stringify(body).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		status, _REASONS.get(status, "Error"), payload.size()]
	var peer: StreamPeerTCP = c.peer
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(payload)
	peer.disconnect_from_host()
	_clients.erase(c)
