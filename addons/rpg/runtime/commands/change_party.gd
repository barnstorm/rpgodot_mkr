@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_party", "schema_version": 1, "category": "party", "label": "Change Party Member",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "operation", "kind": "choice", "options": ["add", "remove"], "default": "add", "label": "Operation"},
			{"key": "initialize", "kind": "bool", "default": false, "label": "Initialize (reset level and equipment)"},
			{"key": "battle_temp", "kind": "bool", "default": false, "label": "Only for this battle",
				"help": "While a battle runs: the actor joins the fight, and leaves the party again when it ends."},
		],
	}


func summary(args: Dictionary) -> String:
	return "Party: %s %s" % [args.operation, args.get("actor", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	var temp: Array = []
	if args.operation == "add":
		var was_in := ctx.state.in_party(id)
		if args.get("initialize", false):
			ctx.state.actors.erase(id)
		if not ctx.state.add_actor(id) and not ctx.state.in_party(id):
			return RPGResult.error("Change Party: actor '%s' does not exist." % id)
		if args.get("battle_temp", false) and not was_in:
			temp = [id]
	else:
		ctx.state.remove_actor(id)
	if ctx.rpg.game != null and ctx.rpg.game.has_method("refresh_party_graphics"):
		ctx.rpg.game.refresh_party_graphics()
	# In a battle (a troop page, or a common event it calls) the field follows at once: the new
	# actor gets a status row, sprite and gauge; a removed one leaves the fight.
	if ctx.battle != null and ctx.battle.valid():
		ctx.battle.refresh_party(temp)
	return RPGResult.ok()
