@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_hp_mp", "schema_version": 1, "category": "party", "label": "Change HP / SP",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader", "troop", "enemy"],
				"allow_labels": {"party": "Whole party", "leader": "Party leader", "troop": "Entire troop", "enemy": "Enemy #"},
				"default": "party", "label": "Target"},
			{"key": "enemy_index", "kind": "int", "default": 1, "min": 1, "max": 8, "label": "Enemy # (1 = first in the group)", "show_if": {"key": "target", "equals": "enemy"}},
			{"key": "resource", "kind": "choice", "options": ["hp", "sp"], "default": "hp", "label": "Resource"},
			{"key": "operation", "kind": "choice", "options": ["increase", "decrease"], "default": "increase", "label": "Operation"},
			{"key": "amount", "kind": "operand", "default": 10, "min": 0, "label": "Amount"},
			{"key": "allow_knockout", "kind": "bool", "default": false, "label": "Allow knockout", "show_if": {"key": "resource", "equals": "hp"}},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change %s: %s %s %s" % [str(args.resource).to_upper(), args.target, args.operation, RPGCommand.describe_operand(args.amount)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var amount := int(ctx.operand(args.amount))
	if amount < 0:
		return RPGResult.error("Change HP/SP: amount must be positive; use the operation to decrease.")
	var res := str(args.resource)
	var enemy_side: bool = ["troop", "enemy"].has(str(args.target))
	for pair in RPGPartyUtil.targets(ctx, str(args.target), int(args.get("enemy_index", 1))):
		var b: Variant = pair[1]
		var cur := RPGPartyUtil.get_res(b, res)
		var nv := cur + amount if args.operation == "increase" else cur - amount
		if res == "hp" and not args.get("allow_knockout", false) and cur > 0:
			nv = maxi(nv, 1)
		RPGPartyUtil.set_res(ctx, b, res, nv)
		if res == "hp" and RPGPartyUtil.get_res(b, "hp") <= 0 and b is Object and b.has_method("add_state"):
			if ctx.rpg.rules is RPGRuleSystem:
				ctx.rpg.rules.add_state(b, "knockout")
			else:
				b.add_state("knockout")
		if str(pair[0]) != "":
			ctx.state.notify_actor_changed(pair[0])
	if enemy_side and ctx.battle != null and ctx.battle.valid():
		ctx.battle.refresh()
	return RPGResult.ok()
