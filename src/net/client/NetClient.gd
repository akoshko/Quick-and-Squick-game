class_name NetClient
extends Node
## Browser client transport: signaling WS -> hello/welcome -> WebRTC (or WS /ws-game) peer,
## keepalive, reconnect with backoff. Drives _net.link.

const CONNECT_TIMEOUT := 15.0
const KEEPALIVE_SECONDS := 5.0
const KEEPALIVE_TIMEOUT := 15.0

var peer_id: int = 0
var player_id: String = ""
var number: int = 0

# the Net autoload, looked up at runtime (autoload names are not known to `--script` checks)
@onready var _net: Node = get_node("/root/Net")
var _ws: WebSocketPeer
var _ws_open := false
var _pc: WebRTCPeerConnection
var _mp: MultiplayerPeer
var _attempt := 0
var _active := false  # an attempt is in progress (ws or peer alive)
var _connected := false
var _attempt_started := 0.0
var _last_seen := 0.0
var _last_ping := 0.0
var _retry_at := -1.0
var _rejected := false
var _attempt_id := 0  # increments per attempt; stale peer-connection signals are ignored


static func backoff_delay(attempt: int) -> float:
	if attempt >= 4:
		return 10.0
	return float(1 << maxi(attempt, 0))


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(func() -> void: _fail("server_disconnected"))
	multiplayer.connection_failed.connect(func() -> void: _fail("connection_failed"))
	if not _net.is_screen():
		PlayerProfile.accessory_changed.connect(_send_accessory)
	_net.set_link(_net.Link.CONNECTING)
	_start()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _start() -> void:
	_attempt_id += 1
	_retry_at = -1.0
	_active = true
	_connected = false
	_ws_open = false
	_attempt_started = _now()
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(_net.config.signaling_url)
	print("NET: connecting %s (attempt %d)" % [_net.config.signaling_url, _attempt])
	if err != OK:
		_fail("ws connect error %s" % error_string(err))


func _process(_delta: float) -> void:
	var now := _now()
	if not _active:
		if _retry_at >= 0.0 and now >= _retry_at and not _rejected:
			_start()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _ws_open:
			_ws_open = true
			_last_seen = now
			_last_ping = now
			var hello := {
				"token": TokenStore.load_or_create(),
				"role": "screen" if _net.is_screen() else "player",
				"version": _net.version,
			}
			# ник и внешность из создания персонажа (формат PlayerProfile.to_dict); сервер их проверяет
			var profile := get_node_or_null("/root/PlayerProfile")
			if not _net.is_screen() and profile != null:
				hello["profile"] = profile.to_dict()
			_send(Msg.HELLO, hello)
		while _ws.get_available_packet_count() > 0:
			var m := Msg.decode(_ws.get_packet().get_string_from_utf8())
			if m.is_empty():
				continue
			_last_seen = now
			_on_message(m)
			if not _active:
				return
		if now - _last_ping >= KEEPALIVE_SECONDS:
			_last_ping = now
			_send(Msg.PING)
		if now - _last_seen > KEEPALIVE_TIMEOUT:
			_fail("signaling keepalive timeout")
			return
	elif st == WebSocketPeer.STATE_CLOSED:
		_fail("signaling closed (code %d)" % _ws.get_close_code())
		return
	if not _connected and now - _attempt_started > CONNECT_TIMEOUT:
		_fail("not connected in %ds" % int(CONNECT_TIMEOUT))


func _on_message(m: Dictionary) -> void:
	match m.t:
		Msg.WELCOME:
			_on_welcome(m)
		Msg.REJECTED:
			var reason := str(m.get("reason", ""))
			print("NET: rejected: %s" % reason)
			_rejected = true
			_teardown()
			_net.set_link(_net.Link.REJECTED, reason)
		Msg.OFFER:
			if _pc != null:
				_pc.set_remote_description("offer", str(m.get("sdp", "")))
		Msg.CANDIDATE:
			if _pc != null:
				_pc.add_ice_candidate(str(m.get("mid", "")), int(m.get("index", 0)), str(m.get("cand", "")))
		Msg.PING:
			_send(Msg.PONG)
		Msg.PONG:
			pass


func _on_welcome(m: Dictionary) -> void:
	player_id = str(m.get("player_id", ""))
	number = int(m.get("number", 0))
	var transport := str(m.get("transport", "webrtc"))
	print("NET: welcome %s number=%d transport=%s" % [player_id, number, transport])
	if transport == "ws":
		var wsp := WebSocketMultiplayerPeer.new()
		var url: String = _net.config.signaling_url + "-game"
		var err := wsp.create_client(url)
		if err != OK:
			_fail("ws-game create_client %s" % error_string(err))
			return
		_mp = wsp
		multiplayer.multiplayer_peer = wsp
		return
	peer_id = int(m.get("peer_id", 0))
	var rtc := WebRTCMultiplayerPeer.new()
	var err := rtc.create_client(peer_id, [MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED])
	if err != OK:
		_fail("webrtc create_client %s" % error_string(err))
		return
	var cfg := {"iceServers": m.get("ice_servers", [])}
	if _net.config.force_relay:
		cfg["iceTransportPolicy"] = "relay"
	_pc = WebRTCPeerConnection.new()
	err = _pc.initialize(cfg)
	if err != OK:
		_fail("pc.initialize %s" % error_string(err))
		return
	# bound methods with the attempt number, not lambdas capturing the pc (cycle -> leak per reconnect)
	_pc.session_description_created.connect(_on_pc_sdp.bind(_attempt_id))
	_pc.ice_candidate_created.connect(_on_pc_candidate.bind(_attempt_id))
	rtc.add_peer(_pc, 1)
	_mp = rtc
	multiplayer.multiplayer_peer = rtc


func _on_pc_sdp(type: String, sdp: String, attempt_id: int) -> void:
	if attempt_id != _attempt_id or _pc == null:
		return
	_pc.set_local_description(type, sdp)
	_send(type, {"sdp": sdp})


func _on_pc_candidate(mid: String, index: int, cand: String, attempt_id: int) -> void:
	if attempt_id != _attempt_id or _pc == null:
		return
	_send(Msg.CANDIDATE, {"mid": mid, "index": index, "cand": cand})


func _on_connected() -> void:
	if not _active:
		return
	_connected = true
	_attempt = 0
	peer_id = multiplayer.get_unique_id()
	print("NET: connected peer=%d after %.2fs" % [peer_id, _now() - _attempt_started])
	if _mp is WebSocketMultiplayerPeer:
		_net.register.rpc_id(1, TokenStore.load_or_create())
	_send_accessory(PlayerProfile.accessory)
	_send_accessory(PlayerProfile.nickname_color)
	_net.set_link(_net.Link.CONNECTED)


func _send_accessory(id: String) -> void:
	if not _net.is_screen() and _connected and _mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_net.equip_accessory.rpc_id(1, id)


func _send(type: String, data := {}) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(Msg.encode(type, data))


## Any break: close everything and retry after backoff_delay.
func _fail(why: String) -> void:
	if not _active or _rejected:
		return
	# A `rejected` sent right before the close may still be queued (e.g. a background tab that was
	# replaced wakes up and sees the peer drop first): it wins over reconnecting.
	if _ws != null:
		_ws.poll()
		while _ws.get_available_packet_count() > 0:
			var m := Msg.decode(_ws.get_packet().get_string_from_utf8())
			if not m.is_empty() and m.t == Msg.REJECTED:
				_on_message(m)
				return
	var delay := backoff_delay(_attempt)
	print("NET: connection lost: %s; retry in %ds" % [why, int(delay)])
	push_warning("NET: connection lost: " + why)
	_attempt += 1
	_teardown()
	_retry_at = _now() + delay
	_net.set_link(_net.Link.RECONNECTING)


func _teardown() -> void:
	_active = false
	_connected = false
	if _ws != null:
		_ws.close()
	_ws = null
	_ws_open = false
	if _pc != null:
		_pc.close()
	_pc = null
	if _mp != null:
		_mp.close()
	_mp = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
