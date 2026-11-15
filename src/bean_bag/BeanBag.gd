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
## Какой вид из skins взять (-1 — случайный). Нужно, чтобы мешок выглядел
## так же, как на макете уровня.
@export var skin_index := -1
## Иногда зеркалить картинку для разнообразия (только для случайного вида)
@export var random_flip := true

signal returned   ## вернулся на место после return_to()

const FADE_TIME := 0.35   # сколько тает и проявляется при возврате на место
# Прозрачность уходит в сеть ступенями 0…NET_ALPHA_STEPS: пока мешок тает при возврате,
# состояние меняется ступеньками, а не каждый кадр
const NET_ALPHA_STEPS := 10

var _target_position: Vector2
var _is_moving := false
var _sprite: Sprite2D
# Номер выбранного вида в skins. skin_index — просьба редактора (-1 — случайный),
# а это итог выбора (в сети его выбирает сервер)
var _chosen_skin := 0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group(WorldSync.GROUP)   # в сети позиция, вид и прозрачность — с сервера
	Grid.snap(self)
	_target_position = global_position
	_make_sprite()


# Спрайт случайного мешка с листа; точка спрайта — у пола (низ клетки),
# поэтому мешок сплющивается «от пола»
func _make_sprite() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	if skins.is_empty():
		atlas.region = Rect2(176, 0, 32, 32)
	else:
		_chosen_skin = skin_index % skins.size() if skin_index >= 0 else randi() % skins.size()
		atlas.region = skins[_chosen_skin]
	_sprite = Sprite2D.new()
	_sprite.texture = atlas
	_sprite.flip_h = random_flip and skin_index < 0 and randf() < 0.5   # иногда зеркально
	var half_height := atlas.region.size.y / 2.0
	_sprite.position = Vector2(0, Grid.tile_size(self).y / 2.0)
	_sprite.offset = Vector2(0, -half_height)
	add_child(_sprite)


## Мешок едет после толчка
func is_moving() -> bool:
	return _is_moving


## Плавно вернуть мешок в точку world_pos (сброс головоломки): мешок тает,
## переносится и проявляется. Пока возвращается, толкать его нельзя и он
## никому не мешает. Если на месте стоит персонаж — ждём, пока он отойдёт.
func return_to(world_pos: Vector2) -> void:
	remove_from_group("interactable")
	while _is_moving:
		await get_tree().physics_frame
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	await fade.finished
	_shape.disabled = true
	while _character_at(world_pos):
		await get_tree().create_timer(0.2).timeout
	displace_to(world_pos)
	_shape.disabled = false
	var appear := create_tween()
	appear.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	await appear.finished
	add_to_group("interactable")
	returned.emit()


# Стоит ли в точке персонаж (игрок или модератор — физический слой 2)
func _character_at(world_pos: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape.shape
	query.transform = Transform2D(0.0, world_pos)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _physics_process(delta: float) -> void:
	if not _is_moving:
		return
	global_position = global_position.move_toward(_target_position, move_speed * delta)
	if global_position == _target_position:
		_is_moving = false


## Сеть: что видят клиенты (позицию WorldSync добавляет сам)
func net_state() -> Dictionary:
	return {"skin": _chosen_skin, "flip": _sprite.flip_h,
		"alpha": roundi(modulate.a * NET_ALPHA_STEPS)}


## Клиент: вид, поворот и прозрачность с сервера
func apply_net_state(state: Dictionary) -> void:
	var skin: int = state.get("skin", _chosen_skin)
	if skin != _chosen_skin and not skins.is_empty():
		_chosen_skin = skin % skins.size()
		(_sprite.texture as AtlasTexture).region = skins[_chosen_skin]
	_sprite.flip_h = state.get("flip", _sprite.flip_h)
	modulate.a = state.get("alpha", NET_ALPHA_STEPS) / float(NET_ALPHA_STEPS)


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
		Sfx.play_at(&"rustle", global_position, 0.12, -6.0)   # упёрся — тише
		Net.world_call(self, &"net_squish")
		return

	_target_position = target_pos
	_is_moving = true
	Sfx.play_at(&"rustle", global_position, 0.15)
	if not quest_id.is_empty():
		Quests.complete(quest_id)   # в сети — тому, кто толкнул (Net.as_actor)
	Net.world_call(self, &"net_squish")


## «Сплющивание» при толчке (у всех, Net.world_call): мешок мягкий — оседает и пружинит
## обратно (меняем только картинку, не коллизию)
func net_squish() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(1.25, 0.75), 0.08)
	var spring := tween.tween_property(_sprite, "scale", Vector2.ONE, 0.3)
	spring.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
