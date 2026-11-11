@tool
class_name RPGCommandListEditor
extends VBoxContainer
## Reusable command list editor (event pages, common events, battle events).
## A Tree of readable summaries (registry.summary) with indented branches (if/else, choices,
## loops, battle outcomes) and an insertion row "◆" at the end of every list.
##
## Double-click a line to edit it, or the "◆" row to insert. Right-click: New, Edit, Cut, Copy,
## Paste, Delete, Select all, Copy as text, Test, Toggle skip (Ctrl+/). Shift-click selects a range
## inside one branch; drag moves lines. Lines that fail validation, and unknown or unavailable
## commands (kept as-is), show a warning.
##
## The editor edits the Array given to set_commands() in place and emits commands_changed.

signal commands_changed
## "Test" in the context menu: the host runs these commands (Event test).
signal test_requested(commands: Array)
signal pick_location_requested(callback: Callable, current: Variant)
## A move route form's "Preview" (route, target character).
signal route_preview_requested(route: Variant, target: String)

const INSERT_TEXT := "◆"
enum Menu { NEW, EDIT, CUT, COPY, PASTE, DELETE, SELECT_ALL, COPY_TEXT, TEST, TOGGLE_SKIP, UNDO, REDO }

static var _clipboard: Array = []

var data: RPGProjectData
var registry: RPGCommandRegistry
var map_id := ""
var read_only := false

var _root: Array = []
var _tree: Tree
var _menu: PopupMenu
var _picker: RPGCommandPicker
var _undo: Array = []
var _redo: Array = []
var _reg_cache: Dictionary = {}
var _pending_insert: Dictionary = {}
var _fixing_selection := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(300, 120)
	_tree.allow_rmb_select = true
	_tree.item_activated.connect(_on_activated)
	_tree.multi_selected.connect(func(_it, _c, _s): _fix_selection.call_deferred())
	_tree.item_mouse_selected.connect(func(_pos, button): if button == MOUSE_BUTTON_RIGHT: _show_menu())
	_tree.empty_clicked.connect(func(_pos, button): if button == MOUSE_BUTTON_RIGHT: _show_menu())
	_tree.gui_input.connect(_on_tree_input)
	_tree.set_drag_forwarding(_get_drag, _can_drop, _drop)
	add_child(_tree)
	_menu = PopupMenu.new()
	_menu.add_item("New…", Menu.NEW, KEY_INSERT)
	_menu.add_item("Edit…", Menu.EDIT, KEY_ENTER)
	_menu.add_separator()
	_menu.add_item("Cut", Menu.CUT, KEY_MASK_CMD_OR_CTRL | KEY_X)
	_menu.add_item("Copy", Menu.COPY, KEY_MASK_CMD_OR_CTRL | KEY_C)
	_menu.add_item("Paste", Menu.PASTE, KEY_MASK_CMD_OR_CTRL | KEY_V)
	_menu.add_item("Delete", Menu.DELETE, KEY_DELETE)
	_menu.add_separator()
	_menu.add_item("Select all", Menu.SELECT_ALL, KEY_MASK_CMD_OR_CTRL | KEY_A)
	_menu.add_item("Copy as text", Menu.COPY_TEXT)
	_menu.add_item("Test", Menu.TEST)
	_menu.add_item("Toggle skip", Menu.TOGGLE_SKIP, KEY_MASK_CMD_OR_CTRL | KEY_SLASH)
	_menu.add_separator()
	_menu.add_item("Undo", Menu.UNDO, KEY_MASK_CMD_OR_CTRL | KEY_Z)
	_menu.add_item("Redo", Menu.REDO, KEY_MASK_CMD_OR_CTRL | KEY_Y)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func setup(p_data: RPGProjectData, p_registry: RPGCommandRegistry, p_map_id := "") -> void:
	data = p_data
	registry = p_registry
	map_id = p_map_id
	if _picker != null:
		_picker.queue_free()
	_picker = RPGCommandPicker.new(registry)
	_picker.picked.connect(_on_picked)
	add_child(_picker)


## Edits `list` in place.
func set_commands(list: Array) -> void:
	_root = list
	_undo.clear()
	_redo.clear()
	rebuild()


func get_commands() -> Array:
	return _root


# ============================================================================================
# Tree
# ============================================================================================

func rebuild() -> void:
	var sel := _selected_refs()
	var scroll := _tree.get_scroll()
	_tree.clear()
	_reg_cache = RPGValidator.registries({}, data) if data != null else {}
	var root := _tree.create_item()
	_add_list(root, _root, null, "")
	_restore_selection(sel)
	# Validation refreshes keep the selection and the scroll position.
	_restore_scroll.call_deferred(scroll.y)


func _restore_scroll(y: float) -> void:
	if is_instance_valid(_tree) and y > 0.0:
		_tree.get_v_scroll_bar().value = y


func _add_list(parent: TreeItem, list: Variant, owner: Variant, key: Variant) -> void:
	if list is Array:
		for i in list.size():
			_add_command(parent, list, i)
	var ins := _tree.create_item(parent)
	ins.set_text(0, INSERT_TEXT)
	ins.set_custom_color(0, Color(1, 1, 1, 0.45))
	ins.set_tooltip_text(0, "Double-click to insert a command here")
	ins.set_metadata(0, {"insert": true, "list": list, "index": list.size() if list is Array else 0, "owner": owner, "key": key})


func _add_command(parent: TreeItem, list: Array, i: int) -> void:
	var c: Variant = list[i]
	var it := _tree.create_item(parent)
	it.set_metadata(0, {"list": list, "index": i})
	if not (c is Dictionary):
		it.set_text(0, "⚠ (not a command) %s" % JSON.stringify(c))
		it.set_custom_color(0, Color(1, 0.5, 0.3))
		return
	var text := summary(c)
	var probs := line_problems(c)
	if not probs.is_empty():
		text = "⚠ " + text
		var tip := PackedStringArray()
		for p in probs:
			tip.append(str(p.message))
		it.set_tooltip_text(0, "\n".join(tip))
		var sev_error := probs.any(func(p): return p.severity == "error")
		it.set_custom_color(0, Color(1, 0.45, 0.35) if sev_error else Color(1, 0.8, 0.35))
		if Engine.is_editor_hint() and _tree.has_theme_icon("StatusWarning", "EditorIcons"):
			it.set_icon(0, _tree.get_theme_icon("StatusWarning", "EditorIcons"))
	if c.get("skip", false):
		text = "// " + text
		it.set_custom_color(0, Color(1, 1, 1, 0.4))
	it.set_text(0, "◆ " + text)
	for b in branches(c):
		var h := _tree.create_item(it)
		h.set_text(0, ": " + str(b.label))
		h.set_custom_color(0, Color(0.6, 0.8, 1.0))
		h.set_selectable(0, false)
		h.set_metadata(0, {"header": true, "list": b.list, "owner": b.owner, "key": b.key})
		_add_list(h, b.list, b.owner, b.key)


func summary(c: Dictionary) -> String:
	if registry == null:
		return str(c.get("type", "?"))
	var t := str(c.get("type", ""))
	if not registry.has_command(t):
		if registry.unavailable.has(t):
			return "%s (unavailable: %s) %s" % [t, registry.unavailable[t], _short_json(c)]
		return "%s (unknown, kept as-is) %s" % [t, _short_json(c)]
	return registry.summary(c)


static func _short_json(c: Dictionary) -> String:
	var d := c.duplicate()
	d.erase("type")
	var s := JSON.stringify(d)
	return s if s.length() < 60 else s.left(57) + "…"


func line_problems(c: Dictionary) -> Array:
	if registry == null:
		return []
	return RPGValidator.command_problems(c, data, registry, map_id, {}, _reg_cache)


## Nested lists of a command: [{label, list, owner, key}] in descriptor order. Lists that do not
## exist yet have list == null; inserting creates them.
func branches(c: Dictionary) -> Array:
	var out := []
	if registry == null:
		return out
	var cmd: RPGCommand = registry.get_command(str(c.get("type", "")))
	if cmd == null:
		return out
	for f in cmd.desc.get("fields", []):
		var k := str(f.get("key", ""))
		if not RPGCommand._visible(f, cmd.with_defaults(c)):
			continue
		match str(f.get("kind", "")):
			"commands":
				out.append({"label": str(f.get("label", k)), "list": c.get(k) if c.get(k) is Array else null, "owner": c, "key": k})
			"list":
				var cmd_field := ""
				var label_field := ""
				for sf in f.get("item_fields", []):
					if sf.get("kind", "") == "commands" and cmd_field == "":
						cmd_field = str(sf.key)
					elif sf.get("kind", "") == "text" and label_field == "":
						label_field = str(sf.key)
				if cmd_field == "" or not (c.get(k) is Array):
					continue
				for j in c[k].size():
					var item: Variant = c[k][j]
					if not (item is Dictionary):
						continue
					var lbl := "When [%s]" % str(item.get(label_field, j + 1)) if label_field != "" else "%s %d" % [f.get("label", k), j + 1]
					out.append({"label": lbl, "list": item.get(cmd_field) if item.get(cmd_field) is Array else null, "owner": item, "key": cmd_field})
	return out


# ============================================================================================
# Selection: one list at a time, a set of indices
# ============================================================================================

## {list, indices (sorted)} of the selected commands, or {} when nothing is selected.
func selection() -> Dictionary:
	var items := _selected_items()
	if items.is_empty():
		return {}
	var first: Dictionary = items[0].get_metadata(0)
	var list: Variant = first.get("list")
	var idx := []
	for it in items:
		var m: Dictionary = it.get_metadata(0)
		if is_same(m.get("list"), list) and not m.get("insert", false) and not m.get("header", false):
			idx.append(int(m.index))
	idx.sort()
	return {"list": list, "indices": idx, "item": items[0]}


func _selected_items() -> Array:
	var out := []
	var it := _tree.get_next_selected(null)
	while it != null:
		if it.get_metadata(0) is Dictionary:
			out.append(it)
		it = _tree.get_next_selected(it)
	return out


## Keeps a multi-selection inside one branch (the list of the first selected line).
func _fix_selection() -> void:
	if _fixing_selection:
		return
	_fixing_selection = true
	var items := _selected_items()
	if items.size() > 1:
		var anchor: TreeItem = _tree.get_selected() if _tree.get_selected() != null else items[0]
		var list: Variant = anchor.get_metadata(0).get("list")
		for it in items:
			var m: Dictionary = it.get_metadata(0)
			if not is_same(m.get("list"), list) or m.get("insert", false):
				it.deselect(0)
	_fixing_selection = false


func _selected_refs() -> Array:
	var out := []
	for it in _selected_items():
		var m: Dictionary = it.get_metadata(0)
		out.append([m.get("list"), m.get("index", -1), m.get("insert", false)])
	return out


func _restore_selection(refs: Array) -> void:
	if refs.is_empty():
		return
	var it := _tree.get_root()
	while it != null:
		var m: Variant = it.get_metadata(0)
		if m is Dictionary:
			for r in refs:
				if is_same(m.get("list"), r[0]) and m.get("index", -1) == r[1] and m.get("insert", false) == r[2]:
					it.select(0)
		it = it.get_next_in_tree()


func clear_selection() -> void:
	_tree.deselect_all()


## Selects lines `indices` of `list` (used by tests and hosts).
func select_lines(list: Array, indices: Array) -> void:
	_tree.deselect_all()
	var it := _tree.get_root()
	while it != null:
		var m: Variant = it.get_metadata(0)
		if m is Dictionary and is_same(m.get("list"), list) and not m.get("insert", false) and indices.has(m.get("index", -1)):
			it.select(0)
		it = it.get_next_in_tree()


# ============================================================================================
# Editing operations (all record undo, edit in place, then rebuild + commands_changed)
# ============================================================================================

func _snapshot() -> void:
	_undo.append(_root.duplicate(true))
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()


func _changed() -> void:
	rebuild()
	commands_changed.emit()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_root.duplicate(true))
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_root.duplicate(true))
	_restore(_redo.pop_back())


func _restore(copy: Array) -> void:
	_root.clear()
	_root.append_array(copy)
	_changed()


## Where a new command goes: before the selected line, or at the "◆" row.
func _insert_target() -> Dictionary:
	var it := _tree.get_selected()
	if it == null:
		var items := _selected_items()
		it = items[0] if not items.is_empty() else null
	if it == null:
		return {"list": _root, "index": _root.size()}
	var m: Dictionary = it.get_metadata(0)
	if m.get("header", false):
		return {"list": m.list, "index": 0, "owner": m.owner, "key": m.key}
	return {"list": m.get("list"), "index": int(m.get("index", 0)), "owner": m.get("owner"), "key": m.get("key")}


## Makes sure a branch list exists (creating it in its owner) and returns it.
static func _ensure_list(target: Dictionary) -> Array:
	if target.get("list") is Array:
		return target.list
	var owner: Variant = target.get("owner")
	var key: Variant = target.get("key")
	var list := []
	if owner is Dictionary and key != null:
		owner[key] = list
	target["list"] = list
	return list


## Inserts commands at a target {list, index, owner?, key?}.
func insert_commands(cmds: Array, target: Dictionary = {}) -> void:
	if read_only or cmds.is_empty():
		return
	if target.is_empty():
		target = _insert_target()
	_snapshot()
	var list := _ensure_list(target)
	var at := clampi(int(target.get("index", list.size())), 0, list.size())
	for k in cmds.size():
		list.insert(at + k, RPGJson.deep_copy(cmds[k]))
	_changed()
	select_lines(list, range(at, at + cmds.size()))


func new_command() -> void:
	if read_only:
		return
	_pending_insert = _insert_target()
	if _picker:
		_picker.open()


func _on_picked(type: String) -> void:
	var cmd: RPGCommand = registry.get_command(type)
	if cmd == null:
		return
	var c := cmd.with_defaults({"type": type})
	var target := _pending_insert if not _pending_insert.is_empty() else _insert_target()
	var editable: bool = cmd.desc.get("fields", []).any(func(f): return f.get("kind", "") != "commands")
	if not editable:
		insert_commands([c], target)
		return
	_open_command_dialog(c, func(result: Dictionary): insert_commands([result], target))


func edit_selected() -> void:
	var s := selection()
	if s.is_empty() or s.indices.is_empty():
		var it := _tree.get_selected()
		if it and it.get_metadata(0) is Dictionary and it.get_metadata(0).get("insert", false):
			new_command()
		return
	var list: Array = s.list
	var i: int = s.indices[0]
	if not (list[i] is Dictionary):
		return
	_open_command_dialog(list[i], func(result: Dictionary):
		_snapshot()
		list[i] = result
		_changed())


## The command's form dialog. OK is refused while a required field is blank; problems show in
## one fixed line under the form (nothing moves while it is filled). Returns the dialog.
func _open_command_dialog(c: Dictionary, on_ok: Callable) -> ConfirmationDialog:
	var dlg := ConfirmationDialog.new()
	var type := str(c.get("type", ""))
	var cmd: RPGCommand = registry.get_command(type) if registry else null
	dlg.title = str(cmd.desc.get("label", type)) if cmd else "Command (%s)" % type
	dlg.min_size = Vector2i(640, 420)
	dlg.dialog_hide_on_ok = false
	var outer := VBoxContainer.new()
	dlg.add_child(outer)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(620, 350)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var footer := Label.new()
	footer.name = "Problems"
	footer.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	footer.clip_text = true
	footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.custom_minimum_size = Vector2(600, 24)
	outer.add_child(footer)
	var getter: Callable
	if cmd == null:
		# Unknown or unavailable: raw JSON, kept as-is unless the user edits it.
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var note := Label.new()
		note.text = "This command type is not available (%s). It is kept as-is; you can edit its JSON." % (registry.unavailable_reason(type) if registry else "no registry")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 580
		vb.add_child(note)
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(480, 200)
		te.text = RPGJson.stringify(c)
		vb.add_child(te)
		var err := Label.new()
		err.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
		vb.add_child(err)
		sc.add_child(vb)
		getter = func() -> Variant:
			var r := RPGJson.parse_text(te.text)
			if not r.ok or not (r.data is Dictionary) or typeof(r.data.get("type")) != TYPE_STRING:
				err.text = RPGFormBuilder.json_error_text(r) if not r.ok else "The command must be an object with a \"type\"."
				return null
			return r.data
	else:
		var form := RPGFormBuilder.for_command(type, registry, data, {"hide_command_lists": true, "map_id": map_id, "inline_errors": false})
		form.name = "Form"
		form.set_value(c)
		form.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
		form.route_preview_requested.connect(func(r): route_preview_requested.emit(r, str(form.get_value().get("target", "player")) if form.get_value() is Dictionary else "player"))
		form.value_changed.connect(func(_k, _v): footer.text = form.problems_text())
		footer.text = form.problems_text()
		sc.add_child(form)
		getter = func() -> Variant:
			var missing := form.missing_required()
			if not missing.is_empty():
				footer.text = form.problems_text()
				var ed := _focusable(form.editor_for(str(missing[0])))
				if ed != null and ed.is_inside_tree():
					ed.grab_focus.call_deferred()
				return null
			return form.get_value()
	dlg.get_ok_button().pressed.connect(func():
		var v: Variant = getter.call()
		if v == null:
			return
		dlg.hide()
		on_ok.call(v)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	return dlg


## The control itself or its first descendant that can take keyboard focus, or null.
static func _focusable(c: Control) -> Control:
	if c == null:
		return null
	if c.focus_mode != Control.FOCUS_NONE:
		return c
	for ch in c.get_children():
		if ch is Control:
			var f := _focusable(ch)
			if f != null:
				return f
	return null


func copy_selected() -> Array:
	var s := selection()
	var out := []
	if s.is_empty():
		return out
	for i in s.indices:
		out.append(RPGJson.deep_copy(s.list[i]))
	_clipboard = out.duplicate(true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(RPGJson.stringify(out))
	return out


func cut_selected() -> void:
	copy_selected()
	delete_selected()


func delete_selected() -> void:
	if read_only:
		return
	var s := selection()
	if s.is_empty() or s.indices.is_empty():
		return
	_snapshot()
	var idx: Array = s.indices.duplicate()
	idx.reverse()
	for i in idx:
		s.list.remove_at(i)
	_changed()


func paste() -> void:
	var cmds := _clipboard.duplicate(true)
	if DisplayServer.get_name() != "headless":
		var r := RPGJson.parse_text(DisplayServer.clipboard_get())
		if r.ok and r.data is Array and not r.data.is_empty() and r.data.all(func(x): return x is Dictionary and x.has("type")):
			cmds = r.data
		elif r.ok and r.data is Dictionary and r.data.has("type"):
			cmds = [r.data]
	insert_commands(cmds)


func toggle_skip() -> void:
	if read_only:
		return
	var s := selection()
	if s.is_empty() or s.indices.is_empty():
		return
	_snapshot()
	var all_skipped := true
	for i in s.indices:
		if s.list[i] is Dictionary and not s.list[i].get("skip", false):
			all_skipped = false
	for i in s.indices:
		if s.list[i] is Dictionary:
			if all_skipped:
				s.list[i].erase("skip")
			else:
				s.list[i]["skip"] = true
	_changed()


func select_all() -> void:
	var s := selection()
	var list: Array = s.list if not s.is_empty() and s.list is Array else _root
	select_lines(list, range(list.size()))


## Readable text of the selection (or everything), indented like the tree.
func copy_as_text() -> String:
	var s := selection()
	var lines := PackedStringArray()
	if s.is_empty() or s.indices.is_empty():
		_text_lines(_root, 0, lines)
	else:
		var part := []
		for i in s.indices:
			part.append(s.list[i])
		_text_lines(part, 0, lines)
	var text := "\n".join(lines)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	return text


func _text_lines(list: Array, depth: int, lines: PackedStringArray) -> void:
	var pad := "  ".repeat(depth)
	for c in list:
		if not (c is Dictionary):
			continue
		lines.append(pad + ("// " if c.get("skip", false) else "") + "◆ " + summary(c))
		for b in branches(c):
			lines.append(pad + "  : " + str(b.label))
			if b.list is Array:
				_text_lines(b.list, depth + 2, lines)


## Moves lines `indices` of `from_list` to `to_list` at `at` (one undo step). Refuses to move a
## command into itself.
func move_commands(from_list: Array, indices: Array, to_list: Array, at: int) -> bool:
	if read_only or indices.is_empty():
		return false
	var moving := []
	for i in indices:
		moving.append(from_list[i])
	for m in moving:
		if _contains_list(m, to_list):
			return false
	_snapshot()
	var sorted := indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		from_list.remove_at(i)
		if is_same(from_list, to_list) and i < at:
			at -= 1
	at = clampi(at, 0, to_list.size())
	for k in moving.size():
		to_list.insert(at + k, moving[k])
	_changed()
	select_lines(to_list, range(at, at + moving.size()))
	return true


func _contains_list(c: Variant, list: Array) -> bool:
	if not (c is Dictionary):
		return false
	for b in branches(c):
		if b.list is Array:
			if is_same(b.list, list):
				return true
			for x in b.list:
				if _contains_list(x, list):
					return true
	return false


# ============================================================================================
# Input, menu, drag and drop
# ============================================================================================

func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var m: Variant = it.get_metadata(0)
	if m is Dictionary and m.get("insert", false):
		new_command()
	else:
		edit_selected()


func _show_menu() -> void:
	var has_sel: bool = not selection().is_empty() and not selection().indices.is_empty()
	for id in [Menu.EDIT, Menu.CUT, Menu.COPY, Menu.DELETE, Menu.TOGGLE_SKIP, Menu.TEST]:
		_menu.set_item_disabled(_menu.get_item_index(id), not has_sel)
	_menu.set_item_disabled(_menu.get_item_index(Menu.UNDO), _undo.is_empty())
	_menu.set_item_disabled(_menu.get_item_index(Menu.REDO), _redo.is_empty())
	preload("res://addons/rpg/editor/rpg_popup_place.gd").at_mouse(self, _menu)


func _on_menu(id: int) -> void:
	match id:
		Menu.NEW: new_command()
		Menu.EDIT: edit_selected()
		Menu.CUT: cut_selected()
		Menu.COPY: copy_selected()
		Menu.PASTE: paste()
		Menu.DELETE: delete_selected()
		Menu.SELECT_ALL: select_all()
		Menu.COPY_TEXT: copy_as_text()
		Menu.TEST:
			var s := selection()
			if not s.is_empty():
				var cmds := []
				for i in s.indices:
					cmds.append(RPGJson.deep_copy(s.list[i]))
				test_requested.emit(cmds)
		Menu.TOGGLE_SKIP: toggle_skip()
		Menu.UNDO: undo()
		Menu.REDO: redo()


func _on_tree_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: InputEventKey = ev
	var ctrl := k.is_command_or_control_pressed()
	var handled := true
	if ctrl and k.keycode == KEY_C:
		copy_selected()
	elif ctrl and k.keycode == KEY_X:
		cut_selected()
	elif ctrl and k.keycode == KEY_V:
		paste()
	elif ctrl and k.keycode == KEY_A:
		select_all()
	elif ctrl and k.keycode == KEY_SLASH:
		toggle_skip()
	elif ctrl and k.keycode == KEY_Z:
		undo()
	elif ctrl and (k.keycode == KEY_Y or (k.shift_pressed and k.keycode == KEY_Z)):
		redo()
	elif k.keycode == KEY_DELETE:
		delete_selected()
	elif k.keycode == KEY_INSERT:
		new_command()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		_on_activated()
	else:
		handled = false
	if handled:
		_tree.accept_event()


func _get_drag(_pos: Vector2) -> Variant:
	if read_only:
		return null
	var s := selection()
	if s.is_empty() or s.indices.is_empty():
		return null
	var l := Label.new()
	l.text = "%d line(s)" % s.indices.size()
	_tree.set_drag_preview(l)
	_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	return {"rpg_commands": true, "source": self, "list": s.list, "indices": s.indices}


func _drop_target(pos: Vector2) -> Dictionary:
	var it := _tree.get_item_at_position(pos)
	if it == null:
		return {"list": _root, "index": _root.size()}
	var m: Variant = it.get_metadata(0)
	if not (m is Dictionary):
		return {}
	var section := _tree.get_drop_section_at_position(pos)
	if m.get("header", false):
		return {"list": m.list, "index": 0, "owner": m.owner, "key": m.key}
	if m.get("insert", false):
		return {"list": m.list, "index": int(m.index), "owner": m.owner, "key": m.key}
	return {"list": m.list, "index": int(m.index) + (1 if section > 0 else 0)}


func _can_drop(pos: Vector2, d: Variant) -> bool:
	return d is Dictionary and d.get("rpg_commands", false) and d.get("source") == self and not _drop_target(pos).is_empty()


func _drop(pos: Vector2, d: Variant) -> void:
	var t := _drop_target(pos)
	if t.is_empty():
		return
	var to_list := _ensure_list(t)
	move_commands(d.list, d.indices, to_list, int(t.index))
	_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
