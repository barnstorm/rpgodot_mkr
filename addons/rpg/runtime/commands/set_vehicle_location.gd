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
	var facing := str(args.get("facing", "left"))
	var target := Vector2i(int(to.position[0]), int(to.position[1]))
	# Moving the vehicle the party rides follows the project's rules: the classic rules move the
	# party with it (RM2000/2003 — a different map is an instant, fade-free transfer, still
	# riding); the VX Ace style rules leave the ridden vehicle with the player, as MV does.
	if ctx.state.riding == kind:
		if _vx_ace_style_rules(ctx):
			return RPGResult.ok()
		if ctx.rpg.game == null:
			return RPGResult.error("Set Vehicle Location: no game is running.")
		var moved: RPGResult = await ctx.rpg.game.transfer(str(to.map), target, facing, "none", 0, ctx.interpreter)
		# transfer parks the ridden vehicle at the destination itself.
		if moved.is_error():
			return RPGResult.error("Set Vehicle Location: " + moved.message)
		return RPGResult.ok()
	load("res://addons/rpg/runtime/rpg_vehicles.gd").park(ctx.state, kind, str(to.map), target, "left" if facing == "keep" else facing)
	var m: Node = ctx.map
	if m != null and m.has_method("refresh_vehicles"):
		m.refresh_vehicles()
	return RPGResult.ok()


## True under the VX Ace style rules, whose Set Vehicle Location follows MV: the vehicle the party
## rides stays with the player. The classic rules move the party with it, as RM2000/2003 do.
func _vx_ace_style_rules(ctx: RPGContext) -> bool:
	return ctx.data != null and str(ctx.data.project.get("rules", "classic")) == "vx_ace"
