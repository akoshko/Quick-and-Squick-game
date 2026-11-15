class_name BossDirector
extends Node

## Временное событие «босс». Раз в interval секунд выпускает мешка-мимика
## в случайной точке BossSpawn (дочерние узлы; не ту же, что в прошлый
## раз). Босс сидит, пока его не победят, и пока он жив, новый не
## появляется: отсчёт до следующего начинается только после победы.
##
## При появлении: ломает локацию точки, показывает полоску здоровья с
## титулом и добавляет задание «Победить босса в …».
## Пока идёт другое большое событие (восстание зомби-модераторов) —
## отсчёт стоит и боссы не появляются.
## В отладочной сборке F9 — выпустить босса прямо сейчас.
##
## Сеть: босс один на всех и живёт на сервере. Клиенты получают состояние директора
## (net_state: номер босса, точка, вид, здоровье, чем кончился) и по нему показывают своего
## «босса-изображение», полоску, задание и надпись; удар (E) выполняет сервер.
## Достижение получают игроки, нанёсшие урон на сервере.

const BOSS_SCENE := preload("res://src/boss/BeanBagBoss.tscn")
const FINISHED_QUEST_LINGER := 6.0   # с: столько выполненное задание босса висит в списке

# Ключи net_state
const KEY_NUMBER := "boss_number"
const KEY_END_REASON := "end_reason"
const KEY_SPAWN := "spawn"            # есть, только пока босс жив
const KEY_SKIN := "skin"
const KEY_HP := "hp"
const KEY_MAX_HP := "max_hp"

## Чем кончился босс (уходит клиентам в net_state)
enum EndReason { NONE, DEFEATED, LEFT, DISMISSED, RESTART }

@export var interval := 60.0      ## секунд после победы до следующего босса
@export var first_delay := 60.0   ## когда появится первый босс
@export var boss_hp := 50
@export var boss_lifetime := 0.0  ## сколько ждёт, прежде чем уползти (0 — сидит, пока не победят)

var _time_left := 0.0
var _boss: BeanBagBoss
var _spawn: BossSpawn
var _last_spawn: BossSpawn
var _quest_id := ""
var _count := 0
var _bar: BossBar
var _end_reason := EndReason.NONE   # чем кончился последний босс
var _view_count := 0                # клиент: номер босса, которого сейчас показываем
var _participants: Dictionary[String, bool] = {}


func _ready() -> void:
	add_to_group("boss_director")
	add_to_group(WorldSync.GROUP)
	_time_left = first_delay
	_bar = BossBar.new()
	add_child(_bar)


func _process(delta: float) -> void:
	if not Net.runs_world():
		return   # у клиентов босс появляется по состоянию с сервера
	if is_instance_valid(_boss) or GameManager.state == GameManager.GameState.PAUSED or _blocked():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		spawn_boss()


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F9 and not is_instance_valid(_boss):
		spawn_boss()


# Другое событие просит не выпускать боссов (например, восстание зомби)
func _blocked() -> bool:
	for node in get_tree().get_nodes_in_group("zombie_uprising"):
		if node.has_method("blocks_boss_events") and node.blocks_boss_events():
			return true
	return false


## Выпустить босса сейчас: в точке at или (если не указана) в случайной.
## В сети — только на сервере (у клиентов босс появляется по состоянию).
func spawn_boss(at: BossSpawn = null) -> void:
	if not Net.runs_world() or is_instance_valid(_boss) or _blocked():
		return
	if at == null:
		var spawns: Array[BossSpawn] = []
		for child in get_children():
			if child is BossSpawn:
				spawns.append(child)
		if spawns.is_empty():
			push_warning("BossDirector: нет точек BossSpawn")
			return
		if spawns.size() > 1 and _last_spawn in spawns:
			spawns.erase(_last_spawn)
		at = spawns.pick_random()
	_spawn = at
	_last_spawn = _spawn

	_spawn.apply()   # сначала ломаем локацию (снесённый стол освобождает место)
	_boss = BOSS_SCENE.instantiate()
	_boss.max_hp = boss_hp
	_boss.lifetime = boss_lifetime
	_boss.title = _spawn.boss_title
	_boss.position = _spawn.global_position
	_boss.hp_changed.connect(_on_boss_hp_changed)
	_boss.hit_by.connect(_on_boss_hit)
	_boss.defeated.connect(_on_defeated)
	_boss.left.connect(_on_left)
	get_tree().current_scene.add_child(_boss)   # в сцену уровня — для y-sort

	_count += 1
	_participants.clear()
	_end_reason = EndReason.NONE
	_show_spawn(_count, _spawn, boss_hp)


## Убрать текущего босса (если есть) без победы и сразу выпустить нового (админ-API).
func restart_boss() -> void:
	if not Net.runs_world():
		return
	if is_instance_valid(_boss):
		_show_end(EndReason.RESTART)
		_boss.queue_free()
		_end_event(EndReason.RESTART)
	spawn_boss()


func _on_boss_hp_changed(hp: int, max_hp: int) -> void:
	_show_hp(hp, max_hp)


func _on_defeated() -> void:
	if Net.is_server():
		for token in _participants:
			Net.award_player_achievement(token, &"boss_victory")
	else:
		GameManager.unlock_achievement(&"boss_victory")
	_show_end(EndReason.DEFEATED)
	_end_event(EndReason.DEFEATED)


func _on_boss_hit(player: Player) -> void:
	if Net.server == null or not is_instance_valid(player):
		return
	var token := Net.server.registry.token_for_player(String(player.name))
	if token != "":
		_participants[token] = true


## Убрать живого босса без победы (началось другое большое событие —
## восстание зомби): босс тает, задание снимается, локация восстанавливается
func dismiss_boss() -> void:
	if not Net.runs_world() or not is_instance_valid(_boss):
		return
	var boss := _boss
	boss.defeated.disconnect(_on_defeated)
	boss.left.disconnect(_on_left)
	_show_end(EndReason.DISMISSED)
	boss.fade_away()
	_end_event(EndReason.DISMISSED)


func _on_left() -> void:
	_show_end(EndReason.LEFT)
	_end_event(EndReason.LEFT)


func _end_event(reason: EndReason) -> void:
	if _spawn:
		_spawn.release()
	_spawn = null
	_boss = null
	_end_reason = reason
	_time_left = interval


# --- Что видит игрок: задание, полоска, надпись. Личное — у сервера этого нет. ---

func _show_spawn(count: int, spawn: BossSpawn, max_hp: int) -> void:
	if not Net.shows_personal_ui():
		return
	_quest_id = "boss_%d" % count
	Quests.add_quest(_quest_id, "Победить босса в " + spawn.location_name)
	_bar.show_boss(spawn.boss_title, max_hp)


func _show_hp(hp: int, max_hp: int) -> void:
	if Net.shows_personal_ui():
		_bar.set_hp(hp, max_hp)


func _show_end(reason: EndReason) -> void:
	if not Net.shows_personal_ui():
		return
	_bar.hide_boss()
	match reason:
		EndReason.DEFEATED:
			Quests.complete(_quest_id)
			_bar.show_banner("ВЕЛИКИЙ ВРАГ ПОВЕРЖЕН")
			# Выполненное задание босса недолго висит в списке, потом убирается
			get_tree().create_timer(FINISHED_QUEST_LINGER).timeout.connect(Quests.remove_quest.bind(_quest_id))
		EndReason.LEFT:
			Quests.remove_quest(_quest_id)
			_bar.show_banner("Мешок-мимик уполз…", Color(0.75, 0.75, 0.82))
		_:
			Quests.remove_quest(_quest_id)


# --- Сеть ---

## Состояние для клиентов: номер босса и чем кончился прошлый; пока босс жив — где он,
## какой вид и сколько здоровья
func net_state() -> Dictionary:
	var state := {KEY_NUMBER: _count, KEY_END_REASON: _end_reason}
	if is_instance_valid(_boss) and _spawn != null:
		state[KEY_SPAWN] = String(_spawn.name)
		state[KEY_SKIN] = _boss.skin_index
		state[KEY_HP] = _boss.hp
		state[KEY_MAX_HP] = _boss.max_hp
	return state


## Клиент: показать босса с сервера — появление, удары, конец (как и почему)
func apply_net_state(state: Dictionary) -> void:
	var number: int = state.get(KEY_NUMBER, 0)
	var alive := state.has(KEY_SPAWN)
	if is_instance_valid(_boss) and (not alive or number != _view_count):
		_end_view(state, number)
	if not alive:
		return
	if not is_instance_valid(_boss):
		_spawn_view(state, number)
	elif state.get(KEY_HP, _boss.hp) != _boss.hp:
		_boss.net_set_hp(state.get(KEY_HP, _boss.hp))
		_show_hp(_boss.hp, _boss.max_hp)


# Клиент: показанный босс кончился — так же, как на сервере
func _end_view(state: Dictionary, number: int) -> void:
	var reason: EndReason = state.get(KEY_END_REASON, EndReason.NONE)
	if number != _view_count:
		# номер сменился, а конца старого мы не видели — значит, сервер перезапустил босса
		reason = EndReason.RESTART
	_show_end(reason)
	match reason:
		EndReason.DEFEATED:
			_boss.net_defeat()
		EndReason.LEFT:
			_boss.net_leave()
		_:
			_boss.fade_away()
	_boss = null


# Клиент: показать живого босса с сервера — изображение, полоску и задание
func _spawn_view(state: Dictionary, number: int) -> void:
	var spawn := get_node_or_null(NodePath(str(state.get(KEY_SPAWN, "")))) as BossSpawn
	if spawn == null:
		return
	_view_count = number
	_boss = BOSS_SCENE.instantiate()
	_boss.net_view = true
	_boss.skin_index = state.get(KEY_SKIN, -1)
	_boss.max_hp = state.get(KEY_MAX_HP, boss_hp)
	_boss.title = spawn.boss_title
	_boss.position = spawn.global_position
	get_tree().current_scene.add_child(_boss)
	_boss.hp = state.get(KEY_HP, _boss.max_hp)
	_show_spawn(number, spawn, _boss.max_hp)
	_show_hp(_boss.hp, _boss.max_hp)
