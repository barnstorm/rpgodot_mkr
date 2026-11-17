@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "change_state", "schema_version": 1, "category": "party", "label": "Change State",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader", "troop", "enemy"],
				"allow_labels": {"party": "Whole party", "leader": "Party leader", "troop": "Entire troop", "enemy": "Enemy #"},
				"default": "party", "label": "Target"},
			{"key": "enemy_index", "kind": "int", "default": 1, "min": 1, "max": 8, "label": "Enemy # (1 = first in the group)", "show_if": {"key": "target", "equals": "enemy"}},
			{"key": "state", "kind": "ref", "ref": "state", "label": "State", "required": true},
			{"key": "operation", "kind": "choice", "options": ["add", "remove"], "default": "add", "label": "Operation"},
			{"key": "force", "kind": "bool", "default": false, "label": "Ignore resist rates", "show_if": {"key": "operation", "equals": "add"}},
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
	var enemy_side: bool = ["troop", "enemy"].has(str(args.target))
	for pair in RPGPartyUtil.targets(ctx, str(args.target), int(args.get("enemy_index", 1))):
		var b: Variant = pair[1]
		if b is RPGBattler and rules is RPGRuleSystem:
			if args.operation == "add":
				if args.get("force", false):
					if not b.has_state(sid):
						b.add_state(sid)
						_notify_state(ctx, b, sid, true)
				else:
					rules.add_state(b, sid)
			else:
				rules.remove_state(b, sid)
			if str(pair[0]) != "":
				ctx.state.notify_actor_changed(pair[0])
			continue
		if args.operation == "add":
			if b is Object and b.has_method("add_state"):
				var had: bool = b.has_state(sid)
				b.add_state(sid)
				if not had:
					_notify_state(ctx, b, sid, true)
			elif not RPGPartyUtil.states_of(b).any(func(s): return s.get("id", "") == sid):
				RPGPartyUtil.states_of(b).append({"id": sid, "turns": -1})
				_notify_state(ctx, b, sid, true)
		else:
			if b is Object and b.has_method("remove_state"):
				if b.remove_state(sid):
					_notify_state(ctx, b, sid, false)
			else:
				var st: Array = RPGPartyUtil.states_of(b)
				for i in range(st.size() - 1, -1, -1):
					if st[i].get("id", "") == sid:
						st.remove_at(i)
						_notify_state(ctx, b, sid, false)
		if str(pair[0]) != "":
			ctx.state.notify_actor_changed(pair[0])
	if enemy_side and ctx.battle != null and ctx.battle.valid():
		ctx.battle.refresh()
	# Adding the knockout state to the last one standing is a party wipe too (VX Ace and MV end
	# the game whenever the whole party is down on the map).
	if args.operation == "add" and not enemy_side and RPGPartyUtil.party_fell_on_map(ctx):
		return await RPGPartyUtil.map_defeat(ctx)
	return RPGResult.ok()


## The on_state_added / on_state_removed common events (issue #52): the rule system's own paths
## emit through the service; these are the no-rules fallbacks of this command.
static func _notify_state(ctx: RPGContext, b: Variant, sid: String, added: bool) -> void:
	if ctx.rpg != null and ctx.rpg.has_signal("actor_state_changed"):
		ctx.rpg.actor_state_changed.emit(b, sid, added)
