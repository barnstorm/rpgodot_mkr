extends "res://tests/rpg_test_case.gd"
## State restrictions (issue #6): the attack-at-random family RPG Maker calls Restriction —
## berserk (attack an enemy, Target Rate weighted), confusion (attack anyone, self included) and
## charm (attack an ally, never self) — plus Cannot Use Skills, ranked MV's way (the most
## limiting state wins) and announced by a log line that names the driving state.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "equip_slots", "entries": [
		{"id": "weapon", "name": "Weapon", "kind": "weapon"}]})
	db.add("types", {"id": "weapon_types", "entries": [
		{"id": "sword", "name": "Sword"}]})
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
		"actions": [{"skill": "glare", "rating": 5}], "skills": ["glare"]})
	# Berserk, confusion and charm are MV's three attack-at-random levels; silence and sleep are
	# the two stronger restrictions; trance's unknown value must rank as no restriction at all.
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "berserk", "name": "Berserk", "restriction": "attack_enemy"})
	db.add("states", {"id": "confusion", "name": "Confusion", "restriction": "attack_anyone",
		"remove_on_damage": 100})
	db.add("states", {"id": "charm", "name": "Charm", "restriction": "attack_ally"})
	db.add("states", {"id": "silence", "name": "Silence", "restriction": "cannot_use_skills"})
	db.add("states", {"id": "sleep", "name": "Sleep", "restriction": "cannot_act"})
	db.add("states", {"id": "trance", "name": "Trance", "restriction": "dance_party"})
	db.add("states", {"id": "autopilot", "name": "Autopilot", "traits": [{"kind": "auto_battle"}]})
	# Aim and flat feet make the physical hit checks certain (a.hit 100, b.eva 0).
	db.add("states", {"id": "true_aim", "name": "True Aim", "traits": [{"kind": "hit_rate", "value": 100}]})
	db.add("states", {"id": "flat_footed", "name": "Flat-footed", "traits": [{"kind": "evasion_rate", "value": -5}]})
	db.add("skills", {"id": "hit100", "name": "Hit 100", "formula": "100", "hit_type": "certain", "variance": 0})
	db.add("skills", {"id": "mend", "name": "Mend", "formula": "300", "damage_type": "recover",
		"hit_type": "certain", "variance": 0, "scope": "one_ally"})
	db.add("skills", {"id": "fire", "name": "Fire", "skill_type": "magic", "formula": "100 + a.mat * 2 - b.mdf * 2",
		"hit_type": "magical", "hit": 100, "variance": 0, "cost": {"mp": 5}, "scope": "one_enemy"})
	db.add("skills", {"id": "glare", "name": "Glare", "formula": "10", "hit_type": "certain", "variance": 0,
		"scope": "one_enemy"})
	db.add("weapons", {"id": "sword", "name": "Sword", "weapon_type": "sword"})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(4242)


func _core(party_ids: Array, enemy_id: String, seed_value: int) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var troop := {"id": "solo", "name": "Solo",
		"members": [{"enemy": enemy_id, "hidden": false, "position": [120, 150]}], "pages": []}
	var core := RPGBattleCore.new(party, troop, rules, RPGRandom.new(seed_value))
	core.start()
	return core


## Runs out the turn, collecting each battler's result by name.
func _turn_results(core: RPGBattleCore) -> Dictionary:
	core.begin_turn()
	var by_name := {}
	for i in 8:
		var r: Dictionary = core.next_action()
		if r.is_empty():
			break
		by_name[str(r.user.name)] = r
	return by_name


# --- Ranking ---------------------------------------------------------------------------------

func test_the_most_limiting_state_wins() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	assert_eq(rules.restriction(eric), "none", "no states, no restriction")
	rules.add_state(eric, "berserk")
	assert_eq(rules.restriction(eric), "attack_enemy", "berserk reads from the state")
	rules.add_state(eric, "confusion")
	assert_eq(rules.restriction(eric), "attack_anyone", "confusion is more limiting than berserk")
	rules.add_state(eric, "charm")
	assert_eq(rules.restriction(eric), "attack_ally", "charm more limiting still")
	rules.add_state(eric, "silence")
	assert_eq(rules.restriction(eric), "cannot_use_skills", "silence outranks attack-at-random")
	rules.add_state(eric, "sleep")
	assert_eq(rules.restriction(eric), "cannot_act", "cannot act outranks everything")
	for sid in ["sleep", "silence", "charm", "confusion", "berserk"]:
		rules.remove_state(eric, sid)
	rules.add_state(eric, "trance")
	assert_eq(rules.restriction(eric), "none", "an unknown value ranks as no restriction")

func test_confused_means_the_attack_restrictions() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	for sid in ["berserk", "confusion", "charm"]:
		rules.add_state(eric, sid)
		assert_true(rules.is_confused(eric), "%s makes the battler attack at random" % sid)
		assert_true(rules.can_act(eric), "%s still allows acting" % sid)
		rules.remove_state(eric, sid)
	for sid in ["silence", "sleep", "trance"]:
		rules.add_state(eric, sid)
		assert_false(rules.is_confused(eric), "%s does not attack at random" % sid)
		rules.remove_state(eric, sid)
	rules.add_state(eric, "sleep")
	assert_false(rules.can_act(eric), "only cannot-act stops actions")


# --- The command menu ------------------------------------------------------------------------

func test_confused_actor_skips_the_command_menu() -> void:
	var core := _core(["eric", "bruno"], "slime", 4242)
	var need := core.inputs_needed()
	assert_true(need.size() == 2 and need.has(0) and need.has(1), "both actors choose normally")
	rules.add_state(core.party[0], "confusion")
	need = core.inputs_needed()
	assert_true(need.size() == 1 and need.has(1), "the confused actor does not")
	rules.add_state(core.party[1], "sleep")
	assert_eq(core.inputs_needed().size(), 0, "sleep also stops input, the usual way")


# --- Berserk ---------------------------------------------------------------------------------

func test_berserk_strikes_a_foe() -> void:
	var core := _core(["eric"], "slime", 4242)
	var eric: RPGBattler = core.party[0]
	var slime: RPGBattler = core.enemies[0]
	rules.add_state(eric, "berserk")
	var r: Dictionary = _turn_results(core)["Eric"]
	assert_eq(str(r.kind), "attack", "the confused actor attacks")
	assert_true(r.targets.size() == 1 and r.targets[0] == slime, "the foe, Target Rate weighted")
	assert_has(r.lines, "Eric is driven by Berserk!", "the log names the driving state")
	assert_true(slime.get_resource("hp") < rules.max_resource(slime, "hp"), "and hurts it")


# --- Charm -----------------------------------------------------------------------------------

func test_charm_strikes_an_ally_never_self() -> void:
	var core := _core(["eric", "bruno"], "slime", 4242)
	var eric: RPGBattler = core.party[0]
	var bruno: RPGBattler = core.party[1]
	rules.add_state(bruno, "charm")
	var r: Dictionary = _turn_results(core)["Bruno"]
	assert_eq(str(r.kind), "attack", "charmed, Bruno attacks")
	assert_true(r.targets.size() == 1 and r.targets[0] == eric, "the only other ally, never himself")
	assert_has(r.lines, "Bruno is driven by Charm!", "the log names the driving state")
	assert_true(eric.get_resource("hp") < rules.max_resource(eric, "hp"), "the ally takes it")
	var solo := _core(["eric"], "slime", 4242)
	rules.add_state(solo.party[0], "charm")
	assert_eq(str(_turn_results(solo)["Eric"].kind), "wait", "with no other ally there is nobody to attack")


# --- Confusion -------------------------------------------------------------------------------

func test_confusion_can_strike_either_side() -> void:
	var ally_hits := 0
	var foe_hits := 0
	for seed_value in range(1, 21):
		var core := _core(["eric", "bruno"], "slime", seed_value)
		var eric: RPGBattler = core.party[0]
		var bruno: RPGBattler = core.party[1]
		var slime: RPGBattler = core.enemies[0]
		rules.add_state(eric, "confusion")
		var r: Dictionary = _turn_results(core)["Eric"]
		assert_eq(r.targets.size(), 1, "some living battler is always picked")
		var t = r.targets[0]
		assert_true(t == eric or t == bruno or t == slime, "seed %d: from one of both sides" % seed_value)
		if t == slime:
			foe_hits += 1
		else:
			ally_hits += 1
	assert_true(ally_hits > 0 and foe_hits > 0,
		"over twenty rolls confusion hits both sides (allies %d, foes %d)" % [ally_hits, foe_hits])

func test_confusion_beats_auto_battle() -> void:
	var core := _core(["eric"], "slime", 4242)
	var eric: RPGBattler = core.party[0]
	rules.add_state(eric, "autopilot")
	rules.add_state(eric, "berserk")
	var r: Dictionary = _turn_results(core)["Eric"]
	assert_eq(str(r.kind), "attack", "the restriction decides the action, not auto battle")
	assert_true(r.targets.size() == 1 and r.targets[0] == core.enemies[0], "a plain attack on the foe")


# --- Confused monsters -----------------------------------------------------------------------

func test_confused_enemy_skips_its_action_list() -> void:
	var plain := _core(["eric"], "slime", 4242)
	assert_eq(str(_turn_results(plain)["Slime"].action.get("skill", "")), "glare",
		"normally the monster follows its action list")
	var core := _core(["eric"], "slime", 4242)
	var eric: RPGBattler = core.party[0]
	rules.add_state(core.enemies[0], "berserk")
	var r: Dictionary = _turn_results(core)["Slime"]
	assert_eq(str(r.kind), "attack", "berserk overrides the action list")
	assert_true(r.targets.size() == 1 and r.targets[0] == eric, "it goes for the hero instead")
	assert_has(r.lines, "Slime is driven by Berserk!", "the log names the driving state")


# --- Silence ---------------------------------------------------------------------------------

func test_silence_locks_skills_but_not_attacks() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	assert_true(rules.can_use(eric, {"kind": "skill", "skill": "fire"}), "fire is usable normally")
	rules.add_state(eric, "silence")
	assert_false(rules.can_use(eric, {"kind": "skill", "skill": "fire"}), "a silenced battler cannot use skills")
	assert_true(rules.can_use(eric, {"kind": "attack"}), "attacking still works")
	var core := _core(["eric"], "slime", 4242)
	rules.add_state(core.party[0], "silence")
	assert_eq(core.inputs_needed().size(), 1, "they still get the command menu")
	assert_false(core.set_action(0, {"kind": "skill", "skill": "fire"}), "the battle refuses the skill")
	assert_true(core.set_action(0, {"kind": "attack", "target": 0}), "and accepts an attack")
	rules.add_state(core.party[0], "charm")
	assert_false(rules.is_confused(core.party[0]), "silence outranks charm")
	assert_eq(core.inputs_needed().size(), 1, "so they still choose commands")


# --- Wearing off -----------------------------------------------------------------------------

func test_confusion_wears_off_when_hit() -> void:
	var eric := rules.new_actor_battler("eric", 1)
	var bruno := rules.new_actor_battler("bruno", 1)
	rules.add_state(eric, "true_aim")
	rules.add_state(bruno, "flat_footed")
	rules.add_state(bruno, "confusion")
	var r := rules.apply_action(eric, bruno, {"kind": "attack"})
	assert_true(r.hit, "the attack connects")
	assert_false(bruno.has_state("confusion"), "remove-on-damage clears the confusion")
	assert_has(r.removed_states, "confusion")


# --- The shipped database and the validator ---------------------------------------------------

func test_classic_database_states_carry_restrictions() -> void:
	var classic := RPGRuleSystem.load_rules("classic", FakeDB.from_folder("res://rpg/database"))
	var hero := classic.new_actor_battler("hero", 1)
	assert_eq(classic.state_name("confusion"), "Confusion", "state names resolve for the log")
	classic.add_state(hero, "confusion")
	assert_true(classic.is_confused(hero), "the shipped Confusion state restricts the hero")
	assert_eq(classic.restriction(hero), "attack_anyone", "at MV's attack-anyone level")
	classic.add_state(hero, "sleep")
	assert_eq(classic.restriction(hero), "cannot_act", "and the shipped Sleep still outranks it")

func test_validator_rejects_unknown_restrictions() -> void:
	var files := {"rpg/database/states.json": {"kind": "database", "db_type": "states", "data": {"records": [
		{"id": "ok", "name": "OK", "restriction": "attack_ally"},
		{"id": "bad", "name": "Bad", "restriction": "dance"},
	]}}}
	var probs: Array = RPGValidator.database_values(files)
	var msgs := probs.map(func(p): return str(p.record) + ": " + str(p.message))
	assert_false(msgs.any(func(m): return m.begins_with("ok:")), "a listed restriction passes: %s" % [msgs])
	assert_true(msgs.any(func(m): return m.begins_with("bad:") and m.contains("not one of")), str(msgs))
