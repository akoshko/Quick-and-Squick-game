class_name Laptop
extends ResourceStation

## Рабочий ноутбук хакатона на столе. По «действию» игрок в него тыкает:
## экран мигает, всплывает реплика. После pokes_needed тычков ноутбук
## «зависает» (синий экран) и выполняется задание. Через 5 секунд
## приходит модератор и чинит его.

@export var quest_id := "poke_laptop"   ## какое задание выполнить (пусто — никакое)
@export var pokes_needed := 3
@export var poke_lines: PackedStringArray = ["тык", "тык-тык", "Ой, всё. Завис."]

const SCREEN_ON := Color(0.35, 0.75, 0.95)
const SCREEN_CRASHED := Color(0.1, 0.25, 0.85)

var _pokes := 0
var _screen := SCREEN_ON
var _shake := 0.0


func _ready() -> void:
	super()
	if refill_text == "":
		refill_text = "Починил!"


func interact(_player: Player) -> void:
	_poke_shake()
	if is_empty:
		FloatingText.spawn(self, global_position + Vector2(0, -14), "Синий экран…", Color(0.7, 0.8, 1))
		return

	_pokes += 1
	var line := poke_lines[mini(_pokes, poke_lines.size()) - 1] if poke_lines.size() > 0 else "тык"
	FloatingText.spawn(self, global_position + Vector2(0, -14), line)

	if _pokes >= pokes_needed:
		_screen = SCREEN_CRASHED
		if quest_id != "":
			Quests.complete(quest_id)
		_set_empty()   # «закончился» — через 5 с модератор починит
	else:
		# Экран мигает случайным цветом и возвращается
		_screen = Color.from_hsv(randf(), 0.5, 1.0)
		create_tween().tween_property(self, "_screen", SCREEN_ON, 0.3)


func _on_refilled() -> void:
	_pokes = 0
	_screen = SCREEN_ON
	_poke_shake()


func _poke_shake() -> void:
	var t := create_tween()
	t.tween_property(self, "_shake", 1.0, 0.04)
	t.tween_property(self, "_shake", 0.0, 0.16).set_trans(Tween.TRANS_ELASTIC)


func _process(_delta: float) -> void:
	queue_redraw()   # меняются цвет экрана и встряска


# Рисуем кодом, пока нет спрайта. Ноутбук стоит на столе (тайл стола).
func _draw() -> void:
	draw_set_transform(Vector2(_shake * 1.5, -_shake), 0.0, Vector2.ONE)
	draw_rect(Rect2(-10, 3, 20, 3), Color(0, 0, 0, 0.18))                   # тень на столе
	draw_rect(Rect2(-9, -10, 18, 13), Color(0.22, 0.23, 0.27))               # крышка
	draw_rect(Rect2(-7.5, -8.5, 15, 10), _screen)                            # экран
	if is_empty:
		draw_rect(Rect2(-5, -6, 6, 1), Color(1, 1, 1, 0.9))                  # «текст» синего экрана
		draw_rect(Rect2(-5, -3, 10, 1), Color(1, 1, 1, 0.7))
		draw_rect(Rect2(-5, -1, 8, 1), Color(1, 1, 1, 0.7))
	else:
		draw_rect(Rect2(-6, -7, 4, 1.5), Color(1, 1, 1, 0.6))                # блик
	draw_rect(Rect2(-10, 3, 20, 3), Color(0.68, 0.7, 0.75))                  # клавиатурная часть
	draw_rect(Rect2(-3, 3.5, 6, 1), Color(0.5, 0.52, 0.56))                  # тачпад
