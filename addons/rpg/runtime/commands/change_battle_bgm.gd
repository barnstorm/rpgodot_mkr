@tool
extends RPGCommand
## RPG Maker's "Change Battle BGM": the music for the following battles (instead of the System
## record's). Saved with the game. A blank file means no battle music.


static func descriptor() -> Dictionary:
	return {
		"type": "change_battle_bgm", "schema_version": 1, "category": "audio", "label": "Change Battle BGM",
		"fields": [{"key": "sound", "kind": "sound", "res": "music", "default": {"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Battle music"}],
	}


func summary(args: Dictionary) -> String:
	var s: Variant = args.get("sound")
	return "Change Battle BGM: %s" % (str(s.get("file", "")) if s is Dictionary and str(s.get("file", "")) != "" else "(none)")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	return store(ctx, "battle", args.get("sound"), "Change Battle BGM")


## Shared with Change Victory ME: checks the file and stores it in state.music_overrides[key].
static func store(ctx: RPGContext, key: String, s: Variant, label: String) -> RPGResult:
	var sound := {}
	if s is Dictionary:
		sound = s.duplicate(true)
	elif s is String:
		sound = {"file": s}
	var file := str(sound.get("file", ""))
	if file != "" and RPGAssets.find("music", file) == "":
		return RPGResult.error("%s: music '%s' not found." % [label, file])
	ctx.state.music_overrides[key] = sound
	return RPGResult.ok()
