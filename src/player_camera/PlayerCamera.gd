class_name PlayerCamera
extends Camera2D

## Камера, следящая за серединой между двумя игроками.

## Видимая область камеры в мировых координатах (используется игроками,
## чтобы не уходить за край экрана).
static var visible_rect := Rect2()

@export var smooth_speed: float = 6.0
@export var zoom_level: float = 6.0

@onready var _player1: Player = %Player1
@onready var _player2: Player = %Player2


func _ready() -> void:
	zoom = Vector2.ONE * zoom_level
	# Сразу ставим камеру в середину, чтобы visible_rect был верным с первого кадра
	global_position = _midpoint()
	_update_visible_rect()


func _exit_tree() -> void:
	visible_rect = Rect2()


func _process(delta: float) -> void:
	global_position = global_position.lerp(_midpoint(), smooth_speed * delta)
	_update_visible_rect()


func _midpoint() -> Vector2:
	return (_player1.global_position + _player2.global_position) / 2.0


func _update_visible_rect() -> void:
	var half_size := get_viewport_rect().size / (2.0 * zoom)
	visible_rect = Rect2(global_position - half_size, half_size * 2.0)
