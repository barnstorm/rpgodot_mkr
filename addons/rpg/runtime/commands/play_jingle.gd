@tool
extends RPGCommand
## RPG Maker's music effect (ME): a short jingle that pauses the BGM and resumes it afterwards.


static func descriptor() -> Dictionary:
	return {
		"type": "play_jingle", "schema_version": 1, "category": "audio", "label": "Play ME",
		"fields": [
			# A jingle is a Music file; a sound effect file is played too (starter packs keep
			# "inn_rest" with the sound effects, and the sound roles name sound effects).
			{"key": "sound", "kind": "sound", "res": "music", "res_also": ["sound"], "default":{"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Jingle"},
			{"key": "wait", "kind": "bool", "default": false, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	var s: Variant = args.get("sound")
	if s is Dictionary and s.has("role"):
		return "Play ME: (%s)" % s.role
	return "Play ME: %s" % (s.get("file", "") if s is Dictionary else str(s))


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var done: Signal = ctx.audio.play_me(args.get("sound"))
	if args.get("wait", false):
		var r := await ctx.wait_signal(done)
		return RPGResult.ok() if r.ok else RPGResult.cancelled()
	return RPGResult.ok()
