class_name EmoteBar
extends CanvasLayer

## Кнопки эмоций своего игрока (создаёт Player, если он is_local).
##   • Компьютер: справа колонка из 4 маленьких полупрозрачных кнопок
##     с номерами 1–4; клавиши 1–4 делают то же самое.
##   • Телефон (когда видно сенсорное управление): кнопка-смайлик в правом
##     верхнем углу, по нажатию под ней раскрывается меню из 4 эмоций.
## Нажатая эмоция «загорается», пока её облачко над головой; пока оно не
## исчезло, остальные кнопки приглушены — новую эмоцию не показать.

const KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4]
const KEYPAD: Array[Key] = [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4]
const BG := Color(0.1, 0.1, 0.14, 0.35)
const BG_HOVER := Color(0.1, 0.1, 0.14, 0.55)
const BG_LIT := Color(1.0, 0.82, 0.4, 0.75)
const NUMBER := Color(1, 1, 1, 0.75)
const DIMMED := 0.4   # прозрачность кнопок, пока облачко ещё висит

var player: Player
var _phone := false
var _root: Control
var _buttons: Array[Button] = []
var _toggle: Button          # кнопка-смайлик на телефоне
var _menu: VBoxContainer     # раскрывающееся меню на телефоне (на компьютере — колонка)


func _ready() -> void:
	layer = 9   # над HUD, под сенсорными кнопками и журналом
	add_to_group("emote_bar")
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_setup.call_deferred()   # сенсорное управление решает, видно ли оно, в своём _ready


func _setup() -> void:
	var controls := get_tree().get_first_node_in_group("mobile_controls") as CanvasLayer
	_phone = controls != null and controls.visible
	_menu = VBoxContainer.new()
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu)
	for i in EmoteBubble.NAMES.size():
		var button := _make_button(EmoteBubble.icon(i), "" if _phone else str(i + 1))
		button.tooltip_text = EmoteBubble.NAMES[i]
		button.pressed.connect(_on_emote_pressed.bind(i))
		_menu.add_child(button)
		_buttons.append(button)
	if _phone:
		_toggle = _make_button(EmoteBubble.icon(EmoteBubble.Kind.SMILE), "")
		_toggle.pressed.connect(func() -> void: _menu.visible = not _menu.visible)
		_root.add_child(_toggle)
		_menu.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make_button(icon: Texture2D, number: String) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE   # клавиши и пробел не «нажимают» кнопку
	button.icon = icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = BG_HOVER if state == "hover" else BG
		button.add_theme_stylebox_override(state, style)
	if number != "":
		var label := Label.new()
		label.name = "Number"
		label.text = number
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", NUMBER)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		button.add_child(label)
	return button


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var basis := minf(screen.y, screen.x * 1.45)
	var margin := basis * 0.03
	# На телефоне кнопки крупнее — под палец; на компьютере совсем небольшие
	var size := basis * (0.1 if _phone else 0.055)
	var gap := size * 0.15
	_menu.add_theme_constant_override("separation", int(gap))
	for button in _buttons + ([_toggle] if _toggle else []):
		button.custom_minimum_size = Vector2.ONE * size
		button.size = Vector2.ONE * size
		button.add_theme_constant_override("icon_max_width", int(size * (0.7 if _phone else 0.58)))
		var corner := int(size * 0.22)
		for state in ["normal", "hover", "pressed", "disabled"]:
			(button.get_theme_stylebox(state) as StyleBoxFlat).set_corner_radius_all(corner)
		var label := button.get_node_or_null("Number") as Label
		if label:
			label.add_theme_font_size_override("font_size", maxi(9, int(size * 0.36)))
			label.add_theme_constant_override("outline_size", 4)
			label.position = Vector2(size * 0.08, -size * 0.06)
	var column_height := size * _buttons.size() + gap * (_buttons.size() - 1)
	if _phone:
		_toggle.position = Vector2(screen.x - margin - size, margin)
		_menu.position = Vector2(screen.x - margin - size, margin + size + gap)
	else:
		# Справа, чуть ниже середины — уведомления о достижениях выезжают сверху
		_menu.position = Vector2(screen.x - margin - size, screen.y * 0.58 - column_height / 2.0)
	_menu.reset_size()


## Нижний край кнопки эмоций в правом верхнем углу (на телефоне), иначе 0:
## уведомления о достижениях встают ниже неё
func top_right_bottom() -> float:
	if _toggle == null or not _toggle.visible:
		return 0.0
	return _toggle.position.y + _toggle.size.y


func _on_emote_pressed(emote: int) -> void:
	if _phone:
		_menu.visible = false
	if is_instance_valid(player):
		player.try_emote(emote)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not is_instance_valid(player):
		return
	var index := KEYS.find(key.physical_keycode)
	if index == -1:
		index = KEYPAD.find(key.keycode)
	if index != -1:
		player.try_emote(index)
		get_viewport().set_input_as_handled()


# Подсветка: нажатая эмоция горит, пока висит облачко, остальные приглушены
func _process(_delta: float) -> void:
	if not is_instance_valid(player) or _buttons.is_empty():
		return
	var lit := player.current_emote()
	for i in _buttons.size():
		var button := _buttons[i]
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		style.bg_color = BG_LIT if i == lit else BG
		button.modulate.a = 1.0 if lit == -1 or i == lit else DIMMED
