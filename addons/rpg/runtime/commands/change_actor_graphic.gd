@tool
extends RPGCommand
## RPG Maker's "Change Actor Graphic": the actor's map sprite (CharSet sheet and index), face
## (FaceSet sheet and index) and battler image. A blank sheet keeps the current one. Saved with
## the actor; the leader's sprite and followers update at once.


static func descriptor() -> Dictionary:
	return {
		"type": "change_actor_graphic", "schema_version": 1, "category": "party", "label": "Change Actor Graphic",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "charset", "kind": "resource", "res": "charset", "default": "", "label": "Map sprite sheet (blank = keep)"},
			{"key": "charset_index", "kind": "int", "default": 0, "min": 0, "max": 7, "label": "Sprite index"},
			{"key": "face", "kind": "resource", "res": "faceset", "default": "", "label": "Face sheet (blank = keep)"},
			{"key": "face_index", "kind": "int", "default": 0, "min": 0, "max": 7, "label": "Face index"},
			{"key": "battler", "kind": "resource", "res": "battler", "default": "", "label": "Battler image (blank = keep)", "help": "Used by battle systems that draw actors (side view)."},
		],
	}


func summary(args: Dictionary) -> String:
	var bits := PackedStringArray()
	if str(args.get("charset", "")) != "":
		bits.append("sprite %s[%d]" % [args.charset, int(args.get("charset_index", 0))])
	if str(args.get("face", "")) != "":
		bits.append("face %s[%d]" % [args.face, int(args.get("face_index", 0))])
	if str(args.get("battler", "")) != "":
		bits.append("battler %s" % args.battler)
	return "Change Actor Graphic: %s, %s" % [args.get("actor", "?"), ", ".join(bits) if not bits.is_empty() else "(no change)"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	if not ctx.data.has_record("actors", id):
		return RPGResult.error("Change Actor Graphic: actor '%s' does not exist." % id)
	var look := {}
	for pair in [["charset", "charset", "charset_index"], ["face", "faceset", "face_index"], ["battler", "battler", ""]]:
		var key: String = pair[0]
		var sheet := str(args.get(key, "")) if args.get(key) != null else ""
		if sheet == "":
			continue
		if RPGAssets.find(pair[1], sheet) == "":
			return RPGResult.error("Change Actor Graphic: %s image '%s' not found." % [pair[1], sheet])
		look[key] = sheet
		if pair[2] != "":
			look[pair[2]] = clampi(int(args.get(pair[2], 0)), 0, 7)
	if look.is_empty():
		return RPGResult.ok()
	ctx.state.set_actor_look(id, look)
	if ctx.rpg.game != null and ctx.rpg.game.has_method("refresh_party_graphics"):
		ctx.rpg.game.refresh_party_graphics()
	return RPGResult.ok()
