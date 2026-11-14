extends Control

## Экран создания персонажа (при старте игры). Ник собирается из двух
## заготовленных слов (как титулы в Animal Crossing), внешность —
## цвет худи, причёска, цвет волос. Выбор сохраняется в PlayerProfile
## и запоминается до следующего запуска.

const GAME_SCENE := "res://src/game/HackathonMap.tscn"
const GOLD := Color(1, 0.85, 0.45)
const DICE_ICON := preload("res://src/character/dice.png")

enum Row { FIRST, SECOND, HOODIE, STYLE, COLOR }

var _index := [0, 0, 0, 0, 0]       # выбранный вариант в каждом ряду
var _options: Array[Array] = []     # названия вариантов для каждого ряда

var _box: VBoxContainer
var _title: Label
var _preview: TextureRect
var _nickname: Label
var _rows: Array[Dictionary] = []   # {label, value, prev, next}
var _dice_button: Button
var _random_button: Button
var _start_button: Button
var _time := 0.0


func _ready() -> void:
	_options = [
		CharacterLook.TITLE_FIRST,
		CharacterLook.TITLE_SECOND,
		CharacterLook.HOODIES.map(func(v: Dictionary) -> String: return v.name),
		CharacterLook.HAIR_STYLES.map(func(v: Dictionary) -> String: return v.name),
		CharacterLook.HAIR_COLORS.map(func(v: Dictionary) -> String: return v.name),
	]
	_index = [
		maxi(0, CharacterLook.TITLE_FIRST.find(PlayerProfile.title_first)),
		maxi(0, CharacterLook.TITLE_SECOND.find(PlayerProfile.title_second)),
		CharacterLook.index_of(CharacterLook.HOODIES, PlayerProfile.hoodie),
		CharacterLook.index_of(CharacterLook.HAIR_STYLES, PlayerProfile.hair_style),
		CharacterLook.index_of(CharacterLook.HAIR_COLORS, PlayerProfile.hair_color),
	]
	_build()
	_update()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_start_button.grab_focus()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_box)

	_title = Label.new()
	_title.text = "Создай персонажа"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", GOLD)
	_box.add_child(_title)

	_preview = TextureRect.new()
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_preview)

	# Ник крупно + кубик «случайный ник»
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(name_row)
	_nickname = Label.new()
	_nickname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nickname.add_theme_color_override("font_color", GOLD)
	name_row.add_child(_nickname)
	_dice_button = Button.new()
	_dice_button.icon = DICE_ICON
	_dice_button.expand_icon = true   # кубик растягивается под размер кнопки
	_dice_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксели остаются чёткими
	_dice_button.tooltip_text = "Случайный ник"
	_dice_button.pressed.connect(_randomize_nickname)
	name_row.add_child(_dice_button)

	_add_row(Row.FIRST, "Слово 1")
	_add_row(Row.SECOND, "Слово 2")
	_add_row(Row.HOODIE, "Худи")
	_add_row(Row.STYLE, "Причёска")
	_add_row(Row.COLOR, "Волосы")

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(buttons)
	_random_button = Button.new()
	_random_button.text = "Случайно"
	_random_button.pressed.connect(_randomize_all)
	buttons.add_child(_random_button)
	_start_button = Button.new()
	_start_button.text = "Начать"
	_start_button.pressed.connect(_start)
	buttons.add_child(_start_button)


# Ряд «Название  <  значение  >»
func _add_row(row_id: Row, caption: String) -> void:
	var row := HBoxContainer.new()
	_box.add_child(row)
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(_step.bind(row_id, -1))
	row.add_child(prev)
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(_step.bind(row_id, 1))
	row.add_child(next)
	_rows.append({"label": label, "value": value, "prev": prev, "next": next})


func _step(row_id: Row, delta: int) -> void:
	_index[row_id] = wrapi(_index[row_id] + delta, 0, _options[row_id].size())
	_update()


func _update() -> void:
	_nickname.text = CharacterLook.make_nickname(_options[Row.FIRST][_index[Row.FIRST]],
			_options[Row.SECOND][_index[Row.SECOND]])
	_preview.texture = CharacterLook.build(_look_id(Row.HOODIE), _look_id(Row.STYLE), _look_id(Row.COLOR))
	for i in _rows.size():
		(_rows[i].value as Label).text = _options[i][_index[i]]
	# Цвет волос не важен, если волос нет
	var bald := _look_id(Row.STYLE) == "bald"
	(_rows[Row.COLOR].prev as Button).disabled = bald
	(_rows[Row.COLOR].next as Button).disabled = bald
	(_rows[Row.COLOR].value as Label).modulate.a = 0.4 if bald else 1.0


func _look_id(row_id: Row) -> String:
	var lists := {Row.HOODIE: CharacterLook.HOODIES, Row.STYLE: CharacterLook.HAIR_STYLES,
			Row.COLOR: CharacterLook.HAIR_COLORS}
	var list: Array[Dictionary] = lists[row_id]
	return list[_index[row_id]].id


func _randomize_nickname() -> void:
	_index[Row.FIRST] = randi() % _options[Row.FIRST].size()
	_index[Row.SECOND] = randi() % _options[Row.SECOND].size()
	_update()


func _randomize_all() -> void:
	for i in _index.size():
		_index[i] = randi() % _options[i].size()
	_update()


func _start() -> void:
	PlayerProfile.set_nickname(_options[Row.FIRST][_index[Row.FIRST]], _options[Row.SECOND][_index[Row.SECOND]])
	PlayerProfile.set_look(_look_id(Row.HOODIE), _look_id(Row.STYLE), _look_id(Row.COLOR))
	PlayerProfile.save_profile()
	get_tree().change_scene_to_file(GAME_SCENE)


# Предпросмотр «дышит», как персонаж в игре (сжатие от пола)
func _process(delta: float) -> void:
	_time += delta
	var squeeze := 0.05 * (1.0 - cos(_time * 2.4)) / 2.0
	_preview.pivot_offset = Vector2(_preview.size.x / 2.0, _preview.size.y)
	_preview.scale = Vector2(1.0 + squeeze * 0.6, 1.0 - squeeze)


# Размеры — от экрана (подходит и для вертикального телефона)
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var unit := minf(screen.y, screen.x * 1.45)
	var font := maxi(10, int(unit * 0.032))
	var width := minf(screen.x * 0.9, font * 22.0)

	_box.add_theme_constant_override("separation", int(font * 0.45))
	_title.add_theme_font_size_override("font_size", int(font * 1.4))
	_preview.custom_minimum_size = Vector2.ONE * unit * 0.22
	_nickname.add_theme_font_size_override("font_size", int(font * 1.25))
	_dice_button.add_theme_font_size_override("font_size", font)
	_dice_button.custom_minimum_size = Vector2.ONE * font * 2.2
	for row in _rows:
		(row.label as Label).add_theme_font_size_override("font_size", font)
		(row.label as Label).custom_minimum_size.x = font * 6.0
		(row.value as Label).add_theme_font_size_override("font_size", font)
		for key in ["prev", "next"]:
			var button := row[key] as Button
			button.add_theme_font_size_override("font_size", font)
			button.custom_minimum_size = Vector2.ONE * font * 2.2
		(row.label.get_parent() as HBoxContainer).custom_minimum_size.x = width
	for button in [_random_button, _start_button]:
		button.add_theme_font_size_override("font_size", font)
		button.custom_minimum_size = Vector2(width / 2.0 - font * 0.3, font * 2.4)
