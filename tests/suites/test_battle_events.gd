extends "res://tests/rpg_test_case.gd"
## Battle events through the public battle API: the rpg.battle facade (#29), End Battle (#4),
## enemy targets of Change HP/SP, Change State and Recover All (#2), and Change Party Member
## during a battle (#5).

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


# --- the validator -----------------------------------------------------------------------------------


func test_validator_checks_enemy_targets() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var t := _later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1}], "commands": [
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 2, "resource": "hp", "operation": "decrease", "amount": 5},
		{"type": "change_hp_mp", "target": "enemy", "enemy_index": 5, "resource": "hp", "operation": "decrease", "amount": 5}]}])
	var probs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json")
	var msgs := probs.map(func(p): return "%s %s" % [p.severity, p.message])
	assert_true(msgs.any(func(m): return m.begins_with("error") and m.contains("no enemy #5")), str(msgs))
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
