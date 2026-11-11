extends RefCounted
## Base class for headless test suites. Methods named test_* are run in order.
## A test may be a coroutine (use `await`). The runner gives each suite `tree` (the SceneTree).

var tree: SceneTree
var failures: Array[String] = []
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg := "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if not _same(actual, expected):
		fail("%s expected <%s> got <%s>" % [msg, str(expected), str(actual)])


func assert_ne(actual: Variant, expected: Variant, msg := "") -> void:
	if _same(actual, expected):
		fail("%s expected anything but <%s>" % [msg, str(expected)])


func assert_has(container: Variant, item: Variant, msg := "") -> void:
	if not container.has(item):
		fail("%s <%s> does not contain <%s>" % [msg, str(container), str(item)])


func frames(n := 1) -> void:
	for i in n:
		await tree.process_frame


func _same(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return a == b
