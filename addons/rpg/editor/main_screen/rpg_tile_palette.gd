@tool
class_name RPGTilePalette
extends TabContainer
## The tile palette: one tab per sheet part (A autotiles, B lower, C upper, Anim) plus R for
## regions. Drag across several tiles to pick a stamp. Emits brush_changed(brush):
##   {kind: "tiles", size: Vector2i, cells: [{offset, source, coords}]}
##   {kind: "region", region: int}

signal brush_changed(brush: Dictionary)

const ZOOM := 2
const AUTOTILE_NAMES := ["Water A", "Water B", "Deep water", "Terrain 1", "Terrain 2", "Terrain 3", "Terrain 4", "Terrain 5", "Terrain 6", "Terrain 7", "Terrain 8", "Terrain 9", "Terrain 10", "Terrain 11", "Terrain 12"]

var tile_set: TileSet
var tile_size := 16
var brush: Dictionary = {}
var _grids: Array = []


class Grid extends Control:
	## One palette page: cells laid out `cols` wide; each cell maps to [source, coords].
	var palette: RPGTilePalette
	var cells: Array = []      # index -> {source, coords, label}
	var cols := 6
	var sel_from := -1
	var sel_to := -1
	var dragging := false
	var region_mode := false

	func _init(p: RPGTilePalette) -> void:
		palette = p
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_CLICK

	func cell_px() -> int:
		# 16 px tiles are zoomed; 32/48 px tiles are shown at their own size.
		return palette.tile_size * (ZOOM if palette.tile_size <= 16 else 1)

	func refresh_size() -> void:
		var rows := int(ceil(cells.size() / float(cols)))
		custom_minimum_size = Vector2(cols * cell_px(), rows * cell_px())
		queue_redraw()

	func _draw() -> void:
		var cp := cell_px()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.12, 0.14))
		for i in cells.size():
			var r := Rect2((i % cols) * cp, (i / cols) * cp, cp, cp)
			var c: Dictionary = cells[i]
			if region_mode:
				var n: int = c.region
				if n == 0:
					draw_rect(r.grow(-2), Color(0.3, 0.3, 0.3), false, 1)
					draw_string(ThemeDB.fallback_font, r.position + Vector2(3, cp - 8), "erase", HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
				else:
					draw_rect(r.grow(-1), RPGTilesetBuilder.region_color(n, 0.85))
					draw_string(ThemeDB.fallback_font, r.position + Vector2(3, cp - 9), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
				continue
			var tex: Texture2D = palette.tile_texture(c.source, c.coords)
			if tex != null:
				draw_texture_rect(tex, r, false)
		if sel_from >= 0:
			var rect := _sel_rect()
			draw_rect(Rect2(rect.position * cp, rect.size * cp), Color(1, 1, 0.3), false, 2)

	func _sel_rect() -> Rect2i:
		var a := Vector2i(sel_from % cols, sel_from / cols)
		var b := Vector2i(sel_to % cols, sel_to / cols)
		var tl := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		var br := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
		return Rect2i(tl, br - tl + Vector2i.ONE)

	func _index_at(pos: Vector2) -> int:
		var cp := cell_px()
		var x := int(pos.x / cp)
		var y := int(pos.y / cp)
		if x < 0 or x >= cols or y < 0:
			return -1
		var i := y * cols + x
		return i if i < cells.size() else -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _index_at(event.position)
			if event.pressed and i >= 0:
				sel_from = i
				sel_to = i
				dragging = not region_mode
				queue_redraw()
			elif not event.pressed and dragging:
				dragging = false
			if not event.pressed or region_mode:
				_emit()
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			var j := _index_at(event.position)
			if j >= 0:
				sel_to = j
				queue_redraw()

	func _emit() -> void:
		if sel_from < 0:
			return
		if region_mode:
			palette._set_brush({"kind": "region", "region": int(cells[sel_from].region)})
			return
		var rect := _sel_rect()
		var out := []
		for y in rect.size.y:
			for x in rect.size.x:
				var i := (rect.position.y + y) * cols + rect.position.x + x
				if i < cells.size():
					out.append({"offset": Vector2i(x, y), "source": cells[i].source, "coords": cells[i].coords})
		palette._set_brush({"kind": "tiles", "size": rect.size, "cells": out})

	func clear_selection() -> void:
		sel_from = -1
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(6 * 16 * ZOOM + 16, 200)


## Rebuilds the pages from a generated TileSet (see RPGTilesetBuilder atlas layout).
func set_tile_set(ts: TileSet, p_tile_size: int) -> void:
	tile_set = ts
	tile_size = ts.tile_size.x if ts != null else p_tile_size
	_tex_cache.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_grids.clear()
	if ts != null:
		# Empty pages are left out (xp/vx/mv TileSets have no Anim source, xp has no B).
		var pages := [["A", _autotile_cells(), 6], ["B", _plain_cells(RPGTilesetBuilder.SOURCE_LOWER), _plain_cols(RPGTilesetBuilder.SOURCE_LOWER)], ["C", _plain_cells(RPGTilesetBuilder.SOURCE_UPPER), _plain_cols(RPGTilesetBuilder.SOURCE_UPPER)], ["Anim", _anim_cells(), 6]]
		if str(ts.get_meta("rpg_profile", "")) in ["vx", "mv"]:
			# RPG Maker VX/Ace/MV tabs: A (autotiles), A5 (plain ground), then one tab per B-E sheet
			# (stacked UPPER_ROWS rows apart in the upper source).
			var upper := _plain_cells(RPGTilesetBuilder.SOURCE_UPPER)
			var cols := _plain_cols(RPGTilesetBuilder.SOURCE_UPPER)
			pages = [["A", _autotile_cells(), 6], ["A5", _plain_cells(RPGTilesetBuilder.SOURCE_LOWER), _plain_cols(RPGTilesetBuilder.SOURCE_LOWER)]]
			for si in 4:
				pages.append([["B", "C", "D", "E"][si], upper.filter(func(c): return int(c.coords.y) / VX_UPPER_ROWS == si), cols])
		for page in pages:
			if not (page[1] as Array).is_empty():
				_add_page(page[0], page[1], page[2])
	var regions := []
	for n in 256:
		regions.append({"region": n})
	var g := _add_page("R", regions, 6)
	g.region_mode = true
	g.refresh_size()


func _add_page(title: String, cells: Array, cols: int) -> Grid:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := Grid.new(self)
	g.cells = cells
	g.cols = cols
	scroll.add_child(g)
	add_child(scroll)
	set_tab_title(get_tab_count() - 1, title)
	set_tab_tooltip(get_tab_count() - 1, {"A": "Autotiles: water and terrains", "A5": "Plain ground tiles (sheet A5)", "B": "Lower layer tiles" if not _vx() else "Sheet B: upper layer tiles (the first one erases)", "C": "Upper layer tiles (the first one erases)" if not _vx() else "Sheet C: upper layer tiles", "D": "Sheet D: upper layer tiles", "E": "Sheet E: upper layer tiles", "Anim": "Animated tiles", "R": "Region numbers"}.get(title, title))
	g.refresh_size()
	_grids.append(g)
	return g


## Rows per B-E sheet in a VX/MV upper source (RPGTilesheetVX.UPPER_ROWS).
const VX_UPPER_ROWS := 32


func _vx() -> bool:
	return tile_set != null and str(tile_set.get_meta("rpg_profile", "")) in ["vx", "mv"]


func _autotile_cells() -> Array:
	var out := []
	for sid in tile_set.get_meta(RPGTilesetBuilder.AUTOTILE_SOURCES_META, [RPGTilesetBuilder.SOURCE_AUTOTILE]):
		var src := tile_set.get_source(sid) as TileSetAtlasSource if tile_set.has_source(sid) else null
		if src == null:
			continue
		var groups := int(src.texture.get_height() / tile_size) if src.texture else 0
		for g in groups:
			var coords := Vector2i(RPGAutotile.PREVIEW_VARIANT, g)
			if src.has_tile(coords):
				out.append({"source": int(sid), "coords": coords})
	return out


func _plain_cells(source_id: int) -> Array:
	var out := []
	if not tile_set.has_source(source_id):
		return out
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	var grid := src.get_atlas_grid_size()
	for i in grid.x * grid.y:
		var coords := Vector2i(i % grid.x, i / grid.x)
		if src.has_tile(coords):
			out.append({"source": source_id, "coords": coords})
	return out


## Columns of a plain source's atlas (6 for rm2k, 8 for xp/vx/mv).
func _plain_cols(source_id: int) -> int:
	if tile_set == null or not tile_set.has_source(source_id):
		return 6
	return maxi(1, (tile_set.get_source(source_id) as TileSetAtlasSource).get_atlas_grid_size().x)


func _anim_cells() -> Array:
	var out := []
	if not tile_set.has_source(RPGTilesetBuilder.SOURCE_ANIMATED):
		return out
	var src := tile_set.get_source(RPGTilesetBuilder.SOURCE_ANIMATED) as TileSetAtlasSource
	for i in 3:
		if src.has_tile(Vector2i(i, 0)):
			out.append({"source": RPGTilesetBuilder.SOURCE_ANIMATED, "coords": Vector2i(i, 0)})
	return out


var _tex_cache: Dictionary = {}


func tile_texture(source_id: int, coords: Vector2i) -> Texture2D:
	var key := "%d:%s" % [source_id, coords]
	if _tex_cache.has(key):
		return _tex_cache[key]
	if tile_set == null or not tile_set.has_source(source_id):
		return null
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coords):
		return null
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = src.get_tile_texture_region(coords)
	_tex_cache[key] = at
	return at


func _set_brush(b: Dictionary) -> void:
	brush = b
	for g in _grids:
		if not (g.get_parent() == get_current_tab_control()):
			g.clear_selection()
	brush_changed.emit(b)


## Selects a brush from outside (eyedropper).
func set_brush_external(b: Dictionary) -> void:
	brush = b
	for g in _grids:
		g.clear_selection()
	_show_brush(b)
	brush_changed.emit(b)


## Eyedropper: switches to the page holding the picked tile(s) and highlights them, as RPG Maker
## does, so the maker can see what they are now painting with.
func _show_brush(b: Dictionary) -> void:
	var cells: Array = b.get("cells", [])
	if b.get("kind", "") != "tiles" or cells.is_empty():
		return
	for g in _grids:
		var first := _cell_index(g, cells[0])
		if first < 0:
			continue
		var last := _cell_index(g, cells[cells.size() - 1])
		g.sel_from = first
		g.sel_to = first
		var size: Vector2i = b.get("size", Vector2i.ONE)
		# A rectangle picked from the map is highlighted whole when it is laid out the same way here.
		if last >= 0 and Vector2i(last % g.cols - first % g.cols, last / g.cols - first / g.cols) == size - Vector2i.ONE:
			g.sel_to = last
		g.queue_redraw()
		var scroll := g.get_parent() as ScrollContainer
		if scroll != null:
			current_tab = scroll.get_index()
			var cp: int = g.cell_px()
			scroll.set_deferred("scroll_vertical", maxi(0, (first / g.cols) * cp - cp * 2))
		return


static func _cell_index(g: Grid, c: Dictionary) -> int:
	for i in g.cells.size():
		var gc: Dictionary = g.cells[i]
		if gc.get("source") == c.get("source") and gc.get("coords") == c.get("coords"):
			return i
	return -1


func show_regions(on: bool) -> void:
	if get_tab_count() == 0:
		return
	var idx := get_tab_count() - 1
	if on:
		current_tab = idx
	elif current_tab == idx:
		current_tab = 0
