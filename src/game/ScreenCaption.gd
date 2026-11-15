class_name ScreenCaption
extends Node2D

## Надпись на большом экране в зале (или на любой стене): текст и картинка
## после него, вместе ровно по центру точки узла.
## Эмодзи в пиксельном шрифте нет — сердечко 🧡 нарисовано картинкой (icon).

@export var text := "Made by Eureka"
@export var icon: Texture2D = preload("res://src/game/visuals/heart_orange.png")
@export var font_size := 9                       ## в пикселях мира; камера сама увеличит
@export var color := Color(0.88, 0.94, 1.0)
@export var gap := 3.0                           ## между текстом и картинкой


func _ready() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(gap))
	add_child(row)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	row.add_child(label)

	if icon:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(picture)

	row.reset_size()
	row.position = (-row.size / 2.0).round()
