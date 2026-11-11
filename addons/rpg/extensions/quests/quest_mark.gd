extends Control
## A small objective mark drawn with lines, so it looks the same with any font: an empty box
## (open), a green check mark (completed) or a red cross (failed).

const OPEN := Color(1, 1, 1, 0.85)
const DONE := Color(0.45, 1.0, 0.45)
const FAILED := Color(1.0, 0.42, 0.42)

var state := "shown":
	set(v):
		state = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var r := Rect2(Vector2.ZERO, Vector2(s, s))
	var shadow := Color(0, 0, 0, 0.6)
	match state:
		"completed":
			var pts := PackedVector2Array([Vector2(s * 0.08, s * 0.55), Vector2(s * 0.4, s * 0.88), Vector2(s * 0.95, s * 0.1)])
			draw_polyline(_shift(pts), shadow, 2.0)
			draw_polyline(pts, DONE, 2.0)
		"failed":
			for pair in [[Vector2(s * 0.12, s * 0.12), Vector2(s * 0.88, s * 0.88)], [Vector2(s * 0.88, s * 0.12), Vector2(s * 0.12, s * 0.88)]]:
				draw_line(pair[0] + Vector2.ONE, pair[1] + Vector2.ONE, shadow, 2.0)
				draw_line(pair[0], pair[1], FAILED, 2.0)
		_:
			draw_rect(Rect2(r.position + Vector2.ONE, r.size), shadow, false, 1.0)
			draw_rect(r, OPEN, false, 1.0)


func _shift(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + Vector2.ONE)
	return out
