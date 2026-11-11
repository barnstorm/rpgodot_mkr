@tool
extends RPGCommand
## Wait for gabs (gab plugin): the event waits until every queued gab has faded.


static func descriptor() -> Dictionary:
	return {"type": "wait_for_gabs", "schema_version": 1, "category": "message", "label": "Wait for gabs", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Wait for gabs"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	var g: Object = ctx.rpg.extension("gab")
	if g == null:
		return RPGResult.error("Wait for gabs: the Gab window plugin is not running.")
	if g.is_busy():
		var r := await ctx.wait_signal(g.all_finished)
		if not r.ok:
			return RPGResult.cancelled()
	return RPGResult.ok()
