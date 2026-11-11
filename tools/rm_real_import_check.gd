extends SceneTree
## Checks the RPG Maker importer on a real RPG Maker folder you own (an RTP install, or an MV/MZ
## NewData folder). Everything goes to user://rm_real_check, never into the project, and nothing
## is downloaded. Renders a contact sheet: each imported tileset's autotiles and plain tiles on a
## small map, plus character walk frames and faces cut with the folder's profile.
##   godot --path . --script res://tools/rm_real_import_check.gd -- --folder="C:/.../NewData" [--out=tools/shots/rm_real.png]

const RMImport := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")
const ROOT := "user://rm_real_check"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var folder := str(args.get("folder", ""))
	var out := str(args.get("out", "res://tools/shots/rm_real.png"))
	if folder == "":
		printerr("usage: --folder=<RPG Maker folder>")
		quit(1)
		return
	# Fresh tileset records each run (the importer never adds a record twice).
	DirAccess.remove_absolute(ROOT + "/rpg/database/tilesets.json")
	var od := DirAccess.open(ROOT + "/rpg/tileset_overrides")
	if od != null:
		for f in od.get_files():
			od.remove(f)
	var det := RMImport.detect(folder)
	print("detected profile: ", det.profile, "  evidence: ", det.evidence)
	var p := RMImport.plan(folder, "rm_real", ROOT + "/assets", ROOT + "/rpg")
	print("plan: %d files, %d skipped, %d tileset records" % [p.files.size(), p.skipped.size(), p.tilesets.size()])
	for w in p.warnings:
		print("  warning: ", w)
	var skipped_reasons := {}
	for s in p.skipped:
		skipped_reasons[str(s.reason)] = int(skipped_reasons.get(str(s.reason), 0)) + 1
	print("  skipped by reason: ", skipped_reasons)
	DirAccess.make_dir_recursive_absolute(ROOT + "/rpg/database")
	var r := RMImport.apply(p, null, null, (p.files as Array).map(func(f): return f.dst))
	print("apply: copied %d, errors %s, records %s" % [r.copied.size(), r.errors, r.records_added])
	# Build every tileset record and paint a sample of each.
	var tiles_png := []
	var problems := []
	for entry in p.tilesets:
		var rec: Dictionary = entry.record
		var ov: Dictionary = RPGJson.load_or(ROOT + "/rpg/tileset_overrides/%s.json" % rec.id, {})
		if not ov.is_empty():
			print("  %s: %d tile settings from RPG Maker" % [rec.id, (ov.get("tiles", {}) as Dictionary).size()])
		var rep := RPGTilesetBuilder.build_with_report(rec, ov)
		if not rep.errors.is_empty():
			problems.append("%s: %s" % [rec.get("id", "?"), rep.errors])
			continue
		for w in rep.get("warnings", []):
			print("  %s warning: %s" % [rec.get("id", "?"), w])
		var ts: TileSet = rep.tileset
		var img := await _paint_sample(ts)
		print("tileset %s (%s): tile %d px, %d sources" % [rec.get("id", "?"), rec.get("profile", "?"), ts.tile_size.x, ts.get_source_count()])
		tiles_png.append([str(rec.get("id", "?")), img])
	# Characters and faces, cut with the detected profile.
	var chars := _strip("charset", "CharSet", det.profile)
	var faces := _strip("faceset", "FaceSet", det.profile)
	var sheet := _compose(tiles_png, chars, faces)
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("saved ", out)
	for pr in problems:
		printerr("PROBLEM ", pr)
	quit(0 if problems.is_empty() else 2)


## A 14x8 map: an A2 (or first autotile) field with a lake of A1 water, a patch of the second
## autotile, and a row of the first B and A5 tiles. Rendered in a SubViewport.
func _paint_sample(ts: TileSet) -> Image:
	var t := ts.tile_size.x
	var size := Vector2i(14, 8)
	var vp := SubViewport.new()
	vp.size = size * t
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var lower := TileMapLayer.new()
	lower.tile_set = ts
	var upper := TileMapLayer.new()
	upper.tile_set = ts
	vp.add_child(lower)
	vp.add_child(upper)
	var autos := []
	for sid in ts.get_meta(RPGTilesetBuilder.AUTOTILE_SOURCES_META, []):
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null or src.texture == null:
			continue
		for g in int(src.texture.get_height() / t):
			var c := Vector2i(RPGAutotile.PREVIEW_VARIANT, g)
			if src.has_tile(c):
				autos.append([int(sid), c])
	var field := []
	for y in size.y:
		for x in size.x:
			field.append(Vector2i(x, y))
	var ground: Array = _pick(ts, autos, "a2_") if not _pick(ts, autos, "a2_").is_empty() else (autos[0] if not autos.is_empty() else [])
	if not ground.is_empty():
		RPGAutotile.paint_cells(lower, field, ground[0], ground[1])
	var water := _pick(ts, autos, "a1_")
	if not water.is_empty():
		var lake := []
		for y in range(1, 5):
			for x in range(1, 6):
				lake.append(Vector2i(x, y))
		RPGAutotile.paint_cells(lower, lake, water[0], water[1])
	if autos.size() > 1:
		var patch := []
		for y in range(1, 4):
			for x in range(8, 12):
				patch.append(Vector2i(x, y))
		var second: Array = autos[mini(5, autos.size() - 1)]
		RPGAutotile.paint_cells(lower, patch, second[0], second[1])
	var x0 := 0
	for key_prefix in ["a5_", "b_", "c_"]:
		for i in range(1, 6):
			var a := RPGTilesetBuilder.atlas_for_key("%s%d" % [key_prefix, i + (8 if key_prefix != "a5_" else 0)], ts)
			if a.is_empty():
				continue
			(lower if key_prefix == "a5_" else upper).set_cell(Vector2i(x0 % size.x, 6 + x0 / size.x), a.source, a.coords)
			x0 += 1
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _pick(ts: TileSet, autos: Array, prefix: String) -> Array:
	for a in autos:
		var src := ts.get_source(a[0]) as TileSetAtlasSource
		var td := src.get_tile_data(a[1], 0)
		if td != null and td.has_custom_data("tile_key") and str(td.get_custom_data("tile_key")).begins_with(prefix):
			return a
	return []


## First few sheets of a kind: one standing frame per character, facing down.
func _strip(kind: String, folder: String, profile: String) -> Image:
	var dir := ROOT + "/assets/rm_real/" + folder
	var out := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var frames := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := Array(d.get_files()).filter(func(f): return str(f).to_lower().ends_with(".png"))
	files.sort()
	# Ordinary multi-character sheets first ($ and ! sheets are single objects or doors).
	files.sort_custom(func(x, y): return (0 if not str(x).begins_with("$") and not str(x).begins_with("!") else 1) < (0 if not str(y).begins_with("$") and not str(y).begins_with("!") else 1))
	for f in files.slice(0, 3):
		var img := Image.load_from_file(dir + "/" + f)
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var tex := ImageTexture.create_from_image(img)
		var single := RPGCharset.is_single_character(str(f), profile)
		for i in (1 if single else 8):
			var r: Rect2i
			if kind == "charset":
				r = Rect2i(RPGCharset.frame_texture(tex, i, "down", 1, profile, single).region)
			else:
				r = RPGCharset.face_rect(profile, img.get_size(), i)
			if r.size.x > 0 and Rect2i(Vector2i.ZERO, img.get_size()).encloses(r):
				frames.append(img.get_region(r))
	if frames.is_empty():
		return out
	var w := 0
	var h := 0
	for fr in frames:
		w += fr.get_width() + 2
		h = maxi(h, fr.get_height())
	out = Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.2, 0.2, 0.25))
	var x := 0
	for fr in frames:
		out.blend_rect(fr, Rect2i(Vector2i.ZERO, fr.get_size()), Vector2i(x, 0))
		x += fr.get_width() + 2
	return out


func _compose(tiles: Array, chars: Image, faces: Image) -> Image:
	var parts := []
	for t in tiles:
		parts.append(t[1])
	parts.append(chars)
	parts.append(faces)
	var w := 0
	var h := 0
	for p in parts:
		w = maxi(w, p.get_width())
		h += p.get_height() + 6
	var out := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.1, 0.1, 0.12))
	var y := 0
	for p in parts:
		p.convert(Image.FORMAT_RGBA8)
		out.blit_rect(p, Rect2i(Vector2i.ZERO, p.get_size()), Vector2i(0, y))
		y += p.get_height() + 6
	return out
