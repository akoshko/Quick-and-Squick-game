class_name CharacterLook

## Внешность персонажа, собранная из слоёв: тело + худи + причёска.
## Слои лежат в res://src/character/ (32×32, тот же стиль, что chel_*.png):
##   body.png        — тело: кожа, ноги, контур, худи «ключевого» красного цвета;
##   hoodie_*.png    — худи с рисунком (накладывается поверх тела);
##   hair_*.png      — причёски, нарисованные «ключевым» коричневым цветом.
## Игра перекрашивает ключевые цвета в выбранные, поэтому новый цвет — это
## одна строка в списке ниже, а новая причёска — картинка + строка.
##
## Рисуешь новую причёску? Волосы — цветом #734829 (115, 72, 41),
## контур — #16161B (22, 22, 27). Прядка ложится на колонки streak_cols.

const DIR := "res://src/character/"
const STREAK_MAX_ROW := 9                     # прядка — только над лбом
static var HOODIE_KEY := Color8(161, 40, 35)  # красное худи в body.png
static var HAIR_KEY := Color8(115, 72, 41)    # коричневые волосы в hair_*.png

static var HOODIES: Array[Dictionary] = [
	{"id": "red", "name": "Красное", "color": Color8(161, 40, 35)},
	{"id": "blue", "name": "Синее", "color": Color8(55, 95, 175)},
	{"id": "grey", "name": "Серое", "color": Color8(122, 124, 132)},
	{"id": "pink", "name": "Розовое", "color": Color8(226, 125, 165)},
	{"id": "logo", "name": "С логотипом", "layer": "hoodie_logo.png"},
]

static var HAIR_STYLES: Array[Dictionary] = [
	{"id": "bald", "name": "Лысина", "layer": ""},
	{"id": "short", "name": "Короткая", "layer": "hair_short.png"},
	{"id": "long", "name": "Длинная", "layer": "hair_long.png"},
	{"id": "mohawk", "name": "Ирокез", "layer": "hair_mohawk.png", "streak_cols": [15, 16]},
	{"id": "buns", "name": "Две дульки", "layer": "hair_buns.png"},
]

static var HAIR_COLORS: Array[Dictionary] = [
	{"id": "brunette", "name": "Брюнет", "color": Color8(58, 40, 34)},
	{"id": "brown", "name": "Каштановые", "color": Color8(115, 72, 41)},
	{"id": "blonde", "name": "Блонд", "color": Color8(222, 184, 102)},
	{"id": "ginger", "name": "Рыжие", "color": Color8(224, 97, 1)},       # как у Елены Анатольевны
	{"id": "pink", "name": "Розовые", "color": Color8(232, 120, 168)},
	{"id": "purple", "name": "Фиолетовые", "color": Color8(142, 82, 196)},
	{"id": "blue", "name": "Синие", "color": Color8(78, 140, 232)},       # светлее синего худи
	{"id": "streak", "name": "С блонд-прядкой", "color": Color8(58, 40, 34), "streak": Color8(222, 184, 102)},
]

const DEFAULT_STREAK_COLS := [11, 12]   # две колонки слева над лбом

## Ник собирается из двух заготовленных слов, как титулы в Animal Crossing:
## первое слово + второе. Своё написать нельзя — никто не напроказничает.
## Все вторые слова мужского рода, чтобы любое первое с ними согласовалось.
## Добавляй слова сюда — старые ники при этом не сломаются.
static var TITLE_FIRST: Array[String] = [
	"Сонный", "Пушистый", "Отважный", "Задумчивый", "Хрустящий", "Тайный",
	"Весёлый", "Кофейный", "Ночной", "Великий", "Мягкий", "Быстрый",
	"Загадочный", "Неунывающий", "Пиксельный", "Ламповый", "Голодный", "Уютный",
	"Шустрый", "Важный", "Сияющий", "Храбрый", "Добрый", "Бодрый",
]
static var TITLE_SECOND: Array[String] = [
	"Кодер", "Пирожок", "Мешок", "Баг", "Дедлайн", "Котик",
	"Хакер", "Пиксель", "Ноутбук", "Бублик", "Енот", "Тимлид",
	"Стажёр", "Коммит", "Сервер", "Пончик", "Чайник", "Дракон",
	"Пельмень", "Кактус", "Рефакторинг", "Печенюх", "Ёжик", "Релиз",
]

static var _cache := {}


## Текстура персонажа для выбранных вариантов (id из списков выше).
## Неизвестный id заменяется первым вариантом списка.
static func build(hoodie_id: String, style_id: String, color_id: String) -> Texture2D:
	var key := "%s/%s/%s" % [hoodie_id, style_id, color_id]
	if _cache.has(key):
		return _cache[key]

	var hoodie := find(HOODIES, hoodie_id)
	var style := find(HAIR_STYLES, style_id)
	var hair := find(HAIR_COLORS, color_id)

	var image := _load_image("body.png")
	if hoodie.has("layer"):
		_overlay(image, _load_image(hoodie.layer))
	else:
		_recolor(image, HOODIE_KEY, hoodie.color)

	if style.layer != "":
		var hair_image := _load_image(style.layer)
		var streak_cols: Array = style.get("streak_cols", DEFAULT_STREAK_COLS)
		_recolor(hair_image, HAIR_KEY, hair.color, hair.get("streak", null), streak_cols)
		_overlay(image, hair_image)

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Привести данные игрока к допустимому виду: неизвестные id и слова ника
## заменяются вариантами по умолчанию. Обязательно для данных из сети.
## Формат (он же сетевой): {title_first, title_second, hoodie, hair_style, hair_color}
## В ответе есть и готовый "nickname" — собранный из двух проверенных слов.
static func sanitize(data: Dictionary) -> Dictionary:
	var first := _word(TITLE_FIRST, data.get("title_first", ""))
	var second := _word(TITLE_SECOND, data.get("title_second", ""))
	return {
		"title_first": first,
		"title_second": second,
		"nickname": make_nickname(first, second),
		"hoodie": find(HOODIES, str(data.get("hoodie", ""))).id,
		"hair_style": find(HAIR_STYLES, str(data.get("hair_style", ""))).id,
		"hair_color": find(HAIR_COLORS, str(data.get("hair_color", ""))).id,
	}


static func make_nickname(first: String, second: String) -> String:
	return "%s %s" % [first, second]


# Слово из списка, иначе — первое слово списка (своё вписать нельзя)
static func _word(list: Array[String], value: Variant) -> String:
	var text := str(value)
	return text if text in list else list[0]


## Текстура по данным внешности (словарь из sanitize / PlayerProfile.to_dict)
static func build_from(data: Dictionary) -> Texture2D:
	var clean := sanitize(data)
	return build(clean.hoodie, clean.hair_style, clean.hair_color)


## Вариант из списка по id (или первый, если такого нет)
static func find(list: Array[Dictionary], id: String) -> Dictionary:
	for item in list:
		if item.id == id:
			return item
	return list[0]


## Индекс варианта в списке (для кнопок «‹ ›»)
static func index_of(list: Array[Dictionary], id: String) -> int:
	for i in list.size():
		if list[i].id == id:
			return i
	return 0


static func _load_image(file: String) -> Image:
	var image := (load(DIR + file) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


# Перекрасить все пиксели ключевого цвета. Если задан streak — пиксели
# в колонках streak_cols над лбом красятся в цвет прядки.
static func _recolor(image: Image, key: Color, color: Color, streak: Variant = null,
		streak_cols: Array = []) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and _same(pixel, key):
				var use_streak := streak != null and x in streak_cols and y <= STREAK_MAX_ROW
				image.set_pixel(x, y, streak if use_streak else color)


static func _overlay(image: Image, layer: Image) -> void:
	image.blend_rect(layer, Rect2i(Vector2i.ZERO, layer.get_size()), Vector2i.ZERO)


static func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
