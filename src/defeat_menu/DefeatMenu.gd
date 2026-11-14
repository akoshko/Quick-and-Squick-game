extends Control

## Экран поражения: через 1.5 с любая кнопка перезапускает уровень.

const RESTART_DELAY := 1.5

var _timer := 0.0
var _can_restart := false
var _gone := false


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= RESTART_DELAY:
		_can_restart = true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_restart or _gone:
		return
	if not event.is_pressed():
		return
	# клавиатура, геймпад или касание экрана (телефон)
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventScreenTouch or event is InputEventMouseButton:
		_gone = true
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/game/Game.tscn")
