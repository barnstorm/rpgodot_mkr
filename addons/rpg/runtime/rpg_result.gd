@tool
class_name RPGResult
extends RefCounted
## Typed result every command returns: success, cancelled or error.
## `flow` carries control flow out of nested lists: "" (continue), "break" (break_loop) or "exit" (exit_event).

enum Status { OK, CANCELLED, ERROR }

var status: Status = Status.OK
var message := ""
var flow := ""
var value: Variant = null
## Where an error happened: filled by the interpreter ({map, event, page, path, command}).
var where: Dictionary = {}


static func ok(v: Variant = null) -> RPGResult:
	var r := RPGResult.new()
	r.value = v
	return r


static func cancelled(reason := "cancelled") -> RPGResult:
	var r := RPGResult.new()
	r.status = Status.CANCELLED
	r.message = reason
	return r


static func error(msg: String) -> RPGResult:
	var r := RPGResult.new()
	r.status = Status.ERROR
	r.message = msg
	return r


static func flow_break() -> RPGResult:
	var r := RPGResult.new()
	r.flow = "break"
	return r


static func flow_exit() -> RPGResult:
	var r := RPGResult.new()
	r.flow = "exit"
	return r


func is_ok() -> bool:
	return status == Status.OK


func is_error() -> bool:
	return status == Status.ERROR


func is_cancelled() -> bool:
	return status == Status.CANCELLED


func _to_string() -> String:
	return "RPGResult(%s%s%s)" % [Status.keys()[status], (" " + message) if message != "" else "", (" flow=" + flow) if flow != "" else ""]
