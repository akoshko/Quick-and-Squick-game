class_name MobileControls
extends CanvasLayer

## Экранное управление для телефонов: крестовина слева, кнопка действия справа.
## Кнопки «нажимают» те же экшены, что и клавиатура (move_*, action),
## поэтому Player.gd ничего не нужно знать про телефон.

@export var show_on_desktop := false    # включи, чтобы проверить на компьютере
@export var margin_ratio := 0.05        # отступ от краёв (доля высоты экрана)
@export var dpad_button_ratio := 0.14   # размер кнопки крестовины (доля высоты)
@export var action_button_ratio := 0.2  # размер кнопки действия (доля высоты)

const TEX_SIZE := 128
const BG_COLOR := Color(1, 1, 1, 0.18)
const BG_PRESSED_COLOR := Color(1, 1, 1, 0.4)
const FG_COLOR := Color(1, 1, 1, 0.85)

const DIRECTIONS := {
	"move_up": Vector2(0, -1),
	"move_down": Vector2(0, 1),
	"move_left": Vector2(-1, 0),
	"move_right": Vector2(1, 0),
}

var _dpad := {}   # имя экшена -> TouchScreenButton
var _action_button: TouchScreenButton


func _ready() -> void:
	layer = 10   # поверх HUD
	visible = show_on_desktop or _is_phone()
	if not visible:
		return

	for action in DIRECTIONS:
		var dir: Vector2 = DIRECTIONS[action]
		var button := _make_button(action,
				_make_arrow_texture(dir, BG_COLOR),
				_make_arrow_texture(dir, BG_PRESSED_COLOR))
		# можно вести пальцем по крестовине, не отрывая его
		button.passby_press = true
		# Зона касания стрелки растянута на углы крестовины: в углу зоны
		# двух стрелок пересекаются, и палец жмёт обе — это диагональ
		var shape := RectangleShape2D.new()
		shape.size = Vector2(TEX_SIZE * 3, TEX_SIZE) if dir.y != 0 else Vector2(TEX_SIZE, TEX_SIZE * 3)
		button.shape = shape
		button.shape_centered = true
		_dpad[action] = button

	_action_button = _make_button("action",
			_make_circle_texture(BG_COLOR),
			_make_circle_texture(BG_PRESSED_COLOR))

	get_viewport().size_changed.connect(_layout)
	_layout()


func _is_phone() -> bool:
	# Android/iOS приложение или браузер на телефоне
	return OS.has_feature("mobile") \
			or OS.has_feature("web_android") \
			or OS.has_feature("web_ios")


func _make_button(action: String, normal: Texture2D, pressed: Texture2D) -> TouchScreenButton:
	var button := TouchScreenButton.new()
	button.action = action
	button.texture_normal = normal
	button.texture_pressed = pressed
	add_child(button)
	return button


# Расставляет кнопки по углам экрана; вызывается и при повороте/смене размера
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var control_scale_basis := minf(screen.y, screen.x * 1.2)
	var margin := control_scale_basis * margin_ratio

	var dpad_scale := control_scale_basis * dpad_button_ratio / TEX_SIZE
	var btn := TEX_SIZE * dpad_scale
	var center := Vector2(margin + btn * 1.5, screen.y - margin - btn * 1.5)
	for action in _dpad:
		var button: TouchScreenButton = _dpad[action]
		button.scale = Vector2.ONE * dpad_scale
		# position у кнопки — её левый верхний угол
		button.position = center + DIRECTIONS[action] * btn - Vector2.ONE * btn / 2.0

	var action_scale := control_scale_basis * action_button_ratio / TEX_SIZE
	var size := TEX_SIZE * action_scale
	_action_button.scale = Vector2.ONE * action_scale
	_action_button.position = Vector2(screen.x - margin - size, screen.y - margin - size)


# Полупрозрачный круг со стрелкой, повёрнутой в сторону dir
func _make_arrow_texture(dir: Vector2, bg: Color) -> ImageTexture:
	var img := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2.ONE * TEX_SIZE / 2.0
	var r := TEX_SIZE / 2.0 - 2.0
	var angle := Vector2.UP.angle_to(dir)
	var tip := c + Vector2(0, -r * 0.5).rotated(angle)
	var left := c + Vector2(-r * 0.4, r * 0.25).rotated(angle)
	var right := c + Vector2(r * 0.4, r * 0.25).rotated(angle)

	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.point_is_inside_triangle(p, tip, left, right):
				img.set_pixel(x, y, FG_COLOR)
			elif p.distance_to(c) <= r:
				img.set_pixel(x, y, bg)
	return ImageTexture.create_from_image(img)


# Полупрозрачный круг с точкой в центре — кнопка действия
func _make_circle_texture(bg: Color) -> ImageTexture:
	var img := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2.ONE * TEX_SIZE / 2.0
	var r := TEX_SIZE / 2.0 - 2.0

	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r * 0.35:
				img.set_pixel(x, y, FG_COLOR)
			elif d <= r:
				img.set_pixel(x, y, bg)
	return ImageTexture.create_from_image(img)
