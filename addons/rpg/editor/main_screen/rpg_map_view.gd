@tool
class_name RPGMapView
extends SubViewportContainer
## The map being edited, drawn in a SubViewport with overlays on top.
## Map mode paints tiles (pencil, rectangle, ellipse, fill, shadow pen) with RPG Maker autotiling;
## Region mode paints region numbers; Event mode selects, moves and opens events.
## Right-click copies a tile, right-drag copies an area (eyedropper); Shift places an autotile
## without connecting it (or draws a shadow rectangle with the shadow pen).
## Every stroke is one undo step (layer data snapshots), joining Godot's undo history.
## VX Ace / MV overlay autotiles painted on Layer 1 keep their base on the map's hidden
## Layer1Base (RPGAutotile); the eyedropper picks the visible overlay, erasing it shows the base.

signal cell_hovered(cell: Vector2i)
signal event_activated(event_id: String)
signal event_context(event_id: String, cell: Vector2i, screen_pos: Vector2)
signal map_context(cell: Vector2i, screen_pos: Vector2)
## Double-click on an empty tile in Event mode: make a new event there (as in RPG Maker).
signal new_event_requested(cell: Vector2i)
signal selection_changed(event_id: String)
signal brush_picked(brush: Dictionary)
signal modified()
signal events_modified()

const ERASER_KEY := "upper_0"

var data: RPGProjectData
var undo: RPGUndo                       # wraps EditorUndoRedoManager or UndoRedo
var viewport: SubViewport
var world: Node2D
var overlay: Node2D
var map_node: RPGMap
var map_id := ""
var props: Dictionary = {}
var events_file: Dictionary = {}
var tile_size := 16
var map_size := Vector2i(20, 15)

var mode := "map"            # map | event | region
var tool := "pencil"         # pencil | rect | ellipse | fill | shadow
var layer_mode := 0          # 0 auto, 1..4 explicit
var brush: Dictionary = {}
var zoom := 2.0
var show_grid := false
var show_passability := false
var show_regions := false
var show_terrain := false
var start_pos: Dictionary = {}
var selected_event := ""
var hover_cell := Vector2i(-1, -1)

var _stroke_before: Dictionary = {}
var _painting := false
var _drag_from := Vector2i(-1, -1)
var _right_from := Vector2i(-1, -1)
var _moving_event := ""
var _move_from := Vector2i.ZERO
var _panning := false
var _event_tex_cache: Dictionary = {}
var dirty := false


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.transparent_bg = false
	add_child(viewport)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.11)
	bg.size = Vector2(8192, 8192)
	bg.position = Vector2(-4096, -4096)
	viewport.add_child(bg)
	world = Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	overlay = Node2D.new()
	overlay.name = "Overlay"
	overlay.z_index = 200
	overlay.z_as_relative = false
	overlay.draw.connect(_draw_overlay)
	world.add_child(overlay)
	world.scale = Vector2(zoom, zoom)
	world.position = Vector2(16, 16)


# --- opening and saving ----------------------------------------------------------------------

func open_map(p_data: RPGProjectData, id: String) -> void:
	data = p_data
	close_map()
	map_id = id
	tile_size = data.tile_size()
	props = data.map_props(id).duplicate(true)
	map_size = Vector2i(int(props.get("width", 20)), int(props.get("height", 15)))
	map_node = RPGMapFiles.load_map(data, id)
	world.add_child(map_node)
	world.move_child(overlay, -1)
	if tile_set() != null:
		tile_size = tile_set().tile_size.x  # the TileSet's profile decides (16/32/48)
	for c in map_node.get_children():
		if c is TileMapLayer:
			c.set_meta(RPGAutotile.MAP_SIZE_META, map_size)
	if map_node.regions:
		map_node.regions.visible = mode == "region" or show_regions
	events_file = RPGMapFiles.load_events_file(data, id)
	start_pos = data.system.get("start", {})
	selected_event = ""
	dirty = false
	_event_tex_cache.clear()
	_update_layer_dimming()
	overlay.queue_redraw()


func close_map() -> void:
	if map_node != null:
		map_node.queue_free()
		map_node = null
	map_id = ""
	# Nothing of the closed map may linger in the overlay (grid, events, start marker).
	map_size = Vector2i.ZERO
	events_file = {}
	selected_event = ""
	hover_cell = Vector2i(-1, -1)
	route_preview = {}
	dirty = false
	overlay.queue_redraw()


func save() -> Error:
	if map_node == null:
		return OK
	var err := RPGMapFiles.save_scene(map_node, data.map_scene_path(map_id))
	if err == OK:
		dirty = false
	return err


## After the map grew from `old_size`: autotiles on the old right and bottom edges were joined
## to the map edge; recompute them (and the new cells next to them) against the new neighbours.
func rejoin_edges(old_size: Vector2i) -> void:
	for l in tile_layers():
		if map_size.x > old_size.x:
			RPGAutotile.refresh_rect(l, Rect2i(old_size.x - 1, 0, 2, map_size.y))
		if map_size.y > old_size.y:
			RPGAutotile.refresh_rect(l, Rect2i(0, old_size.y - 1, map_size.x, 2))


func tile_layers() -> Array:
	return map_node.tile_layers if map_node else []


func tile_set() -> TileSet:
	var ls := tile_layers()
	return ls[0].tile_set if not ls.is_empty() else null


# --- view --------------------------------------------------------------------------------------

## Zoom that shows the map at the size the game draws it (tileset pixels x the project's scale:
## 16 px art in a 48 px MV-style project is drawn 3x).
func game_zoom() -> float:
	if data == null or tile_size <= 0:
		return 1.0
	return maxf(1.0, float(data.tile_size()) / tile_size)


## Zooms around `anchor` (view pixels; the middle of the view by default), keeping the map in view.
func set_zoom(z: float, anchor := Vector2(-1, -1)) -> void:
	var old := zoom
	zoom = clampf(z, 0.5, 8.0)
	var center := anchor if anchor.x >= 0 else size / 2.0
	var world_center := (center - world.position) / old
	world.scale = Vector2(zoom, zoom)
	world.position = center - world_center * zoom
	clamp_pan()
	overlay.queue_redraw()


## Keeps the map on screen: a map smaller than the view is centred, a larger one can't be
## scrolled further than a margin past its edges.
func clamp_pan() -> void:
	if size.x <= 0 or size.y <= 0 or map_size == Vector2i.ZERO:
		return
	var px := Vector2(map_size * tile_size) * zoom
	var margin := 32.0
	for axis in 2:
		if px[axis] + margin * 2 <= size[axis]:
			world.position[axis] = roundf((size[axis] - px[axis]) / 2.0)
		else:
			world.position[axis] = clampf(world.position[axis], size[axis] - px[axis] - margin, margin)


func set_mode(m: String) -> void:
	mode = m
	if map_node and map_node.regions:
		map_node.regions.visible = m == "region" or show_regions
	_update_layer_dimming()
	overlay.queue_redraw()


func set_layer_mode(l: int) -> void:
	layer_mode = l
	_update_layer_dimming()


## Explicit layer mode edits one layer and dims the rest (RPG Maker XP/MZ style).
func _update_layer_dimming() -> void:
	var ls := tile_layers()
	for i in ls.size():
		var dim := mode == "map" and layer_mode != 0 and layer_mode != i + 1
		ls[i].modulate = Color(1, 1, 1, 0.35) if dim else Color.WHITE
	if map_node != null and map_node.base_layer != null and not ls.is_empty():
		map_node.base_layer.modulate = ls[0].modulate


func to_cell(local: Vector2) -> Vector2i:
	var w := (local - world.position) / zoom
	return Vector2i(floori(w.x / tile_size), floori(w.y / tile_size))


func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_size.x and c.y < map_size.y


# --- input -------------------------------------------------------------------------------------

## Location picking for forms: while set, the next left click on a cell calls it with
## (map_id, cell) instead of painting; Esc or right click calls it with ("", (-1, -1)).
var pick_callback: Callable
## Route preview drawn on the overlay ({cells, unknown}); cleared by the next click or after a while.
var route_preview: Dictionary = {}


func _gui_input(event: InputEvent) -> void:
	if map_node == null:
		return
	if pick_callback.is_valid() and _pick_input(event):
		accept_event()
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_mouse_motion(event)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE and mode == "event" and selected_event != "":
			delete_event(selected_event)
			accept_event()


func _pick_input(event: InputEvent) -> bool:
	var cb := pick_callback
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := to_cell(event.position)
		if in_map(cell):
			pick_callback = Callable()
			cb.call(map_id, cell)
		return true
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		pick_callback = Callable()
		cb.call("", Vector2i(-1, -1))
		return true
	if event is InputEventMouseMotion:
		_mouse_motion(event)
	return event is InputEventMouseButton


func _mouse_button(e: InputEventMouseButton) -> void:
	var cell := to_cell(e.position)
	if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		if e.ctrl_pressed:
			set_zoom(zoom * 1.25, e.position)
		else:
			world.position += Vector2(40, 0) if e.shift_pressed else Vector2(0, 40)
			clamp_pan()
			overlay.queue_redraw()
		accept_event()
		return
	if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		if e.ctrl_pressed:
			set_zoom(zoom / 1.25, e.position)
		else:
			world.position -= Vector2(40, 0) if e.shift_pressed else Vector2(0, 40)
			clamp_pan()
			overlay.queue_redraw()
		accept_event()
		return
	if e.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = e.pressed
		accept_event()
		return
	grab_focus()
	match mode:
		"event":
			_event_mouse(e, cell)
		_:
			_paint_mouse(e, cell)
	accept_event()


func _mouse_motion(e: InputEventMouseMotion) -> void:
	if _panning:
		world.position += e.relative
		clamp_pan()
		overlay.queue_redraw()
		return
	var cell := to_cell(e.position)
	if cell != hover_cell:
		hover_cell = cell
		cell_hovered.emit(cell)
		if _painting and mode != "event" and (tool == "pencil" or (tool == "shadow" and not e.shift_pressed)):
			_apply_at(cell, e.shift_pressed, e.position)
		if _moving_event != "" and in_map(cell):
			_set_event_position_live(_moving_event, cell)
		overlay.queue_redraw()


# --- painting -------------------------------------------------------------------------------------

func _paint_mouse(e: InputEventMouseButton, cell: Vector2i) -> void:
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if e.pressed:
			_right_from = cell
		elif _right_from != Vector2i(-1, -1):
			_eyedropper(_right_from, cell)
			_right_from = Vector2i(-1, -1)
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		_begin_stroke()
		_painting = true
		_drag_from = cell
		if tool == "pencil" or (tool == "shadow" and not e.shift_pressed):
			_apply_at(cell, e.shift_pressed, e.position)
		elif tool == "fill":
			_fill(cell)
			_painting = false
			_end_stroke("Fill")
	else:
		if not _painting:
			return
		_painting = false
		if tool in ["rect", "ellipse"] or (tool == "shadow" and e.shift_pressed):
			_apply_shape(_drag_from, cell, e.shift_pressed)
		_end_stroke({"pencil": "Paint", "rect": "Rectangle", "ellipse": "Ellipse", "shadow": "Shadow"}.get(tool, "Paint"))
		_drag_from = Vector2i(-1, -1)
		overlay.queue_redraw()


func _all_paint_layers() -> Array:
	var out: Array = tile_layers().duplicate()
	if map_node.base_layer != null:
		out.append(map_node.base_layer)
	if map_node.shadows:
		out.append(map_node.shadows)
	if map_node.regions:
		out.append(map_node.regions)
	return out


func _begin_stroke() -> void:
	# Overlay autotiles (VX Ace / MV deep sea, bushes ...) keep their base on a hidden layer; it
	# must exist before the snapshot so undo covers it.
	var ts := tile_set()
	if ts != null and not (ts.get_meta(RPGAutotile.OVERLAY_META, {}) as Dictionary).is_empty():
		map_node.ensure_base_layer()
	_stroke_before.clear()
	for l in _all_paint_layers():
		_stroke_before[l] = l.tile_map_data


func _end_stroke(action_name: String) -> void:
	var after := {}
	var changed := false
	for l in _stroke_before:
		after[l] = l.tile_map_data
		if after[l] != _stroke_before[l]:
			changed = true
	if not changed:
		return
	_register_undo("RPG: " + action_name, _stroke_before.duplicate(), after)
	dirty = true
	modified.emit()


func _register_undo(action_name: String, before: Dictionary, after: Dictionary) -> void:
	if undo == null:
		return
	undo.create_action(action_name)
	for l in after:
		undo.add_do_property(l, "tile_map_data", after[l])
		undo.add_undo_property(l, "tile_map_data", before[l])
	undo.add_do_method(self, "_after_undo_redo")
	undo.add_undo_method(self, "_after_undo_redo")
	undo.commit_action(false)


func _after_undo_redo() -> void:
	dirty = true
	modified.emit()
	overlay.queue_redraw()


## Which TileMapLayer a brush cell goes to.
func target_layer(source_id: int) -> TileMapLayer:
	var ls := tile_layers()
	if ls.is_empty():
		return null
	var idx := (layer_mode - 1) if layer_mode > 0 else (RPGTilesetBuilder.default_layer_for(source_id) - 1)
	return ls[clampi(idx, 0, ls.size() - 1)]


func _is_eraser(source_id: int, coords: Vector2i) -> bool:
	return source_id == RPGTilesetBuilder.SOURCE_UPPER and coords == Vector2i.ZERO


func _apply_at(cell: Vector2i, shift: bool, local_pos: Vector2) -> void:
	if not in_map(cell):
		return
	if mode == "region":
		_paint_region(cell)
		return
	if tool == "shadow":
		var w := (local_pos - world.position) / zoom
		var qx := 1 if fmod(w.x, tile_size) >= tile_size / 2.0 else 0
		var qy := 1 if fmod(w.y, tile_size) >= tile_size / 2.0 else 0
		var bit: int = [RPGAutotile.SHADOW_TL, RPGAutotile.SHADOW_TR, RPGAutotile.SHADOW_BL, RPGAutotile.SHADOW_BR][qy * 2 + qx]
		var cur := RPGAutotile.get_shadow(map_node.shadows, cell)
		RPGAutotile.set_shadow(map_node.shadows, cell, cur ^ bit)
		return
	stamp(cell, shift)


## Paints the current brush with its top-left at `cell`.
func stamp(cell: Vector2i, no_connect := false) -> void:
	if brush.get("kind", "") != "tiles":
		return
	for b in brush.cells:
		var c: Vector2i = cell + b.offset
		if in_map(c):
			paint_cell(c, b.source, b.coords, not no_connect)


func paint_cell(c: Vector2i, source_id: int, coords: Vector2i, connect := true) -> void:
	var layer := target_layer(source_id)
	if layer == null:
		return
	var was_wall := RPGAutotile.is_wall(tile_layers(), c)
	if _is_eraser(source_id, coords):
		if layer_mode == 0:
			# Auto layer: the eraser clears the upper layer first, then the lower one.
			var ls := tile_layers()
			var cleared := false
			for i in range(ls.size() - 1, -1, -1):
				if ls[i].get_cell_source_id(c) != -1:
					RPGAutotile.erase(ls[i], c)
					cleared = true
					break
			if not cleared:
				return
		else:
			RPGAutotile.erase(layer, c)
	else:
		RPGAutotile.paint(layer, c, source_id, coords, connect)
	# Auto shadows only follow walls: painting floor must not wipe hand-drawn shadows.
	if map_node.shadows and RPGAutotile.is_wall(tile_layers(), c) != was_wall:
		RPGAutotile.update_auto_shadows_around(tile_layers(), map_node.shadows, c)


func _paint_region(c: Vector2i) -> void:
	var n := int(brush.get("region", 0)) if brush.get("kind", "") == "region" else 0
	if n <= 0:
		map_node.regions.erase_cell(c)
	else:
		map_node.regions.set_cell(c, 0, Vector2i(n % 16, n / 16))


func _shape_cells(a: Vector2i, b: Vector2i, ellipse: bool) -> Array:
	var tl := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var br := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var out := []
	var cx := (tl.x + br.x) / 2.0
	var cy := (tl.y + br.y) / 2.0
	var rx := (br.x - tl.x) / 2.0 + 0.5
	var ry := (br.y - tl.y) / 2.0 + 0.5
	for y in range(tl.y, br.y + 1):
		for x in range(tl.x, br.x + 1):
			if ellipse:
				var dx := (x - cx) / rx
				var dy := (y - cy) / ry
				if dx * dx + dy * dy > 1.0:
					continue
			out.append(Vector2i(x, y))
	return out


func _apply_shape(a: Vector2i, b: Vector2i, shift: bool) -> void:
	if tool == "shadow":
		for c in _shape_cells(a, b, false):
			if in_map(c):
				var cur := RPGAutotile.get_shadow(map_node.shadows, c)
				RPGAutotile.set_shadow(map_node.shadows, c, 0 if cur == 15 else 15)
		return
	var cells := _shape_cells(a, b, tool == "ellipse")
	if mode == "region":
		for c in cells:
			if in_map(c):
				_paint_region(c)
		return
	if brush.get("kind", "") != "tiles":
		return
	var bsize: Vector2i = brush.get("size", Vector2i.ONE)
	var tl := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	for c in cells:
		if not in_map(c):
			continue
		# Tile the stamp across the shape.
		var off := Vector2i(posmod(c.x - tl.x, bsize.x), posmod(c.y - tl.y, bsize.y))
		for bc in brush.cells:
			if bc.offset == off:
				paint_cell(c, bc.source, bc.coords, not shift)


## Flood fill of the contiguous area that has the same tile as the clicked cell on the target layer.
func _fill(start: Vector2i) -> void:
	if not in_map(start):
		return
	if mode == "region":
		var target_r := map_node.region_at(start)
		_flood(start, func(c): return map_node.region_at(c) == target_r, func(c): _paint_region(c))
		return
	if brush.get("kind", "") != "tiles" or brush.cells.is_empty():
		return
	var b: Dictionary = brush.cells[0]
	var eraser := _is_eraser(b.source, b.coords)
	var layer := target_layer(b.source)
	if eraser and layer_mode == 0:
		# Auto layer: erase the region on the topmost layer that has a tile at the start cell.
		layer = null
		var ls := tile_layers()
		for i in range(ls.size() - 1, -1, -1):
			if ls[i].get_cell_source_id(start) != -1:
				layer = ls[i]
				break
	if layer == null:
		return
	var src0 := layer.get_cell_source_id(start)
	if eraser and src0 == -1:
		return
	var grp0 := RPGAutotile.group_of(layer, start)
	var at0 := layer.get_cell_atlas_coords(start)
	var same := func(c: Vector2i) -> bool:
		# Autotiles match by group: a 2000/2003 water cell may sit on the blend source.
		if grp0 >= 0:
			return RPGAutotile.group_of(layer, c) == grp0
		if layer.get_cell_source_id(c) != src0:
			return false
		return layer.get_cell_atlas_coords(c) == at0
	var cells := []
	_flood(start, same, func(c): cells.append(c))
	var walls := {}
	for c in cells:
		walls[c] = RPGAutotile.is_wall(tile_layers(), c)
	if eraser:
		for c in cells:
			RPGAutotile.erase(layer, c)
	else:
		# Autotiles and plain tiles alike: neighbours reconnect and hidden bases follow.
		RPGAutotile.paint_cells(layer, cells, b.source, b.coords)
	# Only cells whose wall status changed move auto shadows; hand-drawn ones elsewhere stay.
	if map_node.shadows:
		for c in cells:
			if RPGAutotile.is_wall(tile_layers(), c) != walls[c]:
				RPGAutotile.update_auto_shadows_around(tile_layers(), map_node.shadows, c)


func _flood(start: Vector2i, same: Callable, act: Callable) -> void:
	var seen := {start: true}
	var stack := [start]
	var count := 0
	while not stack.is_empty() and count < 100000:
		var c: Vector2i = stack.pop_back()
		if not same.call(c):
			continue
		act.call(c)
		count += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if in_map(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)


## Right-click copies a tile; right-drag copies an area (top non-empty layer per cell, or the
## selected layer). The copy becomes the brush.
func _eyedropper(a: Vector2i, b: Vector2i) -> void:
	if mode == "region":
		var n := map_node.region_at(a)
		brush = {"kind": "region", "region": n}
		brush_picked.emit(brush)
		return
	var tl := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var br := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var cells := []
	var ls := tile_layers()
	for y in range(tl.y, br.y + 1):
		for x in range(tl.x, br.x + 1):
			var c := Vector2i(x, y)
			var picked := false
			var order: Array = range(ls.size() - 1, -1, -1) if layer_mode == 0 else [layer_mode - 1]
			for i in order:
				var l: TileMapLayer = ls[i]
				var sid := l.get_cell_source_id(c)
				if sid != -1:
					# Autotiles: the palette tile of the group (also for a 2000/2003 water blend tile).
					var pal := RPGAutotile.palette_tile(l.tile_set, sid, l.get_cell_atlas_coords(c))
					cells.append({"offset": c - tl, "source": int(pal[0]), "coords": pal[1]})
					picked = true
					break
			if not picked:
				cells.append({"offset": c - tl, "source": RPGTilesetBuilder.SOURCE_UPPER, "coords": Vector2i.ZERO})
	brush = {"kind": "tiles", "size": br - tl + Vector2i.ONE, "cells": cells}
	brush_picked.emit(brush)


# --- events ---------------------------------------------------------------------------------------

func events() -> Array:
	return events_file.get("events", [])


func event_at(c: Vector2i) -> Dictionary:
	for ev in events():
		var p: Array = ev.get("position", [0, 0])
		if int(p[0]) == c.x and int(p[1]) == c.y:
			return ev
	return {}


func find_event(id: String) -> Dictionary:
	for ev in events():
		if ev.get("id", "") == id:
			return ev
	return {}


func _event_mouse(e: InputEventMouseButton, cell: Vector2i) -> void:
	var ev := event_at(cell)
	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if e.double_click:
				if not ev.is_empty():
					event_activated.emit(ev.id)
				elif in_map(cell):
					new_event_requested.emit(cell)
				return
			select_event(ev.get("id", ""))
			if not ev.is_empty():
				_moving_event = ev.id
				_move_from = cell
				_events_before_move = events_file.duplicate(true)
		else:
			if _moving_event != "":
				var moved := find_event(_moving_event)
				var p: Array = moved.get("position", [0, 0])
				if Vector2i(int(p[0]), int(p[1])) != _move_from:
					commit_events(_events_before_move, "Move event")
				_moving_event = ""
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		select_event(ev.get("id", ""))
		if ev.is_empty():
			map_context.emit(cell, e.global_position)
		else:
			event_context.emit(ev.id, cell, e.global_position)


var _events_before_move: Dictionary = {}


func select_event(id: String) -> void:
	selected_event = id
	selection_changed.emit(id)
	overlay.queue_redraw()


func _set_event_position_live(id: String, c: Vector2i) -> void:
	var other := event_at(c)
	if not other.is_empty() and other.get("id", "") != id:
		return
	var ev := find_event(id)
	if not ev.is_empty():
		ev["position"] = [c.x, c.y]
		overlay.queue_redraw()


## Writes the events file and registers an undo step from `before` to the current state.
func commit_events(before: Dictionary, action_name: String) -> void:
	var after := events_file.duplicate(true)
	if undo != null:
		undo.create_action("RPG: " + action_name)
		# The map ID travels with the snapshot: undo after switching maps must write the map
		# the edit was made on, not whichever map is open.
		undo.add_do_method(self, "_apply_events_file", [after, map_id])
		undo.add_undo_method(self, "_apply_events_file", [before, map_id])
		undo.commit_action(true)
	else:
		_apply_events_file(after, map_id)


func _apply_events_file(file: Dictionary, for_map := "") -> void:
	if for_map == "":
		for_map = map_id
	if for_map != map_id:
		if data != null and data.maps.has(for_map):
			RPGMapFiles.save_events_file(data, for_map, file.duplicate(true))
			events_modified.emit()
		return
	events_file = file.duplicate(true)
	RPGMapFiles.save_events_file(data, map_id, events_file)
	_event_tex_cache.clear()
	events_modified.emit()
	overlay.queue_redraw()


func reload_events() -> void:
	data.invalidate_map(map_id)
	events_file = RPGMapFiles.load_events_file(data, map_id)
	_event_tex_cache.clear()
	events_modified.emit()
	overlay.queue_redraw()


static func default_page() -> Dictionary:
	return {
		"conditions": [],
		"graphic": null,
		"movement": {"type": "fixed", "speed": 3, "frequency": 3},
		"options": {"walk_anim": true, "step_anim": false, "direction_fix": false, "through": false},
		"priority": "same",
		"trigger": "action_button",
		"commands": [],
	}


func new_event_at(c: Vector2i) -> String:
	var ids := {}
	for ev in events():
		ids[ev.get("id", "")] = true
	var id := RPGIds.unique("event_%d_%d" % [c.x, c.y], ids, events_file.get("retired_ids", []))
	var before := events_file.duplicate(true)
	if not events_file.has("events"):
		events_file["events"] = []
	events_file.events.append({"id": id, "name": "EV%03d" % (events().size() + 1), "position": [c.x, c.y], "notes": "", "pages": [default_page()]})
	commit_events(before, "New event")
	select_event(id)
	return id


func delete_event(id: String) -> void:
	var before := events_file.duplicate(true)
	var keep := []
	for ev in events():
		if ev.get("id", "") != id:
			keep.append(ev)
	events_file["events"] = keep
	# Deleted IDs are never reused by copy/paste or new events.
	var retired: Array = events_file.get("retired_ids", [])
	if not retired.has(id):
		retired.append(id)
	events_file["retired_ids"] = retired
	commit_events(before, "Delete event")
	select_event("")


func paste_event(ev_data: Dictionary, c: Vector2i) -> String:
	if not event_at(c).is_empty():
		return ""
	var ids := {}
	for ev in events():
		ids[ev.get("id", "")] = true
	var copy := ev_data.duplicate(true)
	copy["id"] = RPGIds.unique(str(ev_data.get("id", "event")), ids, events_file.get("retired_ids", []))
	copy["position"] = [c.x, c.y]
	var before := events_file.duplicate(true)
	events_file.events.append(copy)
	commit_events(before, "Paste event")
	select_event(copy.id)
	return copy.id


# --- overlay drawing ------------------------------------------------------------------------------

## Shows a traced route (RPGRoutePreview.trace) for a few seconds.
func show_route_preview(trace: Dictionary, seconds := 6.0) -> void:
	route_preview = trace
	overlay.queue_redraw()
	var stamp := Time.get_ticks_msec()
	route_preview["_stamp"] = stamp
	get_tree().create_timer(seconds).timeout.connect(func():
		if route_preview.get("_stamp", -1) == stamp:
			route_preview = {}
			overlay.queue_redraw())


func _draw_route_preview(ts: float) -> void:
	var cells: Array = route_preview.get("cells", [])
	var col := Color(1.0, 0.85, 0.2, 0.95)
	for i in cells.size():
		var c: Vector2i = cells[i]
		var centre := (Vector2(c) + Vector2(0.5, 0.5)) * ts
		if i > 0:
			var prev: Vector2i = cells[i - 1]
			overlay.draw_line((Vector2(prev) + Vector2(0.5, 0.5)) * ts, centre, col, 2.0 / zoom)
		overlay.draw_circle(centre, ts * (0.22 if i == 0 or i == cells.size() - 1 else 0.12), col)
	if str(route_preview.get("unknown", "")) != "" and not cells.is_empty():
		var last: Vector2i = cells[-1]
		var font := ThemeDB.fallback_font
		overlay.draw_string(font, (Vector2(last) + Vector2(0.6, 0.0)) * ts, "? " + str(route_preview.unknown), HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(8.0, ts * 0.6)), col)


func _draw_overlay() -> void:
	if map_node == null:
		return
	var ts := float(tile_size)
	var full := Rect2(Vector2.ZERO, Vector2(map_size) * ts)
	overlay.draw_rect(full, Color(1, 1, 1, 0.5), false, 1.0 / zoom)
	if mode == "event" or show_grid:
		var col := Color(1, 1, 1, 0.18)
		for x in range(1, map_size.x):
			overlay.draw_line(Vector2(x * ts, 0), Vector2(x * ts, full.size.y), col, 1.0 / zoom)
		for y in range(1, map_size.y):
			overlay.draw_line(Vector2(0, y * ts), Vector2(full.size.x, y * ts), col, 1.0 / zoom)
	if show_passability:
		_draw_passability()
	if not route_preview.is_empty():
		_draw_route_preview(ts)
	if show_terrain:
		_draw_terrain()
	if mode == "event":
		_draw_events()
	if start_pos.get("map", "") == map_id:
		var sp: Array = start_pos.get("position", [0, 0])
		overlay.draw_rect(Rect2(Vector2(int(sp[0]), int(sp[1])) * ts, Vector2(ts, ts)), Color(0.2, 0.5, 1.0), false, 2.0 / zoom)
		overlay.draw_string(ThemeDB.fallback_font, Vector2(int(sp[0]) * ts + 1, int(sp[1]) * ts + 7), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.4, 0.7, 1))
	# Vehicle starting positions (B boat, S ship, A airship), from the System record.
	var vs: Variant = data.system.get("vehicles", {}) if data != null else {}
	if vs is Dictionary:
		for k in vs:
			var st: Variant = vs[k].get("start") if vs[k] is Dictionary else null
			if st is Dictionary and str(st.get("map", "")) == map_id and st.get("position") is Array:
				var vp := Vector2(int(st.position[0]), int(st.position[1])) * ts
				overlay.draw_rect(Rect2(vp, Vector2(ts, ts)), Color(1.0, 0.75, 0.2), false, 2.0 / zoom)
				overlay.draw_string(ThemeDB.fallback_font, vp + Vector2(1, 7), {"boat": "B", "ship": "Sh", "airship": "A"}.get(k, "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 0.85, 0.3))
	if in_map(hover_cell) and mode != "event":
		var bsize: Vector2i = brush.get("size", Vector2i.ONE) if brush.get("kind", "") == "tiles" else Vector2i.ONE
		if _painting and _drag_from != Vector2i(-1, -1) and tool in ["rect", "ellipse", "shadow"]:
			var tl := Vector2i(mini(_drag_from.x, hover_cell.x), mini(_drag_from.y, hover_cell.y))
			var br := Vector2i(maxi(_drag_from.x, hover_cell.x), maxi(_drag_from.y, hover_cell.y))
			overlay.draw_rect(Rect2(Vector2(tl) * ts, Vector2(br - tl + Vector2i.ONE) * ts), Color(1, 1, 0.3, 0.9), false, 1.5 / zoom)
		else:
			overlay.draw_rect(Rect2(Vector2(hover_cell) * ts, Vector2(bsize) * ts), Color(1, 1, 0.3, 0.9), false, 1.5 / zoom)
	if _right_from != Vector2i(-1, -1) and in_map(hover_cell):
		var tl2 := Vector2i(mini(_right_from.x, hover_cell.x), mini(_right_from.y, hover_cell.y))
		var br2 := Vector2i(maxi(_right_from.x, hover_cell.x), maxi(_right_from.y, hover_cell.y))
		overlay.draw_rect(Rect2(Vector2(tl2) * ts, Vector2(br2 - tl2 + Vector2i.ONE) * ts), Color(0.4, 1, 0.4, 0.9), false, 1.5 / zoom)


func _draw_passability() -> void:
	var mv := RPGMovement.new(map_node)
	map_node.size = map_size
	var ts := float(tile_size)
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			var bits := mv.passage(c)
			var p := Vector2(x, y) * ts
			if bits == 0:
				overlay.draw_line(p + Vector2(3, 3), p + Vector2(ts - 3, ts - 3), Color(1, 0.25, 0.25, 0.85), 1.5 / zoom)
				overlay.draw_line(p + Vector2(ts - 3, 3), p + Vector2(3, ts - 3), Color(1, 0.25, 0.25, 0.85), 1.5 / zoom)
			elif bits == 15:
				overlay.draw_circle(p + Vector2(ts / 2, ts / 2), 2.5, Color(0.4, 0.8, 1.0, 0.7))
			else:
				for dn in ["down", "left", "right", "up"]:
					if bits & RPGMovement.BIT[dn]:
						var d := Vector2(RPGMovement.DIRS[dn])
						var mid := p + Vector2(ts / 2, ts / 2)
						overlay.draw_line(mid, mid + d * (ts / 2 - 2), Color(0.4, 0.8, 1.0, 0.9), 1.5 / zoom)
			if mv.flags(c) & RPGMovement.FLAG_STAR:
				overlay.draw_string(ThemeDB.fallback_font, p + Vector2(ts - 6, 6), "*", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.YELLOW)


func _draw_terrain() -> void:
	var mv := RPGMovement.new(map_node)
	var ts := float(tile_size)
	for y in map_size.y:
		for x in map_size.x:
			var t := mv.terrain(Vector2i(x, y))
			if t > 0:
				overlay.draw_string(ThemeDB.fallback_font, Vector2(x * ts + 2, y * ts + ts - 2), str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.9, 0.3))


func _draw_events() -> void:
	var ts := float(tile_size)
	for ev in events():
		var p: Array = ev.get("position", [0, 0])
		var r := Rect2(Vector2(int(p[0]), int(p[1])) * ts, Vector2(ts, ts))
		overlay.draw_rect(r, Color(0, 0, 0, 0.25))
		var tex := _event_texture(ev)
		if tex != null:
			var s := tex.get_size()
			var scale := minf(ts / s.x, ts / s.y)
			var dst := Rect2(r.position + (Vector2(ts, ts) - s * scale) / 2.0, s * scale)
			overlay.draw_texture_rect(tex, dst, false)
		var sel: bool = ev.get("id", "") == selected_event
		overlay.draw_rect(r.grow(-0.5 / zoom), Color(1, 1, 0.3) if sel else Color(1, 1, 1, 0.85), false, (2.0 if sel else 1.0) / zoom)


func _event_texture(ev: Dictionary) -> Texture2D:
	var id: String = ev.get("id", "")
	if _event_tex_cache.has(id):
		return _event_tex_cache[id]
	var tex: Texture2D = null
	var pages: Array = ev.get("pages", [])
	var g: Variant = pages[0].get("graphic") if not pages.is_empty() else null
	if g is Dictionary and str(g.get("sheet", "")) != "" and not str(g.sheet).begins_with("{{"):
		var sheet := RPGAssets.load_texture("charset", str(g.sheet))
		if sheet != null:
			var prof := RPGAssets.sheet_profile("charset", str(g.sheet), str(data.profile.get("profile", "rm2k")) if data != null else "rm2k")
			tex = RPGCharset.frame_texture(sheet, int(g.get("index", 0)), str(g.get("facing", "down")), int(g.get("frame", 1)), prof, RPGCharset.is_single_character(str(g.sheet), prof))
	elif g is Dictionary and g.has("tile") and map_node != null:
		tex = map_node.tile_texture(g.tile)
	_event_tex_cache[id] = tex
	return tex


func _process(_delta: float) -> void:
	if map_node != null and (show_passability or mode == "event"):
		pass
