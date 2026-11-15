class_name PuzzlePhone
extends Node2D

## Телефон на столе у входа в головоломку. По «действию»
## игрок звонит модератору, и тот возвращает мешки головоломки на места.

@export var room: SokobanRoom

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactable")


func interact(_player: Player) -> void:
	Net.world_call(self, &"net_ring")
	if room == null:
		return
	if room.is_resetting():
		_say("Занято…", Color(0.8, 0.82, 0.88))
	elif not room.needs_reset():
		_say("Всё и так на местах!", Color(0.8, 0.82, 0.88))
	else:
		_say("Дзынь! Алло, модератор?", Color(1, 0.85, 0.5))
		room.call_moderator()


func _say(text: String, color: Color) -> void:
	FloatingText.spawn(self, global_position + Vector2(0, -14), text, color)


## Трубка дребезжит (у всех, Net.world_call)
func net_ring() -> void:
	var t := create_tween()
	for i in 3:
		t.tween_property(_sprite, "rotation", deg_to_rad(12.0), 0.04)
		t.tween_property(_sprite, "rotation", deg_to_rad(-12.0), 0.08)
	t.tween_property(_sprite, "rotation", 0.0, 0.04)
