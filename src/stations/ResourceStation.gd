class_name ResourceStation
extends StaticBody2D

## Базовый класс для всего, что может «закончиться»: еда, компьютеры.
##
## Наследник вызывает _set_empty(), когда ресурс кончился. Через
## refill_delay секунд станция зовёт модератора своей зоны (Zone —
## родитель станции): самого свободного, при равенстве — ближайшего.
## Он подходит и вызывает refill(). Если у зоны нет модераторов — зовёт
## модератора без зоны; если и такого нет — пополняется сама.
##
## Чтобы сделать новый ресурс: extends ResourceStation, напиши
## interact(player) и переопредели _on_refilled().

signal depleted(station: ResourceStation)
signal refilled(station: ResourceStation)

@export var refill_delay := 5.0
## Что всплывает, когда модератор пополнил (пусто — текст по умолчанию у наследника)
@export var refill_text := ""

var is_empty := false
## Сбит боссом (еда рассыпана). Пока босс жив, станция заблокирована:
## модератор не может её пополнить
var is_knocked := false
var _locked := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("resource_station")
	Grid.snap(self)


## Пополнить ресурс (вызывает модератор)
func refill() -> void:
	if not is_empty or _locked:
		return
	is_empty = false
	is_knocked = false
	_on_refilled()
	refilled.emit(self)
	FloatingText.spawn(self, global_position + Vector2(0, -14),
			refill_text if refill_text != "" else "Пополнено!", Color(0.6, 1, 0.65))
	queue_redraw()


## Отметить, что ресурс кончился, и запустить таймер до модератора
func _set_empty() -> void:
	if is_empty:
		return
	is_empty = true
	depleted.emit(self)
	get_tree().create_timer(refill_delay).timeout.connect(_call_moderator)


func _call_moderator() -> void:
	if not is_empty or _locked or not is_inside_tree():
		return
	var moderator := _pick_moderator()
	if moderator:
		moderator.request_refill(self)
	else:
		refill()


## Босс опрокинул станцию: ресурс пропал, пока босс жив — не пополнить
func knock_over() -> void:
	is_knocked = true
	is_empty = true
	_locked = true
	depleted.emit(self)
	queue_redraw()


## Босс побеждён (или ушёл): через refill_delay модератор всё уберёт и пополнит
func release_after_boss() -> void:
	if not _locked:
		return
	_locked = false
	get_tree().create_timer(refill_delay).timeout.connect(_call_moderator)


## Босс снёс стол вместе со станцией: прячем её целиком (и обратно)
func set_removed(removed: bool) -> void:
	visible = not removed
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", removed)
	if removed:
		remove_from_group("interactable")
	else:
		add_to_group("interactable")


## Зона, в которой стоит станция (ближайший родитель-Zone), или null
func get_zone() -> Zone:
	var node := get_parent()
	while node != null:
		if node is Zone:
			return node
		node = node.get_parent()
	return null


# Модераторы моей зоны (или без зоны, если своих нет): самый свободный,
# при равенстве — ближайший
func _pick_moderator() -> Moderator:
	var my_zone := get_zone()
	var own: Array[Moderator] = []
	var free_agents: Array[Moderator] = []
	for node in get_tree().get_nodes_in_group("moderator"):
		var moderator := node as Moderator
		if moderator == null:
			continue
		if my_zone != null and moderator.zone == my_zone:
			own.append(moderator)
		elif moderator.zone == null:
			free_agents.append(moderator)
	var candidates := own if not own.is_empty() else free_agents

	var best: Moderator = null
	for moderator in candidates:
		if best == null:
			best = moderator
			continue
		var load_diff := moderator.get_load() - best.get_load()
		var my_dist := global_position.distance_to(moderator.global_position)
		var best_dist := global_position.distance_to(best.global_position)
		if load_diff < 0 or (load_diff == 0 and my_dist < best_dist):
			best = moderator
	return best


## Переопредели в наследнике: вернуть ресурс в «полное» состояние
func _on_refilled() -> void:
	pass
