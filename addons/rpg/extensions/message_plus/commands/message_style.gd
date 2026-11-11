@tool
extends RPGCommand
## Change message style (message_plus): word wrap and the name box position for every later
## message. Saved with the game; "As set up" goes back to the plugin settings.


static func descriptor() -> Dictionary:
	return {
		"type": "message_style", "schema_version": 1, "category": "message", "label": "Change message style",
		"fields": [
			{"key": "word_wrap", "kind": "choice", "options": ["keep", "on", "off", "default"], "option_labels": ["Keep", "On", "Off", "As set up"], "default": "keep", "label": "Word wrap"},
			{"key": "name_box", "kind": "choice", "options": ["keep", "left", "center", "right", "default"], "option_labels": ["Keep", "Left", "Centre", "Right", "As set up"], "default": "keep", "label": "Name box"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Message style: word wrap %s, name box %s" % [args.get("word_wrap", "keep"), args.get("name_box", "keep")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var mp: Object = ctx.rpg.extension("message_plus")
	if mp == null:
		return RPGResult.error("Change message style: the Message codes plus plugin is not running.")
	mp.set_style(str(args.get("word_wrap", "keep")), str(args.get("name_box", "keep")))
	return RPGResult.ok()
