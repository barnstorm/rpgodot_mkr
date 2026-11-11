@tool
class_name RPGRoutePreview
extends RefCounted
## Traces a move route on the grid for the editor's Preview button: the cells a character would
## visit, ignoring collisions (the editor cannot know where the player or other events will be).
## Random and player-relative steps cannot be predicted; they are reported as `unknown` and the
## trace stops there.

const DIRS := {"down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT, "up": Vector2i.UP,
	"lower_left": Vector2i(-1, 1), "lower_right": Vector2i(1, 1), "upper_left": Vector2i(-1, -1), "upper_right": Vector2i(1, -1)}


## route: an Array of steps or {steps, repeat?, ...}. Returns {cells: Array[Vector2i] (start
## included), facing: String, unknown: String (first unpredictable step, or "")}.
static func trace(start: Vector2i, facing: String, route: Variant) -> Dictionary:
	var steps: Array = route.get("steps", []) if route is Dictionary else (route if route is Array else [])
	var cells: Array[Vector2i] = [start]
	var cell := start
	var face := facing if DIRS.has(facing) else "down"
	for s in steps:
		if not (s is Dictionary):
			continue
		if s.has("step"):
			var name := str(s.step)
			var d := Vector2i.ZERO
			if DIRS.has(name):
				d = DIRS[name]
				if not name.contains("_"):
					face = name
			elif name == "forward":
				d = DIRS[face]
			elif name == "backward":
				d = -DIRS[face]
			else:
				return {"cells": cells, "facing": face, "unknown": name}
			cell += d
			cells.append(cell)
		elif s.has("jump"):
			var j: Array = s.jump
			cell += Vector2i(int(j[0]), int(j[1]))
			cells.append(cell)
		elif s.has("turn"):
			var t := str(s.turn)
			match t:
				"left_90": face = {"down": "right", "right": "up", "up": "left", "left": "down"}[face]
				"right_90": face = {"down": "left", "left": "up", "up": "right", "right": "down"}[face]
				"around": face = {"down": "up", "up": "down", "left": "right", "right": "left"}[face]
				_:
					if DIRS.has(t) and not t.contains("_"):
						face = t
					else:
						return {"cells": cells, "facing": face, "unknown": "turn " + t}
	return {"cells": cells, "facing": face, "unknown": ""}
