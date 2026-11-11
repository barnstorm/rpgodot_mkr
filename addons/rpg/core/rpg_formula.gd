@tool
class_name RPGFormula
extends RefCounted
## Restricted formula language used by rule systems and formula-capable database fields.
##
## Formulas are parsed by our own tokenizer and recursive-descent parser into a small AST of
## Dictionaries. Godot's Expression class is deliberately NOT used: it can call methods on
## objects. A formula can only:
##   * use literals: numbers, true/false, 'strings' / "strings" (for helper arguments)
##   * do arithmetic + - * / % (ints stay ints; int / int is floored division), unary -
##   * compare: == != < <= > >=  (not chained)
##   * combine: and / or / not  (also && || !), short-circuit
##   * branch: `if c then x else y`  or  `c ? x : y`
##   * read frozen snapshots by member access: a.atk, b.pdef, v.some_variable, s.hit
##     (roots: a = user, b = target, v = variables, s = the action/skill being used)
##   * call helpers from an allow-list (FUNCTIONS). Method calls (`a.free()`) are rejected.
##
## API:
##   RPGFormula.compile(text) -> {ok, ast, error, column}     (cached by text)
##   RPGFormula.evaluate(ast, env) -> {ok, value, error}
##   RPGFormula.evaluate_text(text, env) -> {ok, value, error}
##   env = {"a": Dictionary, "b": Dictionary, "v": Dictionary, "s": Dictionary, "rng": RPGRandom}
## Errors always name the problem; a failed formula never quietly yields 0.

const MAX_LENGTH := 2000
const MAX_DEPTH := 64
const MAX_DICE_COUNT := 100        ## dice in one term ("100d6")
const MAX_DICE_SIDES := 1000
const MAX_DICE_TERMS := 10
const MAX_DICE_PER_EVAL := 1000    ## total dice one evaluation may roll
const MAX_CACHE := 1024

const ROOTS := ["a", "b", "v", "s"]
## name -> [min args, max args]
const FUNCTIONS := {
	"min": [1, 16], "max": [1, 16], "clamp": [3, 3], "abs": [1, 1],
	"floor": [1, 1], "ceil": [1, 1], "round": [1, 1],
	"roll": [1, 2], "rand": [2, 2],
	"mod": [1, 1], "stat": [2, 2], "resource": [2, 2], "has_state": [2, 2],
}
const KEYWORDS := ["if", "then", "else", "and", "or", "not", "true", "false"]
const COMPARISONS := ["==", "!=", "<", "<=", ">", ">="]

static var _cache := {}


# --------------------------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------------------------

## Parses `text` into an AST. Results are cached by text (the AST is never mutated).
static func compile(text: String) -> Dictionary:
	if _cache.has(text):
		return _cache[text]
	var result := _compile_uncached(text)
	if _cache.size() >= MAX_CACHE:
		_cache.clear()
	_cache[text] = result
	return result


## Evaluates a compiled AST. `env` keys: a, b, v, s (Dictionaries) and rng (RPGRandom).
static func evaluate(ast: Dictionary, env: Dictionary) -> Dictionary:
	if ast.is_empty():
		return {"ok": false, "value": null, "error": "formula was not compiled"}
	var e := _Eval.new()
	e.env = env
	var value: Variant = e.ev(ast)
	if e.error != "":
		return {"ok": false, "value": null, "error": e.error}
	if not (_is_num(value) or value is bool):
		return {"ok": false, "value": null, "error": "formula result must be a number or true/false, got %s" % _type_name(value)}
	return {"ok": true, "value": value, "error": ""}


## compile + evaluate. Compile errors are reported as "column N: message".
static func evaluate_text(text: String, env: Dictionary) -> Dictionary:
	var c := compile(text)
	if not c.ok:
		return {"ok": false, "value": null, "error": "column %d: %s" % [c.column, c.error]}
	return evaluate(c.ast, env)


## Returns "" when `text` compiles, otherwise a readable error.
static func check(text: String) -> String:
	var c := compile(text)
	return "" if c.ok else "column %d: %s" % [c.column, c.error]


## Parses a dice expression such as "2d6+1", "d20", "1d8 - 1", "3d4 + 1d6 + 2".
## Returns {ok, terms: [{count, sides, sign}], bonus, dice, error}.
static func parse_dice(text: String) -> Dictionary:
	var out := {"ok": false, "terms": [], "bonus": 0, "dice": 0, "error": ""}
	var s := text.replace(" ", "").to_lower()
	if s == "":
		out.error = "dice expression is empty"
		return out
	var i := 0
	var sign := 1
	var parts := 0
	while i < s.length():
		# optional sign
		if s[i] == "+" or s[i] == "-":
			sign = 1 if s[i] == "+" else -1
			i += 1
		elif parts > 0:
			out.error = "unexpected '%s' in dice '%s'" % [s[i], text]
			return out
		var num_start := i
		while i < s.length() and s[i] >= "0" and s[i] <= "9":
			i += 1
		var num_text := s.substr(num_start, i - num_start)
		if num_text.length() > 9:
			out.error = "number too large in dice '%s'" % text
			return out
		if i < s.length() and s[i] == "d":
			i += 1
			var side_start := i
			while i < s.length() and s[i] >= "0" and s[i] <= "9":
				i += 1
			var side_text := s.substr(side_start, i - side_start)
			if side_text == "" or side_text.length() > 9:
				out.error = "dice '%s' needs a number of sides after 'd'" % text
				return out
			var count := 1 if num_text == "" else num_text.to_int()
			var sides := side_text.to_int()
			if count < 1 or count > MAX_DICE_COUNT:
				out.error = "dice '%s': number of dice must be 1..%d" % [text, MAX_DICE_COUNT]
				return out
			if sides < 1 or sides > MAX_DICE_SIDES:
				out.error = "dice '%s': number of sides must be 1..%d" % [text, MAX_DICE_SIDES]
				return out
			out.terms.append({"count": count, "sides": sides, "sign": sign})
			out.dice += count
		else:
			if num_text == "":
				out.error = "dice '%s' is not valid (expected e.g. 2d6+1)" % text
				return out
			out.bonus += sign * num_text.to_int()
		parts += 1
		if parts > MAX_DICE_TERMS:
			out.error = "dice '%s' has too many terms (limit %d)" % [text, MAX_DICE_TERMS]
			return out
	if out.dice > MAX_DICE_COUNT:
		out.error = "dice '%s' rolls too many dice (limit %d)" % [text, MAX_DICE_COUNT]
		return out
	out.ok = true
	return out


## Rolls a parsed dice expression (from parse_dice). Returns {total, naturals: [each die]}.
static func roll_parsed(dice: Dictionary, rng: RPGRandom) -> Dictionary:
	var total: int = dice.bonus
	var naturals := []
	for t in dice.terms:
		for k in t.count:
			var r := rng.randi_range(1, t.sides)
			naturals.append(r)
			total += t.sign * r
	return {"total": total, "naturals": naturals}


## Convenience: parse + roll. {ok, value, naturals, error}
static func roll_dice(text: String, rng: RPGRandom) -> Dictionary:
	var d := parse_dice(text)
	if not d.ok:
		return {"ok": false, "value": 0, "naturals": [], "error": d.error}
	if rng == null:
		return {"ok": false, "value": 0, "naturals": [], "error": "rolling dice needs a random number generator"}
	var r := roll_parsed(d, rng)
	return {"ok": true, "value": r.total, "naturals": r.naturals, "error": ""}


# --------------------------------------------------------------------------------------------
# Tokenizer
# --------------------------------------------------------------------------------------------

## Token: {t: "num"|"str"|"id"|"kw"|"op"|"eof", v, c (1-based column)}
static func _tokenize(text: String) -> Dictionary:
	var toks := []
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		var col := i + 1
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			i += 1
			continue
		if _is_digit(ch):
			var start := i
			while i < n and _is_digit(text[i]):
				i += 1
			var is_float := false
			if i + 1 < n and text[i] == "." and _is_digit(text[i + 1]):
				is_float = true
				i += 1
				while i < n and _is_digit(text[i]):
					i += 1
			var num_text := text.substr(start, i - start)
			if i < n and (_is_ident_start(text[i])):
				return {"ok": false, "error": "unexpected '%s' after number %s" % [text[i], num_text], "column": i + 1}
			if num_text.length() > 15:
				return {"ok": false, "error": "number %s is too long" % num_text, "column": col}
			toks.append({"t": "num", "v": num_text.to_float() if is_float else num_text.to_int(), "c": col})
			continue
		if _is_ident_start(ch):
			var start2 := i
			while i < n and (_is_ident_start(text[i]) or _is_digit(text[i])):
				i += 1
			var word := text.substr(start2, i - start2)
			toks.append({"t": "kw" if KEYWORDS.has(word) else "id", "v": word, "c": col})
			continue
		if ch == "\"" or ch == "'":
			var quote := ch
			i += 1
			var start3 := i
			while i < n and text[i] != quote:
				if text[i] == "\\":
					return {"ok": false, "error": "backslashes are not allowed in strings", "column": i + 1}
				i += 1
			if i >= n:
				return {"ok": false, "error": "string is not closed (missing %s)" % quote, "column": col}
			toks.append({"t": "str", "v": text.substr(start3, i - start3), "c": col})
			i += 1
			continue
		var two := text.substr(i, 2)
		if two in ["==", "!=", "<=", ">=", "&&", "||"]:
			var mapped: String = {"&&": "and", "||": "or"}.get(two, two)
			toks.append({"t": "kw" if mapped in ["and", "or"] else "op", "v": mapped, "c": col})
			i += 2
			continue
		if ch == "!":
			toks.append({"t": "kw", "v": "not", "c": col})
			i += 1
			continue
		if ch == "=":
			return {"ok": false, "error": "use == to compare ('=' assigns, which formulas cannot do)", "column": col}
		if ch in ["+", "-", "*", "/", "%", "(", ")", ",", ".", "?", ":", "<", ">"]:
			toks.append({"t": "op", "v": ch, "c": col})
			i += 1
			continue
		return {"ok": false, "error": "character '%s' is not allowed" % ch, "column": col}
	toks.append({"t": "eof", "v": "", "c": n + 1})
	return {"ok": true, "tokens": toks}


static func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"


static func _is_ident_start(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"


# --------------------------------------------------------------------------------------------
# Parser
# --------------------------------------------------------------------------------------------

static func _compile_uncached(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "ast": {}, "error": "formula is empty", "column": 1}
	if text.length() > MAX_LENGTH:
		return {"ok": false, "ast": {}, "error": "formula is longer than %d characters" % MAX_LENGTH, "column": 1}
	var tk := _tokenize(text)
	if not tk.ok:
		return {"ok": false, "ast": {}, "error": tk.error, "column": tk.column}
	var p := _Parser.new()
	p.toks = tk.tokens
	var ast := p.parse_expr()
	if p.error == "" and p.peek().t != "eof":
		p.fail("unexpected %s after the end of the formula" % p.describe(p.peek()), p.peek().c)
	if p.error != "":
		return {"ok": false, "ast": {}, "error": p.error, "column": p.col}
	return {"ok": true, "ast": ast, "error": "", "column": 0}


## AST nodes (Dictionaries, key "k" = kind, "c" = column):
##   num/str/bool {v} | name {v} | member {o, m} | neg {x} | not {x}
##   bin {op, l, r} | and {l, r} | or {l, r} | if {cond, then, else} | call {f, args, dice?}
class _Parser:
	var toks: Array = []
	var pos := 0
	var error := ""
	var col := 0
	var depth := 0

	func peek() -> Dictionary:
		return toks[pos]

	func next() -> Dictionary:
		var t: Dictionary = toks[pos]
		if pos < toks.size() - 1:
			pos += 1
		return t

	func is_op(v: String) -> bool:
		var t := peek()
		return t.t == "op" and t.v == v

	func is_kw(v: String) -> bool:
		var t := peek()
		return t.t == "kw" and t.v == v

	func describe(t: Dictionary) -> String:
		match t.t:
			"eof":
				return "end of formula"
			"str":
				return "string '%s'" % t.v
		return "'%s'" % str(t.v)

	func fail(msg: String, c: int) -> Dictionary:
		if error == "":
			error = msg
			col = c
		return {}

	func expect_op(v: String) -> bool:
		if is_op(v):
			next()
			return true
		fail("expected '%s' but found %s" % [v, describe(peek())], peek().c)
		return false

	func expect_kw(v: String) -> bool:
		if is_kw(v):
			next()
			return true
		fail("expected '%s' but found %s" % [v, describe(peek())], peek().c)
		return false

	func enter() -> bool:
		depth += 1
		if depth > RPGFormula.MAX_DEPTH:
			fail("formula is nested too deeply", peek().c)
			return false
		return true

	func parse_expr() -> Dictionary:
		if not enter():
			return {}
		var node := {}
		var c: int = peek().c
		if is_kw("if"):
			next()
			var cond := parse_expr()
			if error != "" or not expect_kw("then"):
				return {}
			var a := parse_expr()
			if error != "" or not expect_kw("else"):
				return {}
			var b := parse_expr()
			if error != "":
				return {}
			node = {"k": "if", "cond": cond, "then": a, "else": b, "c": c}
		else:
			node = parse_or()
			if error != "":
				return {}
			if is_op("?"):
				next()
				var t := parse_expr()
				if error != "" or not expect_op(":"):
					return {}
				var e := parse_expr()
				if error != "":
					return {}
				node = {"k": "if", "cond": node, "then": t, "else": e, "c": c}
		depth -= 1
		return node

	func parse_or() -> Dictionary:
		var l := parse_and()
		while error == "" and is_kw("or"):
			var c: int = next().c
			var r := parse_and()
			l = {"k": "or", "l": l, "r": r, "c": c}
		return l if error == "" else {}

	func parse_and() -> Dictionary:
		var l := parse_not()
		while error == "" and is_kw("and"):
			var c: int = next().c
			var r := parse_not()
			l = {"k": "and", "l": l, "r": r, "c": c}
		return l if error == "" else {}

	func parse_not() -> Dictionary:
		if is_kw("not"):
			if not enter():
				return {}
			var c: int = next().c
			var x := parse_not()
			depth -= 1
			return {"k": "not", "x": x, "c": c} if error == "" else {}
		return parse_cmp()

	func parse_cmp() -> Dictionary:
		var l := parse_add()
		if error != "":
			return {}
		var t := peek()
		if t.t == "op" and RPGFormula.COMPARISONS.has(t.v):
			next()
			var r := parse_add()
			if error != "":
				return {}
			var t2 := peek()
			if t2.t == "op" and RPGFormula.COMPARISONS.has(t2.v):
				return fail("comparisons cannot be chained; combine them with 'and'", t2.c)
			return {"k": "bin", "op": t.v, "l": l, "r": r, "c": t.c}
		return l

	func parse_add() -> Dictionary:
		var l := parse_mul()
		while error == "" and (is_op("+") or is_op("-")):
			var t := next()
			var r := parse_mul()
			l = {"k": "bin", "op": t.v, "l": l, "r": r, "c": t.c}
		return l if error == "" else {}

	func parse_mul() -> Dictionary:
		var l := parse_unary()
		while error == "" and (is_op("*") or is_op("/") or is_op("%")):
			var t := next()
			var r := parse_unary()
			l = {"k": "bin", "op": t.v, "l": l, "r": r, "c": t.c}
		return l if error == "" else {}

	func parse_unary() -> Dictionary:
		if is_op("-") or is_op("+"):
			if not enter():
				return {}
			var t := next()
			var x := parse_unary()
			depth -= 1
			if error != "":
				return {}
			if t.v == "+":
				return x
			if x.k == "num":
				return {"k": "num", "v": -x.v, "c": t.c}
			return {"k": "neg", "x": x, "c": t.c}
		return parse_postfix()

	func parse_postfix() -> Dictionary:
		var node := parse_primary()
		while error == "" and is_op("."):
			var dot := next()
			var t := peek()
			if t.t != "id" and t.t != "kw":
				return fail("expected a name after '.'", t.c)
			next()
			if is_op("("):
				return fail("method calls are not allowed ('%s(...)'); only helper functions can be called" % t.v, t.c)
			node = {"k": "member", "o": node, "m": t.v, "c": dot.c}
		return node if error == "" else {}

	func parse_primary() -> Dictionary:
		var t := peek()
		match t.t:
			"num":
				next()
				return {"k": "num", "v": t.v, "c": t.c}
			"str":
				next()
				return {"k": "str", "v": t.v, "c": t.c}
			"kw":
				if t.v == "true" or t.v == "false":
					next()
					return {"k": "bool", "v": t.v == "true", "c": t.c}
				return fail("unexpected '%s'" % t.v, t.c)
			"op":
				if t.v == "(":
					next()
					var e := parse_expr()
					if error != "" or not expect_op(")"):
						return {}
					return e
				return fail("unexpected '%s'" % t.v, t.c)
			"id":
				next()
				if is_op("("):
					return parse_call(t)
				if not RPGFormula.ROOTS.has(t.v):
					return fail("unknown name '%s' (formulas can read a, b, v and s)" % t.v, t.c)
				return {"k": "name", "v": t.v, "c": t.c}
		return fail("unexpected %s" % describe(t), t.c)

	func parse_call(name_tok: Dictionary) -> Dictionary:
		var fname: String = name_tok.v
		if not RPGFormula.FUNCTIONS.has(fname):
			return fail("unknown function '%s' (allowed: %s)" % [fname, ", ".join(RPGFormula.FUNCTIONS.keys())], name_tok.c)
		next() # (
		var args := []
		if not is_op(")"):
			while true:
				var a := parse_expr()
				if error != "":
					return {}
				args.append(a)
				if is_op(","):
					next()
					continue
				break
		if not expect_op(")"):
			return {}
		var arity: Array = RPGFormula.FUNCTIONS[fname]
		if args.size() < arity[0] or args.size() > arity[1]:
			var want := str(arity[0]) if arity[0] == arity[1] else "%d to %d" % [arity[0], arity[1]]
			return fail("%s() takes %s argument(s), got %d" % [fname, want, args.size()], name_tok.c)
		var node := {"k": "call", "f": fname, "args": args, "c": name_tok.c}
		# Literal dice are validated (and pre-parsed) at compile time.
		if fname == "roll" and args.size() == 1 and args[0].k == "str":
			var d := RPGFormula.parse_dice(args[0].v)
			if not d.ok:
				return fail(d.error, args[0].c)
			node["dice"] = d
		return node


# --------------------------------------------------------------------------------------------
# Evaluator
# --------------------------------------------------------------------------------------------

class _Eval:
	var env: Dictionary = {}
	var error := ""
	var dice_rolled := 0

	func fail(msg: String) -> Variant:
		if error == "":
			error = msg
		return null

	func ev(n: Dictionary) -> Variant:
		match n.k:
			"num", "str", "bool":
				return n.v
			"name":
				if not env.has(n.v):
					return fail("'%s' is not available in this formula" % n.v)
				return checked(env[n.v], n.v)
			"member":
				var o: Variant = ev(n.o)
				if error != "":
					return null
				var path := RPGFormula._path_of(n.o)
				if not (o is Dictionary):
					return fail("cannot read '.%s' of %s (a %s)" % [n.m, path, RPGFormula._type_name(o)])
				if not o.has(n.m):
					if path == "v":
						return fail("unknown variable '%s'" % n.m)
					return fail("%s has no value '%s'" % [path, n.m])
				return checked(o[n.m], "%s.%s" % [path, n.m])
			"neg":
				var x: Variant = ev(n.x)
				if error != "":
					return null
				if not RPGFormula._is_num(x):
					return fail("cannot negate %s" % RPGFormula._type_name(x))
				return -x
			"not":
				var t: Variant = truth(ev(n.x), "not")
				if error != "":
					return null
				return not t
			"and":
				var l: Variant = truth(ev(n.l), "and")
				if error != "" or not l:
					return false if error == "" else null
				var r: Variant = truth(ev(n.r), "and")
				return r if error == "" else null
			"or":
				var l2: Variant = truth(ev(n.l), "or")
				if error != "":
					return null
				if l2:
					return true
				var r2: Variant = truth(ev(n.r), "or")
				return r2 if error == "" else null
			"if":
				var cond: Variant = truth(ev(n.cond), "if")
				if error != "":
					return null
				return ev(n.then) if cond else ev(n["else"])
			"bin":
				var lv: Variant = ev(n.l)
				if error != "":
					return null
				var rv: Variant = ev(n.r)
				if error != "":
					return null
				return binary(n.op, lv, rv)
			"call":
				return call_fn(n)
		return fail("internal: unknown node '%s'" % str(n.k))

	## Only plain data may enter a formula: numbers, bools, strings, Dictionaries, Arrays.
	func checked(v: Variant, what: String) -> Variant:
		match typeof(v):
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_DICTIONARY, TYPE_ARRAY:
				return v
			TYPE_STRING_NAME:
				return str(v)
			TYPE_NIL:
				return fail("%s has no value" % what)
		return fail("%s is not a plain value and cannot be used in a formula" % what)

	func truth(v: Variant, where: String) -> Variant:
		if error != "":
			return null
		if v is bool:
			return v
		if RPGFormula._is_num(v):
			return v != 0
		return fail("'%s' needs true/false or a number, got %s" % [where, RPGFormula._type_name(v)])

	func binary(op: String, l: Variant, r: Variant) -> Variant:
		var ln := RPGFormula._is_num(l)
		var rn := RPGFormula._is_num(r)
		if op == "==" or op == "!=":
			var same_kind := (ln and rn) or (l is bool and r is bool) or (l is String and r is String)
			if not same_kind:
				return fail("cannot compare %s with %s" % [RPGFormula._type_name(l), RPGFormula._type_name(r)])
			var eq: bool = (l == r)
			return eq if op == "==" else not eq
		if not ln or not rn:
			return fail("'%s' needs numbers, got %s and %s" % [op, RPGFormula._type_name(l), RPGFormula._type_name(r)])
		var both_int := l is int and r is int
		var out: Variant = null
		match op:
			"+":
				out = l + r
			"-":
				out = l - r
			"*":
				out = l * r
			"/":
				if r == 0:
					return fail("division by zero")
				out = floori(float(l) / float(r)) if both_int else float(l) / float(r)
			"%":
				if r == 0:
					return fail("modulo by zero")
				if both_int:
					out = l - r * floori(float(l) / float(r))
				else:
					out = float(l) - float(r) * floorf(float(l) / float(r))
			"<":
				return l < r
			"<=":
				return l <= r
			">":
				return l > r
			">=":
				return l >= r
			_:
				return fail("unknown operator '%s'" % op)
		if out is float and not is_finite(out):
			return fail("result of '%s' is too large" % op)
		return out

	func num_arg(v: Variant, fname: String, idx: int) -> bool:
		if not RPGFormula._is_num(v):
			fail("%s() argument %d must be a number, got %s" % [fname, idx + 1, RPGFormula._type_name(v)])
			return false
		return true

	func int_arg(v: Variant, fname: String, idx: int) -> Variant:
		if not num_arg(v, fname, idx):
			return null
		if v is float:
			if v != floorf(v):
				return fail("%s() argument %d must be a whole number, got %s" % [fname, idx + 1, str(v)])
			return int(v)
		return v

	func get_rng(fname: String) -> RPGRandom:
		var r: Variant = env.get("rng")
		if r is RPGRandom:
			return r
		fail("%s() needs a random number generator, but none was given" % fname)
		return null

	func spend_dice(count: int) -> bool:
		dice_rolled += count
		if dice_rolled > RPGFormula.MAX_DICE_PER_EVAL:
			fail("formula rolls too many dice (limit %d per evaluation)" % RPGFormula.MAX_DICE_PER_EVAL)
			return false
		return true

	func call_fn(n: Dictionary) -> Variant:
		var f: String = n.f
		var args := []
		for a in n.args:
			var v: Variant = ev(a)
			if error != "":
				return null
			args.append(v)
		match f:
			"min", "max":
				var best: Variant = null
				for i in args.size():
					if not num_arg(args[i], f, i):
						return null
					if best == null or (f == "min" and args[i] < best) or (f == "max" and args[i] > best):
						best = args[i]
				return best
			"clamp":
				for i in 3:
					if not num_arg(args[i], f, i):
						return null
				if args[1] > args[2]:
					return fail("clamp() low bound %s is above high bound %s" % [str(args[1]), str(args[2])])
				return min(max(args[0], args[1]), args[2])
			"abs":
				if not num_arg(args[0], f, 0):
					return null
				return absi(args[0]) if args[0] is int else absf(args[0])
			"floor", "ceil", "round":
				if not num_arg(args[0], f, 0):
					return null
				if args[0] is int:
					return args[0]
				match f:
					"floor":
						return floori(args[0])
					"ceil":
						return ceili(args[0])
				return roundi(args[0])
			"mod":
				if not num_arg(args[0], f, 0):
					return null
				return floori((float(args[0]) - 10.0) / 2.0)
			"rand":
				var lo: Variant = int_arg(args[0], f, 0)
				if error != "":
					return null
				var hi: Variant = int_arg(args[1], f, 1)
				if error != "":
					return null
				if lo > hi:
					return fail("rand(%d, %d): low bound is above high bound" % [lo, hi])
				var rng := get_rng(f)
				if rng == null:
					return null
				return rng.randi_range(lo, hi)
			"roll":
				return call_roll(n, args)
			"stat", "resource":
				var key := "stats" if f == "stat" else "resources"
				if not (args[0] is Dictionary) or not args[0].has(key):
					return fail("%s() first argument must be a battler such as a or b" % f)
				if not (args[1] is String):
					return fail("%s() second argument must be a name in quotes" % f)
				var table: Dictionary = args[0][key]
				if not table.has(args[1]):
					return fail("%s has no %s '%s'" % [RPGFormula._path_of(n.args[0]), "stat" if f == "stat" else "resource", args[1]])
				return checked(table[args[1]], "%s('%s')" % [f, args[1]])
			"has_state":
				if not (args[0] is Dictionary) or not args[0].has("states"):
					return fail("has_state() first argument must be a battler such as a or b")
				if not (args[1] is String):
					return fail("has_state() second argument must be a state id in quotes")
				var states: Variant = args[0].states
				return states is Array and (states as Array).has(args[1])
		return fail("unknown function '%s'" % f)

	func call_roll(n: Dictionary, args: Array) -> Variant:
		var dice: Dictionary
		if args.size() == 1:
			if n.has("dice"):
				dice = n.dice
			elif args[0] is String:
				dice = RPGFormula.parse_dice(args[0])
				if not dice.ok:
					return fail(dice.error)
			else:
				return fail("roll() needs dice text such as \"2d6+1\", or roll(count, sides)")
		else:
			var count: Variant = int_arg(args[0], "roll", 0)
			if error != "":
				return null
			var sides: Variant = int_arg(args[1], "roll", 1)
			if error != "":
				return null
			if count < 0 or count > RPGFormula.MAX_DICE_COUNT:
				return fail("roll(): number of dice must be 0..%d, got %d" % [RPGFormula.MAX_DICE_COUNT, count])
			if sides < 1 or sides > RPGFormula.MAX_DICE_SIDES:
				return fail("roll(): number of sides must be 1..%d, got %d" % [RPGFormula.MAX_DICE_SIDES, sides])
			dice = {"ok": true, "terms": [{"count": count, "sides": sides, "sign": 1}], "bonus": 0, "dice": count}
		var rng := get_rng("roll")
		if rng == null:
			return null
		if not spend_dice(dice.dice):
			return null
		return RPGFormula.roll_parsed(dice, rng).total


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

static func _is_num(v: Variant) -> bool:
	return v is int or v is float


static func _type_name(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "nothing"
		TYPE_INT, TYPE_FLOAT:
			return "a number"
		TYPE_BOOL:
			return "true/false"
		TYPE_STRING, TYPE_STRING_NAME:
			return "text"
		TYPE_DICTIONARY:
			return "a record"
		TYPE_ARRAY:
			return "a list"
	return "an object"


## Readable source path of a name/member node, e.g. "a.atk".
static func _path_of(n: Dictionary) -> String:
	match n.k:
		"name":
			return n.v
		"member":
			return "%s.%s" % [_path_of(n.o), n.m]
	return "value"
