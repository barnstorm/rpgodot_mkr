@tool
extends RPGCommand
## RPG Maker's "Enemy Appear": brings an enemy group member marked "Appears later" into the
## battle that is running. Its image fades in and "%1 appears!" shows. Battle events only (an
## enemy group's battle events, or a common event they call); anywhere else it stops the event
## with an error. A member that is already in the battle is left alone.


static func descriptor() -> Dictionary:
	return {
		"type": "enemy_appear", "schema_version": 1, "category": "scenes", "label": "Enemy Appear",
		"battle_only": true,
		"fields": [
			{"key": "which", "kind": "choice", "options": ["one", "all"], "option_labels": ["One enemy", "Every hidden enemy"], "default": "one", "label": "Enemy"},
			{"key": "enemy", "kind": "int", "default": 1, "min": 1, "label": "Enemy # (1 = first in the group)", "show_if": {"key": "which", "equals": "one"}},
		],
	}


func summary(args: Dictionary) -> String:
	if str(args.get("which", "one")) == "all":
		return "Enemy Appear: every hidden enemy"
	return "Enemy Appear: enemy #%d" % int(args.get("enemy", 1))


## The member index (0-based) the args pick, or -1 for every hidden member.
static func member_index(args: Dictionary) -> int:
	if str(args.get("which", "one")) == "all":
		return -1
	return int(args.get("enemy", 1)) - 1


## The battle scene running now (the top scene with enemy_appear()), or null.
static func battle_scene(ctx: RPGContext) -> Node:
	var ui: Node = ctx.ui
	if ui == null or not ("scene_stack" in ui):
		return null
	var stack: Array = ui.scene_stack
	for i in range(stack.size() - 1, -1, -1):
		var n: Node = stack[i]
		if is_instance_valid(n) and n.has_method("enemy_appear"):
			return n
	return null


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var scene := battle_scene(ctx)
	if scene == null:
		return RPGResult.error("Enemy Appear: this only works in a battle event (no battle is running).")
	var idx := member_index(args)
	var core: Variant = scene.get("core")
	if idx >= 0 and core != null and (idx >= core.troop.get("members", []).size()):
		return RPGResult.error("Enemy Appear: enemy group '%s' has no enemy #%d." % [core.troop.get("id", ""), idx + 1])
	await scene.enemy_appear(idx)
	return RPGResult.ok()
