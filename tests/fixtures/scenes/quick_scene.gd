extends Control
## Test Run Scene: finishes with args.value, cancels when args.cancel, or never ends when args.never.

signal finished(result: Variant)
signal cancelled(reason: String)

var rpg: Node


func start(args: Dictionary, _context: Variant) -> void:
	if args.get("never", false):
		return
	await get_tree().process_frame
	if args.get("cancel", false):
		cancelled.emit("test cancel")
	else:
		finished.emit(args.get("value", "done"))
