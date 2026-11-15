class_name BeanBagBoss
extends StaticBody2D

## Босс: мешок-мимик. Занимает 2×2 тайла, спрайт случайный — оранжевый
## или синий (skins). Бьют его «действием» (E), стоя рядом: каждый удар —
## одно деление здоровья, после удара он ненадолго неуязвим.
## Сидит, пока не победят (если lifetime > 0 — уползает через столько секунд).
##
## Анимации — в том же духе, что у игрока и NPC (сжатие и растяжение от пола):
## падает и плюхается при появлении, «дышит», время от времени «клацает»
## (вытягивается и подпрыгивает), от удара вспыхивает и сплющивается,
## побеждённый — сдувается.
##
## Появляется через BossDirector в точках BossSpawn. Позиция босса —
## центр его квадрата 2×2 (угол между четырьмя клетками).

signal hp_changed(hp: int, max_hp: int)
signal defeated
signal left   ## уполз, не дождавшись победы

const INVULNERABLE_TIME := 0.5
const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a);
}
"""

@export var max_hp := 3
@export var lifetime := 0.0   ## секунд до ухода (0 — сидит, пока не победят)
## Варианты спрайта, выбирается случайный (оранжевый / синий)
@export var skins: Array[Texture2D] = []

@export_group("Анимация")
@export var idle_squash := 0.04          ## «дыхание» в покое
@export var idle_speed := 2.2
@export var chomp_every := Vector2(2.0, 4.5)   ## пауза между «клацаньями», от и до (сек)

var title := "Мешок-Мимик"
var hp := 3
## Подсказка «E» над боссом поднимается выше, чем над обычным предметом
var hint_offset := Vector2(0, -14)

var _time := 0.0
var _age := 0.0
var _invulnerable := 0.0
var _flash := 0.0
var _chomp_in := 0.0
var _dead := false
var _anim: Tween          # текущая «большая» анимация (падение, клацанье, удар…)
var _sprite_base := Vector2.ZERO
var _material: ShaderMaterial

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	hp = max_hp
	if not skins.is_empty():
		_sprite.texture = skins.pick_random()
	_sprite_base = _sprite.position
	var shader := Shader.new()
	shader.code = FLASH_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_sprite.material = _material

	add_to_group("interactable")
	_displace_bodies()
	_land()
	_chomp_in = randf_range(chomp_every.x, chomp_every.y) + 1.0


## 4 клетки, которые занимает босс
func get_cells() -> Array[Vector2i]:
	var half := Grid.tile_size(self) / 2.0
	var top_left := Grid.world_to_cell(self, global_position - half)
	var cells: Array[Vector2i] = [top_left, top_left + Vector2i(1, 0),
			top_left + Vector2i(0, 1), top_left + Vector2i(1, 1)]
	return cells


func interact(_player: Player) -> void:
	if _dead or _invulnerable > 0.0:
		return
	hp -= 1
	_invulnerable = INVULNERABLE_TIME
	_flash = 1.0
	FloatingText.spawn(self, global_position + Vector2(0, -38), "-1", Color(1, 0.4, 0.35))
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		_die()
	else:
		_hit()


func _process(delta: float) -> void:
	_time += delta
	_invulnerable = maxf(0.0, _invulnerable - delta)
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_material.set_shader_parameter("flash", _flash)
	if _dead:
		return

	if lifetime > 0.0:
		_age += delta
		if _age >= lifetime:
			_leave()
			return

	if _is_animating():
		return
	# «Дыхание» в покое: (1 - cos) / 2 плавно идёт 0 → 1 → 0, сжимаемся от пола
	var squeeze := idle_squash * (1.0 - cos(_time * idle_speed)) / 2.0
	_sprite.scale = Vector2(1.0 + squeeze * 0.6, 1.0 - squeeze)
	# Время от времени — «клацанье»
	_chomp_in -= delta
	if _chomp_in <= 0.0:
		_chomp_in = randf_range(chomp_every.x, chomp_every.y)
		_chomp()


func _is_animating() -> bool:
	return _anim != null and _anim.is_running()


func _new_anim() -> Tween:
	if _anim:
		_anim.kill()
	_anim = create_tween()
	return _anim


# Появление: падает сверху вытянутым, плюхается, пружинит
func _land() -> void:
	_sprite.position = _sprite_base + Vector2(0, -90)
	_sprite.scale = Vector2(0.7, 1.4)
	_sprite.modulate.a = 0.0
	var t := _new_anim()
	t.tween_property(_sprite, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(_sprite, "position", _sprite_base, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_say_boom)
	t.tween_property(_sprite, "scale", Vector2(1.45, 0.6), 0.08)               # удар о пол
	t.tween_property(_sprite, "scale", Vector2(0.85, 1.2), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _say_boom() -> void:
	FloatingText.spawn(self, global_position + Vector2(0, -34), "БУМ!", Color(1, 0.85, 0.4))


# «Клацанье» мимика: присел → вытянулся с подскоком → плюхнулся → пружинка
func _chomp() -> void:
	var up := _sprite_base + Vector2(0, -6)
	var t := _new_anim().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", Vector2(1.18, 0.82), 0.12)
	t.tween_property(_sprite, "scale", Vector2(0.86, 1.2), 0.14)
	t.parallel().tween_property(_sprite, "position", up, 0.14)
	t.set_ease(Tween.EASE_IN)
	t.tween_property(_sprite, "scale", Vector2(1.15, 0.85), 0.12)
	t.parallel().tween_property(_sprite, "position", _sprite_base, 0.12)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", Vector2.ONE, 0.25)


# Удар: сплющился, вздрогнул из стороны в сторону, спружинил обратно
func _hit() -> void:
	_sprite.position = _sprite_base
	var t := _new_anim()
	t.tween_property(_sprite, "scale", Vector2(1.3, 0.72), 0.06)
	for dx: float in [-4.0, 4.0, -2.0, 0.0]:
		t.tween_property(_sprite, "position", _sprite_base + Vector2(dx, 0), 0.04)
	t.tween_property(_sprite, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# Побеждён: вздрагивает, сдувается в лепёшку и тает
func _die() -> void:
	_dead = true
	_finish()
	defeated.emit()
	_sprite.position = _sprite_base
	var t := _new_anim()
	t.tween_property(_sprite, "scale", Vector2(0.8, 1.3), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", Vector2(1.7, 0.12), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "modulate:a", 0.0, 0.4).set_delay(0.3)
	t.tween_callback(queue_free)


# Ушёл: сжимается и исчезает
func _leave() -> void:
	_dead = true
	_finish()
	FloatingText.spawn(self, global_position + Vector2(0, -30), "уполз…", Color(0.8, 0.8, 0.9))
	left.emit()
	var t := _new_anim()
	t.tween_property(_sprite, "scale", Vector2(1.2, 0.8), 0.1)
	t.tween_property(_sprite, "scale", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


## Тихо растаять (событие важнее — например, восстание зомби): без победы
## и без «уполз», просто прозрачность до нуля
func fade_away(duration := 0.8) -> void:
	if _dead:
		return
	_dead = true
	_finish()
	var t := _new_anim()
	t.tween_property(self, "modulate:a", 0.0, duration)
	t.tween_callback(queue_free)


func _finish() -> void:
	remove_from_group("interactable")
	$CollisionShape2D.set_deferred("disabled", true)


# Всех, кто стоит на месте босса (игроки, модераторы, мешки), отбрасывает
# в ближайшие свободные клетки — чтобы никто не застрял внутри
func _displace_bodies() -> void:
	var my_cells := get_cells()
	var half := Grid.tile_size(self)
	var area := Rect2(global_position - half, half * 2.0).grow(10.0)
	var taken: Array[Vector2i] = my_cells.duplicate()
	for node in get_tree().current_scene.get_children():
		if node is CollisionObject2D and node != self and (node as CollisionObject2D).visible:
			if ((node as CollisionObject2D).collision_layer & 1) != 0:
				taken.append(Grid.world_to_cell(self, (node as Node2D).global_position))
	for node in get_tree().current_scene.get_children():
		if node == self or not (node is CollisionObject2D) or not (node as CollisionObject2D).visible:
			continue
		var body := node as Node2D
		if not area.has_point(body.global_position):
			continue
		var cell := Grid.find_free_cell_near(self, my_cells, taken)
		taken.append(cell)
		var target := Grid.cell_to_world(self, cell)
		if body.has_method("displace_to"):
			body.displace_to(target)
		else:
			body.global_position = target
