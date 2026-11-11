extends "res://tests/rpg_test_case.gd"
## Event core: page selection, triggers, scheduling, cancellation and failure policy.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func before_each() -> void:
	env = Env.create(tree)
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8), "up")
	assert_true(r.is_ok(), "start transfer: %s" % r)


func after_each() -> void:
	await env.destroy()


func test_registry_loads_builtin_and_extension_commands() -> void:
	var reg: RPGCommandRegistry = env.rpg.registry
	assert_true(reg.has_command("show_text"), "show_text")
	assert_true(reg.has_command("explode"), "project extension command")
	assert_false(reg.has_command("fancy_effect"), "disabled extension command must be unavailable")
	assert_true(reg.unavailable_reason("fancy_effect").contains("disabled"), "reason names the disabled extension")
	assert_true(reg.commands.size() >= 50, "about fifty built-in commands, got %d" % reg.commands.size())
	for p in reg.problems:
		fail("registry problem: %s %s" % [p.file, p.message])


func test_highest_page_selection_and_refresh() -> void:
	var door: RPGEvent = env.game.map.get_event("town_house_door")
	assert_eq(door.page_index, 0, "locked page first")
	env.rpg.set_switch("door_unlocked", true)
	assert_eq(door.page_index, 0, "page changes only at the next safe point")
	await frames(2)
	assert_eq(door.page_index, 1, "highest eligible page wins")
	env.rpg.set_switch("door_unlocked", false)
	await frames(2)
	assert_eq(door.page_index, 0)


func test_locked_door_shows_text() -> void:
	var p: RPGPlayer = env.game.player
	assert_true(p.check_action(), "action button starts the door event")
	assert_true(env.rpg.scheduler.input_locked(), "input locked while the main event runs")
	assert_true(await env.settle())
	assert_eq(env.game.map.map_id, "town", "still in town")
	assert_false(env.rpg.scheduler.input_locked(), "lock released")


func test_door_example_transfers_when_unlocked() -> void:
	env.rpg.set_switch("door_unlocked", true)
	await frames(2)
	assert_true(env.game.player.check_action())
	assert_true(await env.settle())
	assert_eq(env.game.map.map_id, "house_inside")
	assert_eq(env.game.player.cell, Vector2i(5, 9))
	assert_eq(env.game.player.facing, "up")


func test_touch_trigger_fires_once_per_step() -> void:
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(3, 2))
	assert_true(p.step(Vector2i.DOWN))
	await env.walk_done(p)
	assert_true(await env.settle())
	await frames(5)
	assert_eq(env.rpg.get_variable("counter"), 1, "touch fired exactly once")
	assert_true(p.step(Vector2i.RIGHT))
	await env.walk_done(p)
	assert_true(p.step(Vector2i.LEFT))
	await env.walk_done(p)
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("counter"), 2, "a new step onto the plate fires again")


func test_autorun_runs_until_it_stops_itself() -> void:
	env.rpg.set_switch("autorun_on", true)
	assert_true(await env.settle())
	await frames(5)
	assert_eq(env.rpg.get_variable("counter"), 10, "autorun ran once then turned itself off")
	assert_false(env.rpg.get_switch("autorun_on"))


func test_autorun_that_never_stops_is_reported() -> void:
	env.rpg.data.common_events["stuck"] = {"id": "stuck", "name": "Stuck", "trigger": "autorun", "switch": "", "commands": [
		{"type": "comment", "text": "forgot to turn myself off"}]}
	for i in 120:
		await frames(1)
		if env.rpg._autorun_warned.has("common:stuck"):
			break
	assert_true(env.rpg._autorun_warned.has("common:stuck"), "a debug warning names the autorun")
	env.rpg.data.common_events.erase("stuck")
	await frames(3)
	assert_eq(env.rpg._autorun_repeats, 0, "the chain counter resets once the player has control")


func test_event_debug_info_explains_pages() -> void:
	var door: Node = null
	for ev in env.game.map.characters():
		if ev is RPGEvent and ev.data.get("pages", []).size() >= 2:
			door = ev
			break
	assert_true(door != null, "the fixture has an event with two pages")
	var d: Dictionary = door.debug_info()
	assert_eq(d.pages.size(), door.data.pages.size())
	assert_true(d.pages[0].ok or d.pages[0].failing != "")
	var failing := 0
	for p in d.pages:
		if not p.ok:
			failing += 1
			assert_true(str(p.failing) != "", "a failing page names its condition")
	assert_eq(d.page, door.best_page())


func test_parallel_has_one_copy_and_stops_on_page_change() -> void:
	env.rpg.set_switch("parallel_on", true)
	await frames(3)
	assert_eq(env.rpg.scheduler.parallels.size(), 1, "one parallel task")
	await env.tree.create_timer(0.4).timeout
	var ticks: int = env.rpg.get_variable("ticks")
	assert_true(ticks >= 3, "parallel repeated (%d)" % ticks)
	assert_false(env.rpg.scheduler.input_locked(), "parallel does not block the player")
	env.rpg.set_switch("parallel_on", false)
	await frames(3)
	assert_eq(env.rpg.scheduler.parallels.size(), 0, "stopped after page change")
	var after: int = env.rpg.get_variable("ticks")
	await env.tree.create_timer(0.2).timeout
	assert_eq(env.rpg.get_variable("ticks"), after, "no more ticks")


func test_self_switch_chest_opens_once() -> void:
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(5, 6))
	p.force_turn("up")
	assert_true(p.check_action())
	assert_true(await env.settle())
	await frames(2)
	assert_eq(env.rpg.get_variable("counter"), 100)
	assert_eq(env.game.map.get_event("chest").page_index, 1, "self switch A page")
	assert_false(p.check_action(), "empty page does nothing")
	assert_eq(env.rpg.get_variable("counter"), 100)


func test_recursion_hits_depth_limit_with_error() -> void:
	var r: RPGResult = await env.rpg.run_common_event("recurse")
	assert_true(r.is_error(), "depth limit is an error")
	assert_true(r.message.contains("depth"), r.message)
	assert_false(env.rpg.scheduler.input_locked())


func test_loop_without_wait_yields_instead_of_freezing() -> void:
	var start := Engine.get_process_frames()
	var r: RPGResult = await env.rpg.run_common_event("busy_loop")
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 2000)
	assert_true(Engine.get_process_frames() - start > 5, "spread over frames by the budget")


func test_cancel_releases_input_lock() -> void:
	var t: RPGScheduler.Ticket = env.rpg.scheduler.request_main("long", [{"type": "wait", "seconds": 30}], {"kind": "test"}, null)
	await frames(3)
	assert_true(env.rpg.scheduler.input_locked())
	await env.rpg.scheduler.cancel_all("test")
	var r: RPGResult = await t.wait()
	assert_true(r.is_cancelled(), str(r))
	assert_false(env.rpg.scheduler.input_locked(), "lock released after cancel")


func test_extension_error_releases_input_lock() -> void:
	var r: RPGResult = await env.rpg.run_commands([{"type": "explode", "message": "kaboom"}])
	assert_true(r.is_error())
	assert_true(r.message.contains("kaboom"))
	assert_eq(r.where.get("command", ""), "explode", "error says where")
	assert_false(env.rpg.scheduler.input_locked(), "never leaves the input locked")


func test_unknown_and_disabled_commands_stop_with_named_error() -> void:
	var r: RPGResult = await env.rpg.run_commands([{"type": "fancy_effect"}])
	assert_true(r.is_error())
	assert_true(r.message.contains("fancy_effect"), r.message)
	var r2: RPGResult = await env.rpg.run_commands([{"type": "no_such_thing", "x": 1}])
	assert_true(r2.is_error())


func test_branches_choices_and_flow() -> void:
	env.rpg.ui.message_box.auto_choice = 1
	var cmds := [
		{"type": "show_choices", "choices": [
			{"label": "A", "then": [{"type": "set_variable", "id": "counter", "value": 1}]},
			{"label": "B", "then": [{"type": "set_variable", "id": "counter", "value": 2}]},
		]},
		{"type": "if", "condition": {"kind": "variable", "id": "counter", "op": "==", "value": 2}, "then": [
			{"type": "set_switch", "id": "touched", "value": "on"},
			{"type": "exit_event"},
		], "else": []},
		{"type": "set_variable", "id": "counter", "value": 99},
	]
	var r: RPGResult = await env.rpg.run_commands(cmds)
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 2, "exit_event stopped before the last line")
	assert_true(env.rpg.get_switch("touched"))


func test_run_scene_contract() -> void:
	var scene := "res://tests/fixtures/scenes/quick_scene.gd"
	var r: RPGResult = await env.rpg.run_commands([{"type": "run_scene", "scene": scene, "args": {"value": "gold"}, "result": "scene_result"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("scene_result"), "gold", "result stored in the variable")
	assert_false(env.rpg.ui.scene_open(), "host removed the scene")
	var r2: RPGResult = await env.rpg.run_commands([{"type": "run_scene", "scene": scene, "args": {"cancel": true}, "on_cancel": [{"type": "set_variable", "id": "counter", "value": 5}]}])
	assert_true(r2.is_ok(), str(r2))
	assert_eq(env.rpg.get_variable("counter"), 5, "cancel branch ran")
	var r3: RPGResult = await env.rpg.run_commands([{"type": "run_scene", "scene": scene, "args": {"never": true}, "timeout": 0.2}])
	assert_true(r3.is_error(), "timeout reported")
	assert_false(env.rpg.scheduler.input_locked(), "lock released after timeout")
	assert_false(env.rpg.ui.scene_open())


func test_typed_variables() -> void:
	var st: RPGGameState = env.rpg.state
	assert_true(st.set_variable("counter", 5))
	assert_eq(typeof(st.get_variable("counter")), TYPE_INT)
	assert_true(st.set_variable("ratio", 3))
	assert_eq(typeof(st.get_variable("ratio")), TYPE_FLOAT)
	assert_false(st.set_variable("counter", "abc"), "text into a number variable is refused")
	assert_true(st.set_variable("hero_name", "Mira"))
	assert_true(st.check_condition({"kind": "variable", "id": "hero_name", "op": "==", "value": "Mira"}))
	assert_false(st.check_condition({"kind": "variable", "id": "hero_name", "op": "<", "value": "Z"}), "text allows only = and !=")
	assert_false(st.set_switch("not_a_switch", true), "unknown switch refused")


func test_blocked_movement_is_deterministic() -> void:
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(12, 8))
	assert_false(p.step(Vector2i.UP), "the door (same priority) blocks")
	p.place(Vector2i(0, 5))
	assert_false(p.step(Vector2i.LEFT), "edge of the map blocks")
	p.place(Vector2i(3, 2))
	assert_true(p.step(Vector2i.DOWN), "below-priority event never blocks")
	await env.settle()


func test_transfer_failure_keeps_previous_map() -> void:
	var r: RPGResult = await env.game.transfer("nowhere", Vector2i(1, 1), "down", "black")
	assert_true(r.is_error())
	assert_eq(env.game.map.map_id, "town")
	var r2: RPGResult = await env.game.transfer("house_inside", Vector2i(99, 99), "down", "black")
	assert_true(r2.is_error(), "cell outside map")
	var r3: RPGResult = await env.game.transfer("house_inside", Vector2i(2, 2), "down", "black")
	assert_true(r3.is_error(), "occupied cell fails without fallback")
	assert_eq(env.game.map.map_id, "town", "previous map still active")
	assert_false(env.rpg.scheduler.input_locked(), "control given back")
	assert_false(env.rpg.screen.is_faded, "screen not left black")
	var r4: RPGResult = await env.game.transfer("house_inside", Vector2i(2, 2), "down", "none", 2)
	assert_true(r4.is_ok(), "fallback finds a free cell: %s" % r4)
	assert_ne(env.game.player.cell, Vector2i(2, 2))


func test_label_and_jump_to_label() -> void:
	# A jump out of a loop to a label in the outer list; and a backwards jump that counts.
	var cmds := [
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 0},
		{"type": "label", "name": "again"},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
		{"type": "loop", "commands": [
			{"type": "if", "condition": {"kind": "variable", "id": "counter", "op": ">=", "value": 3}, "then": [{"type": "jump_to_label", "name": "done"}], "else": [{"type": "jump_to_label", "name": "again"}]},
		]},
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 999},
		{"type": "label", "name": "done"},
	]
	var r: RPGResult = await env.rpg.run_commands(cmds, {"kind": "api", "id": "labels"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 3, "jumped back twice, then out past the 999")
	var bad: RPGResult = await env.rpg.run_commands([{"type": "jump_to_label", "name": "nowhere"}], {"kind": "api", "id": "labels"})
	assert_true(bad.is_error() and bad.message.contains("nowhere"), str(bad))


func test_change_encounter_menu_and_save_access() -> void:
	await env.rpg.run_commands([{"type": "change_encounter", "enabled": false}, {"type": "change_access", "what": "save", "enabled": false}, {"type": "change_access", "what": "menu", "enabled": false}], {"kind": "api", "id": "t"})
	assert_false(env.rpg.state.access.encounters)
	assert_false(env.rpg.state.access.save)
	assert_false(env.rpg.state.access.menu)
	var d: Dictionary = env.rpg.state.to_dict()
	env.rpg.state.new_game()
	assert_true(env.rpg.state.access.menu, "new game resets access")
	env.rpg.state.from_dict(d)
	assert_false(env.rpg.state.access.save, "saved with the game")


func test_game_data_operand() -> void:
	env.rpg.state.gold = 250
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "counter", "operation": "set", "value": {"game_data": {"kind": "gold"}}},
	], {"kind": "api", "id": "gd"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 250)
	assert_eq(env.rpg.state.game_data({"kind": "party_size"}), env.rpg.state.party.size())
	assert_eq(env.rpg.state.game_data({"kind": "item", "id": "nothing"}), 0)
