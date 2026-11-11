@tool
extends RPGCommand
## Open quest journal (quests plugin): shows the journal; the event waits until it is closed.


static func descriptor() -> Dictionary:
	return {
		"type": "open_quest_journal", "schema_version": 1, "category": "quests", "label": "Open quest journal",
		"fields": [
			{"key": "tab", "kind": "choice", "options": ["active", "completed", "failed"], "option_labels": ["Active", "Completed", "Failed"], "default": "active", "label": "Tab"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Open quest journal (%s)" % str(args.get("tab", "active"))


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var q: Object = ctx.rpg.extension("quests")
	if q == null:
		return RPGResult.error("Open quest journal: the Quest journal plugin is not running.")
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var r: Dictionary = await ctx.ui.run_contract_scene(q.JOURNAL, {"tab": str(args.get("tab", "active"))}, {"rpg": ctx.rpg}, ctx.token)
	if r.status == "error":
		return RPGResult.error(str(r.value))
	return RPGResult.cancelled() if ctx.is_cancelled() else RPGResult.ok()
