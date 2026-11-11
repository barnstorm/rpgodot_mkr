extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## The quest journal (quests plugin): Active, Completed and Failed tabs, the quests of the tab on
## the left, and the chosen quest on the right (icon, name, category, giver, location,
## description, objectives with check marks, rewards). OK on an active quest tracks it (OK again
## stops tracking). Left/right change the tab; Cancel closes.
## Mouse as in the other screens: hover moves the cursor, click the chosen row for OK, click a tab
## to show it, right click closes, the wheel scrolls.
## Run Scene contract: start(args, context), finished(result) when closed (result {tracked}).

signal finished(result: Variant)
signal cancelled(reason: String)

const TABS := ["active", "completed", "failed"]
const TAB_LABELS := {"active": "Active", "completed": "Completed", "failed": "Failed"}
const MARK := preload("res://addons/rpg/extensions/quests/quest_mark.gd")
const LIST_W := 124.0
const DETAIL_X := 126.0

var tab := "active"
var list: Control
var tab_labels := {}
var detail: Control
var _done := false


func start(args: Dictionary, context: Variant = null) -> void:
	if rpg == null and context is Dictionary and context.has("rpg"):
		rpg = context.rpg
	if TABS.has(str(args.get("tab", ""))):
		tab = str(args.tab)
	refresh(false)


func plugin() -> Object:
	return rpg.extension("quests") if rpg != null else null


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.94)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var tw := make_window(Rect2(0, 0, W, 24))
	for i in TABS.size():
		var key: String = TABS[i]
		tab_labels[key] = make_label(tw, Vector2(i * W / 3.0, 5), "", FONT, null, W / 3.0, HORIZONTAL_ALIGNMENT_CENTER)
	var lw := make_window(Rect2(0, 26, LIST_W, H - 26))
	list = make_list(lw, Rect2(5, 6, LIST_W - 10, H - 38))
	list.font_size = 10
	var dw := make_window(Rect2(DETAIL_X, 26, W - DETAIL_X, H - 26))
	detail = Control.new()
	detail.position = Vector2(8, 6)
	detail.size = Vector2(W - DETAIL_X - 16, H - 38)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dw.add_child(detail)
	refresh(false)


## Rebuilds the tab titles, the list and the detail pane.
func refresh(keep := true) -> void:
	if list == null or rpg == null or plugin() == null:
		return
	var p := plugin()
	for key in TABS:
		var n: int = p.quests_with(key).size()
		var l: Label = tab_labels[key]
		l.text = "%s (%d)" % [TAB_LABELS[key], n]
		l.add_theme_color_override("font_color", colour(4) if key == tab else Color(1, 1, 1, 0.5))
	var items := []
	for qid in p.quests_with(tab):
		var rec: Dictionary = p.quest(qid)
		var it := {"text": p.quest_name(qid), "data": qid, "icon": record_icon(rec)}
		if qid == p.tracked() and tab == "active":
			it["colour"] = colour(4)
		items.append(it)
	list.set_items(items, keep)
	show_detail()


## The quest under the cursor ("" when the tab is empty).
func current_quest() -> String:
	var it: Dictionary = list.current() if list != null else {}
	return str(it.get("data", ""))


func show_detail() -> void:
	for c in detail.get_children():
		detail.remove_child(c)
		c.queue_free()
	var p := plugin()
	var qid := current_quest()
	var w := detail.size.x
	if qid == "":
		var none := make_label(detail, Vector2(0, 2), "No %s quests." % TAB_LABELS[tab].to_lower(), FONT, Color(1, 1, 1, 0.6), w)
		none.name = "Empty"
		return
	var rec: Dictionary = p.quest(qid)
	var x := 0.0
	var icon := record_icon(rec)
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(0, 2)
		tr.size = Vector2(12, 12)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.add_child(tr)
		x = 15.0
	var title := make_label(detail, Vector2(x, 0), p.quest_name(qid), FONT, colour(4) if qid == p.tracked() and tab == "active" else null, w - x)
	title.name = "Title"
	var info := PackedStringArray()
	for k in ["category", "giver", "location"]:
		var v := str(rec.get(k, "")).strip_edges()
		if v != "":
			info.append(v)
	var y := 16.0
	if not info.is_empty():
		make_label(detail, Vector2(0, y), " · ".join(info), SMALL, system_colour(), w)
		y += 12.0
	var text := RPGText.expand_plain(str(rec.get("description", "")), rpg).strip_edges()
	if text != "":
		var desc := Label.new()
		desc.name = "Description"
		desc.text = text
		# Wrap first: without it the width would grow to fit the text on one line.
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(0, y)
		desc.size = Vector2(w, 10)
		desc.add_theme_font_size_override("font_size", SMALL)
		desc.add_theme_constant_override("line_spacing", 0)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc.max_lines_visible = 6
		detail.add_child(desc)
		var lines := clampi(desc.get_line_count(), 1, 6)
		desc.size.y = lines * 11.0
		y += lines * 11.0 + 4.0
	var shown := []
	for o in p.objectives(qid):
		if o.state != "hidden":
			shown.append(o)
	if not shown.is_empty():
		make_label(detail, Vector2(0, y), "Objectives", SMALL, system_colour(), w)
		y += 12.0
	var rewards := RPGText.expand_plain(str(rec.get("rewards", "")), rpg).strip_edges()
	var bottom := detail.size.y - (24.0 if rewards != "" else 12.0)
	for o in shown:
		if y + 11.0 > bottom:
			make_label(detail, Vector2(12, y), "...", SMALL, null, w - 12)
			break
		var m: Control = MARK.new()
		m.name = "Mark_%s" % o.id
		m.state = str(o.state)
		m.position = Vector2(1, y + 2)
		m.size = Vector2(7, 7)
		detail.add_child(m)
		var ol := make_label(detail, Vector2(12, y), str(o.text), SMALL, Color(1, 1, 1, 0.55) if o.state == "completed" else null, w - 12)
		ol.name = "Objective_%s" % o.id
		y += 11.0
	if rewards != "":
		make_label(detail, Vector2(0, detail.size.y - 24), "Rewards: " + rewards.replace("\n", ", "), SMALL, system_colour(), w).name = "Rewards"
	var hint := ""
	if tab == "active":
		hint = "Tracking  (OK: stop)" if qid == p.tracked() else "OK: track this quest"
	if hint != "":
		var hl := make_label(detail, Vector2(0, detail.size.y - 12), hint, SMALL, Color(1, 1, 1, 0.55), w, HORIZONTAL_ALIGNMENT_RIGHT)
		hl.name = "Hint"


func set_tab(key: String, sound := true) -> void:
	if key == tab or not TABS.has(key):
		return
	tab = key
	if sound:
		play("cursor")
	refresh(false)


# --- input ---------------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done:
		return
	match a:
		"left", "right":
			var i := TABS.find(tab)
			set_tab(TABS[posmod(i + (1 if a == "right" else -1), TABS.size())])
		"up", "down":
			if list.move(0, -1 if a == "up" else 1):
				play("cursor")
				show_detail()
		"ok":
			var qid := current_quest()
			if qid == "" or tab != "active":
				play("buzzer")
				return
			play("decision")
			plugin().track("" if plugin().tracked() == qid else qid)
			refresh()
		"cancel":
			play("cancel")
			close()


func pointer_targets() -> Array:
	if _done:
		return []
	var out := list_targets(list)
	for k in tab_labels:
		var key: String = k
		var l: Control = tab_labels[k]
		out.append({"rect": local_xform(l) * Rect2(Vector2.ZERO, l.size), "selected": tab == key, "select": func() -> void: set_tab(key), "ok": func() -> void: pass})
	return out


func on_pointer_moved(l: Control) -> void:
	if l == list:
		show_detail()


func close() -> void:
	if _done:
		return
	_done = true
	finished.emit({"tracked": plugin().tracked() if plugin() != null else ""})
