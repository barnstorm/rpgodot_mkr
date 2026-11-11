@tool
extends RPGCommand
## RPG Maker VX Ace's "Change Tileset": the current map is drawn with another tileset (painted
## cells keep their tile positions, so use a tileset with the same layout). Saved per map, so it
## lasts through transfers and loads.


static func descriptor() -> Dictionary:
	return {
		"type": "change_tileset", "schema_version": 1, "category": "screen", "label": "Change Tileset",
		"fields": [{"key": "tileset", "kind": "ref", "ref": "tileset", "label": "Tileset", "required": true}],
	}


func summary(args: Dictionary) -> String:
	return "Change Tileset: %s" % args.get("tileset", "?")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var ts := str(args.get("tileset", ""))
	if not ctx.data.has_record("tilesets", ts):
		return RPGResult.error("Change Tileset: tileset '%s' does not exist." % ts)
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Change Tileset: no map is loaded.")
	if m.has_method("change_tileset") and not m.change_tileset(ts):
		return RPGResult.error("Change Tileset: tileset '%s' could not be built." % ts)
	ctx.state.set_map_override(str(m.map_id), "tileset", ts)
	return RPGResult.ok()
