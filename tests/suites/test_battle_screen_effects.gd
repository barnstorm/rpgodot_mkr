extends "res://tests/rpg_test_case.gd"
## Tint, Flash and Shake Screen inside a battle (issue #7): the three commands act on the
## battle's own field (background and battlers, never the windows), wait for completion there,
## start from a clean state that ends with the fight, and leave the map's screen untouched.

const Env := preload("res://tests/rpg_test_env.gd")

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


## Starts a Battle Processing command in the background. Input is frozen once the scene is up
## (auto_advance off), so the fight waits at its first window until the test drives it on.
func _battle_open(troop: String, out: Dictionary) -> Node:
	var run := func():
		out.r = await env.rpg.run_commands([
			{"type": "battle", "troop": troop, "can_escape": false, "can_lose": true},
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
	return scene


## Drives the open battle to its end: auto mode for the fighting, "ok" for whatever window the
## fight happens to be frozen on (the party command never self-confirms, auto or not).
func _battle_end(scene: Node, out: Dictionary) -> void:
	scene.auto = true
	env.rpg.ui.auto_advance = true
	var end := Time.get_ticks_msec() + 30000
	while not out.has("r") and Time.get_ticks_msec() < end and is_instance_valid(scene):
		if scene.phase != "":
			if scene.phase == "party":
				scene.cmd_list.select(0)
			scene.handle_action("ok")
		await tree.process_frame


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func test_effects_act_on_the_battle_stage_not_the_map() -> void:
	await _sample_env()
	var out := {}
	var scene: Node = await _battle_open("slimes", out)
	assert_true(scene != null and is_instance_valid(scene), "the battle screen is up")
	assert_eq(env.rpg.screen.battle_stage, scene.stage, "the battle registered its stage")
	# Tint: the field darkens, the windows do not, the map's tint node is untouched.
	var tint_done: Signal = env.rpg.screen.tint_screen(Color(0.3, 0.3, 0.3, 1.0), 0.25)
	await tint_done
	assert_true(scene.stage.self_modulate.r < 0.9 and scene.stage.self_modulate.g < 0.9, "the stage is dark")
	assert_eq(scene.cmd_win.self_modulate, Color.WHITE, "the command window keeps its colour")
	assert_eq(scene.status_win.self_modulate, Color.WHITE, "so does the status window")
	assert_eq(env.rpg.screen.tint.color, Color.WHITE, "the map's tint stays white below the battle")
	# Flash: the battle's own overlay lights up and fades; the map's flash never fires.
	var flash_done: Signal = env.rpg.screen.flash(Color8(255, 255, 255, 200), 0.4)
	await frames(2)
	assert_true(scene.flash_rect.color.a > 0.05, "the flash is over the field")
	await flash_done
	assert_eq(scene.flash_rect.color.a, 0.0, "and fades out")
	assert_eq(env.rpg.screen.flash_rect.color.a, 0.0, "the map's flash rect stayed dark")
	# Shake: the stage itself moves, not the map's camera.
	var shake_done: Signal = env.rpg.screen.shake(6.0, 0.4)
	var moved := false
	for i in 8:
		await frames(1)
		moved = moved or scene.stage.position != Vector2.ZERO
	assert_true(moved, "the field shakes")
	await shake_done
	await frames(2)
	assert_eq(scene.stage.position, Vector2.ZERO, "and settles back")
	await _battle_end(scene, out)
	assert_true(out.has("r"), "the battle ends")
	assert_eq(env.rpg.screen.battle_stage, null, "the battle's screen state is gone with it")


func test_battle_starts_clean_and_the_map_tint_survives_it() -> void:
	await _sample_env()
	await env.rpg.screen.tint_screen(Color(0.25, 0.25, 0.35, 1.0), 0.0)
	var out := {}
	var scene: Node = await _battle_open("slimes", out)
	assert_eq(scene.stage.self_modulate, Color.WHITE, "a map tint does not leak into the battle")
	assert_eq(env.rpg.screen.tint.color, Color(0.25, 0.25, 0.35, 1.0), "the map's tint waits untouched")
	await _battle_end(scene, out)
	assert_true(await _wait_until(func(): return out.has("r")), "the battle ends")
	assert_eq(env.rpg.screen.tint.color, Color(0.25, 0.25, 0.35, 1.0), "and is still there after it")


## The full command path, in side view (the other tests' default battles are front view): a
## troop page on turn 1 runs the three commands with waits, and they all return before the
## page goes on.
func test_troop_page_commands_wait_in_battle() -> void:
	await _sample_env()
	var data: RPGProjectData = env.rpg.data
	var storm := {"id": "storm", "name": "Storm", "can_escape": true, "battle_view": "side", "members": [
		{"enemy": "slime", "hidden": false, "position": [120, 150]}], "pages": [
		{"id": "p", "conditions": [{"kind": "turn", "n": 0}], "commands": [
			{"type": "tint_screen", "red": 40, "green": 40, "blue": 60, "seconds": 0.5, "wait": true},
			{"type": "flash_screen", "color": [255, 255, 255, 180], "seconds": 0.4, "wait": true},
			{"type": "shake_screen", "power": 6, "seconds": 0.4, "wait": true},
			{"type": "set_variable", "id": "fish_caught", "operation": "add", "value": 1},
		]}]}
	data.db["troops"].by_id[storm.id] = storm
	data.db["troops"].records.append(storm)
	var out := {}
	var scene: Node = await _battle_open("storm", out)
	assert_true(scene != null and is_instance_valid(scene), "the battle screen is up")
	# The page runs as the battle opens (Turn 0), so let the opening log play out.
	env.rpg.ui.auto_advance = true
	assert_true(await _wait_until(func(): return not is_instance_valid(scene) or scene.stage.self_modulate != Color.WHITE, 15.0),
		"the page's Tint Screen darkened the field")
	await _battle_end(scene, out)
	assert_true(await _wait_until(func(): return out.has("r")), "the battle ends")
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "the page ran past all three waits")
	assert_eq(env.rpg.screen.battle_stage, null, "the battle's screen state was cleared")


func test_map_shake_returns_after_the_battle() -> void:
	await _sample_env()
	var out := {}
	var scene: Node = await _battle_open("slimes", out)
	assert_true(env.rpg.screen.battle_stage != null, "battle mode")
	await _battle_end(scene, out)
	assert_true(await _wait_until(func(): return env.rpg.screen.battle_stage == null), "map mode again")
	var cam: Camera2D = env.rpg.get_viewport().get_camera_2d()
	var before := cam.offset
	var done: Signal = env.rpg.screen.shake(5.0, 0.3)
	var moved := false
	for i in 8:
		await frames(1)
		moved = moved or cam.offset != before
	await done
	assert_true(moved, "a shake after the battle moves the map's camera again")
	cam.offset = Vector2.ZERO
