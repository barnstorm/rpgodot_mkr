extends "res://tests/rpg_test_case.gd"
## What an actor may equip (issue #149): the class's "Can equip" lists plus the Equip Weapon /
## Equip Armor traits, one rule for the Equip screen, Change Equipment, the shop and the editor.
## Under the VX Ace rules a class with no lists equips only what traits name.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem
var classic: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"},
		{"id": "shield", "name": "Shield", "kind": "armor"},
		{"id": "body", "name": "Body", "kind": "armor"},
		{"id": "accessory", "name": "Accessory", "kind": "armor"}]})
	var growth := {"mhp": 500, "mmp": 100, "atk": 20, "def": 10, "mat": 20, "mdf": 10, "agi": 20, "luk": 10}
	# "fresh" is a class as New makes it: a "Can equip" entry with no lists yet.
	db.add("classes", {"id": "fresh", "name": "Fresh", "growth": growth, "equip": {}})
	db.add("classes", {"id": "listed", "name": "Listed", "growth": growth,
		"equip": {"weapon_types": ["sword"], "armor_types": ["light"]}})
	db.add("classes", {"id": "half", "name": "Half", "growth": growth, "equip": {"weapon_types": ["sword"]}})
	db.add("classes", {"id": "bare", "name": "Bare", "growth": growth})
	db.add("actors", {"id": "ryan", "name": "Ryan", "class": "fresh", "equips": {},
		"traits": [{"kind": "equip_weapon_type", "id": "sword"}]})
	db.add("actors", {"id": "natalie", "name": "Natalie", "class": "fresh", "equips": {}})
	db.add("actors", {"id": "lars", "name": "Lars", "class": "listed", "equips": {}})
	db.add("actors", {"id": "hal", "name": "Hal", "class": "half", "equips": {}})
	db.add("actors", {"id": "old", "name": "Old", "class": "bare", "equips": {}})
	db.add("weapons", {"id": "sword", "name": "Sword", "weapon_type": "sword"})
	db.add("weapons", {"id": "spear", "name": "Spear", "weapon_type": "spear"})
	db.add("weapons", {"id": "club", "name": "Club"})
	db.add("armors", {"id": "tunic", "name": "Tunic", "armor_type": "light", "slot": "body"})
	db.add("armors", {"id": "plate", "name": "Plate", "armor_type": "heavy", "slot": "body"})
	db.add("armors", {"id": "badge", "name": "Squire's Badge", "armor_type": "light", "slot": "accessory",
		"traits": [{"kind": "equip_armor_type", "id": "heavy"}]})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "spear_training", "name": "Spear Training", "traits": [{"kind": "equip_weapon_type", "id": "spear"}]})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	classic = RPGRuleSystem.load_rules("classic", db)


func test_the_rule_sets_say_what_a_class_without_lists_may_equip() -> void:
	assert_eq(rules.class_equip_default(), "none", "VX Ace rules")
	assert_eq(classic.class_equip_default(), "any", "Classic rules")
	assert_eq(RPGRuleSystem.new().class_equip_default(), "any", "a rule set that does not say")
	var shipped := RPGRuleSystem.load_rules_from_dir("res://addons/rpg/runtime/rules/vx_ace", db)
	assert_eq(shipped.class_equip_default(), "none", "the copy shipped in the addon agrees")


func test_equip_weapon_sword_means_swords_and_nothing_else() -> void:
	# Tutorial 4: Ryan gets the feature Equip Weapon: Sword on a class made with New.
	var ryan := rules.new_actor_battler("ryan")
	assert_true(rules.can_equip(ryan, "weapon", "sword"), "the trait allows swords")
	assert_false(rules.can_equip(ryan, "weapon", "spear"), "and not spears")
	assert_false(rules.can_equip(ryan, "body", "tunic"), "no Equip Armor trait: no armour")
	assert_true(rules.equip_type_allowed(ryan, "weapon", "sword"))
	assert_false(rules.equip_type_allowed(ryan, "armor", "sword"), "a weapon trait says nothing about armour")
	# A state or a worn piece of equipment can carry the trait too.
	rules.add_state(ryan, "spear_training")
	assert_true(rules.can_equip(ryan, "weapon", "spear"))
	var natalie := rules.new_actor_battler("natalie")
	assert_false(rules.can_equip(natalie, "weapon", "sword"), "no trait, no lists: nothing")
	assert_false(rules.can_equip(natalie, "body", "plate"))


func test_class_lists_and_traits_add_up() -> void:
	var lars := rules.new_actor_battler("lars")
	assert_true(rules.can_equip(lars, "weapon", "sword") and rules.can_equip(lars, "body", "tunic"), "the class's lists")
	assert_false(rules.can_equip(lars, "weapon", "spear") or rules.can_equip(lars, "body", "plate"))
	rules.add_state(lars, "spear_training")
	assert_true(rules.can_equip(lars, "weapon", "spear"), "a trait adds a type to the lists")
	assert_true(rules.can_equip(lars, "accessory", "badge"), "light armour")
	lars.equips["accessory"] = "badge"
	assert_true(rules.can_equip(lars, "body", "plate"), "the badge he wears grants heavy armour")
	lars.equips.erase("accessory")
	assert_false(rules.can_equip(lars, "body", "plate"))


func test_a_list_the_class_does_not_have_is_empty() -> void:
	for r in [rules, classic]:
		var hal: RPGBattler = r.new_actor_battler("hal")
		assert_true(r.can_equip(hal, "weapon", "sword"), "%s: the weapon list" % r.rules_id)
		assert_false(r.can_equip(hal, "body", "tunic"), "%s: no armour list is no armour" % r.rules_id)
		var natalie: RPGBattler = r.new_actor_battler("natalie")
		assert_false(r.can_equip(natalie, "weapon", "sword"), "%s: a class made with New has empty lists" % r.rules_id)


func test_a_class_with_no_can_equip_entry_follows_the_rule_set() -> void:
	var old_ace := rules.new_actor_battler("old")
	assert_false(rules.can_equip(old_ace, "weapon", "sword"), "VX Ace rules: only what traits name")
	assert_false(rules.can_equip(old_ace, "body", "plate"))
	rules.add_state(old_ace, "spear_training")
	assert_true(rules.can_equip(old_ace, "weapon", "spear"))
	var old_classic := classic.new_actor_battler("old")
	assert_true(classic.can_equip(old_classic, "weapon", "sword"), "Classic rules: nothing is restricted")
	assert_true(classic.can_equip(old_classic, "weapon", "club"), "an untyped weapon too")
	assert_true(classic.can_equip(old_classic, "body", "plate"))
	assert_false(classic.can_equip(old_classic, "weapon", "plate"), "armour is still not a weapon")


func test_an_untyped_item_needs_a_class_that_restricts_nothing() -> void:
	var lars := rules.new_actor_battler("lars")
	assert_false(rules.can_equip(lars, "weapon", "club"), "no type to list or to grant")
	rules.add_state(lars, "spear_training")
	assert_false(rules.can_equip(lars, "weapon", "club"), "a trait for another type does not cover it")


func test_the_editor_check_follows_the_same_rule() -> void:
	var slot := {"id": "weapon", "kind": "weapon"}
	var body := {"id": "body", "kind": "armor"}
	var fresh: Dictionary = db.record("classes", "fresh")
	var bare: Dictionary = db.record("classes", "bare")
	var sword: Dictionary = db.record("weapons", "sword")
	var spear: Dictionary = db.record("weapons", "spear")
	var tunic: Dictionary = db.record("armors", "tunic")
	var ryan: Dictionary = db.record("actors", "ryan")
	var problem := func(s: Dictionary, kind: String, item: Dictionary, cls: Dictionary, actor: Dictionary, def: String) -> String:
		return RPGValidator.equip_problem(str(s.id), s, kind, item, cls, actor, def)
	assert_eq(problem.call(slot, "weapon", sword, fresh, ryan, "none"), "", "Ryan's trait allows his starting sword")
	assert_true(problem.call(slot, "weapon", spear, fresh, ryan, "none").contains("cannot equip weapon type 'spear'"))
	assert_true(problem.call(body, "armor", tunic, fresh, ryan, "none").contains("cannot equip armour type 'light'"))
	assert_true(problem.call(slot, "weapon", sword, fresh, {}, "any").contains("cannot equip"), "without the actor's trait the empty list says no")
	assert_eq(problem.call(slot, "weapon", sword, bare, {}, "any"), "", "Classic: a class with no entry restricts nothing")
	assert_true(problem.call(slot, "weapon", sword, bare, {}, "none").contains("cannot equip"), "VX Ace: it allows nothing")
	# The older five-argument call still means "no actor traits, Classic default".
	assert_eq(RPGValidator.equip_problem("weapon", slot, "weapon", sword, bare), "")
	assert_eq(RPGValidator.rule_setting("res://rpg", "vx_ace", "class_equip_default", "any"), "none")
	assert_eq(RPGValidator.rule_setting("res://rpg", "classic", "class_equip_default", "any"), "any")
	assert_eq(RPGValidator.rule_setting("res://rpg", "no_such_rules", "class_equip_default", "any"), "any")
