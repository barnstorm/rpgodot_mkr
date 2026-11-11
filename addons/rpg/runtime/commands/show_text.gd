@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "show_text", "schema_version": 1, "category": "message", "label": "Show Text",
		"fields": [
			{"key": "face", "kind": "resource", "res": "faceset", "label": "Face", "default": null},
			{"key": "name", "kind": "text", "label": "Speaker name", "default": ""},
			{"key": "text", "kind": "multiline", "label": "Text", "default": "", "required": true, "help": "Codes: \\V[id] variable, \\N[actor] name, \\G currency, \\C[n] colour, \\. and \\| wait"},
			{"key": "position", "kind": "choice", "options": ["bottom", "middle", "top"], "default": "bottom", "label": "Position"},
			{"key": "background", "kind": "choice", "options": ["window", "dim", "transparent"], "default": "window", "label": "Background"},
			{"key": "gold_window", "kind": "bool", "default": false, "label": "Show gold window"},
		],
	}


func summary(args: Dictionary) -> String:
	var t: String = str(args.get("text", "")).replace("\n", " / ")
	var who: String = str(args.get("name", ""))
	return "Text: %s%s" % [(who + ": ") if who != "" else "", t]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var box: Control = ctx.ui.message_box
	box.open_text(args)
	var r := await ctx.wait_signal(box.closed)
	if not r.ok:
		box.force_close()
		return RPGResult.cancelled()
	var nxt: Dictionary = ctx.interpreter.peek_next()
	if not ["show_text", "show_choices", "input_number"].has(nxt.get("type", "")):
		box.hide_box()
	return RPGResult.ok()
