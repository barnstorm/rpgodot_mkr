@tool
extends RPGCommand
## Open formation (party_formation plugin): the formation screen; the event waits until it is
## closed. In auto mode (headless tests) it does nothing, as Open Menu Screen.


static func descriptor() -> Dictionary:
	return {"type": "open_formation", "schema_version": 1, "category": "party", "label": "Open formation", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Open formation"


func run(ctx: RPGContext, _args: Dictionary) -> RPGResult:
	var pf: Object = ctx.rpg.extension("party_formation")
	if pf == null:
		return RPGResult.error("Open formation: the Party formation plugin is not running.")
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var node: Node = pf.make_screen()
	if node == null:
		return RPGResult.error("Open formation: the formation screen could not be opened.")
	var r := await ctx.wait_signal(node.closed)
	ctx.ui.close_scene(node)
	return RPGResult.ok() if r.ok else RPGResult.cancelled()
