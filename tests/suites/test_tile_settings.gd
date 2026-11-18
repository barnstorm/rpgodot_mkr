extends "res://tests/rpg_test_case.gd"
## Tile settings (passability and flags per tile): override file round trip, rebuilt TileSets,
## reset, copy to many, unknown keys, and the dialog driven headless.

const ROOT := "user://rpg_tile_settings_test"

var data: RPGProjectData


func before_each() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT + "/database")
	RPGJson.save_file(ROOT + "/project.json", {"schema_version": 1, "project_id": "tiles_test", "name": "Tiles test", "extensions": []})
	RPGJson.save_file(ROOT + "/profile.json", {"schema_version": 1, "profile": "rm2k", "tile_size": 16})
	RPGJson.save_file(ROOT + "/database/tilesets.json", {"schema_version": 1, "records": [
		{"id": "town", "name": "Town", "profile": "rm2k", "sheet": "res://assets/starter/ChipSet/town.png"},
		{"id": "town2", "name": "Town copy", "profile": "rm2k", "sheet": "res://assets/starter/ChipSet/town.png"},
	]})
	data = RPGProjectData.open(ROOT)
	RPGMap.clear_tileset_cache()


func after_each() -> void:
	RPGMap.clear_tileset_cache()
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


func _ov_path() -> String:
	return ROOT + "/tileset_overrides/town.json"


func _tile_data(ts: TileSet, key: String) -> TileData:
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key(key)
	return (ts.get_source(a.source) as TileSetAtlasSource).get_tile_data(a.coords, 0)


func test_override_round_trip() -> void:
	var s := RPGTileSettings.open(data, "town")
	assert_true(s.errors.is_empty(), "builds: %s" % str(s.errors))
	assert_eq(s.get_value("lower_10", "passage"), 15, "lower tiles default to open")
	s.toggle_direction("lower_10", RPGTileSettings.DIR_UP)
	s.toggle_flag("lower_10", RPGTilesetBuilder.FLAG_COUNTER)
	s.set_terrain("lower_10", 4)
	assert_true(s.dirty)
	assert_eq(s.save(), OK)
	assert_false(s.dirty)
	var raw: Dictionary = RPGJson.load_or(_ov_path(), {})
	assert_eq(raw.get("schema_version"), 1)
	assert_eq(raw.tiles.lower_10, {"passage": 7, "flags": RPGTilesetBuilder.FLAG_COUNTER, "terrain": 4})
	var again := RPGTileSettings.open(data, "town")
	assert_eq(again.effective("lower_10"), {"passage": 7, "flags": RPGTilesetBuilder.FLAG_COUNTER, "terrain": 4})
	assert_true(again.is_overridden("lower_10"))
	assert_false(again.is_overridden("lower_11"))
	# Toggling back to the default drops the field; the tile is no longer overridden.
	again.toggle_direction("lower_10", RPGTileSettings.DIR_UP)
	again.toggle_flag("lower_10", RPGTilesetBuilder.FLAG_COUNTER)
	again.set_terrain("lower_10", 0)
	assert_false(again.is_overridden("lower_10"))


func test_rebuilt_tileset_reflects_changes() -> void:
	var before: TileSet = RPGMap.tileset_for(data, "town")
	assert_eq(int(_tile_data(before, "lower_20").get_custom_data("passage")), 15)
	var s := RPGTileSettings.open(data, "town")
	s.set_passage("lower_20", 0)
	s.toggle_flag("upper_7", RPGTilesetBuilder.FLAG_LADDER)
	s.set_terrain("terrain_2", 9)
	assert_eq(s.save(), OK)
	var ts: TileSet = RPGMap.tileset_for(data, "town")
	assert_ne(ts, before, "a new TileSet is built after saving")
	assert_eq(int(_tile_data(ts, "lower_20").get_custom_data("passage")), 0, "passage on lower_20")
	assert_eq(int(_tile_data(ts, "lower_21").get_custom_data("passage")), 15, "neighbour untouched")
	assert_true(int(_tile_data(ts, "upper_7").get_custom_data("flags")) & RPGTilesetBuilder.FLAG_LADDER != 0, "ladder on upper_7")
	# Every variant of the autotile group carries the terrain tag.
	for e in RPGTilesetBuilder.tiles_for_key(ts, "terrain_2"):
		assert_eq(int((ts.get_source(e[0]) as TileSetAtlasSource).get_tile_data(e[1], 0).get_custom_data("terrain")), 9, "terrain on %s" % str(e[1]))


func test_reset_removes_override() -> void:
	var s := RPGTileSettings.open(data, "town")
	s.set_passage("lower_3", 0)
	s.set_terrain("lower_4", 2)
	s.save()
	s.reset("lower_3")
	assert_false(s.is_overridden("lower_3"))
	assert_eq(s.effective("lower_3"), s.default_settings("lower_3"))
	s.save()
	var raw: Dictionary = RPGJson.load_or(_ov_path(), {})
	assert_false(raw.tiles.has("lower_3"), "entry removed from the file")
	assert_true(raw.tiles.has("lower_4"), "other overrides stay")


func test_copy_to_many() -> void:
	var s := RPGTileSettings.open(data, "town")
	s.set_passage("lower_1", RPGTileSettings.DIR_DOWN | RPGTileSettings.DIR_UP)
	s.set_flag("lower_1", RPGTilesetBuilder.FLAG_BUSH, true)
	s.set_terrain("lower_1", 3)
	s.copy_to("lower_1", ["lower_2", "lower_3", "upper_9"])
	for k in ["lower_2", "lower_3", "upper_9"]:
		assert_eq(s.effective(k), s.effective("lower_1"), "copied to %s" % k)
	assert_eq(s.effective("lower_4"), s.default_settings("lower_4"), "others untouched")


func test_unknown_keys_survive() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/tileset_overrides")
	RPGJson.save_file(_ov_path(), {"schema_version": 1, "author_note": "keep me", "tiles": {
		"lower_5": {"passage": 0, "comment": "fence"},
		"lower_999": {"passage": 3},
	}})
	var s := RPGTileSettings.open(data, "town")
	assert_eq(s.get_value("lower_5", "passage"), 0)
	s.set_terrain("lower_6", 1)
	s.reset("lower_5")
	assert_eq(s.save(), OK)
	var raw: Dictionary = RPGJson.load_or(_ov_path(), {})
	assert_eq(raw.get("author_note"), "keep me", "top-level key kept")
	assert_eq(raw.tiles.get("lower_5"), {"comment": "fence"}, "unknown field kept after reset")
	assert_eq(raw.tiles.get("lower_999"), {"passage": 3}, "override for a missing tile kept")
	assert_eq(raw.tiles.lower_6.terrain, 1)


func test_dialog_builds_and_click_toggles() -> void:
	var host := Control.new()
	tree.root.add_child(host)
	var dlg := RPGTileSettingsDialog.open_for(data, "town", host)
	var got := []
	dlg.saved.connect(func(id: String) -> void: got.append(id))
	await frames(2)
	assert_eq(dlg.tileset_id, "town")
	assert_eq(dlg.tabs.tab_count, 4, "Autotiles, Lower, Upper, Animated")
	assert_eq(dlg.picker.item_count, 2)
	dlg.show_source(RPGTilesetBuilder.SOURCE_LOWER)
	assert_true(dlg.grid.custom_minimum_size.y > 0)
	# Passable on/off: a click in the middle of lower_8 blocks it.
	dlg.set_edit_mode("passable")
	_click(dlg, "lower_8", Vector2(0.5, 0.5))
	assert_eq(dlg.settings.get_value("lower_8", "passage"), 0, "click blocks the tile")
	# Passage (4-dir): clicking the top edge closes "up" only.
	dlg.set_edit_mode("passage4")
	_click(dlg, "lower_9", Vector2(0.5, 0.05))
	assert_eq(dlg.settings.get_value("lower_9", "passage"), 15 & ~RPGTileSettings.DIR_UP, "top edge toggles up")
	_click(dlg, "lower_9", Vector2(0.95, 0.5))
	assert_eq(dlg.settings.get_value("lower_9", "passage"), RPGTileSettings.DIR_DOWN | RPGTileSettings.DIR_LEFT, "right edge toggles right")
	# Flag mode and terrain mode.
	dlg.set_edit_mode("bush")
	_click(dlg, "lower_10", Vector2(0.5, 0.5))
	assert_true(dlg.settings.get_value("lower_10", "flags") & RPGTilesetBuilder.FLAG_BUSH != 0, "bush toggled on")
	dlg.set_edit_mode("terrain")
	dlg.terrain_spin.value = 5
	_click(dlg, "lower_11", Vector2(0.5, 0.5))
	assert_eq(dlg.settings.get_value("lower_11", "terrain"), 5)
	# Right-click resets.
	_click(dlg, "lower_8", Vector2(0.5, 0.5), MOUSE_BUTTON_RIGHT)
	assert_false(dlg.settings.is_overridden("lower_8"), "right-click resets")
	await frames(1)
	assert_true(dlg.status.text.contains("unsaved"), "status shows unsaved changes")
	assert_eq(dlg.save(), OK)
	assert_eq(got, ["town"], "saved signal")
	assert_eq(RPGTileSettings.open(data, "town").get_value("lower_11", "terrain"), 5, "written to disk")
	dlg.queue_free()
	host.queue_free()
	await frames(1)


## A sheet whose every 16 px quarter has its own colour (as tests/suites/test_profiles.gd).
func _sheet(w: int, h: int, tag: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for qy in h / 16:
		for qx in w / 16:
			img.fill_rect(Rect2i(qx * 16, qy * 16, 16, 16), Color8(qx * 4, qy * 4, tag))
	return img


## Adds the VX-layout tileset "world" (sheets A1 to A5, B and C; no D or E) to the test project.
func _add_vx_tileset() -> void:
	var dir := ROOT + "/tiles"
	DirAccess.make_dir_recursive_absolute(dir)
	var sizes := {"a1": Vector2i(512, 384), "a2": Vector2i(512, 384), "a3": Vector2i(512, 256), "a4": Vector2i(512, 480),
		"a5": Vector2i(256, 512), "b": Vector2i(512, 512), "c": Vector2i(512, 512)}
	var sheets := {}
	var tag := 10
	for k in sizes:
		var path := "%s/%s.png" % [dir, k]
		_sheet(sizes[k].x, sizes[k].y, tag).save_png(path)
		sheets[k] = path
		tag += 20
	var f: Dictionary = RPGJson.load_or(ROOT + "/database/tilesets.json", {})
	f.records.append({"id": "world", "name": "World", "profile": "vx", "sheets": sheets})
	RPGJson.save_file(ROOT + "/database/tilesets.json", f)
	data = RPGProjectData.open(ROOT)
	RPGMap.clear_tileset_cache()


## Issue #144: a VX / VX Ace / MV tileset has RPG Maker's tabs, A (A1 to A5), B, C, D, E, eight
## tiles wide, and every tile of every sheet is on one of them.
func test_vx_tileset_tabs_show_every_sheet() -> void:
	_add_vx_tileset()
	var s := RPGTileSettings.open(data, "world")
	assert_true(s.errors.is_empty(), "builds: %s" % str(s.errors))
	var layout := RPGTileSettingsDialog.tab_layout(s)
	assert_eq(int(layout.columns), 8, "VX sheets are eight tiles wide")
	assert_eq((layout.tabs as Array).map(func(t): return t.label), ["A", "B", "C"], "RPG Maker's tabs; no sheet D or E here")
	var a: Array = layout.tabs[0].cells
	assert_eq(a.size(), 16 + 32 + 32 + 48 + 128, "A1, A2, A3, A4 and A5, one under the other")
	assert_eq([a[0], a[15], a[16], a[47], a[48], a[80], a[127], a[128], a[255]],
		["a1_0", "a1_15", "a2_0", "a2_31", "a3_0", "a4_0", "a4_47", "a5_0", "a5_127"])
	var b: Array = layout.tabs[1].cells
	assert_eq(b.size(), 256)
	assert_eq([b[0], b[9], b[255]], ["b_0", "b_9", "b_255"], "each tile sits at its number")
	assert_eq(int(layout.tabs[1].source), RPGTilesheetVX.SOURCE_UPPER)
	assert_eq((layout.tabs[2].cells as Array)[3], "c_3", "sheet C has its own tab")
	# Nothing is left out: A2, A3 and A4 live in atlas sources the old fixed tab list never showed.
	var shown := {}
	for t in layout.tabs:
		for k in t.cells:
			if k != "":
				assert_false(shown.has(k), "%s is on one tab only" % k)
				shown[k] = true
	for k in s.all_keys():
		assert_true(shown.has(k), "%s is on a tab" % k)
	for src in [RPGTilesheetVX.SOURCE_A2, RPGTilesheetVX.SOURCE_A3, RPGTilesheetVX.SOURCE_A4]:
		assert_false(s.keys_for_source(src).is_empty(), "the tileset has tiles in source %d" % src)
	# A 2000/2003 ChipSet keeps its four tabs, six wide.
	var town := RPGTileSettingsDialog.tab_layout(RPGTileSettings.open(data, "town"))
	assert_eq(int(town.columns), 6)
	assert_eq((town.tabs as Array).map(func(t): return t.label), ["A: Autotiles", "B: Lower", "C: Upper", "Anim: Animated"])
	assert_eq(RPGTileSettingsDialog.tab_layout(null).tabs, [])
	assert_eq(RPGTileSettingsDialog.tile_label("a2_5"), "A2 autotile 5")
	assert_eq(RPGTileSettingsDialog.tile_label("b_12"), "B tile 12")


func _edit(dlg: RPGTileSettingsDialog, mode: String, key: String, uv := Vector2(0.5, 0.5)) -> void:
	assert_true(dlg.show_key(key), "%s has a tab" % key)
	dlg.set_edit_mode(mode)
	_click(dlg, key, uv)


## Issue #144: every flag can be set on A1 to A5 and B to E tiles, and the game's tileset gets them.
func test_vx_tiles_are_editable_in_the_dialog() -> void:
	_add_vx_tileset()
	var host := Control.new()
	tree.root.add_child(host)
	var dlg := RPGTileSettingsDialog.open_for(data, "world", host)
	await frames(2)
	var titles := []
	for i in dlg.tabs.tab_count:
		titles.append(dlg.tabs.get_tab_title(i))
	assert_eq(titles, ["A", "B", "C"])
	assert_eq(dlg.columns, 8)
	var c := float(dlg.cell_px())
	# The set-up the tutorials ask for: mountains and forests (A2) block, wall tops (A4) can be
	# walked on, the A2 tables are counters.
	assert_eq(dlg.settings.get_value("a2_5", "passage"), 15, "an A2 tile starts walkable")
	_edit(dlg, "passable", "a2_5")
	assert_eq(dlg.current_tab_label(), "A")
	assert_eq(dlg.settings.get_value("a2_5", "passage"), 0, "the mountain blocks")
	assert_eq(dlg.tile_rect("a2_5").position, Vector2(5, 2) * c, "a2_5 is in column 6 of the third row, as in RPG Maker")
	assert_eq(dlg.settings.get_value("a4_0", "passage"), 0, "an A4 wall top starts blocked")
	_edit(dlg, "passable", "a4_0")
	assert_eq(dlg.settings.get_value("a4_0", "passage"), 15, "the wall top is walkable")
	_edit(dlg, "counter", "a2_20")
	assert_true(dlg.settings.get_value("a2_20", "flags") & RPGTilesetBuilder.FLAG_COUNTER != 0, "counter on an A2 table")
	_edit(dlg, "bush", "a2_3")
	assert_true(dlg.settings.get_value("a2_3", "flags") & RPGTilesetBuilder.FLAG_BUSH != 0)
	_edit(dlg, "damage", "a1_4")
	assert_true(dlg.settings.get_value("a1_4", "flags") & RPGTilesetBuilder.FLAG_DAMAGE != 0)
	_edit(dlg, "ladder", "a3_2")
	assert_true(dlg.settings.get_value("a3_2", "flags") & RPGTilesetBuilder.FLAG_LADDER != 0)
	dlg.terrain_spin.value = 3
	_edit(dlg, "terrain", "a5_7")
	assert_eq(dlg.settings.get_value("a5_7", "terrain"), 3)
	# Sheets B and C are a tab each.
	var star_before: int = dlg.settings.get_value("b_9", "flags") & RPGTilesetBuilder.FLAG_STAR
	_edit(dlg, "star", "b_9")
	assert_eq(dlg.current_tab_label(), "B")
	assert_ne(dlg.settings.get_value("b_9", "flags") & RPGTilesetBuilder.FLAG_STAR, star_before, "star toggled on a B tile")
	assert_eq(dlg.tile_rect("b_9").position, Vector2(1, 1) * c)
	assert_eq(dlg.tile_rect("c_3").size.x, 0.0, "sheet C is not on tab B")
	assert_eq(dlg.key_at(Vector2(1.5, 1.5) * c), "b_9")
	assert_eq(dlg.key_at(Vector2(8.5, 0.5) * c), "", "nothing beyond the eighth column")
	var c3_before: int = dlg.settings.get_value("c_3", "passage")
	_edit(dlg, "passage4", "c_3", Vector2(0.5, 0.05))
	assert_eq(dlg.current_tab_label(), "C")
	assert_eq(dlg.settings.get_value("c_3", "passage"), c3_before ^ RPGTileSettings.DIR_UP, "the top edge toggles up on a C tile")
	assert_false(dlg.show_tab("D"), "no sheet D, no tab")
	assert_true(dlg.show_tab("A"))
	dlg.show_source(RPGTilesheetVX.SOURCE_A3)
	assert_eq(dlg.current_tab_label(), "A", "the A3 source is on tab A")
	dlg.show_source(RPGTilesheetVX.SOURCE_UPPER)
	assert_eq(dlg.current_tab_label(), "B")
	# Saved, and the TileSet the game builds has the changes.
	assert_eq(dlg.save(), OK)
	RPGMap.clear_tileset_cache()
	var ts: TileSet = RPGMap.tileset_for(data, "world")
	var td := func(key: String) -> TileData:
		var at: Dictionary = RPGTilesetBuilder.atlas_for_key(key, ts)
		return (ts.get_source(at.source) as TileSetAtlasSource).get_tile_data(at.coords, 0)
	assert_eq(int(td.call("a2_5").get_custom_data("passage")), 0, "the mountain blocks in the game")
	assert_eq(int(td.call("a2_6").get_custom_data("passage")), 15, "its neighbour is untouched")
	assert_eq(int(td.call("a4_0").get_custom_data("passage")), 15, "the wall top is walkable in the game")
	assert_true(int(td.call("a2_20").get_custom_data("flags")) & RPGTilesetBuilder.FLAG_COUNTER != 0, "the table is a counter in the game")
	assert_eq(int(td.call("a5_7").get_custom_data("terrain")), 3)
	# Switching to the 2000/2003 tileset brings its own tabs back.
	dlg.load_tileset("town")
	assert_eq(dlg.tabs.tab_count, 4)
	assert_eq(dlg.columns, 6)
	dlg.queue_free()
	host.queue_free()
	await frames(1)


func _click(dlg: RPGTileSettingsDialog, key: String, uv: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var r := dlg.tile_rect(key)
	assert_true(r.size.x > 0, "%s is on the current tab" % key)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = r.position + r.size * uv
	dlg.grid.gui_input.emit(ev)
