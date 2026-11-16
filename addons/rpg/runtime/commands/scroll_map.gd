@tool
extends RPGCommand
## Pan Screen (RM2000/2003) / Scroll Map: pans the view by tiles or back onto the player, with
## Lock / Unlock freezing the camera so it stops following the player (pans still scroll a locked
## screen, and Unlock resumes following with no snap).


static func descriptor() -> Dictionary:
	return {
		"type": "scroll_map", "schema_version": 1, "category": "movement", "label": "Scroll Map",
		"fields": [
			{"key": "direction", "kind": "choice", "options": ["down", "left", "right", "up", "return", "lock", "unlock"], "default": "down", "label": "Direction", "help": "Lock stops the camera following the player (RM2000/2003's Pan Screen Lock); unlock resumes it without snapping"},
			{"key": "distance", "kind": "int", "default": 3, "min": 0, "max": 100, "label": "Tiles", "show_if": {"key": "direction", "equals": ["down", "left", "right", "up"]}},
			{"key": "speed", "kind": "int", "default": 4, "min": 1, "max": 6, "label": "Speed", "show_if": {"key": "direction", "equals": ["down", "left", "right", "up", "return"]}},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done", "show_if": {"key": "direction", "equals": ["down", "left", "right", "up", "return"]}},
		],
	}


func summary(args: Dictionary) -> String:
	match str(args.get("direction", "down")):
		"return":
			return "Scroll Map: return to player"
		"lock":
			return "Scroll Map: lock the camera"
		"unlock":
			return "Scroll Map: unlock the camera"
	return "Scroll Map: %s %d" % [args.get("direction", "down"), int(args.get("distance", 3))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null or m.player == null:
		return RPGResult.ok()
	var p: RPGPlayer = m.player
	var direction := str(args.get("direction", "down"))
	if direction == "lock":
		p.lock_camera()
		return RPGResult.ok()
	if direction == "unlock":
		p.unlock_camera()
		return RPGResult.ok()
	# Pan speeds are the character speeds (1..6) in tiles per second.
	var px_per_sec: float = m.tile_size * RPGCharacter.SPEEDS[clampi(int(args.speed), 1, 6)]
	if direction == "return":
		p.queue_pan_to_center(px_per_sec)
	else:
		p.queue_pan(RPGMovement.dir_vec(direction) * int(args.distance) * m.tile_size, px_per_sec)
	if args.wait:
		# Pans queue up, so waiting means the whole queue settles: the longest pending pan.
		while p.camera_panning():
			if not await ctx.wait_frames(1):
				return RPGResult.cancelled()
	return RPGResult.ok()
