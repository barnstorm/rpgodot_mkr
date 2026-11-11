@tool
extends RPGCommand
## Asks the rule system for a check outside battle (e.g. a STR check to force a door) and stores
## success (true/1) or failure (false/0) in a variable.


static func descriptor() -> Dictionary:
	return {
		"type": "roll_check", "schema_version": 1, "category": "rules", "label": "Roll Check",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "allow": ["leader"], "default": "leader", "label": "Who rolls"},
			{"key": "stat", "kind": "text", "default": "str", "label": "Stat"},
			{"key": "dc", "kind": "operand", "default": 10, "label": "Difficulty"},
			{"key": "result", "kind": "ref", "ref": "variable", "label": "Store success in", "required": true},
			{"key": "roll_into", "kind": "ref", "ref": "variable", "default": "", "label": "Store the roll in (optional)"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Roll Check: %s %s vs %s -> [%s]" % [args.actor, str(args.stat).to_upper(), RPGCommand.describe_operand(args.dc), args.get("result", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var rules: Variant = ctx.rpg.rules
	if rules == null or not rules.has_method("roll_check"):
		return RPGResult.error("Roll Check needs a rule system that provides checks.")
	var targets := RPGPartyUtil.targets(ctx, str(args.actor))
	if targets.is_empty():
		return RPGResult.error("Roll Check: no actor '%s' in the party." % args.actor)
	var res: Variant = rules.roll_check(targets[0][1], {"stat": str(args.stat), "dc": int(ctx.operand(args.dc))})
	var success := bool(res.get("success", false)) if res is Dictionary else bool(res)
	var var_id := str(args.result)
	var t := ctx.state.variable_type(var_id)
	ctx.state.set_variable(var_id, success if t == "bool" else (1 if success else 0))
	if str(args.get("roll_into", "")) != "" and res is Dictionary:
		ctx.state.set_variable(str(args.roll_into), int(res.get("roll", 0)))
	return RPGResult.ok(res)
