class_name Player
extends CharacterBody2D

## Игрок. Top-down движение в 8 направлениях мелкими шагами по четверть
## тайла (8 px): позиции всегда ровные (кратны 8), что удобно для сети.
## По диагонали скорость та же, что и по прямой.
## Игроки и модератор на отдельном физическом слое «персонажи» и
## проходят друг сквозь друга — никто ни в кого не застревает.
## Раз в тайл пути — анимация «сжатия и растяжения» (squash & stretch).

#signal died(player_index: int)
#signal hp_changed(player_index: int, new_hp: int)

const IFRAME_DURATION := 1.2
const SUBSTEPS := 4            # шаг = тайл / 4 = 8 px
const CORNER_NUDGE_STEPS := 2  # на сколько подшагов «доводим» к проходу у угла

#@export var player_index: int = 1
@export var move_speed: float = 120.0   # пикселей в секунду
# Размер клетки берётся из TileMapLayer уровня (см. Grid.gd)

## Куда смотрит персонаж на исходной картинке. chel_1 смотрит влево;
## для спрайта, который смотрит вправо, сними галочку.
@export var sprite_faces_left := true

@export_group("Анимация шага")
@export var squash := 0.28      # насколько сплющивается (0 — без анимации)
@export var hop_height := 4.0   # на сколько пикселей подпрыгивает
#@export var max_hp: int = 3

#var hp: int
#var is_dead: bool:
	#get:
		#return hp <= 0

var _iframe_timer := 0.0
var _step_tween: Tween
var _sprite_base: Vector2   # где спрайт стоит в покое (в ногах)

var _target_position: Vector2   # куда сейчас едем (в пикселях)
var _is_moving := false         # «занят» ли персонаж (едет на подшаг)
var _walk_distance := -1.0      # путь с прошлой анимации шага (-1 — стояли)

## Куда смотрит игрок. Нужен для взаимодействия: предметы узнают
## отсюда, в какую сторону их толкают.
var facing := Vector2i.DOWN

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
	_sprite_base = _sprite.position

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
		else:
			_walk_distance = -1.0   # остановились — следующий шаг начнётся с анимации

	_tick_iframes(delta)


# 8 направлений: каждая ось отдельно, встречные кнопки гасят друг друга.
# Например (1, -1) — вправо-вверх.
func _read_direction() -> Vector2i:
	var x := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	var y := int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))
	return Vector2i(x, y)


func _try_step(direction: Vector2i) -> void:
	if direction.x != 0:
		var going_left := direction.x < 0
		# отражаем, когда идём в сторону, противоположную картинке
		_sprite.flip_h = going_left != sprite_faces_left

	var step := _substep()
	if direction.x != 0 and direction.y != 0:
		_try_diagonal_step(direction, step)
		return

	# Поворачиваемся, даже если шагнуть нельзя: так можно
	# встать лицом к мешку, упёршись в него
	facing = direction

	# Подшаг на четверть тайла. Стена? Проверяем ДО шага
	var motion := Vector2(direction) * step
	if not test_move(global_transform, motion):
		_start_substep(global_position + motion)
		return

	# Упёрлись. Если проход совсем рядом (угол), подталкиваем к нему вбок —
	# так не нужно попадать в дверь с точностью до пикселя
	var nudge := _corner_nudge(direction, step)
	if nudge != Vector2.ZERO:
		_start_substep(global_position + nudge)


# Диагональный подшаг (8, 8). Путь длиннее в √2 раза, а скорость та же
# (move_toward в _physics_process), поэтому по диагонали не быстрее, чем прямо.
# Если диагональ упирается в стену — скользим вдоль неё по свободной оси.
func _try_diagonal_step(direction: Vector2i, step: float) -> void:
	var along_x := Vector2(direction.x, 0) * step
	var along_y := Vector2(0, direction.y) * step
	var x_free := not test_move(global_transform, along_x)
	var y_free := not test_move(global_transform, along_y)

	# Взгляд для «действия» — одно из 4 направлений. Если упёрлись в стол
	# или мешок по одной из осей — смотрим на него; иначе сохраняем взгляд,
	# если он совпадает с одной из осей, или смотрим по горизонтали.
	if not y_free:
		facing = Vector2i(0, direction.y)
	elif not x_free:
		facing = Vector2i(direction.x, 0)
	elif facing != Vector2i(direction.x, 0) and facing != Vector2i(0, direction.y):
		facing = Vector2i(direction.x, 0)

	var diagonal := along_x + along_y
	if x_free and y_free and not test_move(global_transform, diagonal):
		_start_substep(global_position + diagonal)
	elif x_free:
		_start_substep(global_position + along_x)
	elif y_free:
		_start_substep(global_position + along_y)


func _substep() -> float:
	return Grid.tile_size(self).x / SUBSTEPS


# Ищем свободный путь вперёд, сдвинувшись вбок на 1..CORNER_NUDGE_STEPS
# подшагов. Возвращает сдвиг на один подшаг в сторону прохода (или ноль).
func _corner_nudge(direction: Vector2i, step: float) -> Vector2:
	var forward := Vector2(direction) * step
	var side := Vector2(absf(direction.y), absf(direction.x))   # перпендикуляр
	for n in range(1, CORNER_NUDGE_STEPS + 1):
		for dir_sign: float in [1.0, -1.0]:
			var offset := side * dir_sign * step * n
			var shifted := global_transform
			shifted.origin += offset
			if not test_move(global_transform, offset) and not test_move(shifted, forward):
				return side * dir_sign * step
	return Vector2.ZERO


func _start_substep(target: Vector2) -> void:
	# Анимация шага: в начале движения и потом раз в тайл пройденного пути
	if _walk_distance < 0.0 or _walk_distance >= Grid.tile_size(self).x:
		_walk_distance = 0.0
		_play_step_animation()
	_walk_distance += global_position.distance_to(target)
	_target_position = target
	_is_moving = true


# Ищем предмет в клетке перед собой и взаимодействуем с ним.
# «Своя» клетка — та, где центр игрока; когда упёрся в предмет,
# предмет всегда в соседней клетке по направлению взгляда.
# Подходит любой узел из группы "interactable" с методом interact(player).
func _interact() -> void:
	var front_cell := Grid.world_to_cell(self, global_position) + facing
	for node in get_tree().get_nodes_in_group("interactable"):
		if node == self or not (node is Node2D) or not node.has_method("interact"):
			continue
		if Grid.world_to_cell(self, node.global_position) == front_cell:
			node.interact(self)
			return


# Squash & stretch на один шаг. Спрайт «растёт» из ног (точка спрайта
# внизу клетки), поэтому при сплющивании персонаж оседает на пол.
func _play_step_animation() -> void:
	if _step_tween:
		_step_tween.kill()   # следующий шаг начинается сразу, без ожидания

	var step_time := Grid.tile_size(self).x / move_speed
	var flat := Vector2(1.0 + squash, 1.0 - squash)                # сплющен
	var tall := Vector2(1.0 - squash * 0.5, 1.0 + squash * 0.7)    # вытянут
	var land := Vector2(1.0 + squash * 0.6, 1.0 - squash * 0.5)    # удар о пол
	var up := _sprite_base + Vector2(0, -hop_height)

	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_step_tween = t
	# 1) присел перед прыжком
	t.tween_property(_sprite, "scale", flat, step_time * 0.15)
	# 2) прыжок: вытянулся и подлетел
	t.tween_property(_sprite, "scale", tall, step_time * 0.4)
	t.parallel().tween_property(_sprite, "position", up, step_time * 0.4)
	# 3) приземлился ровно к концу шага — снова сплющился (падение ускоряется)
	t.set_ease(Tween.EASE_IN)
	t.tween_property(_sprite, "scale", land, step_time * 0.45)
	t.parallel().tween_property(_sprite, "position", _sprite_base, step_time * 0.45)
	# 4) пружинка обратно в обычную форму, с небольшим «перелётом»
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", Vector2.ONE, 0.18)


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
