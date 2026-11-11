@tool
extends RPGCommand
## RPG Maker's "Set Vehicle Location": parks the boat, ship or airship on any map.


static func descriptor() -> Dictionary:
	return {
		"type": "set_vehicle_location", "schema_version": 1, "category": "movement", "label": "Set Vehicle Location",
		"fields": [
			{"key": "vehicle", "kind": "choice", "options": ["boat", "ship", "airship"], "default": "boat", "label": "Vehicle"},
			{"key": "to", "kind": "location", "label": "Location", "required": true},
			{"key": "facing", "kind": "facing", "default": "left", "label": "Facing"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Set Vehicle Location: %s, %s" % [str(args.get("vehicle", "boat")).capitalize(), RPGCommand.describe_location(args.get("to"))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var kind := str(args.get("vehicle", "boat"))
	var to: Variant = args.get("to")
	if not (to is Dictionary) or not to.has("map") or not (to.get("position") is Array):
		return RPGResult.error("Set Vehicle Location: location must be {map, position}.")
	if not ctx.data.maps.has(str(to.map)):
		return RPGResult.error("Set Vehicle Location: map '%s' does not exist." % to.map)
	if ctx.state.riding == kind:
		return RPGResult.error("Set Vehicle Location: the player is riding the %s; get off first." % kind)
	var facing := str(args.get("facing", "left"))
	load("res://addons/rpg/runtime/rpg_vehicles.gd").park(ctx.state, kind, str(to.map), Vector2i(int(to.position[0]), int(to.position[1])), "left" if facing == "keep" else facing)
	var m: Node = ctx.map
	if m != null and m.has_method("refresh_vehicles"):
		m.refresh_vehicles()
	return RPGResult.ok()
