extends Node2D

const QUEST_ID := "hide_and_seek"
const FIND_ID := "find_missing_participant"
const REPORT_ID := "report_missing_participant"
const INTRO := [
	"Привет! Нужна твоя помощь",
	"У нас пропал один из участников",
	"Помоги его найти, он должен быть где-то на площадке",
]
const THANKS := ["Так вот, где он! Спасибо!"]

@export var moderator: Moderator
@onready var _participant: NPC = $Participant
var _moderator_lines: PackedStringArray
var _searching := false


func _enter_tree() -> void:
	$Participant.sprite_texture = CharacterLook.build("red", "short", "blonde")


func _ready() -> void:
	# прятки идут по личным квестам: в сети тайник открывает клиент игрока у себя
	add_to_group(Player.PERSONAL_GROUP)
	_moderator_lines = moderator.lines
	moderator.dialogue_finished.connect(_on_moderator_dialogue_finished)
	_participant.dialogue_finished.connect(_on_participant_dialogue_finished)
	Quests.changed.connect(_refresh)
	_refresh()


## Сервер: кто действовал с тайником или найденным участником, может засчитать прятки
## (Net.CLIENT_ACHIEVEMENTS — сам квест идёт у клиента)
func witnessed_achievement() -> StringName:
	return &"hide_and_seek"


func interact(_player: Player) -> void:
	if not _searching or _participant.visible:
		return
	remove_from_group("interactable")
	_participant.show()
	_participant.add_to_group("interactable")


func _refresh() -> void:
	var quest := Quests.find(QUEST_ID)
	_searching = quest != null and not Quests.is_done(FIND_ID)
	if not _searching:
		_participant.hide()
		_participant.remove_from_group("interactable")
	if _searching and not _participant.visible:
		add_to_group("interactable")
	else:
		remove_from_group("interactable")

	var lines := _moderator_lines
	if quest == null:
		lines = PackedStringArray(INTRO)
	elif not quest.done and Quests.is_done(FIND_ID):
		lines = PackedStringArray(THANKS)
	if lines != moderator.lines:
		moderator.set_dialogue(lines)


func _on_moderator_dialogue_finished() -> void:
	if Quests.find(QUEST_ID) == null:
		var find_step := Quest.new()
		find_step.id = FIND_ID
		find_step.title = "Найти потерянного участника"
		var report_step := Quest.new()
		report_step.id = REPORT_ID
		report_step.title = "Поговорить с модератором"
		Quests.add_quest(QUEST_ID, "Прятки", true, [find_step, report_step])
	elif Quests.is_done(FIND_ID) and not Quests.is_done(REPORT_ID):
		Quests.complete(REPORT_ID)


func _on_participant_dialogue_finished() -> void:
	if _searching:
		Quests.complete(FIND_ID)
