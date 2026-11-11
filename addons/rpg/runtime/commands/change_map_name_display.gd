@tool
extends RPGCommand
## RPG Maker VX Ace's "Change Map Name Display": whether a map's display name is shown when the
## player arrives. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "change_map_name_display", "schema_version": 1, "category": "screen", "label": "Change Map Name Display",
		"fields": [{"key": "show", "kind": "bool", "default": true, "label": "Show map names"}],
	}


func summary(args: Dictionary) -> String:
	return "Change Map Name Display: %s" % ("ON" if args.get("show", true) else "OFF")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.state.map_name_display = bool(args.get("show", true))
	return RPGResult.ok()
