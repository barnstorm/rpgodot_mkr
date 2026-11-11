@tool
extends RPGCommand
## RPG Maker's "Change Vehicle Graphic" (and its music, as "Change Vehicle BGM" does).


static func descriptor() -> Dictionary:
	return {
		"type": "change_vehicle_graphic", "schema_version": 1, "category": "movement", "label": "Change Vehicle Graphic",
		"fields": [
			{"key": "vehicle", "kind": "choice", "options": ["boat", "ship", "airship"], "default": "boat", "label": "Vehicle"},
			{"key": "graphic", "kind": "graphic", "label": "Graphic"},
			{"key": "bgm", "kind": "resource", "res": "music", "default": "", "label": "Music while riding (blank = keep)"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Change Vehicle Graphic: %s" % str(args.get("vehicle", "boat")).capitalize()


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var kind := str(args.get("vehicle", "boat"))
	# Stored in the game state so saves keep it; RPGVehicles.config reads the System record, so
	# the override is kept per game under state.vehicles[kind].graphic / bgm.
	var v: Dictionary = ctx.state.vehicles.get(kind, {})
	if args.get("graphic") is Dictionary:
		v["graphic"] = args.graphic.duplicate()
	var bgm: Variant = args.get("bgm", "")
	if bgm is String and bgm != "":
		v["bgm"] = {"file": bgm}
	elif bgm is Dictionary:
		v["bgm"] = bgm.duplicate()
	ctx.state.vehicles[kind] = v
	var m: Node = ctx.map
	if m != null and m.has_method("refresh_vehicles"):
		m.refresh_vehicles()
	var p: Node = ctx.rpg.game.player if ctx.rpg.game != null else null
	if p != null and ctx.state.riding == kind and v.has("graphic"):
		p.set_graphic(v.graphic)
	return RPGResult.ok()
