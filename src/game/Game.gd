extends Node2D

## Основная сцена уровня: HUD, переходы на экраны победы/поражения.

# Надпись со счётчиком деталей необязательна: если её нет в HUD,
# счётчик просто не показывается
@onready var _parts_label: Label = get_node_or_null("%PartsLabel")


func _ready() -> void:
	#%Player1.hp_changed.connect(_on_hp_changed)
	#%Player2.hp_changed.connect(_on_hp_changed)
	#%Player1.died.connect(_on_player_died)
	#%Player2.died.connect(_on_player_died)

	GameManager.part_collected.connect(_on_part_collected)
	GameManager.all_parts_collected.connect(_on_all_parts_collected)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.reset()
	Quests.reset()


func _exit_tree() -> void:
	GameManager.part_collected.disconnect(_on_part_collected)
	GameManager.all_parts_collected.disconnect(_on_all_parts_collected)
	GameManager.state_changed.disconnect(_on_state_changed)


func _on_player_died(_player_index: int) -> void:
	GameManager.set_state(GameManager.GameState.GAME_OVER)


func _on_part_collected(total: int) -> void:
	if _parts_label:
		_parts_label.text = "Детали: %d / %d" % [total, GameManager.PARTS_NEEDED]


func _on_all_parts_collected() -> void:
	if _parts_label:
		_parts_label.text = "Все детали собраны! Найди пирог!"


func _on_state_changed(new_state: GameManager.GameState) -> void:
	match new_state:
		GameManager.GameState.VICTORY:
			get_tree().change_scene_to_file.call_deferred("res://src/victory_screen/VictoryScreen.tscn")
		GameManager.GameState.GAME_OVER:
			get_tree().change_scene_to_file.call_deferred("res://src/defeat_menu/DefeatMenu.tscn")
