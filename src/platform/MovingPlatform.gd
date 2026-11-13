extends AnimatableBody2D

## Платформа, плавно двигающаяся туда-обратно.

@export var move_distance := Vector2(100.0, 0.0)
@export var duration: float = 2.0

var _start: Vector2
var _timer := 0.0


func _ready() -> void:
	_start = global_position


func _physics_process(delta: float) -> void:
	_timer += delta
	var t := (sin(_timer * PI / duration) + 1.0) / 2.0
	global_position = _start.lerp(_start + move_distance, t)
