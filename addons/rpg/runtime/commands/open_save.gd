@tool
extends RPGCommand
## Version 1 saves only at a safe point, so the save screen opens as soon as this event (the main
## event) has finished, instead of in the middle of it.


static func descriptor() -> Dictionary:
	return {"type": "open_save", "schema_version": 1, "category": "scenes", "label": "Open Save Screen", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Open Save Screen (after this event)"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	ctx.ui.pending_save_screen = true
	return RPGResult.ok()
