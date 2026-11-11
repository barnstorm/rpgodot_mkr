extends Control
## A victory step that finishes on the next frame (battle_probe).

signal finished()

var ran := false


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	await get_tree().process_frame
	ran = true
	finished.emit()
