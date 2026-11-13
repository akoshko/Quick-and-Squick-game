extends CharacterBody2D

## Жук, который ходит туда-сюда и разворачивается у стен и краёв платформ.

@export var speed: float = 60.0
@export var damage: int = 1

var _direction := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _edge_check: RayCast2D = $EdgeCheck


func _ready() -> void:
	var hit_box: Area2D = $HitBox
	hit_box.collision_mask = 1 # Игрок на физическом слое 1
	hit_box.body_entered.connect(_on_hit_box_body_entered)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta

	velocity.x = _direction * speed
	move_and_slide()

	# Разворот у стены или когда впереди нет пола
	if is_on_wall() or (is_on_floor() and not _edge_check.is_colliding()):
		_turn_around()


func _turn_around() -> void:
	_direction *= -1.0
	_sprite.flip_h = _direction < 0
	# EdgeCheck всегда смотрит вперёд
	_edge_check.position = Vector2(absf(_edge_check.position.x) * _direction, _edge_check.position.y)


func _on_hit_box_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	var player := body as Player
	var side := signf(player.global_position.x - global_position.x)
	var knockback := Vector2(side * 220.0, -320.0)
	player.take_damage(damage, knockback)
