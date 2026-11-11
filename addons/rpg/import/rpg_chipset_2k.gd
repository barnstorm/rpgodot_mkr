@tool
class_name RPGChipset2k
extends RefCounted
## Decoder for the RPG Maker 2000/2003 ChipSet (480x256, 16 px tiles, 30x16 tiles).
## Original code written for this project from layout notes; no EasyRPG source was used.
##
## LAYOUT (pixel coordinates)
##   x   0.. 47, y   0.. 63  water A           (3 animation frames = 3 columns of 16 px)
##   x  48.. 95, y   0.. 63  water B           (3 frames)
##   x   0.. 47, y  64..127  deep water block C (3 frames)
##   x  48.. 95, y  64..127  3 animated tiles, one per 16 px column, 4 frames stacked vertically
##   x   0.. 95, y 128..255  terrain autotiles 0..3  (2 x 2 blocks of 48x64, row-major)
##   x  96..191, y   0..255  terrain autotiles 4..11 (2 x 4 blocks of 48x64, row-major)
##   x 192..287, y   0..255  lower tiles   0..95  (6 x 16, row-major)
##   x 288..383, y   0..127  lower tiles  96..143 (6 x 8, row-major)
##   x 288..383, y 128..255  upper tiles   0..47  (6 x 8, row-major; upper 0 = empty/eraser)
##   x 384..479, y   0..255  upper tiles  48..143 (6 x 16, row-major)
##
## Terrain autotile block (48x64 = 3x4 tiles, XP-style quarter format):
##   (0,0) palette/preview tile   (1,0) unused   (2,0) inner (concave) corners
##   rows 1..3: a 3x3 patch: corners = outer corners, sides = edges, (1,2) = centre fill.
##   Quarter selection: FILL -> (1,2); INNER -> (2,0); OUTER -> (0|2, 1|3);
##   VERT (left/right edge) -> (0|2, 2); HORZ (top/bottom edge) -> (1, 1|3); always the
##   quarter in the same quadrant (TL quarter of the cell comes from a TL quarter).
##
## Water block A/B (48x64): column f = animation frame f; each column is 4 tiles:
##   row 0 outer corners, row 1 left/right (VERT) edges, row 2 top/bottom (HORZ) edges,
##   row 3 inner corners. The open-water FILL quarters come from block C: row 0 = shallow fill
##   (water A/B), row 3 = deep fill (deep water). Deep water uses water A's border pieces.
##   (Checked on the official 2000 and 2003 RTP ChipSets: C row 0 has the colours of the water
##   inside the A/B border pieces, row 3 is the darker deep water, rows 1..2 blend the two.)
## Deep/shallow blend (block C rows 1 and 2), measured on the 2003 RTP sheets (World, Exterior,
##   Dungeon, Interior), whose deep and shallow palettes share no colour, by marking every pixel
##   of rows 1..2 as deep-only or shallow-only:
##     row 1 = a round pool of shallow water in deep water: each quarter is shallow towards the
##             tile centre and deep along its two outer edges and outer corner;
##     row 2 = a round patch of deep water in shallow water: each quarter is deep towards the
##             centre and shallow along its outer edges and corner.
##   So a row-2 quarter is a convex corner of deep water and a row-1 quarter a concave one.
##   Rule used here (one bit per quarter): a FILL quarter of deep water whose vertical AND
##   horizontal neighbours are both shallow water (A or B) takes C row 2 instead of row 3; a
##   FILL quarter of shallow water whose vertical and horizontal neighbours are both deep water
##   takes C row 1 instead of row 0. Deep areas get round corners, a lone deep cell is a round
##   patch, a shallow hole in deep water is round; straight runs stay straight. Border quarters
##   (next to land) are unchanged. Chosen by rendering five candidate rules on the 2003 RTP
##   World ChipSet: "any neighbour" rules put spikes at every seam (the pieces are corners, not
##   edges). The 2000 RTP rows 1..2 use nearly the same colours as rows 0 and 3, so the
##   rounding is subtle there. (No EasyRPG or RPG Maker code was consulted; the rule is read
##   off the art.)
##   All three water groups connect to each other (class "water"); terrains connect only to
##   themselves. Water animates 0,1,2,1 (4 atlas frames) by default.
##
## VERIFIED (and where):
##   - 480x256 sheet, 16x16 tiles, 30 x 16 chips: EasyRPG wiki "Media file format
##     specifications" and Wikibooks "RPG Maker 2003/ChipSets".
##   - Water animation sits at the top-left in 3x4-tile blocks; autotiles are "three columns of
##     four tiles" (3x4 blocks): Wikibooks RPG Maker 2003/ChipSets, rpgmaker.net forum topic
##     12828 (search summary), ynfg tileset guide (water has 3 frames; room for three 4-frame
##     animations).
## ASSUMPTIONS (from general community knowledge of the format, not confirmed by a primary
## source during implementation; each is isolated in a constant below so it can be fixed):
##   - exact block positions above, row-major ordering of the 12 terrain blocks and of the
##     lower/upper tile lists, upper tile 0 being the eraser;
##   - the row meaning inside water columns (rows 1/2 VERT vs HORZ in particular);
##   - terrain isolated tile (variant 46) built from the four outer-corner quarters, (0,0) used
##     only as the palette tile (variant 47);
##   - animated tiles: 4 frames stacked vertically per column, played 0,1,2,3.
## Transparency: real 2000/2003 sheets are 8-bit indexed with palette index 0 as the
## transparent colour, everywhere on the sheet (a transparent lower tile or terrain shows the
## panorama). Godot keeps it only when the PNG has a tRNS chunk (most 2003 RTP sheets do; the
## RPG Maker importer adds one to the others). If the sheet has no alpha at all, the colour of
## the eraser tile's top-left pixel (288,128) is keyed out on the whole sheet.

const SHEET_SIZE := Vector2i(480, 256)
const TILE := 16
const HALF := 8
const LOWER_COUNT := 144
const UPPER_COUNT := 144
const ANIM_COUNT := 3
const ANIM_FRAMES := 4
const WATER_FRAMES := 3
const TERRAIN_COUNT := 12

const WATER_A_ORIGIN := Vector2i(0, 0)
const WATER_B_ORIGIN := Vector2i(48, 0)
const WATER_C_ORIGIN := Vector2i(0, 64)
const ANIM_ORIGIN := Vector2i(48, 64)
## Rows inside a water column (tile units) per quarter kind.
const WATER_ROW_OUTER := 0
const WATER_ROW_VERT := 1
const WATER_ROW_HORZ := 2
const WATER_ROW_INNER := 3
## Rows of block C holding the fill pieces.
const C_ROW_SHALLOW := 0
const C_ROW_DEEP := 3
## Rows of block C with the blend pieces: shallow next to deep, deep next to shallow.
const C_ROW_SHALLOW_BLEND := 1
const C_ROW_DEEP_BLEND := 2
## Quarter-bit combinations (1..15) of blended FILL quarters, per water group.
const BLEND_COMBOS := 15
const ERASER_PIXEL := Vector2i(288, 128)

## Group indices (also the row in the generated autotile atlas).
const GROUP_WATER_A := 0
const GROUP_WATER_B := 1
const GROUP_WATER_C := 2
const GROUP_TERRAIN_0 := 3
const GROUP_COUNT := 15

const PINGPONG := [0, 1, 2, 1]


static func terrain_origin(i: int) -> Vector2i:
	if i < 4:
		return Vector2i((i % 2) * 48, 128 + (i / 2) * 64)
	var j := i - 4
	return Vector2i(96 + (j % 2) * 48, (j / 2) * 64)


static func lower_rect(i: int) -> Rect2i:
	if i < 96:
		return Rect2i(192 + (i % 6) * TILE, (i / 6) * TILE, TILE, TILE)
	var j := i - 96
	return Rect2i(288 + (j % 6) * TILE, (j / 6) * TILE, TILE, TILE)


static func upper_rect(i: int) -> Rect2i:
	if i < 48:
		return Rect2i(288 + (i % 6) * TILE, 128 + (i / 6) * TILE, TILE, TILE)
	var j := i - 48
	return Rect2i(384 + (j % 6) * TILE, (j / 6) * TILE, TILE, TILE)


static func anim_frame_rect(i: int, frame: int) -> Rect2i:
	return Rect2i(ANIM_ORIGIN.x + i * TILE, ANIM_ORIGIN.y + frame * TILE, TILE, TILE)


## Description of every autotile group: {key, kind ("water"|"terrain"), connect_class,
## frames (source frames), anim (atlas frame order), origin, block: Rect2i}.
static func group_info(g: int) -> Dictionary:
	match g:
		GROUP_WATER_A:
			return {"key": "water_a", "kind": "water", "connect_class": "water", "frames": WATER_FRAMES, "anim": PINGPONG, "origin": WATER_A_ORIGIN, "block": Rect2i(WATER_A_ORIGIN, Vector2i(48, 64))}
		GROUP_WATER_B:
			return {"key": "water_b", "kind": "water", "connect_class": "water", "frames": WATER_FRAMES, "anim": PINGPONG, "origin": WATER_B_ORIGIN, "block": Rect2i(WATER_B_ORIGIN, Vector2i(48, 64))}
		GROUP_WATER_C:
			return {"key": "water_c", "kind": "water", "connect_class": "water", "frames": WATER_FRAMES, "anim": PINGPONG, "origin": WATER_A_ORIGIN, "block": Rect2i(WATER_C_ORIGIN, Vector2i(48, 64))}
	var t := g - GROUP_TERRAIN_0
	var o := terrain_origin(t)
	return {"key": "terrain_%d" % t, "kind": "terrain", "connect_class": "terrain_%d" % t, "frames": 1, "anim": [0], "origin": o, "block": Rect2i(o, Vector2i(48, 64))}


static func group_keys() -> Array[String]:
	var out: Array[String] = []
	for g in GROUP_COUNT:
		out.append(group_info(g).key)
	return out


## Source rects of the four quarters [TL, TR, BL, BR] for a group, variant (0..47) and source frame.
## `blend` (water only): quarter bits (TL 1, TR 2, BL 4, BR 8) whose FILL quarter uses the
## deep/shallow blend piece (header).
static func quarter_rects(g: int, variant: int, frame := 0, blend := 0) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var info := group_info(g)
	if info.kind == "terrain" and variant == RPGAutotile.PREVIEW_VARIANT:
		var o: Vector2i = info.origin
		for q in 4:
			out.append(Rect2i(o + Vector2i((q % 2) * HALF, (q / 2) * HALF), Vector2i(HALF, HALF)))
		return out
	var mask := RPGAutotile.mask_for_variant(variant)
	var kinds := RPGAutotile.quarter_kinds(mask)
	for q in 4:
		out.append(quarter_rect_for_kind(g, kinds[q], q, frame, blend & (1 << q) != 0))
	return out


## Water groups that blend with water group g (deep with shallow and back), or [].
static func blend_partners(g: int) -> Array:
	match g:
		GROUP_WATER_A, GROUP_WATER_B:
			return [GROUP_WATER_C]
		GROUP_WATER_C:
			return [GROUP_WATER_A, GROUP_WATER_B]
	return []


## Row of water group g (0..2) with blend bits 1..15 in the generated blend atlas source
## (RPGTilesetBuilder.SOURCE_WATER_BLEND): the 15 combinations of each water group in turn.
static func blend_row(g: int, blend: int) -> int:
	return g * BLEND_COMBOS + blend - 1


## Source rect of one quarter (q: 0 TL, 1 TR, 2 BL, 3 BR) of a given kind. `blended` (water FILL
## quarters only) takes the deep/shallow blend piece.
static func quarter_rect_for_kind(g: int, kind: int, q: int, frame := 0, blended := false) -> Rect2i:
	var info := group_info(g)
	var qx := q % 2
	var qy := q / 2
	var tile := Vector2i.ZERO
	var origin: Vector2i = info.origin
	if info.kind == "terrain":
		match kind:
			RPGAutotile.KIND_FILL:
				tile = Vector2i(1, 2)
			RPGAutotile.KIND_INNER:
				tile = Vector2i(2, 0)
			RPGAutotile.KIND_OUTER:
				tile = Vector2i(qx * 2, 1 + qy * 2)
			RPGAutotile.KIND_VERT:
				tile = Vector2i(qx * 2, 2)
			RPGAutotile.KIND_HORZ:
				tile = Vector2i(1, 1 + qy * 2)
	else:
		var f := clampi(frame, 0, WATER_FRAMES - 1)
		match kind:
			RPGAutotile.KIND_FILL:
				origin = WATER_C_ORIGIN
				if g == GROUP_WATER_C:
					tile = Vector2i(f, C_ROW_DEEP_BLEND if blended else C_ROW_DEEP)
				else:
					tile = Vector2i(f, C_ROW_SHALLOW_BLEND if blended else C_ROW_SHALLOW)
			RPGAutotile.KIND_OUTER:
				tile = Vector2i(f, WATER_ROW_OUTER)
			RPGAutotile.KIND_VERT:
				tile = Vector2i(f, WATER_ROW_VERT)
			RPGAutotile.KIND_HORZ:
				tile = Vector2i(f, WATER_ROW_HORZ)
			RPGAutotile.KIND_INNER:
				tile = Vector2i(f, WATER_ROW_INNER)
	return Rect2i(origin + tile * TILE + Vector2i(qx * HALF, qy * HALF), Vector2i(HALF, HALF))


## Checks the sheet; returns a list of problems (empty when usable).
static func validate(image: Image) -> Array[String]:
	var out: Array[String] = []
	if image == null or image.is_empty():
		out.append("ChipSet image is missing or empty.")
	elif image.get_size() != SHEET_SIZE:
		out.append("ChipSet must be 480x256, got %dx%d." % [image.get_width(), image.get_height()])
	return out


## Returns an RGBA8 copy with transparency keyed (see header) when the sheet has no alpha.
static func prepare(image: Image) -> Image:
	var img := image.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if not _has_alpha(img):
		var key := img.get_pixelv(ERASER_PIXEL)
		for y in SHEET_SIZE.y:
			for x in SHEET_SIZE.x:
				if img.get_pixel(x, y).is_equal_approx(key):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


static func _has_alpha(img: Image) -> bool:
	return img.detect_alpha() != Image.ALPHA_NONE


## Composes one variant tile (16x16) of a group for a source frame (and blend bits, water only).
static func compose_variant(image: Image, g: int, variant: int, frame := 0, blend := 0) -> Image:
	return RPGAutotile.compose_image(image, quarter_rects(g, variant, frame, blend))


## Full decode into images. Returns:
##   {groups: [{key, kind, connect_class, frames: [frame][variant 0..47] -> Image, anim}],
##    lower: [Image x144], upper: [Image x144], animated: [{key, frames: [Image x4]}], errors}
static func decode(image: Image) -> Dictionary:
	var errors := validate(image)
	if not errors.is_empty():
		return {"groups": [], "lower": [], "upper": [], "animated": [], "errors": errors}
	var img := prepare(image)
	var groups := []
	for g in GROUP_COUNT:
		var info := group_info(g)
		var frames := []
		for f in int(info.frames):
			var variants := []
			for v in RPGAutotile.VARIANT_SLOTS:
				variants.append(compose_variant(img, g, v, f))
			frames.append(variants)
		groups.append({"key": info.key, "kind": info.kind, "connect_class": info.connect_class, "frames": frames, "anim": info.anim})
	var lower := []
	for i in LOWER_COUNT:
		lower.append(img.get_region(lower_rect(i)))
	var upper := []
	for i in UPPER_COUNT:
		upper.append(img.get_region(upper_rect(i)))
	var animated := []
	for i in ANIM_COUNT:
		var fr := []
		for f in ANIM_FRAMES:
			fr.append(img.get_region(anim_frame_rect(i, f)))
		animated.append({"key": "anim_%d" % i, "frames": fr})
	return {"groups": groups, "lower": lower, "upper": upper, "animated": animated, "errors": errors}


## Source pixel rect covered by a tile_key (used for change detection on reimport).
static func key_rects(key: String) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if key.begins_with("lower_"):
		out.append(lower_rect(int(key.substr(6))))
	elif key.begins_with("upper_"):
		out.append(upper_rect(int(key.substr(6))))
	elif key.begins_with("anim_"):
		out.append(Rect2i(ANIM_ORIGIN + Vector2i(int(key.substr(5)) * TILE, 0), Vector2i(TILE, 64)))
	else:
		for g in GROUP_COUNT:
			var info := group_info(g)
			if info.key == key:
				out.append(info.block)
				if info.kind == "water":
					out.append(Rect2i(WATER_C_ORIGIN, Vector2i(48, 64)))
					if g == GROUP_WATER_C:
						out.append(Rect2i(WATER_A_ORIGIN, Vector2i(48, 64)))
	return out


## Every tile_key of the 2000/2003 layout, in a stable order.
static func all_keys() -> Array[String]:
	var out := group_keys()
	for i in ANIM_COUNT:
		out.append("anim_%d" % i)
	for i in LOWER_COUNT:
		out.append("lower_%d" % i)
	for i in UPPER_COUNT:
		out.append("upper_%d" % i)
	return out
