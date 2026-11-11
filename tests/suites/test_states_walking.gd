extends "res://tests/rpg_test_case.gd"
## States and map walking (editor-QA D8): states removed after N steps on foot, slip damage and
## regeneration every 20 steps (MV / VX Ace), RPG Maker 2000-style HP changes every N steps,
## System "Knockout by slip damage" (1 HP floor when off, game over when the whole party falls),
## damage floors, the step counters through a save and load, and the Database fields and checks.
## The walking tests run on the sample town (Classic rules) with test states added in memory.

const Env := preload("res://tests/rpg_test_env.gd")
const V := preload("res://addons/rpg/runtime/rpg_vehicles.gd")
const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var env
## The last direction walked; _walk bounces back and forth between two cells.
var _last := Vector2i.ZERO


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	await env.settle()
	env.rpg.state.access["encounters"] = false
	_last = Vector2i.ZERO


func after_each() -> void:
	await env.destroy()


func _add_state(rec: Dictionary) -> void:
	var t: Dictionary = env.rpg.data.db["states"]
	t.records.append(rec)
	t.by_id[rec.id] = rec


func _hero() -> RPGBattler:
	return env.rpg.state.actor("hero")


func _rules() -> RPGRuleSystem:
	return env.rpg.rules


## Walks `n` steps on foot (back and forth), each one finished. Returns the steps taken.
func _walk(n: int) -> int:
	var p: RPGPlayer = env.game.player
	var done := 0
	for i in n:
		var dirs: Array[Vector2i] = [-_last, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		var moved := false
		for d in dirs:
			if d != Vector2i.ZERO and p.step(d):
				await env.walk_done(p)
				_last = d
				moved = true
				break
		if not moved:
			break
		done += 1
	return done


func _step_entry(b: RPGBattler, sid: String) -> Dictionary:
	for s in b.states:
		if s.id == sid:
			return s
	return {}


# --- removal by walking --------------------------------------------------------------------------

func test_state_removed_after_n_steps_with_its_message() -> void:
	_add_state({"id": "tired", "name": "Tired", "remove_by_walking": true, "steps_to_remove": 3,
		"messages": {"added": "", "removed": "%1 feels rested."}})
	assert_true(_rules().add_state(_hero(), "tired"))
	assert_eq(await _walk(2), 2)
	assert_true(_hero().has_state("tired"), "still there after 2 of 3 steps")
	assert_eq(int(_step_entry(_hero(), "tired").get("steps", -1)), 1, "1 step left, kept on the state entry")
	assert_eq(env.rpg.state.walk_steps, 2, "steps on foot are counted")
	assert_false(env.rpg.scheduler.is_main_busy(), "nothing to show yet")
	assert_eq(await _walk(1), 1)
	assert_false(_hero().has_state("tired"), "removed on the 3rd step")
	assert_true(env.rpg.scheduler.is_main_busy(), "the removed message is shown as a message box")
	assert_true(await env.settle(), "the message closes")
	# Added again: the count starts over.
	assert_true(_rules().add_state(_hero(), "tired"))
	assert_eq(await _walk(2), 2)
	assert_true(_hero().has_state("tired"), "a re-added state counts from 0 again")


func test_state_without_removed_message_is_removed_silently() -> void:
	_add_state({"id": "dizzy", "name": "Dizzy", "remove_by_walking": true, "steps_to_remove": 1})
	_rules().add_state(_hero(), "dizzy")
	assert_eq(await _walk(1), 1)
	assert_false(_hero().has_state("dizzy"))
	assert_false(env.rpg.scheduler.is_main_busy(), "no message without one in the data")


func test_states_not_removed_by_walking_stay() -> void:
	_rules().add_state(_hero(), "poison")
	assert_eq(await _walk(3), 3)
	assert_true(_hero().has_state("poison"), "poison has no Removed by walking")
	assert_false(_step_entry(_hero(), "poison").has("steps"))


## A water cell next to a free land cell (as in test_vehicles), with more shallow water beyond.
func _shore() -> Dictionary:
	var mv: RPGMovement = env.game.map.movement
	var s: Vector2i = env.game.map.size
	for y in s.y:
		for x in s.x:
			var w := Vector2i(x, y)
			if V.water_kind(mv, w) != V.SHALLOW:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var land: Vector2i = w - d
				if mv.in_bounds(land) and V.can_land(mv, land) and env.game.map.events_at(land).is_empty():
					var deeper: Vector2i = w + d
					if mv.in_bounds(deeper) and V.water_kind(mv, deeper) == V.SHALLOW:
						return {"water": w, "land": land, "dir": d}
	return {}


func test_steps_in_a_vehicle_dont_count() -> void:
	_add_state({"id": "tired", "name": "Tired", "remove_by_walking": true, "steps_to_remove": 2})
	var sh := _shore()
	assert_false(sh.is_empty(), "the sample town has shallow water next to land")
	if sh.is_empty():
		return
	var run: RPGResult = await env.rpg.run_commands([{"type": "set_vehicle_location", "vehicle": "boat", "to": {"map": "town", "position": [sh.water.x, sh.water.y]}}], {"kind": "api", "id": "t"})
	assert_true(run.is_ok(), str(run))
	var p: RPGPlayer = env.game.player
	p.place(sh.land)
	p.force_turn({Vector2i.LEFT: "left", Vector2i.RIGHT: "right", Vector2i.UP: "up", Vector2i.DOWN: "down"}[sh.dir])
	assert_true(p.check_action(), "boards the boat")
	assert_eq(p.vehicle, "boat")
	_rules().add_state(_hero(), "tired")
	var before: int = env.rpg.state.walk_steps
	var steps_before: int = env.rpg.state.steps
	for i in 4:
		var d: Vector2i = sh.dir if i % 2 == 0 else -sh.dir
		assert_true(p.step(d), "sails")
		await env.walk_done(p)
	assert_eq(env.rpg.state.steps, steps_before + 4, "the step total still counts sailing")
	assert_eq(env.rpg.state.walk_steps, before, "walking steps don't")
	assert_true(_hero().has_state("tired"), "4 steps at sea don't remove a 2-step state")


# --- slip damage every 20 steps (MV / VX Ace) ----------------------------------------------------

func test_slip_damage_every_20_steps_with_flash() -> void:
	_rules().definition["map_turn_steps"] = 20
	_rules().add_state(_hero(), "poison")
	var b := _hero()
	var full := b.get_resource("hp")
	var m := _rules().max_resource(b, "hp")
	env.rpg.state.walk_steps = 17
	assert_eq(await _walk(2), 2)
	assert_eq(b.get_resource("hp"), full, "no damage before the 20th step")
	env.rpg.screen.flash_rect.color.a = 0.0
	assert_eq(await _walk(1), 1)
	assert_eq(env.rpg.state.walk_steps, 20)
	assert_eq(b.get_resource("hp"), full - maxi(1, int(m * 0.1)), "poison: 10% of max HP on the 20th step")
	assert_true(env.rpg.screen.flash_rect.color.a > 0.0, "the screen flashes red")
	assert_true(env.rpg.screen.flash_rect.color.r > 0.9 and env.rpg.screen.flash_rect.color.g < 0.1)


func test_state_turns_tick_on_the_map() -> void:
	_rules().definition["map_turn_steps"] = 20
	_add_state({"id": "dazed", "name": "Dazed", "turns_min": 2, "turns_max": 2, "messages": {"removed": "%1 is clear-headed."}})
	_rules().add_state(_hero(), "dazed")
	var p: RPGPlayer = env.game.player
	env.rpg.state.walk_steps = 19
	p.show_party_walk(p.party_walk())
	assert_eq(int(_step_entry(_hero(), "dazed").turns), 1, "one turn passes every 20 steps")
	env.rpg.state.walk_steps = 39
	var r: Dictionary = p.party_walk()
	assert_false(_hero().has_state("dazed"), "worn off after its turns")
	assert_eq(r.messages, ["%s is clear-headed." % _hero().name], "its removed message")


func test_slip_damage_leaves_1_hp_without_slip_death() -> void:
	_rules().definition["map_turn_steps"] = 20
	env.rpg.data.system["slip_death"] = false
	var b := _hero()
	_rules().add_state(b, "poison")
	b.set_resource("hp", 2)
	var p: RPGPlayer = env.game.player
	for k in 3:
		env.rpg.state.walk_steps = 20 * (k + 1) - 1
		var r: Dictionary = p.party_walk()
		assert_false(r.all_dead)
	assert_eq(b.get_resource("hp"), 1, "walking damage stops at 1 HP")
	assert_true(b.is_alive())
	assert_false(env.rpg.ui.scene_open(), "no game over")


func test_slip_death_knocks_out_and_game_over() -> void:
	_rules().definition["map_turn_steps"] = 20
	env.rpg.data.system["slip_death"] = true
	var b := _hero()
	_rules().add_state(b, "poison")
	b.set_resource("hp", 1)
	env.rpg.state.walk_steps = 19
	# Auto mode would close the game over screen at once (and go back to the title).
	env.rpg.ui.auto_advance = false
	assert_eq(await _walk(1), 1)
	assert_true(b.is_dead(), "poison knocks the hero out")
	assert_true(b.has_state("knockout"))
	var shown := false
	for i in 30:
		await frames(1)
		var top: Node = env.rpg.ui.scene_stack.back() if not env.rpg.ui.scene_stack.is_empty() else null
		if top != null and str(top.get_script().resource_path).ends_with("game_over.gd"):
			shown = true
			break
	assert_true(shown, "the game over screen opens when the whole party is knocked out")


func test_slip_death_with_a_survivor_is_no_game_over() -> void:
	_rules().definition["map_turn_steps"] = 20
	env.rpg.data.system["slip_death"] = true
	env.rpg.state.add_actor("mira")
	var b := _hero()
	_rules().add_state(b, "poison")
	b.set_resource("hp", 1)
	env.rpg.state.walk_steps = 19
	var r: Dictionary = env.game.player.party_walk()
	assert_true(r.knocked_out)
	assert_false(r.all_dead, "Mira is still standing")
	assert_true(r.messages.has("%s falls!" % b.name), "the knockout state's added message")


# --- RPG Maker 2000-style change every N steps ---------------------------------------------------

func test_2000_style_change_every_n_steps() -> void:
	_add_state({"id": "venom", "name": "Venom", "map_hp_change": {"resource": "hp", "effect": "damage", "kind": "flat", "value": 3, "steps": 2}})
	var b := _hero()
	_rules().add_state(b, "venom")
	var full := b.get_resource("hp")
	assert_eq(_rules().map_turn_steps(), 0, "Classic rules have no 20-step map turns")
	assert_eq(await _walk(1), 1)
	assert_eq(b.get_resource("hp"), full, "nothing on step 1")
	assert_eq(await _walk(1), 1)
	assert_eq(b.get_resource("hp"), full - 3, "3 HP on step 2")
	assert_eq(await _walk(2), 2)
	assert_eq(b.get_resource("hp"), full - 6, "and on step 4")
	# Percent and recover; never below 1 HP without slip death.
	_add_state({"id": "bloom", "name": "Bloom", "map_hp_change": {"effect": "recover", "kind": "percent", "value": 50, "steps": 1}})
	_rules().add_state(b, "bloom")
	var p: RPGPlayer = env.game.player
	p.party_walk()
	assert_eq(b.get_resource("hp"), _rules().max_resource(b, "hp"), "50% recovery fills up")
	b.set_resource("hp", 2)
	_rules().remove_state(b, "bloom")
	env.rpg.state.walk_steps = 5
	p.party_walk()
	assert_eq(b.get_resource("hp"), 1, "damage stops at 1 HP")


# --- damage floors ------------------------------------------------------------------------------

func test_damage_floor_hurts_and_never_knocks_out() -> void:
	env.rpg.data.system["damage_floor"] = 7
	env.rpg.state.add_actor("mira")
	var b := _hero()
	var mira: RPGBattler = env.rpg.state.actor("mira")
	var full := b.get_resource("hp")
	var p: RPGPlayer = env.game.player
	var r: Dictionary = p.party_walk(true)
	assert_eq(b.get_resource("hp"), full - 7)
	assert_eq(r.damage, 14, "every member is hurt")
	b.set_resource("hp", 3)
	p.party_walk(true)
	assert_eq(b.get_resource("hp"), 1, "a floor leaves 1 HP")
	_rules().add_state(mira, "knockout")
	p.party_walk(true)
	assert_eq(mira.get_resource("hp"), 0, "a knocked-out actor isn't revived by the floor")
	assert_true(mira.is_dead())


# --- save and load ------------------------------------------------------------------------------

func test_step_counters_survive_save_and_load() -> void:
	_add_state({"id": "tired", "name": "Tired", "remove_by_walking": true, "steps_to_remove": 5})
	_rules().add_state(_hero(), "tired")
	assert_eq(await _walk(3), 3)
	assert_eq(int(_step_entry(_hero(), "tired").steps), 2)
	var raw: Dictionary = env.rpg.saves.build_save()
	var text := JSON.stringify(raw)
	raw = JSON.parse_string(text)
	_rules().remove_state(_hero(), "tired")
	env.rpg.state.walk_steps = 0
	var lr: RPGResult = await env.rpg.saves.load_data(raw)
	assert_true(lr.is_ok(), str(lr))
	await env.settle()
	assert_eq(env.rpg.state.walk_steps, 3, "the party's walking steps are saved")
	assert_eq(int(_step_entry(_hero(), "tired").get("steps", -1)), 2, "the state's steps left are saved")
	_last = Vector2i.ZERO
	assert_eq(await _walk(1), 1)
	assert_true(_hero().has_state("tired"))
	assert_eq(await _walk(1), 1)
	assert_false(_hero().has_state("tired"), "5 steps in all, across the load")


# --- rules (VX Ace style regeneration) ----------------------------------------------------------

func _vx_rules() -> Array:
	var db = FakeDB.new()
	db.add("classes", {"id": "soldier", "name": "Soldier", "growth": {"mhp": 450, "mmp": 80, "atk": 20, "def": 10, "mat": 20, "mdf": 20, "agi": 30, "luk": 20}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {}})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "poison", "name": "Poison", "traits": [{"kind": "hp_regen", "value": -10}]})
	var rules := RPGRuleSystem.load_rules("vx_ace", db)
	return [rules, rules.new_actor_battler("eric", 1)]


func test_vx_ace_regen_traits_every_20_steps() -> void:
	var pair := _vx_rules()
	var rules: RPGRuleSystem = pair[0]
	var eric: RPGBattler = pair[1]
	assert_eq(rules.map_turn_steps(), 20, "rules with regeneration take a map turn every 20 steps")
	rules.add_state(eric, "poison")
	var r := rules.map_turn_end(eric)
	assert_eq(r.damage, 45, "HP Regen -10% of 450")
	assert_eq(eric.get_resource("hp"), 405)
	eric.set_resource("hp", 10)
	r = rules.map_turn_end(eric, false)
	assert_eq(eric.get_resource("hp"), 1, "1 HP left without slip death")
	r = rules.map_turn_end(eric, true)
	assert_eq(eric.get_resource("hp"), 0)
	assert_true(r.knocked_out, "knocked out with slip death")
	assert_true(eric.has_state("knockout"))


# --- Database fields and checks -----------------------------------------------------------------

func test_database_fields_default_off() -> void:
	var fields := RPGRecordSchemas.fields_for("states", [], [{"id": "hp", "label": "HP"}, {"id": "mp", "label": "MP"}])
	var keys := fields.map(func(f): return str(f.get("key", "")))
	for k in ["remove_by_walking", "steps_to_remove", "map_hp_change"]:
		assert_has(keys, k)
	var rec := RPGRecordSchemas.new_record("states", "fresh", fields)
	assert_eq(rec.get("remove_by_walking"), false, "not removed by walking by default")
	assert_false(rec.has("steps_to_remove"), "steps are only stored when walking removes it")
	assert_false(rec.has("map_hp_change"), "no change while walking by default")
	var sys := RPGRecordSchemas.fields_for("system")
	var slip: Array = sys.filter(func(f): return f.get("key") == "slip_death")
	assert_eq(slip.size(), 1)
	assert_eq(slip[0].default, false, "Knockout by slip damage is off by default")
	assert_true(str(slip[0].label) != "" and str(slip[0].get("help", "")) != "")


func test_validator_checks_walking_fields() -> void:
	var files := {"rpg/database/states.json": {"kind": "database", "db_type": "states", "data": {"records": [
		{"id": "ok", "name": "OK", "remove_by_walking": true, "steps_to_remove": 10,
			"map_hp_change": {"resource": "hp", "effect": "damage", "kind": "flat", "value": 1, "steps": 1}},
		{"id": "nosteps", "name": "No steps", "remove_by_walking": true, "steps_to_remove": 0},
		{"id": "badchange", "name": "Bad", "map_hp_change": {"effect": "explode", "kind": "flat", "value": -2, "steps": 0}},
	]}}}
	var probs: Array = RPGValidator.database_values(files)
	var msgs := probs.map(func(p): return str(p.record) + ": " + str(p.message))
	assert_false(msgs.any(func(m): return m.begins_with("ok:")), "a correct state passes: %s" % [msgs])
	assert_true(msgs.any(func(m): return m.begins_with("nosteps:") and m.contains("steps to remove")), str(msgs))
	for bit in ["unknown effect", "amount of 0 or more", "step count of at least 1"]:
		assert_true(msgs.any(func(m): return m.begins_with("badchange:") and m.contains(bit)), "%s: %s" % [bit, msgs])
	var sys_probs: Array = RPGValidator.structure("system", {"schema_version": 1, "system": {"slip_death": "yes", "damage_floor": -1}}, null, "rpg/database/system.json")
	assert_eq(sys_probs.size(), 2, str(sys_probs))
	assert_eq(RPGValidator.structure("system", {"schema_version": 1, "system": {"slip_death": true, "damage_floor": 10}}, null, "f").size(), 0)
