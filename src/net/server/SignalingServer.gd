class_name SignalingServer
extends Node
## Plain-ws signaling endpoint (TLS is terminated by Caddy in front).

signal opened(conn_id: int)
signal message(conn_id: int, msg: Dictionary)
signal closed(conn_id: int)

const HANDSHAKE_TIMEOUT := 5.0

var _tcp := TCPServer.new()
var _conns: Dictionary = {}  # conn_id -> {ws: WebSocketPeer, age: float, open: bool}
var _next_id := 1


func listen(port: int, bind_address := "0.0.0.0") -> Error:
	return _tcp.listen(port, bind_address)


func get_port() -> int:
	return _tcp.get_local_port()


func send(conn_id: int, text: String) -> void:
	if _conns.has(conn_id) and _conns[conn_id].open:
		_conns[conn_id].ws.send_text(text)


func close(conn_id: int, reason := "") -> void:
	if _conns.has(conn_id):
		_conns[conn_id].ws.close(1000, reason)


func _process(delta: float) -> void:
	while _tcp.is_listening() and _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		if ws.accept_stream(stream) != OK:
			continue
		_conns[_next_id] = {"ws": ws, "age": 0.0, "open": false}
		_next_id += 1
	for id: int in _conns.keys():
		var c: Dictionary = _conns[id]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_CONNECTING:
				c.age += delta
				if c.age > HANDSHAKE_TIMEOUT:
					_conns.erase(id)
			WebSocketPeer.STATE_OPEN:
				if not c.open:
					c.open = true
					opened.emit(id)
				while ws.get_available_packet_count() > 0:
					var text := ws.get_packet().get_string_from_utf8()
					var m := Msg.decode(text)
					if m.is_empty():
						push_warning("signaling: invalid message from %d" % id)
						continue
					message.emit(id, m)
			WebSocketPeer.STATE_CLOSED:
				_conns.erase(id)
				if c.open:
					closed.emit(id)
