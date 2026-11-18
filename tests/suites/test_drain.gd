extends "res://tests/rpg_test_case.gd"
## The HP Drain / MP Drain damage type (issue #147): the target loses the amount, capped at
## what it has, and the user gains what was taken. Rules, battle core and the battle scene.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")
const Env := preload("res://tests/rpg_test_env.gd")

var db
var rules: RPGRuleSystem
var env


func before_each() -> void:
	db = FakeDB.new()
	db.add("classes", {"id": "mage", "name": "Mage",
		"growth": {"mhp": 500, "mmp": 100, "atk": 20, "def": 10, "mat": 20, "mdf": 10, "agi": 20, "luk": 10}})
	db.add("actors", {"id": "winter", "name": "Winter", "class": "mage", "equips": {}})
	db.add("actors", {"id": "ally", "name": "Ally", "class": "mage", "equips": {}})
	db.add("enemies", {"id": "ogre", "name": "Ogre",
		"stats": {"mhp": 2000, "mmp": 40, "atk": 30, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("enemies", {"id": "bat", "name": "Bat",
		"stats": {"mhp": 80, "mmp": 0, "atk": 10, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("troops", {"id": "ogres", "name": "Ogre", "members": [{"enemy": "ogre", "position": [160, 150]}], "pages": []})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("skills", {"id": "drain", "name": "Drain", "formula": "300", "damage_type": "drain", "resource": "hp",
		"hit_type": "certain", "variance": 0, "scope": "one_enemy"})
	db.add("skills", {"id": "osmose", "name": "Osmose", "formula": "60", "damage_type": "drain", "resource": "mp",
		"hit_type": "certain", "variance": 0, "scope": "one_enemy"})
	db.add("skills", {"id": "bite", "name": "Bite", "formula": "300", "damage_type": "drain", "resource": "hp",
		"hit_type": "physical", "hit": 100, "variance": 0, "critical": true, "scope": "one_enemy"})
	db.add("items", {"id": "leech", "name": "Leech", "formula": "50", "damage_type": "drain", "resource": "hp",
		"hit_type": "certain", "variance": 0, "scope": "one_enemy"})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(77)


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _skill(id: String) -> Dictionary:
	return {"kind": "skill", "skill": id}


func test_hp_drain_takes_from_the_target_and_gives_to_the_user() -> void:
	var winter := rules.new_actor_battler("winter")
	var ogre := rules.new_enemy_battler("ogre")
	winter.set_resource("hp", 100)
	var r := rules.apply_action(winter, ogre, _skill("drain"))
	assert_true(r.hit)
	assert_eq(ogre.get_resource("hp"), 1700, "the target loses the amount")
	assert_eq(winter.get_resource("hp"), 400, "the user gains it")
	assert_eq(r.damage, 300)
	assert_eq(r.get("drained"), {"hp": 300})
	assert_eq(r.changes.get("hp"), -300, "changes are the target's")
	assert_eq(r.recovered, 0)
	assert_eq(r.lines, ["Ogre was drained of 300 HP!"])
	assert_true(RPGRuleSystem.had_effect(r))


func test_hp_drain_is_capped_at_what_the_target_has() -> void:
	var winter := rules.new_actor_battler("winter")
	var bat := rules.new_enemy_battler("bat")
	winter.set_resource("hp", 100)
	var r := rules.apply_action(winter, bat, _skill("drain"))
	assert_eq(r.damage, 80, "80 HP was all it had")
	assert_eq(r.get("drained"), {"hp": 80})
	assert_eq(winter.get_resource("hp"), 180, "the user gains only what was taken")
	assert_true(r.knocked_out, "a drain can knock out")
	assert_true(bat.is_dead())
	assert_eq(r.lines, ["Bat was drained of 80 HP!", "Bat falls!"])


func test_the_users_gain_stops_at_the_maximum() -> void:
	var winter := rules.new_actor_battler("winter")
	var ogre := rules.new_enemy_battler("ogre")
	winter.set_resource("hp", 450)
	var r := rules.apply_action(winter, ogre, _skill("drain"))
	assert_eq(winter.get_resource("hp"), 500)
	assert_eq(ogre.get_resource("hp"), 1700, "the target still loses all of it")
	assert_eq(r.get("drained"), {"hp": 300}, "the result reports what was taken")


func test_mp_drain_moves_mp_and_leaves_hp_alone() -> void:
	var winter := rules.new_actor_battler("winter")
	var ogre := rules.new_enemy_battler("ogre")
	winter.set_resource("mp", 10)
	var r := rules.apply_action(winter, ogre, _skill("osmose"))
	assert_eq(ogre.get_resource("mp"), 0, "the ogre had 40 MP")
	assert_eq(winter.get_resource("mp"), 50)
	assert_eq(ogre.get_resource("hp"), 2000)
	assert_eq(r.get("drained"), {"mp": 40})
	assert_eq(r.changes, {"mp": -40})
	assert_eq(r.lines, ["Ogre was drained of 40 MP!"])
	assert_false(r.knocked_out)
	# Nothing left to take: nothing happens, and the user gains nothing.
	var again := rules.apply_action(winter, ogre, _skill("osmose"))
	assert_false(again.has("drained"))
	assert_eq(winter.get_resource("mp"), 50)
	assert_eq(again.lines, [rules.term("nothing")])
	assert_false(RPGRuleSystem.had_effect(again))


func test_a_drain_is_damage_for_guard_and_criticals() -> void:
	var winter := rules.new_actor_battler("winter")
	var ogre := rules.new_enemy_battler("ogre")
	ogre.guarding = true
	assert_eq(rules.damage(winter, ogre, _skill("drain")).value, 150, "guarding halves a drain")
	ogre.guarding = false
	assert_eq(rules.damage(winter, ogre, _skill("drain")).type, "drain")
	# A physical drain can be critical (x3 under these rules).
	db.add("states", {"id": "focus", "name": "Focus", "traits": [{"kind": "critical_rate", "value": 100}]})
	rules.add_state(winter, "focus")
	var d := rules.damage(winter, ogre, _skill("bite"))
	assert_true(d.critical)
	assert_eq(d.value, 900)


func test_items_drain_too_and_the_classic_rules_as_well() -> void:
	var winter := rules.new_actor_battler("winter")
	var ogre := rules.new_enemy_battler("ogre")
	winter.set_resource("hp", 100)
	var r := rules.use_item(winter, ogre, "leech")
	assert_eq(r.get("drained"), {"hp": 50})
	assert_eq(winter.get_resource("hp"), 150)
	assert_eq(ogre.get_resource("hp"), 1950)
	# The damage type belongs to no rule set: the sample project's classic rules drain as well.
	var cdb = FakeDB.from_folder("res://rpg/database")
	cdb.add("skills", {"id": "drain", "name": "Drain", "formula": "5", "damage_type": "drain", "resource": "hp",
		"hit": 100, "variance": 0, "scope": "one_enemy"})
	var classic := RPGRuleSystem.load_rules("classic", cdb)
	classic.rng = RPGRandom.new(5)
	var hero := classic.new_actor_battler("hero")
	var slime := classic.new_enemy_battler("slime")
	var life := classic.life_resource()
	hero.set_resource(life, 1)
	var before: int = slime.get_resource(life)
	var cr := classic.apply_action(hero, slime, _skill("drain"))
	assert_true(cr.hit)
	assert_eq(slime.get_resource(life), before - 5)
	assert_eq(hero.get_resource(life), 6)


func test_a_drain_in_a_battle_round() -> void:
	var winter := rules.new_actor_battler("winter")
	winter.skills.append("drain")
	winter.set_resource("hp", 100)
	var core := RPGBattleCore.new([winter], db.record("troops", "ogres"), rules, RPGRandom.new(3))
	core.start()
	core.begin_turn()
	core.set_action(0, {"kind": "skill", "skill": "drain", "target": 0})
	var r := core.next_action()
	while not r.is_empty() and r.user != winter:
		r = core.next_action()
	assert_eq(r.user, winter)
	assert_eq(r.effects.size(), 1)
	assert_eq(r.effects[0].result.get("drained"), {"hp": 300})
	assert_has(r.lines, "Ogre A was drained of 300 HP!" if core.enemies[0].name == "Ogre A" else "Ogre was drained of 300 HP!")
	assert_eq(core.enemies[0].get_resource("hp"), 1700)


func test_the_battle_scene_pops_the_gain_up_on_the_user() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	var out := {}
	var run := func():
		out.r = await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), {"troop": "slimes", "can_lose": true},
			{"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)
	run.call()
	var scene: Node = rpg.ui.scene_stack[-1]
	var user: RPGBattler = scene.core.party[0]
	var foe: RPGBattler = scene.core.enemies[0]
	var life: String = rpg.rules.life_resource()
	var result := {"hit": true, "damage": 7, "recovered": 0, "critical": false, "knocked_out": false,
		"changes": {life: -7}, "drained": {life: 7}, "lines": []}
	var shown := {"done": false}
	var show := func():
		await scene.show_action({"user": user, "action": {"kind": "skill"}, "kind": "skill", "lines": ["Hero uses Drain!"],
			"effects": [{"target": foe, "result": result}]})
		shown.done = true
	show.call()
	# The foe's number and the user's gain are both on the screen.
	var texts := {}
	var end := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < end:
		for c in scene.popups.get_children():
			if c is Label:
				texts[c.text] = (texts.get(c.text, []) as Array) + [c.position.x]
		if shown.done:
			break
		await tree.process_frame
	assert_true(shown.done, "the action was shown")
	assert_true(texts.has("7"), "popups seen: %s" % [texts.keys()])
	var points := []
	for p in texts.get("7", []):
		if not points.has(p):
			points.append(p)
	assert_eq(points.size(), 2, "one 7 over the foe and one over the user: %s" % [points])
	# Let the battle end.
	scene.auto = true
	end = Time.get_ticks_msec() + 20000
	while not out.has("r") and Time.get_ticks_msec() < end:
		if is_instance_valid(scene) and scene.core != null and scene.phase != "":
			if scene.phase == "party":
				scene.cmd_list.select(0)
			scene.handle_action("ok")
		await tree.process_frame
	assert_true(out.has("r"), "the battle ends")
