extends "res://tests/rpg_test_case.gd"
## RPG Maker's map Game Over check (#154): a Change HP with "Allow knockout", or a Change State,
## that leaves the whole party down on the map ends the game and stops the event. One member
## still standing, or Allow knockout left off, does not. The System's defeat handler takes the
## place of Game Over here as it does for a lost battle. (Inside a battle the battle's own defeat
## check decides: test_battle_events' defeat handler test fells the party from a troop page.)

const Env := preload("res://tests/rpg_test_env.gd")

var env


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


## The sample town with the hero alone. UI auto advance is off so the Game Over screen waits
## to be seen instead of closing itself at once.
func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())
	env.rpg.ui.auto_advance = false


func _wait_until(cond: Callable, seconds := 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func _game_over_shown() -> bool:
	for s in env.rpg.ui.scene_stack:
		if is_instance_valid(s) and s.get_script() != null and str(s.get_script().resource_path).ends_with("game_over.gd"):
			return true
	return false


func _hurt(target: String, amount: int, allow_knockout: bool) -> Dictionary:
	return {"type": "change_hp_mp", "target": target, "resource": "hp", "operation": "decrease", "amount": amount, "allow_knockout": allow_knockout}


func _mark() -> Dictionary:
	return {"type": "set_variable", "id": "talks", "operation": "set", "value": 7}


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


func test_change_hp_that_fells_the_whole_party_is_game_over() -> void:
	await _sample_env()
	assert_eq(env.rpg.state.party.size(), 1, "the sample starts with the hero alone")
	var r: RPGResult = await _run([_hurt("party", 9999, true), _mark()])
	assert_false(r.is_error(), str(r))
	assert_true(env.rpg.state.actor("hero").is_dead(), "the trap killed the hero")
	assert_true(await _wait_until(_game_over_shown), "the whole party down on the map is Game Over")
	assert_eq(int(env.rpg.get_variable("talks")), 0, "the event stops at the wipe, as after a lost battle")


func test_without_allow_knockout_the_party_survives() -> void:
	await _sample_env()
	var r: RPGResult = await _run([_hurt("party", 9999, false), _mark()])
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.state.actor("hero").resources.hp), 1, "left at 1 HP")
	assert_eq(int(env.rpg.get_variable("talks")), 7, "the event goes on")
	await frames(10)
	assert_false(_game_over_shown(), "nobody fell")


func test_one_member_standing_is_not_game_over() -> void:
	await _sample_env()
	var r: RPGResult = await _run([
		{"type": "change_party", "operation": "add", "actor": "mira"},
		_hurt("hero", 9999, true), _mark()])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.party.size(), 2)
	assert_true(env.rpg.state.actor("hero").is_dead())
	assert_true(env.rpg.state.actor("mira").is_alive())
	assert_eq(int(env.rpg.get_variable("talks")), 7, "the event goes on while someone stands")
	await frames(10)
	assert_false(_game_over_shown(), "Mira is still up")
	# The last one standing falls to a second trap: now it is Game Over.
	r = await _run([_hurt("mira", 9999, true), {"type": "set_variable", "id": "talks", "operation": "set", "value": 9}])
	assert_false(r.is_error(), str(r))
	assert_true(await _wait_until(_game_over_shown), "the last member falling ends the game")
	assert_eq(int(env.rpg.get_variable("talks")), 7, "and stops that event")


func test_change_state_knockout_on_the_whole_party_is_game_over() -> void:
	await _sample_env()
	var r: RPGResult = await _run([
		{"type": "change_state", "target": "party", "operation": "add", "state": "knockout"}, _mark()])
	assert_false(r.is_error(), str(r))
	assert_true(env.rpg.state.actor("hero").is_dead())
	assert_true(await _wait_until(_game_over_shown), "knocking the party out by state is a wipe too")
	assert_eq(int(env.rpg.get_variable("talks")), 0)


func test_other_states_and_removing_knockout_are_not_game_over() -> void:
	await _sample_env()
	var r: RPGResult = await _run([
		{"type": "change_state", "target": "party", "operation": "add", "state": "poison"}, _mark()])
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("talks")), 7)
	await frames(10)
	assert_false(_game_over_shown())


## The System's defeat handler (#39) takes the place of Game Over for a wipe on the map too: the
## optional transfer, then the common event, and the event that set the trap goes on.
func test_the_defeat_handler_takes_the_place_of_game_over() -> void:
	await _sample_env()
	var data: RPGProjectData = env.rpg.data
	data.common_events["rescue"] = {"id": "rescue", "name": "Rescue", "trigger": "none", "switch": "", "commands": [
		{"type": "recover_all", "target": "party"},
		{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": 3}]}
	data.system["defeat_event"] = "rescue"
	data.system["defeat_transfer"] = {"map": "house_inside", "position": [1, 1]}
	data.system["defeat_facing"] = "down"
	var r: RPGResult = await _run([_hurt("party", 9999, true), _mark()])
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("fish_caught")), 3, "the handler's common event ran")
	assert_true(env.rpg.state.actor("hero").is_alive(), "it healed the fallen party")
	assert_eq(int(env.rpg.get_variable("talks")), 7, "the event goes on after the handler")
	assert_true(await _wait_until(func(): return env.game.map != null and env.game.map.map_id == "house_inside" and not env.game.transferring), "the party was carried to the defeat map")
	assert_eq(env.game.player.cell, Vector2i(1, 1))
	assert_eq(env.game.player.facing, "down")
	assert_eq(int(env.rpg.state.game_data({"kind": "counter", "field": "defeats"})), 0, "a trap is not a lost battle")
	await frames(10)
	assert_false(_game_over_shown(), "no Game Over: the handler took its place")
