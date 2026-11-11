@tool
extends RPGCommand
## RPG Maker's "Change EXP". Gaining experience levels up through the rule system (stat gains,
## skills learned); losing it lowers the level to match.


static func descriptor() -> Dictionary:
	return {
		"type": "change_exp", "schema_version": 1, "category": "rules", "label": "Change EXP",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "leader", "label": "Target"},
			{"key": "operation", "kind": "choice", "options": ["increase", "decrease"], "default": "increase", "label": "Operation"},
			{"key": "amount", "kind": "operand", "default": 10, "min": 0, "label": "EXP"},
			{"key": "show_level_up", "kind": "bool", "default": false, "label": "Show level up"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change EXP: %s %s %s" % [args.target, args.operation, RPGCommand.describe_operand(args.amount)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var err := RPGPartyUtil.check_target(ctx, str(args.target), "Change EXP")
	if err != "":
		return RPGResult.error(err)
	var amount := int(ctx.operand(args.amount))
	if amount < 0:
		return RPGResult.error("Change EXP: amount must be positive; use the operation to decrease.")
	var rules: Variant = ctx.rpg.rules
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		var ups: Array = []
		if str(args.operation) == "increase":
			if b is RPGBattler and rules != null and rules.has_method("gain_exp"):
				ups = rules.gain_exp(b, amount)
			else:
				RPGPartyUtil.set_field(b, "exp", int(RPGPartyUtil.get_field(b, "exp", 0)) + amount)
		else:
			RPGPartyUtil.set_field(b, "exp", maxi(0, int(RPGPartyUtil.get_field(b, "exp", 0)) - amount))
			RPGPartyUtil.sync_level_to_exp(ctx, b)
		ctx.state.notify_actor_changed(pair[0])
		if args.get("show_level_up", false) and not ups.is_empty():
			if not await RPGPartyUtil.show_level_ups(ctx, b, ups):
				return RPGResult.cancelled()
	return RPGResult.ok()
