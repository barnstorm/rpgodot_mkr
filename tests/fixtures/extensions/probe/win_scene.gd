extends Control
## Test battle scene: wins at once with a fixed reward (Run Scene contract).

signal finished(result: Variant)
signal cancelled(reason: String)

var rpg: Node


func start(_args: Dictionary, _context: Variant) -> void:
	await get_tree().process_frame
	finished.emit({"outcome": "win", "rewards": {"exp": 0, "gold": 0, "items": []}})
