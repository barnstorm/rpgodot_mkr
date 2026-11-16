extends "res://tests/rpg_test_case.gd"
## Party abilities (VX Ace / MV, #48): a trait any party member carries applies to the whole
## party. Encounter Half / Encounter None reach the walking rules, Cancel Surprise and Raise
## Preemptive the preemptive / surprise roll, Gold Double and Drop Item Double the rewards.
## The traits are read rule-agnostically from the member records, so these tests run under the
## Classic sample data too; the vx_ace rules.json is only the editor's trait vocabulary.

const Env := preload("res://tests/rpg_test_env.gd")
const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var env


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _classic() -> Array:
	var db = FakeDB.from_folder("res://rpg/database")
	return [db, RPGRuleSystem.load_rules("classic", db)]


## Adds a party-ability trait to a database record, in place.
func _trait(rec: Dictionary, kind: String, value := 0) -> void:
	var t := {"kind": kind}
	if value != 0:
		t["value"] = value
	rec["traits"].append(t)


## Runs a whole battle with automatic actions (actors attack). Returns the result.
func _auto(core: RPGBattleCore, max_turns := 60) -> String:
	while core.battle_over() == "" and core.turn < max_turns:
		core.begin_turn()
		var r := core.next_action()
		while not r.is_empty():
			r = core.next_action()
		for t in core.end_turn():
			pass
	return core.battle_over()


func _core(db, rules: RPGRuleSystem, party_ids: Array, seed: int) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var core := RPGBattleCore.new(party, db.record("troops", "slimes"), rules, RPGRandom.new(seed))
	core.start()
	return core


# --- the trait helpers ---------------------------------------------------------------------------


func test_any_members_trait_applies_and_rates_multiply() -> void:
	var s := _classic()
	var rules: RPGRuleSystem = s[1]
	var hero := rules.new_actor_battler("hero", 1)
	var mira := rules.new_actor_battler("mira", 1)
	var party := [hero, mira]
	assert_false(rules.party_has_trait(party, "cancel_surprise"), "nobody carries it yet")
	assert_eq(rules.party_trait_rate(party, "gold_double"), 1.0, "no trait, no change")
	# Only Mira carries them: one member is enough for the whole party.
	_trait(s[0].record("actors", "mira"), "cancel_surprise")
	_trait(s[0].record("actors", "mira"), "gold_double", 200)
	assert_true(rules.party_has_trait(party, "cancel_surprise"), "any member's flag counts")
	assert_eq(rules.party_trait_rate(party, "gold_double"), 2.0, "one 200% holder doubles")
	# Percent traits multiply across members, like MV's gold rate.
	_trait(s[0].record("actors", "hero"), "gold_double", 200)
	assert_eq(rules.party_trait_rate(party, "gold_double"), 4.0, "two 200% holders quadruple")


# --- the battle-start roll ------------------------------------------------------------------------


func test_cancel_surprise_and_raise_preemptive_shape_the_odds() -> void:
	var troop_rec: Dictionary
	var base: Dictionary
	var s := _classic()
	troop_rec = s[0].record("troops", "slimes")
	base = RPGBattleCore.encounter_rates(s[1], [s[1].new_actor_battler("hero", 1)], troop_rec)
	assert_true(base.preemptive > 0.0 and base.surprise > 0.0, "the base roll has both chances")
	# Cancel Surprise: the ambush chance is gone, the first-strike one untouched.
	s = _classic()
	_trait(s[0].record("actors", "hero"), "cancel_surprise")
	var calm: Dictionary = RPGBattleCore.encounter_rates(s[1], [s[1].new_actor_battler("hero", 1)], s[0].record("troops", "slimes"))
	assert_eq(calm.surprise, 0.0, "Cancel Surprise removes the ambush")
	assert_eq(calm.preemptive, base.preemptive, "and touches nothing else")
	# Raise Preemptive: the first-strike chance quadruples, the ambush one untouched.
	s = _classic()
	_trait(s[0].record("actors", "hero"), "raise_preemptive")
	var up: Dictionary = RPGBattleCore.encounter_rates(s[1], [s[1].new_actor_battler("hero", 1)], s[0].record("troops", "slimes"))
	assert_eq(up.preemptive, base.preemptive * 4.0, "Raise Preemptive quadruples the first strike")
	assert_eq(up.surprise, base.surprise, "and touches nothing else")


func test_the_advantage_roll_follows_the_shaped_odds() -> void:
	var s := _classic()
	var rules: RPGRuleSystem = s[1]
	var troop: Dictionary = s[0].record("troops", "slimes")
	var party := [rules.new_actor_battler("hero", 1)]
	var base: Dictionary = RPGBattleCore.encounter_rates(rules, party, troop)
	# A roll inside the ambush window: an ambush without help, a normal start with the ability.
	var in_ambush := float(base.preemptive) + float(base.surprise) * 0.5
	assert_eq(RPGBattleCore.encounter_advantage(rules, party, troop, in_ambush), "surprise")
	_trait(s[0].record("actors", "hero"), "cancel_surprise")
	assert_eq(RPGBattleCore.encounter_advantage(rules, party, troop, in_ambush), "normal",
		"Cancel Surprise turns the would-be ambush into a normal start")
	# Twice the base first-strike chance: only preemptive once Raise Preemptive widens it.
	var raised := float(base.preemptive) * 2.0
	assert_ne(RPGBattleCore.encounter_advantage(rules, party, troop, raised), "preemptive",
		"the base chance is too small for this roll")
	_trait(s[0].record("actors", "hero"), "raise_preemptive")
	assert_eq(RPGBattleCore.encounter_advantage(rules, party, troop, raised), "preemptive",
		"Raise Preemptive makes the same roll a first strike")


# --- the rewards -----------------------------------------------------------------------------------


func test_gold_double_multiplies_the_gold_not_the_exp() -> void:
	var s := _classic()
	var rules: RPGRuleSystem = s[1]
	_trait(s[0].record("actors", "hero"), "gold_double", 200)
	var core := _core(s[0], rules, ["hero"], 12345)
	assert_eq(_auto(core), "win")
	var rw: Dictionary = core.rewards()
	assert_eq(rw.gold, 32, "200% Gold Double doubles the 16 gold")
	assert_eq(rw.exp, 12, "the experience is not multiplied")
	# Two members carrying it: 200% x 200% = 400%.
	_trait(s[0].record("actors", "mira"), "gold_double", 200)
	core = _core(s[0], rules, ["hero", "mira"], 12345)
	assert_eq(_auto(core), "win")
	assert_eq(core.rewards().gold, 64, "two holders quadruple the gold")


func test_drop_double_makes_a_coin_flip_drop_certain() -> void:
	var s := _classic()
	var rules: RPGRuleSystem = s[1]
	# Both slimes drop a potion at 50%: normally a coin flip each, doubled to a sure thing.
	s[0].record("enemies", "slime")["drops"] = [{"kind": "item", "id": "potion", "chance": 50}]
	_trait(s[0].record("actors", "hero"), "drop_double", 200)
	for seed in [1, 7, 12345]:
		var core := _core(s[0], rules, ["hero"], seed)
		assert_eq(_auto(core), "win")
		var rw: Dictionary = core.rewards()
		assert_eq(rw.items.size(), 1, "both potions drop and merge (seed %d)" % seed)
		assert_eq(rw.items[0].count, 2, "one per slime (seed %d)" % seed)


func test_a_half_chance_drop_stays_a_coin_flip() -> void:
	var s := _classic()
	var rules: RPGRuleSystem = s[1]
	s[0].record("enemies", "slime")["drops"] = [{"kind": "item", "id": "potion", "chance": 50}]
	var core := _core(s[0], rules, ["hero"], 1)
	assert_eq(_auto(core), "win")
	var dropped := 0
	for it in core.rewards().items:
		dropped += int(it.count)
	assert_true(dropped < 2, "without the ability a half-chance drop can miss (dropped %d)" % dropped)


# --- the walking rules ------------------------------------------------------------------------------


func _walk_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	await env.settle()
	env.rpg.state.access["encounters"] = false


func _encounter_queued() -> bool:
	for t in env.rpg.scheduler.queue:
		if t.key == "encounter":
			return true
	return false


func test_encounter_none_blocks_random_encounters() -> void:
	await _walk_env()
	var p: RPGPlayer = env.game.player
	env.rpg.state.access["encounters"] = true
	env.game.map.props["encounters"] = {"steps": 30, "groups": [{"troop": "slimes", "weight": 1}]}
	p.encounter_count = 1
	p._check_encounter()
	assert_true(_encounter_queued(), "without the ability the battle is queued")
	env.rpg.scheduler.queue.clear()
	# The same step with Encounter None: no battle, the counter not even consumed.
	_trait(env.rpg.data.db["actors"].by_id["hero"], "encounter_none")
	p.encounter_count = 1
	p._check_encounter()
	assert_false(_encounter_queued(), "Encounter None keeps the party out of battles")
	assert_eq(p.encounter_count, 1, "the step counter is untouched")


func test_encounter_half_doubles_the_steps_between_battles() -> void:
	await _walk_env()
	var p: RPGPlayer = env.game.player
	# Learn the roll a seed makes, then replay the seed with and without the ability.
	env.rpg.rng = RPGRandom.new(11)
	var roll: float = env.rpg.rng.randf_range(0.5, 1.5)
	env.rpg.rng = RPGRandom.new(11)
	p.reset_encounter()
	assert_eq(p.encounter_count, maxi(1, int(30.0 * roll)), "the base count is steps x the roll")
	_trait(env.rpg.data.db["actors"].by_id["hero"], "encounter_half")
	env.rpg.rng = RPGRandom.new(11)
	p.reset_encounter()
	assert_eq(p.encounter_count, maxi(1, int(60.0 * roll)), "Encounter Half doubles the steps")
