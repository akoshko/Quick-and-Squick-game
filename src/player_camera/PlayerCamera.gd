class_name PlayerCamera
extends Camera2D

## Камера, следящая за серединой между видимыми игроками.

@export var smooth_speed: float = 6.0
## Сколько клеток видно по вертикали. Zoom подбирается сам под размер
## экрана, поэтому на мониторе, ноутбуке и телефоне вид одинаковый.
@export var visible_rows: float = 9.0

@onready var _player1: Player = %Player1
@onready var _player2: Player = %Player2


func _ready() -> void:
	_update_zoom()
	get_viewport().size_changed.connect(_update_zoom)
	# Сразу ставим камеру к игрокам, чтобы она не «прилетала» на старте
	global_position = _midpoint()


func _process(delta: float) -> void:
	global_position = global_position.lerp(_midpoint(), smooth_speed * delta)


func _update_zoom() -> void:
	var screen := get_viewport_rect().size
	var screen_height := minf(screen.y, screen.x * 1.5)
	var world_height := visible_rows * Grid.tile_size(self).y
	zoom = Vector2.ONE * (screen_height / world_height)


# Середина между видимыми игроками. Скрытый игрок (например, Player2,
# пока играем одни) не учитывается, иначе камера тянется к нему.
func _midpoint() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for player in [_player1, _player2]:
		if is_instance_valid(player) and player.visible:
			sum += player.global_position
			count += 1
	if count == 0:
		return global_position   # никого не видно — стоим на месте
	return sum / count
