@tool
extends RPGCommand
## Hides this event until the map is loaded again (it comes back on the next visit).


static func descriptor() -> Dictionary:
	return {"type": "erase_event", "schema_version": 1, "category": "flow", "label": "Erase Event", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Erase Event"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	if ctx.event != null and ctx.event.has_method("erase_event"):
		ctx.event.erase_event()
	return RPGResult.ok()
