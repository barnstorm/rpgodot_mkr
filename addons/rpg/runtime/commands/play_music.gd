@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "play_music", "schema_version": 1, "category": "audio", "label": "Play BGM",
		"fields": [{"key": "sound", "kind": "sound", "res": "music", "default": {"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Music"}],
	}


func summary(args: Dictionary) -> String:
	var s: Variant = args.get("sound")
	return "Play BGM: %s" % (s.get("file", s.get("role", "(none)")) if s is Dictionary else str(s))


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.audio.play_bgm(args.get("sound"))
	return RPGResult.ok()
