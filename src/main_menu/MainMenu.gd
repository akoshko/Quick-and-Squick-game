extends Control

## Главное меню: любая кнопка запускает игру.

var _starting := false


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		_starting = true
		get_tree().change_scene_to_file("res://src/game/GameCopy.tscn")
