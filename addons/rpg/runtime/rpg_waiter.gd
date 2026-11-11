@tool
class_name RPGWaiter
extends RefCounted
## Waits for the first of several signals. `await waiter.done` returns [index, first_arg].
##   var w := RPGWaiter.any([timer.timeout, token.cancelled])
##   var r: Array = await w.done

signal done(index: int, value: Variant)

var fired := false
var _links: Array = []


static func any(signals: Array) -> RPGWaiter:
	var w := RPGWaiter.new()
	for i in signals.size():
		var s: Signal = signals[i]
		var idx := i
		var cb := func(a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
			w._fire(idx, a)
		s.connect(cb, CONNECT_ONE_SHOT)
		w._links.append([s, cb])
	return w


func _fire(idx: int, value: Variant) -> void:
	if fired:
		return
	fired = true
	for link in _links:
		var s: Signal = link[0]
		if s.is_connected(link[1]):
			s.disconnect(link[1])
	_links.clear()
	# Emit on the next idle step so the awaiting coroutine is already suspended on `done`.
	_emit_later.call_deferred(idx, value)


func _emit_later(idx: int, value: Variant) -> void:
	done.emit(idx, value)
