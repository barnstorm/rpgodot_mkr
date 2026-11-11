extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Playtest debug screen (F9). Pages: Switches (OK toggles), Variables (Left/Right +/-1,
## OK enters edit mode where Up/Down are +/-10; bools toggle; strings open a text field) and
## Events (scheduler snapshot and the last error). Cancel steps back; emits closed.

signal closed()

const PAGES := ["switches", "variables", "events"]
const PAGE_LABELS := {"switches": "Switches", "variables": "Variables", "events": "Events"}

var page_list: Control
var list: Control
var info: Label
var help: Label
var focus := "pages"         # pages, list, edit, text
var page := "switches"
var ids: Array = []
var line_edit: LineEdit
var _refresh_t := 0.0
var _done := false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var pw := make_window(Rect2(0, 0, 80, 16 + PAGES.size() * ROW))
	page_list = make_list(pw, Rect2(4, 8, 72, PAGES.size() * ROW))
	page_list.show_inactive_cursor = true
	var items := []
	for p in PAGES:
		items.append({"text": PAGE_LABELS[p]})
	page_list.set_items(items)
	var tw := make_window(Rect2(0, 16 + PAGES.size() * ROW + 2, 80, 40))
	make_label(tw, Vector2(6, 4), "DEBUG", FONT, colour(C_BAD))
	make_label(tw, Vector2(6, 18), "playtest", SMALL, Color(1, 1, 1, 0.6))
	var lw := make_window(Rect2(82, 0, W - 82, 200))
	list = make_list(lw, Rect2(4, 6, W - 82 - 8, 188))
	list.font_size = 10
	list.row_h = 13
	list.active = false
	info = make_label(lw, Vector2(8, 6), "", SMALL, null, W - 82 - 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size.y = 188
	info.clip_text = true
	info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var hw := make_window(Rect2(0, 202, W, 38))
	help = make_label(hw, Vector2(8, 4), "", SMALL, null, W - 16)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size.y = 30
	_show_page()


func _show_page() -> void:
	page = PAGES[page_list.index]
	list.visible = page != "events"
	info.visible = page == "events"
	match page:
		"switches":
			ids = rpg.data.switches.keys() if rpg and rpg.data else []
		"variables":
			ids = rpg.data.variables.keys() if rpg and rpg.data else []
		_:
			ids = []
	_refresh_list(false)
	_refresh_help()


func _label_for(defs: Dictionary, id: String) -> String:
	var d: Variant = defs.get(id, {})
	var l := str(d.get("label", "")) if d is Dictionary else ""
	return id if l == "" or l == id else "%s (%s)" % [l, id]


func _refresh_list(keep := true) -> void:
	if page == "events":
		_refresh_events()
		return
	var items := []
	for id in ids:
		if page == "switches":
			var on: bool = rpg.state.get_switch(id)
			items.append({"text": _label_for(rpg.data.switches, id), "right": "ON" if on else "OFF", "right_colour": colour(4) if on else Color(1, 1, 1, 0.55)})
		else:
			var v: Variant = rpg.state.get_variable(id)
			var t: String = rpg.state.variable_type(id)
			var shown := ("\"%s\"" % v) if t == "string" else str(v)
			if t == "bool":
				shown = "ON" if bool(v) else "OFF"
			items.append({"text": _label_for(rpg.data.variables, id), "right": shown, "right_colour": colour(4) if focus == "edit" and items.size() == list.index else colour(0)})
	if items.is_empty():
		items.append({"text": "(none defined)", "enabled": false})
	list.set_items(items, keep)


func _refresh_events() -> void:
	var lines := []
	if rpg and rpg.scheduler:
		var s: Dictionary = rpg.scheduler.debug_snapshot()
		lines.append("Main: %s [%s]" % [s.get("main", "") if str(s.get("main", "")) != "" else "-", s.get("main_state", "")])
		var q: Array = s.get("queue", [])
		lines.append("Queue: %s" % (", ".join(PackedStringArray(q.map(func(x): return str(x)))) if not q.is_empty() else "-"))
		var par: Dictionary = s.get("parallels", {})
		lines.append("Parallels: %d" % par.size())
		for k in par:
			lines.append("  %s  %s  rounds %d" % [k, par[k].get("state", ""), int(par[k].get("rounds", 0))])
		var locks: Variant = s.get("locks", {})
		lines.append("Input locks: %s" % (str(locks) if not (locks is Dictionary and locks.is_empty()) and not (locks is Array and locks.is_empty()) else "-"))
	var m: Node = rpg.current_map() if rpg else null
	if m != null:
		var p: Node = m.get("player")
		lines.append("Map: %s%s" % [m.get("map_id"), ("  player %s" % str(p.cell)) if p != null else ""])
	lines.append("Gold: %d   Play time: %s" % [rpg.state.gold, format_time(rpg.state.play_time)])
	lines.append_array(event_inspector_lines(m))
	lines.append("")
	lines.append("Last error:")
	lines.append(rpg.last_error if rpg and rpg.last_error != "" else "(none)")
	info.text = "\n".join(PackedStringArray(lines))


## The event in front of the player (or under them): its pages and why each one is or is not active.
func event_inspector_lines(m: Node) -> Array:
	var out := []
	if m == null or m.get("player") == null:
		return out
	var p: Node = m.player
	var target: Node = null
	for c in [p.front_cell(), p.cell]:
		for ev in m.events_at(c):
			if ev.has_method("debug_info"):
				target = ev
				break
		if target != null:
			break
	if target == null:
		out.append("Facing: no event")
		return out
	var d: Dictionary = target.debug_info()
	out.append("Facing: %s (%s) at %s" % [d.name, d.id, str(d.cell)])
	if d.erased:
		out.append("  erased until the map reloads")
	elif d.page < 0:
		out.append("  no page is active (all conditions false)")
	else:
		out.append("  page %d, %s, %s%s" % [d.page + 1, d.trigger, d.priority, ", RUNNING" if d.running else ""])
	if str(d.get("running_command", "")) != "":
		out.append("  %s: %s" % [d.interpreter, d.running_command])
	if str(d.get("last_trigger", "")) != "":
		out.append("  last started by: %s" % d.last_trigger)
	if str(d.get("movement_blocked", "")) != "":
		out.append("  movement: %s" % d.movement_blocked)
	for pi in d.pages:
		out.append("  p%d %s %s" % [pi.index + 1, "ok " if pi.ok else "no ", pi.trigger if pi.ok else "(" + pi.failing + ")"])
	return out


func _refresh_help() -> void:
	var t := ""
	match focus:
		"pages":
			t = "Up/Down: page   OK: open   Cancel: close"
		"list":
			if page == "switches":
				t = "OK: toggle the switch   Cancel: back"
			elif page == "variables":
				t = "Left/Right: -1/+1   OK: edit (Up/Down -10/+10)   Cancel: back"
			else:
				t = "Cancel: back"
		"edit":
			t = "Left/Right: -1/+1   Up/Down: -10/+10   OK/Cancel: done"
		"text":
			t = "Type the new text, Enter to set it, Esc to cancel."
	help.text = t


func _update(delta: float) -> void:
	if line_edit != null and Input.is_key_pressed(KEY_ESCAPE):
		_end_text_edit(false)
	_refresh_t += delta
	if page == "events" and _refresh_t > 0.5:
		_refresh_t = 0.0
		_refresh_events()


func current_id() -> String:
	return str(ids[list.index]) if list.index < ids.size() else ""


func handle_action(a: String) -> void:
	if _done:
		return
	match focus:
		"pages":
			match a:
				"up", "down":
					if page_list.move(0, -1 if a == "up" else 1):
						play("cursor")
						_show_page()
				"ok":
					if page == "events" or not ids.is_empty():
						play("decision")
						focus = "list"
						page_list.active = false
						list.active = page != "events"
						list.select(0)
						_refresh_help()
					else:
						play("buzzer")
				"cancel":
					play("cancel")
					_done = true
					closed.emit()
		"list":
			match a:
				"up", "down":
					if list.move(0, -1 if a == "up" else 1):
						play("cursor")
				"left", "right":
					if page == "variables":
						step_variable(current_id(), -1 if a == "left" else 1)
				"ok":
					if page == "switches":
						toggle_switch(current_id())
					elif page == "variables":
						_begin_edit(current_id())
				"cancel":
					play("cancel")
					focus = "pages"
					page_list.active = true
					list.active = false
					_refresh_list()
					_refresh_help()
		"edit":
			match a:
				"left", "right":
					step_variable(current_id(), -1 if a == "left" else 1)
				"up", "down":
					step_variable(current_id(), 10 if a == "up" else -10)
				"ok", "cancel":
					play("decision" if a == "ok" else "cancel")
					focus = "list"
					_refresh_list()
					_refresh_help()


func toggle_switch(id: String) -> void:
	if id == "":
		return
	rpg.set_switch(id, not rpg.get_switch(id))
	play("decision")
	_refresh_list()


## Changes a variable by `delta` steps according to its type (int, float: 0.1 per step, bool:
## toggles). Strings are not stepped.
func step_variable(id: String, delta: int) -> void:
	if id == "":
		return
	var t: String = rpg.state.variable_type(id)
	var v: Variant = rpg.get_variable(id)
	match t:
		"int":
			rpg.set_variable(id, int(v) + delta)
		"float":
			rpg.set_variable(id, snappedf(float(v) + 0.1 * delta, 0.001))
		"bool":
			rpg.set_variable(id, not bool(v))
		_:
			play("buzzer")
			return
	play("cursor")
	_refresh_list()


func _begin_edit(id: String) -> void:
	if id == "":
		return
	var t: String = rpg.state.variable_type(id)
	if t == "bool":
		step_variable(id, 1)
		return
	play("decision")
	if t == "string":
		_begin_text_edit(id)
		return
	focus = "edit"
	_refresh_list()
	_refresh_help()


func _begin_text_edit(id: String) -> void:
	focus = "text"
	input_enabled = false
	var r: Rect2 = list.item_rect(list.index)
	line_edit = LineEdit.new()
	line_edit.text = str(rpg.get_variable(id))
	line_edit.add_theme_font_size_override("font_size", 10)
	line_edit.position = list.global_position + r.position + Vector2(60, -2)
	line_edit.size = Vector2(r.size.x - 60, 16)
	line_edit.set_meta("var_id", id)
	add_child(line_edit)
	line_edit.text_submitted.connect(func(_t): _end_text_edit(true))
	line_edit.grab_focus()
	line_edit.select_all()
	_refresh_help()


func _end_text_edit(apply: bool) -> void:
	if line_edit == null:
		return
	var le := line_edit
	line_edit = null
	if apply:
		rpg.set_variable(str(le.get_meta("var_id")), le.text)
		play("decision")
	else:
		play("cancel")
	le.queue_free()
	focus = "list"
	_refresh_list()
	_refresh_help()
	# Wait a frame so the Enter/Escape that ended editing does not reach the list.
	await get_tree().process_frame
	input_enabled = true
