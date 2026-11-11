extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## The formation screen (party_formation plugin): the battle row on the left, the reserve on the
## right, the chosen member's details below.
## OK on a member picks it up; OK on another member swaps the two, OK on an empty battle slot
## moves it into battle, OK on the reserve's empty slot moves it out (when the setting allows).
## Locked members cannot be picked; required members cannot go to the reserve; the battle row
## keeps at least one member. Cancel puts a picked member back, else closes the screen.
## Mouse: hover moves the cursor, a click on the selected slot is OK, right click is Cancel.

signal closed()

const ROW_H := 29.0
const LIST_Y := 20.0
const LIST_H := 132.0
const VISIBLE_ROWS := 4
const PICK_COLOUR := Color(1.0, 0.85, 0.35, 0.28)

var plugin: Object
## Cursor: column 0 (battle) or 1 (reserve), and the row in it.
var col := 0
var row := 0
## The member picked up ({col, row, id}), or {}.
var picked: Dictionary = {}
## Reserve column scroll (first row shown).
var top_row := 0
var active: Array = []
var reserve: Array = []
var help: Label
var _cols: Array = []          # [Panel battle, Panel reserve]
var _rows_root: Array = []     # row containers per column
var _cursor: Panel
var _detail: Panel
var _done := false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var top := make_window(Rect2(0, 0, W, LIST_Y))
	help = make_label(top, Vector2(8, 3), "", FONT, null, W - 16)
	for i in 2:
		var p := make_window(Rect2(i * W / 2.0, LIST_Y, W / 2.0, LIST_H))
		_cols.append(p)
		var title := make_label(p, Vector2(8, 3), "", SMALL, system_colour(), W / 2.0 - 16)
		title.name = "Title"
		var r := Control.new()
		r.position = Vector2(4, 14)
		r.size = Vector2(W / 2.0 - 8, ROW_H * VISIBLE_ROWS)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.clip_contents = true
		p.add_child(r)
		_rows_root.append(r)
	_cursor = Panel.new()
	if has_theme_stylebox("cursor", "RPGWindow"):
		_cursor.add_theme_stylebox_override("panel", get_theme_stylebox("cursor", "RPGWindow"))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.15)
		sb.border_color = Color(1, 1, 1, 0.85)
		sb.set_border_width_all(1)
		_cursor.add_theme_stylebox_override("panel", sb)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)
	_detail = make_window(Rect2(0, LIST_Y + LIST_H, W, H - LIST_Y - LIST_H))


func setup(p_plugin: Object) -> void:
	plugin = p_plugin
	_reload()
	(_cols[0].get_node("Title") as Label).text = "%s  (%d/%d)" % [term("battle_members", "Battle"), active.size(), plugin.max_battle()]
	(_cols[1].get_node("Title") as Label).text = term("reserve", "Reserve")
	_refresh()


func _reload() -> void:
	active = plugin.active_ids()
	reserve = plugin.reserve_ids()


## Slots in a column: the battle row has max_battle() slots ("" = empty); the reserve lists its
## members plus one empty slot when members may leave the battle row without a swap.
func slots(c: int) -> Array:
	if c == 0:
		var out := active.duplicate()
		while out.size() < plugin.max_battle():
			out.append("")
		return out
	var r := reserve.duplicate()
	if bool(plugin.setting("allow_remove", true)) or r.is_empty():
		r.append("")
	return r


func _refresh() -> void:
	(_cols[0].get_node("Title") as Label).text = "%s  (%d/%d)" % [term("battle_members", "Battle"), active.size(), plugin.max_battle()]
	row = clampi(row, 0, slots(col).size() - 1)
	if col == 1:
		if row < top_row:
			top_row = row
		elif row >= top_row + VISIBLE_ROWS:
			top_row = row - VISIBLE_ROWS + 1
	for c in 2:
		var root: Control = _rows_root[c]
		for n in root.get_children():
			n.queue_free()
		var list := slots(c)
		var first := top_row if c == 1 else 0
		for i in range(first, mini(list.size(), first + VISIBLE_ROWS)):
			_make_row(root, Vector2(0, (i - first) * ROW_H), str(list[i]), c, i)
	_place_cursor()
	_refresh_detail()
	_refresh_help()


func _make_row(parent: Control, pos: Vector2, id: String, c: int, i: int) -> void:
	var r := Control.new()
	r.position = pos
	r.size = Vector2(parent.size.x, ROW_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	if not picked.is_empty() and int(picked.col) == c and int(picked.row) == i:
		var hl := ColorRect.new()
		hl.color = PICK_COLOUR
		hl.size = r.size
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(hl)
	if id == "":
		var txt := "— %s —" % (term("empty", "empty") if c == 0 else term("to_reserve", "to reserve"))
		make_label(r, Vector2(30, 8), txt, SMALL, Color(1, 1, 1, 0.45), r.size.x - 34)
		return
	var b: Variant = plugin.rpg.state.actor(id)
	make_face(r, Vector2(2, 3), id, 24)
	var nm := actor_name(id)
	make_label(r, Vector2(30, 1), nm, FONT, status_colour(b) if b is Object else null, r.size.x - 56)
	if b is Object:
		make_label(r, Vector2(30, 15), "%s %d" % [term("level", "Lv"), int(b.level)], SMALL, system_colour(), 40)
		var m := max_res(b, life_res())
		make_gauge(r, Rect2(70, 20, r.size.x - 100, 3), float(b.get_resource(life_res())) / float(maxi(m, 1)), Color(1.0, 0.62, 0.25))
	var x := r.size.x - 15
	for mark in [["required_icon", plugin.is_required(id)], ["lock_icon", plugin.is_locked(id)]]:
		if not mark[1]:
			continue
		var tex := _setting_icon(str(mark[0]))
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.position = Vector2(x, 2)
			tr.size = Vector2(12, 12)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(tr)
		else:
			make_label(r, Vector2(x, 1), "*" if mark[0] == "required_icon" else "#", SMALL, Color(1, 0.9, 0.4))
		x -= 13


func _setting_icon(key: String) -> Texture2D:
	if plugin == null or not RPGIcons.enabled(plugin.rpg.data):
		return null
	var v: Variant = plugin.setting(key, 0)
	var i := RPGIcons.icon_index({"icon": v})
	return RPGIcons.texture(i, 12) if i > 0 else null


func _slot_rect(c: int, i: int) -> Rect2:
	var root: Control = _rows_root[c]
	var first := top_row if c == 1 else 0
	return Rect2(root.position + _cols[c].position + Vector2(0, (i - first) * ROW_H), Vector2(root.size.x, ROW_H))


func _place_cursor() -> void:
	var r := _slot_rect(col, row)
	_cursor.position = r.position - Vector2(1, 0)
	_cursor.size = r.size + Vector2(2, 0)


func current_id() -> String:
	var list := slots(col)
	return str(list[row]) if row >= 0 and row < list.size() else ""


func _refresh_detail() -> void:
	for n in _detail.get_children():
		n.queue_free()
	var id := current_id()
	if id == "":
		return
	var b: Variant = plugin.rpg.state.actor(id)
	make_face(_detail, Vector2(8, 10), id, 48)
	make_label(_detail, Vector2(64, 6), actor_name(id), FONT, null, 120)
	if not (b is Object):
		return
	make_label(_detail, Vector2(190, 7), "%s %d" % [term("level", "Lv"), int(b.level)], FONT, null, 60)
	make_label(_detail, Vector2(64, 20), str(record("classes", str(b.class_id)).get("name", "")), SMALL, Color(1, 1, 1, 0.75), 120)
	var y := 34.0
	var shown := 0
	for res in resource_ids():
		if shown >= 2:
			break
		var m := max_res(b, res)
		var v: int = b.get_resource(res)
		make_label(_detail, Vector2(64, y), res_label(res), SMALL, system_colour(), 22)
		make_gauge(_detail, Rect2(86, y + 6, 120, 4), float(v) / float(maxi(m, 1)), Color(1.0, 0.62, 0.25) if shown == 0 else Color(0.38, 0.68, 1.0))
		make_label(_detail, Vector2(210, y - 1), "%d/%d" % [v, m], SMALL, null, 60, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 13
		shown += 1
	var notes := []
	if plugin.is_required(id):
		notes.append(term("required", "Required"))
	if plugin.is_locked(id):
		notes.append(term("locked", "Locked"))
	if not notes.is_empty():
		make_label(_detail, Vector2(8, 62), ", ".join(PackedStringArray(notes)), SMALL, Color(1, 0.9, 0.4), 120)
	if not b.states.is_empty():
		make_states(_detail, Vector2(64, y + 1), b, W - 72, SMALL, colour(C_BAD))


func _refresh_help() -> void:
	if picked.is_empty():
		help.text = "Choose a member to move." if not _done else ""
	else:
		help.text = "Where should %s go?" % actor_name(str(picked.id))


# --- input ---------------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done:
		return
	match a:
		"up", "down":
			var n := slots(col).size()
			if n > 0:
				row = posmod(row + (-1 if a == "up" else 1), n)
				play("cursor")
				_refresh()
		"left", "right":
			# The cursor keeps its height on screen.
			var shown_at := row - (top_row if col == 1 else 0)
			col = 1 - col
			row = clampi(shown_at + (top_row if col == 1 else 0), 0, slots(col).size() - 1)
			play("cursor")
			_refresh()
		"ok":
			choose()
		"cancel":
			if not picked.is_empty():
				play("cancel")
				picked = {}
				_refresh()
			else:
				play("cancel")
				close()


## OK on the slot under the cursor: pick a member up, or put the picked one there.
func choose() -> void:
	var id := current_id()
	if picked.is_empty():
		if id == "" or plugin.is_locked(id):
			play("buzzer")
			return
		play("decision")
		picked = {"col": col, "row": row, "id": id}
		_refresh()
		return
	if int(picked.col) == col and int(picked.row) == row:
		play("cancel")
		picked = {}
		_refresh()
		return
	if not try_place(int(picked.col), int(picked.row), col, row):
		play("buzzer")
		return
	play("decision")
	picked = {}
	_refresh()


## Moves the member at (c1, r1) to slot (c2, r2): a swap with the member there, or a move into
## an empty slot. Returns false (nothing changes) when the rules forbid it.
func try_place(c1: int, r1: int, c2: int, r2: int) -> bool:
	var a := str(slots(c1)[r1])
	var b := str(slots(c2)[r2])
	if a == "" or plugin.is_locked(a) or (b != "" and plugin.is_locked(b)):
		return false
	var act := active.duplicate()
	var res := reserve.duplicate()
	var lists := [act, res]
	if b == "":
		# Into an empty slot: the end of that row.
		if c1 == c2:
			if c1 == 0:
				act.erase(a)
				act.append(a)
			else:
				return false
		elif c2 == 1:
			if plugin.is_required(a) or act.size() <= 1 or not bool(plugin.setting("allow_remove", true)):
				return false
			act.erase(a)
			res.append(a)
		else:
			if act.size() >= plugin.max_battle():
				return false
			res.erase(a)
			act.append(a)
	else:
		# A swap; a required member may not end up in the reserve.
		if c1 != c2 and ((c1 == 0 and plugin.is_required(a)) or (c2 == 0 and plugin.is_required(b))):
			return false
		var la: Array = lists[c1]
		var lb: Array = lists[c2]
		var ia := la.find(a)
		var ib := lb.find(b)
		la[ia] = b
		lb[ib] = a
	plugin.set_rows(act, res)
	_reload()
	return true


func close() -> void:
	if _done:
		return
	_done = true
	closed.emit()


# --- mouse ---------------------------------------------------------------------------------------

func pointer_targets() -> Array:
	var out := []
	if _done:
		return out
	for c in 2:
		var list := slots(c)
		var first := top_row if c == 1 else 0
		for i in range(first, mini(list.size(), first + VISIBLE_ROWS)):
			var cc := c
			var ii := i
			out.append({"rect": _slot_rect(c, i), "selected": col == c and row == i, "select": func() -> void:
				col = cc
				row = ii
				play("cursor")
				_refresh()})
	return out
