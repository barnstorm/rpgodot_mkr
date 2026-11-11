@tool
extends RPGCommand
## RPG Maker's "Change Transparency": hides the player (and followers) while they still move,
## block and trigger events. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "change_transparency", "schema_version": 1, "category": "movement", "label": "Change Transparency",
		"fields": [
			{"key": "transparent", "kind": "bool", "default": true, "label": "Player is transparent"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Transparency: %s" % ("ON" if args.get("transparent", true) else "OFF")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.state.player_transparent = bool(args.get("transparent", true))
	if ctx.rpg.game != null and ctx.rpg.game.has_method("apply_transparency"):
		ctx.rpg.game.apply_transparency()
	return RPGResult.ok()
