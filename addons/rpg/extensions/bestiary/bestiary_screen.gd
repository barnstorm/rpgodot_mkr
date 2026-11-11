extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## The bestiary (bestiary plugin): category tabs and completion along the top, the enemy list on
## the left, the chosen enemy on the right (picture, stats, EXP and gold, weaknesses and
## resistances, drops, lore). Up/down choose an enemy, left/right a category, Cancel closes.
## Mouse: hover a row or a tab to choose it, a click on the chosen row is OK (nothing more to
## open), right click closes.

signal closed()

const LIST_W := 112.0
const TOP_H := 20.0
const MASK := "??????"
const WEAK_COLOUR := Color(1.0, 0.55, 0.45)
const RESIST_COLOUR := Color(0.55, 0.8, 1.0)

var plugin: Object
var tab := 0
var tabs: Array = []
var ids: Array = []
var list: Control
var _tab_rects: Array = []
var _tab_row: Control
var _completion: Label
var _detail: Panel
var _done := false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var top := make_window(Rect2(0, 0, W, TOP_H))
	_tab_row = Control.new()
	_tab_row.position = Vector2(4, 2)
	_tab_row.size = Vector2(W - 110, 16)
	_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_tab_row)
	_completion = make_label(top, Vector2(W - 106, 4), "", SMALL, null, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	var lw := make_window(Rect2(0, TOP_H, LIST_W, H - TOP_H))
	list = make_list(lw, Rect2(4, 6, LIST_W - 8, H - TOP_H - 12))
	_detail = make_window(Rect2(LIST_W, TOP_H, W - LIST_W, H - TOP_H))


func setup(p_plugin: Object) -> void:
	plugin = p_plugin
	tabs = plugin.categories()
	_refresh_tabs()
	_fill_list(false)


func _refresh_tabs() -> void:
	for n in _tab_row.get_children():
		n.queue_free()
	_tab_rects.clear()
	var x := 0.0
	for i in tabs.size():
		var label := str(tabs[i].label)
		var w := _text_w(label, SMALL) + 10
		if x + w > _tab_row.size.x:
			break
		var bg := ColorRect.new()
		bg.position = Vector2(x, 0)
		bg.size = Vector2(w, 15)
		bg.color = Color(1, 1, 1, 0.18) if i == tab else Color(0, 0, 0, 0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tab_row.add_child(bg)
		make_label(_tab_row, Vector2(x + 5, 1), label, SMALL, colour(0) if i == tab else Color(1, 1, 1, 0.6))
		_tab_rects.append(Rect2(_tab_row.position + Vector2(x, 0), Vector2(w, 15)))
		x += w + 2
	var c: Dictionary = plugin.completion(str(tabs[tab].id))
	_completion.text = "%d/%d  %d%%" % [c.defeated, c.total, c.percent]


func _fill_list(keep: bool) -> void:
	ids = plugin.ids_in(str(tabs[tab].id))
	var items := []
	var check: Texture2D = _icon("check")
	for i in ids.size():
		var id: String = ids[i]
		var k: String = plugin.known(id)
		var nm := str(record("enemies", id).get("name", id)) if plugin.reveals(id, "name") else MASK
		var it := {"text": "%03d %s" % [i + 1, nm], "data": id, "enabled": k != "none"}
		if k == "defeated" and check != null:
			it["right_icon"] = check
			it["right"] = " "
		items.append(it)
	list.set_items(items, keep)
	list.active = true
	_refresh_detail()


func current_id() -> String:
	var it: Dictionary = list.current()
	return str(it.get("data", "")) if not it.is_empty() else ""


# --- details -------------------------------------------------------------------------------------

func _refresh_detail() -> void:
	for n in _detail.get_children():
		n.queue_free()
	var id := current_id()
	if id == "":
		make_label(_detail, Vector2(8, 8), "No entries yet.", FONT, Color(1, 1, 1, 0.6), W - LIST_W - 16)
		return
	var rec := record("enemies", id)
	var dw: float = _detail.size.x
	var num := ids.find(id) + 1
	make_label(_detail, Vector2(8, 4), str(rec.get("name", id)) if plugin.reveals(id, "name") else MASK, FONT, null, dw - 60)
	make_label(_detail, Vector2(dw - 52, 5), "No.%03d" % num, SMALL, system_colour(), 44, HORIZONTAL_ALIGNMENT_RIGHT)
	_picture(id, rec, Rect2(8, 20, 72, 64))
	var b: Object = plugin.enemy_battler(id) if plugin.reveals(id, "stats") else null
	# Stats beside the picture: the resources' maximums, then the stats, two columns.
	var entries := []
	if b != null:
		for res in resource_ids():
			var m := max_res(b, res)
			if m > 0:
				entries.append([res_label(res), str(m)])
		for s in rules().stats():
			var sid := str(s.get("id", ""))
			if sid in ["mhp", "msp", "mmp"]:
				continue
			entries.append([stat_label(sid), str(rules().effective_stat(b, sid))])
	var x0 := 86.0
	var cw := (dw - x0 - 8) / 2.0
	for i in mini(entries.size(), 10):
		var e: Array = entries[i]
		var x := x0 + (i % 2) * cw
		var y := 20.0 + (i / 2) * 11.0
		make_label(_detail, Vector2(x, y), str(e[0]), SMALL, system_colour(), 34)
		make_label(_detail, Vector2(x + 30, y), str(e[1]), SMALL, null, cw - 34, HORIZONTAL_ALIGNMENT_RIGHT)
	if b == null:
		make_label(_detail, Vector2(x0, 20), MASK, SMALL, Color(1, 1, 1, 0.5))
	var y2 := 88.0
	var all: bool = plugin.reveals(id, "all")
	make_label(_detail, Vector2(8, y2), term("exp", "EXP"), SMALL, system_colour())
	make_label(_detail, Vector2(30, y2), str(int(rec.get("exp", 0))) if all else "?", SMALL, null, 34)
	make_label(_detail, Vector2(70, y2), currency(), SMALL, system_colour())
	make_label(_detail, Vector2(84, y2), str(int(rec.get("gold", 0))) if all else "?", SMALL, null, 40)
	make_label(_detail, Vector2(dw - 80, y2), "Defeated %d" % int(plugin.defeated_count(id)), SMALL, Color(1, 1, 1, 0.75), 72, HORIZONTAL_ALIGNMENT_RIGHT)
	# Weaknesses and resistances (element rates).
	y2 += 13
	var weak := []
	var resist := []
	if all:
		for r in plugin.element_rates(id):
			(weak if float(r.rate) > 1.0 else resist).append(r)
	_element_row(Vector2(8, y2), "Weak", weak, WEAK_COLOUR, all)
	_element_row(Vector2(8, y2 + 13), "Resist", resist, RESIST_COLOUR, all)
	# Drops.
	y2 += 28
	make_label(_detail, Vector2(8, y2), "Drops", SMALL, system_colour())
	var drops: Array = rec.get("drops", []) if all else []
	if not all:
		make_label(_detail, Vector2(44, y2), MASK, SMALL, Color(1, 1, 1, 0.5))
	elif drops.is_empty():
		make_label(_detail, Vector2(44, y2), "—", SMALL, Color(1, 1, 1, 0.5))
	for i in mini(drops.size(), 3):
		var d: Dictionary = drops[i]
		var kind := RPGGameState.kind_for(str(d.get("kind", "item")))
		var drec := record(kind, str(d.get("id", "")))
		var xx := 44.0
		var ic := record_icon(drec)
		if ic != null:
			_icon_rect(Vector2(xx, y2 + 1), ic)
			xx += 13
		make_label(_detail, Vector2(xx, y2), str(drec.get("name", d.get("id", ""))), SMALL, null, dw - xx - 44)
		make_label(_detail, Vector2(dw - 40, y2), "%d%%" % int(d.get("chance", 100)), SMALL, Color(1, 1, 1, 0.7), 32, HORIZONTAL_ALIGNMENT_RIGHT)
		y2 += 12
	if drops.size() <= 1:
		y2 += 12
	# Lore.
	var lore := str(plugin.custom(id, "lore", ""))
	if lore != "" and all:
		var l := make_label(_detail, Vector2(8, y2 + 2), RPGText.expand_plain(lore, plugin.rpg), SMALL, Color(1, 1, 1, 0.9))
		# Wrapping first: without it the label's minimum width is the whole line.
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.clip_text = true
		l.size = Vector2(dw - 16, _detail.size.y - y2 - 8)


func _element_row(pos: Vector2, label: String, rates: Array, col: Color, known: bool) -> void:
	make_label(_detail, pos, label, SMALL, system_colour())
	var x := pos.x + 36
	if not known:
		make_label(_detail, Vector2(x, pos.y), MASK, SMALL, Color(1, 1, 1, 0.5))
		return
	if rates.is_empty():
		make_label(_detail, Vector2(x, pos.y), "—", SMALL, Color(1, 1, 1, 0.5))
		return
	for r in rates:
		var ic := _element_icon(r)
		if ic != null:
			_icon_rect(Vector2(x, pos.y + 1), ic)
			x += 13
		var txt := "%s %d%%" % [str(r.name) if ic == null else "", roundi(float(r.rate) * 100.0)]
		var w := _text_w(txt.strip_edges(), SMALL) + 6
		make_label(_detail, Vector2(x, pos.y), txt.strip_edges(), SMALL, col)
		x += w
		if x > _detail.size.x - 30:
			break


## An element's icon: its type entry's "icon", else the starter icon of the same name.
func _element_icon(r: Dictionary) -> Texture2D:
	if plugin == null or not RPGIcons.enabled(plugin.rpg.data):
		return null
	var i := RPGIcons.icon_index({"icon": r.get("icon", 0)})
	if i <= 0:
		i = RPGIcons.find(str(r.id))
	return RPGIcons.texture(i, 12) if i > 0 else null


## The picture: the battler image (scaled to fit), a dark silhouette for an enemy not yet shown,
## or a question mark.
func _picture(id: String, rec: Dictionary, box: Rect2) -> void:
	var frame := ColorRect.new()
	frame.color = Color(0, 0, 0, 0.3)
	frame.position = box.position
	frame.size = box.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(frame)
	var shown: bool = plugin.reveals(id, "image")
	var mask := str(plugin.setting("mask", "silhouette"))
	if not shown and (mask != "silhouette" or plugin.known(id) != "none"):
		var q := make_label(frame, Vector2.ZERO, "?", 30, Color(1, 1, 1, 0.35), box.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		q.size = box.size
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return
	var tex := _battler_texture(rec)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if tex.get_width() <= box.size.x * 1.5 else CanvasItem.TEXTURE_FILTER_LINEAR
	tr.size = box.size - Vector2(4, 4)
	tr.position = Vector2(2, 2)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not shown:
		tr.modulate = Color(0, 0, 0, 0.85)
	frame.add_child(tr)


func _battler_texture(rec: Dictionary) -> Texture2D:
	var name_ := str(rec.get("battler", ""))
	var tex: Texture2D = null
	if name_ != "" and rpg != null and rpg.ui != null:
		tex = rpg.ui.load_texture("battler", name_)
		if tex != null and RPGAssets.sheet_profile("battler", name_, str(rpg.data.profile.get("profile", "rm2k"))) == "rm2k":
			tex = RPGCharset.prepared_texture(tex)
	return tex if tex != null else _blob(str(rec.get("id", "")))


## A plain round shape for enemies without a picture.
static func _blob(id: String) -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(float(hash(id) % 360) / 360.0, 0.5, 0.75)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, (y - 18.0) * 1.3).length()
			if d < 14.0:
				img.set_pixel(x, y, c.darkened(0.3 * d / 14.0))
	return ImageTexture.create_from_image(img)


# --- input ---------------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done:
		return
	match a:
		"up", "down":
			if list.move(0, -1 if a == "up" else 1):
				play("cursor")
				_refresh_detail()
		"left", "right":
			if tabs.size() > 1:
				set_tab(posmod(tab + (-1 if a == "left" else 1), tabs.size()))
				play("cursor")
		"ok":
			play("buzzer" if current_id() == "" else "cursor")
		"cancel":
			play("cancel")
			close()


func set_tab(i: int) -> void:
	tab = clampi(i, 0, tabs.size() - 1)
	_refresh_tabs()
	_fill_list(false)


func close() -> void:
	if _done:
		return
	_done = true
	closed.emit()


func pointer_targets() -> Array:
	if _done:
		return []
	var out := list_targets(list)
	for i in _tab_rects.size():
		var ti := i
		var r: Rect2 = _tab_rects[i]
		out.append({"rect": local_xform(_tab_row.get_parent()) * r, "selected": tab == i, "select": func() -> void:
			set_tab(ti)
			play("cursor")})
	return out


func on_pointer_moved(_l: Control) -> void:
	_refresh_detail()


# --- helpers -------------------------------------------------------------------------------------

func _icon(icon_name: String) -> Texture2D:
	if plugin == null or not RPGIcons.enabled(plugin.rpg.data):
		return null
	var i := RPGIcons.find(icon_name)
	return RPGIcons.texture(i, 12) if i > 0 else null


func _icon_rect(pos: Vector2, tex: Texture2D) -> void:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = pos
	tr.size = Vector2(12, 12)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(tr)
