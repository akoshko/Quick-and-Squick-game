class_name NPC
extends StaticBody2D

## Прототип NPC: стоит в клетке, по «действию» показывает облачко с репликой
## поверх всего. Каждое нажатие — следующая реплика, после последней облачко
## закрывается. Если игрок отходит, облачко закрывается само.
##
## Работает через ту же систему, что и мешок: группа "interactable"
## и метод interact(player).

@export var npc_name := "Коллега"
## Задание, которое выполняется, когда игрок дослушал все реплики (пусто — никакое)
@export var quest_id := "talk_npc"
## После завершения этого квеста NPC только здоровается.
@export var greeting_after_quest_id := ""
@export var lines: PackedStringArray = [
	"Привет! Ты новенький?",
	"Говорят, в лаундже стоят очень мягкие кресла-мешки...",
	"Попробуй подвинуть один, только никому не говори!",
]
@export var shirt_color := Color(0.35, 0.55, 0.85)
@export var hair_color := Color(0.3, 0.2, 0.15)
@export var bubble_width := 96.0   # ширина текста в облачке (пиксели мира)

const FONT_SIZE := 8          # в пикселях мира; камера сама увеличит
const BUBBLE_Z := 100         # выше всего на уровне
const HEAD_TOP := -20.0       # где у NPC макушка — над ней висит облачко
const TAIL_HEIGHT := 5.0
const BUBBLE_BG := Color(1, 1, 1, 0.96)
const BUBBLE_BORDER := Color(0.15, 0.15, 0.2)

var _line_index := -1
var _talking_to: Player
var _bubble: Node2D
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	add_to_group("interactable")
	Grid.snap(self)
	_build_bubble()


func interact(player: Player) -> void:
	_talking_to = player
	if not greeting_after_quest_id.is_empty() and Quests.is_done(greeting_after_quest_id):
		if _bubble.visible and _line_index == -1:
			_close()
		else:
			_line_index = -1
			_show_line("Привет!")
		return
	_line_index += 1
	if _line_index >= lines.size():
		# Дослушали до конца — разговор состоялся
		if quest_id != "":
			Quests.complete(quest_id)
		_close()
		return
	_show_line(lines[_line_index])


func _process(_delta: float) -> void:
	# Игрок отошёл дальше соседней клетки — закрываем разговор
	if not _bubble.visible or not is_instance_valid(_talking_to):
		return
	var me := Grid.world_to_cell(self, global_position)
	var them := Grid.world_to_cell(self, _talking_to.global_position)
	if absi(me.x - them.x) + absi(me.y - them.y) > 1:
		_close()


func _show_line(text: String) -> void:
	_label.text = text
	_bubble.visible = true
	_panel.modulate.a = 0.0   # прячем, пока контейнер не пересчитал размер
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = Vector2(-_panel.size.x / 2.0, -TAIL_HEIGHT - _panel.size.y)
	_panel.modulate.a = 1.0

	# Небольшой «поп» при появлении
	_bubble.scale = Vector2.ONE * 0.85
	create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close() -> void:
	_bubble.visible = false
	_line_index = -1
	_talking_to = null


# Облачко собирается кодом: панель с рамкой, имя, текст и «хвостик» вниз
func _build_bubble() -> void:
	_bubble = Node2D.new()
	_bubble.position = Vector2(0, HEAD_TOP)
	_bubble.z_index = BUBBLE_Z
	_bubble.z_as_relative = false   # z считается от всего уровня, а не от NPC
	_bubble.visible = false
	add_child(_bubble)

	var style := StyleBoxFlat.new()
	style.bg_color = BUBBLE_BG
	style.border_color = BUBBLE_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # не перехватывать касания
	_panel.add_theme_stylebox_override("panel", style)
	_bubble.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	_panel.add_child(vbox)

	var name_label := Label.new()
	name_label.text = npc_name
	name_label.add_theme_font_size_override("font_size", FONT_SIZE - 2)
	name_label.add_theme_color_override("font_color", shirt_color.darkened(0.35))
	vbox.add_child(name_label)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = bubble_width
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	vbox.add_child(_label)

	# Хвостик: тёмный треугольник-рамка, сверху белый — он же закрывает
	# кусок нижней рамки панели, чтобы хвостик «вытекал» из облачка
	var tail_border := Polygon2D.new()
	tail_border.polygon = PackedVector2Array([
		Vector2(-5, -TAIL_HEIGHT), Vector2(5, -TAIL_HEIGHT), Vector2(0, 1)])
	tail_border.color = BUBBLE_BORDER
	_bubble.add_child(tail_border)

	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([
		Vector2(-4, -TAIL_HEIGHT - 1.5), Vector2(4, -TAIL_HEIGHT - 1.5), Vector2(0, -0.5)])
	tail.color = BUBBLE_BG
	_bubble.add_child(tail)


# Рисуем человечка кодом, пока нет спрайта. Когда появится картинка —
# добавь в сцену Sprite2D и удали эту функцию.
func _draw() -> void:
	var skin := Color(0.96, 0.8, 0.66)
	var pants := Color(0.22, 0.24, 0.32)
	var dark := Color(0.12, 0.1, 0.12)

	_draw_ellipse(Vector2(0, 12), Vector2(9, 3), Color(0, 0, 0, 0.25))    # тень
	draw_rect(Rect2(-5, 5, 4, 7), pants)                                   # ноги
	draw_rect(Rect2(1, 5, 4, 7), pants)
	draw_rect(Rect2(-7, -5, 14, 11), shirt_color)                          # тело
	draw_rect(Rect2(-9, -4, 2, 8), shirt_color.darkened(0.15))             # руки
	draw_rect(Rect2(7, -4, 2, 8), shirt_color.darkened(0.15))
	draw_rect(Rect2(-9, 4, 2, 2), skin)                                    # кисти
	draw_rect(Rect2(7, 4, 2, 2), skin)
	draw_circle(Vector2(0, -12), 7.0, hair_color)                          # волосы
	draw_circle(Vector2(0, -10.5), 6.0, skin)                              # лицо
	draw_rect(Rect2(-6, -17, 12, 4), hair_color)                           # чёлка
	draw_rect(Rect2(-3, -11, 1.5, 2), dark)                                # глаза
	draw_rect(Rect2(1.5, -11, 1.5, 2), dark)


func _draw_ellipse(center: Vector2, radius: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(points, fill)
