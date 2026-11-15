class_name ZombieTerminal
extends Node2D

## Компьютер в конце комнаты с головоломкой. Чтобы его сломать, нужно
## потыкать pokes_needed раз — над ним видна маленькая полоска прогресса.
## Когда сломан, начинается восстание зомби-модераторов: все узлы из группы
## "zombie_moderator" получают вызов rise().
## Когда зомби снова уснули (repair) — перезагрузка на cooldown секунд:
## на экране крутится загрузка, полная полоска плавно спускается до нуля,
## тыкать бесполезно. Потом компьютер снова как новенький.
##
## Спрайты — монитор с листа res://src/tile_map.png (клетки 16×16),
## загрузка — res://src/sokoban/monitor_loader.png (временный).

signal uprising_started

@export var pokes_needed := 20
@export var cooldown := 60.0   ## секунд перезагрузки после того, как зомби уснули
@export var sheet: Texture2D = preload("res://src/tile_map.png")
@export var loader_sheet: Texture2D = preload("res://src/sokoban/monitor_loader.png")

const FRAME_TIME := 0.45
const FLASH_TIME := 0.3
const CODE_FRAMES: Array[Vector2i] = [Vector2i(15, 8), Vector2i(15, 9)]
const POKE_FRAME := Vector2i(16, 8)                                         # синий грустный экран
const BROKEN_FRAMES: Array[Vector2i] = [Vector2i(16, 9), Vector2i(17, 8)]   # красный злой экран и «!»
const POKE_LINES: PackedStringArray = ["тык", "бип?", "тык-тык", "БИП!", "хрррр…"]
const LOADER_FRAME_TIME := 0.1   # кадр крутилки загрузки

# Полоска прогресса над монитором (пиксели мира, от точки узла)
const BAR_RECT := Rect2(-9, -21, 18, 3)
const BAR_BG := Color(0.1, 0.1, 0.14, 0.85)
const BAR_START := Color(1.0, 0.85, 0.3)
const BAR_END := Color(1.0, 0.3, 0.25)
const BAR_COOLDOWN := Color(0.45, 0.72, 1.0)   # пока перезагружается

var is_broken := false
var cooldown_left := 0.0   ## > 0 — перезагрузка, тыкать нельзя
var _pokes := 0
var _time := 0.0
var _flash := 0.0
var _atlas: AtlasTexture
var _bar: Node2D

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group(WorldSync.GROUP)   # в сети тычки, поломка и перезагрузка — с сервера
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	_sprite.texture = _atlas
	# Полоска — отдельным узлом поверх всего, чтобы её не закрывали стенд и зомби
	_bar = Node2D.new()
	_bar.z_index = 90
	_bar.z_as_relative = false
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_update_frame()


func interact(_player: Player) -> void:
	Net.world_call(self, &"net_shake")
	if is_broken:
		Sfx.play_at(&"boop", global_position, 0.05, -4.0)
		FloatingText.spawn(self, global_position + Vector2(0, -24), "Ошибка 500…", Color(1, 0.5, 0.45))
		return
	if cooldown_left > 0.0:
		Sfx.play_at(&"boop", global_position, 0.05, -6.0, 0.8)
		FloatingText.spawn(self, global_position + Vector2(0, -24),
				"Загрузка… %d с" % ceili(cooldown_left), Color(0.7, 0.85, 1))
		return
	_pokes += 1
	_bar.queue_redraw()
	if _pokes < pokes_needed:
		# Чем ближе к взлому, тем выше пищит
		Sfx.play_at([&"beep", &"boop"].pick_random(), global_position, 0.06, 0.0,
				1.0 + 0.5 * float(_pokes) / pokes_needed)
		Net.world_call(self, &"net_flash")
		FloatingText.spawn(self, global_position + Vector2(0, -24), POKE_LINES[(_pokes - 1) % POKE_LINES.size()])
		return
	is_broken = true
	_bar.visible = false
	Sfx.play_at(&"crash", global_position, 0.0, 2.0)
	FloatingText.spawn(self, global_position + Vector2(0, -24),
			"ВОССТАНИЕ ЗОМБИ-МОДЕРАТОРОВ!", Color(1, 0.35, 0.3))
	get_tree().call_group("zombie_moderator", "rise")
	uprising_started.emit()
	_update_frame()


## Починить (зомби снова уснули): перезагрузка на cooldown секунд,
## полоска спускается от полной до нуля, потом можно ломать заново
func repair() -> void:
	is_broken = false
	_pokes = 0
	_flash = 0.0
	cooldown_left = cooldown
	_bar.visible = true
	_bar.queue_redraw()
	FloatingText.spawn(self, global_position + Vector2(0, -24), "Перезагрузка…", Color(0.7, 0.85, 1))
	_update_frame()


## Состояние для сети: тычки, сломан ли, сколько осталось перезагрузки (целые секунды —
## дальше клиент досчитывает сам, а сервер не шлёт каждый кадр)
func net_state() -> Dictionary:
	return {"pokes": _pokes, "broken": is_broken, "cooldown_left": ceili(cooldown_left)}


## Клиент: тычки, поломка и перезагрузка с сервера
func apply_net_state(state: Dictionary) -> void:
	_pokes = state.get("pokes", 0)
	is_broken = state.get("broken", false)
	var server_cooldown: float = state.get("cooldown_left", 0)
	# перезагрузка кончилась — сразу; иначе досчитываем сами (WorldSync.resync_timer)
	cooldown_left = 0.0 if server_cooldown == 0.0 \
			else WorldSync.resync_timer(cooldown_left, server_cooldown)
	_bar.visible = not is_broken
	_bar.queue_redraw()
	_update_frame()


## Тычок засчитан (у всех, Net.world_call): экран коротко «мигает»
func net_flash() -> void:
	_flash = FLASH_TIME
	_update_frame()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
		_bar.queue_redraw()
		if cooldown_left == 0.0 and Net.runs_world():
			Sfx.play_at(&"beep", global_position, 0.0, 0.0, 1.3)   # снова в строю (в сети шлёт сервер)
	_update_frame()


func _update_frame() -> void:
	if _atlas == null:
		return
	if cooldown_left > 0.0:
		# Перезагрузка: крутилка загрузки с отдельного листа
		_atlas.atlas = loader_sheet
		var frames := maxi(1, floori(loader_sheet.get_width() / 16.0))
		_atlas.region = Rect2((int(_time / LOADER_FRAME_TIME) % frames) * 16, 0, 16, 16)
		return
	_atlas.atlas = sheet
	var cell: Vector2i
	if is_broken:
		# Сломанный мигает быстрее: тревога!
		cell = BROKEN_FRAMES[int(_time / (FRAME_TIME * 0.5)) % BROKEN_FRAMES.size()]
	elif _flash > 0.0:
		cell = POKE_FRAME
	else:
		cell = CODE_FRAMES[int(_time / FRAME_TIME) % CODE_FRAMES.size()]
	_atlas.region = Rect2(Vector2(cell) * 16.0, Vector2(16, 16))


func _draw_bar() -> void:
	var cooling := cooldown_left > 0.0
	var progress := cooldown_left / maxf(cooldown, 0.01) if cooling 			else float(_pokes) / float(maxi(pokes_needed, 1))
	progress = clampf(progress, 0.0, 1.0)
	_bar.draw_rect(BAR_RECT.grow(1.0), BAR_BG)
	if progress > 0.0:
		var fill := BAR_RECT
		fill.size.x *= progress
		_bar.draw_rect(fill, BAR_COOLDOWN if cooling else BAR_START.lerp(BAR_END, progress))


## Встряска от тычка (у всех, Net.world_call)
func net_shake() -> void:
	var t := create_tween()
	t.tween_property(_sprite, "position", Vector2(1.5, -7), 0.04)
	t.tween_property(_sprite, "position", Vector2(0, -6), 0.16).set_trans(Tween.TRANS_ELASTIC)
