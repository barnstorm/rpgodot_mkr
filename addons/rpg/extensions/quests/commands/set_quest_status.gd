@tool
extends RPGCommand
## Set quest status (quests plugin): starts, completes or fails a quest, or forgets it again
## ("Not started"). A started quest shows its objectives that are not hidden.

const LABELS := {"unknown": "not started", "active": "active", "completed": "completed", "failed": "failed"}


static func descriptor() -> Dictionary:
	return {
		"type": "set_quest_status", "schema_version": 1, "category": "quests", "label": "Set quest status",
		"fields": [
			{"key": "quest", "kind": "ref", "ref": "quest", "label": "Quest", "required": true},
			{"key": "status", "kind": "choice", "options": ["active", "completed", "failed", "unknown"], "option_labels": ["Active (start it)", "Completed", "Failed", "Not started (forget it)"], "default": "active", "label": "Status"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Quest %s: %s" % [args.get("quest", "?"), LABELS.get(str(args.get("status", "active")), str(args.get("status", "")))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var q: Object = ctx.rpg.extension("quests")
	if q == null:
		return RPGResult.error("Set quest status: the Quest journal plugin is not running.")
	var id := str(args.get("quest", ""))
	if q.quest(id).is_empty():
		return RPGResult.error("Set quest status: there is no quest '%s' in the Database." % id)
	if not q.set_status(id, str(args.get("status", "active"))):
		return RPGResult.error("Set quest status: unknown status '%s'." % str(args.get("status", "")))
	return RPGResult.ok()
