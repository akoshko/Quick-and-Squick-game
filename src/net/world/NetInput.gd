class_name NetInput
extends Node
## Клиент (CLIENT): читает те же действия, что Player._read_direction(), и `action`, и шлёт их
## серверу RPC NetWorld.submit_input — при изменении и повторно раз в RESEND_SECONDS, чтобы
## потерянный ненадёжный пакет не оставил персонажа идущим или стоящим.
## Пока открыт журнал, шлёт «стоять».
## Нажатие «действия»: обычные личные цели выполняет клиент. Обучение и общие
## взаимодействия проверяет сервер (NetWorld.request_interact).

const RESEND_SECONDS := 0.5

var world: Node

var _dir := Vector2i.ZERO
var _action := false
var _since_send := 0.0


func _physics_process(delta: float) -> void:
	# после разрыва NetClient ставит OfflineMultiplayerPeer (id 1, «подключён») — не шлём
	if multiplayer.get_unique_id() == 1 or multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var dir := Vector2i.ZERO
	var action := false
	# открытый журнал игру в сети не ставит на паузу (QuestPanel.open): персонаж просто стоит
	var journal := world.get_parent().get_node_or_null("QuestPanel") as QuestPanel
	var journal_open := journal != null and journal.is_open()
	if GameManager.state != GameManager.GameState.PAUSED and not journal_open:
		dir = Vector2i(
				int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left")),
				int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up")))
		action = Input.is_action_pressed("action")
		if Input.is_action_just_pressed("action"):
			_interact()
	_since_send += delta
	if dir == _dir and action == _action and _since_send < RESEND_SECONDS:
		return
	_dir = dir
	_action = action
	_since_send = 0.0
	world.submit_input.rpc_id(1, dir, action)


func _interact() -> void:
	var sync := world.get_node_or_null("WorldSync") as WorldSync
	var me := sync.own_player() if sync != null else null
	var target := me.personal_target() if me != null else null
	if target != null and not (target is NPC and target.tracks_server_interaction()):
		target.interact(me)
	else:
		world.request_interact.rpc_id(1)
