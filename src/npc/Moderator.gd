class_name Moderator
extends NPC

## Модератор хакатона. Стоит на своём посту (там, где его поставили на
## уровне). Когда ресурс заканчивается (съели печенье/яблоки, завис
## ноутбук), через 5 секунд ресурс зовёт модератора: он сам находит
## путь по клеткам, подходит, пополняет/чинит и возвращается на пост.
## Несколько вызовов встают в очередь.
##
## Модератор работает на свою зону (поле zone): ресурс зовёт модератора
## своей зоны — того, у кого меньше вызовов, а при равенстве ближайшего.
## Модератор без зоны отвечает за ресурсы, у которых нет своего модератора.
##
## Ещё модератора можно отправить по поручению (send_on_errand): он дойдёт
## до нужного места, сделает дело и вернётся на пост. Поручение важнее вызовов.
##
## С ним можно поговорить, как с обычным NPC (он наследует NPC).

## На какую зону работает (пусто — на ресурсы без своих модераторов)
@export var zone: Zone
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
var _stuck := 0                          # сколько раз подряд упёрлись в следующую клетку
var _avoid: Array[Vector2i] = []         # клетки, в которые физически не пройти (на этот поход)
const STUCK_LIMIT := 5                   # ≈2 секунды упираемся — ищем обход мимо этой клетки
const MAX_ATTEMPTS := 3                  # столько раз не смог подойти — чинит удалённо
const VIEW_STOP_DELAY := 0.15            # клиент: столько секунд позиция стоит — модератор остановился
var _attempts := {}                      # станция -> сколько раз не удалось подойти
var _post := Vector2i.ZERO
var _errand_goals: Array[Vector2i] = []  # куда идти по поручению
var _errand_done := Callable()           # что сделать на месте (пусто — поручения нет)
var _on_errand := false                  # идём (или работаем) по поручению
var _errand_attempts := 0
var _bob_phase := 0.0
var _bob := 0.0
var _view_last := Vector2.ZERO           # клиент: где был в прошлом кадре (позиция приходит с сервера)
var _view_still := 0.0                   # клиент: сколько секунд позиция не менялась


func _ready() -> void:
	super()
	add_to_group("moderator")
	_post = _cell()
	_view_last = global_position


## Поручение: дойти до одной из клеток goals, «поработать» work_time секунд
## и вызвать on_arrive. Потом модератор сам вернётся на пост.
func send_on_errand(goals: Array[Vector2i], on_arrive: Callable) -> void:
	_errand_goals = goals
	_errand_done = on_arrive
	_errand_attempts = 0
	FloatingText.spawn(self, global_position + Vector2(0, -26), "Иду!", Color(1, 0.8, 0.4))


## Босс отбросил при появлении: встаём в новую клетку и заново ищем путь
func displace_to(world_pos: Vector2) -> void:
	global_position = world_pos
	_stepping = false
	_on_errand = false
	_path.clear()
	if _job != null:
		_jobs.push_front(_job)
		_job = null
	_state = State.IDLE
	_wait = 0.3


## Сколько у модератора вызовов (текущий + очередь) — чтобы делить работу
func get_load() -> int:
	return _jobs.size() + (1 if _job != null else 0)


## Вызывается ресурсом, который закончился
func request_refill(station: ResourceStation) -> void:
	if station == _job or station in _jobs:
		return
	_jobs.append(station)
	FloatingText.spawn(self, global_position + Vector2(0, -26), "Иду!", Color(1, 0.8, 0.4))


func _physics_process(delta: float) -> void:
	_update_bob(delta)
	if not Net.runs_world():
		return   # в сети модератора водит сервер, здесь только анимация (_process)
	if _wait > 0.0:
		_wait -= delta
		return
	match _state:
		State.IDLE:
			if _errand_done.is_valid():
				_start_errand()
			elif not _jobs.is_empty():
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
		# Пути нет (например, проход загородили) — попробуем чуть позже,
		# а после нескольких неудач починим удалённо
		_give_up()


func _start_errand() -> void:
	_on_errand = true
	if _cell() in _errand_goals:
		_arrive()
	elif not _walk_to(_errand_goals):
		_errand_failed()


# Не дойти по поручению (проход загорожен): пробуем ещё, а потом делаем дело издалека
func _errand_failed() -> void:
	_on_errand = false
	_errand_attempts += 1
	if _errand_attempts >= MAX_ATTEMPTS:
		_finish_errand()


func _finish_errand() -> void:
	var done := _errand_done
	_errand_done = Callable()
	_errand_goals.clear()
	_on_errand = false
	if done.is_valid():
		done.call()


func _walk_to(goals: Array[Vector2i]) -> bool:
	_goals = goals
	_avoid.clear()
	_stuck = 0
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
	if _job == null and not _on_errand and not _jobs.is_empty():
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
		_stuck += 1
		if _stuck >= STUCK_LIMIT and not (_path[0] in _avoid):
			_avoid.append(_path[0])   # по сетке клетка свободна, а физически не пройти — обходим её
		var blocked := _blockers()
		blocked.append_array(_avoid)
		var detour := Grid.find_path(self, _cell(), _goals, blocked)
		if not detour.is_empty():
			_path = detour
		elif _stuck >= STUCK_LIMIT:
			_give_up()                # обхода нет — отложим вызов и попробуем позже
		return
	_stuck = 0
	_path.remove_at(0)
	_step_target = target
	_stepping = true
	face_horizontal(target.x - global_position.x)


# Не дойти до вызова: возвращаем его в очередь и пробуем позже с чистого листа.
# После MAX_ATTEMPTS неудач чинит удалённо, чтобы ресурс не остался сломанным навсегда.
func _give_up() -> void:
	if _on_errand:
		_errand_failed()
	elif _job != null:
		_attempts[_job] = _attempts.get(_job, 0) + 1
		if _attempts[_job] >= MAX_ATTEMPTS:
			_fix_remotely(_job)
		else:
			_jobs.append(_job)
		_job = null
	_path.clear()
	_avoid.clear()
	_stuck = 0
	_state = State.IDLE
	_wait = 2.0


func _fix_remotely(station: ResourceStation) -> void:
	_attempts.erase(station)
	if not is_instance_valid(station) or not station.is_empty:
		return
	FloatingText.spawn(self, global_position + Vector2(0, -26), "Починю удалённо!", Color(1, 0.8, 0.4))
	station.refill()


func _arrive() -> void:
	if _job or _on_errand:
		_state = State.WORKING
		_wait = work_time
	else:
		_state = State.IDLE


func _finish_job() -> void:
	if _on_errand:
		_finish_errand()
		_state = State.IDLE
		return
	if is_instance_valid(_job) and _job.is_empty:
		_attempts.erase(_job)
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
		if not Grid.is_solid(node):
			continue
		if node.has_method("get_cells"):   # большие предметы (босс 2×2)
			cells.append_array(node.get_cells())
		else:
			cells.append(Grid.world_to_cell(self, node.global_position))
	return cells


# Клиент: идёт ли модератор, видно по тому, как меняется позиция с сервера
func _process(delta: float) -> void:
	super(delta)
	if not Net.is_view():
		return
	var moved := global_position - _view_last
	_view_last = global_position
	if moved != Vector2.ZERO:
		_view_still = 0.0
		_stepping = true
		face_horizontal(moved.x)
	else:
		_view_still += delta
		if _view_still > VIEW_STOP_DELAY:
			_stepping = false


# Пока идёт — вместо «дыхания» покачивание
func _idle_paused() -> bool:
	return _stepping


# Покачивание при ходьбе
func _update_bob(delta: float) -> void:
	var target_bob := 0.0
	if _stepping:
		_bob_phase += delta * 14.0
		target_bob = -absf(sin(_bob_phase)) * 2.5
	else:
		_bob_phase = 0.0
	_bob = target_bob
	_draw_offset = Vector2(0, _bob)   # NPC._draw учитывает этот сдвиг


# Без спрайта выглядит как NPC в оранжевой футболке с бейджем модератора
func _draw() -> void:
	super()   # рисует человечка (с «дыханием» и покачиванием), трансформация сохраняется
	if _sprite:
		return   # у спрайта бейдж уже нарисован
	draw_line(Vector2(-4, -5), Vector2(-1, -1), Color(0.15, 0.3, 0.75), 1.0)   # шнурок
	draw_line(Vector2(4, -5), Vector2(1, -1), Color(0.15, 0.3, 0.75), 1.0)
	draw_rect(Rect2(-2.5, -1.5, 5, 4), Color(1, 1, 1))                         # бейдж
	draw_rect(Rect2(-2, -1, 4, 1), Color(0.9, 0.25, 0.2))
