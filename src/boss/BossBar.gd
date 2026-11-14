class_name BossBar
extends CanvasLayer

## Полоска здоровья босса вверху экрана в духе соулс-игр: титул над
## узкой тёмно-красной полосой с делениями. Когда босс получает урон,
## по потерянному делению пробегает светлый «след урона».
## В конце боя по центру экрана — большая надпись («ВЕЛИКИЙ ВРАГ ПОВЕРЖЕН»).

const NAME_COLOR := Color(0.92, 0.88, 0.8)
const FELLED_COLOR := Color(1, 0.84, 0.45)

var _root: Control
var _name: Label
var _bar: SegmentBar
var _banner: Label
var _fade: Tween


## Полоска из делений, нарисованная кодом
class SegmentBar extends Control:
	var segments := 3
	var hp := 3.0
	var trail := 3.0   # «след урона»: догоняет hp с задержкой

	func _process(delta: float) -> void:
		if trail > hp:
			trail = move_toward(trail, hp, delta * 1.5)
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(2), Color(0.05, 0.04, 0.04, 0.9))                 # подложка
		draw_rect(r.grow(2), Color(0.55, 0.47, 0.32), false, 1.0)          # тонкая рамка
		var gap := maxf(2.0, size.x * 0.006)
		var seg_w := (size.x - gap * (segments - 1)) / segments
		for i in segments:
			var seg := Rect2(i * (seg_w + gap), 0, seg_w, size.y)
			draw_rect(seg, Color(0.16, 0.05, 0.05))                         # пустое деление
			var fill_trail := clampf(trail - i, 0.0, 1.0)
			if fill_trail > 0.0:
				draw_rect(Rect2(seg.position, Vector2(seg_w * fill_trail, size.y)), Color(0.95, 0.85, 0.55))
			var fill := clampf(hp - i, 0.0, 1.0)
			if fill > 0.0:
				draw_rect(Rect2(seg.position, Vector2(seg_w * fill, size.y)), Color(0.62, 0.08, 0.08))
				draw_rect(Rect2(seg.position, Vector2(seg_w * fill, size.y * 0.3)), Color(0.78, 0.18, 0.14))


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_name = Label.new()
	_name.add_theme_color_override("font_color", NAME_COLOR)
	_name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_root.add_child(_name)

	_bar = SegmentBar.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar)

	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.modulate.a = 0.0
	_root.add_child(_banner)

	_set_boss_visible(false)
	get_viewport().size_changed.connect(_layout)
	_layout()


func show_boss(title: String, max_hp: int) -> void:
	_name.text = title
	_bar.segments = max_hp
	_bar.hp = max_hp
	_bar.trail = max_hp
	_bar.queue_redraw()
	_set_boss_visible(true)
	_name.modulate.a = 0.0
	_bar.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_name, "modulate:a", 1.0, 0.8)
	t.tween_property(_bar, "modulate:a", 1.0, 0.8)


func set_hp(hp: int, _max_hp: int) -> void:
	_bar.hp = hp
	_bar.queue_redraw()


func hide_boss() -> void:
	var t := create_tween().set_parallel()
	t.tween_property(_name, "modulate:a", 0.0, 0.8)
	t.tween_property(_bar, "modulate:a", 0.0, 0.8)
	t.chain().tween_callback(_set_boss_visible.bind(false))


## Большая надпись по центру: проявляется, держится и тает
func show_banner(text: String, color := FELLED_COLOR) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _fade:
		_fade.kill()
	_banner.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(_banner, "modulate:a", 1.0, 0.8)
	_fade.tween_interval(2.2)
	_fade.tween_property(_banner, "modulate:a", 0.0, 1.0)


func _set_boss_visible(on: bool) -> void:
	_name.visible = on
	_bar.visible = on


# Размеры — от размера экрана: полоса по центру сверху
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var font := maxi(10, int(screen.y * 0.03))
	var bar_size := Vector2(screen.x * 0.42, maxf(6.0, screen.y * 0.016))
	var top := screen.y * 0.04

	_name.add_theme_font_size_override("font_size", font)
	_name.add_theme_constant_override("outline_size", maxi(2, int(font / 6.0)))
	_name.reset_size()
	_name.position = Vector2((screen.x - bar_size.x) / 2.0, top)

	_bar.size = bar_size
	_bar.position = Vector2((screen.x - bar_size.x) / 2.0, top + _name.size.y + 4.0)

	var banner_font := maxi(16, int(screen.y * 0.075))
	_banner.add_theme_font_size_override("font_size", banner_font)
	_banner.add_theme_constant_override("outline_size", maxi(3, int(banner_font / 8.0)))
	_banner.size = Vector2(screen.x, banner_font * 2.0)
	_banner.position = Vector2(0, (screen.y - _banner.size.y) / 2.0)
