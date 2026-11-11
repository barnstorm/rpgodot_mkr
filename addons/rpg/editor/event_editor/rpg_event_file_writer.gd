@tool
class_name RPGEventFileWriter
extends RefCounted
## Undo/redo target for event file writes: EditorUndoRedoManager calls write(path, text) for do
## and undo, so the event window's saves join Godot's undo history.

var data: RPGProjectData
var map_id := ""
var on_written: Callable
var last_error: Error = OK


func write(path: String, text: String) -> Error:
	if text == "":
		# The file did not exist before: undoing its creation removes it.
		last_error = DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK
	else:
		last_error = RPGJson.write_atomic(path, text)
	if data != null and map_id != "":
		data.invalidate_map(map_id)
	if last_error == OK and on_written.is_valid():
		on_written.call()
	return last_error
