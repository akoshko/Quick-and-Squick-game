extends Node

const MAP := "res://src/game/HackathonMap.tscn"

var _checks := 0
var _failures := 0
var _game: Node2D
var _player: Player
var _journal: QuestPanel
var _progress: QuestProgress


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	seed(20261113)
	var tree := get_tree()
	tree.current_scene = null
	await _load_scene("res://src/Main.tscn")
	while tree.current_scene and tree.current_scene.scene_file_path != "res://src/character/CharacterCreator.tscn":
		await tree.scene_changed
	var creator := tree.current_scene
	_check(creator != null, "Main opens the character creator")
	_check(get_window().size == Vector2i(390, 844), "Portrait startup uses a 390 × 844 viewport")
	var hoodie_row: Dictionary = creator._rows[creator.Row.HOODIE]
	var hoodie_before: String = hoodie_row.value.text
	hoodie_row.prev.pressed.emit()
	_check(hoodie_row.value.text != hoodie_before, "Previous hoodie button changes the selected appearance")
	creator._randomize_all()
	creator._start_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if tree.current_scene == null or tree.current_scene.scene_file_path != MAP:
		_check(false, "Start button opens the game map")
		tree.quit(1)
		return
	_game = tree.current_scene
	_player = _game.get_node("Player1")
	_journal = _game.get_node("QuestPanel")
	_progress = _game.get_node("QuestProgress")
	_test_profile()
	await _test_map_and_input()
	await _test_quests()
	await _test_hide_and_seek()
	await _test_boss()
	await _test_tired_moderators()
	await _test_zombie_uprising()
	if _failures == 0:
		print("Completed %d gameplay checks" % _checks)
	else:
		print("FAIL: %d of %d gameplay checks" % [_failures, _checks])
	tree.quit(int(_failures > 0))


func _load_scene(path: String) -> void:
	if get_tree().change_scene_to_file(path) != OK:
		_check(false, "Scene loads: " + path)
		get_tree().quit(1)
		return
	await get_tree().scene_changed


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _test_profile() -> void:
	_check(_game.scene_file_path == MAP, "Creator starts the new map")
	var profile := PlayerProfile.to_dict()
	PlayerProfile.set_look("invalid", "invalid", "invalid")
	PlayerProfile.load_profile()
	_check(PlayerProfile.to_dict() == profile, "Character creator saves a profile that can be reloaded")
	var clean := CharacterLook.sanitize({"hoodie": "invalid", "hair_style": "invalid",
		"hair_color": "invalid", "title_first": "invalid", "title_second": "invalid"})
	_check(clean.hoodie == CharacterLook.HOODIES[0].id and clean.hair_style == CharacterLook.HAIR_STYLES[0].id
		and clean.hair_color == CharacterLook.HAIR_COLORS[0].id, "Invalid appearance falls back to valid options")
	_check(_player._sprite.texture == PlayerProfile.texture() and _player._nameplate.text == PlayerProfile.nickname,
		"The local player uses the saved sprite and nickname")


func _test_map_and_input() -> void:
	var camera: PlayerCamera = _game.get_node("PlayerCamera")
	var viewport_size := get_viewport().get_visible_rect().size
	var zoom_factor := minf(viewport_size.y, viewport_size.x * 1.5) / (camera.visible_rows * Grid.tile_size(camera).y)
	_check(camera.zoom.is_equal_approx(Vector2.ONE * zoom_factor), "Camera keeps the portrait map legible")
	_check(camera._midpoint() == _player.global_position, "Hidden second player does not pull the camera")
	var mobile: MobileControls = _game.get_node("MobileControls")
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		var button: TouchScreenButton = mobile._dpad.get(action)
		_check(button != null and button.action == action and button.passby_press,
			"Portrait touch button sends " + action)
	_check(mobile.visible and mobile._action_button.action == "action", "Portrait action button is enabled")

	var spawn := Grid.world_to_cell(_player, _player.global_position)
	_check(Grid.cell_to_world(_player, spawn) == _player.global_position and not Grid.is_solid_cell(_player, spawn),
		"Player spawns centered on a walkable cell")
	# Проверки движения — на открытом месте рядом со спавном, чтобы не зависеть
	# от того, куда на карте поставили игрока
	var start := _open_cell_near(spawn)
	_player.displace_to(Grid.cell_to_world(_player, start))
	var goals: Array[Vector2i] = [start + Vector2i(0, 3)]
	var blocked: Array[Vector2i] = [start + Vector2i.DOWN]
	var direct_route := Grid.find_path(_player, start, goals)
	var route := Grid.find_path(_player, start, goals, blocked)
	_check(blocked[0] in direct_route and route.size() > direct_route.size(),
		"Blocking the shortest route forces a detour")
	_check(not route.is_empty() and route.back() in goals and not blocked[0] in route,
		"Moderator pathfinding routes around dynamic blockers")
	for i in range(route.size()):
		var previous := start if i == 0 else route[i - 1]
		var difference := (route[i] - previous).abs()
		_check(difference.x + difference.y == 1 and not Grid.is_solid_cell(_player, route[i]),
			"Moderator route uses walkable cardinal steps")

	Input.action_press("move_right")
	Input.action_press("move_down")
	_check(_player._read_direction() == Vector2i(1, 1), "Two directions generate diagonal movement")
	Input.action_press("move_left")
	_check(_player._read_direction() == Vector2i.DOWN, "Opposite controls cancel on one axis")
	for action in ["move_right", "move_down", "move_left"]:
		Input.action_release(action)
	var start_position := _player.global_position
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _wait(0.12)
	Input.action_release("move_right")
	Input.action_release("move_down")
	await _wait(0.15)
	var displacement := _player.global_position - start_position
	_check(displacement.x > 0 and is_equal_approx(displacement.x, displacement.y),
		"Holding both controls moves the player diagonally")
	var theme: Theme = load("res://assets/GohuTheme.tres")
	_check(theme.default_font is FontFile and theme.default_font.multichannel_signed_distance_field,
		"GohuFont uses MSDF for world text")


# Ближайшая к from клетка, вокруг которой свободно 3 клетки в ширину и 5 вниз
func _open_cell_near(from: Vector2i) -> Vector2i:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var open := true
		for x in range(-1, 2):
			for y in range(-1, 4):
				if Grid.is_solid_cell(_player, cell + Vector2i(x, y)):
					open = false
		if open:
			return cell
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + dir
			if not seen.has(next) and not Grid.is_solid_cell(_player, next) and seen.size() < 2000:
				seen[next] = true
				queue.append(next)
	return from


func _test_quests() -> void:
	var npc: NPC = _game.get_node("NPC")
	_check(npc.lines.size() == 4 and npc.lines[0] == "Привет! Удачного Хакатона!",
		"Elena greets new players with four onboarding lines")
	var arrows: Array[Vector2] = []
	for line in npc.lines:
		arrows.append(NPC.parse_line(line)[1])
	_check(arrows == [Vector2.ZERO, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT],
		"Onboarding lines point left to coworking, down to snacks and right to the bean bag fortress")
	_check(NPC.parse_line("Перекусить в зоне снэков [down]")[0] == "Перекусить в зоне снэков"
		and NPC.parse_line("Без стрелки")[1] == Vector2.ZERO, "Arrow markers are removed from the bubble text")
	var bag: BeanBag = _game.get_node("BeanBag1")
	_check(npc.npc_name == "Елена Анатольевна" and npc.dialogue_quest_id == "main",
		"Map applies the quest-specific NPC override")
	var bubble_style := npc._panel.get_theme_stylebox("panel")
	_check(bubble_style.content_margin_left == 8 and bubble_style.content_margin_top == 6,
		"Dialogue bubble keeps the increased padding")
	Quests.complete("push_bean_bag")
	_check(not Quests.is_done("push_bean_bag"), "Later quest steps cannot be completed early")
	await _talk(npc)
	_check(Quests.is_done("talk_npc") and not Quests.is_done("main"), "NPC dialogue advances only the first step")
	_check(_progress._status.text == Quests.find("push_bean_bag").title, "HUD shows the next step")
	bag.displace_to(Grid.cell_to_world(bag, Vector2i(15, 8)))
	var bag_start := bag.global_position
	_player.facing = Vector2i.DOWN
	_player.displace_to(bag_start - Vector2(0, 32))
	_check(_player._find_target() == bag, "Player action targets the bean bag in front")
	await _press_action()
	await _wait(0.5)
	_check(bag.global_position == bag_start + Vector2(0, 32), "Bean bag moves one cell when pushed")
	_check(Quests.is_done("main") and _progress._done_icon.visible, "Final step completes the quest and shows a checkmark")
	_check(_progress._done_icon.custom_minimum_size.x >= _progress._status.get_theme_font_size("font_size"),
		"Completed quest HUD checkmark is at least as large as its status text")
	_check(GameManager.has_achievement(&"first_steps"), "Main quest awards First Steps")
	npc.interact(_player)
	_check(npc._label.text == "Привет!", "Quest-gated NPC switches to a greeting after completion")
	npc.interact(_player)
	await _wait(0.5)
	_check(Quests.selected_quest_id == "never_too_late", "HUD advances after the completion delay")
	_progress._open_button.pressed.emit()
	var rows := _journal._list.get_root()
	_check(get_tree().paused and rows.get_child_count() == 3, "Journal opens and lists all three quests together")
	_check(rows.get_child(0).get_metadata(0) == "never_too_late" and rows.get_child(2).get_metadata(0) == "main",
		"Journal lists open quests before completed ones")
	_check(rows.get_child(2).get_icon(0) == QuestPanel.DONE_ICON and not rows.get_child(2).is_selectable(0),
		"Completed journal rows have a checkmark and cannot be selected")
	_check(_journal._list.get_theme_constant("icon_max_width") >= _journal._list.get_theme_font_size("font_size"),
		"Completed journal checkmarks are at least as large as the row text")
	rows.get_child(1).select(0)
	await get_tree().process_frame
	_check(not get_tree().paused and Quests.selected_quest_id == "work_time",
		"Selecting a journal row closes it and tracks the chosen quest")

	var laptop: Laptop = _game.get_node("ZoneHackathon/Hackathon9")
	laptop.refill_delay = 0.01
	for i in range(laptop.pokes_needed - 1):
		laptop.interact(_player)
	_check(not laptop.is_empty and not Quests.is_done("poke_laptop"), "Laptop needs multiple interactions")
	laptop.interact(_player)
	_check(laptop.is_empty and Quests.is_done("work_time"), "Laptop freezes and completes the work quest")
	await _wait(5.0)
	_check(not laptop.is_empty and laptop._pokes == 0, "Moderator reaches and repairs the laptop")

	var snacks: Array = _game.get_node("ZoneSnack").get_stations()
	for kind in [SnackStation.Kind.APPLE, SnackStation.Kind.COOKIE]:
		var id := &"steve_jobs" if kind == SnackStation.Kind.APPLE else &"clean_cookies"
		var matching := snacks.filter(func(snack: SnackStation) -> bool: return snack.kind == kind)
		_check(matching.size() > 1, "Map has multiple snack stations for " + String(id))
		for i in range(matching.size()):
			var snack: SnackStation = matching[i]
			for portion in range(snack.portions):
				snack.interact(_player)
			_check(snack.is_empty, "Eating all portions empties a snack station")
			_check(GameManager.has_achievement(id) == (i == matching.size() - 1),
				"Snack achievement waits for the final station: " + String(id))
	_check(Quests.all_done(), "Completing the snack and laptop quests finishes the initial quest list")
	var refill: SnackStation = snacks.front()
	refill.refill()
	_check(not refill.is_empty and refill._left == refill.portions, "Refilling snacks restores all portions")


func _press_action() -> void:
	await get_tree().physics_frame
	var event := InputEventAction.new()
	event.action = &"action"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().physics_frame
	event = InputEventAction.new()
	event.action = &"action"
	Input.parse_input_event(event)
	await get_tree().process_frame


func _talk(npc: NPC) -> void:
	var cell := Grid.world_to_cell(npc, npc.global_position)
	_player.displace_to(Grid.cell_to_world(npc, cell + Vector2i.DOWN))
	for i in range(npc.lines.size() + 1):
		npc.interact(_player)
		await get_tree().process_frame


func _test_hide_and_seek() -> void:
	var hideout = _game.get_node("HideAndSeek")
	var moderator: Moderator = hideout.moderator
	var participant: NPC = hideout.get_node("Participant")
	var id := &"hide_and_seek"
	var hidden_card: PanelContainer = _journal._cards_by_id[id]
	var title: Label = hidden_card.get_node("Row/Labels/Title")
	var description: Label = hidden_card.get_node("Row/Labels/Description")
	_check(title.text == "Скрытое достижение" and description.text != QuestPanel.ACHIEVEMENTS[id][1],
		"Hidden achievement conceals its title and description")
	_check(not hideout.is_in_group("interactable") and not participant.visible,
		"Hideout and Sergey are unavailable before the quest")
	_check(moderator.lines == PackedStringArray(hideout.INTRO), "Moderator offers the hide-and-seek quest")
	await _talk(moderator)
	_check(Quests.selected_quest_id == id and hideout.is_in_group("interactable"),
		"Finishing the introduction tracks the quest and activates the hideout")
	_check(not participant.visible and not participant.is_in_group("interactable"), "Sergey stays hidden until discovery")
	var hideout_cell := Grid.world_to_cell(_player, hideout.global_position)
	_player.displace_to(Grid.cell_to_world(_player, hideout_cell + Vector2i.DOWN))
	_player.facing = Vector2i.UP
	_check(_player._find_target() == hideout, "Hideout is reachable through the player interaction")
	await _press_action()
	_check(participant.visible and participant.is_in_group("interactable") and not hideout.is_in_group("interactable"),
		"Searching reveals Sergey exactly once")
	_check(participant.global_position.is_equal_approx(Grid.cell_to_world(participant, hideout_cell)),
		"Sergey appears at the hideout on the grid")
	_check(_game.y_sort_enabled and participant.npc_name == "Сергей" and participant.lines == PackedStringArray(["Доброе утро"])
		and participant.sprite_texture == CharacterLook.build("red", "short", "blonde"),
		"Sergey uses the configured name, dialogue and appearance on the y-sorted map")
	await _talk(participant)
	_check(Quests.is_done(hideout.FIND_ID) and not Quests.is_done(id), "Finding Sergey unlocks the report step")
	_check(not participant.visible and moderator.lines == PackedStringArray(hideout.THANKS),
		"Sergey is hidden again and the moderator has the report dialogue")
	await _talk(moderator)
	_check(Quests.is_done(id) and GameManager.has_achievement(id), "Reporting to the moderator completes hide-and-seek")
	_check(title.text == QuestPanel.ACHIEVEMENTS[id][0] and description.text == QuestPanel.ACHIEVEMENTS[id][1],
		"Unlocking reveals the hidden achievement title and description")
	_check(moderator.lines == hideout._moderator_lines, "Moderator returns to the configured scene dialogue")


func _test_boss() -> void:
	var director: BossDirector = _game.get_node("BossDirector")
	var snacks: Array = _game.get_node("ZoneSnack").get_stations()
	var spawn: BossSpawn = director.get_node("SpawnSnack")
	var snack: SnackStation = snacks.front()
	snack.refill()
	director.spawn_boss(spawn)
	var boss := director._boss
	var quest_id := director._quest_id
	_check(Quests.selected_quest_id == quest_id and boss.title == spawn.boss_title and director._bar.health_bottom() > 0,
		"Boss spawns with its local title, visible health bar, and tracked quest")
	_check(boss.get_cells().size() == 4 and snacks.all(func(station: SnackStation) -> bool: return station.is_knocked),
		"Boss occupies four cells and knocks over the affected zone")
	snack.refill()
	_check(snack.is_empty and snack.is_knocked, "Knocked stations cannot be refilled while the boss is active")
	director.spawn_boss()
	_check(director._boss == boss and director._quest_id == quest_id, "Only one boss can be alive at a time")
	boss.interact(_player)
	boss.interact(_player)
	_check(boss.hp == director.boss_hp - 1, "Boss ignores hits during the invulnerability window")

	var popups := _journal._achievement_popups
	var recent := popups.get_child_count()
	_journal.show_achievement_notification("Первое", QuestPanel.EARNED_MEDAL)
	_journal.show_achievement_notification("Второе", QuestPanel.EARNED_MEDAL)
	var first := popups.get_child(recent) as Control
	var second := popups.get_child(recent + 1) as Control
	await get_tree().process_frame
	await get_tree().process_frame
	_check(first.get_node("Row/Labels/Description").text == "Первое"
		and second.get_node("Row/Labels/Description").text == "Второе"
		and first.get_global_rect().end.y <= second.get_global_rect().position.y,
		"Two rapid achievement notifications stack in arrival order")
	for card: Control in popups.get_children():
		var rect := card.get_global_rect()
		_check(rect.position.y >= director._bar.health_bottom()
			and not rect.intersects(_progress._panel.get_global_rect())
			and not rect.intersects(_progress._open_button.get_global_rect()),
			"Each portrait notification leaves the boss bar and quest controls clear")
	_journal.open()
	_check(get_tree().paused and not popups.visible, "Notifications hide while the journal is open")
	await _wait(5.5)
	_journal.close()
	_check(popups.visible and is_instance_valid(first) and is_instance_valid(second),
		"Opening and closing the journal preserves both notifications")

	for i in range(boss.hp):
		await _wait(0.55)
		boss.interact(_player)
	_check(Quests.is_done(quest_id) and GameManager.has_achievement(&"boss_victory"),
		"Defeating the boss completes its quest and awards the achievement")
	await _wait(0.85)
	_check(director._boss == null and director._bar.health_bottom() == 0 and not snack._locked,
		"Boss defeat hides its health bar and releases the knocked stations")
	var popup_count := popups.get_child_count()
	GameManager.unlock_achievement(&"boss_victory")
	_check(popups.get_child_count() == popup_count, "Unlocking the same achievement again produces no notification")

	director._time_left = 0.1
	await _wait(0.2)
	_check(director._boss != null and director._spawn != spawn,
		"The timer spawns the next boss at a different point")
	await _wait(6.0)
	_check(Quests.find(quest_id) == null, "The completed boss quest expires from the journal")
	_check(not is_instance_valid(first) and not is_instance_valid(second), "Both notifications expire after gameplay resumes")


func _test_tired_moderators() -> void:
	var zombie: ZombieModerator = _game.get_node("SokobanRoom/Zombie1")
	_check(zombie.asleep and zombie.npc_name == "Уставший модератор",
		"Sleeping moderators are just tired, not zombies")
	zombie.rise()
	await _wait(1.2)
	_check(not zombie.asleep and zombie.npc_name == "Зомби-модератор", "A risen moderator becomes a zombie")
	zombie._shout()
	await get_tree().process_frame
	_check(zombie._bubble.visible and zombie._label.text in zombie.shouts, "Risen zombies shout one of their lines")
	zombie.fall_asleep()
	_check(zombie.asleep and zombie.npc_name == "Уставший модератор", "Falling asleep makes the moderator tired again")


func _test_zombie_uprising() -> void:
	var uprising: ZombieUprising = _game.get_node("ZombieUprising")
	var terminal: ZombieTerminal = _game.get_node("SokobanRoom/Computer")
	var zombie: ZombieModerator = _game.get_node("ZombieUprising/Zombie4")
	_check(zombie.walk_speed <= _player.move_speed / 2.0, "Zombies are much slower than players")
	_check(is_equal_approx(uprising.time_limit, 180.0), "Players get three minutes to collect coffee")

	# Живой босс тает, когда начинается восстание, и новые не появляются
	var director: BossDirector = _game.get_node("BossDirector")
	director.spawn_boss()
	await _wait(0.3)
	var boss: BeanBagBoss = director._boss
	var boss_quest := director._quest_id

	# Не успели: зомби уходят спать без победы и без достижения
	_player.displace_to(Grid.cell_to_world(_player, uprising.respawn_cell))
	for i in terminal.pokes_needed:
		terminal.interact(_player)
	await _wait(0.5)
	_check(is_instance_valid(boss) and boss.modulate.a < 1.0 and not boss.is_in_group("interactable")
		and Quests.find(boss_quest) == null and director._boss == null,
		"Starting the zombie uprising fades the boss away and removes its quest")
	await _wait(0.6)
	_check(not is_instance_valid(boss), "The faded boss is removed")
	director.spawn_boss()
	_check(director._boss == null, "Bosses do not appear during the zombie uprising")
	_check(uprising.state == ZombieUprising.State.ACTIVE and uprising._counter._time_label.text != "",
		"Breaking the zombie computer starts the uprising with a timer")
	uprising.time_left = 0.05
	await _wait(0.3)
	var banner: BossBar = get_tree().get_first_node_in_group("boss_bar")
	_check(uprising.is_failed and banner._banner.text == ZombieUprising.FAIL_TEXT
		and Quests.find(ZombieUprising.QUEST_ID) == null, "Running out of time shows the red failure banner")
	_check(not GameManager.has_achievement(ZombieUprising.ACHIEVEMENT), "Failing the uprising gives no achievement")
	for i in 150:
		if uprising.state == ZombieUprising.State.IDLE:
			break
		await _wait(0.1)
	_check(uprising.state == ZombieUprising.State.IDLE and terminal.cooldown_left > 0.0 and not terminal.is_broken,
		"After failing, zombies go back to sleep and the computer reboots")

	# Успели: конфетти и достижение тем, кто подобрал кофе
	terminal.cooldown_left = 0.0
	for i in terminal.pokes_needed:
		terminal.interact(_player)
	await _wait(0.5)
	while uprising.state == ZombieUprising.State.ACTIVE and not uprising._cups.is_empty():
		uprising.take_coffee(uprising._cups.keys()[0], _player)
	_check(not uprising.is_failed and uprising.state == ZombieUprising.State.CALMING
		and GameManager.has_achievement(ZombieUprising.ACHIEVEMENT), "Collecting all coffee wins and awards the achievement")
