extends "res://tests/rpg_test_case.gd"
## Map editor: map files, autotile painting through the map view, undo/redo, the eraser,
## regions, events (new, move, delete, paste with fresh IDs) and tileset-free scene saving.

const ROOT := "user://rpg_editor_test"

var data: RPGProjectData
var view: RPGMapView
var undo: UndoRedo


func before_each() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT + "/database")
	RPGJson.save_file(ROOT + "/project.json", {"schema_version": 1, "project_id": "editor_test", "name": "Editor test", "extensions": []})
	RPGJson.save_file(ROOT + "/profile.json", {"schema_version": 1, "profile": "rm2k", "tile_size": 16})
	RPGJson.save_file(ROOT + "/database/tilesets.json", {"schema_version": 1, "records": [{"id": "town", "name": "Town", "profile": "rm2k", "sheet": "res://assets/starter/ChipSet/town.png"}]})
	data = RPGProjectData.open(ROOT)
	assert_eq(RPGMapFiles.create_map(data, "meadow", "Meadow", "town", 12, 10), OK)
	view = RPGMapView.new()
	undo = UndoRedo.new()
	view.undo = RPGUndo.new(undo)
	tree.root.add_child(view)
	view.open_map(data, "meadow")


func after_each() -> void:
	view.queue_free()
	undo.free()
	await frames(1)
	_wipe(ROOT)


func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(path.path_join(sub))
		d.remove(sub)


func _brush(key: String) -> Dictionary:
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key(key)
	return {"kind": "tiles", "size": Vector2i.ONE, "cells": [{"offset": Vector2i.ZERO, "source": a.source, "coords": a.coords}]}


func test_create_map_writes_three_files_and_index() -> void:
	assert_true(data.maps.has("meadow"))
	assert_true(FileAccess.file_exists(ROOT + "/maps/meadow.tscn"))
	assert_true(FileAccess.file_exists(ROOT + "/maps/meadow.map.json"))
	assert_true(FileAccess.file_exists(ROOT + "/maps/meadow.events.json"))
	assert_eq(data.map_props("meadow").width, 12)
	assert_eq(RPGMapFiles.create_map(data, "meadow", "Again", "town", 5, 5), ERR_ALREADY_EXISTS, "duplicate IDs are refused")


func test_rectangle_of_autotile_connects_and_undo_restores() -> void:
	view.brush = _brush("terrain_1")
	view.tool = "rect"
	view._begin_stroke()
	view._apply_shape(Vector2i(2, 2), Vector2i(4, 4), false)
	view._end_stroke("Rectangle")
	var l1: TileMapLayer = view.tile_layers()[0]
	assert_eq(RPGAutotile.group_of(l1, Vector2i(3, 3)), RPGAutotile.group_of(l1, Vector2i(2, 2)))
	assert_eq(l1.get_cell_atlas_coords(Vector2i(3, 3)).x, 0, "centre of a 3x3 block is the fully connected variant")
	assert_ne(l1.get_cell_atlas_coords(Vector2i(2, 2)).x, 0, "corner is not the centre variant")
	assert_true(view.dirty)
	assert_true(undo.has_undo())
	undo.undo()
	assert_eq(l1.get_cell_source_id(Vector2i(3, 3)), -1, "undo removes the stroke")
	undo.redo()
	assert_eq(l1.get_cell_atlas_coords(Vector2i(3, 3)).x, 0, "redo restores it")


func test_auto_layer_puts_upper_tiles_on_layer2_and_eraser_clears() -> void:
	view.brush = _brush("upper_6")
	view.stamp(Vector2i(5, 5))
	var l2: TileMapLayer = view.tile_layers()[1]
	assert_ne(l2.get_cell_source_id(Vector2i(5, 5)), -1, "bush is an upper tile")
	assert_eq(view.tile_layers()[0].get_cell_source_id(Vector2i(5, 5)), -1)
	view.brush = _brush("upper_0")
	view.stamp(Vector2i(5, 5))
	assert_eq(l2.get_cell_source_id(Vector2i(5, 5)), -1, "the empty tile erases")


func test_fill_and_regions() -> void:
	view.brush = _brush("terrain_0")
	view.tool = "fill"
	view._fill(Vector2i(0, 0))
	assert_eq(view.tile_layers()[0].get_used_cells().size(), 120, "flood fill covers the empty map")
	view.set_mode("region")
	view.brush = {"kind": "region", "region": 7}
	view._paint_region(Vector2i(3, 3))
	assert_eq(view.map_node.region_at(Vector2i(3, 3)), 7)


func test_events_new_move_delete_paste_never_reuse_ids() -> void:
	var id := view.new_event_at(Vector2i(2, 3))
	assert_true(id != "")
	assert_eq(RPGMapFiles.load_events_file(data, "meadow").events.size(), 1, "written to the events file")
	var before := view.events_file.duplicate(true)
	view._set_event_position_live(id, Vector2i(6, 6))
	view.commit_events(before, "Move")
	assert_eq(view.find_event(id).position, [6, 6])
	undo.undo()
	assert_eq(view.find_event(id).position, [2, 3], "move is undoable")
	var copy := view.find_event(id).duplicate(true)
	view.delete_event(id)
	assert_true(view.find_event(id).is_empty())
	var pasted := view.paste_event(copy, Vector2i(1, 1))
	assert_ne(pasted, id, "paste never reuses a deleted ID")
	assert_true(RPGIds.is_valid(pasted))


func test_scene_saved_without_tilesets_and_reloads_cells() -> void:
	view.brush = _brush("water_a")
	view.stamp(Vector2i(1, 1))
	assert_eq(view.save(), OK)
	var text := FileAccess.get_file_as_string(ROOT + "/maps/meadow.tscn")
	assert_false(text.contains("TileSet"), "map scenes do not embed or reference TileSets")
	var node := RPGMapFiles.load_map(data, "meadow")
	assert_ne(node.tile_layers[0].get_cell_source_id(Vector2i(1, 1)), -1, "cells survive save and reload")
	assert_ne(node.tile_layers[0].tile_set, null, "TileSet assigned on load")
	node.free()


func test_resize_removes_outside_events() -> void:
	view.new_event_at(Vector2i(10, 8))
	view.new_event_at(Vector2i(1, 1))
	var res := RPGMapFiles.resize(data, view.map_node, 5, 5)
	assert_eq(res.removed_events.size(), 1)
	assert_eq(res.events_file.events.size(), 1)


func test_click_on_map_picks_a_location() -> void:
	var got := []
	view.pick_callback = func(map_id: String, cell: Vector2i): got.append([map_id, cell])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.world.position + (Vector2(3, 4) * view.tile_size + Vector2.ONE * 2) * view.zoom
	view._gui_input(click)
	assert_eq(got, [["meadow", Vector2i(3, 4)]], "the clicked cell is returned")
	assert_false(view.pick_callback.is_valid(), "picking is one-shot")
	assert_eq(view.tile_layers()[0].get_used_cells().size(), 0, "the click did not paint")
	view.pick_callback = func(map_id: String, cell: Vector2i): got.append([map_id, cell])
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	view._gui_input(esc)
	assert_eq(got[-1], ["", Vector2i(-1, -1)], "Esc cancels")


func test_route_preview_traces_steps() -> void:
	var tr := RPGRoutePreview.trace(Vector2i(2, 2), "down", {"steps": [{"step": "right"}, {"step": "right"}, {"turn": "left_90"}, {"step": "forward"}, {"jump": [0, 2]}, {"step": "random"}, {"step": "down"}]})
	assert_eq(tr.cells, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 1), Vector2i(4, 3)])
	assert_eq(tr.unknown, "random", "random steps cannot be predicted, so the trace stops there")
	view.show_route_preview(tr)
	assert_eq(view.route_preview.cells.size(), 5)
	await frames(2)


func test_main_screen_notices_outside_edits() -> void:
	# The main screen works on res://rpg; use the sample, change a file's time, and restore it.
	var screen := RPGMainScreen.new()
	screen.setup(null)
	tree.root.add_child(screen)
	await frames(2)
	screen.open_map("town")
	assert_eq(screen.disk_changes(), [], "nothing changed yet")
	var path: String = screen.data.map_entry("town").events
	var text := FileAccess.get_file_as_string(path)
	await tree.create_timer(1.1).timeout   # modification times have one-second resolution
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text + "
")   # changes are detected by content
	f.close()
	assert_eq(screen.disk_changes(), [path], "an outside write is noticed")
	screen.check_disk_changes()
	assert_eq(screen.disk_changes(), [], "with nothing unsaved it reloads silently")
	assert_true(screen.status.text.contains("outside the editor"), screen.status.text)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	screen.queue_free()
	await frames(1)


# Regressions from the editor review.

func test_undo_after_switching_maps_writes_the_right_map() -> void:
	assert_eq(RPGMapFiles.create_map(data, "other", "Other", "town", 8, 8), OK)
	var on_meadow := view.new_event_at(Vector2i(2, 2))
	view.open_map(data, "other")
	view.new_event_at(Vector2i(1, 1))
	view.open_map(data, "meadow")
	undo.undo()   # undoes the event added on "other"
	assert_eq(RPGMapFiles.load_events_file(data, "meadow").events.size(), 1, "meadow keeps its event")
	assert_eq(RPGMapFiles.load_events_file(data, "meadow").events[0].id, on_meadow)
	assert_eq(RPGMapFiles.load_events_file(data, "other").events.size(), 0, "the undo applied to other")
	assert_eq(view.events().size(), 1, "the open map's view is unchanged")
	undo.redo()
	assert_eq(RPGMapFiles.load_events_file(data, "other").events.size(), 1, "redo applied to other")
	assert_eq(RPGMapFiles.load_events_file(data, "meadow").events.size(), 1)


func test_painting_floor_keeps_hand_drawn_shadows() -> void:
	RPGAutotile.set_shadow(view.map_node.shadows, Vector2i(8, 8), 15)
	RPGAutotile.set_shadow(view.map_node.shadows, Vector2i(5, 5), 15)
	view.brush = _brush("terrain_0")
	view._fill(Vector2i(0, 0))
	assert_eq(RPGAutotile.get_shadow(view.map_node.shadows, Vector2i(8, 8)), 15, "fill keeps a shadow")
	view.stamp(Vector2i(4, 5))
	assert_eq(RPGAutotile.get_shadow(view.map_node.shadows, Vector2i(5, 5)), 15, "painting floor keeps a neighbour's shadow")


func test_fill_with_the_eraser_erases() -> void:
	view.brush = _brush("upper_6")
	for x in range(2, 5):
		view.stamp(Vector2i(x, 3))
	var l2: TileMapLayer = view.tile_layers()[1]
	assert_ne(l2.get_cell_source_id(Vector2i(3, 3)), -1)
	view.brush = _brush("upper_0")
	view._fill(Vector2i(3, 3))
	for x in range(2, 5):
		assert_eq(l2.get_cell_source_id(Vector2i(x, 3)), -1, "erased (%d,3)" % x)


func test_growing_a_map_rejoins_edge_autotiles() -> void:
	view.brush = _brush("terrain_1")
	view._fill(Vector2i(0, 0))
	var l1: TileMapLayer = view.tile_layers()[0]
	var full := l1.get_cell_atlas_coords(Vector2i(5, 5)).x
	assert_eq(view.save(), OK)
	var props: Dictionary = data.map_props("meadow").duplicate(true)
	props.width = 14
	RPGMapFiles.save_props(data, "meadow", props)
	data.reload()
	view.open_map(data, "meadow")
	l1 = view.tile_layers()[0]
	view.rejoin_edges(Vector2i(12, 10))
	assert_ne(l1.get_cell_atlas_coords(Vector2i(11, 5)).x, full, "the old edge is no longer drawn fully joined")
	assert_eq(l1.get_cell_atlas_coords(Vector2i(10, 5)).x, full, "inner cells unchanged")


func test_shift_contents_wraps_tiles_and_events() -> void:
	view.brush = _brush("upper_6")
	view.stamp(Vector2i(11, 2))
	var id := view.new_event_at(Vector2i(0, 9))
	view.save()
	var ev := RPGMapFiles.shift_contents(data, view.map_node, Vector2i(1, 1))
	var l2: TileMapLayer = view.tile_layers()[1]
	assert_ne(l2.get_cell_source_id(Vector2i(0, 3)), -1, "x 11 wraps to 0 on a 12-wide map")
	assert_eq(l2.get_cell_source_id(Vector2i(11, 2)), -1)
	var moved: Array = ev.events.filter(func(e): return e.id == id)
	assert_eq(moved[0].position, [1, 0], "y 9 wraps to 0 on a 10-high map")
	RPGMapFiles.shift_contents(data, view.map_node, Vector2i(-1, -1))
	assert_ne(l2.get_cell_source_id(Vector2i(11, 2)), -1, "shifting back restores the map")


func test_load_sample_map_adds_a_tiles_only_map() -> void:
	var samples := RPGMapFiles.sample_maps()
	assert_true(samples.size() >= 3, "sample maps ship with the addon")
	var nid := RPGMapFiles.load_sample_map(data, "town")
	assert_ne(nid, "")
	data.reload()
	assert_true(data.maps.has(nid))
	assert_eq(int(data.map_props(nid).width), 30)
	assert_eq(RPGMapFiles.load_events_file(data, nid).events.size(), 0, "tiles only, no events")
	var node := RPGMapFiles.load_map(data, nid)
	assert_true(node.tile_layers[0].get_used_cells().size() > 100, "tiles copied")
	node.free()


func test_main_screen_menu_bar_drives_modes_tools_and_events() -> void:
	var screen := RPGMainScreen.new()
	screen.setup(null)
	tree.root.add_child(screen)
	await frames(2)
	screen.open_map("town")
	for title in ["Project", "Edit", "Mode", "Draw", "Layer", "Scale", "Tools", "Game", "Help"]:
		assert_true(screen._menus.has(title), "menu %s" % title)
	screen.menu_action(RPGMainScreen.M_MODE + 1)
	assert_eq(screen.view.mode, "event")
	screen.menu_action(RPGMainScreen.M_DRAW + 3)
	assert_eq(screen.view.tool, "fill")
	screen.menu_action(RPGMainScreen.M_LAYER + 2)
	assert_eq(screen.view.layer_mode, 2)
	assert_eq(screen.layer_option.selected, 2, "toolbar follows the menu")
	screen.menu_action(RPGMainScreen.M_ZOOM_2)
	assert_eq(screen.view.zoom, 2.0)
	# Edit > Copy / Paste an event through the clipboard (no write: paste is undone right away).
	var first: String = str(screen.view.events()[0].id)
	screen.view.select_event(first)
	screen.menu_action(RPGMainScreen.M_COPY)
	assert_false(screen.clipboard_event.is_empty(), "copied")
	screen.queue_free()
	await frames(1)


func test_generate_dungeon_is_connected_and_undoable() -> void:
	const DG := preload("res://addons/rpg/editor/map/rpg_dungeon_generator.gd")
	var a: Dictionary = DG.generate(Vector2i(40, 30), 7)
	var b: Dictionary = DG.generate(Vector2i(40, 30), 7)
	assert_eq(a.floor, b.floor, "same seed, same dungeon")
	assert_true(a.rooms.size() >= 2)
	# Every floor cell is reachable from the first room.
	var start: Vector2i = a.rooms[0].get_center()
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < 40 and n.y < 30 and a.floor[n.y][n.x] and not seen.has(n):
				seen[n] = true
				todo.append(n)
	var floors := 0
	for row in a.floor:
		for v in row:
			floors += 1 if v else 0
	assert_eq(seen.size(), floors, "one connected dungeon")
	for x in 40:
		assert_false(a.floor[0][x] or a.floor[29][x], "walls along the edge")
	# Painted through the view as one undo step.
	var choices: Array = DG.tile_choices(view.tile_set())
	assert_true(choices.size() >= 2, "tileset offers floor and wall tiles")
	var keys := choices.map(func(c): return c[0])
	assert_has(keys, "terrain_0")
	var small: Dictionary = DG.generate(view.map_size, 3)
	view._begin_stroke()
	DG.apply(view.map_node, small, "terrain_0", "terrain_5")
	view._end_stroke("Generate dungeon")
	var l1: TileMapLayer = view.tile_layers()[0]
	assert_eq(l1.get_used_cells().size(), view.map_size.x * view.map_size.y, "every cell painted")
	undo.undo()
	assert_eq(l1.get_used_cells().size(), 0, "undo restores the empty map")


func test_new_child_map_inherits_parent_settings_and_sound_choices() -> void:
	var pp: Dictionary = data.map_props("meadow").duplicate(true)
	pp["music"] = {"file": "town"}
	pp["bgs"] = {"file": ""}
	RPGMapFiles.save_props(data, "meadow", pp)
	data.reload()
	var d := RPGMapPropertiesDialog.open_for(tree.root, data, "", true, func(_a = null, _b = null, _c = null): pass, "meadow")
	assert_eq(int(d.props.width), 12, "size from the parent")
	assert_eq(d.props.music, {"file": "town"}, "music from the parent")
	d.queue_free()
	assert_eq(RPGMapPropertiesDialog._sound_value(RPGMapPropertiesDialog.KEEP), null, "keep playing = null")
	assert_eq(RPGMapPropertiesDialog._sound_value(RPGMapPropertiesDialog.STOP), {"file": ""}, "stop = empty file")
	assert_eq(RPGMapPropertiesDialog._sound_choice({"file": ""}), RPGMapPropertiesDialog.STOP)
	assert_eq(RPGMapPropertiesDialog._sound_choice(null), RPGMapPropertiesDialog.KEEP)
	await frames(1)


# --- Editor QA pass (2026-11-10), EDITOR_GAPS.md --------------------------------------------------

## E9: closing a map leaves nothing behind in the view (no ghost grid, events or selection).
func test_closed_map_leaves_no_ghost() -> void:
	view.close_map()
	assert_eq(view.map_size, Vector2i.ZERO)
	assert_eq(view.events(), [])
	assert_false(view.in_map(Vector2i(1, 1)), "no cell of the closed map can be painted")


## E17: double-clicking an empty tile in Event mode asks for a new event (no context menu).
func test_double_click_on_empty_tile_requests_a_new_event() -> void:
	view.set_mode("event")
	var asked := []
	var menus := []
	view.new_event_requested.connect(func(c): asked.append(c))
	view.map_context.connect(func(c, _p): menus.append(c))
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = true
	view._event_mouse(e, Vector2i(3, 4))
	assert_eq(asked, [Vector2i(3, 4)])
	assert_eq(menus, [], "no menu on a double-click")


## E7: "Actual size" is the size the game draws: 16 px art in a 48 px project is 3x.
func test_actual_size_is_the_game_size() -> void:
	assert_eq(view.game_zoom(), 1.0, "16 px tiles in a 16 px project")
	data.profile["tile_size"] = 48
	assert_eq(view.game_zoom(), 3.0, "16 px tiles in a 48 px (MV-style) project")
	data.profile["tile_size"] = 16


## E5: right-clicking the project row or empty space still offers New map (and Paste).
func test_map_tree_menu_on_empty_space_offers_new_map() -> void:
	var t := RPGMapTree.new()
	tree.root.add_child(t)
	t.rebuild(data, "meadow")
	var m := t.open_menu("")
	var items := []
	for i in m.item_count:
		items.append(m.get_item_text(i))
	assert_has(items, "New map...")
	assert_has(items, "Paste")
	assert_false(items.has("Delete"), "nothing to delete without a map")
	m.hide()
	var m2 := t.open_menu("meadow")
	var items2 := []
	for i in m2.item_count:
		items2.append(m2.get_item_text(i))
	assert_has(items2, "Properties...")
	assert_has(items2, "Delete")
	m2.hide()
	t.queue_free()
	await frames(1)


## E4: a bad Map ID keeps the New map dialog open and says why; a good one creates the map.
func test_new_map_dialog_keeps_bad_ids_open() -> void:
	var made := []
	var d := RPGMapPropertiesDialog.open_for(tree.root, data, "", true, func(id, _p, _n): made.append(id))
	await frames(1)
	d._f.id.text = "My Map"
	d._on_ok()
	assert_true(is_instance_valid(d) and not d.is_queued_for_deletion(), "the dialog stays open")
	assert_true(d._error.text.contains("can't be a Map ID"), d._error.text)
	d._f.id.text = "meadow"
	d._on_ok()
	assert_true(d._error.text.contains("already"), d._error.text)
	d._f.id.text = "cave"
	d._on_ok()
	assert_eq(made, ["cave"])
	await frames(1)


## E10: the dungeon's default floor is walkable and its default wall blocks.
func test_dungeon_defaults_walkable_floor_and_blocking_wall() -> void:
	var DG := preload("res://addons/rpg/editor/map/rpg_dungeon_generator.gd")
	var choices: Array = DG.tile_choices(view.tile_set())
	var pair: Array = DG.default_pair(choices)
	assert_true(choices[pair[0]][2], "floor %s is walkable" % choices[pair[0]][1])
	var any_blocking := choices.any(func(c): return not c[2])
	if any_blocking:
		assert_false(choices[pair[1]][2], "wall %s blocks" % choices[pair[1]][1])
	assert_false(str(choices[0][1]).begins_with("Lower 1"), "labels are readable, autotiles first")
	var lowers := choices.filter(func(c): return str(c[0]).begins_with("lower_")).map(func(c): return str(c[0]))
	if lowers.size() > 11:
		assert_true(lowers.find("lower_2") < lowers.find("lower_10"), "numbers sort naturally")


## E8: the eyedropper shows the picked tile in the palette.
func test_eyedropper_shows_the_tile_in_the_palette() -> void:
	var p := RPGTilePalette.new()
	tree.root.add_child(p)
	p.set_tile_set(view.tile_set(), 16)
	await frames(1)
	p.current_tab = 0
	p.set_brush_external(_brush("lower_3"))
	var shown := p.get_current_tab_control()
	var g: Variant = shown.get_child(0) if shown != null and shown.get_child_count() > 0 else null
	assert_true(g != null and g.sel_from >= 0, "the picked tile is highlighted on its page")
	if g != null and g.sel_from >= 0:
		assert_eq(g.cells[g.sel_from].coords, RPGTilesetBuilder.atlas_for_key("lower_3").coords)
	p.queue_free()
	await frames(1)


## E12: the tile settings name tiles the way a maker reads them; regions use one colour everywhere.
func test_tile_labels_and_region_colours() -> void:
	assert_eq(RPGTileSettingsDialog.tile_label("terrain_8"), "Autotile 8")
	assert_eq(RPGTileSettingsDialog.tile_label("lower_12"), "Lower tile 12")
	assert_eq(RPGTilesetBuilder.region_color(1, 0.45).h, RPGTilesetBuilder.region_color(1).h)


## E6 / E19: the zoom keys and the Edit menu's Ctrl+C / Ctrl+V work on the RPG tab.
func test_zoom_and_event_clipboard_keys() -> void:
	var screen := RPGMainScreen.new()
	screen.setup(null)
	tree.root.add_child(screen)
	await frames(2)
	screen.open_map("town")
	var events_path: String = screen.data.map_entry("town").events
	var before := FileAccess.get_file_as_string(events_path)
	var key := func(code: Key):
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.ctrl_pressed = true
		ev.pressed = true
		screen._shortcut_input(ev)
	var z: float = screen.view.zoom
	key.call(KEY_EQUAL)
	assert_true(screen.view.zoom > z, "Ctrl+= zooms in")
	key.call(KEY_MINUS)
	assert_true(absf(screen.view.zoom - z) < 0.001, "Ctrl+- zooms out")
	key.call(KEY_0)
	assert_eq(screen.view.zoom, screen.view.game_zoom(), "Ctrl+0 is the game's size")
	screen.menu_action(RPGMainScreen.M_MODE + 1)
	var n: int = screen.view.events().size()
	screen.view.select_event(str(screen.view.events()[0].id))
	key.call(KEY_C)
	assert_false(screen.clipboard_event.is_empty(), "Ctrl+C copies the event")
	key.call(KEY_V)
	assert_eq(screen.view.events().size(), n + 1, "Ctrl+V pastes it")
	screen.queue_free()
	await frames(1)
	var f := FileAccess.open(events_path, FileAccess.WRITE)
	f.store_string(before)
	f.close()


## I14: on a VX Ace / MV tileset, an overlay autotile painted with the pencil keeps the ground under
## it on the map's hidden Layer1Base; undo, redo, the eyedropper and save / reload keep both.
func test_overlay_autotile_keeps_its_base_through_undo_and_save() -> void:
	var a1 := Image.create_empty(512, 384, false, Image.FORMAT_RGBA8)
	a1.fill(Color8(20, 60, 200))
	var a2 := Image.create_empty(512, 384, false, Image.FORMAT_RGBA8)
	a2.fill(Color8(40, 160, 40))
	a2.fill_rect(Rect2i(256, 0, 64, 96), Color(0, 0, 0, 0))
	a2.fill_rect(Rect2i(264, 8, 48, 80), Color8(20, 100, 20))
	DirAccess.make_dir_recursive_absolute(ROOT + "/sheets")
	a1.save_png(ROOT + "/sheets/Coast_A1.png")
	a2.save_png(ROOT + "/sheets/Coast_A2.png")
	var file: Dictionary = RPGJson.load_or(ROOT + "/database/tilesets.json", {})
	file.records.append({"id": "zz_test_coast", "name": "Coast", "profile": "vx", "sheets": {"a1": ROOT + "/sheets/Coast_A1.png", "a2": ROOT + "/sheets/Coast_A2.png"}})
	RPGJson.save_file(ROOT + "/database/tilesets.json", file)
	data.reload()
	RPGMap.clear_tileset_cache()
	assert_eq(RPGMapFiles.create_map(data, "shore", "Shore", "zz_test_coast", 8, 6), OK)
	view.open_map(data, "shore")
	var ts := view.tile_set()
	assert_true(ts != null and not (ts.get_meta(RPGAutotile.OVERLAY_META, {}) as Dictionary).is_empty(), "the VX tileset lists its overlays")
	if ts == null:
		return
	var pick := func(key: String) -> Dictionary:
		var a: Dictionary = RPGTilesetBuilder.atlas_for_key(key, ts)
		return {"kind": "tiles", "size": Vector2i.ONE, "cells": [{"offset": Vector2i.ZERO, "source": a.source, "coords": a.coords}]}
	var classes: Array = ts.get_meta(RPGAutotile.CLASSES_META)
	view.brush = pick.call("a2_0")
	view.tool = "fill"
	view._begin_stroke()
	view._fill(Vector2i(0, 0))
	view._end_stroke("Fill")
	var base: TileMapLayer = view.map_node.base_layer
	assert_true(base != null and base.name == RPGAutotile.BASE_LAYER, "the hidden base layer is made before the first stroke")
	if base == null:
		return
	assert_eq(base.get_index(), view.tile_layers()[0].get_index() - 1, "drawn just below Layer1")
	view.tool = "pencil"
	view.brush = pick.call("a2_4")
	view._begin_stroke()
	view.stamp(Vector2i(3, 3))
	view._end_stroke("Paint")
	var top: TileMapLayer = view.tile_layers()[0]
	assert_eq(RPGAutotile.group_of(top, Vector2i(3, 3)), classes.find("a2_4"), "the bush is on Layer1")
	assert_eq(RPGAutotile.group_of(base, Vector2i(3, 3)), classes.find("a2_0"), "the grass is under it")
	undo.undo()
	assert_eq(RPGAutotile.group_of(top, Vector2i(3, 3)), classes.find("a2_0"), "undo restores the grass")
	assert_eq(base.get_cell_source_id(Vector2i(3, 3)), -1, "and empties the base")
	undo.redo()
	assert_eq(RPGAutotile.group_of(base, Vector2i(3, 3)), classes.find("a2_0"), "redo puts the base back")
	view._eyedropper(Vector2i(3, 3), Vector2i(3, 3))
	assert_eq(view.brush.cells[0].coords, RPGTilesetBuilder.atlas_for_key("a2_4", ts).coords, "the eyedropper picks the visible bush")
	assert_eq(view.save(), OK)
	var node := RPGMapFiles.load_map(data, "shore")
	assert_true(node.base_layer != null and node.base_layer.tile_set != null, "the base layer is saved and gets the TileSet on load")
	if node.base_layer != null:
		assert_eq(RPGAutotile.group_of(node.base_layer, Vector2i(3, 3)), classes.find("a2_0"))
	node.free()
	# The eraser shows the grass again.
	view.brush = _brush("upper_0")
	view.layer_mode = 1
	view._begin_stroke()
	view.stamp(Vector2i(3, 3))
	view._end_stroke("Erase")
	assert_eq(RPGAutotile.group_of(top, Vector2i(3, 3)), classes.find("a2_0"), "erasing the bush shows the grass")
	assert_eq(base.get_cell_source_id(Vector2i(3, 3)), -1)
	# The TileSet cache this test made in the project is removed again.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RPGTilesetBuilder.cache_path("zz_test_coast")))


## I1 follow-up: deep water painted in shallow water rounds its corners with the blend pieces in
## the editor too; undo, the eyedropper and the fill tool treat a blended cell as plain water.
func test_deep_water_blend_in_the_editor() -> void:
	view.brush = _brush("water_a")
	view.tool = "fill"
	view._begin_stroke()
	view._fill(Vector2i(0, 0))
	view._end_stroke("Fill")
	view.tool = "pencil"
	view.brush = _brush("water_c")
	view._begin_stroke()
	for c in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)]:
		view.stamp(c)
	view._end_stroke("Paint")
	var l1: TileMapLayer = view.tile_layers()[0]
	var water_a := RPGChipset2k.group_keys().find("water_a")
	assert_eq(l1.get_cell_source_id(Vector2i(5, 5)), RPGTilesetBuilder.SOURCE_WATER_BLEND, "shallow water in the inner corner is rounded")
	assert_eq(l1.get_cell_source_id(Vector2i(4, 4)), RPGTilesetBuilder.SOURCE_WATER_BLEND, "the deep corner is rounded")
	assert_eq(RPGAutotile.group_of(l1, Vector2i(5, 5)), water_a)
	undo.undo()
	assert_eq(l1.get_cell_source_id(Vector2i(5, 5)), RPGTilesetBuilder.SOURCE_AUTOTILE, "undo: plain water again")
	undo.redo()
	view._eyedropper(Vector2i(5, 5), Vector2i(5, 5))
	assert_eq([view.brush.cells[0].source, view.brush.cells[0].coords], [RPGTilesetBuilder.SOURCE_AUTOTILE, Vector2i(47, water_a)], "the eyedropper picks water A")
	view.brush = _brush("terrain_0")
	view.tool = "fill"
	view._begin_stroke()
	view._fill(Vector2i(0, 0))
	view._end_stroke("Fill")
	assert_eq(RPGAutotile.group_of(l1, Vector2i(5, 5)), RPGChipset2k.group_keys().find("terrain_0"), "the fill covers the blended water cell")
	assert_eq(RPGAutotile.group_of(l1, Vector2i(4, 4)), RPGChipset2k.group_keys().find("water_c"), "and stops at deep water")
