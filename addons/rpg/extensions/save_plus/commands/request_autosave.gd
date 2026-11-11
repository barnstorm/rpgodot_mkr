@tool
extends RPGCommand
## Request autosave (save_plus): saves to the Auto slot as soon as the running event has finished
## (a safe point), unless autosave is turned off.


static func descriptor() -> Dictionary:
	return {"type": "request_autosave", "schema_version": 1, "category": "scenes", "label": "Request autosave", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Request autosave"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	var sp: Object = ctx.rpg.extension("save_plus")
	if sp == null:
		return RPGResult.error("Request autosave: the Save & autosave plus plugin is not running.")
	sp.request("event")
	return RPGResult.ok()
