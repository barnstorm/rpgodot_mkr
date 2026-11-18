extends "res://tests/rpg_test_case.gd"
## Skills with a Required Weapon (issue #151): VX Ace / MV's "Required Weapon 1 / 2". The skill
## can only be used while a weapon of one of the listed types is equipped; enemies ignore it.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"},
		{"id": "shield", "name": "Shield", "kind": "armor"}]})
	db.add("types", {"id": "weapon_types", "name": "Weapon types", "entries": [
		{"id": "sword", "name": "Sword"}, {"id": "spear", "name": "Spear"}, {"id": "axe", "name": "Axe"}]})
	var growth := {"mhp": 500, "mmp": 100, "atk": 20, "def": 10, "mat": 20, "mdf": 10, "agi": 20, "luk": 10}
	db.add("classes", {"id": "soldier", "name": "Soldier", "growth": growth})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {},
		"skills": ["focus", "lunge", "shout", "blank"]})
	db.add("actors", {"id": "twin", "name": "Twin", "class": "soldier", "equips": {},
		"skills": ["focus", "lunge"], "traits": [{"kind": "dual_wield", "id": "shield"}]})
	db.add("weapons", {"id": "short_sword", "name": "Short Sword", "weapon_type": "sword"})
	db.add("weapons", {"id": "pike", "name": "Pike", "weapon_type": "spear"})
	db.add("weapons", {"id": "hatchet", "name": "Hatchet", "weapon_type": "axe"})
	db.add("weapons", {"id": "stick", "name": "Stick"})
	db.add("armors", {"id": "buckler", "name": "Buckler", "slot": "shield"})
	# Tutorial 3: Focus needs a sword. Tutorial 3.5: Lunge needs a spear (here: spear or axe).
	db.add("skills", {"id": "focus", "name": "Focus", "scope": "user", "required_weapons": ["sword"],
		"damage_type": "none", "effects": []})
	db.add("skills", {"id": "lunge", "name": "Lunge", "scope": "one_enemy", "required_weapons": ["spear", "axe"],
		"formula": "a.atk * 2", "hit": 100, "variance": 0})
	db.add("skills", {"id": "shout", "name": "Shout", "scope": "one_enemy", "formula": "10", "hit": 100, "variance": 0})
	db.add("skills", {"id": "blank", "name": "Blank", "scope": "one_enemy", "required_weapons": ["", ""],
		"formula": "10", "hit": 100, "variance": 0})
	db.add("enemies", {"id": "lancer", "name": "Lancer", "stats": {"mhp": 300, "mmp": 0, "atk": 10, "def": 5, "mat": 5, "mdf": 5, "agi": 5, "luk": 5},
		"actions": [{"kind": "skill", "skill": "lunge", "rating": 5}]})
	db.add("troops", {"id": "lancers", "name": "Lancer", "members": [{"enemy": "lancer", "position": [160, 150]}], "pages": []})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "disarmed", "name": "Disarmed", "traits": [{"kind": "seal_equip", "id": "weapon"}]})
	rules = RPGRuleSystem.load_rules("vx_ace", db)


func _skill(id: String) -> Dictionary:
	return {"kind": "skill", "skill": id}


func test_a_skill_needs_its_weapon_type_equipped() -> void:
	var eric := rules.new_actor_battler("eric")
	assert_false(rules.can_use(eric, _skill("focus")), "bare hands: Focus needs a sword")
	assert_true(rules.can_use(eric, _skill("shout")), "a skill that asks for nothing")
	eric.equips["weapon"] = "short_sword"
	assert_true(rules.can_use(eric, _skill("focus")), "with a sword")
	assert_false(rules.can_use(eric, _skill("lunge")), "a sword is no spear")
	eric.equips["weapon"] = "pike"
	assert_false(rules.can_use(eric, _skill("focus")))
	assert_true(rules.can_use(eric, _skill("lunge")), "Required Weapon 1")
	eric.equips["weapon"] = "hatchet"
	assert_true(rules.can_use(eric, _skill("lunge")), "or Required Weapon 2")
	eric.equips["weapon"] = "stick"
	assert_false(rules.can_use(eric, _skill("lunge")), "a weapon with no type matches nothing")
	assert_eq(rules.equipped_weapon_types(eric), [])
	assert_eq(rules.required_weapon_types(db.record("skills", "lunge")), ["spear", "axe"])


func test_blank_entries_ask_for_nothing() -> void:
	var eric := rules.new_actor_battler("eric")
	assert_eq(rules.required_weapon_types(db.record("skills", "blank")), [])
	assert_true(rules.can_use(eric, _skill("blank")), "a list of blanks is no requirement")
	assert_true(rules.weapon_requirement_met(eric, {"required_weapons": []}))
	assert_true(rules.weapon_requirement_met(eric, {}))
	assert_true(rules.weapon_requirement_met(eric, {"required_weapons": "sword"}), "not a list: ignored")


func test_a_second_weapon_counts_and_a_sealed_slot_does_not() -> void:
	var twin := rules.new_actor_battler("twin")
	twin.equips["weapon"] = "short_sword"
	twin.equips["shield"] = "pike"
	assert_eq(rules.equipped_weapon_types(twin), ["sword", "spear"], "both hands")
	assert_true(rules.can_use(twin, _skill("focus")) and rules.can_use(twin, _skill("lunge")))
	rules.add_state(twin, "disarmed")
	assert_eq(rules.equipped_weapon_types(twin), ["spear"], "the sealed slot's sword does not count")
	assert_false(rules.can_use(twin, _skill("focus")))
	# A shield in an ordinary shield slot is no weapon, whatever its id.
	var eric := rules.new_actor_battler("eric")
	eric.equips["shield"] = "buckler"
	assert_eq(rules.equipped_weapon_types(eric), [])


func test_enemies_ignore_the_requirement() -> void:
	var lancer := rules.new_enemy_battler("lancer")
	assert_true(rules.can_use(lancer, _skill("lunge")), "enemies carry no weapons and are not asked for one")
	assert_true(rules.weapon_requirement_met(lancer, db.record("skills", "lunge")))


func test_the_classic_rules_check_it_too() -> void:
	var classic := RPGRuleSystem.load_rules("classic", db)
	var eric := classic.new_actor_battler("eric")
	assert_false(classic.can_use(eric, _skill("focus")))
	eric.equips["weapon"] = "short_sword"
	assert_true(classic.can_use(eric, _skill("focus")))


func test_battle_refuses_the_skill_without_the_weapon() -> void:
	var eric := rules.new_actor_battler("eric")
	var core := RPGBattleCore.new([eric], db.record("troops", "lancers"), rules, RPGRandom.new(5))
	core.start()
	core.begin_turn()
	assert_false(core.set_action(0, {"kind": "skill", "skill": "lunge", "target": 0}), "no spear: the command is refused")
	eric.equips["weapon"] = "pike"
	assert_true(core.set_action(0, {"kind": "skill", "skill": "lunge", "target": 0}), "with the spear it is taken")
	# The weapon comes off before the action runs (a Change Equipment in a battle event):
	# the action fails with the "cannot use" line, as any unusable skill.
	eric.equips.erase("weapon")
	var before: int = core.enemies[0].get_resource("hp")
	var said := false
	var r := core.next_action()
	while not r.is_empty():
		if r.get("user") == eric:
			said = (r.get("lines", []) as Array).has(rules.term("cannot_use", [eric.name, "Lunge"]))
		r = core.next_action()
	assert_true(said, "Eric's turn says he cannot use Lunge")
	assert_eq(core.enemies[0].get_resource("hp"), before, "and the enemy took nothing")


func test_the_skill_form_offers_the_weapon_types() -> void:
	var lists := {"weapon_types": {"name": "Weapon types", "entries": db.record("types", "weapon_types").entries}}
	var fields := RPGRecordSchemas.fields_for("skills", [], [], [], {}, [], {}, lists)
	var found := fields.filter(func(f): return f.key == "required_weapons")
	assert_eq(found.size(), 1, "the skill form has a Required weapon field")
	if found.is_empty():
		return
	var f: Dictionary = found[0]
	assert_eq(str(f.kind), "list")
	assert_eq(f.item_field.options, ["sword", "spear", "axe"], "one of the project's weapon types per row")
	assert_true(str(f.help).contains("Enemies ignore"), str(f.help))
	var keys := fields.map(func(x): return x.key)
	assert_eq(keys.find("required_weapons"), keys.find("skill_type") + 1, "next to the skill type, as in RPG Maker")
	var rec := RPGRecordSchemas.new_record("skills", "new_skill", fields)
	assert_eq(rec.get("required_weapons"), [], "a new skill asks for nothing")


func test_the_validator_knows_the_field() -> void:
	var files := {
		"res://rpg/database/types.json": {"kind": "database", "db_type": "types", "data": {"records": [db.record("types", "weapon_types")]}},
		"res://rpg/database/skills.json": {"kind": "database", "db_type": "skills", "data": {"records": [
			{"id": "focus", "name": "Focus", "required_weapons": ["sword", "halberd", ""]}]}},
	}
	var refs := RPGValidator.type_refs(files).filter(func(r): return r.field == "required_weapons")
	assert_eq(refs.map(func(r): return r.id), ["sword", "halberd"], "each named type is a reference (blanks are not)")
	assert_true(refs.all(func(r): return r.list == "weapon_types"))
	var msgs := RPGValidator.database_values(files).filter(func(p): return str(p.field) == "required_weapons").map(func(p): return str(p.message))
	assert_eq(msgs.size(), 1, str(msgs))
	assert_true(not msgs.is_empty() and msgs[0].contains("'halberd'") and msgs[0].contains("Weapon types"), str(msgs))
