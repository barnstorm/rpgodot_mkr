@tool
extends RPGCommand
## Reveal enemy (bestiary plugin): marks an enemy (or every enemy) as seen or defeated in the
## bestiary, as if it had been met in battle. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "reveal_enemy", "schema_version": 1, "category": "scenes", "label": "Reveal enemy",
		"fields": [
			{"key": "all", "kind": "bool", "default": false, "label": "Every enemy"},
			{"key": "enemy", "kind": "ref", "ref": "enemy", "default": "", "label": "Enemy", "show_if": {"key": "all", "equals": false}},
			{"key": "level", "kind": "choice", "options": ["seen", "defeated"], "option_labels": ["Seen", "Defeated"], "default": "seen", "label": "As"},
		],
	}


func summary(args: Dictionary) -> String:
	var who := "every enemy" if bool(args.get("all", false)) else str(args.get("enemy", "?"))
	return "Reveal %s as %s" % [who, args.get("level", "seen")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var bk: Object = ctx.rpg.extension("bestiary")
	if bk == null:
		return RPGResult.error("Reveal enemy: the Bestiary plugin is not running.")
	var id := "" if bool(args.get("all", false)) else str(args.get("enemy", ""))
	if id == "" and not bool(args.get("all", false)):
		return RPGResult.error("Reveal enemy: no enemy chosen.")
	if id != "" and not ctx.data.has_record("enemies", id):
		return RPGResult.error("Reveal enemy: enemy '%s' does not exist." % id)
	bk.reveal(id, str(args.get("level", "seen")))
	return RPGResult.ok()
