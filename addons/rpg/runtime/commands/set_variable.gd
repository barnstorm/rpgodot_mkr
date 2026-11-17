@tool
extends RPGCommand
## Sets typed variables: one, a range of them, the one whose id another variable holds, or an
## event's self variable (this event's or any event's, on any map). Numbers support
## set/add/sub/mul/div/mod; true/false and text support set. The value is a number, text,
## true/false, {variable: id}, {pointer: id}, {self_variable: {...}}, game data, {random: [min, max]}
## or {formula: "..."}. Random and formula re-roll for each variable in a range, and a range is
## written all at once: if any value does not fit its variable, nothing is written.
##
## Whole-number division and remainder follow the rule set (RPGRuleSystem.variable_division):
## towards zero as RPG Maker 2000/2003, or rounded down as VX Ace's Ruby. Dividing or taking the
## remainder by zero sets the variable to 0 and the event goes on, as in RPG Maker; the mistake is
## noted as a warning (RPGGameState.warn).


static func descriptor() -> Dictionary:
	return {
		"type": "set_variable", "schema_version": 1, "category": "state", "label": "Control Variable",
		"fields": [
			{"key": "target", "kind": "choice", "options": ["single", "range", "pointer", "self"], "option_labels": ["One variable", "Range", "Indirect", "Self variable"], "default": "single", "label": "Target"},
			{"key": "id", "kind": "ref", "ref": "variable", "label": "Variable", "required": true, "show_if": {"key": "target", "equals": "single"}},
			{"key": "from", "kind": "ref", "ref": "variable", "label": "From", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "to", "kind": "ref", "ref": "variable", "label": "To", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "pointer", "kind": "ref", "ref": "variable", "label": "Holds the target's id", "required": true, "show_if": {"key": "target", "equals": "pointer"}},
			{"key": "name", "kind": "text", "label": "Name (e.g. times_opened)", "required": true, "show_if": {"key": "target", "equals": "self"}},
			{"key": "event", "kind": "text", "default": "", "label": "Event (blank = this event)", "show_if": {"key": "target", "equals": "self"}},
			{"key": "map", "kind": "ref", "ref": "map", "label": "Map (blank = this map)", "show_if": {"key": "target", "equals": "self"}},
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
	elif mode == "self":
		var ev: String = str(args.get("event", ""))
		name = "%s.%s" % [ev if ev != "" else "this", args.get("name", "?")]
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
		"self":
			var n := str(args.get("name", ""))
			if n != "" and not RPGIds.is_valid(n):
				errs.append({"severity": "error", "field": "name", "message": "'Name' is not a valid id (lowercase letters, digits and _)."})
			var e := str(args.get("event", ""))
			if e != "" and not RPGIds.is_valid(e):
				errs.append({"severity": "error", "field": "event", "message": "'Event' is not a valid id."})
			return errs
	var v := str(args.get(key, ""))
	if v != "" and not RPGIds.is_valid(v):
		errs.append({"severity": "error", "field": key, "message": "'%s' is not a valid id." % key})
	return errs


## Resolves the "value" field to [ok, value] (or [false, error message]).
func _resolve_value(ctx: RPGContext, v: Variant) -> Array:
	if v is Dictionary and v.has("random"):
		var lo := int(v.random[0])
		var hi := int(v.random[1])
		return [true, ctx.rpg.rng.randi_range(lo, hi) if ctx.rpg.rng != null else randi_range(lo, hi)]
	if v is Dictionary and v.has("formula"):
		if ctx.rpg.rules == null or not ctx.rpg.rules.has_method("evaluate_formula"):
			return [false, "Formulas need a rule system."]
		var fr: Variant = ctx.rpg.rules.evaluate_formula(str(v.formula), null, null)
		if fr is Dictionary:
			if not fr.get("ok", false):
				return [false, "Formula error in Control Variable: %s" % fr.get("error", "?")]
			return [true, fr.value]
		return [true, fr]
	return [true, ctx.operand(v)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var mode := str(args.get("target", "single"))
	if mode == "self":
		return _run_self(ctx, args)
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
		var rv: Array = _resolve_value(ctx, args.get("value", 0))
		if not rv[0]:
			return RPGResult.error(str(rv[1]))
		var v: Variant = rv[1]
		var t := ctx.state.variable_type(id)
		var ao: Array = _apply_op(ctx, op, t, ctx.state.get_variable(id), v, id)
		if not ao[0]:
			return RPGResult.error(str(ao[1]))
		var coerced: Variant = RPGGameState.coerce(t, ao[1])
		if coerced == null:
			return RPGResult.error("Could not set variable '%s' (unknown, or wrong type: %s)." % [id, t])
		writes[id] = coerced
	for id in writes:
		ctx.state.set_variable(id, writes[id])
	return RPGResult.ok()


## Applies the operation to a current value: [true, value] (or [false, error message]).
func _apply_op(ctx: RPGContext, op: String, t: String, current: Variant, v: Variant, what: String) -> Array:
	if op == "set":
		return [true, v]
	if t != "int" and t != "float":
		return [false, "'%s' is %s; only 'set' is allowed." % [what, t]]
	if op == "div" or op == "mod":
		return [true, _divide(ctx, op, t, current, v, what)]
	var cur := float(current)
	var n := float(v)
	match op:
		"add": cur += n
		"sub": cur -= n
		"mul": cur *= n
	return [true, cur]


## Division and remainder. A whole-number variable divides by the whole part of the value, in
## whole numbers (no detour through decimals, so large values stay exact).
func _divide(ctx: RPGContext, op: String, t: String, current: Variant, v: Variant, what: String) -> Variant:
	var rounds_down := _rounds_down(ctx)
	if t == "float":
		var x := float(current)
		var y := float(v)
		if y == 0.0:
			_warn_zero(ctx, op, what)
			return 0.0
		if op == "div":
			return x / y
		return fposmod(x, y) if rounds_down else fmod(x, y)
	var a := int(current)
	var b := int(v)
	if b == 0:
		_warn_zero(ctx, op, what)
		return 0
	@warning_ignore("integer_division")
	var q := a / b
	var m := a % b
	# GDScript cuts towards zero; rounding down differs only when the signs differ and the
	# division is not exact.
	if rounds_down and m != 0 and ((m < 0) != (b < 0)):
		q -= 1
		m += b
	return q if op == "div" else m


func _rounds_down(ctx: RPGContext) -> bool:
	var rules: Variant = ctx.rpg.rules if ctx.rpg != null else null
	return rules != null and rules.has_method("variable_division") and rules.variable_division() == "floor"


## RPG Maker rescues a division by zero: the variable becomes 0 and the event goes on. The
## maker still hears about it.
func _warn_zero(ctx: RPGContext, op: String, what: String) -> void:
	var where := RPGInterpreter.describe_where(ctx.interpreter.where()) if ctx.interpreter != null else ""
	ctx.state.warn("Control Variable: '%s' was %s zero; it is set to 0%s." % [
		what, "divided by" if op == "div" else "taken modulo", (" (" + where + ")") if where != "" else ""])


## The "Self variable" target: one named value that belongs to an event (any map's, blank map and
## event = this event). Same operations and value kinds as global variables.
func _run_self(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var name := str(args.get("name", ""))
	if name == "":
		return RPGResult.error("Control Variable: name the self variable (e.g. times_opened).")
	var ev := str(args.get("event", ""))
	if ev == "" or ev == "this":
		ev = ctx.event_id()
	if ev == "":
		return RPGResult.error("Control Variable: self variables belong to an event, and this runs outside one.")
	var map_id := str(args.get("map", ""))
	if map_id == "" or map_id == "this":
		map_id = ctx.map_id()
	var rv: Array = _resolve_value(ctx, args.get("value", 0))
	if not rv[0]:
		return RPGResult.error(str(rv[1]))
	var v: Variant = rv[1]
	var t := ctx.state.self_variable_type(map_id, ev, name)
	var ao: Array = _apply_op(ctx, str(args.get("operation", "set")), t, ctx.state.get_self_variable(map_id, ev, name), v, name)
	if not ao[0]:
		return RPGResult.error(str(ao[1]))
	if not ctx.state.set_self_variable(map_id, ev, name, ao[1]):
		return RPGResult.error("Could not set self variable '%s' (it is %s; the value does not fit)." % [name, t])
	return RPGResult.ok()
