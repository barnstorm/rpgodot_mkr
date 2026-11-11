@tool
extends RPGCommand
## RPG Maker's "Change Parallax Background" for the current map. A blank image removes it.
## Saved per map, so it lasts through transfers and loads.


static func descriptor() -> Dictionary:
	return {
		"type": "change_parallax", "schema_version": 1, "category": "screen", "label": "Change Parallax Background",
		"fields": [
			{"key": "image", "kind": "resource", "res": "panorama", "default": "", "label": "Image (blank = none)"},
			{"key": "loop", "kind": "bool", "default": true, "label": "Loop"},
			{"key": "scroll_x", "kind": "float", "default": 0.5, "min": -4.0, "max": 4.0, "label": "Horizontal scroll (0 = fixed, 1 = with the map)"},
			{"key": "scroll_y", "kind": "float", "default": 0.5, "min": -4.0, "max": 4.0, "label": "Vertical scroll (0 = fixed, 1 = with the map)"},
		],
	}


func summary(args: Dictionary) -> String:
	var img := str(args.get("image", "")) if args.get("image") != null else ""
	return "Change Parallax: %s" % (img if img != "" else "(none)")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Change Parallax: no map is loaded.")
	var img := str(args.get("image", "")) if args.get("image") != null else ""
	var p: Variant = null
	if img != "":
		if RPGAssets.find("panorama", img) == "":
			return RPGResult.error("Change Parallax: image '%s' not found." % img)
		p = {"image": img, "loop": bool(args.get("loop", true)), "scroll_x": float(args.get("scroll_x", 0.5)), "scroll_y": float(args.get("scroll_y", 0.5))}
	ctx.state.set_map_override(str(m.map_id), "parallax", p)
	if m.has_method("set_parallax"):
		m.set_parallax(p)
	return RPGResult.ok()
