@tool
extends RefCounted
## Creates an independent Godot project, without copying the current game's data or settings.

const KIT_FOLDERS := ["addons/rpg", "addons/rpg_database", "assets/starter"]


static func destination_error(folder: String, game_name: String) -> String:
	if game_name.strip_edges().is_empty():
		return "Give your game a name first."
	if folder.strip_edges().is_empty():
		return "Choose an empty folder for the new project."
	var path := ProjectSettings.globalize_path(folder.strip_edges()).replace("\\", "/").simplify_path()
	if not path.is_absolute_path():
		return "Choose an absolute folder path."
	var source := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	var compare := path.trim_suffix("/")
	if OS.get_name() == "Windows":
		source = source.to_lower()
		compare = compare.to_lower()
	if compare == source or compare.begins_with(source + "/"):
		return "Choose a folder outside the current Godot project."
	if FileAccess.file_exists(path):
		return "That path is a file. Choose an empty folder."
	if DirAccess.dir_exists_absolute(path):
		var dir := DirAccess.open(path)
		if dir == null:
			return "Cannot read that folder."
		dir.include_hidden = true
		if not dir.get_files().is_empty() or not dir.get_directories().is_empty():
			return "That folder is not empty. Choose a new or empty folder."
	return ""


## Returns {error, messages, folder}. A project.godot is written only after the kit and data exist.
static func create(folder: String, game_name: String, style := "rm2k") -> Dictionary:
	var message := destination_error(folder, game_name)
	if message != "":
		return {"error": ERR_INVALID_PARAMETER, "messages": [message], "folder": folder}
	var target := ProjectSettings.globalize_path(folder.strip_edges()).replace("\\", "/").simplify_path()
	var result := {"error": OK, "messages": [], "folder": target}
	var err := DirAccess.make_dir_recursive_absolute(target)
	if err != OK:
		return _failed(result, err, "Cannot create the project folder.")
	for sub in KIT_FOLDERS:
		# The starter pack is optional when the addon was installed on its own.
		if sub == "assets/starter" and not DirAccess.dir_exists_absolute("res://" + sub):
			continue
		err = _copy_folder("res://" + sub, target.path_join(sub))
		if err != OK:
			return _failed(result, err, "Cannot copy %s into the new project." % sub)
	for file in ["LICENSE", "LICENSE-ASSETS.md"]:
		if FileAccess.file_exists("res://" + file):
			err = DirAccess.copy_absolute(ProjectSettings.globalize_path("res://" + file), target.path_join(file))
			if err != OK:
				return _failed(result, err, "Cannot copy %s." % file)
	var root := target.path_join("rpg")
	var made := RPGProjectTemplate.create(root, game_name.strip_edges(), target.path_join("extensions"), style)
	if made.error != OK:
		return _failed(result, made.error, " ".join(PackedStringArray(made.messages)))
	result.messages.append_array(made.messages)
	# Creation happens in this editor, but the saved references must belong to the NEW res://.
	var index: Dictionary = RPGJson.load_or(root.path_join("map_index.json"), {})
	for map in index.get("maps", []):
		for key in ["scene", "properties", "events"]:
			map[key] = "res://" + str(map[key]).trim_prefix(target + "/")
	err = RPGJson.save_file(root.path_join("map_index.json"), index)
	if err != OK:
		return _failed(result, err, "Cannot save the new map index.")
	var project: Dictionary = RPGJson.load_or(root.path_join("project.json"), {})
	project.erase("extensions_root")
	err = RPGJson.save_file(root.path_join("project.json"), project)
	if err != OK:
		return _failed(result, err, "Cannot save the new RPG project.")
	var config := _config(game_name.strip_edges(), made.screen)
	err = config.save(target.path_join("project.godot"))
	if err != OK:
		return _failed(result, err, "Cannot save project.godot.")
	return result


static func _failed(result: Dictionary, error: int, message: String) -> Dictionary:
	result.error = error
	result.messages.append("%s (error %d). Any files already created are in %s." % [message.trim_suffix("."), error, result.folder])
	return result


static func _copy_folder(source: String, target: String) -> Error:
	var dir := DirAccess.open(source)
	if dir == null:
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.make_dir_recursive_absolute(target)
	if err != OK:
		return err
	for file in dir.get_files():
		# Godot rebuilds import metadata for the new project.
		if file.ends_with(".import") or file.ends_with(".tmp") or dir.is_link(file):
			continue
		err = DirAccess.copy_absolute(ProjectSettings.globalize_path(source.path_join(file)), target.path_join(file))
		if err != OK:
			return err
	for sub in dir.get_directories():
		if sub.begins_with(".") or dir.is_link(sub):
			continue
		err = _copy_folder(source.path_join(sub), target.path_join(sub))
		if err != OK:
			return err
	return OK


static func _config(game_name: String, screen: Vector2i) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("", "config_version", 5)
	config.set_value("application", "config/name", game_name)
	config.set_value("application", "run/main_scene", "res://addons/rpg/runtime/game.tscn")
	config.set_value("application", "config/features", PackedStringArray(["4.5", "GL Compatibility"]))
	config.set_value("autoload", "RPG", "*res://addons/rpg/runtime/rpg_service.gd")
	config.set_value("editor_plugins", "enabled", PackedStringArray(["res://addons/rpg/plugin.cfg", "res://addons/rpg_database/plugin.cfg"]))
	config.set_value("display", "window/size/viewport_width", screen.x)
	config.set_value("display", "window/size/viewport_height", screen.y)
	var scale := 3 if screen.x <= 320 else 2 if screen.x <= 544 else 1
	config.set_value("display", "window/size/window_width_override", screen.x * scale)
	config.set_value("display", "window/size/window_height_override", screen.y * scale)
	config.set_value("display", "window/stretch/mode", "canvas_items")
	config.set_value("display", "window/stretch/scale_mode", "fractional")
	config.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
	config.set_value("rendering", "renderer/rendering_method.mobile", "gl_compatibility")
	config.set_value("rendering", "textures/canvas_textures/default_texture_filter", 0)
	config.set_value("rendering", "2d/snap/snap_2d_transforms_to_pixel", true)
	config.set_value("rendering", "2d/snap/snap_2d_vertices_to_pixel", true)
	return config
