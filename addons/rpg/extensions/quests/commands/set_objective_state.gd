@tool
extends RPGCommand
## Set objective state (quests plugin): shows a hidden objective, or marks one completed or
## failed (or open again).

const LABELS := {"hidden": "hidden", "shown": "shown", "completed": "completed", "failed": "failed"}


static func descriptor() -> Dictionary:
	return {
		"type": "set_objective_state", "schema_version": 1, "category": "quests", "label": "Set objective state",
		"fields": [
			{"key": "quest", "kind": "ref", "ref": "quest", "label": "Quest", "required": true},
			{"key": "objective", "kind": "text", "default": "", "label": "Objective ID", "required": true, "help": "The objective's ID in the quest's Objectives list."},
			{"key": "state", "kind": "choice", "options": ["completed", "failed", "shown", "hidden"], "option_labels": ["Completed", "Failed", "Shown (open)", "Hidden"], "default": "completed", "label": "State"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Objective %s/%s: %s" % [args.get("quest", "?"), args.get("objective", "?"), LABELS.get(str(args.get("state", "completed")), str(args.get("state", "")))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var q: Object = ctx.rpg.extension("quests")
	if q == null:
		return RPGResult.error("Set objective state: the Quest journal plugin is not running.")
	var id := str(args.get("quest", ""))
	var oid := str(args.get("objective", "")).strip_edges()
	if q.quest(id).is_empty():
		return RPGResult.error("Set objective state: there is no quest '%s' in the Database." % id)
	if not q.set_objective_state(id, oid, str(args.get("state", "completed"))):
		return RPGResult.error("Set objective state: quest '%s' has no objective '%s'." % [id, oid])
	return RPGResult.ok()
