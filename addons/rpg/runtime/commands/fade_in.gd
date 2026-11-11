@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "fade_in", "schema_version": 1, "category": "screen", "label": "Fade In Screen",
		"fields": [{"key": "seconds", "kind": "float", "default": 0.5, "min": 0.0, "max": 10.0, "label": "Seconds"}],
	}


func summary(args: Dictionary) -> String:
	return "Fade In (%s s)" % args.get("seconds", 0.5)


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.screen.set_meta("hold_fade", false)
	var r := await ctx.wait_signal(ctx.screen.fade_in(float(args.seconds)))
	return RPGResult.ok() if r.ok else RPGResult.cancelled()
