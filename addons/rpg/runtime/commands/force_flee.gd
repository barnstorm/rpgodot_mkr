@tool
extends RPGCommand
## RPG Maker 2003's "Force Flee": enemies run away (out of the fight, no rewards — the battle
## is won when the last one goes), or the whole party runs (the battle ends as an escape, with
## no chance roll). Battle events only (an enemy group's battle events, or a common event they
## call); anywhere else it stops the event with an error.


static func descriptor() -> Dictionary:
	return {
		"type": "force_flee", "schema_version": 1, "category": "scenes", "label": "Force Flee",
		"battle_only": true,
		"fields": [
			{"key": "target", "kind": "choice", "options": ["enemy", "enemies", "party"], "option_labels": ["Enemy #", "Every enemy", "The party"], "default": "enemy", "label": "Who flees"},
			{"key": "enemy_index", "kind": "int", "default": 1, "min": 1, "label": "Enemy # (1 = first in the group)", "show_if": {"key": "target", "equals": "enemy"}},
		],
	}


func summary(args: Dictionary) -> String:
	match str(args.get("target", "enemy")):
		"enemies":
			return "Force Flee: every enemy"
		"party":
			return "Force Flee: the party"
	return "Force Flee: enemy #%d" % int(args.get("enemy_index", 1))


## The battle scene running now, through the public battle API (rpg.battle), or null.
static func battle_scene(ctx: RPGContext) -> Node:
	return ctx.battle.scene() if ctx.battle != null else null


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var scene := battle_scene(ctx)
	if scene == null:
		return RPGResult.error("Force Flee: this only works in a battle event (no battle is running).")
	var target := str(args.get("target", "enemy"))
	var idx := int(args.get("enemy_index", 1)) - 1 if target == "enemy" else -1
	var core: Variant = scene.get("core")
	if target == "enemy" and core != null and idx >= core.troop.get("members", []).size():
		return RPGResult.error("Force Flee: enemy group '%s' has no enemy #%d." % [core.troop.get("id", ""), idx + 1])
	await scene.enemy_flee(target, idx)
	return RPGResult.ok()
