@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "toggle_followers", "schema_version": 1, "category": "movement", "label": "Change Player Followers",
		"fields": [{"key": "visible", "kind": "bool", "default": true, "label": "Followers visible"}],
	}


func summary(args: Dictionary) -> String:
	return "Followers: %s" % ("ON" if args.get("visible", true) else "OFF")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.state.followers_visible = bool(args.get("visible", true))
	if ctx.rpg.game != null and ctx.rpg.game.has_method("refresh_party_graphics"):
		ctx.rpg.game.refresh_party_graphics()
	return RPGResult.ok()
