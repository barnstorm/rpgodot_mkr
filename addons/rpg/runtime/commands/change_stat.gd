@tool
extends RPGCommand
## Permanently changes a base stat of an actor (the rule system decides which stats exist).


static func descriptor() -> Dictionary:
	return {
		"type": "change_stat", "schema_version": 1, "category": "rules", "label": "Change Stat",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "leader", "label": "Target"},
			{"key": "stat", "kind": "text", "default": "str", "label": "Stat"},
			{"key": "operation", "kind": "choice", "options": ["increase", "decrease", "set"], "default": "increase", "label": "Operation"},
			{"key": "amount", "kind": "operand", "default": 1, "min": 0, "label": "Amount"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Stat: %s %s %s %s" % [args.target, str(args.stat).to_upper(), args.operation, RPGCommand.describe_operand(args.amount)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var stat := str(args.stat).to_lower()
	var rules: Variant = ctx.rpg.rules
	if rules != null and rules.has_method("stats"):
		var known: Array = rules.stats()
		var names := []
		for s in known:
			names.append(str(s.get("id", s) if s is Dictionary else s).to_lower())
		if not names.is_empty() and not names.has(stat):
			return RPGResult.error("Change Stat: the rule system has no stat '%s' (it has %s)." % [stat, ", ".join(names)])
	var amount := int(ctx.operand(args.amount))
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		if not (b is Object and "base" in b):
			continue
		var cur := int(b.base.get(stat, 0))
		match str(args.operation):
			"increase": cur += amount
			"decrease": cur -= amount
			"set": cur = amount
		b.base[stat] = maxi(cur, 0)
		ctx.state.notify_actor_changed(pair[0])
	return RPGResult.ok()
