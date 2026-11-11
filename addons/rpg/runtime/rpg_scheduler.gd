class_name RPGScheduler
extends Node
## Decides who runs. Action, touch and autorun events share ONE main interpreter fed by a queue
## and block player input while active. Each parallel page has its own interpreter (at most one
## running copy per key) that repeats while eligible and yields between rounds.
## A trigger that fires while the main interpreter is busy is queued, or merged with an identical
## pending request; it never starts a second copy inside the first.

signal main_started(ticket: Ticket)
signal main_finished(ticket: Ticket, result: RPGResult)


class Ticket extends RefCounted:
	signal finished(result: RPGResult)
	var key := ""
	var commands: Array = []
	var owner: Dictionary = {}
	var event: Node = null
	var interpreter: RPGInterpreter
	var result: RPGResult
	var done := false

	func finish(r: RPGResult) -> void:
		if done:
			return
		done = true
		result = r
		finished.emit(r)

	## Await this to get the RPGResult (returns at once if already finished).
	func wait() -> RPGResult:
		if not done:
			await finished
		return result


class ParallelTask extends RefCounted:
	signal stopped()
	var key := ""
	var commands: Array = []
	var owner: Dictionary = {}
	var event: Node = null
	var eligible: Callable
	var interpreter: RPGInterpreter
	## True when the task was started for a map event (so a freed event means "stop").
	var had_event := false
	var cancelled := false
	var done := false
	var rounds := 0


var rpg: Node
var main: RPGInterpreter = null
var main_ticket: Ticket = null
var queue: Array[Ticket] = []
## key -> ParallelTask
var parallels: Dictionary = {}
## reason -> count. Anything here blocks player input (transfers, open scenes...).
var input_locks: Dictionary = {}
var paused := false


func _init(p_rpg: Node = null) -> void:
	rpg = p_rpg
	name = "Scheduler"
	process_priority = -100
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(_delta: float) -> void:
	if paused:
		return
	rpg.process_refresh()
	pump()


## Starts the next queued main request when the main interpreter is free.
func pump() -> void:
	if main != null or queue.is_empty():
		return
	if input_locks.has("transfer"):
		return
	var t: Ticket = queue.pop_front()
	_run_main(t)


func is_main_busy() -> bool:
	return main != null or not queue.is_empty()


func input_locked() -> bool:
	return main != null or not queue.is_empty() or not input_locks.is_empty()


func lock_input(reason: String) -> void:
	input_locks[reason] = int(input_locks.get(reason, 0)) + 1


func unlock_input(reason: String) -> void:
	if not input_locks.has(reason):
		return
	input_locks[reason] -= 1
	if input_locks[reason] <= 0:
		input_locks.erase(reason)


## Queues a command list for the main interpreter. Identical pending requests are merged and a
## request for what is already running is ignored (returns the running ticket).
func request_main(key: String, commands: Array, owner: Dictionary, event: Node = null) -> Ticket:
	if key != "":
		if main_ticket != null and main_ticket.key == key and not main_ticket.done:
			return main_ticket
		for t in queue:
			if t.key == key:
				return t
	var ticket := Ticket.new()
	ticket.key = key
	ticket.commands = commands
	ticket.owner = owner
	ticket.event = event
	queue.append(ticket)
	return ticket


func _run_main(t: Ticket) -> void:
	main_ticket = t
	main = RPGInterpreter.new(rpg, t.owner, t.event)
	t.interpreter = main
	main_started.emit(t)
	var r: RPGResult = await main.run(t.commands)
	if r.is_error():
		rpg.report_error(r, t.owner)
	main = null
	main_ticket = null
	t.finish(r)
	main_finished.emit(t, r)
	rpg.request_refresh()


## Starts a parallel task (no-op when one with this key is already running).
func start_parallel(key: String, commands: Array, owner: Dictionary, event: Node, eligible: Callable) -> ParallelTask:
	if parallels.has(key):
		return parallels[key]
	var task := ParallelTask.new()
	task.key = key
	task.commands = commands
	task.owner = owner
	task.event = event
	task.had_event = event != null
	task.eligible = eligible
	parallels[key] = task
	_run_parallel(task)
	return task


func _run_parallel(task: ParallelTask) -> void:
	# Start on the next frame so tasks started in one refresh run in a fixed order.
	await get_tree().process_frame
	while not task.cancelled:
		# The event's map was freed (e.g. a failed transfer rolled back): stop cleanly so
		# `stopped` is always emitted and the key never stays registered.
		if task.had_event and not is_instance_valid(task.event):
			break
		task.interpreter = RPGInterpreter.new(rpg, task.owner, task.event)
		task.rounds += 1
		var r: RPGResult = await task.interpreter.run(task.commands)
		if r.is_error():
			rpg.report_error(r, task.owner)
			break
		if task.cancelled or r.is_cancelled():
			break
		await get_tree().process_frame
		if task.cancelled or not task.eligible.is_valid() or not task.eligible.call():
			break
	task.done = true
	if parallels.get(task.key) == task:
		parallels.erase(task.key)
	task.stopped.emit()


func stop_parallel(key: String, reason := "stopped") -> ParallelTask:
	var task: ParallelTask = parallels.get(key)
	if task == null:
		return null
	task.cancelled = true
	if task.interpreter:
		task.interpreter.cancel(reason)
	parallels.erase(key)
	return task


## Cancels parallel tasks and queued (not yet running) main requests whose owner matches, and
## waits until every cancelled task has cleaned up. `caller` is the interpreter asking for this
## (a parallel event running Transfer Player): it is cancelled too but not waited for, because it
## is suspended inside this call and could never finish first.
func cancel_owned(predicate: Callable, reason := "map unloaded", caller: RPGInterpreter = null) -> void:
	var waiting: Array[ParallelTask] = []
	for key in parallels.keys():
		var task: ParallelTask = parallels[key]
		if predicate.call(task.owner):
			stop_parallel(key, reason)
			if not task.done and (caller == null or task.interpreter != caller):
				waiting.append(task)
	var keep: Array[Ticket] = []
	for t in queue:
		if predicate.call(t.owner):
			t.finish(RPGResult.cancelled(reason))
		else:
			keep.append(t)
	queue = keep
	for task in waiting:
		if not task.done:
			await task.stopped


## Cancels everything (return to title, load game).
func cancel_all(reason := "reset") -> void:
	var waiting: Array = []
	for key in parallels.keys():
		var task: ParallelTask = parallels[key]
		stop_parallel(key, reason)
		if not task.done:
			waiting.append(task)
	for t in queue:
		t.finish(RPGResult.cancelled(reason))
	queue.clear()
	var m := main
	var mt := main_ticket
	if m != null:
		m.cancel(reason)
	for task in waiting:
		if not task.done:
			await task.stopped
	if mt != null and not mt.done:
		await mt.finished
	input_locks.clear()


func debug_snapshot() -> Dictionary:
	var par := {}
	for k in parallels:
		var t: ParallelTask = parallels[k]
		par[k] = {"rounds": t.rounds, "state": RPGInterpreter.State.keys()[t.interpreter.state] if t.interpreter else "IDLE"}
	return {
		"main": main.describe_owner() if main else "",
		"main_state": RPGInterpreter.State.keys()[main.state] if main else "IDLE",
		"queue": queue.map(func(t): return t.key),
		"parallels": par,
		"locks": input_locks.duplicate(),
	}
