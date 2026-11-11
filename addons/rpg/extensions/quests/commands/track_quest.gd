@tool
extends RPGCommand
## Track quest (quests plugin): the map tracker follows this quest (empty: no quest).


static func descriptor() -> Dictionary:
	return {
		"type": "track_quest", "schema_version": 1, "category": "quests", "label": "Track quest",
		"fields": [
			{"key": "quest", "kind": "ref", "ref": "quest", "label": "Quest (empty: none)", "default": ""},
		],
	}


func summary(args: Dictionary) -> String:
	var id := str(args.get("quest", ""))
	return "Track quest: %s" % (id if id != "" else "none")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var q: Object = ctx.rpg.extension("quests")
	if q == null:
		return RPGResult.error("Track quest: the Quest journal plugin is not running.")
	var id := str(args.get("quest", ""))
	if not q.track(id):
		return RPGResult.error("Track quest: there is no quest '%s' in the Database." % id)
	return RPGResult.ok()
