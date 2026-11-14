class_name QuestPanel
extends CanvasLayer

## Список заданий в левом верхнем углу: галочка + текст.
## Строки берутся из Quests и обновляются сами по его сигналам.

@export var font_ratio := 0.032    # размер шрифта (доля высоты экрана)
@export var margin_ratio := 0.03   # отступ от края (доля высоты экрана)

const TEXT_COLOR := Color(1, 1, 1)
const DONE_COLOR := Color(0.65, 0.68, 0.72)
const CHECK_COLOR := Color(0.45, 0.95, 0.5)

var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _rows := {}   # id задания -> { "check": CheckIcon, "label": Label }


## Квадратик-галочка, нарисованный кодом
class CheckIcon extends Control:
	var done := false:
		set(value):
			done = value
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var line := maxf(1.5, size.x * 0.1)
		draw_rect(r, Color(1, 1, 1, 0.12))
		draw_rect(r, Color(1, 1, 1, 0.85), false, line)
		if done:
			draw_polyline(PackedVector2Array([
				Vector2(size.x * 0.18, size.y * 0.52),
				Vector2(size.x * 0.42, size.y * 0.78),
				Vector2(size.x * 0.85, size.y * 0.2),
			]), CHECK_COLOR, line * 1.6)


func _ready() -> void:
	layer = 5   # над уровнем, но под кнопками телефона
	_build()
	Quests.changed.connect(_refresh)
	Quests.quest_completed.connect(_on_quest_completed)
	get_viewport().size_changed.connect(_layout)
	_refresh()
	_layout()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.72)
	style.set_corner_radius_all(8)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_title = Label.new()
	_title.text = "Задания"
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	vbox.add_child(_title)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_list)

	for quest in Quests.quests:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var check := CheckIcon.new()
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = quest.title
		row.add_child(check)
		row.add_child(label)
		_list.add_child(row)
		_rows[quest.id] = {"check": check, "label": label}


# Размеры — от высоты экрана, чтобы на любом экране выглядело одинаково
func _layout() -> void:
	var h := get_viewport().get_visible_rect().size.y
	var font := maxi(8, int(h * font_ratio))
	var margin := h * margin_ratio

	_title.add_theme_font_size_override("font_size", int(font * 1.1))
	for id in _rows:
		var row: Dictionary = _rows[id]
		(row.label as Label).add_theme_font_size_override("font_size", font)
		var check: CheckIcon = row.check
		check.custom_minimum_size = Vector2.ONE * font * 0.85
		check.pivot_offset = check.custom_minimum_size / 2.0
		(check.get_parent() as HBoxContainer).add_theme_constant_override("separation", int(font * 0.5))

	var style: StyleBoxFlat = _panel.get_theme_stylebox("panel")
	style.set_content_margin_all(font * 0.6)
	_list.add_theme_constant_override("separation", int(font * 0.25))
	_panel.position = Vector2(margin, margin)
	_panel.reset_size()


func _refresh() -> void:
	for quest in Quests.quests:
		if not _rows.has(quest.id):
			continue
		var row: Dictionary = _rows[quest.id]
		(row.check as CheckIcon).done = quest.done
		(row.label as Label).add_theme_color_override("font_color", DONE_COLOR if quest.done else TEXT_COLOR)
	_title.text = "Все задания выполнены!" if Quests.all_done() else "Задания"
	_panel.reset_size()


# Галочка «выпрыгивает», строка вспыхивает зелёным
func _on_quest_completed(quest: Quest) -> void:
	if not _rows.has(quest.id):
		return
	var row: Dictionary = _rows[quest.id]
	var check: CheckIcon = row.check
	var label: Label = row.label
	var t := create_tween().set_parallel()
	check.scale = Vector2.ONE * 1.6
	t.tween_property(check, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	label.modulate = Color(0.6, 1.6, 0.7)
	t.tween_property(label, "modulate", Color.WHITE, 0.6)
