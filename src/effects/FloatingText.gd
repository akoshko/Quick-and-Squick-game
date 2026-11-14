class_name FloatingText

## Всплывающий текст в мире: появляется над точкой, улетает вверх и тает.
## Использование из любого узла:
##     FloatingText.spawn(self, global_position + Vector2(0, -20), "Ням!")

const FONT_SIZE := 8      # в пикселях мира, камера сама увеличит
const RISE := 14.0        # на сколько пикселей улетает вверх
const DURATION := 0.9


static func spawn(from: Node, world_pos: Vector2, text: String,
		color := Color(1, 1, 1)) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15))
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 100          # поверх всего уровня
	label.z_as_relative = false

	# Кладём в сцену уровня, а не в предмет: предмет может исчезнуть
	# (съеденное печенье), а текст должен долететь
	from.get_tree().current_scene.add_child(label)
	label.reset_size()
	label.global_position = world_pos - Vector2(label.size.x / 2.0, label.size.y)

	var t := label.create_tween().set_parallel()
	t.tween_property(label, "global_position:y", label.global_position.y - RISE, DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, DURATION * 0.5).set_delay(DURATION * 0.5)
	t.chain().tween_callback(label.queue_free)
