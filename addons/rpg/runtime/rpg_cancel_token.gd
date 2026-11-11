@tool
class_name RPGCancelToken
extends RefCounted
## Cooperative cancellation. Every wait in the runtime races against `cancelled`.

signal cancelled(reason: String)

var is_cancelled := false
var reason := ""


func cancel(why := "cancelled") -> void:
	if is_cancelled:
		return
	is_cancelled = true
	reason = why
	cancelled.emit(why)
