extends "res://tests/rpg_test_case.gd"
## The VX Ace style rule system (rpg/rules/vx_ace): parameter curves, Ace damage formulas,
## HIT/EVA/CRI, TP, Features (skill types, dual wield, seal equip, action times, regen) and the
## basis/extra/acceleration experience curve.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"},
		{"id": "shield", "name": "Shield", "kind": "armor"},
		{"id": "body", "name": "Body", "kind": "armor"},
		{"id": "accessory", "name": "Accessory", "kind": "armor"}]})
	db.add("classes", {"id": "soldier", "name": "Soldier",
		"growth": {
			"mhp": {"at_1": 450, "at_99": 5000, "shape": "linear"},
			"mmp": {"at_1": 80, "at_99": 1000},
			"atk": {"at_1": 20, "at_99": 200, "shape": "late"},
			"def": {"base": 10, "per_level": 2},
			"mat": {"at_1": 20, "at_99": 200, "shape": "early"},
			"mdf": {"at_1": 20, "at_99": 200},
			"agi": {"at_1": 30, "at_99": 230, "shape": 2},
			"luk": {"at_1": 20, "at_99": 120}},
		"traits": [{"kind": "add_skill_type", "id": "magic"}]})
	db.add("classes", {"id": "brawler", "name": "Brawler",
		"growth": {"mhp": 500, "mmp": 100, "atk": 50, "def": 20, "mat": 30, "mdf": 20, "agi": 20, "luk": 10},
		"exp_curve": {"basis": 25, "extra": 15, "acc_a": 20, "acc_b": 40},
		"traits": [{"kind": "dual_wield", "id": "shield"}]})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {}})
	db.add("actors", {"id": "bruno", "name": "Bruno", "class": "brawler",
		"equips": {"weapon": "sword", "shield": "dagger", "body": "plate"}})
	db.add("actors", {"id": "ace", "name": "Ace", "class": "brawler",
		"equips": {"weapon": "sword", "body": "plate"}, "traits": [{"kind": "action_times", "value": 100}]})
	db.add("weapons", {"id": "sword", "name": "Sword", "params": {"atk": 10}})
	db.add("weapons", {"id": "dagger", "name": "Dagger", "params": {"atk": 5}})
	db.add("armors", {"id": "plate", "name": "Plate", "params": {"def": 15}})
	db.add("enemies", {"id": "slime", "name": "Slime", "exp": 10, "gold": 5,
		"stats": {"mhp": 2000, "mmp": 0, "atk": 30, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("enemies", {"id": "ghost", "name": "Ghost",
		"stats": {"mhp": 100, "mmp": 0, "atk": 10, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"traits": [{"kind": "evasion_rate", "value": 100}]})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "regen", "name": "Regen", "traits": [{"kind": "hp_regen", "value": 10}]})
	db.add("states", {"id": "drain", "name": "Drain", "traits": [{"kind": "hp_regen", "value": -10}]})
	db.add("states", {"id": "silence", "name": "Silence", "traits": [{"kind": "seal_skill_type", "id": "magic"}]})
	db.add("states", {"id": "sealed", "name": "Sealed", "traits": [{"kind": "seal_equip", "id": "body"}]})
	db.add("states", {"id": "blind", "name": "Blind", "traits": [{"kind": "hit_rate", "value": 0}]})
	db.add("states", {"id": "focus", "name": "Focus", "traits": [{"kind": "critical_rate", "value": 100}]})
	db.add("states", {"id": "charger", "name": "Charger", "traits": [{"kind": "tp_charge_rate", "value": 200}]})
	db.add("states", {"id": "keep_tp", "name": "Keep TP", "traits": [{"kind": "preserve_tp"}]})
	db.add("skills", {"id": "strike", "name": "Strike", "formula": "a.atk * 4 - b.def * 2", "hit_type": "certain",
		"variance": 0, "scope": "one_enemy"})
	db.add("skills", {"id": "fire", "name": "Fire", "skill_type": "magic", "formula": "100 + a.mat * 2 - b.mdf * 2",
		"hit_type": "magical", "hit": 100, "variance": 0, "cost": {"mp": 5}, "scope": "one_enemy"})
	db.add("skills", {"id": "kick", "name": "Kick", "skill_type": "special", "formula": "10", "hit_type": "certain"})
	db.add("skills", {"id": "heal", "name": "Heal", "skill_type": "magic", "formula": "200 + a.mat", "damage_type": "recover",
		"hit_type": "certain", "variance": 0, "scope": "one_ally"})
	db.add("skills", {"id": "hit100", "name": "Hit 100", "formula": "100", "hit_type": "certain", "variance": 0})
	db.add("skills", {"id": "charge", "name": "Charge", "formula": "1", "hit_type": "certain", "variance": 0, "tp_gain": 10})
	db.add("skills", {"id": "tp_burst", "name": "Burst", "formula": "1", "hit_type": "certain", "cost": {"tp": 20}})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(4242)


func test_load_validate_and_discovery() -> void:
	assert_true(rules != null, "vx_ace loads")
	assert_eq(rules.rules_id, "vx_ace")
	var ids := []
	for s in rules.stats():
		ids.append(s.id)
	assert_eq(ids, ["mhp", "mmp", "atk", "def", "mat", "mdf", "agi", "luk"])
	var res := []
	for r in rules.resources():
		res.append(r.id)
	assert_eq(res, ["hp", "mp", "tp"])
	assert_eq(rules.validate(), [], "rules and formula examples compile")
	var shipped := RPGRuleSystem.load_rules_from_dir("res://addons/rpg/runtime/rules/vx_ace", db)
	assert_eq(shipped.definition, rules.definition, "project copy matches the copy shipped in the addon")
	var available := []
	for e in RPGRuleMigration.available():
		available.append(e.id)
	assert_has(available, "vx_ace", "Database > Rule system... lists it")


func test_parameter_curves() -> void:
	var l1 := rules.new_actor_battler("eric", 1)
	var l50 := rules.new_actor_battler("eric", 50)
	var l99 := rules.new_actor_battler("eric", 99)
	var b1 := rules.stat_block(l1)
	var b50 := rules.stat_block(l50)
	var b99 := rules.stat_block(l99)
	# Linear curve {at_1: 450, at_99: 5000}.
	assert_eq([b1.mhp, b50.mhp, b99.mhp], [450, 2725, 5000])
	assert_eq([b1.mmp, b50.mmp, b99.mmp], [80, 540, 1000], "shape defaults to linear")
	# Late: 20 + 180 * 0.5^1.5 at level 50; early: 20 + 180 * 0.5^0.75.
	assert_eq([b1.atk, b50.atk, b99.atk], [20, 84, 200])
	assert_eq([b1.mat, b50.mat, b99.mat], [20, 127, 200])
	assert_eq([b1.agi, b50.agi, b99.agi], [30, 80, 230], "numeric exponent 2")
	# The old {base, per_level} form still works next to curves.
	assert_eq([b1.def, b50.def, b99.def], [10, 108, 206])
	assert_eq(l50.get_resource("hp"), 2725)
	assert_eq(l50.get_resource("mp"), 540)
	assert_eq(rules.growth_exponent("very_slow"), 2.0, "rules.json growth_shapes")


func test_ace_damage_formulas() -> void:
	var eric := rules.new_actor_battler("eric")
	var bruno := rules.new_actor_battler("bruno")
	var slime := rules.new_enemy_battler("slime")
	# a.atk * 4 - b.def * 2 with bruno's ATK 50 + sword 10 + dagger 5 (dual wield) = 65.
	assert_eq(rules.damage(bruno, slime, {"kind": "skill", "skill": "strike"}).value, 240)
	slime.guarding = true
	assert_eq(rules.damage(bruno, slime, {"kind": "skill", "skill": "strike"}).value, 120, "guard halves")
	slime.guarding = false
	assert_eq(rules.damage(eric, slime, {"kind": "skill", "skill": "fire"}).value, 120, "100 + 20 * 2 - 10 * 2")
	assert_eq(rules.damage(eric, eric, {"kind": "skill", "skill": "heal"}).value, 220, "200 + a.mat")
	assert_eq(rules.damage(eric, eric, {"kind": "skill", "skill": "heal"}).type, "recover")
	# The formula examples in rules.json give the same numbers.
	var ex: Dictionary = {}
	for e in rules.definition.formula_examples:
		ex[e.id] = e.formula
	assert_eq(ex.attack, rules.definition.attack.formula)
	assert_eq(rules.evaluate_formula(ex.magic, eric, slime).value, 120)
	assert_eq(rules.evaluate_formula(ex.heal, eric, eric).value, 220)
	# The real attack: 240 with 20% variance; critical x3.
	var crits := 0
	for i in 60:
		var a := rules.damage(bruno, slime, {"kind": "attack"})
		var lo := 576 if a.critical else 192
		var hi := 864 if a.critical else 288
		assert_true(a.value >= lo and a.value <= hi, "attack %d in %d..%d" % [a.value, lo, hi])
		if a.critical:
			crits += 1
	assert_true(crits < 15, "default CRI 4%% (%d/60)" % crits)
	rules.add_state(eric, "focus")
	for i in 10:
		var c := rules.damage(eric, slime, {"kind": "attack"})
		assert_true(c.critical, "CRI +100% always crits")
		assert_true(c.value >= 144 and c.value <= 216, "(20 * 4 - 20) x3 +-20%%, got %d" % c.value)


func test_ex_parameters_hit_eva() -> void:
	var eric := rules.new_actor_battler("eric")
	var slime := rules.new_enemy_battler("slime")
	var ghost := rules.new_enemy_battler("ghost")
	var snap := eric.snapshot()
	assert_eq([snap.hit, snap.eva, snap.cri, snap.cev, snap.mev, snap.tcr], [95, 5, 4, 0, 0, 100], "default features")
	assert_eq(slime.snapshot().cri, 0, "enemies default to CRI 0")
	var hits := 0
	for i in 100:
		if rules.hit_check(eric, slime, {"kind": "attack"}).hit:
			hits += 1
	assert_true(hits > 80 and hits < 100, "95%% hit, 5%% evasion (%d/100)" % hits)
	var evaded := 0
	for i in 40:
		var h := rules.hit_check(eric, ghost, {"kind": "attack"})
		assert_false(h.hit, "EVA 100% never gets hit")
		if h.evaded:
			evaded += 1
	assert_true(evaded > 30, "most failures are evasions (%d/40)" % evaded)
	assert_true(rules.hit_check(eric, ghost, {"kind": "skill", "skill": "fire"}).hit, "magic ignores EVA (MEV 0)")
	rules.add_state(eric, "blind")
	assert_eq(eric.snapshot().hit, 0)
	for i in 20:
		assert_false(rules.hit_check(eric, slime, {"kind": "attack"}).hit, "HIT 0 never hits")


func test_tp() -> void:
	var bruno := rules.new_actor_battler("bruno")
	var eric := rules.new_actor_battler("eric")
	assert_eq(bruno.get_resource("tp"), 0, "TP starts empty, not at max")
	assert_eq(rules.max_resource(bruno, "tp"), 100)
	bruno.set_resource("tp", 50)
	rules.recover_all(bruno)
	assert_eq(bruno.get_resource("tp"), 50, "Recover All leaves TP alone")
	bruno.set_resource("tp", 0)
	# 100 damage on 500 max HP: 50 * 100 / 500 = 10 TP.
	var r := rules.apply_action(eric, bruno, {"kind": "skill", "skill": "hit100"})
	assert_eq(r.damage, 100)
	assert_eq(bruno.get_resource("tp"), 10)
	assert_eq(r.charged, {"tp": 10})
	assert_eq(r.changes, {"hp": -100, "tp": 10})
	assert_false(r.text.contains("TP"), "charging is not announced: " + r.text)
	rules.add_state(bruno, "charger")
	rules.apply_action(eric, bruno, {"kind": "skill", "skill": "hit100"})
	assert_eq(bruno.get_resource("tp"), 30, "TP Charge Rate 200% doubles the gain")
	# TP Gain of the skill goes to the user when it hits.
	var slime := rules.new_enemy_battler("slime")
	var g := rules.apply_action(eric, slime, {"kind": "skill", "skill": "charge"})
	assert_eq(g.user_changes, {"tp": 10})
	assert_eq(eric.get_resource("tp"), 10)
	# TP costs.
	assert_false(rules.can_use(eric, {"kind": "skill", "skill": "tp_burst"}), "needs 20 TP")
	assert_true(rules.can_use(bruno, {"kind": "skill", "skill": "tp_burst"}))
	# Battle start: 0..25; battle end: back to 0 unless Preserve TP.
	for i in 20:
		rules.start_battle(eric)
		var tp := eric.get_resource("tp")
		assert_true(tp >= 0 and tp <= 25, "starting TP %d" % tp)
	rules.end_battle(bruno)
	assert_eq(bruno.get_resource("tp"), 0)
	bruno.set_resource("tp", 70)
	rules.add_state(bruno, "keep_tp")
	rules.start_battle(bruno)
	rules.end_battle(bruno)
	assert_eq(bruno.get_resource("tp"), 70, "Preserve TP")


func test_regen() -> void:
	var eric := rules.new_actor_battler("eric")
	rules.add_state(eric, "regen")
	eric.set_resource("hp", 100)
	var t := rules.tick_states(eric)
	assert_eq(eric.get_resource("hp"), 145, "HP Regen 10% of 450")
	assert_eq(t.regen, {"hp": 45})
	assert_true(t.lines.size() == 1 and t.lines[0].contains("45"), str(t.lines))
	rules.remove_state(eric, "regen")
	rules.add_state(eric, "drain")
	eric.set_resource("hp", 10)
	var d := rules.tick_states(eric)
	assert_eq(eric.get_resource("hp"), 1, "negative regen never knocks out")
	assert_eq(d.damage, 9)
	assert_true(eric.is_alive())


func test_skill_types() -> void:
	var eric := rules.new_actor_battler("eric")
	var bruno := rules.new_actor_battler("bruno")
	assert_true(rules.can_use(eric, {"kind": "skill", "skill": "fire"}), "Add Skill Type: magic")
	assert_false(rules.can_use(eric, {"kind": "skill", "skill": "kick"}), "special not added")
	assert_false(rules.can_use(bruno, {"kind": "skill", "skill": "fire"}), "brawler has no magic")
	assert_true(rules.can_use(bruno, {"kind": "skill", "skill": "strike"}), "skills without a type stay usable")
	var slime := rules.new_enemy_battler("slime")
	slime.skills.append("kick")
	assert_true(rules.can_use(slime, {"kind": "skill", "skill": "kick"}), "enemies are not limited")
	rules.add_state(eric, "silence")
	assert_false(rules.can_use(eric, {"kind": "skill", "skill": "fire"}), "Seal Skill Type")


func test_dual_wield_and_seal_equip() -> void:
	var bruno := rules.new_actor_battler("bruno")
	assert_eq(rules.dual_wield_slots(bruno), ["shield"])
	assert_eq(rules.equip_slot_kind(bruno, "shield"), "weapon")
	assert_eq(rules.effective_stat(bruno, "atk"), 65, "50 + sword 10 + dagger 5")
	assert_eq(rules.effective_stat(bruno, "def"), 35, "20 + plate 15")
	var ace := rules.new_actor_battler("ace")
	ace.equips["shield"] = "dagger"
	ace.class_id = "soldier"
	assert_eq(rules.equip_slot_kind(ace, "shield"), "armor", "no dual wield: a dagger is not a shield")
	assert_eq(rules.effective_stat(ace, "atk"), 30, "20 + sword 10, the dagger does not count")
	rules.add_state(bruno, "sealed")
	assert_true(rules.is_slot_sealed(bruno, "body"))
	assert_eq(rules.effective_stat(bruno, "def"), 20, "sealed body armour does not count")


func test_action_times_in_battle_round() -> void:
	var ace := rules.new_actor_battler("ace")
	var eric := rules.new_actor_battler("eric")
	var troop := {"id": "t", "members": [{"enemy": "slime"}], "can_escape": true}
	var core := RPGBattleCore.new([ace, eric], troop, rules, RPGRandom.new(99))
	core.start()
	for b in core.all_battlers():
		var tp: int = b.get_resource("tp")
		assert_true(tp >= 0 and tp <= 25, "%s starts with %d TP" % [b.name, tp])
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "attack", "target": 0}))
	assert_true(core.set_action(1, {"kind": "attack", "target": 0}))
	var acted := {}
	var hp_before: int = core.enemies[0].get_resource("hp")
	var r := core.next_action()
	while not r.is_empty():
		var who: String = r.user.id
		acted[who] = int(acted.get(who, 0)) + 1
		r = core.next_action()
	core.end_turn()
	assert_eq(acted.get("ace", 0), 2, "Action Times+ 100%: two actions")
	assert_eq(acted.get("eric", 0), 1)
	assert_eq(acted.get("slime", 0), 1)
	assert_true(core.enemies[0].get_resource("hp") < hp_before, "the slime took damage")
	core.finish()
	for a in core.party:
		assert_eq(a.get_resource("tp"), 0, "TP cleared after battle")


func test_exp_curve() -> void:
	# basis 30, extra 20, acceleration 30/30 (Ace defaults).
	assert_eq(rules.exp_for_level("soldier", 1), 0)
	assert_eq(rules.exp_for_level("soldier", 2), 50)
	assert_eq(rules.exp_for_level("soldier", 3), 162)
	assert_eq(rules.exp_for_level("soldier", 10), 5296)
	assert_eq(rules.exp_for_level("soldier", 50), 529492)
	assert_eq(rules.exp_for_level("soldier", 99), 2547133)
	# Class override.
	assert_eq(rules.exp_for_level("brawler", 2), 40)
	assert_eq(rules.exp_for_level("brawler", 10), 4050)
	assert_eq(rules.exp_for_level("brawler", 99), 2031630)
	var prev := 0
	for lv in range(2, 100):
		var e := rules.exp_for_level("soldier", lv)
		assert_true(e > prev, "curve rises at level %d" % lv)
		prev = e
	var eric := rules.new_actor_battler("eric")
	var ups := rules.gain_exp(eric, 170)
	assert_eq(eric.level, 3)
	assert_eq(ups[0].gains.mhp, 46, "linear curve step 4550 / 98")
