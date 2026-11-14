extends Node2D

## Основная сцена уровня: сбрасывает состояние игры и квесты при старте
## и выдаёт достижения за опустошённые тарелки.

var _snack_stations: Array[SnackStation] = []


func _ready() -> void:
	GameManager.reset()
	Quests.reset()
	var snack_zone := get_node_or_null("ZoneSnack") as Zone
	if snack_zone == null:
		return
	for station in snack_zone.get_stations():
		if station is SnackStation:
			_snack_stations.append(station)
			station.depleted.connect(_on_snack_depleted)


func _on_snack_depleted(station: SnackStation) -> void:
	for snack in _snack_stations:
		if snack.kind == station.kind and (not snack.is_empty or snack.is_knocked):
			return
	match station.kind:
		SnackStation.Kind.APPLE:
			GameManager.unlock_achievement(&"steve_jobs")
		SnackStation.Kind.COOKIE:
			GameManager.unlock_achievement(&"clean_cookies")
