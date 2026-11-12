extends "res://tests/rpg_test_case.gd"
## Image-backed maps (docs/specs/image-backed-maps.md): size validation, creation, editor and
## runtime alignment, foreground draw order, passability painting with undo and redo, runtime
## passability without visible tiles, save and reload, replacing images of the same and of another
## size (review, cancel, backup), validator errors, export keeping the images, and legacy maps
## behaving exactly as before.

const Env := preload("res://tests/rpg_test_env.gd")
const ROOT := "user://rpg_image_map_test"
const SLOT := 15

var data: RPGProjectData
var view: RPGMapView
var undo: UndoRedo
var env


func before_each() -> void:
	_make_project(ROOT, "rm2k", 16)
	data = RPGProjectData.open(ROOT)
	view = null
	undo = null
	env = null


func after_each() -> void:
	if view != null:
		view.queue_free()
	if undo != null:
		undo.free()
	if env != null:
		if FileAccess.file_exists(env.rpg.saves.slot_path(SLOT)):
			DirAccess.remove_absolute(env.rpg.saves.slot_path(SLOT))
		await env.destroy()
	await frames(1)
	_wipe(ROOT)


# --- helpers ------------------------------------------------------------------------------------

## A small runtime-capable project: two tile maps (no scenes) plus whatever a test adds.
func _make_project(root: String, profile: String, tile: int) -> void:
	_wipe(root)
	DirAccess.make_dir_recursive_absolute(root + "/database")
	DirAccess.make_dir_recursive_absolute(root + "/maps")
	RPGJson.save_file(root + "/project.json", {"schema_version": 1, "project_id": "image_maps", "name": "Image maps", "extensions": [], "rules": "classic", "scenes": {}})
	RPGJson.save_file(root + "/profile.json", {"schema_version": 1, "profile": profile, "tile_size": tile})
	RPGJson.save_file(root + "/state.json", {"schema_version": 1, "switches": [], "variables": []})
	RPGJson.save_file(root + "/common_events.json", {"schema_version": 1, "common_events": []})
	RPGJson.save_file(root + "/database/tilesets.json", {"schema_version": 1, "records": [{"id": "town", "name": "Town", "profile": "rm2k", "sheet": "res://assets/starter/ChipSet/town.png"}]})
	RPGJson.save_file(root + "/database/system.json", {"schema_version": 1, "system": {}})
	RPGJson.save_file(root + "/map_index.json", {"schema_version": 1, "maps": [], "favourites": []})


func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(path.path_join(sub))
		d.remove(sub)


## Writes a PNG of `size` filled with `col` under <root>/assets/maps/ and returns its path.
func _png(name: String, size: Vector2i, col := Color(0.2, 0.5, 0.3), root := ROOT) -> String:
	var path := root + "/assets/maps/" + name + ".png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(col)
	img.save_png(path)
	return path


## A transparent foreground with one opaque block ("an arch") over cells (1, 0)..(2, 0).
func _foreground(name: String, size: Vector2i, tile := 16) -> String:
	var path := ROOT + "/assets/maps/" + name + ".png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(tile, 0, tile * 2, tile), Color(0.6, 0.3, 0.1, 1))
	img.save_png(path)
	return path


## Creates image map `id` from a base of `cells` (16 px tiles, no tileset unless given).
func _image_map(id: String, cells: Vector2i, walkable := true, fg := false, tileset := "") -> Dictionary:
	var base := _png(id, cells * 16)
	var fgp := _foreground(id + "_fg", cells * 16) if fg else ""
	var r := RPGMapFiles.create_image_map(data, id, id.capitalize(), tileset, base, fgp, walkable)
	assert_eq(r.error, OK, str(r.message))
	return r


func _open_view(id: String) -> void:
	if view == null:
		view = RPGMapView.new()
		undo = UndoRedo.new()
		view.undo = RPGUndo.new(undo)
		tree.root.add_child(view)
	view.open_map(data, id)


func _add_event(id: String, ev_id: String, pos: Vector2i, priority := "same") -> void:
	var f := RPGMapFiles.load_events_file(data, id)
	f.events.append({"id": ev_id, "name": ev_id, "position": [pos.x, pos.y], "notes": "", "pages": [{
		"conditions": [], "graphic": null, "movement": {"type": "fixed"}, "options": {},
		"priority": priority, "trigger": "action_button", "commands": []}]})
	RPGMapFiles.save_events_file(data, id, f)


func _md5(path: String) -> String:
	return FileAccess.get_md5(path)


func _screen() -> RPGMainScreen:
	var screen := RPGMainScreen.new()
	screen.project_root = ROOT
	screen.setup(null)
	tree.root.add_child(screen)
	await frames(2)
	return screen


## The passage rule as it was before this feature (top non-empty, non-star layer decides; all
## empty = blocked unless the map has no tiles at all), for the legacy regression check.
static func _legacy_passage(map: RPGMap, cell: Vector2i) -> int:
	var layers: Array = map.tile_layers
	if layers.is_empty():
		return 15
	for i in range(layers.size() - 1, -1, -1):
		var layer: TileMapLayer = layers[i]
		var td := layer.get_cell_tile_data(cell)
		if td == null:
			continue
		var flags := int(td.get_custom_data("flags")) if td.has_custom_data("flags") else 0
		if flags & RPGMovement.FLAG_STAR:
			continue
		var p := int(td.get_custom_data("passage")) if td.has_custom_data("passage") else 15
		if flags & RPGMovement.FLAG_EDGE:
			return -1   # depends on neighbours; compared through RPGMovement itself
		return p
	for l in layers:
		if l.get_used_cells().size() > 0:
			return 0
	return 15


# --- IM-02: size validation -------------------------------------------------------------------------

func test_size_check_accepts_aligned_images() -> void:
	var r := RPGImageMap.check_size(Vector2i(640, 480), 16)
	assert_true(r.ok, str(r.error))
	assert_eq(r.cells, Vector2i(40, 30))
	assert_eq(r.warning, "")
	var path := _png("ok", Vector2i(64, 48))
	var c := RPGImageMap.check_image(path, 16)
	assert_true(c.ok, str(c.error))
	assert_eq(c.size, Vector2i(64, 48))
	assert_eq(c.cells, Vector2i(4, 3))
	assert_eq(RPGImageMap.check_size(Vector2i(96, 96), 48).cells, Vector2i(2, 2), "48 px tiles")


func test_size_check_rejects_indivisible_with_nearest_sizes() -> void:
	var r := RPGImageMap.check_size(Vector2i(650, 470), 16)
	assert_false(r.ok)
	for part in ["650×470", "16 px", "640 px below and 656 px above", "464 px below and 480 px above", "never rescales"]:
		assert_true(str(r.error).contains(part), "message has '%s': %s" % [part, r.error])
	assert_eq(r.nearest.width, [640, 656])
	assert_eq(r.nearest.height, [464, 480])
	# Only the bad side is reported.
	var r2 := RPGImageMap.check_size(Vector2i(640, 470), 16)
	assert_false(str(r2.error).contains("width"), r2.error)
	assert_true(str(r2.error).contains("height 470"), r2.error)


func test_size_check_rejects_unreadable_and_missing_images() -> void:
	var bad := ROOT + "/assets/maps/broken.png"
	DirAccess.make_dir_recursive_absolute(bad.get_base_dir())
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("this is not a png")
	f.close()
	var r := RPGImageMap.check_image(bad, 16)
	assert_false(r.ok)
	assert_true(str(r.error).contains("could not be read") and str(r.error).contains(bad), r.error)
	var m := RPGImageMap.check_image(ROOT + "/assets/maps/nowhere.png", 16)
	assert_false(m.ok)
	assert_true(str(m.error).contains("does not exist"), m.error)
	assert_false(RPGImageMap.check_image("", 16).ok, "no image picked")


func test_size_check_rejects_zero_sized() -> void:
	for s in [Vector2i(0, 0), Vector2i(0, 32), Vector2i(32, 0)]:
		var r := RPGImageMap.check_size(s, 16)
		assert_false(r.ok)
		assert_true(str(r.error).contains("empty"), r.error)


func test_size_check_rejects_over_limit_and_warns_near_it() -> void:
	var big := RPGImageMap.check_size(Vector2i(RPGImageMap.MAX_SIDE + 16, 32), 16)
	assert_false(big.ok)
	assert_true(str(big.error).contains(str(RPGImageMap.MAX_SIDE)), "the message shows the limit: " + big.error)
	# A real over-limit file is rejected before creation, and nothing is written.
	var path := _png("huge", Vector2i(RPGImageMap.MAX_SIDE + 16, 16))
	var r := RPGMapFiles.create_image_map(data, "huge", "Huge", "", path)
	assert_eq(r.error, ERR_INVALID_DATA)
	assert_true(str(r.message).contains(str(RPGImageMap.MAX_SIDE)), r.message)
	assert_false(data.maps.has("huge"))
	assert_false(FileAccess.file_exists(ROOT + "/maps/huge.map.json"))
	var warn := RPGImageMap.check_size(Vector2i(RPGImageMap.WARN_SIDE + 16, 32), 16)
	assert_true(warn.ok)
	assert_true(str(warn.warning).contains("MiB"), "texture memory is explained: " + warn.warning)
	assert_eq(RPGImageMap.texture_mib(Vector2i(4096, 4096)), 64)
	assert_false(RPGImageMap.TEST_SIZES.is_empty(), "representative sizes are written down")


func test_map_tile_size_comes_from_the_tileset() -> void:
	assert_eq(RPGImageMap.tile_size_for_tileset(data, "town"), 16, "rm2k tileset")
	assert_eq(RPGImageMap.tile_size_for_tileset(data, ""), 16, "no tileset: project tile size")
	_make_project(ROOT, "mv", 48)
	data = RPGProjectData.open(ROOT)
	assert_eq(RPGImageMap.tile_size_for_tileset(data, "town"), 16, "a 16 px tileset in a 48 px project")
	assert_eq(RPGImageMap.tile_size_for_tileset(data, ""), 48)
	assert_true(RPGImageMap.tile_size_source(data, "").contains("project"))


# --- IM-01: creation ---------------------------------------------------------------------------------

func test_create_image_map_writes_standard_files_and_sizes_the_map() -> void:
	var r := _image_map("harbour", Vector2i(5, 4), true, true)
	assert_eq(r.cells, Vector2i(5, 4))
	for ext in [".tscn", ".map.json", ".events.json"]:
		assert_true(FileAccess.file_exists(ROOT + "/maps/harbour" + ext), ext)
	# Closing and reopening the project keeps the assignment and the size.
	var again := RPGProjectData.open(ROOT)
	var p: Dictionary = again.map_props("harbour")
	assert_true(RPGImageMap.is_image_map(p))
	assert_eq(RPGImageMap.base_path(p), ROOT + "/assets/maps/harbour.png")
	assert_eq(RPGImageMap.foreground_path(p), ROOT + "/assets/maps/harbour_fg.png")
	assert_eq(int(RPGImageMap.block(p).version), 1)
	assert_eq(Vector2i(int(p.width), int(p.height)), Vector2i(5, 4))
	assert_eq(str(p.scroll), "none")
	var node := RPGMapFiles.load_map(again, "harbour")
	assert_true(node.navigation != null, "the scene has a Navigation layer")
	assert_false(node.navigation in node.tile_layers, "and it is not a visible tile layer")
	assert_false(node.navigation.visible)
	assert_eq(node.navigation.get_used_cells().size(), 20, "all walkable: every cell has a mask")
	assert_eq(node.navigation_mask(Vector2i(4, 3)), 15)
	node.free()


func test_create_all_blocked_and_bad_images_write_nothing() -> void:
	_image_map("cellar", Vector2i(3, 3), false)
	var node := RPGMapFiles.load_map(data, "cellar")
	assert_eq(node.navigation.get_used_cells().size(), 0, "all blocked: no mask tiles")
	var mv := RPGMovement.new(node)
	node.size = Vector2i(3, 3)
	assert_eq(mv.passage(Vector2i(1, 1)), 0)
	node.free()
	var odd := _png("odd", Vector2i(50, 48))
	var r := RPGMapFiles.create_image_map(data, "odd", "Odd", "", odd)
	assert_eq(r.error, ERR_INVALID_DATA)
	assert_false(data.maps.has("odd"), "no partial map")
	assert_false(FileAccess.file_exists(ROOT + "/maps/odd.tscn"))
	var base := _png("mm", Vector2i(48, 48))
	var fg := _png("mm_fg", Vector2i(32, 48))
	var r2 := RPGMapFiles.create_image_map(data, "mm", "Mm", "", base, fg)
	assert_eq(r2.error, ERR_INVALID_DATA)
	assert_true(str(r2.message).contains("32×48") and str(r2.message).contains("48×48"), "both sizes shown: " + r2.message)
	assert_false(data.maps.has("mm"))


func test_new_image_map_dialog_validates_before_writing() -> void:
	var made := []
	var d := RPGImageMapDialog.open_for(tree.root, data, func(v): made.append(v))
	await frames(1)
	var odd := _png("dlg_odd", Vector2i(50, 48))
	d.set_values({"id": "dlg", "base": odd})
	assert_true(d.get_ok_button().disabled, "Create is off for a bad image")
	assert_true(d._error.text.contains("50×48"), d._error.text)
	assert_true(d._info.text.contains("Map tile size: 16 px"), d._info.text)
	var good := _png("dlg_good", Vector2i(64, 32))
	d.set_values({"base": good, "walkable": true})
	assert_false(d.get_ok_button().disabled, d._error.text)
	assert_true(d._info.text.contains("4×2 cells"), d._info.text)
	assert_false(FileAccess.file_exists(ROOT + "/maps/dlg.map.json"), "nothing written before Create")
	d._on_ok()
	assert_eq(made.size(), 1)
	assert_eq(made[0].id, "dlg")
	assert_eq(made[0].base, good)
	assert_true(made[0].walkable)
	assert_eq(made[0].cells, Vector2i(4, 2))
	await frames(1)


func test_main_screen_creates_and_opens_in_passability_mode() -> void:
	var screen: RPGMainScreen = await _screen()
	var base := _png("lobby", Vector2i(64, 48))
	var r := screen.create_image_map({"id": "lobby", "name": "Lobby", "tileset": "", "base": base, "walkable": false})
	assert_eq(r.error, OK, str(r.message))
	assert_eq(screen.current_map, "lobby")
	assert_eq(screen.view.mode, "passability", "opens in Passability mode")
	assert_false(screen.mode_buttons.passability.disabled)
	assert_eq(screen.view.map_size, Vector2i(4, 3))
	# The New image-backed map entry sits beside New map in the map tree's menu.
	var menu := screen.tree.open_menu("")
	var labels := []
	for i in menu.item_count:
		labels.append(menu.get_item_text(i))
	assert_true(labels.has("New map...") and labels.has("New image-backed map..."), str(labels))
	menu.queue_free()
	var map_menu := screen.tree.open_menu("lobby")
	assert_true(map_menu.is_item_disabled(map_menu.get_item_index(7)), "Shift contents is off on image maps")
	map_menu.queue_free()
	screen.queue_free()
	await frames(1)


# --- IM-03 / IM-04: rendering ---------------------------------------------------------------------------

func test_base_and_foreground_nodes_are_aligned_and_never_saved() -> void:
	_image_map("arch", Vector2i(4, 3), true, true)
	_open_view("arch")
	var n := view.map_node
	assert_true(n.image_base != null and n.image_foreground != null)
	assert_eq(n.image_base.position, Vector2.ZERO, "top-left at map pixel (0, 0)")
	assert_eq(n.image_base.scale, Vector2.ONE, "scale 1")
	assert_false(n.image_base.centered)
	assert_eq(n.image_base.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(n.image_foreground.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(n.image_base.z_index, -1, "base under the tile layers")
	assert_eq(n.image_foreground.z_index, 5, "foreground above characters and star tiles")
	assert_eq(Vector2i(n.image_base.texture.get_size()), view.map_size * view.tile_size, "one image pixel per map pixel")
	view.save()
	var text := FileAccess.get_file_as_string(ROOT + "/maps/arch.tscn")
	assert_false(text.contains("ImageBase") or text.contains("ImageForeground"), "image nodes are not packed")
	assert_true(text.contains("Navigation"), "the mask is")


func test_editor_and_runtime_alignment() -> void:
	_image_map("plaza", Vector2i(6, 5), true, true)
	_add_event("plaza", "statue", Vector2i(3, 2))
	_open_view("plaza")
	var ed: RPGMap = view.map_node
	env = Env.create(tree, ROOT)
	var res: RPGResult = await env.start_on("plaza", Vector2i(1, 1))
	assert_true(res.is_ok(), str(res))
	var rt: RPGMap = env.game.map
	assert_true(rt.image_base != null, "the game builds the base image")
	for pair in [[ed.image_base, rt.image_base], [ed.image_foreground, rt.image_foreground]]:
		assert_eq(pair[0].position, pair[1].position)
		assert_eq(pair[0].scale, pair[1].scale)
		assert_eq(pair[0].centered, pair[1].centered)
		assert_eq(pair[0].z_index, pair[1].z_index)
		assert_eq(pair[0].texture_filter, pair[1].texture_filter)
		assert_eq(pair[0].texture.get_size(), pair[1].texture.get_size())
	assert_eq(rt.tile_size, view.tile_size)
	# The event's cell lines up with the image: same top-left pixel in the editor and the game.
	var ev: Node2D = rt.get_event("statue")
	var ts := float(rt.tile_size)
	assert_eq(ev.position - Vector2(ts / 2.0, ts), Vector2(3, 2) * ts)
	assert_eq(view.to_cell(view.world.position + Vector2(3.5, 2.5) * ts * view.zoom), Vector2i(3, 2))
	# Draw order at runtime: base < tiles < characters < foreground < airship.
	assert_true(rt.image_base.z_index < rt.tile_layers[0].z_index)
	assert_true(rt.image_foreground.z_index > env.game.player.z_index)
	assert_true(rt.image_foreground.z_index > 4, "above events with priority above")
	assert_eq(rt.image_foreground.texture.get_image().get_pixel(1, 1).a, 0.0, "transparent pixels reveal what is under them")
	assert_eq(rt.image_foreground.texture.get_image().get_pixel(20, 4).a, 1.0, "painted pixels cover the character")


func test_alignment_with_a_16px_tileset_in_a_48px_project() -> void:
	_make_project(ROOT, "mv", 48)
	data = RPGProjectData.open(ROOT)
	var base := _png("big", Vector2i(80, 48))
	var r := RPGMapFiles.create_image_map(data, "big", "Big", "town", base, "", true)
	assert_eq(r.error, OK, str(r.message))
	assert_eq(r.cells, Vector2i(5, 3), "checked against the map tile size (16), not the project's 48")
	_open_view("big")
	assert_eq(view.tile_size, 16)
	assert_eq(view.game_zoom(), 3.0, "drawn 3x like the game")
	env = Env.create(tree, ROOT)
	var res: RPGResult = await env.start_on("big", Vector2i(0, 0))
	assert_true(res.is_ok(), str(res))
	var rt: RPGMap = env.game.map
	assert_eq(rt.tile_size, 16)
	assert_eq(rt.display_scale(), 3)
	assert_eq(rt.image_base.position, view.map_node.image_base.position)
	assert_eq(Vector2i(rt.image_base.texture.get_size()), Vector2i(5, 3) * rt.tile_size)


func test_airship_flies_above_the_foreground() -> void:
	_image_map("roofs", Vector2i(4, 4), true, true)
	env = Env.create(tree, ROOT)
	var res: RPGResult = await env.start_on("roofs", Vector2i(1, 1))
	assert_true(res.is_ok(), str(res))
	var p: RPGPlayer = env.game.player
	p._board("airship")
	assert_eq(p.z_index, 6)
	assert_true(p.z_index > env.game.map.image_foreground.z_index)
	p._leave_vehicle()
	assert_eq(p.z_index, 2)


func test_foreground_show_dim_hide_is_editor_only() -> void:
	_image_map("trees", Vector2i(4, 3), true, true)
	var screen: RPGMainScreen = await _screen()
	screen.open_map("trees")
	assert_true(screen.foreground_option.visible, "control shown on a map with a foreground")
	assert_true(screen.foreground_option.tooltip_text != "")
	assert_eq(screen.foreground_option.focus_mode, Control.FOCUS_ALL, "keyboard reachable")
	screen.set_foreground_view("dim")
	assert_true(absf(screen.view.map_node.image_foreground.modulate.a - RPGMapView.FOREGROUND_DIM_ALPHA) < 0.01)
	assert_eq(screen.foreground_option.selected, 1)
	screen.set_foreground_view("hide")
	assert_false(screen.view.map_node.image_foreground.visible)
	screen.set_foreground_view("show")
	assert_true(screen.view.map_node.image_foreground.visible)
	# Event markers stay above the foreground in Event mode.
	assert_true(screen.view.overlay.z_index > screen.view.map_node.image_foreground.z_index)
	screen.set_foreground_view("hide")
	var props: Dictionary = RPGMapFiles.load_events_file(data, "trees")
	assert_eq(props.events.size(), 0, "hiding changes no data")
	screen.queue_free()
	await frames(1)


# --- IM-05: passability ---------------------------------------------------------------------------------

func test_passability_painting_with_undo_and_redo() -> void:
	_image_map("room", Vector2i(6, 5), false)
	_open_view("room")
	view.set_mode("passability")
	view.brush = {"kind": "passage", "passage": 15}
	view.tool = "rect"
	view._begin_stroke()
	view._apply_shape(Vector2i(1, 1), Vector2i(4, 3), false)
	view._end_stroke("Rectangle")
	var n := view.map_node
	assert_eq(n.navigation_mask(Vector2i(2, 2)), 15)
	assert_eq(n.navigation_mask(Vector2i(0, 0)), 0)
	assert_true(view.dirty)
	# Pencil: a one-way cell (left and right only).
	view.tool = "pencil"
	view.brush = {"kind": "passage", "passage": 2 | 4}
	view._begin_stroke()
	view._apply_at(Vector2i(2, 2), false, Vector2.ZERO)
	view._end_stroke("Paint")
	assert_eq(n.navigation_mask(Vector2i(2, 2)), 6)
	undo.undo()
	assert_eq(n.navigation_mask(Vector2i(2, 2)), 15, "undo restores the cell")
	undo.undo()
	assert_eq(n.navigation_mask(Vector2i(2, 2)), 0, "and the rectangle")
	var mv := RPGMovement.new(n)
	n.size = view.map_size
	assert_eq(mv.passage(Vector2i(2, 2)), 0, "the overlay reads the same data (blocked again)")
	undo.redo()
	undo.redo()
	assert_eq(n.navigation_mask(Vector2i(2, 2)), 6, "redo restores both strokes")
	# Fill: the blocked border area becomes walkable in one step.
	view.tool = "fill"
	view.brush = {"kind": "passage", "passage": 15}
	view._begin_stroke()
	view._fill(Vector2i(0, 0))
	view._end_stroke("Fill")
	assert_eq(n.navigation_mask(Vector2i(5, 4)), 15)
	assert_eq(n.navigation_mask(Vector2i(2, 2)), 6, "fill stops at other masks")
	# Eyedropper picks a cell's mask as the brush.
	view._eyedropper(Vector2i(2, 2), Vector2i(2, 2))
	assert_eq(view.brush, {"kind": "passage", "passage": 6})
	# Painting never touches the visible tile layers.
	for l in view.tile_layers():
		assert_eq(l.get_used_cells().size(), 0)


func test_passability_mode_only_on_image_maps() -> void:
	assert_eq(RPGMapFiles.create_map(data, "tiles", "Tiles", "town", 5, 5), OK)
	_image_map("pic", Vector2i(3, 3))
	var screen: RPGMainScreen = await _screen()
	screen.open_map("tiles")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F4
	ev.pressed = true
	screen._shortcut_input(ev)
	assert_eq(screen.view.mode, "map", "F4 does nothing on a tile map")
	assert_true(screen.mode_buttons.passability.disabled)
	assert_false(screen.foreground_option.visible)
	screen.open_map("pic")
	screen._shortcut_input(ev)
	assert_eq(screen.view.mode, "passability", "F4 opens Passability mode")
	assert_eq(screen.view.brush.kind, "passage")
	screen.menu_action(RPGMainScreen.M_MODE + 1)
	assert_eq(screen.view.mode, "event")
	screen.menu_action(RPGMainScreen.M_MODE + 3)
	assert_eq(screen.view.mode, "passability")
	screen.open_map("tiles")
	assert_eq(screen.view.mode, "map", "leaving for a tile map leaves Passability mode")
	screen.queue_free()
	await frames(1)


func test_runtime_uses_the_mask_without_visible_tiles() -> void:
	_image_map("hall", Vector2i(5, 3), false)
	var node := RPGMapFiles.load_map(data, "hall")
	for x in 4:
		node.set_navigation_mask(Vector2i(x, 1), 15)
	node.set_navigation_mask(Vector2i(2, 1), 2 | 4)   # a cell crossed only left-right
	node.set_navigation_mask(Vector2i(2, 0), 15)
	RPGMapFiles.save_scene(node, data.map_scene_path("hall"))
	node.free()
	_add_event("hall", "guard", Vector2i(3, 1))
	env = Env.create(tree, ROOT)
	var res: RPGResult = await env.start_on("hall", Vector2i(0, 1))
	assert_true(res.is_ok(), str(res))
	var mv: RPGMovement = env.game.map.movement
	var p: RPGPlayer = env.game.player
	assert_true(mv.can_move(p, Vector2i(0, 1), Vector2i.RIGHT), "walkable to walkable with no tile anywhere")
	assert_false(mv.can_move(p, Vector2i(0, 1), Vector2i.UP), "a cell without mask is blocked")
	assert_false(mv.can_move(p, Vector2i(2, 0), Vector2i.DOWN), "the one-way cell refuses entry from above")
	assert_true(mv.can_move(p, Vector2i(1, 1), Vector2i.RIGHT))
	assert_eq(mv.check_move(p, Vector2i(2, 1), Vector2i.RIGHT), "occupied", "events still block")
	assert_false(mv.can_move(p, Vector2i(3, 1), Vector2i.RIGHT), "(4, 1) has no mask")


func test_save_reload_and_saved_game_keep_passability() -> void:
	_image_map("vault", Vector2i(5, 4), false, true)
	_open_view("vault")
	view.set_mode("passability")
	view.brush = {"kind": "passage", "passage": 15}
	view.tool = "rect"
	view._begin_stroke()
	view._apply_shape(Vector2i(0, 1), Vector2i(3, 2), false)
	view._end_stroke("Rectangle")
	view.brush = {"kind": "passage", "passage": 1 | 8}
	view.tool = "pencil"
	view._begin_stroke()
	view._apply_at(Vector2i(1, 1), false, Vector2.ZERO)
	view._end_stroke("Paint")
	var before := {}
	var mv := RPGMovement.new(view.map_node)
	view.map_node.size = view.map_size
	for y in 4:
		for x in 5:
			before[Vector2i(x, y)] = mv.passage(Vector2i(x, y))
	assert_eq(view.save(), OK)
	view.open_map(data, "vault")
	var mv2 := RPGMovement.new(view.map_node)
	view.map_node.size = view.map_size
	for c in before:
		assert_eq(mv2.passage(c), before[c], "editor reload %s" % c)
	env = Env.create(tree, ROOT)
	var res: RPGResult = await env.start_on("vault", Vector2i(0, 1))
	assert_true(res.is_ok(), str(res))
	for c in before:
		assert_eq(env.game.map.movement.passage(c), before[c], "runtime %s" % c)
	# A saved game on the image map loads back onto it, with images and mask; it holds no pixels.
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	var text := FileAccess.get_file_as_string(env.rpg.saves.slot_path(SLOT))
	for bad in ["PNG", "vault.png", "\"image_map\":", "ImageBase"]:
		var at := text.find(bad)
		assert_eq(at, -1, "saves store no images (%s): %s" % [bad, text.substr(maxi(0, at - 80), 160)])
	_make_tile_map_for_runtime()
	await env.game.transfer("plain", Vector2i(0, 0), "down", "none")
	var lr: RPGResult = await env.rpg.saves.load_slot(SLOT)
	assert_true(lr.is_ok(), str(lr))
	assert_eq(env.game.map.map_id, "vault")
	assert_true(env.game.map.image_base != null and env.game.map.image_foreground != null)
	assert_eq(env.game.map.movement.passage(Vector2i(1, 1)), 9)


func _make_tile_map_for_runtime() -> void:
	if not env.rpg.data.maps.has("plain"):
		assert_eq(RPGMapFiles.create_map(env.rpg.data, "plain", "Plain", "", 4, 4), OK)


# --- IM-06 / IM-07: tiles, regions, events ------------------------------------------------------------

func test_tiles_regions_and_mask_coexist_on_an_image_map() -> void:
	_image_map("mixed", Vector2i(6, 6), true, false, "town")
	_open_view("mixed")
	var base_md5 := _md5(ROOT + "/assets/maps/mixed.png")
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key("lower_3")
	view.set_mode("map")
	view.brush = {"kind": "tiles", "size": Vector2i.ONE, "cells": [{"offset": Vector2i.ZERO, "source": a.source, "coords": a.coords}]}
	view._begin_stroke()
	view.stamp(Vector2i(1, 1))
	var anim: Dictionary = RPGTilesetBuilder.atlas_for_key("anim_0")
	view.brush = {"kind": "tiles", "size": Vector2i.ONE, "cells": [{"offset": Vector2i.ZERO, "source": anim.source, "coords": anim.coords}]}
	view.stamp(Vector2i(2, 1))
	view._end_stroke("Paint")
	view.set_mode("region")
	view.brush = {"kind": "region", "region": 7}
	view._begin_stroke()
	view._apply_at(Vector2i(4, 4), false, Vector2.ZERO)
	view._end_stroke("Paint")
	assert_eq(view.map_node.region_at(Vector2i(4, 4)), 7)
	assert_true(view.map_node.image_base.visible, "the image stays visible while painting")
	assert_eq(view.save(), OK)
	assert_eq(_md5(ROOT + "/assets/maps/mixed.png"), base_md5, "painting never changes the image")
	var node := RPGMapFiles.load_map(data, "mixed")
	assert_ne(node.tile_layers[0].get_cell_source_id(Vector2i(1, 1)), -1, "tile saved")
	assert_ne(node.tile_layers[0].get_cell_source_id(Vector2i(2, 1)), -1, "animated tile saved")
	assert_eq(node.region_at(Vector2i(4, 4)), 7)
	assert_eq(node.navigation_mask(Vector2i(4, 4)), 15, "mask kept")
	var mv := RPGMovement.new(node)
	node.size = Vector2i(6, 6)
	assert_eq(mv.passage(Vector2i(1, 1)), 15, "the mask decides passage, not the tile")
	node.free()


# --- IM-08: replacing the images ------------------------------------------------------------------------

func test_same_size_replacement_keeps_events_and_mask() -> void:
	_image_map("shop", Vector2i(4, 3), false, true)
	_add_event("shop", "keeper", Vector2i(2, 1))
	var screen: RPGMainScreen = await _screen()
	screen.open_map("shop")
	screen.view.map_node.set_navigation_mask(Vector2i(1, 1), 15)
	screen.view.dirty = true
	screen.save_current()
	var ev_path := ROOT + "/maps/shop.events.json"
	var scene_path := ROOT + "/maps/shop.tscn"
	var ev_md5 := _md5(ev_path)
	var scene_md5 := _md5(scene_path)
	var new_base := _png("shop_v2", Vector2i(64, 48), Color(0.9, 0.1, 0.1))
	var props: Dictionary = data.map_props("shop").duplicate(true)
	props.image_map.base = new_base
	screen._apply_props("shop", props, "")
	assert_eq(screen.review_dialog, null, "no review for the same size")
	assert_eq(RPGImageMap.base_path(screen.data.map_props("shop")), new_base)
	assert_eq(_md5(ev_path), ev_md5, "events file unchanged")
	assert_eq(_md5(scene_path), scene_md5, "scene (tiles, regions, mask) unchanged")
	var px: Color = screen.view.map_node.image_base.texture.get_image().get_pixel(0, 0)
	assert_true(px.r > 0.8, "the editor shows the new image without a restart")
	# Removing the foreground keeps the map type and everything else.
	props = screen.data.map_props("shop").duplicate(true)
	props.image_map.foreground = null
	screen._apply_props("shop", props, "")
	assert_true(RPGImageMap.is_image_map(screen.data.map_props("shop")))
	assert_eq(screen.view.map_node.image_foreground, null)
	assert_false(screen.foreground_option.visible)
	assert_eq(_md5(ev_path), ev_md5)
	assert_eq(_md5(scene_path), scene_md5)
	screen.queue_free()
	await frames(1)


func test_smaller_replacement_is_reviewed_and_cancel_changes_nothing() -> void:
	_image_map("yard", Vector2i(5, 4), true)
	_add_event("yard", "far", Vector2i(4, 0))
	var screen: RPGMainScreen = await _screen()
	screen.open_map("yard")
	var files := [ROOT + "/maps/yard.events.json", ROOT + "/maps/yard.tscn", ROOT + "/maps/yard.map.json"]
	var sums := files.map(func(f): return _md5(f))
	var smaller := _png("yard_small", Vector2i(48, 48))
	var props: Dictionary = data.map_props("yard").duplicate(true)
	props.image_map.base = smaller
	props.width = 3
	props.height = 3
	screen._apply_props("yard", props, "")
	var dlg := screen.review_dialog
	assert_true(dlg is ConfirmationDialog, "a blocking review opens")
	for part in ["3×3", "far (far)", "passability cell(s)", ".backup"]:
		assert_true(dlg.dialog_text.contains(part), "review mentions '%s': %s" % [part, dlg.dialog_text])
	(dlg as ConfirmationDialog).canceled.emit()
	assert_eq(screen.review_dialog, null)
	assert_eq(files.map(func(f): return _md5(f)), sums, "cancel leaves every file as it was")
	assert_eq(int(screen.data.map_props("yard").width), 5)
	# Confirm: backup first, then the resize.
	screen._apply_props("yard", props, "")
	screen.review_dialog.confirmed.emit()
	assert_ne(screen.last_backup, "")
	for f in files:
		assert_true(FileAccess.file_exists(screen.last_backup.path_join(f.get_file())), "backup of " + f.get_file())
	assert_eq(int(screen.data.map_props("yard").width), 3)
	assert_eq(RPGMapFiles.load_events_file(screen.data, "yard").events.size(), 0, "the listed event is gone")
	var node := RPGMapFiles.load_map(screen.data, "yard")
	for c in node.navigation.get_used_cells():
		assert_true(c.x < 3 and c.y < 3, "mask cells outside removed")
	node.free()
	screen.queue_free()
	await frames(1)


func test_start_position_outside_blocks_the_resize() -> void:
	_image_map("gate", Vector2i(5, 4), true)
	RPGJson.save_file(ROOT + "/database/system.json", {"schema_version": 1, "system": {"start": {"map": "gate", "position": [4, 3], "facing": "down"}}})
	data.reload()
	var screen: RPGMainScreen = await _screen()
	screen.open_map("gate")
	var props: Dictionary = screen.data.map_props("gate").duplicate(true)
	props.image_map.base = _png("gate_small", Vector2i(32, 32))
	props.width = 2
	props.height = 2
	var sum := _md5(ROOT + "/maps/gate.map.json")
	screen._apply_props("gate", props, "")
	var dlg := screen.review_dialog
	assert_true(dlg != null and not (dlg is ConfirmationDialog), "only Close is offered")
	assert_true(dlg.dialog_text.contains("player start (4, 3)"), dlg.dialog_text)
	dlg.confirmed.emit()
	assert_eq(_md5(ROOT + "/maps/gate.map.json"), sum, "nothing changed")
	assert_eq(int(screen.data.map_props("gate").width), 5)
	screen.queue_free()
	await frames(1)


func test_larger_replacement_grows_the_map() -> void:
	_image_map("field", Vector2i(3, 3), true)
	var screen: RPGMainScreen = await _screen()
	screen.open_map("field")
	var props: Dictionary = screen.data.map_props("field").duplicate(true)
	props.image_map.base = _png("field_big", Vector2i(80, 64))
	props.width = 5
	props.height = 4
	screen._apply_props("field", props, "")
	assert_true(screen.review_dialog.dialog_text.contains("grows"), screen.review_dialog.dialog_text)
	screen.review_dialog.confirmed.emit()
	assert_eq(screen.view.map_size, Vector2i(5, 4))
	assert_eq(screen.view.map_node.navigation_mask(Vector2i(2, 2)), 15, "old cells keep their mask")
	assert_eq(screen.view.map_node.navigation_mask(Vector2i(4, 3)), 0, "new cells start blocked")
	screen.queue_free()
	await frames(1)


func test_image_changed_on_disk_is_refreshed_and_rechecked() -> void:
	_image_map("dock", Vector2i(4, 3), true)
	var screen: RPGMainScreen = await _screen()
	screen.open_map("dock")
	# Same size, new pixels: shown again without a review.
	_png("dock", Vector2i(64, 48), Color(0.1, 0.1, 0.9))
	assert_true(screen.check_image_changes())
	assert_true(screen.view.map_node.image_base.texture.get_image().get_pixel(0, 0).b > 0.8)
	assert_eq(screen.review_dialog, null)
	assert_false(screen.check_image_changes(), "nothing new the second time")
	# Another size: the review opens instead of a silent change.
	_png("dock", Vector2i(80, 48))
	screen.check_image_changes()
	assert_true(screen.review_dialog != null, "a changed size opens the review")
	screen.review_dialog.canceled.emit()
	assert_eq(int(screen.data.map_props("dock").width), 4)
	screen.queue_free()
	await frames(1)


func test_properties_dialog_for_image_maps() -> void:
	_image_map("prop", Vector2i(4, 3), true, true)
	var got := []
	var d := RPGMapPropertiesDialog.open_for(tree.root, data, "prop", false, func(id, p, n): got.append(p))
	await frames(1)
	assert_false(d._f.width.editable, "the size comes from the image")
	var sc: OptionButton = d._f.scroll
	for i in range(1, sc.item_count):
		assert_true(sc.is_item_disabled(i), "loop choice %d is off" % i)
	assert_eq(d._f.base.text, ROOT + "/assets/maps/prop.png")
	d._f.foreground.text = _png("prop_wrong", Vector2i(32, 32))
	d._on_ok()
	assert_true(got.is_empty(), "a foreground of another size is refused")
	assert_true(d._error.text.contains("32×32") and d._error.text.contains("64×48"), d._error.text)
	d._f.foreground.text = ""
	d._on_ok()
	assert_eq(got.size(), 1)
	assert_eq(got[0].image_map.foreground, null)
	assert_eq(got[0].image_map.version, 1)
	assert_eq(int(got[0].width), 4)
	await frames(1)


# --- IM-09: validation and export -----------------------------------------------------------------------

func _image_problems() -> Array:
	data.reload()
	return RPGValidator.image_map_problems(data, RPGValidator.collect_files(data))


func test_validator_reports_image_map_problems() -> void:
	_image_map("ok_map", Vector2i(4, 3), true, true)
	assert_eq(_image_problems(), [], "a good image map has no problems")
	var props: Dictionary = data.map_props("ok_map").duplicate(true)
	var cases := [
		["missing base", {"base": ROOT + "/assets/maps/gone.png"}, "is missing"],
		["missing foreground", {"foreground": ROOT + "/assets/maps/gone_fg.png"}, "foreground image " + ROOT + "/assets/maps/gone_fg.png is missing"],
		["misaligned", {"base": _png("bad_align", Vector2i(50, 48))}, "not a whole number"],
		["over the limit", {"base": _png("bad_big", Vector2i(RPGImageMap.MAX_SIDE + 16, 16))}, str(RPGImageMap.MAX_SIDE)],
		["size differs from map", {"base": _png("bad_size", Vector2i(32, 32))}, "but the map is 4×3"],
		["foreground size", {"foreground": _png("bad_fg", Vector2i(32, 32))}, "foreground image is 32×32"],
	]
	for c in cases:
		var p := props.duplicate(true)
		for k in c[1]:
			p.image_map[k] = c[1][k]
		RPGMapFiles.save_props(data, "ok_map", p)
		var probs := _image_problems()
		var hit := false
		for pr in probs:
			if pr.severity == "error" and str(pr.message).contains(c[2]) and str(pr.message).contains("ok_map"):
				hit = true
				assert_true(pr.get("blocks_export", false), c[0] + " blocks export")
		assert_true(hit, "%s reported: %s" % [c[0], str(probs)])
	var loop := props.duplicate(true)
	loop.scroll = "loop_both"
	RPGMapFiles.save_props(data, "ok_map", loop)
	var lp := _image_problems()
	assert_true(lp.any(func(pr): return str(pr.message).contains("loops")), str(lp))
	# The same checks run in the full validation used before playtest and export.
	var reg := RPGCommandRegistry.new()
	reg.load_all([], [], "res://extensions")
	var full := RPGExportCheck.problems(data, reg)
	assert_true(full.any(func(pr): return str(pr.message).contains("loops")), "pre-playtest / export check")
	assert_true(RPGValidator.blocks_export(full))


func test_export_keeps_images_only_image_maps_reference() -> void:
	const Deploy := preload("res://addons/rpg/editor/tools/rpg_deploy.gd")
	_image_map("museum", Vector2i(3, 3), true, true)
	var unused := _png("never_used", Vector2i(16, 16))
	var ex := Deploy.unused_asset_excludes(data, ROOT + "/assets")
	assert_false(ex.has(ROOT + "/assets/maps/museum.png"), "base image kept: " + str(ex))
	assert_false(ex.has(ROOT + "/assets/maps/museum_fg.png"), "foreground image kept")
	assert_true(ex.has(unused), "an unused image is still left out")


# --- IM-10: legacy maps -------------------------------------------------------------------------------

func test_legacy_tile_maps_are_unchanged() -> void:
	assert_eq(RPGMapFiles.create_map(data, "legacy", "Legacy", "town", 6, 5), OK)
	var p: Dictionary = data.map_props("legacy")
	assert_false(p.has("image_map"), "no new key in old-style maps")
	assert_false(RPGImageMap.is_image_map(p))
	var node := RPGMapFiles.load_map(data, "legacy")
	assert_true(node.navigation == null, "no Navigation layer")
	assert_true(node.image_base == null)
	var mv := RPGMovement.new(node)
	node.size = Vector2i(6, 5)
	assert_eq(mv.passage(Vector2i(2, 2)), 15, "a map with no tiles at all is still fully walkable")
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key("lower_3")
	node.tile_layers[0].set_cell(Vector2i(1, 1), a.source, a.coords)
	mv.invalidate()
	assert_eq(mv.passage(Vector2i(4, 4)), 0, "empty cells on a painted map are still blocked")
	node.free()
	assert_eq(_image_problems(), [])


func test_sample_maps_pass_as_before() -> void:
	# Representative legacy maps: the sample project's maps, compared with the old rule cell by cell.
	var sample := RPGProjectData.open("res://rpg")
	var checked := 0
	for id in sample.maps:
		var p: Dictionary = sample.map_props(id)
		assert_false(RPGImageMap.is_image_map(p), "%s is a tile map" % id)
		var node := RPGMapFiles.load_map(sample, id)
		assert_true(node.navigation == null, "%s has no mask" % id)
		var mv := RPGMovement.new(node)
		node.size = sample.map_size(id)
		for y in node.size.y:
			for x in node.size.x:
				var old := _legacy_passage(node, Vector2i(x, y))
				if old >= 0:
					assert_eq(mv.passage(Vector2i(x, y)), old, "%s (%d, %d)" % [id, x, y])
					checked += 1
		node.free()
	assert_true(checked > 100, "compared %d cells" % checked)
	var probs := RPGValidator.image_map_problems(sample, RPGValidator.collect_files(sample))
	assert_eq(probs, [], "no image-map problems in a project without image maps")
