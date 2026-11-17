@tool
extends RPGCommand
## Turns switches ON, OFF or flips them: one, a range of them, or the one whose id another
## variable holds. A range spans the project's declared switches between its two ends in
## declaration order (state.json), in either direction, and is written all at once: if any
## switch in it is not declared, nothing is written.


static func descriptor() -> Dictionary:
	return {
		"type": "set_switch", "schema_version": 1, "category": "state", "label": "Control Switch",
		"fields": [
			{"key": "target", "kind": "choice", "options": ["single", "range", "pointer"], "option_labels": ["One switch", "Range", "Indirect"], "default": "single", "label": "Target"},
			{"key": "id", "kind": "ref", "ref": "switch", "label": "Switch", "required": true, "show_if": {"key": "target", "equals": "single"}},
			{"key": "from", "kind": "ref", "ref": "switch", "label": "From", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "to", "kind": "ref", "ref": "switch", "label": "To", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "pointer", "kind": "ref", "ref": "variable", "label": "Holds the target's id", "required": true, "show_if": {"key": "target", "equals": "pointer"}},
			{"key": "value", "kind": "choice", "options": ["on", "off", "toggle"], "default": "on", "label": "Set to"},
		],
	}


func summary(args: Dictionary) -> String:
	var mode := str(args.get("target", "single"))
	var name := "[%s]" % args.get("id", "?")
	if mode == "range":
		name = "%s..%s" % [args.get("from", "?"), args.get("to", "?")]
	elif mode == "pointer":
		name = "[%s]" % args.get("pointer", "?")
	return "Switch %s = %s" % [name, str(args.get("value", "on")).to_upper()]


## The command's target ids. A range spans the declared switches between "from" and "to" in
## declaration order (state.json), in either direction. Empty when the ids do not name switches.
func _target_ids(ctx: RPGContext, args: Dictionary, mode: String) -> Array:
	if mode == "range":
		var order: Array = ctx.data.switches.keys() if ctx.data != null else []
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
				return "Control Switch: choose the range's start and end switches."
			return "Control Switch: '%s' and '%s' are not both declared switches." % [args.get("from", ""), args.get("to", "")]
		"pointer":
			var pid := str(args.get("pointer", ""))
			if pid == "":
				return "Control Switch: choose the variable that holds the target's id."
			var pointed := str(ctx.state.get_variable(pid))
			if pointed == "":
				return "Control Switch: variable '%s' does not hold a switch id (it is empty)." % pid
			return "Control Switch: '%s' is not a declared switch." % pointed
	return "Control Switch: choose a switch."


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
	# Pass one checks every switch is declared; pass two writes, so a range never ends up
	# half-flipped when one of its switches refuses.
	for id in ids:
		if ctx.data != null and not ctx.data.switches.is_empty() and not ctx.data.switches.has(str(id)):
			return RPGResult.error("Switch '%s' is not defined in state.json." % id)
	var v: Variant = args.get("value", "on")
	for id in ids:
		var sid := str(id)
		var on := false
		if typeof(v) == TYPE_BOOL:
			on = v
		elif v == "toggle":
			on = not ctx.state.get_switch(sid)
		else:
			on = v == "on"
		if not ctx.state.set_switch(sid, on):
			return RPGResult.error("Switch '%s' is not defined in state.json." % sid)
	return RPGResult.ok()
