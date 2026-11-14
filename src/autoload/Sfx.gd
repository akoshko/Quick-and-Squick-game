extends Node

## Звуки игры (autoload "Sfx"). Из любого скрипта:
##     Sfx.play(&"quest")                          — звук интерфейса (слышен везде)
##     Sfx.play_at(&"nom", global_position)        — звук в мире: тише вдали
##     Sfx.speak(self, "Привет!")                  — «голос» NPC по слогам
##
## Повторяющиеся звуки каждый раз звучат чуть по-разному: высота тона
## случайно гуляет (и не совпадает с прошлым разом). Одинаковых звуков
## одновременно играет не больше MAX_SAME — чтобы толпа зомби не оглушала.
## Звуки локальные: в сетевой игре каждый клиент играет их сам.

const SOUNDS := {
	&"beep": preload("res://src/audio/beep.wav"),
	&"boop": preload("res://src/audio/boop.wav"),
	&"crash": preload("res://src/audio/crash.wav"),
	&"nom": preload("res://src/audio/nom.wav"),
	&"growl": [preload("res://src/audio/growl1.wav"), preload("res://src/audio/growl2.wav")],
	&"rustle": preload("res://src/audio/rustle.wav"),
	&"voice": preload("res://src/audio/voice.wav"),
	&"achievement": preload("res://src/audio/achievement.wav"),
	&"quest": preload("res://src/audio/quest.wav"),
}
## Громкость по умолчанию (дБ) — чтобы звуки были ровнее друг с другом
const VOLUME := {
	&"beep": -8.0, &"boop": -8.0, &"crash": -6.0, &"nom": -2.0, &"growl": -4.0,
	&"rustle": -6.0, &"voice": -3.0, &"achievement": -4.0, &"quest": -5.0,
}
const MAX_SAME := 4             # сколько одинаковых звуков может звучать сразу
const HEAR_DISTANCE := 480.0    # дальше (px мира) звуки в мире не слышны
const VOICE_STEP := 0.065       # пауза между слогами голоса NPC
const VOICE_MAX_SYLLABLES := 14

var _playing := {}       # имя -> сколько сейчас звучит
var _last_pitch := {}    # имя -> прошлая высота (чтобы повтор был другим)
var _speech := {}        # говорящий -> номер реплики (новая реплика обрывает старую)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # звук достижения — и при открытом журнале
	GameManager.achievement_unlocked.connect(func(_id: StringName) -> void: play(&"achievement", 0.0))
	Quests.quest_added.connect(func(_quest: Quest) -> void: play(&"quest", 0.0))


## Звук интерфейса: одинаково слышен везде. pitch — базовая высота
## (к ней добавляется случайный разброс pitch_jitter)
func play(sound: StringName, pitch_jitter := 0.08, volume_db := 0.0, pitch := 1.0) -> void:
	var player := AudioStreamPlayer.new()
	if _setup(player, sound, pitch_jitter, volume_db, pitch):
		add_child(player)
		player.play()


## Звук в мире: в точке world_pos, затихает с расстоянием до камеры
func play_at(sound: StringName, world_pos: Vector2, pitch_jitter := 0.1, volume_db := 0.0,
		pitch := 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.max_distance = HEAR_DISTANCE
	player.attenuation = 1.5
	if _setup(player, sound, pitch_jitter, volume_db, pitch):
		scene.add_child(player)
		player.global_position = world_pos
		player.play()


## «Голос» как в Animal Crossing: по короткому слогу на каждые пару букв,
## высота каждого слога чуть своя. pitch — тембр говорящего (1 — обычный).
## Звучит без затухания: NPC говорит, только когда игрок рядом.
func speak(speaker: Node2D, text: String, pitch := 1.0) -> void:
	var line: int = _speech.get(speaker, 0) + 1
	_speech[speaker] = line
	var letters := 0
	for c in text:
		if c.strip_edges() != "" and not c in ".,!?…-—«»\"":
			letters += 1
	var syllables := clampi(ceili(letters / 2.0), 1, VOICE_MAX_SYLLABLES)
	for i in syllables:
		if not is_instance_valid(speaker) or _speech.get(speaker) != line:
			return   # говорящий исчез или начал новую реплику
		play(&"voice", 0.0, 0.0, pitch * randf_range(0.88, 1.18))
		await get_tree().create_timer(VOICE_STEP).timeout


# Настроить плеер: поток (если вариантов несколько — случайный), высота, громкость
func _setup(player: Node, sound: StringName, pitch_jitter: float, volume_db: float, pitch: float) -> bool:
	if not SOUNDS.has(sound):
		push_warning("Sfx: нет звука \"%s\"" % sound)
		player.free()
		return false
	if _playing.get(sound, 0) >= MAX_SAME:
		player.free()
		return false
	var stream: Variant = SOUNDS[sound]
	if stream is Array:
		stream = (stream as Array).pick_random()
	player.set("stream", stream)
	player.set("volume_db", VOLUME.get(sound, 0.0) + volume_db)
	player.set("pitch_scale", pitch * _pick_pitch(sound, pitch_jitter))
	_playing[sound] = _playing.get(sound, 0) + 1
	player.connect("finished", player.queue_free)
	# Считаем по выходу из дерева: звук в мире пропадает и при смене сцены
	player.tree_exiting.connect(_on_player_gone.bind(sound))
	return true


# Случайная высота, заметно отличающаяся от прошлой у этого же звука
func _pick_pitch(sound: StringName, jitter: float) -> float:
	if jitter <= 0.0:
		return 1.0
	var last: float = _last_pitch.get(sound, 1.0)
	var pitch := randf_range(1.0 - jitter, 1.0 + jitter)
	for i in 4:
		if absf(pitch - last) >= jitter * 0.5:
			break
		pitch = randf_range(1.0 - jitter, 1.0 + jitter)
	_last_pitch[sound] = pitch
	return pitch


func _on_player_gone(sound: StringName) -> void:
	_playing[sound] = maxi(0, _playing.get(sound, 1) - 1)
