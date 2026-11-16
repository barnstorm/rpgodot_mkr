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


# --- Action button starts touch events (#51) -----------------------------------------------------

## Stages the floor plate (a player_touch event) at a cell with a chosen trigger and priority.
func _stage_plate(at: Vector2i, trig: String, priority := "same") -> RPGEvent:
	var plate: RPGEvent = env.game.map.get_event("floor_plate")
	plate.data["pages"][0]["trigger"] = trig
	plate.data["pages"][0]["priority"] = priority
	plate.apply_page(0)
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "floor_plate", "position": [at.x, at.y]},
	])
	assert_true(r.is_ok(), str(r))
	return plate


func test_action_button_starts_a_player_touch_event_in_front() -> void:
	# VX Ace/MV/MZ: pressing OK at a same-priority touch-triggered event starts it, so a
	# touch-triggered door can't be walked past by standing still.
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(6, 8))
	p.force_turn("up")
	var plate: RPGEvent = await _stage_plate(Vector2i(6, 7), "player_touch")
	assert_true(p.check_action(), "OK starts a same-priority player_touch event in front")
	assert_eq(plate.last_trigger, "action button")
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("counter"), 1, "the plate's commands ran")


func test_action_button_starts_an_event_touch_event_across_a_counter() -> void:
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(6, 8))
	p.force_turn("up")
	var plate: RPGEvent = await _stage_plate(Vector2i(6, 6), "event_touch")
	var mv := CountersMovement.new(env.game.map)
	mv.counters.append(Vector2i(6, 7))
	env.game.map.movement = mv
	assert_true(p.check_action(), "OK starts a touch event behind a counter")
	assert_eq(plate.last_trigger, "action button")
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("counter"), 1, "the plate's commands ran")


func test_underfoot_touch_events_do_not_start_from_the_action_button() -> void:
	# Only Action Button pages answer OK on the player's own cell (below/above priority).
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(3, 3))  # onto the plate as authored: below priority, player_touch
	p.force_turn("up")
	assert_false(p.check_action(), "a below-priority touch event underfoot does not take OK")
	var plate: RPGEvent = await _stage_plate(Vector2i(3, 3), "player_touch", "above")
	assert_false(p.check_action(), "nor an above-priority one")
	plate = await _stage_plate(Vector2i(3, 3), "action_button", "above")
	assert_true(p.check_action(), "an action_button page underfoot does")
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("counter"), 1, "the plate's commands ran")


# --- Failed steps re-fire touch events (#74) -------------------------------------------------------

func test_bumping_into_a_touch_event_fires_it_again() -> void:
	# A touch-triggered door answers every failed step into it while the player keeps pushing,
	# as in RPG Maker. The once-per-cell rule is gone; the guard is the main-interpreter-busy
	# rule: a bump while the run is going starts nothing.
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(6, 8))
	p.force_turn("up")
	var plate: RPGEvent = await _stage_plate(Vector2i(6, 7), "player_touch")
	plate.data["pages"][0]["commands"].append({"type": "wait", "seconds": 0.4})
	p._bump(Vector2i.UP)
	await frames(2)
	assert_eq(env.rpg.get_variable("counter"), 1, "the first failed step fires it")
	p._bump(Vector2i.UP)
	assert_eq(env.rpg.get_variable("counter"), 1, "a run in progress absorbs the next bump")
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("counter"), 1, "the wait finished without a second run")
	p._bump(Vector2i.UP)
	assert_true(await env.settle())
	await frames(2)
	assert_eq(env.rpg.get_variable("counter"), 2, "bumping again once the run ended fires it again")


# --- Same-frame page refresh (#77) -----------------------------------------------------------------

func test_classic_rules_refresh_pages_before_each_command() -> void:
	var ev: RPGEvent = env.game.map.get_event("chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "event": "chest", "map": "town", "switch": "A", "value": true},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.page_index, 1, "the command after the switch already sees the new page")


func test_a_move_route_uses_the_new_page_in_the_same_list() -> void:
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.data["pages"][1]["movement"] = {"type": "fixed", "speed": 6}
	ev.data["pages"][1]["graphic"] = {"sheet": "door_wood", "facing": "down"}
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "event": "chest", "map": "town", "switch": "A", "value": true},
		{"type": "move_route", "target": "chest", "wait": false, "steps": [{"step": "down"}]},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.page_index, 1, "the move route saw the new page, same frame")
	assert_eq(ev.speed, 6, "the new page's speed applied before the route")
	assert_eq(str(ev.graphic.get("sheet", "")), "door_wood", "the new page's graphic applied")


func test_mv_style_rules_flush_only_before_a_move_route() -> void:
	env.rpg.data.project["rules"] = "vx_ace"
	var ev: RPGEvent = env.game.map.get_event("chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "event": "chest", "map": "town", "switch": "A", "value": true},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.page_index, 0, "a plain command does not flush: MV refreshes on the next frame")
	await frames(2)
	assert_eq(ev.page_index, 1, "the per-frame refresh still applies the page")
	var r2: RPGResult = await env.rpg.run_commands([
		{"type": "set_self_switch", "event": "chest", "map": "town", "switch": "A", "value": false},
		{"type": "move_route", "target": "chest", "wait": false, "steps": [{"step": "down"}]},
	])
	assert_true(r2.is_ok(), str(r2))
	assert_eq(ev.page_index, 0, "the move route flushed the page back, same frame")


func test_a_page_change_caused_by_the_running_event_does_not_stop_it() -> void:
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.data["pages"][0]["commands"] = [
		{"type": "set_self_switch", "switch": "A", "value": true},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	]
	var p: RPGPlayer = env.game.player
	p.place(Vector2i(5, 6))
	p.force_turn("up")
	assert_true(p.check_action(), "the chest starts")
	assert_true(await env.settle(), "the run finished (no error, no hang)")
	assert_eq(env.rpg.get_variable("counter"), 1, "the command after the page change still ran")
	assert_eq(ev.page_index, 1, "the chest ended on its new page")


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
	assert_true(r.message.contains("recurse"), "the error names the call chain: %s" % r.message)
	assert_false(env.rpg.scheduler.input_locked())


func test_call_event_recursion_names_the_chain() -> void:
	# Depth limit errors list the called pages/common events, so a recursion is easy to spot.
	var chest: RPGEvent = env.game.map.get_event("chest")
	chest.data["pages"].append({
		"conditions": [], "graphic": null, "movement": {"type": "fixed"}, "options": {},
		"priority": "same", "trigger": "action_button",
		"commands": [{"type": "call_common_event", "id": "recurse"}],
	})
	var r: RPGResult = await env.rpg.run_commands([{"type": "call_event", "target": "id", "id": "chest", "page": 3}])
	assert_true(r.is_error(), str(r))
	assert_true(r.message.contains("common:recurse"), "the chain names the common event: %s" % r.message)
	assert_true(r.message.contains("event:town/chest:2"), "and the called page: %s" % r.message)


func test_deeply_nested_branches_do_not_hit_a_depth_limit() -> void:
	# The depth limit counts only common-event and page calls (100, like MV); branches, loops and
	# choices nest freely, as in every RPG Maker.
	var cmds: Array = [{"type": "set_variable", "id": "counter", "operation": "set", "value": 7}]
	for _i in 40:
		cmds = [{"type": "if", "condition": {"kind": "variable", "id": "counter", "op": ">=", "value": 0}, "then": cmds, "else": []}]
	var r: RPGResult = await env.rpg.run_commands(cmds)
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 7, "the innermost command ran through 40 nested branches")


func test_a_long_command_list_finishes_in_one_frame() -> void:
	# RM2000/2003 runs up to 10,000 commands per interpreter per frame; the kit matches, so a
	# 2,000-iteration loop (or a HUD redraw) is never shown half done.
	var start := Engine.get_process_frames()
	var r: RPGResult = await env.rpg.run_common_event("busy_loop")
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 2000)
	assert_true(Engine.get_process_frames() - start <= 2, "finished within one frame")


func test_the_budget_still_yields_with_a_small_setting() -> void:
	# A project can lower the budget (project.json: "interpreter_budget"); the interpreter then
	# spreads the work over frames instead of freezing the game.
	env.rpg.data.project["interpreter_budget"] = 100
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


# --- Forbid Event Overlap (#64) ------------------------------------------------------------------

## Restages an event's page 0 (its priority and options) and re-applies it in place.
func _stage_page(ev: RPGEvent, priority: String, options: Dictionary) -> void:
	ev.data["pages"][0]["priority"] = priority
	ev.data["pages"][0]["options"] = options
	ev.apply_page(0)


## Places floor_plate, the fixture's below-priority event, somewhere out of the way.
func _place_plate(at: Vector2i) -> RPGEvent:
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "floor_plate", "position": [at.x, at.y]},
	])
	assert_true(r.is_ok(), str(r))
	return env.game.map.get_event("floor_plate")


func test_forbid_overlap_keeps_two_below_events_apart() -> void:
	var mm: RPGMovement = env.game.map.movement
	var mover: RPGEvent = await _place_chest(Vector2i(7, 6))
	var target: RPGEvent = await _place_plate(Vector2i(6, 6))
	_stage_page(mover, "below", {"forbid_overlap": true})
	_stage_page(target, "below", {})
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.LEFT), "occupied", "the same-layer event blocks")
	assert_false(mover.step(Vector2i.LEFT), "the step is refused")
	assert_eq(mover.cell, Vector2i(7, 6), "the mover stays put")


func test_below_events_share_a_cell_without_the_option() -> void:
	var mm: RPGMovement = env.game.map.movement
	var mover: RPGEvent = await _place_chest(Vector2i(7, 6))
	var target: RPGEvent = await _place_plate(Vector2i(6, 6))
	_stage_page(mover, "below", {})
	_stage_page(target, "below", {})
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.LEFT), "", "below events overlap by default")
	assert_true(mover.step(Vector2i.LEFT), "the step is taken")
	while mover.moving:
		await frames(1)
	assert_eq(mover.cell, Vector2i(6, 6), "both events end up on the same cell")
	assert_eq(target.cell, Vector2i(6, 6))


func test_walk_through_overrides_forbid_overlap() -> void:
	var mm: RPGMovement = env.game.map.movement
	var mover: RPGEvent = await _place_chest(Vector2i(7, 6))
	await _place_plate(Vector2i(6, 6))
	_stage_page(mover, "below", {"forbid_overlap": true, "through": true})
	assert_true(mover.through, "the page option applied")
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.LEFT), "", "through ignores the other event")


func test_the_player_does_not_block_a_below_event_with_forbid_overlap() -> void:
	var mm: RPGMovement = env.game.map.movement
	# The player starts on (12, 8).
	var mover: RPGEvent = await _place_chest(Vector2i(11, 8))
	_stage_page(mover, "below", {"forbid_overlap": true})
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.RIGHT), "", "only events block, not the player")


func test_forbid_overlap_only_blocks_the_movers_own_layer() -> void:
	var mm: RPGMovement = env.game.map.movement
	var mover: RPGEvent = await _place_chest(Vector2i(7, 6))
	var target: RPGEvent = await _place_plate(Vector2i(6, 6))
	_stage_page(mover, "below", {"forbid_overlap": true})
	_stage_page(target, "above", {})
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.LEFT), "", "an above event is another layer")
	_stage_page(target, "below", {})
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.LEFT), "occupied", "a below event is the mover's layer")
	# Same-priority events have always blocked each other; the option changes nothing there.
	_stage_page(mover, "same", {})
	_stage_page(target, "same", {})
	assert_eq(mm.check_move(mover, mover.cell, Vector2i.LEFT), "occupied", "same-priority events always block")


func test_forbid_overlap_follows_the_active_page() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(7, 6))
	_stage_page(ev, "below", {"forbid_overlap": true})
	assert_true(ev.forbid_overlap, "page 0 carries the option")
	_stage_page(ev, "below", {})
	assert_false(ev.forbid_overlap, "a page without it clears the flag")
	ev.apply_page(-1)
	assert_false(ev.forbid_overlap, "no active page clears the flag")
	_stage_page(ev, "below", {"forbid_overlap": true})
	assert_true(ev.forbid_overlap, "the option applies again on the next page change")


# --- Move route step kinds (#65) -----------------------------------------------------------------

## Runs a move route on the chest and returns when it is done.
func _route(steps: Array, extra := {}) -> RPGResult:
	var cmd := {"type": "move_route", "target": "chest", "steps": steps}
	cmd.merge(extra)
	return await env.rpg.run_commands([cmd])


## A tiny inline tileset: one source holding a floor tile (passage 15) and a wall tile (passage 0).
## The fixture map has no tiles, so tests that need walls bring their own.
func _floor_and_wall_tileset() -> Array:
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(32, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "passage")
	ts.set_custom_data_layer_type(0, TYPE_INT)
	var sid := ts.add_source(src)
	src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("passage", 15)
	src.get_tile_data(Vector2i(1, 0), 0).set_custom_data("passage", 0)
	return [ts, sid]


## Paints a wall tile on the cell so routes and pathfinding have something to go around. The whole
## map gets a floor of passage-15 tiles first: with no layer used every empty cell reads 15, but
## once any cell holds a tile, empty cells read 0 — one painted wall would wall off the map.
func _wall_at(at: Vector2i) -> void:
	var map: Node = env.game.map
	if map.tile_layers.is_empty():
		# The fixture map has no Layer1..Layer4 (an empty list reads as fully open) — add one.
		var fresh := TileMapLayer.new()
		fresh.name = "Layer1"
		map.add_child(fresh)
		map.tile_layers.append(fresh)
		map.movement.invalidate()
	var ts_sid: Array = _floor_and_wall_tileset()
	var layer: TileMapLayer = map.tile_layers[0]
	layer.tile_set = ts_sid[0]
	var s: Vector2i = map.size
	for y in s.y:
		for x in s.x:
			layer.set_cell(Vector2i(x, y), ts_sid[1], Vector2i(0, 0))
	layer.set_cell(at, ts_sid[1], Vector2i(1, 0))
	map.movement.invalidate()
	assert_eq(map.movement.passage(at), 0, "the cell is a wall now")


func test_slide_steps_keep_moving_until_blocked() -> void:
	var mm: RPGMovement = env.game.map.movement
	var ev: RPGEvent = await _place_chest(Vector2i(6, 3))
	var r: RPGResult = await _route([{"slide": "down"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.cell.x, 6, "a slide stays in its column")
	assert_true(ev.cell.y > 4, "it slid more than one cell")
	assert_false(mm.can_move(ev, ev.cell, Vector2i.DOWN), "it stopped because the way is blocked")


func test_slide_steps_stop_at_a_blocking_event() -> void:
	var r0: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "town_house_door", "position": [6, 10]},
	])
	assert_true(r0.is_ok(), str(r0))
	var ev: RPGEvent = await _place_chest(Vector2i(6, 3))
	var r: RPGResult = await _route([{"slide": "down"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.cell, Vector2i(6, 9), "the door stops the slide one cell short")
	var r2: RPGResult = await _route([{"slide": "down"}])
	assert_true(r2.is_ok(), str(r2))
	assert_eq(ev.cell, Vector2i(6, 9), "a slide that starts blocked moves nowhere")


func test_speed_and_frequency_steps_move_one_notch_and_clamp() -> void:
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.speed = 6
	assert_true((await _route([{"speed_up": true}])).is_ok())
	assert_eq(ev.speed, 6, "speed 6 cannot go higher")
	ev.speed = 1
	assert_true((await _route([{"speed_down": true}])).is_ok())
	assert_eq(ev.speed, 1, "speed 1 cannot go lower")
	ev.speed = 4
	assert_true((await _route([{"speed_up": true}, {"speed_down": true}, {"speed_up": true}])).is_ok())
	assert_eq(ev.speed, 5, "up, down and up from 4")
	ev.frequency = 5
	assert_true((await _route([{"frequency_up": true}])).is_ok())
	assert_eq(ev.frequency, 5, "frequency 5 cannot go higher")
	ev.frequency = 1
	assert_true((await _route([{"frequency_down": true}])).is_ok())
	assert_eq(ev.frequency, 1, "frequency 1 cannot go lower")
	ev.frequency = 3
	assert_true((await _route([{"frequency_down": true}])).is_ok())
	assert_eq(ev.frequency, 2, "frequency steps are one notch")


func test_opacity_steps_move_32_and_clamp() -> void:
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.opacity = 200
	assert_true((await _route([{"opacity_up": true}])).is_ok())
	assert_eq(ev.opacity, 232, "up is 32 more")
	assert_true((await _route([{"opacity_up": true}])).is_ok())
	assert_eq(ev.opacity, 255, "clamped at fully visible")
	ev.opacity = 10
	assert_true((await _route([{"opacity_down": true}])).is_ok())
	assert_eq(ev.opacity, 0, "clamped at fully transparent")


func test_move_to_walks_the_shortest_way_and_goes_around_walls() -> void:
	var mm: RPGMovement = env.game.map.movement
	_wall_at(Vector2i(4, 5))
	var way: Array = mm.path(Vector2i(4, 3), Vector2i(4, 7))
	assert_eq(way.size(), 6, "the wall makes the way two cells longer")
	assert_false(way.has(Vector2i(4, 5)), "the way avoids the wall")
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	var r: RPGResult = await _route([{"move_to": [4, 7]}])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.cell, Vector2i(4, 7), "the chest walked around the wall to the goal")
	assert_eq(mm.path(Vector2i(4, 3), Vector2i(99, 99)), [], "a goal off the map has no way")


func test_move_to_walks_to_an_events_cell_and_stops_beside_the_player() -> void:
	# The door starts at (12, 7), inside the shortest-way region to the player — move it out so the
	# player is the only character the way has to stop for.
	var r0: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "town_house_door", "position": [2, 12]},
	])
	assert_true(r0.is_ok(), str(r0))
	await _place_plate(Vector2i(6, 6))
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	var r: RPGResult = await _route([{"move_to": "floor_plate"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.cell, Vector2i(6, 6), "a below-priority event's cell can be entered")
	var r2: RPGResult = await _route([{"move_to": [4, 3]}, {"move_to": "player"}])
	assert_true(r2.is_ok(), str(r2))
	assert_ne(ev.cell, env.game.player.cell, "it does not step onto the player")
	assert_eq(absi(ev.cell.x - env.game.player.cell.x) + absi(ev.cell.y - env.game.player.cell.y), 1,
		"it arrives beside the player, as close as the way allows")


func test_move_to_gives_up_with_skip_when_the_way_is_held() -> void:
	var r0: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "town_house_door", "position": [4, 5]},
	])
	assert_true(r0.is_ok(), str(r0))
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	var r: RPGResult = await _route([{"move_to": [4, 7]}], {"skip_if_blocked": true})
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.cell, Vector2i(4, 4), "the door blocks the way and the skip rule gives up")


func test_call_step_runs_a_method_and_skips_a_missing_one() -> void:
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.facing = "down"
	var r: RPGResult = await _route([
		{"call": {"method": "turn", "args": ["left"]}},
		{"call": {"method": "no_such_method"}},
		{"turn": "right"},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.facing, "right", "the call step turned left, the missing method was skipped, the route went on")


# --- Forced move routes (#71) -------------------------------------------------------------------

func test_a_forced_route_takes_over_a_random_walk() -> void:
	# The issue's acceptance test: a random-walk NPC handed a 5-step route by another event
	# makes exactly those 5 steps.
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.move_type = "random"
	ev._move_wait = 0.5
	var start := ev.cell
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": true,
			"steps": [{"step": "down"}, {"step": "down"}, {"step": "down"}, {"step": "down"}, {"step": "down"}]},
	])
	assert_true(r.is_ok(), str(r))
	assert_false(ev.is_route_forced(), "the forced route is over")
	assert_eq(ev.cell, start + Vector2i(0, 5), "exactly the 5 forced steps; the random walk stayed paused")
	# When the route ends, autonomous movement resumes.
	var final_cell := ev.cell
	ev._move_wait = 0.0
	var resumed := await _await_step(ev)
	assert_true(resumed != final_cell, "the random walk resumes when the forced route ends")


func test_a_forced_route_pauses_approach_movement() -> void:
	# Approach steps toward the player on every beat, so any leak of autonomous movement during
	# the route would drift the cell and fail the exact-position checks.
	var ev: RPGEvent = await _place_chest(Vector2i(16, 8))
	ev.frequency = 5
	ev.move_type = "approach"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, Vector2i(15, 8), "approach steps toward the player first")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "down"}, {"step": "down"}, {"step": "down"}, {"step": "down"}, {"step": "down"}]},
	])
	assert_true(r.is_ok(), str(r))
	assert_true(ev.is_route_forced(), "the forced route is running")
	var at := ev.cell
	for i in 5:
		var c := await _await_step(ev)
		at += Vector2i.DOWN
		assert_eq(c, at, "forced step %d of 5 is exactly down" % (i + 1))
	await frames(3)
	assert_false(ev.is_route_forced(), "the forced route ended")
	assert_eq(ev.cell, Vector2i(15, 13), "exactly the forced steps; approach never fired between them")


func test_a_forced_route_keeps_the_custom_route_index() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.custom_route = {"steps": [{"step": "down"}, {"step": "down"}, {"step": "right"}, {"step": "right"}], "repeat": true}
	ev.move_type = "custom"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, Vector2i(4, 4), "custom step 1 (down)")
	var c2 := await _await_step(ev)
	assert_eq(c2, Vector2i(4, 5), "custom step 2 (down)")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": true,
			"steps": [{"step": "left"}, {"step": "left"}, {"step": "left"}]},
	])
	assert_true(r.is_ok(), str(r))
	# The pass resumes where it was (a right step); a restart would step down again.
	var before := ev.cell
	var c3 := await _await_step(ev)
	assert_eq(c3, before + Vector2i.RIGHT, "the custom route resumes at its index (right), not from the start (down)")


func test_page_change_keeps_a_forced_route_under_classic_rules() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.move_type = "random"
	ev._move_wait = 99.0
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "right"}, {"wait": 30.0}]},
	])
	assert_true(r.is_ok(), str(r))
	var after := await _await_step(ev)
	assert_eq(after, Vector2i(5, 3), "the forced step played")
	assert_true(ev.is_route_forced(), "the route is parked on its long wait")
	env.rpg.set_self_switch("town", "chest", "A", true)
	await frames(4)
	assert_eq(ev.page_index, 1, "the chest changed page")
	assert_true(ev.is_route_forced(), "classic rules keep a forced route across a page change")
	ev.cancel_forced_route("test done")
	await frames(2)


func test_page_change_cancels_a_forced_route_under_vx_ace_rules() -> void:
	env.rpg.data.project["rules"] = "vx_ace"
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.move_type = "random"
	ev._move_wait = 99.0
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "right"}, {"wait": 30.0}]},
	])
	assert_true(r.is_ok(), str(r))
	var after := await _await_step(ev)
	assert_eq(after, Vector2i(5, 3), "the forced step played")
	env.rpg.set_self_switch("town", "chest", "A", true)
	await frames(6)
	assert_eq(ev.page_index, 1, "the chest changed page")
	assert_false(ev.is_route_forced(), "VX Ace style rules cancel a forced route on a page change")
	assert_eq(ev.cell, Vector2i(5, 3), "the cancelled route's remaining steps never play")


func test_page_change_resets_a_custom_route_when_the_new_page_differs() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.custom_route = {"steps": [{"step": "down"}, {"wait": 2.0}, {"step": "right"}], "repeat": true}
	ev.move_type = "custom"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, Vector2i(4, 4), "custom step 1 (down); the pass waits mid-route")
	assert_true(ev._route_running, "the pass is in flight")
	env.rpg.set_self_switch("town", "chest", "A", true)
	await frames(4)
	assert_eq(ev.page_index, 1, "the page changed to one without this route")
	assert_false(ev._route_running, "the pass is cancelled, not left waiting out its timer")
	assert_true(ev._custom_token == null, "the cancelled pass cleaned up after itself")
	for i in 20:
		await frames(1)
	assert_eq(ev.cell, Vector2i(4, 4), "the rest of the old route never plays")


# --- Wait for All Movement / Halt All Movement (#59) ----------------------------------------------


func test_wait_for_movement_waits_for_every_forced_route() -> void:
	# Two routes started without waiting (an event and the player): the command returns only
	# after both finished. The player's mid-route wait makes "still running" deterministic.
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	var ev_start := ev.cell
	var p: RPGPlayer = env.game.player
	var p_start := p.cell
	var outcome: Array = []
	var run := func() -> void:
		outcome.append(await env.rpg.run_commands([
			{"type": "move_route", "target": "chest", "wait": false,
				"steps": [{"step": "down"}, {"step": "down"}, {"step": "down"}, {"step": "down"}]},
			{"type": "move_route", "target": "player", "wait": false,
				"steps": [{"step": "right"}, {"step": "right"}, {"wait": 1.0}, {"step": "right"}, {"step": "right"}]},
			{"type": "wait_for_movement"},
			{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
		]))
	run.call()
	await frames(4)
	assert_eq(env.rpg.get_variable("counter"), 0, "the wait has not returned while a route runs")
	assert_true(p.is_route_forced(), "the player's route is parked on its mid-route wait")
	var done: bool = await _wait_until(func(): return int(env.rpg.get_variable("counter")) >= 1)
	assert_true(done, "Wait for All Movement returned when the routes finished")
	var finished: bool = await _wait_until(func(): return outcome.size() > 0)
	assert_true(finished, "the command list finished")
	assert_true(outcome[0].is_ok(), str(outcome[0]))
	assert_eq(ev.cell, ev_start + Vector2i(0, 4), "the event's route played out")
	assert_eq(p.cell, p_start + Vector2i(4, 0), "the player's route played out")
	assert_false(ev.is_route_forced() or p.is_route_forced(), "no route is running any more")


func test_wait_for_movement_ignores_repeating_routes() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false, "repeat": true,
			"steps": [{"step": "down"}, {"step": "up"}]},
		{"type": "wait_for_movement"},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 1, "a repeating route does not block the wait")
	assert_true(ev.is_route_forced(), "the repeating route keeps looping")
	ev.cancel_forced_route("test done")
	await frames(2)


func test_wait_for_movement_returns_at_once_with_no_routes_running() -> void:
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "wait_for_movement"},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("counter"), 1, "nothing to wait for: returned at once")


func test_halt_movement_cancels_every_forced_route() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	var p: RPGPlayer = env.game.player
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "down"}, {"wait": 30.0}]},
		{"type": "move_route", "target": "player", "wait": false,
			"steps": [{"step": "up"}, {"wait": 30.0}]},
	])
	assert_true(r.is_ok(), str(r))
	await frames(4)
	assert_true(ev.is_route_forced() and p.is_route_forced(), "both routes are parked mid-route")
	var halted: RPGResult = await env.rpg.run_commands([{"type": "halt_movement"}])
	assert_true(halted.is_ok(), str(halted))
	assert_false(ev.is_route_forced(), "the event's route was halted")
	assert_false(p.is_route_forced(), "the player's route was halted")
	var ev_at := ev.cell
	var p_at := p.cell
	await frames(10)
	assert_eq(ev.cell, ev_at, "the halted event never moves again")
	assert_eq(p.cell, p_at, "the halted player never moves again")


func test_halt_movement_ends_an_event_waiting_on_its_route() -> void:
	# The halt comes from a parallel event: the main interpreter is the one parked in the waiting
	# Move Route, and the scheduler's queue would not start a second main list beside it.
	env.rpg.data.common_events["halter"] = {"trigger": "parallel", "switch": "clock_on",
		"commands": [{"type": "halt_movement"}]}
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	var outcome: Array = []
	var waiting := func() -> void:
		outcome.append(await env.rpg.run_commands([
			{"type": "move_route", "target": "chest", "wait": true,
				"steps": [{"step": "down"}, {"wait": 30.0}]},
		]))
	waiting.call()
	await frames(4)
	assert_true(ev.is_route_forced(), "the route is parked mid-route")
	env.rpg.set_switch("clock_on", true)
	var ended: bool = await _wait_until(func(): return outcome.size() > 0)
	assert_true(ended, "the waiting command list ended with the halt")
	assert_true(outcome[0].is_cancelled(), "the waiting Move Route was cancelled: %s" % str(outcome[0]))
	env.rpg.set_switch("clock_on", false)
	await frames(2)


func test_halt_movement_resumes_autonomous_movement() -> void:
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.move_type = "random"
	ev._move_wait = 0.0
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "down"}, {"wait": 30.0}]},
	])
	assert_true(r.is_ok(), str(r))
	await frames(4)
	assert_true(ev.is_route_forced(), "the forced route is parked mid-route")
	await env.rpg.run_commands([{"type": "halt_movement"}])
	var parked := ev.cell
	var stepped := await _await_step(ev)
	assert_ne(stepped, parked, "the random walk resumed after the halt")


func test_wait_for_movement_blocks_a_parallel_event_until_routes_finish() -> void:
	env.rpg.data.common_events["mover"] = {
		"trigger": "parallel", "switch": "clock_on",
		"commands": [
			{"type": "wait_for_movement"},
			{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
		],
	}
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "down"}, {"wait": 1.0}, {"step": "down"}]},
	])
	assert_true(r.is_ok(), str(r))
	env.rpg.set_switch("clock_on", true)
	await frames(6)
	assert_eq(env.rpg.get_variable("counter"), 0, "the parallel's pass is blocked in the wait")
	var done: bool = await _wait_until(func(): return int(env.rpg.get_variable("counter")) >= 1)
	assert_true(done, "the parallel carried on once the route finished")
	env.rpg.set_switch("clock_on", false)
	await frames(3)


func test_halt_movement_works_in_an_autorun_event() -> void:
	env.rpg.data.common_events["halter"] = {
		"trigger": "autorun", "switch": "clock_on",
		"commands": [
			{"type": "halt_movement"},
			{"type": "set_switch", "id": "clock_on", "value": "off"},
		],
	}
	var ev: RPGEvent = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "wait": false,
			"steps": [{"step": "down"}, {"wait": 30.0}]},
	])
	assert_true(r.is_ok(), str(r))
	await frames(4)
	assert_true(ev.is_route_forced(), "the forced route is parked mid-route")
	env.rpg.set_switch("clock_on", true)
	var halted: bool = await _wait_until(func(): return not ev.is_route_forced())
	assert_true(halted, "the autorun event halted the route")


func test_page_change_keeps_a_custom_route_index_when_the_route_is_the_same() -> void:
	var route := {"steps": [{"step": "down"}, {"wait": 0.4}, {"step": "right"}], "repeat": true}
	var ev: RPGEvent = env.game.map.get_event("chest")
	ev.data["pages"].append({
		"conditions": [{"kind": "self_switch", "id": "B"}],
		"graphic": null,
		"movement": {"type": "custom", "route": route, "speed": 3, "frequency": 5},
		"options": {},
		"priority": "same",
		"trigger": "action_button",
		"commands": [],
	})
	ev = await _place_chest(Vector2i(4, 3))
	ev.frequency = 5
	ev.custom_route = route
	ev.move_type = "custom"
	ev._move_wait = 0.0
	var c1 := await _await_step(ev)
	assert_eq(c1, Vector2i(4, 4), "custom step 1 (down); the pass waits mid-route")
	env.rpg.set_self_switch("town", "chest", "B", true)
	await frames(3)
	assert_eq(ev.page_index, 2, "the same-route page is now active")
	assert_true(ev._route_running, "the pass is still in flight (same route, index kept)")
	# The wait elapses and the pass continues at its index: right, not down (a restart).
	var c2 := await _await_step(ev)
	assert_eq(c2, Vector2i(5, 4), "the custom route continued from its index")


# --- Blocked route steps (#70) ------------------------------------------------------------------

## Teleports the door event somewhere (it makes a handy wall for staging).
func _place_door(at: Vector2i) -> void:
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "set_event_location", "event": "town_house_door", "position": [at.x, at.y]},
	])
	assert_true(r.is_ok(), str(r))


func test_a_blocked_route_step_waits_until_the_way_clears() -> void:
	# With 'Skip if cannot move' off, a blocked step is retried until it succeeds, however long
	# that takes — never dropped by a timeout (the warning threshold is shortened for the test).
	var ev := await _place_chest(Vector2i(11, 8))
	ev._blocked_warn_after = 0.5
	await _place_door(Vector2i(11, 9))
	env.rpg.run_commands([{"type": "move_route", "target": "chest", "steps": [{"step": "down"}], "wait": false}])
	await env.tree.create_timer(0.8).timeout
	assert_true(ev.is_route_forced(), "past the old timeout, the route is still waiting on the step")
	assert_eq(ev.cell, Vector2i(11, 8), "the blocked step has not moved the chest")
	assert_true(str(ev.debug_info()["movement_blocked"]).begins_with("waiting for blocked step at"),
		"the debug inspector shows where it waits")
	await _place_door(Vector2i(12, 7))
	await frames(90)
	assert_false(ev.is_route_forced(), "the route finished once the way cleared")
	assert_eq(ev.cell, Vector2i(11, 9), "the blocked step completed after the wait")


func test_a_blocked_route_step_with_skip_still_skips() -> void:
	await _place_door(Vector2i(11, 9))
	var ev := await _place_chest(Vector2i(11, 8))
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "move_route", "target": "chest", "steps": [{"step": "down"}, {"step": "down"}], "skip_if_blocked": true, "wait": true},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(ev.cell, Vector2i(11, 8), "both blocked steps were skipped, not waited on")


# --- Map suspended behind screens (#69) ----------------------------------------------------------

const QUICK_SCENE := "res://tests/fixtures/scenes/quick_scene.gd"


## Opens a contract scene that never finishes, in the background, until `hold` seconds pass.
func _hold_scene(hold: float, pause_map := true) -> void:
	env.rpg.run_commands([
		{"type": "run_scene", "scene": QUICK_SCENE, "args": {"never": true}, "timeout": hold, "pause_map": pause_map},
	])


func test_a_scene_pauses_parallels_and_wandering_npcs() -> void:
	# Battle opens through run_contract_scene, so this is the battle path too.
	env.rpg.set_switch("parallel_on", true)
	await env.tree.create_timer(0.2).timeout
	var ev := await _place_chest(Vector2i(4, 3))
	ev.move_type = "random"
	ev.frequency = 5
	ev._move_wait = 0.0
	await _await_step(ev)
	var parked := ev.cell
	_hold_scene(0.8)
	await env.tree.create_timer(0.2).timeout
	assert_true(env.rpg.scheduler.map_suspended(), "the map is suspended while the scene is open")
	var frozen: int = env.rpg.state.get_variable("ticks")
	await env.tree.create_timer(0.35).timeout
	assert_eq(env.rpg.state.get_variable("ticks"), frozen, "the parallel did not tick during the scene")
	assert_eq(ev.cell, parked, "the wandering NPC did not move during the scene")
	await env.tree.create_timer(0.5).timeout
	assert_false(env.rpg.scheduler.map_suspended(), "the map resumed when the scene closed")
	assert_true(env.rpg.state.get_variable("ticks") > frozen, "the parallel resumed")
	var c := await _await_step(ev)
	assert_true(c != parked, "the NPC resumed walking")


func test_the_menu_pauses_the_map() -> void:
	env.rpg.data.project["scenes"] = {"menu": "res://tests/fixtures/scenes/held_menu.gd"}
	env.rpg.set_switch("parallel_on", true)
	await env.tree.create_timer(0.2).timeout
	env.game.open_menu()
	await frames(3)
	assert_true(env.rpg.scheduler.map_suspended(), "the map is suspended while the menu is open")
	assert_true(env.rpg.scheduler.input_locked(), "input is locked")
	var frozen: int = env.rpg.state.get_variable("ticks")
	await env.tree.create_timer(0.3).timeout
	assert_eq(env.rpg.state.get_variable("ticks"), frozen, "the parallel did not tick behind the menu")
	var m: Node = env.rpg.ui.scene_stack[0]
	m.closed.emit()
	await frames(3)
	assert_false(env.rpg.scheduler.map_suspended(), "the map resumed when the menu closed")
	await env.tree.create_timer(0.2).timeout
	assert_true(env.rpg.state.get_variable("ticks") > frozen, "the parallel resumed")


func test_a_parallels_wait_does_not_advance_behind_a_scene() -> void:
	# counter: 1 while the 0.6 s wait runs, 2 after. The wait must not advance while the scene
	# holds the map, even though 0.6 s of real time passes behind it.
	env.rpg.data.common_events["probe"] = {"trigger": "parallel", "switch": "parallel_on", "commands": [
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 1},
		{"type": "wait", "seconds": 0.6},
		{"type": "set_variable", "id": "counter", "operation": "set", "value": 2},
		{"type": "set_switch", "id": "parallel_on", "value": "off"},
	]}
	env.rpg.set_switch("parallel_on", true)
	await env.tree.create_timer(0.15).timeout
	assert_eq(env.rpg.state.get_variable("counter"), 1, "the probe is mid-wait")
	_hold_scene(0.5)
	await env.tree.create_timer(0.75).timeout
	assert_false(env.rpg.scheduler.map_suspended(), "the scene closed")
	assert_eq(env.rpg.state.get_variable("counter"), 1, "the wait did not advance behind the scene")
	await env.tree.create_timer(0.7).timeout
	assert_eq(env.rpg.state.get_variable("counter"), 2, "the wait finished after the map resumed")


func test_an_overlay_scene_can_opt_out_of_the_pause() -> void:
	env.rpg.set_switch("parallel_on", true)
	await env.tree.create_timer(0.2).timeout
	_hold_scene(0.6, false)
	await env.tree.create_timer(0.2).timeout
	assert_true(env.rpg.ui.scene_open(), "the overlay scene is open")
	assert_false(env.rpg.scheduler.map_suspended(), "an overlay scene does not suspend the map")
	var during: int = env.rpg.state.get_variable("ticks")
	await env.tree.create_timer(0.3).timeout
	assert_true(env.rpg.state.get_variable("ticks") > during, "the parallel kept running under the overlay")


# --- Show Text message style (#62) ----------------------------------------------------------------

## Opens a message in the background (auto_advance off) and holds it open until the test calls
## box._finish_text().
func _hold_message(extra: Dictionary = {}) -> void:
	var p := {"type": "show_text", "text": "held"}
	p.merge(extra)
	env.rpg.run_commands([p])


func test_avoid_player_swaps_a_top_or_bottom_box_away_from_the_player() -> void:
	var box: Control = env.rpg.ui.message_box
	env.rpg.ui.auto_advance = false
	# The player starts low on the screen (row 8 of 15, y≈128 of 240): a top box stays put...
	_hold_message({"position": "top", "avoid_player": "on"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 0, "player low: a top box stays")
	box._finish_text()
	# ...and a bottom box flips to the top.
	_hold_message({"position": "bottom", "avoid_player": "on"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 0, "player low: a bottom box flips to the top")
	box._finish_text()
	# The player walks up (row 3, y≈48): now a top box flips down and a bottom box stays.
	env.game.player.place(Vector2i(12, 3))
	await frames(1)
	_hold_message({"position": "top", "avoid_player": "on"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 164, "player high: a top box flips to the bottom")
	box._finish_text()
	_hold_message({"position": "bottom", "avoid_player": "on"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 164, "player high: a bottom box stays")
	box._finish_text()
	# A middle box never moves, and without avoid_player nothing flips.
	_hold_message({"position": "middle", "avoid_player": "on"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 82, "a middle box stays in the middle")
	box._finish_text()
	_hold_message({"position": "top"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 0, "without avoid_player a top box stays while the player is high")
	box._finish_text()


func test_avoid_player_can_come_from_the_system_settings() -> void:
	var box: Control = env.rpg.ui.message_box
	env.rpg.ui.auto_advance = false
	env.game.player.place(Vector2i(12, 3))
	await frames(1)
	env.rpg.data.system["message_avoid_player"] = true
	_hold_message({"position": "top"})  # "keep" (the default) reads the System setting
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 164, "keep + System on: the top box flips to the bottom")
	box._finish_text()
	_hold_message({"position": "top", "avoid_player": "off"})
	await _wait_until(func(): return box.mode == "text")
	assert_eq(int(box.get("panel").position.y), 0, "a message's off wins over the System default")
	box._finish_text()


func test_a_message_pauses_parallels_and_wandering_npcs_by_default() -> void:
	# RM2000/2003 default: "Allow events to continue" off, so the map sleeps behind the pages.
	var box: Control = env.rpg.ui.message_box
	env.rpg.ui.auto_advance = false
	env.rpg.set_switch("parallel_on", true)
	await env.tree.create_timer(0.2).timeout
	var ev := await _place_chest(Vector2i(4, 3))
	ev.move_type = "vertical"
	ev.frequency = 5
	ev._move_wait = 0.0
	await _await_step(ev)
	_hold_message({})
	await _wait_until(func(): return box.mode == "text")
	assert_true(env.rpg.scheduler.map_suspended(), "the map is suspended while the message shows")
	var frozen: int = env.rpg.state.get_variable("ticks")
	await frames(3)  # an in-flight NPC step finishes before its cell is pinned
	var parked := ev.cell
	await env.tree.create_timer(0.3).timeout
	assert_eq(env.rpg.state.get_variable("ticks"), frozen, "the parallel slept during the message")
	assert_eq(ev.cell, parked, "the wandering NPC did not move during the message")
	box._finish_text()
	await env.tree.create_timer(0.3).timeout
	assert_false(env.rpg.scheduler.map_suspended(), "the map resumed when the message closed")
	assert_true(env.rpg.state.get_variable("ticks") > frozen, "the parallel resumed")
	var moved := await _await_step(ev)
	assert_true(moved != parked, "the NPC resumed walking")


func test_events_continue_keeps_everything_running_during_the_message() -> void:
	var box: Control = env.rpg.ui.message_box
	env.rpg.ui.auto_advance = false
	env.rpg.set_switch("parallel_on", true)
	await env.tree.create_timer(0.2).timeout
	var ev := await _place_chest(Vector2i(4, 3))
	ev.move_type = "vertical"
	ev.frequency = 5
	ev._move_wait = 0.0
	await _await_step(ev)
	_hold_message({"events_continue": "on"})
	await _wait_until(func(): return box.mode == "text")
	assert_false(env.rpg.scheduler.map_suspended(), "events_continue on: the map is not suspended")
	var during: int = env.rpg.state.get_variable("ticks")
	await env.tree.create_timer(0.2).timeout
	assert_true(env.rpg.state.get_variable("ticks") > during, "the parallel ticked during the message")
	var before := ev.cell
	var moved := await _await_step(ev)
	assert_true(moved != before, "the NPC kept walking during the message")
	box._finish_text()


func test_events_continue_can_come_from_the_system_settings() -> void:
	var box: Control = env.rpg.ui.message_box
	env.rpg.ui.auto_advance = false
	env.rpg.data.system["message_events_continue"] = true
	_hold_message({})
	await _wait_until(func(): return box.mode == "text")
	assert_false(env.rpg.scheduler.map_suspended(), "keep + System on: events continue")
	box._finish_text()
	_hold_message({"events_continue": "off"})
	await _wait_until(func(): return box.mode == "text")
	assert_true(env.rpg.scheduler.map_suspended(), "a message's off wins over the System default")
	box._finish_text()


func test_choices_do_not_hold_the_pause() -> void:
	# The pause covers only the text pages: choices never hold one, so the map runs while the
	# player picks (RM2000/2003 pauses for neither, MV/MZ for none of it).
	var box: Control = env.rpg.ui.message_box
	env.rpg.ui.auto_advance = false
	_hold_message({})
	await _wait_until(func(): return box.mode == "text")
	assert_true(env.rpg.scheduler.map_suspended(), "the text pages hold the pause")
	box._finish_text()
	box.open_choices(["yes", "no"])
	assert_false(env.rpg.scheduler.map_suspended(), "choices do not hold the pause")
	box.force_close()


# --- Parallel common events: switch off and map change (#78) -------------------------------------


func _wait_until(cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


## A "clock" parallel common event on its own switch (parallel_on would drag the fixture map's
## parallel_evt in too): ticks once per pass, waits, and counter marks passes that reached the end
## of the list. self_off ends the list by turning the switch off.
func _clock_event(wait_s: float, self_off: bool) -> Dictionary:
	var cmds: Array = [
		{"type": "set_variable", "id": "ticks", "operation": "add", "value": 1},
		{"type": "wait", "seconds": wait_s},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	]
	if self_off:
		cmds.append({"type": "set_switch", "id": "clock_on", "value": "off"})
	return {"trigger": "parallel", "switch": "clock_on", "commands": cmds}


func test_classic_rules_pause_a_parallel_common_event_and_resume_it() -> void:
	# The door project runs the classic rules, where a condition switch going off freezes the run
	# at its current command and a later switch-on carries on exactly there (RM2000/2003).
	env.rpg.data.common_events["clock"] = _clock_event(1.5, true)
	env.rpg.set_switch("clock_on", true)
	await env.tree.create_timer(0.4).timeout
	assert_eq(env.rpg.state.get_variable("ticks"), 1, "one pass started")
	assert_eq(env.rpg.state.get_variable("counter"), 0, "it is mid-wait")
	env.rpg.set_switch("clock_on", false)
	await env.tree.create_timer(0.6).timeout
	var task: RPGScheduler.ParallelTask = env.rpg.scheduler.parallels.get("common:clock")
	assert_true(task != null and task.paused, "the run is paused in place, not discarded")
	await env.tree.create_timer(1.2).timeout
	assert_eq(env.rpg.state.get_variable("counter"), 0, "the wait stays frozen while paused")
	env.rpg.set_switch("clock_on", true)
	var finished: bool = await _wait_until(func(): return int(env.rpg.state.get_variable("counter")) >= 1)
	assert_true(finished, "the pass carried on where it stopped")
	assert_eq(env.rpg.state.get_variable("ticks"), 1, "it did not restart from the top")


func test_mv_rules_discard_a_parallel_common_event_and_restart_it_from_the_top() -> void:
	env.rpg.rules.definition["parallel_switch_off"] = "restart"
	env.rpg.data.common_events["clock"] = _clock_event(1.5, false)
	env.rpg.set_switch("clock_on", true)
	await env.tree.create_timer(0.4).timeout
	assert_eq(env.rpg.state.get_variable("ticks"), 1, "one pass started")
	env.rpg.set_switch("clock_on", false)
	var gone: bool = await _wait_until(func(): return not env.rpg.scheduler.parallels.has("common:clock"))
	assert_true(gone, "the run was discarded, not paused (MV behaviour)")
	env.rpg.set_switch("clock_on", true)
	var again: bool = await _wait_until(func(): return int(env.rpg.state.get_variable("ticks")) >= 2)
	assert_true(again, "the event started again from the top")


func test_classic_rules_keep_a_parallel_common_event_running_across_a_map_change() -> void:
	env.rpg.data.common_events["clock"] = _clock_event(0.05, false)
	env.rpg.set_switch("clock_on", true)
	var ticking: bool = await _wait_until(func(): return int(env.rpg.state.get_variable("ticks")) >= 2)
	assert_true(ticking, "the clock is ticking")
	var task: Object = env.rpg.scheduler.parallels["common:clock"]
	var before: int = env.rpg.state.get_variable("ticks")
	var r: RPGResult = await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	assert_true(r.is_ok(), str(r))
	await env.settle()
	assert_true(env.rpg.scheduler.parallels.get("common:clock") == task, "the same task kept running across the transfer")
	var grew: bool = await _wait_until(func(): return int(env.rpg.state.get_variable("ticks")) > before)
	assert_true(grew, "it never stopped ticking")


func test_mv_rules_restart_a_parallel_common_event_on_a_map_change() -> void:
	env.rpg.rules.definition["parallel_map_change"] = "restart"
	# One pass stuck in a long wait: a second tick can only come from a fresh start.
	env.rpg.data.common_events["clock"] = _clock_event(30.0, false)
	env.rpg.set_switch("clock_on", true)
	var started: bool = await _wait_until(func(): return int(env.rpg.state.get_variable("ticks")) >= 1)
	assert_true(started, "the clock is ticking")
	var r: RPGResult = await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	assert_true(r.is_ok(), str(r))
	var restarted: bool = await _wait_until(func(): return int(env.rpg.state.get_variable("ticks")) >= 2)
	assert_true(restarted, "the common event restarted from the top on the new map")


## The fixture's parallel_evt page re-written into a transfer plus a trailing command, so the test
## can see whether the pass continues after the map it belongs to has unloaded.
func _porter_commands() -> Array:
	return [
		{"type": "transfer_player", "to": {"map": "house_inside", "position": [1, 1]}, "fade": "none"},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 1},
	]


func test_the_rm2000_option_lets_a_transferring_map_parallel_finish_its_pass() -> void:
	var ev: RPGEvent = env.game.map.get_event("parallel_evt")
	ev.data["pages"][0]["commands"] = _porter_commands()
	env.rpg.rules.definition["parallel_map_event_survives_map_change"] = true
	env.rpg.set_switch("parallel_on", true)
	var done: bool = await _wait_until(func(): return env.game.map != null and env.game.map.map_id == "house_inside" and int(env.rpg.state.get_variable("counter")) >= 1)
	assert_true(done, "the pass finished on the new map (counter=%d)" % env.rpg.state.get_variable("counter"))
	await env.tree.create_timer(0.3).timeout
	assert_false(env.rpg.scheduler.parallels.has("event:town:parallel_evt"), "the spared task stopped once its pass ended")


func test_without_the_option_a_transferring_map_parallel_stops_mid_pass() -> void:
	var ev: RPGEvent = env.game.map.get_event("parallel_evt")
	ev.data["pages"][0]["commands"] = _porter_commands()
	env.rpg.set_switch("parallel_on", true)
	var arrived: bool = await _wait_until(func(): return env.game.map != null and env.game.map.map_id == "house_inside" and not env.game.transferring)
	assert_true(arrived, "the transfer itself completed")
	await env.tree.create_timer(0.3).timeout
	assert_eq(env.rpg.state.get_variable("counter"), 0, "the pass did not continue after its map unloaded (MV behaviour)")
	assert_false(env.rpg.scheduler.parallels.has("event:town:parallel_evt"), "the task was cancelled with its map")


# --- Call Event (#60) ---------------------------------------------------------------------------

func test_call_event_runs_a_page_with_the_called_event_as_this() -> void:
	# The chest's page 1 adds 100 to counter and turns its own self switch A on. Called from the
	# API (no this event of its own), the page's self switch must still belong to the chest.
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "call_event", "target": "id", "id": "chest", "page": 1},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("counter"), 100, "the called page ran")
	assert_true(env.rpg.state.get_self_switch("town", "chest", "A"), "self switches in the page are the called event's")


func test_call_event_from_a_variable_and_missing_pages() -> void:
	env.rpg.state.set_variable("hero_name", "chest")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "call_event", "target": "variable", "variable": "hero_name", "page": 1},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("counter"), 100, "the event id came from the variable")
	# Page 2 exists (empty commands); page 3 does not, and unknown events are named.
	r = await env.rpg.run_commands([{"type": "call_event", "target": "id", "id": "chest", "page": 2}])
	assert_true(r.is_ok(), str(r))
	r = await env.rpg.run_commands([{"type": "call_event", "target": "id", "id": "chest", "page": 3}])
	assert_true(r.is_error(), str(r))
	r = await env.rpg.run_commands([{"type": "call_event", "target": "id", "id": "ghost"}])
	assert_true(r.is_error(), str(r))


func test_call_event_exit_ends_only_the_called_page() -> void:
	var chest: RPGEvent = env.game.map.get_event("chest")
	chest.data["pages"].append({
		"conditions": [], "graphic": null, "movement": {"type": "fixed"}, "options": {},
		"priority": "same", "trigger": "action_button",
		"commands": [
			{"type": "set_variable", "id": "counter", "operation": "add", "value": 3},
			{"type": "exit_event"},
			{"type": "set_variable", "id": "counter", "operation": "add", "value": 7},
		],
	})
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "call_event", "target": "id", "id": "chest", "page": 3},
		{"type": "set_variable", "id": "counter", "operation": "add", "value": 5},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("counter"), 8, "the page stopped at Exit Event, the caller continued")


func test_call_event_recursion_hits_the_depth_limit() -> void:
	var chest: RPGEvent = env.game.map.get_event("chest")
	chest.data["pages"].append({
		"conditions": [], "graphic": null, "movement": {"type": "fixed"}, "options": {},
		"priority": "same", "trigger": "action_button",
		"commands": [{"type": "call_event", "target": "this", "page": 3}],
	})
	var r: RPGResult = await env.rpg.run_commands([{"type": "call_event", "target": "id", "id": "chest", "page": 3}])
	assert_true(r.is_error(), str(r))
	assert_true(str(r).find("depth") != -1, "the error names the depth limit: %s" % r)


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


## A movement controller with a few counter cells added — counters live in tile data the test
## fixtures don't paint, so the counter path needs them injected for a test.
class CountersMovement extends RPGMovement:
	var counters: Array[Vector2i] = []

	func flags(cell: Vector2i) -> int:
		var f := super.flags(cell)
		if counters.has(cell):
			f |= FLAG_COUNTER
		return f
