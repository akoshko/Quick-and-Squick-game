class_name SnackStation
extends ResourceStation

## Тарелка с печеньем или миска с яблоками. По «действию» игрок съедает
## одну порцию и выполняет задание «Перекусить». Когда порции кончились —
## через 5 секунд модератор приносит ещё.

enum Kind { COOKIE, APPLE }

@export var kind := Kind.COOKIE:
	set(value):
		kind = value
		queue_redraw()
@export var portions := 3
@export var quest_id := "snack"   ## какое задание выполнить (пусто — никакое)

const COOKIE_SPOTS := [Vector2(-4, 1), Vector2(4, 1), Vector2(0, -3)]
const APPLE_SPOTS := [Vector2(-3.5, 0), Vector2(3.5, 0), Vector2(0, -3.5)]

var _left := 0
var _pop := Vector2.ONE


func _ready() -> void:
	super()
	_left = portions
	if refill_text == "":
		refill_text = "Доложил печенье!" if kind == Kind.COOKIE else "Принёс яблок!"


func interact(_player: Player) -> void:
	if is_empty:
		FloatingText.spawn(self, global_position + Vector2(0, -12), "Пусто…", Color(0.8, 0.82, 0.88))
		return
	_left -= 1
	FloatingText.spawn(self, global_position + Vector2(0, -12),
			"Ням!" if kind == Kind.COOKIE else "Хрум!", Color(1, 0.85, 0.5))
	if quest_id != "":
		Quests.complete(quest_id)
	_bounce()
	if _left <= 0:
		_set_empty()


func _on_refilled() -> void:
	_left = portions
	_bounce()


# Тарелка «подпрыгивает» при укусе и при пополнении
func _bounce() -> void:
	var t := create_tween()
	t.tween_method(_set_pop, Vector2(1.25, 0.8), Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pop(value: Vector2) -> void:
	_pop = value
	queue_redraw()


# Рисуем кодом, пока нет спрайта
func _draw() -> void:
	draw_set_transform(Vector2(0, 6) * (Vector2.ONE - _pop), 0.0, _pop)
	if kind == Kind.COOKIE:
		_ellipse(Vector2(0, 3), Vector2(11, 5), Color(0.94, 0.95, 0.97))     # тарелка
		_ellipse(Vector2(0, 3), Vector2(8, 3.5), Color(0.84, 0.87, 0.9))
		for i in mini(_left, COOKIE_SPOTS.size()):
			_draw_cookie(COOKIE_SPOTS[i])
	else:
		_ellipse(Vector2(0, 4), Vector2(11, 5), Color(0.55, 0.36, 0.22))     # миска
		_ellipse(Vector2(0, 2.5), Vector2(9.5, 3.5), Color(0.4, 0.25, 0.15))
		for i in mini(_left, APPLE_SPOTS.size()):
			_draw_apple(APPLE_SPOTS[i])


func _draw_cookie(at: Vector2) -> void:
	draw_circle(at, 4.5, Color(0.55, 0.33, 0.16))
	draw_circle(at + Vector2(0, -0.4), 3.8, Color(0.82, 0.58, 0.3))
	for chip: Vector2 in [Vector2(-1.5, -1.5), Vector2(1.2, -0.5), Vector2(-0.5, 1)]:
		draw_rect(Rect2(at + chip, Vector2(1.2, 1.2)), Color(0.3, 0.17, 0.08))


func _draw_apple(at: Vector2) -> void:
	draw_circle(at, 4.0, Color(0.72, 0.1, 0.12))
	draw_circle(at + Vector2(-0.3, -0.3), 3.4, Color(0.88, 0.2, 0.18))
	draw_circle(at + Vector2(-1.4, -1.6), 1.0, Color(1, 0.6, 0.55))          # блик
	draw_line(at + Vector2(0, -3.5), at + Vector2(0.6, -5.5), Color(0.35, 0.22, 0.1), 1.0)
	_ellipse(at + Vector2(2, -5), Vector2(1.6, 0.9), Color(0.35, 0.7, 0.3))   # листик


func _ellipse(center: Vector2, radius: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(points, fill)
