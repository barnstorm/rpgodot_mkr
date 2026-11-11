@tool
extends RPGCommand
## Opens the shop screen. goods: [{kind: items|weapons|armors, id, price (blank = database price)}].


static func descriptor() -> Dictionary:
	return {
		"type": "shop", "schema_version": 1, "category": "scenes", "label": "Shop Processing",
		"fields": [
			{"key": "goods", "kind": "list", "default": [], "label": "Goods", "item_fields": [
				{"key": "kind", "kind": "choice", "options": ["items", "weapons", "armors"], "default": "items", "label": "Kind"},
				{"key": "id", "kind": "ref", "ref": "item", "ref_from": "kind", "label": "Item"},
				{"key": "price", "kind": "int", "default": null, "min": 0, "label": "Price (blank = database)"},
			]},
			{"key": "buy_only", "kind": "bool", "default": false, "label": "Buy only"},
		],
	}


func summary(args: Dictionary) -> String:
	var names := []
	for g in args.get("goods", []):
		names.append(str(g.get("id", "?")))
	return "Shop: %s%s" % [", ".join(names), " (buy only)" if args.get("buy_only", false) else ""]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var goods: Array = args.get("goods", [])
	for g in goods:
		var kind := RPGGameState.kind_for(str(g.get("kind", "items")))
		if not ctx.data.has_record(kind, str(g.get("id", ""))):
			return RPGResult.error("Shop: '%s' is not in the %s database." % [g.get("id", ""), kind])
	if ctx.ui.auto_advance:
		return RPGResult.ok()
	var r: Dictionary = await ctx.ui.run_contract_scene(ctx.ui.scene_path("shop"), {"goods": goods, "buy_only": args.get("buy_only", false)}, {"rpg": ctx.rpg}, ctx.token)
	if r.status == "error":
		return RPGResult.error(str(r.value))
	return RPGResult.cancelled() if ctx.is_cancelled() else RPGResult.ok()
