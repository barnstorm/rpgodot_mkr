extends "res://tests/rpg_test_case.gd"
## Asset import (2000/2003 profile): ChipSet decoder, autotiles, TileSet builder, region/shadow
## tilesets, CharSet/FaceSet rects, window skin, RPGAssets lookup and pack scanning.

const STARTER_SHEET := "res://assets/starter/ChipSet/town.png"
const QUARTERS_FIXTURE := "res://tests/fixtures/chipset_2k_quarters.json"
const GOLDEN_FIXTURE := "res://tests/fixtures/town_chipset_golden.json"
const TMP_ID := "zz_test_import_tmp"

var _synthetic: Image


## Synthetic ChipSet: every 8x8 quarter at quarter coords (qx, qy) has colour Color8(qx, qy, 77).
func synthetic_sheet() -> Image:
	if _synthetic != null:
		return _synthetic
	var img := Image.create_empty(480, 256, false, Image.FORMAT_RGBA8)
	for qy in 32:
		for qx in 60:
			img.fill_rect(Rect2i(qx * 8, qy * 8, 8, 8), Color8(qx, qy, 77))
	_synthetic = img
	return img


func quarter_at(img: Image, at: Vector2i) -> Array:
	var c := img.get_pixelv(at)
	return [c.r8, c.g8]


func group_index(key: String) -> int:
	return RPGChipset2k.group_keys().find(key)


func starter_tileset() -> Dictionary:
	return RPGTilesetBuilder.build_with_report({"id": "town", "profile": "rm2k", "sheet": STARTER_SHEET})


func td(ts: TileSet, key: String) -> TileData:
	var a := RPGTilesetBuilder.atlas_for_key(key)
	return (ts.get_source(a.source) as TileSetAtlasSource).get_tile_data(a.coords, 0)


# --- decoder -----------------------------------------------------------------------------------

func test_synthetic_quarters_match_fixture() -> void:
	var fx: Dictionary = RPGJson.load_or(QUARTERS_FIXTURE, {})
	assert_true(fx.has("cases"), "fixture loads")
	var img := synthetic_sheet()
	for c in fx.cases:
		var g := group_index(c.group)
		assert_true(g >= 0, "group %s exists" % c.group)
		var variant: int = c.variant if c.has("variant") else RPGAutotile.variant_for_mask(c.mask)
		var rects := RPGChipset2k.quarter_rects(g, variant, c.frame)
		var tile := RPGChipset2k.compose_variant(img, g, variant, c.frame)
		for q in 4:
			var want: Array = c.quarters[q]
			assert_eq([rects[q].position.x / 8, rects[q].position.y / 8], want, "%s rect q%d" % [c.name, q])
			var o := RPGAutotile.quarter_offset(q, 16)
			# every pixel of the composed quarter comes from that source quarter
			assert_eq(quarter_at(tile, o), want, "%s pixel q%d" % [c.name, q])
			assert_eq(quarter_at(tile, o + Vector2i(7, 7)), want, "%s pixel q%d corner" % [c.name, q])


func test_plain_and_anim_rects_match_fixture() -> void:
	var fx: Dictionary = RPGJson.load_or(QUARTERS_FIXTURE, {})
	for t in fx.tiles:
		var key: String = t.key
		var i := int(key.get_slice("_", 1))
		var r := RPGChipset2k.lower_rect(i) if key.begins_with("lower") else RPGChipset2k.upper_rect(i)
		assert_eq([r.position.x, r.position.y, r.size.x, r.size.y], t.rect, key)
	for a in fx.anim:
		var r2 := RPGChipset2k.anim_frame_rect(a.index, a.frame)
		assert_eq([r2.position.x, r2.position.y, r2.size.x, r2.size.y], a.rect, "anim %d f%d" % [a.index, a.frame])


func test_builder_atlas_uses_same_quarters_and_frames() -> void:
	var rep := RPGTilesetBuilder.build_from_image(synthetic_sheet(), {"id": "synthetic", "profile": "rm2k"})
	assert_true(rep.errors.is_empty(), "no errors %s" % [rep.errors])
	var ts: TileSet = rep.tileset
	var src := ts.get_source(RPGTilesetBuilder.SOURCE_AUTOTILE) as TileSetAtlasSource
	var atlas := src.texture.get_image()
	# water_a, mask 0: atlas frames 0..3 play source frames 0,1,2,1
	var g := group_index("water_a")
	var v := RPGAutotile.variant_for_mask(0)
	var expect_x := [0, 2, 4, 2]
	for k in 4:
		var px := Vector2i((v + k * 48) * 16, g * 16)
		assert_eq(quarter_at(atlas, px), [expect_x[k], 0], "water_a frame %d TL quarter" % k)
	var c := Vector2i(v, g)
	assert_eq(src.get_tile_animation_frames_count(c), 4, "water frames")
	assert_eq(src.get_tile_animation_separation(c), Vector2i(47, 0), "water separation")
	# terrain is not animated
	assert_eq(src.get_tile_animation_frames_count(Vector2i(0, group_index("terrain_2"))), 1, "terrain frames")
	# animated tiles: anim_1 at (1,0), 4 frames, separation 2
	var asrc := ts.get_source(RPGTilesetBuilder.SOURCE_ANIMATED) as TileSetAtlasSource
	assert_eq(asrc.get_tile_animation_frames_count(Vector2i(1, 0)), 4, "anim frames")
	assert_eq(asrc.get_tile_animation_separation(Vector2i(1, 0)), Vector2i(2, 0), "anim separation")
	var aimg := asrc.texture.get_image()
	for f in 4:
		assert_eq(quarter_at(aimg, Vector2i((1 + f * 3) * 16, 0)), [8, 8 + f * 2], "anim_1 frame %d" % f)
	# lower / upper sources keep row-major order
	var lsrc := ts.get_source(RPGTilesetBuilder.SOURCE_LOWER) as TileSetAtlasSource
	assert_eq(quarter_at(lsrc.texture.get_image(), Vector2i(5 * 16, 15 * 16)), [34, 30], "lower_95")
	assert_eq(quarter_at(lsrc.texture.get_image(), Vector2i(0, 16 * 16)), [36, 0], "lower_96")
	var usrc := ts.get_source(RPGTilesetBuilder.SOURCE_UPPER) as TileSetAtlasSource
	assert_eq(quarter_at(usrc.texture.get_image(), Vector2i(0, 8 * 16)), [48, 0], "upper_48")


func test_starter_chipset_golden() -> void:
	var img := RPGTilesetBuilder.load_sheet_image(STARTER_SHEET)
	assert_true(img != null, "starter ChipSet loads")
	if img == null:
		return
	assert_eq(RPGChipset2k.validate(img), [], "valid sheet")
	var dec := RPGChipset2k.decode(img)
	assert_eq(dec.groups.size(), 15, "15 autotile groups")
	assert_eq(dec.lower.size(), 144, "144 lower")
	assert_eq(dec.upper.size(), 144, "144 upper")
	assert_eq(dec.animated.size(), 3, "3 animated")
	var gold: Dictionary = RPGJson.load_or(GOLDEN_FIXTURE, {})
	for g in dec.groups:
		assert_eq(g.frames[0].size(), 48, "%s variants" % g.key)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		for fr in g.frames:
			for v in fr:
				ctx.update(v.get_data())
		assert_eq(ctx.finish().hex_encode().substr(0, 16), gold.groups.get(g.key, ""), "golden %s" % g.key)
	for part in ["lower", "upper"]:
		var c2 := HashingContext.new()
		c2.start(HashingContext.HASH_SHA256)
		for t in dec[part]:
			c2.update(t.get_data())
		assert_eq(c2.finish().hex_encode().substr(0, 16), gold[part], "golden %s" % part)
	# Water animates: frame 0 and 1 of the full water variant differ; terrain variants differ.
	var wa: Array = dec.groups[0].frames
	assert_eq(wa.size(), 3, "water has 3 source frames")
	assert_ne(wa[0][0].get_data(), wa[1][0].get_data(), "water frames differ")
	var dirt: Array = dec.groups[group_index("terrain_1")].frames[0]
	assert_ne(dirt[0].get_data(), dirt[46].get_data(), "dirt full != isolated")
	assert_true(dec.upper[0].is_invisible(), "upper_0 is empty")


func test_mask_tables() -> void:
	assert_eq(RPGAutotile.variant_masks().size(), 47, "47 blob variants")
	assert_eq(RPGAutotile.variant_for_mask(255), 0, "full = 0")
	assert_eq(RPGAutotile.variant_for_mask(0), 46, "isolated = 46")
	# diagonals without both orthogonals are ignored
	assert_eq(RPGAutotile.reduce_mask(RPGAutotile.NE | RPGAutotile.N), RPGAutotile.N, "NE needs N and E")
	assert_eq(RPGAutotile.variant_for_mask(2 | 8 | 32 | 128), 46, "only diagonals = isolated")
	assert_eq(RPGAutotile.quarter_kinds(253), [RPGAutotile.KIND_FILL, RPGAutotile.KIND_INNER, RPGAutotile.KIND_FILL, RPGAutotile.KIND_FILL], "inner corner kinds")


# --- painting ----------------------------------------------------------------------------------

func new_layer(ts: TileSet) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.tile_set = ts
	return l


func variant_at(l: TileMapLayer, c: Vector2i) -> int:
	return l.get_cell_atlas_coords(c).x


func paint_key(l: TileMapLayer, key: String, c: Vector2i, connect := true) -> void:
	var a := RPGTilesetBuilder.atlas_for_key(key)
	RPGAutotile.paint(l, c, a.source, a.coords, connect)


func test_paint_3x3_block() -> void:
	var ts: TileSet = starter_tileset().tileset
	var l := new_layer(ts)
	for y in 3:
		for x in 3:
			paint_key(l, "terrain_1", Vector2i(x, y))
	var expect := {
		Vector2i(0, 0): 4 | 8 | 16, Vector2i(1, 0): 64 | 32 | 16 | 8 | 4, Vector2i(2, 0): 64 | 32 | 16,
		Vector2i(0, 1): 1 | 2 | 4 | 8 | 16, Vector2i(1, 1): 255, Vector2i(2, 1): 1 | 128 | 64 | 32 | 16,
		Vector2i(0, 2): 1 | 2 | 4, Vector2i(1, 2): 64 | 128 | 1 | 2 | 4, Vector2i(2, 2): 64 | 128 | 1,
	}
	for c in expect:
		assert_eq(variant_at(l, c), RPGAutotile.variant_for_mask(expect[c]), "cell %s" % c)
		assert_eq(l.get_cell_atlas_coords(c).y, group_index("terrain_1"), "row kept %s" % c)
	assert_eq(variant_at(l, Vector2i(1, 1)), 0, "centre is variant 0")
	l.free()


func test_paint_l_shape_single_and_inner_corners() -> void:
	var ts: TileSet = starter_tileset().tileset
	var l := new_layer(ts)
	for c in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]:
		paint_key(l, "terrain_2", c)
	assert_eq(variant_at(l, Vector2i(0, 0)), RPGAutotile.variant_for_mask(16), "L top")
	assert_eq(variant_at(l, Vector2i(0, 2)), RPGAutotile.variant_for_mask(1 | 4), "L corner")
	assert_eq(variant_at(l, Vector2i(1, 2)), RPGAutotile.variant_for_mask(64 | 4), "L middle (NW ignored)")
	assert_eq(variant_at(l, Vector2i(2, 2)), RPGAutotile.variant_for_mask(64), "L end")
	# single tile
	paint_key(l, "terrain_2", Vector2i(10, 10))
	assert_eq(variant_at(l, Vector2i(10, 10)), 46, "single = isolated")
	# inner corner: 3x3 block, then erase the top-right cell
	for y in 3:
		for x in 3:
			paint_key(l, "terrain_3", Vector2i(20 + x, y))
	RPGAutotile.erase(l, Vector2i(22, 0))
	assert_eq(variant_at(l, Vector2i(21, 1)), RPGAutotile.variant_for_mask(255 & ~2), "centre has inner NE corner")
	assert_eq(RPGAutotile.quarter_kinds(RPGAutotile.mask_for_variant(variant_at(l, Vector2i(21, 1))))[1], RPGAutotile.KIND_INNER, "TR quarter is inner")
	assert_eq(variant_at(l, Vector2i(21, 0)), RPGAutotile.variant_for_mask(64 | 32 | 16), "top middle after erase (SE needs E)")
	# hole in the middle: every ring cell gets inner corners
	for y in 3:
		for x in 3:
			paint_key(l, "terrain_3", Vector2i(30 + x, y))
	RPGAutotile.erase(l, Vector2i(31, 1))
	assert_eq(variant_at(l, Vector2i(31, 0)), RPGAutotile.variant_for_mask(64 | 4), "ring top")
	assert_eq(variant_at(l, Vector2i(30, 0)), RPGAutotile.variant_for_mask(4 | 16), "ring corner")
	l.free()


func test_paint_fixed_classes_bounds() -> void:
	var ts: TileSet = starter_tileset().tileset
	var l := new_layer(ts)
	# Shift-style fixed variant survives neighbour painting
	paint_key(l, "terrain_1", Vector2i(0, 0))
	var g := group_index("terrain_1")
	RPGAutotile.paint(l, Vector2i(1, 0), RPGTilesetBuilder.SOURCE_AUTOTILE, Vector2i(5, g), false)
	paint_key(l, "terrain_1", Vector2i(2, 0))
	assert_eq(variant_at(l, Vector2i(1, 0)), 5, "fixed variant kept")
	assert_true(RPGAutotile.is_fixed(l, Vector2i(1, 0)), "listed as fixed")
	paint_key(l, "terrain_1", Vector2i(1, 0))
	assert_false(RPGAutotile.is_fixed(l, Vector2i(1, 0)), "repaint clears fixed")
	assert_eq(variant_at(l, Vector2i(1, 0)), RPGAutotile.variant_for_mask(64 | 4), "repaint connects")
	# water A and water B connect (class "water"); terrain does not connect to water
	paint_key(l, "water_a", Vector2i(0, 5))
	paint_key(l, "water_b", Vector2i(1, 5))
	assert_eq(variant_at(l, Vector2i(0, 5)), RPGAutotile.variant_for_mask(4), "water A sees water B")
	paint_key(l, "terrain_0", Vector2i(2, 5))
	assert_eq(variant_at(l, Vector2i(1, 5)), RPGAutotile.variant_for_mask(64), "water ignores grass")
	assert_eq(RPGAutotile.group_of(l, Vector2i(1, 5)), group_index("water_b"), "group_of")
	assert_eq(RPGAutotile.group_of(l, Vector2i(9, 9)), -1, "empty group_of")
	# plain tile painting
	paint_key(l, "lower_5", Vector2i(4, 4))
	assert_eq(l.get_cell_source_id(Vector2i(4, 4)), RPGTilesetBuilder.SOURCE_LOWER, "plain tile painted")
	assert_eq(RPGAutotile.group_of(l, Vector2i(4, 4)), -1, "plain tile has no group")
	# map bounds: outside the map counts as connected
	var m := new_layer(ts)
	m.set_meta(RPGAutotile.MAP_SIZE_META, Vector2i(3, 3))
	paint_key(m, "terrain_1", Vector2i(0, 0))
	assert_eq(variant_at(m, Vector2i(0, 0)), RPGAutotile.variant_for_mask(1 | 2 | 128 | 64 | 32), "map corner connects outward")
	l.free()
	m.free()


func test_auto_shadows() -> void:
	var ts: TileSet = starter_tileset().tileset
	var l1 := new_layer(ts)
	var l2 := new_layer(ts)
	var sh := new_layer(RPGTilesetBuilder.shadow_tileset())
	var wall := RPGTilesetBuilder.atlas_for_key("upper_16")
	for y in range(2, 5):
		l2.set_cell(Vector2i(3, y), wall.source, wall.coords)
	RPGAutotile.apply_auto_shadows([l1, l2], sh, Rect2i(0, 0, 8, 8))
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(4, 2)), 4, "top: bottom-left quarter")
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(4, 3)), 5, "middle: left half")
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(4, 4)), 5, "bottom: left half")
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(3, 3)), 0, "wall itself")
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(2, 3)), 0, "west of wall")
	RPGAutotile.toggle_shadow_quarter(sh, Vector2i(4, 3), RPGAutotile.SHADOW_TR, true)
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(4, 3)), 7, "pen adds TR")
	RPGAutotile.toggle_shadow_quarter(sh, Vector2i(4, 2), RPGAutotile.SHADOW_BL, false)
	assert_eq(sh.get_cell_source_id(Vector2i(4, 2)), -1, "empty mask erases")
	l2.erase_cell(Vector2i(3, 2))
	RPGAutotile.update_auto_shadows_around([l1, l2], sh, Vector2i(3, 2))
	assert_eq(RPGAutotile.get_shadow(sh, Vector2i(4, 3)), 4, "recomputed after erase")
	l1.free()
	l2.free()
	sh.free()


# --- builder -----------------------------------------------------------------------------------

func test_custom_data_layers_and_defaults() -> void:
	var rep := RPGTilesetBuilder.build_from_image(synthetic_sheet(), {"id": "synthetic"})
	var ts: TileSet = rep.tileset
	var names := []
	for i in ts.get_custom_data_layers_count():
		names.append([ts.get_custom_data_layer_name(i), ts.get_custom_data_layer_type(i)])
	assert_eq(names, [["passage", TYPE_INT], ["flags", TYPE_INT], ["terrain", TYPE_INT], ["autotile", TYPE_INT], ["tile_key", TYPE_STRING]], "layers")
	assert_eq(ts.tile_size, Vector2i(16, 16), "tile size")
	assert_eq(td(ts, "water_a").get_custom_data("passage"), 0, "water blocked")
	assert_eq(td(ts, "water_c").get_custom_data("passage"), 0, "deep water blocked")
	assert_eq(td(ts, "terrain_5").get_custom_data("passage"), 15, "terrain open")
	assert_eq(td(ts, "terrain_5").get_custom_data("autotile"), group_index("terrain_5"), "autotile group")
	assert_eq(td(ts, "terrain_5").get_custom_data("tile_key"), "terrain_5", "key")
	assert_eq(td(ts, "lower_40").get_custom_data("passage"), 15, "lower open")
	assert_eq(td(ts, "lower_40").get_custom_data("autotile"), -1, "plain autotile -1")
	assert_eq(td(ts, "upper_0").get_custom_data("flags"), RPGTilesetBuilder.FLAG_STAR, "eraser star")
	assert_eq(td(ts, "upper_0").get_custom_data("passage"), 15, "eraser open")
	assert_eq(td(ts, "upper_0").z_index, 3, "star z_index")
	assert_eq(td(ts, "upper_7").get_custom_data("passage"), 0, "unknown upper blocked")
	assert_eq(td(ts, "upper_7").z_index, 0, "plain z_index")
	assert_has(rep.review, "upper_7", "upper tile flagged for review")
	assert_has(rep.review, "anim_0", "anim flagged for review")
	assert_false(rep.review.has("upper_0"), "eraser not reviewed")
	assert_false(rep.warnings.is_empty(), "review warning present")
	# every variant of a group carries the same key
	var src := ts.get_source(0) as TileSetAtlasSource
	assert_eq(src.get_tile_data(Vector2i(30, group_index("water_b")), 0).get_custom_data("tile_key"), "water_b", "variant key")
	assert_eq(ts.get_meta("rpg_autotile_classes")[0], "water", "classes meta")


func test_pack_metadata_overrides_and_rebuild() -> void:
	var rep := starter_tileset()
	assert_eq(rep.errors, [], "no errors")
	assert_eq(rep.review, [], "starter pack metadata covers every guessed tile")
	var ts: TileSet = rep.tileset
	assert_eq(td(ts, "upper_1").get_custom_data("flags"), 16, "tree top star (pack.json)")
	assert_eq(td(ts, "upper_1").z_index, 3, "tree top above characters")
	assert_eq(td(ts, "upper_16").get_custom_data("flags"), 32, "house wall casts shadow")
	assert_eq(td(ts, "upper_25").get_custom_data("flags"), 2, "counter")
	assert_eq(td(ts, "upper_22").get_custom_data("passage"), 15, "door frame open")
	assert_eq(td(ts, "lower_3").get_custom_data("flags"), 1, "tall grass bush")
	assert_eq(td(ts, "upper_100").get_custom_data("flags"), 16, "empty upper slot is star")
	var overrides := {"schema_version": 1, "tiles": {
		"upper_16": {"passage": 15}, "terrain_3": {"terrain": 2}, "upper_40": {"flags": 16}, "gone_9": {"passage": 0},
	}}
	var r2 := RPGTilesetBuilder.build_with_report({"id": "town", "profile": "rm2k", "sheet": STARTER_SHEET}, overrides)
	var ts2: TileSet = r2.tileset
	assert_eq(td(ts2, "upper_16").get_custom_data("passage"), 15, "override passage")
	assert_eq(td(ts2, "upper_16").get_custom_data("flags"), 32, "pack flags kept")
	var src := ts2.get_source(0) as TileSetAtlasSource
	for v in [0, 17, 46, 47]:
		assert_eq(src.get_tile_data(Vector2i(v, group_index("terrain_3")), 0).get_custom_data("terrain"), 2, "terrain tag on variant %d" % v)
	assert_eq(r2.unknown_overrides, ["gone_9"], "unknown override reported")
	assert_true(overrides.tiles.has("gone_9"), "overrides never modified")
	# cache round trip: save, load from cache, overrides survive; changing overrides rebuilds
	var rec := {"id": TMP_ID, "profile": "rm2k", "sheet": STARTER_SHEET}
	var path := RPGTilesetBuilder.cache_path(TMP_ID)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var c1 := RPGTilesetBuilder.cached_or_build(rec, overrides)
	assert_false(c1.from_cache, "first build")
	assert_true(FileAccess.file_exists(path), "cache saved")
	var c2 := RPGTilesetBuilder.cached_or_build(rec, overrides)
	assert_true(c2.from_cache, "second call uses cache")
	assert_eq(c2.fingerprint, c1.fingerprint, "same fingerprint")
	assert_eq(td(c2.tileset, "upper_16").get_custom_data("passage"), 15, "override survives cache")
	assert_eq(td(c2.tileset, "upper_40").z_index, 3, "z_index survives cache")
	var src2 := (c2.tileset as TileSet).get_source(0) as TileSetAtlasSource
	assert_eq(src2.get_tile_animation_frames_count(Vector2i(0, 0)), 4, "animation survives cache")
	assert_true(src2.texture is PortableCompressedTexture2D, "embedded texture, stored compressed (X20)")
	assert_eq(src2.texture.get_image().get_size(), (c1.tileset as TileSet).get_source(0).texture.get_image().get_size(), "same atlas after the round trip")
	overrides.tiles["upper_16"] = {"passage": 0}
	var c3 := RPGTilesetBuilder.cached_or_build(rec, overrides)
	assert_false(c3.from_cache, "changed overrides rebuild")
	assert_eq(td(c3.tileset, "upper_16").get_custom_data("passage"), 0, "new override applied")
	assert_eq(td(c3.tileset, "terrain_3").get_custom_data("terrain"), 2, "other overrides kept on rebuild")
	assert_eq(c3.changed, [], "same sheet: nothing changed")
	DirAccess.remove_absolute(path)


func test_fingerprint_and_reimport_report() -> void:
	var img := synthetic_sheet()
	var a := RPGTilesetBuilder.fingerprint(img, 1, {})
	assert_eq(RPGTilesetBuilder.fingerprint(img.duplicate(), 1, {}), a, "stable")
	assert_ne(RPGTilesetBuilder.fingerprint(img, 2, {}), a, "profile version matters")
	assert_ne(RPGTilesetBuilder.fingerprint(img, 1, {"water_animation": "loop"}), a, "options matter")
	var first := RPGTilesetBuilder.build_from_image(img, {"id": "s"})
	# swap upper_5 and upper_9, repaint lower_2
	var img2 := img.duplicate() as Image
	var r5 := RPGChipset2k.upper_rect(5)
	var r9 := RPGChipset2k.upper_rect(9)
	img2.blit_rect(img, r5, r9.position)
	img2.blit_rect(img, r9, r5.position)
	img2.fill_rect(RPGChipset2k.lower_rect(2), Color(1, 0, 0))
	var second := RPGTilesetBuilder.build_from_image(img2, {"id": "s"}, {}, first.tileset)
	assert_ne(second.fingerprint, first.fingerprint, "fingerprint changes")
	assert_has(second.changed, "lower_2", "changed tile reported")
	var moved := []
	for m in second.renumbered:
		moved.append("%s>%s" % [m.from, m.to])
	assert_has(moved, "upper_5>upper_9", "renumbered reported")
	assert_has(moved, "upper_9>upper_5", "renumbered reported back")
	var bad := RPGTilesetBuilder.build_from_image(Image.create_empty(100, 100, false, Image.FORMAT_RGBA8), {})
	assert_true(bad.tileset == null and not bad.errors.is_empty(), "wrong size rejected")


func test_region_and_shadow_tilesets() -> void:
	var reg := RPGTilesetBuilder.region_tileset()
	var src := reg.get_source(0) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 255, "255 regions")
	assert_false(src.has_tile(Vector2i(0, 0)), "no region 0")
	for n in [1, 15, 16, 100, 255]:
		var c := Vector2i(n % 16, n / 16)
		assert_true(src.has_tile(c), "region %d tile" % n)
		assert_eq(src.get_tile_data(c, 0).get_custom_data("region"), n, "region %d data" % n)
	var img := src.texture.get_image()
	var px := img.get_pixel(7 * 16 + 1, 2)
	assert_true(px.a > 0.2 and px.a < 0.9, "translucent region colour")
	var sh := RPGTilesetBuilder.shadow_tileset()
	var ss := sh.get_source(0) as TileSetAtlasSource
	assert_eq(ss.get_tiles_count(), 16, "16 shadow tiles")
	var si := ss.texture.get_image()
	# mask 5 = TL + BL
	assert_true(si.get_pixel(5 * 16 + 2, 2).a > 0.3, "mask 5 TL dark")
	assert_true(si.get_pixel(5 * 16 + 2, 12).a > 0.3, "mask 5 BL dark")
	assert_eq(si.get_pixel(5 * 16 + 12, 2).a, 0.0, "mask 5 TR clear")
	assert_eq(si.get_pixel(0, 0).a, 0.0, "mask 0 empty")
	assert_eq(ss.get_tile_data(Vector2i(9, 0), 0).get_custom_data("shadow"), 9, "shadow data")


# --- characters, faces, window skin -----------------------------------------------------------

func test_charset_frame_rects() -> void:
	var s := Vector2i(288, 256)
	assert_eq(RPGCharset.frame_rect("rm2k", s, 0, "up", 0), Rect2i(0, 0, 24, 32), "char 0 up f0")
	assert_eq(RPGCharset.frame_rect("rm2k", s, 0, "down", 1), Rect2i(24, 64, 24, 32), "char 0 down idle")
	assert_eq(RPGCharset.frame_rect("rm2k", s, 0, "left", 2), Rect2i(48, 96, 24, 32), "char 0 left f2")
	assert_eq(RPGCharset.frame_rect("rm2k", s, 0, "right", 0), Rect2i(0, 32, 24, 32), "char 0 right")
	assert_eq(RPGCharset.frame_rect("rm2k", s, 5, "down", 2), Rect2i(120, 192, 24, 32), "char 5 down f2")
	assert_eq(RPGCharset.frame_rect("rm2k", s, 7, "left", 1), Rect2i(240, 224, 24, 32), "char 7 left")
	assert_eq(RPGCharset.frame_rect("rm2k", Vector2i(72, 128), 3, "down", 1), Rect2i(24, 64, 24, 32), "one-character sheet")
	assert_eq(RPGCharset.frame_rect("rm2k", Vector2i(24, 32), 0, "up", 2), Rect2i(0, 0, 24, 32), "single frame sheet")
	assert_eq(RPGCharset.character_count("rm2k", s), 8, "8 characters")
	assert_eq(RPGCharset.face_rect("rm2k", Vector2i(192, 192), 5), Rect2i(48, 48, 48, 48), "face 5")
	assert_eq(RPGCharset.face_rect("rm2k", Vector2i(192, 192), 15), Rect2i(144, 144, 48, 48), "face 15")
	# later profiles: VX order down/left/right/up, `$` single sheets
	assert_eq(RPGCharset.frame_rect("vx", Vector2i(384, 256), 1, "down", 1), Rect2i(128, 0, 32, 32), "vx char 1")
	assert_eq(RPGCharset.frame_rect("vx", Vector2i(384, 256), 4, "up", 0), Rect2i(0, 224, 32, 32), "vx char 4 up")
	assert_true(RPGCharset.is_single_character("$Ghost.png", "vx"), "$ prefix")
	assert_false(RPGCharset.is_single_character("$Ghost.png", "rm2k"), "rm2k has no $ rule")
	assert_eq(RPGCharset.frame_rect("vx", Vector2i(96, 128), 0, "right", 2, true), Rect2i(64, 64, 32, 32), "vx single")


func test_sprite_frames_and_window_skin() -> void:
	var tex := RPGAssets.load_texture("charset", "hero")
	assert_true(tex != null, "hero charset loads")
	if tex == null:
		return
	var sf := RPGCharset.make_sprite_frames(tex, 2)
	for a in ["walk_down", "walk_left", "walk_right", "walk_up", "idle", "idle_down", "idle_up"]:
		assert_true(sf.has_animation(a), "animation " + a)
	assert_eq(sf.get_frame_count("walk_down"), 4, "walk pattern length")
	var f3 := sf.get_frame_texture("walk_left", 3) as AtlasTexture
	assert_eq(Rect2i(f3.region), RPGCharset.frame_rect("rm2k", Vector2i(288, 256), 2, "left", 1), "pattern 0,1,2,1")
	var sys := RPGAssets.load_texture("system", "system")
	var theme := RPGWindowSkin.make_theme(sys)
	assert_true(theme.has_stylebox("panel", "PanelContainer"), "panel style")
	assert_true(theme.has_stylebox("focus", "Button"), "cursor style")
	assert_true(theme.has_icon("arrow_down", "RPGWindow"), "arrow icon")
	var c0 := theme.get_color("text_0", "RPGWindow")
	assert_true(c0.r > 0.85 and c0.g > 0.85 and c0.b > 0.85, "text colour 0 is near white")
	assert_eq(theme.get_color("font_color", "Label"), c0, "label colour")
	var fb := RPGWindowSkin.fallback_theme()
	assert_true(fb.has_stylebox("panel", "PanelContainer"), "fallback panel")
	assert_true(RPGWindowSkin.make_theme(null).has_stylebox("panel", "Panel"), "null -> fallback")


# --- RPGAssets / RPGProfile --------------------------------------------------------------------

func test_assets_find_and_profile_roles() -> void:
	RPGAssets.clear_cache()
	assert_eq(RPGAssets.find("charset", "hero"), "res://assets/starter/CharSet/hero.png", "find")
	assert_eq(RPGAssets.find("charset", "HERO"), "res://assets/starter/CharSet/hero.png", "case-insensitive")
	assert_eq(RPGAssets.find("charset", "hero.png"), "res://assets/starter/CharSet/hero.png", "with extension")
	assert_eq(RPGAssets.find("charset", "starter/Objects"), "res://assets/starter/CharSet/objects.png", "pack-qualified")
	assert_eq(RPGAssets.find("chipset", "town"), STARTER_SHEET, "chipset")
	assert_eq(RPGAssets.find("battler", "slime"), "res://assets/starter/Monster/slime.png", "battler -> Monster")
	assert_eq(RPGAssets.find("music", "town"), "res://assets/starter/Music/town.wav", "music")
	assert_eq(RPGAssets.find("charset", "nope"), "", "missing")
	assert_eq(RPGAssets.find("sound", "town"), "", "kind separates folders")
	assert_has(RPGAssets.list("music"), "battle", "list music")
	assert_has(RPGAssets.list("faceset"), "hero_face", "list faces")
	assert_eq(RPGAssets._source_name("a.png.import"), "a.png", "strip .import")
	assert_eq(RPGAssets._source_name("b.wav.remap"), "b.wav", "strip .remap")
	var profile := RPGProfile.load_profile("rm2k")
	assert_eq(profile.tile_size, 16, "tile size")
	assert_eq(profile.folder("battler"), "Monster", "folder")
	assert_eq(profile.sheet_size("charset"), Vector2i(288, 256), "sheet size")
	assert_eq(RPGProfile.load("xp").status, "supported", "xp decoded (fixtures in test_profiles.gd)")
	var mv := RPGProfile.load("mv")
	assert_eq(mv.sound_candidates("door_open"), PackedStringArray(["Open1", "door_open"]), "mv roles: RTP name, then the role's own name")
	# Editor QA E14/E25: without the RTP, a VX/MV-style project uses the starter pack's file.
	assert_eq(mv.sound_role("door_open"), "door_open", "no Open1 here: the starter sound")
	assert_eq(mv.sound_role("battle_start"), "battle_start")
	for role in RPGProfile.SOUND_ROLES:
		var file := profile.sound_role(role)
		assert_ne(file, "", "role %s mapped" % role)
		assert_ne(RPGAssets.find("sound", file), "", "starter has sound for role %s" % role)
		assert_true(RPGAssets.load_audio("sound", file) != null, "sound %s loads" % role)
	var music := RPGAssets.load_audio("music", "field")
	assert_true(music is AudioStreamWAV and (music as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, "music loops")


func test_scan_packs() -> void:
	var reports := RPGAssets.scan_packs()
	var starter: Dictionary = {}
	for r in reports:
		if str(r.path).ends_with("/starter"):
			starter = r
	assert_false(starter.is_empty(), "starter pack scanned")
	assert_true(starter.license_verified, "license verified")
	assert_eq(starter.license, "CC0-1.0", "license")
	assert_eq(starter.profile_candidates, ["rm2k"], "profile from folders + manifest")
	assert_eq(starter.conflicts, [], "no conflicts")
	# A pack without manifest whose files fit two profiles reports both and a conflict.
	var tmp := "res://assets/zz_scan_test"
	DirAccess.make_dir_recursive_absolute(tmp + "/ChipSet")
	DirAccess.make_dir_recursive_absolute(tmp + "/Graphics/Autotiles")
	Image.create_empty(480, 256, false, Image.FORMAT_RGBA8).save_png(tmp + "/ChipSet/a.png")
	var r2 := RPGAssets.scan_pack(tmp)
	assert_false(r2.license_verified, "no manifest -> unverified")
	assert_eq(r2.profile_candidates, ["rm2k", "xp"], "both candidates")
	assert_eq(r2.conflicts.size(), 1, "conflict reported")
	DirAccess.remove_absolute(tmp + "/ChipSet/a.png")
	DirAccess.remove_absolute(tmp + "/ChipSet")
	DirAccess.remove_absolute(tmp + "/Graphics/Autotiles")
	DirAccess.remove_absolute(tmp + "/Graphics")
	DirAccess.remove_absolute(tmp)
	RPGAssets.clear_cache()


# --- regressions from the real-RTP import QA (synthetic data only) ------------------------------

const RMImport := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")
const QA_TMP := "user://rpg_import_qa"


func _qa_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_qa_tree(path.path_join(sub))
		d.remove(sub)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _qa_write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _qa_project() -> String:
	var root := QA_TMP + "/proj"
	DirAccess.make_dir_recursive_absolute(root + "/database")
	RPGJson.save_file(root + "/profile.json", {"schema_version": 1, "profile": "rm2k", "tile_size": 16})
	RPGJson.save_file(root + "/database/tilesets.json", {"schema_version": 1, "records": []})
	return root


func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
	var body := type.to_ascii_buffer()
	body.append_array(data)
	var out := PackedByteArray([(data.size() >> 24) & 255, (data.size() >> 16) & 255, (data.size() >> 8) & 255, data.size() & 255])
	out.append_array(body)
	var crc := RMImport.crc32(body)
	out.append_array(PackedByteArray([(crc >> 24) & 255, (crc >> 16) & 255, (crc >> 8) & 255, crc & 255]))
	return out


## An 8-bit indexed PNG like the 2000/2003 RTP files: `rows` of palette indices, `palette` colours.
func _indexed_png(rows: Array, palette: Array, trns := false) -> PackedByteArray:
	var w: int = (rows[0] as Array).size()
	var h := rows.size()
	var png := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	var ihdr := PackedByteArray([0, 0, 0, w, 0, 0, 0, h, 8, 3, 0, 0, 0])
	png.append_array(_chunk("IHDR", ihdr))
	var plte := PackedByteArray()
	for c in palette:
		plte.append_array(PackedByteArray([(c as Color).r8, (c as Color).g8, (c as Color).b8]))
	png.append_array(_chunk("PLTE", plte))
	if trns:
		png.append_array(_chunk("tRNS", PackedByteArray([0])))
	var raw := PackedByteArray()
	for r in rows:
		raw.append(0)
		raw.append_array(PackedByteArray(r))
	png.append_array(_chunk("IDAT", raw.compress(FileAccess.COMPRESSION_DEFLATE)))
	png.append_array(_chunk("IEND", PackedByteArray()))
	return png


## An 8-bit BMP (bottom-up rows) with a 4-colour palette.
func _indexed_bmp(rows: Array, palette: Array) -> PackedByteArray:
	var w: int = (rows[0] as Array).size()
	var h := rows.size()
	var stride := (w + 3) / 4 * 4
	var off := 54 + palette.size() * 4
	var b := PackedByteArray()
	b.resize(off + stride * h)
	b.encode_u8(0, 0x42)
	b.encode_u8(1, 0x4D)
	b.encode_u32(2, b.size())
	b.encode_u32(10, off)
	b.encode_u32(14, 40)
	b.encode_s32(18, w)
	b.encode_s32(22, h)
	b.encode_u16(26, 1)
	b.encode_u16(28, 8)
	b.encode_u32(34, stride * h)
	b.encode_u32(46, palette.size())
	for i in palette.size():
		var c: Color = palette[i]
		b[54 + i * 4] = c.b8
		b[55 + i * 4] = c.g8
		b[56 + i * 4] = c.r8
	for y in h:
		for x in w:
			b[off + (h - 1 - y) * stride + x] = int(rows[y][x])
	return b


## I1: open water fills from ChipSet block C row 0 (the shallow water of the RTP sheets); row 2
## is a deep/shallow transition piece and made shallow water look like deep water.
func test_chipset_water_fill_comes_from_block_c_row_0() -> void:
	var img := Image.create_empty(480, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color8(10, 10, 10))
	var rows := [Color8(0, 90, 210), Color8(30, 90, 190), Color8(40, 90, 170), Color8(60, 95, 150)]
	for r in 4:
		img.fill_rect(Rect2i(0, 64 + r * 16, 48, 16), rows[r])
	var full := RPGAutotile.variant_for_mask(255)
	for f in 3:
		var shallow := RPGChipset2k.compose_variant(img, group_index("water_a"), full, f)
		assert_eq(shallow.get_pixel(4, 4), rows[0], "water_a fill frame %d = C row 0" % f)
		assert_eq(shallow.get_pixel(12, 12), rows[0], "water_a fill frame %d, BR quarter" % f)
		assert_eq(RPGChipset2k.compose_variant(img, group_index("water_b"), full, f).get_pixel(8, 8), rows[0], "water_b fill = C row 0")
		assert_eq(RPGChipset2k.compose_variant(img, group_index("water_c"), full, f).get_pixel(8, 8), rows[3], "deep fill = C row 3")
	assert_eq(RPGChipset2k.quarter_rect_for_kind(group_index("water_a"), RPGAutotile.KIND_FILL, 0, 1), Rect2i(16, 64, 8, 8))


## A ChipSet without alpha keys the eraser colour on the whole sheet (RPG Maker 2000 shows the
## panorama through transparent lower tiles and terrains, e.g. the RTP Ship ChipSet).
func test_chipset_prepare_keys_lower_tiles_too() -> void:
	var img := Image.create_empty(480, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color8(40, 120, 40))
	var key := Color8(255, 103, 139)
	img.set_pixelv(RPGChipset2k.ERASER_PIXEL, key)
	img.fill_rect(RPGChipset2k.lower_rect(10), key)
	img.fill_rect(Rect2i(RPGChipset2k.terrain_origin(3), Vector2i(48, 64)), key)
	var out := RPGChipset2k.prepare(img)
	assert_eq(out.get_pixelv(RPGChipset2k.lower_rect(10).position).a, 0.0, "lower tile keyed")
	assert_eq(out.get_pixelv(RPGChipset2k.terrain_origin(3) + Vector2i(20, 30)).a, 0.0, "terrain keyed")
	assert_eq(out.get_pixelv(RPGChipset2k.lower_rect(11).position).a, 1.0, "other tiles stay opaque")


## I2: 2000/2003 images keep palette colour 0 transparent when imported (Monster battlers were
## drawn with a coloured box); opaque kinds (Backdrop) are copied as they are.
func test_rm_import_2k_palette_colour_0_is_transparent() -> void:
	_qa_tree(QA_TMP)
	assert_eq(RMImport.crc32("IEND".to_ascii_buffer()), 0xAE426082, "PNG CRC-32")
	var pal := [Color8(255, 0, 255), Color8(200, 40, 40), Color8(40, 40, 200), Color8(0, 0, 0)]
	var rows := [[0, 1, 1, 0], [0, 2, 3, 0], [0, 0, 0, 0]]
	var k2 := QA_TMP + "/RPG2000"
	_qa_write(k2 + "/Monster/Slime.png", _indexed_png(rows, pal))
	_qa_write(k2 + "/Backdrop/Field.png", _indexed_png(rows, pal))
	_qa_write(k2 + "/CharSet/Hero.bmp", _indexed_bmp(rows, pal))
	var with_trns := _indexed_png(rows, pal, true)
	_qa_write(k2 + "/FaceSet/Face.png", with_trns)
	var proj := _qa_project()
	var assets := QA_TMP + "/assets"
	var p := RMImport.plan(k2, "k2", assets, proj)
	assert_eq(p.profile, "rm2k")
	var r := RMImport.apply(p)
	assert_eq(r.errors, [])
	assert_eq(r.keyed.size(), 2, "Slime.png and Hero.bmp: %s" % str(r.keyed))
	var slime := Image.load_from_file(ProjectSettings.globalize_path(assets + "/k2/Monster/Slime.png"))
	assert_eq(slime.get_pixel(0, 0).a, 0.0, "palette colour 0 is transparent")
	assert_eq(slime.get_pixel(1, 0), Color8(200, 40, 40), "other colours stay")
	assert_eq(slime.get_pixel(2, 1), Color8(0, 0, 0), "black (index 3) stays opaque")
	var field := Image.load_from_file(ProjectSettings.globalize_path(assets + "/k2/Backdrop/Field.png"))
	assert_eq(field.detect_alpha(), Image.ALPHA_NONE, "backdrops are opaque in RPG Maker")
	var hero := Image.load_from_file(ProjectSettings.globalize_path(assets + "/k2/CharSet/Hero.png"))
	assert_eq(hero.get_pixel(0, 2).a, 0.0, "BMP palette entry 0 keyed")
	assert_eq(hero.get_pixel(2, 1), Color8(0, 0, 0, 255), "BMP other entries opaque")
	assert_eq(FileAccess.get_file_as_bytes(assets + "/k2/FaceSet/Face.png"), with_trns, "a PNG with tRNS is copied as it is")
	var rgba := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	assert_eq(RMImport.png_key_index0(rgba.save_png_to_buffer()), PackedByteArray(), "true-colour PNG untouched")
	assert_true(RMImport.describe(p, r).contains("palette colour 0"), RMImport.describe(p, r))
	_qa_tree(QA_TMP)


## I3, I5, I6, I7: XP JPG images are converted (title, game over, battle backgrounds, panoramas);
## folders RPG Kit has no place for are listed as skipped; MIDI music is copied (it is rendered
## at import) and an unreadable MIDI file is skipped; XP autotiles and the window skin name are
## reported; the skip summary is grouped by reason.
func test_rm_import_xp_jpg_unlisted_folders_and_hints() -> void:
	_qa_tree(QA_TMP)
	var xp := QA_TMP + "/XPGame"
	var jpg := Image.create(8, 6, false, Image.FORMAT_RGB8)
	jpg.fill(Color(0.6, 0.3, 0.1))
	_qa_write(xp + "/Graphics/Titles/001-Title01.jpg", jpg.save_jpg_to_buffer())
	_qa_write(xp + "/Graphics/Battlebacks/001-Grassland01.jpg", jpg.save_jpg_to_buffer())
	var tile := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	_qa_write(xp + "/Graphics/Tilesets/001-Grassland01.png", tile.save_png_to_buffer())
	_qa_write(xp + "/Graphics/Windowskins/001-Blue01.png", Image.create(192, 128, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	_qa_write(xp + "/Graphics/Animations/001-Fire01.png", jpg.save_png_to_buffer())
	_qa_write(xp + "/Graphics/Fogs/001-Fog01.png", jpg.save_png_to_buffer())
	# A real (tiny) MIDI file, and one that is only its first four bytes.
	_qa_write(xp + "/Audio/BGM/001-Battle01.mid", Marshalls.base64_to_raw("TVRoZAAAAAYAAAABAeBNVHJrAAAABAD/LwA="))
	_qa_write(xp + "/Audio/BGM/002-Battle02.mid", "MThd".to_ascii_buffer())
	var proj := _qa_project()
	var assets := QA_TMP + "/assets"
	var p := RMImport.plan(xp, "xp", assets, proj)
	assert_eq(p.profile, "xp")
	var by_dst := {}
	for f in p.files:
		by_dst[str(f.dst).trim_prefix(assets + "/xp/")] = f
	assert_true(by_dst.has("Title/001-Title01.png") and by_dst["Title/001-Title01.png"].convert, str(by_dst.keys()))
	assert_true(by_dst.has("Backdrop/001-Grassland01.png"), str(by_dst.keys()))
	assert_true(by_dst.has("Music/001-Battle01.mid") and by_dst["Music/001-Battle01.mid"].kind == "music", "MIDI music is copied: %s" % str(by_dst.keys()))
	var reasons := {}
	for s in p.skipped:
		reasons[str(s.src).get_file()] = str(s.reason)
	assert_true(reasons.get("001-Fire01.png", "").contains("battle animation"), str(reasons))
	assert_true(reasons.get("001-Fog01.png", "").contains("fog"), str(reasons))
	assert_false(reasons.has("001-Battle01.mid"), "a readable MIDI file is not skipped")
	assert_true(reasons.get("002-Battle02.mid", "").contains("not a readable MIDI file"), "an unreadable one is: %s" % str(reasons))
	var w := "\n".join(PackedStringArray(p.warnings))
	assert_true(w.contains("1 of 1 music file(s) are MIDI") and w.contains("sound bank"), w)
	assert_true(w.contains("1 MIDI file(s) cannot be read"), w)
	assert_true(w.contains("without autotiles"), w)
	assert_true(w.contains("001-Blue01"), "window skin hint: " + w)
	var r := RMImport.apply(p)
	assert_eq(r.errors, [])
	var title := Image.load_from_file(ProjectSettings.globalize_path(assets + "/xp/Title/001-Title01.png"))
	assert_true(title != null and title.get_size() == Vector2i(8, 6), "the JPG became a PNG")
	var text := RMImport.describe(p, r)
	assert_true(text.contains("1 x not a readable MIDI file"), "skips grouped by reason: " + text)
	assert_true(FileAccess.file_exists(assets + "/xp/Music/001-Battle01.mid"), "the MIDI file was copied")
	_qa_tree(QA_TMP)


## I8, I9: VX / MV GameOver.png goes to GameOver/ (not the window skins); MV tilesets with
## Japanese names get an id from their sheets instead of "tileset", "tileset_2", ...
func test_rm_import_vx_gameover_and_mv_tileset_ids() -> void:
	_qa_tree(QA_TMP)
	var vx := QA_TMP + "/VXGame"
	_qa_write(vx + "/Graphics/System/GameOver.png", Image.create(4, 4, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	_qa_write(vx + "/Graphics/System/Window.png", Image.create(128, 128, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	_qa_write(vx + "/Graphics/Tilesets/World_B.png", Image.create(512, 512, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	var proj := _qa_project()
	var assets := QA_TMP + "/assets"
	var p := RMImport.plan(vx, "vx", assets, proj)
	var kinds := {}
	for f in p.files:
		kinds[str(f.dst).trim_prefix(assets + "/vx/")] = str(f.kind)
	assert_eq(kinds.get("GameOver/GameOver.png"), "gameover", str(kinds))
	assert_eq(kinds.get("System/Window.png"), "system", str(kinds))
	# I16: icons and the like are not window skins; they are skipped with a reason, not copied.
	_qa_write(vx + "/Graphics/System/IconSet.png", Image.create(4, 4, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	var p2 := RMImport.plan(vx, "vx", assets, proj)
	var copied := []
	for f in p2.files:
		copied.append(str(f.dst).get_file())
	assert_false(copied.has("IconSet.png"), str(copied))
	assert_true(copied.has("Window.png"))
	var why := ""
	for sk in p2.skipped:
		if str(sk.src).get_file() == "IconSet.png":
			why = str(sk.reason)
	assert_true(why.contains("window skin"), "skip reason: %s" % why)
	var mv := QA_TMP + "/MVGame"
	_qa_write(mv + "/img/tilesets/World_A1.png", Image.create(4, 4, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	_qa_write(mv + "/img/tilesets/SF_Outside_B.png", Image.create(4, 4, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	_qa_write(mv + "/data/Tilesets.json", JSON.stringify([null,
		{"id": 1, "name": "フィールド", "tilesetNames": ["World_A1", "", "", "", "", "", "", "", ""], "flags": []},
		{"id": 2, "name": "近未来外観", "tilesetNames": ["World_A1", "", "", "", "", "SF_Outside_B", "", "", ""], "flags": []},
		{"id": 3, "name": "Castle", "tilesetNames": ["", "", "", "", "", "SF_Outside_B", "", "", ""], "flags": []}]).to_utf8_buffer())
	var pm := RMImport.plan(mv, "mv", assets, proj)
	var ids := []
	var names := []
	for t in pm.tilesets:
		ids.append(t.record.id)
		names.append(t.record.name)
	assert_eq(ids, ["world", "sf_outside", "castle"], "ids from the sheets when the name has no Latin letters")
	assert_eq(names[0], "フィールド", "the maker's own name is kept")
	_qa_tree(QA_TMP)


func _near(a: Color, b: Color, tol := 1.5 / 255.0) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol


## I4: XP (192x128), VX (128x128) and MV (192x192) window skins are read with their own layout
## (they were cut as a 2000 System graphic, or ignored).
func test_window_skin_xp_vx_mv_layouts() -> void:
	var bg := Color8(30, 40, 160)
	var frame := Color8(250, 250, 250)
	var cursor := Color8(20, 200, 60)
	# VX / MV: background, frame border, cursor and text colour swatches at the VX positions.
	for spec in [["vx", 1.0, Vector2i(128, 128)], ["mv", 1.5, Vector2i(192, 192)]]:
		var s: float = spec[1]
		var img := Image.create_empty(spec[2].x, spec[2].y, false, Image.FORMAT_RGBA8)
		img.fill_rect(Rect2i(0, 0, int(64 * s), int(64 * s)), bg)
		var fr := Rect2i(int(64 * s), 0, int(64 * s), int(64 * s))
		img.fill_rect(fr, frame)
		img.fill_rect(fr.grow(-int(8 * s)), Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(int(64 * s), int(64 * s), int(32 * s), int(32 * s)), cursor)
		for n in 32:
			img.fill_rect(Rect2i(int((64 + (n % 8) * 8) * s), int((96 + (n / 8) * 8) * s), int(8 * s), int(8 * s)), Color8(n * 7, 255 - n * 7, 100))
		assert_eq(RPGWindowSkin.skin_format(img.get_size()), spec[0])
		var theme := RPGWindowSkin.make_theme(ImageTexture.create_from_image(img))
		assert_true(theme.has_meta("rpg_system_texture"), "%s skin used, not the fallback" % spec[0])
		for slot in [[0, 0], [1, 16], [4, 17], [5, 18], [9, 24], [2, 2]]:
			var want := Color8(slot[1] * 7, 255 - slot[1] * 7, 100)
			var got := theme.get_color("text_%d" % slot[0], "RPGWindow")
			assert_true(_near(got, want), "%s text_%d = VX colour %d: %s" % [spec[0], slot[0], slot[1], got])
		var tex: Texture2D = theme.get_meta("rpg_system_texture")
		var norm := tex.get_image()
		assert_eq(norm.get_size(), Vector2i(160, 80))
		assert_true(_near(norm.get_pixel(16, 16), Color(bg.r, bg.g, bg.b, 192.0 / 255.0)), "%s background with the window opacity: %s" % [spec[0], norm.get_pixel(16, 16)])
		assert_true(_near(norm.get_pixel(80, 16), cursor), "%s cursor at the 2000 place: %s" % [spec[0], norm.get_pixel(80, 16)])
		assert_true(_near(norm.get_pixel(33, 16), frame, 0.08), "%s frame border: %s" % [spec[0], norm.get_pixel(33, 16)])
		assert_eq(norm.get_pixel(48, 12).a, 0.0, "%s frame centre stays open" % spec[0])
	# XP: no colours in the skin, its fixed ones are used; frame and cursor at XP's places.
	var xp := Image.create_empty(192, 128, false, Image.FORMAT_RGBA8)
	xp.fill_rect(Rect2i(0, 0, 128, 128), bg)
	xp.fill_rect(Rect2i(128, 0, 64, 64), frame)
	xp.fill_rect(Rect2i(136, 8, 48, 48), Color(0, 0, 0, 0))
	xp.fill_rect(Rect2i(128, 64, 32, 32), cursor)
	var tx := RPGWindowSkin.make_theme(ImageTexture.create_from_image(xp))
	assert_true(_near(tx.get_color("text_0", "RPGWindow"), Color.WHITE), "XP normal text is white")
	assert_true(_near(tx.get_color("text_1", "RPGWindow"), Color8(192, 224, 255)), "XP system colour")
	var n2: Image = (tx.get_meta("rpg_system_texture") as Texture2D).get_image()
	assert_true(_near(n2.get_pixel(80, 16), cursor), "XP cursor")
	assert_true(_near(n2.get_pixel(33, 16), frame, 0.08), "XP frame edge: %s" % n2.get_pixel(33, 16))
	# A 2000/2003 System graphic is still read as before.
	assert_eq(RPGWindowSkin.skin_format(Vector2i(160, 80)), "rm2k")
	assert_eq(RPGWindowSkin.skin_format(Vector2i(256, 320)), "")


## I15: a 2000/2003 Monster graphic copied in by hand (no alpha) is keyed on its top-left colour,
## the way RPG Maker treats palette colour 0. Battlers that already have alpha are left alone.
func test_hand_copied_2k_battler_is_keyed() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color8(255, 0, 255))
	img.set_pixel(4, 4, Color8(10, 200, 10))
	var keyed := RPGCharset.prepared_texture(ImageTexture.create_from_image(img)).get_image()
	assert_eq(keyed.get_pixel(0, 0).a, 0.0, "background keyed")
	assert_eq(keyed.get_pixel(4, 4).a, 1.0, "monster kept")
	var with_alpha := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	with_alpha.fill(Color(1, 0, 1, 1))
	with_alpha.set_pixel(1, 1, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(with_alpha)
	assert_true(RPGCharset.prepared_texture(tex) == tex, "a battler with alpha is used as it is")
	var src := FileAccess.get_file_as_string("res://addons/rpg/runtime/ui/battle/battle_scene.gd")
	assert_true(src.contains("RPGCharset.prepared_texture(tex)"), "the battle scene keys rm2k battlers")


# --- round 2: 2000/2003 deep/shallow blend, VX Ace / MV overlays, XP tilesets from Marshal -----

## I1 follow-up: deep water's convex corners use ChipSet block C row 2 and shallow water's
## concave-to-deep corners C row 1, one bit per quarter; straight deep/shallow runs stay plain.
func test_2k_deep_water_blend_pieces() -> void:
	var img := synthetic_sheet()
	var deep := group_index("water_c")
	var full := RPGAutotile.variant_for_mask(255)
	# Quarter source: C rows 1 and 2 hold the blend pieces (quarter row = (64 + 16 * r) / 8).
	assert_eq(RPGChipset2k.quarter_rect_for_kind(deep, RPGAutotile.KIND_FILL, 0, 0, true), Rect2i(0, 96, 8, 8), "deep blend = C row 2")
	assert_eq(RPGChipset2k.quarter_rect_for_kind(group_index("water_a"), RPGAutotile.KIND_FILL, 3, 1, true), Rect2i(24, 88, 8, 8), "shallow blend = C row 1, frame 1, BR")
	var t := RPGChipset2k.compose_variant(img, deep, full, 0, 1 | 8)
	assert_eq(quarter_at(t, Vector2i(0, 0)), [0, 12], "TL blended")
	assert_eq(quarter_at(t, Vector2i(8, 0)), [1, 14], "TR plain deep (C row 3)")
	assert_eq(quarter_at(t, Vector2i(8, 8)), [1, 13], "BR blended")
	var ts: TileSet = RPGTilesetBuilder.build_from_image(img, {"id": "blend", "profile": "rm2k"}).tileset
	assert_true(ts.has_source(RPGTilesetBuilder.SOURCE_WATER_BLEND), "blend pieces have their own source")
	var bsrc := ts.get_source(RPGTilesetBuilder.SOURCE_WATER_BLEND) as TileSetAtlasSource
	var brow := RPGChipset2k.blend_row(deep, 15)
	assert_eq(int(bsrc.get_tile_data(Vector2i(0, brow), 0).get_custom_data("autotile")), deep, "blend tiles keep the group")
	assert_eq(str(bsrc.get_tile_data(Vector2i(0, brow), 0).get_custom_data("tile_key")), "water_c", "and its tile settings")
	assert_eq(bsrc.get_tile_animation_frames_count(Vector2i(0, brow)), 4, "and its animation")
	assert_eq(quarter_at(bsrc.texture.get_image(), Vector2i(0, brow * 16)), [0, 12], "atlas: all four quarters blended")
	# Painting: a lone deep cell in shallow water is round (all four quarters blended); its
	# neighbours touch it on one side only and stay plain.
	var l := new_layer(ts)
	for y in 5:
		for x in 5:
			paint_key(l, "water_a", Vector2i(x, y))
	paint_key(l, "water_c", Vector2i(2, 2))
	assert_eq(l.get_cell_source_id(Vector2i(2, 2)), RPGTilesetBuilder.SOURCE_WATER_BLEND)
	assert_eq(l.get_cell_atlas_coords(Vector2i(2, 2)), Vector2i(0, RPGChipset2k.blend_row(deep, 15)))
	for c in [Vector2i(1, 2), Vector2i(1, 1), Vector2i(2, 1)]:
		assert_eq(l.get_cell_source_id(c), RPGTilesetBuilder.SOURCE_AUTOTILE, "%s plain shallow" % c)
	# An L of deep water: the shallow cell in its inner corner rounds it (C row 1, TL quarter).
	paint_key(l, "water_c", Vector2i(3, 2))
	paint_key(l, "water_c", Vector2i(2, 3))
	assert_eq(l.get_cell_atlas_coords(Vector2i(3, 3)), Vector2i(0, RPGChipset2k.blend_row(group_index("water_a"), 1)), "inner corner cell")
	assert_eq(l.get_cell_atlas_coords(Vector2i(2, 2)), Vector2i(0, RPGChipset2k.blend_row(deep, 1)), "L corner: only its TL quarter is a convex corner")
	assert_eq(RPGAutotile.group_of(l, Vector2i(3, 3)), group_index("water_a"))
	# The eyedropper gives the plain group back; erasing returns the neighbours to plain water.
	assert_eq(RPGAutotile.palette_tile(ts, RPGTilesetBuilder.SOURCE_WATER_BLEND, Vector2i(0, brow)), [RPGTilesetBuilder.SOURCE_AUTOTILE, Vector2i(47, deep)])
	RPGAutotile.erase(l, Vector2i(3, 2))
	assert_eq(l.get_cell_source_id(Vector2i(3, 3)), RPGTilesetBuilder.SOURCE_AUTOTILE, "no longer an inner corner")
	l.free()


## Synthetic VX Ace sheets (32 px): A1 opaque except kind 1 (deep sea, a ring of clear pixels);
## A2 opaque except kind 4 (clear surroundings).
func _vx_sheets() -> Dictionary:
	var a1 := Image.create_empty(512, 384, false, Image.FORMAT_RGBA8)
	a1.fill(Color8(20, 60, 200))
	a1.fill_rect(Rect2i(0, 96, 192, 96), Color(0, 0, 0, 0))
	a1.fill_rect(Rect2i(8, 104, 176, 80), Color8(10, 30, 120))
	var a2 := Image.create_empty(512, 384, false, Image.FORMAT_RGBA8)
	a2.fill(Color8(40, 160, 40))
	a2.fill_rect(Rect2i(256, 0, 64, 96), Color(0, 0, 0, 0))
	a2.fill_rect(Rect2i(264, 8, 48, 80), Color8(20, 100, 20))
	return {"a1": a1, "a2": a2}


## A map-like pair: Layer1 with its hidden Layer1Base under one parent.
func _overlay_map(ts: TileSet) -> Node2D:
	var root := Node2D.new()
	for n in [RPGAutotile.BASE_LAYER, RPGAutotile.TOP_LAYER]:
		var l := TileMapLayer.new()
		l.name = n
		l.tile_set = ts
		root.add_child(l)
	return root


func _paint_vx(l: TileMapLayer, key: String, c: Vector2i) -> void:
	var a := RPGTilesetBuilder.atlas_for_key(key, l.tile_set)
	RPGAutotile.paint(l, c, a.source, a.coords)


func _group(ts: TileSet, key: String) -> int:
	return (ts.get_meta(RPGAutotile.CLASSES_META) as Array).find(key)


## I14: VX Ace / MV deep sea, A1 decorations and transparent A2 kinds are drawn over a base on
## the hidden Layer1Base: the sea for A1, the ground already there for A2.
func test_vx_overlay_autotiles_keep_their_base() -> void:
	var rep := RPGTilesetBuilder.build_from_images(_vx_sheets(), {"id": "vx_overlay", "profile": "vx"})
	assert_eq(rep.errors, [])
	var ts: TileSet = rep.tileset
	var ov: Dictionary = ts.get_meta(RPGAutotile.OVERLAY_META)
	assert_eq(ov.get(1, {}).get("key"), "a1_0", "deep sea goes over the sea")
	assert_true(ov.has(2) and ov.has(3), "A1 decorations are overlays")
	assert_false(ov.has(0) or ov.has(4), "sea and other A1 kinds are not")
	assert_eq(ov.get(RPGTilesheetVX.GROUP_A2 + 4, {}).get("key"), "", "a transparent A2 kind keeps the ground")
	assert_false(ov.has(RPGTilesheetVX.GROUP_A2), "an opaque A2 kind is ground")
	var m := _overlay_map(ts)
	var top: TileMapLayer = m.get_node(RPGAutotile.TOP_LAYER)
	var base: TileMapLayer = m.get_node(RPGAutotile.BASE_LAYER)
	var cells := []
	for y in 5:
		for x in 5:
			cells.append(Vector2i(x, y))
	var grass := RPGTilesetBuilder.atlas_for_key("a2_0", ts)
	RPGAutotile.paint_cells(top, cells, grass.source, grass.coords)
	# A bush on grass: the grass moves to the base; the grass next to it still connects.
	_paint_vx(top, "a2_4", Vector2i(2, 2))
	assert_eq(RPGAutotile.group_of(top, Vector2i(2, 2)), _group(ts, "a2_4"))
	assert_eq(RPGAutotile.group_of(base, Vector2i(2, 2)), _group(ts, "a2_0"), "grass kept under the bush")
	assert_eq(top.get_cell_atlas_coords(Vector2i(1, 2)).x, 0, "grass beside the bush is still the full centre")
	assert_eq(base.get_cell_atlas_coords(Vector2i(2, 2)).x, 0, "and so is the grass under it")
	assert_eq(top.get_cell_atlas_coords(Vector2i(2, 2)).x, 46, "the lone bush is isolated")
	# Erasing the bush brings the grass back; painting ground clears the base.
	RPGAutotile.erase(top, Vector2i(2, 2))
	assert_eq(RPGAutotile.group_of(top, Vector2i(2, 2)), _group(ts, "a2_0"), "erase shows the base")
	assert_eq(base.get_cell_source_id(Vector2i(2, 2)), -1)
	# Deep sea on grass: the base is the sea, whatever was there. Sea beside it joins that sea
	# (no shore drawn between them: the "both" case).
	_paint_vx(top, "a1_1", Vector2i(2, 2))
	assert_eq(RPGAutotile.group_of(base, Vector2i(2, 2)), _group(ts, "a1_0"), "implicit sea under deep sea")
	_paint_vx(top, "a1_0", Vector2i(1, 2))
	var mask := RPGAutotile.mask_for_variant(top.get_cell_atlas_coords(Vector2i(1, 2)).x)
	assert_true(mask & RPGAutotile.E != 0, "sea connects east to the sea under the deep sea")
	var bmask := RPGAutotile.mask_for_variant(base.get_cell_atlas_coords(Vector2i(2, 2)).x)
	assert_true(bmask & RPGAutotile.W != 0 and bmask & RPGAutotile.E == 0, "base sea joins the sea, not the grass")
	# A non-overlay over an overlay cell drops the base; a fill keeps bases per cell.
	_paint_vx(top, "a2_0", Vector2i(2, 2))
	assert_eq(base.get_cell_source_id(Vector2i(2, 2)), -1, "ground has no base")
	var bush := RPGTilesetBuilder.atlas_for_key("a2_4", ts)
	RPGAutotile.paint_cells(top, [Vector2i(3, 3), Vector2i(4, 3)], bush.source, bush.coords)
	assert_eq(RPGAutotile.group_of(base, Vector2i(4, 3)), _group(ts, "a2_0"), "fill keeps the ground under a bush")
	# An overlay on an empty cell takes the most common ground around it.
	top.erase_cell(Vector2i(0, 0))
	_paint_vx(top, "a2_4", Vector2i(0, 0))
	assert_eq(RPGAutotile.group_of(base, Vector2i(0, 0)), _group(ts, "a2_0"), "ground from the neighbours")
	# Without a Layer1Base sibling nothing changes (other layers, rm2k maps, scripts).
	var lone := new_layer(ts)
	RPGAutotile.paint(lone, Vector2i(0, 0), bush.source, bush.coords)
	assert_eq(RPGAutotile.group_of(lone, Vector2i(0, 0)), _group(ts, "a2_4"))
	lone.free()
	m.free()


# --- Ruby Marshal (XP Data/Tilesets.rxdata), bytes built by hand ---------------------------------

static func _mi(n: int) -> PackedByteArray:
	if n == 0:
		return PackedByteArray([0])
	if n > 0 and n < 123:
		return PackedByteArray([n + 5])
	if n < 0 and n > -124:
		return PackedByteArray([(n - 5) & 255])
	var out := PackedByteArray()
	var x := n
	for i in 4:
		out.append(x & 255)
		x >>= 8
		if (n > 0 and x == 0) or (n < 0 and x == -1):
			break
	var head := PackedByteArray([out.size() if n > 0 else 256 - out.size()])
	head.append_array(out)
	return head


static func _cat(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for p in parts:
		if p is PackedByteArray:
			out.append_array(p)
		elif p is String:
			out.append_array((p as String).to_utf8_buffer())
		else:
			out.append(int(p))
	return out


## A symbol the first time (':'), a symlink (';') after that.
static func _msym(name: String, syms: Array) -> PackedByteArray:
	var i := syms.find(name)
	if i >= 0:
		return _cat([0x3B, _mi(i)])
	syms.append(name)
	return _cat([0x3A, _mi(name.to_utf8_buffer().size()), name])


## A Ruby 1.9+ string: I"..." with :E => true.
static func _mstr(s: String, syms: Array) -> PackedByteArray:
	return _cat([0x49, 0x22, _mi(s.to_utf8_buffer().size()), s, _mi(1), _msym("E", syms), 0x54])


## An RGSS Table (_dump bytes) of one dimension.
static func _mtable(values: Array, syms: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(20 + values.size() * 2)
	b.encode_s32(0, 1)
	b.encode_s32(4, values.size())
	b.encode_s32(8, 1)
	b.encode_s32(12, 1)
	b.encode_s32(16, values.size())
	for i in values.size():
		b.encode_s16(20 + i * 2, int(values[i]))
	return _cat([0x75, _msym("Table", syms), _mi(b.size()), b])


static func _mobj(cls: String, ivars: Array, syms: Array) -> PackedByteArray:
	var out := _cat([0x6F, _msym(cls, syms), _mi(ivars.size() / 2)])
	for i in range(0, ivars.size(), 2):
		out.append_array(_msym(str(ivars[i]), syms))
		out.append_array(ivars[i + 1])
	return out


func test_marshal_reader_values() -> void:
	for n in [0, 1, 122, 123, 255, 256, 300, 65535, 70000, -1, -123, -124, -256, -300, -70000, 2147483647]:
		var r := RPGMarshal.parse(_cat([4, 8, 0x69, _mi(n)]))
		assert_eq(r.value, n, "fixnum %d" % n)
	var syms := []
	# [nil, true, false, "Water", :sym, :sym, {1 => [2]}, RPG::Tileset, Table, link to "Water"]
	# Object table: 0 the outer array, 1 "Water", 2 the hash, 3 its array, 4 the object, 5 its
	# name string, 6 the Table.
	# Pieces are made in stream order, so symbol links point where the reader expects them.
	var water := _mstr("Water", syms)
	var sym1 := _msym("sym", syms)
	var sym2 := _msym("sym", syms)
	var obj := _mobj("RPG::Tileset", ["@id", _cat([0x69, _mi(3)]), "@name", _mstr("Field", syms)], syms)
	var table := _mtable([7, -2, 300], syms)
	var data := _cat([4, 8, 0x5B, _mi(10), 0x30, 0x54, 0x46, water, sym1, sym2,
		0x7B, _mi(1), 0x69, _mi(1), 0x5B, _mi(1), 0x69, _mi(2), obj, table, 0x40, _mi(1)])
	var r2 := RPGMarshal.parse(data)
	assert_eq(r2.error, "")
	var v: Array = r2.value if r2.value is Array else []
	assert_eq(v.size(), 10)
	if v.size() != 10:
		return
	assert_eq([v[0], v[1], v[2], v[3]], [null, true, false, "Water"])
	assert_eq(v[4], &"sym", "symbol")
	assert_eq(v[5], &"sym", "symlink")
	assert_eq(v[6], {1: [2]}, "hash of arrays")
	assert_eq(RPGMarshal.class_of(v[7]), "RPG::Tileset")
	assert_eq(v[7]["@id"], 3)
	assert_eq(v[7]["@name"], "Field", "string ivars (encoding) dropped")
	assert_eq(RPGMarshal.class_of(v[8]), "Table", "user data kept as bytes")
	assert_eq(RPGMarshal.table(v[8]).values, PackedInt32Array([7, -2, 300]))
	assert_eq(v[9], "Water", "object link")
	# Errors are reported, never thrown.
	assert_ne(RPGMarshal.parse(PackedByteArray([4, 9, 0x30])).error, "", "wrong version")
	assert_ne(RPGMarshal.parse(PackedByteArray([4, 8, 0x5B, 10])).error, "", "truncated")
	assert_ne(RPGMarshal.parse(PackedByteArray([4, 8, 0x40, 9])).error, "", "bad link")
	assert_ne(RPGMarshal.parse(PackedByteArray([4, 8, 0x63, 0])).error, "", "class references are not read")


## Data/Tilesets.rxdata as RPG Maker XP writes it: [nil, RPG::Tileset, ...].
func _xp_tilesets_rxdata() -> PackedByteArray:
	var syms := []
	var pas := []
	var pri := []
	var ter := []
	pas.resize(384 + 8)
	pri.resize(384 + 8)
	ter.resize(384 + 8)
	pas.fill(0)
	pri.fill(0)
	ter.fill(0)
	pas[48] = 0x0F           # autotile 0 (water): blocked
	pas[384 + 1] = 0x40      # tile_1: bush
	pri[384 + 2] = 1         # tile_2: above characters
	pas[384 + 3] = 0x0F      # tile_3: a blocking tile with a priority: stays below, still blocks
	pri[384 + 3] = 1
	ter[384 + 4] = 2         # tile_4: terrain tag 2
	var names := _cat([0x5B, _mi(7), _mstr("001-G_Water01", syms), _mstr("", syms), _mstr("Missing01", syms), _mstr("", syms), _mstr("", syms), _mstr("", syms), _mstr("", syms)])
	var ts := _mobj("RPG::Tileset", [
		"@id", _cat([0x69, _mi(1)]), "@name", _mstr("Field", syms), "@tileset_name", _mstr("001-Grassland01", syms),
		"@autotile_names", names, "@passages", _mtable(pas, syms), "@priorities", _mtable(pri, syms),
		"@terrain_tags", _mtable(ter, syms), "@panorama_name", _mstr("", syms)], syms)
	return _cat([4, 8, 0x5B, _mi(2), 0x30, ts])


func _xp_files(root: String, tilesets: Array, autotiles: Array) -> void:
	var tile := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	for n in tilesets:
		_qa_write(root + "/Graphics/Tilesets/%s.png" % n, tile.save_png_to_buffer())
	var auto := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	auto.fill(Color8(30, 80, 200))
	for n in autotiles:
		_qa_write(root + "/Graphics/Autotiles/%s.png" % n, auto.save_png_to_buffer())


## I6: an XP project's tilesets come with their name, autotiles and passability from
## Data/Tilesets.rxdata.
func test_rm_import_xp_project_reads_tilesets_rxdata() -> void:
	_qa_tree(QA_TMP)
	var xp := QA_TMP + "/XPProject"
	_xp_files(xp, ["001-Grassland01"], ["001-G_Water01", "002-G_Shadow01"])
	_qa_write(xp + "/Data/Tilesets.rxdata", _xp_tilesets_rxdata())
	var proj := _qa_project()
	var assets := QA_TMP + "/assets"
	var p := RMImport.plan(xp, "xpp", assets, proj)
	assert_eq(p.profile, "xp")
	assert_eq(p.tilesets.size(), 1, "one record per database tileset")
	if p.tilesets.size() != 1:
		_qa_tree(QA_TMP)
		return
	var rec: Dictionary = p.tilesets[0].record
	assert_eq(rec.name, "Field", "the database name")
	assert_eq(rec.id, "field")
	assert_eq(rec.autotiles, [assets + "/xpp/Autotiles/001-G_Water01.png"], "slot 0 from the database; the missing one is dropped")
	var w := "\n".join(PackedStringArray(p.warnings))
	assert_true(w.contains("Missing01"), "a missing autotile is named: " + w)
	assert_false(w.contains("without autotiles"), w)
	var tiles: Dictionary = p.tilesets[0].get("tiles", {})
	assert_eq(tiles.get("autotile_0", {}).get("passage"), 0, "water blocks")
	assert_eq(tiles.get("tile_1", {}).get("flags"), RPGMovement.FLAG_BUSH, "bush flag")
	assert_eq(tiles.get("tile_2", {}).get("flags"), RPGMovement.FLAG_STAR, "priority over an open tile = star")
	assert_eq([tiles.get("tile_3", {}).get("passage"), tiles.get("tile_3", {}).get("flags")], [0, 0], "a blocking tile with a priority keeps blocking")
	assert_eq(tiles.get("tile_4", {}).get("terrain"), 2)
	assert_false(tiles.has("tile_0"), "the eraser keeps its default")
	var r := RMImport.apply(p)
	assert_eq(r.errors, [])
	assert_true(FileAccess.file_exists(proj + "/tileset_overrides/field.json"), "passability saved as tile settings")
	var built := RPGTilesetBuilder.build_with_report(rec)
	assert_eq(built.errors, [])
	if built.tileset != null:
		assert_true(RPGTilesetBuilder.atlas_for_key("autotile_0", built.tileset).size() > 0, "the autotile is in the TileSet")
	_qa_tree(QA_TMP)


## I6: without Data/Tilesets.rxdata (the RTP), autotiles are matched only where the RTP names
## say so ("G_" -> Grassland, "Sn_" -> Snowfield / SnowTown), and the warning says which were
## guessed and which tilesets got none.
func test_rm_import_xp_rtp_guesses_autotiles_by_name() -> void:
	_qa_tree(QA_TMP)
	var xp := QA_TMP + "/XPRTP"
	var g := ["001-G_Water01", "002-G_Shadow01", "003-G_Ground01", "004-G_Ground02", "005-G_Road01", "006-G_Road02", "007-G_Undulation01", "008-G_Undulation02"]
	_xp_files(xp, ["001-Grassland01", "008-Snowfield01", "043-Cave01"], g + ["028-Sn_Water01", "056-CE_Water01", "024-Ocean01"])
	var assets := QA_TMP + "/assets"
	var p := RMImport.plan(xp, "xr", assets, _qa_project())
	var by_id := {}
	for t in p.tilesets:
		by_id[t.record.id] = t.record
	assert_true(by_id.has("tileset_001_grassland_01") and by_id.has("tileset_008_snowfield_01") and by_id.has("tileset_043_cave_01"), str(by_id.keys()))
	if by_id.size() != 3:
		_qa_tree(QA_TMP)
		return
	assert_eq((by_id["tileset_001_grassland_01"].autotiles as Array).size(), 7, "7 slots")
	assert_eq(str(by_id["tileset_001_grassland_01"].autotiles[0]).get_file(), "001-G_Water01.png")
	assert_eq(by_id["tileset_008_snowfield_01"].autotiles, [assets + "/xr/Autotiles/028-Sn_Water01.png"])
	assert_eq(by_id["tileset_043_cave_01"].autotiles, [], "CE_ does not clearly name a tileset")
	var w := "\n".join(PackedStringArray(p.warnings))
	assert_true(w.contains("guessed") and w.contains("008-G_Undulation02 left out"), w)
	assert_true(w.contains("1 XP tileset(s) are added without autotiles: tileset_043_cave_01"), w)
	_qa_tree(QA_TMP)


## Side-view battlers: a 2003 BattleCharSet and MV img/sv_actors are copied as "sv_battler" into
## BattleCharSet/ (the 2003 one keyed like the other 2000/2003 sheets), not skipped.
func test_rm_import_side_view_battlers_are_copied() -> void:
	_qa_tree(QA_TMP)
	var pal := [Color8(255, 0, 255), Color8(200, 40, 40), Color8(40, 40, 200), Color8(0, 0, 0)]
	var k3 := QA_TMP + "/RPG2003"
	_qa_write(k3 + "/CharSet/Hero.png", _indexed_png([[0, 1], [2, 3]], pal))
	_qa_write(k3 + "/BattleCharSet/Fighter.png", _indexed_png([[0, 1], [2, 3]], pal))
	var mvroot := QA_TMP + "/MVGame"
	_qa_write(mvroot + "/img/characters/Actor1.png", Image.create(8, 8, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	_qa_write(mvroot + "/img/sv_actors/Actor1_1.png", Image.create(8, 8, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	var assets := QA_TMP + "/assets"
	for spec in [[k3, "k3", "rm2k", "Fighter.png", true], [mvroot, "mvs", "mv", "Actor1_1.png", false]]:
		var p := RMImport.plan(spec[0], spec[1], assets, _qa_project())
		assert_eq(p.profile, spec[2])
		var found := {}
		for f in p.files:
			if str(f.dst).get_file() == spec[3]:
				found = f
		assert_eq(found.get("kind"), "sv_battler", "%s copied as a side-view battler" % spec[3])
		assert_eq(str(found.get("dst", "")), assets.path_join(spec[1]).path_join("BattleCharSet").path_join(spec[3]))
		assert_eq(bool(found.get("key_index0", false)), spec[4], "%s keyed only for 2000/2003" % spec[3])
		for s in p.skipped:
			assert_ne(str(s.src).get_file(), spec[3], "not skipped: %s" % str(s.reason))
	_qa_tree(QA_TMP)
