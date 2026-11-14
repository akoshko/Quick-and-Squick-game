class_name EmoteBubble
extends Node2D

## Облачко с эмоцией над головой игрока: выпрыгивает, держится и тает,
## потом удаляется само. Пока облачко живо, новая эмоция не показывается
## (защита от спама — см. Player.try_emote).
##
## Иконки 16×16 — лист res://src/emotes/emotes.png, по порядку как в NAMES.

enum Kind { WAVE, HEART, SMILE, ALERT }

const NAMES: PackedStringArray = ["Привет", "Спасибо", "Ха-ха", "Сюда!"]
const SHEET := preload("res://src/emotes/emotes.png")
const ICON := 16
const PADDING := 3.0
const TAIL := 4.0
const HOLD_TIME := 1.8
const POP_TIME := 0.15
const FADE_TIME := 0.35
const BG := Color(1, 1, 1, 0.96)
const BORDER := Color(0.15, 0.15, 0.2)

var kind := Kind.WAVE


## Иконка эмоции (для кнопок)
static func icon(emote: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEET
	atlas.region = Rect2(emote * ICON, 0, ICON, ICON)
	return atlas


## Сколько живёт облачко целиком (секунд)
static func lifetime() -> float:
	return POP_TIME + HOLD_TIME + FADE_TIME


func _ready() -> void:
	z_index = 100          # поверх всего уровня, как облачко NPC
	z_as_relative = false
	var sprite := Sprite2D.new()
	sprite.texture = icon(kind)
	sprite.position = Vector2(0, -TAIL - PADDING - ICON / 2.0)
	add_child(sprite)
	# Выпрыгивает «пружинкой», держится и тает
	scale = Vector2(0.2, 0.2)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(HOLD_TIME)
	t.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	t.tween_callback(queue_free)


func _draw() -> void:
	var size := Vector2.ONE * (ICON + PADDING * 2.0)
	var rect := Rect2(Vector2(-size.x / 2.0, -TAIL - size.y), size)
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.draw(get_canvas_item(), rect)
	# Хвостик вниз, к голове
	draw_colored_polygon(PackedVector2Array([Vector2(-3.5, -TAIL - 1), Vector2(3.5, -TAIL - 1), Vector2(0, 0.5)]), BORDER)
	draw_colored_polygon(PackedVector2Array([Vector2(-2.5, -TAIL - 1.5), Vector2(2.5, -TAIL - 1.5), Vector2(0, -0.8)]), BG)
