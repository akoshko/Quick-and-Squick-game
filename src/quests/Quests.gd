extends Node

## Список заданий (autoload "Quests"). Доступен из любого скрипта:
##     Quests.complete("talk_npc")
##     Quests.is_done("eat_cookie")
##
## Сами задания задаются в инспекторе: открой Quests.tscn и
## редактируй массив quests (добавь элемент → New Quest → id и текст).

signal quest_completed(quest: Quest)   ## одно задание выполнено
signal changed                         ## список изменился (для UI)
signal all_completed                   ## выполнены все задания

@export var quests: Array[Quest] = []


## Сбросить все задания (вызывается при старте уровня)
func reset() -> void:
	for quest in quests:
		quest.done = false
	changed.emit()


## Отметить задание выполненным. Повторный вызов ничего не делает.
func complete(id: String) -> void:
	var quest := find(id)
	if quest == null:
		push_warning("Quests: нет задания с id \"%s\"" % id)
		return
	if quest.done:
		return
	quest.done = true
	quest_completed.emit(quest)
	changed.emit()
	if all_done():
		all_completed.emit()


func is_done(id: String) -> bool:
	var quest := find(id)
	return quest != null and quest.done


func all_done() -> bool:
	for quest in quests:
		if not quest.done:
			return false
	return true


func find(id: String) -> Quest:
	for quest in quests:
		if quest.id == id:
			return quest
	return null
