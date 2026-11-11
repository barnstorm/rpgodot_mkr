@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "set_self_switch", "schema_version": 1, "category": "state", "label": "Control Self Switch",
		"fields": [
			{"key": "switch", "kind": "choice", "options": ["A", "B", "C", "D"], "default": "A", "label": "Self switch"},
			{"key": "value", "kind": "bool", "default": true, "label": "ON"},
			{"key": "event", "kind": "text", "default": "", "label": "Event (blank = this event)"},
		],
	}


func summary(args: Dictionary) -> String:
	var ev: String = str(args.get("event", ""))
	return "Self Switch %s%s = %s" % [args.get("switch", "A"), (" of " + ev) if ev != "" else "", "ON" if args.get("value", true) else "OFF"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var letter: String = str(args.get("switch", "A"))
	var ev_id: String = str(args.get("event", ""))
	if ev_id == "" or ev_id == "this":
		ev_id = ctx.event_id()
	if ev_id == "":
		return RPGResult.error("Control Self Switch needs an event (common events have no self switches).")
	var v: Variant = args.get("value", true)
	if not ctx.state.set_self_switch(ctx.map_id(), ev_id, letter, bool(v) if typeof(v) == TYPE_BOOL else v == "on"):
		return RPGResult.error("Self switch must be A, B, C or D.")
	return RPGResult.ok()
