class_name Player
extends CharacterBody2D

## Игрок (Сырник — P1, Писклик — P2).

signal died(player_index: int)
signal hp_changed(player_index: int, new_hp: int)

const IFRAME_DURATION := 1.2

@export var player_index: int = 1
@export var speed: float = 180.0
@export var jump_velocity: float = -300.0
@export var power_jump_velocity: float = -400.0
@export var max_hp: int = 3

var hp: int
var is_dead: bool:
	get:
		return hp <= 0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _current_anim := ""
var _is_crouching := false
var _iframe_timer := 0.0

@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	hp = max_hp
	if player_index == 1:
		_sprite.texture = load("res://src/player/visuals/syrnik-Sheet.png")
	else:
		_sprite.texture = load("res://src/player/visuals/pisklik-Sheet.png")


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if GameManager.state == GameManager.GameState.PAUSED:
		return

	if not is_on_floor():
		velocity.y += _gravity * delta

	_is_crouching = Input.is_action_pressed(_p("crouch")) and is_on_floor()

	if is_on_floor() and not _is_crouching:
		if Input.is_action_just_pressed(_p("jump")):
			velocity.y = jump_velocity
		elif Input.is_action_just_pressed(_p("power_jump")):
			velocity.y = power_jump_velocity

	var direction := 0.0
	if not _is_crouching:
		if Input.is_action_pressed(_p("left")):
			direction -= 1.0
		if Input.is_action_pressed(_p("right")):
			direction += 1.0

	if direction != 0.0:
		velocity.x = direction * speed
		_sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)

	move_and_slide()
	_clamp_to_viewport()
	_play_animation(direction)
	_tick_iframes(delta)


func _play_animation(direction: float) -> void:
	var anim: String
	if not is_on_floor():
		anim = "jump"
	elif _is_crouching:
		anim = "crouch"
	elif direction != 0.0:
		anim = "run"
	else:
		anim = "idle"

	if anim == _current_anim:
		return
	_current_anim = anim

	_anim_player.play(anim if _anim_player.has_animation(anim) else "idle")


func _tick_iframes(delta: float) -> void:
	if _iframe_timer <= 0.0:
		return
	_iframe_timer -= delta
	_sprite.visible = int(_iframe_timer / 0.1) % 2 == 0
	if _iframe_timer <= 0.0:
		_sprite.visible = true


func take_damage(amount: int = 1, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_dead or _iframe_timer > 0.0:
		return
	hp = maxi(0, hp - amount)
	_iframe_timer = IFRAME_DURATION
	if knockback != Vector2.ZERO:
		velocity = knockback
	hp_changed.emit(player_index, hp)
	if hp <= 0:
		visible = false
		_collision_shape.set_deferred("disabled", true)
		set_physics_process(false)
		died.emit(player_index)


func _clamp_to_viewport() -> void:
	var rect := PlayerCamera.visible_rect
	if rect == Rect2():
		return

	var margin := 8.0
	var clamped_x := clampf(global_position.x, rect.position.x + margin, rect.end.x - margin)
	if not is_equal_approx(global_position.x, clamped_x):
		global_position.x = clamped_x
		velocity.x = 0.0


func respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	take_damage(1)


## Возвращает "p1_jump", "p2_left" и т.д.
func _p(action: String) -> String:
	return "p%d_%s" % [player_index, action]
