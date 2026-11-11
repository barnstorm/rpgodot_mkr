@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "set_switch", "schema_version": 1, "category": "state", "label": "Control Switch",
		"fields": [
			{"key": "id", "kind": "ref", "ref": "switch", "label": "Switch", "required": true},
			{"key": "value", "kind": "choice", "options": ["on", "off", "toggle"], "default": "on", "label": "Set to"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Switch [%s] = %s" % [args.get("id", "?"), str(args.get("value", "on")).to_upper()]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id: String = str(args.get("id", ""))
	var v: Variant = args.get("value", "on")
	var on: bool
	if typeof(v) == TYPE_BOOL:
		on = v
	elif v == "toggle":
		on = not ctx.state.get_switch(id)
	else:
		on = v == "on"
	if not ctx.state.set_switch(id, on):
		return RPGResult.error("Switch '%s' is not defined in state.json." % id)
	return RPGResult.ok()
