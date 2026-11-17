@tool
extends RPGCommand
## Removes an event from the map (#66): a spawned copy goes for good; a placed one is only gone
## until the map is loaded again, like Erase Event but at once. The event the commands belong to
## ("this") is hidden instead of freed, so it finishes running first.


static func descriptor() -> Dictionary:
	return {
		"type": "despawn_event", "schema_version": 1, "category": "flow", "label": "Despawn Event",
		"fields": [
			{"key": "event", "kind": "operand", "default": "this", "label": "Event", "help": "an event ID, 'this', or a variable holding an ID"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Despawn Event: %s" % RPGCommand.describe_operand(args.get("event", "this"))


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var target := str(ctx.operand(args.get("event", "this")))
	if target == "" or target == "this":
		if ctx.event == null or not is_instance_valid(ctx.event):
			return ctx.error("Despawn Event: no running event to remove.")
		target = str(ctx.event.event_id)
	if ctx.map == null or not ctx.map.despawn_event(target):
		return ctx.error("Despawn Event: event '%s' not found." % target)
	return RPGResult.ok()
