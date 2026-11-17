extends "res://tests/rpg_test_case.gd"
## ui.close_all and the battle screen (issue #23): closing every screen must not strand a
## running Battle command. The battle is kept by default, can be ended with a forced outcome
## (escape), and a screen freed without finishing makes the command return an error instead of
## waiting forever. The last test drives the real battle scene.

const Env := preload("res://tests/rpg_test_env.gd")
const STUB := "res://tests/fixtures/scenes/battle_stub.gd"

var env


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


## Starts a Battle Processing command on the stub screen in the background; the screen stays up
## until the test ends it.
func _stub_battle(out: Dictionary) -> Node:
	var run := func():
		out.r = await env.rpg.run_commands([
			{"type": "battle", "troop": "slimes", "scene": STUB, "result": "battle_outcome",
				"on_escape": [{"type": "set_switch", "id": "door_unlocked", "value": "on"}]},
		], {"kind": "api", "id": "t"})
	run.call()
	for i in 600:
		var n := _battle_screen()
		if n != null:
			return n
		if out.has("r"):
			break
		await tree.process_frame
	return null


## The open screen tagged "battle", or null.
func _battle_screen() -> Node:
	for n in env.rpg.ui.scene_stack:
		if is_instance_valid(n) and str(n.get_meta("rpg_scene_id", "")) == "battle":
			return n
	return null


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func test_close_all_leaves_the_battle_running() -> void:
	await _sample_env()
	var out := {}
	var scene: Node = await _stub_battle(out)
	assert_true(scene != null, "the battle screen is up")
	env.rpg.ui.close_all()
	await frames(3)
	assert_true(is_instance_valid(scene) and not scene.is_queued_for_deletion(), "the battle stays open")
	assert_false(out.has("r"), "the Battle command is still waiting")
	assert_true(env.rpg.ui.scene_open(), "the screen is still registered")
	scene.win()
	assert_true(await _wait_until(func(): return out.has("r")), "the battle ends normally afterwards")
	assert_true(out.r.is_ok(), str(out.r))
	assert_eq(env.rpg.state.get_variable("battle_outcome"), "win")


func test_close_all_can_end_the_battle_with_escape() -> void:
	await _sample_env()
	var out := {}
	var scene: Node = await _stub_battle(out)
	assert_true(scene != null, "the battle screen is up")
	env.rpg.state.set_switch("door_unlocked", false)
	env.rpg.ui.close_all({"battle": "escape"})
	assert_true(await _wait_until(func(): return out.has("r")), "the forced outcome ends the battle")
	assert_true(out.r.is_ok(), str(out.r))
	assert_eq(env.rpg.state.get_variable("battle_outcome"), "escape")
	assert_true(env.rpg.state.get_switch("door_unlocked"), "the If escaped branch ran")


func test_a_freed_battle_screen_errors_the_command() -> void:
	await _sample_env()
	var out := {}
	var scene: Node = await _stub_battle(out)
	assert_true(scene != null, "the battle screen is up")
	scene.free()
	assert_true(await _wait_until(func(): return out.has("r")), "the command returns instead of hanging")
	assert_true(out.r.is_error(), "freeing the screen under the wait is an error")
	assert_true(str(out.r).contains("closed before it finished"), str(out.r))


func test_close_all_battle_close_frees_the_screen() -> void:
	await _sample_env()
	var out := {}
	var scene: Node = await _stub_battle(out)
	assert_true(scene != null, "the battle screen is up")
	env.rpg.ui.close_all({"battle": "close"})
	assert_true(await _wait_until(func(): return out.has("r")), "the command returns instead of hanging")
	assert_true(out.r.is_error(), "closing under the wait is an error")
	assert_true(str(out.r).contains("closed before it finished"), str(out.r))
	assert_false(is_instance_valid(scene), "the screen is gone")


func test_the_real_scene_ends_with_the_forced_outcome() -> void:
	await _sample_env()
	var out := {}
	var run := func():
		out.r = await env.rpg.run_commands([
			{"type": "battle", "troop": "slimes", "can_escape": false, "can_lose": true, "result": "battle_outcome"},
		], {"kind": "api", "id": "t"})
	run.call()
	env.rpg.ui.auto_advance = false
	var scene: Node = null
	for i in 600:
		if not env.rpg.ui.scene_stack.is_empty():
			scene = env.rpg.ui.scene_stack[-1]
			if scene.get("_started") == true:
				break
		if out.has("r"):
			break
		await tree.process_frame
	assert_true(scene != null and is_instance_valid(scene), "the battle screen is up")
	env.rpg.ui.close_all({"battle": "escape"})
	# The fight may be waiting at a window; drive it on so it reaches the forced outcome.
	scene.auto = true
	env.rpg.ui.auto_advance = true
	var end := Time.get_ticks_msec() + 30000
	while not out.has("r") and Time.get_ticks_msec() < end and is_instance_valid(scene):
		if scene.phase == "party":
			scene.cmd_list.select(0)
		scene.handle_action("ok")
		await tree.process_frame
	assert_true(out.has("r"), "the battle command returns")
	assert_true(out.r.is_ok(), str(out.r))
	assert_eq(env.rpg.state.get_variable("battle_outcome"), "escape", "the forced outcome, not a fought win")
