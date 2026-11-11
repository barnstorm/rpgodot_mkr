@tool
extends RPGCommand
## Set darkness (lighting plugin): makes the current map dark (colour and strength), lights it
## up, or gives it back the darkness its Map properties set. Kept for that map (saved).


static func descriptor() -> Dictionary:
	return {
		"type": "set_darkness", "schema_version": 1, "category": "lighting", "label": "Set darkness",
		"fields": [
			{"key": "mode", "kind": "choice", "options": ["dark", "off", "map"], "option_labels": ["Dark", "Not dark", "As in Map properties"], "default": "dark", "label": "This map is"},
			{"key": "colour", "kind": "color", "default": [8, 8, 24, 255], "label": "Colour", "show_if": {"key": "mode", "equals": "dark"}},
			{"key": "strength", "kind": "int", "default": 85, "min": 0, "max": 100, "label": "Strength (%)", "show_if": {"key": "mode", "equals": "dark"}},
		],
	}


func summary(args: Dictionary) -> String:
	match str(args.get("mode", "dark")):
		"off": return "Darkness: off on this map"
		"map": return "Darkness: as in Map properties"
	return "Darkness: %d%%" % int(args.get("strength", 85))


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var l: Object = ctx.rpg.extension("lighting")
	if l == null:
		return RPGResult.error("Set darkness: the Lighting plugin is not running.")
	var map_id := ctx.map_id()
	if map_id == "":
		return RPGResult.error("Set darkness: there is no map.")
	l.set_darkness(map_id, str(args.get("mode", "dark")), args.get("colour"), int(args.get("strength", 85)))
	l.update_lighting()
	return RPGResult.ok()
