class_name BeanBag
extends CharacterBody2D

## Кресло-мешок. Пример предмета для взаимодействия:
## игрок встаёт рядом, смотрит на мешок и жмёт «действие» — мешок
## отъезжает на одну клетку в ту сторону, куда смотрит игрок.
##
## Чтобы сделать свой предмет для взаимодействия, достаточно:
##   1) добавить его в группу "interactable"
##   2) написать у него метод interact(player: Player)

@export var move_speed: float = 90.0     # мешок тяжёлый — едет медленнее игрока
@export var color := Color(0.85, 0.45, 0.2)
@export var quest_id := "push_bean_bag"

var _target_position: Vector2
var _is_moving := false
var _squash := Vector2.ONE   # растяжение картинки для анимации


func _ready() -> void:
	add_to_group("interactable")
	Grid.snap(self)
	_target_position = global_position


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


# Небольшая анимация «сплющивания», чтобы мешок казался мягким
# (меняем только картинку, не коллизию)
func _squish() -> void:
	var tween := create_tween()
	tween.tween_method(_set_squash, Vector2.ONE, Vector2(1.2, 0.8), 0.08)
	tween.tween_method(_set_squash, Vector2(1.2, 0.8), Vector2.ONE, 0.15)


func _set_squash(value: Vector2) -> void:
	_squash = value
	queue_redraw()


# Рисуем мешок кодом, пока нет спрайта. Когда появится картинка —
# добавь в сцену Sprite2D и удали эту функцию.
func _draw() -> void:
	var r := Grid.tile_size(self).x * 0.45
	# сплющиваем «от пола»: нижняя точка мешка остаётся на месте
	draw_set_transform(Vector2(0, r * 0.9) * (Vector2.ONE - _squash), 0.0, _squash)
	_draw_ellipse(Vector2(0, r * 0.55), Vector2(r, r * 0.35), Color(0, 0, 0, 0.25))   # тень
	_draw_ellipse(Vector2(0, r * 0.1), Vector2(r, r * 0.8), color)                     # мешок
	_draw_ellipse(Vector2(0, -r * 0.05), Vector2(r * 0.55, r * 0.4), color.darkened(0.25))  # вмятина-сиденье
	_draw_ellipse(Vector2(-r * 0.45, -r * 0.35), Vector2(r * 0.18, r * 0.12), color.lightened(0.35))  # блик


func _draw_ellipse(center: Vector2, radius: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(points, fill)
