extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## The crafting screen (crafting plugin). Left: the recipes (greyed out when the party lacks an
## ingredient; masked, greyed or left out until known, see the "unknown" setting). Right: each
## ingredient with how many the party has and needs, then what one craft makes. OK chooses how
## many to make (up/down 1, left/right 10), OK again makes them.
## Mouse as in the other screens (hover, click the chosen row, click the quantity window to make).
## Run Scene contract: start({categories: [...]}, context), finished({made: [{kind, id, count}]}).

signal finished(result: Variant)
signal cancelled(reason: String)

const MASK := "??????"
## Have/need when the party has too few (red whatever the window skin's palette).
const SHORT_COLOUR := Color(1.0, 0.45, 0.42)
const LIST_W := 172.0

var categories: Array = []
var mode := "list"            # list, quantity
var qty := 1
var qty_max := 1
var made: Array = []

var help: Label
var list: Control
var info: Control
var owned_label: Label
var qty_win: Panel
var qty_name: Label
var qty_value: Label
var _done := false


func start(args: Dictionary, context: Variant = null) -> void:
	if rpg == null and context is Dictionary and context.has("rpg"):
		rpg = context.rpg
	var c: Variant = args.get("categories", [])
	if c is String:
		c = Array(str(c).split(",", false))
	categories = c if c is Array else []
	refresh(false)


func plugin() -> Object:
	return rpg.extension("crafting") if rpg != null else null


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.94)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var hw := make_window(Rect2(0, 0, W, 26))
	help = make_label(hw, Vector2(8, 5), "", FONT, null, W - 16)
	var lw := make_window(Rect2(0, 28, LIST_W, H - 28))
	list = make_list(lw, Rect2(6, 7, LIST_W - 12, H - 42))
	list.show_inactive_cursor = true
	var iw := make_window(Rect2(LIST_W + 2, 28, W - LIST_W - 2, 166))
	info = Control.new()
	info.position = Vector2(7, 6)
	info.size = Vector2(W - LIST_W - 16, 154)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iw.add_child(info)
	var ow := make_window(Rect2(LIST_W + 2, 196, W - LIST_W - 2, 44))
	owned_label = make_label(ow, Vector2(7, 6), "", SMALL, null, W - LIST_W - 16)
	owned_label.size.y = 32
	owned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	owned_label.clip_text = false
	qty_win = make_window(Rect2(24, 96, 140, 48))
	qty_name = make_label(qty_win, Vector2(8, 6), "", FONT, null, 124)
	qty_value = make_label(qty_win, Vector2(8, 24), "", FONT, colour(4), 124, HORIZONTAL_ALIGNMENT_RIGHT)
	qty_win.visible = false
	refresh(false)


## What the "unknown" setting does with recipes that are not known yet: mask, grey, hide, show.
func unknown_mode() -> String:
	return str(plugin().setting("unknown", "mask")) if plugin() != null else "mask"


func _shown_name(kind: String, id: String) -> String:
	return str(record(kind, id).get("name", id))


func refresh(keep := true) -> void:
	if list == null or rpg == null or plugin() == null:
		return
	var p := plugin()
	var items := []
	for r in p.recipes(categories):
		var is_known: bool = p.known(r.kind, r.id) or unknown_mode() == "show"
		if not is_known and unknown_mode() == "hide":
			continue
		var masked := not is_known and unknown_mode() == "mask"
		var rec := record(r.kind, r.id)
		var can: bool = is_known and p.max_crafts(r.kind, r.id) > 0
		items.append({"text": MASK if masked else _shown_name(r.kind, r.id), "right": ":%d" % rpg.state.item_count(r.id, r.kind),
			"enabled": can, "icon": null if masked else record_icon(rec), "data": {"kind": r.kind, "id": r.id, "known": is_known, "masked": masked}})
	list.set_items(items, keep)
	_show_current()


func _show_current() -> void:
	for c in info.get_children():
		info.remove_child(c)
		c.queue_free()
	var it: Dictionary = list.current()
	var w := info.size.x
	if it.is_empty():
		help.text = "No recipes yet."
		owned_label.text = ""
		return
	var d: Dictionary = it.data
	var p := plugin()
	var r: Dictionary = p.recipe(d.kind, d.id)
	help.text = "You don't know how to make this yet." if not d.known else str(record(d.kind, d.id).get("description", ""))
	make_label(info, Vector2(0, 0), "Ingredients", SMALL, system_colour(), w)
	var y := 13.0
	for ing in r.get("ingredients", []):
		var have: int = rpg.state.item_count(ing.id, ing.kind)
		var need := int(ing.count)
		var ing_seen: bool = p.seen(ing.kind, ing.id) or unknown_mode() == "show"
		var rec := record(ing.kind, ing.id)
		var x := 0.0
		var icon := record_icon(rec) if ing_seen else null
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.position = Vector2(0, y + 1)
			tr.size = Vector2(10, 10)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(tr)
			x = 12.0
		var nl := make_label(info, Vector2(x, y), str(rec.get("name", ing.id)) if ing_seen else MASK, SMALL, null, w - x - 34)
		nl.name = "Ingredient_%s" % ing.id
		var cl := make_label(info, Vector2(w - 34, y), "%d/%d" % [have, need], SMALL, colour(C_NORMAL) if have >= need else SHORT_COLOUR, 34, HORIZONTAL_ALIGNMENT_RIGHT)
		cl.name = "Count_%s" % ing.id
		y += 12.0
		if y > info.size.y - 26:
			break
	var made_each := int(r.get("yield", 1))
	var line := "Makes %d" % made_each if d.masked else "Makes %d %s" % [made_each, _shown_name(d.kind, d.id)]
	make_label(info, Vector2(0, info.size.y - 12), line, SMALL, Color(1, 1, 1, 0.7), w)
	owned_label.text = "Owned %d   Made %d" % [rpg.state.item_count(d.id, d.kind), p.crafted_count(d.kind, d.id)]


# --- input ---------------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done:
		return
	match mode:
		"list":
			match a:
				"up", "down":
					if list.move(0, -1 if a == "up" else 1):
						play("cursor")
						_show_current()
				"ok":
					_choose()
				"cancel":
					play("cancel")
					close()
		"quantity":
			match a:
				"up", "right":
					_set_qty(qty + (1 if a == "up" else 10))
				"down", "left":
					_set_qty(qty - (1 if a == "down" else 10))
				"ok":
					_make()
				"cancel":
					play("cancel")
					_set_mode("list")


func _choose() -> void:
	var it: Dictionary = list.current()
	if it.is_empty() or not bool(it.get("enabled", true)):
		play("buzzer")
		return
	var d: Dictionary = it.data
	qty_max = mini(plugin().max_crafts(d.kind, d.id), maxi(1, int(plugin().setting("max_quantity", 99))))
	if qty_max <= 0:
		play("buzzer")
		return
	play("decision")
	qty_name.text = _shown_name(d.kind, d.id)
	_set_mode("quantity")
	_set_qty(1, false)


func _set_mode(m: String) -> void:
	mode = m
	list.active = m == "list"
	qty_win.visible = m == "quantity"


func _set_qty(n: int, sound := true) -> void:
	var before := qty
	qty = clampi(n, 1, maxi(qty_max, 1))
	if sound and qty != before:
		play("cursor")
	qty_value.text = "x %02d" % qty


func _make() -> void:
	var d: Dictionary = list.current().get("data", {})
	if d.is_empty() or not plugin().craft(d.kind, d.id, qty):
		play("buzzer")
		return
	var n := int(plugin().recipe(d.kind, d.id).get("yield", 1)) * qty
	made.append({"kind": d.kind, "id": d.id, "count": n})
	_set_mode("list")
	refresh()
	help.text = "Made %s x%d." % [_shown_name(d.kind, d.id), n]


## Makes the recipe under the cursor `times` times, as OK, OK would (tests).
func make_current(times := 1) -> bool:
	var it: Dictionary = list.current()
	if it.is_empty() or not bool(it.get("enabled", true)):
		return false
	_choose()
	if mode != "quantity":
		return false
	_set_qty(times, false)
	var before := made.size()
	_make()
	return made.size() > before


func pointer_targets() -> Array:
	if _done:
		return []
	if mode == "quantity":
		return [{"rect": local_xform(qty_win) * Rect2(Vector2.ZERO, qty_win.size), "selected": true, "select": func() -> void: pass}]
	return super.pointer_targets()


func on_pointer_moved(l: Control) -> void:
	if l == list:
		_show_current()


func close() -> void:
	if _done:
		return
	_done = true
	finished.emit({"made": made})
