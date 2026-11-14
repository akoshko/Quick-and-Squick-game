class_name PlayerCamera
extends Camera2D

## Камера, следящая за серединой между видимыми игроками.

const MAP_MARGIN := 0.95   ## запас вокруг карты в экранном виде

@export var smooth_speed: float = 6.0
## Сколько клеток видно по вертикали. Zoom подбирается сам под размер
## экрана, поэтому на мониторе, ноутбуке и телефоне вид одинаковый.
@export var visible_rows: float = 9.0

## Сеть: камера не смотрит на Player1/Player2 (их нет), а следует за
## своим персонажем (follow). В экранном виде (SCREEN) пока стоит на месте.
var network_view := false
## Экранный вид: камера показывает всю карту (fit_map), слежения нет.
var map_rect := Rect2()
var map_right_ratio := 0.0   ## доля ширины экрана справа, занятая колонкой QR

@onready var _player1: Player = %Player1
@onready var _player2: Player = %Player2
var _target: Node2D
var _fit_size := Vector2.ZERO


func _ready() -> void:
	_update_zoom()
	get_viewport().size_changed.connect(_update_zoom)
	# Сразу ставим камеру к игрокам, чтобы она не «прилетала» на старте
	global_position = _midpoint()


func _process(delta: float) -> void:
	if map_rect.has_area():
		# размер окна в вебе может устояться позже сигнала size_changed: подстраховка
		if get_viewport_rect().size != _fit_size:
			_update_zoom()
		return
	global_position = global_position.lerp(_midpoint(), smooth_speed * delta)


func follow(target: Node2D) -> void:
	_target = target
	if is_instance_valid(_target):
		global_position = _target.global_position   # без «прилёта» через карту


## Вписать прямоугольник карты (в мировых координатах) в экран без правой колонки.
func fit_map(rect: Rect2, right_ratio: float) -> void:
	map_rect = rect
	map_right_ratio = right_ratio
	_update_zoom()


func _update_zoom() -> void:
	var screen := get_viewport_rect().size
	if map_rect.has_area():
		var free_w := screen.x * (1.0 - map_right_ratio)
		var z := minf(free_w / map_rect.size.x, screen.y / map_rect.size.y) * MAP_MARGIN
		zoom = Vector2.ONE * z
		_fit_size = screen
		# центр карты — по центру свободной части экрана (левее центра экрана на половину колонки)
		global_position = map_rect.get_center() + Vector2(screen.x * map_right_ratio * 0.5 / z, 0.0)
		return
	var screen_height := minf(screen.y, screen.x * 1.5)
	var world_height := visible_rows * Grid.tile_size(self).y
	zoom = Vector2.ONE * (screen_height / world_height)


# Середина между видимыми игроками. Скрытый игрок (например, Player2,
# пока играем одни) не учитывается, иначе камера тянется к нему.
func _midpoint() -> Vector2:
	if network_view:
		return _target.global_position if is_instance_valid(_target) else global_position
	var sum := Vector2.ZERO
	var count := 0
	for player in [_player1, _player2]:
		if is_instance_valid(player) and player.visible:
			sum += player.global_position
			count += 1
	if count == 0:
		return global_position   # никого не видно — стоим на месте
	return sum / count
