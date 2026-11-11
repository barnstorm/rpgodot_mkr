@tool
extends RPGCommand
## Set save description (save_plus): a line the save screen shows for every save made after this
## (in place of the map name), e.g. "Chapter 2: The Mines". Empty text removes it.


static func descriptor() -> Dictionary:
	return {
		"type": "set_save_description", "schema_version": 1, "category": "scenes", "label": "Set save description",
		"fields": [{"key": "text", "kind": "text", "label": "Description", "default": "", "help": "Codes: \\V[id] \\N[actor]. Empty: the map name again."}],
	}


func summary(args: Dictionary) -> String:
	return "Save description: %s" % (str(args.get("text", "")) if str(args.get("text", "")) != "" else "(map name)")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var sp: Object = ctx.rpg.extension("save_plus")
	if sp == null:
		return RPGResult.error("Set save description: the Save & autosave plus plugin is not running.")
	sp.set_description(RPGText.expand_plain(str(args.get("text", "")), ctx.rpg))
	return RPGResult.ok()
