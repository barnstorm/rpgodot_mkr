extends "res://tests/rpg_test_case.gd"
## Timers: the Control Timer command (issue #13), the countdown in the game state, the timer
## condition, what a timer does in a battle (pause / count / abort), the on-screen readout and
## the save round-trip. RPG Maker 2003 has two timers; a timer set to abort ends the battle.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _sample() -> void:
	env = Env.create(tree)
	env.rpg.state.new_game()
	await env.start_on("town", Vector2i(14, 12))


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


# --- the countdown itself ---------------------------------------------------------------------

func test_set_start_stop_and_the_countdown() -> void:
	var s := RPGGameState.new()
	s.new_game()
	assert_false(bool(s.timer("1").running), "a fresh timer is stopped")
	assert_eq(s.timer_seconds("1"), 0, "a fresh timer has no time")
	s.set_timer("1", 10.0)
	assert_eq(s.timer_seconds("1"), 10, "Set stores the time")
	assert_false(bool(s.timer("1").running), "Set alone does not start it")
	s.start_timer("1")
	assert_true(bool(s.timer("1").running))
	assert_eq(s.tick_timers(0.6), [], "no timer runs out yet")
	assert_eq(s.timer_seconds("1"), 10, "0.6 s off 10 s still leaves 10 whole seconds")
	s.tick_timers(0.6)
	assert_eq(s.timer_seconds("1"), 9, "1.2 s counts down to 9")
	s.stop_timer("1")
	assert_eq(s.tick_timers(5.0), [], "a stopped timer holds")
	assert_eq(s.timer_seconds("1"), 9, "the time is kept while stopped")
	s.start_timer("1")
	assert_eq(s.tick_timers(9.0), ["1"], "the timer that reaches 0 is reported and stops")
	assert_eq(s.timer_seconds("1"), 0)
	assert_false(bool(s.timer("1").running), "a timer that ran out is stopped")
	assert_eq(s.tick_timers(3.0), [], "a timer at 0 does not go negative")
	s.start_timer("1")
	assert_false(bool(s.timer("1").running), "a timer at 0 cannot start")


func test_two_timers_and_their_defaults() -> void:
	var s := RPGGameState.new()
	s.new_game()
	assert_eq(s.timer("1").position, "top_right", "timer 1 keeps the 2003 corner")
	assert_eq(s.timer("2").position, "top_left", "timer 2 keeps the 2003 corner")
	assert_false(bool(s.timer("1").visible), "a timer nobody has set is not on screen")
	s.set_timer("2", 5, false, "bottom_left", "count")
	assert_false(bool(s.timer("2").visible))
	assert_eq(s.timer("2").battle, "count")
	s.set_timer("2", 5, false, "middle", "explode")
	assert_eq(s.timer("2").position, "top_right", "an unknown position falls back")
	assert_eq(s.timer("2").battle, "pause", "an unknown battle mode falls back")
	assert_eq(s.timer(2).seconds, 5.0, "an int timer id reads as a string")


func test_battle_modes_pause_count_abort() -> void:
	var s := RPGGameState.new()
	s.new_game()
	s.set_timer("1", 10, false, "top_right", "pause")
	s.set_timer("2", 10, false, "top_left", "count")
	s.start_timer("1")
	s.start_timer("2")
	s.tick_timers(2.0, true)
	assert_eq(s.timer_seconds("1"), 10, "a pause timer holds in battle")
	assert_eq(s.timer_seconds("2"), 8, "a count timer ticks in battle")
	s.tick_timers(2.0, false)
	assert_eq(s.timer_seconds("1"), 8, "on the map every timer ticks")
	var s2 := RPGGameState.new()
	s2.new_game()
	s2.set_timer("1", 3, false, "top_right", "abort")
	s2.start_timer("1")
	assert_eq(s2.tick_timers(3.0, true), ["1"], "an abort timer ticks in battle")


# --- the condition ------------------------------------------------------------------------

func test_the_timer_condition() -> void:
	var s := RPGGameState.new()
	s.new_game()
	s.set_timer("1", 30)
	s.start_timer("1")
	assert_true(s.check_condition({"kind": "timer", "timer": "1", "op": "<=", "seconds": 30}))
	assert_false(s.check_condition({"kind": "timer", "timer": "1", "op": "<", "seconds": 30}))
	assert_true(s.check_condition({"kind": "timer", "timer": "1", "op": ">=", "seconds": 30}))
	assert_true(s.check_condition({"kind": "timer", "timer": "2", "op": "<=", "seconds": 5}), "timer 2 is at 0")
	s.tick_timers(5.0)
	assert_true(s.check_condition({"kind": "timer", "timer": "1", "op": "<=", "seconds": 25}))
	assert_false(s.check_condition({"kind": "timer", "timer": "1", "op": ">=", "seconds": 26}))


# --- the command and the save ------------------------------------------------------------------

func test_the_command_sets_starts_and_stops() -> void:
	await _sample()
	var r := await _run([
		{"type": "control_timer", "timer": "1", "operation": "set", "seconds": 90, "visible": false, "position": "bottom_right", "battle": "abort"},
		{"type": "control_timer", "timer": "1", "operation": "start"},
	])
	assert_true(r.is_ok(), str(r))
	var t: Dictionary = env.rpg.state.timer("1")
	assert_eq(t.seconds, 90.0)
	assert_true(bool(t.running))
	assert_false(bool(t.visible))
	assert_eq(t.position, "bottom_right")
	assert_eq(t.battle, "abort")
	assert_ne(env.rpg.registry.summary({"type": "control_timer", "timer": "2", "operation": "set", "seconds": 60}), "", "the command has a summary")
	await _run([{"type": "control_timer", "timer": "1", "operation": "stop"}])
	assert_false(bool(env.rpg.state.timer("1").running))
	# The time can come from a variable, like every operand.
	env.rpg.state.set_variable("counter", 12)
	var r2 := await _run([{"type": "control_timer", "operation": "set", "seconds": {"variable": "counter"}}])
	assert_true(r2.is_ok(), str(r2))
	assert_eq(env.rpg.state.timer_seconds("1"), 12)


func test_timers_survive_a_save_and_new_game_clears() -> void:
	await _sample()
	await _run([
		{"type": "control_timer", "timer": "2", "operation": "set", "seconds": 45, "visible": true, "position": "top_left", "battle": "count"},
		{"type": "control_timer", "timer": "2", "operation": "start"},
	])
	var save: Dictionary = env.rpg.saves.build_save()
	env.rpg.state.new_game()
	assert_eq(env.rpg.state.timer_seconds("2"), 0, "a new game clears the timers")
	assert_false(bool(env.rpg.state.timer("2").running))
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	var t: Dictionary = env.rpg.state.timer("2")
	assert_eq(t.seconds, 45.0, "the time survives the load")
	assert_true(bool(t.running), "so does whether it is running")
	assert_eq(t.battle, "count")
	# A save from before timers existed loads both at their defaults.
	env.rpg.state.from_dict({})
	assert_eq(env.rpg.state.timer("1").position, "top_right", "timer 1's default corner")
	assert_false(bool(env.rpg.state.timer("1").running))


# --- the readout and the battle abort -------------------------------------------------------

func test_the_map_readout_appears_and_disappears() -> void:
	await _sample()
	await env.start_on("town", Vector2i(14, 12))
	await _run([{"type": "control_timer", "operation": "set", "seconds": 30}])
	await env.settle()
	var d: Node = env.rpg.ui.root.get_node_or_null("TimerDisplay")
	assert_ne(d, null, "a visible timer puts the readout on screen")
	assert_eq(RPGTimerDisplay.format_seconds(0), "0:00")
	assert_eq(RPGTimerDisplay.format_seconds(61), "1:01")
	assert_eq(RPGTimerDisplay.format_seconds(5999), "99:59")
	assert_eq(RPGTimerDisplay.format_seconds(6000), "99:59", "capped like the classic display")
	await _run([{"type": "control_timer", "operation": "set", "seconds": 30, "visible": false}])
	var gone := false
	for i in 10:
		var n: Node = env.rpg.ui.root.get_node_or_null("TimerDisplay")
		if n == null or not is_instance_valid(n):
			gone = true
			break
		await tree.process_frame
	assert_true(gone, "a hidden timer takes the readout away")


func test_an_abort_timer_ends_the_battle_as_an_escape() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var out := {}
	var starter := func():
		out.r = await env.rpg.ui.run_contract_scene(env.rpg.ui.scene_path("battle"),
			{"troop": "slimes", "can_escape": true, "can_lose": true, "auto": true},
			{"rpg": env.rpg, "state": env.rpg.state, "rules": env.rpg.rules, "interpreter": null},
			RPGCancelToken.new(), 60.0)
	starter.call()
	# Wait for the battle to be live, then arm a very short abort timer.
	for i in 300:
		if env.rpg.battle != null and env.rpg.battle.valid():
			break
		await tree.process_frame
	assert_true(env.rpg.battle != null and env.rpg.battle.valid(), "the battle started")
	var before: int = env.rpg.state.gold
	env.rpg.state.set_timer("1", 0.05, false, "top_right", "abort")
	env.rpg.state.start_timer("1")
	for i in 600:
		if out.has("r"):
			break
		await tree.process_frame
	assert_true(out.has("r"), "the battle ended: %s" % str(out.get("r", {})))
	assert_eq(out.r.get("value", {}).get("outcome", ""), "escape", "the timer ran out and aborted the battle")
	assert_eq(env.rpg.state.gold, before, "an aborted battle hands out no gold")
