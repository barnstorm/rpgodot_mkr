@tool
class_name RPGProjectTemplate
extends RefCounted
## "New project" (spec: Milestones 9, Project menu): creates a working rpg/ folder in a project that
## has none, with a starter database, the Classic rules, one grass map with a start position, and the
## automatic `project` extension. Uses only files shipped in the addon, plus the starter asset pack
## when it is present (otherwise maps show placeholders until a ChipSet is imported).

const TEMPLATE_DIR := "res://addons/rpg/templates/new_project"
const STARTER_CHIPSET := "res://assets/starter/ChipSet/town.png"
## Project styles: the asset profile (how imported RPG Maker sheets are cut) and the game screen.
const STYLES := {
	"rm2k": {"name": "RPG Maker 2000 / 2003", "tile_size": 16, "screen": Vector2i(320, 240)},
	"vx": {"name": "RPG Maker VX / VX Ace", "tile_size": 32, "screen": Vector2i(544, 416)},
	"mv": {"name": "RPG Maker MV", "tile_size": 48, "screen": Vector2i(816, 624)},
}


## Creates the project. Refuses (ERR_ALREADY_EXISTS) when `root`/project.json exists.
## `style` is a STYLES key. Returns {error: Error, root, map, screen: Vector2i, messages: [String]};
## the caller applies `screen` to the Godot project's viewport size.
static func create(root := "res://rpg", game_name := "My Game", extensions_root := "res://extensions", style := "rm2k") -> Dictionary:
	if not STYLES.has(style):
		style = "rm2k"
	var out := {"error": OK, "root": root, "map": "start", "messages": [], "screen": STYLES[style].screen}
	if FileAccess.file_exists(root.path_join("project.json")):
		out.error = ERR_ALREADY_EXISTS
		out.messages.append("%s already holds a project." % root)
		return out
	for sub in ["", "database", "maps"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(sub))
	var pid := RPGIds.slug(game_name)
	if not RPGIds.is_valid(pid):
		pid = "my_game"
	var files := {
		"project.json": {"schema_version": 1, "project_id": pid, "name": game_name, "extensions": ["project"], "disabled_extensions": [],
			"rules": "classic", "scenes": {}, "sound_roles": {}, "custom_fields": {}},
		"profile.json": {"schema_version": 1, "profile": style, "tile_size": STYLES[style].tile_size},
		"state.json": {"schema_version": 1, "switches": [], "variables": []},
		"common_events.json": {"schema_version": 1, "common_events": []},
		"map_index.json": {"schema_version": 1, "maps": []},
	}
	for f in files:
		var err := RPGJson.save_file(root.path_join(f), files[f])
		if err != OK:
			out.error = err
			out.messages.append("Could not write %s (error %d)." % [f, err])
			return out
	# Starter database (the Classic rule system's records: hero, classes, skills, items, enemies...).
	var d := DirAccess.open(TEMPLATE_DIR.path_join("database"))
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				var r := RPGJson.parse_file(TEMPLATE_DIR.path_join("database").path_join(f))
				if r.ok:
					RPGJson.save_file(root.path_join("database").path_join(f), r.data)
	var sys_path := root.path_join("database/system.json")
	var sys: Dictionary = RPGJson.load_or(sys_path, {"schema_version": 1, "system": {}})
	if sys.get("system") is Dictionary:
		sys.system["title"] = game_name
		RPGJson.save_file(sys_path, sys)
	if not FileAccess.file_exists(STARTER_CHIPSET):
		out.messages.append("The starter asset pack is not installed: import a ChipSet and set it in Database > Tilesets.")
	# The automatic `project` extension (spec: each project has one).
	var ext_manifest := extensions_root.path_join("project/manifest.json")
	if not FileAccess.file_exists(ext_manifest):
		DirAccess.make_dir_recursive_absolute(extensions_root.path_join("project/commands"))
		RPGJson.save_file(ext_manifest, {"schema_version": 1, "id": "project", "name": "%s project code" % game_name, "version": "1.0.0",
			"api_versions": [1], "dependencies": [], "entry_scripts": [], "error_policy": "fail_event", "requires_capabilities": [],
			"settings_schema": {}, "commands": []})
	if extensions_root != "res://extensions":
		var pj: Dictionary = RPGJson.load_or(root.path_join("project.json"), {})
		pj["extensions_root"] = extensions_root
		RPGJson.save_file(root.path_join("project.json"), pj)
	# First map: grass with a tree border, and the start position in the middle.
	var data := RPGProjectData.open(root)
	var tileset := "town"
	var err2 := RPGMapFiles.create_map(data, "start", "Start", tileset, 20, 15)
	if err2 != OK:
		out.error = err2
		out.messages.append("Could not create the first map (error %d)." % err2)
		return out
	data.reload()
	var node := RPGMapFiles.load_map(data, "start")
	if node != null:
		_paint_start_map(node, Vector2i(20, 15))
		RPGMapFiles.save_scene(node, data.map_scene_path("start"))
		node.free()
	return out


static func _paint_start_map(node: RPGMap, size: Vector2i) -> void:
	for c in node.get_children():
		if c is TileMapLayer:
			c.set_meta(RPGAutotile.MAP_SIZE_META, size)
	var grass: Dictionary = RPGTilesetBuilder.atlas_for_key("terrain_0")
	if grass.is_empty():
		return
	var cells := []
	for y in size.y:
		for x in size.x:
			cells.append(Vector2i(x, y))
	RPGAutotile.paint_cells(node.tile_layers[0], cells, grass.source, grass.coords)
	var tree: Dictionary = RPGTilesetBuilder.atlas_for_key("upper_1")
	var trunk: Dictionary = RPGTilesetBuilder.atlas_for_key("upper_7")
	if tree.is_empty() or trunk.is_empty():
		return
	var layer: TileMapLayer = node.tile_layers[RPGTilesetBuilder.default_layer_for(tree.source) - 1]
	for x in range(0, size.x, 2):
		layer.set_cell(Vector2i(x, 0), tree.source, tree.coords)
		layer.set_cell(Vector2i(x, 1), trunk.source, trunk.coords)
