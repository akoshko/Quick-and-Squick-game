extends Node

## Глобальный менеджер игры (autoload "GameManager").

enum GameState { PLAYING, PAUSED }

signal state_changed(new_state: GameState)
signal achievement_unlocked(id: StringName)
signal reward_achievements_synced
## Все ачивки сброшены (админка): журнал перерисовывает карточки, профиль снимает награды.
signal achievements_reset

const MUSIC_VOLUME_DB := -12.0   ## музыка тише звуков, чтобы их было слышно

var state: GameState = GameState.PLAYING
var _unlocked_achievements: Dictionary[StringName, bool] = {}


func has_achievement(id: StringName) -> bool:
	return _unlocked_achievements.has(id)


func unlock_achievement(id: StringName) -> void:
	# На сервере награда записывается в профиль игрока и передаётся ему.
	if Net.forward_personal(&"GameManager", &"unlock_achievement", [id]):
		return
	if has_achievement(id):
		return
	_unlocked_achievements[id] = true
	achievement_unlocked.emit(id)


func sync_reward_achievements(earned: Array) -> void:
	for catalog in [CharacterLook.ACCESSORIES, CharacterLook.NICKNAME_COLORS]:
		for option in catalog.values():
			var id: StringName = option.get("achievement", &"")
			if id != &"" and id != CharacterLook.ALL_ACHIEVEMENTS and id not in earned:
				_unlocked_achievements.erase(id)
	for id: StringName in earned:
		unlock_achievement(id)
	reward_achievements_synced.emit()


## Забыть все полученные ачивки (сервер присылает по команде админки «Сбросить ачивки»).
func reset_achievements() -> void:
	_unlocked_achievements.clear()
	achievements_reset.emit()
	reward_achievements_synced.emit()


func _ready() -> void:
	Quests.quest_completed.connect(_on_quest_completed)
	var stream := load("res://src/game/soundtrack.mp3") as AudioStreamMP3
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = MUSIC_VOLUME_DB
	add_child(music)
	music.play()


func _on_quest_completed(quest: Quest) -> void:
	match quest.id:
		"main":
			if not Net.is_network():
				unlock_achievement(&"first_steps")
		"hide_and_seek":
			unlock_achievement(&"hide_and_seek")


func set_state(new_state: GameState) -> void:
	state = new_state
	state_changed.emit(new_state)


func reset() -> void:
	set_state(GameState.PLAYING)


func _process(_delta: float) -> void:
	# Back + Start на любом из двух геймпадов — выход из игры
	for device in range(2):
		if Input.is_joy_button_pressed(device, JOY_BUTTON_BACK) \
				and Input.is_joy_button_pressed(device, JOY_BUTTON_START):
			get_tree().quit()
			return
