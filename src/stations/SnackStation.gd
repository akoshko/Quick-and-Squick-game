class_name SnackStation
extends ResourceStation

## Тарелка с печеньем или миска с яблоками. По «действию» игрок съедает
## одну порцию и выполняет задание «Перекусить». Когда порции кончились —
## через 5 секунд модератор приносит ещё.
##
## Спрайты — с листа res://src/tile_map.png (клетки 16×16), от пустой до
## трёх порций: миска с яблоками — ряд 6, тарелка с печеньем — ряд 7,
## колонки 15 (пусто) … 18 (три порции).

enum Kind { COOKIE, APPLE }

@export var kind := Kind.COOKIE:
	set(value):
		kind = value
		_update_frame()
@export var portions := 3
@export var quest_id := "snack"   ## какое задание выполнить (пусто — никакое)
## Лист со спрайтами еды
@export var sheet: Texture2D = preload("res://src/tile_map.png")

const SHEET_ROW := {Kind.APPLE: 6, Kind.COOKIE: 7}
const EMPTY_COLUMN := 15          # пустая посуда; дальше — 1, 2, 3 порции
const MAX_DRAWN := 3              # больше трёх порций на картинке не помещается

var _left := 0
var _atlas: AtlasTexture

@onready var _sprite: Sprite2D = $Sprite2D   # спрайт в сцене — его видно в редакторе


func _ready() -> void:
	super()
	_left = portions
	if refill_text == "":
		refill_text = "Доложил печенье!" if kind == Kind.COOKIE else "Принёс яблок!"
	_atlas = AtlasTexture.new()   # у каждой тарелки свой кадр
	_atlas.atlas = sheet
	_sprite.texture = _atlas
	_update_frame()


func interact(_player: Player) -> void:
	if is_knocked:
		FloatingText.spawn(self, global_position + Vector2(0, -12), "Всё рассыпано!", Color(1, 0.6, 0.5))
		return
	if is_empty:
		FloatingText.spawn(self, global_position + Vector2(0, -12), "Пусто…", Color(0.8, 0.82, 0.88))
		return
	_left -= 1
	Sfx.play_at(&"nom", global_position, 0.12)
	FloatingText.spawn(self, global_position + Vector2(0, -12),
			"Ням!" if kind == Kind.COOKIE else "Хрум!", Color(1, 0.85, 0.5))
	if quest_id != "":
		Quests.complete(quest_id)
	_update_frame()
	_bounce()
	if _left <= 0:
		_set_empty()


func knock_over() -> void:
	super()
	_update_frame()


func _on_refilled() -> void:
	_left = portions
	_update_frame()
	_bounce()


func _update_frame() -> void:
	if _atlas == null:
		return
	var column := EMPTY_COLUMN + (0 if is_knocked else clampi(_left, 0, MAX_DRAWN))
	_atlas.region = Rect2(column * 16, SHEET_ROW[kind] * 16, 16, 16)
	# Босс опрокинул — пустая посуда лежит на боку
	_sprite.rotation = deg_to_rad(-75.0) if is_knocked else 0.0


# Посуда «подпрыгивает» при укусе и при пополнении
func _bounce() -> void:
	var t := create_tween()
	t.tween_property(_sprite, "scale", Vector2(1.25, 0.8), 0.06)
	t.tween_property(_sprite, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
