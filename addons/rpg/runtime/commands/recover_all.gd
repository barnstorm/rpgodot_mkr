@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "recover_all", "schema_version": 1, "category": "party", "label": "Recover All",
		"fields": [{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "party", "label": "Target"}],
	}


func summary(args: Dictionary) -> String:
	return "Recover All: %s" % args.get("target", "party")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	for pair in RPGPartyUtil.targets(ctx, str(args.get("target", "party"))):
		var b: Variant = pair[1]
		var rules: Variant = ctx.rpg.rules
		if rules != null and rules.has_method("recover_all"):
			rules.recover_all(b)
		else:
			for res in ["hp", "sp"]:
				RPGPartyUtil.set_res(ctx, b, res, RPGPartyUtil.resource_max(ctx, b, res))
			RPGPartyUtil.states_of(b).clear()
		ctx.state.notify_actor_changed(pair[0])
	return RPGResult.ok()
