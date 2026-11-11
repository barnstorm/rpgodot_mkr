@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "show_picture", "schema_version": 1, "category": "pictures", "label": "Show Picture",
		"fields": [
			{"key": "number", "kind": "int", "default": 1, "min": 1, "max": 50, "label": "Number"},
			{"key": "picture", "kind": "resource", "res": "picture", "default": "", "label": "Picture", "required": true},
			{"key": "x", "kind": "operand", "default": 160, "label": "X (pixels)"},
			{"key": "y", "kind": "operand", "default": 120, "label": "Y (pixels)"},
			{"key": "origin", "kind": "choice", "options": ["center", "top_left"], "default": "center", "label": "Origin"},
			{"key": "scale", "kind": "float", "default": 100.0, "min": 1.0, "max": 2000.0, "label": "Scale %"},
			{"key": "opacity", "kind": "int", "default": 255, "min": 0, "max": 255, "label": "Opacity"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Show Picture #%d: %s" % [int(args.number), args.picture]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var tex: Texture2D = ctx.ui.load_texture("picture", str(args.picture))
	if tex == null:
		return RPGResult.error("Show Picture: picture '%s' not found." % args.picture)
	ctx.screen.show_picture(int(args.number), tex, Vector2(float(ctx.operand(args.x)), float(ctx.operand(args.y))), str(args.origin), float(args.scale), int(args.opacity))
	ctx.screen.pictures[int(args.number)].set_meta("picture_name", str(args.picture))
	return RPGResult.ok()
