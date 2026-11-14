class_name ConnectionOverlay
extends CanvasLayer
## Connection status over the game: dim + "Подключение…" while connecting, a red "Нет соединения"
## badge while reconnecting (game stays visible), full screen message when rejected.

const REJECT_TEXT := {
	"kicked": "Вас отключил администратор",
	"replaced": "Игра открыта в другой вкладке",
	"version_mismatch": "Обновите страницу",
}

# the Net autoload, looked up at runtime (autoload names are not known to `--script` checks)
@onready var _net: Node = get_node("/root/Net")
var _dim: ColorRect
var _dim_label: Label
var _badge: PanelContainer
var _reject: ColorRect
var _reject_label: Label
var _retry: Button
var _badge_label: Label
var _badge_style: StyleBoxFlat


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_dim_label = _centered_label("Подключение…")
	_dim.add_child(_dim_label)

	_badge = PanelContainer.new()
	_badge_style = StyleBoxFlat.new()
	_badge_style.bg_color = Color(0.85, 0.1, 0.1, 0.92)
	_badge.add_theme_stylebox_override("panel", _badge_style)
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label = Label.new()
	_badge_label.text = "Нет соединения"
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge.add_child(_badge_label)
	add_child(_badge)

	_reject = ColorRect.new()
	_reject.color = Color(0.08, 0.08, 0.1, 1.0)
	_reject.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reject.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_reject)
	_reject_label = _centered_label("")
	_reject.add_child(_reject_label)
	_retry = Button.new()
	_retry.text = "Попробовать снова"
	_retry.set_anchors_preset(Control.PRESET_CENTER)
	_retry.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_retry.grow_vertical = Control.GROW_DIRECTION_BOTH
	_retry.pressed.connect(func() -> void: JavaScriptBridge.eval("location.reload()"))
	_reject.add_child(_retry)

	get_viewport().size_changed.connect(_layout)
	_layout()
	_net.link_changed.connect(_show)
	_show(_net.link, _net.link_reason)


## Sizes follow the viewport (like QuestProgress), so the badge stays readable on phones and projectors.
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var h := minf(screen.y, screen.x * 1.45)
	var font := maxi(12, int(h * 0.05))
	var badge_font := maxi(10, int(h * 0.035))
	var margin := roundf(h * 0.02)
	_dim_label.add_theme_font_size_override("font_size", font)
	_reject_label.add_theme_font_size_override("font_size", font)
	_retry.add_theme_font_size_override("font_size", font)
	_reject_label.offset_bottom = -font * 2
	_retry.offset_top = font
	_retry.offset_bottom = font * 3
	_badge_label.add_theme_font_size_override("font_size", badge_font)
	_badge_style.set_content_margin_all(roundf(badge_font * 0.5))
	_badge_style.set_corner_radius_all(roundi(badge_font * 0.35))
	_badge.offset_left = -margin
	_badge.offset_right = -margin
	_badge.offset_top = margin
	_badge.reset_size()


func _centered_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _show(state: int, reason: String) -> void:
	_dim.visible = state == _net.Link.CONNECTING
	_badge.visible = state == _net.Link.RECONNECTING
	_reject.visible = state == _net.Link.REJECTED
	if state == _net.Link.REJECTED:
		_reject_label.text = REJECT_TEXT.get(reason, "Соединение отклонено (%s)" % reason)
	_retry.visible = reason == "kicked"
