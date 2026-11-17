@tool
extends RPGCommand
## Opens the party's items and waits for the player to pick one (RPG Maker's Select Item): the
## standard "which item do you use?" pattern. The chosen item's id lands in a variable — item ids
## are names, so use a text variable. Cancelling stores "" (0 in a number variable).


static func descriptor() -> Dictionary:
	return {
		"type": "select_item", "schema_version": 1, "category": "message", "label": "Select Item",
		"fields": [
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Store in", "required": true},
			{"key": "category", "kind": "choice", "options": ["key", "regular", "all"], "option_labels": ["Key items", "Regular items", "All items"], "default": "key", "label": "Which items"},
		],
	}


func summary(args: Dictionary) -> String:
	var cat: String = {"key": "key items", "regular": "regular items", "all": "any items"}.get(str(args.get("category", "key")), "key items")
	return "Select Item (%s) → [%s]" % [cat, args.get("variable", "?")]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var vid := str(args.get("variable", ""))
	var cat := str(args.get("category", "key"))
	var entries := []
	var inv: Dictionary = ctx.state.inventory.get("items", {})
	for id in inv:
		var n := int(inv[id])
		if n <= 0:
			continue
		var rec: Dictionary = ctx.data.record("items", str(id)) if ctx.data != null else {}
		var key := bool(rec.get("key_item", false))
		if cat == "key" and not key:
			continue
		if cat == "regular" and key:
			continue
		entries.append({"id": str(id), "name": str(rec.get("name", id)), "count": n})
	var box: Control = ctx.ui.message_box
	box.open_items(entries)
	var r: Dictionary = await ctx.wait_signal(box.item_selected)
	box.hide_box()
	if not r.ok:
		return RPGResult.cancelled()
	var picked := str(r.value)
	var t := ctx.state.variable_type(vid)
	var v: Variant = picked if picked != "" else ("" if t == "string" else 0)
	if not ctx.state.set_variable(vid, v):
		return RPGResult.error("Select Item: '%s' is a %s variable, but item ids are names; use a text variable." % [vid, t])
	return RPGResult.ok()
