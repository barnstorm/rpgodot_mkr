@tool
extends RPGCommand
## RPG Maker's "Change Battle Background" for the current map (used by Battle Processing when it
## names no background). Blank = the map's default. Saved per map.


static func descriptor() -> Dictionary:
	return {
		"type": "change_battle_back", "schema_version": 1, "category": "scenes", "label": "Change Battle Background",
		"fields": [{"key": "background", "kind": "resource", "res": "backdrop", "default": "", "label": "Background (blank = map default)"}],
	}


func summary(args: Dictionary) -> String:
	var bg := str(args.get("background", "")) if args.get("background") != null else ""
	return "Change Battle Background: %s" % (bg if bg != "" else "(map default)")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Change Battle Background: no map is loaded.")
	var bg := str(args.get("background", "")) if args.get("background") != null else ""
	if bg != "" and RPGAssets.find("backdrop", bg) == "":
		return RPGResult.error("Change Battle Background: image '%s' not found." % bg)
	var map_id := str(m.map_id)
	var value: Variant = bg
	if bg == "":
		value = ctx.data.map_props(map_id).get("battle_background", "auto")
		var ov: Dictionary = ctx.state.map_override(map_id)
		ov.erase("battle_background")
	else:
		ctx.state.set_map_override(map_id, "battle_background", bg)
	if "props" in m:
		var props: Dictionary = m.props.duplicate(true)
		props["battle_background"] = value
		m.props = props
	return RPGResult.ok()
