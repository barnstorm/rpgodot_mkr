@tool
class_name RPGTileSettings
extends RefCounted
## Per-tile settings of one tileset (passage, flags, terrain) as edited in the Tiles dialog.
## Defaults come from a TileSet built WITHOUT user overrides (builder defaults + pack.json);
## user overrides live in rpg/tileset_overrides/<tileset_id>.json:
##   {"schema_version": 1, "tiles": {"<tile_key>": {"passage": int, "flags": int, "terrain": int}}}
## Only the three setting fields are edited. Unknown top-level keys, unknown fields inside a tile
## entry and entries for tile keys this sheet does not have are kept as they are.
## An override field equal to the default is dropped (so the tile no longer shows as overridden),
## except on tiles whose default is only a guess (review list): there an explicit value records
## that the tile was reviewed.

const FIELDS := ["passage", "flags", "terrain"]
const DIR_DOWN := 1
const DIR_LEFT := 2
const DIR_RIGHT := 4
const DIR_UP := 8
const ALL_DIRS := 15

var data: RPGProjectData
var tileset_id := ""
var record: Dictionary = {}
## Whole override file (unknown keys kept); `file.tiles` is the live override dictionary.
var file: Dictionary = {}
## TileSet built from the record without user overrides: defaults and atlas textures.
var base_tileset: TileSet
## Tile keys whose default is a guess (from the builder report).
var review: Array = []
var errors: Array = []
var dirty := false

## tile_key -> {source, coords, defaults: {passage, flags, terrain}}
var _index: Dictionary = {}
## source id -> Array of tile keys in atlas order
var _by_source: Dictionary = {}


## Loads the record, builds the default TileSet and reads the override file.
static func open(p_data: RPGProjectData, p_tileset_id: String) -> RPGTileSettings:
	var s := RPGTileSettings.new()
	s.data = p_data
	s.tileset_id = p_tileset_id
	s.record = p_data.record("tilesets", p_tileset_id)
	if s.record.is_empty():
		s.errors.append("No tileset record '%s'." % p_tileset_id)
	else:
		var report: Dictionary = RPGTilesetBuilder.build_with_report(s.record, {})
		s.errors.append_array(report.get("errors", []))
		s.review = report.get("review", [])
		s.base_tileset = report.get("tileset")
		if s.base_tileset != null:
			s._build_index()
	s.load_file()
	return s


static func overrides_path(p_data: RPGProjectData, p_tileset_id: String) -> String:
	return p_data.root.path_join("tileset_overrides/%s.json" % p_tileset_id)


func path() -> String:
	return overrides_path(data, tileset_id)


# --- file ----------------------------------------------------------------------------------------

## (Re)reads the override file; unsaved edits are dropped.
func load_file() -> void:
	var raw: Variant = RPGJson.load_or(path(), {})
	file = raw if raw is Dictionary else {}
	if not file.has("tiles"):
		if not file.is_empty() and not file.has("schema_version"):
			# Older form: the file is just the tiles dictionary.
			file = {"schema_version": 1, "tiles": file}
		else:
			file["tiles"] = {}
	if not (file.tiles is Dictionary):
		errors.append("'tiles' in %s is not an object; it was replaced." % path())
		file["tiles"] = {}
	if not file.has("schema_version"):
		file["schema_version"] = 1
	dirty = false


## Writes the override file atomically and drops cached TileSets so the next build uses it.
func save() -> Error:
	var err := RPGJson.save_file(path(), file)
	if err == OK:
		dirty = false
		RPGMap.clear_tileset_cache()
	return err


func revert() -> void:
	load_file()


func tiles() -> Dictionary:
	return file.tiles


# --- queries -------------------------------------------------------------------------------------

func has_key(key: String) -> bool:
	return _index.has(key)


## Every tile key of this sheet, grouped by atlas source and in atlas order.
func keys_for_source(source_id: int) -> Array:
	return _by_source.get(source_id, [])


func all_keys() -> Array:
	return _index.keys()


## {source, coords} of the atlas tile that represents `key` (autotiles: the preview variant).
func atlas_of(key: String) -> Dictionary:
	var e: Dictionary = _index.get(key, {})
	return {"source": e.get("source", -1), "coords": e.get("coords", Vector2i(-1, -1))}


## Builder default (no user override) for a tile: {passage, flags, terrain}.
func default_settings(key: String) -> Dictionary:
	var e: Dictionary = _index.get(key, {})
	return (e.get("defaults", {"passage": ALL_DIRS, "flags": 0, "terrain": 0}) as Dictionary).duplicate()


## The user override entry for a tile ({} when none). Only the setting fields are returned.
func override_of(key: String) -> Dictionary:
	var out := {}
	var entry: Variant = tiles().get(key)
	if entry is Dictionary:
		for f in FIELDS:
			if entry.has(f):
				out[f] = int(entry[f])
	return out


func is_overridden(key: String) -> bool:
	return not override_of(key).is_empty()


## Default merged with the override: what the next build gives this tile.
func effective(key: String) -> Dictionary:
	var s := default_settings(key)
	var ov := override_of(key)
	for f in ov:
		s[f] = ov[f]
	return s


func get_value(key: String, field: String) -> int:
	return int(effective(key).get(field, 0))


# --- edits ---------------------------------------------------------------------------------------

## Sets one field of a tile's override (field: passage, flags or terrain).
func set_value(key: String, field: String, value: int) -> void:
	if not FIELDS.has(field):
		push_error("RPGTileSettings: unknown field '%s'." % field)
		return
	var entry: Dictionary = {}
	var existing: Variant = tiles().get(key)
	if existing is Dictionary:
		entry = existing
	var keep_explicit := review.has(key)
	if value == int(default_settings(key).get(field, 0)) and not keep_explicit:
		entry.erase(field)
	else:
		entry[field] = value
	if entry.is_empty():
		tiles().erase(key)
	else:
		tiles()[key] = entry
	dirty = true


func set_passage(key: String, value: int) -> void:
	set_value(key, "passage", value & ALL_DIRS)


## Toggles one direction bit (DIR_DOWN, DIR_LEFT, DIR_RIGHT, DIR_UP).
func toggle_direction(key: String, bit: int) -> void:
	set_passage(key, get_value(key, "passage") ^ bit)


## Passable on/off: open in every direction, or closed in every direction.
func toggle_passable(key: String) -> void:
	set_passage(key, 0 if get_value(key, "passage") == ALL_DIRS else ALL_DIRS)


## Toggles a flag bit (RPGTilesetBuilder.FLAG_*).
func toggle_flag(key: String, bit: int) -> void:
	set_value(key, "flags", get_value(key, "flags") ^ bit)


func set_flag(key: String, bit: int, on: bool) -> void:
	var f := get_value(key, "flags")
	set_value(key, "flags", (f | bit) if on else (f & ~bit))


func set_terrain(key: String, value: int) -> void:
	set_value(key, "terrain", maxi(0, value))


## Copies the effective settings of `from_key` to each tile in `to_keys`.
func copy_to(from_key: String, to_keys: Array) -> void:
	var s := effective(from_key)
	for k in to_keys:
		if str(k) == from_key:
			continue
		for f in FIELDS:
			set_value(str(k), f, int(s[f]))


## Removes a tile's override so it goes back to the default. Unknown fields in its entry stay.
func reset(key: String) -> void:
	var existing: Variant = tiles().get(key)
	if not (existing is Dictionary):
		if existing != null:
			tiles().erase(key)
			dirty = true
		return
	for f in FIELDS:
		existing.erase(f)
	if existing.is_empty():
		tiles().erase(key)
	dirty = true


# --- index ---------------------------------------------------------------------------------------

func _build_index() -> void:
	_index.clear()
	_by_source.clear()
	var ts := base_tileset
	for si in ts.get_source_count():
		var sid := ts.get_source_id(si)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for ti in src.get_tiles_count():
			var c := src.get_tile_id(ti)
			var td := src.get_tile_data(c, 0)
			var key := str(td.get_custom_data("tile_key"))
			if key == "":
				continue
			if not _index.has(key):
				_index[key] = {
					"source": sid, "coords": c,
					"defaults": {"passage": int(td.get_custom_data("passage")), "flags": int(td.get_custom_data("flags")), "terrain": int(td.get_custom_data("terrain"))},
				}
			elif int(td.get_custom_data("autotile")) >= 0 and c.x == RPGAutotile.PREVIEW_VARIANT and _index[key].source == sid:
				_index[key].coords = c
	for key in _index:
		var sid: int = _index[key].source
		if not _by_source.has(sid):
			_by_source[sid] = []
		_by_source[sid].append(key)
	for sid in _by_source:
		_by_source[sid].sort_custom(func(a: String, b: String) -> bool:
			var ca: Vector2i = _index[a].coords
			var cb: Vector2i = _index[b].coords
			return ca.y < cb.y or (ca.y == cb.y and ca.x < cb.x))
