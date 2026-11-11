@tool
extends RPGCommand
## Change battle members (party_formation plugin): how many members fight (1 to 4), or the
## plugin setting again (0). Extra members go to the reserve; saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "formation_size", "schema_version": 1, "category": "party", "label": "Change battle members",
		"fields": [
			{"key": "count", "kind": "int", "default": 4, "min": 0, "max": 4, "label": "Battle members (0 = the plugin setting)"},
		],
	}


func summary(args: Dictionary) -> String:
	var n := int(args.get("count", 4))
	return "Battle members: %s" % (str(n) if n > 0 else "as set up")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var pf: Object = ctx.rpg.extension("party_formation")
	if pf == null:
		return RPGResult.error("Change battle members: the Party formation plugin is not running.")
	pf.set_max_battle(int(args.get("count", 4)))
	return RPGResult.ok()
