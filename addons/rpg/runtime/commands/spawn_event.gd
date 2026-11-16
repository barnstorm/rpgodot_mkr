@tool
extends RPGCommand
## Spawns a copy of a template event on the current map (#66): a dropped item, a summoned
## monster, a projectile — without pre-placing dozens of hidden events. The copy behaves like a
## placed event (pages, triggers, self switches) and rides through map changes and saves.


static func descriptor() -> Dictionary:
	return {
		"type": "spawn_event", "schema_version": 1, "category": "flow", "label": "Spawn Event",
		"fields": [
			{"key": "template", "kind": "text", "default": "", "label": "Template event", "help": "the event to copy, by its ID", "required": true},
			{"key": "map", "kind": "ref", "ref": "map", "label": "Template map (blank = this map)"},
			{"key": "position", "kind": "operand_pair", "default": [0, 0], "label": "Cell [x, y]"},
			{"key": "into_variable", "kind": "ref", "ref": "variable", "label": "Store its ID in (optional)", "help": "a text variable; Despawn Event can read it back"},
		],
	}


func summary(args: Dictionary) -> String:
	var src := str(args.get("template", "?"))
	var m := str(args.get("map", ""))
	var p: Array = args.get("position", [0, 0])
	var out := "Spawn Event: %s at (%s, %s)" % [src if m == "" else "%s from %s" % [src, m], RPGCommand.describe_operand(p[0]), RPGCommand.describe_operand(p[1])]
	if str(args.get("into_variable", "")) != "":
		out += " into [%s]" % args.get("into_variable")
	return out


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var template_id := str(args.get("template", ""))
	if template_id == "":
		return ctx.error("Spawn Event: no template event given.")
	var m := ctx.map
	if m == null:
		return ctx.error("Spawn Event: no map is running.")
	var src_map := str(args.get("map", ""))
	if src_map != "" and not ctx.data.maps.has(src_map):
		return ctx.error("Spawn Event: template map '%s' does not exist." % src_map)
	var template := {}
	for ev in ctx.data.map_events(src_map if src_map != "" else m.map_id):
		if ev is Dictionary and str(ev.get("id", "")) == template_id:
			template = ev
			break
	if template.is_empty():
		return ctx.error("Spawn Event: template event '%s' not found." % template_id)
	var p: Array = args.get("position", [0, 0])
	var cell := Vector2i(int(ctx.operand(p[0])), int(ctx.operand(p[1])))
	if not m.movement.in_bounds(cell):
		return ctx.error("Spawn Event: %s is outside the map." % cell)
	# An event ID is text, so only a text variable can hold it (checked before anything spawns).
	var into := str(args.get("into_variable", ""))
	if into != "" and ctx.state.variable_type(into) != "string":
		return ctx.error("Spawn Event: variable '%s' is not a text variable." % into)
	var ev: RPGEvent = m.spawn_event(template, cell)
	if into != "":
		ctx.state.set_variable(into, ev.event_id)
	return RPGResult.ok()
