extends "res://tests/rpg_test_case.gd"
## Image-backed maps (RPGImageMap): image checks, creation, editor and runtime rendering,
## navigation painting and movement, the foreground, art replacement, validation, export and
## legacy maps. Every image is generated here into user:// (no art files are needed).

const Env := preload("res://tests/rpg_test_env.gd")
const Deploy := preload("res://addons/rpg/editor/tools/rpg_deploy.gd")
const TMP := "user://rpg_image_map_test"
const ROOT := TMP + "/rpg"
const ART := TMP + "/art"
const FIXTURE := "res://tests/fixtures/door_project"

var data: RPGProjectData


func before_each() -> void:
	_make_project()
	data = RPGProjectData.open(ROOT)


func after_each() -> void:
	await frames(1)
	_rm(TMP)


# --- helpers -------------------------------------------------------------------------------------

## The door fixture plus the sample database, as a throwaway project (2000 style, 16 px tiles).
func _make_project() -> void:
	_rm(TMP)
	DirAccess.make_dir_recursive_absolute(ROOT + "/maps")
	DirAccess.make_dir_recursive_absolute(ROOT + "/database")
	DirAccess.make_dir_recursive_absolute(ART)
	for f in ["project.json", "state.json", "common_events.json"]:
		_copy(FIXTURE.path_join(f), ROOT.path_join(f))
	for f in ["town.events.json", "town.map.json"]:
		_copy(FIXTURE.path_join("maps/" + f), ROOT.path_join("maps/" + f))
	var d := DirAccess.open("res://rpg/database")
	for f in d.get_files():
		if f.ends_with(".json"):
			_copy("res://rpg/database/" + f, ROOT.path_join("database/" + f))
	RPGJson.save_file(ROOT.path_join("profile.json"), {"schema_version": 1, "profile": "rm2k", "tile_size": 16})
	RPGJson.save_file(ROOT.path_join("map_index.json"), {"schema_version": 1, "maps": [{"id": "town", "name": "Town", "parent": "", "order": 0}], "favourites": []})


func _copy(from: String, to: String) -> void:
	var f := FileAccess.open(to, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(from))
	f.close()


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)


## A test picture: a checkerboard of 16 px cells with a 1 px white mark on every grid
## intersection (so alignment can be checked pixel by pixel).
func _image(name: String, w: int, h: int, seed_colour := Color(0.2, 0.5, 0.3)) -> String:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := seed_colour if ((x / 16 + y / 16) % 2 == 0) else seed_colour.darkened(0.4)
			if x % 16 == 0 and y % 16 == 0:
				c = Color.WHITE
			img.set_pixel(x, y, c)
	var path := ART.path_join(name)
	img.save_png(path)
	return path


## A transparent foreground with an opaque arch across cells (3..6, 2).
func _foreground(name: String, w: int, h: int) -> String:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(3 * 16, 2 * 16, 4 * 16, 16), Color(0.6, 0.3, 0.1, 1))
	var path := ART.path_join(name)
	img.save_png(path)
	return path


func _props(base: String, fg := "", new_cells := "blocked") -> Dictionary:
	var p := RPGMapFiles.default_props("", "Garden", "", 1, 1)
	p["image_map"] = RPGImageMap.new_block(base, fg, new_cells)
	return p


## Creates image map `id` from a 160×128 base (10×8 cells).
func _make_image_map(id := "garden", start := RPGImageMap.BLOCKED, fg := "") -> void:
	var base := _image("base.png", 160, 128)
	var c := RPGImageMap.check_images(base, fg, 16, RPGImageMap.limits(data))
	assert_true(c.ok, str(c.errors))
	assert_eq(RPGMapFiles.create_image_map(data, id, "Garden", _props(base, fg, "walkable" if start == RPGImageMap.WALKABLE else "blocked"), c.cells, start), OK)


# --- IM-02: checking images ----------------------------------------------------------------------

func test_valid_image_gives_the_cell_size() -> void:
	var c := RPGImageMap.check_images(_image("ok.png", 640, 480), "", 16, RPGImageMap.limits(data))
	assert_true(c.ok, str(c.errors))
	assert_eq(c.cells, Vector2i(40, 30))
	assert_eq(c.pixels, Vector2i(640, 480))


func test_indivisible_image_reports_size_tile_and_nearest_sizes() -> void:
	var c := RPGImageMap.check_images(_image("odd.png", 650, 480), "", 16, RPGImageMap.limits(data))
	assert_false(c.ok)
	var msg := str(c.errors[0])
	for part in ["650×480", "16 px", "640", "656"]:
		assert_true(msg.contains(part), "message names %s: %s" % [part, msg])
	assert_false(msg.contains("height"), "the height already fits")
	assert_eq(RPGImageMap.nearest_valid(650, 16), [640, 656])
	assert_eq(RPGImageMap.nearest_valid(10, 16), [16, 32], "never smaller than one tile")
	assert_eq(RPGImageMap.nearest_valid(48, 48), [48, 96])


func test_unreadable_missing_and_zero_sized_images_are_rejected() -> void:
	var junk := ART.path_join("junk.png")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("this is not a png")
	f.close()
	var c := RPGImageMap.check_images(junk, "", 16, RPGImageMap.limits(data))
	assert_false(c.ok)
	assert_true(str(c.errors[0]).contains("could not be read"), str(c.errors))
	c = RPGImageMap.check_images(ART.path_join("nope.png"), "", 16, RPGImageMap.limits(data))
	assert_false(c.ok)
	assert_true(str(c.errors[0]).contains("does not exist"), str(c.errors))
	c = RPGImageMap.check_size(Vector2i(0, 32), 16, RPGImageMap.limits(data))
	assert_false(c.ok)
	assert_true(str(c.errors[0]).contains("no pixels"), str(c.errors))


func test_over_limit_image_is_rejected_with_the_limit_and_large_ones_warn() -> void:
	var lim := {"max_size": 256, "warn_size": 128}
	var c := RPGImageMap.check_images(_image("big.png", 320, 64), "", 16, lim)
	assert_false(c.ok)
	assert_true(str(c.errors[0]).contains("256"), str(c.errors))
	c = RPGImageMap.check_images(_image("large.png", 192, 64), "", 16, lim)
	assert_true(c.ok)
	assert_eq(c.warnings.size(), 1, "large images warn (video memory)")
	# Project settings can move the limits, never past the engine's.
	data.project["image_maps"] = {"max_size": 99999, "warn_size": 100}
	assert_eq(RPGImageMap.limits(data), {"max_size": RPGImageMap.ENGINE_MAX_SIZE, "warn_size": 100})


func test_foreground_must_match_the_base_size() -> void:
	var base := _image("b.png", 160, 128)
	var c := RPGImageMap.check_images(base, _foreground("f.png", 160, 112), 16, RPGImageMap.limits(data))
	assert_false(c.ok)
	assert_true(str(c.errors[0]).contains("160×112") and str(c.errors[0]).contains("160×128"), "both sizes shown: %s" % c.errors)
	assert_true(RPGImageMap.check_images(base, _foreground("f2.png", 160, 128), 16, RPGImageMap.limits(data)).ok)


# --- IM-01: creating -------------------------------------------------------------------------------

func test_create_image_map_writes_standard_files_sized_from_the_image() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE)
	for ext in [".tscn", ".map.json", ".events.json"]:
		assert_true(FileAccess.file_exists(ROOT + "/maps/garden" + ext), ext)
	assert_true(data.maps.has("garden"), "in the map index")
	var p := data.map_props("garden")
	assert_eq([int(p.width), int(p.height)], [10, 8])
	assert_true(RPGImageMap.is_image_map(p))
	assert_eq(RPGImageMap.base_path(p), ART.path_join("base.png"), "stored as a project path")
	# Reopening keeps the assignment, the size and the navigation.
	var d2 := RPGProjectData.open(ROOT)
	var node := RPGMapFiles.load_map(d2, "garden")
	assert_true(node.navigation != null, "navigation layer saved")
	assert_eq(node.navigation.get_used_cells().size(), 80, "every cell filled")
	assert_eq(RPGImageMap.nav_bits(node.navigation, Vector2i(9, 7)), RPGImageMap.WALKABLE)
	assert_true(node.image_base != null, "base image drawn")
	node.free()


func test_create_blocked_starts_every_cell_blocked() -> void:
	_make_image_map("cave", RPGImageMap.BLOCKED)
	var node := RPGMapFiles.load_map(data, "cave")
	assert_eq(RPGImageMap.nav_bits(node.navigation, Vector2i(4, 4)), RPGImageMap.BLOCKED)
	node.free()


func test_saved_scene_holds_no_image_sprites() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE, _foreground("fg.png", 160, 128))
	var text := FileAccess.get_file_as_string(ROOT + "/maps/garden.tscn")
	assert_false(text.contains(RPGImageMap.BASE_NODE), "the base sprite is not saved")
	assert_false(text.contains(RPGImageMap.FOREGROUND_NODE), "the foreground sprite is not saved")
	assert_false(text.contains("base.png"), "image pixels and paths stay out of the scene")
	assert_true(text.contains("Navigation"))


# --- IM-03 / IM-04: rendering ----------------------------------------------------------------------

func test_images_are_anchored_at_the_origin_unscaled_and_unfiltered() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE, _foreground("fg.png", 160, 128))
	var node := RPGMapFiles.load_map(data, "garden")
	for s in [node.image_base, node.image_foreground]:
		assert_true(s != null)
		assert_eq(s.position, Vector2.ZERO)
		assert_false(s.centered)
		assert_eq(s.scale, Vector2.ONE, "one image pixel is one map pixel")
		assert_eq(s.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_eq(Vector2i(s.texture.get_size()), Vector2i(160, 128))
	assert_true(node.image_base.z_index < 0, "base under every tile layer")
	assert_true(node.image_foreground.z_index > RPGTilesetBuilder.STAR_Z_INDEX and node.image_foreground.z_index > 4, "foreground above star tiles and every character")
	# Grid intersections in the image land on cell corners in map coordinates.
	var img: Image = node.image_base.texture.get_image()
	for cell in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(9, 7)]:
		var px := Vector2i(cell * 16)
		assert_eq(img.get_pixelv(px), Color.WHITE, "mark at cell %s" % cell)
		assert_eq(Vector2i(node.image_base.transform * Vector2(px)), cell * 16)
	node.free()


func test_images_scale_with_a_smaller_tileset_so_the_camera_zoom_restores_them() -> void:
	# 16 px art in a 48 px project: the map is drawn at 16 px and zoomed 3x; the 48 px-per-cell
	# image is scaled by 1/3 so it still covers exactly the same cells.
	RPGJson.save_file(ROOT.path_join("profile.json"), {"schema_version": 1, "profile": "mv", "tile_size": 48})
	data = RPGProjectData.open(ROOT)
	var base := _image("big48.png", 480, 384)
	var c := RPGImageMap.check_images(base, "", 48, RPGImageMap.limits(data))
	assert_eq(c.cells, Vector2i(10, 8))
	var p := _props(base)
	p["tileset"] = "town"   # a 16 px 2000-style tileset from the sample database
	assert_eq(RPGMapFiles.create_image_map(data, "big", "Big", p, c.cells, RPGImageMap.WALKABLE), OK)
	var node := RPGMapFiles.load_map(data, "big")
	assert_eq(node.tile_layers[0].tile_set.tile_size.x, 16)
	assert_true(is_equal_approx(node.image_base.scale.x, 1.0 / 3.0))
	assert_eq(node.image_base.texture.get_size() * node.image_base.scale, Vector2(160, 128), "10×8 cells of 16 px")
	node.free()


func test_editor_foreground_can_be_hidden_or_dimmed_without_changing_the_map() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE, _foreground("fg.png", 160, 128))
	var view := RPGMapView.new()
	tree.root.add_child(view)
	view.open_map(data, "garden")
	assert_true(view.is_image_map())
	var fg: Sprite2D = view.map_node.image_foreground
	assert_true(fg.visible)
	view.set_foreground_view("dim")
	assert_true(fg.visible and fg.modulate.a < 1.0, "dimmed")
	view.set_foreground_view("hide")
	assert_false(fg.visible, "hidden")
	assert_true(view.overlay.z_index > fg.z_index, "event markers are drawn above the foreground")
	var bg: CanvasItem = view.viewport.get_node("Background")
	assert_true(bg.z_index < view.map_node.image_base.z_index, "the editor's backdrop is behind the base picture")
	assert_false(view.dirty, "viewing options are not edits")
	view.set_foreground_view("show")
	view.queue_free()


# --- IM-05: navigation -----------------------------------------------------------------------------

func test_navigation_decides_movement_without_any_tiles() -> void:
	_make_image_map("garden", RPGImageMap.BLOCKED)
	var node := RPGMapFiles.load_map(data, "garden")
	node.size = Vector2i(10, 8)
	var mv := RPGMovement.new(node)
	assert_eq(mv.passage(Vector2i(2, 2)), 0, "blocked to start")
	RPGImageMap.set_nav(node.navigation, Vector2i(2, 2), 15)
	RPGImageMap.set_nav(node.navigation, Vector2i(3, 2), 15)
	assert_true(mv.can_move(null, Vector2i(2, 2), Vector2i.RIGHT), "walkable cells, no tile needed")
	assert_false(mv.can_move(null, Vector2i(3, 2), Vector2i.RIGHT), "into a blocked cell")
	# Directional: (3, 2) open on its left side only can be entered from the left but not left upward.
	RPGImageMap.set_nav(node.navigation, Vector2i(3, 2), RPGMovement.BIT.left)
	assert_true(mv.can_move(null, Vector2i(2, 2), Vector2i.RIGHT))
	RPGImageMap.set_nav(node.navigation, Vector2i(3, 1), 15)
	assert_false(mv.can_move(null, Vector2i(3, 2), Vector2i.UP), "its top side is closed")
	node.free()


func test_a_painted_blocking_tile_still_blocks_on_a_walkable_cell() -> void:
	var base := _image("base.png", 160, 128)
	var p := _props(base)
	p["tileset"] = "town"
	assert_eq(RPGMapFiles.create_image_map(data, "yard", "Yard", p, Vector2i(10, 8), RPGImageMap.WALKABLE), OK)
	var node := RPGMapFiles.load_map(data, "yard")
	node.size = Vector2i(10, 8)
	var mv := RPGMovement.new(node)
	assert_eq(mv.passage(Vector2i(1, 1)), 15)
	# A wall tile: any 2000-style lower tile whose passage is 0.
	var ts: TileSet = node.tile_layers[0].tile_set
	var wall := _tile_with_passage(ts, 0)
	assert_true(wall.size() == 2, "the town tileset has a wall tile")
	node.tile_layers[0].set_cell(Vector2i(1, 1), wall[0], wall[1])
	assert_eq(mv.passage(Vector2i(1, 1)), 0, "navigation AND tile")
	node.free()


func _tile_with_passage(ts: TileSet, bits: int) -> Array:
	for si in ts.get_source_count():
		var sid := ts.get_source_id(si)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var co := src.get_tile_id(i)
			var td := src.get_tile_data(co, 0)
			if td.has_custom_data("passage") and int(td.get_custom_data("passage")) == bits and int(td.get_custom_data("flags")) & RPGMovement.FLAG_STAR == 0 and int(td.get_custom_data("autotile")) < 0:
				return [sid, co]
	return []


func test_painting_navigation_with_pencil_rect_fill_eyedropper_and_undo() -> void:
	_make_image_map("garden", RPGImageMap.BLOCKED)
	var view := RPGMapView.new()
	var undo := UndoRedo.new()
	view.undo = RPGUndo.new(undo)
	tree.root.add_child(view)
	view.open_map(data, "garden")
	view.set_mode("nav")
	var nav: TileMapLayer = view.map_node.navigation
	# Rectangle of walkable floor.
	view.brush = {"kind": "nav", "bits": 15}
	view.tool = "rect"
	view._begin_stroke()
	view._apply_shape(Vector2i(1, 1), Vector2i(4, 3), false)
	view._end_stroke("Rectangle")
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(4, 3)), 15)
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(5, 3)), 0)
	# Pencil a one-way cell.
	view.brush = {"kind": "nav", "bits": 1}
	view.tool = "pencil"
	view._begin_stroke()
	view._apply_at(Vector2i(6, 6), false, Vector2.ZERO)
	view._end_stroke("Paint")
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(6, 6)), 1)
	# Fill the blocked area (everything outside the rectangle and the one-way cell).
	view.brush = {"kind": "nav", "bits": 15}
	view.tool = "fill"
	view._begin_stroke()
	view._fill(Vector2i(9, 0))
	view._end_stroke("Fill")
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(9, 7)), 15, "filled")
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(6, 6)), 1, "a different value stops the fill")
	# Eyedropper picks a navigation brush.
	view._eyedropper(Vector2i(6, 6), Vector2i(6, 6))
	assert_eq(view.brush, {"kind": "nav", "bits": 1})
	# Undo restores the data (and the overlay reads the data).
	undo.undo()
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(9, 7)), 0, "undo the fill")
	undo.undo()
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(6, 6)), 0, "undo the pencil")
	undo.redo()
	assert_eq(RPGImageMap.nav_bits(nav, Vector2i(6, 6)), 1, "redo")
	# Save and reload: identical passability.
	assert_eq(view.save(), OK)
	var before := _passage_grid(view.map_node)
	var node := RPGMapFiles.load_map(RPGProjectData.open(ROOT), "garden")
	assert_eq(_passage_grid(node), before, "same passability after reload")
	node.free()
	view.queue_free()
	undo.free()


func _passage_grid(node: RPGMap) -> Array:
	node.size = Vector2i(10, 8)
	var mv := RPGMovement.new(node)
	var out := []
	for y in 8:
		for x in 10:
			out.append(mv.passage(Vector2i(x, y)))
	return out


# --- IM-06 / IM-07: tiles, regions and events on an image map ------------------------------------

func test_tiles_regions_and_events_work_and_never_touch_the_image() -> void:
	var base := _image("base.png", 160, 128)
	var md5 := FileAccess.get_md5(base)
	var p := _props(base)
	p["tileset"] = "town"
	assert_eq(RPGMapFiles.create_image_map(data, "mixed", "Mixed", p, Vector2i(10, 8), RPGImageMap.WALKABLE), OK)
	var view := RPGMapView.new()
	tree.root.add_child(view)
	view.open_map(data, "mixed")
	# A tile, an animated tile, a region and an event.
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key("upper_6")
	view.set_mode("map")
	view.brush = {"kind": "tiles", "size": Vector2i.ONE, "cells": [{"offset": Vector2i.ZERO, "source": a.source, "coords": a.coords}]}
	view.stamp(Vector2i(2, 2))
	var anim: Dictionary = RPGTilesetBuilder.atlas_for_key("anim_0")
	view.brush = {"kind": "tiles", "size": Vector2i.ONE, "cells": [{"offset": Vector2i.ZERO, "source": anim.source, "coords": anim.coords}]}
	view.stamp(Vector2i(5, 5))
	assert_ne(view.tile_layers()[0].get_cell_source_id(Vector2i(5, 5)), -1, "animated tile painted")
	view.set_mode("region")
	view.brush = {"kind": "region", "region": 7}
	view._apply_at(Vector2i(9, 7), false, Vector2.ZERO)
	assert_eq(view.map_node.region_at(Vector2i(9, 7)), 7, "regions reach the last cell")
	var id := view.new_event_at(Vector2i(9, 7))
	assert_eq(view.find_event(id).position, [9, 7], "events on the last cell")
	assert_eq(view.save(), OK)
	assert_true(view.map_node.image_base.visible, "the image stays visible while painting")
	assert_eq(FileAccess.get_md5(base), md5, "painting never rewrites the image")
	view.queue_free()


func test_event_cells_match_the_image_at_runtime() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE, _foreground("fg.png", 160, 128))
	var ev_file := RPGMapFiles.load_events_file(data, "garden")
	var ev := RPGMapView.default_page()
	ev_file.events.append({"id": "sign", "name": "Sign", "position": [7, 5], "pages": [ev]})
	RPGMapFiles.save_events_file(data, "garden", ev_file)
	var env = Env.create(tree, ROOT)
	var r: RPGResult = await env.start_on("garden", Vector2i(3, 4))
	assert_true(r.is_ok(), str(r))
	var map: RPGMap = env.game.map
	assert_true(map.image_base != null and map.image_foreground != null, "both images in the game")
	var sign: Node2D = map.get_event("sign")
	assert_eq(Vector2i(sign.cell), Vector2i(7, 5))
	# Characters stand on the middle of their cell's bottom edge.
	assert_true(Rect2(Vector2(7, 5) * 16, Vector2(16, 16)).grow(0.5).has_point(sign.position) or Rect2(Vector2(7, 5) * 16, Vector2(16, 16)).has_point(sign.position - Vector2(0, 8)), "event on cell (7, 5): %s" % sign.position)
	# The player walks on navigation alone and the foreground covers characters.
	var pl: RPGPlayer = map.player
	assert_true(map.image_foreground.z_index > pl.z_index)
	assert_true(map.navigation != null and not map.navigation.visible, "navigation hidden in the game")
	assert_true(map.movement.can_move(pl, Vector2i(3, 4), Vector2i.RIGHT))
	await env.destroy()


func test_runtime_navigation_survives_transfer_save_and_load() -> void:
	_make_image_map("garden", RPGImageMap.BLOCKED)
	var node := RPGMapFiles.load_map(data, "garden")
	RPGImageMap.fill_nav(node.navigation, Rect2i(2, 2, 4, 1), 15)
	RPGMapFiles.save_scene(node, data.map_scene_path("garden"))
	node.free()
	var env = Env.create(tree, ROOT)
	var r: RPGResult = await env.start_on("garden", Vector2i(2, 2), "right")
	assert_true(r.is_ok(), str(r))
	var map: RPGMap = env.game.map
	assert_true(map.movement.can_move(map.player, Vector2i(2, 2), Vector2i.RIGHT))
	assert_false(map.movement.can_move(map.player, Vector2i(5, 2), Vector2i.RIGHT), "edge of the painted floor")
	assert_false(map.movement.can_move(map.player, Vector2i(2, 2), Vector2i.DOWN), "blocked below")
	# Save on the image map.
	var built: Dictionary = env.rpg.saves.build_save()
	# Leave for a tile map and come back.
	r = await env.game.transfer("town", Vector2i(3, 3), "down", "none")
	assert_true(r.is_ok(), str(r))
	assert_eq(env.game.map.map_id, "town")
	r = await env.game.transfer("garden", Vector2i(4, 2), "down", "none")
	assert_true(r.is_ok(), str(r))
	assert_true(env.game.map.image_base != null, "back on the image map")
	assert_true(env.game.map.movement.can_move(env.game.map.player, Vector2i(4, 2), Vector2i.LEFT))
	# Leave again, then load the save made on the image map.
	r = await env.game.transfer("town", Vector2i(3, 3), "down", "none")
	r = await env.rpg.saves.load_data(built)
	assert_true(r.is_ok(), str(r))
	await env.settle()
	assert_eq(env.game.map.map_id, "garden", "loaded onto the image map")
	assert_eq(env.game.map.player.cell, Vector2i(2, 2))
	assert_true(env.game.map.image_base != null)
	assert_false(env.game.map.movement.can_move(env.game.map.player, Vector2i(2, 2), Vector2i.DOWN), "navigation after load")
	await env.destroy()


# --- IM-08: replacing art --------------------------------------------------------------------------

func test_same_size_replacement_keeps_every_gameplay_file() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE)
	var scene := data.map_scene_path("garden")
	var events: String = data.map_entry("garden").get("events", ROOT + "/maps/garden.events.json")
	var md5s := [FileAccess.get_md5(scene), FileAccess.get_md5(events)]
	var view := RPGMapView.new()
	tree.root.add_child(view)
	view.open_map(data, "garden")
	var old_tex: Texture2D = view.map_node.image_base.texture
	# Repaint the PNG in place (same size), as a paint program would.
	_image("base.png", 160, 128, Color(0.7, 0.2, 0.2))
	view.refresh_images(true)
	var new_tex: Texture2D = view.map_node.image_base.texture
	assert_ne(new_tex, old_tex, "the new picture is shown without a restart")
	assert_true(new_tex.get_image().get_pixel(1, 1).r > 0.6, "red now")
	# A different file of the same size through Map properties.
	var p := data.map_props("garden").duplicate(true)
	p.image_map.base = _image("base_v2.png", 160, 128, Color(0.1, 0.1, 0.8))
	RPGMapFiles.save_props(data, "garden", p)
	view.refresh_images(true)
	assert_true(view.map_node.image_base.texture.get_image().get_pixel(1, 1).b > 0.6)
	assert_eq([FileAccess.get_md5(scene), FileAccess.get_md5(events)], md5s, "scene (navigation, regions, tiles) and events untouched")
	view.queue_free()


func test_smaller_replacement_lists_what_would_be_lost() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE)
	var ev_file := RPGMapFiles.load_events_file(data, "garden")
	ev_file.events.append({"id": "far", "name": "Far", "position": [9, 7], "pages": [RPGMapView.default_page()]})
	ev_file.events.append({"id": "near", "name": "Near", "position": [1, 1], "pages": [RPGMapView.default_page()]})
	RPGMapFiles.save_events_file(data, "garden", ev_file)
	var node := RPGMapFiles.load_map(data, "garden")
	node.regions.set_cell(Vector2i(8, 1), 0, Vector2i(3, 0))
	var out := RPGMapFiles.outside_after_resize(data, "garden", node, Vector2i(6, 8))
	var text := "\n".join(PackedStringArray(out))
	assert_true(text.contains("'Far' (far)"), text)
	assert_false(text.contains("near"), "events inside are not listed")
	assert_true(text.contains("region"), text)
	assert_true(text.contains("navigation"), "walkable cells outside are listed: " + text)
	assert_eq(RPGMapFiles.outside_after_resize(data, "garden", node, Vector2i(12, 9)), [], "growing loses nothing")
	node.free()


func test_main_screen_review_cancel_keeps_and_confirm_resizes() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE)
	var ev_file := RPGMapFiles.load_events_file(data, "garden")
	ev_file.events.append({"id": "far", "name": "Far", "position": [9, 7], "pages": [RPGMapView.default_page()]})
	RPGMapFiles.save_events_file(data, "garden", ev_file)
	var screen := _screen()
	await frames(2)
	screen.open_map("garden")
	var map_json: String = data.map_entry("garden").get("properties", ROOT + "/maps/garden.map.json")
	var before := FileAccess.get_file_as_string(map_json)
	var p := data.map_props("garden").duplicate(true)
	p.image_map.base = _image("small.png", 96, 128)
	p.width = 6
	p.height = 8
	var dlg: ConfirmationDialog = screen.review_image_resize("garden", p, "")
	assert_true(dlg.dialog_text.contains("Far"), dlg.dialog_text)
	assert_eq(dlg.ok_button_text, "Resize and delete these")
	dlg.hide()
	dlg.canceled.emit()
	await frames(1)
	assert_eq(FileAccess.get_file_as_string(map_json), before, "cancel changes nothing")
	assert_eq(screen.data.map_size("garden"), Vector2i(10, 8))
	# Confirm.
	dlg = screen.review_image_resize("garden", p, "")
	dlg.hide()
	dlg.confirmed.emit()
	await frames(1)
	assert_eq(screen.data.map_size("garden"), Vector2i(6, 8))
	assert_eq(screen.view.map_size, Vector2i(6, 8))
	assert_eq(screen.view.find_event("far"), {}, "the listed event was removed")
	# Growing: new cells get the map's navigation for new cells (walkable here).
	var p2 := screen.data.map_props("garden").duplicate(true)
	p2.image_map.base = _image("wide.png", 192, 128)
	p2.width = 12
	p2.height = 8
	dlg = screen.review_image_resize("garden", p2, "")
	assert_eq(dlg.ok_button_text, "Resize map")
	dlg.hide()
	dlg.confirmed.emit()
	await frames(1)
	assert_eq(screen.view.map_size, Vector2i(12, 8))
	assert_eq(RPGImageMap.nav_bits(screen.view.map_node.navigation, Vector2i(11, 7)), 15)
	assert_eq(Vector2i(screen.view.map_node.image_base.texture.get_size()), Vector2i(192, 128))
	screen.queue_free()
	await frames(1)


func test_main_screen_creates_image_maps_and_reloads_changed_images() -> void:
	var screen := _screen()
	await frames(2)
	var p := _props(_image("hall.png", 128, 96), _foreground("hall_fg.png", 128, 96), "blocked")
	p.width = 8
	p.height = 6
	assert_eq(screen.create_map_from_props("hall", p, "Hall"), OK)
	assert_eq(screen.current_map, "hall")
	assert_eq(screen.view.mode, "nav", "opens in Navigation mode")
	assert_true(screen.palette._page_index("N") >= 0, "navigation palette shown")
	assert_true(screen.foreground_option.visible, "foreground control shown")
	# An outside edit of the same size is picked up on focus.
	await tree.create_timer(0.05).timeout
	_image("hall.png", 128, 96, Color(0.9, 0.9, 0.1))
	assert_eq(screen.check_image_changes(), "refreshed")
	assert_true(screen.view.map_node.image_base.texture.get_image().get_pixel(1, 1).g > 0.8)
	# A tile map hides the navigation tools again.
	screen.open_map("town")
	assert_eq(screen.palette._page_index("N"), -1)
	assert_true(screen.mode_buttons.nav.disabled)
	assert_ne(screen.view.mode, "nav")
	screen.queue_free()
	await frames(1)


## The main screen working on this test's project instead of res://rpg.
func _screen() -> RPGMainScreen:
	var screen := RPGMainScreen.new()
	screen.setup(null)
	tree.root.add_child(screen)
	screen.data = data
	screen.registry = RPGCommandRegistry.new()
	screen.current_map = ""
	screen.tree.rebuild(data, "")
	return screen


# --- IM-09: validation and export ------------------------------------------------------------------

func test_validator_reports_missing_and_misaligned_images_and_size_mismatch() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE)
	assert_eq(RPGValidator.image_map_problems(RPGValidator.collect_files(data), data), [], "a good map has no problems")
	# Missing image.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ART.path_join("base.png")))
	var probs := RPGValidator.image_map_problems(RPGValidator.collect_files(data), data)
	assert_eq(probs.size(), 1)
	assert_true(str(probs[0].message).contains("garden") and str(probs[0].message).contains("base.png"), str(probs[0].message))
	assert_true(RPGValidator.blocks_export(probs), "a missing image blocks export")
	# Misaligned image.
	_image("base.png", 170, 128)
	probs = RPGValidator.image_map_problems(RPGValidator.collect_files(data), data)
	assert_true(str(probs[0].message).contains("16 px"), str(probs[0].message))
	# Right shape, wrong size for the map.
	_image("base.png", 192, 128)
	probs = RPGValidator.image_map_problems(RPGValidator.collect_files(data), data)
	assert_true(str(probs[0].message).contains("10×8 cells"), str(probs[0].message))
	# The full pass includes them.
	var all := RPGValidator.full(data, null)
	assert_true(all.any(func(pr): return str(pr.message).contains("10×8 cells")))


func test_images_used_only_by_image_maps_are_kept_in_exports() -> void:
	var assets := TMP + "/assets"
	DirAccess.make_dir_recursive_absolute(assets + "/pack/MapImage")
	var keep := assets + "/pack/MapImage/room.png"
	var drop := assets + "/pack/MapImage/unused.png"
	for f in [keep, drop]:
		var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		img.save_png(f)
	var p := _props(keep)
	assert_eq(RPGMapFiles.create_image_map(data, "room", "Room", p, Vector2i(2, 2), RPGImageMap.WALKABLE), OK)
	data = RPGProjectData.open(ROOT)
	var ex := Deploy.unused_asset_excludes(data, assets)
	assert_false(ex.has(keep), "the base image is used")
	assert_true(ex.has(drop), "an unreferenced image can be left out")
	assert_true(Deploy.where_used(data, keep, assets)[0].contains("room"))


# --- IM-10: existing maps ----------------------------------------------------------------------------

func test_tile_maps_are_unchanged() -> void:
	assert_eq(RPGMapFiles.create_map(data, "plain", "Plain", "town", 6, 5), OK)
	var p := data.map_props("plain")
	assert_false(p.has("image_map"), "no new keys on tile maps")
	var node := RPGMapFiles.load_map(data, "plain")
	assert_true(node.navigation == null)
	assert_true(node.image_base == null)
	assert_false(node.is_image_map())
	node.size = Vector2i(6, 5)
	var mv := RPGMovement.new(node)
	assert_eq(mv.passage(Vector2i(1, 1)), 15, "a map with no tiles at all is open, as before")
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key("terrain_1")
	node.tile_layers[0].set_cell(Vector2i(0, 0), a.source, a.coords)
	mv.invalidate()
	assert_eq(mv.passage(Vector2i(1, 1)), 0, "once something is painted, empty cells block, as before")
	node.free()
	# The sample project's tile maps have no image data; its image-backed garden validates.
	var sample := RPGProjectData.open("res://rpg")
	assert_eq(RPGValidator.image_map_problems(RPGValidator.collect_files(sample), sample), [])
	for id in ["town", "house_inside", "field"]:
		assert_false(RPGImageMap.is_image_map(sample.map_props(id)), id)
		var n := RPGMapFiles.load_map(sample, id)
		assert_true(n.navigation == null and n.image_base == null, id)
		n.free()
	assert_true(RPGImageMap.is_image_map(sample.map_props("garden")), "the sample garden")


func test_removing_the_foreground_changes_nothing_else() -> void:
	_make_image_map("garden", RPGImageMap.WALKABLE, _foreground("fg.png", 160, 128))
	var scene := data.map_scene_path("garden")
	var md5 := FileAccess.get_md5(scene)
	var p := data.map_props("garden").duplicate(true)
	p.image_map.foreground = null
	RPGMapFiles.save_props(data, "garden", p)
	var after := data.map_props("garden")
	assert_true(RPGImageMap.is_image_map(after), "still an image-backed map")
	assert_eq(RPGImageMap.foreground_path(after), "")
	assert_eq(RPGImageMap.base_path(after), ART.path_join("base.png"))
	assert_eq(FileAccess.get_md5(scene), md5)
	var node := RPGMapFiles.load_map(data, "garden")
	assert_eq(node.image_foreground, null)
	assert_true(node.image_base != null)
	node.free()


# --- exports ----------------------------------------------------------------------------------------

## Exports leave out addons/rpg/editor/ (export_presets.cfg), so a script that ships in the game
## must never name a class defined there, or the game fails to compile it. (RPGImageMap once
## named RPGMapFiles.)
func test_shipped_scripts_name_no_editor_only_class() -> void:
	var editor_classes := {}
	for f in _gd_files("res://addons/rpg/editor"):
		for line in FileAccess.get_file_as_string(f).split("\n"):
			if line.begins_with("class_name "):
				editor_classes[line.substr(11).strip_edges().split(" ")[0]] = f
	assert_true(editor_classes.has("RPGMapFiles"), "found the editor classes")
	var bad := []
	var word := RegEx.create_from_string("\b(" + "|".join(PackedStringArray(editor_classes.keys())) + ")\b")
	for root in ["res://addons/rpg/core", "res://addons/rpg/runtime", "res://addons/rpg/import", "res://addons/rpg/extensions"]:
		for f in _gd_files(root):
			var n := 0
			for line in FileAccess.get_file_as_string(f).split("\n"):
				n += 1
				var code := line
				var hash_at := code.find("#")
				if hash_at >= 0:
					code = code.substr(0, hash_at)
				var m := word.search(code)
				if m != null:
					bad.append("%s:%d names %s" % [f, n, m.get_string(1)])
	assert_eq(bad, [], "shipped scripts use editor-only classes")


func _gd_files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out
