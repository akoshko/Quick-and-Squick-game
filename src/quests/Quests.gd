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
signal selected_quest_changed(quest_id: String)

const COMPLETION_DISPLAY_TIME := 0.9

@export var quests: Array[Quest] = []
var selected_quest_id := ""


func _ready() -> void:
	var ids := {}
	for quest in quests:
		for entry in [quest] + quest.steps:
			_validate_id(entry.id, ids)


func _validate_id(id: String, ids: Dictionary) -> void:
	if id.is_empty():
		push_warning("Quests: у задания не задан id")
	elif ids.has(id):
		push_warning("Quests: повторяется id задания \"%s\"" % id)
	ids[id] = true


## Сбросить все задания (вызывается при старте уровня)
func reset() -> void:
	for quest in quests:
		quest.done = false
		for step in quest.steps:
			step.done = false
	if find(selected_quest_id) == null:
		selected_quest_id = quests[0].id if not quests.is_empty() else ""
	selected_quest_changed.emit(selected_quest_id)
	changed.emit()


## Отметить задание выполненным. Повторный вызов ничего не делает.
func complete(id: String) -> void:
	var quest := find(id)
	if quest == null:
		push_warning("Quests: нет задания с id \"%s\"" % id)
		return
	if quest.done or not quest.steps.is_empty():
		return
	var parent_quest: Quest
	for parent in quests:
		if quest in parent.steps:
			if parent.active_step() != quest:
				return
			parent_quest = parent
			break

	quest.done = true
	quest_completed.emit(quest)
	var completed_quest := quest
	if parent_quest and parent_quest.active_step() == null:
		parent_quest.done = true
		quest_completed.emit(parent_quest)
		completed_quest = parent_quest
	if completed_quest.id == selected_quest_id:
		_advance_after_completion(completed_quest)
	changed.emit()
	if all_done():
		all_completed.emit()


func _advance_after_completion(completed_quest: Quest) -> void:
	await get_tree().create_timer(COMPLETION_DISPLAY_TIME, false).timeout
	if selected_quest_id != completed_quest.id or not completed_quest.done:
		return
	for next_quest in quests:
		if not next_quest.done:
			select_quest(next_quest.id)
			return


func is_done(id: String) -> bool:
	var quest := find(id)
	return quest != null and quest.done


func select_quest(id: String) -> void:
	if not quests.any(func(quest: Quest) -> bool: return quest.id == id) or selected_quest_id == id:
		return
	selected_quest_id = id
	selected_quest_changed.emit(id)


func all_done() -> bool:
	if quests.is_empty():
		return false
	for quest in quests:
		if not quest.done:
			return false
	return true


func find(id: String) -> Quest:
	for quest in quests:
		if quest.id == id:
			return quest
		for step in quest.steps:
			if step.id == id:
				return step
	return null
