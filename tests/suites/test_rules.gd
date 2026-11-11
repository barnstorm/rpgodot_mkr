extends "res://tests/rpg_test_case.gd"
## RPGRuleSystem with the Classic rules and the sample database, the OSR example, and a
## rules.gd override.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.from_folder("res://rpg/database")
	# Deterministic helper skills for exact damage checks.
	db.add("skills", {"id": "test_hit", "name": "Test Hit", "formula": "a.atk - b.pdef / 2", "hit": 100,
		"hit_type": "certain", "variance": 0, "scope": "one_enemy", "damage_type": "damage"})
	db.add("skills", {"id": "test_fire", "name": "Test Fire", "formula": "10", "element": "fire",
		"hit_type": "certain", "variance": 0, "scope": "one_enemy"})
	db.add("skills", {"id": "never_hits", "name": "Whiff", "formula": "10", "hit": 0,
		"hit_type": "physical", "variance": 0, "scope": "one_enemy"})
	db.add("skills", {"id": "bad_formula", "name": "Broken", "formula": "a.atk / 0",
		"hit_type": "certain", "scope": "one_enemy"})
	db.add("skills", {"id": "sleep_spell", "name": "Sleep", "hit_type": "certain", "scope": "one_enemy",
		"effects": [{"kind": "add_state", "id": "sleep", "chance": 100}]})
	rules = RPGRuleSystem.load_rules("classic", db)
	rules.rng = RPGRandom.new(1234)


func test_load_and_declarations() -> void:
	assert_true(rules != null, "classic loads")
	assert_eq(rules.rules_id, "classic")
	var ids := []
	for s in rules.stats():
		ids.append(s.id)
	assert_eq(ids, ["mhp", "msp", "str", "dex", "agi", "int", "atk", "pdef", "mdef"])
	assert_eq(rules.resources().size(), 2)
	for cap in ["turn_order", "action_selection", "target_choice", "battle_events", "escape", "defeat"]:
		assert_has(rules.capabilities(), cap)
	assert_eq(rules.validate(), [], "shipped rules validate")
	var shipped := RPGRuleSystem.load_rules_from_dir("res://addons/rpg/runtime/rules/classic", db)
	assert_eq(shipped.definition, rules.definition, "sample copy matches the shipped classic rules")


func test_validate_reports_bad_formulas() -> void:
	var rs := RPGRuleSystem.new()
	rs.setup({"id": "bad", "stats": [], "resources": [{"id": "hp"}], "attack": {"formula": "a.atk +"},
		"hit_check": {"physical": {"type": "percent", "steps": ["OS.execute('x')"]}}}, db)
	var problems := rs.validate()
	assert_eq(problems.size(), 2, str(problems))


func test_classic_actor_stats() -> void:
	var hero := rules.new_actor_battler("hero")
	assert_eq(hero.name, "Alex")
	assert_eq(hero.level, 1)
	assert_eq(rules.effective_stat(hero, "mhp"), 120)
	assert_eq(rules.effective_stat(hero, "atk"), 14, "class 4 + bronze sword 10")
	assert_eq(rules.effective_stat(hero, "pdef"), 10, "class 6 + leather 4")
	assert_eq(rules.effective_stat(hero, "mdef"), 5)
	assert_eq(hero.get_resource("hp"), 120)
	assert_eq(hero.get_resource("sp"), 10)
	var hero5 := rules.new_actor_battler("hero", 5)
	assert_eq(rules.max_resource(hero5, "hp"), 220)
	assert_eq(hero5.exp, rules.exp_for_level("warrior", 5))
	assert_has(hero5.skills, "power_strike", "learned at level 3")
	hero.equips.weapon = "iron_sword"
	assert_eq(rules.effective_stat(hero, "atk"), 26)
	assert_eq(rules.effective_stat(hero, "dex"), 14)
	var mira := rules.new_actor_battler("mira")
	assert_eq(mira.skills, ["heal", "fire"])
	var snap := hero.snapshot()
	assert_eq(snap.atk, 26)
	assert_eq(snap.hp, 120)
	assert_eq(snap.max_hp, 120)
	assert_eq(snap.stats.atk, 26)


func test_traits_and_states() -> void:
	var hero := rules.new_actor_battler("hero")
	var slime := rules.new_enemy_battler("slime")
	assert_eq(rules.effective_stat(slime, "mhp"), 40)
	assert_eq(rules.trait_rate(slime, "element_rate", "fire"), 1.5)
	assert_eq(rules.attack_element(hero), "physical", "from bronze sword")
	assert_eq(rules.state_chance_rate(hero, "sleep"), 0.5, "warrior class trait")
	assert_true(rules.add_state(hero, "sleep"))
	assert_eq(rules.effective_stat(hero, "agi"), 5, "sleep halves AGI")
	assert_false(rules.can_act(hero))
	var st: Dictionary = hero.states[0]
	assert_true(st.turns >= 2 and st.turns <= 4)
	rules.end_battle(hero)
	assert_false(hero.has_state("sleep"), "removed at battle end")
	rules.add_state(hero, "poison")
	var tick := rules.tick_states(hero)
	assert_eq(tick.damage, 12, "poison 10% of 120")
	assert_eq(hero.get_resource("hp"), 108)
	hero.set_resource("hp", 1)
	rules.tick_states(hero)
	assert_eq(hero.get_resource("hp"), 1, "poison does not kill")


func test_damage_guard_element() -> void:
	var hero := rules.new_actor_battler("hero")
	var slime := rules.new_enemy_battler("slime")
	var d := rules.damage(hero, slime, {"kind": "skill", "skill": "test_hit"})
	assert_true(d.ok)
	assert_eq(d.value, 12, "14 - 4 / 2")
	slime.guarding = true
	assert_eq(rules.damage(hero, slime, {"kind": "skill", "skill": "test_hit"}).value, 6, "guard halves")
	slime.guarding = false
	var f := rules.damage(hero, slime, {"kind": "skill", "skill": "test_fire"})
	assert_eq(f.value, 15, "fire x1.5 against slime")
	# The real attack: 14 + 14/2 - 4/2 = 19, 15% variance, critical doubles.
	for i in 50:
		var a := rules.damage(hero, slime, {"kind": "attack"})
		var lo := 33 if a.critical else 17
		var hi := 43 if a.critical else 21
		assert_true(a.value >= lo and a.value <= hi, "attack damage %d in %d..%d" % [a.value, lo, hi])
	assert_true(rules.damage(hero, slime, {"kind": "attack"}).value is int, "damage is an int")


func test_hit_and_apply_action() -> void:
	var hero := rules.new_actor_battler("hero")
	var slime := rules.new_enemy_battler("slime")
	var miss := rules.apply_action(hero, slime, {"kind": "skill", "skill": "never_hits"})
	assert_false(miss.hit)
	assert_eq(slime.get_resource("hp"), 40)
	assert_true(miss.text.contains("missed"))
	var hits := 0
	for i in 100:
		if rules.hit_check(hero, slime, {"kind": "attack"}).hit:
			hits += 1
	assert_true(hits > 75 and hits < 100, "attack hits most of the time (%d/100)" % hits)
	var r := rules.apply_action(hero, slime, {"kind": "skill", "skill": "test_hit"})
	assert_true(r.hit)
	assert_eq(r.damage, 12)
	assert_eq(slime.get_resource("hp"), 28)
	assert_eq(r.changes, {"hp": -12})
	assert_true(r.text.contains("12"), r.text)
	slime.set_resource("hp", 5)
	var k := rules.apply_action(hero, slime, {"kind": "skill", "skill": "test_hit"})
	assert_true(k.knocked_out)
	assert_has(k.added_states, "knockout")
	assert_true(slime.is_dead())
	assert_eq(slime.get_resource("hp"), 0)
	var again := rules.apply_action(hero, slime, {"kind": "skill", "skill": "test_hit"})
	assert_false(again.hit, "dead targets are skipped")
	# Sleep wakes up when damaged.
	var slime2 := rules.new_enemy_battler("slime")
	rules.apply_action(hero, slime2, {"kind": "skill", "skill": "sleep_spell"})
	assert_true(slime2.has_state("sleep"))
	var w := rules.apply_action(hero, slime2, {"kind": "skill", "skill": "test_hit"})
	assert_has(w.removed_states, "sleep")


func test_formula_errors_are_reported() -> void:
	var hero := rules.new_actor_battler("hero")
	var slime := rules.new_enemy_battler("slime")
	rules.report_errors = false
	var r := rules.apply_action(hero, slime, {"kind": "skill", "skill": "bad_formula"})
	assert_true(r.error.contains("division by zero"), r.error)
	assert_true(r.error.contains("bad_formula"), "names the record")
	assert_true(r.error.contains("a.atk / 0"), "names the formula")
	assert_eq(slime.get_resource("hp"), 40, "no damage applied")


func test_items_and_healing() -> void:
	var hero := rules.new_actor_battler("hero")
	var mira := rules.new_actor_battler("mira")
	hero.set_resource("hp", 50)
	var p := rules.use_item(hero, hero, "potion")
	assert_eq(hero.get_resource("hp"), 100)
	assert_eq(p.recovered, 50)
	rules.use_item(hero, hero, "hi_potion")
	assert_eq(hero.get_resource("hp"), 120, "capped at max")
	hero.set_resource("hp", 50)
	assert_true(rules.can_use(mira, {"kind": "skill", "skill": "heal"}))
	rules.pay_cost(mira, {"kind": "skill", "skill": "heal"})
	assert_eq(mira.get_resource("sp"), 35)
	var h := rules.apply_action(mira, hero, {"kind": "skill", "skill": "heal"})
	assert_true(h.recovered >= 47 and h.recovered <= 57, "heal 52 +-10%%, got %d" % h.recovered)
	rules.add_state(hero, "poison")
	var a := rules.use_item(hero, hero, "antidote")
	assert_has(a.removed_states, "poison")
	assert_false(hero.has_state("poison"))
	mira.set_resource("sp", 2)
	assert_false(rules.can_use(mira, {"kind": "skill", "skill": "fire"}), "not enough SP")


func test_exp_curve_and_level_up() -> void:
	assert_eq(rules.exp_for_level("warrior", 1), 0)
	assert_eq(rules.exp_for_level("warrior", 2), 25)
	assert_eq(rules.exp_for_level("warrior", 3), 65)
	var prev := 0
	for lv in range(2, 100):
		var e := rules.exp_for_level("warrior", lv)
		assert_true(e > prev, "curve rises at level %d" % lv)
		prev = e
	assert_true(rules.exp_for_level("mage", 10) > rules.exp_for_level("warrior", 10), "class curve overrides")
	var hero := rules.new_actor_battler("hero")
	var ups := rules.gain_exp(hero, 70)
	assert_eq(hero.level, 3)
	assert_eq(ups.size(), 2)
	assert_eq(ups[0].level, 2)
	assert_eq(ups[0].gains.mhp, 25)
	assert_eq(ups[1].learned, ["power_strike"])
	assert_eq(rules.gain_exp(hero, 1), [], "no level up")


func test_roll_check() -> void:
	var hero := rules.new_actor_battler("hero")
	var easy := rules.roll_check(hero, {"stat": "str", "dc": 1})
	assert_true(easy.success)
	assert_true(easy.roll >= 3 and easy.roll <= 22, "1d20 + 14/5")
	assert_false(rules.roll_check(hero, {"stat": "str", "dc": 100}).success)
	assert_true(rules.roll_check(hero, {"formula": "a.str >= 10"}).success)
	assert_false(rules.roll_check(hero, {"formula": "a.str + 1", "dc": 20}).success)
	assert_true(rules.roll_check(hero, {"stat": "str", "dc": "a.level"}).success, "dc may be a formula")
	rules.report_errors = false
	assert_true(rules.roll_check(hero, {"stat": "luck", "dc": 1}).error != "")
	rules.report_errors = true
	# Same seed, same rolls.
	var r1 := RPGRuleSystem.load_rules("classic", db)
	var r2 := RPGRuleSystem.load_rules("classic", db)
	r1.rng = RPGRandom.new(5)
	r2.rng = RPGRandom.new(5)
	for i in 10:
		assert_eq(r1.roll_check(hero, {"stat": "dex", "dc": 12}), r2.roll_check(hero, {"stat": "dex", "dc": 12}))


func test_escape_chance() -> void:
	var hero := rules.new_actor_battler("hero")
	var slime := rules.new_enemy_battler("slime")
	var bat := rules.new_enemy_battler("bat")
	assert_eq(rules.escape_chance([hero], [slime]), 83, "50 * 10 / 6")
	assert_eq(rules.escape_chance([hero], [bat]), 35, "50 * 10 / 14")


func test_battler_roundtrip() -> void:
	var hero := rules.new_actor_battler("hero", 4)
	rules.add_state(hero, "poison")
	hero.set_resource("hp", 77)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(hero.to_dict()))
	var back := RPGBattler.from_dict(RPGJson.normalise(saved))
	rules.attach(back)
	assert_eq(back.to_dict(), hero.to_dict())
	assert_eq(rules.effective_stat(back, "mhp"), rules.effective_stat(hero, "mhp"))
	assert_true(back.has_state("poison"))
	assert_true(back.snapshot().has("atk"))


func test_osr_example_rules() -> void:
	var odb = FakeDB.new()
	odb.add("classes", {"id": "fighter", "name": "Fighter", "hit_die": 8, "exp_table": [0, 2000, 4000, 8000, 16000]})
	odb.add("actors", {"id": "bran", "name": "Bran", "class": "fighter", "initial_level": 1,
		"base_stats": {"str": 16, "dex": 13, "con": 14, "int": 9, "wis": 10, "cha": 11},
		"equips": {"weapon": "long_sword", "body": "chain_mail"}})
	odb.add("weapons", {"id": "long_sword", "name": "Long sword", "dice": "1d8", "params": {}})
	odb.add("armors", {"id": "chain_mail", "name": "Chain mail", "params": {"ac": 4}})
	odb.add("enemies", {"id": "orc", "name": "Orc", "dice": "1d6",
		"stats": {"str": 13, "dex": 10, "con": 12, "int": 7, "wis": 8, "cha": 6, "mhp": 6, "ac": 13}})
	var osr := RPGRuleSystem.load_rules("osr_example", odb)
	assert_true(osr != null)
	assert_eq(osr.validate(), [])
	osr.rng = RPGRandom.new(77)
	var bran := osr.new_actor_battler("bran")
	assert_eq(osr.effective_stat(bran, "ac"), 15, "10 + mod(13) + chain 4")
	assert_eq(osr.effective_stat(bran, "mhp"), 10, "hit die 8 + mod(14)")
	assert_eq(osr.effective_stat(bran, "attack_bonus"), 1)
	assert_eq(bran.get_resource("hp"), 10)
	assert_eq(bran.snapshot().weapon_dice, "1d8")
	var orc := osr.new_enemy_battler("orc")
	assert_eq(osr.effective_stat(orc, "ac"), 13, "enemy states AC directly")
	assert_eq(orc.snapshot().weapon_dice, "1d6")
	var hits := 0
	var misses := 0
	for i in 60:
		orc.set_resource("hp", 6)
		orc.states.clear()
		var h := osr.hit_check(bran, orc, {"kind": "attack"})
		assert_true(h.natural >= 1 and h.natural <= 20)
		var r := osr.apply_action(bran, orc, {"kind": "attack"})
		if r.hit:
			hits += 1
			var hi := 22 if r.critical else 11
			assert_true(r.damage >= 4 and r.damage <= hi, "1d8 + 3 (x2 on a natural 20), got %d" % r.damage)
		else:
			misses += 1
	assert_true(hits > 0 and misses > 0, "d20 vs AC both hits and misses (%d/%d)" % [hits, misses])
	assert_eq(osr.exp_for_level("fighter", 3), 4000)
	assert_eq(osr.exp_for_level("fighter", 7), 32000, "past the table: last step repeats")
	var ups := osr.gain_exp(bran, 2000)
	assert_eq(bran.level, 2)
	var gain: int = ups[0].gains.mhp
	assert_true(gain >= 3 and gain <= 10, "1d8 + 2 hit points, got %d" % gain)
	assert_eq(osr.effective_stat(bran, "attack_bonus"), 2)
	var chk := osr.roll_check(bran, {"stat": "str", "dc": 10})
	assert_true(chk.natural >= 1 and chk.natural <= 20)
	assert_eq(chk.roll, chk.natural + 3)
	assert_eq(osr.escape_chance([bran], [orc]), 50)


func test_rules_gd_override() -> void:
	var rs := RPGRuleSystem.load_rules_from_dir("res://tests/fixtures/rules/override_test", db)
	assert_true(rs != null, "override loads")
	assert_true(rs is RPGRuleSystem)
	assert_true(rs.get_script().resource_path.ends_with("rules.gd"), "the project script is used")
	var a := RPGBattler.new()
	rs.attach(a)
	a.kind = "enemy"
	a.base = {"mhp": 50, "atk": 30, "pdef": 0, "agi": 5}
	rs.recover_all(a)
	var b := RPGBattler.new()
	rs.attach(b)
	b.kind = "enemy"
	b.base = {"mhp": 50, "atk": 1, "pdef": 0, "agi": 5}
	rs.recover_all(b)
	var r := rs.apply_action(a, b, {"kind": "attack"})
	assert_eq(r.damage, 7, "overridden damage step is used by apply_action")
	assert_eq(b.get_resource("hp"), 43)



## D4: every effect kind the Database offers does something: damage, grow, learn skill,
## chances on add / remove state, and common events (run once, after the action).
func test_d4_effect_kinds() -> void:
	db.add("skills", {"id": "acid", "name": "Acid", "hit_type": "certain", "scope": "one_enemy",
		"effects": [{"kind": "damage", "resource": "hp", "amount": 5, "percent": 10}]})
	db.add("items", {"id": "power_seed", "name": "Power Seed", "scope": "one_ally",
		"effects": [{"kind": "grow", "id": "atk", "amount": 3}]})
	db.add("items", {"id": "fire_book", "name": "Fire Book", "scope": "one_ally",
		"effects": [{"kind": "learn_skill", "id": "power_strike"}]})
	db.add("items", {"id": "whistle", "name": "Whistle", "scope": "one_ally",
		"effects": [{"kind": "common_event", "id": "heal_party"}, {"kind": "recover", "resource": "hp", "amount": 1}]})
	db.add("skills", {"id": "never_sleep", "name": "Dud", "hit_type": "certain", "scope": "one_enemy",
		"effects": [{"kind": "add_state", "id": "poison", "chance": 0}]})
	db.add("items", {"id": "weak_cure", "name": "Weak cure", "scope": "one_ally",
		"effects": [{"kind": "remove_state", "id": "poison", "chance": 0}]})
	db.add("skills", {"id": "old_format", "name": "Old", "hit_type": "certain", "scope": "one_enemy",
		"effects": [{"id": "poison", "kind": "add_state", "amount": 60, "resource": null}]})
	var hero := rules.new_actor_battler("hero")
	var slime := rules.new_enemy_battler("slime")
	var r := rules.apply_action(hero, slime, {"kind": "skill", "skill": "acid"})
	assert_eq(slime.get_resource("hp"), 40 - 5 - 4, "damage: flat 5 plus 10% of 40")
	assert_eq(int(r.changes.hp), -9)
	var atk: int = rules.effective_stat(hero, "atk")
	r = rules.use_item(hero, hero, "power_seed")
	assert_eq(rules.effective_stat(hero, "atk"), atk + 3, "grow raises the stat for good")
	assert_true(RPGRuleSystem.had_effect(r))
	assert_true(r.text.contains("went up"), r.text)
	r = rules.use_item(hero, hero, "fire_book")
	assert_has(hero.skills, "power_strike", "learn skill")
	assert_true(RPGRuleSystem.had_effect(r))
	assert_eq(rules.common_events(hero, {"kind": "item", "item": "whistle"}), ["heal_party"])
	assert_eq(rules.common_events(hero, {"kind": "item", "item": "power_seed"}), [])
	r = rules.apply_action(hero, slime, {"kind": "skill", "skill": "never_sleep"})
	assert_false(slime.has_state("poison"), "a 0% chance never adds")
	rules.add_state(hero, "poison")
	rules.use_item(hero, hero, "weak_cure")
	assert_true(hero.has_state("poison"), "a 0% chance never removes")
	# Data saved before the chance field: chance 100 (Amount is not a chance).
	rules.apply_action(hero, slime, {"kind": "skill", "skill": "old_format"})
	assert_true(slime.has_state("poison"))


## D8: a state lasting "0 to 3 turns" always wears off (a roll of 0 ends at the end of that
## turn); "at most 0" lasts until removed.
func test_d8_zero_roll_never_makes_a_state_permanent() -> void:
	db.add("states", {"id": "dizzy", "name": "Dizzy", "turns_min": 0, "turns_max": 3})
	db.add("states", {"id": "cursed", "name": "Cursed", "turns_min": 0, "turns_max": 0})
	for s in 40:
		rules.rng = RPGRandom.new(s)
		var hero := rules.new_actor_battler("hero")
		assert_true(rules.add_state(hero, "dizzy"))
		var turns := int(hero.states[0].turns)
		assert_true(turns >= 1 and turns <= 3, "turns %d" % turns)
		for t in 3:
			rules.tick_states(hero)
		assert_false(hero.has_state("dizzy"), "worn off within 3 turns (seed %d)" % s)
	var h2 := rules.new_actor_battler("hero")
	rules.add_state(h2, "cursed")
	assert_eq(int(h2.states[0].turns), -1, "at most 0: until removed")
