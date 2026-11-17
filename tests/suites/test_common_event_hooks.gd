extends "res://tests/rpg_test_case.gd"
## Common events on engine moments (#52): every trigger queues (or, for battle and game over,
## inline-runs) its matching common events, the filters narrow them to one map/actor/state/
## region/outcome/vehicle, the condition switch gates them, several moments queue in order
## without overwriting each other, and the moment's data is readable through game data "hook.*".

const Env := preload("res://tests/rpg_test_env.gd")

var env


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


## The sample town, walked to a stable stop. CEs are injected after this, so the start-of-game
## moments have already passed unless a test wants them.
func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


func _ce(id: String, extra: Dictionary = {}) -> void:
	var ce := {"id": id, "name": id.capitalize(), "trigger": "none", "switch": "", "commands": []}
	ce.merge(extra, true)
	env.rpg.data.common_events[id] = ce


func _bump(id: String, by := 1) -> Dictionary:
	return {"type": "set_variable", "id": id, "operation": "add", "value": by}


func _set_var(id: String, value: Variant) -> Dictionary:
	return {"type": "set_variable", "id": id, "operation": "set", "value": value}


func _wait_until(cond: Callable, seconds := 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


## Emits a step onto a cell with the given region and terrain (the player_stepped signal the
## real step emits; direct, so region numbers are exact whatever the sample map paints).
func _step(region: int, terrain: int, cell := Vector2i(20, 20)) -> void:
	env.rpg.player_stepped.emit(cell, region, terrain)


## The region/terrain the player currently stands in (hooks seed their trackers from it).
func _here() -> Vector2i:
	var m: RPGMap = env.game.map
	return Vector2i(m.region_at(env.game.player.cell), m.terrain_at(env.game.player.cell))


# --- maps ----------------------------------------------------------------------------------------------


func test_map_enter_and_leave_hooks_with_map_filter() -> void:
	await _sample_env()
	_ce("enter_any", {"trigger": "on_map_enter", "commands": [_bump("fish_caught")]})
	_ce("enter_field", {"trigger": "on_map_enter", "hook_map": "field", "commands": [_set_var("fishing_result", "field")]})
	_ce("leave_town", {"trigger": "on_map_leave", "hook_map": "town", "commands": [_set_var("battle_outcome", "left town")]})
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "transfer_player", "to": {"map": "field", "position": [10, 10]}, "fallback_distance": 8},
	], {"kind": "api", "id": "t"})
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "entering the field queues the enter hook")
	assert_eq(env.rpg.get_variable("fishing_result"), "field", "the map filter matches the field")
	assert_eq(env.rpg.get_variable("battle_outcome"), "left town", "leaving town queues the leave hook (the moment's map is the one left)")


func test_new_game_hook_runs_once_the_game_starts() -> void:
	env = Env.create(tree, "res://rpg")
	_ce("fresh", {"trigger": "on_new_game", "commands": [_bump("fish_caught")]})
	await env.game.new_game()
	assert_true(await env.settle())
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "starting a new game queues the hook")


func test_load_hook_runs_after_a_save_is_loaded() -> void:
	await _sample_env()
	_ce("loaded", {"trigger": "on_load", "commands": [_bump("fish_caught")]})
	var slot := 3
	var path: String = env.rpg.saves.slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	assert_true(env.rpg.saves.save(slot).is_ok(), "save")
	var lr: RPGResult = await env.rpg.saves.load_slot(slot)
	assert_true(lr.is_ok(), str(lr))
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "loading the save queues the hook")


# --- steps and tile moments ---------------------------------------------------------------------------


func test_step_hook_runs_every_n_steps() -> void:
	await _sample_env()
	_ce("paces", {"trigger": "on_step", "hook_every": 2, "commands": [_bump("fish_caught")]})
	var here := _here()
	_step(here.x, here.y)
	_step(here.x, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "the second step reaches every 2")
	await frames(2)
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "the first step only counted")
	_step(here.x, here.y)
	await frames(2)
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "the third step starts the next count, it does not fire")


func test_step_spam_queues_one_run_not_one_per_step() -> void:
	await _sample_env()
	_ce("once", {"trigger": "on_step", "commands": [_bump("fish_caught")]})
	var here := _here()
	_step(here.x, here.y)
	_step(here.x, here.y)
	_step(here.x, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1))
	await frames(2)
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "three steps in one frame queue one run")
	_step(here.x, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 2), "the next step queues the next run")


func test_hooked_events_queue_in_file_order() -> void:
	await _sample_env()
	_ce("first_ce", {"trigger": "on_step", "commands": [_set_var("fish_caught", 10)]})
	_ce("later_ce", {"trigger": "on_step", "commands": [_bump("fish_caught")]})
	var here := _here()
	_step(here.x, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 11))
	assert_eq(env.rpg.get_variable("fish_caught"), 11, "first_ce runs first, later_ce adds after it (11, not 10)")


func test_region_enter_and_leave_with_region_filter() -> void:
	await _sample_env()
	_ce("region_any", {"trigger": "on_region_enter", "commands": [_bump("fish_caught")]})
	_ce("region_five", {"trigger": "on_region_enter", "hook_region": 5, "commands": [_set_var("fishing_result", "five")]})
	_ce("region_left", {"trigger": "on_region_leave", "hook_region": 3, "commands": [_bump("talks")]})
	var here := _here()
	_step(3, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1))
	assert_eq(env.rpg.get_variable("fishing_result"), "", "region 5 did not match region 3")
	_step(0, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("talks") == 1), "leaving region 3 fires the leave hook")
	await frames(2)
	assert_eq(env.rpg.get_variable("fish_caught"), 1, "stepping out to no region fires no enter")


func test_terrain_enter_with_terrain_filter() -> void:
	await _sample_env()
	_ce("ground", {"trigger": "on_terrain_enter", "commands": [_bump("fish_caught")]})
	_ce("bog_only", {"trigger": "on_terrain_enter", "hook_terrain": 7, "commands": [_set_var("fishing_result", "bog")]})
	var here := _here()
	_step(here.x, 7)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1 and str(env.rpg.get_variable("fishing_result")) == "bog"), "both runs finish (file order)")
	_step(here.x, 9)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 2), "entering terrain 9 is also a terrain enter")
	assert_eq(env.rpg.get_variable("fishing_result"), "bog", "the terrain filter kept terrain 9 out of the bog event")


# --- actors and states ---------------------------------------------------------------------------------


func test_level_up_hook_with_actor_filter() -> void:
	await _sample_env()
	_ce("grew", {"trigger": "on_level_up", "commands": [_bump("fish_caught")]})
	_ce("mira_only", {"trigger": "on_level_up", "hook_actor": "mira", "commands": [_set_var("door_check", true)]})
	env.rpg.state.actor("hero").level += 1
	env.rpg.check_levels()
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1))
	assert_false(bool(env.rpg.get_variable("door_check")), "the hero's level-up is not Mira's")


func test_state_added_and_removed_with_state_filter() -> void:
	await _sample_env()
	_ce("poisoned", {"trigger": "on_state_added", "hook_state": "poison", "commands": [_bump("fish_caught")]})
	_ce("cured", {"trigger": "on_state_removed", "hook_state": "poison", "commands": [_bump("talks")]})
	_ce("slept", {"trigger": "on_state_added", "hook_state": "sleep", "commands": [_set_var("fishing_result", "zzz")]})
	var add: RPGResult = await env.rpg.run_commands([
		{"type": "change_state", "target": "party", "state": "poison", "operation": "add", "force": true},
	], {"kind": "api", "id": "t"})
	assert_true(add.is_ok(), str(add))
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "adding poison queues the state-added hook")
	assert_eq(env.rpg.get_variable("fishing_result"), "", "the sleep filter did not match poison")
	var rm: RPGResult = await env.rpg.run_commands([
		{"type": "change_state", "target": "party", "state": "poison", "operation": "remove"},
	], {"kind": "api", "id": "t"})
	assert_true(rm.is_ok(), str(rm))
	assert_true(await _wait_until(func(): return env.rpg.get_variable("talks") == 1), "removing poison queues the state-removed hook")


func test_actor_ko_hook_fires_when_the_hero_falls() -> void:
	await _sample_env()
	_ce("fell", {"trigger": "on_actor_ko", "commands": [_bump("fish_caught")]})
	_ce("death_state", {"trigger": "on_state_added", "hook_state": "knockout", "commands": [_bump("talks")]})
	# Mira stays up: the whole party down on the map would be Game Over (#154).
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "change_party", "operation": "add", "actor": "mira"},
		{"type": "change_hp_mp", "target": "hero", "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true},
	], {"kind": "api", "id": "t"})
	assert_true(r.is_ok(), str(r))
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "dropping the hero to 0 HP is its own moment")
	assert_true(await _wait_until(func(): return env.rpg.get_variable("talks") == 1), "the knockout state also counts as a state added")


# --- battle and game over ------------------------------------------------------------------------------


## A whole Battle Processing command (the hooks live in the command, so the scene is run through
## it, not started directly).
func _fight(troop: String, out: Dictionary) -> void:
	var run := func():
		out.r = await env.rpg.run_commands([
			{"type": "battle", "troop": troop, "can_escape": false, "can_lose": true, "auto": true},
		], {"kind": "api", "id": "t"})
	run.call()


func test_battle_start_and_end_hooks_with_outcome_filter() -> void:
	await _sample_env()
	_ce("to_arms", {"trigger": "on_battle_start", "commands": [_bump("fish_caught")]})
	_ce("after_any", {"trigger": "on_battle_end", "commands": [_set_var("battle_outcome", "any")]})
	_ce("after_win", {"trigger": "on_battle_end", "hook_outcome": "win", "commands": [_set_var("door_check", true)]})
	_ce("after_lose", {"trigger": "on_battle_end", "hook_outcome": "lose", "commands": [_bump("talks")]})
	var out := {}
	_fight("slimes", out)
	# The start hook runs inline, before the scene does anything.
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1, 15.0), "the battle-start moment runs before the fight")
	assert_true(await _wait_until(func(): return out.has("r"), 30.0), "the battle ends")
	assert_eq(env.rpg.get_variable("battle_outcome"), "any", "the battle-end moment ran after the fight")
	assert_true(env.rpg.get_variable("door_check"), "the outcome filter matched the win")
	assert_eq(env.rpg.get_variable("talks"), 0, "the defeat filter did not match a victory")


func test_game_over_hook_runs_before_the_screen() -> void:
	await _sample_env()
	_ce("last_words", {"trigger": "on_game_over", "commands": [_bump("fish_caught")]})
	env.game.game_over()
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "the game-over moment runs while the world is still up")


# --- menus, party, vehicles -----------------------------------------------------------------------------


func test_menu_open_and_close_hooks() -> void:
	await _sample_env()
	_ce("menu_up", {"trigger": "on_menu_open", "commands": [_bump("fish_caught")]})
	_ce("menu_down", {"trigger": "on_menu_close", "commands": [_bump("talks")]})
	env.game.open_menu()
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "opening the menu queues the hook")
	var menu: Node = env.rpg.ui.scene_stack[-1]
	menu.closed.emit()
	assert_true(await _wait_until(func(): return env.rpg.get_variable("talks") == 1), "closing it queues the close hook")


func test_party_change_hook() -> void:
	await _sample_env()
	_ce("reshuffle", {"trigger": "on_party_change", "commands": [_bump("fish_caught")]})
	assert_true(env.rpg.state.add_actor("mira"), "Mira joins")
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "the party growing queues the hook")


func test_vehicle_enter_and_exit_hooks_with_vehicle_filter() -> void:
	await _sample_env()
	_ce("aboard", {"trigger": "on_vehicle_enter", "commands": [_bump("fish_caught")]})
	_ce("aboard_ship", {"trigger": "on_vehicle_enter", "hook_vehicle": "ship", "commands": [_bump("talks")]})
	_ce("ashore", {"trigger": "on_vehicle_exit", "commands": [_set_var("door_check", true)]})
	env.rpg.vehicle_entered.emit("boat")
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1))
	assert_eq(env.rpg.get_variable("talks"), 0, "the boat is not the ship")
	env.rpg.vehicle_exited.emit("boat")
	assert_true(await _wait_until(func(): return env.rpg.get_variable("door_check")), "getting off queues the exit hook")


# --- data, triggers, switches ---------------------------------------------------------------------------


func test_hook_data_is_readable_as_game_data() -> void:
	await _sample_env()
	_ce("where", {"trigger": "on_region_enter", "commands": [
		_set_var("fish_caught", {"game_data": {"kind": "hook.region"}}),
		_set_var("fishing_result", {"game_data": {"kind": "hook.name"}}),
		_set_var("battle_outcome", {"game_data": {"kind": "hook.map"}}),
	]})
	_ce("foot", {"trigger": "on_step", "commands": [_set_var("talks", {"game_data": {"kind": "hook.x"}})]})
	_step(3, 0)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("talks") == 20 and str(env.rpg.get_variable("fishing_result")) == "on_region_enter"), "both the region and the step run finish")
	assert_eq(env.rpg.get_variable("fish_caught"), 3, "hook.region")
	assert_eq(env.rpg.get_variable("battle_outcome"), "town", "hook.map")


func test_a_trigger_array_fires_on_each_moment() -> void:
	await _sample_env()
	_ce("both", {"trigger": ["on_step", "on_region_enter"], "commands": [_bump("fish_caught")]})
	var here := _here()
	_step(3, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 2), "one step into a region is a step and a region enter")
	await frames(2)
	assert_eq(env.rpg.get_variable("fish_caught"), 2, "no double queue beyond the two moments")


func test_the_condition_switch_gates_a_hook() -> void:
	await _sample_env()
	_ce("gated", {"trigger": "on_step", "switch": "intro_done", "commands": [_bump("fish_caught")]})
	var here := _here()
	_step(here.x, here.y)
	await frames(3)
	assert_eq(env.rpg.get_variable("fish_caught"), 0, "the switch is off: no run")
	env.rpg.set_switch("intro_done", true)
	_step(here.x, here.y)
	assert_true(await _wait_until(func(): return env.rpg.get_variable("fish_caught") == 1), "the switch is on: the run queues")


func test_validator_checks_hook_triggers_and_filters() -> void:
	await _sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var good := {"id": "g", "name": "G", "trigger": ["on_step", "on_map_enter"], "hook_every": 2, "commands": []}
	var msgs := RPGValidator.structure("common_events", {"schema_version": 1, "common_events": [good]}, reg, "common_events.json").map(func(p): return str(p.message))
	assert_false(msgs.any(func(m): return m.contains("unknown trigger")), "an array of moments is fine: %s" % str(msgs))
	var bad_trigger := {"id": "b1", "name": "B", "trigger": ["on_step", "on_lunch"], "commands": []}
	var m1 := RPGValidator.structure("common_events", {"schema_version": 1, "common_events": [bad_trigger]}, reg, "common_events.json").map(func(p): return str(p.message))
	assert_true(m1.any(func(m): return m.contains("unknown trigger") and m.contains("on_lunch")), "an unknown moment is named: %s" % str(m1))
	var bad_every := {"id": "b2", "name": "B", "trigger": "on_step", "hook_every": 0, "commands": []}
	var m2 := RPGValidator.structure("common_events", {"schema_version": 1, "common_events": [bad_every]}, reg, "common_events.json").map(func(p): return str(p.message))
	assert_true(m2.any(func(m): return m.contains("every")), "every N steps has a floor of 1: %s" % str(m2))
	var bad_outcome := {"id": "b3", "name": "B", "trigger": "on_battle_end", "hook_outcome": "draw", "commands": []}
	var m3 := RPGValidator.structure("common_events", {"schema_version": 1, "common_events": [bad_outcome]}, reg, "common_events.json").map(func(p): return str(p.message))
	assert_true(m3.any(func(m): return m.contains("outcome")), "an unknown outcome is rejected: %s" % str(m3))
	var bad_vehicle := {"id": "b4", "name": "B", "trigger": "on_vehicle_enter", "hook_vehicle": "submarine", "commands": []}
	var m4 := RPGValidator.structure("common_events", {"schema_version": 1, "common_events": [bad_vehicle]}, reg, "common_events.json").map(func(p): return str(p.message))
	assert_true(m4.any(func(m): return m.contains("vehicle")), "an unknown vehicle is rejected: %s" % str(m4))
