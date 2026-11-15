@tool
extends RPGCommand
## RPG Maker's "Force Action": a battler (an enemy group member or an actor) uses a skill or an
## item at once, outside the turn order — a boss's signature move, a counterattack, a story beat.
## The target is its last target, a random one, or a number in the target row. "At its next turn"
## queues the action instead: the battler uses it when its turn comes (the player is not asked),
## and a timed battle's gauge is consumed as usual. Battle events only; anywhere else it stops
## the event with an error. A battler that cannot act (dead, hidden, restricted) skips quietly.


static func descriptor() -> Dictionary:
	return {
		"type": "force_action", "schema_version": 1, "category": "scenes", "label": "Force Action",
		"battle_only": true,
		"fields": [
			{"key": "subject", "kind": "choice", "options": ["enemy", "actor"], "default": "enemy", "label": "Subject"},
			{"key": "enemy_index", "kind": "int", "default": 1, "min": 1, "label": "Enemy # (1 = first in the group)",
				"show_if": {"key": "subject", "equals": "enemy"}},
			{"key": "actor", "kind": "ref", "ref": "actor", "allow": ["leader"], "allow_labels": {"leader": "Party leader"},
				"default": "leader", "label": "Actor", "show_if": {"key": "subject", "equals": "actor"}},
			{"key": "what", "kind": "choice", "options": ["skill", "item"], "default": "skill", "label": "Uses"},
			{"key": "skill", "kind": "ref", "ref": "skill", "label": "Skill", "required": true,
				"show_if": {"key": "what", "equals": "skill"}},
			{"key": "item", "kind": "ref", "ref": "item", "label": "Item", "required": true,
				"show_if": {"key": "what", "equals": "item"}},
			{"key": "target", "kind": "choice", "options": ["last", "random", "index"],
				"option_labels": ["Its last target", "A random target", "Target #"],
				"default": "last", "label": "Target"},
			{"key": "target_index", "kind": "int", "default": 1, "min": 1, "label": "Target # (1 = first of the row)",
				"show_if": {"key": "target", "equals": "index"}},
			{"key": "timing", "kind": "choice", "options": ["now", "turn"],
				"option_labels": ["Right now (out of turn)", "At its next turn (uses its turn)"],
				"default": "now", "label": "Timing"},
		],
	}


func summary(args: Dictionary) -> String:
	var who := "enemy #%d" % int(args.get("enemy_index", 1))
	if str(args.get("subject", "enemy")) == "actor":
		who = str(args.get("actor", ""))
	var what := str(args.get("skill", args.get("item", "")))
	var s := "Force Action: %s uses %s" % [who, what if what != "" else "?"]
	match str(args.get("target", "last")):
		"random":
			s += " (random target)"
		"index":
			s += " (target #%d)" % int(args.get("target_index", 1))
	if str(args.get("timing", "now")) == "turn":
		s += ", at its next turn"
	return s


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var facade: RPGBattleFacade = ctx.battle
	if facade == null or not facade.valid():
		return RPGResult.error("Force Action: this only works in a battle event (no battle is running).")
	var core: RPGBattleCore = facade.core()

	# Subject: an enemy group member (1-based) or an actor in the fighting party.
	var b: RPGBattler = null
	if str(args.get("subject", "enemy")) == "actor":
		var actor := str(args.get("actor", "leader"))
		if actor == "leader":
			if not core.party.is_empty():
				b = core.party[0]
		else:
			for a in core.party:
				if a.id == actor:
					b = a
					break
		if b == null:
			return RPGResult.error("Force Action: actor '%s' is not in this battle." % actor)
	else:
		var n := int(args.get("enemy_index", 1))
		if n < 1 or n > core.enemies.size():
			return RPGResult.error("Force Action: enemy group '%s' has no enemy #%d." % [core.troop.get("id", ""), n])
		b = core.enemies[n - 1]

	# What it uses: a skill record (anyone can be forced to use one) or an item record.
	var what := str(args.get("what", "skill"))
	var action := {"kind": what, "target": -1, "target_mode": str(args.get("target", "last"))}
	if what == "item":
		var item := str(args.get("item", ""))
		if not ctx.data.has_record("items", item):
			return RPGResult.error("Force Action: item '%s' does not exist." % item)
		action["item"] = item
	else:
		var skill := str(args.get("skill", ""))
		if not ctx.data.has_record("skills", skill):
			return RPGResult.error("Force Action: skill '%s' does not exist." % skill)
		action["skill"] = skill
	if str(args.get("target", "last")) == "index":
		action.target = int(args.get("target_index", 1)) - 1

	if str(args.get("timing", "now")) == "turn":
		if not facade.queue(b, action):
			push_warning("Force Action: %s cannot act; nothing happens." % b.name)
		return RPGResult.ok()
	var res: Dictionary = await facade.perform(b, action)
	if res.is_empty():
		push_warning("Force Action: %s cannot act; nothing happens." % b.name)
	return RPGResult.ok()
