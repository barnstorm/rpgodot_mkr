@tool
class_name RPGInterpreter
extends RefCounted
## Runs a command list in order, pausing whenever a command waits.
## Lifecycle: IDLE -> RUNNING <-> WAITING -> COMPLETED | CANCELLED | FAILED.
## Each interpreter has an owner, a cancellation token, a call stack with a depth limit and a
## per-frame command budget: when the budget runs out it yields to the next frame, so an
## endless loop without waits cannot freeze the game.

signal finished(result: RPGResult)
signal state_changed(new_state: int)

enum State { IDLE, RUNNING, WAITING, COMPLETED, CANCELLED, FAILED }

const DEFAULT_DEPTH_LIMIT := 32
const DEFAULT_BUDGET := 256

var rpg: Node
## {kind: "map_event"|"common_event"|"battle_event"|"api"|"test", map, event, page, id}
var owner: Dictionary = {}
var event: Node = null
var token := RPGCancelToken.new()
var depth_limit := DEFAULT_DEPTH_LIMIT
var budget := DEFAULT_BUDGET
var state: State = State.IDLE
var ctx: RPGContext
var last_result: RPGResult
## Call stack: [{label, list, index}]
var stack: Array = []
## How many times the per-frame budget was hit (debug inspector).
var budget_hits := 0
## Current command (for the debug inspector).
var current_command: Dictionary = {}

var _frame := -1
var _count := 0


func _init(p_rpg: Node, p_owner: Dictionary = {}, p_event: Node = null) -> void:
	rpg = p_rpg
	owner = p_owner
	event = p_event
	ctx = RPGContext.new(rpg, self, event, token)


func is_active() -> bool:
	return state == State.RUNNING or state == State.WAITING


func set_waiting(w: bool) -> void:
	if state == State.RUNNING and w:
		_set_state(State.WAITING)
	elif state == State.WAITING and not w:
		_set_state(State.RUNNING)


func cancel(reason := "cancelled") -> void:
	token.cancel(reason)


## Runs a top-level command list to completion. Always emits `finished` exactly once.
func run(commands: Array) -> RPGResult:
	if is_active():
		push_error("RPGInterpreter.run called while already running (%s)" % describe_owner())
		return RPGResult.error("interpreter already running")
	stack.clear()
	_set_state(State.RUNNING)
	var result: RPGResult = await run_list(commands, "root")
	if result.flow.begins_with("jump:"):
		result = _fail("Jump to Label: there is no label '%s' in this event." % result.flow.substr(5))
	elif result.flow != "":
		result = RPGResult.ok()
	if token.is_cancelled and not result.is_error():
		result = RPGResult.cancelled(token.reason)
	last_result = result
	match result.status:
		RPGResult.Status.OK:
			_set_state(State.COMPLETED)
		RPGResult.Status.CANCELLED:
			_set_state(State.CANCELLED)
		RPGResult.Status.ERROR:
			_set_state(State.FAILED)
	current_command = {}
	finished.emit(result)
	return result


## Runs a nested list inside this interpreter (used by if/loop/choices and call_common_event).
func run_list(list: Array, label := "") -> RPGResult:
	if stack.size() >= depth_limit:
		var e := RPGResult.error("Call depth limit (%d) reached in %s. Check for a common event calling itself." % [depth_limit, describe_owner()])
		e.where = where()
		return e
	var frame := {"label": label, "list": list, "index": 0}
	stack.append(frame)
	var result := RPGResult.ok()
	var i := 0
	while i < list.size():
		if token.is_cancelled:
			result = RPGResult.cancelled(token.reason)
			break
		await _spend_budget()
		if token.is_cancelled:
			result = RPGResult.cancelled(token.reason)
			break
		frame.index = i
		var cmd_data: Variant = list[i]
		i += 1
		if not (cmd_data is Dictionary):
			result = _fail("Command %d is not an object." % i)
			break
		if cmd_data.get("skip", false):
			continue
		current_command = cmd_data
		var r: RPGResult = await execute(cmd_data)
		if r == null:
			r = RPGResult.ok()
		if r.is_error():
			if r.where.is_empty():
				r.where = where()
			result = r
			break
		if r.is_cancelled():
			result = r
			break
		if r.flow.begins_with("jump:"):
			# Jump to Label: continue after the label if it is in this list, else pass it outwards
			# (out of branches and loops) until a list that has it.
			var at := find_label(list, r.flow.substr(5))
			if at >= 0:
				i = at + 1
				continue
			result = r
			break
		if r.flow != "":
			result = r
			break
	stack.pop_back()
	return result


## Index of the Label command named `label_name` directly in `list`, or -1.
static func find_label(list: Array, label_name: String) -> int:
	for j in list.size():
		var c: Variant = list[j]
		if c is Dictionary and str(c.get("type", "")) == "label" and str(c.get("name", "")) == label_name and not c.get("skip", false):
			return j
	return -1


## Executes one command object.
func execute(cmd_data: Dictionary) -> RPGResult:
	var type: String = str(cmd_data.get("type", ""))
	var registry: RPGCommandRegistry = rpg.registry
	var cmd: RPGCommand = registry.get_command(type)
	if cmd == null:
		var why := registry.unavailable_reason(type)
		return _fail("Unknown or unavailable command '%s'%s." % [type, (": " + why) if why != "" else ""])
	var args := cmd.with_defaults(cmd_data)
	var r: Variant = await cmd.run(ctx, args)
	if r is RPGResult:
		return r
	return RPGResult.ok(r)


## The command after the current one in the innermost list (skipped lines ignored), or {}.
func peek_next() -> Dictionary:
	if stack.is_empty():
		return {}
	var fr: Dictionary = stack[-1]
	var list: Array = fr.list
	var i: int = fr.index + 1
	while i < list.size():
		var c: Variant = list[i]
		if c is Dictionary and not c.get("skip", false):
			return c
		i += 1
	return {}


func _spend_budget() -> void:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_count = 0
	_count += 1
	if _count > budget:
		budget_hits += 1
		if budget_hits == 50 and OS.is_debug_build():
			push_warning("RPG: %s keeps hitting its per-frame command budget. Is there a loop without a wait?" % describe_owner())
		await rpg.get_tree().process_frame
		_frame = Engine.get_process_frames()
		_count = 1


func _fail(msg: String) -> RPGResult:
	var e := RPGResult.error(msg)
	e.where = where()
	return e


## Where the interpreter is: owner info plus the path of list indices.
func where() -> Dictionary:
	var path := []
	for fr in stack:
		path.append("%s[%d]" % [fr.label, fr.index])
	if path.size() > 6:
		path = path.slice(0, 2) + ["...(%d more)" % (path.size() - 5)] + path.slice(-3)
	var w := owner.duplicate()
	w["path"] = "/".join(path)
	w["command"] = current_command.get("type", "")
	return w


func describe_owner() -> String:
	var parts := []
	for k in ["kind", "map", "event", "page", "id"]:
		if owner.has(k) and str(owner[k]) != "":
			parts.append("%s=%s" % [k, owner[k]])
	return "{" + ", ".join(parts) + "}"


static func describe_where(w: Dictionary) -> String:
	var parts := []
	if w.get("map", "") != "":
		parts.append("map '%s'" % w.map)
	if w.get("event", "") != "":
		parts.append("event '%s'" % w.event)
	if w.has("page"):
		parts.append("page %s" % (int(w.page) + 1))
	if w.get("id", "") != "" and w.get("kind", "") == "common_event":
		parts.append("common event '%s'" % w.id)
	if w.get("command", "") != "":
		parts.append("command '%s'" % w.command)
	if w.get("path", "") != "":
		parts.append("at %s" % w.path)
	return ", ".join(parts)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
