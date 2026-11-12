@tool
class_name RPGMovement
extends RefCounted
## One movement controller for the player, followers and events. Each step checks map bounds and
## looping, passage out of the current tile and into the next (by direction), tile flags, whether
## the next cell is occupied, and reservations held by steps already in progress.
##
## Passage bits on a tile say which of its edges are open: 1 down, 2 left, 4 right, 8 up.
## Moving A -> B in direction d needs A's d edge and B's opposite edge open.

const RPGVehicles := preload("res://addons/rpg/runtime/rpg_vehicles.gd")
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)
const UP := Vector2i(0, -1)
const DIRS := {"down": DOWN, "left": LEFT, "right": RIGHT, "up": UP}
const BIT := {"down": 1, "left": 2, "right": 4, "up": 8}
const OPPOSITE := {"down": "up", "up": "down", "left": "right", "right": "left"}

const FLAG_BUSH := 1
const FLAG_COUNTER := 2
const FLAG_LADDER := 4
const FLAG_DAMAGE := 8
const FLAG_STAR := 16
const FLAG_WALL := 32
const FLAG_EDGE := 64  # see RPGTilesetBuilder.FLAG_EDGE

var map: Node
## cell -> character holding a reservation
var reservations: Dictionary = {}
## Diagonal steps may cut corners only when this is true.
var allow_corner_cutting := false


func _init(p_map: Node) -> void:
	map = p_map


static func dir_name(v: Vector2i) -> String:
	if v.y > 0 and v.x == 0: return "down"
	if v.y < 0 and v.x == 0: return "up"
	if v.x < 0 and v.y == 0: return "left"
	if v.x > 0 and v.y == 0: return "right"
	return ""


static func dir_vec(name: String) -> Vector2i:
	return DIRS.get(name, Vector2i.ZERO)


func size() -> Vector2i:
	return map.size


func loops_h() -> bool:
	return map.scroll_type in ["loop_h", "loop_both"]


func loops_v() -> bool:
	return map.scroll_type in ["loop_v", "loop_both"]


## Wraps a cell on looping maps; returns Vector2i(-1, -1) when off the map.
func normalize(cell: Vector2i) -> Vector2i:
	var s := size()
	var c := cell
	if loops_h():
		c.x = posmod(c.x, s.x)
	if loops_v():
		c.y = posmod(c.y, s.y)
	if c.x < 0 or c.y < 0 or c.x >= s.x or c.y >= s.y:
		return Vector2i(-1, -1)
	return c


func in_bounds(cell: Vector2i) -> bool:
	return normalize(cell) != Vector2i(-1, -1)


## Passage bits for a cell. On a map with a Navigation layer (image-backed maps) the layer's mask
## decides, and a cell without a mask tile is blocked; visible tiles then only supply flags and
## terrain. Otherwise the top layer that is not empty and not a star tile decides.
func passage(cell: Vector2i) -> int:
	var nav: Variant = map.get("navigation")
	if nav is TileMapLayer and is_instance_valid(nav):
		var nl: TileMapLayer = nav
		if nl.get_cell_source_id(cell) < 0:
			return 0
		return nl.get_cell_atlas_coords(cell).x & 15
	var layers: Array = map.tile_layers
	if layers.is_empty():
		return 15
	for i in range(layers.size() - 1, -1, -1):
		var layer: TileMapLayer = layers[i]
		var td := layer.get_cell_tile_data(cell)
		if td == null:
			continue
		var flags := _custom_int(td, "flags", 0)
		if flags & FLAG_STAR:
			continue
		var p := _custom_int(td, "passage", 15)
		if flags & FLAG_EDGE:
			p &= _open_edges(layer, cell, td)
		return p
	# Every layer empty: blocked (unless the map has no tiles at all, handled above).
	return 0 if _any_layer_used(layers) else 15


## For FLAG_EDGE tiles: the edges whose neighbour (same layer) is the same tile kind, as RPG
## Maker MV's autotile shapes do. Off the map counts as the same kind, as in MV.
func _open_edges(layer: TileMapLayer, cell: Vector2i, td: TileData) -> int:
	var key: Variant = td.get_custom_data("tile_key") if layer.tile_set and layer.tile_set.get_custom_data_layer_by_name("tile_key") >= 0 else null
	var open := 0
	for d in DIRS:
		var n: Vector2i = cell + DIRS[d]
		if not in_bounds(n):
			open |= BIT[d]
			continue
		var ntd := layer.get_cell_tile_data(n)
		if ntd != null and key != null and ntd.get_custom_data("tile_key") == key:
			open |= BIT[d]
	return open


## Cached: get_used_cells() allocates, and passage() runs for every step and overlay cell.
## Call invalidate() after painting (the editor builds a fresh RPGMovement per check).
var _layers_used := -1


func _any_layer_used(layers: Array) -> bool:
	if _layers_used < 0:
		_layers_used = 0
		for l in layers:
			if l.get_used_cells().size() > 0:
				_layers_used = 1
				break
	return _layers_used == 1


func invalidate() -> void:
	_layers_used = -1


## OR of the flags of every tile in the cell.
func flags(cell: Vector2i) -> int:
	var f := 0
	for layer in map.tile_layers:
		var td: TileData = layer.get_cell_tile_data(cell)
		if td != null:
			f |= _custom_int(td, "flags", 0)
	return f


func terrain(cell: Vector2i) -> int:
	var layers: Array = map.tile_layers
	for i in range(layers.size() - 1, -1, -1):
		var td: TileData = layers[i].get_cell_tile_data(cell)
		if td != null:
			var t := _custom_int(td, "terrain", 0)
			if t != 0:
				return t
	return 0


static func _custom_int(td: TileData, layer_name: String, fallback: int) -> int:
	if td == null or not td.has_custom_data(layer_name):
		return fallback
	var v: Variant = td.get_custom_data(layer_name)
	return int(v) if v != null else fallback


## Whether `ch` may step from `from` in direction `dir` (one of the 8 unit vectors).
func can_move(ch: Node, from: Vector2i, dir: Vector2i) -> bool:
	return check_move(ch, from, dir) == ""


## Returns "" when the step is allowed, otherwise why it is blocked (for the debug inspector).
func check_move(ch: Node, from: Vector2i, dir: Vector2i) -> String:
	if ch != null and "vehicle" in ch and str(ch.vehicle) != "" and not ch.debug_through():
		return RPGVehicles.check_move(self, str(ch.vehicle), ch, from, dir)
	var to := normalize(from + dir)
	if to == Vector2i(-1, -1):
		return "edge of map"
	var through: bool = ch != null and (ch.through or (ch.has_method("debug_through") and ch.debug_through()))
	if dir.x != 0 and dir.y != 0:
		var hx := Vector2i(dir.x, 0)
		var vy := Vector2i(0, dir.y)
		if not through and not allow_corner_cutting:
			if check_move(ch, from, hx) != "" or check_move(ch, from + hx, vy) != "":
				if check_move(ch, from, vy) != "" or check_move(ch, from + vy, hx) != "":
					return "corner"
			if check_move(ch, from, hx) != "" or check_move(ch, from, vy) != "":
				return "corner"
		if not through and is_occupied(to, ch):
			return "occupied"
		return ""
	if through:
		return ""
	var d := dir_name(dir)
	if (passage(from) & BIT[d]) == 0:
		return "cannot leave tile %s going %s" % [from, d]
	if (passage(to) & BIT[OPPOSITE[d]]) == 0:
		return "tile %s is not passable from the %s" % [to, OPPOSITE[d]]
	if is_occupied(to, ch):
		return "occupied"
	return ""


## Occupied: the cell holds (or is reserved by) the player, a follower, or an event whose
## priority is "same as characters". Below/above events never block.
func is_occupied(cell: Vector2i, except: Node = null) -> bool:
	var c := normalize(cell)
	if except != null and except.priority != "same":
		return false
	var r: Node = reservations.get(c)
	if r != null and r != except and is_instance_valid(r) and r.blocks():
		return true
	for other in map.characters():
		if other == except or not is_instance_valid(other):
			continue
		if not other.blocks():
			continue
		if other.cell == c:
			return true
	return false


func occupant(cell: Vector2i, except: Node = null) -> Node:
	var c := normalize(cell)
	for other in map.characters():
		if other != except and other.blocks() and other.cell == c:
			return other
	return null


func reserve(ch: Node, cell: Vector2i) -> void:
	reservations[normalize(cell)] = ch


func release(ch: Node, cell: Vector2i) -> void:
	var c := normalize(cell)
	if reservations.get(c) == ch:
		reservations.erase(c)


## Nearest free cell within `max_dist` (for transfers that opt in to a fallback).
func nearest_free(cell: Vector2i, ch: Node, max_dist := 3) -> Vector2i:
	if in_bounds(cell) and not is_occupied(cell, ch) and passage(cell) != 0:
		return cell
	for d in range(1, max_dist + 1):
		for y in range(-d, d + 1):
			for x in range(-d, d + 1):
				if absi(x) != d and absi(y) != d:
					continue
				var c := cell + Vector2i(x, y)
				if in_bounds(c) and not is_occupied(c, ch) and passage(c) != 0:
					return c
	return Vector2i(-1, -1)
