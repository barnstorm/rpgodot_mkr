@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_gold", "schema_version": 1, "category": "party", "label": "Change Gold",
		"fields": [
			{"key": "operation", "kind": "choice", "options": ["increase", "decrease", "set"], "default": "increase", "label": "Operation"},
			{"key": "amount", "kind": "operand", "default": 0, "min": 0, "label": "Amount"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Gold: %s %s" % [args.operation, RPGCommand.describe_operand(args.amount)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var amount := int(ctx.operand(args.amount))
	if amount < 0:
		return RPGResult.error("Change Gold: amount must be positive; use the operation to decrease.")
	ctx.state.change_gold(str(args.operation), amount)
	return RPGResult.ok()
