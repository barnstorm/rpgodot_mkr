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


func _click(dlg: RPGTileSettingsDialog, key: String, uv: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var r := dlg.tile_rect(key)
	assert_true(r.size.x > 0, "%s is on the current tab" % key)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = r.position + r.size * uv
	dlg.grid.gui_input.emit(ev)
