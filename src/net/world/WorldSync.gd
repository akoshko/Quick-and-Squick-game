class_name WorldSync
extends Node
## Общий мир в сети: один механизм для всех предметов уровня (мешки, босс, NPC и модераторы,
## станции, ноутбуки, сокобан, зомби). Узел создаёт NetWorld — и на сервере, и у клиентов.
##
## • Состояние. Предмет добавляет себя в группу GROUP; его состояние — словарь:
##   net_state() (если есть) плюс позиция POSITION_KEY для Node2D. Сервер раз в SEND_INTERVAL
##   сравнивает состояния с прошлыми и рассылает изменившиеся одним надёжным RPC (только пирам,
##   подтвердившим world_ready); пиру, который только что подтвердил, — снимок всего мира.
##   Клиент ставит позицию плавно (_glide_to), остальное отдаёт предмету в apply_net_state().
## • Вызовы. Net.world_call(предмет, метод, аргументы) на сервере повторяет вызов у клиентов —
##   для видимых эффектов, которых нет в состоянии (мешок плюхнулся, реплика модератора).
## • Эффекты. Всплывающий текст, звуки и конфетти на сервере не создаются, а рассылаются
##   (Net.route_fx -> broadcast_fx -> play_fx).
## • Действие игрока. Клиент шлёт NetWorld.request_interact; сервер выполняет Player._interact()
##   у своего экземпляра персонажа. Личные цели (диалоги NPC, прятки) клиент обрабатывает сам,
##   а если такую цель выбрал сервер — возвращает её клиенту (run_personal_interact).
## Пока клиент применяет присланное (receive_states, replay_call), Net.replaying = true (Net.replay).
##
## Как добавить синхронизируемый предмет:
##   1. add_to_group(WorldSync.GROUP) в _ready. Предмет узнаётся по пути в сцене уровня, поэтому
##      имя узла должно быть стабильным и одинаковым на сервере и у клиентов. Узлы, созданные
##      во время игры (например, CoffeeCup), в группу не входят: их синхронизирует родитель
##      в своём состоянии.
##   2. net_state() -> Dictionary: только простые значения Variant (числа, строки, векторы,
##      массивы, словари), считается дёшево и при неизменном мире равен прошлому по ==,
##      потому что сравнивается раз в SEND_INTERVAL. Ключи — полными словами.
##   3. apply_net_state(state) — у клиента: только показать состояние. Не слать сигналы
##      игровой логики и не запускать симуляцию (её ведёт только Net.runs_world()).
##   4. Позиция идёт под зарезервированным ключом POSITION_KEY (округлена до Vector2i) —
##      свои ключи с таким именем предметам заводить нельзя.
##   5. Разовые видимые эффекты — Net.world_call(self, &"net_…") с публичным методом net_…
##      (метод — часть сетевого контракта).
## Всё идёт надёжным RPC: рассылаются только изменения, и один потерянный пакет оставил бы
## клиента рассинхронизированным до следующей перемены.

const GROUP := "net_sync"
const POSITION_KEY := "position"   # зарезервирован: позиция Node2D (Vector2i)
const SEND_INTERVAL := 0.1         # с между рассылками изменений (10 Гц; неподвижное не шлётся)
const TELEPORT_DISTANCE := 48.0    # дальше этого (px) позиция ставится сразу, без скольжения
const MIN_GLIDE_SPEED := 20.0      # px/с: медленнее скольжение не идёт

## Видимый эффект, который сервер рассылает клиентам (Net.route_fx). Аргументы — массив,
## порядок как у вызова, который эффект повторяет:
##   TEXT:     [world_pos, text, color]                          — FloatingText.spawn
##   SOUND_AT: [sound, world_pos, pitch_jitter, volume_db, pitch] — Sfx.play_at
##   SOUND:    [sound, pitch_jitter, volume_db, pitch]           — Sfx.play
##   CONFETTI: [pieces]                                          — Confetti.burst
enum Fx { TEXT, SOUND_AT, SOUND, CONFETTI }

var _net: Node
var _scene: Node
var _last_sent_states := {}   # сервер: путь -> последнее разосланное состояние
var _since_send := 0.0
var _glide_targets := {}      # клиент: Node2D -> куда скользит
var _glide_speeds := {}       # клиент: Node2D -> скорость скольжения (px/с)


func _ready() -> void:
	_net = get_node("/root/Net")
	_scene = get_parent().owner   # сцена уровня, в которой лежит NetWorld


func _process(delta: float) -> void:
	if _net.is_server():
		_since_send += delta
		if _since_send >= SEND_INTERVAL:
			_since_send = 0.0
			_send_changes()
	elif not _glide_targets.is_empty():
		_glide_step(delta)


## Состояние предмета для рассылки (сервер; тесты зовут напрямую, без сети)
static func state_of(node: Node) -> Dictionary:
	var state: Dictionary = node.call("net_state") if node.has_method("net_state") else {}
	if node is Node2D and not state.has(POSITION_KEY):
		state[POSITION_KEY] = Vector2i((node as Node2D).global_position.round())
	return state


## Применить состояние сразу, без скольжения (тесты, снимок без экземпляра WorldSync)
static func apply_now(node: Node, state: Dictionary) -> void:
	if state.has(POSITION_KEY) and node is Node2D:
		(node as Node2D).global_position = Vector2(state[POSITION_KEY] as Vector2i)
	_apply_rest(node, state)


## Клиент: сверить свой таймер с серверным. Сервер шлёт время целыми секундами, а дальше клиент
## досчитывает сам — поэтому перезаписываем, только если разошлись на секунду и больше.
static func resync_timer(local: float, server: float) -> float:
	return server if absf(server - local) >= 1.0 else local


# Всё, кроме позиции, — самому предмету
static func _apply_rest(node: Node, state: Dictionary) -> void:
	if node.has_method("apply_net_state"):
		node.call("apply_net_state", state)


# --- сервер ---

func _ready_peers() -> Array:
	var out: Array = []
	var peers := multiplayer.get_peers()
	for peer: int in _net.world_ready_peers:
		if peer in peers:
			out.append(peer)
	return out


func _collect(full: bool) -> Dictionary:
	var out := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		if not _scene.is_ancestor_of(node) or not node.is_inside_tree():
			continue
		var key := str(_scene.get_path_to(node))
		var state := state_of(node)
		if full:
			out[key] = state
			continue
		var last: Variant = _last_sent_states.get(key)
		if last == state:
			continue
		_last_sent_states[key] = state
		# Идёт, а остальное прежнее (зомби, модератор) — шлём одну позицию: так за тик
		# уходит в разы меньше, а клиент уже знает остальное из прошлых рассылок
		out[key] = {POSITION_KEY: state[POSITION_KEY]} 			if last is Dictionary and state.has(POSITION_KEY) and _same_except_position(last, state) else state
	return out


static func _same_except_position(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in b:
		if k != POSITION_KEY and (not a.has(k) or a[k] != b[k]):
			return false
	return true


func _send_changes() -> void:
	var changes := _collect(false)
	if changes.is_empty():
		return
	for peer: int in _ready_peers():
		receive_states.rpc_id(peer, changes)


## Пир подтвердил world_ready: весь мир целиком
func send_snapshot(peer: int) -> void:
	receive_states.rpc_id(peer, _collect(true))


## Повторить вызов метода предмета у всех клиентов (Net.world_call)
func broadcast_call(node: Node, method: StringName, args: Array) -> void:
	if not _scene.is_ancestor_of(node):
		return
	var key := str(_scene.get_path_to(node))
	for peer: int in _ready_peers():
		replay_call.rpc_id(peer, key, method, args)


## Разослать видимый эффект всем клиентам (Net.route_fx)
func broadcast_fx(kind: Fx, args: Array) -> void:
	for peer: int in _ready_peers():
		play_fx.rpc_id(peer, kind, args)


## Личная цель действия, выбранная сервером, — клиенту пира peer
func send_personal_interact(peer: int, target: Node) -> void:
	if peer > 0 and _scene.is_ancestor_of(target) and peer in multiplayer.get_peers():
		run_personal_interact.rpc_id(peer, str(_scene.get_path_to(target)))


# --- клиент ---

## Сервер -> клиент: состояния предметов (изменившиеся или снимок всего мира)
@rpc("authority", "call_remote", "reliable")
func receive_states(states: Dictionary) -> void:
	_net.replay(func() -> void:
		for key: String in states:
			var node := _scene.get_node_or_null(NodePath(key))
			if node == null or typeof(states[key]) != TYPE_DICTIONARY:
				continue
			var state := states[key] as Dictionary
			if state.has(POSITION_KEY) and node is Node2D:
				_glide_to(node, Vector2(state[POSITION_KEY] as Vector2i))
			if state.size() > 1 or not state.has(POSITION_KEY):
				_apply_rest(node, state))


## Сервер -> клиент: повторить вызов метода предмета (Net.world_call)
@rpc("authority", "call_remote", "reliable")
func replay_call(key: String, method: StringName, args: Array) -> void:
	var node := _scene.get_node_or_null(NodePath(key))
	if node == null or not node.has_method(method):
		return
	_net.replay(node.callv.bind(method, args))


## Сервер -> клиент: показать видимый эффект (Net.route_fx); аргументы — см. Fx
@rpc("authority", "call_remote", "reliable")
func play_fx(kind: Fx, args: Array) -> void:
	match kind:
		Fx.TEXT:
			FloatingText.spawn(self, args[0], args[1], args[2])
		Fx.SOUND_AT:
			Sfx.play_at(args[0], args[1], args[2], args[3], args[4])
		Fx.SOUND:
			Sfx.play(args[0], args[1], args[2], args[3])
		Fx.CONFETTI:
			Confetti.burst(self, args[0])


## Сервер -> клиент: сервер выбрал для действия личную цель — выполнить её у своего персонажа
@rpc("authority", "call_remote", "reliable")
func run_personal_interact(key: String) -> void:
	var target := _scene.get_node_or_null(NodePath(key))
	var me := own_player()
	if target != null and me != null and target.has_method("interact"):
		target.interact(me)


## Свой персонаж клиента (или null)
func own_player() -> Player:
	if _net.client == null or _net.client.player_id == "":
		return null
	return get_parent().get_node_or_null(NodePath("Players/" + _net.client.player_id)) as Player


# Плавно довести предмет до позиции с сервера; далеко — поставить сразу
func _glide_to(node: Node2D, target: Vector2) -> void:
	var distance := node.global_position.distance_to(target)
	if distance > TELEPORT_DISTANCE:
		node.global_position = target
		_stop_glide(node)
	elif distance > 0.0:
		_glide_targets[node] = target
		_glide_speeds[node] = maxf(distance / SEND_INTERVAL, MIN_GLIDE_SPEED)


func _stop_glide(node: Variant) -> void:
	_glide_targets.erase(node)
	_glide_speeds.erase(node)


func _glide_step(delta: float) -> void:
	for node: Variant in _glide_targets.keys():
		if not is_instance_valid(node):
			_stop_glide(node)
			continue
		var body := node as Node2D
		var target: Vector2 = _glide_targets[node]
		var speed: float = _glide_speeds[node]
		body.global_position = body.global_position.move_toward(target, speed * delta)
		if body.global_position == target:
			_stop_glide(node)
