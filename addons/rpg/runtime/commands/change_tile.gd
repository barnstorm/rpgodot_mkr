@tool
extends RPGCommand
## Change Tile (issue #15): replaces every tile matching a key on one map layer (RPG Maker
## 2000/2003's Change Tile) or just the tile at X, Y (a kit extension; the coordinates are
## operands, so they can come from variables). The map redraws immediately and passability
## follows the new tile. Like RPG Maker, a change lasts until the map is reloaded (a transfer
## to another map and back resets it); Keep also stores it in the save, so it survives reloads
## and loading. The exact tile picked is painted — autotiles do not re-shape around it.


static func descriptor() -> Dictionary:
	return {
		"type": "change_tile", "schema_version": 1, "category": "screen", "label": "Change Tile",
		"fields": [
			{"key": "layer", "kind": "choice", "options": ["Layer1", "Layer2", "Layer3", "Layer4"],
				"option_labels": ["Layer1 (lower)", "Layer2 (upper)", "Layer3", "Layer4"],
				"default": "Layer1", "label": "Layer"},
			{"key": "mode", "kind": "choice", "options": ["all", "cell"],
				"option_labels": ["Every tile matching a key", "One cell (X, Y)"],
				"default": "all", "label": "Change"},
			{"key": "from", "kind": "tile_key", "required": true, "label": "From tile",
				"show_if": {"key": "mode", "equals": "all"},
				"help": "Every cell of the layer holding this tile key is replaced"},
			{"key": "to", "kind": "tile_key", "required": true, "label": "To tile"},
			{"key": "x", "kind": "operand", "default": 0, "min": 0, "label": "X",
				"show_if": {"key": "mode", "equals": "cell"}},
			{"key": "y", "kind": "operand", "default": 0, "min": 0, "label": "Y",
				"show_if": {"key": "mode", "equals": "cell"}},
			{"key": "keep", "kind": "bool", "default": false, "label": "Keep",
				"help": "Also store the change in the save, so it survives map reloads and loading"},
		],
	}


func summary(args: Dictionary) -> String:
	var layer: String = args.get("layer", "Layer1")
	if str(args.get("mode", "all")) == "cell":
		return "Change Tile: (%s, %s) on %s -> %s" % [args.get("x", 0), args.get("y", 0), layer, args.get("to", "?")]
	return "Change Tile: %s -> %s on %s" % [args.get("from", "?"), args.get("to", "?"), layer]


func validate(args: Dictionary) -> Array:
	var problems := super(args)
	# Tile keys always carry their family (lower_17, water_a, terrain_3, autotile_2); a value
	# without one is almost certainly a typo. The real test runs against the live tileset.
	var fields: Array = desc.get("fields", [])
	for f in fields:
		if not ["from", "to"].has(str(f.get("key", ""))) or not _visible(f, args, fields):
			continue
		var v := str(args.get(str(f.key), ""))
		if v != "" and not v.contains("_"):
			problems.append({"severity": "warning", "field": str(f.key),
				"message": "'%s' does not look like a tile key (lower_17, water_a…)." % v})
	return problems


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Change Tile: no map is loaded.")
	var op := {"layer": str(args.get("layer", "Layer1")), "mode": str(args.get("mode", "all")), "to": str(args.get("to", ""))}
	if op.mode == "cell":
		op["cell"] = [int(ctx.operand(args.get("x", 0))), int(ctx.operand(args.get("y", 0)))]
	else:
		op["from"] = str(args.get("from", ""))
	if not m.has_method("apply_tile_change"):
		return RPGResult.error("Change Tile: this map has no tile layers.")
	var err: String = m.apply_tile_change(op)
	if err != "":
		return RPGResult.error("Change Tile: %s" % err)
	if bool(args.get("keep", false)):
		ctx.state.remember_tile_change(str(m.map_id), op)
	return RPGResult.ok()
