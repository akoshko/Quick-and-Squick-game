@tool
class_name BossSpawn
extends Node2D

## Точка появления босса (дочерний узел BossDirector). Позиция — центр
## квадрата 2×2, то есть угол между четырьмя клетками. В редакторе
## видна пунктирным квадратом с подписью.
##
## При появлении босса точка «ломает» свою локацию:
##   knock_zone  — все ресурсы этой зоны опрокидываются (еда рассыпана);
##   clear_tiles — клетки стола, которые босс сносит (станут полом
##                 clear_floor, ресурсы и декор на них пропадают).
## После победы (или ухода босса) всё возвращается: столы — сразу,
## опрокинутую еду через 5 секунд убирают модераторы.

## Как назвать локацию в задании: «Победить босса в …»
@export var location_name := "главном зале"
## «Соулс»-титул босса над полоской здоровья
@export var boss_title := "Мешок-Мимик"
## Зона, ресурсы которой босс опрокидывает (пусто — никакая)
@export var knock_zone: Zone
## Клетки стола, которые босс сносит (размер 0 — ничего не сносит)
@export var clear_tiles := Rect2i()
## Каким тайлом пола заменить снесённый стол (координаты в атласе)
@export var clear_floor := Vector2i(4, 0)

var _saved_tiles := {}                       # клетка -> [source, atlas, alternative]
var _saved_decor := {}                       # слой -> клетки декора и их тайлы
var _removed: Array[ResourceStation] = []    # ресурсы, снесённые вместе со столом
var _knocked: Array[ResourceStation] = []    # опрокинутые ресурсы зоны


## Сломать локацию перед появлением босса
func apply() -> void:
	if knock_zone:
		for station in knock_zone.get_stations():
			station.knock_over()
			_knocked.append(station)

	var layer := Grid.get_layer(self)
	if layer == null or clear_tiles.size == Vector2i.ZERO:
		return
	for x in range(clear_tiles.position.x, clear_tiles.end.x):
		for y in range(clear_tiles.position.y, clear_tiles.end.y):
			var cell := Vector2i(x, y)
			_saved_tiles[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell),
					layer.get_cell_alternative_tile(cell)]
			layer.set_cell(cell, 0, clear_floor)
	for objects: TileMapLayer in get_tree().get_nodes_in_group(Grid.OBJECTS_GROUP):
		var decor := {}
		for cell in objects.get_used_cells():
			var world := objects.to_global(objects.map_to_local(cell))
			if clear_tiles.has_point(Grid.world_to_cell(self, world)):
				decor[cell] = [objects.get_cell_source_id(cell), objects.get_cell_atlas_coords(cell),
						objects.get_cell_alternative_tile(cell)]
				objects.erase_cell(cell)
		if not decor.is_empty():
			_saved_decor[objects] = decor
	for node in get_tree().get_nodes_in_group("resource_station"):
		var station := node as ResourceStation
		if station and clear_tiles.has_point(Grid.world_to_cell(self, station.global_position)):
			station.set_removed(true)
			_removed.append(station)


## Вернуть локацию после победы или ухода босса
func release() -> void:
	var layer := Grid.get_layer(self)
	var restored_tiles := layer != null and not _saved_tiles.is_empty()
	if layer:
		for cell: Vector2i in _saved_tiles:
			var saved: Array = _saved_tiles[cell]
			layer.set_cell(cell, saved[0], saved[1], saved[2])
	_saved_tiles.clear()
	for objects: TileMapLayer in _saved_decor:
		if is_instance_valid(objects):
			for cell: Vector2i in _saved_decor[objects]:
				var saved: Array = _saved_decor[objects][cell]
				objects.set_cell(cell, saved[0], saved[1], saved[2])
	_saved_decor.clear()
	for station in _removed:
		if is_instance_valid(station):
			station.set_removed(false)
	_removed.clear()
	if restored_tiles:
		for node in get_tree().current_scene.get_children():
			if node is Player and node.is_visible_in_tree():
				node.check_restored_tiles(clear_tiles)
	for station in _knocked:
		if is_instance_valid(station):
			station.release_after_boss()
	_knocked.clear()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := Vector2(64, 64)
	draw_dashed_line(Vector2(-32, -32), Vector2(32, -32), Color(1, 0.4, 0.3), 1.5, 4.0)
	draw_dashed_line(Vector2(32, -32), Vector2(32, 32), Color(1, 0.4, 0.3), 1.5, 4.0)
	draw_dashed_line(Vector2(32, 32), Vector2(-32, 32), Color(1, 0.4, 0.3), 1.5, 4.0)
	draw_dashed_line(Vector2(-32, 32), Vector2(-32, -32), Color(1, 0.4, 0.3), 1.5, 4.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-size.x / 2.0 + 2, -size.y / 2.0 - 3), "БОСС: " + location_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.5, 0.4))
