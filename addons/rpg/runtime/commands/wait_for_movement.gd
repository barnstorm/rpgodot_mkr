@tool
extends RPGCommand
## Proceed with Movement (RM2000/2003) / Wait for Move Completion (VX Ace, MV): waits until every
## one-pass forced move route on the map has finished. Repeating routes are ignored, as in RPG
## Maker: they never complete.


static func descriptor() -> Dictionary:
	return {
		"type": "wait_for_movement", "schema_version": 1, "category": "movement",
		"label": "Wait for All Movement",
		"fields": [],
	}


func summary(args: Dictionary) -> String:
	return "Wait for All Movement"


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Wait for All Movement: no map is running.")
	while _routes_running(m):
		# Frame waits keep the parallel/autorun rules: no time passes while the map is suspended
		# (menu, battle) or the task is paused, and cancelling the event ends the wait.
		if not await ctx.wait_frames(1):
			return RPGResult.cancelled()
	return RPGResult.ok()


func _routes_running(m: Node) -> bool:
	for ch in m.characters():
		if ch != null and ch.has_method("has_waitable_forced_route") and ch.has_waitable_forced_route():
			return true
	return false
