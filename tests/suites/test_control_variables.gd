extends "res://tests/rpg_test_case.gd"
## Control Variables arithmetic as RPG Maker has it (#160): whole-number division and remainder
## follow the rule set (VX Ace rounds down and gives the remainder the divisor's sign, as Ruby
## does; the Classic rules cut towards zero, as RPG Maker 2000/2003 do), dividing or taking the
## remainder by zero sets 0 and the event goes on, and the Timer game data reads the seconds a
## timer has left.

const Env := preload("res://tests/rpg_test_env.gd")
const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var env


func before_each() -> void:
	env = Env.create(tree)
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8), "up")
	assert_true(r.is_ok(), "start transfer: %s" % r)


func after_each() -> void:
	await env.destroy()


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


func _var(id: String, op: String, value: Variant) -> Dictionary:
	return {"type": "set_variable", "id": id, "operation": op, "value": value}


## counter = a, then counter <op>= b; returns the result.
func _calc(a: int, op: String, b: int) -> int:
	var r: RPGResult = await _run([_var("counter", "set", a), _var("counter", op, b)])
	assert_true(r.is_ok(), "%d %s %d: %s" % [a, op, b, r])
	return int(env.rpg.get_variable("counter"))


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _use_rules(division: String) -> void:
	env.rpg.rules.definition["variable_division"] = division


func test_the_rule_sets_say_how_whole_numbers_divide() -> void:
	var db = FakeDB.from_folder("res://rpg/database")
	assert_eq(RPGRuleSystem.load_rules("classic", db).variable_division(), "truncate", "Classic: as RPG Maker 2000/2003")
	assert_eq(RPGRuleSystem.load_rules("vx_ace", db).variable_division(), "floor", "VX Ace: as Ruby")
	env.rpg.rules.definition.erase("variable_division")
	assert_eq(env.rpg.rules.variable_division(), "truncate", "a rule set that does not say keeps the old arithmetic")


func test_classic_rules_cut_towards_zero() -> void:
	_use_rules("truncate")
	assert_eq(await _calc(7, "div", 2), 3)
	assert_eq(await _calc(-7, "div", 2), -3)
	assert_eq(await _calc(7, "div", -2), -3)
	assert_eq(await _calc(-7, "div", -2), 3)
	assert_eq(await _calc(7, "mod", 2), 1)
	assert_eq(await _calc(-7, "mod", 2), -1, "the remainder takes the sign of the variable")
	assert_eq(await _calc(7, "mod", -2), 1)
	assert_eq(await _calc(-7, "mod", -2), -1)


func test_vx_ace_rules_round_down_as_ruby_does() -> void:
	_use_rules("floor")
	assert_eq(await _calc(7, "div", 2), 3)
	assert_eq(await _calc(-7, "div", 2), -4, "-7 / 2 rounds down")
	assert_eq(await _calc(7, "div", -2), -4)
	assert_eq(await _calc(-7, "div", -2), 3)
	assert_eq(await _calc(-8, "div", 2), -4, "an exact division is the same either way")
	assert_eq(await _calc(7, "mod", 2), 1)
	assert_eq(await _calc(-7, "mod", 2), 1, "the remainder takes the sign of the divisor")
	assert_eq(await _calc(7, "mod", -2), -1)
	assert_eq(await _calc(-7, "mod", -2), -1)
	assert_eq(await _calc(-8, "mod", 2), 0)
	# Large values stay exact (no detour through floating point).
	assert_eq(await _calc(-9007199254740993, "div", 2), -4503599627370497)
	assert_eq(await _calc(-9007199254740993, "mod", 2), 1)


## The tile maths the tutorials do: an offset that goes negative still lands on the right cell.
func test_wrapping_a_negative_offset() -> void:
	_use_rules("floor")
	assert_eq(await _calc(-1, "mod", 20), 19, "one step left of column 0 on a 20-wide looping map")
	_use_rules("truncate")
	assert_eq(await _calc(-1, "mod", 20), -1)


## Dividing or taking the remainder by zero sets 0 (RPG Maker rescues the error) and the event
## goes on; the game state notes the mistake for the maker.
func test_dividing_by_zero_sets_zero_and_the_event_goes_on() -> void:
	for division in ["truncate", "floor"]:
		_use_rules(division)
		for op in ["div", "mod"]:
			var before: int = env.rpg.state.errors.size()
			var r: RPGResult = await _run([
				_var("counter", "set", 42), _var("order_var", "set", 0),
				_var("counter", op, 0),
				_var("order_var", "set", 1)])
			assert_true(r.is_ok(), "%s by zero does not stop the event (%s): %s" % [op, division, r])
			assert_eq(int(env.rpg.get_variable("counter")), 0, "%s by zero sets 0 (%s)" % [op, division])
			assert_eq(int(env.rpg.get_variable("order_var")), 1, "the next command ran")
			assert_eq(env.rpg.state.errors.size(), before + 1, "the mistake is noted")
			assert_true(str(env.rpg.state.errors[-1]).contains("counter"), "and names the variable: %s" % env.rpg.state.errors[-1])
	# A zero that comes from another variable is the usual way to get here.
	var r2: RPGResult = await _run([_var("counter", "set", 10), _var("order_var", "set", 0), _var("counter", "div", {"variable": "order_var"})])
	assert_true(r2.is_ok(), str(r2))
	assert_eq(int(env.rpg.get_variable("counter")), 0)


func test_decimal_variables() -> void:
	_use_rules("truncate")
	var r: RPGResult = await _run([_var("ratio", "set", -7.5), _var("ratio", "div", 2)])
	assert_true(r.is_ok(), str(r))
	assert_true(_near(float(env.rpg.get_variable("ratio")), -3.75), "decimals divide exactly under every rule set")
	r = await _run([_var("ratio", "set", -7.5), _var("ratio", "mod", 2)])
	assert_true(_near(float(env.rpg.get_variable("ratio")), -1.5), "Classic: the sign of the variable")
	_use_rules("floor")
	r = await _run([_var("ratio", "set", -7.5), _var("ratio", "div", 2)])
	assert_true(_near(float(env.rpg.get_variable("ratio")), -3.75), "expected about -3.75")
	r = await _run([_var("ratio", "set", -7.5), _var("ratio", "mod", 2)])
	assert_true(_near(float(env.rpg.get_variable("ratio")), 0.5), "VX Ace: the sign of the divisor")
	r = await _run([_var("ratio", "set", 3.5), _var("ratio", "div", 0), _var("counter", "set", 5)])
	assert_true(r.is_ok(), str(r))
	assert_true(_near(float(env.rpg.get_variable("ratio")), 0.0), "by zero: 0")
	assert_eq(int(env.rpg.get_variable("counter")), 5)


## A range is still written all at once, and a zero divisor zeroes every variable of it.
func test_a_range_divided_by_zero() -> void:
	var r: RPGResult = await _run([
		_var("counter", "set", 8), _var("ticks", "set", 9),
		{"type": "set_variable", "target": "range", "from": "counter", "to": "ratio", "operation": "div", "value": 0}])
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 0)
	assert_true(_near(float(env.rpg.get_variable("ratio")), 0.0), "expected about 0.0")


func test_self_variables_follow_the_same_rules() -> void:
	_use_rules("floor")
	var me := {"kind": "api", "id": "t", "map": "town", "event": "town_house_door"}
	var cmds := [
		{"type": "set_variable", "target": "self", "name": "offset", "event": "town_house_door", "map": "town", "operation": "set", "value": -7},
		{"type": "set_variable", "target": "self", "name": "offset", "event": "town_house_door", "map": "town", "operation": "div", "value": 2}]
	var r: RPGResult = await env.rpg.run_commands(cmds, me)
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.state.get_self_variable("town", "town_house_door", "offset")), -4)
	cmds[1]["value"] = 0
	r = await env.rpg.run_commands(cmds, me)
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.state.get_self_variable("town", "town_house_door", "offset")), 0)


## VX Ace's "Other: Timer": the whole seconds a timer has left, for either of the kit's two.
func test_the_timer_game_data_reads_the_seconds_left() -> void:
	var s: RPGGameState = env.rpg.state
	s.set_timer("1", 90.0)
	s.set_timer("2", 12.0)
	s.start_timer("2")
	s.tick_timers(1.5)
	var r: RPGResult = await _run([
		_var("counter", "set", {"game_data": {"kind": "timer", "timer": "1"}}),
		_var("ticks", "set", {"game_data": {"kind": "timer", "timer": "2"}})])
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 90, "timer 1")
	assert_eq(int(env.rpg.get_variable("ticks")), 11, "timer 2: 10.5 s left shows as 11, as the readout does")
	assert_eq(int(s.game_data({"kind": "timer"})), 90, "timer 1 when none is named")
	# Minutes and seconds the tutorial way: divide and take the remainder.
	r = await _run([
		_var("counter", "set", {"game_data": {"kind": "timer", "timer": "1"}}),
		_var("ticks", "set", {"variable": "counter"}),
		_var("counter", "div", 60), _var("ticks", "mod", 60)])
	assert_true(r.is_ok(), str(r))
	assert_eq([int(env.rpg.get_variable("counter")), int(env.rpg.get_variable("ticks"))], [1, 30])
	s.set_timer("1", 0.0)
	assert_eq(int(s.game_data({"kind": "timer", "timer": "1"})), 0, "a timer that ran out reads 0")


func test_the_editor_and_the_checks_know_the_timer() -> void:
	var ki := RPGFormBuilder.GAME_DATA_KINDS.find("timer")
	assert_true(ki >= 0, "Game data offers the timer")
	assert_eq(RPGFormBuilder.GAME_DATA_KINDS.size(), RPGFormBuilder.GAME_DATA_LABELS.size())
	assert_eq(RPGCommand.describe_operand({"game_data": {"kind": "timer", "timer": "2"}}), "(timer 2)")
	var ok := _var("counter", "set", {"game_data": {"kind": "timer", "timer": "2"}})
	assert_eq(RPGValidator.command_structure(ok, env.rpg.registry).filter(func(x): return x.severity == "error"), [])
	var out := []
	RPGValidator._game_data_structure({"kind": "timer", "timer": "2"}, "f", "r", "p", out)
	assert_eq(out, [], "timer 2 passes the check")
	RPGValidator._game_data_structure({"kind": "timer", "timer": "3"}, "f", "r", "p", out)
	assert_eq(out.size(), 1, "there is no timer 3")
	# The operand control: choosing Timer shows the timer picker and stores which one.
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup([{"key": "value", "kind": "operand", "default": 0, "label": "Value"}], env.rpg.data)
	form.set_value({"value": {"game_data": {"kind": "timer", "timer": "2"}}})
	assert_eq(form.get_value().value, {"game_data": {"kind": "timer", "timer": "2"}}, "a stored timer operand survives the form")
	form.set_value({"value": {"game_data": {"kind": "gold"}}})
	assert_eq(form.get_value().value, {"game_data": {"kind": "gold"}}, "and other kinds do not gain a timer")
	form.queue_free()
