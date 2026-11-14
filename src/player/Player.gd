class_name Player
extends CharacterBody2D

## Игрок (Сырник — P1, Писклик — P2).
## Top-down движение по клеткам, как в старых играх.

#signal died(player_index: int)
#signal hp_changed(player_index: int, new_hp: int)

const IFRAME_DURATION := 1.2

#@export var player_index: int = 1
@export var move_speed: float = 120.0   # пикселей в секунду
# Размер клетки берётся из TileMapLayer уровня (см. Grid.gd)
#@export var max_hp: int = 3

#var hp: int
#var is_dead: bool:
	#get:
		#return hp <= 0

var _current_anim := ""
var _iframe_timer := 0.0

var _target_position: Vector2   # куда сейчас едем (в пикселях)
var _is_moving := false         # «занят» ли персонаж

## Куда смотрит игрок. Нужен для взаимодействия: предметы узнают
## отсюда, в какую сторону их толкают.
var facing := Vector2i.DOWN

@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	#hp = max_hp

	#выбор игрока
	#if player_index == 1:
		#_sprite.texture = load("res://src/player/visuals/syrnik-Sheet.png")
	#else:
		#_sprite.texture = load("res://src/player/visuals/pisklik-Sheet.png")

	# На старте ставим персонажа ровно в центр клетки, в которой он стоит
	Grid.snap(self)
	_target_position = global_position

	# Скрытый игрок (например, Player2 в одиночной игре) не должен
	# ни ходить от тех же кнопок, ни быть невидимой стеной
	if not visible:
		_collision_shape.disabled = true
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	#if is_dead:
		#return
	if GameManager.state == GameManager.GameState.PAUSED:
		return

	# 1. Если едем — плавно приближаемся к цели
	if _is_moving:
		global_position = global_position.move_toward(_target_position, move_speed * delta)
		if global_position == _target_position:
			_is_moving = false

	# 2. Если стоим — читаем кнопки и пробуем шагнуть.
	# Кнопки читаются только когда стоим, поэтому is_action_pressed
	# не разгонит персонажа, а при удержании он идёт без остановок.
	if not _is_moving and Input.is_action_just_pressed("action"):
		_interact()

	if not _is_moving:
		var direction := _read_direction()
		if direction != Vector2i.ZERO:
			_try_step(direction)

	_play_animation()
	_tick_iframes(delta)


# Только 4 направления, как в старых играх
func _read_direction() -> Vector2i:
	if Input.is_action_pressed("move_right"):
		return Vector2i.RIGHT   # (1, 0)
	if Input.is_action_pressed("move_left"):
		return Vector2i.LEFT    # (-1, 0)
	if Input.is_action_pressed("move_down"):
		return Vector2i.DOWN    # (0, 1)
	if Input.is_action_pressed("move_up"):
		return Vector2i.UP      # (0, -1)
	return Vector2i.ZERO


func _try_step(direction: Vector2i) -> void:
	# текущая клетка + направление = целевая клетка
	var target_cell := Grid.world_to_cell(self, global_position) + direction
	var target_pos := Grid.cell_to_world(self, target_cell)

	# Поворачиваемся, даже если шагнуть нельзя: так можно
	# встать лицом к мешку, упёршись в него
	facing = direction
	if direction.x != 0:
		_sprite.flip_h = direction.x < 0

	# Стена? Проверяем ДО шага
	if test_move(global_transform, target_pos - global_position):
		return

	_target_position = target_pos
	_is_moving = true


# Ищем предмет в клетке перед собой и взаимодействуем с ним.
# Подходит любой узел из группы "interactable" с методом interact(player).
func _interact() -> void:
	var front_cell := Grid.world_to_cell(self, global_position) + facing
	for node in get_tree().get_nodes_in_group("interactable"):
		if node == self or not (node is Node2D) or not node.has_method("interact"):
			continue
		if Grid.world_to_cell(self, node.global_position) == front_cell:
			node.interact(self)
			return


func _play_animation() -> void:
	var anim := "run" if _is_moving else "idle"
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


#func take_damage(amount: int = 1) -> void:
	#if is_dead or _iframe_timer > 0.0:
		#return
	#hp = maxi(0, hp - amount)
	#_iframe_timer = IFRAME_DURATION
	#hp_changed.emit(player_index, hp)
	#if hp <= 0:
		#visible = false
		#_collision_shape.set_deferred("disabled", true)
		#set_physics_process(false)
		#died.emit(player_index)


## Возвращает "p1_move_up", "p2_move_left" и т.д.
#func _p(action: String) -> String:
	#return "p%d_%s" % [player_index, action]
