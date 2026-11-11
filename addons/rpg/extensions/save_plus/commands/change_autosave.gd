@tool
extends RPGCommand
## Change autosave (save_plus): turns autosaving on or off for the rest of the game (saved), for
## example during a story scene that must not be saved halfway.


static func descriptor() -> Dictionary:
	return {
		"type": "change_autosave", "schema_version": 1, "category": "scenes", "label": "Change autosave",
		"fields": [{"key": "enabled", "kind": "bool", "default": true, "label": "Autosave on"}],
	}


func summary(args: Dictionary) -> String:
	return "Autosave: %s" % ("on" if bool(args.get("enabled", true)) else "off")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var sp: Object = ctx.rpg.extension("save_plus")
	if sp == null:
		return RPGResult.error("Change autosave: the Save & autosave plus plugin is not running.")
	sp.set_disabled(not bool(args.get("enabled", true)))
	return RPGResult.ok()
