extends SceneTree
## Screenshots of the kit plugins at work (real rendering, so run it without --headless):
##   godot --path . --script res://tools/plugin_shots.gd -- --out=C:/path/to/folder
## Turns menu_plus, message_plus, letter_sounds, gab and save_plus on for this run only (the
## project files are not changed), starts on the field map and saves:
##   plugins_menu_entry.png     the main menu with an extra entry
##   plugins_options_rows.png   the options screen with the plugins' rows
##   plugins_message_codes.png  a word-wrapped message with size, bold, italic, keyword, macro
##   plugins_gab.png            a gab on the map while the player walks
##   plugins_autosave_toast.png the "Autosaved" note after a map transfer
## The options file and the autosave slot it writes are put back / removed afterwards.
##
## With --set=wave2 it shows the second-wave plugins instead (quests, lighting, crafting), with
## quests, lights and recipes added in memory only:
##   quests_menu_entry.png      the main menu with the Quests entry
##   quests_journal.png         the journal (Active tab, objectives with marks)
##   quests_tracker.png         the tracker and the notes after objectives change
##   crafting.png, crafting_quantity.png, crafting_short.png   the crafting screen, choosing how
##                              many, and a recipe the party lacks an ingredient for (with a
##                              masked one below)
##   lighting_dark_320x240.png  a dark map: the player's light and two event lights (also at
##   lighting_dark_544x416.png  544x416 and 816x624, VX- and MV-size screens, where the 16 px
##   lighting_dark_816x624.png  art is zoomed 2x and 3x)
##   lighting_flashlight_320x240.png  the flashlight cone
##   lighting_dusk_320x240.png  the town at 19:00 with the time-of-day tint (and at 816x624)
##   lighting_dusk_816x624.png
##   lighting_indoor_dusk_320x240.png  the same hour indoors: no tint
## 320x240 and 544x416 shots are saved at 2x / 1x of the game screen as the window shows them.

const OPTIONS_FILE := "user://rpg_options.json"
const QA_SLOTS := 93
const SETTINGS := {
	"menu_plus": {
		"entries": [{"id": "rest", "label": "Rest", "common_event": "full_heal", "after": "item", "icon": 21}],
		"option_rows": [{"key": "hints", "label": "Show Hints", "kind": "bool", "default": "true"},
			{"key": "difficulty", "label": "Difficulty", "kind": "choice", "choices": "Easy, Normal, Hard", "default": "Normal"}],
	},
	"message_plus": {
		"keywords": [{"word": "Crystal", "colour": [255, 120, 120, 255]}],
		"macros": [{"name": "town", "text": "\\C[4]Oakvale\\C[0]"}],
		"name_box": "right",
	},
	"gab": {"base_seconds": 4.0},
	"save_plus": {"max_slots": QA_SLOTS, "on_transfer": true},
}

var out_dir := "res://tools/shots"
var rpg: Node
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var which := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--set="):
			which = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	if which == "wave2":
		await _run_wave2()
		quit(0)
		return
	var options_backup: Variant = FileAccess.get_file_as_bytes(OPTIONS_FILE) if FileAccess.file_exists(OPTIONS_FILE) else null
	rpg = root.get_node("RPG")
	rpg.data.project["extensions"] = ["project", "menu_plus", "message_plus", "letter_sounds", "gab", "save_plus"]
	rpg.data.project["disabled_extensions"] = []
	rpg.reload_extensions(SETTINGS)
	RPGJson.save_file("user://rpg_playtest.json", {"map": "field", "position": [8, 10]})
	game = load("res://addons/rpg/runtime/game.tscn").instantiate()
	root.add_child(game)
	await _wait(1.5)
	# 1. Main menu with the extra entry.
	game.open_menu()
	await _wait(0.5)
	var menu: Node = rpg.ui.scene_stack[-1]
	menu.commands.select(menu.command_ids().find("rest"))
	await _wait(0.2)
	await _shot("plugins_menu_entry")
	# 2. Options with the plugins' rows (opened from the menu).
	menu.choose("options")
	await _wait(0.4)
	var opts: Node = rpg.ui.scene_stack[-1]
	opts.list.select(opts.rows.find("letter_sounds.enabled"))
	opts._refresh()
	await _wait(0.2)
	await _shot("plugins_options_rows")
	opts.handle_action("cancel")
	await _wait(0.3)
	menu.close()
	await _wait(0.5)
	# 3. A message: word wrap, bigger text, bold, italic, keyword and macro, name box at right.
	var text := "<wordwrap>Welcome to \\M[town]! The \\{old\\} <b>Crystal</b>\nunder the well\nhums at night.<br><i>Nobody</i> goes near it."
	rpg.run_commands([{"type": "show_text", "name": "Alex", "face": {"sheet": "hero_face", "index": 0}, "text": text}])
	await _wait(3.0)
	await _shot("plugins_message_codes")
	_action("rpg_ok", true)
	await process_frame
	await process_frame
	_action("rpg_ok", false)
	await _wait(0.5)
	# 4. A gab while the player walks.
	rpg.extension("gab").show_gab("Brr... the wind off the hills is \\C[1]cold\\C[0] today.", {"name": "Alex", "face": {"sheet": "hero_face", "index": 0}})
	_action("rpg_left", true)
	await _wait(0.6)
	_action("rpg_left", false)
	await _wait(0.3)
	await _shot("plugins_gab")
	rpg.extension("gab").clear_gabs()
	# 5. Autosave note after a transfer.
	var r: RPGResult = await game.transfer("house_inside", Vector2i(6, 6), "up", "black", 8)
	print("transfer: ", r)
	await _wait(0.3)
	await _shot("plugins_autosave_toast")
	# Clean up what the run wrote.
	var slot_file := "user://saves/slot_%02d.json" % QA_SLOTS
	if FileAccess.file_exists(slot_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_file))
	if options_backup == null:
		if FileAccess.file_exists(OPTIONS_FILE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_FILE))
	else:
		var f := FileAccess.open(OPTIONS_FILE, FileAccess.WRITE)
		f.store_buffer(options_backup)
		f.close()
	quit(0)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(shot_name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("saved ", path)


func _action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


# --- second wave: quests, lighting, crafting -------------------------------------------------------

const W2_SETTINGS := {
	"quests": {"tracker_corner": "top_right", "toast_seconds": 6.0},
	"lighting": {"day_night": true, "start_hour": 12, "clock": true, "clock_corner": "bottom_right", "player_radius": 3.5},
	"crafting": {"unknown": "mask"},
}
const W2_QUESTS := [
	{"id": "lost_ring", "name": "The Lost Ring", "category": "Main", "icon": 104, "giver": "Elder Maren", "location": "Oakvale",
		"description": "Elder Maren lost her silver ring somewhere near the old well. She thinks someone took it.",
		"objectives": [{"id": "ask", "text": "Ask the villagers"}, {"id": "well", "text": "Search the old well"}, {"id": "thief", "text": "Find who took the ring"}, {"id": "secret", "text": "Follow the footprints", "hidden": true}],
		"rewards": "200 G, Silver Charm"},
	{"id": "herbs", "name": "Herbs for Mira", "category": "Side", "icon": 66, "giver": "Mira", "location": "Green Field",
		"description": "Mira needs three healing herbs from the field.", "objectives": [{"id": "pick", "text": "Pick 3 herbs"}, {"id": "bring", "text": "Bring them to Mira"}], "rewards": "Hi-Potion x2"},
	{"id": "fish", "name": "The Big Catch", "category": "Side", "icon": 17, "description": "Help the fisherman.", "objectives": [{"id": "rod", "text": "Find a rod"}]},
	{"id": "wolves", "name": "Wolf Trouble", "category": "Main", "icon": 16, "description": "Wolves were seen near the road.", "objectives": [{"id": "hunt", "text": "Drive off the wolves"}]},
]


func _w2_data() -> void:
	var data: RPGProjectData = rpg.data
	var db: Dictionary = data.db["quests"]
	for q in W2_QUESTS:
		db.file.records.append(q.duplicate(true))
	db.records = db.file.records
	for r in db.records:
		db.by_id[r.id] = r
	data.map_props("field")["custom"] = {"darkness": {"colour": [6, 6, 22, 255], "strength": 88}}
	data.map_props("house_inside")["custom"] = {"indoor": true}
	var lights := {"field": {"field_sign": [3.0, [255, 190, 110, 255]], "boulder": [2.5, [140, 190, 255, 255]]},
		"town": {"village_sign": [3.0, [255, 200, 120, 255]], "garden_chest": [2.0, [150, 200, 255, 255]], "shopkeeper": [3.0, [255, 210, 140, 255]]}}
	for map_id in lights:
		for ev in data.map_events(map_id):
			if lights[map_id].has(ev.id):
				var l: Array = lights[map_id][ev.id]
				for pg in ev.pages:
					pg["custom"] = {"light": {"radius": l[0], "colour": l[1], "intensity": 100, "flicker": false}}
	data.record("items", "hi_potion")["custom"] = {"recipe": {"ingredients": [{"kind": "items", "id": "potion", "count": 2}, {"kind": "items", "id": "antidote", "count": 1}], "yield": 1, "category": "kitchen", "switch": ""}}
	data.record("weapons", "iron_sword")["custom"] = {"recipe": {"ingredients": [{"kind": "weapons", "id": "bronze_sword", "count": 1}, {"kind": "items", "id": "potion", "count": 3}], "yield": 1, "category": "forge", "switch": ""}}
	data.record("armors", "wooden_shield")["custom"] = {"recipe": {"ingredients": [{"kind": "items", "id": "house_key", "count": 1}, {"kind": "items", "id": "antidote", "count": 1}], "yield": 1, "category": "forge", "switch": ""}}
	data.record("armors", "leather_armor")["custom"] = {"recipe": {"ingredients": [{"kind": "items", "id": "hi_potion", "count": 2}, {"kind": "items", "id": "potion", "count": 1}], "yield": 1, "category": "forge", "switch": ""}}
	data.record("items", "antidote")["custom"] = {"recipe": {"ingredients": [{"kind": "items", "id": "potion", "count": 1}], "yield": 2, "category": "kitchen", "switch": ""}}


## Presses OK until no message is showing (the sample's opening lines).
func _dismiss_messages() -> void:
	for i in 30:
		var box: Node = rpg.ui.message_box
		if box == null or not box.is_open():
			return
		_action("rpg_ok", true)
		await process_frame
		await process_frame
		_action("rpg_ok", false)
		await _wait(0.25)


## Game screen size (the project's viewport) and the project tile size (16 px art is zoomed to
## fill a 32 or 48 px project, as on VX- and MV-size screens).
func _screen_size(game_size: Vector2i, tile: int) -> void:
	rpg.data.profile["tile_size"] = tile
	root.content_scale_size = game_size
	root.size = game_size * 2 if game_size.x <= 320 else game_size
	await _wait(0.3)


func _run_wave2() -> void:
	rpg = root.get_node("RPG")
	rpg.data.project["extensions"] = ["project", "quests", "lighting", "crafting"]
	rpg.data.project["disabled_extensions"] = []
	rpg.reload_extensions(W2_SETTINGS)
	_w2_data()
	await _screen_size(Vector2i(320, 240), 16)
	RPGJson.save_file("user://rpg_playtest.json", {"map": "town", "position": [12, 12]})
	game = load("res://addons/rpg/runtime/game.tscn").instantiate()
	root.add_child(game)
	await _wait(1.5)
	var light: Object = rpg.extension("lighting")
	var quests: Object = rpg.extension("quests")
	var crafting: Object = rpg.extension("crafting")
	light.set_paused(true)
	light.set_time(12, 0)
	await _dismiss_messages()
	# 1. Quests: three active, one completed, objectives in every state.
	quests.set_status("lost_ring", "active")
	quests.set_objective_state("lost_ring", "ask", "completed")
	quests.set_objective_state("lost_ring", "well", "failed")
	quests.set_status("herbs", "active")
	quests.set_status("fish", "active")
	quests.set_status("wolves", "completed")
	quests.track("lost_ring")
	quests._clear_toasts()
	game.open_menu()
	await _wait(0.5)
	var menu: Node = rpg.ui.scene_stack[-1]
	menu.commands.select(menu.command_ids().find("quests"))
	await _wait(0.2)
	await _shot("quests_menu_entry")
	menu.choose("quests")
	await _wait(0.5)
	await _shot("quests_journal")
	var journal: Node = rpg.ui.scene_stack[-1]
	journal.handle_action("cancel")
	await _wait(0.3)
	menu.close()
	await _wait(0.5)
	quests.set_objective_state("herbs", "pick", "completed")
	quests.set_objective_state("lost_ring", "secret", "shown")
	await _wait(0.3)
	await _shot("quests_tracker")
	quests._clear_toasts()
	# 2. Crafting (opened as Open crafting does).
	rpg.state.change_items("antidote", "increase", 1)
	rpg.state.change_items("potion", "increase", 3)
	var cs: Node = rpg.ui.open_scene(crafting.SCREEN)
	cs.start({}, {"rpg": rpg})
	await _wait(0.4)
	await _shot("crafting")
	cs.handle_action("ok")
	cs.handle_action("up")
	await _wait(0.2)
	await _shot("crafting_quantity")
	cs.handle_action("cancel")
	cs.handle_action("down")
	cs.handle_action("down")
	await _wait(0.2)
	await _shot("crafting_short")
	rpg.ui.close_scene(cs)
	await _wait(0.3)
	quests.track("")
	# 3. A dark map at three screen sizes (16 px art zoomed 1x, 2x, 3x).
	for sz in [[Vector2i(320, 240), 16], [Vector2i(544, 416), 32], [Vector2i(816, 624), 48]]:
		await _screen_size(sz[0], sz[1])
		await game.transfer("field", Vector2i(6, 10), "left", "none")
		await _wait(0.6)
		await _shot("lighting_dark_%dx%d" % [sz[0].x, sz[0].y])
	await _screen_size(Vector2i(320, 240), 16)
	await game.transfer("field", Vector2i(6, 10), "right", "none")
	light.set_player_light(null, 0.0, true)
	await _wait(0.5)
	await _shot("lighting_flashlight_320x240")
	light.set_player_light(null, 0.0, false)
	# 4. Dusk outdoors at 320x240 and 816x624, and the same hour indoors.
	light.set_time(19, 0)
	for sz in [[Vector2i(320, 240), 16], [Vector2i(816, 624), 48]]:
		await _screen_size(sz[0], sz[1])
		await game.transfer("town", Vector2i(14, 9), "down", "none")
		await _wait(0.6)
		await _shot("lighting_dusk_%dx%d" % [sz[0].x, sz[0].y])
	await _screen_size(Vector2i(320, 240), 16)
	await game.transfer("house_inside", Vector2i(5, 7), "up", "none")
	await _wait(0.6)
	await _shot("lighting_indoor_dusk_320x240")
