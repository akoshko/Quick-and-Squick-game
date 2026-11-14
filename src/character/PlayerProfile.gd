extends Node

## Профиль ЛОКАЛЬНОГО игрока (autoload "PlayerProfile"): ник и внешность.
## Ник — два заготовленных слова (CharacterLook.TITLE_FIRST / TITLE_SECOND).
## Заполняется на экране создания персонажа и сохраняется между запусками
## в user://profile.cfg. При первом запуске ник выбирается случайно.
##
## Для сетевой игры: to_dict() — это всё, что нужно отправить другим
## игрокам (два слова ника + три id внешности). На их стороне те же данные
## проходят CharacterLook.sanitize() и применяются через Player.set_appearance().

signal changed

const SAVE_PATH := "user://profile.cfg"

var title_first := ""
var title_second := ""
var nickname: String:
	get:
		return CharacterLook.make_nickname(title_first, title_second)
var hoodie := "red"
var hair_style := "short"
var hair_color := "brown"


func _ready() -> void:
	randomize_nickname()   # если сохранённого профиля нет — случайный ник
	load_profile()


## Готовая текстура персонажа для текущей внешности
func texture() -> Texture2D:
	return CharacterLook.build(hoodie, hair_style, hair_color)


## Данные профиля одним словарём — формат для сети и для Player.set_appearance()
func to_dict() -> Dictionary:
	return {"title_first": title_first, "title_second": title_second,
			"hoodie": hoodie, "hair_style": hair_style, "hair_color": hair_color}


func set_nickname(first: String, second: String) -> void:
	title_first = first
	title_second = second
	changed.emit()


func randomize_nickname() -> void:
	set_nickname(CharacterLook.TITLE_FIRST.pick_random(), CharacterLook.TITLE_SECOND.pick_random())


func set_look(new_hoodie: String, new_style: String, new_color: String) -> void:
	hoodie = new_hoodie
	hair_style = new_style
	hair_color = new_color
	changed.emit()


func randomize_look() -> void:
	set_look(CharacterLook.HOODIES.pick_random().id,
			CharacterLook.HAIR_STYLES.pick_random().id,
			CharacterLook.HAIR_COLORS.pick_random().id)


func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "title_first", title_first)
	config.set_value("player", "title_second", title_second)
	config.set_value("player", "hoodie", hoodie)
	config.set_value("player", "hair_style", hair_style)
	config.set_value("player", "hair_color", hair_color)
	config.save(SAVE_PATH)


func load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	# Через sanitize: файл могли поправить руками — в ник попадут только слова из списков
	var clean := CharacterLook.sanitize({
		"title_first": config.get_value("player", "title_first", title_first),
		"title_second": config.get_value("player", "title_second", title_second),
		"hoodie": config.get_value("player", "hoodie", hoodie),
		"hair_style": config.get_value("player", "hair_style", hair_style),
		"hair_color": config.get_value("player", "hair_color", hair_color),
	})
	title_first = clean.title_first
	title_second = clean.title_second
	hoodie = clean.hoodie
	hair_style = clean.hair_style
	hair_color = clean.hair_color
	changed.emit()
