@tool
extends RPGCommand
## RPG Maker VX Ace's "Change Class". "Keep EXP" keeps the actor's experience and sets the level
## that experience reaches with the new class's curve; otherwise the level is kept and the
## experience becomes what that level needs in the new class.


static func descriptor() -> Dictionary:
	return {
		"type": "change_class", "schema_version": 1, "category": "rules", "label": "Change Class",
		"fields": [
			{"key": "target", "kind": "ref", "ref": "actor", "allow": ["party", "leader"], "default": "leader", "label": "Target"},
			{"key": "class", "kind": "ref", "ref": "class", "label": "Class", "required": true},
			{"key": "keep_exp", "kind": "bool", "default": false, "label": "Keep EXP"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Class: %s -> %s%s" % [args.target, args.get("class", "?"), " (keep EXP)" if args.get("keep_exp", false) else ""]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var err := RPGPartyUtil.check_target(ctx, str(args.target), "Change Class")
	if err != "":
		return RPGResult.error(err)
	var cls := str(args.get("class", ""))
	if not ctx.data.has_record("classes", cls):
		return RPGResult.error("Change Class: class '%s' does not exist." % cls)
	var keep := bool(args.get("keep_exp", false))
	var rules: Variant = ctx.rpg.rules
	for pair in RPGPartyUtil.targets(ctx, str(args.target)):
		var b: Variant = pair[1]
		if RPGPartyUtil.rules_has(ctx, "change_class", 3):
			rules.change_class(b, cls, keep)
		elif b is RPGBattler:
			b.class_id = cls
			if keep:
				RPGPartyUtil.sync_level_to_exp(ctx, b)
			elif rules != null and rules.has_method("exp_for_level"):
				b.exp = int(rules.exp_for_level(cls, b.level))
			RPGPartyUtil.clamp_after_change(ctx, b)
		else:
			RPGPartyUtil.set_field(b, "class", cls)
		ctx.state.notify_actor_changed(pair[0])
	return RPGResult.ok()
