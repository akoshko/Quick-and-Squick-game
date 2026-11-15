extends Node
## Сетевые игроки в мире (§6.4). Сервер — авторитет всех персонажей: спавнит их в `Players`
## (имя узла — стабильный player_id), двигает по вводу из submit_input и выполняет их действие
## (request_interact) в общем мире; клиенты только рисуют реплицированное состояние.
## Предметы уровня синхронизирует дочерний WorldSync. В OFFLINE ничего не делает.
## В сцене узел — Node2D (y-сортировка персонажей вместе с остальным уровнем).

signal player_count_changed(n: int)

const PLAYER_SCENE := preload("res://src/player/Player.tscn")
const DEFAULT_SPAWN := Vector2(176, 176)
## Сервер: не чаще одной эмоции игрока за столько секунд (своё облачко клиент и так не даёт
## показать, пока не исчезло прошлое — ограничение только от подделанных клиентов).
const EMOTE_MIN_INTERVAL := 0.3

var player_count: int = 0

var _net: Node
var _spawn_position := DEFAULT_SPAWN
var _sync: WorldSync
var _last_emote: Dictionary = {}   # сервер: player_id -> время последней принятой эмоции (с)

@onready var _players: Node2D = $Players


func _ready() -> void:
	_net = get_node("/root/Net")
	if not _net.is_network():
		return
	var start := get_parent().get_node_or_null("Player1") as Node2D
	if start != null:
		_spawn_position = start.position
	_sync = WorldSync.new()
	_sync.name = "WorldSync"
	add_child(_sync)
	if _net.is_server():
		_ready_server()
	elif _net.is_screen():
		var overlay := ScreenOverlay.new()
		overlay.name = "ScreenOverlay"
		overlay.world = self
		add_child(overlay)
	else:
		var input := NetInput.new()
		input.name = "NetInput"
		input.world = self
		add_child(input)
		# своя эмоция (Player.emoted) уходит серверу, он рассылает её остальным
		_players.child_entered_tree.connect(_on_client_player_added)
	if not _net.is_server():
		# сцена мира готова: сервер покажет персонажей только после этого подтверждения (Net.ack_world)
		_net.ack_world.call_deferred()


# --- сервер ---

func _ready_server() -> void:
	var server: NetServer = _net.server
	server.player_joined.connect(_on_player_joined)
	server.player_held.connect(_on_player_held)
	server.player_removed.connect(_on_player_removed)
	_net.world_peer_ready.connect(_show_world_to)
	# персонажи создаются сразу, но видны только пирам, подтвердившим эту эпоху (Net.world_ready_peers)
	for rec in server.registry.records():
		if (rec.state == "connected" or rec.state == "held") and _player(rec.player_id) == null:
			var p := _spawn(rec.player_id, rec.number)
			p.held = rec.state == "held"
	_update_player_count()


func _spawn(player_id: String, number: int) -> Player:
	var p := PLAYER_SCENE.instantiate() as Player
	p.name = player_id
	p.position = _free_spawn_position()
	p.player_number = number
	p.profile = _net.server.registry.profile_of(player_id)
	p.network_controlled = true
	# видимость задаётся до add_child: первый спавн уходит только подтвердившим world_ready
	var sync := p.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	sync.public_visibility = false
	for peer: int in _net.world_ready_peers:
		sync.set_visibility_for(peer, true)
	_players.add_child(p)
	return p


## Свободная проходимая клетка рядом со стартом (не занятая другим персонажем).
func _free_spawn_position() -> Vector2:
	var start := Grid.world_to_cell(self, _spawn_position)
	var taken: Array[Vector2i] = []
	# мешки, NPC и столы-станции твёрдые и на сервере: в них не спавним
	for node in get_parent().get_children():
		if Grid.is_solid(node) and node.visible:
			taken.append(Grid.world_to_cell(self, (node as Node2D).global_position))
	for p: Node2D in _players.get_children():
		taken.append(Grid.world_to_cell(self, p.global_position))
		if p is Player:
			taken.append(Grid.world_to_cell(self, (p as Player)._target_position))
	var cell := Grid.find_free_cell_near(self, [start] as Array[Vector2i], taken)
	return _players.to_local(Grid.cell_to_world(self, cell))


func _player(player_id: String) -> Player:
	if player_id == "":
		return null
	return _players.get_node_or_null(NodePath(player_id)) as Player


func _number_of(player_id: String) -> int:
	for rec in _net.server.registry.records():
		if rec.player_id == player_id:
			return rec.number
	return 0


func _on_player_joined(player_id: String, _peer_id: int) -> void:
	var p := _player(player_id)
	if p != null:
		p.held = false   # вернулся из удержания: тот же персонаж и место
		refresh_player_profile(player_id)
	else:
		_spawn(player_id, _number_of(player_id))
	_update_player_count()


func refresh_player_profile(player_id: String) -> void:
	var p := _player(player_id)
	if p != null:
		p.profile = _net.server.registry.profile_of(player_id)


func _on_player_held(player_id: String) -> void:
	var p := _player(player_id)
	if p != null:
		p.held = true
		p.remote_dir = Vector2i.ZERO
		p.remote_action = false


func _on_player_removed(player_id: String) -> void:
	_last_emote.erase(player_id)
	var p := _player(player_id)
	if p != null:
		_players.remove_child(p)
		p.queue_free()
	_update_player_count()


## Пир подтвердил эпоху (Net.world_ready): его сцена мира на месте — показываем персонажей
## (видимость синхронизатора управляет и спавном через MultiplayerSpawner), число игроков
## и снимок общего мира (WorldSync).
func _show_world_to(peer_id: int) -> void:
	for p in _players.get_children():
		var sync := p.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if sync != null:
			sync.set_visibility_for(peer_id, true)
	set_player_count.rpc_id(peer_id, player_count)
	_sync.send_snapshot(peer_id)


func _update_player_count() -> void:
	var n := 0
	for rec in _net.server.registry.records():
		if rec.state == "connected" or rec.state == "held":
			n += 1
	if n == player_count:
		return
	player_count = n
	player_count_changed.emit(n)
	# отложенно: пир, которого NetServer только что отключил, к этому моменту уже уйдёт
	_broadcast_player_count.call_deferred()


## Только пирам, чья сцена мира готова: остальным RPC на NetWorld может прийти в кадр
## перезагрузки сцены и потеряться; они получат число в _show_world_to.
func _broadcast_player_count() -> void:
	for peer: int in _net.world_ready_peers:
		if peer in multiplayer.get_peers():
			set_player_count.rpc_id(peer, player_count)


## Пересоздать мир: клиенты перезагружают свою сцену, сервер — свою; новая NetWorld
## спавнит всех подключённых и удерживаемых игроков из реестра, а каждому пиру показывает их
## после его world_ready с новой эпохой.
func restart_world() -> void:
	if not _net.is_server():
		return
	print("NET: world restart")
	# сначала убираем персонажей (despawn уходит клиентам до команды перезагрузки)
	for p in _players.get_children():
		_players.remove_child(p)
		p.queue_free()
	_net.restart_world_epoch()
	get_tree().reload_current_scene()


## «Сбросить прогресс» (админка): личные квесты всех игроков и общий мир заново.
func reset_progress() -> void:
	if not _net.is_server():
		return
	Quests.reset()   # на сервере уходит всем игрокам (Net.forward_personal)
	restart_world()


# --- RPC ---

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(dir: Vector2i, action: bool) -> void:
	if not _net.is_server():
		return
	var pid: String = _net.server.registry.player_for_peer(multiplayer.get_remote_sender_id())
	var p := _player(pid)
	if p == null:
		return
	p.remote_dir = Vector2i(clampi(dir.x, -1, 1), clampi(dir.y, -1, 1))
	p.remote_action = action


## Клиент нажал «действие» (E): сервер выполняет его у своего экземпляра персонажа,
## как в одиночной игре (Player.queue_interact -> _interact), от имени этого игрока.
@rpc("any_peer", "call_remote", "reliable")
func request_interact() -> void:
	if not _net.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var p := _player(_net.server.registry.player_for_peer(sender))
	if p != null and not p.held:
		p.queue_interact(sender)


## Клиент нажал «Я застрял»: сервер возвращает персонажа на точку возрождения.
@rpc("any_peer", "call_remote", "reliable")
func request_respawn() -> void:
	if not _net.is_server():
		return
	var p := _player(_net.server.registry.player_for_peer(multiplayer.get_remote_sender_id()))
	if p != null and not p.held:
		p.respawn()


@rpc("authority", "reliable")
func set_player_count(n: int) -> void:
	if n == player_count:
		return
	player_count = n
	player_count_changed.emit(n)


# --- эмоции ---

func _on_client_player_added(node: Node) -> void:
	if node is Player and not (node as Player).emoted.is_connected(_send_emote):
		(node as Player).emoted.connect(_send_emote)


# Клиент: своя эмоция (Player.try_emote уже показал облачко) — на сервер
func _send_emote(emote: int) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp == null or mp is OfflineMultiplayerPeer or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	submit_emote.rpc_id(1, emote)


## Сервер: принять ли эмоцию игрока в момент now (с): известная эмоция и не чаще
## EMOTE_MIN_INTERVAL. Принятая запоминается для следующей проверки.
func accept_emote(player_id: String, emote: int, now: float) -> bool:
	if player_id == "" or emote < 0 or emote >= EmoteBubble.NAMES.size():
		return false
	if _last_emote.has(player_id) and now - float(_last_emote[player_id]) < EMOTE_MIN_INTERVAL:
		return false
	_last_emote[player_id] = now
	return true


@rpc("any_peer", "call_remote", "reliable")
func submit_emote(emote: int) -> void:
	if not _net.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var pid: String = _net.server.registry.player_for_peer(sender)
	var p := _player(pid)
	if p == null or p.held or not accept_emote(pid, emote, Time.get_ticks_msec() / 1000.0):
		return
	# всем, чья сцена мира готова (телефоны и проектор), кроме автора: у него облачко уже есть
	for peer: int in _net.world_ready_peers:
		if peer != sender and peer in multiplayer.get_peers():
			play_emote.rpc_id(peer, pid, emote)


@rpc("authority", "call_remote", "reliable")
func play_emote(player_id: String, emote: int) -> void:
	var p := _player(player_id)
	if p != null and emote >= 0 and emote < EmoteBubble.NAMES.size():
		p.show_emote(emote)
