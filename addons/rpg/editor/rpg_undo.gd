@tool
class_name RPGUndo
extends RefCounted
## One API over EditorUndoRedoManager (inside the Godot editor, so RPG edits join Godot's undo
## history) and plain UndoRedo (tests and previews).

var manager: Object


func _init(p_manager: Object) -> void:
	manager = p_manager


func is_editor() -> bool:
	return manager != null and not (manager is UndoRedo)


func create_action(action_name: String) -> void:
	manager.create_action(action_name)


func add_do_property(obj: Object, property: StringName, value: Variant) -> void:
	manager.add_do_property(obj, property, value)


func add_undo_property(obj: Object, property: StringName, value: Variant) -> void:
	manager.add_undo_property(obj, property, value)


func add_do_method(obj: Object, method: StringName, args: Array = []) -> void:
	if manager is UndoRedo:
		manager.add_do_method(Callable(obj, method).bindv(args))
	else:
		manager.callv("add_do_method", [obj, method] + args)


func add_undo_method(obj: Object, method: StringName, args: Array = []) -> void:
	if manager is UndoRedo:
		manager.add_undo_method(Callable(obj, method).bindv(args))
	else:
		manager.callv("add_undo_method", [obj, method] + args)


func commit_action(execute := true) -> void:
	manager.commit_action(execute)
