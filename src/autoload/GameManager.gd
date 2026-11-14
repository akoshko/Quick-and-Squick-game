extends Node

## Глобальный менеджер игры (autoload "GameManager").

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER, VICTORY }

const PARTS_NEEDED := 15

signal state_changed(new_state: GameState)
signal part_collected(total: int)
signal all_parts_collected

var state: GameState = GameState.PLAYING
var parts_collected: int = 0


func _ready() -> void:
	var stream := load("res://src/game/soundtrack.mp3") as AudioStreamMP3
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	add_child(music)
	music.play()


func set_state(new_state: GameState) -> void:
	state = new_state
	state_changed.emit(new_state)


func collect_part() -> void:
	parts_collected += 1
	part_collected.emit(parts_collected)
	if parts_collected >= PARTS_NEEDED:
		all_parts_collected.emit()


func reset() -> void:
	parts_collected = 0
	set_state(GameState.PLAYING)


func _process(_delta: float) -> void:
	# Back + Start на любом из двух геймпадов — выход из игры
	for device in range(2):
		if Input.is_joy_button_pressed(device, JOY_BUTTON_BACK) \
				and Input.is_joy_button_pressed(device, JOY_BUTTON_START):
			get_tree().quit()
			return
