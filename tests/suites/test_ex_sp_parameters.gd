extends "res://tests/rpg_test_case.gd"
## The Ex- and Sp-Parameters (#46): Counter Attack (CNT), Magic Reflection (MRF), Target Rate
## (TGR), Guard Effect (GRD), Recovery Effect (REC), Pharmacology (PHA), MP Cost Rate (MCR),
## Physical/Magic Damage Rate (PDR/MDR), Floor Damage Rate (FDR) and Experience Rate (EXR) —
## each as a VX Ace style trait applied where RPG Maker applies it, and a no-op for rules
## that don't define the field.

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
		"growth": {"mhp": 450, "mmp": 80, "atk": 20, "def": 10, "mat": 20, "mdf": 20, "agi": 30, "luk": 20},
		"traits": [{"kind": "add_skill_type", "id": "magic"}]})
	db.add("classes", {"id": "brawler", "name": "Brawler",
		"growth": {"mhp": 500, "mmp": 100, "atk": 50, "def": 20, "mat": 30, "mdf": 20, "agi": 20, "luk": 10}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {}, "skills": ["fire", "hit100"]})
	db.add("actors", {"id": "bruno", "name": "Bruno", "class": "brawler", "equips": {}})
	db.add("enemies", {"id": "slime", "name": "Slime", "exp": 10, "gold": 5,
		"stats": {"mhp": 500, "mmp": 0, "atk": 30, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("enemies", {"id": "fencer", "name": "Fencer",
		"stats": {"mhp": 500, "mmp": 0, "atk": 30, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"traits": [{"kind": "counter_rate", "value": 100}],
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("enemies", {"id": "mirror", "name": "Mirror",
		"stats": {"mhp": 400, "mmp": 0, "atk": 10, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"traits": [{"kind": "counter_rate", "value": 100}, {"kind": "magic_reflection", "value": 100}],
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	# Aim and flat feet make the physical hit checks certain (a.hit 100, b.eva 0). Ex-Parameter
	# traits replace the default, so the states carry the whole value.
	db.add("states", {"id": "true_aim", "name": "True Aim", "traits": [{"kind": "hit_rate", "value": 100}]})
	db.add("states", {"id": "flat_footed", "name": "Flat-footed", "traits": [{"kind": "evasion_rate", "value": 0}]})
	db.add("states", {"id": "fencing", "name": "Fencing", "traits": [
		{"kind": "counter_rate", "value": 60}, {"kind": "magic_reflection", "value": 40}]})
	db.add("states", {"id": "taunt", "name": "Taunt", "traits": [{"kind": "target_rate", "value": 0}]})
	db.add("states", {"id": "light_lure", "name": "Light Lure", "traits": [{"kind": "target_rate", "value": 10}]})
	db.add("states", {"id": "heavy_lure", "name": "Heavy Lure", "traits": [{"kind": "target_rate", "value": 990}]})
	db.add("states", {"id": "great_guard", "name": "Great Guard", "traits": [{"kind": "guard_effect", "value": 200}]})
	db.add("states", {"id": "poor_guard", "name": "Poor Guard", "traits": [{"kind": "guard_effect", "value": 50}]})
	db.add("states", {"id": "blessed", "name": "Blessed", "traits": [{"kind": "recovery_effect", "value": 200}]})
	db.add("states", {"id": "cursed", "name": "Cursed", "traits": [{"kind": "recovery_effect", "value": 50}]})
	db.add("states", {"id": "alchemist", "name": "Alchemist", "traits": [{"kind": "pharmacology", "value": 200}]})
	db.add("states", {"id": "cheap_cast", "name": "Cheap Cast", "traits": [{"kind": "mp_cost_rate", "value": 40}]})
	db.add("states", {"id": "tough", "name": "Tough", "traits": [{"kind": "physical_damage", "value": 50}]})
	db.add("states", {"id": "warded", "name": "Warded", "traits": [{"kind": "magic_damage", "value": 50}]})
	db.add("states", {"id": "feather", "name": "Feather", "traits": [{"kind": "floor_damage", "value": 50}]})
	db.add("states", {"id": "quick_study", "name": "Quick Study", "traits": [{"kind": "experience_gain", "value": 200}]})
	db.add("skills", {"id": "hit100", "name": "Hit 100", "formula": "100", "hit_type": "certain", "variance": 0})
	db.add("skills", {"id": "stab100", "name": "Stab 100", "formula": "100", "hit_type": "physical", "variance": 0})
	db.add("skills", {"id": "bolt100", "name": "Bolt 100", "formula": "100", "hit_type": "magical", "variance": 0})
	db.add("skills", {"id": "mend", "name": "Mend", "formula": "100", "damage_type": "recover",
		"hit_type": "certain", "variance": 0, "scope": "one_ally"})
	db.add("skills", {"id": "mend_effect", "name": "Mending Touch", "hit_type": "certain", "variance": 0,
		"scope": "one_ally", "effects": [{"kind": "recover", "resource": "hp", "amount": 100}]})
	db.add("skills", {"id": "fire", "name": "Fire", "skill_type": "magic", "formula": "100 + a.mat * 2 - b.mdf * 2",
		"hit_type": "magical", "hit": 100, "variance": 0, "cost": {"mp": 5}, "scope": "one_enemy"})
	db.add("skills", {"id": "tp_move", "name": "TP Move", "hit_type": "certain", "variance": 0,
		"cost": {"tp": 10}, "formula": "1"})
	db.add("items", {"id": "potion", "name": "Potion", "hit_type": "certain",
		"effects": [{"kind": "recover", "resource": "hp", "amount": 100}]})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(4242)


func _pair() -> Array:
	var eric := rules.new_actor_battler("eric", 1)
	var bruno := rules.new_actor_battler("bruno", 1)
	rules.add_state(eric, "true_aim")
	rules.add_state(bruno, "flat_footed")
	return [eric, bruno]


func _damage_done(user, target, skill_id: String) -> int:
	var hp: int = target.get_resource("hp")
	var r := rules.apply_action(user, target, {"kind": "skill", "skill": skill_id})
	assert_true(r.hit, "%s hits" % skill_id)
	assert_eq(r.error, "", "%s resolves" % skill_id)
	return hp - target.get_resource("hp")


func _healed(target, user, action: Dictionary) -> int:
	target.set_resource("hp", 10)
	var r := rules.apply_action(user, target, action)
	assert_true(r.hit)
	return r.recovered


func test_snapshot_exposes_the_new_fields() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	var snap := rules.snapshot(eric)
	assert_eq(snap.cnt, 0, "CNT defaults to 0")
	assert_eq(snap.mrf, 0, "MRF defaults to 0")
	for code in ["tgr", "grd", "rec", "pha", "mcr", "pdr", "mdr", "fdr", "exr"]:
		assert_eq(int(snap[code]), 100, "%s defaults to 100%%" % code)
	rules.add_state(eric, "fencing")
	assert_eq(rules.snapshot(eric).cnt, 60, "CNT comes from the traits")
	assert_eq(rules.snapshot(eric).mrf, 40, "MRF comes from the traits")


func test_rules_without_the_fields_are_untouched() -> void:
	var classic := RPGRuleSystem.load_rules("classic", FakeDB.from_folder("res://rpg/database"))
	var hero := classic.new_actor_battler("hero", 1)
	assert_false(classic.has_snapshot_field("tgr"), "classic has no Target Rate")
	assert_false(classic.has_snapshot_field("fdr"), "classic has no Floor Damage Rate")
	assert_eq(classic.trait_field(hero, "pdr", 100), 100, "a missing field falls back")
	assert_false(classic.snapshot(hero).has("pdr"), "the classic snapshot has no such key")
	assert_eq(classic.floor_damage(hero, 5).changes.hp, -5, "classic floor damage is not scaled")


func test_guard_effect_divides_the_halved_damage() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	bruno.guarding = true
	assert_eq(_damage_done(eric, bruno, "hit100"), 50, "guard halves (GRD 100)")
	rules.add_state(bruno, "great_guard")
	assert_eq(_damage_done(eric, bruno, "hit100"), 25, "GRD 200 quarters (damage / 2 x 2)")
	rules.remove_state(bruno, "great_guard")
	rules.add_state(bruno, "poor_guard")
	assert_eq(_damage_done(eric, bruno, "hit100"), 100, "GRD 50 cancels the guard")


func test_recovery_effect_scales_healing_received() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	assert_eq(_healed(bruno, eric, {"kind": "skill", "skill": "mend"}), 100, "REC 100 heals the formula amount")
	rules.add_state(bruno, "blessed")
	assert_eq(_healed(bruno, eric, {"kind": "skill", "skill": "mend"}), 200, "REC 200 doubles it")
	assert_eq(_healed(bruno, eric, {"kind": "skill", "skill": "mend_effect"}), 200, "the recover effect scales too")
	rules.remove_state(bruno, "blessed")
	rules.add_state(bruno, "cursed")
	assert_eq(_healed(bruno, eric, {"kind": "skill", "skill": "mend"}), 50, "REC 50 halves it")


func test_pharmacology_scales_item_recovery_for_the_user() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	assert_eq(_healed(bruno, eric, {"kind": "item", "item": "potion"}), 100, "PHA 100 heals as listed")
	rules.add_state(eric, "alchemist")
	assert_eq(_healed(bruno, eric, {"kind": "item", "item": "potion"}), 200, "PHA 200 doubles an item's recovery")
	assert_eq(_healed(bruno, eric, {"kind": "skill", "skill": "mend_effect"}), 100,
		"a skill's recover effect ignores the user's PHA")


func test_mp_cost_rate_scales_the_magic_cost() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	var fire := {"kind": "skill", "skill": "fire"}
	eric.set_resource("mp", 4)
	assert_false(rules.can_use(eric, fire), "4 MP is not enough for a 5 MP skill")
	rules.add_state(eric, "cheap_cast")
	assert_true(rules.can_use(eric, fire), "MCR 40 makes it 2 MP")
	rules.pay_cost(eric, fire)
	assert_eq(eric.get_resource("mp"), 2, "only the scaled MP is paid")
	eric.set_resource("mp", 1)
	assert_false(rules.can_use(eric, fire), "1 MP is still not enough")
	rules.remove_state(eric, "cheap_cast")
	eric.set_resource("tp", 10)
	rules.pay_cost(eric, {"kind": "skill", "skill": "tp_move"})
	assert_eq(eric.get_resource("tp"), 0, "a TP cost is not scaled by MCR")


func test_physical_and_magic_damage_rates() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	assert_eq(_damage_done(eric, bruno, "stab100"), 100, "PDR 100 keeps physical damage")
	assert_eq(_damage_done(eric, bruno, "bolt100"), 100, "MDR 100 keeps magical damage")
	assert_eq(_damage_done(eric, bruno, "hit100"), 100, "a certain hit is neither")
	rules.add_state(bruno, "tough")
	bruno.set_resource("hp", 500)
	assert_eq(_damage_done(eric, bruno, "stab100"), 50, "PDR 50 halves physical damage")
	assert_eq(_damage_done(eric, bruno, "bolt100"), 100, "PDR does not touch magic")
	assert_eq(_damage_done(eric, bruno, "hit100"), 100, "PDR does not touch a certain hit")
	rules.remove_state(bruno, "tough")
	bruno.set_resource("hp", 500)
	rules.add_state(bruno, "warded")
	assert_eq(_damage_done(eric, bruno, "bolt100"), 50, "MDR 50 halves magical damage")
	assert_eq(_damage_done(eric, bruno, "stab100"), 100, "MDR does not touch physical")


func test_floor_damage_rate() -> void:
	var bruno := rules.new_actor_battler("bruno", 1)
	assert_eq(rules.floor_damage(bruno, 10).changes.hp, -10, "FDR 100 takes the full amount")
	rules.add_state(bruno, "feather")
	assert_eq(rules.floor_damage(bruno, 10).changes.hp, -5, "FDR 50 halves it")
	bruno.set_resource("hp", 5)
	rules.floor_damage(bruno, 20)
	assert_eq(bruno.get_resource("hp"), 1, "a floor still never knocks out")


func test_experience_rate() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	rules.gain_exp(eric, 100)
	assert_eq(eric.exp, 100, "EXR 100 keeps the earned EXP")
	rules.add_state(eric, "quick_study")
	rules.gain_exp(eric, 100)
	assert_eq(eric.exp, 300, "EXR 200 doubles what is earned")


# ----------------------------------------------------------------------------------------------
# Battle core: the counter/reflect rolls and the enemy target weighting
# ----------------------------------------------------------------------------------------------

func _core(party_ids: Array, enemy_id: String, seed_value: int) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var troop := {"id": "solo", "name": "Solo",
		"members": [{"enemy": enemy_id, "hidden": false, "position": [120, 150]}], "pages": []}
	var core := RPGBattleCore.new(party, troop, rules, RPGRandom.new(seed_value))
	core.start()
	return core


func _run_turn(core: RPGBattleCore, action0: Dictionary) -> Array:
	var results := []
	core.begin_turn()
	core.set_action(0, action0)
	var r := core.next_action()
	while not r.is_empty():
		results.append(r)
		r = core.next_action()
	for t in core.end_turn():
		results.append(t)
	return results


func test_core_counter_replaces_the_hit() -> void:
	var core := _core(["eric"], "fencer", 12345)
	var fencer = core.enemies[0]
	var hp: int = fencer.get_resource("hp")
	var results := _run_turn(core, {"kind": "attack", "target": 0})
	assert_eq(fencer.get_resource("hp"), hp, "the countered attack lands nothing")
	var seen := {"line": false, "entry": false}
	for res in results:
		for l in res.lines:
			if l == "Fencer counterattacks!":
				seen.line = true
		for e in res.effects:
			if e is Dictionary and e.has("countered_by"):
				seen.entry = true
				assert_eq(e.target, core.party[0], "the counter strikes the attacker")
	assert_true(seen.line, "the counterattack line is shown")
	assert_true(seen.entry, "the counterattack is an effect entry")


func test_core_reflect_sends_the_spell_back() -> void:
	var core := _core(["eric"], "mirror", 777)
	var mirror = core.enemies[0]
	var hp: int = mirror.get_resource("hp")
	var results := _run_turn(core, {"kind": "skill", "skill": "fire", "target": 0})
	assert_eq(mirror.get_resource("hp"), hp, "the reflected spell lands nothing on the reflector")
	assert_eq(core.party[0].get_resource("mp"), 75, "the caster still paid the cost exactly once")
	var seen := {"line": false, "entry": false}
	for res in results:
		for l in res.lines:
			if l == "Mirror reflects the magic!":
				seen.line = true
		for e in res.effects:
			if e is Dictionary and e.has("reflected_by"):
				seen.entry = true
				assert_eq(e.target, core.party[0], "the reflection hits the caster")
	assert_true(seen.line, "the reflection line is shown")
	assert_true(seen.entry, "the reflection is an effect entry")
	assert_true(core.party[0].get_resource("hp") < 450, "the caster took its own spell")


func test_core_certain_hits_are_never_answered() -> void:
	var core := _core(["eric"], "mirror", 777)
	var mirror = core.enemies[0]
	var hp: int = mirror.get_resource("hp")
	var results := _run_turn(core, {"kind": "skill", "skill": "hit100", "target": 0})
	assert_true(mirror.get_resource("hp") < hp, "a certain hit lands through CNT and MRF")
	for res in results:
		for l in res.lines:
			assert_ne(l, "Mirror counterattacks!", "a certain hit draws no counter roll")
			assert_ne(l, "Mirror reflects the magic!", "a certain hit draws no reflection roll")


func test_target_rate_weights_enemy_picks() -> void:
	var core := _core(["eric", "bruno"], "slime", 99)
	var slime = core.enemies[0]
	var u := rules.resolve_action(slime, {"kind": "attack"})
	rules.add_state(core.party[0], "taunt")
	for i in 20:
		var picked: Array = core.resolve_targets(slime, u, -1)
		assert_eq(picked, [core.party[1]], "a Target Rate of 0 never draws the taunted hero")
	# A 10:990 split lands almost always on the heavy target (a 100-scaled weighting).
	rules.remove_state(core.party[0], "taunt")
	rules.add_state(core.party[0], "light_lure")
	rules.add_state(core.party[1], "heavy_lure")
	var heavy := 0
	for i in 200:
		var picked: Array = core.resolve_targets(slime, u, -1)
		if picked[0] == core.party[1]:
			heavy += 1
	assert_true(heavy >= 180, "the 990%% target is drawn nearly always (%d/200)" % heavy)


func test_target_rate_never_draws_when_all_weights_are_zero() -> void:
	var core := _core(["eric", "bruno"], "slime", 99)
	var slime = core.enemies[0]
	var u := rules.resolve_action(slime, {"kind": "attack"})
	rules.add_state(core.party[0], "taunt")
	rules.add_state(core.party[1], "taunt")
	for i in 10:
		assert_eq(core.resolve_targets(slime, u, -1), [], "nobody draws when every weight is 0")
