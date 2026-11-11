@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "flash_screen", "schema_version": 1, "category": "screen", "label": "Flash Screen",
		"fields": [
			{"key": "color", "kind": "color", "default": [255, 255, 255, 170], "label": "Colour (r, g, b, strength)"},
			{"key": "seconds", "kind": "float", "default": 0.5, "min": 0.0, "max": 10.0, "label": "Seconds"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Flash Screen: %s, %s s" % [str(args.color), args.seconds]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var c: Array = args.get("color", [255, 255, 255, 170])
	var col := Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3]) if c.size() > 3 else 170)
	var done: Signal = ctx.screen.flash(col, float(args.seconds))
	if args.wait:
		var r := await ctx.wait_signal(done)
		return RPGResult.ok() if r.ok else RPGResult.cancelled()
	return RPGResult.ok()
