@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "shake_screen", "schema_version": 1, "category": "screen", "label": "Shake Screen",
		"fields": [
			{"key": "power", "kind": "int", "default": 5, "min": 1, "max": 9, "label": "Power"},
			{"key": "seconds", "kind": "float", "default": 0.5, "min": 0.0, "max": 10.0, "label": "Seconds"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Shake Screen: power %d, %s s" % [int(args.power), args.seconds]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var done: Signal = ctx.screen.shake(float(args.power), float(args.seconds))
	if args.wait:
		var r := await ctx.wait_signal(done)
		return RPGResult.ok() if r.ok else RPGResult.cancelled()
	return RPGResult.ok()
