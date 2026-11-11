@tool
extends RPGCommand
## RPG Maker's "Get Location Info": stores what is at a cell of the current map in a variable.
##   terrain_tag  the tile's terrain tag (number)
##   region_id    the region painted there (number, 0 = none)
##   event_id     the ID of the event standing there ("" or 0 when none)
##   tile_key     the tile's key on a layer (text, "" when empty; needs a text variable)
##   tile_id      a number for the tile on a layer: 0 = empty, else
##                source * 10000 + atlas row * 100 + atlas column + 1


static func descriptor() -> Dictionary:
	return {
		"type": "get_location_info", "schema_version": 1, "category": "state", "label": "Get Location Info",
		"fields": [
			{"key": "result", "kind": "ref", "ref": "variable", "label": "Store in", "required": true},
			{"key": "info", "kind": "choice", "options": ["terrain_tag", "region_id", "event_id", "tile_key", "tile_id"], "default": "terrain_tag", "label": "Info"},
			{"key": "layer", "kind": "int", "default": 1, "min": 1, "max": 4, "label": "Layer", "show_if": {"key": "info", "equals": ["tile_key", "tile_id"]}},
			{"key": "x", "kind": "operand", "default": 0, "min": 0, "label": "X"},
			{"key": "y", "kind": "operand", "default": 0, "min": 0, "label": "Y"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Get Location Info: [%s] = %s at (%s, %s)" % [args.get("result", "?"), args.get("info", "?"), RPGCommand.describe_operand(args.x), RPGCommand.describe_operand(args.y)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var var_id := str(args.get("result", ""))
	if not ctx.data.variables.has(var_id):
		return RPGResult.error("Get Location Info: variable '%s' does not exist." % var_id)
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Get Location Info: no map is loaded.")
	var c := Vector2i(int(ctx.operand(args.x)), int(ctx.operand(args.y)))
	if m.movement != null and not m.movement.in_bounds(c):
		return RPGResult.error("Get Location Info: cell %s is outside map '%s'." % [c, m.map_id])
	var is_text := ctx.state.variable_type(var_id) == "string"
	var value: Variant = 0
	match str(args.get("info", "terrain_tag")):
		"terrain_tag":
			value = m.terrain_at(c)
		"region_id":
			value = m.region_at(c)
		"event_id":
			var evs: Array = m.events_at(c)
			var id := str(evs[0].event_id) if not evs.is_empty() else ""
			if is_text:
				value = id
			elif id == "":
				value = 0
			elif id.is_valid_int():
				value = id.to_int()
			else:
				return RPGResult.error("Get Location Info: event IDs are text ('%s'); store them in a text variable." % id)
		"tile_key", "tile_id":
			var layer := clampi(int(args.get("layer", 1)), 1, 4) - 1
			var tl: TileMapLayer = m.tile_layers[layer] if layer < m.tile_layers.size() else null
			var src := tl.get_cell_source_id(c) if tl != null else -1
			if str(args.info) == "tile_id":
				var ac := tl.get_cell_atlas_coords(c) if src >= 0 else Vector2i.ZERO
				value = 0 if src < 0 else src * 10000 + ac.y * 100 + ac.x + 1
			else:
				if not is_text:
					return RPGResult.error("Get Location Info: a tile key is text; store it in a text variable.")
				var td: TileData = tl.get_cell_tile_data(c) if src >= 0 else null
				value = RPGMap._tile_key(tl.tile_set, td) if td != null else ""
	if not ctx.state.set_variable(var_id, value):
		return RPGResult.error("Get Location Info: could not store %s in variable '%s'." % [var_to_str(value), var_id])
	return RPGResult.ok()
