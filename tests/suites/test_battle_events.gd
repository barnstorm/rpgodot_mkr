extends "res://tests/rpg_test_case.gd"
## Battle events through the public battle API: the rpg.battle facade (#29), End Battle (#4),
## enemy targets of Change HP/SP, Change State and Recover All (#2), Change Party Member
## during a battle (#5), and Force Flee (#40).

const Env := preload("res://tests/rpg_test_env.gd")

var env


func after_each() -> void:
	Engine.time_scale = 1.0
	if env != null:
		await env.destroy()
		env = null


func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	env.rpg.ui.auto_advance = false


func _later_troop(pages: Array = []) -> Dictionary:
	return {"id": "later", "name": "Later", "can_escape": true, "members": [
		{"enemy": "slime", "hidden": false, "position": [120, 150]},
		{"enemy": "slime", "hidden": true, "position": [200, 150]}], "pages": pages}


## Both enemies visible: for tests that end the fight with "Entire troop".
func _twin_troop(pages: Array = []) -> Dictionary:
	return {"id": "twins", "name": "Twins", "can_escape": true, "members": [
		{"enemy": "slime", "hidden": false, "position": [120, 150]},
		{"enemy": "slime", "hidden": false, "position": [200, 150]}], "pages": pages}


func _add_troop(t: Dictionary) -> void:
	var data: RPGProjectData = env.rpg.data
	data.db["troops"].by_id[t.id] = t
	data.db["troops"].records.append(t)


func _run_battle(battle_args: Dictionary) -> Dictionary:
	var rpg: Node = env.rpg
	return await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), battle_args, {"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)


func _start_battle(battle_args: Dictionary, out: Dictionary) -> Node:
	var run := func():
		out.r = await _run_battle(battle_args)
	run.call()
	return env.rpg.ui.scene_stack[-1]


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


## Whether the game over screen is open right now.
func _game_over_shown() -> bool:
	for s in env.rpg.ui.scene_stack:
		if is_instance_valid(s) and s.get_script() != null and str(s.get_script().resource_path).ends_with("game_over.gd"):
			return true
	return false


## Turn-based: the Fight / Escape command is open.
func _open_party_command(scene: Node) -> void:
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "party"), "the party command opens")


## Timed battles: the first full actor's command window is open.
func _open_actor_command(scene: Node) -> void:
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.input_actor != null and scene.phase == "actor"), "an actor command window opens")


## After commands changed the battle: let the scene run itself out (auto confirms open menus).
func _finish(scene: Node, out: Dictionary) -> void:
	scene.auto = true
	env.rpg.ui.auto_advance = true
	var end := Time.get_ticks_msec() + 20000
	while not out.has("r") and Time.get_ticks_msec() < end:
		if is_instance_valid(scene) and scene.phase != "":
			if scene.phase == "party":
				scene.cmd_list.select(0)
			scene.handle_action("ok")
		await tree.process_frame
	assert_eq(out.get("r", {}).get("status", ""), "finished", "the battle ends")


# --- the battle facade (#29) ------------------------------------------------------------------------


func test_battle_facade_is_valid_while_the_fight_runs() -> void:
	_sample_env()
	env.rpg.ui.auto_advance = true
	_add_troop(_later_troop())
	assert_true(env.rpg.battle == null, "no battle, no facade")
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true, "auto": true}, out)
	var facade: RPGBattleFacade = env.rpg.battle
	assert_true(facade != null and facade.valid(), "the facade is there while the battle runs")
	assert_eq(facade.scene(), scene)
	assert_eq(facade.core(), scene.core)
	assert_eq(facade.party().size(), 1)
	assert_eq(facade.enemies().size(), 2)
	var node: Node2D = facade.node_of(scene.core.enemies[0])
	assert_true(node is Node2D, "node_of finds the enemy's node")
	assert_true(await _wait_until(func(): return out.has("r"), 20.0), "the battle ends")
	assert_true(env.rpg.battle == null, "and goes away with it")


func test_facade_add_enemy_and_set_gauge() -> void:
	_sample_env()
	Engine.time_scale = 4.0
	_add_troop(_later_troop())
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true, "battle_system": "atb"}, out)
	await _open_actor_command(scene)
	var facade: RPGBattleFacade = env.rpg.battle
	var slime: RPGBattler = facade.add_enemy("slime", Vector2(90, 150))
	assert_true(slime is RPGBattler, "a reinforcement was built")
	assert_eq(scene.core.enemies.size(), 3)
	assert_false(slime.hidden)
	assert_eq(scene.core.active_enemies().size(), 2, "the hidden member and the reinforcement are on the field")
	var hero: RPGBattler = scene.core.party[0]
	facade.set_gauge(hero, 0.0)
	assert_eq(scene.core.gauge(hero), 0.0)
	facade.set_gauge(hero, 1.0)
	assert_eq(scene.core.gauge(hero), 1.0, "a full actor waits for its command")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "escape")


# --- End Battle (#4) --------------------------------------------------------------------------------


func test_abort_battle_from_a_troop_page() -> void:
	for what in [
		{"result": "abort", "outcome": "escape"},
		{"result": "win", "outcome": "win"},
		{"result": "lose", "outcome": "lose"},
	]:
		_sample_env()
		env.rpg.ui.auto_advance = true
		var page := {"id": "stop", "conditions": [{"kind": "turn", "n": 1}], "span": "once_per_battle",
			"commands": [{"type": "abort_battle", "result": what.result}]}
		_add_troop(_later_troop([page]))
		var out := {}
		_start_battle({"troop": "later", "can_escape": false, "can_lose": true, "auto": true}, out)
		assert_true(await _wait_until(func(): return out.has("r"), 20.0), "%s: the battle ends" % what.result)
		assert_eq(out.r.value.outcome, what.outcome, "%s: the result matches" % what.result)
		if what.outcome == "win":
			assert_eq(int(out.r.value.rewards.get("exp", 0)), 0, "the page ran before anyone fell: no EXP yet")


func test_abort_battle_win_can_withhold_rewards() -> void:
	_sample_env()
	_add_troop(_later_troop())
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	# A scripted victory: both enemies fall to battle events, then the win is taken without rewards.
	await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1, "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true},
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 2, "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true},
		{"type": "abort_battle", "result": "win", "award_rewards": false}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "win")
	assert_eq(int(out.r.value.rewards.get("exp", 0)), 0, "rewards withheld")
	assert_eq(int(env.rpg.state.actor("hero").exp), 0, "no EXP was given")


func test_abort_battle_outside_a_battle_is_a_no_op() -> void:
	_sample_env()
	var r: RPGResult = await env.rpg.run_commands([{"type": "abort_battle", "result": "win"}], {"kind": "api", "id": "t"})
	assert_false(r.is_error(), "no battle: nothing happens, no error")
	var cmd: RPGCommand = env.rpg.registry.get_command("abort_battle")
	assert_eq(cmd.summary({"result": "abort"}), "End Battle: abort")
	assert_eq(cmd.summary({"result": "win", "award_rewards": false}), "End Battle: win (no rewards)")


# --- enemy targets of the party commands (#2) ---------------------------------------------------------


func test_change_hp_sp_on_enemies() -> void:
	_sample_env()
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var e1: RPGBattler = scene.core.enemies[0]
	# Without "allow knockout" an enemy keeps 1 HP, as an actor does.
	await env.rpg.run_commands([{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1, "resource": "hp", "operation": "decrease", "amount": 999}], {"kind": "api", "id": "t"})
	assert_eq(e1.get_resource("hp"), 1, "the floor holds")
	# With it, the enemy dies, collapses and counts toward victory.
	await env.rpg.run_commands([{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1, "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}], {"kind": "api", "id": "t"})
	assert_true(e1.is_dead())
	assert_true(await _wait_until(func(): return not scene.enemy_nodes[e1].visible, 5.0), "its sprite collapses")
	# SP follows the same target rules.
	var sp_before: int = scene.core.enemies[1].get_resource("sp")
	await env.rpg.run_commands([{"type": "change_hp_mp", "target": "enemy", "enemy_index": 2, "resource": "sp", "operation": "decrease", "amount": 5}], {"kind": "api", "id": "t"})
	assert_eq(scene.core.enemies[1].get_resource("sp"), maxi(0, sp_before - 5), "SP follows the same rules")
	# An amount from a variable, and "entire troop" targeting.
	var rr: RPGResult = await env.rpg.run_commands([
		{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": 999},
		{"type": "change_hp_mp", "target": "troop", "resource": "hp", "operation": "decrease", "amount": {"variable": "fish_caught"}, "allow_knockout": true}], {"kind": "api", "id": "t"})
	assert_false(rr.is_error(), "the variable amount ran: %s" % str(rr))
	assert_true(scene.core.enemies[1].is_dead(), "the whole troop fell")
	assert_eq(scene.core.battle_over(), "win", "and that wins the battle")
	await _finish(scene, out)
	assert_eq(int(out.r.value.rewards.get("exp", 0)), 12, "both slimes give their EXP")


func test_change_state_and_recover_all_on_enemies() -> void:
	_sample_env()
	_add_troop(_later_troop())
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var e1: RPGBattler = scene.core.enemies[0]
	await env.rpg.run_commands([{"type": "change_state", "target": "enemy", "enemy_index": 1, "state": "poison", "operation": "add", "force": true}], {"kind": "api", "id": "t"})
	assert_true(e1.state_ids().has("poison"), "the state was added")
	await env.rpg.run_commands([{"type": "change_state", "target": "enemy", "enemy_index": 1, "state": "poison", "operation": "remove"}], {"kind": "api", "id": "t"})
	assert_false(e1.state_ids().has("poison"), "and removed again")
	# Recover All on an enemy heals its resources and clears its states.
	await env.rpg.run_commands([
		{"type": "change_state", "target": "enemy", "enemy_index": 1, "state": "sleep", "operation": "add", "force": true},
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1, "resource": "hp", "operation": "decrease", "amount": 10},
		{"type": "recover_all", "target": "enemy", "enemy_index": 1}], {"kind": "api", "id": "t"})
	assert_false(e1.state_ids().has("sleep"))
	var max_hp: int = env.rpg.rules.max_resource(e1, "hp")
	assert_eq(e1.get_resource("hp"), max_hp, "restored to full")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "escape")


func test_enemy_targets_outside_a_battle_do_nothing() -> void:
	_sample_env()
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1, "resource": "hp", "operation": "decrease", "amount": 5},
		{"type": "change_state", "target": "troop", "state": "poison", "operation": "add"},
		{"type": "recover_all", "target": "troop"}], {"kind": "api", "id": "t"})
	assert_false(r.is_error(), "no battle: a quiet no-op, no error")


# --- Change Party Member during a battle (#5) ---------------------------------------------------------


func test_change_party_during_a_battle() -> void:
	_sample_env()
	Engine.time_scale = 4.0
	_add_troop(_later_troop())
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true, "battle_system": "atb"}, out)
	await _open_actor_command(scene)
	await env.rpg.run_commands([{"type": "change_party", "actor": "mira", "operation": "add"}], {"kind": "api", "id": "t"})
	assert_eq(scene.core.party.size(), 2, "Mira is on the field")
	var mira: RPGBattler = env.rpg.state.actor("mira")
	assert_eq(scene.core.party[1], mira)
	assert_true(scene.core.gauges.has(mira), "she got a gauge (ATB)")
	var rows: int = scene.status_rows.get_children().filter(func(c): return not c.is_queued_for_deletion()).size()
	assert_eq(rows, 2, "a status row for her")
	# Taking the leader out leaves Mira fighting alone.
	await env.rpg.run_commands([{"type": "change_party", "actor": "hero", "operation": "remove"}], {"kind": "api", "id": "t"})
	assert_eq(scene.core.party, [mira])
	assert_ne(scene.core.battle_over(), "lose", "Mira keeps the fight going")
	# Victory EXP goes to the members present at the end.
	await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "troop", "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "win")
	assert_true(mira.exp > 0, "Mira, who was there, gets the EXP")
	assert_eq(env.rpg.state.party, ["mira"], "the map party follows the change")


func test_change_party_battle_temp_member_leaves_afterwards() -> void:
	_sample_env()
	_add_troop(_later_troop())
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	await env.rpg.run_commands([{"type": "change_party", "actor": "mira", "operation": "add", "battle_temp": true}], {"kind": "api", "id": "t"})
	assert_eq(scene.core.party.size(), 2, "she joins the fight")
	await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "troop", "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(env.rpg.state.party, ["hero"], "but leaves the party when the battle ends")


# --- troop page conditions, the RM2003 set (#11) --------------------------------------------------------


## A variable condition on a troop page: the scene hands it to rpg.state.check_condition, and the
## page runs mid-battle once the variable is set.
func test_troop_page_variable_condition_runs_mid_battle() -> void:
	_sample_env()
	var page := {"id": "hook", "conditions": [{"kind": "variable", "id": "fish_caught", "op": ">=", "value": 3}],
		"span": "once_per_battle", "commands": [{"type": "set_switch", "id": "rain", "value": "on"}]}
	_add_troop(_later_troop([page]))
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	assert_false(env.rpg.get_switch("rain"), "the page has not run yet")
	await env.rpg.run_commands([{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": 3}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_true(env.rpg.get_switch("rain"), "the variable condition fired during the fight")


# --- Conditional Branch battle checks (#50) ------------------------------------------------------------


## Runs one Conditional Branch in the running battle; returns true (then) or false (else).
func _branch(cond: Dictionary) -> bool:
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "if", "condition": cond, "then": [
			{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": 1}], "else": [
			{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": 0}]}], {"kind": "api", "id": "t"})
	assert_false(r.is_error(), "the branch ran: %s" % str(r))
	return int(env.rpg.state.get_variable("fish_caught")) == 1


func test_conditional_branch_battle_checks_in_events() -> void:
	_sample_env()
	# A troop page runs an `if` with a page-style check: branches read the running battle too.
	var page := {"id": "probe", "conditions": [{"kind": "turn", "n": 1}], "span": "once_per_battle", "commands": [
		{"type": "if", "condition": {"kind": "enemy_hp", "index": 0, "op": "<=", "percent": 100}, "then": [
			{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": 1}], "else": []}]}
	_add_troop(_later_troop([page]))
	var out := {}
	var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	assert_eq(int(env.rpg.state.get_variable("fish_caught")), 1, "the page's if read the enemy's HP")
	assert_true(await _branch({"kind": "actor_can_act", "id": "hero"}), "the hero can act")
	assert_true(await _branch({"kind": "enemy_can_act", "index": 0}), "so can the first slime")
	assert_true(await _branch({"kind": "turn", "n": 1}), "and it is turn 1")
	assert_false(await _branch({"kind": "actor_can_act", "id": "mira"}), "an actor outside the battle cannot act")
	assert_false(await _branch({"kind": "enemy_can_act", "index": 1}), "nor can the hidden member")
	assert_false(await _branch({"kind": "enemy_hp", "index": 0, "op": "<=", "percent": 50}), "the slime is above half HP")
	assert_false(await _branch({"kind": "enemy_is_target", "index": 0}), "no action has run, nothing is the target")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "escape")
	# Outside a battle the checks are quietly false (with a warning logged), not an error.
	assert_false(await _branch({"kind": "enemy_is_target", "index": 0}), "outside a battle the check is false")
	assert_true(env.rpg.state.errors.size() > 0, "the misuse was reported")


# --- troop sources (#38) ------------------------------------------------------------------------------


## Runs a battle command to its end and reports the scene, the group it fought and the result.
## Commands that stop with an error before a scene opens report it without asserting here.
func _fight(cmd: Dictionary) -> Dictionary:
	var out := {"r": null, "scene": null, "troop_id": ""}
	var run := func(): out.r = await env.rpg.run_commands([cmd], {"kind": "api", "id": "t"})
	run.call()
	await _wait_until(func(): return env.rpg.ui.scene_stack.size() > 0 or out.r != null)
	if env.rpg.ui.scene_stack.size() > 0:
		out.scene = env.rpg.ui.scene_stack[-1]
		out.troop_id = str(out.scene.core.troop.get("id", ""))
		out.scene.auto = true
		env.rpg.ui.auto_advance = true
		var end := Time.get_ticks_msec() + 20000
		while out.r == null and Time.get_ticks_msec() < end:
			if is_instance_valid(out.scene) and out.scene.phase != "":
				if out.scene.phase == "party":
					out.scene.cmd_list.select(0)
				out.scene.handle_action("ok")
			await tree.process_frame
	return out


## The group can be named by a variable, or come from the same roll a random encounter on the
## map would make. Both stop with a named error when they name no group.
func test_battle_troop_from_variable_and_encounter_roll() -> void:
	_sample_env()
	_add_troop(_later_troop())
	env.rpg.data.variables["battle_group"] = {"id": "battle_group", "label": "Battle group", "type": "string"}
	env.rpg.data.state_defs["variables"].append({"id": "battle_group", "label": "Battle group", "type": "string"})
	await env.start_on("town", Vector2i(14, 12), "up")
	# Named by a variable.
	env.rpg.state.set_variable("battle_group", "later")
	var r1: Dictionary = await _fight({"type": "battle", "troop_source": "variable", "variable": "battle_group", "can_escape": false, "can_lose": true})
	assert_eq(r1.troop_id, "later", "the variable named the group")
	assert_true(r1.r != null and r1.r.is_ok(), "the battle runs: %s" % [r1.r])
	env.rpg.state.set_variable("battle_group", "ghost")
	var r2: Dictionary = await _fight({"type": "battle", "troop_source": "variable", "variable": "battle_group"})
	assert_true(r2.r != null and r2.r.is_error() and str(r2.r.message).contains("ghost"), "a missing group is a named error: %s" % [r2.r])
	# The random encounter's roll: the map's groups, region-filtered, weight-rolled (weight 0
	# never wins, so "slimes" is certain).
	env.game.map.props["encounters"] = {"steps": 30, "groups": [{"troop": "bats", "weight": 0}, {"troop": "slimes", "weight": 3}]}
	var r3: Dictionary = await _fight({"type": "battle", "troop_source": "encounter", "can_escape": false, "can_lose": true})
	assert_eq(r3.troop_id, "slimes", "the encounter roll picked from the map's list")
	assert_true(r3.r != null and r3.r.is_ok(), "the battle runs: %s" % [r3.r])
	# No group for this region: a named error, not a silent no-op.
	env.game.map.props["encounters"] = {"steps": 30, "groups": [{"troop": "bats", "weight": 1, "regions": [7]}]}
	var r4: Dictionary = await _fight({"type": "battle", "troop_source": "encounter"})
	assert_true(r4.r != null and r4.r.is_error() and str(r4.r.message).contains("no encounter group"), "a map without groups here is a named error: %s" % [r4.r])


# --- Force Flee (#40) ---------------------------------------------------------------------------------


## One enemy runs: it leaves the field and the rewards, and the fight goes on until the rest
## falls — the fled one gives nothing.
func test_force_flee_one_enemy_leaves_without_rewards() -> void:
	_sample_env()
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var e1: RPGBattler = scene.core.enemies[0]
	var e2: RPGBattler = scene.core.enemies[1]
	var r: RPGResult = await env.rpg.run_commands([{"type": "force_flee", "target": "enemy", "enemy_index": 1}], {"kind": "api", "id": "t"})
	assert_false(r.is_error(), "the command ran: %s" % [r])
	assert_true(e1.escaped, "the first slime ran")
	assert_false(e1.is_active(), "it is out of the fight and the targeting")
	assert_false(e2.escaped, "the second one stays")
	assert_true(await _wait_until(func(): return not scene.enemy_nodes[e1].visible, 5.0), "its sprite fades out")
	assert_eq(scene.core.battle_over(), "", "one enemy left: the battle goes on")
	# The one left standing falls: victory, but only its EXP and gold.
	await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "troop", "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "win")
	assert_eq(int(out.r.value.rewards.get("exp", 0)), 6, "the fled slime gives no EXP")
	assert_eq(int(out.r.value.rewards.get("gold", 0)), 8, "and no gold")


## Every enemy runs: the battle is won at once, with no rewards at all — RM2003's way of ending
## a story fight where nobody has to die.
func test_force_flee_every_enemy_wins_without_rewards() -> void:
	_sample_env()
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	await env.rpg.run_commands([{"type": "force_flee", "target": "enemies"}], {"kind": "api", "id": "t"})
	assert_true(scene.core.enemies.all(func(e): return e.escaped), "the whole group ran")
	assert_eq(scene.core.active_enemies().size(), 0)
	assert_eq(scene.core.battle_over(), "win", "with no enemies left, the battle is won")
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "win")
	assert_eq(int(out.r.value.rewards.get("exp", 0)), 0, "no EXP for a fight everyone fled")
	assert_eq(int(out.r.value.rewards.get("gold", 0)), 0, "no gold either")


## The party runs: the battle ends as an escape with no chance roll — even when the group says
## the party cannot escape on its own.
func test_force_flee_the_party_ends_the_battle_as_escape() -> void:
	_sample_env()
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	await env.rpg.run_commands([{"type": "force_flee", "target": "party"}], {"kind": "api", "id": "t"})
	assert_true(scene.core.party.all(func(a): return a.escaped), "the party ran")
	assert_eq(scene.core.battle_over(), "escape")
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "escape")


## Outside a battle it stops the event with a named error, and inside one the enemy number has
## to exist in the group.
func test_force_flee_errors() -> void:
	_sample_env()
	var r: RPGResult = await env.rpg.run_commands([{"type": "force_flee", "target": "enemies"}], {"kind": "api", "id": "t"})
	assert_true(r.is_error() and str(r.message).contains("only works in a battle event"), "no battle: %s" % [r])
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var r2: RPGResult = await env.rpg.run_commands([{"type": "force_flee", "target": "enemy", "enemy_index": 5}], {"kind": "api", "id": "t"})
	assert_true(r2.is_error() and str(r2.message).contains("no enemy #5"), "out of range: %s" % [r2])
	assert_false(scene.core.enemies[0].escaped, "nobody ran")
	var cmd: RPGCommand = env.rpg.registry.get_command("force_flee")
	assert_eq(cmd.summary({"target": "enemy", "enemy_index": 2}), "Force Flee: enemy #2")
	assert_eq(cmd.summary({"target": "enemies"}), "Force Flee: every enemy")
	assert_eq(cmd.summary({"target": "party"}), "Force Flee: the party")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)


# --- the defeat handler (#39) --------------------------------------------------------------------------


## The System's defeat handler: when the party falls, a common event (and optional transfer)
## takes the place of Game Over, and the event that started the battle goes on. Without one —
## or when it names no common event — Game Over comes as before.
func test_defeat_handler_instead_of_game_over() -> void:
	_sample_env()
	await env.start_on("town", Vector2i(14, 12), "up")
	var data: RPGProjectData = env.rpg.data
	data.variables["rescue_ran"] = {"id": "rescue_ran", "label": "Rescue ran", "type": "int"}
	data.variables["battle_outcome"] = {"id": "battle_outcome", "label": "Battle outcome", "type": "string"}
	data.state_defs["variables"].append({"id": "rescue_ran", "label": "Rescue ran", "type": "int"})
	data.state_defs["variables"].append({"id": "battle_outcome", "label": "Battle outcome", "type": "string"})
	data.common_events["rescue"] = {"id": "rescue", "name": "Rescue", "trigger": "none", "switch": "", "commands": [
		{"type": "set_variable", "id": "rescue_ran", "operation": "set", "value": 1},
		{"type": "recover_all", "target": "party"}]}
	data.system["defeat_event"] = "rescue"
	data.system["defeat_transfer"] = {"map": "house_inside", "position": [1, 1]}
	data.system["defeat_facing"] = "down"
	# A group whose page fells the whole party on turn 1: a certain loss, whatever the rolls.
	_add_troop(_later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1, "every": 1}], "span": "every_check", "commands": [
		{"type": "change_hp_mp", "target": "party", "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}]}]))
	var r1: Dictionary = await _fight({"type": "battle", "troop": "later", "can_escape": false, "result": "battle_outcome"})
	assert_true(r1.r != null and r1.r.is_ok(), "the battle ran to its loss: %s" % [r1.r])
	assert_eq(str(env.rpg.get_variable("battle_outcome")), "lose", "the party fell")
	assert_eq(int(env.rpg.get_variable("rescue_ran")), 1, "the common event ran")
	assert_true(env.rpg.state.actor("hero").is_alive(), "it healed the fallen party")
	assert_true(await _wait_until(func(): return env.game.map != null and env.game.map.map_id == "house_inside" and not env.game.transferring), "the party was carried to the defeat map")
	assert_eq(env.game.player.cell, Vector2i(1, 1))
	assert_eq(env.game.player.facing, "down", "the defeat facing applies")
	assert_eq(int(env.rpg.state.game_data({"kind": "counter", "field": "defeats"})), 1, "the defeat still counts")
	await frames(5)
	assert_false(_game_over_shown(), "no Game Over: the handler took its place")
	# A handler that names no common event is no handler: Game Over as before. The battle scene
	# runs in auto mode while ui auto advance stays off, so the game over screen waits to be
	# seen instead of closing itself at once; the message box alone runs on auto because the
	# battle event's text would otherwise wait for a click.
	env.rpg.state.new_game()
	data.system["defeat_event"] = "ghost"
	env.rpg.ui.auto_advance = false
	env.rpg.ui.message_box.auto_advance = true
	var r2 := {"r": null}
	var run2 := func(): r2.r = await env.rpg.run_commands([{"type": "battle", "troop": "later", "can_escape": false, "result": "battle_outcome"}], {"kind": "api", "id": "t"})
	run2.call()
	var end2 := Time.get_ticks_msec() + 20000
	while r2.r == null and Time.get_ticks_msec() < end2:
		for s in env.rpg.ui.scene_stack:
			if is_instance_valid(s) and s.get("core") != null:
				s.auto = true
				if s.phase != "":
					if s.phase == "party":
						s.cmd_list.select(0)
					s.handle_action("ok")
		await tree.process_frame
	assert_true(r2.r != null, "the second battle ends")
	assert_eq(str(env.rpg.get_variable("battle_outcome")), "lose", "the party falls again")
	assert_true(await _wait_until(func(): return _game_over_shown(), 10.0), "a missing handler shows Game Over as before")


# --- the validator -----------------------------------------------------------------------------------


func test_validator_checks_enemy_targets() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var t := _later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1}], "commands": [
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 2, "resource": "hp", "operation": "decrease", "amount": 5},
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 5, "resource": "hp", "operation": "decrease", "amount": 5},
		{"type": "force_flee", "target": "enemy", "enemy_index": 5},
		{"type": "force_flee", "target": "enemy", "enemy_index": 2}]}])
	var probs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json")
	var msgs := probs.map(func(p): return "%s %s" % [p.severity, p.message])
	assert_true(msgs.any(func(m): return m.begins_with("error") and m.contains("no enemy #5")), str(msgs))
	assert_eq(msgs.filter(func(m): return m.contains("no enemy #5")).size(), 2, "both the party command and Force Flee check the number")
	assert_false(msgs.any(func(m): return m.contains("#2")), "enemy #2 is a member of the group: %s" % str(msgs))
	# On a map they can never work: flagged, also inside a branch.
	var ev := {"id": "e", "position": [1, 1], "pages": [{"commands": [
		{"type": "if", "condition": {"kind": "switch", "id": "s"}, "then": [
			{"type": "change_state", "target": "troop", "state": "poison", "operation": "add"}], "else": []}]}]}
	var p2 := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, reg, "events.json")
	var w := p2.filter(func(p): return str(p.message).contains("only works in a battle event"))
	assert_eq(w.size(), 1, str(p2))
	assert_eq(w[0].severity, "warning")
	assert_eq(w[0].path, "events/0/pages/0/commands/0/then/0/target")
	# Force Flee on a map gets the same battle-only warning.
	var ev2 := {"id": "f", "position": [1, 1], "pages": [{"commands": [{"type": "force_flee", "target": "enemies"}]}]}
	var p3 := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev2]}, reg, "events.json")
	var w3 := p3.filter(func(p): return str(p.message).contains("only works in a battle event"))
	assert_eq(w3.size(), 1, str(p3))
	assert_eq(w3[0].severity, "warning")
	assert_eq(w3[0].path, "events/0/pages/0/commands/0")


# --- Game Data: play counters and last used (#54) -----------------------------------------------------


func test_battle_command_updates_play_counters() -> void:
	_sample_env()
	env.rpg.ui.auto_advance = true
	var st: RPGGameState = env.rpg.state
	var r: RPGResult = await env.rpg.run_commands([{"type": "battle", "troop": "slimes", "can_lose": true}], {"kind": "api", "id": "counters"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(st.game_data({"kind": "counter", "which": "battles"})), 1, "the fight was counted")
	assert_eq(int(st.game_data({"kind": "counter", "which": "victories"})), 1, "a win")
	assert_eq(int(st.game_data({"kind": "counter", "which": "defeats"})), 0)
	assert_eq(int(st.game_data({"kind": "counter", "which": "escapes"})), 0)


func test_counters_readable_while_the_fight_runs() -> void:
	_sample_env()
	env.rpg.ui.auto_advance = true
	var seen := {"battles": -1}
	var on_started := func(_args: Dictionary) -> void:
		seen.battles = int(env.rpg.state.game_data({"kind": "counter", "which": "battles"}))
	env.rpg.battle_started.connect(on_started)
	var r: RPGResult = await env.rpg.run_commands([{"type": "battle", "troop": "slimes", "can_lose": true}], {"kind": "api", "id": "live"})
	env.rpg.battle_started.disconnect(on_started)
	assert_true(r.is_ok(), str(r))
	assert_eq(seen.battles, 1, "the counter is live during the battle")


func test_last_used_recorded_by_battle_actions() -> void:
	_sample_env()
	env.rpg.ui.auto_advance = true
	var r: RPGResult = await env.rpg.run_commands([{"type": "battle", "troop": "slimes", "can_lose": true}], {"kind": "api", "id": "lu"})
	assert_true(r.is_ok(), str(r))
	var st: RPGGameState = env.rpg.state
	assert_eq(str(st.game_data({"kind": "last_used", "what": "actor"})), "hero", "the hero acted")
	assert_true(int(st.game_data({"kind": "last_used", "what": "target_enemy"})) in [0, 1], "an enemy was targeted: %s" % str(st.last_used))


func test_battle_event_reads_enemy_game_data() -> void:
	_sample_env()
	env.rpg.ui.auto_advance = true
	var page := {"id": "probe", "conditions": [{"kind": "turn", "n": 1}], "span": "once_per_battle",
		"commands": [
			{"type": "set_variable", "id": "fish_caught", "operation": "set", "value": {"game_data": {"kind": "enemy", "index": 0, "field": "hp"}}},
			{"type": "abort_battle", "result": "abort"}]}
	_add_troop(_later_troop([page]))
	var r: RPGResult = await env.rpg.run_commands([{"type": "battle", "troop": "later", "can_lose": true, "can_escape": false}], {"kind": "api", "id": "probe"})
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("fish_caught")), 40, "the first slime's HP read from inside the battle")


func test_validator_checks_troop_condition_kinds() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var good := _later_troop([{"id": "p", "conditions": [
		{"kind": "enemy_mp", "index": 0, "op": "<=", "percent": 25},
		{"kind": "enemy_turns", "index": 0, "op": ">=", "n": 2},
		{"kind": "actor_mp", "id": "hero", "op": "<=", "percent": 50},
		{"kind": "actor_turns", "id": "hero", "op": "==", "n": 2},
		{"kind": "command_used", "id": "mira", "command": "skill", "skill": "fire"},
		{"kind": "variable", "id": "fish_caught", "op": ">=", "value": 3},
	], "commands": []}])
	var probs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [good]}, reg, "troops.json")
	assert_false(probs.any(func(p): return p.severity == "error"), str(probs))
	var bad := _later_troop([{"id": "p", "conditions": [
		{"kind": "enemy_turns", "index": 0, "op": "~=", "n": 2},
		{"kind": "command_used", "id": "mira", "command": "dance"},
		{"kind": "command_used", "id": "mira", "command": "skill"},
		{"kind": "actor_mp", "id": "", "op": "<=", "percent": 50},
	], "commands": []}])
	var msgs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [bad]}, reg, "troops.json").map(func(p): return str(p.message))
	assert_true(msgs.any(func(m): return m.contains("Unknown comparison '~='")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("Unknown battle command 'dance'")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("needs the skill")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("no valid ID")), str(msgs))
	# Battle-only kinds do not work on map pages.
	var ev := {"id": "e", "position": [1, 1], "pages": [{"conditions": [{"kind": "enemy_turns", "index": 0, "op": ">=", "n": 2}], "commands": []}]}
	var p3 := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, reg, "events.json")
	assert_true(p3.any(func(p): return str(p.message).contains("Unknown condition kind 'enemy_turns'")), str(p3))


func test_validator_checks_enemy_action_conditions() -> void:
	_sample_env()
	var good := {"id": "strategist", "name": "Strategist", "stats": {}, "actions": [
		{"skill": "attack", "rating": 5, "condition": {"kind": "mp", "op": "<=", "percent": 25}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "state", "state": "poison"}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "party_level", "pick": "highest", "op": ">=", "level": 5}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "enemies_alive", "op": "<=", "count": 1}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "variable", "variable": "fish_caught", "op": ">=", "against": 3}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "variable", "id": "fish_caught", "op": ">=", "value": 3}},
	]}
	var probs := RPGValidator.structure("database:enemies", {"schema_version": 1, "records": [good]})
	assert_false(probs.any(func(p): return p.severity == "error"), str(probs))
	var bad := {"id": "strategist", "name": "Strategist", "stats": {}, "actions": [
		{"skill": "attack", "rating": 5, "condition": {"kind": "party_loyalty"}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "mp", "op": "~=", "percent": 25}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "state"}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "variable", "op": ">=", "against": "sometimes"}},
		{"skill": "attack", "rating": 5, "condition": {"kind": "switch"}},
	]}
	var msgs := RPGValidator.structure("database:enemies", {"schema_version": 1, "records": [bad]}).map(func(p): return str(p.message))
	assert_true(msgs.any(func(m): return m.contains("Unknown condition kind 'party_loyalty'")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("Unknown comparison '~='")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("no valid state")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("no valid variable")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("no valid ID")), str(msgs))


func test_validator_battle_branch_kinds() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	# Inside a battle event (or a common event) the battle checks are fine.
	var t := _later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1}], "commands": [
		{"type": "if", "condition": {"kind": "actor_can_act", "id": "hero"}, "then": [], "else": [
			{"type": "if", "condition": {"kind": "enemy_is_target", "index": 0}, "then": [], "else": []}]}]}])
	assert_eq(RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json").size(), 0, "troop page commands may use them")
	var ce := {"id": "probe", "trigger": "none", "commands": [
		{"type": "if", "condition": {"kind": "enemy_can_act", "index": 0}, "then": [], "else": []}]}
	assert_eq(RPGValidator.structure("common_events", {"schema_version": 1, "common_events": [ce]}, reg, "common_events.json").size(), 0, "so may common events")
	# On a map they only ever evaluate false: warned, not an error.
	var ev := {"id": "e", "position": [1, 1], "pages": [{"commands": [
		{"type": "if", "condition": {"kind": "enemy_is_target", "index": 0}, "then": [], "else": []}]}]}
	var probs := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, reg, "events.json")
	assert_eq(probs.size(), 1, str(probs))
	assert_eq(probs[0].severity, "warning")
	# And they are not page conditions, even on a battle page.
	var bad := _later_troop([{"id": "p", "conditions": [{"kind": "actor_can_act", "id": "hero"}], "commands": []}])
	var p2 := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [bad]}, reg, "troops.json")
	assert_eq(p2.size(), 1, "a branch-only kind is not a page condition")
	assert_eq(p2[0].severity, "error")
