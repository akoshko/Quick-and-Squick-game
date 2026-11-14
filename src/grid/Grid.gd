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


## Ставит узел ровно в центр клетки, в которой он сейчас находится
static func snap(node: Node2D) -> void:
	node.global_position = cell_to_world(node, world_to_cell(node, node.global_position))
