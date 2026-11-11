@tool
extends RPGCommand
## Opens any Godot scene over the map and pauses the event. The scene gets start(args, context)
## and ends by emitting exactly one finished(result) or cancelled(reason). The result goes into a
## variable and the event continues. Minigames, puzzles and action fights plug in this way.


static func descriptor() -> Dictionary:
	return {
		"type": "run_scene", "schema_version": 1, "category": "scenes", "label": "Run Scene",
		"fields": [
			{"key": "scene", "kind": "resource", "res": "scene", "default": "", "label": "Scene", "required": true},
			{"key": "args", "kind": "object", "default": {}, "label": "Arguments", "fields": []},
			{"key": "result", "kind": "ref", "ref": "variable", "default": "", "label": "Store result in"},
			{"key": "timeout", "kind": "float", "default": 0.0, "min": 0.0, "max": 3600.0, "label": "Timeout (0 = none)"},
			{"key": "on_cancel", "kind": "commands", "default": [], "label": "If cancelled"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Run Scene: %s%s" % [str(args.scene).get_file(), (" -> [%s]" % args.result) if str(args.get("result", "")) != "" else ""]


func child_lists(args: Dictionary) -> Array:
	return [{"label": "If cancelled", "key": "on_cancel", "list": args.get("on_cancel", [])}]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var context := {"rpg": ctx.rpg, "state": ctx.state, "map_id": ctx.map_id(), "event_id": ctx.event_id()}
	var r: Dictionary = await ctx.ui.run_contract_scene(str(args.scene), args.get("args", {}), context, ctx.token, float(args.get("timeout", 0.0)))
	match r.status:
		"finished":
			var var_id := str(args.get("result", ""))
			if var_id != "":
				var v: Variant = r.value
				if not ctx.state.set_variable(var_id, v):
					ctx.state.set_variable(var_id, str(v))
			return RPGResult.ok(r.value)
		"cancelled":
			if ctx.is_cancelled():
				return RPGResult.cancelled()
			return await ctx.run_list(args.get("on_cancel", []), "on_cancel")
		"timeout":
			return RPGResult.error(str(r.value))
	return RPGResult.error("Run Scene failed: %s" % str(r.value))
