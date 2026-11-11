@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "name_input", "schema_version": 1, "category": "scenes", "label": "Name Input Processing",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "max_length", "kind": "int", "default": 8, "min": 1, "max": 16, "label": "Max characters"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Name Input: %s (%d)" % [args.get("actor", "?"), int(args.max_length)]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	var b: Variant = ctx.state.actor(id)
	if b == null:
		return RPGResult.error("Name Input: actor '%s' does not exist." % id)
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var cur := RPGText._actor_name(ctx.rpg, id)
	var r: Dictionary = await ctx.ui.run_contract_scene(ctx.ui.scene_path("name_input"), {"actor": id, "name": cur, "max_length": int(args.max_length)}, {"rpg": ctx.rpg}, ctx.token)
	if r.status == "finished" and str(r.value) != "":
		if b is Object and "name" in b:
			b.name = str(r.value)
		elif b is Dictionary:
			b["name"] = str(r.value)
		ctx.state.notify_actor_changed(id)
	if r.status == "error":
		return RPGResult.error(str(r.value))
	return RPGResult.cancelled() if ctx.is_cancelled() else RPGResult.ok()
