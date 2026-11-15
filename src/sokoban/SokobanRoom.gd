class_name SokobanRoom
extends Node2D

## Головоломка-сокобан: мешки (bags) нужно растолкать так, чтобы пройти
## между столами к компьютеру в конце комнаты. Тянуть мешки нельзя —
## неудачный толчок может загородить проход насовсем.
##
## Тогда выручает телефон у входа: по звонку приходит модератор и
## возвращает мешки на исходные места (мешки тают и проявляются на старте).

signal reset_finished

## Мешки головоломки (их стартовые места запоминаются при запуске уровня)
@export var bags: Array[BeanBag] = []
## Кто приходит по звонку (пусто — мешки вернутся сами)
@export var moderator: Moderator
## Клетка, куда модератор подходит по звонку (рядом со входом в головоломку)
@export var moderator_cell := Vector2i.ZERO
@export var reset_line := "Сейчас всё верну как было!"

var _starts := {}          # мешок -> стартовая точка (пиксели мира)
var _resetting := false
var _returning := 0        # сколько мешков ещё возвращаются


func _ready() -> void:
	# Мешки ровняются по клеткам в своём _ready — запоминаем места после этого
	_remember_starts.call_deferred()


func _remember_starts() -> void:
	for bag in bags:
		if is_instance_valid(bag):
			_starts[bag] = bag.global_position


## Сдвинут ли хоть один мешок со своего места
func needs_reset() -> bool:
	for bag: BeanBag in _starts:
		if is_instance_valid(bag) and bag.global_position != _starts[bag]:
			return true
	return false


func is_resetting() -> bool:
	return _resetting


## Звонок по телефону: модератор идёт к головоломке и возвращает мешки
func call_moderator() -> void:
	if _resetting:
		return
	_resetting = true
	if moderator:
		var goals: Array[Vector2i] = [moderator_cell]
		moderator.send_on_errand(goals, _on_moderator_arrived)
	else:
		_on_moderator_arrived()


func _on_moderator_arrived() -> void:
	if moderator:
		Net.world_call(moderator, &"say", [reset_line])
	reset_bags()


## Вернуть все сдвинутые мешки на стартовые места
func reset_bags() -> void:
	_resetting = true
	_returning = 0
	for bag: BeanBag in _starts:
		if is_instance_valid(bag) and bag.global_position != _starts[bag]:
			_returning += 1
			bag.returned.connect(_on_bag_returned, CONNECT_ONE_SHOT)
			bag.return_to(_starts[bag])
	if _returning == 0:
		_finish_reset()


func _on_bag_returned() -> void:
	_returning -= 1
	if _returning <= 0:
		_finish_reset()


func _finish_reset() -> void:
	_resetting = false
	reset_finished.emit()
