@tool
extends RPGCommand
## Turns one event's self switch ON or OFF, or clears a map's per-event state: "Reset one event"
## erases that event's self switches and self variables, "Reset whole map" every event's. The
## event can be on any map (blank map = the current one); blank event = this event.


static func descriptor() -> Dictionary:
	return {
		"type": "set_self_switch", "schema_version": 1, "category": "state", "label": "Control Self Switch",
		"fields": [
			{"key": "mode", "kind": "choice", "options": ["set", "reset_event", "reset_map"], "option_labels": ["Set", "Reset one event", "Reset whole map"], "default": "set", "label": "Action"},
			{"key": "switch", "kind": "choice", "options": ["A", "B", "C", "D"], "default": "A", "label": "Self switch", "show_if": {"key": "mode", "equals": "set"}},
			{"key": "value", "kind": "bool", "default": true, "label": "ON", "show_if": {"key": "mode", "equals": "set"}},
			{"key": "event", "kind": "text", "default": "", "label": "Event (blank = this event)", "show_if": {"key": "mode", "equals": ["set", "reset_event"]}},
			{"key": "map", "kind": "ref", "ref": "map", "label": "Map (blank = this map)", "show_if": {"key": "mode", "equals": ["set", "reset_event", "reset_map"]}},
		],
	}


func summary(args: Dictionary) -> String:
	var mode := str(args.get("mode", "set"))
	var ev: String = str(args.get("event", ""))
	var mp: String = str(args.get("map", ""))
	if mode == "reset_map":
		return "Reset self state: all of %s" % (mp if mp != "" else "this map")
	var where := ev if ev != "" else "this event"
	if mp != "":
		where = "%s on %s" % [where, mp]
	if mode == "reset_event":
		return "Reset self state: %s" % where
	return "Self Switch %s of %s = %s" % [args.get("switch", "A"), where, "ON" if args.get("value", true) else "OFF"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var mode := str(args.get("mode", "set"))
	var map_id: String = str(args.get("map", ""))
	if map_id == "" or map_id == "this":
		map_id = ctx.map_id()
	if map_id == "":
		return RPGResult.error("Control Self Switch needs a map (there is none here).")
	var ev_id: String = str(args.get("event", ""))
	if mode != "reset_map":
		if ev_id == "" or ev_id == "this":
			ev_id = ctx.event_id()
		if ev_id == "":
			return RPGResult.error("Control Self Switch needs an event (common events have no self switches).")
	if mode != "set":
		ctx.state.reset_self_state(map_id, "" if mode == "reset_map" else ev_id)
		return RPGResult.ok()
	var letter: String = str(args.get("switch", "A"))
	var v: Variant = args.get("value", true)
	if not ctx.state.set_self_switch(map_id, ev_id, letter, bool(v) if typeof(v) == TYPE_BOOL else v == "on"):
		return RPGResult.error("Self switch must be A, B, C or D.")
	return RPGResult.ok()
