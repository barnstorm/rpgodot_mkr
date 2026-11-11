@tool
extends RPGCommand
## RPG Maker's "Change Name": the actor's name for the rest of the game (saved with the actor).


static func descriptor() -> Dictionary:
	return {
		"type": "change_name", "schema_version": 1, "category": "party", "label": "Change Name",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "name", "kind": "text", "default": "", "label": "Name"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Name: %s = %s" % [args.get("actor", "?"), args.get("name", "")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	if not ctx.data.has_record("actors", id):
		return RPGResult.error("Change Name: actor '%s' does not exist." % id)
	var b: Variant = ctx.state.actor(id)
	if b == null:
		return RPGResult.error("Change Name: actor '%s' could not be created." % id)
	RPGPartyUtil.set_field(b, "name", str(args.get("name", "")))
	ctx.state.notify_actor_changed(id)
	return RPGResult.ok()
