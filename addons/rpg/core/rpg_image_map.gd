@tool
class_name RPGImageMap
extends RefCounted
## Image-backed maps (docs/specs/image-backed-maps.md): shared rules for the new-map dialog, Map
## Properties, the map view, the runtime map, the validator and the tests.
##
## A map is image-backed when its properties (<id>.map.json) hold
##   "image_map": {"version": 1, "base": "res://...png", "foreground": "res://...png" or null}
## with a non-empty "base". A missing key means a tile map: old maps need no migration.
##
## Images are checked against the MAP tile size: the tile size of the map's tileset (its profile:
## 16, 32 or 48 px), or the project tile size when the map has no tileset. One image pixel is one
## map pixel; RPG Kit never rescales, crops, pads or resamples the image.

const VERSION := 1
const KEY := "image_map"

## Largest image side accepted, in pixels. Almost every desktop GPU supports 8192 x 8192 textures;
## a 500-cell map of 16 px tiles (8000 px) fits. ASSUMPTION, not a measurement: confirm it on each
## export target (web and mobile GPUs may stop at 4096 or 2048) before release.
const MAX_SIDE := 8192
## Above this many pixels on either side the editor warns: web and mobile GPUs may support only
## 4096 (or 2048). Also still to be confirmed per export target.
const WARN_SIDE := 4096
## Texture memory is the decoded size (4 bytes per pixel), not the PNG file size:
## 4096 x 4096 = 64 MiB, 8192 x 8192 = 256 MiB.
const BYTES_PER_PIXEL := 4
## Representative sizes the feature is tested and measured with (Performance requirement):
## [profile, tile size, cells, pixels].
const TEST_SIZES := [
	["rm2k", 16, Vector2i(40, 30), Vector2i(640, 480)],
	["xp / vx", 32, Vector2i(40, 30), Vector2i(1280, 960)],
	["mv", 48, Vector2i(40, 30), Vector2i(1920, 1440)],
	["rm2k, largest map", 16, Vector2i(500, 500), Vector2i(8000, 8000)],
]

## Node names (built at load time, never saved into the map scene).
const BASE_NODE := "ImageBase"
const FOREGROUND_NODE := "ImageForeground"
## The navigation mask layer, saved with the map scene (see RPGMap.navigation).
const NAVIGATION_LAYER := "Navigation"
## Draw order: base under the tile layers (z 0), foreground above every character and star tile
## (events "above" are 4) and under the airship (6).
const BASE_Z := -1
const FOREGROUND_Z := 5


# --- properties -------------------------------------------------------------------------------

## The image_map block of map properties, or {} for a tile map.
static func block(props: Dictionary) -> Dictionary:
	var b: Variant = props.get(KEY)
	return b if b is Dictionary else {}


static func is_image_map(props: Dictionary) -> bool:
	return base_path(props) != ""


static func base_path(props: Dictionary) -> String:
	var b := block(props)
	var v: Variant = b.get("base")
	return str(v).strip_edges() if v is String else ""


static func foreground_path(props: Dictionary) -> String:
	var b := block(props)
	var v: Variant = b.get("foreground")
	return str(v).strip_edges() if v is String else ""


## A new image_map block (foreground "" is stored as null).
static func make_block(base: String, foreground := "") -> Dictionary:
	return {"version": VERSION, "base": base, "foreground": foreground if foreground != "" else null}


## Map tile size of a map's properties: its tileset's tile size, else the project's.
static func map_tile_size(data: RPGProjectData, props: Dictionary) -> int:
	return tile_size_for_tileset(data, str(props.get("tileset", "")))


static func tile_size_for_tileset(data: RPGProjectData, tileset_id: String) -> int:
	if tileset_id != "" and data.has_record("tilesets", tileset_id):
		var rec: Dictionary = data.record("tilesets", tileset_id)
		var prof := RPGProfile.load_profile(str(rec.get("profile", "rm2k")))
		if prof != null and prof.tile_size > 0:
			return prof.tile_size
	return data.tile_size()


## Where the map tile size comes from, in maker words.
static func tile_size_source(data: RPGProjectData, tileset_id: String) -> String:
	if tileset_id != "" and data.has_record("tilesets", tileset_id):
		return "the tile size of the map's tileset '%s'" % tileset_id
	return "the project tile size (the map has no tileset)"


# --- images ---------------------------------------------------------------------------------------

## Loads an image as a texture: an imported resource (res://, what an exported game has), or a
## PNG/WebP/JPEG file read directly (files outside res://, or not imported yet). Null if unreadable.
## `fresh` reads an imported texture again instead of reusing the cached one (after a reimport).
static func load_texture(path: String, fresh := false) -> Texture2D:
	if path == "":
		return null
	if _imported(path):
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE if fresh else ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## An imported project resource (what an exported game reads; the raw file may be left out).
static func _imported(path: String) -> bool:
	return path.begins_with("res://") and ResourceLoader.exists(path)


static func exists(path: String) -> bool:
	return path != "" and (_imported(path) or FileAccess.file_exists(path))


## {ok, size: Vector2i, error}: the pixel size of an image file.
static func read_size(path: String) -> Dictionary:
	if path == "":
		return {"ok": false, "size": Vector2i.ZERO, "error": "No image is selected."}
	if not exists(path):
		return {"ok": false, "size": Vector2i.ZERO, "error": "The image %s does not exist." % path}
	var tex := load_texture(path)
	if tex == null:
		return {"ok": false, "size": Vector2i.ZERO, "error": "The image %s could not be read. Save it again as a PNG and try once more." % path}
	var s := Vector2i(tex.get_width(), tex.get_height())
	if s.x <= 0 or s.y <= 0:
		return {"ok": false, "size": s, "error": "The image %s is empty (%d×%d pixels)." % [path, s.x, s.y]}
	return {"ok": true, "size": s, "error": ""}


static func nearest_below(v: int, tile: int) -> int:
	return (v / tile) * tile if tile > 0 else v


static func nearest_above(v: int, tile: int) -> int:
	if tile <= 0:
		return v
	return v if v % tile == 0 else (v / tile + 1) * tile


## Checks a pixel size against a map tile size.
## Returns {ok, size, tile_size, cells, error, warning, nearest: {width: [below, above], height: [below, above]}}.
## `ok` is false for a zero size, a side that is not a multiple of the tile size, or a side over
## MAX_SIDE. `warning` is set (with ok true) above WARN_SIDE.
static func check_size(size: Vector2i, tile: int) -> Dictionary:
	var out := {"ok": false, "size": size, "tile_size": tile, "cells": Vector2i.ZERO, "error": "", "warning": "",
		"nearest": {"width": [nearest_below(size.x, tile), nearest_above(size.x, tile)], "height": [nearest_below(size.y, tile), nearest_above(size.y, tile)]}}
	if tile <= 0:
		out.error = "The map tile size is unknown."
		return out
	if size.x <= 0 or size.y <= 0:
		out.error = "The image is empty (%d×%d pixels)." % [size.x, size.y]
		return out
	if size.x > MAX_SIDE or size.y > MAX_SIDE:
		out.error = "The image is %d×%d pixels, larger than the limit of %d pixels per side. Split the area into several maps, or use a larger tile size." % [size.x, size.y, MAX_SIDE]
		return out
	var bad := []
	if size.x % tile != 0:
		bad.append("width %d px: nearest valid widths are %d px below and %d px above" % [size.x, nearest_below(size.x, tile), nearest_above(size.x, tile)])
	if size.y % tile != 0:
		bad.append("height %d px: nearest valid heights are %d px below and %d px above" % [size.y, nearest_below(size.y, tile), nearest_above(size.y, tile)])
	if not bad.is_empty():
		out.error = "The image is %d×%d pixels, which is not a whole number of %d px map tiles (%s). Resize the canvas in your art program; RPG Kit never rescales or crops the image." % [size.x, size.y, tile, "; ".join(PackedStringArray(bad))]
		return out
	var cells := size / tile
	if cells.x > 500 or cells.y > 500:
		out.error = "The image is %d×%d pixels = %d×%d cells; a map can be at most 500 cells per side." % [size.x, size.y, cells.x, cells.y]
		return out
	out.ok = true
	out.cells = cells
	if size.x > WARN_SIDE or size.y > WARN_SIDE:
		out.warning = "The image is %d×%d pixels. Above %d pixels per side some web and mobile GPUs cannot show it, and it takes %d MiB of texture memory." % [size.x, size.y, WARN_SIDE, texture_mib(size)]
	return out


## Reads an image and checks it (read errors come back as `error` with ok false).
static func check_image(path: String, tile: int) -> Dictionary:
	var r := read_size(path)
	if not r.ok:
		var out := check_size(Vector2i.ZERO, tile)
		out.size = r.size
		out.error = r.error
		return out
	return check_size(r.size, tile)


## A foreground must be the same pixel size as the base. "" when it is.
static func foreground_mismatch(base_size: Vector2i, fg_size: Vector2i) -> String:
	if base_size == fg_size:
		return ""
	return "The foreground image is %d×%d pixels but the base image is %d×%d. Both must be the same size." % [fg_size.x, fg_size.y, base_size.x, base_size.y]


static func texture_mib(size: Vector2i) -> int:
	return int(ceil(float(size.x) * size.y * BYTES_PER_PIXEL / 1048576.0))


## Import settings that make pixel art blurry or lossy: [messages]. Reads the .import file only
## (RPG Kit never rewrites it).
static func import_warnings(path: String) -> Array:
	var out := []
	var imp := path + ".import"
	if not FileAccess.file_exists(imp):
		return out
	var cfg := ConfigFile.new()
	if cfg.load(imp) != OK:
		return out
	if bool(cfg.get_value("params", "mipmaps/generate", false)):
		out.append("%s is imported with mipmaps; turn them off in the Import dock so the art stays sharp." % path)
	# compress/mode: 0 lossless, 1 lossy, 2 VRAM compressed, 3 VRAM uncompressed, 4 Basis Universal.
	var mode := int(cfg.get_value("params", "compress/mode", 0))
	if mode in [1, 2, 4]:
		out.append("%s is imported with lossy or VRAM compression, which changes pixel colours; set Compress to Lossless in the Import dock." % path)
	return out


# --- review of a size change ------------------------------------------------------------------------

## What would fall outside a map of `new_cells`: {events: [label], tiles, regions, navigation,
## starts: [label], blocking: bool}. `map_node` is the open map (cells), `events` its events,
## `system` the System record (player and vehicle start positions).
static func outside_report(map_id: String, map_node: Node, events: Array, system: Dictionary, new_cells: Vector2i) -> Dictionary:
	var out := {"events": [], "tiles": 0, "regions": 0, "navigation": 0, "starts": [], "blocking": false}
	var outside := func(c: Vector2i) -> bool: return c.x >= new_cells.x or c.y >= new_cells.y
	for ev in events:
		var p: Array = ev.get("position", [0, 0])
		if outside.call(Vector2i(int(p[0]), int(p[1]))):
			out.events.append("%s (%s) at (%d, %d)" % [ev.get("name", ""), ev.get("id", ""), int(p[0]), int(p[1])])
	if map_node != null:
		for c in map_node.get_children():
			if not (c is TileMapLayer):
				continue
			var n := 0
			for cell in c.get_used_cells():
				if outside.call(cell):
					n += 1
			match str(c.name):
				"Regions": out.regions += n
				NAVIGATION_LAYER: out.navigation += n
				_: out.tiles += n
	var st: Variant = system.get("start")
	if st is Dictionary and str(st.get("map", "")) == map_id and st.get("position") is Array:
		var sp: Vector2i = Vector2i(int(st.position[0]), int(st.position[1]))
		if outside.call(sp):
			out.starts.append("player start (%d, %d)" % [sp.x, sp.y])
	var vs: Variant = system.get("vehicles", {})
	if vs is Dictionary:
		for k in vs:
			var vst: Variant = vs[k].get("start") if vs[k] is Dictionary else null
			if vst is Dictionary and str(vst.get("map", "")) == map_id and vst.get("position") is Array:
				var vp := Vector2i(int(vst.position[0]), int(vst.position[1]))
				if outside.call(vp):
					out.starts.append("%s start (%d, %d)" % [k, vp.x, vp.y])
	out.blocking = not out.starts.is_empty()
	return out


static func report_has_losses(r: Dictionary) -> bool:
	return not r.events.is_empty() or r.tiles > 0 or r.regions > 0 or r.navigation > 0 or not r.starts.is_empty()


# --- validation -------------------------------------------------------------------------------------

## Problems of one map's image_map block: [{severity, message}] (the validator adds file and path).
static func problems(data: RPGProjectData, map_id: String, props: Dictionary) -> Array:
	var out := []
	if not props.has(KEY) or props.get(KEY) == null:
		return out
	if not (props.get(KEY) is Dictionary):
		out.append({"severity": "error", "field": "image_map", "message": "Map '%s': \"image_map\" must be an object {version, base, foreground}." % map_id})
		return out
	var base := base_path(props)
	if base == "":
		return out
	var tile := map_tile_size(data, props)
	var base_check := check_image(base, tile)
	if not base_check.ok:
		var missing := not exists(base)
		out.append({"severity": "error", "field": "image_map/base", "message": ("Map '%s': the base image %s is missing." % [map_id, base]) if missing else ("Map '%s': base image %s: %s" % [map_id, base, base_check.error])})
	else:
		var want := Vector2i(int(props.get("width", 0)), int(props.get("height", 0)))
		if base_check.cells != want:
			out.append({"severity": "error", "field": "image_map/base", "message": "Map '%s': the base image %s is %d×%d cells (%d×%d px at %d px per tile) but the map is %d×%d cells. Open Map Properties to review the size change." % [map_id, base, base_check.cells.x, base_check.cells.y, base_check.size.x, base_check.size.y, tile, want.x, want.y]})
		if base_check.warning != "":
			out.append({"severity": "warning", "field": "image_map/base", "message": "Map '%s': %s" % [map_id, base_check.warning]})
	for w in import_warnings(base):
		out.append({"severity": "warning", "field": "image_map/base", "message": "Map '%s': %s" % [map_id, w]})
	var fg := foreground_path(props)
	if fg != "":
		var fr := read_size(fg)
		if not fr.ok:
			var fg_missing := not exists(fg)
			out.append({"severity": "error", "field": "image_map/foreground", "message": ("Map '%s': the foreground image %s is missing." % [map_id, fg]) if fg_missing else ("Map '%s': foreground image: %s" % [map_id, fr.error])})
		elif base_check.ok:
			var mm := foreground_mismatch(base_check.size, fr.size)
			if mm != "":
				out.append({"severity": "error", "field": "image_map/foreground", "message": "Map '%s': %s (%s and %s)" % [map_id, mm, fg, base]})
		for w2 in import_warnings(fg):
			out.append({"severity": "warning", "field": "image_map/foreground", "message": "Map '%s': %s" % [map_id, w2]})
	if str(props.get("scroll", "none")) != "none":
		out.append({"severity": "error", "field": "scroll", "message": "Map '%s' is image-backed but loops (%s). Its image would show a seam; set Scroll type to No loop." % [map_id, props.get("scroll")]})
	return out
