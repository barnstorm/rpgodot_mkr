@tool
extends RPGCommand
## Sets typed variables: one, a range of them, or the one whose id another variable holds. Numbers
## support set/add/sub/mul/div/mod; true/false and text support set. The value is a number, text,
## true/false, {variable: id}, {pointer: id}, game data, {random: [min, max]} or {formula: "..."}.
## Random and formula re-roll for each variable in a range, and a range is written all at once: if
## any value does not fit its variable, nothing is written.


static func descriptor() -> Dictionary:
	return {
		"type": "set_variable", "schema_version": 1, "category": "state", "label": "Control Variable",
		"fields": [
			{"key": "target", "kind": "choice", "options": ["single", "range", "pointer"], "option_labels": ["One variable", "Range", "Indirect"], "default": "single", "label": "Target"},
			{"key": "id", "kind": "ref", "ref": "variable", "label": "Variable", "required": true, "show_if": {"key": "target", "equals": "single"}},
			{"key": "from", "kind": "ref", "ref": "variable", "label": "From", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "to", "kind": "ref", "ref": "variable", "label": "To", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "pointer", "kind": "ref", "ref": "variable", "label": "Holds the target's id", "required": true, "show_if": {"key": "target", "equals": "pointer"}},
			{"key": "operation", "kind": "choice", "options": ["set", "add", "sub", "mul", "div", "mod"], "default": "set", "label": "Operation"},
			{"key": "value", "kind": "operand", "default": 0, "label": "Value"},
		],
	}


func summary(args: Dictionary) -> String:
	var ops := {"set": "=", "add": "+=", "sub": "-=", "mul": "*=", "div": "/=", "mod": "%="}
	var mode := str(args.get("target", "single"))
	var name := "[%s]" % args.get("id", "?")
	if mode == "range":
		name = "%s..%s" % [args.get("from", "?"), args.get("to", "?")]
	elif mode == "pointer":
		name = "[%s]" % args.get("pointer", "?")
	var v: Variant = args.get("value", 0)
	var shown := RPGCommand.describe_operand(v)
	if v is Dictionary and v.has("random"):
		shown = "random %s..%s" % [v.random[0], v.random[1]]
	elif v is Dictionary and v.has("formula"):
		shown = "formula %s" % v.formula
	return "Variable %s %s %s" % [name, ops.get(args.get("operation", "set"), "="), shown]


## The command's target ids. A range spans the declared variables between "from" and "to" in
## declaration order (state.json), in either direction. Empty when the ids do not name variables.
func _target_ids(ctx: RPGContext, args: Dictionary, mode: String) -> Array:
	if mode == "range":
		var order: Array = ctx.data.variables.keys() if ctx.data != null else []
		var ia := order.find(str(args.get("from", "")))
		var ib := order.find(str(args.get("to", "")))
		if ia < 0 or ib < 0:
			return []
		if ia > ib:
			var t := ia
			ia = ib
			ib = t
		return order.slice(ia, ib + 1)
	if mode == "pointer":
		var pointed := str(ctx.state.get_variable(str(args.get("pointer", ""))))
		return [pointed] if pointed != "" else []
	var id := str(args.get("id", ""))
	return [id] if id != "" else []


func _target_error(ctx: RPGContext, args: Dictionary, mode: String) -> String:
	match mode:
		"range":
			if str(args.get("from", "")) == "" or str(args.get("to", "")) == "":
				return "Control Variable: choose the range's start and end variables."
			return "Control Variable: '%s' and '%s' are not both declared variables." % [args.get("from", ""), args.get("to", "")]
		"pointer":
			var pid := str(args.get("pointer", ""))
			if pid == "":
				return "Control Variable: choose the variable that holds the target's id."
			var pointed := str(ctx.state.get_variable(pid))
			if pointed == "":
				return "Control Variable: variable '%s' does not hold a variable id (it is empty)." % pid
			return "Control Variable: '%s' is not a declared variable." % pointed
	return "Control Variable: choose a variable."


## Checks the ref fields for the chosen target; the base validate() skips fields hidden by show_if,
## which also hides them when "target" is missing entirely (commands saved before it existed).
func validate(args: Dictionary) -> Array:
	var errs: Array = super.validate(args)
	var key := "id"
	match str(args.get("target", "single")):
		"range":
			key = "from"
			var b := str(args.get("to", ""))
			if b != "" and not RPGIds.is_valid(b):
				errs.append({"severity": "error", "field": "to", "message": "'To' is not a valid id."})
		"pointer":
			key = "pointer"
	var v := str(args.get(key, ""))
	if v != "" and not RPGIds.is_valid(v):
		errs.append({"severity": "error", "field": key, "message": "'%s' is not a valid id." % key})
	return errs


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var mode := str(args.get("target", "single"))
	var ids := _target_ids(ctx, args, mode)
	if ids.is_empty():
		return RPGResult.error(_target_error(ctx, args, mode))
	var op: String = args.get("operation", "set")
	# Pass one resolves every value and checks it fits its variable (random and formulas re-roll
	# per variable); pass two writes, so a range never ends up half-changed when one refuses.
	var writes := {}
	for id in ids:
		id = str(id)
		if ctx.data != null and not ctx.data.variables.is_empty() and not ctx.data.variables.has(id):
			return RPGResult.error("Could not set variable '%s' (it is not declared)." % id)
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
		var coerced: Variant = RPGGameState.coerce(t, v)
		if coerced == null:
			return RPGResult.error("Could not set variable '%s' (unknown, or wrong type: %s)." % [id, t])
		writes[id] = coerced
	for id in writes:
		ctx.state.set_variable(id, writes[id])
	return RPGResult.ok()
