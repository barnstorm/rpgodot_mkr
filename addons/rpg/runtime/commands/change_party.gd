@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_party", "schema_version": 1, "category": "party", "label": "Change Party Member",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "operation", "kind": "choice", "options": ["add", "remove"], "default": "add", "label": "Operation"},
			{"key": "initialize", "kind": "bool", "default": false, "label": "Initialize (reset level and equipment)"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Party: %s %s" % [args.operation, args.get("actor", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	if args.operation == "add":
		if args.get("initialize", false):
			ctx.state.actors.erase(id)
		if not ctx.state.add_actor(id) and not ctx.state.in_party(id):
			return RPGResult.error("Change Party: actor '%s' does not exist." % id)
	else:
		ctx.state.remove_actor(id)
	if ctx.rpg.game != null and ctx.rpg.game.has_method("refresh_party_graphics"):
		ctx.rpg.game.refresh_party_graphics()
	return RPGResult.ok()
