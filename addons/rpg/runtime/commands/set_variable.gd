@tool
extends RPGCommand
## Sets a typed variable. Numbers support set/add/sub/mul/div/mod; true/false and text support set.
## The value is a number, text, true/false, {variable: id}, {pointer: id} (the variable another
## variable names), {random: [min, max]} or {formula: "..."}. The target is one variable, every
## variable between two ids (in state.json's order), or the variable a pointer variable names;
## the operation applies to each target on its own (#54).


static func descriptor() -> Dictionary:
	return {
		"type": "set_variable", "schema_version": 1, "category": "state", "label": "Control Variable",
		"fields": [
			{"key": "target", "kind": "choice", "options": ["one", "range", "pointer"], "option_labels": ["One variable", "Range of variables", "Variable named by a variable"], "default": "one", "label": "Target"},
			{"key": "id", "kind": "ref", "ref": "variable", "label": "Variable", "required": true, "show_if": {"key": "target", "equals": ["one", null]}},
			{"key": "from", "kind": "ref", "ref": "variable", "label": "From", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "to", "kind": "ref", "ref": "variable", "label": "To", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Variable named by variable", "required": true, "show_if": {"key": "target", "equals": "pointer"}},
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
	match str(args.get("target", "one")):
		"range":
			return "Variables [%s] .. [%s] %s %s" % [args.get("from", "?"), args.get("to", "?"), ops.get(args.get("operation", "set"), "="), shown]
		"pointer":
			return "Variable V[%s] %s %s" % [args.get("variable", "?"), ops.get(args.get("operation", "set"), "="), shown]
	return "Variable [%s] %s %s" % [args.get("id", "?"), ops.get(args.get("operation", "set"), "="), shown]


## The variable ids this command writes to: one id, the slice of state.json's order between two
## ids, or the id a variable holds (empty when it holds none).
func _target_ids(ctx: RPGContext, args: Dictionary) -> Array:
	match str(args.get("target", "one")):
		"range":
			var order := ctx.state.variable_order()
			var a := order.find(str(args.get("from", "")))
			var b := order.find(str(args.get("to", "")))
			if a == -1 or b == -1 or a > b:
				return []
			return order.slice(a, b + 1)
		"pointer":
			var id := str(ctx.state.get_variable(str(args.get("variable", ""))))
			return [id] if id != "" else []
	return [str(args.get("id", ""))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var v: Variant = args.get("value", 0)
	if v is Dictionary and v.has("pointer"):
		# Resolved here as well so an empty pointer stops the command instead of writing 0.
		if str(ctx.state.get_variable(str(v.pointer))) == "":
			return RPGResult.error("Variable '%s' holds no variable id." % v.pointer)
		v = ctx.operand(v)
	elif v is Dictionary and v.has("random"):
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
	var ids := _target_ids(ctx, args)
	if ids.is_empty():
		if str(args.get("target", "one")) == "pointer":
			return RPGResult.error("Variable '%s' holds no variable id." % args.get("variable", "?"))
		return RPGResult.error("No variables between [%s] and [%s]." % [args.get("from", "?"), args.get("to", "?")])
	var op: String = args.get("operation", "set")
	# The value is resolved once, then the operation applies to each target's own current value.
	for id in ids:
		var value: Variant = v
		var t := ctx.state.variable_type(id)
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
			value = cur
		if not ctx.state.set_variable(id, value):
			return RPGResult.error("Could not set variable '%s' (unknown, or wrong type: %s)." % [id, t])
	return RPGResult.ok()
