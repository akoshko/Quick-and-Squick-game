class_name Confetti
extends CanvasLayer

## Конфетти на весь экран (поверх всего): бумажки вылетают сверху,
## кружатся, падают и через несколько секунд исчезают.
## Использование: Confetti.burst(self)

const COLORS: Array[Color] = [
	Color(1, 0.35, 0.35), Color(1, 0.8, 0.25), Color(0.4, 0.85, 0.45),
	Color(0.35, 0.65, 1), Color(0.8, 0.45, 1), Color(1, 0.55, 0.8),
]
const LIFETIME := 4.5
const GRAVITY := 0.45     # доля высоты экрана в секунду²

var count := 160
var _pieces: Array[Dictionary] = []
var _canvas: Control
var _time := 0.0


## Запустить конфетти в текущей сцене
static func burst(from: Node, pieces := 160) -> void:
	# Сеть: конфетти над общим миром рисуют клиенты — сервер рассылает его (Net.route_fx)
	if Net.route_fx(WorldSync.Fx.CONFETTI, [pieces]):
		return
	var confetti := Confetti.new()
	confetti.count = pieces
	from.get_tree().current_scene.add_child(confetti)


func _ready() -> void:
	layer = 20
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_pieces)
	add_child(_canvas)
	var screen := get_viewport().get_visible_rect().size
	var unit := minf(screen.x, screen.y)
	for i in count:
		_pieces.append({
			"pos": Vector2(randf() * screen.x, -randf() * screen.y * 0.4 - 10.0),
			"vel": Vector2(randf_range(-0.15, 0.15), randf_range(0.05, 0.35)) * unit,
			"size": Vector2(randf_range(0.012, 0.022), randf_range(0.006, 0.012)) * unit,
			"angle": randf() * TAU,
			"spin": randf_range(-8.0, 8.0),
			"sway": randf() * TAU,
			"color": COLORS.pick_random(),
		})


func _process(delta: float) -> void:
	_time += delta
	var screen := get_viewport().get_visible_rect().size
	for piece in _pieces:
		var vel: Vector2 = piece.vel
		vel.y = minf(vel.y + GRAVITY * screen.y * delta, screen.y * 0.35)   # падают не быстрее «воздуха»
		vel.x *= 0.99
		piece.vel = vel
		piece.sway += delta * 4.0
		piece.pos += (vel + Vector2(sin(piece.sway) * screen.x * 0.03, 0)) * delta
		piece.angle += piece.spin * delta
	_canvas.modulate.a = clampf((LIFETIME - _time) / 0.8, 0.0, 1.0)
	_canvas.queue_redraw()
	if _time >= LIFETIME:
		queue_free()


func _draw_pieces() -> void:
	for piece in _pieces:
		var size: Vector2 = piece.size
		# Бумажка «переворачивается»: ширина меняется по синусу
		size.x *= absf(cos(piece.angle))
		_canvas.draw_set_transform(piece.pos, piece.angle * 0.3, Vector2.ONE)
		_canvas.draw_rect(Rect2(-size / 2.0, size), piece.color)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
