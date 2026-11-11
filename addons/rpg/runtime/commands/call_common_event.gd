@tool
extends RPGCommand
## Runs a common event inside the caller's interpreter, then continues. Recursion is allowed up
## to the interpreter's depth limit.


static func descriptor() -> Dictionary:
	return {
		"type": "call_common_event", "schema_version": 1, "category": "flow", "label": "Call Common Event",
		"fields": [{"key": "id", "kind": "ref", "ref": "common_event", "label": "Common event", "required": true}],
	}


func summary(args: Dictionary) -> String:
	return "Common Event: %s" % args.get("id", "?")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var ce: Dictionary = ctx.data.common_events.get(str(args.get("id", "")), {})
	if ce.is_empty():
		return RPGResult.error("Common event '%s' does not exist." % args.get("id", ""))
	var r: RPGResult = await ctx.run_list(ce.get("commands", []), "common:" + str(args.id))
	if r.flow == "exit":
		# Exit Event inside a common event ends only the common event.
		return RPGResult.ok()
	if r.flow.begins_with("jump:"):
		return RPGResult.error("Jump to Label: there is no label '%s' in common event '%s'." % [r.flow.substr(5), args.id])
	return r
