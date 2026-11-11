@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "set_event_location", "schema_version": 1, "category": "movement", "label": "Set Event Location",
		"fields": [
			{"key": "event", "kind": "text", "default": "this", "label": "Event", "help": "this, or an event ID on this map"},
			{"key": "mode", "kind": "choice", "options": ["position", "swap"], "default": "position", "label": "Mode"},
			{"key": "position", "kind": "operand_pair", "default": [0, 0], "label": "Cell [x, y]", "show_if": {"key": "mode", "equals": "position"}},
			{"key": "swap_with", "kind": "text", "default": "", "label": "Swap with event", "show_if": {"key": "mode", "equals": "swap"}},
			{"key": "facing", "kind": "facing", "default": "keep", "label": "Facing"},
		],
	}


func summary(args: Dictionary) -> String:
	if args.get("mode", "position") == "swap":
		return "Event Location: %s <-> %s" % [args.get("event", "this"), args.get("swap_with", "")]
	var p: Array = args.get("position", [0, 0])
	return "Event Location: %s to (%s, %s)" % [args.get("event", "this"), RPGCommand.describe_operand(p[0]), RPGCommand.describe_operand(p[1])]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var ev: Node = ctx.character(str(args.get("event", "this")))
	if ev == null or not (ev is RPGEvent):
		return RPGResult.error("Set Event Location: event '%s' not found." % args.get("event", "this"))
	if args.get("mode", "position") == "swap":
		var other: Node = ctx.character(str(args.get("swap_with", "")))
		if other == null or not (other is RPGEvent):
			return RPGResult.error("Set Event Location: event '%s' not found." % args.get("swap_with", ""))
		var c: Vector2i = ev.cell
		ev.place(other.cell)
		other.place(c)
		other.set_meta("persist", true)
		other.save_change()
	else:
		var p: Array = args.get("position", [0, 0])
		var cell := Vector2i(int(ctx.operand(p[0])), int(ctx.operand(p[1])))
		if not ctx.map.movement.in_bounds(cell):
			return RPGResult.error("Set Event Location: %s is outside the map." % cell)
		ev.place(cell)
	ev.force_turn(str(args.get("facing", "keep")))
	ev.set_meta("persist", true)
	ev.save_change()
	return RPGResult.ok()
