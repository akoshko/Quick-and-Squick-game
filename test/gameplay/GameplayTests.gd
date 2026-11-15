extends Node

const MAP := "res://src/game/HackathonMap.tscn"
## Пир, от имени которого сервер действует в проверках: подключённым не числится и world_ready
## не подтверждал, поэтому личные события ему (Net.forward_personal) просто не уходят
const FAKE_PEER := 7

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
	await _test_journal_profile()
	await _test_notification_overflow()
	_test_network_profile()
	_test_network_emotes()
	await _test_map_and_input()
	await _test_quests()
	await _test_hide_and_seek()
	await _test_boss()
	await _test_tired_moderators()
	await _test_net_interact_pushes_bag()
	await _test_boss_knocks_back_network_players()
	_test_personal_targets()
	_test_client_quest_steps()
	_test_replay_suppresses_world_fx()
	_test_client_bag_mirror()
	await _test_client_boss_view()
	await _test_server_boss_rewards()
	await _test_client_zombie_view()
	_test_world_sync_diff()
	await _test_world_sync_glide()
	_test_world_sync_replay_call()
	_test_server_forwards_personal()
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


func _test_journal_profile() -> void:
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	_check(_journal.is_open() and get_tree().paused, "Esc opens the journal in solo play")
	var tabs := _journal._tabs
	var profile := tabs.get_node("Профиль") as ScrollContainer
	await get_tree().process_frame
	var profile_rect := tabs.get_tab_bar().get_tab_rect(tabs.get_tab_idx_from_control(profile))
	_check(profile_rect.has_area() and profile_rect.end.x <= tabs.size.x,
		"The profile tab is visible alongside the existing journal tabs in portrait mode")
	tabs.current_tab = tabs.get_tab_idx_from_control(profile)
	await get_tree().process_frame
	_check(profile.is_visible_in_tree() and _journal._profile_preview.texture == PlayerProfile.texture()
		and _journal._profile_name.text == PlayerProfile.nickname, "Profile tab shows the saved player appearance")
	var inventory := _journal._profile_layout.get_child(0) as Control
	var preview_panel := _journal._profile_layout.get_child(1) as Control
	_check(preview_panel.position.y >= inventory.position.y + inventory.size.y,
		"Portrait profile places the preview below the inventory")
	var layout_rect := _journal._profile_layout.get_global_rect()
	var profile_rect_global := profile.get_global_rect()
	_check(layout_rect.position.x > profile_rect_global.position.x
		and layout_rect.position.y > profile_rect_global.position.y
		and layout_rect.end.x < profile_rect_global.end.x,
		"The profile content is inset from the top and both sides")
	var starter := _journal._accessory_slots[CharacterLook.STARTER_ACCESSORY]
	var locked := _journal._accessory_slots[&"first_steps"]
	_check(_journal._accessory_grid.get_child_count() == CharacterLook.ACCESSORIES.size()
		and starter.modulate == Color.WHITE and locked.modulate.r < 1.0
		and locked.disabled and locked.get_node("Content/Icon").texture == CharacterLook.accessory_icon("first_steps"),
		"Each accessory has a visible icon and locked slots are dimmed")
	var orange := _journal._accessory_slots[&"orange"]
	var blue := _journal._accessory_slots[&"blue"]
	var apple := _journal._accessory_slots[&"apple"]
	var empty := _journal._accessory_slots[CharacterLook.NO_ACCESSORY]
	orange.pressed.emit()
	blue.pressed.emit()
	_check(_journal._nickname_color_grid.get_child_count() == CharacterLook.NICKNAME_COLORS.size()
		and orange.disabled and blue.disabled and PlayerProfile.nickname_color == CharacterLook.DEFAULT_NICKNAME_COLOR
		and not _journal._accessory_slots.has(&"boss_victory") and apple.disabled
		and not empty.disabled and empty.accessibility_name == "Нет аксессуара",
		"Nickname rewards start locked and the removed medal has no inventory slot")
	_check(_journal._profile_preview.get_parent().get_child_count() == 2,
		"The profile preview contains the player sprite and nickname without reward descriptions")
	var portrait_slot_side := starter.size.x
	_check(portrait_slot_side > 0 and _journal._accessory_slots.values().all(
		func(slot: Button) -> bool: return slot.size == Vector2(portrait_slot_side, portrait_slot_side)
	), "Portrait slots are uniform squares across grids of different lengths and availability")
	_check(empty.position.x < starter.position.x and starter.position.x < locked.position.x
		and locked.position.y == empty.position.y and apple.position.y > empty.position.y
		and apple.position.x == empty.position.x,
		"Portrait inventory fills the first row left to right before wrapping")
	var portrait_size := get_window().size
	get_window().size = Vector2i(844, 390)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(preview_panel.position.x >= inventory.position.x + inventory.size.x,
		"Landscape profile places the preview to the right of the inventory")
	var preview_bounds := _journal._profile_preview.get_global_rect().merge(_journal._profile_name.get_global_rect())
	_check(preview_bounds.get_center().distance_to(preview_panel.get_global_rect().get_center()) <= 1.0,
		"The sprite and nickname are centered together in the preview panel")
	var landscape_slot_side := starter.size.x
	_check(landscape_slot_side > 0 and _journal._accessory_slots.values().all(
		func(slot: Button) -> bool: return slot.size == Vector2(landscape_slot_side, landscape_slot_side)
	), "Landscape slots remain uniform squares")
	_check(locked.position.x < apple.position.x and apple.position.y == empty.position.y,
		"The wider inventory fits all four items on one row")
	get_window().size = portrait_size
	tabs.current_tab = 0
	get_viewport().push_input(escape)
	_check(not _journal.is_open() and not get_tree().paused, "Esc closes the journal and resumes play")


func _test_notification_overflow() -> void:
	var popups := _journal._achievement_popups
	_journal.open()
	for i in 12:
		_journal._show_notification("Новый аксессуар", "Награда %d" % i, QuestPanel.EARNED_MEDAL)
	_journal.close()
	await get_tree().process_frame
	await get_tree().process_frame
	var last := popups.get_child(-1) as Control
	var last_timer := last.get_meta(&"dismiss_tween") as Tween
	_check(not last_timer.is_running() and last.modulate.a == 0.0,
		"Notifications beyond the portrait viewport wait with their timers paused")
	var mobile := _game.get_node("MobileControls") as MobileControls
	var bounds := popups.get_global_rect()
	var bottom := mobile.top_edge(bounds.position.x, bounds.end.x)
	_check(popups.get_children().all(func(card: Control) -> bool:
		return card.modulate.a == 0.0 or card.get_global_rect().end.y <= bottom),
		"Visible notifications leave the portrait touch controls clear")
	for card in popups.get_children():
		var timer := card.get_meta(&"dismiss_tween") as Tween
		if timer.is_running():
			timer.custom_step(5.4)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_instance_valid(last) and last_timer.is_running() and last.modulate.a > 0.0,
		"Once visible notifications expire, the queued notifications become visible and start their timers")
	for card in popups.get_children():
		card.queue_free()
	await get_tree().process_frame


func _test_network_profile() -> void:
	var valid := PlayerRegistry.clean_profile({"title_first": " Сонный ", "title_second": "Кодер",
		"hoodie": "blue", "hair_style": "mohawk", "hair_color": "pink", "accessory": "first_steps",
		"nickname_color": "orange"}, 3, {&"first_steps": true})
	_check(valid == {"name": "Сонный Кодер", "hoodie": "blue", "hair_style": "mohawk", "hair_color": "pink",
		"accessory": "first_steps", "nickname_color": "orange"},
		"Server keeps a valid network profile and trims its nickname words")
	var forged := PlayerRegistry.clean_profile({"title_first": "<b>Админ</b>", "title_second": "Кодер",
		"hoodie": "gold", "hair_style": 5, "hair_color": null, "accessory": {"name": "fake"},
		"nickname_color": "#ff0000"}, 7)
	_check(forged.name == "Игрок 7" and forged.hoodie == CharacterLook.HOODIES[0].id
		and forged.hair_style == CharacterLook.HAIR_STYLES[0].id and forged.hair_color == CharacterLook.HAIR_COLORS[0].id
		and forged.accessory == CharacterLook.STARTER_ACCESSORY
		and forged.nickname_color == CharacterLook.DEFAULT_NICKNAME_COLOR,
		"Server replaces an unknown nickname with «Игрок N» and unknown looks with defaults")
	_check(PlayerRegistry.clean_profile("not a dictionary", 2).name == "Игрок 2", "Server survives a malformed profile")
	var longest := 0
	for first in CharacterLook.TITLE_FIRST:
		for second in CharacterLook.TITLE_SECOND:
			longest = maxi(longest, PlayerRegistry.clean_profile({"title_first": first, "title_second": second}, 1).name.length())
	_check(longest <= PlayerRegistry.NAME_MAX and longest > 0, "Every creator nickname fits the server length cap")

	var registry := PlayerRegistry.new()
	var token := "token-0000000000000001"
	var requested := {"title_first": "Тайный", "title_second": "Енот", "hoodie": "pink",
		"accessory": "apple", "nickname_color": "blue"}
	var joined := registry.admit(token, "player", 0.0, requested)
	registry.bind_peer(joined.player_id, 2)
	var initial := registry.profile_of(joined.player_id)
	_check(initial.accessory == CharacterLook.STARTER_ACCESSORY and initial.nickname_color == "white",
		"Joining with locked rewards falls back to the starter appearance")
	_check(registry.equip_accessory(2, "apple") == "" and registry.equip_accessory(2, "blue") == "",
		"Live equip requests cannot bypass the achievement requirement")
	_check(registry.equip_accessory(7, "blue") == "" and registry.equip_accessory(2, "boss_victory") == "",
		"Only registered peers can equip catalog accessories")
	registry.award_achievement(token, &"first_steps")
	registry.award_achievement(token, &"boss_victory")
	_check(registry.equip_accessory(2, "first_steps") == joined.player_id,
		"Selecting an accessory updates the sender's registered profile")
	_check(registry.equip_accessory(2, "blue") == joined.player_id
		and registry.profile_of(joined.player_id).accessory == "first_steps",
		"Selecting a nickname color updates the network profile independently of the worn item")
	registry.peer_lost(2, 1.0)
	registry.admit(token, "player", 2.0)
	var rec: Dictionary = registry.records()[0]
	_check(rec.name == "Тайный Енот" and rec.skin == "pink/%s/%s" % [CharacterLook.HAIR_STYLES[0].id, CharacterLook.HAIR_COLORS[0].id],
		"Registry keeps the profile as the name and skin source across a reconnect")
	_check(rec.profile.accessory == "first_steps" and rec.profile.nickname_color == "blue",
		"Registry retains both choices when reconnecting without a new profile")
	registry.bind_peer(joined.player_id, 2)
	registry.equip_accessory(2, CharacterLook.NO_ACCESSORY)
	registry.equip_accessory(2, CharacterLook.DEFAULT_NICKNAME_COLOR)
	_check(registry.profile_of(joined.player_id).accessory == CharacterLook.NO_ACCESSORY
		and registry.profile_of(joined.player_id).nickname_color == CharacterLook.DEFAULT_NICKNAME_COLOR,
		"The server accepts removal of both accessory types")
	registry.admit(token, "player", 3.0, {"title_first": "Бодрый", "title_second": "Ёжик"})
	_check(registry.profile_of(joined.player_id).name == "Бодрый Ёжик", "A rejoin with a new profile updates it")
	registry.admit(token, "player", 4.0, requested)
	var returning := registry.profile_of(joined.player_id)
	_check(returning.accessory == CharacterLook.STARTER_ACCESSORY and returning.nickname_color == "blue",
		"Rejoining accepts earned rewards and rejects other catalog items")

	var remote: Player = load("res://src/player/Player.tscn").instantiate()
	remote.visible = false
	remote.player_number = 4
	_game.add_child(remote)
	_check(remote._label.text == "Игрок 4", "A network player without a profile is labelled «Игрок N»")
	remote.profile = valid
	_check(remote._label.text == "Сонный Кодер"
		and remote._label.get_theme_color("font_color") == CharacterLook.nickname_tint("orange")
		and remote._sprite.texture == CharacterLook.build("blue", "mohawk", "pink", "first_steps"),
		"A replicated profile sets the network player's look and nickname label")
	var badge_texture := remote._sprite.texture
	remote.profile = valid.merged({"accessory": CharacterLook.STARTER_ACCESSORY}, true)
	_check(remote._sprite.texture.get_image().get_pixel(16, 21) != badge_texture.get_image().get_pixel(16, 21),
		"A replicated accessory change visibly changes the remote player's sprite")
	var starter_texture := remote._sprite.texture
	remote.profile = remote.profile.merged({"nickname_color": "blue"}, true)
	_check(remote._label.get_theme_color("font_color") == CharacterLook.nickname_tint("blue")
		and remote._sprite.texture == starter_texture,
		"A replicated nickname color change leaves the worn item alone")
	remote.profile = remote.profile.merged({"accessory": CharacterLook.NO_ACCESSORY, "nickname_color": "white"}, true)
	_check(remote._sprite.texture.get_image().get_pixel(16, 21)
		== CharacterLook.build("blue", "mohawk", "pink").get_image().get_pixel(16, 21)
		and remote._label.get_theme_color("font_color") == Color.WHITE,
		"Remote players see an unadorned sprite and white nickname after a reset")
	remote.free()


func _test_network_emotes() -> void:
	var world: Node = load("res://src/net/world/NetWorld.gd").new()
	_check(not world.accept_emote("p1", -1, 0.0) and not world.accept_emote("p1", EmoteBubble.NAMES.size(), 0.0),
		"Server rejects unknown emotes")
	_check(world.accept_emote("p1", 0, 10.0), "Server accepts a known emote")
	_check(not world.accept_emote("p1", 1, 10.0 + world.EMOTE_MIN_INTERVAL * 0.5), "Server rate-limits emote spam")
	_check(world.accept_emote("p2", 1, 10.1), "The emote rate limit is per player")
	_check(world.accept_emote("p1", 2, 10.0 + world.EMOTE_MIN_INTERVAL), "Emotes are accepted again after the interval")
	world.free()


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
	_check(_player.find_target() == bag, "Player action targets the bean bag in front")
	await _press_action()
	await _wait(0.5)
	_check(bag.global_position == bag_start + Vector2(0, 32), "Bean bag moves one cell when pushed")
	_check(Quests.is_done("main") and _progress._done_icon.visible, "Final step completes the quest and shows a checkmark")
	_check(_progress._done_icon.custom_minimum_size.x >= _progress._status.get_theme_font_size("font_size"),
		"Completed quest HUD checkmark is at least as large as its status text")
	_check(GameManager.has_achievement(&"first_steps"), "Main quest awards First Steps")
	var badge := _journal._accessory_slots[&"first_steps"]
	_check(badge.modulate == Color.WHITE and not badge.disabled,
		"Completing the office quest makes its accessory available in the profile")
	var reward_popups := _journal._achievement_popups.get_children()
	var reward_names: Array[String] = []
	for notification in reward_popups:
		if notification.get_node("Row/Labels/Title").text == "Новый аксессуар":
			reward_names.append(notification.get_node("Row/Labels/Description").text)
	_check(reward_names == ["Значок новичка", "Цвет ника: оранжевый"],
		"The training achievement announces both rewards in inventory order")
	badge.pressed.emit()
	_check(PlayerProfile.to_dict().accessory == "first_steps" and _player._sprite.texture == PlayerProfile.texture()
		and _journal._profile_preview.texture == PlayerProfile.texture(),
		"Equipping an unlocked accessory updates the local player, profile, and network payload")
	var orange := _journal._accessory_slots[&"orange"]
	_check(not orange.disabled, "Completing training unlocks the orange nickname color")
	orange.pressed.emit()
	var orange_tint := CharacterLook.nickname_tint("orange")
	_check(PlayerProfile.to_dict().nickname_color == "orange" and PlayerProfile.accessory == "first_steps"
		and _player._nameplate.get_theme_color("font_color") == orange_tint
		and _journal._profile_name.get_theme_color("font_color") == orange_tint,
		"Equipping orange updates the local nameplate and preview while retaining the worn item")
	_journal._accessory_slots[CharacterLook.NO_ACCESSORY].pressed.emit()
	_check(PlayerProfile.accessory == CharacterLook.NO_ACCESSORY and PlayerProfile.nickname_color == "orange"
		and _player._nameplate.get_theme_color("font_color") == orange_tint
		and _journal._profile_preview.texture == PlayerProfile.texture() and not badge.disabled and not orange.disabled,
		"Choosing no wearable accessory removes the badge independently of nickname color")
	badge.pressed.emit()
	npc.interact(_player)
	_check(npc._label.text == "Привет!", "Quest-gated NPC switches to a greeting after completion")
	npc.interact(_player)
	await _wait(0.5)
	_check(Quests.selected_quest_id == "never_too_late", "HUD advances after the completion delay")
	for mode: NetConfig.Mode in [NetConfig.Mode.CLIENT, NetConfig.Mode.SCREEN]:
		var result := {}
		_in_mode(mode, func() -> void:
			_journal.open()
			result.open_unpaused = _journal.is_open() and not get_tree().paused
			_journal.close())
		_check(result.open_unpaused and not _journal.is_open() and not get_tree().paused,
			"The journal does not pause network play")
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
	var apple := _journal._accessory_slots[&"apple"]
	var steve_title: Label = _journal._cards_by_id[&"steve_jobs"].get_node("Row/Labels/Title")
	_check(apple.disabled and steve_title.text == "Скрытое достижение",
		"The apple starts locked and its achievement title is hidden")
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
			if kind == SnackStation.Kind.APPLE:
				_check(apple.disabled == (i < matching.size() - 1), "The apple badge follows the apple achievement")
		if kind == SnackStation.Kind.APPLE:
			var notification := _journal._achievement_popups.get_child(-1)
			_check(steve_title.text == "Стив Джобс"
				and notification.get_node("Row/Labels/Description").text == "Яблоко",
				"Unlocking the hidden achievement reveals its title and announces the apple badge")
	apple.pressed.emit()
	_check(PlayerProfile.accessory == "apple" and _player._sprite.texture == PlayerProfile.texture()
		and CharacterLook.accessory_icon("apple").get_size() == Vector2(5, 6),
		"The unlocked apple can be worn at the smaller size")
	_journal._accessory_slots[&"first_steps"].pressed.emit()
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
	_check(_player.find_target() == hideout, "Hideout is reachable through the player interaction")
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
	_journal._show_notification("Новое достижение", "Первое", QuestPanel.EARNED_MEDAL)
	_journal.open()
	_journal._show_notification("Новый аксессуар", "Второе", CharacterLook.accessory_icon("blue"))
	var first := popups.get_child(recent) as Control
	var second := popups.get_child(recent + 1) as Control
	var first_timer: Tween = first.get_meta(&"dismiss_tween")
	var second_timer: Tween = second.get_meta(&"dismiss_tween")
	_check(get_tree().paused and not popups.visible and not first_timer.is_running() and not second_timer.is_running(),
		"The journal pauses notifications that arrived before and while it was open")
	await _wait(5.5)
	_journal.close()
	_check(popups.visible and is_instance_valid(first) and is_instance_valid(second),
		"Opening and closing the journal preserves both notifications")
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
	for i in range(boss.hp):
		await _wait(0.55)
		boss.interact(_player)
	_check(Quests.is_done(quest_id) and GameManager.has_achievement(&"boss_victory"),
		"Defeating the boss completes its quest and awards the achievement")
	var blue := _journal._accessory_slots[&"blue"]
	_check(not blue.disabled, "Defeating the mimic makes the blue nickname available")
	blue.pressed.emit()
	_check(PlayerProfile.nickname_color == "blue" and PlayerProfile.accessory == "first_steps"
		and _player._nameplate.get_theme_color("font_color") == CharacterLook.nickname_tint("blue"),
		"Equipping the mimic reward sets the blue nameplate and leaves the worn item in place")
	_check(popups.get_child(-1).get_node("Row/Labels/Description").text == "Цвет ника: синий",
		"The mimic achievement announces the blue nickname reward")
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


# --- Общий мир в сети. Сеть не нужна: те же методы, что вызывают NetWorld и WorldSync;
# режим сервера подменяется на время проверки (_as_server).

# Выполнить action в режиме сети mode и вернуть прежний режим
func _in_mode(mode: NetConfig.Mode, action: Callable) -> void:
	var previous := Net.config.mode
	Net.config.mode = mode
	action.call()
	Net.config.mode = previous


# Выполнить action как сервер: режим SERVER, а у NetWorld — синхронизатор sync (и вернуть как было)
func _as_server(sync: WorldSync, action: Callable) -> void:
	var net_world := _game.get_node("NetWorld")
	var previous_sync: WorldSync = net_world._sync
	net_world._sync = sync
	_in_mode(NetConfig.Mode.SERVER, action)
	net_world._sync = previous_sync


# Свой WorldSync в NetWorld (в OFFLINE NetWorld его не создаёт); после проверки — free()
func _new_world_sync() -> WorldSync:
	var ws := WorldSync.new()
	ws.name = "WorldSync"
	_game.get_node("NetWorld").add_child(ws)
	return ws


# Сервер: «действие» сетевого игрока (request_interact) — та же логика, что у своего;
# мешки твёрдые и для сетевых игроков
func _test_net_interact_pushes_bag() -> void:
	var bag: BeanBag = _game.get_node("BeanBag1")
	# открытый пол рядом с местом, где тест квестов толкал мешок
	var cell := _open_cell_near(Vector2i(15, 8))
	bag.displace_to(Grid.cell_to_world(bag, cell + Vector2i.DOWN))
	_player.displace_to(Grid.cell_to_world(_player, cell))
	_player.facing = Vector2i.DOWN
	_player.network_controlled = true
	_player.remote_dir = Vector2i.ZERO
	_player.queue_interact(0)
	await _wait(0.6)
	_check(not _player._interact_queued and bag.global_position == Grid.cell_to_world(bag, cell + Vector2i(0, 2)),
		"A network player's action request pushes the bean bag on the server")
	_player.remote_dir = Vector2i.DOWN
	await _wait(0.6)
	_player.remote_dir = Vector2i.ZERO
	await _wait(0.2)
	_check(Grid.world_to_cell(_player, _player.global_position) == cell + Vector2i.DOWN
		and bag.global_position == Grid.cell_to_world(bag, cell + Vector2i(0, 2)),
		"A network player walking into a bean bag is blocked by it")
	_player.network_controlled = false


# Сервер: босс отбрасывает и сетевых игроков (они живут в NetWorld/Players, а не в корне сцены)
func _test_boss_knocks_back_network_players() -> void:
	var director: BossDirector = _game.get_node("BossDirector")
	var spawn: BossSpawn = director.get_node("SpawnHall")
	director.dismiss_boss()
	await _wait(0.9)
	var remote: Player = load("res://src/player/Player.tscn").instantiate()
	remote.is_local = false
	remote.network_controlled = true
	remote.position = spawn.global_position + Vector2(16, 16)
	_game.get_node("NetWorld/Players").add_child(remote)
	director.spawn_boss(spawn)
	_check(director._boss != null and not Grid.world_to_cell(remote, remote.global_position) in director._boss.get_cells(),
		"The boss knocks back network players standing on its cells")
	remote.free()


# Личные цели (диалоги, прятки) выполняет клиент, остальное — сервер
func _test_personal_targets() -> void:
	var director: BossDirector = _game.get_node("BossDirector")
	_check(director._boss != null, "A live boss is there to check personal targets against")
	_check(Player.is_personal_target(_game.get_node("NPC")) and Player.is_personal_target(_game.get_node("HideAndSeek"))
		and not Player.is_personal_target(_game.get_node("BeanBag1"))
		and not (director._boss != null and Player.is_personal_target(director._boss)),
		"NPC dialogue and hide-and-seek are personal, bags and the boss are shared")


# Клиент: присланное сервером задание с шагами
func _test_client_quest_steps() -> void:
	Quests.net_add_quest("net_test", "Сетевое задание", false, [["net_test_step", "Шаг"]])
	var net_quest := Quests.find("net_test")
	_check(net_quest != null and net_quest.steps.size() == 1 and Quests.find("net_test_step") != null,
		"A quest sent by the server keeps its steps")
	Quests.remove_quest("net_test")


# Клиент: пока применяется состояние с сервера, свои тексты мира не создаются (их шлёт сервер)
func _test_replay_suppresses_world_fx() -> void:
	var child_count_before := _game.get_child_count()
	Net.replay(func() -> void: FloatingText.spawn(_game, Vector2.ZERO, "дубль"))
	_check(_game.get_child_count() == child_count_before and not Net.replaying,
		"World effects are not duplicated while server state is applied")


# Клиент: мешок принимает позицию, вид и поворот с сервера
func _test_client_bag_mirror() -> void:
	var source: BeanBag = _game.get_node("BeanBag3")
	var copy: BeanBag = load("res://src/bean_bag/BeanBag.tscn").instantiate()
	_game.add_child(copy)
	WorldSync.apply_now(copy, WorldSync.state_of(source))
	_check(copy.global_position == source.global_position
		and (copy._sprite.texture as AtlasTexture).region == (source._sprite.texture as AtlasTexture).region
		and copy._sprite.flip_h == source._sprite.flip_h, "A client bean bag mirrors the server's position and look")
	copy.free()


# Клиент: босс по состоянию директора — тот же вид и место, без отбрасывания; удар и победа
func _test_client_boss_view() -> void:
	var director: BossDirector = _game.get_node("BossDirector")
	var view := BossDirector.new()
	view.first_delay = 1.0e9
	var view_spawn := BossSpawn.new()
	view_spawn.name = "SpawnView"
	view_spawn.boss_title = "Мешок-Мимик, Тестовый"
	view_spawn.location_name = "тесте"
	view_spawn.position = director.get_node("SpawnLounge").position
	view.add_child(view_spawn)
	_game.add_child(view)
	var spot := view_spawn.global_position + Vector2(16, 16)
	_player.displace_to(spot)
	var net_boss := {BossDirector.KEY_NUMBER: 99, BossDirector.KEY_END_REASON: BossDirector.EndReason.NONE,
		BossDirector.KEY_SPAWN: "SpawnView", BossDirector.KEY_SKIN: 1, BossDirector.KEY_HP: 3,
		BossDirector.KEY_MAX_HP: 3}
	view.apply_net_state(net_boss)
	var shown := view._boss
	_check(shown != null and shown.net_view and shown.global_position == view_spawn.global_position
		and shown._sprite.texture == shown.skins[1] and view._bar.health_bottom() > 0 and Quests.find("boss_99") != null,
		"A client shows the server's boss at its spot with its look, health bar and quest")
	_check(_player.global_position == spot, "The client's boss image does not knock anyone back")
	net_boss[BossDirector.KEY_HP] = 2
	view.apply_net_state(net_boss)
	_check(shown != null and shown.hp == 2 and view._bar.current_hp() == 2.0,
		"A server hit lowers the boss health on the client")
	GameManager._unlocked_achievements.erase(&"boss_victory")
	view.apply_net_state({BossDirector.KEY_NUMBER: 99, BossDirector.KEY_END_REASON: BossDirector.EndReason.DEFEATED})
	_check(view._boss == null and Quests.is_done("boss_99") and view._bar.banner_text() == "ВЕЛИКИЙ ВРАГ ПОВЕРЖЕН",
		"A server defeat completes the client's boss quest and shows the banner")
	_check(not GameManager.has_achievement(&"boss_victory"), "A spectator does not earn the boss achievement from world replication")
	GameManager._unlocked_achievements[&"boss_victory"] = true
	await _wait(1.0)
	_check(not is_instance_valid(shown), "The defeated boss image is removed")
	view.free()


func _test_server_boss_rewards() -> void:
	var director: BossDirector = _game.get_node("BossDirector")
	director.dismiss_boss()
	await _wait(0.9)
	Net.server = NetServer.new()
	var registry := Net.server.registry
	var first_token := "boss-player-00001"
	var second_token := "boss-player-00002"
	var observer_token := "boss-observer-00001"
	var first := Player.new()
	first.name = registry.admit(first_token, "player", 0.0).player_id
	registry.bind_peer(first.name, 2)
	var second := Player.new()
	second.name = registry.admit(second_token, "player", 0.0).player_id
	registry.admit(observer_token, "player", 0.0)
	_in_mode(NetConfig.Mode.SERVER, func() -> void:
		director.spawn_boss(director.get_node("SpawnHall"))
		var boss := director._boss
		boss.interact(first)
		boss.interact(second)
		_check(director._participants.size() == 1, "An invulnerable hit does not qualify as damage")
		registry.peer_lost(2, 1.0)
		registry.expire(1.0 + PlayerRegistry.HOLD_SECONDS)
		while boss.hp > 0:
			boss._invulnerable = 0.0
			boss.interact(second))
	_check(registry.achievements_of(first_token).has(&"boss_victory")
		and registry.achievements_of(second_token).has(&"boss_victory")
		and not registry.achievements_of(observer_token).has(&"boss_victory"),
		"The server awards both damage dealers, including a disconnected player, and excludes observers")
	var rejoined := registry.admit(first_token, "player", 100.0, {"nickname_color": "blue"})
	_check(registry.profile_of(rejoined.player_id).nickname_color == "blue",
		"A participant can reconnect after victory and equip the reward even after their old slot expired")
	first.free()
	second.free()
	Net.server.free()
	Net.server = null


# Клиент: зомби встаёт и ложится по состоянию с сервера
func _test_client_zombie_view() -> void:
	var zombie: ZombieModerator = _game.get_node("SokobanRoom/Zombie2")
	zombie.apply_net_state({"mode": ZombieModerator.Mode.ROAM, "asleep": false})
	_check(not zombie.asleep and zombie.npc_name == zombie.risen_name and zombie.lines == zombie.risen_lines,
		"A client zombie rises when the server says so")
	await _wait(0.5)
	zombie.apply_net_state({"mode": ZombieModerator.Mode.SLEEP, "asleep": true})
	_check(zombie.asleep and zombie.npc_name == "Уставший модератор" and zombie.mode == ZombieModerator.Mode.SLEEP,
		"A client zombie lies down again when the server says so")


# Сервер: первая рассылка — весь мир, без изменений — пусто, сдвинули мешок — только он
func _test_world_sync_diff() -> void:
	var ws := _new_world_sync()
	var bag: BeanBag = _game.get_node("BeanBag2")
	var key := str(_game.get_path_to(bag))
	var first := ws._collect(false)
	_check(first.has(key) and first.has("BossDirector") and first.has("ZombieUprising")
		and ws._collect(false).is_empty(), "WorldSync sends each shared object once and nothing while the world is still")
	# открытый пол подальше от прошлых проверок: мешок туда просто переставляется
	var cell := _open_cell_near(Vector2i(20, 12))
	bag.displace_to(Grid.cell_to_world(bag, cell))
	var changes := ws._collect(false)
	_check(changes.keys() == [key] and changes[key][WorldSync.POSITION_KEY] == Vector2i(bag.global_position.round()),
		"WorldSync sends only the object that changed")
	_check(ws._collect(true).size() == first.size(), "A world_ready snapshot contains the whole shared world")
	ws.free()


# Клиент: позиция с сервера — плавно вблизи и сразу издалека; «повтор» сервера снимается
func _test_world_sync_glide() -> void:
	var ws := _new_world_sync()
	var bag: BeanBag = _game.get_node("BeanBag2")
	var key := str(_game.get_path_to(bag))
	var target := bag.global_position
	bag.global_position = target + Vector2(16, 0)
	ws.receive_states({key: {WorldSync.POSITION_KEY: Vector2i(target)}})
	_check(ws._glide_targets.has(bag) and bag.global_position != target and not Net.replaying,
		"A client glides a shared object toward the server position")
	await _wait(0.3)
	_check(bag.global_position == target and not ws._glide_targets.has(bag),
		"The glide ends exactly at the server position")
	bag.global_position = target + Vector2(200, 0)
	ws.receive_states({key: {WorldSync.POSITION_KEY: Vector2i(target)}})
	_check(bag.global_position == target, "A far server position is applied at once")
	ws.free()


# Рабочий (не зависший) и видимый компьютер на карте, или null
func _working_laptop() -> Laptop:
	for node in get_tree().get_nodes_in_group("resource_station"):
		if node is Laptop and not (node as Laptop).is_empty and node.visible:
			return node
	return null


# Клиент: вызов эффекта с сервера (replay_call) — реакция компьютера на тычок
func _test_world_sync_replay_call() -> void:
	var laptop := _working_laptop()
	_check(laptop != null, "The map has a working laptop for the replayed effect call")
	if laptop == null:
		return
	var ws := _new_world_sync()
	ws.replay_call(str(_game.get_path_to(laptop)), &"net_poke_flash", [])
	_check(laptop._flash > 0.0 and not Net.replaying, "A server effect call replays on the client's object")
	ws.free()


# Сервер (подменённый режим): действия сетевых игроков и личные события
func _test_server_forwards_personal() -> void:
	var laptop := _working_laptop()
	_check(laptop != null, "The map has a working laptop for the server interaction")
	if laptop == null:
		return
	var ws := _new_world_sync()
	var npc: NPC = _game.get_node("NPC")
	npc._close()
	var npc_cell := Grid.world_to_cell(npc, npc.global_position)
	_player.displace_to(Grid.cell_to_world(npc, npc_cell + Vector2i.DOWN))
	_player.facing = Vector2i.UP
	var quest_id := "net_forward_test"
	Quests.add_quest(quest_id, "Сетевое задание", false)
	var child_count_before := _game.get_child_count()
	var pokes: int = laptop._pokes
	Net.server = NetServer.new()
	var token := "tutorial-player-001"
	var registry := Net.server.registry
	var player_id: String = registry.admit(token, "player", 0.0).player_id
	registry.bind_peer(player_id, FAKE_PEER)
	_as_server(ws, func() -> void:
		_player._interact_actor_peer = FAKE_PEER
		Net.as_actor(FAKE_PEER, Quests.complete.bind("push_bean_bag"))
		_check(registry.tutorial_step_of(player_id) == 0, "The server ignores a tutorial step attempted out of order")
		for i in npc.lines.size():
			Net.as_actor(FAKE_PEER, _player._interact)
		_check(registry.tutorial_step_of(player_id) == 0, "The tutorial dialogue must be finished on the server")
		Net.as_actor(FAKE_PEER, _player._interact)
		_check(registry.tutorial_step_of(player_id) == 1, "The server records the completed tutorial dialogue")
		Net.as_actor(FAKE_PEER, Quests.complete.bind("push_bean_bag"))
		_check(registry.achievements_of(token).has(&"first_steps")
			and registry.equip_accessory(FAKE_PEER, "orange") == player_id,
			"The server grants the tutorial accessory only after both steps")
		_player._interact_actor_peer = 0
		Net.as_actor(FAKE_PEER, laptop.interact.bind(_player))
		Quests.complete(quest_id)
		Net.as_actor(FAKE_PEER, GameManager.unlock_achievement.bind(&"net_test_achievement"))
		FloatingText.spawn(_game, Vector2.ZERO, "сервер"))
	var dialogue_stayed_closed_on_server: bool = not npc._bubble.visible
	_check(dialogue_stayed_closed_on_server, "The server leaves NPC dialogue to the player's client")
	_check(laptop._pokes == pokes + 1, "The server runs a shared interaction for a network player")
	_check(Quests.find(quest_id) != null and not Quests.is_done(quest_id)
		and not GameManager.has_achievement(&"net_test_achievement"),
		"The server forwards quests and achievements instead of keeping them")
	_check(registry.achievements_of(token).has(&"net_test_achievement"),
		"Server-earned achievements are recorded for the acting player")
	Net.server.free()
	Net.server = null
	Quests.remove_quest(quest_id)
	_check(_game.get_child_count() == child_count_before, "The server sends world effects instead of creating them")
	_player._interact()
	_check(npc._bubble.visible, "Offline the same action opens the NPC dialogue locally")
	npc._close()
	laptop._pokes = pokes
	ws.free()


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
	_check(uprising.is_failed and banner.banner_text() == ZombieUprising.FAIL_TEXT
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
