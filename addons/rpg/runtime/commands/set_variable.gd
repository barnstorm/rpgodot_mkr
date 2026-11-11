@tool
extends RPGCommand
## Sets a typed variable. Numbers support set/add/sub/mul/div/mod; true/false and text support set.
## The value is a number, text, true/false, {variable: id}, {random: [min, max]} or {formula: "..."}.


static func descriptor() -> Dictionary:
	return {
		"type": "set_variable", "schema_version": 1, "category": "state", "label": "Control Variable",
		"fields": [
			{"key": "id", "kind": "ref", "ref": "variable", "label": "Variable", "required": true},
			{"key": "operation", "kind": "choice", "options": ["set", "add", "sub", "mul", "div", "mod"], "default": "set", "label": "Operation"},
			{"key": "value", "kind": "operand", "default": 0, "label": "Value"},
		],
	}


func summary(args: Dictionary) -> String:
	var ops := {"set": "=", "add": "+=", "sub": "-=", "mul": "*=", "div": "/=", "mod": "%="}
	var v: Variant = args.get("value", 0)
	var shown := RPGCommand.describe_operand(v)
	if v is Dictionary and v.has("random"):
		shown = "random %s..%s" % [v.random[0], v.random[1]]
	elif v is Dictionary and v.has("formula"):
		shown = "formula %s" % v.formula
	return "Variable [%s] %s %s" % [args.get("id", "?"), ops.get(args.get("operation", "set"), "="), shown]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id: String = str(args.get("id", ""))
	var v: Variant = args.get("value", 0)
	if v is Dictionary and v.has("random"):
		var lo := int(v.random[0])
		var hi := int(v.random[1])
		v = ctx.rpg.rng.randi_range(lo, hi) if ctx.rpg.rng != null else randi_range(lo, hi)
	elif v is Dictionary and v.has("formula"):
		if ctx.rpg.rules == null or not ctx.rpg.rules.has_method("evaluate_formula"):
			return RPGResult.error("Formulas need a rule system.")
		var fr: Variant = ctx.rpg.rules.evaluate_formula(str(v.formula), null, null)
		if fr is Dictionary:
			if not fr.get("ok", false):
				return RPGResult.error("Formula error in Control Variable: %s" % fr.get("error", "?"))
			v = fr.value
		else:
			v = fr
	else:
		v = ctx.operand(v)
	var t := ctx.state.variable_type(id)
	var op: String = args.get("operation", "set")
	if op != "set":
		if t != "int" and t != "float":
			return RPGResult.error("Variable '%s' is %s; only 'set' is allowed." % [id, t])
		var cur := float(ctx.state.get_variable(id))
		var n := float(v)
		match op:
			"add": cur += n
			"sub": cur -= n
			"mul": cur *= n
			"div":
				if n == 0:
					return RPGResult.error("Division by zero in Control Variable '%s'." % id)
				cur = cur / n if t == "float" else float(int(cur) / int(n))
			"mod":
				if n == 0:
					return RPGResult.error("Modulo by zero in Control Variable '%s'." % id)
				cur = fmod(cur, n) if t == "float" else float(int(cur) % int(n))
		v = cur
	if not ctx.state.set_variable(id, v):
		return RPGResult.error("Could not set variable '%s' (unknown, or wrong type: %s)." % [id, t])
	return RPGResult.ok()
