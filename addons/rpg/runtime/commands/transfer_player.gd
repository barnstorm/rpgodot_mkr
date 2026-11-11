@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "transfer_player", "schema_version": 1, "category": "movement", "label": "Transfer Player",
		"fields": [
			{"key": "to", "kind": "location", "label": "Destination", "required": true},
			{"key": "facing", "kind": "facing", "default": "keep", "label": "Facing"},
			{"key": "fade", "kind": "choice", "options": ["black", "white", "none"], "default": "black", "label": "Fade"},
			{"key": "fallback_distance", "kind": "int", "default": 0, "min": 0, "max": 10, "label": "If occupied, use the nearest free cell within"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Transfer Player: %s%s" % [RPGCommand.describe_location(args.get("to")), (", face " + str(args.facing)) if str(args.get("facing", "keep")) != "keep" else ""]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var to: Variant = args.get("to")
	if not (to is Dictionary) or not to.has("map") or not (to.get("position") is Array):
		return RPGResult.error("Transfer Player: destination must be {map, position}.")
	if ctx.rpg.game == null:
		return RPGResult.error("Transfer Player: no game is running.")
	var pos: Array = to.position
	var r: RPGResult = await ctx.rpg.game.transfer(str(to.map), Vector2i(int(pos[0]), int(pos[1])), str(args.get("facing", "keep")), str(args.get("fade", "black")), int(args.get("fallback_distance", 0)), ctx.interpreter)
	return r
