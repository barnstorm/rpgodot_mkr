@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "set_weather", "schema_version": 1, "category": "screen", "label": "Set Weather Effects",
		"fields": [
			{"key": "weather", "kind": "choice", "options": ["none", "rain", "snow"], "default": "none", "label": "Weather"},
			{"key": "power", "kind": "int", "default": 5, "min": 1, "max": 9, "label": "Power"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Weather: %s" % args.get("weather", "none")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.screen.set_weather(str(args.weather), int(args.power))
	return RPGResult.ok()
