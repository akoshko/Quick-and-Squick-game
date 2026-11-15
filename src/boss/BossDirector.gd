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

const BOSS_SCENE := preload("res://src/boss/BeanBagBoss.tscn")

@export var interval := 60.0      ## секунд после победы до следующего босса
@export var first_delay := 60.0   ## когда появится первый босс
@export var boss_hp := 3
@export var boss_lifetime := 0.0  ## сколько ждёт, прежде чем уползти (0 — сидит, пока не победят)

var _time_left := 0.0
var _boss: BeanBagBoss
var _spawn: BossSpawn
var _last_spawn: BossSpawn
var _quest_id := ""
var _count := 0
var _bar: BossBar


func _ready() -> void:
	add_to_group("boss_director")
	_time_left = first_delay
	_bar = BossBar.new()
	add_child(_bar)


func _process(delta: float) -> void:
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


## Выпустить босса сейчас: в точке at или (если не указана) в случайной
func spawn_boss(at: BossSpawn = null) -> void:
	if is_instance_valid(_boss) or _blocked():
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
	_boss.hp_changed.connect(_bar.set_hp)
	_boss.defeated.connect(_on_defeated)
	_boss.left.connect(_on_left)
	get_tree().current_scene.add_child(_boss)   # в сцену уровня — для y-sort

	_count += 1
	_quest_id = "boss_%d" % _count
	Quests.add_quest(_quest_id, "Победить босса в " + _spawn.location_name)
	_bar.show_boss(_spawn.boss_title, boss_hp)


func _on_defeated() -> void:
	Quests.complete(_quest_id)
	GameManager.unlock_achievement(&"boss_victory")
	_bar.hide_boss()
	_bar.show_banner("ВЕЛИКИЙ ВРАГ ПОВЕРЖЕН")
	_end_event()
	# Выполненное задание босса недолго висит в списке, потом убирается
	var finished_id := _quest_id
	get_tree().create_timer(6.0).timeout.connect(Quests.remove_quest.bind(finished_id))


## Убрать живого босса без победы (началось другое большое событие —
## восстание зомби): босс тает, задание снимается, локация восстанавливается
func dismiss_boss() -> void:
	if not is_instance_valid(_boss):
		return
	var boss := _boss
	boss.defeated.disconnect(_on_defeated)
	boss.left.disconnect(_on_left)
	Quests.remove_quest(_quest_id)
	_bar.hide_boss()
	boss.fade_away()
	_end_event()


func _on_left() -> void:
	Quests.remove_quest(_quest_id)
	_bar.hide_boss()
	_bar.show_banner("Мешок-мимик уполз…", Color(0.75, 0.75, 0.82))
	_end_event()


func _end_event() -> void:
	if _spawn:
		_spawn.release()
	_spawn = null
	_boss = null
	_time_left = interval
