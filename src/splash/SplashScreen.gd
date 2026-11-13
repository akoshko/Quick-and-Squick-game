extends Control

## Заставка: через 3 с или по нажатию переходит в главное меню.

const DURATION := 3.0

var _timer := 0.0
var _gone := false


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= DURATION:
		_go_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		_go_to_menu()


func _go_to_menu() -> void:
	if _gone:
		return
	_gone = true
	get_tree().change_scene_to_file("res://src/main_menu/MainMenu.tscn")
