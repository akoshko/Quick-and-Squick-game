class_name QuestPanel
extends CanvasLayer

const DONE_ICON = preload("res://src/quests/quest_done_journal.svg")
const GOLD := Color(1, 0.85, 0.45)
const HIDDEN_MEDAL = preload("res://src/quests/achievements/medal_hidden.svg")
const EARNED_MEDAL = preload("res://src/quests/achievements/medal_earned.svg")
const UNEARNED_MEDAL = preload("res://src/quests/achievements/medal_unearned.svg")
const ACHIEVEMENTS := {
	&"boss_victory": ["Легендарная битва", "Принять участие в победе над боссом."],
	&"first_steps": ["Первые шаги", "Пройти квест «Освоиться в офисе»."],
	&"steve_jobs": ["Стив Джобс", "Съесть все яблоки, пока модератор их не пополнил.", true],
	&"clean_cookies": ["Чистим cookie", "Съесть всё печенье, пока модератор его не пополнил.", true],
	&"hide_and_seek": ["А я тебя вижу!", "Пройти квест «Прятки».", true],
}

@export var font_ratio := 0.032

var _root: Control
var _was_paused := false
var _panel: PanelContainer
var _list: Tree
var _tabs: TabContainer
var _achievement_cards: VBoxContainer
var _achievement_popup: PanelContainer
var _cards_by_id: Dictionary[StringName, PanelContainer] = {}
var _notification_queue: Array[PanelContainer] = []
var _boss_bar: BossBar
var _arrow_size := 0
var _heading: Label
var _close_button: Button


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	GameManager.achievement_unlocked.connect(_on_achievement_unlocked)
	_boss_bar = get_tree().get_first_node_in_group("boss_bar") as BossBar
	if _boss_bar:
		_boss_bar.health_layout_changed.connect(_layout_achievement_popup)
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
	_heading.text = "Журнал"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.add_theme_color_override("font_color", GOLD)
	header.add_child(_heading)
	_close_button = Button.new()
	_close_button.text = "Закрыть"
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)

	_list = Tree.new()
	_list.name = "Задания"
	_list.hide_root = true
	_list.item_selected.connect(_select_quest)
	_tabs.add_child(_list)
	_build_achievements()

	_root.hide()


func _build_achievements() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Достижения"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	_achievement_cards = VBoxContainer.new()
	_achievement_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_achievement_cards)

	for id: StringName in ACHIEVEMENTS:
		var card := _make_achievement_card()
		_cards_by_id[id] = card
		_achievement_cards.add_child(card)
		_refresh_achievement(id)


func _make_achievement_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.20)
	style.border_color = Color(0.25, 0.26, 0.33)
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.name = "Row"
	card.add_child(row)
	var medal := TextureRect.new()
	medal.name = "Medal"
	medal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(medal)

	var labels := VBoxContainer.new()
	labels.name = "Labels"
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(labels)
	var title := Label.new()
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(title)
	var description := Label.new()
	description.name = "Description"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.73, 0.75, 0.82))
	labels.add_child(description)
	return card


func _refresh_achievement(id: StringName) -> void:
	var achievement: Array = ACHIEVEMENTS[id]
	var earned := GameManager.has_achievement(id)
	var hidden: bool = achievement.size() > 2 and achievement[2] and not earned
	var icon := EARNED_MEDAL if earned else (HIDDEN_MEDAL if hidden else UNEARNED_MEDAL)
	var title: String = "Скрытое достижение" if hidden else achievement[0]
	var description: String = "Описание откроется после получения." if hidden else achievement[1]
	var color := GOLD if earned else (Color(0.74, 0.70, 0.81) if hidden else Color.WHITE)
	_set_card_content(_cards_by_id[id], icon, title, description, color)


func _set_card_content(card: PanelContainer, icon: Texture2D, title: String,
		description: String, title_color: Color, description_color := Color(0.73, 0.75, 0.82)) -> void:
	var row := card.get_node("Row")
	row.get_node("Medal").texture = icon
	var labels := row.get_node("Labels")
	labels.get_node("Title").text = title
	labels.get_node("Title").add_theme_color_override("font_color", title_color)
	labels.get_node("Description").text = description
	labels.get_node("Description").add_theme_color_override("font_color", description_color)


func _on_achievement_unlocked(id: StringName) -> void:
	if not _cards_by_id.has(id):
		return
	_refresh_achievement(id)
	show_achievement_notification(ACHIEVEMENTS[id][0], EARNED_MEDAL)


func show_achievement_notification(achievement_title: String, icon: Texture2D) -> void:
	var card := _make_achievement_card()
	_set_card_content(card, icon, "Новое достижение", achievement_title, GOLD, Color.WHITE)
	card.hide()
	add_child(card)
	_notification_queue.append(card)
	_show_next_achievement_popup()


func _show_next_achievement_popup() -> void:
	if _root.visible or is_instance_valid(_achievement_popup) or _notification_queue.is_empty():
		return
	_achievement_popup = _notification_queue.pop_front()
	for control in _achievement_popup.find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_achievement_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_achievement_popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_achievement_popup.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_layout_achievement_popup()
	_achievement_popup.show()
	var tween := _achievement_popup.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(5.0)
	tween.tween_property(_achievement_popup, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_finish_achievement_popup)


func _finish_achievement_popup() -> void:
	_achievement_popup.queue_free()
	_achievement_popup = null
	_show_next_achievement_popup()


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
	_tabs.add_theme_font_size_override("font_size", font)

	_achievement_cards.add_theme_constant_override("separation", roundi(font * 0.35))
	for card in _achievement_cards.get_children():
		_layout_achievement_card(card, font)
	_layout_achievement_popup()


func _layout_achievement_popup() -> void:
	if not is_instance_valid(_achievement_popup):
		return
	var size := get_viewport().get_visible_rect().size
	var font := maxi(8, int(minf(size.y, size.x * 1.45) * font_ratio))
	_layout_achievement_card(_achievement_popup, font)
	var margin := float(font)
	var width := minf(font * 16.0, size.x * 0.35)
	var top := margin
	if is_instance_valid(_boss_bar):
		top += _boss_bar.health_bottom()
	_achievement_popup.offset_left = -margin - width
	_achievement_popup.offset_right = -margin
	_achievement_popup.offset_top = top
	_achievement_popup.offset_bottom = top


func _layout_achievement_card(card: PanelContainer, font: int) -> void:
	card.custom_minimum_size.y = roundi(font * 4.8)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(roundi(font * 0.55))
	style.set_corner_radius_all(roundi(font * 0.35))
	var row := card.get_node("Row") as HBoxContainer
	row.add_theme_constant_override("separation", roundi(font * 0.55))
	var medal := row.get_node("Medal") as TextureRect
	medal.custom_minimum_size.x = maxi(16, roundi(font * 2.5 / 16.0) * 16)
	var labels := row.get_node("Labels") as VBoxContainer
	labels.add_theme_constant_override("separation", roundi(font * 0.15))
	labels.get_node("Title").add_theme_font_size_override("font_size", font)
	labels.get_node("Description").add_theme_font_size_override("font_size", roundi(font * 0.85))


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
			item.set_selectable(0, not quest.done)
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
	if is_instance_valid(_achievement_popup):
		_achievement_popup.hide()
	_close_button.grab_focus()


func close() -> void:
	if not _root.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and _root.is_ancestor_of(focused):
		focused.release_focus()
	_root.hide()
	get_tree().paused = _was_paused
	if is_instance_valid(_achievement_popup):
		_achievement_popup.show()
	else:
		_show_next_achievement_popup()


func _exit_tree() -> void:
	if _root and _root.visible:
		get_tree().paused = _was_paused


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (_root.visible and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		if _root.visible:
			close()
		elif not get_tree().paused and GameManager.state == GameManager.GameState.PLAYING:
			open()
