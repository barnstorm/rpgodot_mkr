@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "erase_picture", "schema_version": 1, "category": "pictures", "label": "Erase Picture",
		"fields": [{"key": "number", "kind": "int", "default": 1, "min": 1, "max": 50, "label": "Number"}],
	}


func summary(args: Dictionary) -> String:
	return "Erase Picture #%d" % int(args.number)


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.screen.erase_picture(int(args.number))
	return RPGResult.ok()
