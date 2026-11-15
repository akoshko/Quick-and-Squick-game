class_name ZombieUprising
extends Node2D

## Восстание зомби-модераторов. Начинается, когда сломан компьютер
## ZombieTerminal:
##   • все зомби (группа "zombie_moderator") встают с пуфов и бродят по карте,
##     стараясь разойтись как можно шире; заметив игрока рядом — идут к нему;
##   • пойманный игрок возрождается в клетке respawn_cell (зона перекуса);
##   • по свободным клеткам появляются стаканчики кофе — нужно собрать
##     coffee_needed штук — общий счётчик на всех игроков (плашка вверху);
##   • живой босс тает и исчезает, а пока идёт восстание (и пока зомби
##     укладываются), новые боссы не появляются.
## На сбор кофе — time_limit секунд (время видно на плашке счётчика).
## Не успели — красная надпись «МОДЕРАТОРЫ ПОШЛИ ОТДЫХАТЬ», задание снимается,
## зомби идут спать без победы и без достижения.
## Когда кофе собран — общее конфетти, большая надпись, а каждый, кто
## подобрал хоть один стаканчик, получает достижение «Третий день хакатона».
## Зомби успокаиваются: идут к своим пуфам напрямую, сквозь стены и
## предметы, никого не ловят. Компьютер пока остаётся сломанным. Когда все
## улеглись — головоломка и компьютер сбрасываются.
##
## Сеть (много игроков, сервер): всё, что решает исход — случайные места
## кофе, маршруты зомби, кто пойман, — считает только хозяин сети
## (is_multiplayer_authority(); в одиночной игре это сама игра). Наружу —
## сигналы-события и снимок состояния get_state()/apply_state() для
## подключившихся позже. Стаканчики пронумерованы (id).

signal started
signal coffee_spawned(id: int, cell: Vector2i)
signal coffee_taken(id: int, player: Player)
signal player_caught(player: Player, respawn_position: Vector2)
signal calming_started
signal failed         ## не успели собрать кофе за time_limit
signal calmed_down   ## все зомби снова спят

@export var terminal: ZombieTerminal
@export var room: SokobanRoom
## Куда попадает пойманный игрок. Если на уровне есть маркер точки
## возрождения (группа Player.RESPAWN_GROUP) — берётся он.
@export var respawn_cell := Vector2i(28, 20)
@export var coffee_needed := 25
## Сколько секунд даётся на сбор кофе (не успели — зомби уходят спать без победы)
@export var time_limit := 180.0
@export var coffee_scene: PackedScene = preload("res://src/sokoban/CoffeeCup.tscn")
## Где кофе не появляется (комната с головоломкой — там мешки и тупики)
@export var no_coffee_area := Rect2i(35, 2, 7, 9)
## На скольких клетках (без диагоналей) зомби замечает игрока
@export var chase_radius := 5
@export var catch_distance := 14.0
## Сколько секунд после возрождения зомби не трогают игрока
@export var respawn_grace := 2.0

const QUEST_ID := "zombie_uprising"
const FAIL_TEXT := "МОДЕРАТОРЫ ПОШЛИ ОТДЫХАТЬ"
const FAIL_COLOR := Color(1, 0.3, 0.28)
const ACHIEVEMENT := &"zombie_apocalypse"
const COFFEE_STEP_ID := "collect_coffee"
const TARGET_SAMPLES := 12   # из скольких случайных клеток зомби выбирает, куда идти

enum State { IDLE, ACTIVE, CALMING }

var state := State.IDLE
var collected := 0
var time_left := 0.0
var is_failed := false   ## восстание закончилось поражением (не успели)
var _astar: AStarGrid2D
var _walkable: Array[Vector2i] = []
var _cups := {}      # id -> CoffeeCup
var _next_cup_id := 1
var _coffee_step: Quest
var _targets := {}   # зомби -> клетка, куда он идёт (чтобы расходиться)
var _grace := {}     # игрок -> до какого времени (мс) его не ловят
var _takers := {}    # игрок -> сколько стаканчиков подобрал (для достижения)
var _counter: CoffeeCounter


func _ready() -> void:
	add_to_group("zombie_uprising")
	var marker := get_tree().get_first_node_in_group(Player.RESPAWN_GROUP) as Node2D
	if marker:
		respawn_cell = Grid.world_to_cell(self, marker.global_position)
	if terminal:
		terminal.uprising_started.connect(_on_uprising_started)


func is_active() -> bool:
	return state == State.ACTIVE


## Пока зомби не спят — босс-ивенты на паузе (см. BossDirector)
func blocks_boss_events() -> bool:
	return state != State.IDLE


func _zombies() -> Array[ZombieModerator]:
	var result: Array[ZombieModerator] = []
	for node in get_tree().get_nodes_in_group("zombie_moderator"):
		if node is ZombieModerator:
			result.append(node)
	return result


func _players() -> Array[Player]:
	var result: Array[Player] = []
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player and player.visible:
			result.append(player)
	return result


func _on_uprising_started() -> void:
	if is_multiplayer_authority():
		start()


## Начать восстание (сервер; клиенты получают это через apply_state)
func start() -> void:
	if state != State.IDLE:
		return
	state = State.ACTIVE
	collected = 0
	time_left = time_limit
	is_failed = false
	_targets.clear()
	_grace.clear()
	_takers.clear()
	# Боссы и зомби вместе не бывают: живой босс тает и исчезает
	get_tree().call_group("boss_director", "dismiss_boss")
	_build_grid()
	_add_quest()
	if is_instance_valid(_counter):
		_counter.queue_free()
	_counter = CoffeeCounter.new()
	add_child(_counter)
	_counter.set_count(collected, coffee_needed)
	_counter.set_time_left(time_left)
	if is_multiplayer_authority():
		_spawn_coffee()
	for zombie in _zombies():
		zombie.start_roaming(self)
	# Вернулся на точку возрождения (пойман или нажал «Я застрял») — недолго не трогаем
	for player in _players():
		if not player.respawned.is_connected(_on_player_respawned):
			player.respawned.connect(_on_player_respawned.bind(player))
	started.emit()


func _on_player_respawned(player: Player) -> void:
	_grace[player] = Time.get_ticks_msec() + int(respawn_grace * 1000.0)


# --- Карта для зомби: стены и столы, но не мешки и не персонажи ---

func _build_grid() -> void:
	var layer := Grid.get_layer(self)
	_astar = AStarGrid2D.new()
	_astar.region = layer.get_used_rect()
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	_walkable.clear()
	for x in range(_astar.region.position.x, _astar.region.end.x):
		for y in range(_astar.region.position.y, _astar.region.end.y):
			var cell := Vector2i(x, y)
			if Grid.is_solid_cell(self, cell):
				_astar.set_point_solid(cell)
	# Только клетки, связанные с зоной перекуса (без замурованных уголков)
	var seen := {respawn_cell: true}
	var queue: Array[Vector2i] = [respawn_cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		_walkable.append(cell)
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + dir
			if not seen.has(next) and _astar.is_in_boundsv(next) and not _astar.is_point_solid(next):
				seen[next] = true
				queue.append(next)


## Путь для зомби: к игроку рядом или в самое «пустое» от других зомби место
func next_path(zombie: ZombieModerator) -> Array[Vector2i]:
	var here := Grid.world_to_cell(self, zombie.global_position)
	var from := _nearest_walkable(here)
	var player := _nearest_player(zombie, chase_radius)
	var target := Grid.world_to_cell(self, player.global_position) if player else _spread_target(zombie)
	_targets[zombie] = target
	var path: Array[Vector2i] = _astar.get_id_path(from, _nearest_walkable(target))
	if not path.is_empty() and path[0] == here:
		path.remove_at(0)
	if player:
		path = path.slice(0, 2)   # за игроком — короткими отрезками, чтобы успевать сворачивать
	return path


## Есть ли рядом с зомби игрок, за которым стоит погнаться
func sees_player(zombie: ZombieModerator) -> bool:
	return _nearest_player(zombie, chase_radius) != null


func _spread_target(zombie: ZombieModerator) -> Vector2i:
	var others: Array[Vector2i] = []
	for other in _zombies():
		if other != zombie:
			others.append(_targets.get(other, Grid.world_to_cell(self, other.global_position)))
	var best: Vector2i = _walkable.pick_random()
	var best_score := -1.0
	for i in TARGET_SAMPLES:
		var cell: Vector2i = _walkable.pick_random()
		var nearest := 1000
		for other in others:
			nearest = mini(nearest, absi(other.x - cell.x) + absi(other.y - cell.y))
		var score := float(nearest) + randf() * 2.0
		if score > best_score:
			best_score = score
			best = cell
	return best


func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
		return cell
	var best := cell
	var best_dist := 1 << 30
	for other in _walkable:
		var d := absi(other.x - cell.x) + absi(other.y - cell.y)
		if d < best_dist:
			best_dist = d
			best = other
	return best


func _nearest_player(zombie: ZombieModerator, radius: int) -> Player:
	var zombie_cell := Grid.world_to_cell(self, zombie.global_position)
	var best: Player = null
	var best_dist := radius + 1
	for player in _players():
		if _in_grace(player):
			continue
		var cell := Grid.world_to_cell(self, player.global_position)
		var d := absi(cell.x - zombie_cell.x) + absi(cell.y - zombie_cell.y)
		if d < best_dist:
			best_dist = d
			best = player
	return best


func _in_grace(player: Player) -> bool:
	return _grace.get(player, 0) > Time.get_ticks_msec()


## Зомби проверяет, не задел ли он игрока (только на сервере)
func check_catch(zombie: ZombieModerator) -> void:
	if state != State.ACTIVE or not is_multiplayer_authority():
		return
	for player in _players():
		if not _in_grace(player) and player.global_position.distance_to(zombie.global_position) < catch_distance:
			_catch(player)


func _catch(player: Player) -> void:
	_grace[player] = Time.get_ticks_msec() + int(respawn_grace * 1000.0)
	var spawn := Grid.cell_to_world(self, respawn_cell)
	FloatingText.spawn(self, player.global_position + Vector2(0, -20), "Поймали!", Color(1, 0.4, 0.35))
	# Своего персонажа переставляем сразу; сетевого — переставит его клиент
	# по событию player_caught (сетевой код вызовет у него respawn_at)
	if player.is_local:
		player.respawn_at(spawn)
	player_caught.emit(player, spawn)


# --- Кофе ---

func _add_quest() -> void:
	Quests.remove_quest(QUEST_ID)
	_coffee_step = Quest.new()
	_coffee_step.id = COFFEE_STEP_ID
	_coffee_step.title = "Собрать кофе"
	var steps: Array[Quest] = [_coffee_step]
	Quests.add_quest(QUEST_ID, "Успокоить зомби-модераторов", true, steps)


func _spawn_coffee() -> void:
	var busy := {}
	for node in get_tree().current_scene.get_children():
		if node is CollisionObject2D:
			busy[Grid.world_to_cell(self, (node as Node2D).global_position)] = true
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Node2D:
			busy[Grid.world_to_cell(self, (node as Node2D).global_position)] = true
	for zombie in _zombies():
		busy[zombie.get_home_cell()] = true
	for player in _players():
		busy[Grid.world_to_cell(self, player.global_position)] = true
	var cells := _walkable.filter(func(cell: Vector2i) -> bool:
		return not busy.has(cell) and not no_coffee_area.has_point(cell) and cell != respawn_cell)
	cells.shuffle()
	for i in mini(coffee_needed, cells.size()):
		var id := _next_cup_id
		_next_cup_id += 1
		spawn_coffee_at(id, cells[i])
		coffee_spawned.emit(id, cells[i])


## Поставить стаканчик (сервер — сам, клиент — по событию coffee_spawned)
func spawn_coffee_at(id: int, cell: Vector2i) -> void:
	if _cups.has(id):
		return
	var cup := coffee_scene.instantiate() as CoffeeCup
	cup.id = id
	cup.uprising = self
	add_child(cup)
	cup.global_position = Grid.cell_to_world(self, cell)
	_cups[id] = cup


## Игрок наступил на стаканчик (решает сервер)
func take_coffee(id: int, player: Player) -> void:
	if state != State.ACTIVE or not _cups.has(id) or not is_multiplayer_authority():
		return
	coffee_taken_by(id, player)
	coffee_taken.emit(id, player)
	set_collected(collected + 1)
	if collected >= coffee_needed:
		calm_down()


## Стаканчик взял игрок (сервер — сам, клиент — по событию coffee_taken)
func coffee_taken_by(id: int, player: Player) -> void:
	remove_coffee(id, true)
	if is_instance_valid(player):
		_takers[player] = _takers.get(player, 0) + 1


## Убрать стаканчик (сервер — сам, клиент — по событию coffee_taken)
func remove_coffee(id: int, with_effect := true) -> void:
	var cup: CoffeeCup = _cups.get(id)
	_cups.erase(id)
	if is_instance_valid(cup):
		cup.vanish(with_effect)


func set_collected(value: int) -> void:
	collected = value
	if is_instance_valid(_counter):
		_counter.set_count(collected, coffee_needed)


# Отсчёт времени: идёт у всех, а решает, что время вышло, только сервер
func _process(delta: float) -> void:
	if state != State.ACTIVE:
		return
	time_left = maxf(0.0, time_left - delta)
	if is_instance_valid(_counter):
		_counter.set_time_left(time_left)
	if time_left <= 0.0 and is_multiplayer_authority():
		fail()


# --- Успокоились ---

## Кофе собран: зомби идут спать (сервер; клиентам — через apply_state)
func calm_down() -> void:
	if state != State.ACTIVE:
		return
	state = State.CALMING
	for id in _cups.keys():
		remove_coffee(id, false)
	Quests.complete(COFFEE_STEP_ID)
	_celebrate()
	for zombie in _zombies():
		zombie.go_home()
	calming_started.emit()


## Время вышло: зомби уходят спать без победы и без достижения
## (сервер; клиентам — через apply_state)
func fail() -> void:
	if state != State.ACTIVE:
		return
	state = State.CALMING
	is_failed = true
	for id in _cups.keys():
		remove_coffee(id, false)
	Quests.remove_quest(QUEST_ID)
	var banner := get_tree().get_first_node_in_group("boss_bar") as BossBar
	if banner:
		banner.show_banner(FAIL_TEXT, FAIL_COLOR)
	if is_instance_valid(_counter):
		_counter.fade_out()
	Sfx.play(&"crash", 0.0, 0.0, 0.7)
	for zombie in _zombies():
		zombie.go_home()
	failed.emit()
	calming_started.emit()


# Победа видна всем: конфетти, большая надпись, достижение участникам
func _celebrate() -> void:
	Confetti.burst(self)
	var banner := get_tree().get_first_node_in_group("boss_bar") as BossBar
	if banner:
		banner.show_banner("ЗОМБИ-МОДЕРАТОРЫ УСПОКОИЛИСЬ")
	if is_instance_valid(_counter):
		_counter.fade_out()
	# Каждый клиент выдаёт достижение своему персонажу, если тот подобрал кофе
	for player: Player in _takers:
		if is_instance_valid(player) and player.is_local:
			GameManager.unlock_achievement(ACHIEVEMENT)
			break


## Зомби улёгся на свой пуф
func zombie_asleep(_zombie: ZombieModerator) -> void:
	if state != State.CALMING:
		return
	for zombie in _zombies():
		if not zombie.asleep:
			return
	state = State.IDLE
	if room and is_multiplayer_authority():
		room.reset_bags()
	if terminal:
		terminal.repair()
	calmed_down.emit()


# --- Снимок состояния для подключившихся игроков ---

func get_state() -> Dictionary:
	var cups := {}
	for id: int in _cups:
		cups[id] = Grid.world_to_cell(self, (_cups[id] as CoffeeCup).global_position)
	return {"state": state, "collected": collected, "cups": cups, "time_left": time_left, "failed": is_failed}


func apply_state(data: Dictionary) -> void:
	var new_state: int = data.get("state", State.IDLE)
	if new_state != State.IDLE and state == State.IDLE:
		start()
	set_collected(data.get("collected", 0))
	var cups: Dictionary = data.get("cups", {})
	for id: int in _cups.keys():
		if not cups.has(id):
			remove_coffee(id, false)
	for id: int in cups:
		spawn_coffee_at(id, cups[id])
	time_left = data.get("time_left", time_left)
	if new_state == State.CALMING and state == State.ACTIVE:
		if data.get("failed", false):
			fail()
		else:
			calm_down()
