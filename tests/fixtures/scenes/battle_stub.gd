extends Control
## A battle-screen stand-in for the close_all tests (#23): follows the Run Scene contract and
## stays open until something ends it — a win() from the test, close_all's force_finish, or being
## freed outright.

signal finished(result: Variant)
signal cancelled(reason: String)

var rpg: Node
var started_args: Dictionary = {}


func start(args: Dictionary, _context: Variant) -> void:
	started_args = args


func force_finish(outcome: String) -> void:
	finished.emit({"outcome": outcome, "rewards": {"exp": 0, "gold": 0, "items": []}})


func win() -> void:
	force_finish("win")
