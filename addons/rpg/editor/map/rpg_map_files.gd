@tool
class_name RPGMapFiles
extends RefCounted
## File operations for maps, shared by the map editor and headless tools (no EditorInterface).
## A map is three files plus an index entry:
##   rpg/maps/<id>.tscn        painted cells (Layer1..Layer4, Regions, Shadows) + any Godot nodes
##   rpg/maps/<id>.map.json    properties
##   rpg/maps/<id>.events.json events
## Map scenes are saved WITHOUT TileSets: they are generated caches assigned on load.
## Image-backed maps (RPGImageMap) add a Navigation layer to the scene and an "image_map" block to
## the properties; their image sprites are built on load and never saved.

const LAYER_NAMES := ["Layer1", "Layer2", "Layer3", "Layer4"]
const MAP_SCRIPT := "res://addons/rpg/runtime/rpg_map.gd"


static func maps_dir(data: RPGProjectData) -> String:
	return data.root.path_join("maps")


static func default_props(id: String, display_name: String, tileset: String, w: int, h: int) -> Dictionary:
	return {
		"schema_version": 1,
		"id": id,
		"display_name": display_name,
		"tileset": tileset,
		"width": w,
		"height": h,
		"scroll": "none",
		"music": null,
		"bgs": null,
		"battle_background": "auto",
		"disable_dash": false,
		"parallax": null,
		"encounters": {"steps": 30, "groups": []},
		"notes": "",
		"custom": {},
	}


## Builds an empty map node tree (not saved).
static func new_map_node(id: String, layer_count := 4) -> RPGMap:
	var root := RPGMap.new()
	root.name = id.to_pascal_case() if id != "" else "Map"
	root.map_id = id
	for i in layer_count:
		var l := TileMapLayer.new()
		l.name = LAYER_NAMES[i]
		root.add_child(l)
		l.owner = root
	var shadows := TileMapLayer.new()
	shadows.name = "Shadows"
	shadows.modulate = Color(1, 1, 1, 1)
	root.add_child(shadows)
	shadows.owner = root
	# Draw the shadows between the lower and upper layers.
	root.move_child(shadows, 1)
	var regions := TileMapLayer.new()
	regions.name = "Regions"
	regions.z_index = 80
	root.add_child(regions)
	regions.owner = root
	return root


## Creates a new map: scene, properties, empty events, index entry. Returns OK or an error code.
## `image`: for an image-backed map, {image_map: block, walkable: bool}; the scene then gets a
## Navigation layer, every cell walkable or (walkable false) blocked, and the map does not loop.
static func create_map(data: RPGProjectData, id: String, display_name: String, tileset: String, w: int, h: int, parent := "", image := {}) -> Error:
	if not RPGIds.is_valid(id) or data.maps.has(id):
		return ERR_ALREADY_EXISTS
	var dir := maps_dir(data)
	DirAccess.make_dir_recursive_absolute(dir)
	var node := new_map_node(id)
	if not image.is_empty():
		node.ensure_navigation_layer()
		if bool(image.get("walkable", false)):
			for y in h:
				for x in w:
					node.set_navigation_mask(Vector2i(x, y), 15)
	var scene_path := dir.path_join(id + ".tscn")
	var err := save_scene(node, scene_path)
	node.free()
	if err != OK:
		return err
	var props := default_props(id, display_name, tileset, w, h)
	if not image.is_empty():
		props[RPGImageMap.KEY] = image.get("image_map", {})
		props["scroll"] = "none"
	err = RPGJson.save_file(dir.path_join(id + ".map.json"), props)
	if err != OK:
		return err
	err = RPGJson.save_file(dir.path_join(id + ".events.json"), {"schema_version": 1, "map": id, "events": []})
	if err != OK:
		return err
	var index: Dictionary = data.map_index.duplicate(true)
	if not index.has("maps"):
		index["maps"] = []
	var order := 0
	for m in index.maps:
		if str(m.get("parent", "")) == parent:
			order = maxi(order, int(m.get("order", 0)) + 1)
	index.maps.append({
		"id": id, "name": display_name if display_name != "" else id, "parent": parent, "order": order,
		"scene": scene_path, "properties": dir.path_join(id + ".map.json"), "events": dir.path_join(id + ".events.json"),
	})
	if not index.has("schema_version"):
		index["schema_version"] = 1
	err = RPGJson.save_file(data.root.path_join("map_index.json"), index)
	data.reload()
	return err


## New image-backed map from a base image: checks the image against the map tile size and sizes
## the map from it. Writes nothing when the check fails. Returns {error: Error, message, cells}.
static func create_image_map(data: RPGProjectData, id: String, display_name: String, tileset: String, base: String, foreground := "", walkable := false, parent := "") -> Dictionary:
	var tile := RPGImageMap.tile_size_for_tileset(data, tileset)
	var chk := RPGImageMap.check_image(base, tile)
	if not chk.ok:
		return {"error": ERR_INVALID_DATA, "message": chk.error, "cells": Vector2i.ZERO}
	if foreground != "":
		var fr := RPGImageMap.read_size(foreground)
		if not fr.ok:
			return {"error": ERR_INVALID_DATA, "message": fr.error, "cells": Vector2i.ZERO}
		var mm := RPGImageMap.foreground_mismatch(chk.size, fr.size)
		if mm != "":
			return {"error": ERR_INVALID_DATA, "message": mm, "cells": Vector2i.ZERO}
	var err := create_map(data, id, display_name, tileset, chk.cells.x, chk.cells.y, parent, {"image_map": RPGImageMap.make_block(base, foreground), "walkable": walkable})
	return {"error": err, "message": "" if err == OK else "Could not create map '%s' (error %d)." % [id, err], "cells": chk.cells}


## Adds a Navigation layer to an open map that has none (a tile map given a base image), copying
## today's tile passability into it so movement stays exactly as it was. Returns the layer.
static func ensure_navigation(map_node: RPGMap, size: Vector2i) -> TileMapLayer:
	if map_node.navigation != null and is_instance_valid(map_node.navigation):
		return map_node.navigation
	var mv := RPGMovement.new(map_node)
	map_node.size = size
	var bits := {}
	for y in size.y:
		for x in size.x:
			bits[Vector2i(x, y)] = mv.passage(Vector2i(x, y))
	var nav := map_node.ensure_navigation_layer()
	for c in bits:
		map_node.set_navigation_mask(c, bits[c])
	return nav


## Copies a map's scene, properties and events files into rpg/.backup/map_<id>_<time>/ (before a
## size change that cannot be undone). Returns the folder, or "" on failure.
static func backup_map(data: RPGProjectData, id: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var dir := data.root.path_join(".backup/map_%s_%s_%d" % [id, stamp, Time.get_ticks_msec() % 1000])
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var e: Dictionary = data.map_entry(id)
	for key in ["scene", "properties", "events"]:
		var p := str(e.get(key, ""))
		if p != "" and FileAccess.file_exists(p):
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(dir.path_join(p.get_file()))) != OK:
				return ""
	return dir


## Saves a map node as a scene without its TileSets (they are caches).
static func save_scene(map_node: Node, path: String) -> Error:
	var saved_sets := {}
	for c in map_node.get_children():
		if c is TileMapLayer:
			saved_sets[c] = c.tile_set
			c.tile_set = null
	var packed := PackedScene.new()
	var err := packed.pack(map_node)
	for c in saved_sets:
		c.tile_set = saved_sets[c]
	if err != OK:
		return err
	return ResourceSaver.save(packed, path)


## Loads a map scene for editing, with TileSets assigned. Returns null if missing.
static func load_map(data: RPGProjectData, id: String) -> RPGMap:
	var path: String = data.map_scene_path(id)
	var node: RPGMap
	if ResourceLoader.exists(path):
		var packed: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		var inst := packed.instantiate() if packed else null
		if inst is RPGMap:
			node = inst
		elif inst != null:
			inst.free()
	if node == null:
		node = new_map_node(id)
	node.map_id = id
	node.assign_tilesets(data)
	for w in node.apply_image_map(data.map_props(id)):
		push_warning("RPG map '%s': %s" % [id, w])
	return node


static func save_props(data: RPGProjectData, id: String, props: Dictionary) -> Error:
	var e: Dictionary = data.map_entry(id)
	var path: String = e.get("properties", maps_dir(data).path_join(id + ".map.json"))
	var err := RPGJson.save_file(path, props)
	data.invalidate_map(id)
	return err


static func load_events_file(data: RPGProjectData, id: String) -> Dictionary:
	var e: Dictionary = data.map_entry(id)
	var path: String = e.get("events", maps_dir(data).path_join(id + ".events.json"))
	var d: Variant = RPGJson.load_or(path, {})
	if not (d is Dictionary) or d.is_empty():
		d = {"schema_version": 1, "map": id, "events": []}
	return d


static func save_events_file(data: RPGProjectData, id: String, file: Dictionary) -> Error:
	var e: Dictionary = data.map_entry(id)
	var path: String = e.get("events", maps_dir(data).path_join(id + ".events.json"))
	var err := RPGJson.save_file(path, file)
	data.invalidate_map(id)
	return err


static func save_index(data: RPGProjectData, index: Dictionary) -> Error:
	var err := RPGJson.save_file(data.root.path_join("map_index.json"), index)
	data.reload()
	return err


## Deletes a map's files and its index entry (children move up to the parent).
static func delete_map(data: RPGProjectData, id: String) -> Error:
	var e: Dictionary = data.map_entry(id)
	if e.is_empty():
		return ERR_DOES_NOT_EXIST
	for key in ["scene", "properties", "events"]:
		var p: String = e.get(key, "")
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var index: Dictionary = data.map_index.duplicate(true)
	var keep := []
	for m in index.get("maps", []):
		if m.id == id:
			continue
		if str(m.get("parent", "")) == id:
			m["parent"] = e.get("parent", "")
		keep.append(m)
	index["maps"] = keep
	index["favourites"] = index.get("favourites", []).filter(func(f): return f != id)
	return save_index(data, index)


## Copies a map (scene, properties and events) under a new unique ID.
static func copy_map(data: RPGProjectData, id: String) -> String:
	var e: Dictionary = data.map_entry(id)
	if e.is_empty():
		return ""
	var new_id := RPGIds.unique(id + "_copy", data.maps)
	var props: Dictionary = data.map_props(id).duplicate(true)
	props["id"] = new_id
	if create_map(data, new_id, str(e.get("name", id)) + " (copy)", str(props.get("tileset", "")), int(props.get("width", 20)), int(props.get("height", 15)), str(e.get("parent", ""))) != OK:
		return ""
	var node := load_map(data, id)
	node.map_id = new_id
	save_scene(node, maps_dir(data).path_join(new_id + ".tscn"))
	node.free()
	save_props(data, new_id, props)
	var ev: Dictionary = load_events_file(data, id).duplicate(true)
	ev["map"] = new_id
	save_events_file(data, new_id, ev)
	return new_id


## RPG Maker's "Shift": moves everything on the map (all tile layers, shadows, regions and
## events) by `offset` tiles. Contents wrap around the edges, so nothing is lost. Returns the
## updated events file (the caller saves it with the scene).
static func shift_contents(data: RPGProjectData, map_node: RPGMap, offset: Vector2i) -> Dictionary:
	var props: Dictionary = data.map_props(map_node.map_id)
	var size := Vector2i(int(props.get("width", 20)), int(props.get("height", 15)))
	var wrap := func(c: Vector2i) -> Vector2i:
		return Vector2i(posmod(c.x + offset.x, size.x), posmod(c.y + offset.y, size.y))
	for layer in map_node.get_children():
		if not (layer is TileMapLayer):
			continue
		var cells := []
		for c in layer.get_used_cells():
			cells.append([c, layer.get_cell_source_id(c), layer.get_cell_atlas_coords(c), layer.get_cell_alternative_tile(c)])
		layer.clear()
		for e in cells:
			layer.set_cell(wrap.call(e[0]), e[1], e[2], e[3])
		if layer.has_meta(RPGAutotile.FIXED_META):
			var moved := {}
			for c in layer.get_meta(RPGAutotile.FIXED_META):
				moved[wrap.call(c)] = true
			layer.set_meta(RPGAutotile.FIXED_META, moved)
	# Autotiles along the wrap seam now touch different neighbours.
	for l in map_node.tile_layers:
		RPGAutotile.refresh_rect(l, Rect2i(Vector2i.ZERO, size))
	var ev_file := load_events_file(data, map_node.map_id)
	for ev in ev_file.get("events", []):
		var p: Array = ev.get("position", [0, 0])
		var np: Vector2i = wrap.call(Vector2i(int(p[0]), int(p[1])))
		ev["position"] = [np.x, np.y]
	return ev_file


const SAMPLE_MAPS_DIR := "res://addons/rpg/templates/sample_maps"


## Sample maps shipped with the addon (RPG Maker's "Load sample map"): [{id, name}].
static func sample_maps() -> Array:
	var out := []
	var idx: Dictionary = RPGJson.load_or(SAMPLE_MAPS_DIR.path_join("index.json"), {})
	for m in idx.get("maps", []):
		out.append(m)
	return out


## Copies a sample map into the project as a new map (tiles only, no events). Returns its ID.
static func load_sample_map(data: RPGProjectData, sample_id: String, parent := "") -> String:
	var src_props: Dictionary = RPGJson.load_or(SAMPLE_MAPS_DIR.path_join(sample_id + ".map.json"), {})
	var src_scene := SAMPLE_MAPS_DIR.path_join(sample_id + ".tscn")
	if src_props.is_empty() or not ResourceLoader.exists(src_scene):
		return ""
	var tileset := str(src_props.get("tileset", ""))
	if tileset != "" and not data.has_record("tilesets", tileset):
		var all: Array = data.records("tilesets")
		tileset = str(all[0].get("id", "")) if not all.is_empty() else ""
	var new_id := RPGIds.unique(sample_id, data.maps)
	var name := str(src_props.get("display_name", sample_id))
	if create_map(data, new_id, name if name != "" else sample_id, tileset, int(src_props.get("width", 20)), int(src_props.get("height", 15)), parent) != OK:
		return ""
	var packed: PackedScene = load(src_scene)
	var node: Node = packed.instantiate()
	node.set("map_id", new_id)
	save_scene(node, maps_dir(data).path_join(new_id + ".tscn"))
	node.free()
	var props := data.map_props(new_id).duplicate(true)
	for k in ["width", "height", "scroll", "music", "bgs", "battle_background", "parallax", "display_name"]:
		if src_props.has(k):
			props[k] = src_props[k]
	props["tileset"] = tileset
	save_props(data, new_id, props)
	return new_id


## Resizes a map: cells and events outside the new size are removed (the caller warns first).
static func resize(data: RPGProjectData, map_node: RPGMap, w: int, h: int) -> Dictionary:
	var removed_cells := 0
	for c in map_node.get_children():
		if c is TileMapLayer:
			for cell in c.get_used_cells():
				if cell.x >= w or cell.y >= h:
					c.erase_cell(cell)
					removed_cells += 1
	var ev_file := load_events_file(data, map_node.map_id)
	var kept := []
	var removed_events := []
	for ev in ev_file.get("events", []):
		var p: Array = ev.get("position", [0, 0])
		if int(p[0]) < w and int(p[1]) < h:
			kept.append(ev)
		else:
			removed_events.append(ev.get("id", ""))
	ev_file["events"] = kept
	return {"removed_cells": removed_cells, "removed_events": removed_events, "events_file": ev_file}
