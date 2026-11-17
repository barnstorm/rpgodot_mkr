extends "res://tests/rpg_test_case.gd"
## When state and buff turns count down and when they wear off (issue #152). Under the VX Ace
## rules ("state_countdown": "turn_end") everything counts down at the end of the turn; "End of
## the action" states and buffs are removed at the end of their battler's next action once they
## have run out. The Classic rules ("own_timing") keep counting each state at its own timing.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var db
var rules: RPGRuleSystem


func before_each() -> void:
	db = FakeDB.new()
	db.add("classes", {"id": "lancer", "name": "Lancer",
		"growth": {"mhp": 500, "mmp": 100, "atk": 30, "def": 20, "mat": 20, "mdf": 10, "agi": 50, "luk": 10}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "lancer", "equips": {}})
	db.add("enemies", {"id": "ogre", "name": "Ogre",
		"stats": {"mhp": 9000, "mmp": 0, "atk": 12, "def": 10, "mat": 10, "mdf": 10, "agi": 5, "luk": 10},
		"actions": [{"skill": "wait", "rating": 5}], "skills": []})
	db.add("troops", {"id": "ogres", "name": "Ogre", "members": [{"enemy": "ogre", "position": [160, 150]}], "pages": []})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	# Tutorial 3.5's Lunge: a state the user puts on itself, Action End, 1 turn.
	db.add("states", {"id": "off_guard", "name": "Off Guard", "auto_removal": "action_end", "turns_min": 1, "turns_max": 1,
		"traits": [{"kind": "stat_rate", "id": "def", "value": 50}]})
	db.add("states", {"id": "regen", "name": "Regen", "auto_removal": "turn_end", "turns_min": 3, "turns_max": 3})
	db.add("states", {"id": "dazed", "name": "Dazed", "auto_removal": "turn_end", "turns_min": 1, "turns_max": 1})
	db.add("states", {"id": "stun", "name": "Stun", "auto_removal": "action_end", "turns_min": 1, "turns_max": 1,
		"restriction": "cannot_act"})
	db.add("states", {"id": "kept", "name": "Kept", "auto_removal": "none", "turns_min": 2, "turns_max": 2})
	db.add("states", {"id": "curse", "name": "Curse"})
	db.add("skills", {"id": "lunge", "name": "Lunge", "scope": "user", "hit_type": "certain",
		"effects": [{"kind": "add_state", "id": "off_guard"}]})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(11)


func _turns(b: RPGBattler, state_id: String) -> int:
	for s in b.states:
		if str(s.id) == state_id:
			return int(s.turns)
	return -99


func test_the_rule_sets_say_how_turns_count_down() -> void:
	assert_eq(rules.state_countdown(), "turn_end", "VX Ace rules")
	assert_eq(RPGRuleSystem.load_rules("classic", db).state_countdown(), "own_timing", "Classic rules")
	assert_eq(RPGRuleSystem.new().state_countdown(), "own_timing", "a rule set that does not say keeps the old model")
	var shipped := RPGRuleSystem.load_rules_from_dir("res://addons/rpg/runtime/rules/vx_ace", db)
	assert_eq(shipped.state_countdown(), "turn_end", "the copy shipped in the addon agrees")


func test_a_one_turn_action_end_state_lasts_through_the_next_action() -> void:
	var eric := rules.new_actor_battler("eric")
	rules.add_state(eric, "off_guard")
	assert_eq(_turns(eric, "off_guard"), 1)
	# The end of the action that put it on: it has not run out.
	var out := rules.tick_states(eric, "action_end")
	assert_eq(out.removed_states, [])
	assert_true(eric.has_state("off_guard"))
	# The end of the turn counts it down; it stays through the next turn's blows.
	out = rules.tick_states(eric, "turn_end")
	assert_eq(out.removed_states, [])
	assert_eq(_turns(eric, "off_guard"), 0)
	assert_true(eric.has_state("off_guard"), "still off guard while the enemies act")
	# The end of his next action removes it.
	out = rules.tick_states(eric, "action_end")
	assert_eq(out.removed_states, ["off_guard"])
	assert_false(eric.has_state("off_guard"))
	assert_eq(out.lines.size(), 1, str(out.lines))


func test_turn_end_states_count_down_and_end_at_the_turns_end() -> void:
	var eric := rules.new_actor_battler("eric")
	rules.add_state(eric, "regen")
	rules.add_state(eric, "dazed")
	rules.tick_states(eric, "action_end")
	assert_eq([_turns(eric, "regen"), _turns(eric, "dazed")], [3, 1], "an action's end does not count them")
	var out := rules.tick_states(eric, "turn_end")
	assert_eq(out.removed_states, ["dazed"], "a 1-turn state ends with the turn it was added in")
	assert_eq(_turns(eric, "regen"), 2)
	rules.tick_states(eric, "turn_end")
	rules.tick_states(eric, "action_end")
	assert_true(eric.has_state("regen"), "an action's end never removes a turn-end state")
	out = rules.tick_states(eric, "turn_end")
	assert_eq(out.removed_states, ["regen"], "gone at the end of its third turn")


func test_states_without_a_countdown_stay() -> void:
	var eric := rules.new_actor_battler("eric")
	rules.add_state(eric, "kept")
	rules.add_state(eric, "curse")
	for i in 4:
		rules.tick_states(eric, "turn_end")
		rules.tick_states(eric, "action_end")
	assert_eq(_turns(eric, "kept"), 2, "\"Never\" keeps its turns")
	assert_eq(_turns(eric, "curse"), -1, "until removed")
	assert_true(eric.has_state("kept") and eric.has_state("curse"))


func test_a_buff_lasts_one_more_action_than_its_turns() -> void:
	var eric := rules.new_actor_battler("eric")
	# Focus: ATK up for 3 turns, cast on his own action in turn 1.
	rules.add_buff(eric, "atk", 3)
	rules.tick_states(eric, "action_end")
	var seen := []
	for turn in [1, 2, 3]:
		rules.tick_states(eric, "turn_end")
		seen.append(int(eric.buffs.atk.turns))
		if turn < 3:
			# His action in the next turn: still buffed, and it stays.
			assert_eq(rules.tick_states(eric, "action_end").removed_buffs, [], "turn %d" % (turn + 1))
	assert_eq(seen, [2, 1, 0])
	assert_eq(rules.buff_level(eric, "atk"), 1, "turn 4's action is still buffed")
	var out := rules.tick_states(eric, "action_end")
	assert_eq(out.removed_buffs, ["atk"], "and takes the buff with it")
	assert_eq(rules.buff_level(eric, "atk"), 0)


func test_own_timing_keeps_the_older_model() -> void:
	var own := RPGRuleSystem.load_rules("vx_ace", db)
	own.definition = own.definition.duplicate(true)
	own.definition["state_countdown"] = "own_timing"
	own.rng = RPGRandom.new(11)
	var eric := own.new_actor_battler("eric")
	own.add_state(eric, "off_guard")
	var out := own.tick_states(eric, "action_end")
	assert_eq(out.removed_states, ["off_guard"], "counted and removed at the first action end")
	own.add_state(eric, "regen")
	own.tick_states(eric, "action_end")
	assert_eq(_turns(eric, "regen"), 3)
	own.add_buff(eric, "atk", 2)
	own.tick_states(eric, "turn_end")
	out = own.tick_states(eric, "turn_end")
	assert_eq(out.removed_buffs, ["atk"], "buffs wear off at the turn's end")
	# The Classic rules ship with it.
	var classic := RPGRuleSystem.load_rules("classic", db)
	var c := classic.new_actor_battler("eric")
	classic.add_state(c, "off_guard")
	assert_eq(classic.tick_states(c, "action_end").removed_states, ["off_guard"])


func _core(party: Array) -> RPGBattleCore:
	var core := RPGBattleCore.new(party, db.record("troops", "ogres"), rules, RPGRandom.new(5))
	core.start()
	return core


## Plays one battle turn; `action` is the first actor's command. Returns the results in order.
func _play_turn(core: RPGBattleCore, action: Dictionary) -> Array:
	core.begin_turn()
	if core.inputs_needed().has(0):
		core.set_action(0, action)
	var out := []
	var r := core.next_action()
	while not r.is_empty():
		out.append(r)
		r = core.next_action()
	core.end_turn()
	return out


func test_lunge_in_a_battle_leaves_the_user_off_guard_until_his_next_action_ends() -> void:
	var eric := rules.new_actor_battler("eric")
	eric.skills.append("lunge")
	var core := _core([eric])
	_play_turn(core, {"kind": "skill", "skill": "lunge", "target": 0})
	assert_true(eric.has_state("off_guard"), "off guard after the turn he lunged in")
	# Turn 2: he attacks, still off guard; the state goes as that action ends.
	core.begin_turn()
	assert_true(eric.has_state("off_guard"), "off guard while the commands go in")
	core.set_action(0, {"kind": "attack", "target": 0})
	var mine := {}
	var r := core.next_action()
	while not r.is_empty():
		if r.user == eric:
			mine = r
			assert_false(eric.has_state("off_guard"), "gone once his action has ended")
		r = core.next_action()
	core.end_turn()
	assert_false(mine.is_empty())
	assert_eq(mine.get("ticks", []).size(), 1, "the wearing off is reported with his action")
	assert_eq(mine.ticks[0].removed_states, ["off_guard"])


func test_a_battler_that_cannot_act_still_reaches_its_action_end() -> void:
	var eric := rules.new_actor_battler("eric")
	var core := _core([eric])
	# Stunned before he acts in turn 1 (Action End, 1 turn): he loses that action.
	core.begin_turn()
	rules.add_state(eric, "stun")
	var acted := false
	var r := core.next_action()
	while not r.is_empty():
		if r.user == eric:
			acted = true
		r = core.next_action()
	core.end_turn()
	assert_false(acted, "no action and nothing to report in turn 1")
	assert_true(eric.has_state("stun"))
	assert_eq(_turns(eric, "stun"), 0, "the turn's end counted it down")
	# Turn 2: he still cannot give a command; the stun goes when his lost action ends.
	core.begin_turn()
	assert_false(core.inputs_needed().has(0), "still stunned at the start of turn 2")
	var lost := {}
	r = core.next_action()
	while not r.is_empty():
		if r.user == eric:
			lost = r
		r = core.next_action()
	core.end_turn()
	assert_false(lost.is_empty(), "the wearing off is reported")
	assert_true(bool(lost.action.get("silent", false)) and bool(lost.get("skipped", false)), "as a silent, skipped turn")
	assert_eq(lost.ticks[0].removed_states, ["stun"])
	assert_false(eric.has_state("stun"))
	# Turn 3: he acts again.
	core.begin_turn()
	assert_true(core.inputs_needed().has(0))


func test_timed_battles_follow_the_same_model() -> void:
	var eric := rules.new_actor_battler("eric")
	eric.skills.append("lunge")
	var core := RPGBattleCore.new([eric], db.record("troops", "ogres"), rules, RPGRandom.new(5))
	core.battle_system = "ctb"
	core.start()
	# Eric's first two turns: Lunge, then an attack. Off Guard lasts through the second.
	core.begin_turn()
	var mine := []
	var guard := 0
	while mine.size() < 2 and guard < 2000:
		guard += 1
		var b := core.next_auto_ready()
		if b == null:
			var a := core.next_input_actor()
			if a == null:
				core.atb_advance_to_next()
				continue
			var cmd := {"kind": "skill", "skill": "lunge", "target": 0} if mine.is_empty() else {"kind": "attack", "target": 0}
			assert_true(core.set_action(core.party.find(a), cmd), "the full actor takes a command")
			continue
		var r := core.act(b)
		if r.get("turn_end", false):
			core.begin_turn()
		if b == eric and not r.is_empty() and not r.get("again", false):
			mine.append(r)
			if mine.size() == 1:
				assert_true(eric.has_state("off_guard"), "off guard after his own turn ended")
	assert_eq(mine.size(), 2, "eric took two turns")
	assert_false(eric.has_state("off_guard"), "gone at the end of his next action")
	var removed := []
	for t in mine[1].get("ticks", []):
		removed.append_array(t.removed_states)
	assert_eq(removed, ["off_guard"])
