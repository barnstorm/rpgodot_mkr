extends "res://tests/rpg_test_case.gd"
## Golden fixtures for the XP, VX/VX Ace and MV/MZ profiles (spec "Testing and acceptance
## criteria" item 9). Sheets are synthesized: every half-tile cell (qx, qy) of a sheet is filled
## with Color8(qx, qy, tag), so a decoded quarter tells exactly which source quarter it came from.
## Expected quarters below are written out from the published sheet layouts (not computed by the
## decoder), in half-tile units relative to the autotile block, order [TL, TR, BL, BR].

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128
const TMP_ID := "zz_test_profiles_tmp"
const TMP_DIR := "user://zz_test_profiles"

## VX/MV floor block (2 x 3 tiles): mask -> quarters.
const FLOOR_CASES := [
	["full", 255, [[2, 4], [1, 4], [2, 3], [1, 3]]],
	["inner NW", 255 & ~NW, [[2, 0], [1, 4], [2, 3], [1, 3]]],
	["inner NE", 255 & ~NE, [[2, 4], [3, 0], [2, 3], [1, 3]]],
	["inner SW", 255 & ~SW, [[2, 4], [1, 4], [2, 1], [1, 3]]],
	["inner SE", 255 & ~SE, [[2, 4], [1, 4], [2, 3], [3, 1]]],
	["four inner", N | E | S | W, [[2, 0], [3, 0], [2, 1], [3, 1]]],
	["left edge", N | NE | E | SE | S, [[0, 4], [1, 4], [0, 3], [1, 3]]],
	["top edge", E | SE | S | SW | W, [[2, 2], [1, 2], [2, 3], [1, 3]]],
	["right edge", N | S | SW | W | NW, [[2, 4], [3, 4], [2, 3], [3, 3]]],
	["bottom edge", N | NE | E | W | NW, [[2, 4], [1, 4], [2, 5], [1, 5]]],
	["vertical corridor", N | S, [[0, 4], [3, 4], [0, 3], [3, 3]]],
	["horizontal corridor", E | W, [[2, 2], [1, 2], [2, 5], [1, 5]]],
	["top-left corner", E | SE | S, [[0, 2], [1, 2], [0, 3], [1, 3]]],
	["bottom-right corner", N | NW | W, [[2, 4], [3, 4], [2, 5], [3, 5]]],
	["end cap (south only)", S, [[0, 2], [3, 2], [0, 3], [3, 3]]],
	["isolated", 0, [[0, 2], [3, 2], [0, 5], [3, 5]]],
]

## VX/MV wall block (2 x 2 tiles).
const WALL_CASES := [
	["full", 255, [[2, 2], [1, 2], [2, 1], [1, 1]]],
	["full, diagonals ignored", N | E | S | W, [[2, 2], [1, 2], [2, 1], [1, 1]]],
	["left edge", N | NE | E | SE | S, [[0, 2], [1, 2], [0, 1], [1, 1]]],
	["top edge", E | SE | S | SW | W, [[2, 0], [1, 0], [2, 1], [1, 1]]],
	["right edge", N | S | SW | W | NW, [[2, 2], [3, 2], [2, 1], [3, 1]]],
	["bottom edge", N | NE | E | W | NW, [[2, 2], [1, 2], [2, 3], [1, 3]]],
	["isolated", 0, [[0, 0], [3, 0], [0, 3], [3, 3]]],
]

## VX/MV A1 waterfall strip (2 x 1 tiles): only left/right count.
const WATERFALL_CASES := [
	["both sides", E | W, [[2, 0], [1, 0], [2, 1], [1, 1]]],
	["left open", W, [[2, 0], [3, 0], [2, 1], [3, 1]]],
	["right open", E, [[0, 0], [1, 0], [0, 1], [1, 1]]],
	["alone", 0, [[0, 0], [3, 0], [0, 1], [3, 1]]],
	["vertical ignored", N | S, [[0, 0], [3, 0], [0, 1], [3, 1]]],
]

## XP autotile (3 x 4 tiles): quarter numbers 1..48 (6 per row), as RPG Maker XP lists them.
const XP_CASES := [
	["full", 255, [27, 28, 33, 34]],
	["inner NW", 255 & ~NW, [5, 28, 33, 34]],
	["four inner", N | E | S | W, [5, 6, 11, 12]],
	["left edge", N | NE | E | SE | S, [25, 26, 31, 32]],
	["left edge, inner NE", N | E | SE | S, [25, 6, 31, 32]],
	["top edge", E | SE | S | SW | W, [15, 16, 21, 22]],
	["right edge", N | S | SW | W | NW, [29, 30, 35, 36]],
	["bottom edge", N | NE | E | W | NW, [39, 40, 45, 46]],
	["vertical corridor", N | S, [25, 30, 31, 36]],
	["horizontal corridor", E | W, [15, 16, 45, 46]],
	["top-left corner", E | SE | S, [13, 14, 19, 20]],
	["isolated", 0, [13, 18, 43, 48]],
]

var _img_cache: Dictionary = {}


func before_each() -> void:
	_img_cache.clear()


## Sheet of w x h px where half-tile cell (qx, qy) has colour Color8(qx, qy, tag).
func synth(w: int, h: int, half: int, tag: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for qy in h / half:
		for qx in w / half:
			img.fill_rect(Rect2i(qx * half, qy * half, half, half), Color8(qx, qy, tag))
	return img


func src_image(ts: TileSet, sid: int) -> Image:
	var k := "%d:%d" % [ts.get_instance_id(), sid]
	if not _img_cache.has(k):
		_img_cache[k] = (ts.get_source(sid) as TileSetAtlasSource).texture.get_image()
	return _img_cache[k]


## [qx, qy, tag] of the source quarter drawn in quadrant q of a tile (frame = animation frame),
## or ["mixed"] if the quarter is not one uniform source quarter.
func quarter(ts: TileSet, sid: int, coords: Vector2i, q: int, frame := 0) -> Array:
	var src := ts.get_source(sid) as TileSetAtlasSource
	var r := src.get_tile_texture_region(coords, frame)
	var h := r.size.x / 2
	var p := r.position + Vector2i((q % 2) * h, (q / 2) * h)
	var img := src_image(ts, sid)
	var a := img.get_pixelv(p)
	var b := img.get_pixelv(p + Vector2i(h - 1, h - 1))
	if a != b:
		return ["mixed"]
	return [a.r8, a.g8, a.b8]


func expect_quarters(ts: TileSet, sid: int, row: int, origin_half: Vector2i, cases: Array, tag: int, label: String) -> void:
	for c in cases:
		var v := RPGAutotile.variant_for_mask(int(c[1]))
		for q in 4:
			var want: Array = c[2][q]
			assert_eq(quarter(ts, sid, Vector2i(v, row), q), [origin_half.x + int(want[0]), origin_half.y + int(want[1]), tag], "%s %s q%d" % [label, c[0], q])


func distinct_variants(ts: TileSet, sid: int, row: int) -> int:
	var seen := {}
	for v in RPGAutotile.VARIANT_COUNT:
		var key := []
		for q in 4:
			key.append(quarter(ts, sid, Vector2i(v, row), q))
		seen[str(key)] = true
	return seen.size()


func td(ts: TileSet, key: String) -> TileData:
	var a := RPGTilesetBuilder.atlas_for_key(key, ts)
	if a.is_empty():
		return null
	return (ts.get_source(a.source) as TileSetAtlasSource).get_tile_data(a.coords, 0)


func build(profile: String, images: Dictionary, overrides := {}, previous: TileSet = null) -> Dictionary:
	var rep := RPGTilesetBuilder.build_from_images(images, {"id": "fx_" + profile, "profile": profile}, overrides, previous)
	assert_eq(rep.errors, [], "%s builds" % profile)
	return rep


# --- VX / MV A2 floors (priority 1) ------------------------------------------------------------

func test_vx_a2_floor_fixture() -> void:
	var rep := build("vx", {"a2": synth(512, 384, 16, 2)})
	var ts: TileSet = rep.tileset
	assert_eq(ts.tile_size, Vector2i(32, 32), "vx tile size")
	assert_eq(ts.get_meta("rpg_autotile_sources"), [RPGTilesheetVX.SOURCE_A2], "only the A2 autotile source")
	# kind 9 = block column 1, row 1 -> tiles (2, 3) -> half (4, 6)
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A2, 9, Vector2i(4, 6), FLOOR_CASES, 2, "a2_9")
	# palette tile (variant 47) is block tile (0,0)
	for q in 4:
		assert_eq(quarter(ts, RPGTilesheetVX.SOURCE_A2, Vector2i(47, 9), q), [4 + q % 2, 6 + q / 2, 2], "a2_9 palette q%d" % q)
	assert_eq(distinct_variants(ts, RPGTilesheetVX.SOURCE_A2, 9), 47, "47 distinct floor variants")
	# kind 31 = last block (14, 9) tiles
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A2, 31, Vector2i(28, 18), [FLOOR_CASES[0], FLOOR_CASES[15]], 2, "a2_31")
	assert_eq(RPGTilesetBuilder.atlas_for_key("a2_9", ts), {"source": RPGTilesheetVX.SOURCE_A2, "coords": Vector2i(47, 9)}, "atlas_for_key with TileSet")
	assert_eq(td(ts, "a2_9").get_custom_data("autotile"), RPGTilesheetVX.GROUP_A2 + 9, "group id = RPG Maker kind")
	assert_eq(td(ts, "a2_9").get_custom_data("passage"), 15, "floors open")
	assert_eq(td(ts, "a2_9").get_custom_data("tile_key"), "a2_9", "tile key")
	var src := ts.get_source(RPGTilesheetVX.SOURCE_A2) as TileSetAtlasSource
	assert_eq(src.get_tile_data(Vector2i(20, 9), 0).get_custom_data("tile_key"), "a2_9", "every variant keyed")
	assert_eq(src.get_tile_animation_frames_count(Vector2i(0, 9)), 1, "A2 is still")
	assert_eq(ts.get_meta("rpg_autotile_classes")[RPGTilesheetVX.GROUP_A2 + 9], "a2_9", "class")


func test_mv_a2_uses_48px_tiles() -> void:
	var rep := build("mv", {"a2": synth(768, 576, 24, 3)})
	var ts: TileSet = rep.tileset
	assert_eq(ts.tile_size, Vector2i(48, 48), "mv tile size")
	assert_eq(ts.get_meta("rpg_tile_size"), 48, "tile size meta")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A2, 0, Vector2i(0, 0), FLOOR_CASES, 3, "mv a2_0")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A2, 20, Vector2i(16, 12), FLOOR_CASES, 3, "mv a2_20")
	var wrong := RPGTilesetBuilder.build_from_images({"a2": synth(512, 384, 16, 3)}, {"id": "x", "profile": "mv"})
	assert_true(wrong.tileset == null and not wrong.errors.is_empty(), "VX-size sheet rejected by mv")
	assert_false(wrong.warnings.is_empty(), "size warning names the sheet")


# --- XP autotiles (priority 2) -----------------------------------------------------------------

func xp_cell(n: int) -> Array:
	return [(n - 1) % 6, (n - 1) / 6]


func test_xp_autotile_fixture() -> void:
	var images := {
		"tileset": synth(256, 64, 16, 9),
		"autotile_0": synth(96, 128, 16, 10),
		"autotile_3": synth(384, 128, 16, 13),
		"autotile_5": synth(32, 32, 16, 15),
	}
	var rep := build("xp", images)
	var ts: TileSet = rep.tileset
	assert_eq(ts.tile_size, Vector2i(32, 32), "xp tile size")
	var cases := []
	for c in XP_CASES:
		var qs := []
		for n in c[2]:
			qs.append(xp_cell(int(n)))
		cases.append([c[0], c[1], qs])
	expect_quarters(ts, 0, 0, Vector2i.ZERO, cases, 10, "autotile_0")
	for q in 4:
		assert_eq(quarter(ts, 0, Vector2i(47, 0), q), [q % 2, q / 2, 10], "palette tile q%d" % q)
	assert_eq(distinct_variants(ts, 0, 0), 47, "47 distinct XP variants")
	# Animated autotile: 384 px wide = 4 frames, 96 px (6 half tiles) apart, stacked every 7 rows.
	var src := ts.get_source(0) as TileSetAtlasSource
	var c3 := Vector2i(RPGAutotile.variant_for_mask(0), 3)
	assert_eq(src.get_tile_animation_frames_count(c3), 4, "4 frames")
	assert_eq(src.get_tile_animation_columns(c3), 1, "frames stacked vertically")
	assert_eq(src.get_tile_animation_separation(c3), Vector2i(0, 6), "7 rows per frame")
	assert_eq(src.get_tile_animation_frame_duration(c3, 2), 0.4, "XP frame time")
	for k in 4:
		assert_eq(quarter(ts, 0, c3, 1, k), [5 + 6 * k, 2, 13], "frame %d isolated TR" % k)
		assert_eq(quarter(ts, 0, Vector2i(0, 3), 0, k), [2 + 6 * k, 4, 13], "frame %d full TL" % k)
	# 32x32 autotile: every variant is the tile itself.
	for v in [0, 17, 46, 47]:
		for q in 4:
			assert_eq(quarter(ts, 0, Vector2i(v, 5), q), [q % 2, q / 2, 15], "single autotile v%d q%d" % [v, q])
	assert_true(td(ts, "autotile_1") == null, "missing slot has no tiles")
	assert_eq(td(ts, "autotile_3").get_custom_data("passage"), 0, "animated autotile defaults to blocked")
	assert_eq(td(ts, "autotile_0").get_custom_data("passage"), 15, "still autotile defaults to open")
	assert_has(rep.review, "autotile_0", "autotiles reviewed")
	assert_eq(td(ts, "autotile_3").get_custom_data("autotile"), 3, "group = slot")
	# A broken autotile is skipped with a warning, the rest still builds.
	var bad := RPGTilesetBuilder.build_from_images({"tileset": synth(256, 32, 16, 9), "autotile_2": synth(100, 128, 4, 1)}, {"id": "b", "profile": "xp"})
	assert_eq(bad.errors, [], "bad autotile is not fatal")
	assert_false(bad.warnings.is_empty(), "bad autotile reported")
	var no_ts := RPGTilesetBuilder.build_from_images({"autotile_0": synth(96, 128, 16, 1)}, {"id": "b", "profile": "xp"})
	assert_false(no_ts.errors.is_empty(), "XP needs its tileset image")


func test_xp_tileset_tiles() -> void:
	var sheet := synth(256, 96, 16, 9)
	sheet.fill_rect(Rect2i(0, 0, 32, 32), Color(0, 0, 0, 0))     # tile_0 (eraser)
	sheet.fill_rect(Rect2i(64, 0, 32, 32), Color(0, 0, 0, 0))    # tile_2 empty
	sheet.fill_rect(Rect2i(96, 0, 16, 32), Color(0, 0, 0, 0))    # tile_3 half transparent
	var rep := build("xp", {"tileset": sheet})
	var ts: TileSet = rep.tileset
	assert_eq(RPGTilesetBuilder.atlas_for_key("tile_0", ts), {"source": RPGTilesetBuilder.SOURCE_UPPER, "coords": Vector2i.ZERO}, "tile_0 is the eraser slot")
	assert_eq(RPGTilesetBuilder.atlas_for_key("tile_21", ts), {"source": RPGTilesetBuilder.SOURCE_UPPER, "coords": Vector2i(5, 2)}, "8 columns")
	assert_eq(quarter(ts, 2, Vector2i(5, 2), 3), [11, 5, 9], "tile_21 pixels")
	assert_eq(td(ts, "tile_0").get_custom_data("flags"), 16, "eraser star")
	assert_eq(td(ts, "tile_2").get_custom_data("flags"), 16, "empty tile star")
	assert_eq(td(ts, "tile_1").get_custom_data("passage"), 15, "opaque tile = ground, open")
	assert_eq(td(ts, "tile_3").get_custom_data("passage"), 0, "tile with transparency = object, blocked")
	assert_has(rep.review, "tile_1", "ground reviewed")
	assert_has(rep.review, "tile_3", "object reviewed")
	assert_false(rep.review.has("tile_2"), "empty tile not reviewed")
	assert_eq(td(ts, "tile_23").get_custom_data("tile_key"), "tile_23", "last tile")
	assert_true(td(ts, "tile_24") == null, "no tile past the sheet")
	assert_false(ts.has_source(RPGTilesetBuilder.SOURCE_LOWER), "XP has no lower source")
	var wrong := RPGTilesetBuilder.build_from_images({"tileset": synth(240, 64, 16, 1)}, {"id": "b", "profile": "xp"})
	assert_false(wrong.errors.is_empty(), "XP tileset must be 256 px wide")


# --- plain sheets (priority 3) -----------------------------------------------------------------

func test_vx_a5_and_b_to_e() -> void:
	var b := synth(512, 512, 16, 20)
	b.fill_rect(Rect2i(32, 0, 32, 32), Color(0, 0, 0, 0))  # b_1 empty
	var rep := build("vx", {"a5": synth(256, 512, 16, 25), "b": b, "c": synth(512, 512, 16, 21)})
	var ts: TileSet = rep.tileset
	# A5 tile 9 -> (1, 1)
	assert_eq(RPGTilesetBuilder.atlas_for_key("a5_9", ts), {"source": RPGTilesetBuilder.SOURCE_LOWER, "coords": Vector2i(1, 1)}, "a5_9 coords")
	assert_eq(quarter(ts, 1, Vector2i(1, 1), 0), [2, 2, 25], "a5_9 pixels")
	assert_eq(td(ts, "a5_9").get_custom_data("passage"), 15, "A5 open")
	# B tile 130 sits in the right half of the sheet: (8 + 2, 0)
	assert_eq(RPGTilesetBuilder.atlas_for_key("b_130", ts).coords, Vector2i(2, 16), "b_130 atlas coords")
	assert_eq(quarter(ts, 2, Vector2i(2, 16), 0), [20, 0, 20], "b_130 from the right half")
	assert_eq(quarter(ts, 2, Vector2i(7, 15), 3), [15, 31, 20], "b_127 last of the left half")
	# C follows B, 32 rows further down
	assert_eq(RPGTilesetBuilder.atlas_for_key("c_5", ts).coords, Vector2i(5, 32), "c_5 coords")
	assert_eq(quarter(ts, 2, Vector2i(5, 32), 0), [10, 0, 21], "c_5 pixels")
	assert_eq((ts.get_source(2) as TileSetAtlasSource).get_atlas_grid_size(), Vector2i(8, 64), "B and C only")
	assert_true(td(ts, "d_0") == null, "no D sheet")
	assert_eq(td(ts, "b_0").get_custom_data("flags"), 16, "b_0 eraser star")
	assert_eq(td(ts, "b_0").z_index, 3, "star z")
	assert_eq(td(ts, "b_1").get_custom_data("flags"), 16, "empty B tile star")
	assert_eq(td(ts, "b_2").get_custom_data("passage"), 0, "B tile with pixels blocked")
	assert_has(rep.review, "b_2", "B tile reviewed")
	assert_eq(RPGTilesetBuilder.default_layer_for(2), 2, "B-E go to the upper layer")


# --- A1 water, A3/A4 walls (priority 4) --------------------------------------------------------

func test_vx_a1_water_and_waterfalls() -> void:
	var rep := build("vx", {"a1": synth(512, 384, 16, 30)})
	var ts: TileSet = rep.tileset
	var src := ts.get_source(0) as TileSetAtlasSource
	# kind 0: sea at (0,0), frames 2 tiles (4 half) apart, played 0,1,2,1
	var c0 := Vector2i(0, 0)
	assert_eq(src.get_tile_animation_frames_count(c0), 4, "sea 4 atlas frames")
	assert_eq(src.get_tile_animation_separation(c0), Vector2i(0, 15), "16 rows per frame")
	assert_eq(src.get_tile_animation_frame_duration(c0, 0), 0.5, "vx frame time")
	var xs := [0, 4, 8, 4]
	for k in 4:
		assert_eq(quarter(ts, 0, c0, 0, k), [2 + xs[k], 4, 30], "sea frame %d full TL" % k)
	expect_quarters(ts, 0, 0, Vector2i(0, 0), FLOOR_CASES, 30, "a1_0")
	# kind 1: deep sea at (0,3)
	expect_quarters(ts, 0, 1, Vector2i(0, 6), [FLOOR_CASES[0], FLOOR_CASES[15]], 30, "a1_1")
	# kind 2: decoration at (6,0), still
	assert_eq(src.get_tile_animation_frames_count(Vector2i(0, 2)), 1, "decoration still")
	expect_quarters(ts, 0, 2, Vector2i(12, 0), [FLOOR_CASES[0]], 30, "a1_2")
	# kind 12: water at tiles (8,6); kind 5: waterfall at tiles (14,0), 3 frames one tile apart
	expect_quarters(ts, 0, 12, Vector2i(16, 12), FLOOR_CASES, 30, "a1_12")
	expect_quarters(ts, 0, 5, Vector2i(28, 0), WATERFALL_CASES, 30, "a1_5")
	var c5 := Vector2i(RPGAutotile.variant_for_mask(E | W), 5)
	assert_eq(src.get_tile_animation_frames_count(c5), 3, "waterfall 3 frames")
	for k in 3:
		assert_eq(quarter(ts, 0, c5, 2, k), [30, 1 + 2 * k, 30], "waterfall frame %d BL" % k)
	# kind 15: waterfall at tiles (14, 9)
	expect_quarters(ts, 0, 15, Vector2i(28, 18), WATERFALL_CASES, 30, "a1_15")
	assert_eq(td(ts, "a1_0").get_custom_data("passage"), 0, "water blocked")
	assert_has(rep.review, "a1_5", "waterfall reviewed")
	assert_false(rep.review.has("a1_0"), "sea not reviewed")


func test_vx_a3_a4_walls() -> void:
	var rep := build("vx", {"a3": synth(512, 256, 16, 40), "a4": synth(512, 480, 16, 41)})
	var ts: TileSet = rep.tileset
	# A3 kind 10 -> tiles (4, 2)
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A3, 10, Vector2i(8, 4), WALL_CASES, 40, "a3_10")
	assert_eq(distinct_variants(ts, RPGTilesheetVX.SOURCE_A3, 10), 16, "16 wall shapes")
	for q in 4:
		assert_eq(quarter(ts, RPGTilesheetVX.SOURCE_A3, Vector2i(47, 10), q), quarter(ts, RPGTilesheetVX.SOURCE_A3, Vector2i(46, 10), q), "wall palette = isolated q%d" % q)
	assert_eq(td(ts, "a3_10").get_custom_data("flags"), 32, "A3 casts shadow")
	assert_eq(td(ts, "a3_10").get_custom_data("passage"), 0, "A3 blocked")
	# A4: wall tops (floor layout) at y = 0, 5, 10; wall sides (wall layout) at y = 3, 8, 13 tiles
	# (half-tile origin = 2 x tile origin)
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A4, 3, Vector2i(12, 0), FLOOR_CASES, 41, "a4_3 top")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A4, 8, Vector2i(0, 6), WALL_CASES, 41, "a4_8 side")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A4, 17, Vector2i(4, 10), FLOOR_CASES, 41, "a4_17 top")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A4, 31, Vector2i(28, 16), WALL_CASES, 41, "a4_31 side")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A4, 32, Vector2i(0, 20), FLOOR_CASES, 41, "a4_32 top")
	expect_quarters(ts, RPGTilesheetVX.SOURCE_A4, 47, Vector2i(28, 26), WALL_CASES, 41, "a4_47 side")
	assert_eq(td(ts, "a4_8").get_custom_data("flags"), 32, "wall side casts shadow")
	assert_eq(td(ts, "a4_3").get_custom_data("flags"), 0, "wall top no shadow flag")
	assert_eq(td(ts, "a4_3").get_custom_data("autotile"), RPGTilesheetVX.GROUP_A4 + 3, "A4 group id")


# --- painting through the TileSet contract -----------------------------------------------------

func paint_key(l: TileMapLayer, key: String, c: Vector2i) -> void:
	var a := RPGTilesetBuilder.atlas_for_key(key, l.tile_set)
	RPGAutotile.paint(l, c, a.source, a.coords)


func test_paint_vx_and_xp_autotiles() -> void:
	var ts: TileSet = build("vx", {"a2": synth(512, 384, 16, 2), "a3": synth(512, 256, 16, 4), "b": synth(512, 512, 16, 5)}).tileset
	var l := TileMapLayer.new()
	l.tile_set = ts
	for y in 3:
		for x in 3:
			paint_key(l, "a2_3", Vector2i(x, y))
	assert_eq(l.get_cell_source_id(Vector2i(1, 1)), RPGTilesheetVX.SOURCE_A2, "source kept")
	assert_eq(l.get_cell_atlas_coords(Vector2i(1, 1)), Vector2i(0, 3), "centre = variant 0, row kept")
	assert_eq(l.get_cell_atlas_coords(Vector2i(0, 0)).x, RPGAutotile.variant_for_mask(E | SE | S), "corner")
	# the painted corner shows the top-left corner quarters of block 3 (tiles (6,0) -> half (12,0))
	var corner := l.get_cell_atlas_coords(Vector2i(0, 0))
	assert_eq(quarter(ts, RPGTilesheetVX.SOURCE_A2, corner, 0), [12, 2, 2], "painted corner TL")
	# different kinds do not connect; walls connect to themselves
	paint_key(l, "a2_4", Vector2i(3, 1))
	assert_eq(l.get_cell_atlas_coords(Vector2i(3, 1)).x, 46, "a2_4 next to a2_3 stays isolated")
	paint_key(l, "a3_0", Vector2i(10, 0))
	paint_key(l, "a3_0", Vector2i(11, 0))
	assert_eq(l.get_cell_atlas_coords(Vector2i(10, 0)), Vector2i(RPGAutotile.variant_for_mask(E), 0), "wall connects east")
	assert_eq(RPGAutotile.group_of(l, Vector2i(10, 0)), RPGTilesheetVX.GROUP_A3, "wall group")
	paint_key(l, "b_7", Vector2i(5, 5))
	assert_eq(l.get_cell_source_id(Vector2i(5, 5)), RPGTilesetBuilder.SOURCE_UPPER, "plain B tile painted")
	l.free()
	var xts: TileSet = build("xp", {"tileset": synth(256, 32, 16, 1), "autotile_1": synth(96, 128, 16, 7)}).tileset
	var xl := TileMapLayer.new()
	xl.tile_set = xts
	for x in 3:
		paint_key(xl, "autotile_1", Vector2i(x, 0))
	assert_eq(xl.get_cell_atlas_coords(Vector2i(1, 0)), Vector2i(RPGAutotile.variant_for_mask(E | W), 1), "xp corridor")
	assert_eq(quarter(xts, 0, xl.get_cell_atlas_coords(Vector2i(1, 0)), 2), [2, 7, 7], "xp corridor BL from the bottom side")
	xl.free()


# --- overrides, reimport, cache ----------------------------------------------------------------

func test_vx_overrides_reimport_and_cache() -> void:
	var a2 := synth(512, 384, 16, 2)
	var first := build("vx", {"a2": a2, "b": synth(512, 512, 16, 5)}, {"tiles": {"a2_5": {"terrain": 3}, "b_9": {"passage": 15, "flags": 16}, "nope_1": {"passage": 0}}})
	var ts: TileSet = first.tileset
	var src := ts.get_source(RPGTilesheetVX.SOURCE_A2) as TileSetAtlasSource
	for v in [0, 30, 47]:
		assert_eq(src.get_tile_data(Vector2i(v, 5), 0).get_custom_data("terrain"), 3, "override on variant %d" % v)
	assert_eq(td(ts, "b_9").z_index, 3, "override star z")
	assert_false(first.review.has("b_9"), "override clears review")
	assert_eq(first.unknown_overrides, ["nope_1"], "unknown override")
	var a2b := a2.duplicate() as Image
	a2b.fill_rect(Rect2i(2 * 32, 3 * 32, 8, 8), Color(1, 0, 0))   # block 9 (tiles (2,3))
	var second := build("vx", {"a2": a2b, "b": synth(512, 512, 16, 5)}, {}, ts)
	assert_ne(second.fingerprint, first.fingerprint, "fingerprint follows pixels")
	assert_eq(second.changed, ["a2_9"], "changed block reported")
	assert_eq(RPGTilesetBuilder.fingerprint_images("vx", {"a2": a2}, 1), RPGTilesetBuilder.fingerprint_images("vx", {"a2": a2.duplicate()}, 1), "stable fingerprint")
	# Cached build from files (user:// PNGs), reloaded TileSet keeps the key map.
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	a2.save_png(TMP_DIR + "/A2.png")
	synth(512, 512, 16, 5).save_png(TMP_DIR + "/B.png")
	var rec := {"id": TMP_ID, "profile": "vx", "sheets": {"a2": TMP_DIR + "/A2.png", "b": TMP_DIR + "/B.png", "c": TMP_DIR + "/missing.png"}}
	var path := RPGTilesetBuilder.cache_path(TMP_ID)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var c1 := RPGTilesetBuilder.cached_or_build(rec)
	assert_eq(c1.errors, [], "cached build")
	assert_false(c1.from_cache, "first build")
	assert_true((c1.warnings as Array).any(func(w: String) -> bool: return w.contains("missing.png")), "missing sheet warned")
	var c2 := RPGTilesetBuilder.cached_or_build(rec)
	assert_true(c2.from_cache, "second call from cache")
	var cts: TileSet = c2.tileset
	assert_eq(RPGTilesetBuilder.atlas_for_key("a2_9", cts), {"source": RPGTilesheetVX.SOURCE_A2, "coords": Vector2i(47, 9)}, "key map survives the cache")
	assert_eq(cts.get_meta("rpg_autotile_sources"), [RPGTilesheetVX.SOURCE_A2], "sources meta survives")
	var full := RPGTilesetBuilder.build_with_report(rec)
	assert_eq(full.errors, [], "build_with_report loads vx sheets")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(TMP_DIR + "/A2.png")
	DirAccess.remove_absolute(TMP_DIR + "/B.png")
	DirAccess.remove_absolute(TMP_DIR)
	var none := RPGTilesetBuilder.build_with_report({"id": "x", "profile": "vx", "sheets": {}})
	assert_false(none.errors.is_empty(), "no sheets -> error")
	var unknown := RPGTilesetBuilder.build_with_report({"id": "x", "profile": "zz"})
	assert_false(unknown.errors.is_empty(), "unknown profile -> error")


# --- editor palette reads the TileSet's tile size ----------------------------------------------

func test_palette_uses_tileset_tile_size_and_sources() -> void:
	var ts: TileSet = build("mv", {"a2": synth(768, 576, 24, 2), "a3": synth(768, 384, 24, 3), "b": synth(768, 768, 24, 4)}).tileset
	var p := RPGTilePalette.new()
	p.set_tile_set(ts, 16)
	assert_eq(p.tile_size, 48, "palette tile size from the TileSet")
	var titles := []
	for i in p.get_tab_count():
		titles.append(p.get_tab_title(i))
	assert_eq(titles, ["A", "B", "R"], "VX/MV tab names; empty pages left out")
	var auto := p._autotile_cells()
	assert_eq(auto.size(), 64, "A2 + A3 kinds on the A page")
	assert_eq(auto[0], {"source": RPGTilesheetVX.SOURCE_A2, "coords": Vector2i(47, 0)}, "first A2 kind")
	assert_eq(auto[32], {"source": RPGTilesheetVX.SOURCE_A3, "coords": Vector2i(47, 0)}, "first A3 kind")
	assert_eq(p._plain_cols(RPGTilesetBuilder.SOURCE_UPPER), 8, "8 columns for B-E")
	assert_eq(p._plain_cells(RPGTilesetBuilder.SOURCE_UPPER).size(), 256, "256 B tiles")
	p.free()
	# A5 plus sheets B and C: one tab per sheet, as in RPG Maker VX/Ace/MV.
	var ts2: TileSet = build("vx", {"a5": synth(256, 512, 16, 25), "b": synth(512, 512, 16, 5), "c": synth(512, 512, 16, 21)}).tileset
	var p2 := RPGTilePalette.new()
	p2.set_tile_set(ts2, 16)
	var t2 := []
	for i in p2.get_tab_count():
		t2.append(p2.get_tab_title(i))
	assert_eq(t2, ["A5", "B", "C", "R"], "A5, B and C tabs")
	var c_grid = p2._grids[2]
	assert_eq(c_grid.cells.size(), 256, "the C tab holds sheet C only")
	assert_eq(int(c_grid.cells[0].coords.y), 32, "sheet C starts 32 rows down in the upper source")
	p2.free()


# --- characters and faces (priority 5) ---------------------------------------------------------

func test_charsets_and_faces() -> void:
	# XP: one character per file, 4 frames x 4 directions (down, left, right, up)
	var xp := Vector2i(128, 192)
	assert_eq(RPGCharset.character_count("xp", xp), 1, "xp one character")
	assert_eq(RPGCharset.frame_size("xp", xp), Vector2i(32, 48), "xp frame size")
	assert_eq(RPGCharset.frame_rect("xp", xp, 0, "left", 2), Rect2i(64, 48, 32, 48), "xp left f2")
	assert_eq(RPGCharset.frame_rect("xp", xp, 0, "up", 3), Rect2i(96, 144, 32, 48), "xp up f3")
	var img := Image.create_empty(128, 192, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var sf := RPGCharset.make_sprite_frames(ImageTexture.create_from_image(img), 0, "xp")
	assert_eq(sf.get_frame_count("walk_down"), 4, "xp walk 4 frames")
	assert_eq(Rect2i((sf.get_frame_texture("walk_right", 3) as AtlasTexture).region), Rect2i(96, 96, 32, 48), "xp walk frame 3")
	assert_eq(Rect2i((sf.get_frame_texture("idle_down", 0) as AtlasTexture).region), Rect2i(0, 0, 32, 48), "xp idle frame 0")
	# VX / MV: 4 x 2 characters, $ = one character (also after !)
	var mv := Vector2i(576, 384)
	assert_eq(RPGCharset.character_count("mv", mv), 8, "mv 8 characters")
	assert_eq(RPGCharset.frame_rect("mv", mv, 5, "right", 1), Rect2i(192, 288, 48, 48), "mv char 5 right")
	assert_true(RPGCharset.is_single_character("!$Door.png", "mv"), "!$ single")
	assert_true(RPGCharset.is_single_character("$!Door.png", "vx"), "$! single")
	assert_false(RPGCharset.is_single_character("!Chest.png", "mv"), "! alone is not single")
	assert_false(RPGCharset.is_single_character("Hero$.png", "mv"), "$ must lead")
	assert_eq(RPGCharset.frame_rect("mv", Vector2i(144, 192), 0, "up", 2, true), Rect2i(96, 144, 48, 48), "mv $ sheet")
	# Faces: 96 (VX) and 144 (MV), 4 x 2 per sheet
	assert_eq(RPGCharset.face_rect("vx", Vector2i(384, 192), 5), Rect2i(96, 96, 96, 96), "vx face 5")
	assert_eq(RPGCharset.face_rect("mv", Vector2i(576, 288), 7), Rect2i(432, 144, 144, 144), "mv face 7")
	assert_eq(RPGCharset.face_rect("mv", Vector2i(144, 144), 0), Rect2i(0, 0, 144, 144), "mv single face")


## Imported RPG Maker packs declare their profile in pack.json; their character and face sheets are
## sliced with it even in a project of another profile.
func test_sheet_profile_follows_pack_json() -> void:
	var old_root := RPGAssets.root
	var tmp := "user://test_sheet_profile"
	DirAccess.make_dir_recursive_absolute(tmp + "/vxpack/CharSet")
	DirAccess.make_dir_recursive_absolute(tmp + "/plain/CharSet")
	var img := Image.create(384, 256, false, Image.FORMAT_RGBA8)
	img.save_png(tmp + "/vxpack/CharSet/Actor1.png")
	img.save_png(tmp + "/plain/CharSet/hero.png")
	var f := FileAccess.open(tmp + "/vxpack/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "VX", "license": "own", "profile": "vx"}))
	f.close()
	RPGAssets.root = tmp
	RPGAssets.clear_cache()
	assert_eq(RPGAssets.sheet_profile("charset", "Actor1", "rm2k"), "vx", "pack.json profile wins")
	assert_eq(RPGAssets.sheet_profile("charset", "hero", "rm2k"), "rm2k", "no pack.json: the project's profile")
	assert_eq(RPGAssets.sheet_profile("charset", "missing", "xp"), "xp", "unknown sheet: fallback")
	RPGAssets.root = old_root
	RPGAssets.clear_cache()
	for d in ["/vxpack/CharSet/Actor1.png", "/vxpack/pack.json", "/plain/CharSet/hero.png"]:
		DirAccess.remove_absolute(tmp + d)


func test_profile_descriptors() -> void:
	for pid in ["xp", "vx", "mv"]:
		var p := RPGProfile.load_profile(pid)
		assert_eq(p.status, "supported", "%s supported" % pid)
		assert_true(p.version >= 1, "%s version" % pid)
		assert_false(p.decoders.is_empty(), "%s lists its decoders" % pid)
		assert_true(p.decodes("charset"), "%s charset decoder" % pid)
	assert_eq(RPGProfile.load_profile("xp").tile_size, 32, "xp 32")
	assert_eq(RPGProfile.load_profile("vx").tile_size, 32, "vx 32")
	assert_eq(RPGProfile.load_profile("mv").tile_size, 48, "mv 48")
	assert_true(RPGProfile.load_profile("vx").decodes("tileset_a2"), "vx A2")
	assert_true(RPGProfile.load_profile("xp").decodes("autotile"), "xp autotile")
	assert_eq(RPGProfile.load_profile("mv").sheet_size("tileset_a4"), Vector2i(768, 720), "mv A4 size")


## I14: overlay kinds at 48 px (MV) as at 32 px: A1 deep sea and decorations over the sea, and an
## A2 kind with any clear pixel in its block over the ground. Opaque kinds are ground.
func test_mv_overlay_kinds_from_clear_pixels() -> void:
	var a2 := synth(768, 576, 24, 3)
	# a2_20: block at tiles (8, 6) = half (16, 12) = px (384, 288), 96 x 144 px.
	a2.set_pixel(389, 293, Color(0, 0, 0, 0))
	var ts: TileSet = build("mv", {"a1": synth(768, 576, 24, 4), "a2": a2}).tileset
	var ov: Dictionary = ts.get_meta(RPGAutotile.OVERLAY_META)
	var keys := ov.keys()
	keys.sort()
	assert_eq(keys, [1, 2, 3, RPGTilesheetVX.GROUP_A2 + 20], "overlay groups")
	assert_eq([ov[1].key, ov[1].source, ov[1].coords], ["a1_0", RPGTilesheetVX.SOURCE_A1, Vector2i(47, 0)], "deep sea base = the sea's palette tile")
	assert_eq(ov[RPGTilesheetVX.GROUP_A2 + 20].key, "", "A2 overlays keep the ground")
	var xp := build("xp", {"tileset": synth(256, 64, 16, 5)}).tileset as TileSet
	assert_eq(xp.get_meta(RPGAutotile.OVERLAY_META, {}), {}, "XP has no implicit lower tiles")
