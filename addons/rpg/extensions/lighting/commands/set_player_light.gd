@tool
extends RPGCommand
## Set player light (lighting plugin): the light around the player and the flashlight, on or
## off, and the light's radius. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "set_player_light", "schema_version": 1, "category": "lighting", "label": "Set player light",
		"fields": [
			{"key": "light", "kind": "choice", "options": ["keep", "on", "off"], "option_labels": ["Keep", "On", "Off"], "default": "on", "label": "Light around the player"},
			{"key": "radius", "kind": "float", "default": 0.0, "min": 0.0, "max": 30.0, "label": "Radius (tiles, 0 = keep)"},
			{"key": "flashlight", "kind": "choice", "options": ["keep", "on", "off"], "option_labels": ["Keep", "On", "Off"], "default": "keep", "label": "Flashlight"},
		],
	}


func summary(args: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(args.get("light", "on")) != "keep":
		parts.append("light %s" % args.get("light", "on"))
	if float(args.get("radius", 0.0)) > 0.0:
		parts.append("radius %s" % str(args.radius))
	if str(args.get("flashlight", "keep")) != "keep":
		parts.append("flashlight %s" % args.flashlight)
	return "Player light: %s" % (", ".join(parts) if not parts.is_empty() else "no change")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var l: Object = ctx.rpg.extension("lighting")
	if l == null:
		return RPGResult.error("Set player light: the Lighting plugin is not running.")
	var on: Variant = null
	match str(args.get("light", "on")):
		"on": on = true
		"off": on = false
	var fl: Variant = null
	match str(args.get("flashlight", "keep")):
		"on": fl = true
		"off": fl = false
	l.set_player_light(on, float(args.get("radius", 0.0)), fl)
	return RPGResult.ok()
