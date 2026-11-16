@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "show_text", "schema_version": 1, "category": "message", "label": "Show Text",
		"fields": [
			{"key": "face", "kind": "resource", "res": "faceset", "label": "Face", "default": null},
			{"key": "name", "kind": "text", "label": "Speaker name", "default": ""},
			{"key": "text", "kind": "multiline", "label": "Text", "default": "", "required": true, "help": "Codes: \\V[id] variable, \\N[actor] name, \\G currency, \\E[name] self variable, \\C[n] colour, \\. and \\| wait"},
			{"key": "position", "kind": "choice", "options": ["bottom", "middle", "top"], "default": "bottom", "label": "Position"},
			{"key": "avoid_player", "kind": "choice", "options": ["keep", "on", "off"], "option_labels": ["Keep (System)", "Never cover the player", "Stay put"], "default": "keep", "label": "Don't cover the player", "help": "RM2000/2003's Prevent Hero Hiding: a top or bottom box moves to the other half of the screen when the player stands in its half"},
			{"key": "events_continue", "kind": "choice", "options": ["keep", "on", "off"], "option_labels": ["Keep (System)", "Events keep running", "Events pause"], "default": "keep", "label": "Other events during the message", "help": "RM2000/2003's Allow events to continue: with it off, wandering NPCs stop and parallel events sleep while the pages show"},
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
	# The running event rides along so \E[name] can read this event's self variable.
	var p := args.duplicate()
	p["_event_map"] = ctx.map_id()
	p["_event_id"] = ctx.event_id()
	box.open_text(p)
	var r := await ctx.wait_signal(box.closed)
	if not r.ok:
		box.force_close()
		return RPGResult.cancelled()
	var nxt: Dictionary = ctx.interpreter.peek_next()
	if not ["show_text", "show_choices", "input_number", "select_item"].has(nxt.get("type", "")):
		box.hide_box()
	return RPGResult.ok()
