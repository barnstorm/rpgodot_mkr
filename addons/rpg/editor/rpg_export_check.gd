@tool
extends EditorExportPlugin
## Runs the full project validation when an export starts. While any event, common event or
## battle event uses a command from a disabled or missing extension (or other errors remain), the
## export is blocked: every file is skipped so no playable build is produced, and the problems are
## reported. The Deploy dialog runs the same check first and refuses to start.

var _blocked := false


func _get_name() -> String:
	return "RPGExportCheck"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_blocked = false
	var problems := RPGExportCheck.run_checks()
	var errors := problems.filter(func(p): return p.get("severity", "") == "error")
	if errors.is_empty():
		return
	_blocked = true
	var lines := PackedStringArray()
	for p in errors.slice(0, 20):
		lines.append("- %s: %s" % [p.get("file", ""), p.get("message", "")])
	push_error("RPG Kit: export blocked by %d problem(s):\n%s" % [errors.size(), "\n".join(lines)])


func _export_file(_path: String, _type: String, _features: PackedStringArray) -> void:
	if _blocked:
		skip()


func _export_end() -> void:
	_blocked = false
