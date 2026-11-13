@tool
class_name RPGContext
extends RefCounted
## The restricted API a command receives. Commands change game state only through this object.

## The RPG service node (autoload "RPG" in a game, or a test instance).
var rpg: Node
## The interpreter running the command. Held weakly: the interpreter owns this context, and two
## RefCounted objects pointing at each other are never freed (they showed up as leaked instances
## and "resources still in use" when the game quit).
var interpreter: RPGInterpreter:
	get:
		return _interpreter_ref.get_ref() as RPGInterpreter if _interpreter_ref != null else null
	set(v):
		_interpreter_ref = weakref(v) if v != null else null
var _interpreter_ref: WeakRef = null
## The map event that owns this run, or null (common event, API call, battle event).
var event: Node = null
var token: RPGCancelToken
## The owning event's map and id, cached: the event node is freed when a transfer unloads its
## map, but self switches still belong to it.
var _event_map := ""
var _event_id := ""


func _init(p_rpg: Node, p_interpreter: RPGInterpreter, p_event: Node, p_token: RPGCancelToken) -> void:
	rpg = p_rpg
	interpreter = p_interpreter
	event = p_event
	token = p_token
	if event != null and is_instance_valid(event):
		if "event_id" in event:
			_event_id = str(event.event_id)
		if "map_id" in event:
			_event_map = str(event.map_id)


# --- shortcuts -------------------------------------------------------------

var state: RPGGameState:
	get: return rpg.state

var data: RPGProjectData:
	get: return rpg.data

var screen: Node:
	get: return rpg.screen

var audio: Node:
	get: return rpg.audio

var ui: Node:
	get: return rpg.ui

var map: Node:
	get: return rpg.current_map()

## The public battle API while a battle runs (null otherwise). Battle-only commands use it
## instead of searching the scene stack.
var battle: RPGBattleFacade:
	get: return rpg.battle if rpg != null and "battle" in rpg else null

var tree: SceneTree:
	get: return rpg.get_tree()


func map_id() -> String:
	if _event_map != "":
		return _event_map
	var m: Node = map
	return m.map_id if m != null else ""


func event_id() -> String:
	return _event_id


func is_cancelled() -> bool:
	return token.is_cancelled


# --- flow ------------------------------------------------------------------

## Runs a nested command list (if/else branch, loop body, choice branch) inside this interpreter.
func run_list(list: Variant, label := "") -> RPGResult:
	if not (list is Array):
		return RPGResult.ok()
	return await interpreter.run_list(list, label)


func check_condition(cond: Dictionary) -> bool:
	return state.check_condition(cond, map_id(), event_id(), self)


## Resolves a number field that may be a literal or {variable: id}.
func operand(v: Variant) -> Variant:
	return state.resolve_operand(v)


# --- waiting (every wait is cancellable) -------------------------------------

## Waits `seconds` of game time. Returns false if cancelled.
func wait_seconds(seconds: float) -> bool:
	if token.is_cancelled:
		return false
	if seconds <= 0.0:
		await tree.process_frame
		return not token.is_cancelled
	interpreter.set_waiting(true)
	var timer := tree.create_timer(seconds, false)
	var w := RPGWaiter.any([timer.timeout, token.cancelled])
	var r: Array = await w.done
	interpreter.set_waiting(false)
	return r[0] == 0 and not token.is_cancelled


## Waits for a signal. Returns {ok: bool, value}.
func wait_signal(sig: Signal) -> Dictionary:
	if token.is_cancelled:
		return {"ok": false, "value": null}
	interpreter.set_waiting(true)
	var w := RPGWaiter.any([sig, token.cancelled])
	var r: Array = await w.done
	interpreter.set_waiting(false)
	return {"ok": r[0] == 0 and not token.is_cancelled, "value": r[1]}


func wait_frames(n: int) -> bool:
	for i in n:
		if token.is_cancelled:
			return false
		await tree.process_frame
	return not token.is_cancelled


## Self switch key for this event (map/event/letter).
func self_switch_key(letter: String) -> String:
	return RPGIds.self_switch_key(map_id(), event_id(), letter)


## Finds a character by route target: "player", "this", or an event ID on the current map.
func character(target: String) -> Node:
	if target == "" or target == "this":
		return event if event != null and is_instance_valid(event) and event.is_inside_tree() else null
	var m: Node = map
	if m == null:
		return null
	if target == "player":
		return m.player
	return m.get_event(target)


func error(msg: String) -> RPGResult:
	return RPGResult.error(msg)
