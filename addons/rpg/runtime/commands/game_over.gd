@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {"type": "game_over", "schema_version": 1, "category": "scenes", "label": "Game Over", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Game Over"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	if ctx.rpg.game != null:
		ctx.rpg.game.game_over.call_deferred()
	return RPGResult.flow_exit()
