@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "fade_out", "schema_version": 1, "category": "screen", "label": "Fade Out Screen",
		"fields": [
			{"key": "seconds", "kind": "float", "default": 0.5, "min": 0.0, "max": 10.0, "label": "Seconds"},
			{"key": "color", "kind": "choice", "options": ["black", "white"], "default": "black", "label": "Colour"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Fade Out (%s s)" % args.get("seconds", 0.5)


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.screen.set_meta("hold_fade", true)
	var r := await ctx.wait_signal(ctx.screen.fade_out(float(args.seconds), Color.WHITE if args.color == "white" else Color.BLACK))
	return RPGResult.ok() if r.ok else RPGResult.cancelled()
