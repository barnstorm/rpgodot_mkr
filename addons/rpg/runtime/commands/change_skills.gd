@tool
extends RPGCommand
## RPG Maker's "Change Skills": learn or forget a skill.


static func descriptor() -> Dictionary:
	return {
		"type": "change_skills", "schema_version": 1, "category": "rules", "label": "Change Skills",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "leader", "label": "Target"},
			{"key": "operation", "kind": "choice", "options": ["learn", "forget"], "default": "learn", "label": "Operation"},
			{"key": "skill", "kind": "ref", "ref": "skill", "label": "Skill", "required": true},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Skills: %s %s %s" % [args.target, args.operation, args.get("skill", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var err := RPGPartyUtil.check_target(ctx, str(args.target), "Change Skills")
	if err != "":
		return RPGResult.error(err)
	var skill := str(args.get("skill", ""))
	if not ctx.data.has_record("skills", skill):
		return RPGResult.error("Change Skills: skill '%s' does not exist." % skill)
	var learn := str(args.operation) == "learn"
	var rules: Variant = ctx.rpg.rules
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		if learn and RPGPartyUtil.rules_has(ctx, "learn_skill", 2):
			rules.learn_skill(b, skill)
		elif not learn and RPGPartyUtil.rules_has(ctx, "forget_skill", 2):
			rules.forget_skill(b, skill)
		else:
			var list: Variant = RPGPartyUtil.get_field(b, "skills", [])
			if not (list is Array):
				list = []
			if learn and not list.has(skill):
				list.append(skill)
			elif not learn:
				list.erase(skill)
			RPGPartyUtil.set_field(b, "skills", list)
		ctx.state.notify_actor_changed(pair[0])
	return RPGResult.ok()
