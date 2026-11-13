extends Control

## Экран победы: показывает результат, через 2 с любая кнопка ведёт в меню.

const EXIT_DELAY := 2.0

var _timer := 0.0
var _can_exit := false
var _gone := false


func _ready() -> void:
	var score_label: Label = $Center/VBox/ScoreMessage
	var collected: int = GameManager.parts_collected
	var needed: int = GameManager.PARTS_NEEDED

	if collected >= needed:
		score_label.text = "Congrats! You collected all the parts!"
	else:
		score_label.text = "You didn't collect all the details, pay attention next time!\n(%d / %d)" % [collected, needed]


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= EXIT_DELAY:
		_can_exit = true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_exit or _gone:
		return
	if not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		_gone = true
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/main_menu/MainMenu.tscn")
