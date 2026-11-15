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
signal quest_added(quest: Quest)       ## по ходу игры появилось новое задание

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


## Сбросить все задания (вызывается при старте уровня).
## Временные задания (босс и т.п.) убираются совсем.
func reset() -> void:
	if Net.forward_personal(&"Quests", &"reset"):
		return
	for i in range(quests.size() - 1, -1, -1):
		if quests[i].temporary:
			quests.remove_at(i)
	for quest in quests:
		quest.done = false
		for step in quest.steps:
			step.done = false
	if find(selected_quest_id) == null:
		selected_quest_id = quests[0].id if not quests.is_empty() else ""
	selected_quest_changed.emit(selected_quest_id)
	changed.emit()


## Добавить временное задание по ходу игры (например, «Победить босса»).
## make_current — сразу сделать его текущим квестом (виден на экране).
## На сервере задание уходит игрокам (Net.forward_personal) и возвращается null.
func add_quest(id: String, title: String, make_current := true, steps: Array[Quest] = []) -> Quest:
	if Net.is_server() and Net.forward_personal(&"Quests", &"net_add_quest",
			[id, title, make_current, _steps_to_net(steps)]):
		return null
	var existing := find(id)
	if existing:
		return existing
	var quest := Quest.new()
	quest.id = id
	quest.title = title
	quest.steps = steps
	quest.temporary = true
	quests.append(quest)
	quest_added.emit(quest)
	changed.emit()
	if make_current:
		select_quest(id)
	return quest


# Шаги задания для сети: пары [id, title] (Quest — ресурс, по RPC не передаётся)
static func _steps_to_net(steps: Array[Quest]) -> Array:
	var step_data: Array = []
	for step in steps:
		step_data.append([step.id, step.title])
	return step_data


## Клиент: задание, присланное сервером (Net.personal_call); steps — пары [id, title]
func net_add_quest(id: String, title: String, make_current: bool, step_data: Array) -> void:
	var steps: Array[Quest] = []
	for entry in step_data:
		if entry is Array and (entry as Array).size() == 2:
			var step := Quest.new()
			step.id = str(entry[0])
			step.title = str(entry[1])
			steps.append(step)
	add_quest(id, title, make_current, steps)


## Убрать задание из списка. Если оно было текущим — текущим станет
## следующий невыполненный квест.
func remove_quest(id: String) -> void:
	if Net.forward_personal(&"Quests", &"remove_quest", [id]):
		return
	var quest := find(id)
	if quest == null:
		return
	quests.erase(quest)
	if selected_quest_id == id:
		selected_quest_id = ""
		for next_quest in quests:
			if not next_quest.done:
				selected_quest_id = next_quest.id
				break
		selected_quest_changed.emit(selected_quest_id)
	changed.emit()


## Отметить задание выполненным. Повторный вызов ничего не делает.
func complete(id: String) -> void:
	if Net.forward_personal(&"Quests", &"complete", [id]):
		return
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
	var selected := find(selected_quest_id)
	if selected and selected.done and (selected == completed_quest or all_done()):
		_advance_after_completion(selected)
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
	selected_quest_id = ""
	selected_quest_changed.emit(selected_quest_id)


func is_done(id: String) -> bool:
	var quest := find(id)
	return quest != null and quest.done


func select_quest(id: String) -> void:
	if selected_quest_id == id or not quests.any(func(quest: Quest) -> bool: return quest.id == id and not quest.done):
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
