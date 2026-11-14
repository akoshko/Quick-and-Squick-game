extends Area2D

## Собираемая деталь компьютера.


func _ready() -> void:
	collision_mask = 2 # Игрок на физическом слое 2
	body_entered.connect(_on_body_entered)

	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation("float"):
		anim.play("float")


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	GameManager.collect_part()
	queue_free()
