extends SceneTree
## Headless test runner.
##   godot --headless --path <project> --script res://tests/run_tests.gd [-- --suite=name]
## Runs every tests/suites/test_*.gd (or only the named one) and exits 1 on any failure.


const STEP_TIMEOUT := 60


## Collects script errors (Godot 4.5 Logger API) so a test that hits one fails instead of
## silently stopping early and passing.
class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		mutex.lock()
		errors.append("script error: %s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		mutex.unlock()
		return out


var catcher := ErrorCatcher.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(catcher)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			only = arg.substr(8)
	var dir := DirAccess.open("res://tests/suites")
	var files: Array[String] = []
	if dir:
		for f in dir.get_files():
			if f.begins_with("test_") and f.ends_with(".gd"):
				if only == "" or f == "test_%s.gd" % only:
					files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	for f in files:
		var script: GDScript = load("res://tests/suites/" + f)
		if script == null or not script.can_instantiate():
			print("LOAD FAIL ", f)
			failed += 1
			continue
		var suite = script.new()
		suite.tree = self
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var n: String = m.name
			if n.begins_with("test_") and not methods.has(n):
				methods.append(n)
		print("== ", f, " (", methods.size(), " tests)")
		for m in methods:
			total += 1
			suite.current_test = m
			suite.failures.clear()
			catcher.take()
			# A script error inside a coroutine leaves it suspended forever, so each step is raced
			# against a timeout instead of awaited directly.
			var ok := await _step(suite, "before_each") and await _step(suite, m) and await _step(suite, "after_each")
			if not ok:
				suite.failures.append("timed out or stopped by a script error (%ds limit)" % STEP_TIMEOUT)
			for e in catcher.take():
				suite.failures.append(e)
			if suite.failures.is_empty():
				print("  PASS ", m)
			else:
				failed += 1
				print("  FAIL ", m)
				for msg in suite.failures:
					print("       ", msg)
	print("")
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


func _step(suite: Object, method: String) -> bool:
	var state := {"done": false}
	var runner := func() -> void:
		await suite.call(method)
		state.done = true
	runner.call()
	var deadline := Time.get_ticks_msec() + STEP_TIMEOUT * 1000
	while not state.done:
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true
