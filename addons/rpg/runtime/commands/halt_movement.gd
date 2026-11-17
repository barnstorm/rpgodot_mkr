@tool
extends RPGCommand
## Halt All Movement (RM2000/2003): cancels every forced move route on the map — player, events
## and vehicles. The characters' own (autonomous) movement resumes where it was paused.


static func descriptor() -> Dictionary:
	return {
		"type": "halt_movement", "schema_version": 1, "category": "movement",
		"label": "Halt All Movement",
		"fields": [],
	}


func summary(args: Dictionary) -> String:
	return "Halt All Movement"


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null:
		return RPGResult.error("Halt All Movement: no map is running.")
	for ch in m.characters():
		if ch != null and ch.has_method("is_route_forced") and ch.is_route_forced():
			ch.cancel_forced_route("halt all movement")
	return RPGResult.ok()
