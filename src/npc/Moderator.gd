class_name Moderator
extends NPC

## Модератор хакатона. Стоит на своём посту (там, где его поставили на
## уровне). Когда ресурс заканчивается (съели печенье/яблоки, завис
## ноутбук), через 5 секунд ресурс зовёт модератора: он сам находит
## путь по клеткам, подходит, пополняет/чинит и возвращается на пост.
## Несколько вызовов встают в очередь.
##
## С ним можно поговорить, как с обычным NPC (он наследует NPC).

@export var walk_speed := 90.0   ## пикселей в секунду
@export var work_time := 0.8     ## сколько секунд «чинит/докладывает»

enum State { IDLE, WALKING, WORKING }

var _state := State.IDLE
var _jobs: Array[ResourceStation] = []   # очередь вызовов
var _job: ResourceStation                # текущий вызов
var _path: Array[Vector2i] = []
var _goals: Array[Vector2i] = []
var _step_target := Vector2.ZERO
var _stepping := false
var _wait := 0.0
var _post := Vector2i.ZERO
var _bob_phase := 0.0
var _bob := 0.0


func _ready() -> void:
	super()
	add_to_group("moderator")
	_post = _cell()


## Вызывается ресурсом, который закончился
func request_refill(station: ResourceStation) -> void:
	if station == _job or station in _jobs:
		return
	_jobs.append(station)
	FloatingText.spawn(self, global_position + Vector2(0, -26), "Иду!", Color(1, 0.8, 0.4))


func _physics_process(delta: float) -> void:
	_update_bob(delta)
	if _wait > 0.0:
		_wait -= delta
		return
	match _state:
		State.IDLE:
			if not _jobs.is_empty():
				_start_job(_jobs.pop_front())
			elif _cell() != _post:
				var home: Array[Vector2i] = [_post]
				_walk_to(home)
		State.WALKING:
			_walk(delta)
		State.WORKING:
			_finish_job()


func _cell() -> Vector2i:
	return Grid.world_to_cell(self, global_position)


func _start_job(station: ResourceStation) -> void:
	if not is_instance_valid(station) or not station.is_empty:
		return
	_job = station
	# Подходим к любой свободной соседней клетке ресурса
	var station_cell := Grid.world_to_cell(self, station.global_position)
	var goals: Array[Vector2i] = []
	for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		goals.append(station_cell + dir)
	if _cell() in goals:
		_arrive()
	elif not _walk_to(goals):
		# Пути нет (например, проход загородили) — попробуем чуть позже
		_jobs.append(station)
		_job = null
		_wait = 1.0


func _walk_to(goals: Array[Vector2i]) -> bool:
	_goals = goals
	_path = Grid.find_path(self, _cell(), goals, _blockers())
	if _path.is_empty():
		_wait = 1.0
		return false
	_state = State.WALKING
	return true


func _walk(delta: float) -> void:
	# Идём к центру следующей клетки
	if _stepping:
		global_position = global_position.move_toward(_step_target, walk_speed * delta)
		if global_position != _step_target:
			return
		_stepping = false

	# Стоим ровно в клетке. Шли домой, а пришёл вызов — переключаемся
	if _job == null and not _jobs.is_empty():
		_path.clear()
		_state = State.IDLE
		return
	if _path.is_empty():
		_arrive()
		return

	var target := Grid.cell_to_world(self, _path[0])
	if test_move(global_transform, target - global_position):
		# На пути предмет (например, мешок подвинули) — ждём и ищем обход
		_wait = 0.4
		var detour := Grid.find_path(self, _cell(), _goals, _blockers())
		if not detour.is_empty():
			_path = detour
		return
	_path.remove_at(0)
	_step_target = target
	_stepping = true


func _arrive() -> void:
	if _job:
		_state = State.WORKING
		_wait = work_time
	else:
		_state = State.IDLE


func _finish_job() -> void:
	if is_instance_valid(_job) and _job.is_empty:
		_job.refill()
	_job = null
	_state = State.IDLE


# Клетки, занятые предметами мира (NPC, мешки) — их обходим.
# Персонажей (слой 2: игроки) не считаем — сквозь них можно пройти.
func _blockers() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for node in get_tree().current_scene.get_children():
		if node == self or not (node is CollisionObject2D) or not node.visible:
			continue
		if ((node as CollisionObject2D).collision_layer & 1) == 0:
			continue
		cells.append(Grid.world_to_cell(self, node.global_position))
	return cells


# Покачивание при ходьбе
func _update_bob(delta: float) -> void:
	var target_bob := 0.0
	if _stepping:
		_bob_phase += delta * 14.0
		target_bob = -absf(sin(_bob_phase)) * 2.5
	else:
		_bob_phase = 0.0
	if not is_equal_approx(_bob, target_bob):
		_bob = target_bob
		queue_redraw()


# Выглядит как NPC, но в оранжевой футболке и с бейджем модератора
func _draw() -> void:
	draw_set_transform(Vector2(0, _bob), 0.0, Vector2.ONE)
	super()
	draw_line(Vector2(-4, -5), Vector2(-1, -1), Color(0.15, 0.3, 0.75), 1.0)   # шнурок
	draw_line(Vector2(4, -5), Vector2(1, -1), Color(0.15, 0.3, 0.75), 1.0)
	draw_rect(Rect2(-2.5, -1.5, 5, 4), Color(1, 1, 1))                         # бейдж
	draw_rect(Rect2(-2, -1, 4, 1), Color(0.9, 0.25, 0.2))
