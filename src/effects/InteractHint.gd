class_name InteractHint
extends Node2D

## Подсказка-клавиша над предметом, с которым сейчас можно взаимодействовать.
## Игрок каждый кадр сообщает цель через set_target() (null — спрятать).
## Значок подстраивается под устройство, с которого играют:
## E — клавиатура, A — геймпад, кружок — телефон (как кнопка действия).

enum Device { KEYBOARD, GAMEPAD, TOUCH }

const OFFSET := Vector2(0, -30)    # над предметом
const FONT_SIZE := 8
const CAP := Vector2(12, 12)       # размер «клавиши»
const FADE_SPEED := 8.0

var _target: Node2D
var _device := Device.KEYBOARD
var _time := 0.0
var _alpha := 0.0


func _ready() -> void:
	top_level = true          # не двигается и не сжимается вместе с игроком
	z_index = 100             # поверх всего уровня
	z_as_relative = false
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_device = Device.TOUCH


func set_target(target: Node2D) -> void:
	_target = target


# Запоминаем, с какого устройства играют, — от этого зависит значок
func _input(event: InputEvent) -> void:
	var device := _device
	if event is InputEventKey:
		device = Device.KEYBOARD
	elif event is InputEventJoypadButton:
		device = Device.GAMEPAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		device = Device.GAMEPAD
	elif event is InputEventScreenTouch:
		device = Device.TOUCH
	if device != _device:
		_device = device
		queue_redraw()


func _process(delta: float) -> void:
	var has_target := is_instance_valid(_target)
	if has_target:
		# Большие предметы могут поднять подсказку повыше (поле hint_offset)
		var extra: Variant = _target.get("hint_offset")
		var offset := OFFSET + (extra as Vector2 if extra is Vector2 else Vector2.ZERO)
		global_position = (_target.global_position + offset).round()
	# Плавно появляется и исчезает
	_alpha = move_toward(_alpha, 1.0 if has_target else 0.0, delta * FADE_SPEED)
	modulate.a = _alpha
	visible = _alpha > 0.01
	_time += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	var bob := roundf(sin(_time * 4.0))   # лёгкое покачивание вверх-вниз
	var cap := Rect2(-CAP / 2.0 + Vector2(0, bob), CAP)

	draw_rect(Rect2(cap.position + Vector2(0, 2), cap.size), Color(0.1, 0.1, 0.14))   # тень-«толщина» клавиши
	draw_rect(cap, Color(0.96, 0.96, 0.92))                                           # верх клавиши
	draw_rect(cap, Color(0.1, 0.1, 0.14), false, 1.0)                                 # обводка

	var center := cap.get_center()
	if _device == Device.TOUCH:
		draw_circle(center, 3.5, Color(0.2, 0.2, 0.26))   # как кнопка действия на экране
		return
	var letter := "A" if _device == Device.GAMEPAD else "E"
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var baseline := center + Vector2(-text_size.x / 2.0,
			(font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0)
	draw_string(font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.12, 0.12, 0.16))
