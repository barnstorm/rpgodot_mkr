@tool
extends RPGCommand
## Change letter sound (letter_sounds): turns letter sounds on or off for the game, sets the
## sound every later message uses (over actors' own sounds), or the interval. Saved with the
## game; "As set up" goes back to the plugin settings.


static func descriptor() -> Dictionary:
	return {
		"type": "letter_sound_settings", "schema_version": 1, "category": "message", "label": "Change letter sound",
		"fields": [
			{"key": "enabled", "kind": "choice", "options": ["keep", "on", "off"], "option_labels": ["Keep", "On", "Off"], "default": "keep", "label": "Letter sounds"},
			{"key": "sound_mode", "kind": "choice", "options": ["keep", "set", "default"], "option_labels": ["Keep", "Use this sound", "As set up (actors' own)"], "default": "keep", "label": "Sound"},
			{"key": "sound", "kind": "sound", "default": {"file": "", "volume": 60, "pitch": 100, "pan": 0}, "label": "Sound (empty file: built-in blip)", "show_if": {"key": "sound_mode", "equals": "set"}},
			{"key": "interval", "kind": "int", "default": 0, "min": -1, "max": 10, "label": "Every N letters (0 keep, -1 as set up)"},
		],
	}


func summary(args: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(args.get("enabled", "keep")) != "keep":
		parts.append(str(args.enabled))
	match str(args.get("sound_mode", "keep")):
		"set":
			var f := str(args.get("sound", {}).get("file", "")) if args.get("sound") is Dictionary else ""
			parts.append("sound " + (f if f != "" else "blip"))
		"default":
			parts.append("sound as set up")
	if int(args.get("interval", 0)) != 0:
		parts.append("every %d" % int(args.interval))
	return "Letter sound: %s" % (", ".join(parts) if not parts.is_empty() else "no change")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var ls: Object = ctx.rpg.extension("letter_sounds")
	if ls == null:
		return RPGResult.error("Change letter sound: the Letter sounds plugin is not running.")
	ls.change(str(args.get("enabled", "keep")), str(args.get("sound_mode", "keep")), args.get("sound"), int(args.get("interval", 0)))
	return RPGResult.ok()
