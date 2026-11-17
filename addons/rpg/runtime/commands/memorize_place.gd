@tool
extends RPGCommand
## RPG Maker 2000/2003's "Memorize Place": store where the player stands now (map id, x, y) in
## three variables, so Transfer Player with those variables can bring them back later (#16).


static func descriptor() -> Dictionary:
	return {
		"type": "memorize_place", "schema_version": 1, "category": "movement", "label": "Memorize Place",
		"fields": [
			{"key": "map_variable", "kind": "ref", "ref": "variable", "label": "Store map in", "required": true},
			{"key": "x_variable", "kind": "ref", "ref": "variable", "label": "Store x in", "required": true},
			{"key": "y_variable", "kind": "ref", "ref": "variable", "label": "Store y in", "required": true},
		],
	}


func summary(args: Dictionary) -> String:
	return "Memorize Place: map [%s], x [%s], y [%s]" % [args.get("map_variable", "?"), args.get("x_variable", "?"), args.get("y_variable", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	if ctx.map == null or ctx.map.player == null:
		return RPGResult.error("Memorize Place: no game is running.")
	for k in ["map_variable", "x_variable", "y_variable"]:
		if str(args.get(k, "")) == "":
			return RPGResult.error("Memorize Place: pick the variables to store the place in.")
	var cell: Vector2i = ctx.map.player.cell
	ctx.state.set_variable(str(args.map_variable), ctx.map_id())
	ctx.state.set_variable(str(args.x_variable), cell.x)
	ctx.state.set_variable(str(args.y_variable), cell.y)
	return RPGResult.ok()
