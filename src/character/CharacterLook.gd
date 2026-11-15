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
const NO_ACCESSORY := "none"
const STARTER_ACCESSORY := NO_ACCESSORY
## Награда за ВСЕ достижения (Achievements.LIST), а не за одно
const ALL_ACHIEVEMENTS := &"all"
## Предметы: надевается один. "effect" — не рисуется на спрайте, а показывается
## над головой (Player); остальные — пиксель-арт из ACCESSORY_ART поверх персонажа.
const ACCESSORIES := {
	NO_ACCESSORY: {"title": "Нет аксессуара"},
	"first_steps": {"title": "Значок хакатона", "achievement": &"first_steps"},
	"apple": {"title": "Яблоко во рту", "achievement": &"steve_jobs"},
	"cookie": {"title": "Печенька во рту", "achievement": &"clean_cookies"},
	"detective": {"title": "Очки детектива", "achievement": &"hide_and_seek"},
	"zz": {"title": "Zz над головой", "achievement": &"zombie_apocalypse", "effect": true},
	"cat_hat": {"title": "Шапочка-котик", "achievement": ALL_ACHIEVEMENTS},
}
const DEFAULT_NICKNAME_COLOR := "white"
## Цвет ника. "stars" — звёздочки по бокам, "gradient" — переливающийся
## градиент из трёх цветов (рисует NicknameStyle)
const NICKNAME_COLORS := {
	DEFAULT_NICKNAME_COLOR: {"title": "Белый", "tint": Color.WHITE},
	"blue": {"title": "Синий со звёздами", "tint": Color("#75aaff"), "stars": true, "achievement": &"boss_victory"},
	"green": {"title": "Зелёный градиент", "tint": Color("#5be37d"),
			"gradient": [Color("#c4ff6b"), Color("#35d67c"), Color("#109e5c")], "achievement": &"zombie_apocalypse"},
	"mascot": {"title": "Котик-градиент", "tint": Color("#ff6a3d"),
			"gradient": [Color("#e8423a"), Color("#ff9d43"), Color("#ffd75e")], "achievement": ALL_ACHIEVEMENTS},
}
## Пиксель-арт предметов: где лежит на спрайте 32×32 (левый верхний угол) и
## картинка по строкам (буквы — цвета из ART_PALETTE, точка — прозрачно)
const ACCESSORY_ART := {
	"first_steps": {"at": Vector2i(14, 17), "rows": [   # значок TulaHack: белый, с красным котиком
		".KKKKK.", "KWWWWWK", "KWRWRWK", "KWRRRWK", "KWRRRWK", "KWWWWWK", ".KKKKK."]},
	"cat_hat": {"at": Vector2i(8, 0), "rows": [         # шапочка-маскот: ушки и белые ^ ^
		".KK..........KK.", "KRRK........KRRK", "KRRRK......KRRRK", "KRRRRKKKKKKRRRRK",
		"KRRRRRRRRRRRRRRK", "KRRWRRRRRRRRWRRK", "KRWRWRRRRRRWRWRK", "KrrrrrrrrrrrrrrK",
		".KKKKKKKKKKKKKK."]},
	"detective": {"at": Vector2i(10, 8), "rows": [      # круглые очки
		".FFF...FFF.", "FLLLF.FLLLF", "FLLLFFFLLLF", ".FFF...FFF."]},
	"apple": {"at": Vector2i(10, 10), "rows": [          # яблоко во рту
		"...gG", ".KAKG", "KAAAK", "KAAaK", ".KaK."]},
	"cookie": {"at": Vector2i(10, 10), "rows": [         # печенька во рту
		".ccc.", "cCDCc", "cCCCc", "cDCDc", ".ccc."]},
	"zz": {"at": Vector2i.ZERO, "rows": [                # значок для инвентаря (сама Zz — над головой)
		"ZZZZ...", "...Z...", "..Z.zzz", ".Z....z", "ZZZZ.z.", ".....zz", "....zzz"]},
}
const ART_PALETTE := {
	"K": Color("#16161b"), "W": Color("#fafafa"), "R": Color("#d6302a"), "r": Color("#a01e1c"),
	"F": Color("#5c3c28"), "L": Color(0.75, 0.88, 1.0, 0.6), "A": Color("#f26368"), "a": Color("#be323c"),
	"G": Color("#78c85a"), "g": Color("#46963c"), "C": Color("#ecbe78"), "c": Color("#965f2d"),
	"D": Color("#502d19"), "Z": Color("#9fd8ff"), "z": Color("#5fa8e6"),
}
## Особые скины создателей игры: готовые спрайты 32×32 вместо собранных слоёв.
## Выдаёт только сервер (админка, по токену сессии); из профиля игрока не принимаются.
const SPECIAL_SKINS := {
	"dasha": {"title": "Даша", "texture": "res://src/dasha.png"},
	"artem": {"title": "Артём", "texture": "res://src/artem.png"},
	"valera": {"title": "Валера", "texture": "res://src/valera.png"},
	"mark": {"title": "Марк", "texture": "res://src/mark.png"},
}
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
static var _accessory_icons: Dictionary[String, Texture2D] = {}


## Текстура персонажа для выбранных вариантов (id из списков выше).
## Неизвестный id заменяется первым вариантом списка. Особый скин (SPECIAL_SKINS) заменяет
## тело, худи и причёску целиком; аксессуар на него не надевается, чтобы не закрыть рисунок.
static func build(hoodie_id: String, style_id: String, color_id: String, accessory_id := "",
		special_skin := "") -> Texture2D:
	if SPECIAL_SKINS.has(special_skin):
		return load(SPECIAL_SKINS[special_skin].texture) as Texture2D
	var key := "%s/%s/%s/%s" % [hoodie_id, style_id, color_id, accessory_id]
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

	if ACCESSORY_ART.has(accessory_id) and not ACCESSORIES.get(accessory_id, {}).get("effect", false):
		var art := accessory_icon(accessory_id).get_image()
		image.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), ACCESSORY_ART[accessory_id].at)

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Привести данные игрока к допустимому виду: неизвестные id и слова ника
## заменяются вариантами по умолчанию. Обязательно для данных из сети.
## Формат профиля: {title_first, title_second, hoodie, hair_style, hair_color, accessory}
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
		"accessory": clean_accessory(data.get("accessory")),
		"special_skin": clean_special_skin(data.get("special_skin")),
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
	return build(clean.hoodie, clean.hair_style, clean.hair_color, clean.accessory, clean.special_skin)


## Id особого скина или "" (обычная внешность), если такого нет.
static func clean_special_skin(value: Variant) -> String:
	return str(value) if value is String and SPECIAL_SKINS.has(value) else ""


static func clean_accessory(value: Variant) -> String:
	return str(value) if value is String and ACCESSORIES.has(value) else STARTER_ACCESSORY


static func accessory_option(id: String) -> Dictionary:
	return ACCESSORIES.get(id, NICKNAME_COLORS.get(id, {}))


static func accessory_icon(id: String) -> Texture2D:
	if _accessory_icons.has(id):
		return _accessory_icons[id]
	var icon: Image
	if ACCESSORY_ART.has(id):
		var rows: Array = ACCESSORY_ART[id].rows
		icon = Image.create_empty(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				if ART_PALETTE.has(rows[y][x]):
					icon.set_pixel(x, y, ART_PALETTE[rows[y][x]])
	elif id == NO_ACCESSORY:
		icon = Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
		for pixel in range(1, 6):
			icon.set_pixel(pixel, pixel, Color("#a0a6b5"))
			icon.set_pixel(pixel, 6 - pixel, Color("#a0a6b5"))
	else:
		icon = _nickname_icon(id)
	_accessory_icons[id] = ImageTexture.create_from_image(icon)
	return _accessory_icons[id]


# Значок цвета ника: квадрат цвета, градиент или синий со звёздочкой
static func _nickname_icon(id: String) -> Image:
	var style: Dictionary = NICKNAME_COLORS[clean_nickname_color(id)]
	var icon := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	var gradient: Array = style.get("gradient", [])
	for x in 8:
		var color: Color = style.tint
		if not gradient.is_empty():
			var t := x / 7.0
			color = gradient[0].lerp(gradient[1], t * 2.0) if t < 0.5 else gradient[1].lerp(gradient[2], t * 2.0 - 1.0)
		for y in 8:
			icon.set_pixel(x, y, color)
	if style.get("stars", false):
		for point: Vector2i in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(1, 3), Vector2i(2, 3),
				Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 4), Vector2i(3, 5)]:
			icon.set_pixel(point.x, point.y, Color("#fff4b0"))
	return icon


## Можно ли надеть награду: нет требования, есть нужное достижение или
## (для ALL_ACHIEVEMENTS) все достижения. earned(id) -> bool — есть ли достижение.
## Одна проверка для клиента (PlayerProfile) и сервера (PlayerRegistry).
static func is_reward_available(id: String, earned: Callable) -> bool:
	var option := accessory_option(id)
	if option.is_empty():
		return false
	var requirement: StringName = option.get("achievement", &"")
	if requirement == &"":
		return true
	if requirement == ALL_ACHIEVEMENTS:
		return Achievements.LIST.keys().all(func(achievement: StringName) -> bool: return earned.call(achievement))
	return earned.call(requirement)


## Все награды (предметы и цвета ника), которые требуют достижения — кроме тех, что даются всем
static func reward_ids() -> Array[String]:
	var ids: Array[String] = []
	for catalog: Dictionary in [ACCESSORIES, NICKNAME_COLORS]:
		for id: String in catalog:
			if catalog[id].get("achievement", &"") != &"":
				ids.append(id)
	return ids


## Награды, которые открылись, когда получено достижение achievement_id:
## привязанные к нему и «за все достижения», если теперь собраны все
static func rewards_unlocked_by(achievement_id: StringName, earned: Callable) -> Array[String]:
	var ids: Array[String] = []
	for id in reward_ids():
		var requirement: StringName = accessory_option(id).achievement
		if requirement == achievement_id or (requirement == ALL_ACHIEVEMENTS and is_reward_available(id, earned)):
			ids.append(id)
	return ids


static func clean_nickname_color(value: Variant) -> String:
	return str(value) if value is String and NICKNAME_COLORS.has(value) else DEFAULT_NICKNAME_COLOR


static func nickname_tint(value: Variant) -> Color:
	return NICKNAME_COLORS[clean_nickname_color(value)].tint


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
