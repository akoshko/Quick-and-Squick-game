extends Node
## Сетевые игроки в мире (§6.4). Сервер — авторитет всех персонажей: спавнит их в `Players`
## (имя узла — стабильный player_id), двигает по вводу из submit_input; клиенты только рисуют
## реплицированное состояние. В OFFLINE ничего не делает.
## В сцене узел — Node2D (y-сортировка персонажей вместе с остальным уровнем).

signal player_count_changed(n: int)

const PLAYER_SCENE := preload("res://src/player/Player.tscn")
const DEFAULT_SPAWN := Vector2(176, 176)

var player_count: int = 0

var _net: Node
var _spawn_position := DEFAULT_SPAWN
var _dynamic_bodies: Array[CollisionObject2D] = []   # сервер: всё, кроме карты и игроков

@onready var _players: Node2D = $Players


func _ready() -> void:
	_net = get_node("/root/Net")
	if not _net.is_network():
		return
	var start := get_parent().get_node_or_null("Player1") as Node2D
	if start != null:
		_spawn_position = start.position
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
	if not _net.is_server():
		# сцена мира готова: сервер покажет персонажей только после этого подтверждения (Net.ack_world)
		_net.ack_world.call_deferred()


# --- сервер ---

func _ready_server() -> void:
	var game := get_parent()
	for node in game.find_children("*", "CollisionObject2D", true, false):
		_track_dynamic_body(node)
	get_tree().node_added.connect(_on_node_added)
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


## Сервер проверяет движение только по статичной карте (TileMapLayer): подвижные объекты уровня
## (мешки и сокобан, NPC, модераторы и зомби, станции, босс) не мешают ходьбе.
## Скрипты сами меняют слой во время игры (зомби ложится — снова препятствие, мешок
## возвращается и т.п.), поэтому слой гасится не один раз, а каждый физический кадр.
func _track_dynamic_body(node: Node) -> void:
	if node is CollisionObject2D and not node is Player and not node is TileMapLayer:
		_dynamic_bodies.append(node)
		(node as CollisionObject2D).collision_layer = 0


func _on_node_added(node: Node) -> void:
	if node is CollisionObject2D and get_parent().is_ancestor_of(node):
		_track_dynamic_body(node)


func _physics_process(_delta: float) -> void:
	if _dynamic_bodies.is_empty():
		return
	var alive: Array[CollisionObject2D] = []
	for body in _dynamic_bodies:
		if is_instance_valid(body):
			body.collision_layer = 0
			alive.append(body)
	_dynamic_bodies = alive


func _spawn(player_id: String, number: int) -> Player:
	var p := PLAYER_SCENE.instantiate() as Player
	p.name = player_id
	p.position = _free_spawn_position()
	p.player_number = number
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
	else:
		_spawn(player_id, _number_of(player_id))
	_update_player_count()


func _on_player_held(player_id: String) -> void:
	var p := _player(player_id)
	if p != null:
		p.held = true
		p.remote_dir = Vector2i.ZERO
		p.remote_action = false


func _on_player_removed(player_id: String) -> void:
	var p := _player(player_id)
	if p != null:
		_players.remove_child(p)
		p.queue_free()
	_update_player_count()


## Пир подтвердил эпоху (Net.world_ready): его сцена мира на месте — показываем персонажей
## (видимость синхронизатора управляет и спавном через MultiplayerSpawner) и число игроков.
func _show_world_to(peer_id: int) -> void:
	for p in _players.get_children():
		var sync := p.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if sync != null:
			sync.set_visibility_for(peer_id, true)
	set_player_count.rpc_id(peer_id, player_count)


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


@rpc("authority", "reliable")
func set_player_count(n: int) -> void:
	if n == player_count:
		return
	player_count = n
	player_count_changed.emit(n)
