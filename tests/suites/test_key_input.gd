extends "res://tests/rpg_test_case.gd"
## Key Input Processing (#14): the codes match RPG Maker 2003 (1-7 the pad keys, 10-19 digits,
## 20-24 operators, 30-33 the kit's actions, 100+ named extras), waiting fires when a key lands
## with the variable reading 0 until then, unaccepted keys never fire, without waiting a held
## key or 0 is stored, the time variable counts tenths of a second, and a parallel event can
## run the command while the map plays.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func after_each() -> void:
	for a in InputMap.get_actions():
		if str(a).begins_with("rpg_"):
			Input.action_release(a)
	if env != null:
		await env.destroy()
		env = null


## The sample town, walked to a stable stop, so map input is live like in a real game.
func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


## Presses an input action for one frame, like a player would.
func press(action: String) -> void:
	Input.action_press(action)
	await frames(1)
	Input.action_release(action)
	await frames(1)


## Runs the command in the background and returns the shared out dictionary it will fill.
func _start(cmd: Dictionary) -> Dictionary:
	var out := {}
	var run := func():
		out.r = await env.rpg.run_commands([cmd], {"kind": "api", "id": "t"})
	run.call()
	return out


func _ok(out: Dictionary, what: String) -> void:
	assert_true(out.has("r"), "%s: the command finished" % what)
	if out.has("r"):
		assert_true(out.r.is_ok(), "%s: %s" % [what, str(out.r)])


func test_wait_stores_the_code_of_the_pressed_key() -> void:
	await _sample_env()
	var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "ok": true})
	await frames(3)
	assert_false(out.has("r"), "nothing pressed: still waiting")
	assert_eq(env.rpg.get_variable("fish_caught"), 0, "the variable reads 0 during the wait")
	await press("rpg_ok")
	_ok(out, "confirm")
	assert_eq(env.rpg.get_variable("fish_caught"), 5, "confirm stores 5")


func test_two_keys_in_one_frame_report_the_rm2003_priority() -> void:
	await _sample_env()
	var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "ok": true, "up": true, "numbers": true})
	await frames(3)
	Input.action_press("rpg_num3")
	Input.action_press("rpg_ok")
	Input.action_press("rpg_up")
	await frames(1)
	Input.action_release("rpg_num3")
	Input.action_release("rpg_ok")
	Input.action_release("rpg_up")
	await frames(1)
	_ok(out, "three keys")
	assert_eq(env.rpg.get_variable("fish_caught"), 13, "the digit outranks confirm, which outranks up")


func test_unaccepted_keys_keep_the_wait_going() -> void:
	await _sample_env()
	var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "cancel": true})
	await press("rpg_ok")
	await press("rpg_up")
	assert_false(out.has("r"), "unaccepted keys do not end the wait")
	await press("rpg_cancel")
	_ok(out, "cancel")
	assert_eq(env.rpg.get_variable("fish_caught"), 6, "cancel stores 6")


func test_without_wait_reads_held_keys_and_zero() -> void:
	await _sample_env()
	Input.action_press("rpg_down")
	await frames(2)
	var a: RPGResult = await env.rpg.run_commands([
		{"type": "key_input", "variable": "fish_caught", "wait": false, "down": true},
	], {"kind": "api", "id": "t"})
	Input.action_release("rpg_down")
	assert_true(a.is_ok(), str(a))
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "a held down key reads 1 without waiting")
	var b: RPGResult = await env.rpg.run_commands([
		{"type": "key_input", "variable": "fish_caught", "wait": false, "ok": true},
	], {"kind": "api", "id": "t"})
	assert_true(b.is_ok(), str(b))
	assert_eq(env.rpg.get_variable("fish_caught"), 0, "nothing pressed reads 0")


func test_digits_and_operators_match_rm2003_codes() -> void:
	await _sample_env()
	for k in [["rpg_num7", 17], ["rpg_decimal", 24], ["rpg_add", 20]]:
		var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "numbers": true, "operators": true})
		await frames(2)
		await press(str(k[0]))
		_ok(out, str(k[0]))
		assert_eq(env.rpg.get_variable("fish_caught"), k[1], "%s stores %d" % [str(k[0]), int(k[1])])


func test_the_time_variable_counts_tenths_while_waiting() -> void:
	await _sample_env()
	var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "ok": true, "time_variable": "talks"})
	await frames(60)
	await press("rpg_ok")
	_ok(out, "timed")
	assert_eq(env.rpg.get_variable("fish_caught"), 5, "confirm stores 5")
	var t: int = env.rpg.get_variable("talks")
	assert_true(t >= 8 and t <= 12, "a second of waiting records about 10 tenths, got %d" % t)


func test_the_kit_actions_and_named_extras_have_their_own_codes() -> void:
	await _sample_env()
	var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "through": true})
	await frames(2)
	await press("rpg_through")
	_ok(out, "through")
	assert_eq(env.rpg.get_variable("fish_caught"), 32, "the through action stores 32")
	var out2 := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "actions": "rpg_through, rpg_overlay"})
	await frames(2)
	await press("rpg_overlay")
	_ok(out2, "second listed action")
	assert_eq(env.rpg.get_variable("fish_caught"), 101, "the second listed action stores 101")


func test_a_key_already_down_when_the_wait_began_needs_a_fresh_press() -> void:
	await _sample_env()
	Input.action_press("rpg_ok")
	await frames(2)
	var out := _start({"type": "key_input", "variable": "fish_caught", "wait": true, "ok": true})
	await frames(4)
	assert_false(out.has("r"), "a key held before the wait does not fire (2003's triggered)")
	Input.action_release("rpg_ok")
	await frames(1)
	await press("rpg_ok")
	_ok(out, "repressed")
	assert_eq(env.rpg.get_variable("fish_caught"), 5, "the fresh press stores 5")


func test_a_parallel_event_can_wait_for_a_key_while_the_map_plays() -> void:
	await _sample_env()
	env.rpg.data.common_events["listener"] = {"trigger": "parallel", "switch": "door_unlocked", "commands": [
		{"type": "key_input", "variable": "fish_caught", "wait": true, "ok": true, "cancel": true},
		{"type": "set_switch", "id": "door_unlocked", "value": "off"},
	]}
	env.rpg.set_switch("door_unlocked", true)
	await frames(4)
	await press("rpg_cancel")
	assert_true(await _wait_until(func(): return not env.rpg.get_switch("door_unlocked")), "the parallel finished and switched itself off")
	assert_eq(env.rpg.get_variable("fish_caught"), 6, "cancel stores 6 from a parallel event")


func _wait_until(cond: Callable, seconds := 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()
