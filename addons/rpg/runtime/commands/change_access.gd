@tool
extends RPGCommand
## RPG Maker's "Change Menu Access" and "Change Save Access" (saved with the game).


static func descriptor() -> Dictionary:
	return {
		"type": "change_access", "schema_version": 1, "category": "scenes", "label": "Change Menu / Save Access",
		"fields": [
			{"key": "what", "kind": "choice", "options": ["menu", "save"], "default": "menu", "label": "Access to"},
			{"key": "enabled", "kind": "bool", "default": false, "label": "Allowed"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change %s Access: %s" % [str(args.get("what", "menu")).capitalize(), "Enable" if args.get("enabled", false) else "Disable"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var what := str(args.get("what", "menu"))
	if not what in ["menu", "save"]:
		return RPGResult.error("Change Access: 'what' must be menu or save.")
	ctx.state.access[what] = bool(args.get("enabled", false))
	return RPGResult.ok()
