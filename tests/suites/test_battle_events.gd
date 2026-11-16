extends "res://tests/rpg_test_case.gd"
## Battle events through the public battle API: the rpg.battle facade (#29), End Battle (#4),
## enemy targets of Change HP/SP, Change State and Recover All (#2), Change Party Member
## during a battle (#5), Force Flee (#40), Transform Enemy (#3), and Force Action (#12).

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


## A certain-hit, flat-damage skill injected for the Force Action tests: the sample fire's 95%
## hit would make the "was hit" assertions flaky (a forced cast can miss like any other).
func _zapt() -> Dictionary:
	return {"id": "zapt", "name": "Zapt", "cost": {"sp": 6}, "damage_type": "damage",
		"formula": "25", "hit": 100, "hit_type": "certain", "message": "%1 casts Zapt!",
		"occasion": "battle", "resource": "hp", "scope": "one_enemy", "skill_type": "magic",
		"variance": 0}


func _add_skill(s: Dictionary) -> void:
	var data: RPGProjectData = env.rpg.data
	data.db["skills"].by_id[s.id] = s
	data.db["skills"].records.append(s)


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
	# A timed battle can end on its own before the caller aborts it (the hero falls), which frees
	# the scene; then there is nothing left to drive, only the result to check.
	if not is_instance_valid(scene):
		assert_eq(out.get("r", {}).get("status", ""), "finished", "the battle ends")
		return
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


# --- play counters, last used and enemy stats (#54) ---------------------------------------------------


## A finished battle counts itself and its outcome, records what was used and at what, and a
## battle event reads an enemy's stats through the enemy game data kind.
func test_battle_counts_records_use_and_reads_enemy_stats() -> void:
	_sample_env()
	_add_troop(_later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1, "every": 1}], "span": "every_check", "commands": [
		{"type": "set_variable", "id": "talks", "operation": "set", "value": {"game_data": {"kind": "enemy", "index": 0, "field": "level"}}}]}]))
	var done := {"r": null}
	var run_cmd := func(): done.r = await env.rpg.run_commands([{"type": "battle", "troop": "later", "can_escape": false, "can_lose": true}])
	run_cmd.call()
	assert_true(await _wait_until(func(): return env.rpg.ui.scene_stack.size() > 0), "the battle scene opens")
	var scene: Node = env.rpg.ui.scene_stack[-1]
	scene.auto = true
	env.rpg.ui.auto_advance = true
	var end := Time.get_ticks_msec() + 20000
	while done.r == null and Time.get_ticks_msec() < end:
		if is_instance_valid(scene) and scene.phase != "":
			if scene.phase == "party":
				scene.cmd_list.select(0)
			scene.handle_action("ok")
		await tree.process_frame
	assert_true(done.r != null and done.r.is_ok(), "the battle command finishes: %s" % [done.r])
	var st: RPGGameState = env.rpg.state
	assert_eq(st.game_data({"kind": "counter", "field": "battles"}), 1, "the battle counts")
	assert_eq(st.game_data({"kind": "counter", "field": "victories"}), 1, "the win counts")
	assert_eq(st.game_data({"kind": "counter", "field": "escapes"}), 0, "nothing escaped")
	assert_eq(str(st.game_data({"kind": "last_used", "field": "actor"})), "hero", "the hero acted")
	assert_eq(st.game_data({"kind": "last_used", "field": "target_enemy"}), 0, "the first enemy was the target")
	assert_true(int(env.rpg.get_variable("talks")) >= 1, "a battle event read the enemy's level")


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


# --- Transform Enemy (#3) ------------------------------------------------------------------------------


## A troop page turns enemy #1 into a bat: same slot with its "A" suffix, the sprite rebuilt where
## the slime stood, and victory pays the bat's rewards for it.
func test_transform_enemy_from_a_troop_page() -> void:
	_sample_env()
	_add_troop(_twin_troop([{"id": "molt", "conditions": [{"kind": "turn", "n": 1}], "span": "once_per_battle",
		"commands": [{"type": "transform_enemy", "enemy_index": 1, "enemy": "bat"}]}]))
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	assert_true(await _wait_until(func(): return scene.core.enemies[0].id == "bat" and scene.enemy_nodes.has(scene.core.enemies[0])), "enemy #1 became a bat with a rebuilt sprite")
	var nb: RPGBattler = scene.core.enemies[0]
	assert_eq(nb.name, "Bat A", "the twin group keeps the suffix")
	assert_eq(scene.core.enemies[1].id, "slime", "the other member is untouched")
	assert_eq(nb.get_resource("hp"), 30, "keep HP clamps the slime's full 40 to the bat's maximum")
	var spr: TextureRect = scene.enemy_nodes[nb]
	assert_true(spr is TextureRect and spr.visible, "the new sprite stands in the field")
	assert_eq(scene.enemy_nodes.size(), 2, "one sprite per member, the old one gone")
	# The fight ends: the former slime now pays the bat's rewards.
	await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "troop", "resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "win")
	assert_eq(int(out.r.value.rewards.get("exp", 0)), 11, "the bat's EXP replaced the slime's")
	assert_eq(int(out.r.value.rewards.get("gold", 0)), 14, "and its gold")


## The HP and state options: keep the value (clamped), keep the percentage, or refill — states
## ride along unless the command says to clear them.
func test_transform_enemy_hp_modes_and_clear_states() -> void:
	_sample_env()
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	await env.rpg.run_commands([
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1, "resource": "hp", "operation": "decrease", "amount": 20},
		{"type": "change_state", "target": "enemy", "enemy_index": 1, "state": "poison", "operation": "add", "force": true}], {"kind": "api", "id": "t"})
	# Keep: 20 of the slime's 40 carries straight over (the goblin's maximum is 150).
	await env.rpg.run_commands([{"type": "transform_enemy", "enemy_index": 1, "enemy": "goblin"}], {"kind": "api", "id": "t"})
	var goblin: RPGBattler = scene.core.enemies[0]
	assert_eq(goblin.id, "goblin")
	assert_eq(goblin.get_resource("hp"), 20, "keep carries the value, under the new maximum")
	assert_true(goblin.state_ids().has("poison"), "states ride along by default")
	# Percent: 20 of 150 is 13.3%, and 13.3% of the bat's 30 rounds to 4.
	await env.rpg.run_commands([{"type": "transform_enemy", "enemy_index": 1, "enemy": "bat", "hp": "percent"}], {"kind": "api", "id": "t"})
	var bat: RPGBattler = scene.core.enemies[0]
	assert_eq(bat.get_resource("hp"), 4, "percent converts the ratio")
	assert_true(bat.state_ids().has("poison"), "still kept without clear_states")
	# Refill and clear: back to a slime at full health, the poison left behind.
	await env.rpg.run_commands([{"type": "transform_enemy", "enemy_index": 1, "enemy": "slime", "hp": "refill", "clear_states": true}], {"kind": "api", "id": "t"})
	var slime: RPGBattler = scene.core.enemies[0]
	assert_eq(slime.get_resource("hp"), 40, "refill fills the new maximum")
	assert_false(slime.state_ids().has("poison"), "clear_states leaves the old states behind")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "escape")


## Outside a battle it stops the event with a named error; inside one the enemy number has to be
## a member of the group and the record has to exist.
func test_transform_enemy_errors() -> void:
	_sample_env()
	var r: RPGResult = await env.rpg.run_commands([{"type": "transform_enemy", "enemy_index": 1, "enemy": "bat"}], {"kind": "api", "id": "t"})
	assert_true(r.is_error() and str(r.message).contains("only works in a battle event"), "no battle: %s" % [r])
	_add_troop(_twin_troop())
	var out := {}
	var scene := _start_battle({"troop": "twins", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var r2: RPGResult = await env.rpg.run_commands([{"type": "transform_enemy", "enemy_index": 5, "enemy": "bat"}], {"kind": "api", "id": "t"})
	assert_true(r2.is_error() and str(r2.message).contains("no enemy #5"), "out of range: %s" % [r2])
	assert_eq(scene.core.enemies[0].id, "slime", "nobody changed")
	var r3: RPGResult = await env.rpg.run_commands([{"type": "transform_enemy", "enemy_index": 1, "enemy": "ghost"}], {"kind": "api", "id": "t"})
	assert_true(r3.is_error() and str(r3.message).contains("ghost"), "a missing record is a named error: %s" % [r3])
	assert_eq(scene.core.enemies[0].id, "slime", "still nobody changed")
	var cmd: RPGCommand = env.rpg.registry.get_command("transform_enemy")
	assert_eq(cmd.summary({"enemy_index": 2, "enemy": "bat"}), "Transform: enemy #2 becomes bat")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)


## The export checks: the enemy number must be a member of the group, the command only works in
## a battle, and the "Becomes" record has to exist.
func test_validator_checks_transform_enemy() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var t := _later_troop([{"id": "m", "conditions": [{"kind": "turn", "n": 1}], "commands": [
		{"type": "transform_enemy", "enemy_index": 5, "enemy": "bat"},
		{"type": "transform_enemy", "enemy_index": 2, "enemy": "bat"}]}])
	var probs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json")
	var msgs := probs.map(func(p): return "%s %s" % [p.severity, p.message])
	assert_true(msgs.any(func(m): return m.begins_with("error") and m.contains("no enemy #5")), str(msgs))
	assert_false(msgs.any(func(m): return m.contains("#2")), "enemy #2 is a member of the group: %s" % str(msgs))
	# On a map it can never work: the battle-only warning on the command itself.
	var ev := {"id": "t", "position": [1, 1], "pages": [{"commands": [{"type": "transform_enemy", "enemy_index": 1, "enemy": "bat"}]}]}
	var p2 := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, reg, "events.json")
	var w := p2.filter(func(p): return str(p.message).contains("only works in a battle event"))
	assert_eq(w.size(), 1, str(p2))
	assert_eq(w[0].severity, "warning")
	assert_eq(w[0].path, "events/0/pages/0/commands/0")
	# The "Becomes" record is a command ref: a missing enemy is flagged like any other ref.
	var ghost := _twin_troop([{"id": "m", "conditions": [{"kind": "turn", "n": 1}], "commands": [
		{"type": "transform_enemy", "enemy_index": 1, "enemy": "ghost"}]}])
	_add_troop(ghost)
	env.rpg.data.db["troops"].file["records"].append(ghost)
	var refs := RPGValidator.references(env.rpg.data, env.rpg.registry).map(func(p): return p.message)
	assert_true(refs.any(func(m): return m.contains("Enemy 'ghost' does not exist")), str(refs))
	assert_false(refs.any(func(m): return m.contains("'bat' does not exist")), "a real enemy is fine")


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


# --- Force Action (#12) ------------------------------------------------------------------------------


## A one-member goblin group: the goblin has 10 SP and a pattern that never picks the skills the
## tests force, so a spent SP point can only come from the Force Action command.
func _goblin_troop(pages: Array = []) -> Dictionary:
	return {"id": "boss", "name": "Boss", "can_escape": true, "members": [
		{"enemy": "goblin", "hidden": false, "position": [160, 150]}], "pages": pages}


func test_force_action_right_now_acts_out_of_turn() -> void:
	_sample_env()
	Engine.time_scale = 4.0
	_add_skill(_zapt())
	_add_troop(_goblin_troop())
	var out := {}
	var scene := _start_battle({"troop": "boss", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var goblin: RPGBattler = scene.core.enemies[0]
	var hero: RPGBattler = scene.core.party[0]
	# The goblin zaps the hero while the party command window is still open.
	var hero_hp: int = hero.get_resource("hp")
	await env.rpg.run_commands([{"type": "force_action", "enemy_index": 1, "what": "skill", "skill": "zapt",
		"target": "index", "target_index": 1, "timing": "now"}], {"kind": "api", "id": "t"})
	assert_eq(scene.phase, "party", "the battle has not taken a turn")
	assert_true(hero.get_resource("hp") < hero_hp, "the hero was hit")
	assert_eq(goblin.get_resource("sp"), 4, "the goblin paid zapt's 6 SP")
	# The hero answers in kind: enemy #1 by number, then the same enemy by "its last target".
	var goblin_hp: int = goblin.get_resource("hp")
	for target in ["index", "last"]:
		hero.set_resource("sp", 99)
		var sp_before: int = hero.get_resource("sp")
		await env.rpg.run_commands([{"type": "force_action", "subject": "actor", "actor": "leader",
			"what": "skill", "skill": "zapt", "target": target, "target_index": 1, "timing": "now"}], {"kind": "api", "id": "t"})
		assert_true(goblin.get_resource("hp") < goblin_hp, "%s target: the goblin was hit again" % target)
		goblin_hp = goblin.get_resource("hp")
		assert_eq(hero.get_resource("sp"), sp_before - 6, "the hero paid for the zapt")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "escape")


func test_force_action_at_its_next_turn_uses_the_turn() -> void:
	_sample_env()
	Engine.time_scale = 4.0
	# A start-of-turn page forces both sides' turn-1 actions: the goblin burns the hero, the hero
	# burns the goblin (each 6 SP of their 10).
	var page := {"id": "forced", "conditions": [{"kind": "turn", "n": 1}], "span": "once_per_battle", "commands": [
		{"type": "force_action", "subject": "enemy", "enemy_index": 1, "what": "skill", "skill": "fire",
			"target": "index", "target_index": 1, "timing": "turn"},
		{"type": "force_action", "subject": "actor", "actor": "leader", "what": "skill", "skill": "fire",
			"target": "index", "target_index": 1, "timing": "turn"}]}
	_add_troop(_goblin_troop([page]))
	var out := {}
	var scene := _start_battle({"troop": "boss", "can_escape": false, "can_lose": true}, out)
	# Turn 1 plays out with nobody asked: no ok is ever pressed here, so the battle could only
	# move on if the party command never opened (the forced hero is not waiting for a command).
	var reached := await _wait_until(func():
		return not is_instance_valid(scene) or (scene.phase == "party" and scene.core.turn >= 2), 30.0)
	assert_true(reached, "turn 2's party command opens (turn 1 needed no input)")
	assert_eq(scene.core.enemies[0].get_resource("sp"), 4, "the goblin's forced fire ran on its turn")
	assert_eq(scene.core.party[0].get_resource("sp"), 4, "the hero's forced fire ran on their turn")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)


func test_force_action_in_a_timed_battle() -> void:
	_sample_env()
	Engine.time_scale = 4.0
	_add_skill(_zapt())
	_add_troop(_goblin_troop())
	var out := {}
	var scene := _start_battle({"troop": "boss", "can_escape": false, "can_lose": true, "battle_system": "atb"}, out)
	await _open_actor_command(scene)
	scene.atb_mode = "wait"     # time only moves when no command window is open
	var goblin: RPGBattler = scene.core.enemies[0]
	var hero: RPGBattler = scene.core.party[0]
	# Right now: the goblin zaps the hero while the hero's window is open — out of turn, and
	# without the goblin's gauge filling.
	var hero_hp: int = hero.get_resource("hp")
	await env.rpg.run_commands([{"type": "force_action", "enemy_index": 1, "what": "skill", "skill": "zapt",
		"target": "index", "target_index": 1, "timing": "now"}], {"kind": "api", "id": "t"})
	assert_eq(scene.phase, "actor", "the hero's command window is still open")
	assert_true(hero.get_resource("hp") < hero_hp, "the hero was hit")
	assert_eq(goblin.get_resource("sp"), 4, "zapt's SP were paid")
	assert_false(scene.core.ready_queue.has(goblin), "the goblin's gauge was not filled by the force")
	# At its next turn: both sides heal themselves (5 SP). Forcing the hero closes the open
	# window (it no longer needs input), so time moves again and both turns come.
	goblin.set_resource("sp", 10)
	await env.rpg.run_commands([
		{"type": "force_action", "subject": "actor", "actor": "leader", "what": "skill", "skill": "heal",
			"target": "index", "target_index": 1, "timing": "turn"},
		{"type": "force_action", "subject": "enemy", "enemy_index": 1, "what": "skill", "skill": "heal",
			"target": "index", "target_index": 1, "timing": "turn"}], {"kind": "api", "id": "t"})
	assert_true(await _wait_until(func():
		return not is_instance_valid(scene) or (hero.get_resource("sp") == 5 and goblin.get_resource("sp") == 5), 30.0),
		"both forced heals ran when their turns came (SP 10 -> 5)")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)


func test_force_action_skips_quietly_when_the_subject_cannot_act() -> void:
	_sample_env()
	Engine.time_scale = 4.0
	_add_troop({"id": "mixed", "name": "Mixed", "can_escape": true, "members": [
		{"enemy": "goblin", "hidden": false, "position": [120, 150]},
		{"enemy": "goblin", "hidden": false, "position": [200, 150]},
		{"enemy": "slime", "hidden": true, "position": [260, 150]}], "pages": []})
	var out := {}
	var scene := _start_battle({"troop": "mixed", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	var goblin: RPGBattler = scene.core.enemies[0]
	var hero: RPGBattler = scene.core.party[0]
	var hero_hp: int = hero.get_resource("hp")
	# A hidden member and (after Change HP) a dead one: no error, nothing happens.
	var r: RPGResult = await env.rpg.run_commands([{"type": "force_action", "enemy_index": 3,
		"what": "skill", "skill": "fire", "target": "random", "timing": "now"}], {"kind": "api", "id": "t"})
	assert_false(r.is_error(), "a hidden enemy skips quietly")
	await env.rpg.run_commands([{"type": "change_hp_mp", "target": "enemy", "enemy_index": 1,
		"resource": "hp", "operation": "decrease", "amount": 999, "allow_knockout": true}], {"kind": "api", "id": "t"})
	r = await env.rpg.run_commands([{"type": "force_action", "enemy_index": 1, "what": "skill", "skill": "fire",
		"target": "random", "timing": "now"}], {"kind": "api", "id": "t"})
	assert_false(r.is_error(), "a dead enemy skips quietly")
	assert_eq(hero.get_resource("hp"), hero_hp, "nothing happened")
	assert_eq(goblin.get_resource("sp"), 10, "no cost was paid")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)


func test_force_action_errors_and_summary() -> void:
	_sample_env()
	var r: RPGResult = await env.rpg.run_commands([{"type": "force_action", "enemy_index": 1,
		"what": "skill", "skill": "fire"}], {"kind": "api", "id": "t"})
	assert_true(r.is_error(), "outside a battle it stops the event")
	assert_true(r.message.contains("battle event"), r.message)
	Engine.time_scale = 4.0
	_add_troop(_goblin_troop())
	var out := {}
	var scene := _start_battle({"troop": "boss", "can_escape": false, "can_lose": true}, out)
	await _open_party_command(scene)
	r = await env.rpg.run_commands([{"type": "force_action", "enemy_index": 2, "what": "skill", "skill": "fire"}], {"kind": "api", "id": "t"})
	assert_true(r.is_error() and r.message.contains("no enemy #2"), r.message)
	r = await env.rpg.run_commands([{"type": "force_action", "enemy_index": 1, "what": "skill", "skill": "fireball"}], {"kind": "api", "id": "t"})
	assert_true(r.is_error() and r.message.contains("does not exist"), r.message)
	r = await env.rpg.run_commands([{"type": "force_action", "subject": "actor", "actor": "mira",
		"what": "skill", "skill": "fire"}], {"kind": "api", "id": "t"})
	assert_true(r.is_error() and r.message.contains("not in this battle"), r.message)
	assert_eq(scene.core.party[0].get_resource("hp"), env.rpg.rules.max_resource(scene.core.party[0], "hp"), "nothing happened")
	await env.rpg.run_commands([{"type": "abort_battle", "result": "abort"}], {"kind": "api", "id": "t"})
	await _finish(scene, out)
	var cmd: RPGCommand = env.rpg.registry.get_command("force_action")
	assert_eq(cmd.summary({"enemy_index": 2, "skill": "power_strike"}), "Force Action: enemy #2 uses power_strike")
	assert_eq(cmd.summary({"subject": "actor", "actor": "leader", "skill": "fire"}), "Force Action: leader uses fire")
	assert_eq(cmd.summary({"enemy_index": 1, "skill": "fire", "target": "random"}), "Force Action: enemy #1 uses fire (random target)")
	assert_eq(cmd.summary({"enemy_index": 1, "skill": "fire", "target": "index", "target_index": 2}), "Force Action: enemy #1 uses fire (target #2)")
	assert_eq(cmd.summary({"enemy_index": 1, "item": "potion", "what": "item", "timing": "turn"}), "Force Action: enemy #1 uses potion, at its next turn")


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


func test_validator_checks_force_action() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var t := _later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1}], "commands": [
		{"type": "force_action", "enemy_index": 2, "what": "skill", "skill": "fire"},
		{"type": "force_action", "enemy_index": 5, "what": "skill", "skill": "fire"},
		{"type": "force_action", "subject": "actor", "actor": "hero", "what": "skill", "skill": "heal"}]}])
	var probs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json")
	var msgs := probs.map(func(p): return "%s %s" % [p.severity, p.message])
	assert_true(msgs.any(func(m): return m.begins_with("error") and m.contains("no enemy #5")), str(msgs))
	assert_false(msgs.any(func(m): return m.contains("#2")), "enemy #2 is a member of the group: %s" % str(msgs))
	# An actor subject has no enemy number to check.
	assert_false(msgs.any(func(m): return m.contains("Force Action") and m.contains("hero")), str(msgs))
	# On a map it can never work: the battle-only warning.
	var ev := {"id": "e", "position": [1, 1], "pages": [{"commands": [
		{"type": "if", "condition": {"kind": "switch", "id": "s"}, "then": [
			{"type": "force_action", "enemy_index": 1, "what": "skill", "skill": "fire"}], "else": []}]}]}
	var p2 := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, reg, "events.json")
	var w := p2.filter(func(p): return str(p.message).contains("only works in a battle event"))
	assert_eq(w.size(), 1, str(p2))
	assert_eq(w[0].severity, "warning")
