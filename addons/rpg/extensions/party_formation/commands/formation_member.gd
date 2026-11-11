@tool
extends RPGCommand
## Change formation member (party_formation plugin): locks or unlocks a party member (the player
## cannot move a locked member), makes it required or not (a required member cannot go to the
## reserve), and moves it to the battle row or the reserve. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "formation_member", "schema_version": 1, "category": "party", "label": "Change formation member",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "lock", "kind": "choice", "options": ["keep", "lock", "unlock"], "option_labels": ["Keep", "Lock", "Unlock"], "default": "keep", "label": "Locked"},
			{"key": "require", "kind": "choice", "options": ["keep", "require", "release"], "option_labels": ["Keep", "Required", "Not required"], "default": "keep", "label": "Required"},
			{"key": "move", "kind": "choice", "options": ["keep", "active", "reserve"], "option_labels": ["Keep", "To the battle row", "To the reserve"], "default": "keep", "label": "Move"},
		],
	}


func summary(args: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in ["lock", "require", "move"]:
		if str(args.get(k, "keep")) != "keep":
			parts.append(str(args[k]))
	return "Formation %s: %s" % [args.get("actor", "?"), ", ".join(parts) if not parts.is_empty() else "no change"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var pf: Object = ctx.rpg.extension("party_formation")
	if pf == null:
		return RPGResult.error("Change formation member: the Party formation plugin is not running.")
	var id := str(args.get("actor", ""))
	if id == "":
		return RPGResult.error("Change formation member: no actor.")
	match str(args.get("lock", "keep")):
		"lock": pf.set_locked(id, true)
		"unlock": pf.set_locked(id, false)
	match str(args.get("require", "keep")):
		"require": pf.set_required(id, true)
		"release": pf.set_required(id, false)
	var mv := str(args.get("move", "keep"))
	if mv in ["active", "reserve"]:
		var why: String = pf.move(id, mv)
		if why != "":
			return RPGResult.error("Change formation member: %s" % why)
	return RPGResult.ok()
