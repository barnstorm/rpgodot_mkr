@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_state", "schema_version": 1, "category": "party", "label": "Change State",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "party", "label": "Target"},
			{"key": "state", "kind": "ref", "ref": "state", "label": "State", "required": true},
			{"key": "operation", "kind": "choice", "options": ["add", "remove"], "default": "add", "label": "Operation"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change State: %s %s %s" % [args.target, args.operation, args.get("state", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var sid := str(args.get("state", ""))
	if not ctx.data.has_record("states", sid) and not ctx.data.records("states").is_empty():
		return RPGResult.error("Change State: state '%s' does not exist." % sid)
	# Through the rule system when there is one: the death state zeroes HP and clears the other
	# states, and removing it leaves at least 1 HP, as in battle.
	var rules: Variant = ctx.rpg.get("rules") if ctx.rpg else null
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		if b is RPGBattler and rules is RPGRuleSystem:
			if args.operation == "add":
				rules.add_state(b, sid)
			else:
				rules.remove_state(b, sid)
			ctx.state.notify_actor_changed(pair[0])
			continue
		if args.operation == "add":
			if b is Object and b.has_method("add_state"):
				b.add_state(sid)
			elif not RPGPartyUtil.states_of(b).any(func(s): return s.get("id", "") == sid):
				RPGPartyUtil.states_of(b).append({"id": sid, "turns": -1})
		else:
			if b is Object and b.has_method("remove_state"):
				b.remove_state(sid)
			else:
				var st: Array = RPGPartyUtil.states_of(b)
				for i in range(st.size() - 1, -1, -1):
					if st[i].get("id", "") == sid:
						st.remove_at(i)
		ctx.state.notify_actor_changed(pair[0])
	return RPGResult.ok()
