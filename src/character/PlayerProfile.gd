extends Node

## Профиль ЛОКАЛЬНОГО игрока (autoload "PlayerProfile"): ник и внешность.
## Ник — два заготовленных слова (CharacterLook.TITLE_FIRST / TITLE_SECOND).
## Заполняется на экране создания персонажа и сохраняется между запусками
## в user://profile.cfg. При первом запуске ник выбирается случайно.
##
## Для сетевой игры: to_dict() — это всё, что нужно отправить другим
## игрокам (два слова ника, внешность, предмет и цвет ника).

signal changed
signal accessory_changed(id: String)
## Изменилось, что у игрока «новое»: непросмотренные награды и достижения
signal news_changed

const SAVE_PATH := "user://profile.cfg"
## Что игрок уже видел из наград — отдельно от внешности, сохраняется сразу
const REWARDS_PATH := "user://rewards.cfg"

var title_first := ""
var title_second := ""
var nickname: String:
	get:
		return CharacterLook.make_nickname(title_first, title_second)
var hoodie := "red"
var hair_style := "short"
var hair_color := "brown"
var accessory := CharacterLook.STARTER_ACCESSORY
var nickname_color := CharacterLook.DEFAULT_NICKNAME_COLOR
var _seen_rewards: Array[String] = []             # предметы и цвета ника, на которые уже нажимал
var _seen_achievements: Array[StringName] = []    # достижения, которые уже видел в профиле


func _ready() -> void:
	GameManager.reward_achievements_synced.connect(_refresh_reward_choices)
	GameManager.achievement_unlocked.connect(func(_id: StringName) -> void: news_changed.emit())
	GameManager.achievements_reset.connect(news_changed.emit)
	randomize_nickname()   # если сохранённого профиля нет — случайный ник
	load_profile()
	_load_seen()


## Готовая текстура персонажа для текущей внешности
func texture() -> Texture2D:
	return CharacterLook.build(hoodie, hair_style, hair_color, accessory)


## Данные профиля одним словарём — формат для сети и для Player.set_appearance()
func to_dict() -> Dictionary:
	return {"title_first": title_first, "title_second": title_second,
			"hoodie": hoodie, "hair_style": hair_style, "hair_color": hair_color,
			"accessory": accessory, "nickname_color": nickname_color}


func equip_accessory(id: String) -> void:
	if id == accessory or id == nickname_color or not can_equip_accessory(id):
		return
	if CharacterLook.NICKNAME_COLORS.has(id):
		nickname_color = id
	else:
		accessory = id
	accessory_changed.emit(id)


func can_equip_accessory(id: String) -> bool:
	return CharacterLook.is_reward_available(id, GameManager.has_achievement)


## Новая награда: открыта, но игрок на неё ещё не нажимал (на ней — «Новое»)
func is_new_reward(id: String) -> bool:
	return CharacterLook.accessory_option(id).get("achievement", &"") != &"" 			and can_equip_accessory(id) and not _seen_rewards.has(id)


## Есть ли в профиле что-то новое (получено достижение, а профиль с тех пор не открывали)
func has_profile_news() -> bool:
	for id: StringName in Achievements.LIST:
		if GameManager.has_achievement(id) and not _seen_achievements.has(id):
			return true
	return false


## Есть ли вообще что-то новое (для значка «!» на кнопке «Журнал»)
func has_news() -> bool:
	if has_profile_news():
		return true
	for id in CharacterLook.reward_ids():
		if is_new_reward(id):
			return true
	return false


## Игрок нажал на новую награду — «Новое» с неё снимается
func mark_reward_seen(id: String) -> void:
	if _seen_rewards.has(id):
		return
	_seen_rewards.append(id)
	_save_seen()
	news_changed.emit()


## Игрок открыл профиль — все полученные достижения больше не «новые»
func mark_profile_seen() -> void:
	if not has_profile_news():
		return
	for id: StringName in Achievements.LIST:
		if GameManager.has_achievement(id) and not _seen_achievements.has(id):
			_seen_achievements.append(id)
	_save_seen()
	news_changed.emit()


func _save_seen() -> void:
	var config := ConfigFile.new()
	config.set_value("seen", "rewards", _seen_rewards)
	config.set_value("seen", "achievements", _seen_achievements)
	config.save(REWARDS_PATH)


func _load_seen() -> void:
	var config := ConfigFile.new()
	if config.load(REWARDS_PATH) != OK:
		return
	_seen_rewards.assign(config.get_value("seen", "rewards", []))
	_seen_achievements.assign(config.get_value("seen", "achievements", []))


func _refresh_reward_choices() -> void:
	if not can_equip_accessory(accessory):
		accessory = CharacterLook.STARTER_ACCESSORY
	if not can_equip_accessory(nickname_color):
		nickname_color = CharacterLook.DEFAULT_NICKNAME_COLOR
	changed.emit()


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
