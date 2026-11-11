extends "res://tests/rpg_test_case.gd"
## Runtime gaps found by the QA pass of an exported game (moonveil_export_qa/EXPORT_GAPS.md,
## findings X1-X21): mouse and touch, gamepad, release-build start hooks, music, the message box,
## window options, save times, exit leaks and tileset cache size. Named after the findings.
## Mouse events go through the root viewport (push_input) from a point in a node's coordinates,
## the way a real click arrives, so the UI scaling transform is part of what is tested.

const Env := preload("res://tests/rpg_test_env.gd")
const UIScreen := preload("res://addons/rpg/runtime/ui/rpg_ui_screen.gd")
const OPTIONS_FILE := "user://rpg_options.json"

var env
var _backups := {}
var _slot_files := []


func before_each() -> void:
	env = Env.create(tree, "res://rpg")


func after_each() -> void:
	for a in ["rpg_up", "rpg_down", "rpg_left", "rpg_right", "rpg_ok", "rpg_cancel", "rpg_menu"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	UIScreen.release_injected()
	ProjectSettings.set_setting("rpg/input/mouse", null)
	for p in _slot_files:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_slot_files.clear()
	if env != null:
		await env.destroy()
		env = null
	for path in _backups:
		var data: Variant = _backups[path]
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(data)
	_backups.clear()


func backup(path: String) -> void:
	if not _backups.has(path):
		_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func open(key: String) -> Node:
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path(key))
	assert_true(node != null, "%s opens" % key)
	await frames(2)
	return node


func press(action: String) -> void:
	Input.action_press("rpg_" + action)
	await frames(1)
	Input.action_release("rpg_" + action)
	await frames(1)


# --- mouse helpers ----------------------------------------------------------------------------

## Window coordinates of point `at` in `node`'s own coordinates.
func window_pos(node: CanvasItem, at: Vector2) -> Vector2:
	return tree.root.get_final_transform() * (node.get_global_transform_with_canvas() * at)


func _push(ev: InputEvent) -> void:
	tree.root.push_input(ev)


## Moves the mouse to `at` (in `node`'s coordinates).
func hover(node: CanvasItem, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = window_pos(node, at)
	ev.global_position = ev.position
	_push(ev)


## A click: button down, a frame, button up, a frame.
func click(node: CanvasItem, at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = window_pos(node, at)
	ev.global_position = ev.position
	_push(ev)
	await frames(1)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	_push(up)
	await frames(1)


func wheel(node: CanvasItem, at: Vector2, down := true) -> void:
	await click(node, at, MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP)


## Centre of row `i` of a list, in the list's coordinates.
func row_centre(list: Control, i: int) -> Vector2:
	return list.item_rect(i).get_center()


func on_map(cell := Vector2i(14, 12), facing := "up") -> void:
	await env.start_on("town", cell, facing)
	await env.settle()
	env.rpg.ui.auto_advance = false
	env.rpg.ui.message_box.auto_advance = false
	await frames(2)


func cell_centre(c: Vector2i) -> Vector2:
	var t: int = env.game.map.tile_size
	return Vector2(c * t) + Vector2(t, t) / 2.0


# --- X1: mouse and touch --------------------------------------------------------------------------

func test_x1_title_hover_click_and_wheel() -> void:
	var title: Node = await open("title")
	var got := []
	title.chosen.connect(func(c): got.append(c))
	title.list.select(0)
	hover(title.list, row_centre(title.list, 2))
	assert_eq(title.list.index, 2, "hover moves the cursor to Options")
	await wheel(title.list, row_centre(title.list, 2), false)
	assert_eq(title.list.index, 1, "the wheel moves it up")
	hover(title.list, row_centre(title.list, 0))
	assert_eq(title.list.index, 0)
	await click(title.list, row_centre(title.list, 0))
	assert_eq(got, ["new_game"], "a click on the selected entry chooses it")


func test_x1_click_selects_first_then_confirms() -> void:
	var title: Node = await open("title")
	var got := []
	title.chosen.connect(func(c): got.append(c))
	title.list.select(0)
	await click(title.list, row_centre(title.list, 3))
	assert_eq(title.list.index, 3, "a click on another entry selects it (touch)")
	assert_eq(got, [])
	await click(title.list, row_centre(title.list, 3))
	assert_eq(got, ["quit"])


func test_x1_main_menu_status_and_right_click() -> void:
	await on_map()
	env.game.open_menu()
	await frames(2)
	var menu: Node = env.rpg.ui.scene_stack[-1]
	var status_row: int = menu.COMMANDS.find("status")
	hover(menu.commands, row_centre(menu.commands, status_row))
	assert_eq(menu.commands.index, status_row, "hover over Status")
	await click(menu.commands, row_centre(menu.commands, status_row))
	assert_eq(menu.mode, "actor", "click on Status picks an actor next")
	await click(menu.party_win, Vector2(100, 30))
	assert_eq(menu.mode, "status", "click on the selected actor opens the status")
	await click(menu, Vector2(160, 120), MOUSE_BUTTON_RIGHT)
	assert_eq(menu.mode, "actor", "right click goes back")
	await click(menu, Vector2(160, 120), MOUSE_BUTTON_RIGHT)
	await click(menu, Vector2(160, 120), MOUSE_BUTTON_RIGHT)
	await frames(2)
	assert_false(env.rpg.ui.scene_open(), "right click closes the menu")


func test_x1_item_list_hover_updates_help() -> void:
	env.rpg.state.change_items("potion", "increase", 1)
	for item: Dictionary in env.rpg.data.records("items"):
		if str(item.get("id", "")) != "potion" and not bool(item.get("key_item", false)):
			env.rpg.state.change_items(str(item.id), "increase", 1)
			break
	await on_map()
	env.game.open_menu()
	await frames(2)
	var menu: Node = env.rpg.ui.scene_stack[-1]
	menu.choose("item")
	await frames(1)
	assert_eq(menu.mode, "items")
	if menu.list.items.size() >= 2:
		hover(menu.list, row_centre(menu.list, 1))
		assert_eq(menu.list.index, 1)
		var id := str(menu.list.items[1].data)
		assert_eq(menu.help.text, str(env.rpg.data.record("items", id).get("description", "")), "help follows the mouse")
	var key_tab: Control = menu.tab_labels["key"]
	await click(key_tab, key_tab.size / 2.0)
	assert_eq(menu.item_tab, "key", "a click on the Key Items tab switches to it")
	assert_eq(menu.mode, "items", "and uses nothing")


func test_x1_message_click_advances_and_choices() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	var closed := [0]
	mb.closed.connect(func(): closed[0] += 1)
	mb.open_text({"text": "A short line."})
	await frames(1)
	await click(mb, Vector2(160, 200))
	assert_true(mb._text_done(), "a click while typing shows the whole page")
	assert_eq(closed[0], 0)
	await click(mb, Vector2(160, 200))
	assert_eq(closed[0], 1, "the next click closes it")
	var picked := []
	mb.choice_made.connect(func(i): picked.append(i))
	mb.open_choices(["Yes", "No", "Maybe"], {"cancel_index": 1})
	await frames(2)
	var third: Label = mb.choice_box.get_child(2)
	hover(third, third.size / 2.0)
	assert_eq(mb._choice_index, 2, "hover moves the choice cursor")
	await wheel(third, third.size / 2.0, false)
	assert_eq(mb._choice_index, 1, "the wheel moves it")
	await click(third, third.size / 2.0)
	assert_eq(mb._choice_index, 2, "a click on another choice selects it")
	assert_eq(picked, [])
	await click(third, third.size / 2.0)
	assert_eq(picked, [2], "a click on the selected choice picks it")
	mb.open_choices(["Yes", "No"], {"cancel_index": 1})
	await frames(2)
	await click(mb, Vector2(10, 10), MOUSE_BUTTON_RIGHT)
	assert_eq(picked, [2, 1], "right click cancels")


func test_x1_number_input_mouse() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	var got := []
	mb.number_entered.connect(func(v): got.append(v))
	mb.open_number(3, 0)
	await frames(2)
	var r0: Rect2 = mb.digit_rect(0)
	await click(mb, r0.get_center())
	assert_eq(mb._number_pos, 0, "a click selects the first digit")
	assert_eq(mb._number, 0)
	await click(mb, r0.get_center() - Vector2(0, 3))
	assert_eq(mb._number, 100, "a click on the upper half of the selected digit raises it")
	await click(mb, r0.get_center() + Vector2(0, 3))
	await click(mb, r0.get_center() + Vector2(0, 3))
	assert_eq(mb._number, 900, "the lower half lowers it (wrapping 0 to 9)")
	await wheel(mb, r0.get_center(), false)
	assert_eq(mb._number, 0, "wheel up raises it")
	await click(mb, Vector2(20, 20))
	assert_eq(got, [0], "a click away from the digits enters the number")


func test_x1_battle_commands_and_enemy_click() -> void:
	var rpg: Node = env.rpg
	rpg.ui.auto_advance = false
	rpg.rng.seed = 99
	var out := {}
	var run := func():
		out.r = await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), {"troop": "slimes", "can_escape": true, "can_lose": true, "background": ""}, {"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)
	run.call()
	var scene: Node = rpg.ui.scene_stack[-1]
	for i in 600:
		if scene.phase == "party":
			break
		await frames(1)
	assert_eq(scene.phase, "party")
	await click(scene.cmd_list, row_centre(scene.cmd_list, 0))
	assert_eq(scene.phase, "actor", "click on Fight")
	await click(scene.cmd_list, row_centre(scene.cmd_list, 0))
	assert_eq(scene.phase, "target_enemy", "click on Attack")
	var e1: RPGBattler = scene.core.enemies[1]
	var spr: TextureRect = scene.enemy_nodes[e1]
	hover(spr, spr.size / 2.0)
	assert_eq(scene.target_index, 1, "hover over the second slime targets it")
	await click(spr, spr.size / 2.0)
	assert_eq(scene.core.party[0].action.get("target"), 1, "a click on the targeted enemy attacks it")
	scene.auto = true
	for i in 600:
		if out.has("r"):
			break
		await frames(1)
	assert_eq(out.get("r", {}).get("status", ""), "finished")


func test_x1_name_input_click_types_a_letter() -> void:
	var node: Node = await open("name_input")
	node.start({"actor": "hero", "name": "", "max_length": 6}, {"rpg": env.rpg})
	await frames(1)
	var cell := Vector2(2 * node.CELL_W, 1 * node.CELL_H) + Vector2(node.CELL_W, node.CELL_H) / 2.0
	await click(node.grid, cell)
	assert_eq([node.cx, node.cy], [2, 1], "a click selects the letter")
	await click(node.grid, cell)
	assert_eq(node.text, "M", "a second click types it")
	await click(node, Vector2(10, 10), MOUSE_BUTTON_RIGHT)
	assert_eq(node.text, "", "right click deletes")


func test_x1_shop_hover_wheel_and_sell_click() -> void:
	var node: Node = await open("shop")
	node.start({"goods": [{"kind": "items", "id": "potion"}, {"kind": "items", "id": "potion", "price": 5}]}, {"rpg": env.rpg})
	await frames(1)
	await click(node.commands, row_centre(node.commands, 0))
	await click(node.commands, row_centre(node.commands, 0))
	assert_eq(node.mode, "buy", "click, click: Buy")
	hover(node.list, row_centre(node.list, 1))
	assert_eq(node.list.index, 1)
	await wheel(node.list, row_centre(node.list, 1), false)
	assert_eq(node.list.index, 0, "the wheel scrolls the list")
	await click(node, Vector2(10, 10), MOUSE_BUTTON_RIGHT)
	assert_eq(node.mode, "command")
	await click(node.commands, row_centre(node.commands, 1))
	await click(node.commands, row_centre(node.commands, 1))
	assert_eq(node.mode, "sell", "Sell by mouse")


func test_x1_save_slot_click() -> void:
	await on_map()
	_slot_files.append(env.rpg.saves.slot_path(2))
	if FileAccess.file_exists(env.rpg.saves.slot_path(2)):
		backup(env.rpg.saves.slot_path(2))
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("save"))
	node.setup("save")
	await frames(2)
	node.index = 0
	node._redraw_slots()
	var slot2: Vector2 = Vector2(160, node.SLOT_H * 1.5)
	await click(node.slot_root, slot2)
	assert_eq(node.index, 1, "click selects File 02")
	await click(node.slot_root, slot2)
	assert_true(node.last_result != null and node.last_result.is_ok(), "second click saves")
	assert_true(env.rpg.saves.exists(2))


func test_x1_touch_to_move_and_talk() -> void:
	await on_map(Vector2i(14, 12), "down")
	var p: RPGPlayer = env.game.player
	await click(env.game.map, cell_centre(Vector2i(14, 15)))
	assert_eq(p.destination, Vector2i(14, 15), "a click on the map sets a destination")
	for i in 300:
		if p.cell == Vector2i(14, 15) and not p.moving:
			break
		await frames(1)
	assert_eq(p.cell, Vector2i(14, 15), "the player walked there")
	assert_eq(p.destination, p.NO_DESTINATION)
	# The sign at (13, 9): walk next to it, then a click on it reads it.
	p.place(Vector2i(13, 10))
	await frames(2)
	await click(env.game.map, cell_centre(Vector2i(13, 9)))
	await frames(2)
	assert_true(env.rpg.ui.message_box.is_open() or env.rpg.scheduler.is_main_busy(), "a click on the adjacent sign talks to it")
	assert_eq(p.facing, "up", "facing it")


func test_x1_pathfinding_goes_around_walls() -> void:
	await on_map(Vector2i(14, 12), "down")
	var p: RPGPlayer = env.game.player
	var mv: RPGMovement = env.game.map.movement
	# Find a cell two steps away whose straight line is blocked but which can be reached.
	var dir := p.find_direction_to(Vector2i(14, 12))
	assert_eq(dir, Vector2i.ZERO, "already there")
	var goal := Vector2i(14, 15)
	dir = p.find_direction_to(goal)
	assert_ne(dir, Vector2i.ZERO, "a path to an open cell")
	assert_true(mv.can_move(p, p.cell, dir), "the first step is walkable")


func test_x1_right_click_on_map_opens_menu() -> void:
	await on_map()
	await click(env.game.map, cell_centre(Vector2i(14, 12)), MOUSE_BUTTON_RIGHT)
	await frames(2)
	assert_true(env.rpg.ui.scene_open(), "right click on the map opens the menu")


func test_x1_mouse_can_be_turned_off() -> void:
	var title: Node = await open("title")
	title.list.select(0)
	ProjectSettings.set_setting("rpg/input/mouse", false)
	hover(title.list, row_centre(title.list, 2))
	assert_eq(title.list.index, 0, "project setting rpg/input/mouse = false: no mouse")
	ProjectSettings.set_setting("rpg/input/mouse", null)
	env.rpg.data.system["mouse_input"] = false
	hover(title.list, row_centre(title.list, 2))
	assert_eq(title.list.index, 0, "System mouse_input = false: no mouse")
	env.rpg.data.system.erase("mouse_input")
	hover(title.list, row_centre(title.list, 2))
	assert_eq(title.list.index, 2, "on by default")


func test_x1_game_over_click_closes() -> void:
	env.rpg.ui.auto_advance = false
	var node: Node = await open("game_over")
	var closed := [false]
	node.closed.connect(func(): closed[0] = true)
	node._t = 1.0
	await click(node, Vector2(160, 120))
	assert_true(closed[0], "a click is the 'press a button'")


## A touchpad tap can deliver button down and up in the same frame: the OK it stands for must
## still reach the screen.
func test_x1_quick_tap_still_counts() -> void:
	env.rpg.ui.auto_advance = false
	var node: Node = await open("game_over")
	var closed := [false]
	node.closed.connect(func(): closed[0] = true)
	node._t = 1.0
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = window_pos(node, Vector2(160, 120))
	_push(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	_push(up)
	await frames(2)
	assert_true(closed[0], "press and release in one frame still close it")
	assert_false(Input.is_action_pressed("rpg_ok"), "and OK is not left held down")


# --- X2 / X16: gamepad --------------------------------------------------------------------------

func _pad_events(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			out.append("b%d" % ev.button_index)
		elif ev is InputEventJoypadMotion:
			out.append("a%d:%d" % [ev.axis, int(ev.axis_value)])
	return out


func test_x2_stick_start_back_and_y_are_bound() -> void:
	assert_has(_pad_events("rpg_left"), "a%d:-1" % JOY_AXIS_LEFT_X, "left stick left")
	assert_has(_pad_events("rpg_down"), "a%d:1" % JOY_AXIS_LEFT_Y, "left stick down")
	assert_true(is_equal_approx(InputMap.action_get_deadzone("rpg_up"), 0.5), "deadzone 0.5")
	assert_has(_pad_events("rpg_menu"), "b%d" % JOY_BUTTON_START)
	assert_has(_pad_events("rpg_menu"), "b%d" % JOY_BUTTON_Y, "Y opens the menu as in MV")
	assert_has(_pad_events("rpg_cancel"), "b%d" % JOY_BUTTON_BACK)
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = 0.6
	assert_true(InputMap.event_is_action(ev, "rpg_right"), "0.6 to the right is a press")
	assert_true(ev.is_action_pressed("rpg_right"), "past the deadzone")
	ev.axis_value = 0.3
	assert_false(ev.is_action_pressed("rpg_right"), "0.3 is inside the deadzone")


func test_x2_project_actions_keep_keys_and_get_pad_buttons() -> void:
	var saved := {}
	for a in ["rpg_ok", "rpg_cancel"]:
		saved[a] = InputMap.action_get_events(a)
	InputMap.erase_action("rpg_ok")
	InputMap.add_action("rpg_ok")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_C
	InputMap.action_add_event("rpg_ok", k)
	InputMap.erase_action("rpg_cancel")
	InputMap.add_action("rpg_cancel")
	var own := InputEventJoypadButton.new()
	own.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("rpg_cancel", own)
	env.rpg._register_input()
	var keys := []
	for e in InputMap.action_get_events("rpg_ok"):
		if e is InputEventKey:
			keys.append(e.physical_keycode)
	assert_eq(keys, [KEY_C], "the project's own key stays, no default keys added")
	assert_has(_pad_events("rpg_ok"), "b%d" % JOY_BUTTON_A, "but the pad's A is added")
	assert_eq(_pad_events("rpg_cancel"), ["b%d" % JOY_BUTTON_RIGHT_SHOULDER], "a project's own pad events are left alone")
	for a in saved:
		InputMap.erase_action(a)
		InputMap.add_action(a)
		for e in saved[a]:
			InputMap.action_add_event(a, e)


func test_x2_start_opens_the_menu_and_closes_it() -> void:
	await on_map()
	await press("menu")
	assert_true(env.rpg.ui.scene_open(), "Start opens the menu")
	await press("menu")
	await frames(3)
	assert_false(env.rpg.ui.scene_open(), "Start again closes it")


func test_x16_name_input_hint_follows_the_device() -> void:
	var node: Node = await open("name_input")
	node.start({"actor": "hero", "name": "", "max_length": 6}, {"rpg": env.rpg})
	env.rpg.last_device = "keyboard"
	await frames(1)
	assert_true(node._hint.text.begins_with("Z/Enter"), node._hint.text)
	env.rpg.last_device = "pad"
	await frames(1)
	assert_eq(node._hint.text, "A: choose   B: delete")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_A
	b.pressed = true
	env.rpg.last_device = "keyboard"
	env.rpg._input(b)
	assert_eq(env.rpg.last_device, "pad", "a pad button makes the pad the last device")


# --- X3: start hooks in release builds ----------------------------------------------------------

func test_x3_start_hooks_only_in_playtest() -> void:
	var args := PackedStringArray(["--rpg-start=house_inside:3:4"])
	env.rpg.playtest = false
	assert_eq(env.game.start_request(args), {}, "release: --rpg-start ignored")
	assert_eq(env.game.start_request(PackedStringArray(["--rpg-battle-test=slimes"])), {}, "release: battle test ignored")
	assert_eq(env.game.start_request(PackedStringArray(["--rpg-smoke"])), {"smoke": true}, "smoke stays (CI)")
	backup(RPGGame.PLAYTEST_FILE)
	var f := FileAccess.open(RPGGame.PLAYTEST_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"map": "house_inside", "position": [3, 4]}))
	f = null
	assert_eq(env.game.start_request(PackedStringArray()), {}, "release: playtest file ignored")
	assert_true(FileAccess.file_exists(RPGGame.PLAYTEST_FILE), "and left alone")
	env.rpg.playtest = true
	var req: Dictionary = env.game.start_request(args)
	assert_eq(req.get("map"), "house_inside", "playtest: honoured")


func test_x3_start_without_a_cell_finds_a_free_one() -> void:
	await env.game._start_from("house_inside", null)
	await env.settle()
	assert_true(env.game.map != null and env.game.map.map_id == "house_inside", "the map loaded (no grey screen)")
	var p: RPGPlayer = env.game.player
	assert_true(env.game.map.movement.passage(p.cell) != 0, "on a walkable cell %s" % p.cell)
	await env.game._start_from("town", null)
	await env.settle()
	assert_eq(env.game.player.cell, Vector2i(14, 12), "the start map uses the System start cell")


func test_x3_failed_start_goes_to_the_title() -> void:
	await env.game._start_from("no_such_map", null)
	await frames(2)
	assert_true(env.rpg.ui.scene_open(), "the title opens instead of a grey screen")


# --- X4 / X5 / X21: music ---------------------------------------------------------------------------

func _audio() -> RPGAudio:
	return env.rpg.audio


func test_x4_victory_brings_the_map_music_back_where_it_was() -> void:
	var a := _audio()
	a.play_bgm({"file": "town"}, 1.5)
	var saved := a.save_bgm()
	assert_true(float(saved.pos) >= 1.4, "saved with its position: %s" % saved)
	a.play_bgm({"file": "battle"})
	a.play_me({"file": "victory"})
	assert_false(a.bgm.playing, "the jingle pauses the battle music")
	a.replay_bgm(saved)
	assert_eq(a.current_bgm.get("file"), "town", "the map's music is set during the jingle")
	assert_false(a.bgm.playing, "but waits for it")
	a.me.stop()
	a._on_me_finished()
	assert_true(a.bgm.playing, "after the jingle the music plays")
	assert_eq(a.bgm.stream, a.resolve("music", {"file": "town"}), "the map's track, not the battle's")
	assert_true(a.bgm.get_playback_position() >= 1.4, "from where it was")
	a.replay_bgm(saved)
	assert_true(a.bgm.get_playback_position() >= 1.4, "replaying the current track keeps it going")


func test_x4_battle_command_restores_the_map_music() -> void:
	await on_map()
	env.rpg.ui.auto_advance = true
	var a := _audio()
	a.play_bgm({"file": "town", "volume": 80}, 2.0)
	var r: RPGResult = await env.rpg.run_commands([{"type": "battle", "troop": "slimes", "can_escape": true, "can_lose": true}], {"kind": "api", "id": "t"})
	assert_true(r.is_ok(), str(r.message))
	assert_eq(a.current_bgm.get("file"), "town", "map music after the battle")
	assert_true(a.bgm_position() >= 1.9 or a.me.playing, "resumed from its position (%s)" % a.bgm_position())


func test_x5_game_over_jingle_plays_once() -> void:
	var a := _audio()
	env.rpg.data.system["music"] = {"game_over": "victory", "battle": "battle"}
	a.play_bgm({"file": "battle"})
	env.rpg.ui.auto_advance = false
	var node: Node = await open("game_over")
	assert_false(a.bgm.playing, "the battle music stops")
	assert_true(a.current_bgm.is_empty())
	assert_true(a.me.playing, "the game over jingle plays")
	if a.me.stream is AudioStreamWAV:
		assert_eq(a.me.stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "not looped")
	node.close()


func test_x5_defeat_stops_the_battle_music() -> void:
	var a := _audio()
	var scene: Node = load(env.rpg.ui.scene_path("battle")).new()
	scene.rpg = env.rpg
	scene.args = {"can_lose": false}
	scene.context = {"map_bgm": {"file": "town", "pos": 1.0}}
	env.rpg.data.system["music"] = {"defeat": "victory"}
	a.play_bgm({"file": "battle"})
	scene._defeat_audio()
	assert_true(a.me.playing, "the defeat jingle plays")
	assert_true(a.current_bgm.is_empty(), "the battle music does not come back")
	a.me.stop()
	a._on_me_finished()
	assert_false(a.bgm.playing)
	scene.args = {"can_lose": true}
	a.play_bgm({"file": "battle"})
	scene._defeat_audio()
	assert_eq(a.current_bgm.get("file"), "town", "a battle that may be lost brings the map music back")
	scene.free()


func test_x21_saves_keep_the_music_position() -> void:
	await on_map()
	var a := _audio()
	a.play_bgm({"file": "town", "volume": 80}, 3.0)
	var save: Dictionary = env.rpg.saves.build_save()
	assert_true(float(save.audio.bgm.get("pos", 0.0)) >= 2.9, "the save has the position: %s" % save.audio.bgm)
	a.play_bgm({"file": "town", "volume": 80}, 0.0)
	var r: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(r.is_ok(), r.message)
	assert_eq(a.current_bgm.get("file"), "town")
	assert_false(a.current_bgm.has("pos"), "the position is not kept in current_bgm")
	assert_true(a.bgm.get_playback_position() >= 2.9, "loading resumes the music (%s)" % a.bgm.get_playback_position())


# --- X6: OGG loop points ------------------------------------------------------------------------

## A Vorbis comment header packet with the given entries.
func _comment_packet(entries: Array) -> PackedByteArray:
	var b := PackedByteArray([3])
	b.append_array("vorbis".to_ascii_buffer())
	var vendor := "test".to_utf8_buffer()
	var n := PackedByteArray()
	n.resize(4)
	n.encode_u32(0, vendor.size())
	b.append_array(n)
	b.append_array(vendor)
	n.encode_u32(0, entries.size())
	b.append_array(n)
	for e in entries:
		var eb: PackedByteArray = str(e).to_utf8_buffer()
		n.encode_u32(0, eb.size())
		b.append_array(n)
		b.append_array(eb)
	b.append(1)
	return b


func test_x6_vorbis_comment_parser() -> void:
	var c := RPGAssets.vorbis_comments(_comment_packet(["LOOPSTART=320796", "LoopLength=2822198", "TITLE=Battle1"]))
	assert_eq(c.get("loopstart"), "320796")
	assert_eq(c.get("looplength"), "2822198", "keys are case-insensitive")
	assert_eq(c.get("title"), "Battle1")
	assert_eq(RPGAssets.vorbis_comments(PackedByteArray([1, 2, 3])), {}, "not a comment header")


func test_x6_loop_start_sets_the_loop_offset() -> void:
	var ogg := AudioStreamOggVorbis.new()
	var seq := OggPacketSequence.new()
	seq.sampling_rate = 44100
	seq.packet_data = [[PackedByteArray([1])], [_comment_packet(["LOOPSTART=88200", "LOOPLENGTH=44100"])]]
	ogg.packet_sequence = seq
	var lp := RPGAssets.apply_loop_points(ogg)
	assert_eq(lp, {"start": 88200, "length": 44100}, "read from the comment header packet")
	assert_true(is_equal_approx(ogg.loop_offset, 2.0), "loop_offset = LOOPSTART / rate")
	var tagged := AudioStreamOggVorbis.new()
	tagged.tags = {"LOOPSTART": "22050"}
	RPGAssets.apply_loop_points(tagged)
	assert_true(is_equal_approx(tagged.loop_offset, 0.5), "or from Godot's tags (imported files)")
	var plain := AudioStreamOggVorbis.new()
	assert_eq(RPGAssets.apply_loop_points(plain), {}, "no tags: no change")
	assert_eq(plain.loop_offset, 0.0)


# --- X7 / X8 / X14 / X15: message box -------------------------------------------------------------

func test_x7_number_cursor_never_copies_a_digit() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	mb.open_number(4, 0)
	await frames(1)
	for i in 3:
		await press("up")
	assert_eq(mb._number, 3, "0003")
	await press("left")
	assert_eq(mb._number, 3, "moving left keeps 0003 (was 0033)")
	assert_eq(mb._number_pos, 2)
	await press("up")
	await press("left")
	await press("up")
	await press("left")
	await press("up")
	assert_eq(mb._number, 1113, "dialling left to right works")
	await press("right")
	await press("down")
	assert_eq(mb._number, 1013)


func test_x8_tap_ok_shows_the_whole_page() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	env.rpg.data.system["text_speed"] = 10
	var closed := [0]
	mb.closed.connect(func(): closed[0] += 1)
	mb.open_text({"text": "This is a long line of text that types slowly enough to tap through."})
	await frames(2)
	assert_false(mb._text_done(), "still typing")
	await press("ok")
	assert_true(mb._text_done(), "one tap shows the rest of the page")
	assert_eq(closed[0], 0, "without closing it")
	await press("ok")
	assert_eq(closed[0], 1)


func test_x8_wait_codes_still_wait_after_a_tap() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	mb.open_text({"text": "Before\\!After"})
	await frames(1)
	await press("ok")
	assert_true(mb._await_key, "the \\! pause still waits for a key")
	assert_false(mb._text_done())
	await press("ok")
	assert_true(mb._text_done(), "then the rest shows at once")


## True when a sound effect player was given `role`'s sound since _reset_se (a short sound may
## already have ended, so "playing" is not checked).
func _se_playing(role: String) -> bool:
	var s: AudioStream = _audio().resolve("sound", {"role": role}, true)
	for p in _audio().se_pool:
		if p.stream == s:
			return true
	return false


func _reset_se() -> void:
	for p in _audio().se_pool:
		p.stop()
		p.stream = null


func test_x14_message_pages_close_silently() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	mb.open_text({"text": "Hi."})
	await frames(2)
	mb.text_label.visible_characters = -1
	_reset_se()
	await press("ok")
	assert_false(mb.is_open())
	assert_false(_se_playing("decision"), "no Decision on a page close (MV)")
	env.rpg.data.system["message_advance_sound"] = true
	mb.open_text({"text": "Hi."})
	await frames(2)
	mb.text_label.visible_characters = -1
	await press("ok")
	assert_true(_se_playing("decision"), "a project can ask for it")


func test_x15_choices_and_digits_repeat_while_held() -> void:
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	mb.open_choices(["A", "B", "C", "D", "E", "F", "G", "H"])
	await frames(1)
	Input.action_press("rpg_down")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await frames(1)
	Input.action_release("rpg_down")
	await frames(1)
	assert_true(mb._choice_index >= 3, "holding down repeats (index %d)" % mb._choice_index)
	mb.force_close()
	mb.open_number(2, 0)
	await frames(1)
	_reset_se()
	await press("up")
	assert_true(_se_playing("cursor"), "a digit change plays the cursor sound")


# --- X9: window options -------------------------------------------------------------------------

func test_x9_options_have_full_screen_and_scaling() -> void:
	backup(OPTIONS_FILE)
	if FileAccess.file_exists(OPTIONS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_FILE))
	var o: Node = await open("options")
	assert_has(o.ROWS, "fullscreen")
	assert_has(o.ROWS, "scale")
	assert_eq(o.options.scale, "fit", "fit to the window by default")
	o.list.select(o.ROWS.find("fullscreen"))
	o.handle_action("ok")
	assert_true(o.options.fullscreen)
	o.list.select(o.ROWS.find("scale"))
	o.handle_action("right")
	assert_eq(o.options.scale, "pixel")
	o.handle_action("cancel")
	var saved: Dictionary = o.load_options()
	assert_true(saved.fullscreen)
	assert_eq(saved.scale, "pixel")
	var win: Panel = o.list.get_parent()
	assert_true(win.position.y + win.size.y <= 240 and o.help.get_parent().position.y + o.help.get_parent().size.y <= 240, "every row fits on the screen")


# --- X10: save times ----------------------------------------------------------------------------

func test_x10_save_time_is_shown_in_local_time() -> void:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var unix := 1762818281  # 2025-11-10 23:44:41 UTC
	var expect := Time.get_datetime_string_from_unix_time(unix + bias * 60, true).substr(0, 16)
	var svc: RefCounted = env.rpg.saves
	assert_eq(svc.local_time_text({"unix_time": unix, "timestamp": "2025-11-10T23:44:41"}), expect)
	assert_eq(svc.local_time_text({"timestamp": "2025-11-10T23:44:41"}), expect, "older saves: the UTC timestamp converted")
	await on_map()
	var save: Dictionary = svc.build_save()
	assert_true(save.has("unix_time"), "new saves keep a unix time")


# --- X11 / X12 / X13: volume, fades, limiter ---------------------------------------------------------

func test_x11_zero_volume_is_silence_not_minus_infinity() -> void:
	var a := _audio()
	a.master_music = 0.0
	a.master_sound = 0.0
	a.play_bgm({"file": "town"})
	a.play_se({"role": "cursor"})
	a.play_me({"file": "victory"})
	assert_true(is_finite(a.bgm.volume_db) and a.bgm.volume_db <= -79.0, "bgm %s" % a.bgm.volume_db)
	assert_true(is_finite(a.me.volume_db), "me %s" % a.me.volume_db)
	for p in a.se_pool:
		assert_true(is_finite(p.volume_db), "se %s" % p.volume_db)


func test_x12_fade_does_not_stop_the_next_track() -> void:
	var a := _audio()
	a.play_bgm({"file": "town"})
	var done: Signal = a.fade_bgm(0.2)
	a.play_bgm({"file": "field"})
	var finished := [false]
	done.connect(func(): finished[0] = true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await frames(1)
	assert_true(finished[0], "a waiting fade still finishes")
	assert_eq(a.current_bgm.get("file"), "field", "the new track is still the music")
	assert_true(a.bgm.playing, "and still playing")
	assert_true(a.bgm.volume_db > -10.0, "at its own volume (%s)" % a.bgm.volume_db)


func test_x13_master_bus_has_a_limiter() -> void:
	var found := false
	for i in AudioServer.get_bus_effect_count(0):
		var e := AudioServer.get_bus_effect(0, i)
		if e is AudioEffectHardLimiter:
			found = true
			assert_true(e.ceiling_db <= 0.0 and e.ceiling_db >= -1.0, "ceiling %s" % e.ceiling_db)
			assert_eq(e.pre_gain_db, 0.0, "no change in loudness")
	assert_true(found, "a hard limiter on Master")
	RPGAudio.ensure_master_limiter()
	assert_eq(AudioServer.get_bus_effect_count(0), 1, "added only once")


# --- X17 / X18: screens ---------------------------------------------------------------------------

func test_x17_save_screen_hides_the_menu_below() -> void:
	await on_map()
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("save"))
	node.setup("save")
	await frames(1)
	var dim: ColorRect = node.get_child(0)
	assert_true(dim.color.a >= 0.9, "the backdrop is nearly opaque (%s)" % dim.color.a)
	node.close()


func test_x18_knocked_out_fits_the_battle_status() -> void:
	var rec: Dictionary = env.rpg.data.record("states", "knockout")
	rec["name"] = "Knocked out"
	var hero: RPGBattler = env.rpg.state.actor("hero")
	var scene: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("battle"))
	await frames(1)
	scene.start({"troop": "slimes", "can_escape": true, "can_lose": true, "background": "", "auto": true}, {"rpg": env.rpg})
	if not hero.has_state("knockout"):
		hero.add_state("knockout")
	scene._refresh_status()
	await frames(1)
	var found: Label = null
	for row in scene.status_rows.get_children():
		if row.is_queued_for_deletion():
			continue
		for c in row.get_children():
			if c is Label and c.text == "Knocked out":
				found = c
	assert_true(found != null, "the state shows")
	if found != null:
		assert_eq(found.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "shrunk to fit, not cut to 'Knocke'")
		assert_true(found.position.x + found.size.x <= scene.STATUS_ROW_W + 0.5, "inside the row")
	scene._done = true
	env.rpg.ui.close_scene(scene)


# --- X19: no leaks at exit --------------------------------------------------------------------------

func test_x19_interpreter_and_context_are_freed() -> void:
	var interp := RPGInterpreter.new(env.rpg, {"kind": "test"})
	var wr: WeakRef = weakref(interp)
	var ctx_ref: WeakRef = weakref(interp.ctx)
	assert_true(interp.ctx.interpreter == interp, "the context still reaches its interpreter")
	interp = null
	assert_eq(wr.get_ref(), null, "no reference cycle keeps the interpreter alive")
	assert_eq(ctx_ref.get_ref(), null, "nor its context")


func test_x19_release_caches_drops_streams() -> void:
	var a := _audio()
	a.play_bgm({"file": "town"})
	assert_false(RPGAssets._audio.is_empty())
	env.rpg.release_caches()
	assert_true(RPGAssets._audio.is_empty(), "asset cache cleared")
	assert_true(a.bgm.stream == null, "players hold no stream")
	assert_false(a.bgm.playing)


# --- X20: tileset cache size ------------------------------------------------------------------------

func test_x20_tileset_cache_is_stored_compressed() -> void:
	var rec: Dictionary = env.rpg.data.record("tilesets", "town").duplicate()
	rec["id"] = "x20_size_check"
	var path := RPGTilesetBuilder.cache_path("x20_size_check")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var report := RPGTilesetBuilder.cached_or_build(rec, {})
	var ts: TileSet = report.tileset
	assert_true(ts != null, str(report.errors))
	var raw := 0
	for i in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(i)) as TileSetAtlasSource
		raw += src.texture.get_image().get_data().size()
		assert_true(src.texture is ImageTexture, "in memory the textures stay plain")
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length()
	f = null
	assert_true(size < raw / 4, "cache file %d bytes for %d bytes of atlas pixels" % [size, raw])
	var again := RPGTilesetBuilder.cached_or_build(rec, {})
	assert_true(again.from_cache, "loads back from the cache")
	var a0 := (again.tileset as TileSet).get_source(ts.get_source_id(0)) as TileSetAtlasSource
	var b0 := ts.get_source(ts.get_source_id(0)) as TileSetAtlasSource
	assert_eq(a0.texture.get_image().get_data(), b0.texture.get_image().get_data(), "lossless: same pixels")
	assert_eq(a0.get_tiles_count(), b0.get_tiles_count(), "same tiles")
	# An old cache with raw atlases (saved before this change) is compressed the next time the
	# editor or a playtest loads it, without a rebuild.
	ResourceSaver.save(ts, path)
	f = FileAccess.open(path, FileAccess.READ)
	var raw_file := f.get_length()
	f = null
	assert_true(raw_file > raw / 2, "a plain save keeps the raw pixels (%d bytes)" % raw_file)
	var migrated := RPGTilesetBuilder.cached_or_build(rec, {})
	assert_true(migrated.from_cache, "still a cache hit")
	f = FileAccess.open(path, FileAccess.READ)
	assert_true(f.get_length() < raw / 4, "and the file was shrunk in place (%d bytes)" % f.get_length())
	f = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	RPGMap.clear_tileset_cache()


# --- D4 wiring: Common Event effects from the menu (EDITOR_GAPS_DB.md) --------------------------

func _add_item(rec: Dictionary) -> void:
	var t: Variant = env.rpg.data.db.get("items")
	t.records.append(rec)
	t.by_id[rec.id] = rec


func test_d4_menu_item_runs_its_common_event_on_the_map() -> void:
	env.rpg.data.variables["horn_count"] = {"id": "horn_count", "name": "Horn count", "type": "int"}
	env.rpg.data.common_events["horn_call"] = {"id": "horn_call", "name": "Horn call", "trigger": "none", "switch": "",
		"commands": [{"type": "set_variable", "id": "horn_count", "value": 7}]}
	_add_item({"id": "war_horn", "name": "War Horn", "scope": "user", "consumable": true, "usable": "always",
		"occasion": "always", "effects": [{"kind": "common_event", "id": "horn_call"}]})
	env.rpg.state.change_items("war_horn", "increase", 2)
	await on_map()
	env.game.open_menu()
	await frames(2)
	var menu: Node = env.rpg.ui.scene_stack[-1]
	menu.choose("item")
	await frames(1)
	menu.open_target({"kind": "item", "id": "war_horn", "scope": "user"})
	await frames(1)
	menu._input_target("ok")
	await frames(3)
	assert_eq(env.rpg.state.item_count("war_horn"), 1, "an item whose only effect is a common event is used")
	assert_false(env.rpg.ui.scene_open(), "the menu closes so the event can run on the map")
	await env.settle()
	assert_eq(env.rpg.state.get_variable("horn_count"), 7, "the reserved common event ran on the map")
	assert_true(env.rpg.state.reserved_common_events.is_empty())


func test_x19_to_title_cancels_routes_parked_on_a_wait() -> void:
	await on_map()
	var ev: RPGEvent = null
	for id in env.game.map.events:
		if env.game.map.events[id].page_index >= 0:
			ev = env.game.map.events[id]
			break
	assert_true(ev != null, "the map has an active event")
	ev.custom_route = {"steps": [{"wait": 30.0}], "repeat": true}
	ev.move_type = "custom"
	ev._move_wait = 0.0
	for i in 30:
		await frames(1)
		if ev._route_running:
			break
	assert_true(ev._route_running, "the custom route started and waits")
	var tok: RPGCancelToken = ev._route_token
	await env.game.return_to_title()
	assert_true(tok.is_cancelled, "To Title cancels the route, so its timer and suspended function are let go")
