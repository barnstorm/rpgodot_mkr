@tool
class_name RPGInterpreter
extends RefCounted
## Runs a command list in order, pausing whenever a command waits.
## Lifecycle: IDLE -> RUNNING <-> WAITING -> COMPLETED | CANCELLED | FAILED.
## Each interpreter has an owner, a cancellation token, a per-frame command budget and a call
## depth limit: when the budget runs out it yields to the next frame, so an endless loop without
## waits cannot freeze the game. The budget matches RM2000/2003 (10,000 commands per frame); the
## depth limit counts only common-event and page calls (100, like MV) — branches, loops and
## choices nest freely.

signal finished(result: RPGResult)
signal state_changed(new_state: int)

enum State { IDLE, RUNNING, WAITING, COMPLETED, CANCELLED, FAILED }

const DEFAULT_DEPTH_LIMIT := 100
const DEFAULT_BUDGET := 10000

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
## How many called event pages are on the stack (Call Event); started_by conditions read it.
var in_called_page := 0
## The chain of called common events and pages, newest last (the depth limit's error names it).
var call_chain: Array[String] = []
## True for parallel-event interpreters: they sleep between commands while a menu-type screen or
## a battle suspends the map (RPG Maker's map scene), resuming at the same command when it closes.
## Main interpreters never sleep (the one that opened the screen is waiting on it).
var suspends_with_map := false
## True while this interpreter's parallel task is paused (its condition switch went off under the
## classic rules): it sleeps at its current command until the flag clears, keeping its whole run
## so it carries on at that command when the switch returns (RM2000/2003 behaviour).
var paused := false

var _frame := -1
var _count := 0


func _init(p_rpg: Node, p_owner: Dictionary = {}, p_event: Node = null) -> void:
	rpg = p_rpg
	owner = p_owner
	event = p_event
	ctx = RPGContext.new(rpg, self, event, token)
	# A project can tune the per-frame budget (project.json: "interpreter_budget").
	if p_rpg != null and "data" in p_rpg and p_rpg.data != null:
		budget = int(p_rpg.data.project.get("interpreter_budget", DEFAULT_BUDGET))


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
## Blocks (branches, loops, choices) nest freely: only calls count toward the depth limit.
func run_list(list: Array, label := "") -> RPGResult:
	var frame := {"label": label, "list": list, "index": 0}
	stack.append(frame)
	var result := RPGResult.ok()
	var i := 0
	while i < list.size():
		if token.is_cancelled:
			result = RPGResult.cancelled(token.reason)
			break
		if suspends_with_map:
			await _sleep_while_suspended()
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


## Entering a called common event or event page (Call Common Event / Call Event). Returns "" when
## the call may proceed, or the error that stops it: nested calls are capped at `depth_limit`
## (100, like MV) and the error names the chain of calls that led there.
func push_call(label: String) -> String:
	if call_chain.size() >= depth_limit:
		# Show how the chain was entered and where it loops; the middle is more of the same.
		var shown := call_chain.duplicate()
		if shown.size() > 7:
			shown = shown.slice(0, 2) + ["...(%d calls)" % (shown.size() - 7)] + shown.slice(shown.size() - 5)
		return "Call depth limit (%d) reached: %s. Check for a common event or a called page calling itself." % [depth_limit, " -> ".join(shown)]
	call_chain.append(label)
	return ""


## Leaving a called common event or event page (its list finished, errored or was cancelled).
func pop_call() -> void:
	if not call_chain.is_empty():
		call_chain.pop_back()


## Executes one command object.
func execute(cmd_data: Dictionary) -> RPGResult:
	var type: String = str(cmd_data.get("type", ""))
	var registry: RPGCommandRegistry = rpg.registry
	var cmd: RPGCommand = registry.get_command(type)
	if cmd == null:
		var why := registry.unavailable_reason(type)
		return _fail("Unknown or unavailable command '%s'%s." % [type, (": " + why) if why != "" else ""])
	var args := cmd.with_defaults(cmd_data)
	# A pending page refresh runs before the commands that read the map's live state, so "turn on
	# the switch, then move that event" acts on the new page within one list: under the classic
	# rules before every command (RM2000/2003), MV-style only before Set Move Route. The per-frame
	# refresh stays.
	if rpg.refresh_pending() and (type == "move_route" or not _vx_ace_style_rules()):
		rpg.process_refresh()
	var r: Variant = await cmd.run(ctx, args)
	if r is RPGResult:
		return r
	return RPGResult.ok(r)


## True under the VX Ace style rules, whose event timing follows the newer RPG Makers (pages
## refresh before Set Move Route only); the classic rules refresh before every command, as
## RM2000/2003 do.
func _vx_ace_style_rules() -> bool:
	return str(rpg.data.project.get("rules", "classic")) == "vx_ace"


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


## A parallel sleeps here while a menu, shop, save screen or battle suspends the map, or while its
## task is paused, and resumes at this exact command when the screen closes or it is un-paused.
func _sleep_while_suspended() -> void:
	while (rpg.scheduler.map_suspended() or paused) and not token.is_cancelled:
		await rpg.get_tree().process_frame


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
