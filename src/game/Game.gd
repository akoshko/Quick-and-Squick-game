extends Node2D

## Основная сцена уровня: HUD, респаун, переходы на экраны победы/поражения.

@onready var _player1: Player = %Player1
@onready var _player2: Player = %Player2
@onready var _spawn1: Vector2 = (%SpawnPoint1 as Marker2D).global_position
@onready var _spawn2: Vector2 = (%SpawnPoint2 as Marker2D).global_position
@onready var _parts_label: Label = %PartsLabel
@onready var _p1_hp_label: Label = %P1HpLabel
@onready var _p2_hp_label: Label = %P2HpLabel


func _ready() -> void:
	_player1.hp_changed.connect(_on_hp_changed)
	_player2.hp_changed.connect(_on_hp_changed)
	_player1.died.connect(_on_player_died)
	_player2.died.connect(_on_player_died)

	($Killzone as Area2D).body_entered.connect(_on_killzone_body_entered)

	GameManager.part_collected.connect(_on_part_collected)
	GameManager.all_parts_collected.connect(_on_all_parts_collected)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.reset()

	_refresh_hp_label(_player1)
	_refresh_hp_label(_player2)


func _exit_tree() -> void:
	GameManager.part_collected.disconnect(_on_part_collected)
	GameManager.all_parts_collected.disconnect(_on_all_parts_collected)
	GameManager.state_changed.disconnect(_on_state_changed)


func _on_killzone_body_entered(body: Node2D) -> void:
	if body == _player1:
		_player1.respawn(_spawn1)
	elif body == _player2:
		_player2.respawn(_spawn2)


func _on_hp_changed(player_index: int, _new_hp: int) -> void:
	_refresh_hp_label(_player1 if player_index == 1 else _player2)


func _refresh_hp_label(player: Player) -> void:
	var hearts := "♥".repeat(player.hp) + "♡".repeat(player.max_hp - player.hp)
	var label := _p1_hp_label if player.player_index == 1 else _p2_hp_label
	label.text = "P%d: %s" % [player.player_index, hearts]


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
