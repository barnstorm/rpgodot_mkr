@tool
class_name RPGTilesheetVX
extends RefCounted
## Decoder for the VX / VX Ace (profile "vx", 32 px) and MV / MZ (profile "mv", 48 px) tile
## sheets A1-A5 and B-E. Both profiles share one layout measured in tiles; only the tile size
## differs. Original code written for this project from public descriptions of the format.
##
## TILESET RECORD
##   {id, name, profile: "vx" | "mv", sheets: {"a1": path, "a2": ..., "a3", "a4", "a5", "b", "c",
##    "d", "e"}}   (every sheet is optional, at least one is needed)
## Sheet sizes come from the profile descriptor (tileset_a1 ... tileset_b); a sheet of another
## size is reported and skipped.
##
## SHEETS (T = tile size; positions in tiles)
##   A1  16 x 12  animated water. 16 kinds; kind k:
##         k 0  sea           floor block at (0,0), 3 frames 2 tiles apart, played 0,1,2,1
##         k 1  deep sea      floor block at (0,3), same animation
##         k 2  decoration    floor block at (6,0), still
##         k 3  decoration    floor block at (6,3), still
##         k >= 4: tx = k % 8, ty = k / 8, bx = (tx / 4) * 8, by = ty * 6 + ((tx / 2) % 2) * 3;
##               even k: water floor block at (bx, by), 3 frames 2 tiles apart, played 0,1,2,1
##               odd k:  waterfall at (bx + 6, by): 2 x 1 tiles per frame, 3 frames stacked
##                       vertically, played 0,1,2; connects left/right only.
##   A2  16 x 12  floors: 8 x 4 floor blocks (2 x 3 tiles), kind k at ((k % 8) * 2, (k / 8) * 3).
##   A3  16 x 8   building walls/roofs: 8 x 4 wall blocks (2 x 2), kind k at ((k % 8)*2, (k / 8)*2).
##   A4  16 x 15  interior walls: 6 rows of 8 kinds; row r = k / 8 alternates wall tops (even r,
##                floor blocks, 3 tiles high) and wall sides (odd r, wall blocks, 2 tiles high);
##                block y = 0, 3, 5, 8, 10, 13 for r = 0..5, x = (k % 8) * 2.
##   A5  8 x 16   plain lower tiles, index i at (i % 8, i / 8).
##   B-E 16 x 16  plain upper tiles, 256 per sheet: i < 128 at (i % 8, i / 8), i >= 128 at
##                (8 + i % 8, (i - 128) / 8). B tile 0 is the empty tile (eraser).
## Quarter layouts: RPGAutotileLayout (FLOOR, WALL, WATERFALL).
##
## GENERATED ATLAS (sources; autotile rows are fixed so painted maps survive adding a sheet):
##   source 0  A1 kinds, row = kind (0..15); frame k at row kind + 16k (animation columns 1,
##             separation (0, 15)).
##   source 1  A5: a5_i at (i % 8, i / 8).
##   source 2  B-E: sheet s (0 = B .. 3 = E) tile i at (i % 8, 32s + i / 8)  (b_0 = eraser).
##   source 4  A2 kinds, row = kind (0..31).
##   source 5  A3 kinds, row = kind (0..31).
##   source 6  A4 kinds, row = kind (0..47).
##   Autotile group ids (custom data `autotile`) follow the RPG Maker kind numbering: A1 0..15,
##   A2 16..47, A3 48..79, A4 80..127. Every kind connects only to itself.
## TILE KEYS: a1_0..a1_15, a2_0..a2_31, a3_0..a3_31, a4_0..a4_47, a5_0..a5_127, b_0..b_255,
##   c_*, d_*, e_*.
## DEFAULTS:
##   a1_0..a1_3                 passage 0 (water)
##   a1_4..a1_15                passage 0, review (water, lava, waterfalls...)
##   a2_*                       passage 15
##   a3_*                       passage 0, flags wall (32: casts the auto shadow)
##   a4_* wall tops (even row)  passage 0
##   a4_* wall sides (odd row)  passage 0, flags wall
##   a5_*                       passage 15
##   b_0, empty B-E tiles       passage 15, flags star
##   other B-E tiles            passage 0, review (as 2000/2003 upper tiles)
## OVERLAYS (layout "overlays", see RPGTilesetBuilder; painted with a hidden base by RPGAutotile):
##   a1_1..a1_3 (deep sea and the two decorations): base a1_0, the sea, always (RPG Maker puts
##                this implicit lower tile under them).
##   a2_k with any fully transparent pixel in its block (bushes, forests, mountains, holes,
##                fences, "dark" grass edges ...): base = the ground already on the cell.
##   Decided by the pixels, not by the tileset mode (field / area), which the record does not
##   carry: an opaque A2 kind is a ground tile either way, and a transparent one only looks
##   right over a ground. Other A1 kinds with transparency (VX Ace World "Land's End", clouds)
##   are not overlays: RPG Maker draws them over the panorama.
## NOT DECODED (documented limitations): A2 "table" tiles (drawn with legs in MV), A3/A4 roof
## and wall connections across kinds, and passability flags stored in the original database
## files (MV/MZ data/Tilesets.json is read by the RPG Maker importer instead).

const SHEETS: Array[String] = ["a1", "a2", "a3", "a4", "a5", "b", "c", "d", "e"]
const UPPER_SHEETS: Array[String] = ["b", "c", "d", "e"]

const SOURCE_A1 := 0
const SOURCE_A5 := 1
const SOURCE_UPPER := 2
const SOURCE_A2 := 4
const SOURCE_A3 := 5
const SOURCE_A4 := 6

const GROUP_A1 := 0
const GROUP_A2 := 16
const GROUP_A3 := 48
const GROUP_A4 := 80
const GROUP_COUNT := 128

const A1_KINDS := 16
const A2_KINDS := 32
const A3_KINDS := 32
const A4_KINDS := 48
const A5_TILES := 128
const UPPER_TILES := 256
const UPPER_ROWS := 32
## A1 kinds drawn over the sea (a1_0): deep sea and the two decorations.
const A1_OVERLAY_KINDS := [1, 2, 3]
const WATER_FRAMES := [0, 1, 2, 1]
const WATERFALL_FRAMES := [0, 1, 2]
const FLAG_STAR := 16
const FLAG_WALL := 32

## Size of each sheet in tiles (the profile descriptor holds the pixel sizes).
const SHEET_TILES := {
	"a1": Vector2i(16, 12), "a2": Vector2i(16, 12), "a3": Vector2i(16, 8), "a4": Vector2i(16, 15),
	"a5": Vector2i(8, 16), "b": Vector2i(16, 16), "c": Vector2i(16, 16), "d": Vector2i(16, 16),
	"e": Vector2i(16, 16),
}


## Image name -> sheet path for a tileset record.
static func image_paths(record: Dictionary) -> Dictionary:
	var out := {}
	var sheets: Variant = record.get("sheets", {})
	if sheets is Dictionary:
		for s in SHEETS:
			var p := str((sheets as Dictionary).get(s, ""))
			if p != "" and p != "<null>":
				out[s] = p
	return out


## Expected pixel size of a sheet for a profile.
static func sheet_size(profile: RPGProfile, sheet: String, tile_size: int) -> Vector2i:
	if profile != null:
		var kind := "tileset_" + ("b" if sheet in UPPER_SHEETS else sheet)
		var s := profile.sheet_size(kind)
		if s != Vector2i.ZERO:
			return s
	return SHEET_TILES[sheet] * tile_size


## A1 kind -> {layout, origin (tiles), frames: Array of tile offsets, anim (source frame order)}.
static func a1_kind(k: int) -> Dictionary:
	var still := [Vector2i.ZERO]
	match k:
		0:
			return {"layout": RPGAutotileLayout.LAYOUT_FLOOR, "origin": Vector2i(0, 0), "frames": _water_frames()}
		1:
			return {"layout": RPGAutotileLayout.LAYOUT_FLOOR, "origin": Vector2i(0, 3), "frames": _water_frames()}
		2:
			return {"layout": RPGAutotileLayout.LAYOUT_FLOOR, "origin": Vector2i(6, 0), "frames": still}
		3:
			return {"layout": RPGAutotileLayout.LAYOUT_FLOOR, "origin": Vector2i(6, 3), "frames": still}
	var tx := k % 8
	var ty := k / 8
	var bx := (tx / 4) * 8
	var by := ty * 6 + ((tx / 2) % 2) * 3
	if k % 2 == 0:
		return {"layout": RPGAutotileLayout.LAYOUT_FLOOR, "origin": Vector2i(bx, by), "frames": _water_frames()}
	var wf := []
	for f in WATERFALL_FRAMES:
		wf.append(Vector2i(0, int(f)))
	return {"layout": RPGAutotileLayout.LAYOUT_WATERFALL, "origin": Vector2i(bx + 6, by), "frames": wf}


static func _water_frames() -> Array:
	var out := []
	for f in WATER_FRAMES:
		out.append(Vector2i(int(f) * 2, 0))
	return out


## A4 kind -> {layout, origin (tiles)}.
static func a4_kind(k: int) -> Dictionary:
	var r := k / 8
	var by := (r * 5) / 2 if r % 2 == 0 else (r * 5 + 1) / 2
	var layout := RPGAutotileLayout.LAYOUT_FLOOR if r % 2 == 0 else RPGAutotileLayout.LAYOUT_WALL
	return {"layout": layout, "origin": Vector2i((k % 8) * 2, by)}


## Pixel rect of plain tile i of an upper sheet (B-E).
static func upper_rect(i: int, tile_size: int) -> Rect2i:
	var x := (i / 128) * 8 + i % 8
	var y := (i % 128) / 8
	return Rect2i(x * tile_size, y * tile_size, tile_size, tile_size)


static func a5_rect(i: int, tile_size: int) -> Rect2i:
	return Rect2i((i % 8) * tile_size, (i / 8) * tile_size, tile_size, tile_size)


## True when the rect of an RGBA8 image has a fully transparent pixel.
static func has_clear_pixel(img: Image, rect: Rect2i) -> bool:
	var data := img.get_region(rect).get_data()
	for i in range(3, data.size(), 4):
		if data[i] == 0:
			return true
	return false


## Decodes loaded RGBA8 images (names from image_paths) into a generic layout
## (RPGTilesetBuilder.new_layout).
static func decode(profile_id: String, images: Dictionary, tile_size: int, frame_time: float) -> Dictionary:
	var t := tile_size
	var out := RPGTilesetBuilder.new_layout(profile_id, t)
	var profile := RPGProfile.load_profile(profile_id)
	for s in SHEETS:
		var img: Image = images.get(s)
		if img == null:
			continue
		var want := sheet_size(profile, s, t)
		if img.get_size() != want:
			out.warnings.append("Sheet %s must be %dx%d for the %s profile, got %dx%d. Skipped." % [s.to_upper(), want.x, want.y, profile_id, img.get_width(), img.get_height()])
			continue
		out.images[s] = img
	if out.images.is_empty():
		out.errors.append("No usable A1-A5 or B-E sheet for the %s profile." % profile_id)
		return out
	for g in GROUP_COUNT:
		out.classes.append(_group_key(g))
	# A1
	if out.images.has("a1"):
		var max_frames := 1
		for k in A1_KINDS:
			var d := a1_kind(k)
			var frames: Array[Vector2i] = []
			for f in d.frames:
				frames.append((f as Vector2i) * t)
			max_frames = maxi(max_frames, frames.size())
			_add_group(out, "a1_%d" % k, GROUP_A1 + k, SOURCE_A1, k, "a1", d.origin * t, d.layout, frames, frame_time)
			var bt := RPGAutotileLayout.block_tiles(d.layout)
			var span := Vector2i(bt.x, bt.y)
			if d.layout == RPGAutotileLayout.LAYOUT_WATERFALL:
				span.y = 3
			elif frames.size() > 1:
				span.x = 6
			out.key_rects["a1_%d" % k] = [["a1", Rect2i(d.origin * t, span * t)]]
			out.defaults["a1_%d" % k] = {"passage": 0, "flags": 0, "terrain": 0}
			if k >= 4:
				out.review.append("a1_%d" % k)
			if k in A1_OVERLAY_KINDS:
				out.overlays[GROUP_A1 + k] = "a1_0"
		out.autotile_sources.append({"id": SOURCE_A1, "rows": A1_KINDS, "frames": max_frames})
	# A2
	if out.images.has("a2"):
		for k in A2_KINDS:
			var o := Vector2i((k % 8) * 2, (k / 8) * 3) * t
			_add_still(out, "a2_%d" % k, GROUP_A2 + k, SOURCE_A2, k, "a2", o, RPGAutotileLayout.LAYOUT_FLOOR)
			out.defaults["a2_%d" % k] = {"passage": 15, "flags": 0, "terrain": 0}
			if has_clear_pixel(out.images.a2, Rect2i(o, RPGAutotileLayout.block_tiles(RPGAutotileLayout.LAYOUT_FLOOR) * t)):
				out.overlays[GROUP_A2 + k] = ""
		out.autotile_sources.append({"id": SOURCE_A2, "rows": A2_KINDS, "frames": 1})
	# A3
	if out.images.has("a3"):
		for k in A3_KINDS:
			var o3 := Vector2i((k % 8) * 2, (k / 8) * 2) * t
			_add_still(out, "a3_%d" % k, GROUP_A3 + k, SOURCE_A3, k, "a3", o3, RPGAutotileLayout.LAYOUT_WALL)
			out.defaults["a3_%d" % k] = {"passage": 0, "flags": FLAG_WALL, "terrain": 0}
		out.autotile_sources.append({"id": SOURCE_A3, "rows": A3_KINDS, "frames": 1})
	# A4
	if out.images.has("a4"):
		for k in A4_KINDS:
			var d4 := a4_kind(k)
			_add_still(out, "a4_%d" % k, GROUP_A4 + k, SOURCE_A4, k, "a4", d4.origin * t, d4.layout)
			var wall: bool = d4.layout == RPGAutotileLayout.LAYOUT_WALL
			out.defaults["a4_%d" % k] = {"passage": 0, "flags": FLAG_WALL if wall else 0, "terrain": 0}
		out.autotile_sources.append({"id": SOURCE_A4, "rows": A4_KINDS, "frames": 1})
	# A5
	if out.images.has("a5"):
		out.plain_sources.append({"id": SOURCE_A5, "cols": 8, "rows": A5_TILES / 8})
		for i in A5_TILES:
			var key := "a5_%d" % i
			var r := a5_rect(i, t)
			out.plain.append({"key": key, "source": SOURCE_A5, "coords": Vector2i(i % 8, i / 8), "image": "a5", "rect": r})
			out.key_rects[key] = [["a5", r]]
			out.defaults[key] = {"passage": 15, "flags": 0, "terrain": 0}
	# B-E
	var last := -1
	for si in UPPER_SHEETS.size():
		if out.images.has(UPPER_SHEETS[si]):
			last = si
	if last >= 0:
		out.plain_sources.append({"id": SOURCE_UPPER, "cols": 8, "rows": UPPER_ROWS * (last + 1)})
	for si in UPPER_SHEETS.size():
		var sname: String = UPPER_SHEETS[si]
		if not out.images.has(sname):
			continue
		var img2: Image = out.images[sname]
		for i in UPPER_TILES:
			var key2 := "%s_%d" % [sname, i]
			var r2 := upper_rect(i, t)
			out.plain.append({"key": key2, "source": SOURCE_UPPER, "coords": Vector2i(i % 8, si * UPPER_ROWS + i / 8), "image": sname, "rect": r2})
			out.key_rects[key2] = [[sname, r2]]
			if (si == 0 and i == 0) or img2.get_region(r2).is_invisible():
				out.defaults[key2] = {"passage": 15, "flags": FLAG_STAR, "terrain": 0}
			else:
				out.defaults[key2] = {"passage": 0, "flags": 0, "terrain": 0}
				out.review.append(key2)
	return out


static func _add_still(out: Dictionary, key: String, group: int, source: int, row: int, image: String, origin: Vector2i, layout: String) -> void:
	var frames: Array[Vector2i] = [Vector2i.ZERO]
	_add_group(out, key, group, source, row, image, origin, layout, frames, 0.0)
	var bt := RPGAutotileLayout.block_tiles(layout) * int(out.tile_size)
	out.key_rects[key] = [[image, Rect2i(origin, bt)]]


static func _add_group(out: Dictionary, key: String, group: int, source: int, row: int, image: String, origin: Vector2i, layout: String, frames: Array[Vector2i], frame_time: float) -> void:
	out.groups.append({
		"key": key, "group": group, "source": source, "row": row, "class": key, "image": image,
		"origin": origin, "layout": layout, "frames": frames, "frame_time": frame_time,
	})


## Tile key of an autotile group id (RPG Maker kind numbering).
static func _group_key(g: int) -> String:
	if g < GROUP_A2:
		return "a1_%d" % g
	if g < GROUP_A3:
		return "a2_%d" % (g - GROUP_A2)
	if g < GROUP_A4:
		return "a3_%d" % (g - GROUP_A3)
	return "a4_%d" % (g - GROUP_A4)
