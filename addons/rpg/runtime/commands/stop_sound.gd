@tool
extends RPGCommand
## RPG Maker's "Stop SE" (and stopping the background sound or a jingle).


static func descriptor() -> Dictionary:
	return {
		"type": "stop_sound", "schema_version": 1, "category": "audio", "label": "Stop Sound",
		"fields": [{"key": "what", "kind": "choice", "options": ["se", "bgs", "me", "all"], "default": "se", "label": "Stop", "help": "se = sound effects, bgs = background sound, me = jingle, all = all three"}],
	}


func summary(args: Dictionary) -> String:
	return "Stop Sound: %s" % str(args.get("what", "se")).to_upper()


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var a: Node = ctx.audio
	if a == null:
		return RPGResult.ok()
	var what := str(args.get("what", "se"))
	if what == "se" or what == "all":
		for p in a.se_pool:
			p.stop()
	if what == "bgs" or what == "all":
		a.bgs.stop()
		a.current_bgs = {}
	if (what == "me" or what == "all") and a.me.playing:
		a.me.stop()
		# Resume the map music the jingle paused.
		a._on_me_finished()
	return RPGResult.ok()
