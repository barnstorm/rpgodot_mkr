@tool
extends RPGCommand
## Colour tone: red, green, blue in percent (100 = normal, 0..200), plus saturation-like grey.


static func descriptor() -> Dictionary:
	return {
		"type": "tint_screen", "schema_version": 1, "category": "screen", "label": "Tint Screen",
		"fields": [
			{"key": "red", "kind": "int", "default": 100, "min": 0, "max": 200, "label": "Red %"},
			{"key": "green", "kind": "int", "default": 100, "min": 0, "max": 200, "label": "Green %"},
			{"key": "blue", "kind": "int", "default": 100, "min": 0, "max": 200, "label": "Blue %"},
			{"key": "seconds", "kind": "float", "default": 1.0, "min": 0.0, "max": 10.0, "label": "Seconds"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Tint Screen: (%d, %d, %d), %s s" % [args.red, args.green, args.blue, args.seconds]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var c := Color(args.red / 100.0, args.green / 100.0, args.blue / 100.0, 1.0)
	var done: Signal = ctx.screen.tint_screen(c, float(args.seconds))
	if args.wait:
		var r := await ctx.wait_signal(done)
		return RPGResult.ok() if r.ok else RPGResult.cancelled()
	return RPGResult.ok()
