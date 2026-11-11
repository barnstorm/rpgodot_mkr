extends "res://tests/rpg_test_case.gd"
## RPGFormula (parser, evaluator, helpers, dice limits, forbidden constructs) and RPGRandom.


func _env(rng_seed: int = 1) -> Dictionary:
	return {
		"a": {"atk": 30, "str": 18, "hp": 40, "max_hp": 100, "level": 3, "dice": "1d4",
			"stats": {"atk": 30, "str": 18}, "resources": {"hp": 40}, "states": []},
		"b": {"pdef": 10, "hp": 25, "stats": {"pdef": 10}, "resources": {"hp": 25}, "states": ["poison"]},
		"v": {"gold_found": 7, "flag": true},
		"s": {"hit": 95, "hit_type": "physical"},
		"rng": RPGRandom.new(rng_seed),
	}


func _val(text: String, env: Dictionary = {}) -> Variant:
	var r := RPGFormula.evaluate_text(text, env if not env.is_empty() else _env())
	if not r.ok:
		fail("'%s' failed: %s" % [text, r.error])
		return null
	return r.value


func _err(text: String, env: Dictionary = {}) -> String:
	var r := RPGFormula.evaluate_text(text, env if not env.is_empty() else _env())
	if r.ok:
		fail("'%s' should fail but gave %s" % [text, str(r.value)])
		return ""
	return r.error


func test_arithmetic_and_precedence() -> void:
	assert_eq(_val("1 + 2 * 3"), 7)
	assert_eq(_val("(1 + 2) * 3"), 9)
	assert_eq(_val("10 - 4 - 3"), 3, "left associative")
	assert_eq(_val("7 / 2"), 3, "int division")
	assert_true(_val("7 / 2") is int, "int / int stays int")
	assert_eq(_val("-7 / 2"), -4, "floored division")
	assert_eq(_val("7 % 3"), 1)
	assert_eq(_val("-7 % 3"), 2, "floored modulo")
	assert_eq(_val("7.0 / 2"), 3.5)
	assert_eq(_val("2 * -3"), -6)
	assert_eq(_val("-(2 + 3)"), -5)
	assert_eq(_val("--4"), 4)
	assert_eq(_val("2 + 3 * 4 - 6 / 2"), 11)


func test_comparisons_and_logic() -> void:
	assert_eq(_val("1 < 2 and 3 >= 3"), true)
	assert_eq(_val("not true or false"), false)
	assert_eq(_val("!(1 == 2)"), true)
	assert_eq(_val("1 != 1 || 2 <= 1"), false)
	assert_eq(_val("1 + 1 == 2"), true, "arithmetic binds tighter than ==")
	assert_eq(_val("true and false or true"), true, "and binds tighter than or")
	assert_eq(_val("false and (1 / 0 == 1)"), false, "and short-circuits")
	assert_eq(_val("true or (1 / 0 == 1)"), true, "or short-circuits")
	assert_true(_err("1 < 2 < 3").contains("chained"))


func test_if_then_else() -> void:
	assert_eq(_val("if 1 > 2 then 10 else 20"), 20)
	assert_eq(_val("if a.hp < 50 then 1 else 2"), 1)
	assert_eq(_val("if false then 1 else if true then 2 else 3"), 2, "nested else-if")
	assert_eq(_val("1 + (if v.flag then 10 else 0)"), 11)
	assert_eq(_val("a.hp > 10 ? 5 : 6"), 5, "ternary")
	assert_eq(_val("if s.hit_type == 'physical' then 1 else 0"), 1, "string compare")
	assert_true(_err("if 1 then 2").contains("else"))


func test_members_and_variables() -> void:
	assert_eq(_val("a.atk - b.pdef / 2"), 25)
	assert_eq(_val("v.gold_found * 2"), 14)
	assert_eq(_val("a.level"), 3)
	assert_true(_err("a.missing").contains("a has no value 'missing'"))
	assert_true(_err("v.nope").contains("unknown variable 'nope'"))
	assert_true(_err("a.atk.x").contains("cannot read"))


func test_helpers() -> void:
	assert_eq(_val("min(3, 1, 2)"), 1)
	assert_eq(_val("max(3, 9, 2)"), 9)
	assert_eq(_val("clamp(150, 0, 100)"), 100)
	assert_eq(_val("clamp(-5, 0, 100)"), 0)
	assert_eq(_val("abs(-4)"), 4)
	assert_eq(_val("floor(3.7)"), 3)
	assert_eq(_val("ceil(3.2)"), 4)
	assert_eq(_val("round(2.5)"), 3)
	assert_true(_val("floor(3.7)") is int)
	assert_eq(_val("mod(18)"), 4)
	assert_eq(_val("mod(10)"), 0)
	assert_eq(_val("mod(9)"), -1)
	assert_eq(_val("mod(3)"), -4)
	assert_eq(_val("stat(a, 'atk')"), 30)
	assert_eq(_val("resource(b, \"hp\")"), 25)
	assert_eq(_val("has_state(b, 'poison')"), true)
	assert_eq(_val("has_state(a, 'poison')"), false)
	assert_true(_err("stat(a, 'luck')").contains("no stat 'luck'"))
	assert_true(_err("clamp(1, 5, 2)").contains("low bound"))
	assert_true(RPGFormula.check("min()").contains("takes"), "arity is checked at compile time")


func test_dice_and_rand() -> void:
	var env := _env(42)
	for i in 200:
		var v: int = RPGFormula.evaluate_text("roll('2d6+1')", env).value
		assert_true(v >= 3 and v <= 13, "2d6+1 in range, got %d" % v)
	assert_eq(_val("roll('1d1+4')"), 5)
	assert_eq(_val("roll(3, 1)"), 3)
	assert_eq(_val("rand(4, 4)"), 4)
	assert_eq(_val("roll('d1 - 1')"), 0)
	var dyn: int = _val("roll(a.dice)")
	assert_true(dyn >= 1 and dyn <= 4, "dice text from a snapshot")
	# Same seed, same rolls.
	var e1 := _env(7)
	var e2 := _env(7)
	var s1 := []
	var s2 := []
	for i in 20:
		s1.append(RPGFormula.evaluate_text("roll('1d20') + rand(1, 100)", e1).value)
		s2.append(RPGFormula.evaluate_text("roll('1d20') + rand(1, 100)", e2).value)
	assert_eq(s1, s2, "deterministic with a fixed seed")


func test_dice_limits() -> void:
	assert_true(RPGFormula.check("roll('101d6')").contains("number of dice"))
	assert_true(RPGFormula.check("roll('1d1001')").contains("number of sides"))
	assert_true(RPGFormula.check("roll('2x6')") != "")
	assert_true(RPGFormula.check("roll('')") != "")
	assert_true(RPGFormula.check("roll('60d6 + 60d6')").contains("too many dice"))
	assert_true(_err("roll(101, 6)").contains("number of dice"))
	assert_true(_err("roll(1, 0)").contains("sides"))
	var env := _env()
	env.a.dice = "500d6"
	assert_true(_err("roll(a.dice)", env).contains("number of dice"))
	# Cost cap across one evaluation: 11 x 100 dice > 1000.
	var parts := []
	for i in 11:
		parts.append("roll(100, 6)")
	assert_true(_err(" + ".join(parts)).contains("too many dice"))
	var no_rng := _env()
	no_rng.erase("rng")
	assert_true(_err("roll('1d6')", no_rng).contains("random number generator"))
	assert_true(_err("rand(1, 6)", no_rng).contains("random number generator"))
	assert_true(_err("rand(6, 1)").contains("low bound"))
	var d := RPGFormula.parse_dice("3d4 + 1d6 - 2")
	assert_true(d.ok)
	assert_eq(d.dice, 4)
	assert_eq(d.bonus, -2)


func test_forbidden_constructs() -> void:
	assert_true(RPGFormula.check("OS.execute('calc')").contains("unknown name 'OS'"))
	assert_true(RPGFormula.check("a.free()").contains("method calls are not allowed"))
	assert_true(RPGFormula.check("a.get('atk')").contains("method calls are not allowed"))
	assert_true(RPGFormula.check("Engine.get_singleton('OS')").contains("unknown name 'Engine'"))
	assert_true(RPGFormula.check("load('res://x.gd')").contains("unknown function 'load'"))
	assert_true(RPGFormula.check("print(1)").contains("unknown function 'print'"))
	assert_true(RPGFormula.check("rng").contains("unknown name 'rng'"), "the RNG object is not readable")
	assert_true(RPGFormula.check("x = 1").contains("=="))
	assert_true(RPGFormula.check("a[0]") != "", "indexing is not part of the grammar")
	assert_true(RPGFormula.check("1; 2") != "")
	# Godot objects never pass into a formula even if someone puts one in a snapshot.
	var env := _env()
	env.a["node"] = RefCounted.new()
	assert_true(_err("a.node", env).contains("not a plain value"))


func test_error_cases() -> void:
	assert_true(_err("1 / 0").contains("division by zero"))
	assert_true(_err("5 % 0").contains("modulo by zero"))
	assert_true(_err("true + 1").contains("needs numbers"))
	assert_true(_err("'abc'").contains("must be a number"))
	assert_true(_err("a").contains("must be a number"))
	assert_true(_err("1 == true").contains("cannot compare"))
	var c := RPGFormula.compile("")
	assert_false(c.ok)
	assert_true(c.error.contains("empty"))
	c = RPGFormula.compile("1 + * 2")
	assert_false(c.ok)
	assert_eq(c.column, 5, "error column")
	c = RPGFormula.compile("(1 + 2")
	assert_true(c.error.contains("')'"))
	c = RPGFormula.compile("1 2")
	assert_true(c.error.contains("after the end"))
	c = RPGFormula.compile("'open")
	assert_true(c.error.contains("not closed"))
	var deep := "(".repeat(100) + "1" + ")".repeat(100)
	assert_true(RPGFormula.check(deep).contains("nested too deeply"))
	var r := RPGFormula.evaluate({}, {})
	assert_false(r.ok)


func test_compile_cache_and_reuse() -> void:
	var c1 := RPGFormula.compile("a.atk * 2")
	var c2 := RPGFormula.compile("a.atk * 2")
	assert_true(c1.ok)
	assert_true(is_same(c1.ast, c2.ast), "compiled AST is cached")
	assert_eq(RPGFormula.evaluate(c1.ast, _env()).value, 60)
	var env := _env()
	env.a.atk = 5
	assert_eq(RPGFormula.evaluate(c1.ast, env).value, 10, "same AST, new snapshot")


func test_random_state_roundtrip() -> void:
	var r := RPGRandom.new(99)
	for i in 5:
		r.randi_range(1, 100)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(r.get_state()))
	var expected := []
	for i in 10:
		expected.append(r.randi_range(1, 1000))
	var r2 := RPGRandom.new(1)
	r2.set_state(saved)
	var got := []
	for i in 10:
		got.append(r2.randi_range(1, 1000))
	assert_eq(got, expected, "state survives a JSON round trip")
	assert_eq(r.pick_weighted([{"weight": 0}, {"weight": 0}]), null)
	assert_eq(r.pick_weighted([{"weight": 0, "id": "x"}, {"weight": 5, "id": "y"}]).id, "y")
	assert_false(r.chance(0.0))
	assert_true(r.chance(1.0))
	var counts := {"a": 0, "b": 0}
	for i in 1000:
		counts[r.pick_weighted([{"id": "a", "weight": 1}, {"id": "b", "weight": 3}]).id] += 1
	assert_true(counts.b > counts.a * 2, "weights respected: %s" % str(counts))
