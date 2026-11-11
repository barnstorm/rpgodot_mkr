@tool
extends RPGCommand
## Set time of day (lighting plugin): sets the game clock.


static func descriptor() -> Dictionary:
	return {
		"type": "set_time", "schema_version": 1, "category": "lighting", "label": "Set time of day",
		"fields": [
			{"key": "hour", "kind": "int", "default": 8, "min": 0, "max": 23, "label": "Hour"},
			{"key": "minute", "kind": "int", "default": 0, "min": 0, "max": 59, "label": "Minute"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Time: %02d:%02d" % [int(args.get("hour", 8)), int(args.get("minute", 0))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var l: Object = ctx.rpg.extension("lighting")
	if l == null:
		return RPGResult.error("Set time of day: the Lighting plugin is not running.")
	l.set_time(int(args.get("hour", 8)), int(args.get("minute", 0)))
	return RPGResult.ok()
