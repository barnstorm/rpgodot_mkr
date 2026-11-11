@tool
extends RPGCommand
## Set event light (lighting plugin): lights or puts out an event's light on this map, or gives it
## back the light of its page. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "set_event_light", "schema_version": 1, "category": "lighting", "label": "Set event light",
		"fields": [
			{"key": "event", "kind": "character", "default": "this", "label": "Event"},
			{"key": "mode", "kind": "choice", "options": ["on", "off", "page"], "option_labels": ["On", "Off", "As its page says"], "default": "on", "label": "Light"},
			{"key": "radius", "kind": "float", "default": 3.0, "min": 0.5, "max": 30.0, "label": "Radius (tiles)", "show_if": {"key": "mode", "equals": "on"}},
			{"key": "colour", "kind": "color", "default": [255, 214, 150, 255], "label": "Colour", "show_if": {"key": "mode", "equals": "on"}},
			{"key": "intensity", "kind": "int", "default": 100, "min": 0, "max": 100, "label": "Brightness (%)", "show_if": {"key": "mode", "equals": "on"}},
			{"key": "flicker", "kind": "bool", "default": false, "label": "Flickers", "show_if": {"key": "mode", "equals": "on"}},
		],
	}


func summary(args: Dictionary) -> String:
	return "Event light %s: %s" % [args.get("event", "this"), args.get("mode", "on")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var l: Object = ctx.rpg.extension("lighting")
	if l == null:
		return RPGResult.error("Set event light: the Lighting plugin is not running.")
	var target := str(args.get("event", "this"))
	if target == "" or target == "this":
		target = ctx.event_id()
	if target == "" or target == "player":
		return RPGResult.error("Set event light: choose an event (the player has Set player light).")
	l.set_event_light(ctx.map_id(), target, str(args.get("mode", "on")), {
		"radius": float(args.get("radius", 3.0)), "colour": args.get("colour", [255, 214, 150, 255]),
		"intensity": int(args.get("intensity", 100)), "flicker": bool(args.get("flicker", false))})
	return RPGResult.ok()
