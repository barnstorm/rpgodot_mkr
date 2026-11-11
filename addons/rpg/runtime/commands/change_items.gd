@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_items", "schema_version": 1, "category": "party", "label": "Change Items",
		"fields": [
			{"key": "item_kind", "kind": "choice", "options": ["items", "weapons", "armors"], "default": "items", "label": "Kind"},
			{"key": "item", "kind": "ref", "ref": "item", "ref_from": "item_kind", "label": "Item", "required": true},
			{"key": "operation", "kind": "choice", "options": ["increase", "decrease", "set"], "default": "increase", "label": "Operation"},
			{"key": "amount", "kind": "operand", "default": 1, "min": 0, "label": "Amount"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Items: %s %s x%s" % [args.operation, args.get("item", "?"), RPGCommand.describe_operand(args.amount)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var kind := RPGGameState.kind_for(str(args.get("item_kind", "items")))
	var id := str(args.get("item", ""))
	if not ctx.data.has_record(kind, id) and not ctx.data.records(kind).is_empty():
		return RPGResult.error("Change Items: '%s' is not in the %s database." % [id, kind])
	var amount := int(ctx.operand(args.amount))
	if amount < 0:
		return RPGResult.error("Change Items: amount must be positive; use the operation to decrease.")
	ctx.state.change_items(id, str(args.operation), amount, kind)
	return RPGResult.ok()
