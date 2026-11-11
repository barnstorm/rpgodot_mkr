@tool
class_name RPGJson
extends RefCounted
## JSON helpers shared by editor and runtime.
## - parse_file / parse_text return {ok, data, error, line} and normalise whole floats to int.
## - stringify writes a stable key order (preferred keys first, then alphabetical) with tabs,
##   so diffs stay readable and a load/save round trip is byte-identical.
## - write_atomic writes a temp file, flushes, then replaces the target, keeping a .bak copy.

const PREFERRED_KEYS := [
	"schema_version", "id", "type", "kind", "key", "name", "label", "map", "position",
	"project_id", "display_name", "notes", "skip",
]


static func parse_text(text: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {"ok": false, "data": null, "error": json.get_error_message(), "line": json.get_error_line()}
	return {"ok": true, "data": normalise(json.data), "error": "", "line": -1}


static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "File not found: %s" % path, "line": -1}
	var text := FileAccess.get_file_as_string(path)
	var result := parse_text(text)
	if not result.ok:
		result.error = "%s (line %d): %s" % [path, result.line, result.error]
	return result


## Loads a file and returns its data, or `fallback` when missing/invalid (errors are pushed).
static func load_or(path: String, fallback: Variant = {}) -> Variant:
	var r := parse_file(path)
	if not r.ok:
		if FileAccess.file_exists(path):
			push_error(r.error)
		return fallback
	return r.data


## Converts whole-number floats to ints, recursively.
static func normalise(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			if is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
				return int(v)
			return v
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(normalise(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = normalise(v[k])
			return d
	return v


static func ordered_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	var first := []
	for p in PREFERRED_KEYS:
		if d.has(p):
			first.append(p)
	var rest := []
	for k in keys:
		if not first.has(k):
			rest.append(str(k))
	rest.sort()
	return first + rest


static func stringify(v: Variant, indent := "\t") -> String:
	return _write(v, indent, "") + "\n"


static func _write(v: Variant, indent: String, cur: String) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			if is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
				return str(int(v))
			var s := String.num(v, 6)
			return s
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return JSON.stringify(str(v))
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var arr: Array = Array(v)
			if arr.is_empty():
				return "[]"
			if _is_flat(arr):
				var parts := []
				for x in arr:
					parts.append(_write(x, indent, cur))
				var line := "[" + ", ".join(parts) + "]"
				if line.length() <= 80:
					return line
			var inner := cur + indent
			var items := []
			for x in arr:
				items.append(inner + _write(x, indent, inner))
			return "[\n" + ",\n".join(items) + "\n" + cur + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_empty():
				return "{}"
			var inner2 := cur + indent
			var items2 := []
			for k in ordered_keys(d):
				items2.append(inner2 + JSON.stringify(str(k)) + ": " + _write(d[k], indent, inner2))
			return "{\n" + ",\n".join(items2) + "\n" + cur + "}"
		TYPE_VECTOR2I, TYPE_VECTOR2:
			return "[%s, %s]" % [_write(v.x, indent, cur), _write(v.y, indent, cur)]
	return JSON.stringify(str(v))


static func _is_flat(arr: Array) -> bool:
	for x in arr:
		var t := typeof(x)
		if t == TYPE_ARRAY or t == TYPE_DICTIONARY:
			return false
	return true


## Atomic write: temp file, flush, keep backup, rename. Returns OK or an error code.
static func write_atomic(path: String, text: String) -> Error:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var e := DirAccess.rename_absolute(path, bak)
		if e != OK:
			return e
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		# Restore the backup so the old version stays usable.
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(path + ".bak", path)
		return err
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	return OK


static func save_file(path: String, data: Variant) -> Error:
	return write_atomic(path, stringify(data))


## Finds interrupted writes (leftover .tmp or .bak files) under a folder.
static func find_interrupted(root: String) -> Array[String]:
	var found: Array[String] = []
	_scan_interrupted(root, found)
	return found


static func _scan_interrupted(path: String, found: Array[String]) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json.tmp") or f.ends_with(".json.bak"):
			found.append(path.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_scan_interrupted(path.path_join(sub), found)


## Recovers interrupted writes found by find_interrupted():
##   X.json.bak with no X.json   -> the backup becomes X.json again (the write died mid-swap)
##   X.json.bak next to X.json   -> X.json is the finished new version; the stale backup is removed
##   X.json.tmp                  -> an unfinished write; X.json (old version) is kept and the partial
##                                  file is renamed X.json.interrupted so nothing is lost
## Returns [{file, action}] describing what was done.
static func recover_interrupted(root: String) -> Array:
	var out := []
	for f in find_interrupted(root):
		if f.ends_with(".bak"):
			var target := f.trim_suffix(".bak")
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(f)
				out.append({"file": target, "action": "removed a stale backup"})
			elif DirAccess.rename_absolute(f, target) == OK:
				out.append({"file": target, "action": "restored from backup"})
		elif f.ends_with(".tmp"):
			var target2 := f.trim_suffix(".tmp")
			var keep := target2 + ".interrupted"
			if FileAccess.file_exists(keep):
				DirAccess.remove_absolute(keep)
			if not FileAccess.file_exists(target2) and parse_file(f).ok:
				DirAccess.rename_absolute(f, target2)
				out.append({"file": target2, "action": "completed the interrupted write"})
			elif DirAccess.rename_absolute(f, keep) == OK:
				out.append({"file": target2, "action": "kept the last good version; the unfinished write is in %s" % keep.get_file()})
	return out


static func deep_copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v
