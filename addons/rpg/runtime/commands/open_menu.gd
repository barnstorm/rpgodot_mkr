@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {"type": "open_menu", "schema_version": 1, "category": "scenes", "label": "Open Menu Screen", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Open Menu Screen"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var node: Node = ctx.ui.open_scene(ctx.ui.scene_path("menu"))
	if node == null:
		return RPGResult.error("Open Menu: the menu scene could not be opened.")
	if "opened_by_event" in node:
		node.opened_by_event = true
		if node.has_method("_refresh_commands") and node.get("commands") != null:
			node._refresh_commands()
	var r := await ctx.wait_signal(node.closed)
	ctx.ui.close_scene(node)
	return RPGResult.ok() if r.ok else RPGResult.cancelled()
