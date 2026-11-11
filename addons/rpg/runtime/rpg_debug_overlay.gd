extends Node2D
## Playtest overlay (F7): passability arrows, regions and terrain tags drawn over the map.
## Catches most "why can't I walk here" problems.

var map: RPGMap


func _ready() -> void:
	z_index = 90
	z_as_relative = false
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if map == null or map.movement == null:
		return
	var ts: int = map.tile_size
	var font := ThemeDB.fallback_font
	var cam := get_viewport().get_camera_2d()
	var center: Vector2 = cam.get_screen_center_position() if cam else Vector2(160, 120)
	var x0 := maxi(0, int((center.x - 170) / ts))
	var y0 := maxi(0, int((center.y - 130) / ts))
	for y in range(y0, mini(map.size.y, y0 + 17)):
		for x in range(x0, mini(map.size.x, x0 + 22)):
			var c := Vector2i(x, y)
			var p := Vector2(x * ts, y * ts)
			var bits: int = map.movement.passage(c)
			if bits == 0:
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(ts - 2, ts - 2)), Color(1, 0, 0, 0.35))
			elif bits != 15:
				var mid := p + Vector2(ts / 2.0, ts / 2.0)
				for dn in ["down", "left", "right", "up"]:
					if bits & RPGMovement.BIT[dn] == 0:
						var d := Vector2(RPGMovement.DIRS[dn])
						draw_line(mid + d * (ts / 2.0 - 1) + Vector2(d.y, d.x) * 5, mid + d * (ts / 2.0 - 1) - Vector2(d.y, d.x) * 5, Color(1, 0.3, 0.2, 0.9), 2)
			var r := map.region_at(c)
			if r > 0:
				draw_rect(Rect2(p, Vector2(ts, ts)), Color.from_hsv(fmod(r * 0.137, 1.0), 0.7, 1.0, 0.3))
				draw_string(font, p + Vector2(1, 7), str(r), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
			var t := map.terrain_at(c)
			if t > 0:
				draw_string(font, p + Vector2(ts - 6, ts - 1), str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.YELLOW)
	for ev in map.characters():
		if ev is RPGEvent and ev.page_index >= 0:
			var ep := Vector2(ev.cell * ts)
			draw_rect(Rect2(ep, Vector2(ts, ts)), Color(0.3, 0.6, 1, 0.9), false, 1)
