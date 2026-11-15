class_name CoffeeCup
extends Node2D

## Стаканчик кофе во время восстания зомби-модераторов (спрайт временный).
## Подбирается, когда игрок наступает на него. Кто взял — решает сервер
## (ZombieUprising.take_coffee), у каждого стаканчика свой id.

const PICK_DISTANCE := 12.0   # насколько близко (px) нужно подойти центром

var id := 0
var uprising: ZombieUprising
var _gone := false
var _time := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_time = randf() * TAU
	# Появляется с «попом»
	_sprite.scale = Vector2.ZERO
	create_tween().tween_property(_sprite, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	_time += delta
	_sprite.position.y = -4.0 + sin(_time * 3.0) * 1.5   # покачивается над полом
	if _gone or uprising == null or not Net.runs_world():
		return
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player and player.global_position.distance_to(global_position) < PICK_DISTANCE:
			uprising.take_coffee(id, player)
			return


## Исчезнуть (with_effect — с надписью «+кофе», иначе тихо)
func vanish(with_effect: bool) -> void:
	if _gone:
		return
	_gone = true
	if with_effect:
		FloatingText.spawn(self, global_position + Vector2(0, -12), "+кофе", Color(0.95, 0.8, 0.55))
	var t := create_tween()
	t.tween_property(_sprite, "scale", Vector2(1.4, 0.6), 0.06)
	t.tween_property(_sprite, "scale", Vector2.ZERO, 0.12)
	t.tween_callback(queue_free)
