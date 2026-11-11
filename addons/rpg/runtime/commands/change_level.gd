@tool
extends RPGCommand
## RPG Maker's "Change Level". Raising a level goes through the rule system's experience and
## level-up rules (stat gains, skills learned). Lowering it sets the level and the experience
## for that level; stats gained on the way up are kept (they are not recorded per level).


static func descriptor() -> Dictionary:
	return {
		"type": "change_level", "schema_version": 1, "category": "rules", "label": "Change Level",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "leader", "label": "Target"},
			{"key": "operation", "kind": "choice", "options": ["increase", "decrease"], "default": "increase", "label": "Operation"},
			{"key": "amount", "kind": "operand", "default": 1, "min": 0, "label": "Levels"},
			{"key": "show_level_up", "kind": "bool", "default": false, "label": "Show level up"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Level: %s %s %s" % [args.target, args.operation, RPGCommand.describe_operand(args.amount)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var err := RPGPartyUtil.check_target(ctx, str(args.target), "Change Level")
	if err != "":
		return RPGResult.error(err)
	var amount := int(ctx.operand(args.amount))
	if amount < 0:
		return RPGResult.error("Change Level: amount must be positive; use the operation to decrease.")
	var delta := amount if str(args.operation) == "increase" else -amount
	var rules: Variant = ctx.rpg.rules
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		var cur := int(RPGPartyUtil.get_field(b, "level", 1))
		var cap := 99
		if rules != null and b is RPGBattler and rules.has_method("max_level"):
			cap = int(rules.max_level(b))
		var want := clampi(cur + delta, 1, cap)
		var ups: Array = []
		if RPGPartyUtil.rules_has(ctx, "change_level", 2):
			var r: Variant = rules.change_level(b, want)
			ups = r if r is Array else []
		elif b is RPGBattler and rules != null and rules.has_method("exp_for_level") and rules.has_method("gain_exp"):
			if want > cur:
				ups = rules.gain_exp(b, maxi(0, int(rules.exp_for_level(b.class_id, want)) - b.exp))
			elif want < cur:
				b.level = want
				b.exp = int(rules.exp_for_level(b.class_id, want))
				RPGPartyUtil.clamp_after_change(ctx, b)
		else:
			RPGPartyUtil.set_field(b, "level", want)
		ctx.state.notify_actor_changed(pair[0])
		if args.get("show_level_up", false) and not ups.is_empty():
			if not await RPGPartyUtil.show_level_ups(ctx, b, ups):
				return RPGResult.cancelled()
	return RPGResult.ok()
