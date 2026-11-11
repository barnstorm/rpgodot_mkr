@tool
class_name RPGProjectData
extends RefCounted
## Loads every authored file under rpg/ into registries keyed by stable ID.
## Shared by the editor and the runtime; holds definitions only, never playthrough state.

const DB_TYPES := ["actors", "classes", "skills", "items", "weapons", "armors", "enemies", "troops", "states", "animations", "tilesets", "types", "terms"]
## Database types added by extensions (manifest "database_types", see add_db_types): loaded
## from database/<type>.json like the built-in ones, also by reload().
var extra_types: Array = []

var root := "res://rpg"
var project: Dictionary = {}
var profile: Dictionary = {}
var state_defs: Dictionary = {}
var map_index: Dictionary = {}
var common_events_file: Dictionary = {}
var system: Dictionary = {}
## type -> {"records": Array, "by_id": Dictionary}
var db: Dictionary = {}
## map id -> map index entry
var maps: Dictionary = {}
## switch id -> definition, variable id -> definition
var switches: Dictionary = {}
var variables: Dictionary = {}
var common_events: Dictionary = {}
var load_errors: Array = []

var _props_cache: Dictionary = {}
var _events_cache: Dictionary = {}


static func open(p_root := "res://rpg") -> RPGProjectData:
	var d := RPGProjectData.new()
	d.root = p_root
	d.reload()
	return d


func reload() -> void:
	load_errors.clear()
	_props_cache.clear()
	_events_cache.clear()
	project = _load("project.json", {"schema_version": 1, "project_id": "untitled", "name": "Untitled"})
	profile = _load("profile.json", {"schema_version": 1, "profile": "rm2k", "tile_size": 16})
	state_defs = _load("state.json", {"schema_version": 1, "switches": [], "variables": []})
	map_index = _load("map_index.json", {"schema_version": 1, "maps": []})
	common_events_file = _load("common_events.json", {"schema_version": 1, "common_events": []})
	var sys_file: Dictionary = _load("database/system.json", {"schema_version": 1, "system": {}})
	system = sys_file.get("system", {})
	switches.clear()
	for s in state_defs.get("switches", []):
		switches[s.id] = s
	variables.clear()
	for v in state_defs.get("variables", []):
		variables[v.id] = v
	maps.clear()
	for m in map_index.get("maps", []):
		maps[m.id] = m
	common_events.clear()
	for c in common_events_file.get("common_events", []):
		common_events[c.id] = c
	db.clear()
	for t in DB_TYPES + extra_types:
		reload_db_type(t)


## Reads one database file (database/<type>.json) again, e.g. after the Database tab saved it.
func reload_db_type(type: String) -> void:
	if not DB_TYPES.has(type) and not extra_types.has(type):
		return
	var f: Dictionary = _load("database/%s.json" % type, {"schema_version": 1, "records": []})
	var by_id := {}
	for r in f.get("records", []):
		if r is Dictionary and r.has("id"):
			by_id[r.id] = r
	db[type] = {"records": f.get("records", []), "by_id": by_id, "file": f}


## Adds database types owned by extensions (RPGCommandRegistry.database_types(): Dictionaries
## with "type", or plain type names) and loads them; a missing file is an empty type. Types
## already known are left as they are.
func add_db_types(types: Array) -> void:
	for t in types:
		var type := str(t.get("type", "")) if t is Dictionary else str(t)
		if type == "" or not RPGIds.is_valid(type) or DB_TYPES.has(type) or extra_types.has(type):
			continue
		extra_types.append(type)
		reload_db_type(type)


## Every database type this data holds: the built-in ones, then the extensions' (add_db_types).
func all_db_types() -> Array:
	return DB_TYPES + extra_types


func _load(rel: String, fallback: Dictionary) -> Dictionary:
	var path := root.path_join(rel)
	if not FileAccess.file_exists(path):
		return fallback.duplicate(true)
	var r := RPGJson.parse_file(path)
	if not r.ok:
		load_errors.append({"severity": "error", "file": path, "message": r.error})
		return fallback.duplicate(true)
	if not (r.data is Dictionary):
		load_errors.append({"severity": "error", "file": path, "message": "Top level must be an object."})
		return fallback.duplicate(true)
	return r.data


# --- database ------------------------------------------------------------------

func record(type: String, id: String) -> Dictionary:
	if not db.has(type):
		return {}
	return db[type].by_id.get(id, {})


func records(type: String) -> Array:
	if not db.has(type):
		return []
	return db[type].records


func has_record(type: String, id: String) -> bool:
	return db.has(type) and db[type].by_id.has(id)


## The currency unit, from one place for every screen and message: System's currency, then the
## "currency" or "gold_unit" term, then "G".
func currency() -> String:
	var c := str(system.get("currency", ""))
	if c != "":
		return c
	for key in ["currency", "gold_unit"]:
		var t := term(key, "")
		if t != "" and t != key:
			return t
	return "G"


func term(key: String, fallback := "") -> String:
	var terms: Array = records("terms")
	for t in terms:
		if t.get("id", "") == key:
			return str(t.get("text", t.get("name", fallback)))
	return fallback if fallback != "" else key


# --- maps ----------------------------------------------------------------------

func map_entry(map_id: String) -> Dictionary:
	return maps.get(map_id, {})


func map_scene_path(map_id: String) -> String:
	var e := map_entry(map_id)
	return e.get("scene", root.path_join("maps/%s.tscn" % map_id))


func map_props(map_id: String) -> Dictionary:
	if _props_cache.has(map_id):
		return _props_cache[map_id]
	var e := map_entry(map_id)
	var path: String = e.get("properties", root.path_join("maps/%s.map.json" % map_id))
	var d: Dictionary = {}
	if FileAccess.file_exists(path):
		var r := RPGJson.parse_file(path)
		if r.ok:
			d = r.data
		else:
			load_errors.append({"severity": "error", "file": path, "message": r.error})
	_props_cache[map_id] = d
	return d


func map_events(map_id: String) -> Array:
	if _events_cache.has(map_id):
		return _events_cache[map_id]
	var e := map_entry(map_id)
	var path: String = e.get("events", root.path_join("maps/%s.events.json" % map_id))
	var list: Array = []
	if FileAccess.file_exists(path):
		var r := RPGJson.parse_file(path)
		if r.ok:
			list = r.data.get("events", [])
		else:
			load_errors.append({"severity": "error", "file": path, "message": r.error})
	_events_cache[map_id] = list
	return list


func map_event(map_id: String, event_id: String) -> Dictionary:
	for ev in map_events(map_id):
		if ev.get("id", "") == event_id:
			return ev
	return {}


func invalidate_map(map_id: String) -> void:
	_props_cache.erase(map_id)
	_events_cache.erase(map_id)


func map_size(map_id: String) -> Vector2i:
	var p := map_props(map_id)
	return Vector2i(int(p.get("width", 20)), int(p.get("height", 15)))


func cell_in_map(map_id: String, pos: Variant) -> bool:
	if not maps.has(map_id) or not (pos is Array) or pos.size() != 2:
		return false
	var s := map_size(map_id)
	return int(pos[0]) >= 0 and int(pos[1]) >= 0 and int(pos[0]) < s.x and int(pos[1]) < s.y


func tile_size() -> int:
	return int(profile.get("tile_size", 16))


func scene_setting(key: String, fallback: String) -> String:
	var scenes: Dictionary = project.get("scenes", {})
	var v: String = scenes.get(key, "")
	return v if v != "" else fallback
