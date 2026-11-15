extends Node2D

## Основная сцена уровня: сбрасывает состояние игры и квесты при старте
## и выдаёт достижения за опустошённые тарелки.
## В сетевых режимах (Net) заранее поставленных игроков нет: персонажей создаёт NetWorld.

var _snack_stations: Array[SnackStation] = []

@onready var _camera: PlayerCamera = $PlayerCamera
@onready var _net_players: Node2D = $NetWorld/Players


func _ready() -> void:
	GameManager.reset()
	Quests.reset()
	if Net.is_network():
		_setup_network()
	var snack_zone := get_node_or_null("ZoneSnack") as Zone
	if snack_zone == null:
		return
	for station in snack_zone.get_stations():
		if station is SnackStation:
			_snack_stations.append(station)
			station.depleted.connect(_on_snack_depleted)


func _on_snack_depleted(station: SnackStation) -> void:
	for snack in _snack_stations:
		if snack.kind == station.kind and (not snack.is_empty or snack.is_knocked):
			return
	match station.kind:
		SnackStation.Kind.APPLE:
			GameManager.unlock_achievement(&"steve_jobs")
		SnackStation.Kind.COOKIE:
			GameManager.unlock_achievement(&"clean_cookies")


func _setup_network() -> void:
	# В сети персонажей создаёт NetWorld; заранее поставленные не нужны
	for p in [get_node_or_null("Player1"), get_node_or_null("Player2")]:
		if p != null:
			remove_child(p)
			p.queue_free()
	_camera.network_view = true
	if not Net.is_server() and not Net.is_screen():
		_net_players.child_entered_tree.connect(_on_net_player_added)
	if Net.is_screen():
		_setup_screen_view()


# Экранный вид (проектор): вся карта слева, справа колонка ScreenOverlay; управления и квестов нет
func _setup_screen_view() -> void:
	# слои интерфейса уровня (управление, квесты, ачивки, HUD) скрыты; общие для всех полоска
	# босса и счётчик кофе остаются. ScreenOverlay и ConnectionOverlay лежат вне этого набора
	for node in find_children("*", "CanvasLayer", true, false):
		_hide_screen_ui(node)
	# слои, которые уровень создаёт позже (счётчик кофе, эмоции и т.п.), — тоже
	get_tree().node_added.connect(_on_screen_node_added)
	_fit_screen_camera()
	get_viewport().size_changed.connect(_fit_screen_camera)


func _hide_screen_ui(node: Variant) -> void:
	if not is_instance_valid(node):
		return  # отложенный вызов: слой мог быть удалён
	if node is CanvasLayer and not _kept_on_screen(node):
		(node as CanvasLayer).visible = false


# Слои, которые остаются на проекторе: его колонка, полоска босса и счётчик кофе
func _kept_on_screen(layer: CanvasLayer) -> bool:
	return layer is ScreenOverlay or layer is BossBar or layer is CoffeeCounter


func _on_screen_node_added(node: Node) -> void:
	if node is CanvasLayer and is_ancestor_of(node):
		_hide_screen_ui(node)
		# скрипт слоя мог сам включить видимость в _ready
		_hide_screen_ui.call_deferred(node)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_screen_node_added):
		get_tree().node_added.disconnect(_on_screen_node_added)


# Вся карта: объединение всех слоёв сетки (пол и мебель)
func _fit_screen_camera() -> void:
	var rect := Rect2()
	for node in get_tree().get_nodes_in_group(Grid.GROUP) + get_tree().get_nodes_in_group(Grid.OBJECTS_GROUP):
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null or not is_ancestor_of(layer):
			continue
		var cell := Vector2(layer.tile_set.tile_size)
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var top_left := layer.to_global(layer.map_to_local(used.position) - cell / 2.0)
		var r := Rect2(top_left, Vector2(used.size) * cell * layer.global_scale)
		rect = r if not rect.has_area() else rect.merge(r)
	if rect.has_area():
		_camera.fit_map(rect, ScreenOverlay.COLUMN_RATIO)


# Камера клиента следует за своим персонажем, как только он появился
func _on_net_player_added(node: Node) -> void:
	if Net.client != null and node.name == Net.client.player_id:
		_camera.follow(node as Node2D)
