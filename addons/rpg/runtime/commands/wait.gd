@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "wait", "schema_version": 1, "category": "flow", "label": "Wait",
		"fields": [{"key": "seconds", "kind": "float", "default": 1.0, "min": 0.0, "max": 999.0, "label": "Seconds"}],
	}


func summary(args: Dictionary) -> String:
	return "Wait: %s s" % args.get("seconds", 1.0)


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	if not await ctx.wait_seconds(float(args.get("seconds", 1.0))):
		return RPGResult.cancelled()
	return RPGResult.ok()
