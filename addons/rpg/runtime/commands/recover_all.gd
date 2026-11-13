@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "recover_all", "schema_version": 1, "category": "party", "label": "Recover All",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader", "troop", "enemy"],
				"allow_labels": {"party": "Whole party", "leader": "Party leader", "troop": "Entire troop", "enemy": "Enemy #"},
				"default": "party", "label": "Target"},
			{"key": "enemy_index", "kind": "int", "default": 1, "min": 1, "max": 8, "label": "Enemy # (1 = first in the group)", "show_if": {"key": "target", "equals": "enemy"}},
		],
	}


func summary(args: Dictionary) -> String:
	return "Recover All: %s" % args.get("target", "party")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var enemy_side: bool = ["troop", "enemy"].has(str(args.get("target", "party")))
	for pair in RPGPartyUtil.targets(ctx, str(args.get("target", "party")), int(args.get("enemy_index", 1))):
		var b: Variant = pair[1]
		var rules: Variant = ctx.rpg.rules
		if rules != null and rules.has_method("recover_all"):
			rules.recover_all(b)
		else:
			for res in ["hp", "sp"]:
				RPGPartyUtil.set_res(ctx, b, res, RPGPartyUtil.resource_max(ctx, b, res))
			RPGPartyUtil.states_of(b).clear()
		if str(pair[0]) != "":
			ctx.state.notify_actor_changed(pair[0])
	if enemy_side and ctx.battle != null and ctx.battle.valid():
		ctx.battle.refresh()
	return RPGResult.ok()
