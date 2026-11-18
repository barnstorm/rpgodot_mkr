extends "res://tests/rpg_test_case.gd"
## Seal Equip, Dual Wield and Fix Equip from any trait source, equipment included (issue #150):
## a two-handed sword that seals the shield slot, a weapon that turns the shield slot into a
## weapon slot, and slots the Equip menu may not change.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")
const Env := preload("res://tests/rpg_test_env.gd")

var db
var rules: RPGRuleSystem
var env


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"},
		{"id": "shield", "name": "Shield", "kind": "armor"},
		{"id": "body", "name": "Body", "kind": "armor"},
		{"id": "accessory", "name": "Accessory", "kind": "armor"}]})
	var growth := {"mhp": 500, "mmp": 100, "atk": 20, "def": 10, "mat": 20, "mdf": 10, "agi": 20, "luk": 10}
	db.add("classes", {"id": "soldier", "name": "Soldier", "growth": growth,
		"equip": {"weapon_types": ["sword"], "armor_types": ["light", "shield"]}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier",
		"equips": {"weapon": "short_sword", "shield": "buckler", "body": "tunic", "accessory": ""}})
	db.add("actors", {"id": "held", "name": "Held", "class": "soldier", "equips": {"weapon": "short_sword"},
		"traits": [{"kind": "fix_equip", "id": "weapon"}]})
	db.add("actors", {"id": "statue", "name": "Statue", "class": "soldier", "equips": {"weapon": "short_sword"},
		"traits": [{"kind": "fix_equip"}]})
	db.add("weapons", {"id": "short_sword", "name": "Short Sword", "weapon_type": "sword", "params": {"atk": 10}})
	db.add("weapons", {"id": "dagger", "name": "Dagger", "weapon_type": "sword", "params": {"atk": 5}})
	# Tutorial 4: a two-handed sword with the feature Seal Equip: Shield.
	db.add("weapons", {"id": "greatsword", "name": "Greatsword", "weapon_type": "sword", "params": {"atk": 30},
		"traits": [{"kind": "seal_equip", "id": "shield"}]})
	db.add("weapons", {"id": "twin_blade", "name": "Twin Blade", "weapon_type": "sword", "params": {"atk": 8},
		"traits": [{"kind": "dual_wield", "id": "shield"}]})
	db.add("armors", {"id": "buckler", "name": "Buckler", "armor_type": "shield", "slot": "shield", "params": {"def": 5}})
	db.add("armors", {"id": "tunic", "name": "Tunic", "armor_type": "light", "slot": "body", "params": {"def": 3}})
	db.add("armors", {"id": "plate", "name": "Plate", "armor_type": "heavy", "slot": "body", "params": {"def": 15}})
	db.add("armors", {"id": "badge", "name": "Squire's Badge", "armor_type": "light", "slot": "accessory",
		"traits": [{"kind": "equip_armor_type", "id": "heavy"}]})
	# Two pieces that seal each other's slot.
	db.add("armors", {"id": "binding_mail", "name": "Binding Mail", "armor_type": "light", "slot": "body", "params": {"def": 8},
		"traits": [{"kind": "seal_equip", "id": "accessory"}]})
	db.add("armors", {"id": "jealous_ring", "name": "Jealous Ring", "armor_type": "light", "slot": "accessory", "params": {"def": 2},
		"traits": [{"kind": "seal_equip", "id": "body"}]})
	# A cursed ring: once on, the Equip menu cannot take it off.
	db.add("armors", {"id": "cursed_ring", "name": "Cursed Ring", "armor_type": "light", "slot": "accessory",
		"traits": [{"kind": "fix_equip", "id": "accessory"}]})
	db.add("armors", {"id": "sheath", "name": "Off-hand Sheath", "armor_type": "shield", "slot": "shield",
		"traits": [{"kind": "dual_wield", "id": "shield"}]})
	db.add("enemies", {"id": "ogre", "name": "Ogre", "stats": {"mhp": 300, "mmp": 0, "atk": 10, "def": 5, "mat": 5, "mdf": 5, "agi": 5, "luk": 5},
		"traits": [{"kind": "seal_equip", "id": "weapon"}]})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "bound_hands", "name": "Bound Hands", "traits": [{"kind": "seal_equip", "id": "weapon"}]})
	rules = RPGRuleSystem.load_rules("vx_ace", db)


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


func _def(b: RPGBattler) -> int:
	return int(rules.effective_stat(b, "def"))


func _atk(b: RPGBattler) -> int:
	return int(rules.effective_stat(b, "atk"))


func test_a_weapon_seals_the_shield_slot() -> void:
	var eric := rules.new_actor_battler("eric")
	assert_eq(_def(eric), 18, "10 + buckler 5 + tunic 3")
	assert_false(rules.is_slot_sealed(eric, "shield"))
	eric.equips["weapon"] = "greatsword"
	assert_true(rules.is_slot_sealed(eric, "shield"), "Seal Equip on the weapon counts")
	assert_eq(_def(eric), 13, "the buckler in the sealed slot does not count")
	assert_eq(_atk(eric), 50, "20 + greatsword 30")
	assert_false(rules.can_equip(eric, "shield", "buckler"), "nothing goes in a sealed slot")
	assert_false(rules.equip_change_ok(eric, "shield"))
	assert_true(rules.equip_change_ok(eric, "weapon"))
	var st := rules.equip_state(eric)
	assert_eq(st.sealed, ["shield"])
	assert_false(st.records.has("shield"))
	assert_true(st.records.has("weapon") and st.records.has("body"))
	eric.equips["weapon"] = "short_sword"
	assert_false(rules.is_slot_sealed(eric, "shield"), "the seal goes with the weapon")
	assert_eq(_def(eric), 18)


func test_equipping_the_sealing_weapon_takes_the_shield_off() -> void:
	var eric := rules.new_actor_battler("eric")
	var off := rules.set_equip(eric, "weapon", "greatsword")
	assert_eq(off, [{"slot": "shield", "item": "buckler", "kind": "armor"}], "the buckler comes off, to go back to the bag")
	assert_eq(str(eric.equips["shield"]), "")
	assert_eq(str(eric.equips["weapon"]), "greatsword")
	assert_eq(str(eric.equips["body"]), "tunic", "nothing else moves")
	assert_eq(rules.set_equip(eric, "weapon", "short_sword"), [], "an ordinary change takes nothing off")
	assert_eq(rules.set_equip(eric, "body", ""), [], "nor does taking something off")


func test_a_weapon_grants_dual_wield() -> void:
	var eric := rules.new_actor_battler("eric")
	assert_eq(rules.dual_wield_slots(eric), [])
	var off := rules.set_equip(eric, "weapon", "twin_blade")
	assert_eq(rules.dual_wield_slots(eric), ["shield"], "Dual Wield on the weapon counts")
	assert_eq(rules.equip_slot_kind(eric, "shield"), "weapon")
	assert_eq(off, [{"slot": "shield", "item": "buckler", "kind": "armor"}], "a shield does not fit a weapon slot")
	assert_true(rules.can_equip(eric, "shield", "dagger"), "a second weapon does")
	assert_false(rules.can_equip(eric, "shield", "buckler"))
	assert_eq(rules.set_equip(eric, "shield", "dagger"), [])
	assert_eq(_atk(eric), 33, "20 + twin blade 8 + dagger 5")
	assert_eq(rules.equipped_weapon_types(eric), ["sword"])
	# The Twin Blade comes off: the dagger no longer fits a shield slot and comes off as a weapon.
	off = rules.set_equip(eric, "weapon", "short_sword")
	assert_eq(off, [{"slot": "shield", "item": "dagger", "kind": "weapon"}])
	assert_eq(rules.dual_wield_slots(eric), [])
	assert_eq(_atk(eric), 30, "20 + short sword 10")


func test_an_item_that_stops_fitting_its_slot_stops_counting() -> void:
	# The Twin Blade is put in by hand over a worn buckler (starting equipment, a loaded save):
	# the buckler is in what is now a weapon slot, so it does not count.
	var eric := rules.new_actor_battler("eric")
	eric.equips["weapon"] = "twin_blade"
	assert_eq(_def(eric), 13, "10 + tunic 3")
	assert_false(rules.equip_state(eric).records.has("shield"))
	# A sheath that grants Dual Wield from the very slot it turns into a weapon slot: it stops
	# fitting there, so it does not count, and neither does its Dual Wield.
	var solo := rules.new_actor_battler("eric")
	solo.equips["shield"] = "sheath"
	assert_eq(rules.dual_wield_slots(solo), [], "settles instead of flipping back and forth")
	assert_false(rules.equip_state(solo).records.has("shield"))


func test_two_pieces_that_seal_each_other() -> void:
	var eric := rules.new_actor_battler("eric")
	eric.equips["body"] = "binding_mail"
	eric.equips["accessory"] = "jealous_ring"
	# As RPG Maker: slot by slot in order. The body comes first and is sealed by the ring, so
	# the mail stops counting, and with it its seal on the accessory slot.
	var st := rules.equip_state(eric)
	assert_false(st.records.has("body"), "the mail is out")
	assert_true(st.records.has("accessory"), "so the ring stays")
	assert_eq(st.sealed, ["body"])
	assert_eq(_def(eric), 17, "10 + buckler 5 + ring 2")
	# Through the menu's path the mail goes back to the bag.
	var fresh := rules.new_actor_battler("eric")
	fresh.equips["body"] = "binding_mail"
	assert_eq(rules.set_equip(fresh, "accessory", "jealous_ring"), [{"slot": "body", "item": "binding_mail", "kind": "armor"}])


func test_what_a_removed_piece_allowed_comes_off_with_it() -> void:
	var eric := rules.new_actor_battler("eric")
	assert_eq(rules.set_equip(eric, "accessory", "badge"), [])
	assert_true(rules.can_equip(eric, "body", "plate"), "the badge allows heavy armour")
	assert_eq(rules.set_equip(eric, "body", "plate"), [])
	assert_eq(rules.set_equip(eric, "accessory", ""), [{"slot": "body", "item": "plate", "kind": "armor"}],
		"without the badge he may not wear the plate")
	assert_eq(str(eric.equips["body"]), "")


func test_what_was_already_unwearable_is_left_alone() -> void:
	# Starting equipment the class may not wear (the editor warns about it) is not stripped by
	# an unrelated change.
	var eric := rules.new_actor_battler("eric")
	eric.equips["body"] = "plate"
	assert_eq(rules.unwearable_slots(eric), ["body"])
	assert_eq(rules.set_equip(eric, "weapon", "dagger"), [])
	assert_eq(str(eric.equips["body"]), "plate")
	# A state's seal leaves the item where it is: it only stops counting.
	var bound := rules.new_actor_battler("eric")
	rules.add_state(bound, "bound_hands")
	assert_true(rules.is_slot_sealed(bound, "weapon"))
	assert_eq(_atk(bound), 20)
	assert_eq(rules.set_equip(bound, "body", ""), [])
	assert_eq(str(bound.equips["weapon"]), "short_sword")
	rules.remove_state(bound, "bound_hands")
	assert_eq(_atk(bound), 30, "and counts again when the state ends")


func test_fix_equip() -> void:
	assert_true(rules.declares_trait("fix_equip"), "the VX Ace rules offer the trait")
	var shipped := RPGRuleSystem.load_rules_from_dir("res://addons/rpg/runtime/rules/vx_ace", db)
	assert_true(shipped.declares_trait("fix_equip"), "the copy shipped in the addon agrees")
	var held := rules.new_actor_battler("held")
	assert_true(rules.is_slot_fixed(held, "weapon"))
	assert_false(rules.is_slot_fixed(held, "shield"))
	assert_false(rules.equip_change_ok(held, "weapon"), "the menu may not change it")
	assert_true(rules.equip_change_ok(held, "shield"))
	assert_false(rules.is_slot_sealed(held, "weapon"), "fixed is not sealed")
	assert_eq(_atk(held), 30, "what is in a fixed slot counts")
	assert_true(rules.can_equip(held, "weapon", "dagger"), "Change Equipment is not held back")
	# No slot named: every slot, VX's actor option Fix Equipment.
	var statue := rules.new_actor_battler("statue")
	for slot in ["weapon", "shield", "body", "accessory"]:
		assert_true(rules.is_slot_fixed(statue, slot), slot)
	# From a piece of equipment: a cursed ring fixes its own slot.
	var eric := rules.new_actor_battler("eric")
	assert_true(rules.equip_change_ok(eric, "accessory"))
	assert_eq(rules.set_equip(eric, "accessory", "cursed_ring"), [], "being fixed takes nothing off")
	assert_true(rules.is_slot_fixed(eric, "accessory"))
	assert_false(rules.equip_change_ok(eric, "accessory"))


func test_enemies_and_the_classic_rules() -> void:
	var ogre := rules.new_enemy_battler("ogre")
	assert_true(rules.is_slot_sealed(ogre, "weapon"), "an enemy's own trait still reads")
	assert_eq(rules.equip_state(ogre).records, {})
	assert_eq(rules.unwearable_slots(ogre), [])
	assert_false(rules.is_slot_fixed(null, "weapon"))
	assert_eq(rules.equip_state(null).sealed, [])
	# The traits are read whatever the rule set.
	var classic := RPGRuleSystem.load_rules("classic", db)
	var eric := classic.new_actor_battler("eric")
	assert_eq(classic.set_equip(eric, "weapon", "greatsword"), [{"slot": "shield", "item": "buckler", "kind": "armor"}])


func test_the_validator_knows_fix_equip_names_a_slot() -> void:
	assert_eq(str(RPGValidator.TRAIT_REFS.get("fix_equip", "")), "equip_slot")


func test_the_equip_menu_and_change_equipment() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	rpg.state.new_game()
	var started: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(started.is_ok(), str(started))
	await env.settle()
	var hero: RPGBattler = rpg.state.actor("hero")
	var sword: Dictionary = rpg.data.db["weapons"].by_id["iron_sword"]
	var kept_sword: Variant = sword.get("traits")
	var hero_rec: Dictionary = rpg.data.db["actors"].by_id["hero"]
	var kept_hero: Variant = hero_rec.get("traits")
	sword["traits"] = [{"kind": "seal_equip", "id": "shield"}]
	rpg.state.change_items("iron_sword", "increase", 1, "weapons")
	rpg.state.change_items("wooden_shield", "increase", 1, "armors")
	var menu: Node = rpg.ui.open_scene(rpg.ui.scene_path("menu"))
	await frames(2)
	menu.equip_actor = hero
	assert_true(menu.equip(hero, "shield", "wooden_shield"), "the shield goes on")
	assert_eq(rpg.state.item_count("wooden_shield", "armors"), 0)
	# The two-handed sword: the shield comes off and is back in the bag, and its slot is locked.
	assert_true(menu.equip(hero, "weapon", "iron_sword"))
	assert_eq(str(hero.equips["weapon"]), "iron_sword")
	assert_eq(str(hero.equips["shield"]), "", "the shield came off")
	assert_eq(rpg.state.item_count("wooden_shield", "armors"), 1, "and is back in the bag")
	assert_eq(rpg.state.item_count("bronze_sword", "weapons"), 1, "with the old sword")
	assert_true(menu._locked("shield"), "the sealed slot is greyed out")
	assert_false(menu.equip(hero, "shield", "wooden_shield"), "and takes nothing")
	assert_eq(menu.candidates(hero, "shield"), [])
	# Change Equipment follows the same path: back to the bronze sword, then the event puts the
	# iron sword on again over a worn shield.
	assert_true(menu.equip(hero, "weapon", "bronze_sword"))
	assert_true(menu.equip(hero, "shield", "wooden_shield"))
	var r: RPGResult = await _run([{"type": "change_equipment", "actor": "hero", "slot": "weapon", "kind": "weapon", "item": "iron_sword"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(str(hero.equips["weapon"]), "iron_sword")
	assert_eq(str(hero.equips["shield"]), "")
	assert_eq(rpg.state.item_count("wooden_shield", "armors"), 1, "the event's change sends the shield back too")
	# Fix Equip: the menu's slot is locked, the event command still changes it.
	hero_rec["traits"] = [{"kind": "fix_equip", "id": "weapon"}]
	assert_true(menu._locked("weapon"), "a fixed slot is greyed out")
	assert_false(menu._locked("body"))
	r = await _run([{"type": "change_equipment", "actor": "hero", "slot": "weapon", "kind": "weapon", "item": "bronze_sword"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(str(hero.equips["weapon"]), "bronze_sword", "Change Equipment is not held back by Fix Equip")
	if kept_sword == null:
		sword.erase("traits")
	else:
		sword["traits"] = kept_sword
	if kept_hero == null:
		hero_rec.erase("traits")
	else:
		hero_rec["traits"] = kept_hero
