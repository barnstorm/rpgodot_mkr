extends "res://tests/rpg_test_case.gd"
## RPGBattleCore: deterministic battles with fixed seeds, enemy AI, escape, items, and
## battle event page eligibility (conditions, spans, priority order).

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.from_folder("res://rpg/database")
	rules = RPGRuleSystem.load_rules("classic", db)


func _core(party_ids: Array, troop_id: String, rng_seed: int, level := 1) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, level))
	var core := RPGBattleCore.new(party, db.record("troops", troop_id), rules, RPGRandom.new(rng_seed))
	core.start()
	return core


## Runs a whole battle with automatic actions (actors attack). Returns [result, log lines].
func _auto_battle(core: RPGBattleCore, max_turns := 60) -> Array:
	var log := []
	while core.battle_over() == "" and core.turn < max_turns:
		core.begin_turn()
		var r := core.next_action()
		while not r.is_empty():
			log.append_array(r.lines)
			r = core.next_action()
		for t in core.end_turn():
			log.append_array(t.lines)
	return [core.battle_over(), log]


func test_start_creates_enemies() -> void:
	var core := _core(["hero"], "slimes", 1)
	assert_eq(core.enemies.size(), 2)
	assert_eq(core.enemies[0].name, "Slime A")
	assert_eq(core.enemies[1].name, "Slime B")
	assert_eq(core.enemies[1].screen_position, Vector2(200, 150))
	assert_eq(core.enemies[0].get_resource("hp"), 40)
	assert_eq(core.battle_over(), "")
	assert_eq(core.inputs_needed(), [0])


func test_deterministic_win_vs_slimes() -> void:
	var a := _auto_battle(_core(["hero"], "slimes", 12345))
	var b := _auto_battle(_core(["hero"], "slimes", 12345))
	assert_eq(a[0], "win", "level-1 hero beats two slimes")
	assert_eq(a[1], b[1], "same seed, same battle")
	assert_true(a[1].size() > 4)
	var c := _auto_battle(_core(["hero"], "slimes", 999))
	assert_ne(a[1], c[1], "a different seed plays differently")
	# Robust across seeds, but not free.
	var hp_lost := 0
	for s in 20:
		var core := _core(["hero"], "slimes", 1000 + s)
		var r := _auto_battle(core)
		assert_eq(r[0], "win", "seed %d" % (1000 + s))
		hp_lost += 120 - core.party[0].get_resource("hp")
	assert_true(hp_lost / 20 > 20, "slimes do real damage (avg %d)" % (hp_lost / 20))


func test_rewards_after_win() -> void:
	var core := _core(["hero"], "slimes", 12345)
	_auto_battle(core)
	var rw := core.rewards()
	assert_eq(rw.exp, 12)
	assert_eq(rw.gold, 16)
	assert_true(rw.items is Array)
	assert_eq(core.rewards(), rw, "rewards are rolled once")
	var awarded := core.award_exp()
	assert_eq(awarded.size(), 1)
	assert_eq(core.party[0].exp, 12)
	assert_eq(core.finish(), "win")


func test_goblin_boss_is_not_trivial() -> void:
	var wins := 0
	for s in 10:
		if _auto_battle(_core(["hero"], "goblin_boss", 500 + s))[0] == "win":
			wins += 1
	assert_eq(wins, 0, "a lone level-1 hero cannot beat the goblin boss")
	var core := _core(["hero"], "goblin_boss", 7)
	assert_false(core.can_escape)
	assert_false(core.set_action(0, {"kind": "escape"}))
	assert_false(core.attempt_escape().success)


func test_player_actions_and_skills() -> void:
	var core := _core(["hero", "mira"], "slimes", 42)
	core.begin_turn()
	assert_false(core.set_action(0, {"kind": "skill", "skill": "fire"}), "hero does not know fire")
	assert_false(core.set_action(5, {"kind": "attack"}))
	assert_false(core.set_action(0, {"kind": "dance"}))
	assert_true(core.set_action(0, {"kind": "guard"}))
	assert_true(core.set_action(1, {"kind": "skill", "skill": "fire", "target": 1}))
	var results := []
	var r := core.next_action()
	while not r.is_empty():
		results.append(r)
		r = core.next_action()
	var fire_seen := false
	for res in results:
		if res.kind == "skill":
			fire_seen = true
			assert_eq(res.name, "Fire")
			assert_eq(res.targets, [core.enemies[1]])
			assert_eq(res.lines[0], "Mira casts Fire!")
			assert_eq(core.party[1].get_resource("sp"), 34, "SP paid")
		if res.kind == "guard":
			assert_true(core.party[0].guarding)
	assert_true(fire_seen)
	core.end_turn()


func test_items_use_consumer() -> void:
	var core := _core(["hero"], "slimes", 3)
	var stock := {"potion": 1}
	core.item_consumer = func(id):
		if int(stock.get(id, 0)) <= 0:
			return false
		stock[id] -= 1
		return true
	core.party[0].set_resource("hp", 30)
	for turn in 2:
		core.begin_turn()
		assert_true(core.set_action(0, {"kind": "item", "item": "potion", "target": 0}))
		var r := core.next_action()
		while not r.is_empty():
			if r.user == core.party[0]:
				if turn == 0:
					assert_eq(r.effects[0].result.recovered, 50)
				else:
					assert_true(r.text.contains("can't use"), r.text)
			r = core.next_action()
		core.end_turn()
	assert_eq(stock.potion, 0)


## The Escape effect (VX Ace / MV, #43): a smoke bomb — the user leaves the battle, and a
## lone party that escapes ends the fight as an escape (not a win, no rewards).
func test_escape_effect_on_a_lone_party_ends_the_battle() -> void:
	db.add("items", {"id": "smoke_bomb", "name": "Smoke Bomb", "scope": "user",
		"effects": [{"kind": "escape"}]})
	var core := _core(["hero"], "slimes", 5)
	core.item_consumer = func(id): return true
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "item", "item": "smoke_bomb", "target": 0}))
	var fled: Array = []
	var r := core.next_action()
	while not r.is_empty():
		if not r.get("fled", []).is_empty():
			fled = r.fled
		r = core.next_action()
	core.end_turn()
	assert_eq(fled, [core.party[0]], "the hero left the field")
	assert_true(core.party[0].escaped)
	assert_eq(core.battle_over(), "escape", "a lone escaper ends the fight as an escape")


## The same effect aimed at an enemy makes just that enemy leave — no rewards for it, and
## the fight continues until the rest of the troop is dealt with.
func test_escape_effect_on_an_enemy_leaves_it_without_rewards() -> void:
	db.add("skills", {"id": "banish", "name": "Banish", "scope": "one_enemy",
		"hit_type": "certain", "formula": "0", "variance": 0,
		"effects": [{"kind": "escape"}]})
	var core := _core(["hero"], "slimes", 5)
	core.party[0].skills.append("banish")
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "skill", "skill": "banish", "target": 0}))
	var fled: Array = []
	var r := core.next_action()
	while not r.is_empty():
		if not r.get("fled", []).is_empty():
			fled = r.fled
		r = core.next_action()
	core.end_turn()
	assert_eq(fled, [core.enemies[0]], "the first slime was banished")
	assert_true(core.enemies[0].escaped)
	assert_eq(core.battle_over(), "", "the fight goes on while the second slime stands")
	assert_eq(_auto_battle(core)[0], "win")
	var rw := core.rewards()
	assert_eq(rw.exp, 6, "only the slime that fell counts")
	assert_eq(rw.gold, 8)


## MV/MZ scopes (#44): the (dead or alive) scopes reach a fallen ally, "everyone" covers both
## sides' living battlers, and the living-only scopes stay clear of the dead.
func test_mz_scopes_reach_dead_allies_and_everyone() -> void:
	var core := _core(["hero", "mira"], "slimes", 7)
	var hero: RPGBattler = core.party[0]
	assert_eq(core.resolve_targets(hero, {"scope": "everyone"}, -1),
		[hero, core.party[1], core.enemies[0], core.enemies[1]], "both sides, friends first")
	rules.add_state(core.party[1], rules.death_state())
	assert_eq(core.resolve_targets(hero, {"scope": "one_ally"}, 1), [hero],
		"a dead ally cannot take a living-only scope")
	assert_eq(core.resolve_targets(hero, {"scope": "one_ally_any"}, 1), [core.party[1]],
		"the (dead or alive) scope picks her")
	assert_eq(core.resolve_targets(hero, {"scope": "all_allies"}, -1), [hero])
	assert_eq(core.resolve_targets(hero, {"scope": "all_allies_any"}, -1), [hero, core.party[1]])
	assert_eq(core.resolve_targets(hero, {"scope": "everyone"}, -1),
		[hero, core.enemies[0], core.enemies[1]], "the dead stay out of Everyone")
	# A revive item aimed at her works through the any-scope instead of reading "no effect".
	db.add("items", {"id": "phoenix_down", "name": "Phoenix Down", "scope": "one_ally_any",
		"effects": [{"kind": "remove_state", "id": rules.death_state()}]})
	var r := rules.use_item(hero, core.party[1], "phoenix_down")
	assert_true(RPGRuleSystem.had_effect(r))
	assert_false(core.party[1].is_dead(), "revived")


## MV's "N random enemies": one pick per hit from the living, the same enemy can come up twice,
## and the picks are the seeded RNG's (same seed, same storm).
func test_random_enemies_scope_hits_once_per_pick() -> void:
	var storm := func(c: RPGBattleCore) -> Array:
		return c.resolve_targets(c.party[0], {"scope": "random_enemies", "random_count": 4}, -1)\
			.map(func(p): return c.enemies.find(p))
	var core := _core(["hero", "mira"], "slimes", 7)
	var hero: RPGBattler = core.party[0]
	var picks: Array = core.resolve_targets(hero, {"scope": "random_enemies", "random_count": 4}, -1)
	assert_eq(picks.size(), 4, "four picks from two slimes means repeats")
	for p in picks:
		assert_true(p.is_active() and core.enemies.has(p))
	assert_eq(core.resolve_targets(hero, {"scope": "random_enemies"}, -1).size(), 1, "count defaults to one")
	assert_eq(storm.call(_core(["hero", "mira"], "slimes", 7)),
		picks.map(func(p): return core.enemies.find(p)), "the same seed draws the same storm")
	for e in core.enemies:
		e.escaped = true
	assert_eq(core.resolve_targets(hero, {"scope": "random_enemies", "random_count": 3}, -1), [],
		"nothing to pick from")
	# In battle: a hit per pick, each rolled separately.
	db.add("skills", {"id": "spark_storm", "name": "Spark Storm", "scope": "random_enemies",
		"random_count": 3, "hit_type": "certain", "formula": "4", "variance": 0})
	var battle := _core(["hero"], "slimes", 5)
	battle.party[0].skills.append("spark_storm")
	battle.begin_turn()
	assert_true(battle.set_action(0, {"kind": "skill", "skill": "spark_storm", "target": -1}))
	var effects := []
	var r := battle.next_action()
	while not r.is_empty():
		if r.user == battle.party[0] and str(r.get("kind", "")) == "skill":
			effects = r.effects
		r = battle.next_action()
	battle.end_turn()
	assert_eq(effects.size(), 3, "three picks, three hits")
	var total := 0
	for fe in effects:
		total += int(fe.result.damage)
	assert_eq(total, 12, "4 damage a hit")


func test_turn_order_and_checkpoints() -> void:
	var core := _core(["hero"], "bats", 11)
	var seen := []
	core.checkpoint.connect(func(kind): seen.append(kind))
	core.begin_turn()
	var users := []
	var r := core.next_action()
	while not r.is_empty():
		users.append(r.user)
		r = core.next_action()
	core.end_turn()
	assert_eq(seen[0], "start_of_turn")
	assert_eq(seen[-1], "end_of_turn")
	assert_eq(seen.count("after_action"), users.size())
	assert_eq(users.size(), 3)
	assert_true(seen.has("after_change"), "a hit changes HP, so the HP/state checkpoint fires")
	assert_true(seen.find("after_change") < seen.rfind("after_action"), "it comes before the matching after_action")
	# Bats (AGI 14) act before the hero (AGI 10, max speed 12).
	assert_true(users[0].is_enemy() and users[1].is_enemy(), "fast bats first")


func test_enemy_ai_conditions() -> void:
	var core := _core(["hero"], "goblin_boss", 21)
	var goblin: RPGBattler = core.enemies[0]
	core.turn = 1
	for i in 20:
		assert_eq(core.choose_enemy_action(goblin).kind, "attack", "power strike only on turns 3, 6, ...")
	core.turn = 3
	var kinds := {}
	for i in 60:
		kinds[core.choose_enemy_action(goblin).kind] = true
	assert_true(kinds.has("skill") and kinds.has("attack"), "both actions possible on turn 3: %s" % str(kinds))
	goblin.set_resource("sp", 0)
	for i in 20:
		assert_eq(core.choose_enemy_action(goblin).kind, "attack", "no SP, no power strike")


func _page_ids(pages: Array) -> Array:
	var out := []
	for p in pages:
		out.append(p.id)
	return out


func test_battle_page_eligibility() -> void:
	var troop := {"id": "t", "members": [{"enemy": "slime"}, {"enemy": "slime"}], "pages": [
		{"id": "every", "conditions": [{"kind": "turn", "n": 1, "every": 1}], "span": "every_check", "priority": 0},
		{"id": "turn2", "conditions": [{"kind": "turn", "n": 2}], "span": "once_per_battle", "priority": 5},
		{"id": "per_turn", "conditions": [{"kind": "turn", "n": 1, "every": 1}], "span": "once_per_turn", "priority": 5},
		{"id": "low_hp", "conditions": [{"kind": "enemy_hp", "index": 0, "op": "<=", "percent": 50}], "span": "once_per_battle", "priority": 1},
		{"id": "flag", "conditions": [{"kind": "switch", "id": "boss_flag"}], "span": "every_check", "priority": -1},
		{"id": "hurt_hero", "conditions": [{"kind": "actor_hp", "id": "hero", "op": "<", "percent": 25}, {"kind": "turn", "n": 1, "every": 1}], "span": "once_per_turn", "priority": 0},
		{"id": "never", "conditions": [], "span": "every_check", "priority": 99},
	]}
	var hero := rules.new_actor_battler("hero")
	var core := RPGBattleCore.new([hero], troop, rules, RPGRandom.new(1))
	core.start()
	var switches := {"boss_flag": false}
	core.switch_reader = func(id): return switches.get(id, false)
	core.begin_turn()
	assert_eq(_page_ids(core.eligible_battle_pages("start_of_turn")), ["per_turn", "every"], "priority desc, then page order")
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["every"], "once_per_turn ran already")
	core.end_turn()
	core.begin_turn()
	assert_eq(_page_ids(core.eligible_battle_pages("start_of_turn", false)), ["turn2", "per_turn", "every"], "peek")
	assert_eq(_page_ids(core.eligible_battle_pages("start_of_turn")), ["turn2", "per_turn", "every"])
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["every"])
	core.enemies[0].set_resource("hp", 20)
	switches.boss_flag = true
	hero.set_resource("hp", 10)
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["low_hp", "every", "hurt_hero", "flag"])
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["every", "flag"], "once spans consumed")
	core.end_turn()
	core.begin_turn()
	assert_eq(_page_ids(core.eligible_battle_pages("end_of_turn")), ["per_turn", "every", "hurt_hero", "flag"], "turn 3")


func test_sample_goblin_page() -> void:
	var core := _core(["hero"], "goblin_boss", 5)
	var fired := []
	var on_checkpoint := func(kind):
		for p in core.eligible_battle_pages(kind):
			fired.append([core.turn, p.id, p.commands[0].text])
	core.checkpoint.connect(on_checkpoint)
	for t in 3:
		if core.battle_over() != "":
			break
		core.begin_turn()
		var r := core.next_action()
		while not r.is_empty():
			r = core.next_action()
		core.end_turn()
	core.checkpoint.disconnect(on_checkpoint)
	assert_eq(fired, [[2, "goblin_snarls", "The goblin snarls!"]])


func test_escape_from_slimes() -> void:
	var core := _core(["hero"], "slimes", 8)
	var escaped := false
	for i in 10:
		if core.attempt_escape().success:
			escaped = true
			break
	assert_true(escaped, "83%% chance escapes within 10 tries")
	assert_eq(core.battle_over(), "escape")
	assert_eq(core.next_action(), {})



## D4: an item with a Common Event effect names it once in the action result (the battle scene
## runs it after the action), however many targets it has; the game state queues reserved ones.
func test_d4_common_event_effect_in_battle() -> void:
	db.add("items", {"id": "war_horn", "name": "War Horn", "scope": "all_allies", "consumable": false,
		"effects": [{"kind": "common_event", "id": "count_up"}]})
	var core := _core(["hero", "mira"], "slimes", 3)
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "item", "item": "war_horn", "target": -1}))
	var found := false
	var r := core.next_action()
	while not r.is_empty():
		if r.user == core.party[0]:
			assert_eq(r.get("common_events", []), ["count_up"], "once, not once per target")
			assert_eq(r.effects.size(), 2)
			found = true
		r = core.next_action()
	assert_true(found)
	var st := RPGGameState.new()
	st.reserve_common_event("count_up")
	assert_eq(st.take_reserved_common_events(), ["count_up"])
	assert_true(st.reserved_common_events.is_empty())
