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


func test_enemy_ai_condition_list() -> void:
	# The #9 kinds, one phase each so a single action qualifies at a time (a rating 4 apart from
	# the best never enters the weighted pool, so every pick is deterministic).
	db.add("enemies", {"id": "tactician", "name": "Tactician",
		"stats": {"mhp": 200, "msp": 40, "agi": 20},
		"actions": [
			{"skill": "attack", "rating": 4, "condition": {"kind": "always"}},
			{"skill": "guard", "rating": 9, "condition": {"kind": "mp", "op": "<=", "percent": 25}},
			{"skill": "wait", "rating": 9, "condition": {"kind": "state", "state": "poison"}},
			{"skill": "wait", "rating": 8, "condition": {"kind": "enemies_alive", "op": "<=", "count": 1}},
			{"skill": "guard", "rating": 7, "condition": {"kind": "variable", "variable": "boss_rage", "op": "==", "against": 1}},
		]})
	var troop := {"id": "tactics", "members": [{"enemy": "tactician"}, {"enemy": "slime"}]}
	var core := RPGBattleCore.new([rules.new_actor_battler("hero")], troop, rules, RPGRandom.new(1))
	core.start()
	core.turn = 1
	var t: RPGBattler = core.enemies[0]
	assert_eq(core.choose_enemy_action(t).kind, "attack", "nothing holds: plain attack")
	t.set_resource("sp", 0)
	assert_eq(core.choose_enemy_action(t).kind, "guard", "own MP at 0% <= 25%: guard")
	t.set_resource("sp", 40)
	t.add_state("poison", 3)
	assert_eq(core.choose_enemy_action(t).kind, "wait", "poisoned: wait")
	t.remove_state("poison")
	rules.add_state(core.enemies[1], rules.death_state())
	assert_false(core.enemies[1].is_active(), "the slime is down")
	assert_eq(core.choose_enemy_action(t).kind, "wait", "alone on its side (1 <= 1 alive): wait")
	rules.remove_state(core.enemies[1], rules.death_state())
	core.enemies[1].set_resource("hp", 40)
	core.condition_reader = func(c): return str(c.get("kind")) == "variable" and str(c.get("id")) == "boss_rage" and int(c.get("value", 0)) == 1
	assert_eq(core.choose_enemy_action(t).kind, "guard", "boss_rage == 1 (ref 'variable', operand 'against'): guard")


func test_enemy_ai_party_level_condition() -> void:
	db.add("enemies", {"id": "veteran", "name": "Veteran",
		"stats": {"mhp": 200, "agi": 20},
		"actions": [
			{"skill": "attack", "rating": 4, "condition": {"kind": "always"}},
			{"skill": "guard", "rating": 9, "condition": {"kind": "party_level", "op": ">=", "level": 10}},
			{"skill": "wait", "rating": 8, "condition": {"kind": "party_level", "pick": "highest", "op": ">=", "level": 10}},
		]})
	var troop := {"id": "levels", "members": [{"enemy": "veteran"}]}
	var core := RPGBattleCore.new([rules.new_actor_battler("hero", 5), rules.new_actor_battler("mira", 5)], troop, rules, RPGRandom.new(1))
	core.start()
	core.turn = 1
	var v: RPGBattler = core.enemies[0]
	assert_eq(core.choose_enemy_action(v).kind, "attack", "party average 5, highest 5: plain attack")
	core.party[1].level = 10
	assert_eq(core.choose_enemy_action(v).kind, "wait", "average 7.5 but highest 10: wait")
	core.party[0].level = 10
	var kinds := {}
	for i in 30:
		kinds[core.choose_enemy_action(v).kind] = true
	assert_true(kinds.has("guard") and kinds.has("wait"), "average and highest both qualify, both stay in the weighted pool: %s" % str(kinds))


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


func test_turn_end_page_condition() -> void:
	var troop := {"id": "t", "members": [{"enemy": "slime"}], "pages": [
		{"id": "once", "conditions": [{"kind": "turn_end"}], "span": "once_per_battle"},
		{"id": "each", "conditions": [{"kind": "turn_end"}, {"kind": "turn", "n": 1, "every": 1}], "span": "every_check"},
		{"id": "per_turn", "conditions": [{"kind": "turn_end"}], "span": "once_per_turn"},
		{"id": "flagged", "conditions": [{"kind": "turn_end"}, {"kind": "switch", "id": "boss_flag"}], "span": "every_check", "priority": 1},
	]}
	var core := RPGBattleCore.new([rules.new_actor_battler("hero")], troop, rules, RPGRandom.new(1))
	core.start()
	var switches := {"boss_flag": false}
	core.switch_reader = func(id): return switches.get(id, false)
	core.begin_turn()
	assert_false(core.page_conditions_met({"conditions": [{"kind": "turn_end"}]}, "start_of_turn"), "only true when a turn ends")
	assert_eq(_page_ids(core.eligible_battle_pages("start_of_turn")), [], "not at the start of a turn")
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), [], "nor after an action")
	switches.boss_flag = true
	assert_eq(_page_ids(core.eligible_battle_pages("end_of_turn")), ["flagged", "once", "each", "per_turn"], "turn 1 ends; the switch AND holds")
	core.end_turn()
	core.begin_turn()
	switches.boss_flag = false
	assert_eq(_page_ids(core.eligible_battle_pages("end_of_turn")), ["each", "per_turn"], "turn 2 ends: once per battle is done, switch off")
	core.end_turn()
	core.begin_turn()
	switches.boss_flag = true
	assert_eq(_page_ids(core.eligible_battle_pages("end_of_turn")), ["flagged", "each", "per_turn"], "turn 3 ends: every check keeps firing")


# --- troop page conditions, the RM2003 set (#11) ------------------------------------------------------


func test_battle_page_mp_conditions() -> void:
	assert_eq(rules.magic_resource(), "sp", "classic's spell resource is SP")
	var troop := {"id": "t", "members": [{"enemy": "goblin"}], "pages": [
		{"id": "drained", "conditions": [{"kind": "enemy_mp", "index": 0, "op": "<=", "percent": 25}], "span": "every_check"},
		{"id": "hero_sp", "conditions": [{"kind": "actor_mp", "id": "hero", "op": "<=", "percent": 50}], "span": "every_check"},
	]}
	var hero := rules.new_actor_battler("hero")
	var core := RPGBattleCore.new([hero], troop, rules, RPGRandom.new(1))
	core.start()
	core.begin_turn()
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), [], "full SP everywhere")
	var goblin: RPGBattler = core.enemies[0]
	assert_true(rules.max_resource(goblin, "sp") > 0, "the goblin has SP to spend")
	goblin.set_resource("sp", int(rules.max_resource(goblin, "sp")) / 4)
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["drained"], "the goblin is down to a quarter of its SP")
	hero.set_resource("sp", int(rules.max_resource(hero, "sp")) / 2)
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["drained", "hero_sp"], "the hero reaches exactly 50% (<=)")
	hero.set_resource("sp", rules.max_resource(hero, "sp"))
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["drained"], "the hero refilled")


func test_battle_page_turn_conditions() -> void:
	var troop := {"id": "t", "members": [{"enemy": "goblin"}], "pages": [
		{"id": "foe2", "conditions": [{"kind": "enemy_turns", "index": 0, "op": ">=", "n": 2}], "span": "every_check"},
		{"id": "hero2", "conditions": [{"kind": "actor_turns", "id": "hero", "op": "==", "n": 2}], "span": "every_check"},
	]}
	var hero := rules.new_actor_battler("hero")
	var core := RPGBattleCore.new([hero], troop, rules, RPGRandom.new(7))
	core.start()
	for t in 3:
		core.begin_turn()
		while not core.next_action().is_empty():
			pass
		core.end_turn()
		hero.set_resource("hp", 999)   # keep the hero standing: only the turn counts matter here
		assert_eq(core.enemies[0].turns_taken, t + 1, "enemy own turn %d" % (t + 1))
		assert_eq(hero.turns_taken, t + 1, "hero own turn %d" % (t + 1))
		var want: Array = [] if t == 0 else (["foe2", "hero2"] if t == 1 else ["foe2"])
		assert_eq(_page_ids(core.eligible_battle_pages("end_of_turn")), want, "after own turn %d" % (t + 1))
	core.enemies[0].hidden = true
	core.begin_turn()
	while not core.next_action().is_empty():
		pass
	core.end_turn()
	assert_eq(core.enemies[0].turns_taken, 3, "a hidden enemy does not take turns")
	hero.add_state("sleep", 1)
	core.begin_turn()
	while not core.next_action().is_empty():
		pass
	core.end_turn()
	assert_eq(hero.turns_taken, 5, "a battler that cannot act still loses (and counts) its turn")


func test_battle_page_command_used_condition() -> void:
	var troop := {"id": "t", "members": [{"enemy": "slime"}, {"enemy": "slime"}], "pages": [
		{"id": "attacked", "conditions": [{"kind": "command_used", "id": "hero", "command": "attack"}], "span": "every_check"},
		{"id": "fired", "conditions": [{"kind": "command_used", "id": "mira", "command": "skill", "skill": "fire"}], "span": "every_check"},
		{"id": "other_skill", "conditions": [{"kind": "command_used", "id": "mira", "command": "skill", "skill": "heal"}], "span": "every_check"},
		{"id": "guarded", "conditions": [{"kind": "command_used", "id": "hero", "command": "guard"}], "span": "every_check"},
	]}
	var core := RPGBattleCore.new([rules.new_actor_battler("hero"), rules.new_actor_battler("mira")], troop, rules, RPGRandom.new(9))
	core.start()
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "attack"}))
	assert_true(core.set_action(1, {"kind": "skill", "skill": "fire", "target": 1}))
	while not core.next_action().is_empty():
		pass
	core.end_turn()
	assert_eq(_page_ids(core.eligible_battle_pages("end_of_turn")), ["attacked", "fired"], "attack and Fire matched; the other skill and guard did not")
	core.begin_turn()   # a new battle turn clears what was used
	assert_true(core.set_action(0, {"kind": "guard"}))
	assert_true(core.set_action(1, {"kind": "attack"}))
	while not core.next_action().is_empty():
		pass
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["guarded"], "only this battle turn's commands count")


func test_battle_page_variable_condition_through_the_reader() -> void:
	# The core hands kinds it does not know (variable, item, gold...) to condition_reader; the
	# battle scene wires it to rpg.state.check_condition (end to end in test_battle_events).
	var troop := {"id": "t", "members": [{"enemy": "slime"}], "pages": [
		{"id": "fish", "conditions": [{"kind": "variable", "id": "fish_caught", "op": ">=", "value": 3}], "span": "every_check"},
	]}
	var core := RPGBattleCore.new([rules.new_actor_battler("hero")], troop, rules, RPGRandom.new(1))
	core.start()
	core.begin_turn()
	var st := RPGGameState.new()
	st.set_variable("fish_caught", 0)
	core.condition_reader = func(c): return st.check_condition(c)
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), [], "no fish yet")
	st.set_variable("fish_caught", 3)
	assert_eq(_page_ids(core.eligible_battle_pages("after_action")), ["fish"], "3 fish >= 3 through the game state")
func test_conditional_branch_battle_checks() -> void:
	# A bat (quick: it acts before a level-1 hero) and a hidden slime: the hero's attack is the
	# turn's last action, and the hidden member can never act.
	var troop := {"id": "t", "members": [
		{"enemy": "bat", "position": [100, 120]},
		{"enemy": "slime", "hidden": true, "position": [200, 120]}], "pages": []}
	var core := RPGBattleCore.new([rules.new_actor_battler("hero", 1)], troop, rules, RPGRandom.new(5))
	core.start()
	core.begin_turn()
	assert_true(core.branch_check("actor_can_act", {"id": "hero"}), "the hero can act")
	assert_false(core.branch_check("actor_can_act", {"id": "mira"}), "an actor outside the battle cannot")
	assert_true(core.branch_check("enemy_can_act", {"index": 0}), "the bat can act")
	assert_false(core.branch_check("enemy_can_act", {"index": 1}), "the hidden member cannot")
	assert_false(core.branch_check("enemy_is_target", {"index": 0}), "no action has run yet")
	assert_true(core.set_action(0, {"kind": "attack", "target": 0}))
	var r := core.next_action()
	while not r.is_empty():
		r = core.next_action()
	assert_true(core.branch_check("enemy_is_target", {"index": 0}), "the hero's attack was the last action")
	assert_false(core.branch_check("enemy_is_target", {"index": 1}), "not the hidden one")
	core.end_turn()
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "guard"}))
	r = core.next_action()
	while not r.is_empty():
		r = core.next_action()
	assert_false(core.branch_check("enemy_is_target", {"index": 0}), "an enemy attacked the hero: no enemy is the target")
	rules.add_state(core.enemies[0], rules.death_state())
	assert_false(core.branch_check("enemy_can_act", {"index": 0}), "a defeated enemy cannot act")
	rules.add_state(core.party[0], "sleep")
	assert_false(core.branch_check("actor_can_act", {"id": "hero"}), "a sleeping actor cannot act")


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


# --- Game Data "last used" (recorded per action that really happens) -----------------------


func test_last_used_recorder_reports_actions() -> void:
	var core := _core(["hero", "mira"], "slimes", 42)
	var recorded := []
	core.last_used_recorder = func(d: Dictionary): recorded.append(d.duplicate())
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "guard"}))
	assert_true(core.set_action(1, {"kind": "skill", "skill": "fire", "target": 1}))
	var r := core.next_action()
	while not r.is_empty():
		r = core.next_action()
	core.end_turn()
	# A guard reports only who guarded; a skill reports the skill, its actor and the enemy targeted.
	assert_true(recorded.has({"actor": "hero"}), "guard: %s" % str(recorded))
	assert_true(recorded.has({"skill": "fire", "actor": "mira", "target_enemy": 1}), "skill: %s" % str(recorded))


func test_last_used_recorder_items_and_refused_actions() -> void:
	var core := _core(["hero"], "slimes", 3)
	var recorded := []
	core.last_used_recorder = func(d: Dictionary): recorded.append(d.duplicate())
	core.party[0].set_resource("hp", 30)
	core.begin_turn()
	# The hero does not know fire: the action is refused and reports nothing.
	assert_false(core.set_action(0, {"kind": "skill", "skill": "fire", "target": 0}))
	assert_true(core.set_action(0, {"kind": "item", "item": "potion", "target": 0}))
	var r := core.next_action()
	while not r.is_empty():
		r = core.next_action()
	core.end_turn()
	# The hero's refused skill never reported; the item action did, with actor and target.
	assert_eq(recorded[0], {"item": "potion", "actor": "hero", "target_actor": "hero"}, str(recorded))
	# The slimes strike back: an enemy action names its target but not an "actor".
	for i in range(1, recorded.size()):
		assert_eq(recorded[i], {"target_actor": "hero"}, str(recorded))


func test_last_used_recorder_attack_and_enemies() -> void:
	var core := _core(["hero"], "slimes", 7)
	var recorded := []
	core.last_used_recorder = func(d: Dictionary): recorded.append(d.duplicate())
	_auto_battle(core)
	# Some action attacked an enemy, and the slimes struck back at the hero.
	var seen_target_enemy := false
	var seen_target_actor := false
	for d in recorded:
		seen_target_enemy = seen_target_enemy or d.has("target_enemy")
		seen_target_actor = seen_target_actor or d.has("target_actor")
	assert_true(seen_target_enemy, "an action targeted an enemy: %s" % str(recorded))
	assert_true(seen_target_actor, "an enemy targeted the hero: %s" % str(recorded))
	assert_false(recorded.is_empty())


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


# --- State timing (#49) -----------------------------------------------------------------------


func _turns_of(b: RPGBattler, state_id: String) -> int:
	for s in b.states:
		if s.id == state_id:
			return int(s.turns)
	return -1


## An "action end" state wears off right after its battler's second action, without waiting for
## the turn to end (the turn's end neither counts it down nor slips it away early).
func test_action_end_states_wear_off_with_the_action() -> void:
	var poison: Dictionary = db.record("states", "poison")
	poison["turns_min"] = 2
	poison["turns_max"] = 2
	poison["auto_removal"] = "action_end"
	var core := _core(["hero"], "slimes", 21)
	var hero: RPGBattler = core.party[0]
	assert_true(rules.add_state(hero, "poison"))
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "attack", "target": 0}))
	var r := core.next_action()
	while not r.is_empty():
		if r.user == hero:
			assert_true(hero.has_state("poison"), "one action is not enough")
			assert_eq(_turns_of(hero, "poison"), 1, "the action counts it down")
			assert_true(r.get("ticks", []).is_empty(), "nothing to report while it stays")
		r = core.next_action()
	for t in core.end_turn():
		assert_false(t.removed_states.has("poison"), "the turn's end does not count it down")
	assert_eq(_turns_of(hero, "poison"), 1)
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "attack", "target": 0}))
	var seen_removal := false
	r = core.next_action()
	while not r.is_empty():
		if r.user == hero:
			var removed := []
			for t in r.get("ticks", []):
				removed.append_array(t.removed_states)
			assert_eq(removed, ["poison"], "wears off right after the second action")
			assert_false(hero.has_state("poison"))
			seen_removal = true
		r = core.next_action()
	assert_true(seen_removal)
