@tool
class_name RPGTilesheetXP
extends RefCounted
## Decoder for RPG Maker XP tile graphics (profile "xp", 32 px tiles).
## Original code written for this project from public descriptions of the format.
##
## TILESET RECORD
##   {id, name, profile: "xp", sheet: "res://.../Graphics/Tilesets/<file>.png",
##    autotiles: ["res://.../Graphics/Autotiles/<file>.png" or "", ... up to 7]}
##
## SHEETS
##   Tileset: 8 tiles wide (256 px), any height that is a whole number of tiles. Tile i sits at
##     (i % 8, i / 8). Tile 0 is the empty tile (eraser).
##   Autotile: one file per autotile, 3 x 4 tiles (96 x 128) in the XP quarter layout
##     (RPGAutotileLayout.LAYOUT_XP). A wider file is animated: each 96 px wide strip is one
##     frame, played left to right in a loop (at most MAX_FRAMES frames).
##     A file one tile high (32 px; 32 px wide or a multiple) is a plain repeating tile, with one
##     frame per 32 px. Other sizes are reported and skipped.
##
## GENERATED ATLAS (see RPGTilesetBuilder "generic layout"):
##   source 0  autotiles: row s = autotile slot s (0..6), column = variant 0..47.
##             Frame k of slot s is at row s + 7k (animation columns 1, separation (0, 6)).
##   source 2  tileset tiles: tile_i at (i % 8, i / 8) (tile_0 = eraser). Auto layer puts them on
##             Layer2, above the autotiles on Layer1.
## TILE KEYS: autotile_0..autotile_6, tile_0..tile_<n-1>.
## DEFAULTS (pixels cannot tell; every guessed key is listed for review except empty tiles):
##   autotile, one frame        passage 15 (open)         review
##   autotile, animated         passage 0 (usually water)  review
##   tile_0 or a fully transparent tile   passage 15, flags star (no review)
##   tile with no transparency  passage 15 (ground)        review
##   tile with transparency     passage 0 (object)         review
## Each autotile connects only to itself.

const AUTOTILE_SLOTS := 7
const COLUMNS := 8
const MAX_FRAMES := 8
const SOURCE_AUTOTILE := 0
const SOURCE_TILES := 2
const FLAG_STAR := 16


## Image name -> sheet path for a tileset record.
static func image_paths(record: Dictionary) -> Dictionary:
	var out := {}
	var sheet := str(record.get("sheet", ""))
	if sheet != "":
		out["tileset"] = sheet
	var list: Variant = record.get("autotiles", [])
	if list is Array:
		for i in mini((list as Array).size(), AUTOTILE_SLOTS):
			var p := str(list[i])
			if p != "" and p != "<null>":
				out["autotile_%d" % i] = p
	return out


## Decodes loaded RGBA8 images (names from image_paths) into a generic layout
## (RPGTilesetBuilder.new_layout). Errors leave the layout unusable; warnings skip one file.
static func decode(images: Dictionary, tile_size: int, frame_time: float) -> Dictionary:
	var t := tile_size
	var out := RPGTilesetBuilder.new_layout("xp", t)
	var tileset: Image = images.get("tileset")
	if tileset == null:
		out.errors.append("XP tileset needs its tileset image ('sheet').")
		return out
	if tileset.get_width() != COLUMNS * t or tileset.get_height() < t or tileset.get_height() % t != 0:
		out.errors.append("XP tileset must be %d px wide and a whole number of %d px tiles high, got %dx%d." % [COLUMNS * t, t, tileset.get_width(), tileset.get_height()])
		return out
	out.images["tileset"] = tileset
	# Autotiles.
	var max_frames := 1
	for s in AUTOTILE_SLOTS:
		out.classes.append("autotile_%d" % s)
		var name := "autotile_%d" % s
		var img: Image = images.get(name)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var layout := ""
		var frame_w := 0
		if h == 4 * t and w >= 3 * t and w % (3 * t) == 0:
			layout = RPGAutotileLayout.LAYOUT_XP
			frame_w = 3 * t
		elif h == t and w >= t and w % t == 0:
			layout = RPGAutotileLayout.LAYOUT_SINGLE
			frame_w = t
		else:
			out.warnings.append("XP autotile %d is %dx%d; expected %dx%d (or a wider animated strip). Skipped." % [s, w, h, 3 * t, 4 * t])
			continue
		var n := mini(w / frame_w, MAX_FRAMES)
		if w / frame_w > MAX_FRAMES:
			out.warnings.append("XP autotile %d has %d frames; only the first %d are used." % [s, w / frame_w, MAX_FRAMES])
		var frames: Array[Vector2i] = []
		for k in n:
			frames.append(Vector2i(k * frame_w, 0))
		max_frames = maxi(max_frames, n)
		out.images[name] = img
		var key := name
		out.groups.append({
			"key": key, "group": s, "source": SOURCE_AUTOTILE, "row": s, "class": key, "image": name,
			"origin": Vector2i.ZERO, "layout": layout, "frames": frames, "frame_time": frame_time,
		})
		out.key_rects[key] = [[name, Rect2i(0, 0, w, h)]]
		if n > 1:
			out.defaults[key] = {"passage": 0, "flags": 0, "terrain": 0}
		else:
			out.defaults[key] = {"passage": 15, "flags": 0, "terrain": 0}
		out.review.append(key)
	out.autotile_sources.append({"id": SOURCE_AUTOTILE, "rows": AUTOTILE_SLOTS, "frames": max_frames})
	# Tileset tiles.
	var rows := tileset.get_height() / t
	out.plain_sources.append({"id": SOURCE_TILES, "cols": COLUMNS, "rows": rows})
	for i in rows * COLUMNS:
		var key := "tile_%d" % i
		var r := Rect2i((i % COLUMNS) * t, (i / COLUMNS) * t, t, t)
		out.plain.append({"key": key, "source": SOURCE_TILES, "coords": Vector2i(i % COLUMNS, i / COLUMNS), "image": "tileset", "rect": r})
		out.key_rects[key] = [["tileset", r]]
		var region := tileset.get_region(r)
		if i == 0 or region.is_invisible():
			out.defaults[key] = {"passage": 15, "flags": FLAG_STAR, "terrain": 0}
		elif region.detect_alpha() == Image.ALPHA_NONE:
			out.defaults[key] = {"passage": 15, "flags": 0, "terrain": 0}
			out.review.append(key)
		else:
			out.defaults[key] = {"passage": 0, "flags": 0, "terrain": 0}
			out.review.append(key)
	return out
