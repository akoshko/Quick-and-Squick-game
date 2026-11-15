class_name ZombieModerator
extends NPC

## Модератор, который спит на пуфе. Пока восстание не началось, это просто
## «Уставший модератор» (npc_name): лежит и похрапывает (спрайт sleep_texture,
## уже нарисован лёжа). Встал во время восстания — он «Зомби-модератор»
## (risen_name), улёгся обратно — снова уставший.
##
## Восстание (ZombieUprising): rise() — встаёт, start_roaming() — бродит по
## карте по клеткам (кадры walk_frames), ловит игроков. go_home() — идёт
## к своему пуфу напрямую, сквозь стены и предметы, и снова засыпает.
##
## Сеть: куда идти и когда вставать/ложиться, решает только сервер. Клиенты получают
## позицию, режим и «спит ли» (WorldSync, net_state) и повторяют анимации; выкрики и хрип
## на ходу у каждого клиента свои.

## Спящий зомби (картинка лёжа). Если не задан — обычный спрайт кладётся на бок
@export var sleep_texture: Texture2D
## Кадры ходьбы (сменяются по мере пути)
@export var walk_frames: Array[Texture2D] = []
## Пуф, на котором спит зомби (область 32×32 на листе tile_map.png)
@export var bed_region := Rect2(176, 0, 32, 32)
@export var bed_sheet: Texture2D = preload("res://src/tile_map.png")
@export var asleep := true
## Как зовут вставшего во время восстания (спящего — npc_name)
@export var risen_name := "Зомби-модератор"
@export var risen_lines: PackedStringArray = PackedStringArray(["ыыыы… дедлайн…", "мозги… то есть код-ревью…", "ууу… прод упал…"])
## Что выкрикивают, пока бродят (раз в shout_every секунд, каждый в своём ритме)
@export var shouts: PackedStringArray = PackedStringArray(["хочу спать!", "вайфай на табличке!", "еды больше нет!", "где кофе!!"])
@export var shout_every := 3.0
@export var walk_speed := 40.0     ## пикселей в секунду (игрок — 120): медленно, но их много
@export var return_speed := 110.0  ## когда успокоился и идёт спать

const SLEEP_OFFSET := Vector2.ZERO      # спящий спрайт нарисован под пуф той же клетки
const LYING_ROTATION := 90.0             # без sleep_texture: обычный спрайт на боку
const LYING_OFFSET := Vector2(-16, -15)
const SNORE_EVERY := Vector2(2.0, 4.0)   # храп раз в столько секунд (от и до)
const SLEEPING_LAYER := 1                # спящий — препятствие; проснувшийся ходит сквозь всё
const GROWL_EVERY := Vector2(4.0, 9.0)   # пока бродит, хрипит раз в столько секунд (от и до)
const FIRST_SHOUT_DELAY := 0.8           # первая реплика после подъёма — не раньше (с)
const SLEEP_LINE := "Хррр…"              # что «говорит» спящий

enum Mode { SLEEP, ROAM, RETURN }

var mode := Mode.SLEEP
var _home := Vector2.ZERO
var _uprising: ZombieUprising
var _rising := false
var _path: Array[Vector2i] = []
var _step_target := Vector2.ZERO
var _stepping := false
var _frame := 0
var _walked := 0.0
var _last_position := Vector2.ZERO
var _snore_timer := 0.0
var _tired_name := ""
var _growl_timer := 0.0
var _shout_timer := 0.0
var _last_shout := -1
var _bed: Sprite2D


func _ready() -> void:
	super()
	add_to_group("zombie_moderator")
	_tired_name = npc_name
	if not asleep:
		set_npc_name(risen_name)
	_home = global_position
	_last_position = global_position
	_make_bed.call_deferred()
	if asleep:
		_lie_down()
	else:
		collision_layer = 0
	_snore_timer = randf_range(SNORE_EVERY.x, SNORE_EVERY.y)


## Клетка пуфа
func get_home_cell() -> Vector2i:
	return Grid.world_to_cell(self, _home)


# Пуф — отдельный спрайт рядом с зомби (остаётся на месте, когда тот уходит).
# Стоит на 1 px выше, чтобы при сортировке по Y рисоваться под зомби.
func _make_bed() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = bed_sheet
	atlas.region = bed_region
	var bed := Sprite2D.new()
	bed.name = "%sBed" % name
	bed.texture = atlas
	bed.flip_h = randf() < 0.5
	_bed = bed
	get_parent().add_child(bed)
	bed.global_position = _home - Vector2(0, 1)
	bed.offset = Vector2(0, 1)


func _lie_down() -> void:
	collision_layer = SLEEPING_LAYER
	if sleep_texture:
		_sprite.texture = sleep_texture
		_sprite.offset = Vector2(0, -sleep_texture.get_height() / 2.0)
		_sprite.rotation = 0.0
		_draw_offset = SLEEP_OFFSET
	else:
		_sprite.rotation = deg_to_rad(LYING_ROTATION)
		_draw_offset = LYING_OFFSET


## Восстание! Зомби встаёт с пуфа
func rise() -> void:
	if not asleep:
		return
	_rising = true
	collision_layer = 0
	_become_risen()
	# Встают вразнобой, каждый бормочет своё (облачка соседей налезали бы друг на друга)
	await get_tree().create_timer(randf() * 0.6).timeout
	growl()
	await _stand_up().finished
	set_dialogue(risen_lines)
	var line: String = risen_lines[randi() % risen_lines.size()] if not risen_lines.is_empty() else "ыыыы…"
	FloatingText.spawn(self, global_position + Vector2(0, -22), line, Color(0.7, 1, 0.6))
	_rising = false


# Вскакивает с пуфа (анимация; у клиентов — по состоянию с сервера)
func _stand_up() -> Tween:
	if sleep_texture:
		# Подменяем картинку на стоящую и «подпрыгиваем» с пуфа
		_sprite.texture = sprite_texture
		_sprite.offset = Vector2(0, -sprite_texture.get_height() / 2.0)
		_draw_offset = Vector2(0, -6)
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "rotation", 0.0, 0.45)
	t.parallel().tween_property(self, "_draw_offset", Vector2.ZERO, 0.45)
	return t


## Хрип (слышно поблизости)
func growl() -> void:
	Sfx.play_at(&"growl", global_position, 0.15)
	_growl_timer = randf_range(GROWL_EVERY.x, GROWL_EVERY.y)


# Уставший модератор говорит обычным голосом NPC, а зомби — хрипит
func _voice(text: String) -> void:
	if asleep:
		super(text)
	else:
		growl()


# Случайная реплика в облачке (не та же, что в прошлый раз), без звука
func _shout() -> void:
	if shouts.is_empty():
		return
	var index := randi() % shouts.size()
	if index == _last_shout and shouts.size() > 1:
		index = (index + 1) % shouts.size()
	_last_shout = index
	say(shouts[index], minf(2.0, shout_every * 0.7), false)


## Начать бродить по карте (встаёт, если ещё лежит)
func start_roaming(uprising: ZombieUprising) -> void:
	_uprising = uprising
	_path.clear()
	_stepping = false
	mode = Mode.ROAM
	_schedule_first_shout()
	if asleep:
		rise()


## Успокоился: идёт к своему пуфу напрямую (сквозь всё) и засыпает
func go_home() -> void:
	mode = Mode.RETURN
	_path.clear()
	_stepping = false


func _physics_process(delta: float) -> void:
	_animate_walk()
	if mode == Mode.SLEEP or _rising:
		return
	# Звуки — у тех, кто их слышит; ходьба — у того, кто ведёт мир
	if mode == Mode.ROAM and Net.shows_personal_ui():
		# Хрип и выкрики — локальные, у каждого клиента свои (сервер их не рассылает)
		_growl_timer -= delta
		if _growl_timer <= 0.0:
			growl()
		_shout_timer -= delta
		if _shout_timer <= 0.0:
			_shout_timer += shout_every
			_shout()
	if _uprising == null or not Net.runs_world():
		return   # на клиенте зомби двигает синхронизация с сервера
	match mode:
		Mode.ROAM:
			_roam(delta)
			_uprising.check_catch(self)
		Mode.RETURN:
			global_position = global_position.move_toward(_home, return_speed * delta)
			if global_position == _home:
				fall_asleep()


func _roam(delta: float) -> void:
	if _stepping:
		global_position = global_position.move_toward(_step_target, walk_speed * delta)
		if global_position != _step_target:
			return
		_stepping = false
		# Заметил игрока, а идёт по длинному маршруту — сворачивает к нему
		if _path.size() > 2 and _uprising.sees_player(self):
			_path.clear()
	if _path.is_empty():
		_path = _uprising.next_path(self)
		if _path.is_empty():
			return
	_step_target = Grid.cell_to_world(self, _path.pop_front())
	_stepping = true


# Анимация по пройденному пути (одинаково на сервере и на клиентах):
# поворот, смена кадров ходьбы каждые полклетки и покачивание
func _animate_walk() -> void:
	var moved := global_position - _last_position
	_last_position = global_position
	if asleep or _rising or moved == Vector2.ZERO:
		return
	face_horizontal(moved.x)
	_walked += moved.length() / 16.0
	if int(_walked) != _frame:
		_frame = int(_walked)
		if not walk_frames.is_empty():
			_sprite.texture = walk_frames[_frame % walk_frames.size()]
	_draw_offset = Vector2(0, -absf(sin(_walked * PI)) * 2.0)


## Улечься на пуф (дошёл сам или пришло с сервера)
func fall_asleep() -> void:
	global_position = _home
	mode = Mode.SLEEP
	_become_tired()
	FloatingText.spawn(self, global_position + Vector2(0, -16), "z-z-z…", Color(0.75, 0.85, 1))
	if _uprising:
		_uprising.zombie_asleep(self)


# Проснулся зомби (сервер — в rise, клиент — по состоянию): имя и диалог закрыт
func _become_risen() -> void:
	asleep = false
	_close()
	set_npc_name(risen_name)


# Снова уставший модератор (сервер — в fall_asleep, клиент — по состоянию): лёг на пуф
func _become_tired() -> void:
	asleep = true
	_stepping = false
	_close()
	set_npc_name(_tired_name)
	set_dialogue(PackedStringArray([SLEEP_LINE]))
	_lie_down()


# Первая реплика — в случайный момент: зомби кричат не хором
func _schedule_first_shout() -> void:
	_shout_timer = randf_range(FIRST_SHOUT_DELAY, FIRST_SHOUT_DELAY + shout_every)


## Сеть: режим, спит ли и как повёрнут пуф (позицию WorldSync добавляет сам)
func net_state() -> Dictionary:
	return {"mode": mode, "asleep": asleep, "bed_flip": _bed != null and _bed.flip_h}


## Клиент: встать или улечься, как на сервере (звуки и надписи присылает сервер)
func apply_net_state(state: Dictionary) -> void:
	if is_instance_valid(_bed):
		_bed.flip_h = state.get("bed_flip", _bed.flip_h)
	var sleeping: bool = state.get("asleep", asleep)
	mode = state.get("mode", mode)
	if not sleeping and asleep:
		_become_risen()
		_stand_up()
		set_dialogue(risen_lines)
		_schedule_first_shout()
	elif sleeping and not asleep:
		_become_tired()


# Пока ходит — без «дыхания»
func _idle_paused() -> bool:
	return mode != Mode.SLEEP and not _rising


func _process(delta: float) -> void:
	super(delta)
	if not asleep or not Net.shows_personal_ui():
		return   # храп у каждого клиента свой
	_snore_timer -= delta
	if _snore_timer <= 0.0:
		_snore_timer = randf_range(SNORE_EVERY.x, SNORE_EVERY.y)
		FloatingText.spawn(self, global_position + Vector2(6, -4), "z", Color(0.75, 0.85, 1))
