extends "res://tests/rpg_test_case.gd"
## Recover HP on a fallen ally (issue #153). Under the VX Ace rules a skill or item whose scope
## reaches the dead and restores HP revives, whatever the order of its effects; under the
## Classic rules only Remove State does.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("classes", {"id": "knight", "name": "Knight",
		"growth": {"mhp": 500, "mmp": 100, "atk": 20, "def": 10, "mat": 20, "mdf": 10, "agi": 20, "luk": 10}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "knight", "equips": {}})
	db.add("actors", {"id": "natalie", "name": "Natalie", "class": "knight", "equips": {}})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "poison", "name": "Poison"})
	# The tutorial's buyable revive item: Recover HP 50% on one dead ally, and nothing else.
	db.add("items", {"id": "feather", "name": "Phoenix Feather", "scope": "one_dead_ally", "hit_type": "certain",
		"effects": [{"kind": "recover", "percent": 50}]})
	db.add("items", {"id": "recover_then_remove", "name": "Feather B", "scope": "one_dead_ally", "hit_type": "certain",
		"effects": [{"kind": "recover", "percent": 50}, {"kind": "remove_state", "id": "knockout"}]})
	db.add("items", {"id": "remove_then_recover", "name": "Feather C", "scope": "one_dead_ally", "hit_type": "certain",
		"effects": [{"kind": "remove_state", "id": "knockout"}, {"kind": "recover", "percent": 50}]})
	db.add("items", {"id": "potion", "name": "Potion", "scope": "one_ally", "hit_type": "certain",
		"effects": [{"kind": "recover", "amount": 100}]})
	db.add("items", {"id": "ether", "name": "Ether", "scope": "one_dead_ally", "hit_type": "certain",
		"effects": [{"kind": "recover", "resource": "mp", "amount": 30}]})
	db.add("items", {"id": "dud", "name": "Dud", "scope": "one_dead_ally", "hit_type": "certain",
		"effects": [{"kind": "recover", "percent": 0}]})
	db.add("items", {"id": "megalixir", "name": "Megalixir", "scope": "all_allies_any", "hit_type": "certain",
		"effects": [{"kind": "recover", "amount": 120}]})
	db.add("skills", {"id": "raise", "name": "Raise", "scope": "one_dead_ally", "formula": "100", "damage_type": "recover",
		"hit_type": "certain", "variance": 0})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(9)


func _fallen(r: RPGRuleSystem, id := "natalie") -> RPGBattler:
	var b := r.new_actor_battler(id)
	b.set_resource(r.life_resource(), 0)
	r.add_state(b, r.death_state())
	return b


func test_the_rule_sets_say_whether_recovery_revives() -> void:
	assert_true(rules.recover_revives(), "VX Ace rules")
	assert_false(RPGRuleSystem.load_rules("classic", db).recover_revives(), "Classic rules")
	var bare := RPGRuleSystem.new()
	assert_false(bare.recover_revives(), "a rule set that does not say keeps the old behaviour")
	var shipped := RPGRuleSystem.load_rules_from_dir("res://addons/rpg/runtime/rules/vx_ace", db)
	assert_true(shipped.recover_revives(), "the copy shipped in the addon agrees")


func test_recover_hp_alone_revives_with_the_recovered_hp() -> void:
	var eric := rules.new_actor_battler("eric")
	var natalie := _fallen(rules)
	assert_true(natalie.is_dead())
	var r := rules.use_item(eric, natalie, "feather")
	assert_true(natalie.is_alive(), "Recover HP 50% raised her")
	assert_eq(natalie.get_resource("hp"), 250, "with the recovered HP, not 1 more")
	assert_true(r.revived)
	assert_eq(r.removed_states, ["knockout"])
	assert_eq(r.recovered, 250)
	assert_eq(r.lines, ["Natalie recovers 250 HP!", "Natalie is revived!"])
	assert_true(RPGRuleSystem.had_effect(r), "the menu uses the item up")


func test_both_effect_orders_revive() -> void:
	var eric := rules.new_actor_battler("eric")
	var a := _fallen(rules)
	var ra := rules.use_item(eric, a, "recover_then_remove")
	assert_true(a.is_alive())
	assert_eq(a.get_resource("hp"), 250, "Recover HP, then Remove State finds nothing left to do")
	assert_true(ra.revived)
	assert_eq(ra.removed_states, ["knockout"], "reported once")
	var b := _fallen(rules)
	var rb := rules.use_item(eric, b, "remove_then_recover")
	assert_true(b.is_alive())
	assert_eq(b.get_resource("hp"), 251, "Remove State revives at 1 HP, then the recovery adds to it (as VX Ace)")
	assert_true(rb.revived)


func test_a_recover_skill_revives_too() -> void:
	var eric := rules.new_actor_battler("eric")
	var natalie := _fallen(rules)
	var r := rules.apply_action(eric, natalie, {"kind": "skill", "skill": "raise"})
	assert_true(natalie.is_alive())
	assert_eq(natalie.get_resource("hp"), 100)
	assert_true(r.revived)
	assert_eq(r.lines, ["Natalie recovers 100 HP!", "Natalie is revived!"])


func test_only_a_scope_for_the_dead_reaches_the_fallen() -> void:
	var eric := rules.new_actor_battler("eric")
	var natalie := _fallen(rules)
	var r := rules.use_item(eric, natalie, "potion")
	assert_true(natalie.is_dead(), "a potion for a living ally does nothing for the fallen")
	assert_eq(natalie.get_resource("hp"), 0)
	assert_false(RPGRuleSystem.had_effect(r))
	# The "dead or alive" scope heals the living and raises the fallen.
	eric.set_resource("hp", 200)
	rules.use_item(eric, eric, "megalixir")
	rules.use_item(eric, natalie, "megalixir")
	assert_eq(eric.get_resource("hp"), 320)
	assert_true(natalie.is_alive())
	assert_eq(natalie.get_resource("hp"), 120)


func test_recovery_that_restores_no_hp_does_not_revive() -> void:
	var eric := rules.new_actor_battler("eric")
	var natalie := _fallen(rules)
	natalie.set_resource("mp", 10)
	var r := rules.use_item(eric, natalie, "ether")
	assert_true(natalie.is_dead(), "MP recovery is not a revive")
	assert_eq(natalie.get_resource("mp"), 40, "the MP still arrives")
	assert_false(r.revived)
	var r2 := rules.use_item(eric, natalie, "dud")
	assert_true(natalie.is_dead(), "0 HP recovered leaves her down")
	assert_false(r2.revived)
	assert_false(RPGRuleSystem.had_effect(r2))


func test_the_fallen_come_back_without_their_old_states() -> void:
	var eric := rules.new_actor_battler("eric")
	var natalie := rules.new_actor_battler("natalie")
	rules.add_state(natalie, "poison")
	natalie.set_resource("hp", 0)
	rules.add_state(natalie, "knockout")
	rules.use_item(eric, natalie, "feather")
	assert_true(natalie.is_alive())
	assert_false(natalie.has_state("poison"), "the knockout cleared it")
	assert_false(natalie.has_state("knockout"))


func test_classic_rules_keep_remove_state_as_the_only_revive() -> void:
	var classic := RPGRuleSystem.load_rules("classic", db)
	classic.rng = RPGRandom.new(9)
	var life := classic.life_resource()
	var eric := classic.new_actor_battler("eric")
	var a := _fallen(classic)
	var r := classic.use_item(eric, a, "feather")
	assert_true(a.is_dead(), "Recover HP alone does not revive under the Classic rules")
	assert_eq(a.get_resource(life), 0)
	assert_false(r.revived)
	assert_false(RPGRuleSystem.had_effect(r))
	var b := _fallen(classic)
	classic.use_item(eric, b, "recover_then_remove")
	assert_true(b.is_alive())
	assert_eq(b.get_resource(life), 1, "the recovery came before the revive and was lost, as before")
	var c := _fallen(classic)
	classic.use_item(eric, c, "remove_then_recover")
	assert_true(c.is_alive())
	assert_true(c.get_resource(life) > 1, "Remove State first, then the recovery lands")
