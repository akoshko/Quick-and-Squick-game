class_name ResourceStation
extends StaticBody2D

## Базовый класс для всего, что может «закончиться»: еда, компьютеры.
##
## Наследник вызывает _set_empty(), когда ресурс кончился. Через
## refill_delay секунд станция зовёт модератора (узел из группы
## "moderator"): он подходит и вызывает refill(). Если модератора
## на уровне нет — станция пополняется сама.
##
## Чтобы сделать новый ресурс: extends ResourceStation, напиши
## interact(player) и переопредели _on_refilled().

signal depleted(station: ResourceStation)
signal refilled(station: ResourceStation)

@export var refill_delay := 5.0
## Что всплывает, когда модератор пополнил (пусто — текст по умолчанию у наследника)
@export var refill_text := ""

var is_empty := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("resource_station")
	Grid.snap(self)


## Пополнить ресурс (вызывает модератор)
func refill() -> void:
	if not is_empty:
		return
	is_empty = false
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
	if not is_empty or not is_inside_tree():
		return
	var moderator := get_tree().get_first_node_in_group("moderator")
	if moderator and moderator.has_method("request_refill"):
		moderator.request_refill(self)
	else:
		refill()


## Переопредели в наследнике: вернуть ресурс в «полное» состояние
func _on_refilled() -> void:
	pass
