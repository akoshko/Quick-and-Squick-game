class_name ScreenOverlay
extends CanvasLayer
## Правая колонка экранного вида для проектора (§6.7): QR-код на адрес страницы, сам адрес
## и счётчик «Игроков: N». Колонка занимает COLUMN_RATIO ширины; камера (PlayerCamera.fit_map)
## вписывает карту в оставшуюся левую часть.

const QRCode := preload("res://src/vendor/qr/qr_code.gd")

const COLUMN_RATIO := 0.25
const QR_MODULE_PX := 8       ## пикселей на модуль в исходной картинке (дальше масштабируется)
const PANEL_COLOR := Color(0.08, 0.09, 0.12, 1.0)

var world: Node   ## NetWorld: источник player_count / player_count_changed

var _panel: ColorRect
var _box: VBoxContainer
var _qr_rect: TextureRect
var _url_label: Label
var _count_label: Label


## Матрица QR (строка за строкой, 1 = тёмный модуль) для текста; пустая при ошибке.
static func encode_text(text: String) -> PackedByteArray:
	return QRCode.encode(text)


## Картинка QR с тихой зоной в 4 модуля.
static func make_image(text: String, module_px: int = QR_MODULE_PX) -> Image:
	return QRCode.generate_image(encode_text(text), module_px)


func _ready() -> void:
	layer = 20
	_panel = ColorRect.new()
	_panel.color = PANEL_COLOR
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_box)

	_qr_rect = TextureRect.new()
	_qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_box.add_child(_qr_rect)

	_url_label = _make_label()
	_url_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_url_label.clip_text = true
	_box.add_child(_url_label)
	_count_label = _make_label()
	_box.add_child(_count_label)

	var net := get_node("/root/Net")
	var url: String = net.config.share_url
	_url_label.text = url
	if url != "":
		_qr_rect.texture = ImageTexture.create_from_image(make_image(url))

	if world != null:
		world.player_count_changed.connect(_on_count)
		_on_count(world.player_count)
	else:
		_on_count(0)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make_label() -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _on_count(n: int) -> void:
	_count_label.text = "Игроков: %d" % n


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var col_w := roundf(screen.x * COLUMN_RATIO)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = screen.x - col_w
	_panel.offset_right = screen.x
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	var step := UiSpacing.step(screen)
	var pad := step * 3
	_box.add_theme_constant_override("separation", step * 2)
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = pad
	_box.offset_right = -pad
	_box.offset_top = pad
	_box.offset_bottom = -pad
	var qr_side := minf(col_w - 2.0 * pad, screen.y * 0.5)
	_qr_rect.custom_minimum_size = Vector2(qr_side, qr_side)
	var font := maxi(12, int(minf(col_w * 0.07, screen.y * 0.04)))
	# адрес всегда в одну строку: шрифт сжимается под ширину колонки
	var url_font := _url_label.get_theme_font("font")
	var avail := col_w - 2.0 * pad
	var url_size := font
	if url_font != null and _url_label.text != "":
		var w := url_font.get_string_size(_url_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font).x
		if w > avail:
			url_size = maxi(6, int(floor(font * avail / w)))
	_url_label.add_theme_font_size_override("font_size", url_size)
	_count_label.add_theme_font_size_override("font_size", int(font * 1.3))
