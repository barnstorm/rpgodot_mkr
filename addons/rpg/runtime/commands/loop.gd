@tool
extends RPGCommand
## Repeats its commands until Break Loop. A loop without waits cannot freeze the game: the
## interpreter's per-frame command budget yields to the next frame.


static func descriptor() -> Dictionary:
	return {
		"type": "loop", "schema_version": 1, "category": "flow", "label": "Loop",
		"fields": [{"key": "commands", "kind": "commands", "label": "Repeat", "default": []}],
	}


func summary(_args: Dictionary) -> String:
	return "Loop"


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var body: Array = args.get("commands", [])
	while true:
		var r: RPGResult = await ctx.run_list(body, "loop")
		if r.is_error() or r.is_cancelled():
			return r
		if r.flow == "break":
			return RPGResult.ok()
		if r.flow == "exit" or r.flow.begins_with("jump:"):
			return r
		if body.is_empty():
			# An empty loop would spin forever; yield every pass.
			await ctx.tree.process_frame
		if ctx.is_cancelled():
			return RPGResult.cancelled()
	return RPGResult.ok()
