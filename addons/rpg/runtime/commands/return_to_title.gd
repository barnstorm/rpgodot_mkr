@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {"type": "return_to_title", "schema_version": 1, "category": "scenes", "label": "Return to Title Screen", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Return to Title Screen"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	if ctx.rpg.game != null:
		ctx.rpg.game.return_to_title.call_deferred()
	return RPGResult.flow_exit()
