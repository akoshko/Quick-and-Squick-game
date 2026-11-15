class_name NetServer
extends Node
## Server side of the transport: signaling (9080), player admission, WebRTC (or WS 9082) peers,
## keepalive, RTT pings and reconnect hold.

signal player_joined(player_id: String, peer_id: int)
signal player_held(player_id: String)
signal player_removed(player_id: String)

const SIGNALING_PORT := 9080
const WS_GAME_PORT := 9082
const KEEPALIVE_SECONDS := 5.0
const KEEPALIVE_TIMEOUT := 15.0
const HELLO_TIMEOUT := 10.0
const RTT_PING_SECONDS := 2.0
const REGISTER_TIMEOUT := 10.0

var registry := PlayerRegistry.new()
var started_at: float = 0.0

# the Net autoload, looked up at runtime (autoload names are not known to `--script` checks)
@onready var _net: Node = get_node("/root/Net")
var _sig := SignalingServer.new()
var _transport := "webrtc"
var _rtc: WebRTCMultiplayerPeer
var _wsp: WebSocketMultiplayerPeer
var _next_peer := 2
# conn_id -> {hello: bool, opened_at, last_seen, last_ping, token, role, player_id, peer_id, pc}
var _conns: Dictionary = {}
var _peer_conn: Dictionary = {}  # peer_id (negative placeholder in ws mode until register) -> conn_id
var _rtt: Dictionary = {}  # peer_id -> ms
var _cand_types: Dictionary = {}  # player_id -> PackedStringArray
var _ws_unregistered: Dictionary = {}  # ws mode: peer_id on 9082 -> connected_at, until register(token)
var _expire_acc := 0.0
var _rtt_acc := 0.0


func _ready() -> void:
	started_at = Time.get_unix_time_from_system()
	_transport = _net.config.transport
	add_child(_sig)
	_sig.opened.connect(func(conn_id: int) -> void: _conns[conn_id] = _new_conn())
	_sig.message.connect(_on_message)
	_sig.closed.connect(_on_closed)
	var bind: String = _net.config.bind_address
	var err := _sig.listen(SIGNALING_PORT, bind)
	if err != OK:
		push_error("NET: signaling listen %d failed: %s" % [SIGNALING_PORT, error_string(err)])
		return
	if _transport == "ws":
		_wsp = WebSocketMultiplayerPeer.new()
		err = _wsp.create_server(WS_GAME_PORT, bind)
		if err != OK:
			push_error("NET: ws transport listen %d failed: %s" % [WS_GAME_PORT, error_string(err)])
			return
		multiplayer.multiplayer_peer = _wsp
	else:
		_rtc = WebRTCMultiplayerPeer.new()
		err = _rtc.create_server([MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED])
		if err != OK:
			push_error("NET: webrtc create_server failed: %s" % error_string(err))
			return
		multiplayer.multiplayer_peer = _rtc
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("NET: server listening %d transport=%s" % [SIGNALING_PORT, _transport])
	if _net.config.turn_secret == "":
		push_error("NET: TURN_SECRET is not set: clients get no TURN/STUN servers (ice_servers empty)")
	_start_admin()


func _start_admin() -> void:
	var token: String = _net.config.admin_token
	if token == "":
		print("NET: admin disabled (no ADMIN_TOKEN)")
		return
	var admin := AdminHttp.new()
	admin.name = "AdminHttp"
	admin.token = token
	admin.server = self
	add_child(admin)
	var err := admin.listen(AdminHttp.PORT, _net.config.bind_address)
	if err != OK:
		push_error("NET: admin listen %d failed: %s" % [AdminHttp.PORT, error_string(err)])
		return
	print("NET: admin listening %d" % AdminHttp.PORT)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- public API ---

func kick(player_id: String) -> bool:
	var known := false
	for rec in registry.records():
		if rec.player_id == player_id:
			known = true
	if not known:
		return false
	var peer := registry.ban(player_id, _now())
	var conn_id := _conn_for_player(player_id)
	if conn_id != 0:
		_reject_and_drop(conn_id, "kicked")
	elif peer != 0:
		_remove_mp_peer(peer)
	_cand_types.erase(player_id)
	print("NET: removed %s (kicked)" % player_id)
	player_removed.emit(player_id)
	return true


func unban(player_id: String) -> bool:
	if not registry.unban(player_id):
		return false
	print("NET: unbanned %s" % player_id)
	return true


## Admitted connections with the screen role (the registry does not track screens).
func screen_count() -> int:
	var n := 0
	for c: Dictionary in _conns.values():
		if c.hello and c.role == "screen":
			n += 1
	return n


func rtt_ms(peer_id: int) -> int:
	return int(_rtt.get(peer_id, -1))


func candidate_types(player_id: String) -> PackedStringArray:
	return _cand_types.get(player_id, PackedStringArray())


# --- loop ---

func _process(delta: float) -> void:
	var now := _now()
	for conn_id: int in _conns.keys():
		if not _conns.has(conn_id):
			continue
		var c: Dictionary = _conns[conn_id]
		if not c.hello:
			if now - c.opened_at > HELLO_TIMEOUT:
				print("NET: conn %d: no hello in %ds, closing" % [conn_id, int(HELLO_TIMEOUT)])
				_drop(conn_id)
			continue
		if now - c.last_seen > KEEPALIVE_TIMEOUT:
			print("NET: conn %d (%s): keepalive timeout" % [conn_id, c.player_id])
			_drop(conn_id)
			continue
		if now - c.last_ping >= KEEPALIVE_SECONDS:
			c.last_ping = now
			_sig.send(conn_id, Msg.encode(Msg.PING))
	for peer: int in _ws_unregistered.keys():
		if now - float(_ws_unregistered[peer]) > REGISTER_TIMEOUT:
			print("NET: ws peer %d: no register in %ds, disconnecting" % [peer, int(REGISTER_TIMEOUT)])
			_ws_unregistered.erase(peer)
			_wsp.disconnect_peer(peer)
	_expire_acc += delta
	if _expire_acc >= 1.0:
		_expire_acc = 0.0
		for pid in registry.expire(now):
			_cand_types.erase(pid)
			print("NET: removed %s" % pid)
			player_removed.emit(pid)
	_rtt_acc += delta
	if _rtt_acc >= RTT_PING_SECONDS:
		_rtt_acc = 0.0
		var t := _now()
		for peer in multiplayer.get_peers():
			if _peer_conn.has(peer):  # only peers bound to an admitted connection (ws: registered)
				_net.ping.rpc_id(peer, t)


func on_pong(peer_id: int, t: float) -> void:
	_rtt[peer_id] = int((_now() - t) * 1000.0)


# --- signaling ---

func _on_message(conn_id: int, m: Dictionary) -> void:
	if not _conns.has(conn_id):
		return
	var c: Dictionary = _conns[conn_id]
	c.last_seen = _now()
	match m.t:
		Msg.HELLO:
			_on_hello(conn_id, m)
		Msg.PING:
			_sig.send(conn_id, Msg.encode(Msg.PONG))
		Msg.PONG:
			pass
		Msg.ANSWER:
			if c.pc != null:
				c.pc.set_remote_description("answer", str(m.get("sdp", "")))
		Msg.CANDIDATE:
			if c.pc != null:
				var cand := str(m.get("cand", ""))
				c.pc.add_ice_candidate(str(m.get("mid", "")), int(m.get("index", 0)), cand)
				_note_candidate(c.player_id, cand)


func _new_conn() -> Dictionary:
	var now := _now()
	return {
		"hello": false, "opened_at": now, "last_seen": now, "last_ping": now,
		"token": "", "role": "", "player_id": "", "peer_id": 0, "pc": null,
	}


func _on_hello(conn_id: int, m: Dictionary) -> void:
	var c: Dictionary = _conns[conn_id]
	if c.hello:
		return
	c.hello = true
	var version := str(m.get("version", ""))
	if not _net.versions_compatible(version, _net.version):
		_reject_and_drop(conn_id, "version_mismatch")
		return
	var token := str(m.get("token", ""))
	var role := str(m.get("role", ""))
	# профиль (ник и внешность из создания персонажа) проверяет и хранит реестр
	var res := registry.admit(token, role, _now(), m.get("profile", {}))
	if not res.ok:
		_reject_and_drop(conn_id, res.reason)
		return
	c.token = token
	c.role = role
	c.player_id = res.player_id
	var peer_id := 0
	if _transport == "ws":
		peer_id = -conn_id  # placeholder until the client registers over /ws-game
	else:
		peer_id = _next_peer
		_next_peer += 1
	c.peer_id = peer_id
	_peer_conn[peer_id] = conn_id
	if c.player_id != "":
		# Bind the new peer BEFORE dropping the replaced one, so its close cannot mark the player held.
		registry.bind_peer(c.player_id, peer_id)
		_cand_types[c.player_id] = PackedStringArray()
	if res.replaced_peer != 0:
		var old_conn: int = _peer_conn.get(res.replaced_peer, 0)
		print("NET: %s replaced: peer %d -> %d" % [c.player_id, res.replaced_peer, peer_id])
		if old_conn != 0 and old_conn != conn_id:
			_reject_and_drop(old_conn, "replaced")
		else:
			_remove_mp_peer(res.replaced_peer)
	var ice: Array = []
	if _net.config.turn_secret != "":
		var creds := TurnCredentials.make(_net.config.turn_secret, c.player_id if c.player_id != "" else "screen%d" % conn_id, int(Time.get_unix_time_from_system()))
		ice = TurnCredentials.ice_servers(_net.config.turn_host, creds)
	_sig.send(conn_id, Msg.encode(Msg.WELCOME, {
		"peer_id": peer_id if _transport == "webrtc" else 0,
		"transport": _transport,
		"ice_servers": ice,
		"player_id": c.player_id,
		"number": res.number,
	}))
	if _transport == "webrtc":
		_start_webrtc(conn_id, peer_id, ice)


func _start_webrtc(conn_id: int, peer_id: int, ice: Array) -> void:
	var c: Dictionary = _conns[conn_id]
	var pc := WebRTCPeerConnection.new()
	var err := pc.initialize({"iceServers": _server_ice(ice, _net.config.server_use_turn)})
	if err != OK:
		push_error("NET: pc.initialize failed: %s" % error_string(err))
		_drop(conn_id)
		return
	# bound methods, not lambdas capturing `pc`: a lambda on pc's own signal holding pc is a cycle (leak)
	pc.session_description_created.connect(_on_pc_sdp.bind(conn_id))
	pc.ice_candidate_created.connect(_on_pc_candidate.bind(conn_id))
	c.pc = pc
	_rtc.add_peer(pc, peer_id)
	pc.create_offer()


func _on_pc_sdp(type: String, sdp: String, conn_id: int) -> void:
	if not _conns.has(conn_id) or _conns[conn_id].pc == null:
		return
	_conns[conn_id].pc.set_local_description(type, sdp)
	_sig.send(conn_id, Msg.encode(type, {"sdp": sdp}))


func _on_pc_candidate(mid: String, index: int, cand: String, conn_id: int) -> void:
	if _conns.has(conn_id):
		_sig.send(conn_id, Msg.encode(Msg.CANDIDATE, {"mid": mid, "index": index, "cand": cand}))


## ICE servers for the server's own end of each connection. By default STUN only: on the prod VDS
## (host network, public IP) a server-side TURN allocation per player would only eat coturn's relay
## ports; the browser's relay candidate reaches the server's public IP directly.
## use_turn (SERVER_USE_TURN=1, local Docker bridge only) also keeps turn:...udp
## (libjuice in webrtc-native only does UDP).
static func _server_ice(ice: Array, use_turn := false) -> Array:
	var out: Array = []
	for srv: Dictionary in ice:
		var urls: Array = []
		for u: String in srv.get("urls", []):
			if u.begins_with("stun:") or (use_turn and u.begins_with("turn:") and u.ends_with("transport=udp")):
				urls.append(u)
		if not urls.is_empty():
			var d := srv.duplicate()
			d["urls"] = urls
			out.append(d)
	return out


func on_register(peer_id: int, token: String) -> void:
	if _transport != "ws":
		return
	for conn_id: int in _conns:
		var c: Dictionary = _conns[conn_id]
		if c.hello and c.token == token and c.peer_id < 0:
			_ws_unregistered.erase(peer_id)
			_peer_conn.erase(c.peer_id)
			c.peer_id = peer_id
			_peer_conn[peer_id] = conn_id
			if c.player_id != "":
				registry.bind_peer(c.player_id, peer_id)
			_announce_join(conn_id)
			return
	push_warning("NET: register from peer %d with unknown token" % peer_id)
	_ws_unregistered.erase(peer_id)
	_wsp.disconnect_peer(peer_id)


func _note_candidate(player_id: String, cand: String) -> void:
	if player_id == "":
		return
	var parts := cand.split(" ", false)
	var i := parts.find("typ")
	if i < 0 or i + 1 >= parts.size():
		return
	var typ := parts[i + 1]
	if not typ in ["host", "srflx", "prflx", "relay"]:
		return
	var types: PackedStringArray = _cand_types.get(player_id, PackedStringArray())
	if not typ in types:
		types.append(typ)
		_cand_types[player_id] = types


# --- connection lifecycle ---

func _on_peer_connected(peer_id: int) -> void:
	if _transport == "ws" and not _peer_conn.has(peer_id):
		_ws_unregistered[peer_id] = _now()
	if _transport == "webrtc" and _peer_conn.has(peer_id):
		_announce_join(_peer_conn[peer_id])


func _announce_join(conn_id: int) -> void:
	var c: Dictionary = _conns[conn_id]
	if c.player_id == "":
		print("NET: screen joined peer=%d" % c.peer_id)
		return
	print("NET: joined %s peer=%d" % [c.player_id, c.peer_id])
	player_joined.emit(c.player_id, c.peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_rtt.erase(peer_id)
	_ws_unregistered.erase(peer_id)
	if _peer_conn.has(peer_id):
		_drop(_peer_conn[peer_id])


func _on_closed(conn_id: int) -> void:
	_drop(conn_id)


func _conn_for_player(player_id: String) -> int:
	for conn_id: int in _conns:
		if _conns[conn_id].player_id == player_id:
			return conn_id
	return 0


func _reject_and_drop(conn_id: int, reason: String) -> void:
	print("NET: conn %d rejected: %s" % [conn_id, reason])
	_sig.send(conn_id, Msg.encode(Msg.REJECTED, {"reason": reason}))
	_drop(conn_id)


## Forget a signaling connection: close it, remove its multiplayer peer, hold its player.
## Lost events for a peer that is no longer the player's current peer are ignored by the registry.
func _drop(conn_id: int) -> void:
	if not _conns.has(conn_id):
		_sig.close(conn_id)
		return
	var c: Dictionary = _conns[conn_id]
	_conns.erase(conn_id)
	_sig.close(conn_id)
	if c.pc != null:
		c.pc.close()
		c.pc = null
	if c.peer_id != 0:
		_peer_conn.erase(c.peer_id)
		_remove_mp_peer(c.peer_id)
		var held := registry.peer_lost(c.peer_id, _now())
		if held != "":
			print("NET: held %s" % held)
			player_held.emit(held)


func _remove_mp_peer(peer_id: int) -> void:
	_rtt.erase(peer_id)
	if peer_id <= 0:
		return
	if _rtc != null and _rtc.has_peer(peer_id):
		_rtc.remove_peer(peer_id)
	elif _wsp != null and peer_id in multiplayer.get_peers():
		_wsp.disconnect_peer(peer_id)
