extends Area2D

## Пирог — финиш уровня.

var _hint_label: Label


func _ready() -> void:
	collision_mask = 2 # Игрок на физическом слое 2
	body_entered.connect(_on_body_entered)

	_hint_label = get_node_or_null("Hint") as Label
	GameManager.part_collected.connect(_on_part_collected)
	_update_hint()


func _exit_tree() -> void:
	GameManager.part_collected.disconnect(_on_part_collected)


func _on_part_collected(_total: int) -> void:
	_update_hint()


func _update_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.visible = GameManager.parts_collected >= GameManager.PARTS_NEEDED


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return

	# TODO: Just show final score and finish the game
	# When not all the Parts were collected, then show "You didn't collect all the details, pay attention nex time!"
	# or if collected - then show "Congrats!" message
	# Pass this text as a scene parameter
	# if GameManager.parts_collected < GameManager.PARTS_NEEDED:
	# 	return

	GameManager.set_state(GameManager.GameState.VICTORY)
