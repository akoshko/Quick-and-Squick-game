@tool
class_name Zone
extends Node2D

## Зона на уровне (перекус, хакатон…): группирует ресурсы — они лежат
## дочерними узлами — и показывает табличку с названием в точке узла.
## @tool — табличку видно прямо в редакторе.

@export var title := "Зона":
	set(value):
		title = value
		queue_redraw()
@export var color := Color(1, 0.92, 0.7):
	set(value):
		color = value
		queue_redraw()

const FONT_SIZE := 9


## Все ресурсы зоны
func get_stations() -> Array[ResourceStation]:
	var result: Array[ResourceStation] = []
	for child in get_children():
		if child is ResourceStation:
			result.append(child)
	return result


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var pos := Vector2(-width / 2.0, 0)
	draw_string_outline(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0.1, 0.1, 0.14))
	draw_string(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
