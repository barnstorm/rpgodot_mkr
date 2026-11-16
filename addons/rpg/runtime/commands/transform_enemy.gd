@tool
extends RPGCommand
## RPG Maker 2003's "Transform Monster": an enemy group member becomes another enemy record —
## name, graphic, stats, actions, traits and rewards — keeping its slot on screen and its "A/B"
## suffix. HP is kept (clamped to the new maximum), kept as a percentage, or refilled; states
## are kept or cleared. Battle events only (an enemy group's battle events, or a common event
## they call); anywhere else it stops the event with an error. The same swap also runs without a
## command, as the enemy action "transform" (#10).


static func descriptor() -> Dictionary:
	return {
		"type": "transform_enemy", "schema_version": 1, "category": "scenes", "label": "Transform Enemy",
		"battle_only": true,
		"fields": [
			{"key": "enemy_index", "kind": "int", "default": 1, "min": 1, "label": "Enemy # (1 = first in the group)"},
			{"key": "enemy", "kind": "ref", "ref": "enemy", "required": true, "label": "Becomes"},
			{"key": "hp", "kind": "choice", "options": ["keep", "percent", "refill"], "option_labels": ["Keep HP (clamped to the new max)", "Keep HP %", "Refill HP"], "default": "keep", "label": "HP"},
			{"key": "clear_states", "kind": "bool", "default": false, "label": "Clear states"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Transform: enemy #%d becomes %s" % [int(args.get("enemy_index", 1)), args.get("enemy", "")]


## The battle scene running now, through the public battle API (rpg.battle), or null.
static func battle_scene(ctx: RPGContext) -> Node:
	return ctx.battle.scene() if ctx.battle != null else null


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var scene := battle_scene(ctx)
	if scene == null:
		return RPGResult.error("Transform Enemy: this only works in a battle event (no battle is running).")
	var idx := int(args.get("enemy_index", 1)) - 1
	var core: Variant = scene.get("core")
	if core != null and idx >= core.troop.get("members", []).size():
		return RPGResult.error("Transform Enemy: enemy group '%s' has no enemy #%d." % [core.troop.get("id", ""), idx + 1])
	var nb: Variant = await scene.enemy_transform(idx, str(args.get("enemy", "")), str(args.get("hp", "keep")), bool(args.get("clear_states", false)))
	if nb == null:
		return RPGResult.error("Transform Enemy: enemy '%s' does not exist." % args.get("enemy", ""))
	return RPGResult.ok()
