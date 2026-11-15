class_name NicknameStyle

## Как выглядит ник (награда «цвет ника», CharacterLook.NICKNAME_COLORS):
##   обычный цвет — просто цвет текста;
##   "gradient"   — переливающийся градиент из трёх цветов (шейдер, бежит по нику);
##   "stars"      — по бокам ника мерцают звёздочки.
## Один и тот же стиль — над головой персонажа и на бейдже в журнале.
## Использование: NicknameStyle.apply(label, PlayerProfile.nickname_color)

const DECOR_META := &"nickname_decor"
const STAR_COLOR := Color("#fff4b0")
const GRADIENT_SHADER := """
shader_type canvas_item;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform vec4 color_c : source_color;
uniform float width = 64.0;
uniform float speed = 0.35;
varying float local_x;
void vertex() {
	local_x = VERTEX.x;
}
void fragment() {
	// Перекрашиваем только светлые пиксели букв — тёмная обводка остаётся
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	if (lum > 0.45) {
		float t = fract(local_x / max(width, 1.0) * 0.75 - TIME * speed) * 3.0;
		vec3 g = t < 1.0 ? mix(color_a.rgb, color_b.rgb, t)
			: (t < 2.0 ? mix(color_b.rgb, color_c.rgb, t - 1.0) : mix(color_c.rgb, color_a.rgb, t - 2.0));
		COLOR.rgb = g;
	}
}
"""

static var _shader: Shader
static var _star: Texture2D


## Применить стиль ника к надписи. on_light — надпись на светлом фоне
## (бейдж): слишком светлые цвета заменяются тёмным ink.
static func apply(label: Label, style_id: Variant, on_light := false, ink := Color(0.17, 0.14, 0.14)) -> void:
	_clear(label)
	var style: Dictionary = CharacterLook.NICKNAME_COLORS[CharacterLook.clean_nickname_color(style_id)]
	var gradient: Array = style.get("gradient", [])
	if not gradient.is_empty():
		label.add_theme_color_override("font_color", Color.WHITE)   # шейдер красит светлое
		var material := ShaderMaterial.new()
		material.shader = _gradient_shader()
		material.set_shader_parameter("color_a", gradient[0])
		material.set_shader_parameter("color_b", gradient[1])
		material.set_shader_parameter("color_c", gradient[2])
		label.material = material
		_watch_size(label)
	else:
		var tint: Color = style.tint
		label.add_theme_color_override("font_color", ink if on_light and tint.get_luminance() > 0.75 else tint)
	if style.get("stars", false):
		_add_stars(label)


static func _clear(label: Label) -> void:
	label.material = null
	for child in label.get_children():
		if child.has_meta(DECOR_META):
			label.remove_child(child)
			child.queue_free()


# Ширина градиента и место звёздочек зависят от размера надписи
static func _watch_size(label: Label) -> void:
	if not label.has_meta(&"nickname_watch"):
		label.set_meta(&"nickname_watch", true)
		label.resized.connect(_update_width.bind(label))
	_update_width(label)


static func _update_width(label: Label) -> void:
	var material := label.material as ShaderMaterial
	if material:
		material.set_shader_parameter("width", maxf(label.size.x, 1.0))
	for child in label.get_children():
		if child.has_meta(DECOR_META):
			_place_star(label, child as TextureRect)


# Звёздочки слева и справа от ника, мерцают по очереди
static func _add_stars(label: Label) -> void:
	for side in [-1, 1]:
		var star := TextureRect.new()
		star.texture = _star_texture()
		star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.set_meta(DECOR_META, side)
		label.add_child(star)
		_place_star(label, star)
		star.pivot_offset = star.size / 2.0
		var twinkle := star.create_tween().set_loops()
		twinkle.tween_interval(0.35 if side < 0 else 0.0)
		twinkle.tween_property(star, "scale", Vector2.ONE * 0.55, 0.45).set_trans(Tween.TRANS_SINE)
		twinkle.tween_property(star, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		twinkle.tween_interval(0.35 if side > 0 else 0.0)
	_watch_size(label)


static func _place_star(label: Label, star: TextureRect) -> void:
	var side: int = star.get_meta(DECOR_META)
	var font_size := label.get_theme_font_size(&"font_size")
	var star_size := Vector2.ONE * maxf(5.0, roundf(font_size * 0.7))
	star.size = star_size
	star.pivot_offset = star_size / 2.0
	var y := (label.size.y - star_size.y) / 2.0
	star.position = Vector2(-star_size.x - 1.0 if side < 0 else label.size.x + 1.0, y)


static func _gradient_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = GRADIENT_SHADER
	return _shader


# Пиксельная звёздочка 5×5
static func _star_texture() -> Texture2D:
	if _star == null:
		var image := Image.create_empty(5, 5, false, Image.FORMAT_RGBA8)
		for point: Vector2i in [Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2),
				Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(2, 4)]:
			image.set_pixel(point.x, point.y, STAR_COLOR)
		_star = ImageTexture.create_from_image(image)
	return _star
