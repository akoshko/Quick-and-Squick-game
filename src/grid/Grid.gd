class_name Grid

## Общие функции для клеточной сетки уровня.
##
## Сетка берётся из TileMapLayer, который состоит в группе "grid".
## Поэтому размер клетки и сдвиг слоя всегда совпадают с тайлами:
## если поменять tile_size в TileSet или подвинуть слой — игрок и
## предметы автоматически подстроятся.

const GROUP := "grid"
const FALLBACK_TILE_SIZE := 32   # если на сцене нет слоя с сеткой


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
	return data.get_collision_polygons_count(0) > 0


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


## Ставит узел ровно в центр клетки, в которой он сейчас находится
static func snap(node: Node2D) -> void:
	node.global_position = cell_to_world(node, world_to_cell(node, node.global_position))
