@tool
extends RPGCommand
## Open bestiary (bestiary plugin): the enemy book; the event waits until it is closed. In auto
## mode (headless tests) it does nothing, as Open Menu Screen.


static func descriptor() -> Dictionary:
	return {"type": "open_bestiary", "schema_version": 1, "category": "scenes", "label": "Open bestiary", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Open bestiary"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	var bk: Object = ctx.rpg.extension("bestiary")
	if bk == null:
		return RPGResult.error("Open bestiary: the Bestiary plugin is not running.")
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var node: Node = bk.make_screen()
	if node == null:
		return RPGResult.error("Open bestiary: the bestiary screen could not be opened.")
	var r := await ctx.wait_signal(node.closed)
	ctx.ui.close_scene(node)
	return RPGResult.ok() if r.ok else RPGResult.cancelled()
