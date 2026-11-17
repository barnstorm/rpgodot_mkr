@tool
extends RPGCommand
## RPG Maker's "Transform Enemy": an enemy group member fighting the battle becomes a different
## enemy. It keeps its slot (position in the group, screen position, "appears later" flag, turn
## state) and its "A"/"B" suffix; stats, actions, graphic and rewards come from the new record.
## Battle events only (an enemy group's battle events, or a common event they call); anywhere
## else it stops the event with an error.


static func descriptor() -> Dictionary:
	return {
		"type": "transform_enemy", "schema_version": 1, "category": "scenes", "label": "Transform Enemy",
		"battle_only": true,
		"fields": [
			{"key": "enemy", "kind": "int", "default": 1, "min": 1, "label": "Enemy # (1 = first in the group)"},
			{"key": "into", "kind": "ref", "ref": "enemy", "label": "Transform into", "required": true},
			{"key": "hp", "kind": "choice", "options": ["keep", "percent", "refill"],
				"option_labels": ["Keep HP (clamped to the new maximum)", "Keep HP percentage", "Start at full HP"],
				"default": "keep", "label": "HP"},
			{"key": "clear_states", "kind": "bool", "default": false, "label": "Remove its states"},
		],
	}


func summary(args: Dictionary) -> String:
	var what := str(args.get("into", ""))
	var label := "Transform Enemy: enemy #%d%s" % [int(args.get("enemy", 1)), (" -> " + what) if what != "" else ""]
	match str(args.get("hp", "keep")):
		"percent":
			label += " (HP % kept)"
		"refill":
			label += " (HP refilled)"
	if bool(args.get("clear_states", false)):
		label += ", states removed"
	return label


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var facade: RPGBattleFacade = ctx.battle
	if facade == null or not facade.valid():
		return RPGResult.error("Transform Enemy: this only works in a battle event (no battle is running).")
	var enemy_id := str(args.get("into", ""))
	if not ctx.data.has_record("enemies", enemy_id):
		return RPGResult.error("Transform Enemy: enemy '%s' does not exist." % enemy_id)
	var b: RPGBattler = await facade.transform(int(args.get("enemy", 1)), enemy_id,
		str(args.get("hp", "keep")), bool(args.get("clear_states", false)))
	if b == null:
		var n := int(args.get("enemy", 1))
		return RPGResult.error("Transform Enemy: enemy group '%s' has no enemy #%d." % [facade.core().troop.get("id", ""), n])
	return RPGResult.ok()
