extends "res://tests/rpg_test_case.gd"
## The "Normal Attack" element and the item editor's Damage / Invocation fields (issue #167).
## A skill or item whose element is Normal Attack uses the user's Attack Element traits (its
## weapon's elements); with several, the one the target is weakest to counts, as in VX Ace.
## Items get the Damage type, Affects, Element, formula, Hit %, Hit type, Variance and critical
## fields skills have.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "elements", "name": "Elements", "entries": [
		{"id": "fire", "name": "Fire"}, {"id": "ice", "name": "Ice"}, {"id": "thunder", "name": "Thunder"}]})
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"}, {"id": "accessory", "name": "Accessory", "kind": "armor"}]})
	var growth := {"mhp": 5000, "mmp": 100, "atk": 100, "def": 20, "mat": 20, "mdf": 10, "agi": 20, "luk": 10}
	db.add("classes", {"id": "soldier", "name": "Soldier", "growth": growth})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {}, "skills": ["weapon_strike", "fire_strike"]})
	db.add("weapons", {"id": "flame_sword", "name": "Flame Sword", "traits": [{"kind": "attack_element", "id": "fire"}]})
	db.add("weapons", {"id": "plain_sword", "name": "Plain Sword"})
	db.add("armors", {"id": "frost_ring", "name": "Frost Ring", "slot": "accessory", "traits": [{"kind": "attack_element", "id": "ice"}]})
	var stats := {"mhp": 90000, "mmp": 0, "atk": 10, "def": 0, "mat": 10, "mdf": 0, "agi": 5, "luk": 10}
	# The dummy takes everything as it is; the others are weak to or resist an element.
	db.add("enemies", {"id": "dummy", "name": "Dummy", "stats": stats})
	db.add("enemies", {"id": "ice_weak", "name": "Lizard", "stats": stats,
		"traits": [{"kind": "element_rate", "id": "fire", "value": 50}, {"kind": "element_rate", "id": "ice", "value": 200}]})
	db.add("enemies", {"id": "tough", "name": "Golem", "stats": stats,
		"traits": [{"kind": "element_rate", "id": "fire", "value": 50}, {"kind": "element_rate", "id": "ice", "value": 25}]})
	db.add("enemies", {"id": "dodger", "name": "Dodger", "stats": stats, "traits": [{"kind": "evasion_rate", "value": 100}]})
	db.add("enemies", {"id": "imp", "name": "Imp", "stats": stats, "traits": [{"kind": "attack_element", "id": "fire"}]})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	# Tutorial 3.5's Lunge: a weapon skill whose element is Normal Attack.
	db.add("skills", {"id": "weapon_strike", "name": "Weapon Strike", "scope": "one_enemy", "formula": "100",
		"element": "normal_attack", "hit_type": "certain", "variance": 0})
	db.add("skills", {"id": "fire_strike", "name": "Fire Strike", "scope": "one_enemy", "formula": "100",
		"element": "fire", "hit_type": "certain", "variance": 0})
	# Tutorial 4: "items are incredibly similar to skills". A thrown fire bomb, and a dart that
	# takes on whatever the thrower's weapon has.
	db.add("items", {"id": "fire_bomb", "name": "Fire Bomb", "scope": "one_enemy", "damage_type": "damage", "formula": "100",
		"element": "fire", "hit": 100, "hit_type": "certain", "variance": 0})
	db.add("items", {"id": "dart", "name": "Dart", "scope": "one_enemy", "damage_type": "damage", "formula": "100",
		"element": "normal_attack", "hit": 100, "hit_type": "physical", "variance": 0})
	db.add("items", {"id": "dud", "name": "Dud", "scope": "one_enemy", "damage_type": "damage", "formula": "100",
		"hit": 0, "hit_type": "magical", "variance": 0})
	db.add("items", {"id": "old_bomb", "name": "Old Bomb", "scope": "one_enemy", "formula": "100"})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(3)


func _dmg(user: RPGBattler, target: RPGBattler, action: Dictionary) -> Dictionary:
	return rules.damage(user, target, action)


func test_the_attack_command_uses_every_attack_element() -> void:
	var eric := rules.new_actor_battler("eric")
	var lizard := rules.new_enemy_battler("ice_weak")
	var golem := rules.new_enemy_battler("tough")
	var attack := {"kind": "attack"}
	var d := _dmg(eric, lizard, attack)
	assert_eq(d.element, "", "bare hands: no element")
	assert_eq(d.element_rate, 1.0)
	eric.equips["weapon"] = "flame_sword"
	d = _dmg(eric, lizard, attack)
	assert_eq(d.element, "fire", "one Attack Element: that element, as before")
	assert_eq(d.element_rate, 0.5)
	assert_eq(rules.resolve_action(eric, attack).element, "fire", "the resolved attack names the first")
	# A second Attack Element (the ring): the one the target is weakest to counts.
	eric.equips["accessory"] = "frost_ring"
	assert_eq(rules.attack_elements(eric), ["fire", "ice"])
	d = _dmg(eric, lizard, attack)
	assert_eq(d.element, "ice", "weak to ice, resists fire: ice counts")
	assert_eq(d.element_rate, 2.0)
	d = _dmg(eric, golem, attack)
	assert_eq(d.element, "fire", "resists both: the better of the two")
	assert_eq(d.element_rate, 0.5)
	assert_eq(rules.resolve_action(eric, attack).elements, ["fire", "ice"])
	assert_eq(rules.attack_elements(null), [])


func test_a_skill_with_the_normal_attack_element() -> void:
	var eric := rules.new_actor_battler("eric")
	var lizard := rules.new_enemy_battler("ice_weak")
	var strike := {"kind": "skill", "skill": "weapon_strike"}
	assert_eq(_dmg(eric, lizard, strike).value, 100, "no weapon element: plain damage")
	eric.equips["weapon"] = "flame_sword"
	var d := _dmg(eric, lizard, strike)
	assert_eq(d.value, 50, "the flame sword makes it a fire skill")
	assert_eq(d.element, "fire")
	eric.equips["accessory"] = "frost_ring"
	assert_eq(_dmg(eric, lizard, strike).value, 200, "with the ring, ice counts against the lizard")
	# A skill with its own element ignores the weapon's.
	eric.equips["weapon"] = "plain_sword"
	d = _dmg(eric, lizard, {"kind": "skill", "skill": "fire_strike"})
	assert_eq(d.value, 50)
	assert_eq(d.element, "fire")
	# Enemies have Attack Elements too.
	var imp := rules.new_enemy_battler("imp")
	assert_eq(_dmg(imp, lizard, strike).element, "fire")
	assert_eq(RPGValidator.NORMAL_ATTACK_ELEMENT, RPGRuleSystem.NORMAL_ATTACK_ELEMENT, "one value for both")


func test_items_do_damage_like_skills() -> void:
	var eric := rules.new_actor_battler("eric")
	var lizard := rules.new_enemy_battler("ice_weak")
	var dummy := rules.new_enemy_battler("dummy")
	var before: int = dummy.get_resource("hp")
	var r := rules.apply_action(eric, dummy, {"kind": "item", "item": "fire_bomb"})
	assert_true(r.hit)
	assert_eq(r.damage, 100, "the item's formula")
	assert_eq(dummy.get_resource("hp"), before - 100)
	assert_eq(_dmg(eric, lizard, {"kind": "item", "item": "fire_bomb"}).value, 50, "its element meets the target's rate")
	# Normal Attack on an item: the user's weapon element.
	eric.equips["accessory"] = "frost_ring"
	assert_eq(_dmg(eric, lizard, {"kind": "item", "item": "dart"}).value, 200)
	# Hit % (RPG Maker's Success %) and Hit type.
	r = rules.apply_action(eric, dummy, {"kind": "item", "item": "dud"})
	assert_false(r.hit, "Hit 0% on a magical item: it never works")
	assert_eq(r.damage, 0)
	var dodger := rules.new_enemy_battler("dodger")
	r = rules.apply_action(eric, dodger, {"kind": "item", "item": "dart"})
	assert_true(r.evaded, "a physical item can be evaded")
	r = rules.apply_action(eric, dodger, {"kind": "item", "item": "fire_bomb"})
	assert_true(r.hit, "a certain-hit item cannot")
	# An item written before the field existed: a formula with no Damage type still damages.
	assert_eq(rules.apply_action(eric, dummy, {"kind": "item", "item": "old_bomb"}).hit, true)
	assert_eq(str(rules.resolve_action(eric, {"kind": "item", "item": "old_bomb"}).damage_type), "damage")


func _lists() -> Dictionary:
	return {"elements": {"name": "Elements", "entries": db.record("types", "elements").entries}}


func _field(fields: Array, key: String) -> Dictionary:
	var found := fields.filter(func(f): return f.key == key)
	assert_eq(found.size(), 1, "one '%s' field" % key)
	return found[0] if not found.is_empty() else {}


func test_the_element_field_offers_normal_attack() -> void:
	for type in ["skills", "items"]:
		var f := _field(RPGRecordSchemas.fields_for(type, [], [], [], {}, [], {}, _lists()), "element")
		assert_eq(f.get("options"), ["", "normal_attack", "fire", "ice", "thunder"], type)
		assert_eq(f.get("option_labels"), ["(none)", "Normal Attack", "Fire", "Ice", "Thunder"], type)
		assert_true(str(f.get("help", "")).contains("Attack Element"), str(f.get("help", "")))
	# No Types > Elements list: a text field that says what to type.
	var plain := _field(RPGRecordSchemas.fields_for("skills"), "element")
	assert_eq(str(plain.kind), "text")
	assert_true(str(plain.help).contains("normal_attack"), str(plain.help))


func test_the_item_form_has_the_damage_and_invocation_fields() -> void:
	var resources := [{"id": "hp", "name": "HP"}, {"id": "mp", "name": "MP"}]
	var fields := RPGRecordSchemas.fields_for("items", [], resources, [], {}, [], rules.definition, _lists())
	var keys := fields.map(func(f): return f.key)
	for k in ["damage_type", "resource", "element", "formula", "variance", "critical", "hit", "hit_type", "speed", "repeats"]:
		assert_has(keys, k)
	assert_eq(_field(fields, "damage_type").default, "none", "most items do no damage")
	assert_eq(_field(fields, "damage_type").options, ["none", "damage", "recover", "drain"])
	assert_eq(int(_field(fields, "variance").default), 20, "the rule set's variance, what the game uses when the item has none")
	assert_eq(int(_field(RPGRecordSchemas.fields_for("items"), "variance").default), 15, "without a rule set")
	assert_true(bool(_field(fields, "formula").get("formula", false)), "the formula has its Test button")
	# The damage fields show only with a Damage type, and stay out of the record without one.
	for k in ["resource", "element", "formula", "variance", "critical"]:
		var f := _field(fields, k)
		assert_false(RPGCommand._visible(f, {"damage_type": "none"}, fields), "%s hidden for None" % k)
		assert_false(RPGCommand._visible(f, {}, fields), "%s hidden on a record without the field" % k)
		assert_true(RPGCommand._visible(f, {"damage_type": "drain"}, fields), "%s shown for Drain" % k)
		assert_true(bool(f.get("drop_hidden", false)), k)
	for k in ["hit", "hit_type"]:
		assert_true(RPGCommand._visible(_field(fields, k), {"damage_type": "none"}, fields), "%s always shows: effects use it too" % k)
	var rec := RPGRecordSchemas.new_record("items", "new_item", fields)
	assert_eq(rec.get("damage_type"), "none")
	assert_eq(int(rec.get("hit", -1)), 100)
	assert_eq(rec.get("hit_type"), "certain")
	for k in ["resource", "element", "formula", "variance", "critical"]:
		assert_false(rec.has(k), "a new item has no '%s'" % k)


func test_an_older_item_with_a_formula_shows_as_damage() -> void:
	var old: Dictionary = db.record("items", "old_bomb")
	var shown := RPGRecordSchemas.for_form("items", old)
	assert_eq(shown.get("damage_type"), "damage", "the form shows what the game does")
	assert_false(old.has("damage_type"), "the record itself is untouched")
	var potion := {"id": "potion", "name": "Potion", "effects": [{"kind": "recover", "amount": 50}]}
	assert_true(RPGRecordSchemas.for_form("items", potion) == potion, "an item with no formula is shown as it is")
	var bomb: Dictionary = db.record("items", "fire_bomb")
	assert_true(RPGRecordSchemas.for_form("items", bomb) == bomb)


func test_the_validator_checks_item_elements_and_lets_normal_attack_be() -> void:
	var files := {
		"res://rpg/database/types.json": {"kind": "database", "db_type": "types", "data": {"records": [db.record("types", "elements")]}},
		"res://rpg/database/skills.json": {"kind": "database", "db_type": "skills", "data": {"records": [
			{"id": "weapon_strike", "name": "Weapon Strike", "element": "normal_attack"},
			{"id": "odd", "name": "Odd", "element": "wind"}]}},
		"res://rpg/database/items.json": {"kind": "database", "db_type": "items", "data": {"records": [
			{"id": "dart", "name": "Dart", "element": "normal_attack"},
			{"id": "fire_bomb", "name": "Fire Bomb", "element": "fire"},
			{"id": "mud", "name": "Mud", "element": "earth"}]}},
	}
	var refs := RPGValidator.type_refs(files).filter(func(r): return r.field == "element")
	var ids := refs.map(func(r): return "%s:%s" % [r.record, r.id])
	ids.sort()
	assert_eq(ids, ["fire_bomb:fire", "mud:earth", "odd:wind"], "Normal Attack is not a reference to Types > Elements")
	var msgs := RPGValidator.database_values(files).filter(func(p): return str(p.field) == "element").map(func(p): return str(p.message))
	assert_eq(msgs.size(), 2, str(msgs))
	assert_true(msgs.any(func(m): return m.contains("'earth'")), "an item's unknown element is reported: %s" % str(msgs))
