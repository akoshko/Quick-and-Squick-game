class_name UiSpacing
extends RefCounted

## One step is 4 logical pixels in the 390 × 844 portrait viewport.
static func step(viewport_size: Vector2) -> int:
	return maxi(2, roundi(minf(viewport_size.y, viewport_size.x * 1.45) * 0.007))


static func inset(container: MarginContainer, padding: int) -> void:
	for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		container.add_theme_constant_override(side, padding)
