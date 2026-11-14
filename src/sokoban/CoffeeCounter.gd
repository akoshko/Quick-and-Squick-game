class_name CoffeeCounter
extends CanvasLayer

## Общий счётчик кофе во время восстания зомби-модераторов: один на всех
## игроков («☕ 7 / 25»). Внизу по центру — вверху квест, полоска босса и
## уведомления о достижениях; на телефоне встаёт над кнопками управления.

const BG := Color(0.1, 0.09, 0.13, 0.85)
const TEXT := Color(1, 0.9, 0.7)
const DONE := Color(0.6, 1, 0.6)

var _panel: PanelContainer
var _icon: TextureRect
var _label: Label
var _pulse: Tween


func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(row)
	_icon = TextureRect.new()
	_icon.texture = preload("res://src/sokoban/coffee.png")
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)
	_label = Label.new()
	_label.add_theme_color_override("font_color", TEXT)
	row.add_child(_label)
	_layout_sizes()
	get_viewport().size_changed.connect(_layout_sizes)


func set_count(count: int, needed: int) -> void:
	var changed := _label.text != "" and _label.text != "%d / %d" % [count, needed]
	_label.text = "%d / %d" % [count, needed]
	_label.add_theme_color_override("font_color", DONE if count >= needed else TEXT)
	_panel.reset_size()
	if changed:
		# «Подпрыгивает», когда кто-то подобрал стаканчик
		if _pulse:
			_pulse.kill()
		_panel.pivot_offset = _panel.size / 2.0
		_panel.scale = Vector2.ONE * 1.2
		_pulse = create_tween()
		_pulse.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Плавно скрыть и удалить
func fade_out(delay := 2.5) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(_panel, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)


func _layout_sizes() -> void:
	var screen := get_viewport().get_visible_rect().size
	var font := maxi(10, int(minf(screen.y, screen.x * 1.45) * 0.04))
	_label.add_theme_font_size_override("font_size", font)
	_icon.custom_minimum_size = Vector2.ONE * font * 1.3
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(font * 0.4)
	style.content_margin_left = font * 0.6
	style.content_margin_right = font * 0.8
	style.set_corner_radius_all(roundi(font * 0.4))
	_panel.reset_size()


# Положение пересчитываем каждый кадр: размер экрана и кнопок может смениться
func _process(_delta: float) -> void:
	var screen := get_viewport().get_visible_rect().size
	var margin := minf(screen.y, screen.x * 1.45) * 0.03
	var bottom := screen.y
	var controls := get_tree().get_first_node_in_group("mobile_controls") as MobileControls
	if controls:
		bottom = controls.top_edge()
	_panel.position = Vector2((screen.x - _panel.size.x) / 2.0, bottom - margin - _panel.size.y)
