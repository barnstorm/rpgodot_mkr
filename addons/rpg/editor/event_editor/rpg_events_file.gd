@tool
class_name RPGEventsFile
extends RefCounted
## The data layer the event window edits through: one `<map>.events.json` held as a whole
## Dictionary, so unknown fields and unknown command types are never dropped. Edits replace whole
## event objects (deep copies); save() writes atomically with the stable key order.
##
##   var f := RPGEventsFile.open(path, "town")
##   var ev := f.get_event_copy("town_house_door")   # deep copy to edit
##   ev.name = "Front door"
##   f.set_event(ev)                                 # replaces by id (or appends)
##   f.save()

var path := ""
var map_id := ""
## The whole file. Never rebuilt from parts.
var data: Dictionary = {}
var error := ""
## Text that was loaded (or last saved), to detect outside edits.
var disk_text := ""


static func open(p_path: String, p_map_id := "") -> RPGEventsFile:
	var f := RPGEventsFile.new()
	f.path = p_path
	f.map_id = p_map_id
	f.reload()
	return f


func reload() -> bool:
	error = ""
	if not FileAccess.file_exists(path):
		data = {"schema_version": 1, "map": map_id, "events": []}
		disk_text = ""
		return true
	disk_text = FileAccess.get_file_as_string(path)
	var r := RPGJson.parse_text(disk_text)
	if not r.ok:
		error = "%s (line %d): %s" % [path, r.line + 1, r.error]
		return false
	if not (r.data is Dictionary):
		error = "%s: the file must contain an object." % path
		return false
	data = r.data
	if map_id == "":
		map_id = str(data.get("map", ""))
	if not (data.get("events") is Array):
		data["events"] = []
	return true


func events() -> Array:
	return data.get("events", [])


func ids() -> Array:
	var out := []
	for e in events():
		if e is Dictionary:
			out.append(str(e.get("id", "")))
	return out


func index_of(event_id: String) -> int:
	var list := events()
	for i in list.size():
		if list[i] is Dictionary and str(list[i].get("id", "")) == event_id:
			return i
	return -1


func has_event(event_id: String) -> bool:
	return index_of(event_id) != -1


func get_event(event_id: String) -> Dictionary:
	var i := index_of(event_id)
	return events()[i] if i != -1 else {}


func get_event_copy(event_id: String) -> Dictionary:
	return get_event(event_id).duplicate(true)


## Replaces the event whose id is `old_id` (default: ev.id) with `ev`, or appends it.
func set_event(ev: Dictionary, old_id := "") -> void:
	var key := old_id if old_id != "" else str(ev.get("id", ""))
	var i := index_of(key)
	if i == -1:
		events().append(ev)
	else:
		events()[i] = ev


## Adds an event with a new unique ID (never a retired one). Returns the ID used.
func add_event(ev: Dictionary, base_id := "") -> String:
	var base := base_id
	if base == "":
		base = str(ev.get("id", ""))
	if base == "":
		base = RPGIds.slug(str(ev.get("name", "event")))
	var id := RPGIds.unique(base, ids(), retired_ids())
	ev["id"] = id
	events().append(ev)
	return id


func remove_event(event_id: String) -> bool:
	var i := index_of(event_id)
	if i == -1:
		return false
	events().remove_at(i)
	retire(event_id)
	return true


## IDs that were deleted from this map and must never be reused.
func retired_ids() -> Array:
	var r: Variant = data.get("retired_ids", [])
	return r if r is Array else []


func retire(event_id: String) -> void:
	if not (data.get("retired_ids") is Array):
		data["retired_ids"] = []
	if not data.retired_ids.has(event_id):
		data.retired_ids.append(event_id)


func event_at(cell: Vector2i) -> Dictionary:
	for e in events():
		if e is Dictionary and e.get("position") is Array and e.position.size() == 2:
			if int(e.position[0]) == cell.x and int(e.position[1]) == cell.y:
				return e
	return {}


func to_text() -> String:
	return RPGJson.stringify(data)


## True when the file on disk differs from what was loaded or last saved (an outside edit).
func changed_on_disk() -> bool:
	if not FileAccess.file_exists(path):
		return disk_text != ""
	return FileAccess.get_file_as_string(path) != disk_text


func save() -> Error:
	var text := to_text()
	var err := RPGJson.write_atomic(path, text)
	if err == OK:
		disk_text = text
	return err
