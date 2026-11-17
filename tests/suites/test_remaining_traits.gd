extends "res://tests/rpg_test_case.gd"
## The remaining VX Ace / MV traits (#47): Attack State, Attack Speed, Add / Seal Skill, Equip
## Weapon / Armor Type, the Auto Battle, Guard and Substitute special flags, and the Collapse
## Effect — each applied where RPG Maker applies it, and invisible to a rules set whose data
## never uses them.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"},
		{"id": "body", "name": "Body", "kind": "armor"}]})
	db.add("types", {"id": "weapon_types", "entries": [
		{"id": "sword", "name": "Sword"}, {"id": "axe", "name": "Axe"}]})
	db.add("types", {"id": "armor_types", "entries": [
		{"id": "light", "name": "Light"}, {"id": "heavy", "name": "Heavy"}]})
	db.add("classes", {"id": "soldier", "name": "Soldier",
		"growth": {"mhp": 450, "mmp": 80, "atk": 20, "def": 10, "mat": 20, "mdf": 20, "agi": 30, "luk": 20},
		"equip": {"weapon_types": ["sword"], "armor_types": ["light"]},
		"traits": [{"kind": "add_skill_type", "id": "magic"}]})
	db.add("classes", {"id": "brawler", "name": "Brawler",
		"growth": {"mhp": 500, "mmp": 100, "atk": 50, "def": 20, "mat": 30, "mdf": 20, "agi": 20, "luk": 10}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {"weapon": "sword"},
		"skills": ["fire", "hit100", "mend"]})
	db.add("actors", {"id": "bruno", "name": "Bruno", "class": "brawler", "equips": {}})
	db.add("enemies", {"id": "slime", "name": "Slime",
		"stats": {"mhp": 500, "mmp": 0, "atk": 30, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("enemies", {"id": "titan", "name": "Titan", "collapse": "boss",
		"stats": {"mhp": 500, "mmp": 0, "atk": 30, "def": 10, "mat": 10, "mdf": 10, "agi": 10, "luk": 10},
		"actions": [{"skill": "attack", "rating": 5}], "skills": []})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	# Aim and flat feet make the physical hit checks certain (a.hit 100, b.eva 0); Ex-Parameter
	# traits replace the default, so the states carry the whole value.
	db.add("states", {"id": "true_aim", "name": "True Aim", "traits": [{"kind": "hit_rate", "value": 100}]})
	db.add("states", {"id": "flat_footed", "name": "Flat-footed", "traits": [{"kind": "evasion_rate", "value": 0}]})
	db.add("states", {"id": "venom", "name": "Venom"})
	db.add("states", {"id": "venom_blade", "name": "Venom Blade", "traits": [{"kind": "attack_state", "id": "venom", "value": 100}]})
	db.add("states", {"id": "dull_blade", "name": "Dull Blade", "traits": [{"kind": "attack_state", "id": "venom", "value": 0}]})
	db.add("states", {"id": "venom_proof", "name": "Venom Proof", "traits": [{"kind": "state_rate", "id": "venom", "value": 0}]})
	db.add("states", {"id": "swift", "name": "Swift", "traits": [{"kind": "attack_speed", "value": 500}]})
	db.add("states", {"id": "taught", "name": "Taught", "traits": [{"kind": "add_skill", "id": "stab100"}]})
	db.add("states", {"id": "muffled", "name": "Muffled", "traits": [{"kind": "seal_skill", "id": "fire"}]})
	db.add("states", {"id": "axe_rights", "name": "Axe Rights", "traits": [{"kind": "equip_weapon_type", "id": "axe"}]})
	db.add("states", {"id": "plate_rights", "name": "Plate Rights", "traits": [{"kind": "equip_armor_type", "id": "heavy"}]})
	db.add("states", {"id": "bound_hands", "name": "Bound Hands", "traits": [{"kind": "seal_equip", "id": "weapon"}]})
	db.add("states", {"id": "bulwark", "name": "Bulwark", "traits": [{"kind": "guard"}]})
	db.add("states", {"id": "protector", "name": "Protector", "traits": [{"kind": "substitute"}]})
	db.add("states", {"id": "berserk", "name": "Berserk", "traits": [{"kind": "auto_battle"}]})
	db.add("states", {"id": "iron_heart", "name": "Iron Heart", "traits": [{"kind": "collapse", "value": 2}]})
	db.add("skills", {"id": "hit100", "name": "Hit 100", "formula": "100", "hit_type": "certain", "variance": 0})
	db.add("skills", {"id": "stab100", "name": "Stab 100", "formula": "100", "hit_type": "physical", "variance": 0})
	db.add("skills", {"id": "mend", "name": "Mend", "formula": "300", "damage_type": "recover",
		"hit_type": "certain", "variance": 0, "scope": "one_ally"})
	db.add("skills", {"id": "fire", "name": "Fire", "skill_type": "magic", "formula": "100 + a.mat * 2 - b.mdf * 2",
		"hit_type": "magical", "hit": 100, "variance": 0, "cost": {"mp": 5}, "scope": "one_enemy"})
	db.add("weapons", {"id": "sword", "name": "Sword", "weapon_type": "sword"})
	db.add("weapons", {"id": "axe", "name": "Axe", "weapon_type": "axe"})
	db.add("armors", {"id": "leather", "name": "Leather", "armor_type": "light", "slot": "body"})
	db.add("armors", {"id": "plate", "name": "Plate", "armor_type": "heavy", "slot": "body"})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(4242)


func _pair() -> Array:
	var eric := rules.new_actor_battler("eric", 1)
	var bruno := rules.new_actor_battler("bruno", 1)
	rules.add_state(eric, "true_aim")
	rules.add_state(bruno, "flat_footed")
	return [eric, bruno]


func _core(party_ids: Array, enemy_id: String, seed_value: int) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var troop := {"id": "solo", "name": "Solo",
		"members": [{"enemy": enemy_id, "hidden": false, "position": [120, 150]}], "pages": []}
	var core := RPGBattleCore.new(party, troop, rules, RPGRandom.new(seed_value))
	core.start()
	return core


# --- Attack State ---------------------------------------------------------------------------

func test_attack_state_lands_on_normal_attacks() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	rules.add_state(eric, "venom_blade")
	var r := rules.apply_action(eric, bruno, {"kind": "attack"})
	assert_true(r.hit, "the attack connects")
	assert_true(bruno.has_state("venom"), "the attack state lands")
	assert_has(bruno.states.map(func(s): return s.id), "venom")

func test_attack_state_spares_skills_and_resists() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	rules.add_state(eric, "venom_blade")
	rules.apply_action(eric, bruno, {"kind": "skill", "skill": "hit100"})
	assert_false(bruno.has_state("venom"), "a skill does not carry the attack state")
	rules.add_state(bruno, "venom_proof")
	rules.apply_action(eric, bruno, {"kind": "attack"})
	assert_false(bruno.has_state("venom"), "the target's State Rate can resist it")
	rules.remove_state(bruno, "venom_proof")
	rules.remove_state(eric, "venom_blade")
	rules.add_state(eric, "dull_blade")
	rules.apply_action(eric, bruno, {"kind": "attack"})
	assert_false(bruno.has_state("venom"), "a 0% attack state never lands")


# --- Attack Speed ---------------------------------------------------------------------------

func test_attack_speed_joins_the_turn_order_roll() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	# The turn-order roll draws the RNG, so both measurements start from the same seed.
	rules.rng = RPGRandom.new(77)
	var plain := rules.action_speed(eric, {"kind": "attack"})
	rules.add_state(eric, "swift")
	rules.rng = RPGRandom.new(77)
	assert_eq(rules.action_speed(eric, {"kind": "attack"}), plain + 500, "Attack Speed adds to attacks")
	var u := rules.resolve_action(eric, {"kind": "attack"})
	assert_eq(int(u.get("speed", 0)), 500, "the resolved attack carries the speed")
	var fire := rules.resolve_action(eric, {"kind": "skill", "skill": "fire"})
	assert_eq(int(fire.get("speed", 0)), 0, "other skills are untouched")


# --- Add / Seal Skill -----------------------------------------------------------------------

func test_add_and_seal_skill() -> void:
	var bruno := rules.new_actor_battler("bruno", 1)
	assert_false(rules.known_skills(bruno).has("stab100"), "not known before")
	rules.add_state(bruno, "taught")
	assert_true(rules.known_skills(bruno).has("stab100"), "an Add Skill trait grants it")
	assert_true(rules.can_use(bruno, {"kind": "skill", "skill": "stab100"}), "and it is usable")
	var eric := rules.new_actor_battler("eric", 1)
	assert_true(rules.known_skills(eric).has("fire"), "learned skills stay")
	rules.add_state(eric, "muffled")
	assert_false(rules.known_skills(eric).has("fire"), "a Seal Skill trait removes it")
	assert_false(rules.can_use(eric, {"kind": "skill", "skill": "fire"}), "and it cannot be used")
	var core := _core(["eric"], "slime", 4242)
	rules.add_state(core.party[0], "muffled")
	assert_false(core.set_action(0, {"kind": "skill", "skill": "fire"}), "battle refuses the sealed skill")
	rules.remove_state(core.party[0], "muffled")
	rules.add_state(core.party[0], "taught")
	assert_true(core.set_action(0, {"kind": "skill", "skill": "stab100"}), "battle accepts the granted skill")


# --- Equip Weapon / Armor Type --------------------------------------------------------------

func test_equip_type_traits() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	assert_true(rules.can_equip(eric, "weapon", "sword"), "the class's list allows the sword")
	assert_false(rules.can_equip(eric, "weapon", "axe"), "not the axe")
	assert_true(rules.can_equip(eric, "body", "leather"), "light armour fits the class")
	assert_false(rules.can_equip(eric, "body", "plate"), "heavy armour does not")
	rules.add_state(eric, "axe_rights")
	assert_true(rules.can_equip(eric, "weapon", "axe"), "an Equip Weapon Type trait widens the list")
	rules.add_state(eric, "plate_rights")
	assert_true(rules.can_equip(eric, "body", "plate"), "an Equip Armor Type trait widens it too")
	var bruno := rules.new_actor_battler("bruno", 1)
	assert_true(rules.can_equip(bruno, "weapon", "axe"), "a class without lists allows every weapon")
	assert_true(rules.can_equip(bruno, "body", "plate"), "and every armour")
	assert_false(rules.can_equip(bruno, "weapon", "leather"), "armour is still not a weapon")
	rules.add_state(eric, "bound_hands")
	assert_false(rules.can_equip(eric, "weapon", "sword"), "a sealed slot equips nothing")


# --- Guard special flag ---------------------------------------------------------------------

func test_guard_special_flag_always_guards() -> void:
	var pair := _pair()
	var eric = pair[0]
	var bruno = pair[1]
	assert_eq(rules.apply_action(eric, bruno, {"kind": "skill", "skill": "hit100"}).damage, 100, "unguarded")
	rules.add_state(bruno, "bulwark")
	assert_eq(rules.apply_action(eric, bruno, {"kind": "skill", "skill": "hit100"}).damage, 50,
		"the Guard flag halves damage without guarding")


# --- Substitute -----------------------------------------------------------------------------

func test_substitute_covers_a_dying_ally() -> void:
	var core := _core(["eric", "bruno"], "slime", 12345)
	var eric: RPGBattler = core.party[0]
	var bruno: RPGBattler = core.party[1]
	var slime: RPGBattler = core.enemies[0]
	rules.add_state(bruno, "protector")
	rules.add_state(bruno, "flat_footed")
	rules.add_state(slime, "true_aim")
	eric.set_resource("hp", 20)
	var res: Dictionary = core.force(slime, {"kind": "attack", "target": 0})
	assert_true(bruno.get_resource("hp") < rules.max_resource(bruno, "hp"), "the substitute takes the hit")
	assert_eq(eric.get_resource("hp"), 20, "the dying ally is untouched")
	assert_has(res.lines, "Bruno covers Eric!")

func test_substitute_stays_home_otherwise() -> void:
	var core := _core(["eric", "bruno"], "slime", 12345)
	var eric: RPGBattler = core.party[0]
	var bruno: RPGBattler = core.party[1]
	var slime: RPGBattler = core.enemies[0]
	rules.add_state(bruno, "protector")
	rules.add_state(bruno, "flat_footed")
	rules.add_state(slime, "true_aim")
	var res: Dictionary = core.force(slime, {"kind": "attack", "target": 0})
	assert_eq(bruno.get_resource("hp"), rules.max_resource(bruno, "hp"), "a healthy ally is not covered")
	assert_true(eric.get_resource("hp") < rules.max_resource(eric, "hp"), "the target takes it")
	assert_false(res.lines.has("Bruno covers Eric!"))
	eric.set_resource("hp", 20)
	res = core.force(slime, {"kind": "skill", "skill": "hit100", "target": 0})
	assert_eq(eric.get_resource("hp"), 0, "a certain hit cannot be covered")
	assert_eq(bruno.get_resource("hp"), rules.max_resource(bruno, "hp"), "and nobody steps in")


# --- Auto Battle ----------------------------------------------------------------------------

func test_auto_battle_picks_its_own_action() -> void:
	var core := _core(["eric"], "slime", 4242)
	var eric: RPGBattler = core.party[0]
	rules.add_state(eric, "berserk")
	assert_eq(core.inputs_needed().size(), 0, "no command is asked for")
	core.begin_turn()
	eric.set_resource("hp", 100)
	var r := core.next_action()
	assert_eq(str(r.kind), "skill", "a hurt actor mends itself")
	assert_true(eric.get_resource("hp") > 100, "the heal landed")
	assert_eq(str(r.action.get("skill", "")), "mend", "it picked the recovery skill")

func test_auto_battle_falls_back_to_the_best_hit() -> void:
	var core := _core(["eric"], "slime", 4242)
	var eric: RPGBattler = core.party[0]
	var slime: RPGBattler = core.enemies[0]
	rules.add_state(eric, "berserk")
	core.begin_turn()
	var hp: int = slime.get_resource("hp")
	var r := core.next_action()
	assert_eq(str(r.action.get("skill", "")), "fire", "at full health it throws the strongest spell")
	assert_true(slime.get_resource("hp") < hp, "which hurts the foe")
	var plain := _core(["bruno"], "slime", 4242)
	rules.add_state(plain.party[0], "berserk")
	assert_eq(plain.inputs_needed().size(), 0, "still no command")
	plain.begin_turn()
	var r2 := plain.next_action()
	assert_eq(str(r2.kind), "attack", "with no skills it attacks")


# --- Collapse Effect ------------------------------------------------------------------------

func test_collapse_kind() -> void:
	var slime := rules.new_enemy_battler("slime")
	assert_eq(rules.collapse_kind(slime), "normal", "the default")
	var titan := rules.new_enemy_battler("titan")
	assert_eq(rules.collapse_kind(titan), "boss", "an enemy record can set it")
	rules.add_state(titan, "iron_heart")
	assert_eq(rules.collapse_kind(titan), "instant", "a trait overrides the record")
	rules.remove_state(titan, "iron_heart")
	var bruno := rules.new_actor_battler("bruno", 1)
	rules.add_state(bruno, "iron_heart")
	assert_eq(rules.collapse_kind(bruno), "instant", "actors can carry it too")


# --- Classic rules are untouched ------------------------------------------------------------

func test_classic_rules_are_untouched() -> void:
	var classic := RPGRuleSystem.load_rules("classic", FakeDB.from_folder("res://rpg/database"))
	var hero := classic.new_actor_battler("hero", 1)
	assert_eq(classic.known_skills(hero), hero.skills, "no traits, no change")
	assert_eq(classic.collapse_kind(hero), "normal", "no collapse traits")
	var u := classic.resolve_action(hero, {"kind": "attack"})
	assert_true((u.get("effects", []) as Array).is_empty(), "an attack carries no extra effects")
