class_name Quest
extends Resource

## Одно задание. Список заданий редактируется в инспекторе
## сцены res://src/quests/Quests.tscn.
##
## Предмет на уровне отмечает задание выполненным по его id:
##     Quests.complete("eat_cookie")

## По этому id предметы отмечают задание (у предмета поле quest_id)
@export var id := ""
## Текст в списке заданий слева
@export var title := ""
## Пункты квеста в порядке выполнения. Объекты уровня отмечают их по id.
@export var steps: Array[Quest] = []

## Выполнено ли в текущей игре. Не сохраняется в файл —
## при перезапуске уровня Quests.reset() сбрасывает его.
var done := false

## Временное задание (например, «Победить босса»): добавляется по ходу
## игры через Quests.add_quest() и убирается при перезапуске уровня
var temporary := false


func active_step() -> Quest:
	for step in steps:
		if not step.done:
			return step
	return null
