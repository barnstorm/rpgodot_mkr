extends "res://tests/rpg_test_case.gd"
## The 2003 enemy basic actions (#10): how action patterns translate to runtime actions, each
## kind's semantics (double attack, charge, self destruct, escape, observe, transform), the
## switch_on / switch_off toggles, the editor schema and validator, and the battle scene wiring.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")
const Env := preload("res://tests/rpg_test_env.gd")

const BASICS := ["attack", "double_attack", "guard", "observe", "charge", "self_destruct", "escape", "transform", "wait"]

var db
var rules: RPGRuleSystem
var env


func before_each() -> void:
	db = FakeDB.from_folder("res://rpg/database")
	rules = RPGRuleSystem.load_rules("classic", db)
	_pin_damage()


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


## Flat damage (the attacker's ATK, no variance, no misses) so exact values can be asserted.
func _pin_damage() -> void:
	for key in ["attack", "self_destruct"]:
		var d: Dictionary = rules.definition[key]
		d.formula = "a.atk" if key == "attack" else "a.hp"
		d.hit = 100
		d.hit_type = "certain"
		d.variance = 0
		d.critical = false


func _core(party_ids: Array, troop: Variant, rng_seed := 1) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var t: Dictionary = troop if troop is Dictionary else db.record("troops", str(troop))
	var core := RPGBattleCore.new(party, t, rules, RPGRandom.new(rng_seed))
	core.start()
	return core


func _troop(enemy_ids: Array) -> Dictionary:
	return {"id": "t", "members": enemy_ids.map(func(id): return {"enemy": id})}


## An enemy record with one action pattern, so the AI choice is deterministic.
func _enemy(id: String, action: Dictionary, stats := {"agi": 99, "atk": 7, "dex": 6, "int": 2, "mdef": 2, "mhp": 500, "msp": 0, "pdef": 4, "str": 8}, exp := 0, gold := 0) -> Dictionary:
	var pattern := action.duplicate()
	pattern.merge({"condition": {"kind": "always"}, "rating": 5}, false)
	db.add("enemies", {"id": id, "name": id.capitalize(), "stats": stats, "exp": exp, "gold": gold, "drops": [],
		"actions": [pattern]})
	return db.record("enemies", id)


## Runs every queued action of the current turn; returns the results in order.
func _turn(core: RPGBattleCore) -> Array:
	var out := []
	var r := core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	return out


func _of(results: Array, b: RPGBattler) -> Dictionary:
	for r in results:
		if r.user == b:
			return r
	return {}


# --- action patterns -------------------------------------------------------------------------------


func test_patterns_translate_to_runtime_actions() -> void:
	_enemy("shifter", {"skill": "transform", "enemy": "ghost"})
	var core := _core(["hero"], _troop(["shifter"]))
	assert_eq(core._enemy_action_dict({"skill": "attack"}), {"kind": "attack", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "double_attack"}), {"kind": "attack", "times": 2, "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "guard"}), {"kind": "guard", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "observe"}), {"kind": "observe", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "charge"}), {"kind": "charge", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "self_destruct"}), {"kind": "self_destruct", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "escape"}), {"kind": "escape", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "transform", "enemy": "bat"}), {"kind": "transform", "enemy": "bat", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "wait"}), {"kind": "wait", "target": -1})
	assert_eq(core._enemy_action_dict({"skill": "fire"}), {"kind": "skill", "skill": "fire", "target": -1}, "anything else is a skill")
	assert_eq(core._enemy_action_dict({"skill": "attack", "switch_on": "phase_two", "switch_off": "intro"}),
		{"kind": "attack", "target": -1, "switch_on": "phase_two", "switch_off": "intro"}, "the toggles ride along")
	assert_eq(core._enemy_action_dict({"skill": "observe", "switch_on": ""}), {"kind": "observe", "target": -1}, "empty toggles do not")
	# A transform to a record that does not exist can never be chosen.
	for i in 10:
		assert_eq(core.choose_enemy_action(core.enemies[0]).kind, "attack", "the broken transform is skipped")


# --- the kinds -------------------------------------------------------------------------------------


func test_double_attack_hits_twice() -> void:
	_enemy("twin", {"skill": "double_attack"}, {"agi": 99, "atk": 7, "dex": 6, "int": 2, "mdef": 2, "mhp": 300, "msp": 0, "pdef": 4, "str": 8})
	var core := _core(["hero"], _troop(["twin"]))
	var hero: RPGBattler = core.party[0]
	var hp0 := hero.get_resource("hp")
	var twin: RPGBattler = core.enemies[0]
	var chosen := core.choose_enemy_action(twin)
	assert_eq(chosen.kind, "attack", "double attack is an attack")
	assert_eq(chosen.times, 2, "that hits twice")
	core.begin_turn()
	var res := _of(_turn(core), twin)
	assert_eq(res.effects.size(), 2, "two hits on the hero")
	assert_eq(hero.get_resource("hp"), hp0 - 14, "7 ATK, twice")
	core.end_turn()


func test_charge_up_doubles_the_next_attack() -> void:
	# The 2003 pattern way: Charge Up on turn 1, attacks after (2003 conditions on patterns).
	db.add("enemies", {"id": "charger", "name": "Charger", "exp": 0, "gold": 0, "drops": [],
		"stats": {"agi": 99, "atk": 7, "dex": 6, "int": 2, "mdef": 2, "mhp": 500, "msp": 0, "pdef": 4, "str": 8},
		"actions": [
			{"skill": "charge", "condition": {"kind": "turn", "n": 1}, "rating": 5},
			{"skill": "attack", "condition": {"kind": "turn", "n": 2, "every": 1}, "rating": 5}]})
	var core := _core(["hero"], _troop(["charger"]))
	var hero: RPGBattler = core.party[0]
	var charger: RPGBattler = core.enemies[0]
	var hp0 := hero.get_resource("hp")
	core.begin_turn()
	var r1 := _of(_turn(core), charger)
	assert_eq(r1.kind, "charge")
	assert_eq(r1.effects, [], "charging does no damage")
	assert_eq(hero.get_resource("hp"), hp0, "the hero is untouched")
	assert_eq(str(r1.lines[0]), "Charger is charging up!")
	core.end_turn()
	# The stored charge doubles every hit of the next attack...
	core.begin_turn()
	_turn(core)
	assert_eq(hero.get_resource("hp"), hp0 - 14, "7 ATK x 2")
	core.end_turn()
	# ...then it is spent.
	core.begin_turn()
	_turn(core)
	assert_eq(hero.get_resource("hp"), hp0 - 21, "the charge is spent after one attack")
	core.end_turn()


func test_self_destruct_trades_life_for_damage() -> void:
	_enemy("bomber", {"skill": "self_destruct"}, {"agi": 99, "atk": 5, "dex": 6, "int": 2, "mdef": 2, "mhp": 25, "msp": 0, "pdef": 4, "str": 8}, 6, 8)
	var core := _core(["hero"], _troop(["bomber"]))
	var hero: RPGBattler = core.party[0]
	var bomber: RPGBattler = core.enemies[0]
	var hp0 := hero.get_resource("hp")
	assert_eq(core.choose_enemy_action(bomber).kind, "self_destruct", "the AI picks the basic action from the pattern")
	core.begin_turn()
	var res := _of(_turn(core), bomber)
	assert_eq(res.targets, [hero], "the blast hits the party")
	assert_eq(hero.get_resource("hp"), hp0 - 25, "the damage is the monster's remaining HP")
	assert_true(bomber.is_dead(), "the bomber falls with its blast")
	assert_eq(res.battle_over, "win", "a lone self-destructor ends the battle")
	assert_eq(core.rewards().exp, 6, "it still counts for rewards (a normal death)")
	assert_eq(core.rewards().gold, 8)


func test_escape_leaves_the_battle_without_rewards() -> void:
	_enemy("runner", {"skill": "escape"})
	_enemy("sitter", {"skill": "observe"}, {"agi": 1, "atk": 1, "dex": 6, "int": 2, "mdef": 2, "mhp": 500, "msp": 0, "pdef": 4, "str": 8}, 4, 4)
	var core := _core(["hero"], _troop(["runner", "sitter"]))
	var runner: RPGBattler = core.enemies[0]
	core.begin_turn()
	var res := _of(_turn(core), runner)
	assert_true(runner.escaped, "the runner is out of the battle")
	assert_eq(res.get("fled", []), [runner])
	assert_false(res.escaped, "an enemy fleeing is not the party escaping")
	assert_eq(res.battle_over, "", "the sitter keeps fighting")
	assert_eq(str(res.lines[0]), "Runner flees!")
	core.end_turn()
	# Finish the fight: the runner gives no exp, no gold.
	core.enemies[1].set_resource("hp", 0)
	assert_eq(core.battle_over(), "win")
	assert_eq(core.rewards().exp, 4, "only the sitter counts")
	assert_eq(core.rewards().gold, 4)


func test_observe_does_nothing_and_toggles_switches() -> void:
	_enemy("watcher", {"skill": "observe", "switch_on": "phase_two", "switch_off": "intro"})
	var core := _core(["hero"], _troop(["watcher"]))
	var switches := {}
	core.switch_setter = func(id: String, value: bool) -> void: switches[id] = value
	var watcher: RPGBattler = core.enemies[0]
	core.begin_turn()
	var res := _of(_turn(core), watcher)
	assert_eq(res.effects, [], "observing changes nothing")
	assert_eq(str(res.lines[0]), "Watcher is observing.")
	assert_eq(switches, {"phase_two": true, "intro": false}, "the toggles fire once the action has run")
	core.end_turn()
	# Without a setter the toggles are skipped, not an error.
	core.switch_setter = Callable()
	core.begin_turn()
	core.enemies[0].action = {"kind": "attack", "target": -1, "switch_on": "solo"}
	_turn(core)
	assert_false(switches.has("solo"))


func test_transform_action_becomes_the_new_record() -> void:
	_enemy("caterpillar", {"skill": "transform", "enemy": "butterfly"}, {"agi": 99, "atk": 1, "dex": 6, "int": 2, "mdef": 2, "mhp": 60, "msp": 0, "pdef": 4, "str": 8}, 1, 1)
	_enemy("butterfly", {"skill": "attack"}, {"agi": 20, "atk": 12, "dex": 6, "int": 2, "mdef": 2, "mhp": 30, "msp": 0, "pdef": 4, "str": 8}, 20, 30)
	var core := _core(["hero"], _troop(["caterpillar", "caterpillar"]))
	var seen: Array = []
	core.enemy_transformed.connect(func(old_b: RPGBattler, new_b: RPGBattler): seen.append([old_b, new_b]))
	var first: RPGBattler = core.enemies[0]
	var second: RPGBattler = core.enemies[1]
	var pos := first.screen_position
	first.set_resource("hp", 50)   # above the butterfly's maximum: keep clamps
	second.set_resource("hp", 60)
	assert_eq(core.choose_enemy_action(first).kind, "transform")
	core.begin_turn()
	var results := _turn(core)
	assert_eq(seen.size(), 2, "both members transform")
	var pair: Array = seen.filter(func(s): return s[0] == first)
	assert_eq(pair.size(), 1)
	var nb: RPGBattler = pair[0][1]
	assert_eq(core.enemies[0], nb, "the member is replaced in place, at its index")
	assert_eq(_of(results, first).get("transformed", null), nb)
	assert_eq(nb.id, "butterfly")
	assert_eq(nb.name, "Butterfly A", "the A/B suffix stays")
	assert_eq(core.enemies[1].name, "Butterfly B")
	assert_eq(nb.screen_position, pos, "the slot on screen is kept")
	assert_eq(nb.get_resource("hp"), 30, "keep mode: the HP carries over, clamped to the new max")
	core.end_turn()
	# Rewards come from the new record.
	core.enemies[0].set_resource("hp", 0)
	core.enemies[1].set_resource("hp", 0)
	assert_eq(core.battle_over(), "win")
	assert_eq(core.rewards().exp, 40, "two butterflies, not two caterpillars")
	assert_eq(core.rewards().gold, 60)


func test_transform_enemy_hp_modes_states_and_misses() -> void:
	var core := _core(["hero"], _troop(["slime", "bat"]))
	var slime: RPGBattler = core.enemies[0]
	slime.set_resource("hp", 10)          # a quarter of 40
	rules.add_state(slime, "poison")
	# keep: the value, clamped to the new maximum.
	var kept := core.transform_enemy(0, "bat")
	assert_ne(kept, null)
	assert_eq(kept.get_resource("hp"), 10)
	assert_true(kept.has_state("poison"), "states carry over")
	# percent: the ratio, not the value.
	kept.set_resource("hp", 15)           # half of the bat's 30
	var pct := core.transform_enemy(0, "goblin", "percent", true)
	assert_eq(pct.get_resource("hp"), 75, "half of the goblin's 150")
	assert_false(pct.has_state("poison"), "clear_states drops them")
	# anything else refills.
	var full := core.transform_enemy(0, "slime", "refill")
	assert_eq(full.get_resource("hp"), 40, "the new record's maximum")
	# A missing member or record transforms nothing.
	assert_eq(core.transform_enemy(9, "slime"), null)
	assert_eq(core.transform_enemy(0, "ghost"), null)
	assert_eq(core.enemies[0], full, "a failed transform leaves the member alone")


# --- editor: schema and validator -----------------------------------------------------------------


func test_schema_knows_the_basic_actions_and_toggles() -> void:
	var actions: Dictionary = RPGRecordSchemas.fields_for("enemies").filter(func(f): return f.key == "actions")[0]
	var by_key := {}
	for f in actions.item_fields:
		by_key[f.key] = f
	var skill: Dictionary = by_key.skill
	assert_eq(skill.get("ref"), "skill")
	assert_eq((skill.allow as Array).size(), BASICS.size(), "the 2003 basic actions sit beside the skills")
	for b in BASICS:
		assert_true((skill.allow as Array).has(b), b)
	var becomes: Dictionary = by_key.enemy
	assert_eq(becomes.get("ref"), "enemy")
	assert_eq(becomes.show_if, {"key": "skill", "equals": "transform"}, "the Becomes field only shows for Transform")
	for skey in ["switch_on", "switch_off"]:
		var f: Dictionary = by_key[skey]
		assert_eq(f.get("ref"), "switch", skey)


func test_validator_checks_the_new_references() -> void:
	env = Env.create(tree, "res://rpg")
	var data: RPGProjectData = env.rpg.data
	data.db.enemies.records[0]["actions"] = [
		{"skill": "double_attack", "rating": 5},
		{"skill": "transform", "enemy": "ghost_enemy", "rating": 5},
		{"skill": "attack", "switch_on": "ghost_switch", "rating": 5}]
	var msgs := RPGValidator.references(data, env.rpg.registry).map(func(p): return str(p.message))
	assert_false(msgs.any(func(m): return m.contains("double_attack")), "a basic action is not a skill ref: %s" % str(msgs))
	assert_true(msgs.any(func(m): return m.contains("ghost_enemy")), "transform names an enemy record")
	assert_true(msgs.any(func(m): return m.contains("ghost_switch")), "the switch toggles are checked")
	# Everything existing: no complaints about the actions.
	data.db.enemies.records[0]["actions"] = [
		{"skill": "transform", "enemy": "bat", "switch_on": "rain", "switch_off": "intro_done", "rating": 5}]
	var clean := RPGValidator.references(data, env.rpg.registry).map(func(p): return str(p.message))
	assert_false(clean.any(func(m): return m.contains("actions")), "real records pass: %s" % str(clean))


# --- the battle scene -------------------------------------------------------------------------------


func test_scene_transforms_and_toggles_through_the_state() -> void:
	env = Env.create(tree, "res://rpg")
	var data: RPGProjectData = env.rpg.data
	var molt := {"id": "molt", "name": "Molt", "notes": "", "battler": "", "battler_hue": 0, "custom": {}, "drops": [],
		"exp": 2, "gold": 2, "level": 1, "traits": [],
		"stats": {"agi": 99, "atk": 1, "dex": 6, "int": 2, "mdef": 2, "mhp": 200, "msp": 0, "pdef": 4, "str": 8},
		"actions": [{"condition": {"kind": "always"}, "rating": 5, "skill": "transform", "enemy": "bat",
			"switch_on": "goblin_defeated", "switch_off": "intro_done"}]}
	data.db["enemies"].by_id[molt.id] = molt
	data.db["enemies"].records.append(molt)
	var troop := {"id": "molters", "name": "Molters", "can_escape": true, "pages": [],
		"members": [{"enemy": "molt", "hidden": false, "position": [160, 150]}]}
	data.db["troops"].by_id[troop.id] = troop
	data.db["troops"].records.append(troop)
	env.rpg.state.set_switch("intro_done", true)
	var out := {}
	var run := func():
		out.r = await env.rpg.ui.run_contract_scene(env.rpg.ui.scene_path("battle"), {"troop": "molters", "auto": true},
			{"rpg": env.rpg, "state": env.rpg.state, "rules": env.rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)
	run.call()
	assert_true(await _wait_until(func(): return env.rpg.ui.scene_stack.size() > 0 and env.rpg.ui.scene_stack[-1].core != null))
	var scene: Node = env.rpg.ui.scene_stack[-1]
	var old: RPGBattler = scene.core.enemies[0]
	assert_eq(old.id, "molt")
	assert_true(scene.enemy_nodes.has(old), "the old sprite is up")
	# The transform runs; the sprite is rebuilt for the new record, in place.
	assert_true(await _wait_until(func(): return scene.core != null and not scene.core.enemies.is_empty() and scene.core.enemies[0].id == "bat"))
	var nb: RPGBattler = scene.core.enemies[0]
	assert_true(await _wait_until(func(): return scene.enemy_nodes.has(nb) and not scene.enemy_nodes.has(old)))
	assert_eq(nb.name, "Bat")
	# The toggles went through the scene's wiring into the game state.
	assert_true(env.rpg.state.get_switch("goblin_defeated"), "switch_on ran")
	assert_false(env.rpg.state.get_switch("intro_done"), "switch_off ran")
	await _wait_until(func(): return out.has("r"))
	assert_eq(out.r.status, "finished")
	assert_eq(out.r.value.outcome, "win", "the hero beats the butterfly it became")
	assert_eq(out.r.value.rewards.exp, 5, "the bat's exp")


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()
