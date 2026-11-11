@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "move_picture", "schema_version": 1, "category": "pictures", "label": "Move Picture",
		"fields": [
			{"key": "number", "kind": "int", "default": 1, "min": 1, "max": 50, "label": "Number"},
			{"key": "x", "kind": "operand", "default": 160, "label": "X (pixels)"},
			{"key": "y", "kind": "operand", "default": 120, "label": "Y (pixels)"},
			{"key": "scale", "kind": "float", "default": 100.0, "min": 1.0, "max": 2000.0, "label": "Scale %"},
			{"key": "opacity", "kind": "int", "default": 255, "min": 0, "max": 255, "label": "Opacity"},
			{"key": "seconds", "kind": "float", "default": 1.0, "min": 0.0, "max": 60.0, "label": "Seconds"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Move Picture #%d to (%s, %s), %s s" % [int(args.number), RPGCommand.describe_operand(args.x), RPGCommand.describe_operand(args.y), args.seconds]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var done: Signal = ctx.screen.move_picture(int(args.number), Vector2(float(ctx.operand(args.x)), float(ctx.operand(args.y))), float(args.scale), int(args.opacity), float(args.seconds))
	if args.wait:
		var r := await ctx.wait_signal(done)
		return RPGResult.ok() if r.ok else RPGResult.cancelled()
	return RPGResult.ok()
