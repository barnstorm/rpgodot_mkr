@tool
extends RPGCommand
## Open crafting (crafting plugin): the crafting screen with every recipe, or only the recipes of
## some crafting categories (a forge, a kitchen). The event waits until it is closed.


static func descriptor() -> Dictionary:
	return {
		"type": "open_crafting", "schema_version": 1, "category": "scenes", "label": "Open crafting",
		"fields": [
			{"key": "categories", "kind": "list", "default": [], "label": "Only these crafting categories (empty: all)",
				"item_field": {"kind": "text", "default": "", "label": "Category"}},
		],
	}


func summary(args: Dictionary) -> String:
	var cats := _categories(args)
	return "Open crafting" + (": %s" % ", ".join(PackedStringArray(cats)) if not cats.is_empty() else "")


static func _categories(args: Dictionary) -> Array:
	var out := []
	var c: Variant = args.get("categories", [])
	if c is String:
		c = Array(str(c).split(",", false))
	if c is Array:
		for x in c:
			var s := str(x.get("name", "")) if x is Dictionary else str(x)
			if s.strip_edges() != "":
				out.append(s.strip_edges())
	return out


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var cr: Object = ctx.rpg.extension("crafting")
	if cr == null:
		return RPGResult.error("Open crafting: the Item crafting plugin is not running.")
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var r: Dictionary = await ctx.ui.run_contract_scene(cr.SCREEN, {"categories": _categories(args)}, {"rpg": ctx.rpg}, ctx.token)
	if r.status == "error":
		return RPGResult.error(str(r.value))
	return RPGResult.cancelled() if ctx.is_cancelled() else RPGResult.ok()
