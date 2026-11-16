@tool
extends RPGCommand
## Sets one switch, every switch between two ids (in state.json's order), or the switch whose id
## a variable holds. On / off / toggle applies to each switch on its own (#55).


static func descriptor() -> Dictionary:
	return {
		"type": "set_switch", "schema_version": 1, "category": "state", "label": "Control Switch",
		"fields": [
			{"key": "target", "kind": "choice", "options": ["one", "range", "pointer"], "option_labels": ["One switch", "Range of switches", "Switch named by a variable"], "default": "one", "label": "Target"},
			{"key": "id", "kind": "ref", "ref": "switch", "label": "Switch", "required": true, "show_if": {"key": "target", "equals": ["one", null]}},
			{"key": "from", "kind": "ref", "ref": "switch", "label": "From", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "to", "kind": "ref", "ref": "switch", "label": "To", "required": true, "show_if": {"key": "target", "equals": "range"}},
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Switch named by variable", "required": true, "show_if": {"key": "target", "equals": "pointer"}},
			{"key": "value", "kind": "choice", "options": ["on", "off", "toggle"], "default": "on", "label": "Set to"},
		],
	}


func summary(args: Dictionary) -> String:
	var v := str(args.get("value", "on")).to_upper()
	match str(args.get("target", "one")):
		"range":
			return "Switches [%s] .. [%s] = %s" % [args.get("from", "?"), args.get("to", "?"), v]
		"pointer":
			return "Switch V[%s] = %s" % [args.get("variable", "?"), v]
	return "Switch [%s] = %s" % [args.get("id", "?"), v]


## The switch ids this command touches: one id, the slice of state.json's order between two ids,
## or the id a variable holds (empty when it holds none).
func _target_ids(ctx: RPGContext, args: Dictionary) -> Array:
	match str(args.get("target", "one")):
		"range":
			var order := ctx.state.switch_order()
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
	var v: Variant = args.get("value", "on")
	var ids := _target_ids(ctx, args)
	if ids.is_empty():
		if str(args.get("target", "one")) == "pointer":
			return RPGResult.error("Variable '%s' holds no switch id." % args.get("variable", "?"))
		return RPGResult.error("No switches between [%s] and [%s]." % [args.get("from", "?"), args.get("to", "?")])
	for id in ids:
		var on: bool
		if typeof(v) == TYPE_BOOL:
			on = v
		elif v == "toggle":
			on = not ctx.state.get_switch(id)
		else:
			on = v == "on"
		if not ctx.state.set_switch(str(id), on):
			return RPGResult.error("Switch '%s' is not defined in state.json." % id)
	# A range still asks for one page refresh: request_refresh collapses the per-switch changes.
	return RPGResult.ok()
