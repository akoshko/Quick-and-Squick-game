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
	&"zombie_apocalypse": ["Третий день хакатона", "Пережить зомби-апокалипсис: собрать хотя бы один стаканчик кофе.", true],
}
@export var font_ratio := 0.032

var _root: Control
var _was_paused := false
var _panel: PanelContainer
var _list: Tree
var _tabs: TabContainer
var _profile_layout: BoxContainer
var _accessory_grid: GridContainer
var _nickname_color_grid: GridContainer
var _profile_preview: TextureRect
var _profile_name: Label
var _accessory_slots: Dictionary[StringName, Button] = {}
var _achievement_cards: VBoxContainer
var _achievement_popups: VBoxContainer
var _cards_by_id: Dictionary[StringName, PanelContainer] = {}
var _boss_bar: BossBar
var _arrow_size := 0
var _heading: Label
var _close_button: Button
var _stuck_button: Button


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	GameManager.achievement_unlocked.connect(_on_achievement_unlocked)
	PlayerProfile.changed.connect(_refresh_profile)
	PlayerProfile.accessory_changed.connect(_refresh_profile)
	_boss_bar = get_tree().get_first_node_in_group("boss_bar") as BossBar
	if _boss_bar:
		_boss_bar.health_layout_changed.connect(_layout_achievement_popups)
	Quests.changed.connect(_refresh)
	Quests.selected_quest_changed.connect(_refresh)
	get_viewport().size_changed.connect(_layout, CONNECT_DEFERRED)
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
	_stuck_button = Button.new()
	_stuck_button.text = "Я застрял"
	_stuck_button.pressed.connect(_on_stuck_pressed)
	header.add_child(_stuck_button)
	_close_button = Button.new()
	_close_button.text = "Закрыть"
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for style_name in [&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled"]:
		var tab_style := _tabs.get_theme_stylebox(style_name).duplicate() as StyleBox
		_tabs.add_theme_stylebox_override(style_name, tab_style)

	_list = Tree.new()
	_list.name = "Задания"
	_list.add_theme_stylebox_override("panel", _list.get_theme_stylebox("panel").duplicate())
	_list.hide_root = true
	_list.item_selected.connect(_select_quest)
	_tabs.add_child(_list)
	_build_achievements()
	_build_profile()

	_root.hide()

	_achievement_popups = VBoxContainer.new()
	_achievement_popups.sort_children.connect(_update_notification_timers)
	_achievement_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_achievement_popups)
	_achievement_popups.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_achievement_popups.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _build_profile() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Профиль"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)

	_profile_layout = BoxContainer.new()
	inset.add_child(_profile_layout)

	var inventory := VBoxContainer.new()
	inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_layout.add_child(inventory)

	_accessory_grid = _build_accessory_grid(inventory, "Предметы", CharacterLook.ACCESSORIES.keys())
	_nickname_color_grid = _build_accessory_grid(inventory, "Цвет ника", CharacterLook.NICKNAME_COLORS.keys())

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.12, 0.13, 0.17)
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	_profile_layout.add_child(preview_panel)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_panel.add_child(content)

	_profile_preview = TextureRect.new()
	_profile_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_profile_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profile_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_profile_preview)

	_profile_name = Label.new()
	_profile_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_profile_name)

	_refresh_profile()


func _build_accessory_grid(inventory: VBoxContainer, title: String, ids: Array) -> GridContainer:
	var section := VBoxContainer.new()
	inventory.add_child(section)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", GOLD)
	section.add_child(heading)
	var grid := GridContainer.new()
	section.add_child(grid)
	for id: String in ids:
		var slot := Button.new()
		slot.pressed.connect(PlayerProfile.equip_accessory.bind(id))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.15, 0.20)
		style.set_border_width_all(1)
		for state in [&"normal", &"hover", &"pressed", &"disabled"]:
			slot.add_theme_stylebox_override(state, style)
		grid.add_child(slot)

		var content := VBoxContainer.new()
		content.name = "Content"
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = CharacterLook.accessory_icon(id)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)

		var label := Label.new()
		label.name = "Title"
		label.text = CharacterLook.accessory_option(id).title
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		_accessory_slots[id] = slot
	return grid


func _refresh_profile(_id := "") -> void:
	_profile_preview.texture = PlayerProfile.texture()
	_profile_name.text = PlayerProfile.nickname
	_profile_name.add_theme_color_override("font_color", CharacterLook.nickname_tint(PlayerProfile.nickname_color))
	for id: String in _accessory_slots:
		_refresh_accessory(id)


func _refresh_accessory(id: String) -> void:
	var title: String = CharacterLook.accessory_option(id).title
	var available := PlayerProfile.can_equip_accessory(id)
	var slot := _accessory_slots[id]
	slot.accessibility_name = title if available else "%s, закрыто" % title
	slot.disabled = not available
	slot.modulate = Color.WHITE if available else Color(0.65, 0.65, 0.65)
	var style := slot.get_theme_stylebox("normal") as StyleBoxFlat
	var equipped := id == PlayerProfile.accessory or id == PlayerProfile.nickname_color
	style.border_color = GOLD if equipped else Color(0.25, 0.26, 0.33)


func _build_achievements() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Достижения"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	_achievement_cards = VBoxContainer.new()
	_achievement_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	inset.add_child(_achievement_cards)

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
	if _cards_by_id.has(id):
		_refresh_achievement(id)
		_show_notification("Новое достижение", ACHIEVEMENTS[id][0], EARNED_MEDAL)
	for accessory_id: String in _accessory_slots:
		var option := CharacterLook.accessory_option(accessory_id)
		if option.get("achievement") == id:
			_refresh_accessory(accessory_id)
			var title: String = option.title
			if CharacterLook.NICKNAME_COLORS.has(accessory_id):
				title = "Цвет ника: " + title.to_lower()
			_show_notification("Новый аксессуар", title, CharacterLook.accessory_icon(accessory_id))


func _show_notification(title: String, description: String, icon: Texture2D) -> void:
	var card := _make_achievement_card()
	_set_card_content(card, icon, title, description, GOLD, Color.WHITE)
	for control in card.find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_achievement_popups.add_child(card)
	_layout_achievement_popups()

	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(5.0)
	tween.tween_property(card, "modulate:a", 0.0, 0.3)
	tween.tween_callback(card.queue_free)
	card.set_meta(&"dismiss_tween", tween)
	card.set_meta(&"queued_alpha", 1.0)
	card.modulate.a = 0.0
	tween.pause()


func _set_notifications_visible(show_notifications: bool) -> void:
	_achievement_popups.visible = show_notifications
	_update_notification_timers()


func _update_notification_timers() -> void:
	if not is_inside_tree():
		return
	var bottom := get_viewport().get_visible_rect().end.y
	var mobile := get_tree().get_first_node_in_group("mobile_controls") as MobileControls
	if mobile != null:
		var bounds := _achievement_popups.get_global_rect()
		bottom = mobile.top_edge(bounds.position.x, bounds.end.x)
	for card in _achievement_popups.get_children():
		var tween := card.get_meta(&"dismiss_tween", null) as Tween
		if tween == null or not tween.is_valid():
			continue
		if _achievement_popups.visible and card.size.y > 0.0 and card.get_global_rect().end.y <= bottom:
			if card.has_meta(&"queued_alpha"):
				card.modulate.a = card.get_meta(&"queued_alpha")
				card.remove_meta(&"queued_alpha")
			tween.play()
		else:
			if not card.has_meta(&"queued_alpha"):
				card.set_meta(&"queued_alpha", card.modulate.a)
				card.modulate.a = 0.0
			tween.pause()


func _layout() -> void:
	if not is_inside_tree():
		return
	var size := get_viewport().get_visible_rect().size
	var font := maxi(8, int(minf(size.y, size.x * 1.45) * font_ratio))
	var step := UiSpacing.step(size)
	var padding := step * 2
	var icon_scale := clampf(size.y / maxf(size.x, 1.0), 1.0, 1.5)
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(step * 3)
	style.set_corner_radius_all(roundi(font * 0.5))

	var box := _panel.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", padding)
	var row_height := font * 2.4
	_list.add_theme_font_size_override("font_size", font)
	_resize_expanders(roundi(font * 0.85 * icon_scale))
	var check_scale := clampf(size.y / maxf(size.x, 1.0), 1.0, 1.8)
	_list.add_theme_constant_override("icon_max_width", roundi(font * 1.4 * check_scale))
	_list.add_theme_constant_override("item_margin", step * 4)
	_list.add_theme_constant_override("v_separation", padding)
	_list.get_theme_stylebox("panel").set_content_margin_all(padding)
	_panel.custom_minimum_size = Vector2(size.x * 0.88, size.y * 0.84)
	_close_button.custom_minimum_size.y = row_height
	_stuck_button.custom_minimum_size.y = row_height
	_stuck_button.add_theme_font_size_override("font_size", font)
	_heading.add_theme_font_size_override("font_size", int(font * 1.1))
	_close_button.add_theme_font_size_override("font_size", font)
	_tabs.add_theme_font_size_override("font_size", font)
	for style_name in [&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled"]:
		var tab_style := _tabs.get_theme_stylebox(style_name)
		tab_style.content_margin_left = step
		tab_style.content_margin_right = step
	_heading.get_parent().add_theme_constant_override("separation", padding)
	_profile_layout.vertical = size.y > size.x
	_profile_layout.add_theme_constant_override("separation", step * 4)
	UiSpacing.inset(_profile_layout.get_parent(), padding)
	UiSpacing.inset(_achievement_cards.get_parent(), padding)
	var inventory := _profile_layout.get_child(0) as VBoxContainer
	inventory.add_theme_constant_override("separation", step * 4)
	var slot_side := roundi(font * 5.0)
	var slot_gap := padding
	var inventory_width := _panel.custom_minimum_size.x - style.get_minimum_size().x - padding * 2
	if not _profile_layout.vertical:
		inventory_width = (inventory_width - step * 4) * 0.5
	for grid in [_accessory_grid, _nickname_color_grid]:
		grid.get_parent().add_theme_constant_override("separation", slot_gap)
		grid.add_theme_constant_override("h_separation", slot_gap)
		grid.add_theme_constant_override("v_separation", slot_gap)
		grid.columns = clampi(floori((inventory_width + slot_gap) / (slot_side + slot_gap)), 1, grid.get_child_count())
	var preview := _profile_layout.get_child(1) as PanelContainer
	var preview_style := preview.get_theme_stylebox("panel") as StyleBoxFlat
	preview_style.set_content_margin_all(step * 3)
	preview.get_child(0).add_theme_constant_override("separation", padding)
	_profile_preview.custom_minimum_size.y = font * 8
	for label in _profile_layout.find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", font)
	var slot_font := maxi(8, roundi(font * 0.78))
	for slot in _accessory_slots.values():
		slot.custom_minimum_size = Vector2(slot_side, slot_side)
		var content := slot.get_child(0) as VBoxContainer
		content.offset_left = step
		content.offset_right = -step
		content.add_theme_constant_override("separation", step)
		content.get_node("Icon").custom_minimum_size.y = roundi(font * 1.8)
		content.get_node("Title").add_theme_font_size_override("font_size", slot_font)

	_achievement_cards.add_theme_constant_override("separation", padding)
	for card in _achievement_cards.get_children():
		_layout_achievement_card(card, font, step)
	_layout_achievement_popups()


func _layout_achievement_popups() -> void:
	var size := get_viewport().get_visible_rect().size
	var font := maxi(8, int(minf(size.y, size.x * 1.45) * font_ratio))
	var step := UiSpacing.step(size)
	_achievement_popups.add_theme_constant_override("separation", step * 2)
	var portrait := size.y > size.x
	var card_font := maxi(8, roundi(font * 0.78)) if portrait else font
	for card in _achievement_popups.get_children():
		_layout_achievement_card(card, card_font, step)
		if portrait:
			card.get_node("Row/Medal").custom_minimum_size.x = roundi(font * 1.5)
	var margin := float(step * 4)
	var width := minf(font * 16.0, size.x * 0.35)
	var top := margin
	if is_instance_valid(_boss_bar):
		top += _boss_bar.health_bottom()
	# На телефоне справа вверху кнопка эмоций — уведомления встают под неё
	var emote_bar := get_tree().get_first_node_in_group("emote_bar") as EmoteBar
	if emote_bar:
		top = maxf(top, emote_bar.top_right_bottom() + margin)
	_achievement_popups.offset_left = -margin - width
	_achievement_popups.offset_right = -margin
	_achievement_popups.offset_top = top
	_achievement_popups.offset_bottom = top
	_update_notification_timers.call_deferred()


func _layout_achievement_card(card: PanelContainer, font: int, step: int) -> void:
	card.custom_minimum_size.y = roundi(font * 4.8)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(step * 2)
	style.set_corner_radius_all(roundi(font * 0.35))
	var row := card.get_node("Row") as HBoxContainer
	row.add_theme_constant_override("separation", step * 2)
	var medal := row.get_node("Medal") as TextureRect
	medal.custom_minimum_size.x = maxi(16, roundi(font * 2.5 / 16.0) * 16)
	var labels := row.get_node("Labels") as VBoxContainer
	labels.add_theme_constant_override("separation", step)
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
	# В сети (телефон, проектор) игру не ставим на паузу: пауза остановила бы и сетевой код
	# (персонаж «отключился» бы). Свой персонаж просто не слушает ввод, пока журнал открыт (NetInput).
	if not Net.is_network():
		_was_paused = get_tree().paused
		get_tree().paused = true
	_root.show()
	_set_notifications_visible(false)
	_close_button.grab_focus()


func close() -> void:
	if not _root.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and _root.is_ancestor_of(focused):
		focused.release_focus()
	_root.hide()
	if not Net.is_network():
		get_tree().paused = _was_paused
	_set_notifications_visible(true)


## Открыт ли журнал (в сети ввод своему персонажу на это время не уходит)
func is_open() -> bool:
	return _root != null and _root.visible


# «Я застрял»: закрываем меню и возвращаем своего персонажа на точку возрождения
func _on_stuck_pressed() -> void:
	close()
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player and player.is_local:
			player.respawn()


func _exit_tree() -> void:
	if _root and _root.visible and not Net.is_network():
		get_tree().paused = _was_paused


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (_root.visible and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		if _root.visible:
			close()
		elif not get_tree().paused and GameManager.state == GameManager.GameState.PLAYING:
			open()
