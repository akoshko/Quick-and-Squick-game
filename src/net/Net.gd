extends Node

enum Link { CONNECTING, CONNECTED, RECONNECTING, REJECTED }

signal link_changed(state: int, reason: String)
## Server: a peer confirmed its world scene is ready for the current epoch (NetWorld shows it the characters).
signal world_peer_ready(peer_id: int)

var config: NetConfig
var link: int = Link.CONNECTING
var link_reason: String = ""
var version: String = "dev"
var server: NetServer
var client: NetClient

## World epoch = restart number («Перезапустить мир», §6.4). Server: the current epoch and the peers
## that confirmed it (world_ready). Client: the last epoch from the server, -1 = not known yet.
## Lives on the autoload, not on NetWorld: an RPC to a scene node that arrives in the frame of a
## scene reload (old scene gone, new one not added yet) is dropped.
var world_epoch: int = -1
var world_ready_peers: Dictionary = {}  # server: peer_id -> true


func _ready() -> void:
	var vf := FileAccess.open("res://src/net/version.txt", FileAccess.READ)
	if vf != null:
		var v := vf.get_as_text().strip_edges()
		if v != "":
			version = v
	var is_web := OS.has_feature("web")
	var url := ""
	if is_web:
		url = str(JavaScriptBridge.eval("window.location.href"))
	var env := {}
	for k in ["TURN_SECRET", "TURN_HOST", "ADMIN_TOKEN", "TRANSPORT", "BIND_ADDRESS", "SERVER_USE_TURN"]:
		env[k] = OS.get_environment(k)
	config = NetConfig.parse(OS.get_cmdline_user_args(), url, is_web, env)
	if is_screen():
		# проектор молчит: музыка и звуки игры (GameManager, Sfx) — только на телефонах
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	if not is_network():
		return
	if is_server():
		world_epoch = 0
		multiplayer.peer_connected.connect(_on_world_peer_connected)
		multiplayer.peer_disconnected.connect(_on_world_peer_disconnected)
		server = NetServer.new()
		server.name = "NetServer"
		add_child(server)
	elif is_screen():
		start_client()
	# CLIENT: подключение начинается после создания персонажа (CharacterCreator зовёт start_client),
	# чтобы в hello ушли выбранные ник и внешность


## Клиент (CLIENT, SCREEN): начать подключение к серверу. Повторный вызов и вызов в OFFLINE /
## на сервере ничего не делают.
func start_client() -> void:
	if client != null or not is_network() or is_server():
		return
	add_child(ConnectionOverlay.new())
	client = NetClient.new()
	client.name = "NetClient"
	add_child(client)


func is_network() -> bool:
	return config.mode != NetConfig.Mode.OFFLINE


func is_server() -> bool:
	return config.mode == NetConfig.Mode.SERVER


func is_screen() -> bool:
	return config.mode == NetConfig.Mode.SCREEN


## "dev" is compatible with any version.
static func versions_compatible(a: String, b: String) -> bool:
	return a == "dev" or b == "dev" or a == b


func set_link(state: int, reason := "") -> void:
	if state == link and reason == link_reason:
		return
	link = state
	link_reason = reason
	link_changed.emit(state, reason)


# --- Transport RPCs. They live on the autoload because /root/Net has the same path on server and
# client; NetServer / NetClient handle them.

@rpc("authority", "call_remote", "reliable")
func ping(t: float) -> void:
	if client != null:
		pong.rpc_id(1, t)


@rpc("any_peer", "call_remote", "reliable")
func pong(t: float) -> void:
	if server != null:
		server.on_pong(multiplayer.get_remote_sender_id(), t)


# --- World epoch. The server gives each peer the epoch (on connect and on a world restart); the peer
# answers world_ready once its world scene is ready, and only then does the server make the
# characters visible to it (spawn). So spawns never land in a client scene that is about to be freed.

func _on_world_peer_connected(peer_id: int) -> void:
	set_world_epoch.rpc_id(peer_id, world_epoch, false)


func _on_world_peer_disconnected(peer_id: int) -> void:
	world_ready_peers.erase(peer_id)


## Server, right before reloading its own scene: a new epoch, every peer reloads its scene too.
func restart_world_epoch() -> void:
	world_epoch += 1
	world_ready_peers.clear()
	set_world_epoch.rpc(world_epoch, true)


@rpc("authority", "call_remote", "reliable")
func set_world_epoch(epoch: int, reload: bool) -> void:
	world_epoch = epoch
	if not reload:
		ack_world()
	elif get_tree().current_scene != null:
		# the new NetWorld acks from its _ready. With current_scene == null a reload is already in
		# progress: that new scene is not ready yet and will ack this (newer) epoch as well.
		get_tree().reload_current_scene()


## Client: tell the server the world scene is ready for the current epoch (called from
## NetWorld._ready, and on an epoch that comes without a reload).
func ack_world() -> void:
	if world_epoch < 0 or client == null:
		return
	var mp := multiplayer.multiplayer_peer
	if mp == null or mp is OfflineMultiplayerPeer \
			or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return  # the server sends the epoch on connect (set_world_epoch)
	var scene := get_tree().current_scene
	if scene == null or not scene.is_node_ready() or scene.get_node_or_null("NetWorld") == null:
		return  # the world scene is not in place yet: its NetWorld._ready acks
	world_ready.rpc_id(1, world_epoch)


## Peer -> server. An ack of an older epoch (another restart came in between) is ignored: the
## ack of the new one follows the reload.
@rpc("any_peer", "call_remote", "reliable")
func world_ready(epoch: int) -> void:
	if server == null or epoch != world_epoch:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not peer in multiplayer.get_peers():
		return
	world_ready_peers[peer] = true
	world_peer_ready.emit(peer)


@rpc("any_peer", "call_remote", "reliable")
func register(token: String) -> void:
	if server != null:
		server.on_register(multiplayer.get_remote_sender_id(), token)
