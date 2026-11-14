class_name QuestPanel
extends CanvasLayer

const DONE_ICON = preload("res://src/quests/quest_done_journal.svg")
const GOLD := Color(1, 0.85, 0.45)

@export var font_ratio := 0.032

var _root: Control
var _was_paused := false
var _panel: PanelContainer
var _list: Tree
var _arrow_size := 0
var _heading: Label
var _close_button: Button


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Quests.changed.connect(_refresh)
	Quests.selected_quest_changed.connect(_refresh)
	get_viewport().size_changed.connect(_layout)
	_refresh()


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.025, 0.04, 0.65)
	_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.15, 1)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)

	var box := VBoxContainer.new()
	_panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_heading = Label.new()
	_heading.text = "Квесты"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.add_theme_color_override("font_color", GOLD)
	header.add_child(_heading)
	_close_button = Button.new()
	_close_button.text = "Закрыть"
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	_list = Tree.new()
	_list.hide_root = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select_quest)
	box.add_child(_list)

	_root.hide()


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var font := maxi(8, int(minf(size.y, size.x * 1.45) * font_ratio))
	var icon_scale := clampf(size.y / maxf(size.x, 1.0), 1.0, 1.5)
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(font * 0.6)
	style.set_corner_radius_all(roundi(font * 0.5))

	var box := _panel.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", roundi(font * 0.5))
	var row_height := font * 2.4
	_list.add_theme_font_size_override("font_size", font)
	_resize_expanders(roundi(font * 0.85 * icon_scale))
	var check_scale := clampf(size.y / maxf(size.x, 1.0), 1.0, 1.8)
	_list.add_theme_constant_override("icon_max_width", roundi(font * 1.4 * check_scale))
	_list.add_theme_constant_override("item_margin", roundi(font))
	_list.add_theme_constant_override("v_separation", roundi(font * 0.4))
	_panel.custom_minimum_size = Vector2(size.x * 0.88, size.y * 0.84)
	_close_button.custom_minimum_size.y = row_height
	_heading.add_theme_font_size_override("font_size", int(font * 1.1))
	_close_button.add_theme_font_size_override("font_size", font)


func _resize_expanders(size: int) -> void:
	if size == _arrow_size:
		return
	_arrow_size = size
	for icon_name in ["arrow", "arrow_collapsed", "arrow_collapsed_mirrored"]:
		var icon := ThemeDB.get_default_theme().get_icon(icon_name, "Tree")
		var image := icon.get_image()
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		_list.add_theme_icon_override(icon_name, ImageTexture.create_from_image(image))


func _refresh(_value: Variant = null) -> void:
	_list.clear()
	var root := _list.create_item()
	for show_completed in [false, true]:
		for quest in Quests.quests:
			if quest.done != show_completed:
				continue
			var item := _list.create_item(root)
			item.set_text(0, quest.title)
			if quest.done:
				item.set_icon(0, DONE_ICON)
			if quest.id == Quests.selected_quest_id:
				item.set_text(0, item.get_text(0) + "  ·  Текущий квест")
				item.set_custom_color(0, GOLD)
			item.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
			item.set_metadata(0, quest.id)
			item.set_selectable(0, not Quests.all_done())
			for step in quest.steps:
				var row := _list.create_item(item)
				row.set_text(0, step.title)
				row.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
				row.set_selectable(0, false)
				if step.done:
					row.set_icon(0, DONE_ICON)
					row.set_custom_color(0, Color(0.55, 1, 0.62))
				else:
					break
	if root.get_child_count() == 0:
		var empty := _list.create_item(root)
		empty.set_text(0, "Нет квестов")
		empty.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		empty.set_selectable(0, false)
	_layout()


func _select_quest() -> void:
	var item := _list.get_selected()
	if item == null:
		return
	var id: String = item.get_metadata(0)
	close()
	# Выбор обновляет дерево. Дождёмся завершения обработки клика.
	Quests.select_quest.call_deferred(id)
	_list.deselect_all()


func open() -> void:
	if _root.visible:
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	_root.show()
	_close_button.grab_focus()


func close() -> void:
	if not _root.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and _root.is_ancestor_of(focused):
		focused.release_focus()
	_root.hide()
	get_tree().paused = _was_paused


func _exit_tree() -> void:
	if _root and _root.visible:
		get_tree().paused = _was_paused


func _unhandled_key_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
