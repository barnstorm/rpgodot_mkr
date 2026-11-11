@tool
extends RPGCommand
## RPG Maker VX Ace's "Change Nickname" (the title shown on the status screen). Saved with the
## actor; RPGGameState.actor_look(id).nickname reads it.


static func descriptor() -> Dictionary:
	return {
		"type": "change_nickname", "schema_version": 1, "category": "party", "label": "Change Nickname",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "nickname", "kind": "text", "default": "", "label": "Nickname"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Nickname: %s = %s" % [args.get("actor", "?"), args.get("nickname", "")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	if not ctx.data.has_record("actors", id):
		return RPGResult.error("Change Nickname: actor '%s' does not exist." % id)
	if ctx.state.actor(id) == null:
		return RPGResult.error("Change Nickname: actor '%s' could not be created." % id)
	ctx.state.set_actor_look(id, {"nickname": str(args.get("nickname", ""))})
	return RPGResult.ok()
