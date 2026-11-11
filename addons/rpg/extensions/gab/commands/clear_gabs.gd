@tool
extends RPGCommand
## Clear gabs (gab plugin): removes the gab showing and every gab waiting.


static func descriptor() -> Dictionary:
	return {"type": "clear_gabs", "schema_version": 1, "category": "message", "label": "Clear gabs", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Clear gabs"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	var g: Object = ctx.rpg.extension("gab")
	if g == null:
		return RPGResult.error("Clear gabs: the Gab window plugin is not running.")
	g.clear_gabs()
	return RPGResult.ok()
