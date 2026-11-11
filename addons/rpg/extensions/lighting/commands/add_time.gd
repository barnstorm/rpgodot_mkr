@tool
extends RPGCommand
## Advance time (lighting plugin): moves the game clock on (or back, with negative numbers), for
## example after a night at the inn.


static func descriptor() -> Dictionary:
	return {
		"type": "add_time", "schema_version": 1, "category": "lighting", "label": "Advance time",
		"fields": [
			{"key": "hours", "kind": "int", "default": 1, "min": -999, "max": 999, "label": "Hours"},
			{"key": "minutes", "kind": "int", "default": 0, "min": -59, "max": 59, "label": "Minutes"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Advance time: %+d h %+d min" % [int(args.get("hours", 1)), int(args.get("minutes", 0))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var l: Object = ctx.rpg.extension("lighting")
	if l == null:
		return RPGResult.error("Advance time: the Lighting plugin is not running.")
	l.add_minutes(int(args.get("hours", 1)) * 60.0 + int(args.get("minutes", 0)))
	return RPGResult.ok()
