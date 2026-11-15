class_name QuestProgress
extends CanvasLayer

## Плашка текущего задания в углу экрана — маленький бейдж в стиле журнала:
## белая карточка с красной полосой сверху, чекбокс и текст задания (без
## заголовков и названия квеста) и красная кнопка «Журнал».

const CHECK_EMPTY := preload("res://src/quests/checkbox_empty_dark.png")
const CHECK_DONE := preload("res://src/quests/checkbox_done_dark.png")
const DONE_COLOR := Color(0.16, 0.52, 0.28)
const DONE_FLASH := Color(0.84, 0.95, 0.85, 0.97)   # плашка вспыхивает зелёным, когда задание выполнено
const CARD_COLOR := Color(QuestPanel.BADGE_WHITE, 0.97)

@export var font_ratio := 0.032

var _panel: PanelContainer
var _task: Label          # текст текущего задания
var _check: TextureRect   # чекбокс задания
var _open_button: Button
var _news_dot: TextureRect   # «!» на кнопке «Журнал», пока в профиле есть новое
var _shake_tween: Tween


func _ready() -> void:
	layer = 5
	_build()
	var boss_bar := get_tree().get_first_node_in_group("boss_bar") as BossBar
	if boss_bar:
		boss_bar.avoid_quest_panel(_panel)
	Quests.changed.connect(_refresh)
	Quests.selected_quest_changed.connect(_refresh)
	Quests.quest_completed.connect(_animate_completion)
	GameManager.achievement_unlocked.connect(_on_reward_unlocked)
	PlayerProfile.news_changed.connect(_refresh_news_dot)
	get_viewport().size_changed.connect(_layout)
	_refresh()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.border_color = QuestPanel.BADGE_RED   # красная полоса сверху — как шапка бейджа
	style.shadow_color = Color(0, 0, 0, 0.3)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	_panel.add_child(box)

	var task_row := HBoxContainer.new()
	box.add_child(task_row)
	_check = TextureRect.new()
	_check.texture = CHECK_EMPTY
	_check.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_check.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	task_row.add_child(_check)

	_task = Label.new()
	_task.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_row.add_child(_task)

	# «Журнал» — красная, как выбранная вкладка бейджа
	_open_button = Button.new()
	_open_button.text = "Журнал"
	_open_button.pressed.connect(_open_quest_list)
	for state in [&"normal", &"hover", &"pressed", &"focus"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = QuestPanel.BADGE_RED_LIGHT if state == &"hover" else (
				QuestPanel.BADGE_RED.darkened(0.15) if state == &"pressed" else QuestPanel.BADGE_RED)
		button_style.draw_center = state != &"focus"
		_open_button.add_theme_stylebox_override(state, button_style)
	for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		_open_button.add_theme_color_override(color_name, Color.WHITE)
	box.add_child(_open_button)
	_news_dot = TextureRect.new()
	_news_dot.texture = QuestPanel.NEWS_ICON
	_news_dot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_news_dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_news_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open_button.add_child(_news_dot)
	_refresh_news_dot()


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var layout_height := minf(screen.y, screen.x * 1.45)
	var font := maxi(8, int(layout_height * font_ratio))
	var step := UiSpacing.step(screen)
	var margin := step * 4
	var padding := step * 2
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_content_margin_all(padding)
	style.border_width_top = step * 2
	style.content_margin_top = padding + step * 2
	style.set_corner_radius_all(roundi(font * 0.5))
	style.shadow_size = step
	for state in [&"normal", &"hover", &"pressed", &"focus"]:
		(_open_button.get_theme_stylebox(state) as StyleBoxFlat).set_corner_radius_all(step)

	var box := _panel.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", step)
	_task.get_parent().add_theme_constant_override("separation", step)
	var icon_scale := clampf(screen.y / maxf(screen.x, 1.0), 1.0, 1.5)
	var check_size := roundi(font * icon_scale)
	_task.custom_minimum_size.x = maxf(0, minf(font * 12.0, screen.x * 0.53) - padding * 2.0 - check_size - step)
	_open_button.custom_minimum_size.y = font * 2.4
	_task.add_theme_font_size_override("font_size", font)
	_check.custom_minimum_size = Vector2.ONE * check_size
	_open_button.add_theme_font_size_override("font_size", font)
	_panel.position = Vector2(margin, margin)
	var dot := roundi(font * 1.1)
	_news_dot.size = Vector2(dot, dot)
	_news_dot.position = Vector2(step, (font * 2.4 - dot) / 2.0)
	_panel.reset_size.call_deferred()


func _refresh(_quest_id: String = "") -> void:
	var quest := Quests.find(Quests.selected_quest_id)
	_check.visible = quest != null
	if quest:
		var task := quest.current_task()
		_task.text = task.title
		_check.texture = CHECK_DONE if task.done else CHECK_EMPTY
		_task.add_theme_color_override("font_color", DONE_COLOR if task.done else QuestPanel.INK)
	else:
		_task.text = "Все задания выполнены" if Quests.all_done() else "Заданий пока нет"
		_task.add_theme_color_override("font_color", DONE_COLOR if Quests.all_done() else QuestPanel.INK)
	_layout()


func _animate_completion(quest: Quest) -> void:
	if quest.id != Quests.selected_quest_id:
		return
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	var normal_color := style.bg_color
	var tween := create_tween()
	tween.tween_property(style, "bg_color", DONE_FLASH, 0.18)
	tween.tween_property(style, "bg_color", normal_color, Quests.COMPLETION_DISPLAY_TIME - 0.18)


# Новая награда или достижение: плашка трясётся, из неё вылетает «!»
func _on_reward_unlocked(_id: StringName) -> void:
	# Трясём весь слой HUD (offset), а не плашку: её место и размер не меняются —
	# по ним раскладываются полоска босса и уведомления
	if _shake_tween:
		_shake_tween.kill()
	offset = Vector2.ZERO
	_shake_tween = create_tween()
	for shift: float in [7.0, -6.0, 5.0, -3.0, 1.5, 0.0]:
		_shake_tween.tween_property(self, "offset:x", shift, 0.05)
	_pop_exclamation()
	_refresh_news_dot()


func _pop_exclamation() -> void:
	var mark := Label.new()
	mark.text = "!"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := _task.get_theme_font_size(&"font_size")
	mark.add_theme_font_size_override("font_size", font * 2)
	mark.add_theme_color_override("font_color", QuestPanel.BADGE_RED)
	mark.add_theme_color_override("font_outline_color", Color.WHITE)
	mark.add_theme_constant_override("outline_size", maxi(4, roundi(font * 0.35)))
	add_child(mark)
	mark.reset_size()
	var start := _panel.position + Vector2(_panel.size.x - mark.size.x * 0.6, -mark.size.y * 0.3)
	mark.position = start
	mark.pivot_offset = mark.size / 2.0
	mark.scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(mark, "scale", Vector2.ONE * 1.3, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(mark, "scale", Vector2.ONE, 0.1)
	t.tween_property(mark, "position:y", start.y - font * 2.5, 0.8).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mark, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.tween_callback(mark.queue_free)


func _refresh_news_dot(_value: Variant = null) -> void:
	if _news_dot:
		_news_dot.visible = PlayerProfile.has_news()


func _open_quest_list() -> void:
	var quest_panel := get_parent().get_node_or_null("QuestPanel") as QuestPanel
	if quest_panel:
		quest_panel.open()
