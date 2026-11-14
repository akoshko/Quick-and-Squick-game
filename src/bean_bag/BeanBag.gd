class_name BeanBag
extends CharacterBody2D

## Кресло-мешок (случайный спрайт мешка с листа tile_map.png).
## Пример предмета для взаимодействия:
## игрок встаёт рядом, смотрит на мешок и жмёт «действие» — мешок
## отъезжает на одну клетку в ту сторону, куда смотрит игрок.
##
## Чтобы сделать свой предмет для взаимодействия, достаточно:
##   1) добавить его в группу "interactable"
##   2) написать у него метод interact(player: Player)

@export var move_speed: float = 90.0     # мешок тяжёлый — едет медленнее игрока
## Какое задание выполняется, когда мешок сдвинули (пусто — никакое)
@export var quest_id := "push_bean_bag"
## Лист с мебелью, откуда берётся картинка мешка
@export var sheet: Texture2D = preload("res://src/tile_map.png")
## Мешки на листе (области 32×32) — при появлении выбирается случайный
@export var skins: Array[Rect2] = [
	Rect2(176, 0, 32, 32), Rect2(208, 0, 32, 32),   # синие
	Rect2(240, 0, 32, 32), Rect2(272, 0, 32, 32),   # оранжевые
]

var _target_position: Vector2
var _is_moving := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	Grid.snap(self)
	_target_position = global_position
	_make_sprite()


# Спрайт случайного мешка с листа; точка спрайта — у пола (низ клетки),
# поэтому мешок сплющивается «от пола»
func _make_sprite() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = skins.pick_random() if not skins.is_empty() else Rect2(176, 0, 32, 32)
	_sprite = Sprite2D.new()
	_sprite.texture = atlas
	_sprite.flip_h = randf() < 0.5   # для разнообразия — иногда зеркально
	var half_height := atlas.region.size.y / 2.0
	_sprite.position = Vector2(0, Grid.tile_size(self).y / 2.0)
	_sprite.offset = Vector2(0, -half_height)
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if not _is_moving:
		return
	global_position = global_position.move_toward(_target_position, move_speed * delta)
	if global_position == _target_position:
		_is_moving = false


## Вызывается игроком, который стоит рядом и смотрит на мешок
func interact(player: Player) -> void:
	if _is_moving:
		return
	push(player.facing)


## Мгновенно переставить мешок (например, босс отбросил при появлении)
func displace_to(world_pos: Vector2) -> void:
	global_position = world_pos
	_target_position = world_pos
	_is_moving = false


func push(direction: Vector2i) -> void:
	var target_pos := Grid.cell_to_world(self, Grid.world_to_cell(self, global_position) + direction)

	# За мешком стена или другой предмет — не двигаемся, просто «плюхаемся»
	if test_move(global_transform, target_pos - global_position):
		_squish()
		return

	_target_position = target_pos
	_is_moving = true
	if not quest_id.is_empty():
		Quests.complete(quest_id)
	_squish()


# «Сплющивание» при толчке: мешок мягкий — оседает и пружинит обратно
# (меняем только картинку, не коллизию)
func _squish() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(1.25, 0.75), 0.08)
	var spring := tween.tween_property(_sprite, "scale", Vector2.ONE, 0.3)
	spring.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
