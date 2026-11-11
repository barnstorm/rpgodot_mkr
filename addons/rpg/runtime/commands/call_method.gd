@tool
extends RPGCommand
## For programmers: calls a method on a node and optionally stores the return value.
## target: "map" (the map scene root), a node path relative to the map scene ("Props/Lever"),
## or "/root/<Autoload>". Arguments are JSON values. If the method is a coroutine it is awaited.


static func descriptor() -> Dictionary:
	return {
		"type": "call_method", "schema_version": 1, "category": "godot", "label": "Call Method",
		"fields": [
			{"key": "target", "kind": "text", "default": "map", "label": "Node", "help": "map, a path inside the map scene, or /root/Autoload"},
			{"key": "method", "kind": "text", "default": "", "label": "Method", "required": true},
			{"key": "args", "kind": "list", "default": [], "label": "Arguments", "item_fields": []},
			{"key": "result", "kind": "ref", "ref": "variable", "default": "", "label": "Store return value in"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Call Method: %s.%s(%s)" % [args.target, args.method, ", ".join(PackedStringArray(args.get("args", []).map(func(a): return str(a))))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var target := str(args.get("target", "map"))
	var node: Node = null
	if target == "map" or target == "":
		node = ctx.map
	elif target.begins_with("/root/"):
		node = ctx.tree.root.get_node_or_null(target.substr(6))
	elif ctx.map != null:
		node = ctx.map.get_node_or_null(target)
	if node == null:
		return RPGResult.error("Call Method: node '%s' not found." % target)
	var m := str(args.get("method", ""))
	if not node.has_method(m):
		return RPGResult.error("Call Method: '%s' has no method '%s'." % [target, m])
	var call_args: Array = args.get("args", [])
	var ret: Variant = await node.callv(m, call_args)
	if str(args.get("result", "")) != "" and ret != null:
		ctx.state.set_variable(str(args.result), ret)
	return RPGResult.ok(ret)
