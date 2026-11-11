@tool
extends RPGCommand
## RPG Maker's "Change Encounter": turns random battles on or off (saved with the game).


static func descriptor() -> Dictionary:
	return {
		"type": "change_encounter", "schema_version": 1, "category": "party", "label": "Change Encounter",
		"fields": [{"key": "enabled", "kind": "bool", "default": false, "label": "Random encounters on"}],
	}


func summary(args: Dictionary) -> String:
	return "Change Encounter: %s" % ("Enable" if args.get("enabled", false) else "Disable")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.state.access["encounters"] = bool(args.get("enabled", false))
	return RPGResult.ok()
