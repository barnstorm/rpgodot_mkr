extends RefCounted
## Minimal stand-in for RPGProjectData in tests: record(type, id) and records(type).

var _data := {}     ## type -> {id -> record}
var _order := {}    ## type -> [ids]


## Loads every <type>.json with a "records" array from a folder (e.g. res://rpg/database).
static func from_folder(path: String):
	var db = load("res://tests/fixtures/rpg_fake_db.gd").new()
	var dir := DirAccess.open(path)
	if dir == null:
		return db
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed := RPGJson.parse_file(path.path_join(f))
		if parsed.ok and parsed.data is Dictionary and parsed.data.has("records"):
			for r in parsed.data.records:
				db.add(f.get_basename(), r)
	return db


func add(type: String, rec: Dictionary) -> void:
	if not _data.has(type):
		_data[type] = {}
		_order[type] = []
	if not _data[type].has(rec.id):
		_order[type].append(rec.id)
	_data[type][rec.id] = rec


func record(type: String, id: String) -> Dictionary:
	return _data.get(type, {}).get(id, {})


func records(type: String) -> Array:
	var out := []
	for id in _order.get(type, []):
		out.append(_data[type][id])
	return out
