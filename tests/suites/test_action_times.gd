extends "res://tests/rpg_test_case.gd"
## Action Times+ (issue #148): in a turn-based battle each of a battler's actions is chosen on
## its own. An enemy rolls its action list once per action, an actor enters one command per
## action, the battler comes up once at the slowest of its actions' speeds, and its action end
## comes after the last of them.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")
const Env := preload("res://tests/rpg_test_env.gd")

var db
var rules: RPGRuleSystem
var env


func before_each() -> void:
	db = FakeDB.new()
	var growth := {"mhp": 9000, "mmp": 100, "atk": 30, "def": 20, "mat": 20, "mdf": 10, "agi": 500, "luk": 10}
	db.add("classes", {"id": "soldier", "name": "Soldier", "growth": growth})
	db.add("actors", {"id": "ace", "name": "Ace", "class": "soldier", "equips": {}, "skills": ["lunge", "slow_swing"],
		"traits": [{"kind": "action_times", "value": 100}]})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {}})
	db.add("actors", {"id": "lucky", "name": "Lucky", "class": "soldier", "equips": {},
		"traits": [{"kind": "action_times", "value": 50}]})
	db.add("actors", {"id": "robo", "name": "Robo", "class": "soldier", "equips": {},
		"traits": [{"kind": "action_times", "value": 100}, {"kind": "auto_battle"}]})
	var stats := {"mhp": 90000, "mmp": 0, "atk": 12, "def": 10, "mat": 10, "mdf": 10, "agi": 5, "luk": 10}
	db.add("enemies", {"id": "slime", "name": "Slime", "stats": stats, "actions": [{"skill": "wait", "rating": 5}]})
	# Tutorial 7's Cerberus: Action Times+ 100%, so it can attack and use a skill in one round.
	db.add("enemies", {"id": "cerberus", "name": "Cerberus", "stats": stats,
		"traits": [{"kind": "action_times", "value": 100}],
		"actions": [{"skill": "attack", "rating": 5}, {"skill": "bite", "rating": 5}]})
	db.add("enemies", {"id": "wolf", "name": "Wolf", "stats": stats,
		"traits": [{"kind": "action_times", "value": 100}],
		"actions": [{"skill": "attack", "rating": 5}, {"skill": "bite", "rating": 2},
			{"skill": "howl", "rating": 9, "condition": {"kind": "hp", "min": 0, "max": 50}}]})
	db.add("enemies", {"id": "runner", "name": "Runner", "stats": stats,
		"traits": [{"kind": "action_times", "value": 100}],
		"actions": [{"skill": "escape", "rating": 5}]})
	db.add("troops", {"id": "slimes", "name": "Slime", "members": [{"enemy": "slime"}], "pages": []})
	db.add("troops", {"id": "cerberus", "name": "Cerberus", "members": [{"enemy": "cerberus"}], "pages": []})
	db.add("troops", {"id": "wolves", "name": "Wolf", "members": [{"enemy": "wolf"}], "pages": []})
	db.add("troops", {"id": "runners", "name": "Runner", "members": [{"enemy": "runner"}, {"enemy": "slime"}], "pages": []})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "off_guard", "name": "Off Guard", "auto_removal": "action_end", "turns_min": 1, "turns_max": 1})
	db.add("skills", {"id": "bite", "name": "Bite", "scope": "one_enemy", "formula": "5", "hit_type": "certain", "variance": 0})
	db.add("skills", {"id": "howl", "name": "Howl", "scope": "user", "damage_type": "none", "hit_type": "certain"})
	db.add("skills", {"id": "lunge", "name": "Lunge", "scope": "user", "hit_type": "certain",
		"effects": [{"kind": "add_state", "id": "off_guard"}]})
	db.add("skills", {"id": "slow_swing", "name": "Slow Swing", "scope": "one_enemy", "formula": "5", "hit_type": "certain",
		"variance": 0, "speed": -2000})
	rules = RPGRuleSystem.load_rules("vx_ace", db)


func after_each() -> void:
	Engine.time_scale = 1.0
	if env != null:
		await env.destroy()
		env = null


func _core(party: Array, troop: String, rng_seed := 7) -> RPGBattleCore:
	var core := RPGBattleCore.new(party, db.record("troops", troop), rules, RPGRandom.new(rng_seed))
	core.start()
	return core


## Plays one turn. `entered` maps a party index to the commands the player gives it, in order
## (Guard for everyone it does not name). Returns the results in order.
func _play(core: RPGBattleCore, entered := {}) -> Array:
	core.begin_turn()
	for i in core.inputs_needed():
		var list: Array = entered.get(i, [{"kind": "guard"}])
		for k in list.size():
			core.set_action(i, list[k], k)
	var out := []
	var r := core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	core.end_turn()
	return out


func _of(results: Array, b: RPGBattler) -> Array:
	return results.filter(func(r): return r.user == b)


func _label(r: Dictionary) -> String:
	return "%s:%s" % [r.kind, r.name]


func test_an_enemy_picks_each_action_on_its_own() -> void:
	var eric := rules.new_actor_battler("eric")
	var core := _core([eric], "cerberus")
	var cerberus: RPGBattler = core.enemies[0]
	var differing := 0
	var same := 0
	for t in 30:
		var results := _play(core)
		var mine := _of(results, cerberus)
		assert_eq(mine.size(), 2, "Action Times+ 100%%: two actions on turn %d" % (t + 1))
		if mine.size() != 2:
			return
		var at := []
		for i in results.size():
			if results[i].user == cerberus:
				at.append(i)
		assert_eq(at[1], at[0] + 1, "one after the other")
		if _label(mine[0]) != _label(mine[1]):
			differing += 1
		else:
			same += 1
	assert_true(differing > 0, "some rounds it attacks and bites: the second action is its own pick")
	assert_true(same > 0, "and some rounds it picks the same thing twice")


func test_each_pick_honours_ratings_and_conditions() -> void:
	var eric := rules.new_actor_battler("eric")
	var core := _core([eric], "wolves")
	var wolf: RPGBattler = core.enemies[0]
	for t in 8:
		for r in _of(_play(core), wolf):
			assert_eq(str(r.kind), "attack", "at full HP: Bite is rated too low, Howl's condition fails")
	wolf.set_resource("hp", int(rules.max_resource(wolf, "hp") * 0.4))
	for t in 8:
		var mine := _of(_play(core), wolf)
		assert_eq(mine.size(), 2)
		for r in mine:
			assert_eq(str(r.name), "Howl", "under half HP both picks are the top-rated Howl")


func test_an_actor_enters_one_command_per_action() -> void:
	var ace := rules.new_actor_battler("ace")
	var eric := rules.new_actor_battler("eric")
	var core := _core([ace, eric], "slimes")
	core.begin_turn()
	assert_eq(core.inputs_needed(), [0, 1], "each actor is listed once")
	assert_eq(core.actions_needed(0), 2, "Ace enters two commands")
	assert_eq(core.actions_needed(1), 1)
	assert_eq(core.actions_needed(5), 0, "nobody there")
	assert_true(core.set_action(0, {"kind": "attack", "target": 0}))
	assert_true(core.set_action(0, {"kind": "guard"}, 1), "the second command")
	assert_false(core.set_action(0, {"kind": "guard"}, 2), "he has no third action")
	assert_false(core.set_action(1, {"kind": "guard"}, 1), "Eric has one")
	assert_false(core.set_action(0, {"kind": "skill", "skill": "nope"}, 1), "the usual checks apply to every command")
	assert_true(core.set_action(1, {"kind": "guard"}))
	var out := []
	var r := core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	core.end_turn()
	var mine := _of(out, ace)
	assert_eq(mine.map(func(x): return str(x.kind)), ["attack", "guard"], "his two commands, in the order entered")
	assert_eq(_of(out, eric).size(), 1)


func test_a_cancelled_command_and_a_driver_that_enters_one() -> void:
	var ace := rules.new_actor_battler("ace")
	var core := _core([ace], "slimes")
	# A driver that enters only the first command gets it for every action, as before.
	var mine := _of(_play(core, {0: [{"kind": "guard"}]}), ace)
	assert_eq(mine.map(func(x): return str(x.kind)), ["guard", "guard"])
	# The second command is taken back: the first is repeated.
	core.begin_turn()
	core.set_action(0, {"kind": "guard"})
	core.set_action(0, {"kind": "attack", "target": 0}, 1)
	core.clear_action(0, 1)
	var out := []
	var r := core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	core.end_turn()
	assert_eq(_of(out, ace).map(func(x): return str(x.kind)), ["guard", "guard"])
	# Both are taken back: nothing was entered, so he attacks.
	core.begin_turn()
	core.set_action(0, {"kind": "guard"})
	core.set_action(0, {"kind": "guard"}, 1)
	core.clear_action(0, 1)
	core.clear_action(0)
	assert_true(ace.action.is_empty())
	out = []
	r = core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	core.end_turn()
	assert_eq(_of(out, ace).map(func(x): return str(x.kind)), ["attack", "attack"])


func test_the_count_is_rolled_once_per_turn() -> void:
	var lucky := rules.new_actor_battler("lucky")
	var core := _core([lucky], "slimes")
	var seen := {}
	for t in 30:
		core.begin_turn()
		var n: int = core.actions_needed(0)
		for k in 4:
			assert_eq(core.actions_needed(0), n, "asking again gives the same answer")
		assert_eq(core.action_count(lucky), n)
		seen[n] = true
		for k in n:
			assert_true(core.set_action(0, {"kind": "guard"}, k))
		var acted := 0
		var r := core.next_action()
		while not r.is_empty():
			if r.user == lucky:
				acted += 1
			r = core.next_action()
		core.end_turn()
		assert_eq(acted, n, "he acts as often as he was asked on turn %d" % (t + 1))
	assert_true(seen.has(1) and seen.has(2), "Action Times+ 50%%: one action some turns, two on others: %s" % str(seen.keys()))


func test_the_battler_comes_up_at_its_slowest_action() -> void:
	var ace := rules.new_actor_battler("ace")
	var core := _core([ace], "slimes")
	var slime: RPGBattler = core.enemies[0]
	var attack := {"kind": "attack", "target": 0}
	var order := _play(core, {0: [attack, attack]}).map(func(r): return r.user)
	assert_eq(order, [ace, ace, slime], "two plain attacks: he is far faster")
	order = _play(core, {0: [attack, {"kind": "skill", "skill": "slow_swing", "target": 0}]}).map(func(r): return r.user)
	assert_eq(order, [slime, ace, ace], "a slow second action holds both back")
	order = _play(core, {0: [{"kind": "skill", "skill": "slow_swing", "target": 0}, attack]}).map(func(r): return r.user)
	assert_eq(order, [slime, ace, ace], "whichever of the two it is")


func test_the_action_end_comes_after_the_last_action() -> void:
	var ace := rules.new_actor_battler("ace")
	var core := _core([ace], "slimes")
	var attack := {"kind": "attack", "target": 0}
	# Turn 1: Lunge (puts Off Guard on him, Action End, 1 turn), then an attack.
	_play(core, {0: [{"kind": "skill", "skill": "lunge"}, attack]})
	assert_true(ace.has_state("off_guard"), "off guard after the turn he lunged in")
	# Turn 2: the state stays through his first action and goes after his second.
	core.begin_turn()
	core.set_action(0, attack)
	core.set_action(0, attack, 1)
	var first := core.next_action()
	assert_true(first.user == ace)
	assert_true(ace.has_state("off_guard"), "still off guard between his two actions")
	assert_eq(first.get("ticks", []).size(), 0, "no action end yet")
	var second := core.next_action()
	assert_true(second.user == ace)
	assert_false(ace.has_state("off_guard"), "it goes as his last action ends")
	assert_eq(second.get("ticks", []).size(), 1, "and that action's result reports it")
	while not core.next_action().is_empty():
		pass
	core.end_turn()


func test_auto_battle_and_forced_actions() -> void:
	var robo := rules.new_actor_battler("robo")
	var core := _core([robo], "slimes")
	core.begin_turn()
	assert_eq(core.inputs_needed(), [], "an auto-battling actor asks for no command")
	assert_eq(core.actions_needed(0), 0)
	var out := []
	var r := core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	core.end_turn()
	assert_eq(_of(out, robo).size(), 2, "and picks each of its two actions itself")
	# A forced action is the battler's only one that turn (VX Ace's force_action).
	var ace := rules.new_actor_battler("ace")
	core = _core([ace], "slimes")
	assert_true(core.force(ace, {"kind": "guard"}, "turn"))
	var mine := _of(_play(core), ace)
	assert_eq(mine.map(func(x): return str(x.kind)), ["guard"])
	assert_eq(_of(_play(core), ace).size(), 2, "the turn after he has his two again")


func test_escaping_ends_the_battlers_turn() -> void:
	var eric := rules.new_actor_battler("eric")
	var core := _core([eric], "runners")
	var runner: RPGBattler = core.enemies[0]
	var mine := _of(_play(core), runner)
	assert_eq(mine.size(), 1, "one escape, not two")
	assert_eq(str(mine[0].kind), "escape")
	assert_false(runner.is_active(), "it has left the battle")
	# An actor's own command of that kind is not repeated for his other actions either.
	var ace := rules.new_actor_battler("ace")
	core = _core([ace], "slimes")
	core.can_escape = false
	core.begin_turn()
	ace.action = {"kind": "escape"}
	var count := 0
	var r := core.next_action()
	while not r.is_empty():
		if r.user == ace:
			count += 1
		r = core.next_action()
	core.end_turn()
	assert_eq(count, 1)


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func test_the_battle_scene_asks_for_each_command() -> void:
	env = Env.create(tree, "res://rpg")
	var data: RPGProjectData = env.rpg.data
	data.db["actors"].by_id["hero"]["traits"] = [{"kind": "action_times", "value": 100}]
	data.db["classes"].by_id["warrior"]["battle_commands"] = [{"kind": "attack"}, {"kind": "guard"}, {"kind": "row"}]
	env.rpg.state.new_game()
	env.rpg.ui.auto_advance = false
	var rpg: Node = env.rpg
	var out := {}
	var run := func():
		out.r = await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), {"troop": "slimes", "can_escape": true, "can_lose": true},
			{"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)
	run.call()
	var scene: Node = rpg.ui.scene_stack[-1]
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "party"), "the party command opens")
	scene.handle_action("ok")
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "actor"), "the actor command opens")
	var hero: RPGBattler = scene.core.party[0]
	assert_eq(scene.inputs, [0, 0], "the hero is asked twice")
	assert_true(str(scene.log_label.text).ends_with("(1/2)"), str(scene.log_label.text))
	# First command: Guard. The menu comes up again for the second.
	scene.cmd_list.select(1)
	scene.handle_action("ok")
	assert_eq(scene.phase, "actor")
	assert_eq(scene.input_pos, 1)
	assert_true(str(scene.log_label.text).ends_with("(2/2)"), str(scene.log_label.text))
	assert_eq(str(hero.action.get("kind", "")), "guard")
	# Cancel goes back to the first command and takes it back.
	scene.handle_action("cancel")
	assert_eq(scene.input_pos, 0)
	assert_true(hero.action.is_empty(), "the first command is taken back")
	scene.cmd_list.select(1)
	scene.handle_action("ok")
	# Second command: Row.
	assert_eq(hero.row, 0)
	scene.cmd_list.select(2)
	scene.handle_action("ok")
	assert_eq(str(hero.action.get("kind", "")), "guard", "the first command stands")
	assert_eq(str((scene.core._plans.get(hero, [{}]) as Array)[0].get("kind", "")), "row", "the second is stored after it")
	assert_true(await _wait_until(func(): return not is_instance_valid(scene) or hero.row == 1), "the Row command ran as his second action")
	# Let the battle play out.
	if is_instance_valid(scene):
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
