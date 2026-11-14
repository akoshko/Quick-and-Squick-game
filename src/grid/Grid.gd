class_name Grid

## Общие функции для клеточной сетки уровня.
##
## Сетка берётся из TileMapLayer, который состоит в группе "grid".
## Поэтому размер клетки и сдвиг слоя всегда совпадают с тайлами:
## если поменять tile_size в TileSet или подвинуть слой — игрок и
## предметы автоматически подстроятся.
##
## Мебель на слоях из группы "grid_objects" (у них своя, более мелкая
## сетка) тоже делает клетки твёрдыми — по своей коллизии.

const GROUP := "grid"
const OBJECTS_GROUP := "grid_objects"
const FALLBACK_TILE_SIZE := 32   # если на сцене нет слоя с сеткой
const OBJECT_OVERLAP := 6.0      # насколько (px) мебель должна заходить в клетку, чтобы её занять

static var _object_cells := {}        # клетки, занятые мебелью (кэш на кадр)
static var _object_cells_frame := -1


static func _layer(node: Node) -> TileMapLayer:
	return node.get_tree().get_first_node_in_group(GROUP) as TileMapLayer


## Размер клетки в пикселях
static func tile_size(node: Node) -> Vector2:
	var layer := _layer(node)
	if layer and layer.tile_set:
		return Vector2(layer.tile_set.tile_size)
	return Vector2.ONE * FALLBACK_TILE_SIZE


## Мировые координаты (пиксели) -> номер клетки
static func world_to_cell(node: Node, world: Vector2) -> Vector2i:
	var layer := _layer(node)
	if layer:
		return layer.local_to_map(layer.to_local(world))
	return Vector2i((world / FALLBACK_TILE_SIZE).floor())


## Номер клетки -> мировые координаты ЦЕНТРА клетки
static func cell_to_world(node: Node, cell: Vector2i) -> Vector2:
	var layer := _layer(node)
	if layer:
		return layer.to_global(layer.map_to_local(cell))
	return Vector2(cell * FALLBACK_TILE_SIZE) + Vector2.ONE * FALLBACK_TILE_SIZE / 2.0


## Твёрдая ли клетка: у тайла есть коллизия (стена, стол) или это
## пустота за пределами карты
static func is_solid_cell(node: Node, cell: Vector2i) -> bool:
	var layer := _layer(node)
	if layer == null:
		return false
	var data := layer.get_cell_tile_data(cell)
	if data == null:
		return true
	if data.get_collision_polygons_count(0) > 0:
		return true
	return _object_cells_for(node).has(cell)


# Клетки сетки, которые заметно перекрыты коллизией мебели со слоёв
# "grid_objects". Считается один раз за кадр физики.
static func _object_cells_for(node: Node) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame == _object_cells_frame:
		return _object_cells
	_object_cells_frame = frame
	_object_cells = {}
	var size := tile_size(node)
	for objects in node.get_tree().get_nodes_in_group(OBJECTS_GROUP):
		var obj_layer := objects as TileMapLayer
		if obj_layer == null or not obj_layer.visible:
			continue
		for map_cell in obj_layer.get_used_cells():
			var data := obj_layer.get_cell_tile_data(map_cell)
			if data == null:
				continue
			var center := obj_layer.to_global(obj_layer.map_to_local(map_cell))
			for i in data.get_collision_polygons_count(0):
				var points := data.get_collision_polygon_points(0, i)
				if points.is_empty():
					continue
				var rect := Rect2(points[0], Vector2.ZERO)
				for point in points:
					rect = rect.expand(point)
				rect.position += center
				var first := world_to_cell(node, rect.position)
				var last := world_to_cell(node, rect.end)
				for x in range(first.x, last.x + 1):
					for y in range(first.y, last.y + 1):
						var cell := Vector2i(x, y)
						var cell_rect := Rect2(cell_to_world(node, cell) - size / 2.0, size)
						var overlap := cell_rect.intersection(rect)
						if overlap.size.x >= OBJECT_OVERLAP and overlap.size.y >= OBJECT_OVERLAP:
							_object_cells[cell] = true
	return _object_cells


## Путь по клеткам от from до ближайшей из goals (без стартовой клетки),
## в обход твёрдых тайлов и клеток из blocked. Ходит только в 4 стороны.
## Пустой массив — пути нет (проверь заранее, что from не входит в goals).
static func find_path(node: Node, from: Vector2i, goals: Array[Vector2i],
		blocked: Array[Vector2i] = []) -> Array[Vector2i]:
	var layer := _layer(node)
	if layer == null:
		return []
	var astar := AStarGrid2D.new()
	astar.region = layer.get_used_rect()
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	var region := astar.region
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var cell := Vector2i(x, y)
			if is_solid_cell(node, cell):
				astar.set_point_solid(cell)
	for cell in blocked:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell)
	if not astar.is_in_boundsv(from):
		return []
	astar.set_point_solid(from, false)

	var best: Array[Vector2i] = []
	var found := false
	for goal in goals:
		if not astar.is_in_boundsv(goal) or astar.is_point_solid(goal):
			continue
		var path: Array[Vector2i] = astar.get_id_path(from, goal)
		if path.is_empty():
			continue
		path.remove_at(0)
		if not found or path.size() < best.size():
			best = path
			found = true
	return best


## Слой тайлов уровня (TileMapLayer из группы "grid") или null
static func get_layer(node: Node) -> TileMapLayer:
	return _layer(node)


## Ближайшая к from_cells проходимая клетка, которой нет в avoid
## (поиск в ширину по 4 направлениям). Если не нашлось — первая из from_cells.
static func find_free_cell_near(node: Node, from_cells: Array[Vector2i],
		avoid: Array[Vector2i]) -> Vector2i:
	var seen := {}
	var queue: Array[Vector2i] = []
	for cell in from_cells:
		seen[cell] = true
		queue.append(cell)
	var limit := 2000   # защита от бесконечного поиска за пределами карты
	while not queue.is_empty() and limit > 0:
		limit -= 1
		var cell: Vector2i = queue.pop_front()
		if not (cell in avoid) and not is_solid_cell(node, cell):
			return cell
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + dir
			if not seen.has(next) and not is_solid_cell(node, next):
				seen[next] = true
				queue.append(next)
	return from_cells[0] if not from_cells.is_empty() else Vector2i.ZERO


## Ставит узел ровно в центр клетки, в которой он сейчас находится
static func snap(node: Node2D) -> void:
	node.global_position = cell_to_world(node, world_to_cell(node, node.global_position))
