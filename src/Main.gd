extends Node2D

## Точка входа: настраивает масштаб окна и открывает создание персонажа.

const DESIGN_RESOLUTION := Vector2i(3840, 2160) # UHD 4K


func _ready() -> void:
	_look_good()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_run_scene.call_deferred()


## Аналог Chickensoft `LookGood(WindowScaleBehavior.UIFixed, UHD4k)`:
## UI не растягивается вместе с окном, а масштабируется под нативное
## разрешение монитора относительно дизайн-разрешения темы.
func _look_good() -> void:
	var window := get_window()
	var screen_size := DisplayServer.screen_get_size(window.current_screen)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var factor := minf(
		float(screen_size.x) / DESIGN_RESOLUTION.x,
		float(screen_size.y) / DESIGN_RESOLUTION.y
	)
	if factor > 0.0: # в headless-режиме размер экрана равен 0
		window.content_scale_factor = factor


func _run_scene() -> void:
	get_tree().change_scene_to_file("res://src/character/CharacterCreator.tscn")
