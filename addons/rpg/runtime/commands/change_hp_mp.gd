@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_hp_mp", "schema_version": 1, "category": "party", "label": "Change HP / SP",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "party", "label": "Target"},
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
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		var cur := RPGPartyUtil.get_res(b, res)
		var nv := cur + amount if args.operation == "increase" else cur - amount
		if res == "hp" and not args.get("allow_knockout", false) and cur > 0:
			nv = maxi(nv, 1)
		RPGPartyUtil.set_res(ctx, b, res, nv)
		if res == "hp" and RPGPartyUtil.get_res(b, "hp") <= 0 and b is Object and b.has_method("add_state"):
			b.add_state("knockout")
		ctx.state.notify_actor_changed(pair[0])
	return RPGResult.ok()
