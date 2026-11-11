@tool
extends RPGCommand
## RPG Maker's "Change Victory ME": the jingle played when a battle is won (instead of the System
## record's). Saved with the game. A blank file means no jingle.

const BattleBgm := preload("res://addons/rpg/runtime/commands/change_battle_bgm.gd")


static func descriptor() -> Dictionary:
	return {
		"type": "change_victory_me", "schema_version": 1, "category": "audio", "label": "Change Victory ME",
		"fields": [{"key": "sound", "kind": "sound", "res": "music", "default": {"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Victory jingle"}],
	}


func summary(args: Dictionary) -> String:
	var s: Variant = args.get("sound")
	return "Change Victory ME: %s" % (str(s.get("file", "")) if s is Dictionary and str(s.get("file", "")) != "" else "(none)")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	return BattleBgm.store(ctx, "victory", args.get("sound"), "Change Victory ME")
