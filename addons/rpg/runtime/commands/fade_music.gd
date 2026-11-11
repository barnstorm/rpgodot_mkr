@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "fade_music", "schema_version": 1, "category": "audio", "label": "Fade Out BGM",
		"fields": [{"key": "seconds", "kind": "float", "default": 1.0, "min": 0.0, "max": 60.0, "label": "Seconds"}],
	}


func summary(args: Dictionary) -> String:
	return "Fade Out BGM: %s s" % args.seconds


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.audio.fade_bgm(float(args.seconds))
	return RPGResult.ok()
