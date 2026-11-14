class_name QuestProgress
extends CanvasLayer

@export var font_ratio := 0.032
@export var margin_ratio := 0.03

var _panel: PanelContainer
var _header: Label
var _title: Label
var _status: Label
var _open_button: Button


func _ready() -> void:
	layer = 5
	_build()
	Quests.changed.connect(_refresh)
	Quests.selected_quest_changed.connect(_refresh)
	Quests.quest_completed.connect(_animate_completion)
	get_viewport().size_changed.connect(_layout)
	_refresh()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.78)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	_panel.add_child(box)

	_header = Label.new()
	_header.text = "Текущий квест"
	_header.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	box.add_child(_header)

	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	_open_button = Button.new()
	_open_button.text = "Все квесты"
	_open_button.pressed.connect(_open_quest_list)
	box.add_child(_open_button)


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var font := maxi(8, int(screen.y * font_ratio))
	var margin := screen.y * margin_ratio
	var padding := font * 0.6
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(padding)
	style.set_corner_radius_all(roundi(font * 0.35))

	var box := _panel.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", roundi(font * 0.22))
	_title.custom_minimum_size.x = maxf(0, minf(font * 12.0, screen.x * 0.53) - padding * 2.0)
	_header.add_theme_font_size_override("font_size", roundi(font * 0.9))
	_open_button.custom_minimum_size.y = font * 2.4
	_title.add_theme_font_size_override("font_size", font)
	_status.add_theme_font_size_override("font_size", maxi(8, roundi(font * 0.75)))
	_open_button.add_theme_font_size_override("font_size", font)
	_panel.position = Vector2(margin, margin)
	_panel.reset_size.call_deferred()


func _refresh(_quest_id: String = "") -> void:
	var quest := Quests.find(Quests.selected_quest_id)
	if quest:
		_title.text = quest.title
		var step := quest.active_step()
		_status.text = "✓ Выполнен" if quest.done else (step.title if step else "Выполняется")
		_status.add_theme_color_override("font_color", Color(0.55, 1, 0.62) if quest.done else Color(1, 1, 1))
	else:
		_title.text = "Квесты не добавлены"
		_status.text = ""
	_layout()


func _animate_completion(quest: Quest) -> void:
	if quest.id != Quests.selected_quest_id:
		return
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	var normal_color := style.bg_color
	var tween := create_tween()
	tween.tween_property(style, "bg_color", Color(0.16, 0.38, 0.23, 0.96), 0.18)
	tween.tween_property(style, "bg_color", normal_color, Quests.COMPLETION_DISPLAY_TIME - 0.18)


func _open_quest_list() -> void:
	var quest_panel := get_parent().get_node_or_null("QuestPanel") as QuestPanel
	if quest_panel:
		quest_panel.open()
