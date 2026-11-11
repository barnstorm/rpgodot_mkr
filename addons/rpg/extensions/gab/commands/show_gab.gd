@tool
extends RPGCommand
## Show gab (gab plugin): a short line in the gab strip. The event goes on at once and the player
## keeps moving; use Wait for gabs to wait. Text codes work as in Show Text (no waits).


static func descriptor() -> Dictionary:
	return {
		"type": "show_gab", "schema_version": 1, "category": "message", "label": "Show gab",
		"fields": [
			{"key": "text", "kind": "text", "label": "Text", "default": "", "required": true, "help": "Codes: \\V[id] \\N[actor] \\C[n] \\I[n] ..."},
			{"key": "name", "kind": "text", "label": "Speaker name", "default": ""},
			{"key": "face", "kind": "resource", "res": "faceset", "label": "Face", "default": null},
			{"key": "sound", "kind": "sound", "label": "Sound (empty: the plugin's)", "default": {"file": "", "volume": 80, "pitch": 100, "pan": 0}},
			{"key": "switch", "kind": "ref", "ref": "switch", "label": "Turn ON when it has faded", "default": ""},
		],
	}


func summary(args: Dictionary) -> String:
	var who := str(args.get("name", ""))
	return "Gab: %s%s" % [(who + ": ") if who != "" else "", args.get("text", "")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var g: Object = ctx.rpg.extension("gab")
	if g == null:
		return RPGResult.error("Show gab: the Gab window plugin is not running.")
	var opts := {"name": str(args.get("name", "")), "switch": str(args.get("switch", ""))}
	if args.get("face") is Dictionary:
		opts["face"] = args.face
	if args.get("sound") is Dictionary:
		opts["sound"] = args.sound
	g.show_gab(str(args.get("text", "")), opts)
	return RPGResult.ok()
