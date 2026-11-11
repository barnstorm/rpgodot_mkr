extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default save/load screen: numbered slots (1..rpg.saves.slot_count(), RPGSaveService.MAX_SLOTS
## unless an extension changes it), each showing the party faces, map name (or the description
## an event set, save header "description"), play time and date from rpg.saves.describe(slot).
## setup("save") saves with rpg.saves.save(slot); setup("load") loads with
## rpg.saves.load_slot(slot) and closes on success. A failed load shows why and the game
## continues unchanged. Emits closed once, then removes itself.

signal closed()

const SLOT_H := 70
const VISIBLE := 3

var mode := "save"
var index := 0
var top := 0
var help: Label
var slot_root: Control
var slot_panels: Array = []
var cursor_panel: Panel
## Last result of a save or load (tests).
var last_result: RPGResult = null
var _infos := {}
var _done := false
var _blocked := ""


func setup(p_mode: String) -> void:
	mode = "load" if p_mode == "load" else "save"
	if is_node_ready():
		_after_setup()


func _build() -> void:
	# Nearly opaque, so the menu or title under it never shows through translucent windows.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.94)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var hw := make_window(Rect2(0, 0, W, 26))
	help = make_label(hw, Vector2(8, 5), "", FONT, null, W - 16)
	slot_root = Control.new()
	slot_root.position = Vector2(0, 28)
	slot_root.size = Vector2(W, SLOT_H * VISIBLE)
	slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_root.clip_contents = true
	add_child(slot_root)
	_after_setup()


func _after_setup() -> void:
	_blocked = rpg.saves.save_blocked_reason() if mode == "save" and rpg and rpg.saves else ""
	# Start on the most recent save (load) or the first free slot (save).
	var newest := ""
	index = 0
	for i in slot_count():
		var info := describe(i + 1)
		if info.get("exists", false) and str(info.get("timestamp", "")) > newest:
			newest = str(info.timestamp)
			index = i
	_refresh_help()
	_redraw_slots()


func slot_count() -> int:
	if rpg and rpg.saves:
		return int(rpg.saves.slot_count()) if rpg.saves.has_method("slot_count") else int(rpg.saves.MAX_SLOTS)
	return 16


func describe(slot: int) -> Dictionary:
	if not _infos.has(slot):
		_infos[slot] = rpg.saves.describe(slot)
	return _infos[slot]


func _refresh_help(text := "", bad := false) -> void:
	if text == "":
		if _blocked != "":
			text = _blocked
			bad = true
		else:
			text = "Save to which file?" if mode == "save" else "Load which file?"
	help.text = text
	help.add_theme_color_override("font_color", colour(C_BAD) if bad else colour(0))


func _redraw_slots() -> void:
	top = clampi(top, 0, maxi(0, slot_count() - VISIBLE))
	if index < top:
		top = index
	elif index >= top + VISIBLE:
		top = index - VISIBLE + 1
	for p in slot_panels:
		p.queue_free()
	slot_panels.clear()
	for k in VISIBLE:
		var i := top + k
		if i >= slot_count():
			break
		slot_panels.append(_slot_panel(i + 1, Rect2(0, k * SLOT_H, W, SLOT_H)))


func _slot_panel(slot: int, rect: Rect2) -> Panel:
	var p := make_window(rect, slot_root)
	var info := describe(slot)
	var selected := slot - 1 == index
	if selected:
		var cur := Panel.new()
		var sb: StyleBox = null
		if has_theme_stylebox("cursor", "RPGWindow"):
			sb = get_theme_stylebox("cursor", "RPGWindow")
		else:
			var f := StyleBoxFlat.new()
			f.bg_color = Color(1, 1, 1, 0.15)
			f.border_color = Color(1, 1, 1, 0.85)
			f.set_border_width_all(1)
			f.set_corner_radius_all(2)
			sb = f
		cur.add_theme_stylebox_override("panel", sb)
		cur.position = Vector2(4, 4)
		cur.size = Vector2(66, 16)
		cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(cur)
	var is_auto: bool = rpg != null and rpg.saves.has_method("is_autosave_slot") and rpg.saves.is_autosave_slot(slot)
	make_label(p, Vector2(8, 4), "Auto" if is_auto else "File %02d" % slot, FONT, system_colour())
	if not info.get("exists", false):
		make_label(p, Vector2(8, 26), "Empty", FONT, Color(1, 1, 1, 0.5))
		return p
	if info.has("error"):
		make_label(p, Vector2(8, 26), str(info.error), FONT, colour(C_BAD))
		return p
	var members: Array = info.get("party", [])
	var saved: Array = info.get("members", [])
	var x := 78.0
	for k in mini(members.size(), 4):
		make_face(p, Vector2(x, 6), str(members[k]), 40, saved[k] if k < saved.size() else {})
		x += 42
	# The leader's name as saved (a rename after saving must not change old slots).
	var leader := ""
	if not saved.is_empty() and str(saved[0].get("name", "")) != "":
		leader = str(saved[0].name)
	elif not members.is_empty():
		leader = actor_name(str(members[0]))
	make_label(p, Vector2(8, 22), leader, SMALL)
	var desc := str(info.get("header", {}).get("description", "")) if info.get("header") is Dictionary else ""
	make_label(p, Vector2(8, 34), desc if desc != "" else str(info.get("map_name", "")), SMALL, null, 68)
	make_label(p, Vector2(W - 112, 48), "Time " + format_time(float(info.get("play_time", 0))), SMALL, null, 104, HORIZONTAL_ALIGNMENT_RIGHT)
	# Local time (the file keeps UTC for sorting).
	var ts := str(info.get("local_time", ""))
	if ts == "":
		ts = str(info.get("timestamp", "")).replace("T", " ").substr(0, 16)
	make_label(p, Vector2(8, 48), ts, SMALL, Color(1, 1, 1, 0.75))
	return p


func handle_action(a: String) -> void:
	match a:
		"up", "down":
			var n := posmod(index + (-1 if a == "up" else 1), slot_count())
			if n != index:
				index = n
				play("cursor")
				_redraw_slots()
		"left", "right":
			var n2 := clampi(index + (-VISIBLE if a == "left" else VISIBLE), 0, slot_count() - 1)
			if n2 != index:
				index = n2
				play("cursor")
				_redraw_slots()
		"ok":
			confirm(index + 1)
		"cancel":
			play("cancel")
			close()


## Mouse: the visible slots; hover selects one, a click on the selected one saves or loads.
func pointer_targets() -> Array:
	var out := []
	var xf := local_xform(slot_root)
	for k in VISIBLE:
		var i := top + k
		if i >= slot_count():
			break
		var idx := i
		out.append({"rect": xf * Rect2(0, k * SLOT_H, W, SLOT_H), "selected": index == i, "select": func() -> void: _point_slot(idx)})
	return out


func _point_slot(i: int) -> void:
	if i == index:
		return
	index = i
	play("cursor")
	_redraw_slots()


## Saves to or loads from `slot` (1-based), as if the player pressed OK on it.
func confirm(slot: int) -> void:
	if not input_enabled or _done:
		return
	index = slot - 1
	if mode == "save":
		await _save(slot)
	else:
		await _load(slot)


func _save(slot: int) -> void:
	var r: RPGResult = rpg.saves.save(slot)
	last_result = r
	if r.is_error():
		play("buzzer")
		_refresh_help(r.message, true)
		return
	play("save")
	_infos.erase(slot)
	_redraw_slots()
	_refresh_help("Saved to file %02d." % slot)
	input_enabled = false
	if not auto_mode():
		await get_tree().create_timer(0.4).timeout
	close()


func _load(slot: int) -> void:
	var info := describe(slot)
	if not info.get("exists", false) or info.has("error"):
		play("buzzer")
		return
	play("decision")
	input_enabled = false
	_refresh_help("Loading...")
	# Loading closes every overlay scene; keep this screen alive until it reports back.
	var was_in_stack: bool = rpg.ui.scene_stack.has(self)
	rpg.ui.scene_stack.erase(self)
	var r: RPGResult = await rpg.saves.load_slot(slot)
	last_result = r
	if r.is_ok():
		close()
		return
	if was_in_stack and not rpg.ui.scene_stack.has(self):
		rpg.ui.scene_stack.append(self)
	play("buzzer")
	_refresh_help(r.message, true)
	input_enabled = true


func close() -> void:
	if _done:
		return
	_done = true
	input_enabled = false
	closed.emit()
	if is_inside_tree() and rpg and rpg.ui:
		rpg.ui.close_scene.call_deferred(self)
