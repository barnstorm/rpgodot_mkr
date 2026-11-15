extends "res://tests/rpg_test_case.gd"

const NewProject := preload("res://addons/rpg/editor/project/rpg_new_project.gd")
const ROOT := "user://new_project_menu_test"


func before_each() -> void:
	_remove_test_folder(ROOT)


func after_each() -> void:
	_remove_test_folder(ROOT)


func test_new_project_menu_opens_a_dialog_with_an_existing_game() -> void:
	var screen := RPGMainScreen.new()
	screen.setup(null)
	tree.root.add_child(screen)
	await frames(2)
	var current_root := screen.data.root
	var current_map := screen.current_map
	var original := FileAccess.get_file_as_string("res://rpg/project.json")
	# Use the same signal as selecting the menu item, rather than calling the dialog directly.
	screen._menus.Project.id_pressed.emit(RPGMainScreen.M_NEW_PROJECT)
	await frames(1)
	var dialog: ConfirmationDialog
	for child in screen.get_children():
		if child is ConfirmationDialog and child.title == "New RPG project":
			dialog = child
	assert_true(dialog != null, "New project opens a visible dialog even with the sample loaded")
	if dialog != null:
		assert_true(dialog.visible)
		assert_true(dialog.size.y < 600, "the project form fits on screen: %s" % dialog.size)
		dialog.folder_edit.text = ProjectSettings.globalize_path(ROOT)
		dialog.name_edit.text = "Moon Quest"
		dialog.style_pick.select(1)
		dialog.open_check.button_pressed = false
		dialog.confirmed.emit()
		assert_true(FileAccess.file_exists(ROOT + "/project.godot"), dialog.message.text)
		assert_true(screen.status.text.contains("Created"), screen.status.text)
	assert_eq(screen.data.root, current_root, "the open project's data is kept")
	assert_eq(screen.current_map, current_map, "the open map is kept")
	assert_eq(FileAccess.get_file_as_string("res://rpg/project.json"), original)
	screen.free()


func test_generated_project_has_portable_paths_and_its_own_settings() -> void:
	var original := FileAccess.get_file_as_string("res://project.godot")
	var result := NewProject.create(ROOT, "Moon Quest", "vx")
	assert_eq(result.error, OK, str(result.messages))
	var config := ConfigFile.new()
	assert_eq(config.load(ROOT + "/project.godot"), OK)
	assert_eq(config.get_value("application", "config/name"), "Moon Quest")
	assert_eq(config.get_value("display", "window/size/viewport_width"), 544)
	assert_eq(config.get_value("display", "window/size/viewport_height"), 416)
	assert_eq(config.get_value("application", "run/main_scene"), "res://addons/rpg/runtime/game.tscn")
	assert_eq(config.get_value("autoload", "RPG"), "*res://addons/rpg/runtime/rpg_service.gd")
	assert_eq(config.get_value("editor_plugins", "enabled").size(), 2)
	var data := RPGProjectData.open(ROOT + "/rpg")
	assert_eq(data.project.name, "Moon Quest")
	assert_eq(data.profile.profile, "vx")
	assert_false(data.project.has("extensions_root"), "extensions use the new project's default folder")
	assert_eq(data.maps.keys(), ["start"], "sample maps are not copied")
	assert_eq(data.map_scene_path("start"), "res://rpg/maps/start.tscn")
	assert_eq(data.map_entry("start").properties, "res://rpg/maps/start.map.json")
	assert_eq(data.map_entry("start").events, "res://rpg/maps/start.events.json")
	for path in ["addons/rpg/plugin.cfg", "addons/rpg/runtime/game.tscn", "addons/rpg_database/plugin.cfg", "assets/starter/ChipSet/town.png", "extensions/project/manifest.json"]:
		assert_true(FileAccess.file_exists(ROOT.path_join(path)), path)
	assert_false(DirAccess.dir_exists_absolute(ROOT + "/.godot"), "generated caches are not copied")
	assert_false(DirAccess.dir_exists_absolute(ROOT + "/tests"), "development files are not copied")
	assert_eq(FileAccess.get_file_as_string("res://project.godot"), original, "current settings are untouched")


func test_nonempty_destinations_and_invalid_inputs_are_refused() -> void:
	assert_true(NewProject.destination_error(ROOT, "  ") != "")
	assert_true(NewProject.destination_error("", "Quest") != "")
	assert_true(NewProject.destination_error("relative/folder", "Quest") != "")
	assert_true(NewProject.destination_error("res://", "Quest") != "")
	assert_true(NewProject.destination_error("res://nested_project", "Quest") != "")
	DirAccess.make_dir_recursive_absolute(ROOT)
	var file := FileAccess.open(ROOT + "/.keep", FileAccess.WRITE)
	file.store_string("keep me")
	file.close()
	var result := NewProject.create(ROOT, "Quest")
	assert_ne(result.error, OK)
	assert_eq(FileAccess.get_file_as_string(ROOT + "/.keep"), "keep me")
	assert_false(FileAccess.file_exists(ROOT + "/project.godot"))
	DirAccess.remove_absolute(ROOT + "/.keep")
	DirAccess.make_dir_recursive_absolute(ROOT + "/empty_subfolder")
	assert_ne(NewProject.create(ROOT, "Quest").error, OK, "folders count as occupied too")


func _remove_test_folder(path: String) -> void:
	# Only delete within this suite's fixed user-data folder.
	assert_true(path == ROOT or path.begins_with(ROOT + "/"))
	if path != ROOT and not path.begins_with(ROOT + "/"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_test_folder(path.path_join(sub))
	DirAccess.remove_absolute(path)
