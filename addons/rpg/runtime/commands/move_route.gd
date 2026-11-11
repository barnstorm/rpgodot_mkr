@tool
extends RPGCommand
## Moves a character along a route. With wait = true the event waits until the route is done.


static func descriptor() -> Dictionary:
	return {
		"type": "move_route", "schema_version": 1, "category": "movement", "label": "Set Move Route",
		"fields": [
			{"key": "target", "kind": "text", "default": "player", "label": "Character", "help": "player, this, or an event ID"},
			{"key": "steps", "kind": "route", "default": [], "label": "Route"},
			{"key": "repeat", "kind": "bool", "default": false, "label": "Repeat"},
			{"key": "skip_if_blocked", "kind": "bool", "default": false, "label": "Skip if blocked"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	var parts := []
	for s in args.get("steps", []):
		for k in s:
			parts.append("%s %s" % [k, s[k]])
	return "Move Route: %s: %s" % [args.get("target", "player"), ", ".join(parts).left(70)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var ch: Node = ctx.character(str(args.get("target", "player")))
	if ch == null:
		return RPGResult.error("Move Route: character '%s' not found on this map." % args.get("target", ""))
	var route := {"steps": args.get("steps", []), "repeat": args.get("repeat", false), "skip_if_blocked": args.get("skip_if_blocked", false)}
	if args.get("wait", true) and not args.get("repeat", false):
		var ok: bool = await ch.run_route(route, ctx.token)
		if ch is RPGEvent:
			ch.set_meta("persist", true)
		return RPGResult.ok() if ok else RPGResult.cancelled()
	# Not waiting: run with its own token so the event can continue.
	var tok := RPGCancelToken.new()
	ch.set_meta("route_token", tok)
	ch.run_route(route, tok)
	return RPGResult.ok()
