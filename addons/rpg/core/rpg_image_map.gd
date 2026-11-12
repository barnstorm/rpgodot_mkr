@tool
class_name RPGImageMap
extends RefCounted
## Image-backed maps: a normal map whose look comes from one pixel-aligned base image (and an
## optional same-sized transparent foreground image drawn above the characters), with
## passability painted on a hidden Navigation layer instead of coming from tiles.
##
## Data (see docs/ARCHITECTURE.md, "Image-backed maps"):
##   <id>.map.json  "image_map": {"version": 1, "base": "res://...png", "foreground": "res://...png" | null,
##                                "new_cells": "blocked" | "walkable"}
##   <id>.tscn      TileMapLayer "Navigation": one tile per cell, atlas (passage bits, 0) with the
##                  RPGMovement bits (1 down, 2 left, 4 right, 8 up; 0 blocked, 15 walkable).
##                  An empty cell is blocked. Hidden in the game; the editor draws it as an overlay.
## One image pixel is one map pixel: the image is (width x tile size) by (height x tile size)
## pixels, where the tile size is the project's (rpg/profile.json tile_size).
##
## Movement on an image-backed map: the cell's navigation bits, ANDed with the passage of the top
## visible tile when there is one (so a painted fence can still block, but a cell needs no tile).

const VERSION := 1
const NAV_LAYER := "Navigation"
const BASE_NODE := "ImageBase"
const FOREGROUND_NODE := "ImageForeground"
## Draw order: the base image under every tile layer; the foreground above upper-layer (star)
## tiles (z 3), characters (z 2) and "above characters" events (z 4). A flying airship (z 5, drawn
## later in the tree) stays on top of it, as it does over star tiles.
const BASE_Z := -1
const FOREGROUND_Z := 5
const NAV_Z := 81
## Largest side accepted by default, and the side above which the editor warns (overridable in
## rpg/project.json "image_maps": {"max_size", "warn_size"}). 8192 is what every desktop GPU and
## WebGL 2 browser in common use handles; Godot's own hard limit is 16384.
const DEFAULT_MAX_SIZE := 8192
const DEFAULT_WARN_SIZE := 4096
const ENGINE_MAX_SIZE := 16384
const WALKABLE := 15
const BLOCKED := 0


## True when map properties describe an image-backed map.
static func is_image_map(props: Dictionary) -> bool:
	return props.get("image_map") is Dictionary


static func block(props: Dictionary) -> Dictionary:
	var b: Variant = props.get("image_map")
	return b if b is Dictionary else {}


static func base_path(props: Dictionary) -> String:
	var b := block(props)
	return str(b.get("base", "")) if b.get("base") != null else ""


static func foreground_path(props: Dictionary) -> String:
	var b := block(props)
	return str(b.get("foreground", "")) if b.get("foreground") != null else ""


static func new_block(base: String, foreground: String, new_cells: String) -> Dictionary:
	return {"version": VERSION, "base": base, "foreground": foreground if foreground != "" else null, "new_cells": new_cells if new_cells in ["blocked", "walkable"] else "blocked"}


## {max_size, warn_size} for a project (project.json "image_maps" can lower or raise them, never
## past the engine's limit).
static func limits(data: RPGProjectData = null) -> Dictionary:
	var out := {"max_size": DEFAULT_MAX_SIZE, "warn_size": DEFAULT_WARN_SIZE}
	if data != null and data.project.get("image_maps") is Dictionary:
		var c: Dictionary = data.project.image_maps
		if c.has("max_size"):
			out.max_size = clampi(int(c.max_size), 16, ENGINE_MAX_SIZE)
		if c.has("warn_size"):
			out.warn_size = clampi(int(c.warn_size), 16, out.max_size)
	out.warn_size = mini(out.warn_size, out.max_size)
	return out


# --- reading and checking images ---------------------------------------------------------------

## Pixel size of an image file, read from the file itself (works before Godot has imported it and
## in headless tools): {ok, size: Vector2i, error}.
static func read_size(path: String) -> Dictionary:
	if path == "":
		return {"ok": false, "size": Vector2i.ZERO, "error": "No image chosen."}
	if not FileAccess.file_exists(path):
		# An exported game has only the imported texture.
		if ResourceLoader.exists(path):
			var t: Variant = load(path)
			if t is Texture2D:
				return {"ok": true, "size": Vector2i(t.get_size()), "error": ""}
		return {"ok": false, "size": Vector2i.ZERO, "error": "The image file '%s' does not exist." % path}
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path)) if path.begins_with("res://") or path.begins_with("user://") else img.load(path)
	if err != OK or img.is_empty():
		return {"ok": false, "size": Vector2i.ZERO, "error": "'%s' could not be read as an image (error %d). Save it as a PNG." % [path.get_file(), err]}
	var s := Vector2i(img.get_width(), img.get_height())
	if s.x <= 0 or s.y <= 0:
		return {"ok": false, "size": s, "error": "'%s' has no pixels (%d×%d)." % [path.get_file(), s.x, s.y]}
	return {"ok": true, "size": s, "error": ""}


## The nearest multiples of `tile` below and above `px` (the lower one is at least one tile).
static func nearest_valid(px: int, tile: int) -> Array:
	var lo := maxi(tile, (px / tile) * tile)
	var hi := ((px + tile - 1) / tile) * tile
	if hi == lo:
		hi = lo + tile
	return [lo, hi]


## Checks pixel dimensions against the tile size and limits. Returns
## {ok, cells: Vector2i, errors: [String], warnings: [String]}.
static func check_size(px: Vector2i, tile: int, lim: Dictionary) -> Dictionary:
	var errors := []
	var warnings := []
	if px.x <= 0 or px.y <= 0:
		errors.append("The image has no pixels (%d×%d)." % [px.x, px.y])
		return {"ok": false, "cells": Vector2i.ZERO, "errors": errors, "warnings": warnings}
	var max_size := int(lim.get("max_size", DEFAULT_MAX_SIZE))
	if px.x > max_size or px.y > max_size:
		errors.append("The image is %d×%d px; the largest side allowed is %d px. Split the area into several maps." % [px.x, px.y, max_size])
	if px.x % tile != 0 or px.y % tile != 0:
		var nx := nearest_valid(px.x, tile)
		var ny := nearest_valid(px.y, tile)
		var w_ok := px.x % tile == 0
		var h_ok := px.y % tile == 0
		var parts := []
		if not w_ok:
			parts.append("width %d or %d" % nx)
		if not h_ok:
			parts.append("height %d or %d" % ny)
		errors.append("The image is %d×%d px, which is not a whole number of %d px tiles. Resize or pad the canvas (not the artwork) to %s px. The kit never rescales or crops it for you." % [px.x, px.y, tile, " and ".join(PackedStringArray(parts))])
	var warn := int(lim.get("warn_size", DEFAULT_WARN_SIZE))
	if errors.is_empty() and (px.x > warn or px.y > warn):
		warnings.append("The image is large (%d×%d px, about %d MB of video memory once loaded, whatever the PNG's file size). It may be slow on older computers and phones." % [px.x, px.y, ceili(px.x * px.y * 4 / 1048576.0)])
	var cells := Vector2i(px.x / tile, px.y / tile) if errors.is_empty() else Vector2i.ZERO
	return {"ok": errors.is_empty(), "cells": cells, "errors": errors, "warnings": warnings}


## Full check of a base image (and an optional foreground) for a project tile size:
## {ok, pixels, cells, errors, warnings}.
static func check_images(base: String, foreground: String, tile: int, lim: Dictionary) -> Dictionary:
	var r := read_size(base)
	if not r.ok:
		return {"ok": false, "pixels": Vector2i.ZERO, "cells": Vector2i.ZERO, "errors": ["Base image: " + str(r.error)], "warnings": []}
	var c := check_size(r.size, tile, lim)
	c["pixels"] = r.size
	if foreground != "":
		var f := read_size(foreground)
		if not f.ok:
			c.errors.append("Foreground image: " + str(f.error))
		elif f.size != r.size:
			c.errors.append("The foreground image is %d×%d px but the base image is %d×%d px. They must be the same size so they line up." % [f.size.x, f.size.y, r.size.x, r.size.y])
	c.ok = c.errors.is_empty()
	return c


## Validator problems for one map's properties (file = its .map.json path).
static func problems_for(map_id: String, props: Dictionary, file: String, tile: int, lim: Dictionary) -> Array:
	var out := []
	if not is_image_map(props):
		return out
	var b := block(props)
	var base := base_path(props)
	if base == "":
		var pr := RPGValidator.problem("error", file, map_id, "image_map.base", "image_map/base", "Image-backed map '%s' has no base image." % map_id, "Pick a base image in the map's Properties.")
		pr["blocks_export"] = true
		out.append(pr)
		return out
	var fg := foreground_path(props)
	var c := check_images(base, fg, tile, lim)
	for e in c.errors:
		var field := "image_map.foreground" if str(e).begins_with("Foreground") or str(e).begins_with("The foreground") else "image_map.base"
		out.append(RPGValidator.problem("error", file, map_id, field, field.replace(".", "/"), "Map '%s': %s" % [map_id, e], "Fix the image file, or pick another in the map's Properties."))
	if c.ok:
		var size := Vector2i(int(props.get("width", 0)), int(props.get("height", 0)))
		if size != c.cells:
			out.append(RPGValidator.problem("error", file, map_id, "width", "width", "Map '%s' is %d×%d cells but its base image (%d×%d px) covers %d×%d cells." % [map_id, size.x, size.y, c.pixels.x, c.pixels.y, c.cells.x, c.cells.y], "Open the map's Properties and choose the image again to review the size change."))
	for pr in out:
		if pr.severity == "error":
			pr["blocks_export"] = true
	if int(b.get("version", VERSION)) > VERSION:
		out.append(RPGValidator.problem("warning", file, map_id, "image_map.version", "image_map/version", "Map '%s' was saved by a newer kit (image_map version %s)." % [map_id, b.get("version")], "Update the kit."))
	return out


# --- textures ------------------------------------------------------------------------------------

## The texture of an image path: the imported resource when Godot has one (games, editor),
## otherwise read straight from the file (a file copied in a moment ago). `fresh` skips caches
## (after the file changed on disk).
static func load_texture(path: String, fresh := false) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var t: Variant = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE if fresh else ResourceLoader.CACHE_MODE_REUSE)
		if t is Texture2D and (not fresh or not FileAccess.file_exists(path) or Vector2i(t.get_size()) == read_size(path).size):
			return t
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# --- navigation ----------------------------------------------------------------------------------

static var _nav_tilesets: Dictionary = {}


## TileSet for the Navigation layer: source 0, tiles (bits, 0) for bits 0..15, custom data
## `passage`. The tiles are transparent; the editor draws the navigation as an overlay.
static func navigation_tileset(tile_size := 16) -> TileSet:
	if _nav_tilesets.has(tile_size):
		return _nav_tilesets[tile_size]
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "passage")
	ts.set_custom_data_layer_type(0, TYPE_INT)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(Image.create_empty(16 * tile_size, tile_size, false, Image.FORMAT_RGBA8))
	src.texture_region_size = Vector2i(tile_size, tile_size)
	ts.add_source(src, 0)
	for bits in 16:
		src.create_tile(Vector2i(bits, 0))
		src.get_tile_data(Vector2i(bits, 0), 0).set_custom_data("passage", bits)
	ts.set_meta("rpg_kind", "navigation")
	_nav_tilesets[tile_size] = ts
	return ts


## Passage bits of a navigation cell (an empty cell is blocked).
static func nav_bits(layer: TileMapLayer, cell: Vector2i) -> int:
	if layer == null or layer.get_cell_source_id(cell) < 0:
		return BLOCKED
	return layer.get_cell_atlas_coords(cell).x & 15


static func set_nav(layer: TileMapLayer, cell: Vector2i, bits: int) -> void:
	layer.set_cell(cell, 0, Vector2i(clampi(bits, 0, 15), 0))


static func fill_nav(layer: TileMapLayer, rect: Rect2i, bits: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			set_nav(layer, Vector2i(x, y), bits)


## A new, empty Navigation layer (hidden; saved with the scene).
static func new_nav_layer() -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = NAV_LAYER
	l.z_index = NAV_Z
	l.visible = false
	return l


## Short description of a passage value, for the palette and the status bar.
static func describe(bits: int) -> String:
	if bits == WALKABLE:
		return "Walkable"
	if bits == BLOCKED:
		return "Blocked"
	var open := []
	for d in ["up", "down", "left", "right"]:
		if bits & RPGMovement.BIT[d]:
			open.append(d)
	return "Open: " + ", ".join(PackedStringArray(open))
