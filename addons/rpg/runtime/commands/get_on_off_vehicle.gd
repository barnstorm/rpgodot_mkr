@tool
extends RPGCommand
## RPG Maker's "Get on/off Vehicle": boards the boat or ship in front of the player (or the
## airship underfoot), or leaves the one being ridden where landing is possible.


static func descriptor() -> Dictionary:
	return {
		"type": "get_on_off_vehicle", "schema_version": 1, "category": "movement", "label": "Get On/Off Vehicle",
		"fields": [],
	}


func summary(_args: Dictionary) -> String:
	return "Get On/Off Vehicle"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	var p: Node = ctx.rpg.game.player if ctx.rpg.game != null else null
	if p == null or not p.has_method("get_on_off_vehicle"):
		return RPGResult.error("Get On/Off Vehicle: no player on a map.")
	p.get_on_off_vehicle()
	return RPGResult.ok()
