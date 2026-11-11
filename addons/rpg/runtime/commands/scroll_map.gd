@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "scroll_map", "schema_version": 1, "category": "movement", "label": "Scroll Map",
		"fields": [
			{"key": "direction", "kind": "choice", "options": ["down", "left", "right", "up", "return"], "default": "down", "label": "Direction"},
			{"key": "distance", "kind": "int", "default": 3, "min": 0, "max": 100, "label": "Tiles"},
			{"key": "speed", "kind": "int", "default": 4, "min": 1, "max": 6, "label": "Speed"},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until done"},
		],
	}


func summary(args: Dictionary) -> String:
	if args.get("direction", "") == "return":
		return "Scroll Map: return to player"
	return "Scroll Map: %s %d" % [args.get("direction", "down"), int(args.get("distance", 3))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var m: Node = ctx.map
	if m == null or m.player == null:
		return RPGResult.ok()
	var cam: Camera2D = m.player.camera
	var target := Vector2(0, -m.tile_size / 2.0)
	if args.direction != "return":
		target = cam.position + Vector2(RPGMovement.dir_vec(args.direction) * int(args.distance) * m.tile_size)
	var tiles_per_sec: float = RPGCharacter.SPEEDS[clampi(int(args.speed), 1, 6)]
	var secs: float = cam.position.distance_to(target) / (m.tile_size * tiles_per_sec)
	var t := cam.create_tween()
	t.tween_property(cam, "position", target, maxf(secs, 0.01))
	if args.wait:
		var r := await ctx.wait_signal(t.finished)
		if not r.ok:
			return RPGResult.cancelled()
	return RPGResult.ok()
