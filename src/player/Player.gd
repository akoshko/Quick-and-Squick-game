class_name Player
extends CharacterBody2D

## Игрок. Top-down движение в 8 направлениях мелкими шагами по четверть
## тайла (8 px): позиции всегда ровные (кратны 8), что удобно для сети.
## По диагонали скорость та же, что и по прямой.
## Игроки и модератор на отдельном физическом слое «персонажи» и
## проходят друг сквозь друга — никто ни в кого не застревает.
## Раз в тайл пути — анимация «сжатия и растяжения» (squash & stretch).

signal respawned   ## игрок возродился (respawn_at)
signal emoted(emote: int)   ## свой игрок показал эмоцию (сеть рассылает её остальным)

const GROUP := "player"
const RESPAWN_GROUP := "player_respawn"   ## маркер точки возрождения на уровне
## Личные цели действия (реплики NPC, прятки): в сети их выполняет клиент игрока у своей копии
## мира — по своим квестам; остальное (мешки, босс, станции…) выполняет сервер в общем мире.
const PERSONAL_GROUP := "personal_interaction"
const SUBSTEPS := 4            # шаг = тайл / 4 = 8 px
const CORNER_NUDGE_STEPS := 2  # на сколько подшагов «доводим» к проходу у угла
const REACH := 44.0            # докуда (px от центра игрока) достаёт «действие»: ≈1,4 клетки
const REACH_SLACK := 12.0      # запас, прежде чем начатый разговор закроется
const FACING_BONUS := 16.0     # предмет перед глазами «ближе» на столько px
const PUSH_ALIGN := 20.0       # мешок толкаем, только если смещены вбок не больше чем на столько
const NAMEPLATE_FONT_SIZE := 8  # ник над головой (в пикселях мира)
const NAMEPLATE_Y := -17.0      # нижний край ника — чуть выше макушки
const ZZ_FONT_SIZE := 9
const ZZ_COLOR := Color("#9fd8ff")
const EMOTE_Y := -28.0          # кончик облачка эмоции — над ником
const EMOTE_PITCH: Array[float] = [1.0, 1.25, 1.45, 0.85]   # «голос» эмоции: у каждой свой тон

## Этим персонажем управляет этот компьютер (клавиатура, геймпад, экран).
## Сетевые игроки — is_local = false: их двигает и одевает сетевой код
## (позиция — с сервера, внешность — через set_appearance()).
@export var is_local := true
@export var move_speed: float = 120.0   # пикселей в секунду
# Размер клетки берётся из TileMapLayer уровня (см. Grid.gd)

## Куда смотрит персонаж на исходной картинке. chel_1 смотрит влево;
## для спрайта, который смотрит вправо, сними галочку.
@export var sprite_faces_left := true

@export_group("Анимация шага")
@export var squash := 0.28      # насколько сплющивается (0 — без анимации)
@export var hop_height := 4.0   # на сколько пикселей подпрыгивает

@export_group("Анимация покоя")
@export var idle_squash := 0.05   # насколько «оседает» в покое (0 — без анимации)
@export var idle_speed := 2.4     # скорость «дыхания»

var _step_tween: Tween
var _sprite_base: Vector2   # где спрайт стоит в покое (в ногах)

var _target_position: Vector2   # куда сейчас едем (в пикселях)
var _is_moving := false         # «занят» ли персонаж (едет на подшаг)
var _walk_distance := -1.0      # путь с прошлой анимации шага (-1 — стояли)
var _idle_time := 0.0           # фаза «дыхания» в покое
var _start_position := Vector2.ZERO   # где появился (если на уровне нет точки возрождения)
var _restored_tiles := Rect2i()
var _restore_frame := 0

## Куда смотрит игрок. Нужен для взаимодействия: предметы узнают
## отсюда, в какую сторону их толкают.
var facing := Vector2i.DOWN

## Во сколько раз крупнее подпись «Игрок N» в экранном виде (проектор, вся карта)
const SCREEN_LABEL_SCALE := 2.5

## Сеть. На сервере персонажем управляет ввод игрока (RPC NetWorld.submit_input),
## а не клавиатура. На клиентах позиция приходит синхронизатором.
var network_controlled := false
var remote_dir := Vector2i.ZERO
var remote_action := false
## Номер игрока для подписи «Игрок N» (реплицируется)
@export var player_number := 0:
	set(value):
		player_number = value
		_update_label()
## Реплицируемый профиль с сервера: внешность, аксессуар и подпись над головой.
## Пустой профиль даёт подпись «Игрок N» и спрайт сцены.
@export var profile: Dictionary = {}:
	set(value):
		profile = value
		_apply_profile()
## Игрок отключился, персонаж ждёт его возвращения (реплицируется)
@export var held := false:
	set(value):
		held = value
		modulate.a = 0.5 if held else 1.0

var _net_view := false          # клиент: только рисуем реплицированную позицию
var _interact_queued := false   # сервер: игрок нажал «действие» (NetWorld.request_interact)
var _interact_actor_peer := 0   # чей это запрос: личные события (квесты) уходят ему
var _net_last_pos := Vector2.ZERO
var _net_lag := Vector2.ZERO    # визуальное отставание спрайта (сглаживание тиков)
var _net_still := 0.0
var _sprite_offset: Vector2
var _label_base: Vector2

var _hint: InteractHint   # подсказка «нажми E» над ближайшим предметом (только у своего)
var _nameplate: Label     # ник над головой
var _effect: Label        # награда-эффект над головой («Zz»)
var _emote_bubble: EmoteBubble   # облачко эмоции (пока живо — новую не показать)
var _emote := -1                 # какая эмоция сейчас над головой

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _label: Label = $Label


func _ready() -> void:
	# Все игроки (свой и сетевые) — в группе "player": так их ищут зомби, кофе и т.п.
	if visible:
		add_to_group(GROUP)
	# На старте ставим персонажа ровно в центр клетки, в которой он стоит
	Grid.snap(self)
	_target_position = global_position
	_start_position = global_position
	_sprite_base = _sprite.position
	_sprite_offset = _sprite.offset
	_label_base = _label.position
	if Net.is_screen():
		# проектор показывает всю карту мелко: подпись крупнее, растёт вверх от низа по центру
		_label.pivot_offset = Vector2(_label.size.x * 0.5, _label.size.y)
		_label.scale = Vector2.ONE * SCREEN_LABEL_SCALE
	_apply_profile()

	if Net.is_network():
		# В сети «свой» — только персонаж этого клиента; на сервере своих нет
		# (там персонажей ведёт ввод игроков: network_controlled)
		is_local = Net.client != null and name == Net.client.player_id

	# Клиент: персонажей двигает сервер, здесь только анимация по позиции
	if Net.is_view():
		_net_view = true
		_net_last_pos = position
		set_physics_process(false)
		if is_local:
			# Свои эмоции: облачко сразу здесь, остальным их рассылает сервер (NetWorld.submit_emote)
			var bar := EmoteBar.new()
			bar.player = self
			add_child(bar)
			# подсказка «E» над целью, как в одиночной игре (само действие решает сервер)
			_hint = InteractHint.new()
			add_child(_hint)
		return

	# Скрытый игрок (например, Player2 в одиночной игре) не должен
	# ни ходить от тех же кнопок, ни быть невидимой стеной
	if not visible:
		_collision_shape.disabled = true
		set_physics_process(false)
		return

	if is_local:
		# Подсказка «E» и внешность из профиля — только у своего персонажа
		_hint = InteractHint.new()
		add_child(_hint)
		# Кнопки эмоций (справа на компьютере, меню в углу на телефоне)
		var emote_bar := EmoteBar.new()
		emote_bar.player = self
		add_child(emote_bar)
		set_appearance(PlayerProfile.to_dict())
		PlayerProfile.accessory_changed.connect(_refresh_local_accessory)


func _refresh_local_accessory(_id: String) -> void:
	_sprite.texture = PlayerProfile.texture()
	NicknameStyle.apply(_nameplate, PlayerProfile.nickname_color)
	_show_effect(PlayerProfile.accessory)


## Применить внешность и ник из PlayerProfile.to_dict().
func set_appearance(data: Dictionary) -> void:
	var clean := CharacterLook.sanitize(data)
	_sprite.texture = CharacterLook.build_from(clean)
	_set_nameplate(clean.nickname)
	NicknameStyle.apply(_nameplate, data.get("nickname_color"))
	_show_effect(clean.accessory)


# Награда-эффект над головой (не рисуется на спрайте): «Zz» за победу над зомби —
# жирные буквы, покачиваются и мерцают над ником
func _show_effect(accessory_id: String) -> void:
	var wanted := accessory_id == "zz"
	if not wanted:
		if is_instance_valid(_effect):
			_effect.queue_free()
		_effect = null
		return
	if is_instance_valid(_effect):
		return
	_effect = Label.new()
	_effect.text = "Zz"
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect.add_theme_font_size_override("font_size", ZZ_FONT_SIZE)
	_effect.add_theme_color_override("font_color", ZZ_COLOR)
	# «Жирный шрифт»: толстая обводка того же цвета утолщает буквы, тёмная тень — контур
	_effect.add_theme_color_override("font_outline_color", ZZ_COLOR)
	_effect.add_theme_constant_override("outline_size", 2)
	_effect.add_theme_color_override("font_shadow_color", Color(0.08, 0.08, 0.12))
	_effect.add_theme_constant_override("shadow_offset_x", 1)
	_effect.add_theme_constant_override("shadow_offset_y", 1)
	_effect.z_index = 50
	add_child(_effect)
	_effect.reset_size()
	# Над подписью: своя (_nameplate) или сетевая (_label)
	var above: Control = _nameplate if is_instance_valid(_nameplate) and _nameplate.visible else _label
	var top := above.position.y if above else NAMEPLATE_Y - 10.0
	var base := Vector2(-_effect.size.x * 0.3, top - _effect.size.y + 2.0)
	_effect.position = base
	var float_up := _effect.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	float_up.tween_property(_effect, "position", base + Vector2(3, -3), 0.9)
	float_up.parallel().tween_property(_effect, "modulate:a", 0.55, 0.9)
	float_up.tween_property(_effect, "position", base, 0.9)
	float_up.parallel().tween_property(_effect, "modulate:a", 1.0, 0.9)


## Для сетевого игрока: плавно перейти в точку (пришедшую с сервера).
## Анимация шага играет так же, как у своего персонажа.
func move_to(world_pos: Vector2, new_facing := facing) -> void:
	facing = new_facing
	var dx := world_pos.x - global_position.x
	if dx != 0.0:
		_sprite.flip_h = (dx < 0.0) != sprite_faces_left
	if world_pos != global_position:
		_start_substep(world_pos)


# Ник над головой (пустой ник — без таблички)
func _set_nameplate(nickname: String) -> void:
	if _nameplate == null:
		_nameplate = Label.new()
		_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nameplate.add_theme_font_size_override("font_size", NAMEPLATE_FONT_SIZE)
		_nameplate.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.12))
		_nameplate.add_theme_constant_override("outline_size", 3)
		_nameplate.z_index = 50
		add_child(_nameplate)
	_nameplate.text = nickname
	_nameplate.visible = not nickname.is_empty()
	_nameplate.reset_size()
	_nameplate.position = Vector2(-_nameplate.size.x / 2.0, NAMEPLATE_Y - _nameplate.size.y)


func _physics_process(delta: float) -> void:
	if GameManager.state == GameManager.GameState.PAUSED:
		return

	if _restore_frame != 0:
		if Engine.get_physics_frames() < _restore_frame:
			return
		if (not _escape_overlap() and _is_moving
				and test_move(global_transform, _target_position - global_position)):
			_is_moving = false
		_restore_frame = 0
		_restored_tiles = Rect2i()

	# 1. Если едем — плавно приближаемся к цели
	if _is_moving:
		global_position = global_position.move_toward(_target_position, move_speed * delta)
		if global_position == _target_position:
			_is_moving = false

	# Сетевого игрока клавиатура не двигает — его позицию задаёт сетевой код
	# (например, через move_to()), а мы только доводим его до цели выше.
	if not is_local and not network_controlled:
		return

	# 2. Если стоим — читаем кнопки и пробуем шагнуть.
	# Кнопки читаются только когда стоим, поэтому is_action_pressed
	# не разгонит персонажа, а при удержании он идёт без остановок.
	if not _is_moving:
		var direction := _read_direction()
		if _action_just_pressed():
			_interact()
		elif _interact_queued:
			# Сеть: «действие» игрока — та же логика, что в одиночной игре, от его имени
			_interact_queued = false
			Net.as_actor(_interact_actor_peer, _interact)
		if _restore_frame == 0 and direction != Vector2i.ZERO:
			_try_step(direction)
			if not _is_moving:
				_escape_overlap(direction)
		elif direction == Vector2i.ZERO:
			_walk_distance = -1.0   # остановились — следующий шаг начнётся с анимации

	_update_hint()


# 8 направлений: каждая ось отдельно, встречные кнопки гасят друг друга.
# Например (1, -1) — вправо-вверх.
func _read_direction() -> Vector2i:
	if network_controlled:
		return remote_dir
	var x := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	var y := int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))
	return Vector2i(x, y)


func _action_just_pressed() -> bool:
	# сетевой персонаж действует по запросу (queue_interact), а не по удержанию кнопки
	return not network_controlled and Input.is_action_just_pressed("action")


## Сервер: игрок пира peer нажал «действие» — выполнить, как только персонаж встанет в клетку
## (как в одиночной игре: действие читается, только когда не едем)
func queue_interact(peer: int) -> void:
	_interact_queued = true
	_interact_actor_peer = peer


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


func check_restored_tiles(tiles: Rect2i) -> void:
	if not tiles.grow(1).has_point(Grid.world_to_cell(self, global_position)):
		return
	_restored_tiles = tiles
	# После отложенного обновления тайлов физике нужен ещё один кадр.
	_restore_frame = Engine.get_physics_frames() + 2


func _escape_overlap(direction := Vector2i.ZERO) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _collision_shape.shape
	query.transform = _collision_shape.global_transform
	query.collision_mask = collision_mask
	var space := get_world_2d().direct_space_state
	var overlaps := space.intersect_shape(query)
	if overlaps.is_empty():
		return false
	var starting_bodies := {}
	for hit in overlaps:
		starting_bodies[hit.rid] = true

	var origin := query.transform
	var layer := Grid.get_layer(self)
	var step := _substep()
	var cell_center := Grid.cell_to_world(self, Grid.world_to_cell(self, global_position))
	var aligned := cell_center + (global_position - cell_center).snapped(Vector2.ONE * step)
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	if direction != Vector2i.ZERO:
		directions.erase(direction)
		directions.push_front(direction)
	var max_steps := (maxi(1, maxi(_restored_tiles.size.x, _restored_tiles.size.y)) + 1) * SUBSTEPS
	var closest_target := global_position
	var closest_distance := INF
	for dir in directions:
		for n in range(1, max_steps + 1):
			var target := aligned + Vector2(dir) * step * n
			var shifted := origin
			shifted.origin += target - global_position
			query.transform = shifted
			overlaps = space.intersect_shape(query)
			if overlaps.is_empty():
				var distance := global_position.distance_squared_to(target)
				if distance < closest_distance:
					closest_distance = distance
					closest_target = target
				break
			# Можно выйти через восстановленный предмет, но не через соседнюю стену.
			if overlaps.any(func(hit: Dictionary) -> bool:
				if starting_bodies.has(hit.rid):
					return false
				if hit.collider == layer:
					return not _restored_tiles.has_point(layer.get_coords_for_body_rid(hit.rid))
				if hit.collider is ResourceStation:
					return not _restored_tiles.has_point(Grid.world_to_cell(self, hit.collider.global_position))
				return true):
				break
		if direction != Vector2i.ZERO and closest_distance < INF:
			break
	if closest_distance == INF:
		return false
	_walk_distance = -1.0
	_start_substep(closest_target)
	return true


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


# Взаимодействуем с целью (см. find_target). Если цель сбоку или сзади —
# сначала поворачиваемся к ней: мешок толкается туда, куда смотрим.
func _interact() -> void:
	var target := find_target()
	if target == null:
		return
	var dir := _dir_to(target)
	if dir != facing:
		facing = dir
		if dir.x != 0:
			_sprite.flip_h = (dir.x < 0) != sprite_faces_left
	# Диалог и прятки у каждого свои: на сервере такую цель выполняет клиент игрока
	if is_personal_target(target) and Net.route_personal_interact(_interact_actor_peer, target):
		if target is NPC:
			target.track_server_interaction(self)
		return
	target.interact(self)


## Личная цель действия (группа PERSONAL_GROUP: реплики NPC, прятки)
static func is_personal_target(target: Node) -> bool:
	return target.is_in_group(PERSONAL_GROUP)


## Клиент: цель действия, если она личная (её клиент выполняет сам), иначе null
func personal_target() -> Node2D:
	var target := find_target()
	return target if target != null and is_personal_target(target) else null


## Цель для «действия»: ближайший предмет в пределах досягаемости (REACH),
## а тот, на который смотрим, — в приоритете. Считаем по расстоянию, а не по
## клеткам: так работает и вплотную (компьютер на столе, модератор, сквозь
## которого можно пройти), и наискосок. Мешок (есть push) толкается, только
## если стоим почти на одной линии с ним — правила сокобана не меняются.
## Подходит любой узел из группы "interactable" с методом interact(player).
## Публичная: по ней и клиент выбирает личную цель (NetInput).
func find_target() -> Node2D:
	var best: Node2D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		if node == self or not (node is Node2D) or not node.has_method("interact"):
			continue
		var to := _nearest_point(node) - global_position
		var dist := to.length()
		if dist > REACH:
			continue
		var dir := _axis_dir(to)
		if node.has_method("push") and absf(to.y if dir.x != 0 else to.x) > PUSH_ALIGN:
			continue
		var score := dist - (FACING_BONUS if dir == facing else 0.0)
		if score < best_score:
			best_score = score
			best = node
	return best


## Достаёт ли «действие» игрока до предмета (например, NPC закрывает
## облачко, когда игрок отошёл дальше)
func can_reach(node: Node2D) -> bool:
	return (_nearest_point(node) - global_position).length() <= REACH + REACH_SLACK


# Ближайшая к игроку точка предмета: большие предметы (босс 2×2)
# сообщают свои клетки через get_cells()
func _nearest_point(node: Node2D) -> Vector2:
	if not node.has_method("get_cells"):
		return node.global_position
	var best := node.global_position
	var best_dist := INF
	for cell: Vector2i in node.get_cells():
		var point := Grid.cell_to_world(self, cell)
		var dist := point.distance_squared_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = point
	return best


# Одно из 4 направлений по большей оси; при равенстве — взгляд, если подходит
func _axis_dir(to: Vector2) -> Vector2i:
	var x := Vector2i(signi(roundi(to.x)), 0)
	var y := Vector2i(0, signi(roundi(to.y)))
	if absf(to.x) > absf(to.y):
		return x
	if absf(to.y) > absf(to.x):
		return y
	if to == Vector2.ZERO or facing == x or facing == y:
		return facing
	return x


# Куда повернуться к цели перед действием (мешок поедет в эту сторону)
func _dir_to(target: Node2D) -> Vector2i:
	return _axis_dir(_nearest_point(target) - global_position)


## Мгновенно переставить игрока (например, босс отбросил при появлении)
func displace_to(world_pos: Vector2) -> void:
	# В сети позицию задаёт сервер (он и отбрасывает); клиент её только показывает
	if Net.is_view():
		return
	global_position = world_pos
	_target_position = world_pos
	_is_moving = false


## Точка возрождения: маркер уровня из группы RESPAWN_GROUP (на новой
## карте — в зоне перекуса), а если его нет — место, где игрок появился
func respawn_position() -> Vector2:
	var marker := get_tree().get_first_node_in_group(RESPAWN_GROUP) as Node2D
	if marker:
		return Grid.cell_to_world(self, Grid.world_to_cell(self, marker.global_position))
	return _start_position


## Вернуться на точку возрождения (кнопка «Я застрял» в меню)
func respawn() -> void:
	if _net_view:
		# в сети персонажа переставляет сервер
		var world := Net.world()
		if world != null and Net.connected_to_server():
			world.request_respawn.rpc_id(1)
		return
	respawn_at(respawn_position())


## Можно ли показать эмоцию: пока прошлое облачко не исчезло — нельзя
func can_emote() -> bool:
	return not is_instance_valid(_emote_bubble)


## Какая эмоция сейчас над головой (-1 — никакой)
func current_emote() -> int:
	return _emote if is_instance_valid(_emote_bubble) else -1


## Своя эмоция (кнопки, клавиши 1–4) — с защитой от спама.
## Возвращает false, если прошлое облачко ещё не исчезло.
func try_emote(emote: int) -> bool:
	if not can_emote() or not visible:
		return false
	show_emote(emote)
	emoted.emit(emote)
	return true


## Показать эмоцию над головой: облачко с иконкой и одно «сжатие».
## Для сетевых игроков вызывает сетевой код, когда пришла их эмоция.
func show_emote(emote: int) -> void:
	if is_instance_valid(_emote_bubble):
		_emote_bubble.queue_free()
	_emote = emote
	_emote_bubble = EmoteBubble.new()
	_emote_bubble.kind = emote as EmoteBubble.Kind
	_emote_bubble.position = Vector2(0, EMOTE_Y)
	add_child(_emote_bubble)
	Sfx.play_at(&"voice", global_position, 0.04, 0.0, EMOTE_PITCH[emote % EMOTE_PITCH.size()])
	# Единичное сжатие: присел и пружинкой обратно
	if _step_tween:
		_step_tween.kill()
	_sprite.position = _sprite_base
	_step_tween = create_tween()
	_step_tween.tween_property(_sprite, "scale", Vector2(1.0 + squash, 1.0 - squash), 0.08)
	_step_tween.tween_property(_sprite, "scale", Vector2.ONE, 0.4) 			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Возрождение в точке (например, поймал зомби). В сетевой игре сервер решает,
## что игрок пойман, и вызывает это у клиента-владельца персонажа.
func respawn_at(world_pos: Vector2) -> void:
	displace_to(world_pos)
	_walk_distance = -1.0
	respawned.emit()


# Подсказка «нажми E» над текущей целью. Предмет может попросить её
# спрятать (например, NPC, пока над ним облачко с репликой)
func _update_hint() -> void:
	if _hint == null:
		return
	var target := find_target()
	if target and target.has_method("hides_interact_hint") and target.hides_interact_hint():
		target = null
	_hint.set_target(target)


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


# Анимация покоя: лёгкое «дыхание» — плавно оседает и расширяется от пола
# и возвращается. Пока идём (или доигрывает анимация шага) — выключена.
func _process(delta: float) -> void:
	if _net_view:
		_follow_replicated_position(delta)
		_update_hint()
	if _is_moving or (_step_tween and _step_tween.is_running()):
		_idle_time = 0.0
		return
	_idle_time += delta * idle_speed
	# (1 - cos) / 2 плавно идёт 0 → 1 → 0, начиная с нуля — без рывка после шага
	var squeeze := idle_squash * (1.0 - cos(_idle_time)) / 2.0
	_sprite.scale = Vector2(1.0 + squeeze * 0.6, 1.0 - squeeze)


# Клиент: позиция приходит тиками (20 Гц). Спрайт и подпись отстают
# от узла на пройденный за тик путь и догоняют его с обычной скоростью,
# поэтому движение плавное; анимация шага — как при локальной ходьбе.
func _follow_replicated_position(delta: float) -> void:
	var moved := position - _net_last_pos
	_net_last_pos = position
	var tile := Grid.tile_size(self).x
	if moved != Vector2.ZERO:
		_net_still = 0.0
		if moved.length() > tile * 2.0:   # телепорт (спавн, перезапуск) — без сглаживания
			_net_lag = Vector2.ZERO
			_walk_distance = -1.0
		else:
			_net_lag = (_net_lag - moved).limit_length(tile)
			if moved.x != 0.0:
				_sprite.flip_h = (moved.x < 0.0) != sprite_faces_left
			if _walk_distance < 0.0 or _walk_distance >= tile:
				_walk_distance = 0.0
				_play_step_animation()
			_walk_distance += moved.length()
	else:
		_net_still += delta
		if _net_still > 0.2:
			_walk_distance = -1.0
	_net_lag = _net_lag.move_toward(Vector2.ZERO, move_speed * 1.25 * delta)
	_sprite.offset = _sprite_offset + _net_lag
	_label.position = _label_base + _net_lag
	_is_moving = _net_lag != Vector2.ZERO


## Подпись над сетевым игроком: ник из профиля (его проверил сервер), иначе «Игрок N».
func display_name() -> String:
	var nick := str(profile.get("name", ""))
	return nick if nick != "" else "Игрок %d" % player_number


# Внешность и подпись из сетевого профиля. Серверу текстура не нужна (он ничего не рисует).
func _apply_profile() -> void:
	if _sprite != null and not profile.is_empty() and not Net.is_server():
		_sprite.texture = CharacterLook.build_from(profile)
		_show_effect(CharacterLook.clean_accessory(profile.get("accessory")))
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	_label.visible = player_number > 0
	_label.text = display_name()
	NicknameStyle.apply(_label, profile.get("nickname_color"))
