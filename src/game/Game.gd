extends Node2D

## Основная сцена уровня: HUD, респаун, переходы на экраны победы/поражения.

@onready var _player1: Player = %Player1
@onready var _spawn1: Vector2 = (%SpawnPoint1 as Marker2D).global_position
@onready var _parts_label: Label = %PartsLabel


func _ready() -> void:
	#_player1.hp_changed.connect(_on_hp_changed)
	#_player2.hp_changed.connect(_on_hp_changed)
	#_player1.died.connect(_on_player_died)
	#_player2.died.connect(_on_player_died)

	($Killzone as Area2D).body_entered.connect(_on_killzone_body_entered)

	GameManager.part_collected.connect(_on_part_collected)
	GameManager.all_parts_collected.connect(_on_all_parts_collected)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.reset()


func _exit_tree() -> void:
	GameManager.part_collected.disconnect(_on_part_collected)
	GameManager.all_parts_collected.disconnect(_on_all_parts_collected)
	GameManager.state_changed.disconnect(_on_state_changed)


func _on_killzone_body_entered(body: Node2D) -> void:
	if body == _player1:
		_player1.respawn(_spawn1)


func _on_player_died(_player_index: int) -> void:
	GameManager.set_state(GameManager.GameState.GAME_OVER)


func _on_part_collected(total: int) -> void:
	_parts_label.text = "Детали: %d / %d" % [total, GameManager.PARTS_NEEDED]


func _on_all_parts_collected() -> void:
	_parts_label.text = "Все детали собраны! Найди пирог!"


func _on_state_changed(new_state: GameManager.GameState) -> void:
	match new_state:
		GameManager.GameState.VICTORY:
			get_tree().change_scene_to_file.call_deferred("res://src/victory_screen/VictoryScreen.tscn")
		GameManager.GameState.GAME_OVER:
			get_tree().change_scene_to_file.call_deferred("res://src/defeat_menu/DefeatMenu.tscn")
