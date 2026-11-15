class_name ResourceStation
extends StaticBody2D

## Базовый класс для всего, что может «закончиться»: еда, компьютеры.
##
## Наследник вызывает _set_empty(), когда ресурс кончился. Через
## refill_delay секунд станция зовёт модератора своей зоны (Zone —
## родитель станции): самого свободного, при равенстве — ближайшего.
## Он подходит и вызывает refill(). Если у зоны нет модераторов — зовёт
## модератора без зоны; если и такого нет — пополняется сама.
##
## Чтобы сделать новый ресурс: extends ResourceStation, напиши
## interact(player) и переопредели _on_refilled().

signal depleted(station: ResourceStation)
signal refilled(station: ResourceStation)

@export var refill_delay := 5.0
## Что всплывает, когда модератор пополнил (пусто — текст по умолчанию у наследника)
@export var refill_text := ""

var is_empty := false
## Сбит боссом (еда рассыпана). Пока босс жив, станция заблокирована:
## модератор не может её пополнить
var is_knocked := false
var _locked := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("resource_station")
	add_to_group(WorldSync.GROUP)   # в сети состояние (пусто, опрокинута, снесена) — с сервера
	# Не притягиваем к клетке: станция стоит ровно там, где её поставили
	# в редакторе (например, на столешнице, которая не совпадает с клеткой)
	_draw_above_furniture.call_deferred()


# Станция стоит на столе, но может задевать и соседний стол (стык двух
# столов): тогда при сортировке по Y стол «наезжает» на монитор или тарелку.
# Опускаем точку сортировки спрайта ниже всех тайлов мебели, которые он
# задевает, а картинку сдвигаем обратно — внешне ничего не двигается.
# Сама станция остаётся на месте (её клетку ищут модераторы и игрок).
func _draw_above_furniture() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return
	var rect := sprite.get_rect()
	rect.position += sprite.global_position
	var sort_y := sprite.global_position.y
	var need := sort_y
	for node in get_tree().get_nodes_in_group(Grid.OBJECTS_GROUP):
		var layer := node as TileMapLayer
		if layer == null or not layer.visible:
			continue
		for cell in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			var source := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			if data == null or source == null:
				continue
			var size := Vector2(source.get_tile_texture_region(layer.get_cell_atlas_coords(cell)).size)
			var center := layer.to_global(layer.map_to_local(cell))
			var tile_rect := Rect2(center - size / 2.0 - Vector2(data.texture_origin), size)
			var tile_sort := center.y + data.y_sort_origin
			if tile_rect.intersects(rect) and tile_sort >= need:
				need = tile_sort + 1.0
	if need > sort_y:
		var shift := need - sort_y
		y_sort_enabled = true   # спрайт сортируется сам по себе, по своей точке
		sprite.position.y += shift
		sprite.offset.y -= shift


## Пополнить ресурс (вызывает модератор)
func refill() -> void:
	if not is_empty or _locked:
		return
	is_empty = false
	is_knocked = false
	_on_refilled()
	refilled.emit(self)
	FloatingText.spawn(self, global_position + Vector2(0, -14),
			refill_text if refill_text != "" else "Пополнено!", Color(0.6, 1, 0.65))
	queue_redraw()


## Отметить, что ресурс кончился, и запустить таймер до модератора
func _set_empty() -> void:
	if is_empty:
		return
	is_empty = true
	depleted.emit(self)
	get_tree().create_timer(refill_delay).timeout.connect(_call_moderator)


func _call_moderator() -> void:
	if not is_empty or _locked or not is_inside_tree() or not Net.runs_world():
		return
	var moderator := _pick_moderator()
	if moderator:
		moderator.request_refill(self)
	else:
		refill()


## Босс опрокинул станцию: ресурс пропал, пока босс жив — не пополнить
func knock_over() -> void:
	is_knocked = true
	is_empty = true
	_locked = true
	depleted.emit(self)
	queue_redraw()


## Босс побеждён (или ушёл): через refill_delay модератор всё уберёт и пополнит
func release_after_boss() -> void:
	if not _locked:
		return
	_locked = false
	get_tree().create_timer(refill_delay).timeout.connect(_call_moderator)


## Босс снёс стол вместе со станцией: прячем её целиком (и обратно)
func set_removed(removed: bool) -> void:
	visible = not removed
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", removed)
	if removed:
		remove_from_group("interactable")
	else:
		add_to_group("interactable")


## Сеть: состояние для клиентов. Наследник дописывает своё (super() + ключи)
func net_state() -> Dictionary:
	return {"empty": is_empty, "knocked": is_knocked, "removed": not visible}


## Клиент: применить состояние с сервера (сигналы не шлём — ачивки и вызовы решает сервер)
func apply_net_state(state: Dictionary) -> void:
	is_empty = state.get("empty", is_empty)
	is_knocked = state.get("knocked", is_knocked)
	var removed: bool = state.get("removed", not visible)
	if removed != (not visible):   # снесена ли сейчас — не совпадает с присланным: применить
		set_removed(removed)
	queue_redraw()


## Зона, в которой стоит станция (ближайший родитель-Zone), или null
func get_zone() -> Zone:
	var node := get_parent()
	while node != null:
		if node is Zone:
			return node
		node = node.get_parent()
	return null


# Модераторы моей зоны (или без зоны, если своих нет): самый свободный,
# при равенстве — ближайший
func _pick_moderator() -> Moderator:
	var my_zone := get_zone()
	var own: Array[Moderator] = []
	var free_agents: Array[Moderator] = []
	for node in get_tree().get_nodes_in_group("moderator"):
		var moderator := node as Moderator
		if moderator == null:
			continue
		if my_zone != null and moderator.zone == my_zone:
			own.append(moderator)
		elif moderator.zone == null:
			free_agents.append(moderator)
	var candidates := own if not own.is_empty() else free_agents

	var best: Moderator = null
	for moderator in candidates:
		if best == null:
			best = moderator
			continue
		var load_diff := moderator.get_load() - best.get_load()
		var my_dist := global_position.distance_to(moderator.global_position)
		var best_dist := global_position.distance_to(best.global_position)
		if load_diff < 0 or (load_diff == 0 and my_dist < best_dist):
			best = moderator
	return best


## Переопредели в наследнике: вернуть ресурс в «полное» состояние
func _on_refilled() -> void:
	pass
