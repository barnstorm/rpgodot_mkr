@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "play_sound", "schema_version": 1, "category": "audio", "label": "Play SE",
		"fields": [{"key": "sound", "kind": "sound", "res": "sound", "default": {"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Sound"}],
	}


func summary(args: Dictionary) -> String:
	var s: Variant = args.get("sound")
	if s is Dictionary and s.has("role"):
		return "Play SE: (%s)" % s.role
	return "Play SE: %s" % (s.get("file", "") if s is Dictionary else str(s))


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.audio.play_se(args.get("sound"))
	return RPGResult.ok()
