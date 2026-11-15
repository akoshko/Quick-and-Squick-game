extends Node

enum Link { CONNECTING, CONNECTED, RECONNECTING, REJECTED }

## Сервер, as_actor: личные события вне действия игрока — всем игрокам
const ACTOR_EVERYONE := 0
## Сервер, as_actor: личные события действия отключённого игрока — никому
const ACTOR_NOBODY := -1
## Какие личные события сервер может вызвать у клиента (personal_call): autoload -> методы.
## Каждый вызов forward_personal должен быть в этом списке, иначе клиент его молча проигнорирует.
const PERSONAL_CALLS := {
	&"Quests": [&"complete", &"remove_quest", &"reset", &"net_add_quest"],
	&"GameManager": [&"unlock_achievement", &"sync_reward_achievements", &"reset_achievements"],
}

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

## Клиент: сейчас применяется состояние или вызов с сервера (replay). Свои всплывающие тексты и
## звуки мира в это время не создаются — сервер присылает их сам (route_fx), иначе они бы удвоились.
var replaying := false
## Сервер: пир, от имени чьего персонажа сейчас выполняется действие; личные события (квесты,
## ачивки) уходят ему. ACTOR_EVERYONE — всем игрокам, ACTOR_NOBODY — никому (игрок отключён).
var _actor_peer := ACTOR_EVERYONE


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


# --- Общий мир (gameplay sync). Мир один и живёт на сервере: сервер (и одиночная игра) его
# симулирует, клиенты и проектор только показывают реплицированное состояние (WorldSync).

## Симулирует ли этот процесс общий мир: одиночная игра или сервер. Клиент и проектор — нет.
func runs_world() -> bool:
	return not is_network() or is_server()


## Только показывает общий мир, присланный сервером (клиент, проектор): обратное runs_world().
func is_view() -> bool:
	return not runs_world()


## Показывает ли этот процесс личное: квесты, полоски, голоса и звуки рядом с игроком.
## Всё, кроме сервера (у него нет экрана и своего игрока).
func shows_personal_ui() -> bool:
	return not is_server()


## Подключены ли к серверу (клиент; после разрыва стоит OfflineMultiplayerPeer — это «нет»).
func connected_to_server() -> bool:
	var mp := multiplayer.multiplayer_peer
	return client != null and mp != null and not mp is OfflineMultiplayerPeer \
			and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Сетевые игроки текущей сцены (NetWorld) или null. Без типа: autoload не должен зависеть от
## классов уровня (циклическая загрузка скриптов).
func world() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("NetWorld") if scene != null else null


## Синхронизатор общего мира текущей сцены (WorldSync; есть только в сети). Без типа — как world().
func world_sync() -> Node:
	var net_world := world()
	return net_world.get_node_or_null("WorldSync") if net_world != null else null


## Клиент: выполнить action как повтор присланного сервером (Net.replaying = true на это время).
func replay(action: Callable) -> void:
	var was_replaying := replaying
	replaying = true
	action.call()
	replaying = was_replaying


## Вызвать метод у предмета мира везде, где этот мир есть: здесь и (на сервере) у всех клиентов.
## Для видимых эффектов, которые не следуют из состояния (мешок плюхнулся, реплика модератора).
func world_call(node: Node, method: StringName, args := []) -> void:
	node.callv(method, args)
	if is_server():
		var ws := world_sync()
		if ws != null:
			ws.broadcast_call(node, method, args)


## Сервер: разослать эффект (всплывающий текст, звук, конфетти) всем клиентам вместо того, чтобы
## создавать его у себя. kind — WorldSync.Fx (int: autoload не зависит от классов уровня).
## Возвращает true, если эффект «съеден» (сервер или клиент в replaying).
func route_fx(kind: int, args: Array) -> bool:
	if is_server():
		var ws := world_sync()
		if ws != null:
			ws.broadcast_fx(kind, args)
		return true
	return replaying


## Выполнить действие от имени персонажа пира peer (личные события — ему).
func as_actor(peer: int, action: Callable) -> void:
	var prev := _actor_peer
	_actor_peer = peer
	action.call()
	_actor_peer = prev


## Выполнить действие от имени игрока: в одиночной игре — если это свой персонаж, на сервере —
## отправляя личные события его клиенту. На клиенте ничего не делает (мир решает сервер).
## player без типа и is_local через get — как в world(): autoload не знает класс Player.
func as_player(player: Node, action: Callable) -> void:
	if not is_network():
		if player.get("is_local"):
			action.call()
	elif is_server():
		var peer := server.registry.peer_for_player(str(player.name)) if server != null else 0
		as_actor(peer if peer > 0 else ACTOR_NOBODY, action)


## Сервер: личную цель действия (диалог NPC, прятки) выполнит клиент пира peer у своей копии
## мира. Возвращает true на сервере — у себя сервер её не выполняет, вызывающий должен закончить.
func route_personal_interact(peer: int, target: Node) -> bool:
	if not is_server():
		return false
	var ws := world_sync()
	if ws != null:
		ws.send_personal_interact(peer, target)
	return true


## Сервер: личное событие (Quests / GameManager) уходит клиенту того, кто действует сейчас
## (as_actor), а вне действия — всем игрокам. Возвращает true на сервере: у себя сервер
## квестов не ведёт, вызывающий метод должен на этом закончить.
func forward_personal(target: StringName, method: StringName, args := []) -> bool:
	if not is_server():
		return false
	var peers: Array = []
	if _actor_peer > 0:
		peers = [_actor_peer]
	elif _actor_peer == ACTOR_EVERYONE:
		peers = world_ready_peers.keys()
	for peer: int in peers:
		if target == &"GameManager" and method == &"unlock_achievement" and server != null:
			var player_id := server.registry.player_for_peer(peer)
			award_player_achievement(server.registry.token_for_player(player_id), args[0])
			continue
		if world_ready_peers.has(peer) and peer in multiplayer.get_peers():
			personal_call.rpc_id(peer, target, method, args)
	return true


func award_player_achievement(token: String, id: StringName) -> void:
	if server == null or not server.registry.award_achievement(token, id):
		return
	var peer := server.registry.peer_for_token(token)
	if world_ready_peers.has(peer) and peer in multiplayer.get_peers():
		personal_call.rpc_id(peer, &"GameManager", &"unlock_achievement", [id])


## Сервер: забрать все ачивки сессии с этим токеном (админка). Подключённый игрок сразу видит
## сброс у себя, его персонаж снимает награды. Возвращает player_id ("" — сейчас не в игре).
func reset_player_achievements(token: String) -> String:
	if server == null:
		return ""
	var player_id := server.registry.reset_achievements(token)
	if player_id == "":
		return ""
	var peer := server.registry.peer_for_player(player_id)
	if world_ready_peers.has(peer) and peer in multiplayer.get_peers():
		personal_call.rpc_id(peer, &"GameManager", &"reset_achievements", [])
	var net_world := world()
	if net_world != null:
		net_world.refresh_player_profile(player_id)
	return player_id


func record_tutorial_step(id: String) -> void:
	if server == null or _actor_peer <= 0:
		return
	var player_id := server.registry.player_for_peer(_actor_peer)
	if server.registry.advance_tutorial(player_id, id, Quests.find("main").steps):
		award_player_achievement(server.registry.token_for_player(player_id), &"first_steps")


## Сервер -> клиент: личное событие (квест, ачивка). Живёт на autoload: квесты переживают
## перезагрузку сцены.
@rpc("authority", "call_remote", "reliable")
func personal_call(target: StringName, method: StringName, args: Array) -> void:
	if not PERSONAL_CALLS.has(target) or not method in PERSONAL_CALLS[target]:
		return
	var node := get_node_or_null(NodePath("/root/" + String(target)))
	if node != null:
		node.callv(method, args)


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
	if server != null:
		server.registry.reset_tutorial_progress()
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
	if scene == null or not scene.is_node_ready() or world() == null:
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
	var player_id := server.registry.player_for_peer(peer)
	if player_id != "":
		var token := server.registry.token_for_player(player_id)
		personal_call.rpc_id(peer, &"GameManager", &"sync_reward_achievements", [server.registry.achievements_of(token).keys()])
		var steps: Array[Quest] = Quests.find("main").steps
		for i in server.registry.tutorial_step_of(player_id):
			personal_call.rpc_id(peer, &"Quests", &"complete", [steps[i].id])
	world_peer_ready.emit(peer)


@rpc("any_peer", "call_remote", "reliable")
func register(token: String) -> void:
	if server != null:
		server.on_register(multiplayer.get_remote_sender_id(), token)


@rpc("any_peer", "call_remote", "reliable")
func equip_accessory(id: String) -> void:
	if server == null:
		return
	var player_id := server.registry.equip_accessory(multiplayer.get_remote_sender_id(), id)
	if player_id == "":
		return
	var net_world := world()
	if net_world != null:
		net_world.refresh_player_profile(player_id)
