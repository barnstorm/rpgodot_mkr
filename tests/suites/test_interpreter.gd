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


func test_game_data_character_map_party() -> void:
	# Character game data (player at 12, 8 facing up) and the map id, read through a command.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "hero_name", "operation": "set", "value": {"game_data": {"kind": "map_id"}}},
		{"type": "set_variable", "id": "ticks", "operation": "set", "value": {"game_data": {"kind": "character", "target": "player", "field": "x"}}},
		{"type": "set_variable", "id": "ratio", "operation": "set", "value": {"game_data": {"kind": "character", "target": "player", "field": "direction"}}},
	], {"kind": "api", "id": "gd2"})
	assert_true(r.is_ok(), str(r))
	assert_eq(str(env.rpg.get_variable("hero_name")), "town", "map id is the string id")
	assert_eq(int(env.rpg.get_variable("ticks")), 12, "player x cell")
	assert_eq(int(env.rpg.get_variable("ratio")), 8, "facing up reads as RPG Maker's 8")
	# Party slots hold actor ids (empty past the end).
	env.rpg.state.party.append("hero")
	assert_eq(str(env.rpg.state.game_data({"kind": "party_member", "slot": 0})), "hero")
	assert_eq(str(env.rpg.state.game_data({"kind": "party_member", "slot": 4})), "")
	# No running map context: character and map id explain themselves.
	assert_eq(env.rpg.state.game_data({"kind": "map_id"}), "", "needs a command context")


func test_game_data_counters_and_last_used() -> void:
	var st: RPGGameState = env.rpg.state
	for k in ["saves", "battles", "victories", "defeats", "escapes"]:
		st.bump_counter(k)
	st.bump_counter("victories")
	assert_eq(int(st.game_data({"kind": "counter", "which": "saves"})), 1)
	assert_eq(int(st.game_data({"kind": "counter", "which": "victories"})), 2)
	assert_eq(int(st.game_data({"kind": "counter", "which": "battles"})), 1)
	st.record_last_used({"skill": "fire", "target_enemy": 1})
	st.record_last_used({"actor": "hero"})
	assert_eq(str(st.game_data({"kind": "last_used", "what": "skill"})), "fire")
	assert_eq(int(st.game_data({"kind": "last_used", "what": "target_enemy"})), 1)
	assert_eq(str(st.game_data({"kind": "last_used", "what": "actor"})), "hero")
	assert_eq(str(st.game_data({"kind": "last_used", "what": "item"})), "", "untouched keys stay empty")
	# Both survive a save and load round trip.
	var d: Dictionary = st.to_dict()
	st.new_game()
	assert_eq(int(st.game_data({"kind": "counter", "which": "victories"})), 0, "new game resets counters")
	st.from_dict(d)
	assert_eq(int(st.game_data({"kind": "counter", "which": "victories"})), 2, "counters restored")
	assert_eq(str(st.game_data({"kind": "last_used", "what": "skill"})), "fire", "last used restored")


func test_variable_target_range() -> void:
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 10},
		{"type": "set_variable", "id": "ratio", "operation": "set", "value": 1},
		{"type": "set_variable", "target": "range", "from": "counter", "to": "ratio", "operation": "add", "value": 5},
	], {"kind": "api", "id": "range"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 15)
	assert_eq(float(env.rpg.get_variable("ratio")), 6.0)
	# Reversed endpoints span the same variables.
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "range", "from": "ratio", "to": "counter", "operation": "set", "value": 2},
	], {"kind": "api", "id": "range2"})
	assert_true(r2.is_ok(), str(r2))
	assert_eq(int(env.rpg.get_variable("counter")), 2)
	assert_eq(float(env.rpg.get_variable("ratio")), 2.0)


func test_variable_range_is_atomic() -> void:
	await env.rpg.run_commands([
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 7},
		{"type": "set_variable", "id": "ticks", "operation": "set", "value": 8},
	])
	# counter..ticks includes flag (bool) and hero_name (string): adding a number fits neither, so
	# nothing in the range changes.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "range", "from": "counter", "to": "ticks", "operation": "add", "value": 5},
	], {"kind": "api", "id": "atomic"})
	assert_true(r.is_error(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 7, "unchanged")
	assert_eq(int(env.rpg.get_variable("ticks")), 8, "unchanged")
	# Undeclared endpoints name nothing.
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "range", "from": "counter", "to": "nope", "operation": "set", "value": 1},
	], {"kind": "api", "id": "atomic2"})
	assert_true(r2.is_error() and r2.message.contains("nope"), str(r2))


func test_variable_range_rerolls_random_per_variable() -> void:
	env.rpg.rng.seed = hash("dice")
	var twin := RandomNumberGenerator.new()
	twin.seed = hash("dice")
	var want_a := twin.randi_range(1, 1000)
	var want_b := twin.randi_range(1, 1000)
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "range", "from": "counter", "to": "ratio", "operation": "set", "value": {"random": [1, 1000]}},
	], {"kind": "api", "id": "dice"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), want_a, "first roll")
	assert_eq(float(env.rpg.get_variable("ratio")), float(want_b), "each variable gets its own roll")


func test_variable_pointer_target_and_source() -> void:
	# hero_name holds the id of the variable to change ("ticks").
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "hero_name", "operation": "set", "value": "ticks"},
		{"type": "set_variable", "target": "pointer", "pointer": "hero_name", "operation": "set", "value": 41},
		{"type": "set_variable", "id": "counter", "operation": "set", "value": {"pointer": "hero_name"}},
	], {"kind": "api", "id": "ptr"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("ticks")), 41, "the pointed-to variable changed")
	assert_eq(int(env.rpg.get_variable("counter")), 41, "pointer source reads the pointed-to value")
	# A pointer variable holding nothing names nothing.
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "pointer", "pointer": "scene_result", "operation": "set", "value": 1},
	], {"kind": "api", "id": "ptr2"})
	assert_true(r2.is_error(), str(r2))


# --- Control Switch target modes (#55) ---------------------------------------------------------------


func test_switch_target_range() -> void:
	# Switches in state.json order: door_unlocked, autorun_on, parallel_on, touched.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_switch", "target": "range", "from": "autorun_on", "to": "touched", "value": "on"},
	], {"kind": "api", "id": "swrange"})
	assert_true(r.is_ok(), str(r))
	assert_false(env.rpg.get_switch("door_unlocked"), "before the range")
	assert_true(env.rpg.get_switch("autorun_on"))
	assert_true(env.rpg.get_switch("parallel_on"))
	assert_true(env.rpg.get_switch("touched"))
	# Reversed endpoints span the same switches; toggle flips each one where it stands.
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_switch", "target": "range", "from": "touched", "to": "autorun_on", "value": "toggle"},
	], {"kind": "api", "id": "swrange2"})
	assert_true(r2.is_ok(), str(r2))
	assert_false(env.rpg.get_switch("autorun_on"))
	assert_false(env.rpg.get_switch("parallel_on"))
	assert_false(env.rpg.get_switch("touched"))


func test_switch_range_is_atomic_and_indirect() -> void:
	await env.rpg.run_commands([
		{"type": "set_switch", "id": "autorun_on", "value": "on"},
		{"type": "set_switch", "id": "door_unlocked", "value": "off"},
	])
	# A range naming an undeclared switch flips nothing.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_switch", "target": "range", "from": "door_unlocked", "to": "ghost", "value": "on"},
	], {"kind": "api", "id": "swatom"})
	assert_true(r.is_error() and r.message.contains("ghost"), str(r))
	assert_false(env.rpg.get_switch("door_unlocked"), "unchanged")
	assert_true(env.rpg.get_switch("autorun_on"), "unchanged")
	# Indirect: the switch id comes from a variable (RM2003's switch number from a variable).
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "hero_name", "operation": "set", "value": "touched"},
		{"type": "set_switch", "target": "pointer", "pointer": "hero_name", "value": "on"},
	], {"kind": "api", "id": "swptr"})
	assert_true(r2.is_ok(), str(r2))
	assert_true(env.rpg.get_switch("touched"))
	var r3: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "hero_name", "operation": "set", "value": "ghost"},
		{"type": "set_switch", "target": "pointer", "pointer": "hero_name", "value": "on"},
	], {"kind": "api", "id": "swptr2"})
	assert_true(r3.is_error(), str(r3))


func test_switch_range_sets_pages_at_the_safe_point() -> void:
	# The whole range lands, then pages re-check at the next safe point (the door's page 2 needs
	# door_unlocked, the range's first switch).
	var door: RPGEvent = env.game.map.get_event("town_house_door")
	assert_eq(door.page_index, 0)
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_switch", "target": "range", "from": "door_unlocked", "to": "touched", "value": "on"},
	], {"kind": "api", "id": "swpage"})
	assert_true(r.is_ok(), str(r))
	assert_true(env.rpg.get_switch("door_unlocked") and env.rpg.get_switch("touched"), "whole range set")
	await frames(2)
	assert_eq(door.page_index, 1, "pages re-checked after the range")


# --- Self switches anywhere and self variables (#57) --------------------------------------------------


func test_self_switch_on_another_map() -> void:
	# From town: flip a self switch of an event on house_inside, and read it back through a
	# condition that names the map and event.
	var chest: RPGEvent = env.game.map.get_event("chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "switch": "B", "value": "on", "event": "blocker", "map": "house_inside"},
	], {"kind": "api", "id": "xsw"}, chest)
	assert_true(r.is_ok(), str(r))
	assert_true(env.rpg.state.get_self_switch("house_inside", "blocker", "B"))
	assert_false(env.rpg.state.get_self_switch("town", "chest", "B"), "this event's own B untouched")
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "if", "condition": {"kind": "self_switch", "id": "B", "map": "house_inside", "event": "blocker"}, "then": [
			{"type": "set_variable", "id": "counter", "operation": "set", "value": 7},
		], "else": []},
	], {"kind": "api", "id": "xsw2"}, chest)
	assert_true(r2.is_ok(), str(r2))
	assert_eq(env.rpg.get_variable("counter"), 7, "a condition can test another map's self switch")
	# A page on that other map follows the switch once the player gets there (blocker gains a
	# page-2 gated on its own A).
	var r3: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "switch": "A", "value": "on", "event": "blocker", "map": "house_inside"},
	], {"kind": "api", "id": "xsw3"}, chest)
	assert_true(r3.is_ok(), str(r3))
	var tr: RPGResult = await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	assert_true(tr.is_ok(), str(tr))
	var blocker: RPGEvent = env.game.map.get_event("blocker")
	blocker.data.pages.append({
		"conditions": [{"kind": "self_switch", "id": "A"}],
		"graphic": null, "movement": {"type": "fixed"}, "options": {"walk_anim": false, "step_anim": false, "direction_fix": false, "through": false},
		"priority": "same", "trigger": "action_button", "commands": [],
	})
	blocker.refresh()
	assert_eq(blocker.page_index, 1, "the remote-set switch picked the page up on arrival")


func test_self_switch_reset_modes() -> void:
	var chest: RPGEvent = env.game.map.get_event("chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "switch": "A", "value": "on"},
		{"type": "set_variable", "target": "self", "name": "times_opened", "operation": "set", "value": 2},
	], {"kind": "api", "id": "rmode"}, chest)
	assert_true(r.is_ok(), str(r))
	assert_true(env.rpg.state.get_self_switch("town", "chest", "A"))
	assert_eq(env.rpg.state.get_self_variable("town", "chest", "times_opened"), 2)
	# Reset one event (blank event = this event): its switches and variables both go.
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "mode": "reset_event"},
	], {"kind": "api", "id": "rmode2"}, chest)
	assert_true(r2.is_ok(), str(r2))
	assert_false(env.rpg.state.get_self_switch("town", "chest", "A"))
	assert_eq(env.rpg.state.get_self_variable("town", "chest", "times_opened"), 0, "reset clears variables too")
	# Reset whole map: another town event's switch goes as well.
	env.rpg.state.set_self_switch("town", "town_house_door", "C", true)
	var r3: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "mode": "reset_map"},
	], {"kind": "api", "id": "rmode3"}, chest)
	assert_true(r3.is_ok(), str(r3))
	assert_false(env.rpg.state.get_self_switch("town", "town_house_door", "C"), "every event on the map")
	# A remote reset names the map and event explicitly.
	env.rpg.state.set_self_switch("house_inside", "blocker", "A", true)
	var r4: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "mode": "reset_event", "event": "blocker", "map": "house_inside"},
	], {"kind": "api", "id": "rmode4"}, chest)
	assert_true(r4.is_ok(), str(r4))


# --- Select Item (#61) -------------------------------------------------------------------------

func _grant_items() -> void:
	env.rpg.data.db["items"]["by_id"] = {
		"potion": {"id": "potion", "name": "Potion", "key_item": false},
		"antidote": {"id": "antidote", "name": "Antidote", "key_item": false},
		"house_key": {"id": "house_key", "name": "House Key", "key_item": true},
	}
	env.rpg.state.change_items("potion", "increase", 2)
	env.rpg.state.change_items("antidote", "increase", 1)
	env.rpg.state.change_items("house_key", "increase", 1)


func test_select_item_stores_the_picked_id() -> void:
	_grant_items()
	var box = env.rpg.ui.message_box
	# Key items only: the one entry is the house key.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "select_item", "variable": "hero_name", "category": "key"},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("hero_name"), "house_key", "the picked id lands in the text variable")
	assert_false(box.is_open(), "the picker closed")
	# All items, auto pick index 1: the antidote.
	box.auto_item = 1
	await env.rpg.run_commands([{"type": "select_item", "variable": "hero_name", "category": "all"}])
	assert_eq(env.rpg.state.get_variable("hero_name"), "antidote")
	box.auto_item = 0
	# Regular items hides the key item: index 0 is the potion.
	await env.rpg.run_commands([{"type": "select_item", "variable": "hero_name", "category": "regular"}])
	assert_eq(env.rpg.state.get_variable("hero_name"), "potion")
	# A missing category field means key items (the descriptor default).
	await env.rpg.run_commands([{"type": "select_item", "variable": "hero_name"}])
	assert_eq(env.rpg.state.get_variable("hero_name"), "house_key")


func test_select_item_cancel_and_type_rules() -> void:
	_grant_items()
	var box = env.rpg.ui.message_box
	# Cancel stores "" in a text variable.
	box.auto_item = -1
	await env.rpg.run_commands([{"type": "select_item", "variable": "hero_name"}])
	assert_eq(env.rpg.state.get_variable("hero_name"), "")
	# Cancel stores 0 in an int variable.
	await env.rpg.run_commands([{"type": "select_item", "variable": "counter"}])
	assert_eq(env.rpg.state.get_variable("counter"), 0)
	# Picking into a number variable refuses: item ids are names.
	box.auto_item = 0
	var r: RPGResult = await env.rpg.run_commands([{"type": "select_item", "variable": "counter"}])
	assert_true(r.is_error(), str(r))
	assert_eq(env.rpg.state.get_variable("counter"), 0, "nothing stored")


# --- Movement types (#58) ----------------------------------------------------------------------

## Waits for the event's next autonomous step and returns its cell (the start cell on timeout).
func _await_step(ev: RPGEvent, timeout := 240) -> Vector2i:
	var before := ev.cell
	for i in timeout:
		await frames(1)
		if ev.cell != before:
			return ev.cell
	return ev.cell


## Teleports the chest event to a cell so movement tests can stage it anywhere.
func _place_chest(at: Vector2i) -> RPGEvent:
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "chest", "position": [at.x, at.y]},
	])
	assert_true(r.is_ok(), str(r))
	return env.game.map.get_event("chest")


func test_vertical_movement_patrols_and_reverses() -> void:
	var mm: RPGMovement = env.game.map.movement
	var ev: RPGEvent = env.game.map.get_event("chest")
	# A cell with open ground up and down and its way two below blocked (the map edge): down,
	# bounce off the block, up. The fixture map is fully open, so the edge is the wall.
	var spot := Vector2i(-1, -1)
	for y in range(2, 14):
		for x in range(2, 25):
			var c := Vector2i(x, y)
			if c == env.game.player.cell:
				continue
			if mm.can_move(ev, c, Vector2i.DOWN) and mm.can_move(ev, c, Vector2i.UP) \
					and not mm.can_move(ev, c + Vector2i.DOWN, Vector2i.DOWN):
				spot = c
				break
		if spot.x >= 0:
			break
	assert_true(spot.x >= 0, "the map has an open cell backed by the map edge")
	ev = await _place_chest(spot)
	ev.frequency = 5
	ev.move_type = "vertical"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, spot + Vector2i.DOWN, "vertical starts downward")
	var c2 := await _await_step(ev)
	assert_eq(c2, spot, "the wall below turns it around")
	var c3 := await _await_step(ev)
	assert_eq(c3, spot + Vector2i.UP, "it keeps going up")
	assert_eq(c3.x, spot.x, "vertical never leaves its column")


func test_horizontal_movement_patrols_and_reverses() -> void:
	var mm: RPGMovement = env.game.map.movement
	var ev: RPGEvent = env.game.map.get_event("chest")
	# Mirror of the vertical probe: open left and right, the way two right blocked (map edge).
	var spot := Vector2i(-1, -1)
	for y in range(2, 14):
		for x in range(2, 25):
			var c := Vector2i(x, y)
			if c == env.game.player.cell:
				continue
			if mm.can_move(ev, c, Vector2i.LEFT) and mm.can_move(ev, c, Vector2i.RIGHT) \
					and not mm.can_move(ev, c + Vector2i.RIGHT, Vector2i.RIGHT):
				spot = c
				break
		if spot.x >= 0:
			break
	assert_true(spot.x >= 0, "the map has an open cell backed by the map edge")
	ev = await _place_chest(spot)
	ev.frequency = 5
	ev.move_type = "horizontal"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, spot + Vector2i.RIGHT, "horizontal starts rightward")
	var c2 := await _await_step(ev)
	assert_eq(c2, spot, "the wall to the right turns it around")
	var c3 := await _await_step(ev)
	assert_eq(c3, spot + Vector2i.LEFT, "it keeps going left")
	assert_eq(c3.y, spot.y, "horizontal never leaves its row")


func test_away_movement_flees_the_player() -> void:
	var mm: RPGMovement = env.game.map.movement
	var ev: RPGEvent = env.game.map.get_event("chest")
	var pc: Vector2i = env.game.player.cell
	# Open ground clearly west of the player: the fleeing direction is unambiguous (left).
	var spot := Vector2i(-1, -1)
	for dy in range(-6, 7):
		for dx in range(-9, -1):
			var c := pc + Vector2i(dx, dy)
			if absi(dx) > absi(dy) and mm.can_move(ev, c, Vector2i.LEFT):
				spot = c
				break
		if spot.x >= 0:
			break
	assert_true(spot.x >= 0, "open ground lies west of the player")
	ev = await _place_chest(spot)
	ev.frequency = 5
	ev.move_type = "away"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, spot + Vector2i.LEFT, "away steps directly away from the player")


func test_away_movement_sidesteps_at_walls() -> void:
	# The chest flees west from the player at (12, 8), but the house door is parked at (9, 8)
	# (a "same as characters" event, so it blocks). With the direct escape cut off, the flee
	# tries the perpendicular sidestep — RM's coin flip, the same one Approach uses.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "town_house_door", "position": [9, 8]},
		{"type": "set_event_location", "event": "chest", "position": [10, 8]},
	])
	assert_true(r.is_ok(), str(r))
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.frequency = 5
	ev.move_type = "away"
	ev._move_wait = 0.0
	# The sidestep fires on half the beats; force them back to back until the event moves.
	var spot := ev.cell
	var moved := spot
	for i in 240:
		await frames(1)
		ev._move_wait = 0.0
		if ev.cell != spot:
			moved = ev.cell
			break
	assert_eq(moved, spot + Vector2i.UP, "the flee sidesteps along the wall")


func test_movement_frequency_paces_the_beats() -> void:
	var mm: RPGMovement = env.game.map.movement
	var ev: RPGEvent = env.game.map.get_event("chest")
	var spot := Vector2i(-1, -1)
	for y in range(2, 14):
		for x in range(2, 25):
			var c := Vector2i(x, y)
			if c == env.game.player.cell:
				continue
			if mm.can_move(ev, c, Vector2i.DOWN):
				spot = c
				break
		if spot.x >= 0:
			break
	assert_true(spot.x >= 0, "the map has open ground below some cell")
	ev = await _place_chest(spot)
	ev.frequency = 1
	ev.move_type = "vertical"
	ev._move_wait = 0.0
	var first := await _await_step(ev)
	assert_eq(first, spot + Vector2i.DOWN, "the first beat fires at once")
	# Frequency 1 waits seconds between beats: nothing moves for at least a second.
	var held := 0
	for i in 60:
		await frames(1)
		if ev.cell != first:
			break
		held += 1
	assert_eq(held, 60, "frequency 1 paces the beats slowly")


func test_select_item_empty_list_only_cancels() -> void:
	# No items at all: the window opens, picking is impossible, cancel stores 0.
	var box = env.rpg.ui.message_box
	box.auto_item = -1
	var r: RPGResult = await env.rpg.run_commands([{"type": "select_item", "variable": "ticks"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("ticks"), 0)
	box.auto_item = 0
	assert_false(env.rpg.state.get_self_switch("house_inside", "blocker", "A"), "remote event reset")


func test_self_variable_target_modes() -> void:
	var chest: RPGEvent = env.game.map.get_event("chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 21},
		# Blank event and map: this event (chest on town).
		{"type": "set_variable", "target": "self", "name": "times_opened", "operation": "set", "value": 1},
		{"type": "set_variable", "target": "self", "name": "times_opened", "operation": "add", "value": 1},
		# Another event on this map, and an event on another map (value read from a variable).
		{"type": "set_variable", "target": "self", "name": "score", "event": "town_house_door", "operation": "set", "value": 10},
		{"type": "set_variable", "target": "self", "name": "score", "event": "blocker", "map": "house_inside", "operation": "set", "value": {"variable": "counter"}},
	], {"kind": "api", "id": "sv"}, chest)
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_self_variable("town", "chest", "times_opened"), 2, "set then add")
	assert_eq(env.rpg.state.get_self_variable("town", "town_house_door", "score"), 10, "a named event on this map")
	assert_eq(env.rpg.state.get_self_variable("house_inside", "blocker", "score"), 21, "an event on another map, value read from a variable")
	# Type rules, same as declared variables: numbers stringify into text ("5"); text that is
	# not a number is refused by a number self variable.
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "self", "name": "label", "operation": "set", "value": "hello"},
		{"type": "set_variable", "target": "self", "name": "label", "operation": "set", "value": 5},
		{"type": "set_variable", "target": "self", "name": "times_opened", "operation": "set", "value": "nope"},
	], {"kind": "api", "id": "sv2"}, chest)
	assert_true(r2.is_error(), str(r2))
	assert_eq(env.rpg.state.get_self_variable("town", "chest", "label"), "5", "a number stringifies into text")
	assert_eq(env.rpg.state.get_self_variable("town", "chest", "times_opened"), 2, "text into the int self variable refused")
	# A self variable needs an event to belong to.
	var r3: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "self", "name": "lost", "operation": "set", "value": 1},
	], {"kind": "api", "id": "sv3"})
	assert_true(r3.is_error(), "no running event")
	# Never-set reads as 0.
	assert_eq(env.rpg.state.get_self_variable("town", "chest", "never_set"), 0)


func test_self_variable_operand_and_conditions() -> void:
	var chest: RPGEvent = env.game.map.get_event("chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "target": "self", "name": "times_opened", "operation": "set", "value": 5},
		# An operand can read a self variable (blank event/map = the running one).
		{"type": "set_variable", "id": "counter", "operation": "set", "value": {"self_variable": {"name": "times_opened"}}},
		# ...and one that names the map and event explicitly.
		{"type": "set_variable", "id": "ticks", "operation": "set", "value": {"self_variable": {"map": "house_inside", "event": "blocker", "name": "score"}}},
		# Conditions: numbers compare, text only = and !=.
		{"type": "if", "condition": {"kind": "self_variable", "name": "times_opened", "op": "==", "value": 5}, "then": [
			{"type": "set_switch", "id": "touched", "value": "on"},
		], "else": []},
	], {"kind": "api", "id": "svop"}, chest)
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 5, "operand read this event's value")
	assert_eq(int(env.rpg.get_variable("ticks")), 0, "a never-set remote self variable reads 0")
	assert_true(env.rpg.get_switch("touched"), "self_variable condition compared the number")
	var st: RPGGameState = env.rpg.state
	assert_true(st.set_self_variable("town", "chest", "label", "hello"))
	assert_true(st.check_condition({"kind": "self_variable", "name": "label", "op": "==", "value": "hello", "map": "town", "event": "chest"}))
	assert_false(st.check_condition({"kind": "self_variable", "name": "label", "op": "<", "value": "z"}), "text allows only = and !=")
	assert_false(st.check_condition({"kind": "self_variable", "name": "times_opened", "op": ">", "value": 5, "map": "town", "event": "chest"}), "5 is not > 5")
	assert_true(st.check_condition({"kind": "self_variable", "name": "times_opened", "op": ">=", "value": 5, "map": "town", "event": "chest"}))


func test_self_variable_in_message_text() -> void:
	var chest: RPGEvent = env.game.map.get_event("chest")
	env.rpg.state.set_self_variable("town", "chest", "times_opened", 3)
	env.rpg.state.set_self_variable("town", "town_house_door", "times_opened", 4)
	env.rpg.state.set_self_variable("house_inside", "blocker", "score", 12)
	env.rpg.ui.message_box.auto_advance = true
	var box: Control = env.rpg.ui.message_box
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "show_text", "text": "this \\E[times_opened] door \\E[town_house_door/times_opened] far \\E[house_inside/blocker/score]"},
	], {"kind": "api", "id": "etxt"}, chest)
	assert_true(r.is_ok(), str(r))
	assert_eq(box.text_label.get_parsed_text(), "this 3 door 4 far 12", "\\E reads this event, this map and other maps")
	# Choice labels expand the same way with the event threaded in.
	box.open_choices(["open again (\\E[times_opened])"], {"_event_map": "town", "_event_id": "chest"})
	var labels := 0
	for c in box.choice_box.get_children():
		if c is Label:
			labels += 1
			assert_true(c.text.contains("open again (3)"), "label expanded the code: '%s'" % c.text)
			assert_false(c.text.contains("\\E"), "no raw code left")
	assert_eq(labels, 1)
	box.force_close()
