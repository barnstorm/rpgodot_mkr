@tool
class_name RPGTilesetBuilder
extends RefCounted
## Builds Godot TileSets from a tileset record + overrides (see docs/ARCHITECTURE.md,
## "TileSet contract"). Pure code: works in the editor and in exported games.
## Profiles: rm2k (RPGChipset2k, below), xp (RPGTilesheetXP), vx and mv (RPGTilesheetVX). The
## later profiles go through the GENERIC LAYOUT path described after the rm2k layout; their own
## source/key layout is documented in their decoder.
##
## GENERATED ATLAS LAYOUT, rm2k (tile size = profile tile size, 16 px for rm2k):
##   source 0  autotiles. Row g = autotile group g, column v = variant v (0..47):
##             row 0 water_a, 1 water_b, 2 water_c (deep), 3..14 terrain_0..terrain_11.
##             Variant 0 = fully connected centre, 46 = isolated, 47 = palette/preview tile.
##             Animated groups (water) store frame k at column v + 48*k
##             (animation separation (47, 0)); water plays source frames 0,1,2,1.
##             Paint with atlas (47, g) or any (v, g); RPGAutotile.paint picks the variant.
##   source 1  lower tiles: lower_i at (i % 6, i / 6), i = 0..143
##   source 2  upper tiles: upper_i at (i % 6, i / 6), i = 0..143 (upper_0 = empty/eraser)
##   source 3  animated tiles: anim_i at (i, 0), i = 0..2, 4 frames at (i + 3*k, 0)
##             (separation (2, 0)).
##   source 4  deep/shallow water blend pieces, laid out like source 0: 15 rows per water group
##             (water_a 0..14, water_b 15..29, water_c 30..44; row = RPGChipset2k.blend_row),
##             one per combination of blended quarters. Their tiles carry the group's autotile
##             id and tile_key, so passability and tile settings follow the group. Not shown in
##             the palette; RPGAutotile switches a water cell to them (TileSet meta
##             rpg_autotile_blend).
## Auto layer: source 2 goes to Layer2 (upper), everything else to Layer1 (lower).
##
## CUSTOM DATA LAYERS (exact order): passage:int, flags:int, terrain:int, autotile:int, tile_key:String
## Tiles with the star flag (16) get TileData.z_index = 3 (characters are at z 1/2/4).
##
## DEFAULTS (applied first, then pack.json metadata, then user overrides by tile_key):
##   water_a / water_b / water_c    passage 0 (blocked)
##   terrain_0..11                  passage 15 (open)
##   anim_0..2                      passage 0, review warning (animated tiles are usually
##                                  waterfalls/lava; pixels cannot tell)
##   lower_i                        passage 15 (open)
##   upper_0                        passage 15, flags star (the eraser)
##   upper_i fully transparent      passage 15, flags star (unused slot, no warning)
##   upper_i with pixels            passage 0 (blocked), review warning
##   flags 0 and terrain 0 everywhere else.
## Pack metadata: res://assets/<pack>/pack.json may hold
##   "chipsets": {"<sheet basename>": {"tiles": {"<tile_key>": {passage, flags, terrain}}}}
## Overrides: {"schema_version": 1, "tiles": {"<tile_key>": {passage, flags, terrain}}} or just
## the "tiles" dictionary. Overrides are never modified by the builder; overrides for keys that
## do not exist are reported and kept.
##
## GENERIC LAYOUT (xp, vx, mv). A decoder returns new_layout(): images, autotile sources
## ({id, rows, frames}), plain sources ({id, cols, rows}), groups ({key, group, source, row,
## class, image, origin, layout, frames: pixel offsets per atlas frame, frame_time}), plain tiles
## ({key, source, coords, image, rect}), defaults, review keys, key_rects (for change detection),
## classes (index = group id) and overlays ({group: base tile_key, or "" to keep the ground}:
## autotiles drawn over an implicit lower tile, stored as TileSet meta rpg_overlay_bases for
## RPGAutotile's hidden base layer). The builder then makes:
##   autotile source: 48 columns (variants, 47 = palette tile); group at (variant, row); atlas
##     frame k of a row at row + k * rows (vertical frames: animation columns 1, separation
##     (0, rows - 1)), so a still group costs one row only.
##   plain source: tile at its coords. Source 2 (0,0) is always the eraser tile, as in rm2k.
## Custom data, defaults -> pack metadata -> overrides, z_index, hashes and the reimport report
## work as for rm2k. Extra TileSet meta: rpg_key_atlas (tile_key -> [source, coords]; read it
## with atlas_for_key(key, tile_set)), rpg_autotile_sources (Array of source ids),
## rpg_tile_size. pack.json "chipsets" entries are looked up by the basename of every sheet.
##
## FINGERPRINT: SHA-256 of the decoded source pixels + "rm2k:<profile version>" + builder
## version + options JSON. TileSet meta: rpg_fingerprint, rpg_overrides_hash, rpg_tile_hashes
## (tile_key -> pixel hash, used to report changed/renumbered tiles on reimport), rpg_profile,
## rpg_sources, rpg_autotile_classes, rpg_tileset_id.

## 3: rm2k deep/shallow water blend pieces (source 4); overlay base meta (rpg_overlay_bases)
## for vx / mv.
const BUILDER_VERSION := 3
const CACHE_DIR := "res://rpg/generated/tilesets"

const SOURCE_AUTOTILE := 0
const SOURCE_LOWER := 1
const SOURCE_UPPER := 2
const SOURCE_ANIMATED := 3
## rm2k only: deep/shallow water blend pieces (not a palette source; RPGAutotile picks them).
const SOURCE_WATER_BLEND := 4
const AUTOTILE_FRAME_STRIDE := 48
const MAX_AUTOTILE_FRAMES := 4

const FLAG_BUSH := 1
const FLAG_COUNTER := 2
const FLAG_LADDER := 4
const FLAG_DAMAGE := 8
const FLAG_STAR := 16
const FLAG_WALL := 32
## Blocks movement across the tile's outer edges (where the neighbour on its layer is not the
## same tile kind), open inside: RPG Maker MV's wall-top (ceiling) autotiles.
const FLAG_EDGE := 64
const STAR_Z_INDEX := 3

const CUSTOM_LAYERS := [
	["passage", TYPE_INT],
	["flags", TYPE_INT],
	["terrain", TYPE_INT],
	["autotile", TYPE_INT],
	["tile_key", TYPE_STRING],
]

const WATER_FRAME_TIME := 0.25
const ANIM_FRAME_TIME := 0.2
const AUTOTILE_FRAME_TIME := 0.5
const KEY_ATLAS_META := "rpg_key_atlas"
const AUTOTILE_SOURCES_META := "rpg_autotile_sources"
## Profiles with a tile sheet decoder.
const DECODED_PROFILES: Array[String] = ["rm2k", "xp", "vx", "mv"]


## Convenience: just the TileSet (null on error).
static func build(tileset_record: Dictionary, overrides: Dictionary = {}) -> TileSet:
	return build_with_report(tileset_record, overrides).tileset


## Builds a TileSet and reports:
##   {tileset, warnings: Array[String], review: Array[String] (tile_keys left on a guessed
##    default), fingerprint, errors, changed, renumbered, removed, unknown_overrides, from_cache}
## `previous` may be an earlier TileSet built from the same record (for the reimport report).
static func build_with_report(tileset_record: Dictionary, overrides: Dictionary = {}, previous: TileSet = null) -> Dictionary:
	var report := _empty_report()
	var profile_id := str(tileset_record.get("profile", "rm2k"))
	if not DECODED_PROFILES.has(profile_id):
		report.errors.append("Profile '%s' has no tile sheet decoder yet." % profile_id)
		return report
	if profile_id != "rm2k":
		var loaded := load_record_images(tileset_record)
		if (loaded.images as Dictionary).is_empty():
			report.errors.append("Cannot load any sheet of tileset '%s' (%s)." % [tileset_record.get("id", ""), ", ".join(PackedStringArray(loaded.missing))])
			return report
		var rep := build_from_images(loaded.images, tileset_record, overrides, previous)
		for m in loaded.missing:
			rep.warnings.append("Cannot load sheet '%s'; it is skipped." % m)
		return rep
	var image := load_sheet_image(str(tileset_record.get("sheet", "")))
	if image == null:
		report.errors.append("Cannot load sheet '%s'." % tileset_record.get("sheet", ""))
		return report
	return build_from_image(image, tileset_record, overrides, previous)


## Same as build_with_report but from an already loaded Image (tests, previews). rm2k only; the
## other profiles use build_from_images.
static func build_from_image(image: Image, tileset_record: Dictionary, overrides: Dictionary = {}, previous: TileSet = null) -> Dictionary:
	var report := _empty_report()
	var errors := RPGChipset2k.validate(image)
	if not errors.is_empty():
		report.errors = errors
		return report
	var options: Dictionary = tileset_record.get("options", {})
	var profile := RPGProfile.load_profile("rm2k")
	var profile_version := profile.version if profile != null else 1
	var tile_size := profile.tile_size if profile != null else 16
	var src_img := image.duplicate() as Image
	if src_img.is_compressed():
		src_img.decompress()
	src_img.convert(Image.FORMAT_RGBA8)
	report.fingerprint = fingerprint(src_img, profile_version, options)
	var img := RPGChipset2k.prepare(src_img)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	for l in CUSTOM_LAYERS:
		var i := ts.get_custom_data_layers_count()
		ts.add_custom_data_layer()
		ts.set_custom_data_layer_name(i, l[0])
		ts.set_custom_data_layer_type(i, l[1])

	var keys := {}  # tile_key -> Array of [source, coords]
	_build_autotiles(ts, img, options, keys)
	_build_plain(ts, img, SOURCE_LOWER, "lower", keys)
	_build_plain(ts, img, SOURCE_UPPER, "upper", keys)
	_build_animated(ts, img, options, keys)

	# Defaults, then pack metadata, then overrides.
	var settings := {}
	for key in keys:
		settings[key] = _default_for(key, img, report)
	_resolve_settings(ts, keys, settings, [str(tileset_record.get("sheet", ""))], overrides, report)

	var hashes := tile_hashes(src_img)
	if previous != null and previous.has_meta("rpg_tile_hashes"):
		_compare(previous.get_meta("rpg_tile_hashes"), hashes, report)

	var classes := []
	for g in RPGChipset2k.GROUP_COUNT:
		classes.append(RPGChipset2k.group_info(g).connect_class)
	ts.set_meta("rpg_fingerprint", report.fingerprint)
	ts.set_meta("rpg_overrides_hash", overrides_hash(overrides))
	ts.set_meta("rpg_builder_version", BUILDER_VERSION)
	ts.set_meta("rpg_profile", "rm2k")
	ts.set_meta("rpg_tileset_id", str(tileset_record.get("id", "")))
	ts.set_meta("rpg_tile_hashes", hashes)
	ts.set_meta("rpg_autotile_classes", classes)
	ts.set_meta("rpg_sources", {"autotile": SOURCE_AUTOTILE, "lower": SOURCE_LOWER, "upper": SOURCE_UPPER, "animated": SOURCE_ANIMATED})
	ts.set_meta(AUTOTILE_SOURCES_META, [SOURCE_AUTOTILE])
	ts.set_meta("rpg_tile_size", tile_size)
	report.tileset = ts
	return report


## Defaults (already in `settings`) -> pack.json metadata -> user overrides, then writes them.
static func _resolve_settings(ts: TileSet, keys: Dictionary, settings: Dictionary, sheet_paths: Array, overrides: Dictionary, report: Dictionary) -> void:
	for p in sheet_paths:
		var pack_tiles := pack_tile_defaults(str(p))
		for key in pack_tiles:
			if settings.has(key) and pack_tiles[key] is Dictionary:
				_merge(settings[key], pack_tiles[key])
				report.review.erase(key)
	var ov: Dictionary = overrides.get("tiles", overrides) if overrides is Dictionary else {}
	for key in ov:
		if settings.has(key):
			if ov[key] is Dictionary:
				_merge(settings[key], ov[key])
				report.review.erase(key)
		else:
			report.unknown_overrides.append(str(key))
			report.warnings.append("Override for '%s' matches no tile in this sheet; it is kept but unused." % key)
	for key in keys:
		for entry in keys[key]:
			_apply(ts, entry[0], entry[1], key, settings[key])
	if not report.review.is_empty():
		# The full list stays in report.review; the message names the first few.
		var shown: Array = report.review.slice(0, 8)
		var more := "" if report.review.size() <= 8 else " and %d more" % (report.review.size() - 8)
		report.warnings.append("%d tile(s) use a guessed default; review them in the Tilesets tab: %s%s" % [report.review.size(), ", ".join(PackedStringArray(shown)), more])


static func _new_tileset(tile_size: int) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	for l in CUSTOM_LAYERS:
		var i := ts.get_custom_data_layers_count()
		ts.add_custom_data_layer()
		ts.set_custom_data_layer_name(i, l[0])
		ts.set_custom_data_layer_type(i, l[1])
	return ts


static func _rgba(image: Image) -> Image:
	var img := image.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


# --- generic layout (xp, vx, mv) ---------------------------------------------------------------

## Empty generic layout, filled by the profile decoders (see the header).
static func new_layout(profile_id: String, tile_size: int) -> Dictionary:
	return {
		"profile": profile_id, "tile_size": tile_size, "errors": [], "warnings": [],
		"images": {}, "autotile_sources": [], "plain_sources": [], "groups": [], "plain": [],
		"defaults": {}, "review": [], "key_rects": {}, "classes": [], "overlays": {},
	}


## Image name -> sheet path of every sheet a tileset record uses (rm2k: {"sheet": path}).
static func record_sheet_paths(record: Dictionary) -> Dictionary:
	match str(record.get("profile", "rm2k")):
		"xp":
			return RPGTilesheetXP.image_paths(record)
		"vx", "mv":
			return RPGTilesheetVX.image_paths(record)
	var sheet := str(record.get("sheet", ""))
	return {"sheet": sheet} if sheet != "" else {}


## Loads every sheet of a record: {images: {name: Image}, missing: [paths that did not load]}.
static func load_record_images(record: Dictionary) -> Dictionary:
	var images := {}
	var missing := []
	var paths := record_sheet_paths(record)
	for n in paths:
		var img := load_sheet_image(str(paths[n]))
		if img == null:
			missing.append(str(paths[n]))
		else:
			images[n] = img
	return {"images": images, "missing": missing}


## Runs the profile's decoder on loaded images (names as in record_sheet_paths).
static func decode_layout(profile_id: String, images: Dictionary, options: Dictionary = {}) -> Dictionary:
	var profile := RPGProfile.load_profile(profile_id)
	if profile == null:
		var bad := new_layout(profile_id, 16)
		bad.errors.append("Unknown profile '%s'." % profile_id)
		return bad
	var t := profile.tile_size
	var ft := float(options.get("autotile_frame_time", profile.data.get("autotile_frame_time", AUTOTILE_FRAME_TIME)))
	match profile_id:
		"xp":
			return RPGTilesheetXP.decode(images, t, ft)
		"vx", "mv":
			return RPGTilesheetVX.decode(profile_id, images, t, ft)
	var none := new_layout(profile_id, t)
	none.errors.append("Profile '%s' has no tile sheet decoder." % profile_id)
	return none


## Builds a TileSet from already loaded images (every profile; names as in record_sheet_paths).
## Same report as build_with_report.
static func build_from_images(images: Dictionary, tileset_record: Dictionary, overrides: Dictionary = {}, previous: TileSet = null) -> Dictionary:
	var profile_id := str(tileset_record.get("profile", "rm2k"))
	if profile_id == "rm2k":
		var sheet: Image = images.get("sheet")
		if sheet == null:
			var r0 := _empty_report()
			r0.errors.append("The rm2k profile needs one ChipSet image ('sheet').")
			return r0
		return build_from_image(sheet, tileset_record, overrides, previous)
	var report := _empty_report()
	var options: Dictionary = tileset_record.get("options", {})
	var prepared := {}
	for n in images:
		if images[n] is Image and not (images[n] as Image).is_empty():
			prepared[n] = _rgba(images[n])
	var layout := decode_layout(profile_id, prepared, options)
	report.warnings.append_array(layout.warnings)
	if not (layout.errors as Array).is_empty():
		report.errors.append_array(layout.errors)
		return report
	var profile := RPGProfile.load_profile(profile_id)
	report.fingerprint = fingerprint_images(profile_id, prepared, profile.version, options)
	var ts := _new_tileset(int(layout.tile_size))
	var keys := {}
	var key_atlas := _build_layout(ts, layout, keys)
	var settings := {}
	for key in keys:
		var d: Dictionary = layout.defaults.get(key, {"passage": 15, "flags": 0, "terrain": 0})
		settings[key] = d.duplicate()
	for key in layout.review:
		report.review.append(key)
	_resolve_settings(ts, keys, settings, record_sheet_paths(tileset_record).values(), overrides, report)
	var hashes := layout_tile_hashes(layout)
	if previous != null and previous.has_meta("rpg_tile_hashes"):
		_compare(previous.get_meta("rpg_tile_hashes"), hashes, report)
	var auto_ids := []
	for s in layout.autotile_sources:
		auto_ids.append(int(s.id))
	ts.set_meta("rpg_fingerprint", report.fingerprint)
	ts.set_meta("rpg_overrides_hash", overrides_hash(overrides))
	ts.set_meta("rpg_builder_version", BUILDER_VERSION)
	ts.set_meta("rpg_profile", profile_id)
	ts.set_meta("rpg_tileset_id", str(tileset_record.get("id", "")))
	ts.set_meta("rpg_tile_hashes", hashes)
	ts.set_meta("rpg_autotile_classes", layout.classes)
	ts.set_meta("rpg_sources", {"autotile": auto_ids[0] if not auto_ids.is_empty() else SOURCE_AUTOTILE, "lower": SOURCE_LOWER, "upper": SOURCE_UPPER, "animated": SOURCE_ANIMATED})
	ts.set_meta(AUTOTILE_SOURCES_META, auto_ids)
	ts.set_meta(KEY_ATLAS_META, key_atlas)
	ts.set_meta("rpg_tile_size", int(layout.tile_size))
	ts.set_meta(RPGAutotile.OVERLAY_META, _overlay_meta(layout, key_atlas))
	report.tileset = ts
	return report


## Layout overlays {group: base tile_key or ""} -> TileSet meta {group: {key, source, coords}}.
## A base key the TileSet does not have falls back to "keep the ground" ("").
static func _overlay_meta(layout: Dictionary, key_atlas: Dictionary) -> Dictionary:
	var out := {}
	var overlays: Dictionary = layout.get("overlays", {})
	for g in overlays:
		var key := str(overlays[g])
		if key != "" and key_atlas.has(key):
			out[int(g)] = {"key": key, "source": int(key_atlas[key][0]), "coords": key_atlas[key][1]}
		else:
			out[int(g)] = {"key": ""}
	return out


## Creates the sources of a generic layout; fills keys (tile_key -> [[source, coords], ...]) and
## returns tile_key -> [source, palette coords].
static func _build_layout(ts: TileSet, layout: Dictionary, keys: Dictionary) -> Dictionary:
	var t := int(layout.tile_size)
	var key_atlas := {}
	var images: Dictionary = layout.images
	for s in layout.autotile_sources:
		var sid := int(s.id)
		var rows := int(s.rows)
		var nframes := maxi(1, int(s.frames))
		var atlas := Image.create_empty(RPGAutotile.VARIANT_SLOTS * t, rows * nframes * t, false, Image.FORMAT_RGBA8)
		var groups := []
		for g in layout.groups:
			if int(g.source) == sid:
				groups.append(g)
		for g in groups:
			var img: Image = images[g.image]
			var frames: Array = g.frames
			for k in mini(frames.size(), nframes):
				var origin: Vector2i = (g.origin as Vector2i) + (frames[k] as Vector2i)
				for v in RPGAutotile.VARIANT_SLOTS:
					var rects := RPGAutotileLayout.variant_rects(str(g.layout), v, origin, t)
					RPGAutotile.compose(img, rects, atlas, Vector2i(v * t, (int(g.row) + k * rows) * t))
		var src := _new_source(ts, atlas, sid)
		for g in groups:
			var key := str(g.key)
			var row := int(g.row)
			var n := mini((g.frames as Array).size(), nframes)
			keys[key] = []
			for v in RPGAutotile.VARIANT_SLOTS:
				var c := Vector2i(v, row)
				src.create_tile(c)
				if n > 1:
					set_tile_animation(src, c, n, Vector2i(0, rows - 1), float(g.frame_time), 1)
				keys[key].append([sid, c])
				src.get_tile_data(c, 0).set_custom_data("autotile", int(g.group))
			key_atlas[key] = [sid, Vector2i(RPGAutotile.PREVIEW_VARIANT, row)]
	for s in layout.plain_sources:
		var sid2 := int(s.id)
		var atlas2 := Image.create_empty(int(s.cols) * t, int(s.rows) * t, false, Image.FORMAT_RGBA8)
		var tiles := []
		for p in layout.plain:
			if int(p.source) == sid2:
				tiles.append(p)
				atlas2.blit_rect(images[p.image], p.rect, (p.coords as Vector2i) * t)
		var src2 := _new_source(ts, atlas2, sid2)
		for p in tiles:
			var c2: Vector2i = p.coords
			src2.create_tile(c2)
			src2.get_tile_data(c2, 0).set_custom_data("autotile", -1)
			keys[str(p.key)] = [[sid2, c2]]
			key_atlas[str(p.key)] = [sid2, c2]
	return key_atlas


## tile_key -> hash of the source pixels it is built from (generic layouts).
static func layout_tile_hashes(layout: Dictionary) -> Dictionary:
	var out := {}
	var images: Dictionary = layout.images
	for key in layout.key_rects:
		var parts := PackedByteArray()
		for e in layout.key_rects[key]:
			var img: Image = images.get(e[0])
			if img != null:
				parts.append_array(img.get_region(e[1]).get_data())
		if not _any_alpha(parts):
			out[key] = "empty"
			continue
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(parts)
		out[key] = ctx.finish().hex_encode().substr(0, 16)
	return out


## Fingerprint of every source image (sorted by name) + profile + builder version + options.
static func fingerprint_images(profile_id: String, images: Dictionary, profile_version: int, options: Dictionary = {}) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var names := images.keys()
	names.sort()
	for n in names:
		var img: Image = images[n]
		ctx.update(("%s:%dx%d:" % [n, img.get_width(), img.get_height()]).to_utf8_buffer())
		ctx.update(img.get_data())
	ctx.update(("%s:%d:builder:%d:" % [profile_id, profile_version, BUILDER_VERSION]).to_utf8_buffer())
	ctx.update(RPGJson.stringify(options).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Fingerprint a record's loaded images would get (cache check).
static func record_fingerprint(tileset_record: Dictionary, images: Dictionary) -> String:
	var profile_id := str(tileset_record.get("profile", "rm2k"))
	var profile := RPGProfile.load_profile(profile_id)
	var version := profile.version if profile != null else 1
	var options: Dictionary = tileset_record.get("options", {})
	if profile_id == "rm2k":
		return fingerprint(images.get("sheet"), version, options)
	var prepared := {}
	for n in images:
		prepared[n] = _rgba(images[n])
	return fingerprint_images(profile_id, prepared, version, options)


static func _empty_report() -> Dictionary:
	return {
		"tileset": null, "warnings": [], "review": [], "fingerprint": "", "errors": [],
		"changed": [], "renumbered": [], "removed": [], "unknown_overrides": [], "from_cache": false,
	}


# --- cache -------------------------------------------------------------------------------------

static func cache_path(tileset_id: String) -> String:
	return CACHE_DIR.path_join(tileset_id + ".res")


## Loads res://rpg/generated/tilesets/<id>.res when its fingerprint and overrides still match,
## otherwise rebuilds (reporting changes against the old cache) and saves it. In an exported game
## the cache folder is read-only: the fresh TileSet is returned without saving.
static func cached_or_build(tileset_record: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var tid := str(tileset_record.get("id", "tileset"))
	var path := cache_path(tid)
	var loaded := load_record_images(tileset_record)
	var images: Dictionary = loaded.images
	var previous: TileSet = null
	if ResourceLoader.exists(path):
		previous = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
	if not images.is_empty() and previous != null:
		var fp := record_fingerprint(tileset_record, images)
		if previous.get_meta("rpg_fingerprint", "") == fp and previous.get_meta("rpg_overrides_hash", "") == overrides_hash(overrides) and int(previous.get_meta("rpg_builder_version", 0)) == BUILDER_VERSION:
			var r := _empty_report()
			r.tileset = previous
			r.fingerprint = fp
			r.from_cache = true
			# A cache saved before atlases were stored compressed: shrink it in place (editor or
			# playtest only; an exported game cannot write res://).
			if OS.has_feature("editor") and _has_raw_atlas(previous):
				var err0 := save_cache(previous, path)
				if err0 != OK:
					r.warnings.append("Could not compress TileSet cache %s (error %d)." % [path, err0])
			return r
	if images.is_empty():
		if previous != null:
			var r2 := _empty_report()
			r2.tileset = previous
			r2.from_cache = true
			r2.warnings.append("Sheet '%s' is missing; using the cached TileSet." % tileset_record.get("sheet", ""))
			return r2
		var r3 := _empty_report()
		r3.errors.append("Cannot load sheet '%s'." % tileset_record.get("sheet", ""))
		return r3
	var report := build_from_images(images, tileset_record, overrides, previous)
	for m in loaded.missing:
		report.warnings.append("Cannot load sheet '%s'; it is skipped." % m)
	if report.tileset != null:
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		var err := save_cache(report.tileset, path)
		if err != OK:
			report.warnings.append("Could not save TileSet cache %s (error %d)." % [path, err])
	return report


const FORCE_PNG_SETTING := "rendering/textures/lossless_compression/force_png"


## True when a TileSet keeps an atlas as a raw ImageTexture (an old, uncompressed cache).
static func _has_raw_atlas(ts: TileSet) -> bool:
	for i in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(i)) as TileSetAtlasSource
		if src != null and src.texture is ImageTexture:
			return true
	return false


## Saves a TileSet cache with its atlas images stored as lossless PNG inside the .res (a raw
## RGBA 48 px autotile atlas is about 80 MB; PNG makes it about 6 MB, which also keeps exported
## .pck files small). The TileSet in memory keeps its plain ImageTextures.
static func save_cache(ts: TileSet, path: String) -> Error:
	var originals := {}
	var force_png: Variant = ProjectSettings.get_setting(FORCE_PNG_SETTING, false)
	ProjectSettings.set_setting(FORCE_PNG_SETTING, true)  # PNG encodes ~3x faster than WebP here
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null or not (src.texture is ImageTexture):
			continue
		var img := src.texture.get_image()
		if img == null or img.is_empty():
			continue
		var packed := PortableCompressedTexture2D.new()
		packed.keep_compressed_buffer = true  # the buffer is what gets saved
		packed.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		originals[sid] = src.texture
		src.texture = packed
	var err := ResourceSaver.save(ts, path)
	for sid in originals:
		(ts.get_source(sid) as TileSetAtlasSource).texture = originals[sid]
	ProjectSettings.set_setting(FORCE_PNG_SETTING, force_png)
	return err


static func overrides_hash(overrides: Dictionary) -> String:
	return RPGJson.stringify(overrides).sha256_text()


## Fingerprint of decoded source pixels + profile version + builder version + options.
static func fingerprint(image: Image, profile_version: int, options: Dictionary = {}) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%dx%d:" % [image.get_width(), image.get_height()]).to_utf8_buffer())
	ctx.update(image.get_data())
	ctx.update(("rm2k:%d:builder:%d:" % [profile_version, BUILDER_VERSION]).to_utf8_buffer())
	ctx.update(RPGJson.stringify(options).to_utf8_buffer())
	return ctx.finish().hex_encode()


## tile_key -> hash of the source pixels it is built from.
static func tile_hashes(image: Image) -> Dictionary:
	var out := {}
	for key in RPGChipset2k.all_keys():
		var parts := PackedByteArray()
		for r in RPGChipset2k.key_rects(key):
			parts.append_array(image.get_region(r).get_data())
		if not _any_alpha(parts):
			out[key] = "empty"
			continue
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(parts)
		out[key] = ctx.finish().hex_encode().substr(0, 16)
	return out


static func _any_alpha(rgba: PackedByteArray) -> bool:
	for i in range(3, rgba.size(), 4):
		if rgba[i] != 0:
			return true
	return false


static func _compare(old: Dictionary, new: Dictionary, report: Dictionary) -> void:
	var by_hash := {}
	for k in old:
		if old[k] != "empty":
			by_hash[old[k]] = k
	for k in old:
		if not new.has(k):
			report.removed.append(k)
			report.warnings.append("Tile '%s' no longer exists in the sheet." % k)
	for k in new:
		if not old.has(k) or old[k] == new[k]:
			continue
		if new[k] != "empty" and by_hash.has(new[k]) and by_hash[new[k]] != k:
			report.renumbered.append({"from": by_hash[new[k]], "to": k})
			report.warnings.append("Tile '%s' moved to '%s': its settings stay on '%s' (check the override)." % [by_hash[new[k]], k, by_hash[new[k]]])
		elif new[k] == "empty":
			report.removed.append(k)
			report.warnings.append("Tile '%s' is now empty." % k)
		else:
			report.changed.append(k)
	if not report.changed.is_empty():
		report.warnings.append("%d tile(s) changed their pixels: %s" % [report.changed.size(), ", ".join(report.changed)])


# --- sheet loading -----------------------------------------------------------------------------

## Loads a sheet as an RGBA8 Image (imported texture first, raw file as fallback).
static func load_sheet_image(path: String) -> Image:
	if path == "":
		return null
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := ResourceLoader.load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Tile defaults from the pack.json of the pack that holds the sheet.
static func pack_tile_defaults(sheet_path: String) -> Dictionary:
	if not sheet_path.begins_with("res://assets/"):
		return {}
	var rel := sheet_path.substr("res://assets/".length())
	var pack := rel.get_slice("/", 0)
	var manifest_path := "res://assets/%s/pack.json" % pack
	if not FileAccess.file_exists(manifest_path):
		return {}
	var r := RPGJson.parse_file(manifest_path)
	if not r.ok or not (r.data is Dictionary):
		return {}
	var chipsets: Dictionary = r.data.get("chipsets", {})
	var entry: Variant = chipsets.get(sheet_path.get_file().get_basename(), {})
	if entry is Dictionary:
		return entry.get("tiles", {})
	return {}


# --- atlas building ----------------------------------------------------------------------------

static func _build_autotiles(ts: TileSet, img: Image, options: Dictionary, keys: Dictionary) -> void:
	var anims := []
	for g in RPGChipset2k.GROUP_COUNT:
		var info := RPGChipset2k.group_info(g)
		var anim: Array = info.anim
		if info.kind == "water" and str(options.get("water_animation", "pingpong")) == "loop":
			anim = [0, 1, 2]
		anims.append(anim)
	# [group, blend bits, atlas row] per source: every group's own row; then the water blend rows.
	var own := []
	for g in RPGChipset2k.GROUP_COUNT:
		own.append([g, 0, g])
	var water := [RPGChipset2k.GROUP_WATER_A, RPGChipset2k.GROUP_WATER_B, RPGChipset2k.GROUP_WATER_C]
	var blended := []
	for g in water:
		for b in range(1, RPGChipset2k.BLEND_COMBOS + 1):
			blended.append([g, b, RPGChipset2k.blend_row(g, b)])
	_build_autotile_source(ts, img, SOURCE_AUTOTILE, own, anims, options, keys)
	_build_autotile_source(ts, img, SOURCE_WATER_BLEND, blended, anims, options, keys)
	var blend := {}
	for g in water:
		var tiles := [[SOURCE_AUTOTILE, g]]
		for b in range(1, RPGChipset2k.BLEND_COMBOS + 1):
			tiles.append([SOURCE_WATER_BLEND, RPGChipset2k.blend_row(g, b)])
		blend[g] = {"tiles": tiles, "with": RPGChipset2k.blend_partners(g)}
	ts.set_meta(RPGAutotile.BLEND_META, blend)


## One rm2k autotile atlas source from lines [group, blend bits, row] (columns: variants, frame k
## at column v + 48 * k).
static func _build_autotile_source(ts: TileSet, img: Image, sid: int, lines: Array, anims: Array, options: Dictionary, keys: Dictionary) -> void:
	var t := RPGChipset2k.TILE
	var atlas := Image.create_empty(AUTOTILE_FRAME_STRIDE * MAX_AUTOTILE_FRAMES * t, lines.size() * t, false, Image.FORMAT_RGBA8)
	for line in lines:
		var anim: Array = anims[line[0]]
		for k in anim.size():
			for v in RPGAutotile.VARIANT_SLOTS:
				var rects := RPGChipset2k.quarter_rects(line[0], v, int(anim[k]), line[1])
				RPGAutotile.compose(img, rects, atlas, Vector2i((v + k * AUTOTILE_FRAME_STRIDE) * t, int(line[2]) * t))
	var src := _new_source(ts, atlas, sid)
	var frame_time := float(options.get("water_frame_time", WATER_FRAME_TIME))
	for line in lines:
		var g: int = line[0]
		var key: String = RPGChipset2k.group_info(g).key
		if not keys.has(key):
			keys[key] = []
		for v in RPGAutotile.VARIANT_SLOTS:
			var c := Vector2i(v, int(line[2]))
			src.create_tile(c)
			if anims[g].size() > 1:
				set_tile_animation(src, c, anims[g].size(), Vector2i(AUTOTILE_FRAME_STRIDE - 1, 0), frame_time)
			keys[key].append([sid, c])
			src.get_tile_data(c, 0).set_custom_data("autotile", g)


static func _build_plain(ts: TileSet, img: Image, source_id: int, prefix: String, keys: Dictionary) -> void:
	var t := RPGChipset2k.TILE
	var count := RPGChipset2k.LOWER_COUNT
	var atlas := Image.create_empty(6 * t, (count / 6) * t, false, Image.FORMAT_RGBA8)
	for i in count:
		var r := RPGChipset2k.lower_rect(i) if prefix == "lower" else RPGChipset2k.upper_rect(i)
		atlas.blit_rect(img, r, Vector2i((i % 6) * t, (i / 6) * t))
	var src := _new_source(ts, atlas, source_id)
	for i in count:
		var c := Vector2i(i % 6, i / 6)
		src.create_tile(c)
		src.get_tile_data(c, 0).set_custom_data("autotile", -1)
		keys["%s_%d" % [prefix, i]] = [[source_id, c]]


static func _build_animated(ts: TileSet, img: Image, options: Dictionary, keys: Dictionary) -> void:
	var t := RPGChipset2k.TILE
	var n := RPGChipset2k.ANIM_COUNT
	var frames := RPGChipset2k.ANIM_FRAMES
	var atlas := Image.create_empty(n * frames * t, t, false, Image.FORMAT_RGBA8)
	for i in n:
		for f in frames:
			atlas.blit_rect(img, RPGChipset2k.anim_frame_rect(i, f), Vector2i((i + f * n) * t, 0))
	var src := _new_source(ts, atlas, SOURCE_ANIMATED)
	for i in n:
		var c := Vector2i(i, 0)
		src.create_tile(c)
		set_tile_animation(src, c, frames, Vector2i(n - 1, 0), float(options.get("anim_frame_time", ANIM_FRAME_TIME)))
		src.get_tile_data(c, 0).set_custom_data("autotile", -1)
		keys["anim_%d" % i] = [[SOURCE_ANIMATED, c]]


static func _new_source(ts: TileSet, atlas: Image, source_id: int) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas)
	src.texture_region_size = ts.tile_size
	ts.add_source(src, source_id)
	return src


## Animation helper: `frames` frames laid out to the right of the tile, `separation` tiles apart.
## columns 0 lays the frames out in one row; 1 stacks them vertically.
static func set_tile_animation(src: TileSetAtlasSource, coords: Vector2i, frames: int, separation: Vector2i, frame_time: float, columns := 0) -> void:
	src.set_tile_animation_columns(coords, columns)
	src.set_tile_animation_separation(coords, separation)
	src.set_tile_animation_frames_count(coords, frames)
	for f in frames:
		src.set_tile_animation_frame_duration(coords, f, frame_time)
	src.set_tile_animation_mode(coords, TileSetAtlasSource.TILE_ANIMATION_MODE_DEFAULT)


## Changes the frame time of every animated tile in a TileSet (e.g. water speed option).
static func set_animation_speed(ts: TileSet, frame_time: float) -> void:
	for si in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(si)) as TileSetAtlasSource
		if src == null:
			continue
		for ti in src.get_tiles_count():
			var c := src.get_tile_id(ti)
			for f in src.get_tile_animation_frames_count(c):
				src.set_tile_animation_frame_duration(c, f, frame_time)


# --- tile settings -----------------------------------------------------------------------------

static func _default_for(key: String, img: Image, report: Dictionary) -> Dictionary:
	var d := {"passage": 15, "flags": 0, "terrain": 0}
	if key.begins_with("water_"):
		d.passage = 0
	elif key.begins_with("anim_"):
		d.passage = 0
		report.review.append(key)
	elif key == "upper_0":
		d.flags = FLAG_STAR
	elif key.begins_with("upper_"):
		var r := RPGChipset2k.upper_rect(int(key.substr(6)))
		if img.get_region(r).is_invisible():
			d.flags = FLAG_STAR
		else:
			d.passage = 0
			report.review.append(key)
	return d


static func _merge(into: Dictionary, from: Dictionary) -> void:
	for f in ["passage", "flags", "terrain"]:
		if from.has(f):
			into[f] = int(from[f])


static func _apply(ts: TileSet, source_id: int, coords: Vector2i, key: String, s: Dictionary) -> void:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var td := src.get_tile_data(coords, 0)
	td.set_custom_data("passage", int(s.passage))
	td.set_custom_data("flags", int(s.flags))
	td.set_custom_data("terrain", int(s.terrain))
	td.set_custom_data("tile_key", key)
	td.z_index = STAR_Z_INDEX if int(s.flags) & FLAG_STAR else 0


## Re-applies tile settings to an existing TileSet (Tilesets tab edits without a rebuild).
static func apply_tile_settings(ts: TileSet, tile_key: String, settings: Dictionary) -> void:
	for e in tiles_for_key(ts, tile_key):
		var td := (ts.get_source(e[0]) as TileSetAtlasSource).get_tile_data(e[1], 0)
		var s := {"passage": td.get_custom_data("passage"), "flags": td.get_custom_data("flags"), "terrain": td.get_custom_data("terrain")}
		_merge(s, settings)
		_apply(ts, e[0], e[1], tile_key, s)


## Every [source_id, atlas_coords] whose tile_key matches.
static func tiles_for_key(ts: TileSet, tile_key: String) -> Array:
	var out := []
	for si in ts.get_source_count():
		var sid := ts.get_source_id(si)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for ti in src.get_tiles_count():
			var c := src.get_tile_id(ti)
			if str(src.get_tile_data(c, 0).get_custom_data("tile_key")) == tile_key:
				out.append([sid, c])
	return out


## Atlas location to paint a tile_key with: {source, coords} (autotiles: the preview variant 47).
## Pass the TileSet for xp/vx/mv TileSets (their layout is stored in its rpg_key_atlas meta);
## without it the rm2k layout is assumed.
static func atlas_for_key(tile_key: String, tile_set: TileSet = null) -> Dictionary:
	if tile_set != null and tile_set.has_meta(KEY_ATLAS_META):
		var m: Dictionary = tile_set.get_meta(KEY_ATLAS_META)
		if m.has(tile_key):
			var e: Array = m[tile_key]
			return {"source": int(e[0]), "coords": e[1] as Vector2i}
		return {}
	if tile_key.begins_with("lower_"):
		var i := int(tile_key.substr(6))
		return {"source": SOURCE_LOWER, "coords": Vector2i(i % 6, i / 6)}
	if tile_key.begins_with("upper_"):
		var j := int(tile_key.substr(6))
		return {"source": SOURCE_UPPER, "coords": Vector2i(j % 6, j / 6)}
	if tile_key.begins_with("anim_"):
		return {"source": SOURCE_ANIMATED, "coords": Vector2i(int(tile_key.substr(5)), 0)}
	var g := RPGChipset2k.group_keys().find(tile_key)
	if g >= 0:
		return {"source": SOURCE_AUTOTILE, "coords": Vector2i(RPGAutotile.PREVIEW_VARIANT, g)}
	return {}


## Tile layer (1 = lower, 2 = upper) the Auto layer mode uses for a source.
static func default_layer_for(source_id: int) -> int:
	return 2 if source_id == SOURCE_UPPER else 1


# --- region and shadow tilesets ----------------------------------------------------------------

## Region TileSet: source 0, region n (1..255) at atlas (n % 16, n / 16): a translucent coloured
## square with the number. Custom data layer `region` (int).
## The colour of region `n` everywhere it is drawn (map overlay and the R palette).
static func region_color(n: int, alpha := 1.0) -> Color:
	return Color.from_hsv(fmod(n * 0.618034, 1.0), 0.7, 0.95, alpha)


static func region_tileset(tile_size := 16) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "region")
	ts.set_custom_data_layer_type(0, TYPE_INT)
	var atlas := Image.create_empty(16 * tile_size, 16 * tile_size, false, Image.FORMAT_RGBA8)
	for n in range(1, 256):
		var o := Vector2i((n % 16) * tile_size, (n / 16) * tile_size)
		var c := region_color(n, 0.45)
		atlas.fill_rect(Rect2i(o, Vector2i(tile_size, tile_size)), c)
		var edge := Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, 0.8)
		for i in tile_size:
			atlas.set_pixelv(o + Vector2i(i, 0), edge)
			atlas.set_pixelv(o + Vector2i(i, tile_size - 1), edge)
			atlas.set_pixelv(o + Vector2i(0, i), edge)
			atlas.set_pixelv(o + Vector2i(tile_size - 1, i), edge)
		_draw_number(atlas, n, o, tile_size)
	var src := _new_source(ts, atlas, 0)
	for n in range(1, 256):
		var coords := Vector2i(n % 16, n / 16)
		src.create_tile(coords)
		src.get_tile_data(coords, 0).set_custom_data("region", n)
	ts.set_meta("rpg_kind", "regions")
	return ts


## Shadow TileSet: source 0, 16 tiles at atlas (mask, 0); bits 1 TL, 2 TR, 4 BL, 8 BR are filled
## with semi-transparent black. Custom data layer `shadow` (int, the mask). z_index stays 0.
static func shadow_tileset(tile_size := 16) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "shadow")
	ts.set_custom_data_layer_type(0, TYPE_INT)
	var h := tile_size / 2
	var atlas := Image.create_empty(16 * tile_size, tile_size, false, Image.FORMAT_RGBA8)
	var shade := Color(0, 0, 0, 0.5)
	for m in 16:
		for q in 4:
			if m & (1 << q):
				atlas.fill_rect(Rect2i(m * tile_size + (q % 2) * h, (q / 2) * h, h, h), shade)
	var src := _new_source(ts, atlas, 0)
	for m in 16:
		src.create_tile(Vector2i(m, 0))
		src.get_tile_data(Vector2i(m, 0), 0).set_custom_data("shadow", m)
	ts.set_meta("rpg_kind", "shadows")
	return ts


## 3x5 pixel digits, rows top to bottom, 3 bits per row (MSB = left).
const DIGITS := [
	[7, 5, 5, 5, 7], [2, 6, 2, 2, 7], [7, 1, 7, 4, 7], [7, 1, 3, 1, 7], [5, 5, 7, 1, 1],
	[7, 4, 7, 1, 7], [7, 4, 7, 5, 7], [7, 1, 1, 2, 2], [7, 5, 7, 5, 7], [7, 5, 7, 1, 7],
]


static func _draw_number(img: Image, n: int, origin: Vector2i, tile_size: int) -> void:
	var s := str(n)
	var w := s.length() * 4 - 1
	if w > tile_size - 2:
		return
	var x0 := origin.x + (tile_size - w) / 2
	var y0 := origin.y + (tile_size - 5) / 2
	for pass_i in 2:
		for ci in s.length():
			var rows: Array = DIGITS[int(s[ci])]
			for ry in 5:
				for rx in 3:
					if int(rows[ry]) & (4 >> rx):
						var p := Vector2i(x0 + ci * 4 + rx, y0 + ry)
						if pass_i == 0:
							img.set_pixelv(p + Vector2i(1, 1), Color(0, 0, 0, 0.85))
						else:
							img.set_pixelv(p, Color(1, 1, 1, 1))
