class_name NetConfig
extends RefCounted

enum Mode { OFFLINE, CLIENT, SCREEN, SERVER }

var mode: Mode = Mode.OFFLINE
var signaling_url: String = ""
var transport: String = "webrtc"
var force_relay: bool = false
var share_url: String = ""
var turn_secret: String = ""
var turn_host: String = ""
var admin_token: String = ""
## Адрес для TCP-портов сервера (9080/9081/9082). IPv4 явно: на VDS без IPv6 "*" не слушает.
var bind_address: String = "0.0.0.0"
## Своему WebRTC сервер даёт TURN только при SERVER_USE_TURN=1 (локальный Docker bridge);
## на проде (сеть хоста, публичный IP) хватает STUN и TURN-аллокации не тратятся.
var server_use_turn: bool = false


static func parse(args: PackedStringArray, page_url: String, is_web: bool, env: Dictionary) -> NetConfig:
	var c := NetConfig.new()
	c.turn_secret = str(env.get("TURN_SECRET", ""))
	c.turn_host = str(env.get("TURN_HOST", ""))
	c.admin_token = str(env.get("ADMIN_TOKEN", ""))
	if str(env.get("BIND_ADDRESS", "")) != "":
		c.bind_address = str(env.get("BIND_ADDRESS", ""))
	c.server_use_turn = str(env.get("SERVER_USE_TURN", "")) == "1"
	if "--transport=ws" in args or str(env.get("TRANSPORT", "")) == "ws":
		c.transport = "ws"
	if is_web:
		c.mode = Mode.CLIENT
		var url := page_url
		var hash_i := url.find("#")
		if hash_i >= 0:
			url = url.substr(0, hash_i)
		var query := ""
		var q_i := url.find("?")
		if q_i >= 0:
			query = url.substr(q_i + 1)
			url = url.substr(0, q_i)
		var scheme := ""
		var rest := url
		var s_i := url.find("://")
		if s_i >= 0:
			scheme = url.substr(0, s_i)
			rest = url.substr(s_i + 3)
		var host := rest
		var path := ""
		var p_i := rest.find("/")
		if p_i >= 0:
			host = rest.substr(0, p_i)
			path = rest.substr(p_i)
		else:
			path = "/"
		c.share_url = "%s://%s%s" % [scheme, host, path]
		c.signaling_url = ("wss" if scheme == "https" else "ws") + "://" + host + "/ws"
		for pair in query.split("&", false):
			var kv := pair.split("=", true, 1)
			var val := kv[1] if kv.size() > 1 else ""
			if kv[0] == "view" and val == "screen":
				c.mode = Mode.SCREEN
			elif kv[0] == "relay" and val == "1":
				c.force_relay = true
	elif "--server" in args:
		c.mode = Mode.SERVER
	return c
