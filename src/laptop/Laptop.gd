class_name Laptop
extends ResourceStation

## Рабочий компьютер хакатона на столе (ноутбук или монитор — поле style).
## По «действию» игрок в него тыкает: экран мигает, всплывает реплика.
## После pokes_needed тычков компьютер «зависает» (синий экран) и выполняется
## задание. Через 5 секунд приходит модератор и чинит его.
##
## Спрайты — с листа res://src/tile_map.png (клетки 16×16):
##   ноутбук: колонка 14 — код (2 кадра), синий экран, красный экран;
##   монитор: колонки 15–17 — код (2 кадра), синий грустный, красный злой, «!».

enum Style { LAPTOP, MONITOR }

@export var style := Style.MONITOR   ## монитор смотрит прямо; ноутбук — под углом
@export var quest_id := "poke_laptop"   ## какое задание выполнить (пусто — никакое)
@export var pokes_needed := 10
## Реплики на тычки: по очереди по кругу, последняя — когда компьютер завис
@export var poke_lines: PackedStringArray = ["тык", "тык-тык", "Ой, всё. Завис."]
## Лист со спрайтами компьютеров
@export var sheet: Texture2D = preload("res://src/tile_map.png")

const FRAME_TIME := 0.45   # смена кадров «бегущего кода»
const FLASH_TIME := 0.3    # сколько держится реакция на тычок
# Клетки листа (16×16) для каждого состояния
const FRAMES := {
	Style.LAPTOP: {"code": [Vector2i(14, 6), Vector2i(14, 7)], "poke": Vector2i(14, 9),
			"crashed": Vector2i(14, 8), "knocked": Vector2i(14, 9)},
	Style.MONITOR: {"code": [Vector2i(15, 8), Vector2i(15, 9)], "poke": Vector2i(17, 8),
			"crashed": Vector2i(16, 8), "knocked": Vector2i(16, 9)},
}

var _pokes := 0
var _time := 0.0
var _flash := 0.0
var _atlas: AtlasTexture
var _shake: Tween
var _sprite_home := Vector2.ZERO   # где спрайт стоит в покое (встряска возвращает сюда)

@onready var _sprite: Sprite2D = $Sprite2D   # спрайт в сцене — его видно в редакторе, центр = точка узла


func _ready() -> void:
	super()
	if refill_text == "":
		refill_text = "Починил!"
	_atlas = AtlasTexture.new()   # у каждого компьютера свой кадр
	_atlas.atlas = sheet
	_sprite.texture = _atlas
	_time = randf() * FRAME_TIME * 2.0  # компьютеры «мигают» не синхронно
	_update_frame()


func interact(_player: Player) -> void:
	_poke_shake()
	if is_empty:
		Sfx.play_at(&"boop", global_position, 0.05, -4.0)
		FloatingText.spawn(self, global_position + Vector2(0, -14), "Синий экран…", Color(0.7, 0.8, 1))
		return

	_pokes += 1
	FloatingText.spawn(self, global_position + Vector2(0, -14), _poke_line())

	if _pokes >= pokes_needed:
		Sfx.play_at(&"crash", global_position)
		if quest_id != "":
			Quests.complete(quest_id)
		_set_empty()   # «закончился» — через 5 с модератор починит
	else:
		Sfx.play_at([&"beep", &"boop"].pick_random(), global_position)
		_flash = FLASH_TIME   # короткая реакция на тычок
	_update_frame()


# Реплика на тычок: последняя — на поломку, остальные идут по кругу
func _poke_line() -> String:
	if poke_lines.is_empty():
		return "тык"
	if _pokes >= pokes_needed or poke_lines.size() == 1:
		return poke_lines[-1]
	return poke_lines[(_pokes - 1) % (poke_lines.size() - 1)]


func _on_refilled() -> void:
	_pokes = 0
	_flash = 0.0
	_poke_shake()
	_update_frame()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_update_frame()


func _update_frame() -> void:
	if _atlas == null:
		return
	var frames: Dictionary = FRAMES[style]
	var cell: Vector2i
	if is_knocked:
		cell = frames.knocked          # босс опрокинул
	elif is_empty:
		cell = frames.crashed          # завис — ждёт модератора
	elif _flash > 0.0:
		cell = frames.poke             # только что ткнули
	else:
		var code: Array = frames.code  # работает: «бегущий код»
		cell = code[int(_time / FRAME_TIME) % code.size()]
	_atlas.region = Rect2(Vector2(cell) * 16.0, Vector2(16, 16))


# Встряска от тычка: спрайт подпрыгивает и пружинит
func _poke_shake() -> void:
	if _sprite == null:
		return
	if _shake:
		_shake.kill()
		_sprite.position = _sprite_home
	_sprite_home = _sprite.position
	_shake = create_tween()
	_shake.tween_property(_sprite, "position", _sprite_home + Vector2(1.5, -1), 0.04)
	_shake.tween_property(_sprite, "position", _sprite_home, 0.16).set_trans(Tween.TRANS_ELASTIC)
