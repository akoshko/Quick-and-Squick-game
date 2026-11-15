class_name QuestPanel
extends CanvasLayer

## Журнал — бейдж участника хакатона на шнурке (как настоящий бейдж TulaHack):
## красная шапка с логотипом, плашка «Участник», персонаж и ник, две вкладки —
## «Задания» (список чекбоксов) и «Профиль» (предметы, цвет ника, достижения).
## Бейдж висит вертикально; при открытии падает сверху, при смене вкладки
## слегка покачивается на шнурке.
##
## Здесь же — уведомления о достижениях и наградах (выезжают справа сверху).

const CHECK_EMPTY := preload("res://src/quests/checkbox_empty_dark.png")
const CHECK_DONE := preload("res://src/quests/checkbox_done_dark.png")
const SOUND_ON := preload("res://src/ui/sound_on.png")
const SOUND_OFF := preload("res://src/ui/sound_off.png")
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

# Цвета бейджа
const GOLD := Color(1, 0.85, 0.45)                 # уведомления на тёмном фоне
const BADGE_RED := Color(0.72, 0.17, 0.14)
const BADGE_RED_LIGHT := Color(0.85, 0.32, 0.26)
const BADGE_WHITE := Color(0.98, 0.96, 0.93)
const INK := Color(0.17, 0.14, 0.14)               # основной текст на белом
const MUTED_INK := Color(0.55, 0.52, 0.5)          # выполненное, подписи
const EARNED_INK := Color(0.6, 0.42, 0.05)         # полученное достижение (тёмное золото)
const TILE := Color(0.93, 0.91, 0.87)              # плитки и кнопки на бейдже
const TILE_BORDER := Color(0.8, 0.77, 0.72)
const ROPE := Color(0.94, 0.91, 0.83)
const ROPE_SHADOW := Color(0.62, 0.58, 0.5)
const DONE_TEXT := MUTED_INK                       # выполненные задания — приглушённые и зачёркнутые

const SWING := [3.2, -2.3, 1.4, -0.7, 0.25, 0.0]   # покачивание бейджа (градусы), затухающее

@export var font_ratio := 0.032

var _root: Control
var _was_paused := false
var _backdrop: ColorRect
var _lanyard: Control          # шнурок: от дырочек бейджа к верху экрана
var _badge: Control            # бейдж целиком — его и качаем
var _panel: PanelContainer
var _header: Control           # красная шапка с логотипом (рисуется кодом)
var _logo: Label
var _brand: Label
var _role: Label               # плашка «Участник»
var _list: VBoxContainer       # список заданий: сверху текущие, ниже выполненные
var _tabs: TabContainer
var _profile_layout: VBoxContainer
var _accessory_grid: GridContainer
var _nickname_color_grid: GridContainer
var _profile_preview: TextureRect
var _profile_name: Label
var _accessory_slots: Dictionary[StringName, Button] = {}
var _achievement_cards: HFlowContainer
var _achievement_hint: Label   # название и описание нажатого достижения
var _achievement_popups: VBoxContainer
var _cards_by_id: Dictionary[StringName, PanelContainer] = {}
var _boss_bar: BossBar
var _close_button: Button
var _stuck_button: Button
var _sound_button: Button
var _swing_tween: Tween
var _drop_tween: Tween
var _rest_y := 0.0             # где бейдж висит в покое


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	GameManager.achievement_unlocked.connect(_on_achievement_unlocked)
	GameManager.achievements_reset.connect(_on_achievements_reset)
	PlayerProfile.changed.connect(_refresh_profile)
	PlayerProfile.accessory_changed.connect(_refresh_profile)
	_boss_bar = get_tree().get_first_node_in_group("boss_bar") as BossBar
	if _boss_bar:
		_boss_bar.health_layout_changed.connect(_layout_achievement_popups)
	Quests.changed.connect(_refresh)
	Quests.selected_quest_changed.connect(_refresh)
	get_viewport().size_changed.connect(_layout, CONNECT_DEFERRED)
	_refresh()


# --- Сборка бейджа ---

func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.025, 0.04, 0.65)
	_root.add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_lanyard = Control.new()
	_lanyard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lanyard.draw.connect(_draw_lanyard)
	_root.add_child(_lanyard)
	_lanyard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_badge = Control.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_badge)

	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_WHITE
	style.shadow_color = Color(0, 0, 0, 0.35)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_badge.add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 0)
	_panel.add_child(box)

	_build_header(box)

	var body := MarginContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var content := VBoxContainer.new()
	content.name = "Content"
	body.add_child(content)

	# Как на настоящем бейдже: «Участник», а ниже — кто это (персонаж и ник)
	_role = Label.new()
	_role.text = "Участник"
	_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_role.add_theme_color_override("font_color", Color.WHITE)
	var role_style := StyleBoxFlat.new()
	role_style.bg_color = BADGE_RED
	role_style.skew = Vector2(0.25, 0)
	_role.add_theme_stylebox_override("normal", role_style)
	content.add_child(_role)

	var identity := HBoxContainer.new()
	identity.name = "Identity"
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(identity)
	_profile_preview = TextureRect.new()
	_profile_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_profile_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profile_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(_profile_preview)
	_profile_name = Label.new()
	_profile_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_child(_profile_name)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	_tabs.tab_changed.connect(func(_tab: int) -> void:
		_scroll_to_top()
		_swing(1.0))
	content.add_child(_tabs)
	_style_tabs()

	var tasks_scroll := ScrollContainer.new()
	tasks_scroll.name = "Задания"
	tasks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(tasks_scroll)
	var tasks_inset := MarginContainer.new()
	tasks_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tasks_scroll.add_child(tasks_inset)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tasks_inset.add_child(_list)
	_build_profile()

	# Внизу бейджа — звук и «Я застрял»
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(footer)
	_sound_button = _make_badge_button("")
	_sound_button.expand_icon = true
	_sound_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sound_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sound_button.pressed.connect(func() -> void: Sfx.set_muted(not Sfx.muted))
	Sfx.muted_changed.connect(_refresh_sound_button)
	footer.add_child(_sound_button)
	_refresh_sound_button(Sfx.muted)
	_stuck_button = _make_badge_button("Я застрял")
	_stuck_button.pressed.connect(_on_stuck_pressed)
	footer.add_child(_stuck_button)

	_root.hide()

	_achievement_popups = VBoxContainer.new()
	_achievement_popups.sort_children.connect(_update_notification_timers)
	_achievement_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_achievement_popups)
	_achievement_popups.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_achievement_popups.grow_horizontal = Control.GROW_DIRECTION_BEGIN


# Красная шапка: узор, логотип </> и «TulaHack 2026», дырочки под шнурок, крестик
func _build_header(box: VBoxContainer) -> void:
	_header = Control.new()
	_header.name = "Header"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.clip_contents = true   # узор не вылезает за шапку
	_header.draw.connect(_draw_header)
	box.add_child(_header)

	_logo = Label.new()
	_logo.text = "</>"
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_logo.add_theme_color_override("font_color", BADGE_RED)
	var logo_style := StyleBoxFlat.new()
	logo_style.bg_color = Color.WHITE
	_logo.add_theme_stylebox_override("normal", logo_style)
	_header.add_child(_logo)

	_brand = Label.new()
	_brand.text = "TulaHack\n2026"
	_brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brand.add_theme_color_override("font_color", Color.WHITE)
	_header.add_child(_brand)

	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.flat = true
	_close_button.tooltip_text = "Закрыть"
	_close_button.add_theme_color_override("font_color", Color.WHITE)
	_close_button.add_theme_color_override("font_hover_color", Color(1, 0.85, 0.8))
	_close_button.add_theme_color_override("font_focus_color", Color.WHITE)
	_close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_button.pressed.connect(close)
	_header.add_child(_close_button)


func _make_badge_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	for state in [&"normal", &"hover", &"pressed", &"focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = TILE.darkened(0.06) if state == &"hover" else (TILE.darkened(0.12) if state == &"pressed" else TILE)
		style.border_color = TILE_BORDER if state != &"focus" else BADGE_RED
		style.set_border_width_all(1)
		style.draw_center = state != &"focus"
		button.add_theme_stylebox_override(state, style)
	for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
			&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_focus_color"]:
		button.add_theme_color_override(color_name, INK)
	return button


# Вкладки — как плашка «Участник»: выбранная красная, остальные светлые
func _style_tabs() -> void:
	for style_name in [&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled", &"tab_focus"]:
		var tab_style := StyleBoxFlat.new()
		tab_style.bg_color = BADGE_RED if style_name == &"tab_selected" else (TILE.darkened(0.06) if style_name == &"tab_hovered" else TILE)
		tab_style.draw_center = style_name != &"tab_focus"
		_tabs.add_theme_stylebox_override(style_name, tab_style)
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	_tabs.add_theme_color_override("font_unselected_color", INK)
	_tabs.add_theme_color_override("font_hovered_color", INK)


func _build_profile() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Профиль"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)

	_profile_layout = VBoxContainer.new()
	_profile_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(_profile_layout)

	var inventory := VBoxContainer.new()
	inventory.name = "Inventory"
	inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_layout.add_child(inventory)
	_accessory_grid = _build_accessory_grid(inventory, "Предметы", CharacterLook.ACCESSORIES.keys())
	_nickname_color_grid = _build_accessory_grid(inventory, "Цвет ника", CharacterLook.NICKNAME_COLORS.keys())

	_build_achievements()
	_refresh_profile()


func _build_accessory_grid(inventory: VBoxContainer, title: String, ids: Array) -> GridContainer:
	var section := VBoxContainer.new()
	inventory.add_child(section)
	section.add_child(_section_heading(title))
	var grid := GridContainer.new()
	section.add_child(grid)
	for id: String in ids:
		var slot := Button.new()
		slot.pressed.connect(PlayerProfile.equip_accessory.bind(id))
		var style := StyleBoxFlat.new()
		style.bg_color = TILE
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
		label.add_theme_color_override("font_color", INK)
		content.add_child(label)
		_accessory_slots[id] = slot
	return grid


func _section_heading(title: String) -> Label:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", BADGE_RED)
	return heading


func _refresh_profile(_id := "") -> void:
	_profile_preview.texture = PlayerProfile.texture()
	_profile_name.text = PlayerProfile.nickname
	_profile_name.add_theme_color_override("font_color", _ink_tint(CharacterLook.nickname_tint(PlayerProfile.nickname_color)))
	for id: String in _accessory_slots:
		_refresh_accessory(id)


# Цвет ника на белом бейдже: светлые цвета (белый по умолчанию) — тёмным
static func _ink_tint(tint: Color) -> Color:
	return INK if tint.get_luminance() > 0.75 else tint


func _refresh_accessory(id: String) -> void:
	var title: String = CharacterLook.accessory_option(id).title
	var available := PlayerProfile.can_equip_accessory(id)
	var slot := _accessory_slots[id]
	slot.accessibility_name = title if available else "%s, закрыто" % title
	slot.disabled = not available
	slot.modulate = Color.WHITE if available else Color(0.65, 0.65, 0.65)
	var style := slot.get_theme_stylebox("normal") as StyleBoxFlat
	var equipped := id == PlayerProfile.accessory or id == PlayerProfile.nickname_color
	style.border_color = BADGE_RED if equipped else TILE_BORDER


# Достижения в профиле: на телефоне — значки (нажатие показывает название и
# описание), на компьютере — значок и название
func _build_achievements() -> void:
	var section := VBoxContainer.new()
	section.name = "Achievements"
	_profile_layout.add_child(section)
	section.add_child(_section_heading("Достижения"))
	_achievement_cards = HFlowContainer.new()
	_achievement_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(_achievement_cards)
	_achievement_hint = Label.new()
	_achievement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_achievement_hint.add_theme_color_override("font_color", MUTED_INK)
	_achievement_hint.text = "Нажми на значок, чтобы узнать, за что он."
	section.add_child(_achievement_hint)

	for id: StringName in ACHIEVEMENTS:
		var card := _make_achievement_card(true)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_achievement_card_input.bind(id))
		_cards_by_id[id] = card
		_achievement_cards.add_child(card)
		_refresh_achievement(id)


## light — карточка на белом бейдже; иначе тёмная (уведомление поверх игры)
func _make_achievement_card(light := false) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = TILE if light else Color(0.14, 0.15, 0.20)
	style.border_color = TILE_BORDER if light else Color(0.25, 0.26, 0.33)
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var medal := TextureRect.new()
	medal.name = "Medal"
	medal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(medal)

	var labels := VBoxContainer.new()
	labels.name = "Labels"
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var color := EARNED_INK if earned else (Color(0.5, 0.45, 0.58) if hidden else INK)
	var card := _cards_by_id[id]
	_set_card_content(card, icon, title, description, color, MUTED_INK)
	card.tooltip_text = "%s\n%s" % [title, description]
	card.modulate = Color.WHITE if earned else Color(1, 1, 1, 0.75)


func _on_achievement_card_input(event: InputEvent, id: StringName) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var labels := _cards_by_id[id].get_node("Row/Labels")
		_achievement_hint.text = "%s — %s" % [labels.get_node("Title").text, labels.get_node("Description").text]
		_achievement_hint.add_theme_color_override("font_color", INK)


func _set_card_content(card: PanelContainer, icon: Texture2D, title: String,
		description: String, title_color: Color, description_color := Color(0.73, 0.75, 0.82)) -> void:
	var row := card.get_node("Row")
	row.get_node("Medal").texture = icon
	var labels := row.get_node("Labels")
	labels.get_node("Title").text = title
	labels.get_node("Title").add_theme_color_override("font_color", title_color)
	labels.get_node("Description").text = description
	labels.get_node("Description").add_theme_color_override("font_color", description_color)


func _on_achievements_reset() -> void:
	for id: StringName in _cards_by_id:
		_refresh_achievement(id)
	_refresh_profile()


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


# --- Уведомления о достижениях (поверх игры, справа сверху) ---

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


# --- Раскладка ---

func _layout() -> void:
	if not is_inside_tree():
		return
	var size := get_viewport().get_visible_rect().size
	var font := maxi(8, int(minf(size.y, size.x * 1.45) * font_ratio))
	var step := UiSpacing.step(size)
	var padding := step * 2
	var portrait := size.y > size.x
	var icon_scale := clampf(size.y / maxf(size.x, 1.0), 1.0, 1.5)
	var row_height := font * 2.4

	# Бейдж всегда вертикальный: в портрете почти во весь экран, на широком — по высоте
	var badge_h := size.y * (0.86 if portrait else 0.9)
	var badge_w := minf(size.x - step * 8, badge_h * (0.6 if portrait else 0.66))
	_rest_y = maxf(step * 8, size.y - badge_h - step * 2) if portrait else (size.y - badge_h) / 2.0 + step * 2
	_badge.size = Vector2(badge_w, badge_h)
	_badge.position = Vector2((size.x - badge_w) / 2.0, _rest_y)
	_badge.pivot_offset = Vector2(badge_w / 2.0, 0)   # качается на шнурке — вокруг верха
	_panel.size = _badge.size
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	var corner := roundi(font * 0.6)
	style.set_corner_radius_all(corner)
	style.shadow_size = step * 2

	_layout_header(badge_w, font, step, corner)

	var body := _panel.get_node("Box/Body") as MarginContainer
	UiSpacing.inset(body, padding)
	body.add_theme_constant_override("margin_left", step * 3)
	body.add_theme_constant_override("margin_right", step * 3)
	var content := body.get_node("Content") as VBoxContainer
	content.add_theme_constant_override("separation", padding)

	_role.add_theme_font_size_override("font_size", font)
	var role_style := _role.get_theme_stylebox("normal") as StyleBoxFlat
	role_style.content_margin_left = step * 6
	role_style.content_margin_right = step * 6
	role_style.content_margin_top = step
	role_style.content_margin_bottom = step
	role_style.set_corner_radius_all(step)
	(_profile_preview.get_parent() as HBoxContainer).add_theme_constant_override("separation", padding)
	_profile_preview.custom_minimum_size = Vector2.ONE * roundi(font * 3.2)
	_profile_name.add_theme_font_size_override("font_size", roundi(font * 1.25))
	# Ник переносится, если не влез рядом с персонажем
	var name_width := badge_w - step * 6 - _profile_preview.custom_minimum_size.x - padding
	_profile_name.custom_minimum_size.x = minf(name_width, _profile_name.get_theme_font(&"font").get_string_size(
			_profile_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font * 1.25)).x + 2.0)

	_tabs.add_theme_font_size_override("font_size", font)
	for style_name in [&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled"]:
		var tab_style := _tabs.get_theme_stylebox(style_name) as StyleBoxFlat
		tab_style.content_margin_left = step * 3
		tab_style.content_margin_right = step * 3
		tab_style.content_margin_top = step
		tab_style.content_margin_bottom = step
		tab_style.set_corner_radius_all(step)
	_tabs.add_theme_constant_override("side_margin", 0)

	UiSpacing.inset(_list.get_parent(), padding)
	_list.add_theme_constant_override("separation", padding)
	_layout_task_rows(font, step, icon_scale)

	var footer := _stuck_button.get_parent() as HBoxContainer
	footer.add_theme_constant_override("separation", padding)
	_stuck_button.custom_minimum_size.y = row_height
	_stuck_button.add_theme_font_size_override("font_size", font)
	_sound_button.custom_minimum_size = Vector2.ONE * row_height
	_sound_button.add_theme_constant_override("icon_max_width", roundi(row_height * 0.55))
	for button in [_stuck_button, _sound_button]:
		for state in [&"normal", &"hover", &"pressed", &"focus"]:
			var button_style := button.get_theme_stylebox(state) as StyleBoxFlat
			button_style.set_corner_radius_all(step)
			button_style.content_margin_left = step * 3
			button_style.content_margin_right = step * 3

	# Профиль: предметы, цвет ника, достижения — столбиком
	UiSpacing.inset(_profile_layout.get_parent(), padding)
	_profile_layout.add_theme_constant_override("separation", step * 4)
	var inventory := _profile_layout.get_node("Inventory") as VBoxContainer
	inventory.add_theme_constant_override("separation", step * 4)
	var slot_side := roundi(font * 5.0)
	var slot_gap := padding
	var inventory_width := badge_w - step * 6 - padding * 2
	for grid in [_accessory_grid, _nickname_color_grid]:
		grid.get_parent().add_theme_constant_override("separation", slot_gap)
		grid.add_theme_constant_override("h_separation", slot_gap)
		grid.add_theme_constant_override("v_separation", slot_gap)
		grid.columns = clampi(floori((inventory_width + slot_gap) / (slot_side + slot_gap)), 1, grid.get_child_count())
	for label in _profile_layout.find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", font)
	var slot_font := maxi(8, roundi(font * 0.78))
	for slot in _accessory_slots.values():
		slot.custom_minimum_size = Vector2(slot_side, slot_side)
		(slot.get_theme_stylebox("normal") as StyleBoxFlat).set_corner_radius_all(step)
		var slot_content := slot.get_child(0) as VBoxContainer
		slot_content.offset_left = step
		slot_content.offset_right = -step
		slot_content.add_theme_constant_override("separation", step)
		slot_content.get_node("Icon").custom_minimum_size.y = roundi(font * 1.8)
		slot_content.get_node("Title").add_theme_font_size_override("font_size", slot_font)

	_achievement_cards.add_theme_constant_override("h_separation", padding)
	_achievement_cards.add_theme_constant_override("v_separation", padding)
	(_achievement_cards.get_parent() as VBoxContainer).add_theme_constant_override("separation", padding)
	_achievement_hint.add_theme_font_size_override("font_size", slot_font)
	for card in _achievement_cards.get_children():
		_layout_achievement_card(card, font, step)
		# Телефон — только значок; компьютер — значок и название (описание — по нажатию)
		var labels := card.get_node("Row/Labels") as VBoxContainer
		labels.visible = not portrait
		labels.get_node("Description").visible = false
		card.custom_minimum_size.y = 0
		var medal := card.get_node("Row/Medal") as TextureRect
		medal.custom_minimum_size = Vector2.ONE * roundi(font * (2.6 if portrait else 2.0))
		card.custom_minimum_size.x = 0.0 if portrait else inventory_width   # на компьютере — по одной в строку
	_layout_achievement_popups()
	_lanyard.queue_redraw()
	_header.queue_redraw()


func _layout_header(badge_w: float, font: int, step: int, corner: int) -> void:
	var header_h := roundf(badge_w * 0.32)
	_header.custom_minimum_size.y = header_h
	_header.set_meta(&"corner", corner)
	var logo_side := roundf(header_h * 0.44)
	var logo_style := _logo.get_theme_stylebox("normal") as StyleBoxFlat
	logo_style.set_corner_radius_all(roundi(logo_side * 0.14))
	_logo.add_theme_font_size_override("font_size", roundi(logo_side * 0.42))
	_logo.size = Vector2.ONE * logo_side
	var group_w := logo_side + step * 3 + font * 4.6
	_logo.position = Vector2(roundf((badge_w - group_w) / 2.0), roundf(header_h * 0.22))
	_brand.add_theme_font_size_override("font_size", roundi(logo_side * 0.36))
	_brand.add_theme_constant_override("line_spacing", -roundi(logo_side * 0.06))
	_brand.position = Vector2(_logo.position.x + logo_side + step * 3, _logo.position.y)
	_brand.size = Vector2(font * 5.0, logo_side)
	_close_button.add_theme_font_size_override("font_size", font)
	_close_button.size = Vector2.ONE * roundf(font * 2.0)
	# Справа, ниже дырочки под шнурок
	_close_button.position = Vector2(badge_w - _close_button.size.x - step * 2, roundf(header_h * 0.32))


# Шапка: красный фон со скруглёнными верхними углами, «сеть» из линий и
# точек, белый скос снизу (как на настоящем бейдже) и две дырочки под шнурок
func _draw_header() -> void:
	var w := _header.size.x
	var h := _header.size.y
	var corner: int = _header.get_meta(&"corner", 8)
	var red := StyleBoxFlat.new()
	red.bg_color = BADGE_RED
	red.corner_radius_top_left = corner
	red.corner_radius_top_right = corner
	_header.draw_style_box(red, Rect2(0, 0, w, h))
	# Узор: шестиугольная сетка тонкими линиями с точками в узлах
	var cell := w / 6.0
	for row in range(-1, 4):
		for col in range(-1, 8):
			var center := Vector2(col * cell + (cell * 0.5 if row % 2 else 0.0), row * cell * 0.85)
			for i in 6:
				var a := TAU * i / 6.0 + PI / 6.0
				var b := TAU * (i + 1) / 6.0 + PI / 6.0
				var p := center + Vector2(cos(a), sin(a)) * cell * 0.5
				var q := center + Vector2(cos(b), sin(b)) * cell * 0.5
				_header.draw_line(p, q, BADGE_RED_LIGHT, 1.0)
			_header.draw_circle(center + Vector2(cell * 0.5, 0).rotated(PI / 6.0), maxf(1.5, cell * 0.035), BADGE_RED_LIGHT)
	# Белый скос: белое тело бейджа поднимается к середине и опускается вправо
	var body := PackedVector2Array([Vector2(0, h * 0.86), Vector2(w * 0.32, h * 0.7),
			Vector2(w, h * 0.97), Vector2(w, h + 1), Vector2(0, h + 1)])
	_header.draw_colored_polygon(body, BADGE_WHITE)
	# Дырочки под шнурок
	for hole in _holes():
		_header.draw_circle(hole, h * 0.07, Color(0.08, 0.06, 0.06))


# Где дырочки (в координатах бейджа)
func _holes() -> Array[Vector2]:
	var w := _header.size.x
	var h := _header.size.y
	return [Vector2(w * 0.09, h * 0.16), Vector2(w * 0.91, h * 0.16)]


# Шнурок: из каждой дырочки уходит вверх, за край экрана
func _draw_lanyard() -> void:
	if not _root.visible:
		return
	var screen := get_viewport().get_visible_rect().size
	var xform := _badge.get_global_transform()
	var width := maxf(3.0, screen.y * 0.008)
	var top := Vector2(screen.x / 2.0, -screen.y * 0.25)
	for hole in _holes():
		var start := xform * hole
		var end := Vector2(lerpf(start.x, top.x, 0.55), top.y)
		_lanyard.draw_line(start + Vector2(1.5, 1.5), end + Vector2(1.5, 1.5), ROPE_SHADOW, width)
		_lanyard.draw_line(start, end, ROPE, width)


func _process(_delta: float) -> void:
	if _root.visible and (_is_animating()):
		_lanyard.queue_redraw()


func _is_animating() -> bool:
	return (_swing_tween != null and _swing_tween.is_running()) or (_drop_tween != null and _drop_tween.is_running())


# Обе вкладки — к самому верху (при закрытии бейджа и при смене вкладки)
func _scroll_to_top() -> void:
	for tab in _tabs.get_children():
		var scroll := tab as ScrollContainer
		if scroll:
			scroll.scroll_vertical = 0


## Бейдж качнулся на шнурке (смена вкладки, открытие)
func _swing(strength: float) -> void:
	if _swing_tween:
		_swing_tween.kill()
	_badge.rotation = 0.0
	_swing_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for angle: float in SWING:
		_swing_tween.tween_property(_badge, "rotation", deg_to_rad(angle * strength), 0.13)
	_swing_tween.finished.connect(_lanyard.queue_redraw)


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


# --- Задания ---

func _refresh(_value: Variant = null) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	# Сверху — текущие задания (по одному на незавершённый квест)
	var active := 0
	for quest in Quests.quests:
		if not quest.done:
			_list.add_child(_make_task_row(quest.current_task(), quest.id, false, quest.id == Quests.selected_quest_id))
			active += 1
	# Ниже — всё выполненное, зачёркнутым
	var done_rows: Array[Control] = []
	for quest in Quests.quests:
		var tasks: Array[Quest] = quest.steps
		if quest.steps.is_empty():
			tasks = [quest]
		for task in tasks:
			if task.done:
				done_rows.append(_make_task_row(task, quest.id, true, false))
	if active > 0 and not done_rows.is_empty():
		_list.add_child(HSeparator.new())
	for row in done_rows:
		_list.add_child(row)
	if _list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Заданий пока нет"
		empty.add_theme_color_override("font_color", MUTED_INK)
		_list.add_child(empty)
	_layout()


# Строка списка: чекбокс и текст задания. Текущее выбранное — красное,
# выполненное — с галочкой, приглушённое и зачёркнутое
func _make_task_row(task: Quest, quest_id: String, done: bool, current: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.set_meta(&"quest_id", quest_id)
	row.set_meta(&"done", done)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BADGE_RED, 0.09) if current else Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", style)
	if done:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(_on_task_row_input.bind(quest_id))
	var line := HBoxContainer.new()
	line.name = "Line"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var check := TextureRect.new()
	check.name = "Check"
	check.texture = CHECK_DONE if done else CHECK_EMPTY
	check.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(check)
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := task.title.replace("[", "[lb]")
	text.text = "[s]%s[/s]" % title if done else title
	text.add_theme_color_override("default_color", DONE_TEXT if done else (BADGE_RED if current else INK))
	line.add_child(text)
	return row


# Размеры строк списка заданий (у журнала свои размеры чекбоксов)
func _layout_task_rows(font: int, step: int, check_scale: float) -> void:
	for row in _list.get_children():
		if row is Label:
			row.add_theme_font_size_override("font_size", font)
		if not row is PanelContainer:
			continue
		var style := row.get_theme_stylebox("panel") as StyleBoxFlat
		style.set_content_margin_all(step)
		style.set_corner_radius_all(step)
		var line := row.get_child(0) as HBoxContainer
		line.add_theme_constant_override("separation", step * 2)
		line.get_node("Check").custom_minimum_size = Vector2.ONE * roundi(font * check_scale)
		var text := line.get_node("Text") as RichTextLabel
		for font_name in [&"normal_font_size", &"bold_font_size"]:
			text.add_theme_font_size_override(font_name, font)


func _on_task_row_input(event: InputEvent, quest_id: String) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_select_quest(quest_id)


## Сделать задание текущим (нажатие на строку в журнале): журнал закрывается
func _select_quest(quest_id: String) -> void:
	close()
	# Выбор пересобирает список. Дождёмся завершения обработки клика.
	Quests.select_quest.call_deferred(quest_id)


# --- Открыть и закрыть ---

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
	_layout()
	# Бейдж падает сверху на шнурке и покачивается
	if _drop_tween:
		_drop_tween.kill()
	_badge.position.y = -_badge.size.y
	_drop_tween = create_tween()
	_drop_tween.tween_property(_badge, "position:y", _rest_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_swing(0.7)
	_close_button.grab_focus()


func close() -> void:
	if not _root.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and _root.is_ancestor_of(focused):
		focused.release_focus()
	if _drop_tween:
		_drop_tween.kill()
	_badge.position.y = _rest_y
	_scroll_to_top()   # открылся снова — всё наверху
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


# Кнопка звука: динамик с волнами или перечёркнутый
func _refresh_sound_button(muted: bool) -> void:
	_sound_button.icon = SOUND_OFF if muted else SOUND_ON
	_sound_button.tooltip_text = "Включить звук" if muted else "Выключить звук"


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
