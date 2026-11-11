@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "show_balloon", "schema_version": 1, "category": "message", "label": "Show Balloon Icon",
		"fields": [
			{"key": "target", "kind": "text", "default": "this", "label": "Character", "help": "player, this, or an event ID"},
			{"key": "balloon", "kind": "choice", "options": ["exclamation", "question", "music", "heart", "anger", "sweat", "frustration", "silence", "light_bulb", "zzz"], "default": "exclamation", "label": "Balloon"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Balloon: %s, %s" % [args.get("target", "this"), args.get("balloon", "")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var ch: Node = ctx.character(args.target)
	if ch == null:
		return RPGResult.error("Show Balloon: character '%s' not found on this map." % args.target)
	var done: Signal = ctx.ui.balloon(ch, args.balloon)
	if args.wait:
		var r := await ctx.wait_signal(done)
		if not r.ok:
			return RPGResult.cancelled()
	return RPGResult.ok()
