@tool
class_name RPGEventEditor
extends Window
## The event window (spec "Event editor").
##
##   RPGEventEditor.open_for(map_id, event_id, project_data, registry, undo_redo, on_saved)
##
## Edits a deep copy of one event from `<map>.events.json`; OK/Apply writes the whole file
## atomically (RPGEventsFile), so unknown fields and unknown commands are kept. When `undo_redo`
## (an EditorUndoRedoManager, or anything with the same create_action/add_do_method/... API) is
## given, the write is one undoable action in Godot's history; otherwise the file is written
## directly. `on_saved.call(event_id)` runs after every successful write (and after undo/redo).
##
## Layout: header (ID with rename, name, notes, "Open JSON"), page tabs with New/Copy/Paste/
## Delete/Clear page, left column page settings (conditions, graphic, movement, options, priority,
## trigger), right column RPGCommandListEditor.
##
## A brand-new event (open_new) exists only in this window until OK or Apply writes it
## (`is_new`); Cancel leaves the map untouched.

## "Pick on map" in any location field. The map editor answers with callback.call(map_id, cell),
## or callback.call("", Vector2i(-1, -1)) when the pick is cancelled. While a pick is open this
## window and its dialogs are hidden so the map can be clicked; the answer brings them back.
signal pick_location_requested(callback: Callable, current: Variant)
## "Test" in the command list: the host runs these commands (Event test).
signal event_test_requested(commands: Array)
## A move route "Preview": the page's custom movement (target "this") or a Move route command.
signal route_preview_requested(route: Variant, target: String)
signal saved(event_id: String)
## The window closed (OK, Cancel or discard); the host can clear previews it drew for it.
signal closed

const PAGE_FIELDS := [
	{"key": "conditions", "kind": "list", "item_kind": "condition", "default": [], "label": "Conditions",
		"help": "All conditions must be true for this page to be active. There is no limit."},
	{"key": "graphic", "kind": "graphic", "default": null, "label": "Graphic"},
	{"key": "movement", "kind": "object", "default": {"type": "fixed"}, "label": "Movement", "fields": [
		{"key": "type", "kind": "choice", "options": ["fixed", "random", "approach", "custom"], "option_labels": ["Fixed", "Random", "Approach the player", "Custom route"], "default": "fixed", "label": "Type"},
		{"key": "speed", "kind": "int", "default": 3, "min": 1, "max": 6, "label": "Speed (1-6)"},
		{"key": "frequency", "kind": "int", "default": 3, "min": 1, "max": 5, "label": "Frequency (1-5)"},
		{"key": "route", "kind": "route", "route_options": true, "default": null, "label": "Route", "show_if": {"key": "type", "equals": "custom"}},
	]},
	{"key": "options", "kind": "object", "default": {}, "label": "Options", "fields": [
		{"key": "walk_anim", "kind": "bool", "default": true, "label": "Walking animation"},
		{"key": "step_anim", "kind": "bool", "default": false, "label": "Stepping animation"},
		{"key": "direction_fix", "kind": "bool", "default": false, "label": "Direction fix"},
		{"key": "through", "kind": "bool", "default": false, "label": "Walk through"},
	]},
	{"key": "priority", "kind": "choice", "options": ["below", "same", "above"], "option_labels": ["Below characters", "Same as characters", "Above characters"], "default": "same", "label": "Priority"},
	{"key": "trigger", "kind": "choice", "options": ["action_button", "player_touch", "event_touch", "autorun", "parallel"], "option_labels": ["Action button", "Player touch", "Event touch", "Autorun", "Parallel"], "default": "action_button", "label": "Trigger"},
]

static var _page_clipboard: Variant = null


## The page form's fields: PAGE_FIELDS, plus "Plugin fields" (the page's "custom" object) when
## enabled extensions declare custom_fields for "event_pages" (or the project does).
static func page_fields(p_registry: RPGCommandRegistry, p_data: RPGProjectData) -> Array:
	var out: Array = PAGE_FIELDS.duplicate(true)
	var project_fields: Dictionary = p_data.project.get("custom_fields", {}) if p_data != null and p_data.project.get("custom_fields") is Dictionary else {}
	var merged: Dictionary = p_registry.merged_custom_fields(project_fields) if p_registry != null else project_fields
	var extra: Variant = merged.get("event_pages", [])
	if extra is Array and not extra.is_empty():
		out.append({"key": "custom", "kind": "object", "default": {}, "label": "Plugin fields", "fields": extra,
			"help": "Fields that plugins (and the project's custom_fields \"event_pages\") add to each page."})
	return out

var map_id := ""
var event_id := ""
var data: RPGProjectData
var registry: RPGCommandRegistry
var undo_redo: Object
var on_saved: Callable
var file: RPGEventsFile
## The working copy (never the file's own dictionary).
var event: Dictionary = {}
var dirty := false
## True while the event exists only in this window (opened with open_new, not yet saved).
var is_new := false

var _loaded_event: Dictionary = {}
var _page := 0
var _id_edit: LineEdit
var _name_edit: LineEdit
var _notes_edit: TextEdit
var _json_toggle: Button
var _main_box: VBoxContainer
var _json_box: VBoxContainer
var _json_edit: TextEdit
var _json_msg: Label
var _tabs: TabBar
var _page_form: RPGFormBuilder
var _cmd_list: RPGCommandListEditor
var _problems: RichTextLabel
var _status: Label
var _writer: RPGEventFileWriter
## Windows hidden while a location is picked on the map (this one and its open dialogs).
var _pick_hidden: Array = []
var _rebuilding_tabs := false
## The status line shows an ID or JSON message (cleared once it no longer applies).
var _id_status := false
var _json_status := false


## Opens the window for one event and returns it. Adds itself to the editor's base control (or
## the scene tree root outside the editor).
static func open_for(p_map_id: String, p_event_id: String, p_data: RPGProjectData, p_registry: RPGCommandRegistry, p_undo_redo: Object, p_on_saved: Callable) -> RPGEventEditor:
	var w := RPGEventEditor.new()
	w.setup(p_map_id, p_event_id, p_data, p_registry, p_undo_redo, p_on_saved)
	_popup_window(w)
	return w


## Opens the window for a new event at `cell` without adding it to the map: it gets a free ID
## (event_<x>_<y>) and the name EV<n>, and is written only by OK / Apply. `event_id` holds the
## ID (the maker may still rename it; `saved` reports the final one).
static func open_new(p_map_id: String, p_cell: Vector2i, p_data: RPGProjectData, p_registry: RPGCommandRegistry, p_undo_redo: Object, p_on_saved: Callable) -> RPGEventEditor:
	var w := RPGEventEditor.new()
	w.setup(p_map_id, "", p_data, p_registry, p_undo_redo, p_on_saved, p_cell)
	_popup_window(w)
	return w


static func _popup_window(w: RPGEventEditor) -> void:
	var parent: Node = null
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		parent = Engine.get_singleton("EditorInterface").get_base_control()
	else:
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			parent = ml.root
	if parent != null:
		parent.add_child(w)
		# Fit small screens (e.g. 1366x768 laptops) instead of opening off-screen.
		var avail := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
		if avail.x <= 0 or avail.y <= 0:
			avail = Vector2i(1280, 800)
		w.popup_centered(Vector2i(mini(1120, avail.x - 40), mini(720, avail.y - 60)))


## `p_new_at` >= (0, 0): a new event at that cell (see open_new); `p_event_id` is then ignored.
func setup(p_map_id: String, p_event_id: String, p_data: RPGProjectData, p_registry: RPGCommandRegistry, p_undo_redo: Object, p_on_saved: Callable, p_new_at := Vector2i(-1, -1)) -> void:
	map_id = p_map_id
	event_id = p_event_id
	data = p_data
	registry = p_registry
	undo_redo = p_undo_redo
	on_saved = p_on_saved
	_writer = RPGEventFileWriter.new()
	_writer.data = data
	_writer.map_id = map_id
	_writer.on_written = func(): if on_saved.is_valid(): on_saved.call(event_id)
	file = RPGEventsFile.open(RPGValidator.events_path(data, map_id) if data != null else "", map_id)
	if p_new_at.x >= 0 and p_new_at.y >= 0:
		is_new = true
		event_id = RPGIds.unique("event_%d_%d" % [p_new_at.x, p_new_at.y], file.ids(), file.retired_ids())
		var page := RPGQuickEvents.complete_page({})
		page["movement"] = {"type": "fixed", "speed": 3, "frequency": 3}
		event = {"id": event_id, "name": "EV%03d" % (file.ids().size() + 1), "position": [p_new_at.x, p_new_at.y], "notes": "", "pages": [page]}
	elif file.has_event(event_id):
		event = file.get_event_copy(event_id)
	else:
		event = {"id": event_id, "name": "", "position": [0, 0], "notes": "", "pages": [RPGQuickEvents.complete_page({})]}
	_loaded_event = event.duplicate(true)
	if not (event.get("pages") is Array) or event.pages.is_empty():
		event["pages"] = [RPGQuickEvents.complete_page({})]
	title = _title()
	_build_ui()
	if file.error != "":
		_status.text = "The events file could not be read: %s. Saving is disabled until it is fixed." % file.error
	_load_header()
	_rebuild_tabs()
	_show_page(0)


# ============================================================================================
# UI
# ============================================================================================

func _build_ui() -> void:
	min_size = Vector2i(900, 560)
	wrap_controls = false
	close_requested.connect(cancel)
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	bg.add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	# Header.
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(_label("ID"))
	_id_edit = LineEdit.new()
	_id_edit.custom_minimum_size.x = 200
	_id_edit.tooltip_text = "Stable ID used by commands and saves. Changing it renames every reference on this map when you save."
	_id_edit.text_changed.connect(func(_t): _mark_dirty(); _check_id())
	head.add_child(_id_edit)
	head.add_child(_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t): event["name"] = t; _mark_dirty())
	head.add_child(_name_edit)
	_json_toggle = Button.new()
	_json_toggle.text = "Open JSON"
	_json_toggle.toggle_mode = true
	_json_toggle.tooltip_text = "Show this event as text. Edits are checked before they are used."
	_json_toggle.toggled.connect(_on_json_toggled)
	head.add_child(_json_toggle)
	var notes_row := HBoxContainer.new()
	root.add_child(notes_row)
	notes_row.add_child(_label("Notes"))
	_notes_edit = TextEdit.new()
	_notes_edit.custom_minimum_size = Vector2(0, 40)
	_notes_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_edit.text_changed.connect(func(): event["notes"] = _notes_edit.text; _mark_dirty())
	notes_row.add_child(_notes_edit)
	# Main (form) view.
	_main_box = VBoxContainer.new()
	_main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_main_box)
	var tools := HBoxContainer.new()
	_main_box.add_child(tools)
	for spec in [["New page", new_page], ["Copy page", copy_page], ["Paste page", paste_page], ["Delete page", _confirm_delete_page], ["Clear page", clear_page]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		tools.add_child(b)
	_tabs = TabBar.new()
	_tabs.tab_changed.connect(func(i): if not _rebuilding_tabs: _show_page(i))
	_main_box.add_child(_tabs)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 40
	_main_box.add_child(split)
	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 440
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	_page_form = RPGFormBuilder.new()
	_page_form.setup(page_fields(registry, data), data, registry, {"map_id": map_id})
	_page_form.value_changed.connect(_on_page_field)
	_page_form.pick_location_requested.connect(request_pick_location)
	_page_form.route_preview_requested.connect(func(r): route_preview_requested.emit(r, "this"))
	left.add_child(_page_form)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	right.add_child(_label("Commands"))
	_cmd_list = RPGCommandListEditor.new()
	_cmd_list.setup(data, registry, map_id)
	_cmd_list.commands_changed.connect(_mark_dirty)
	_cmd_list.test_requested.connect(func(c): event_test_requested.emit(c))
	_cmd_list.pick_location_requested.connect(request_pick_location)
	_cmd_list.route_preview_requested.connect(func(r, t): route_preview_requested.emit(r, t))
	right.add_child(_cmd_list)
	# JSON view.
	_json_box = VBoxContainer.new()
	_json_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json_box.visible = false
	root.add_child(_json_box)
	_json_edit = TextEdit.new()
	_json_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json_edit.text_changed.connect(_on_json_text)
	_json_box.add_child(_json_edit)
	_json_msg = Label.new()
	_json_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_json_box.add_child(_json_msg)
	# Problems + buttons.
	_problems = RichTextLabel.new()
	_problems.bbcode_enabled = true
	_problems.fit_content = true
	_problems.custom_minimum_size.y = 0
	_problems.scroll_active = false
	root.add_child(_problems)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	var check := Button.new()
	check.text = "Check"
	check.tooltip_text = "Check this event for missing switches, maps and other problems"
	check.pressed.connect(func(): show_problems(check_problems()))
	bottom.add_child(check)
	for spec in [["OK", ok], ["Cancel", cancel], ["Apply", func(): apply()]]:
		var b2 := Button.new()
		b2.text = spec[0]
		b2.custom_minimum_size.x = 80
		b2.pressed.connect(spec[1])
		bottom.add_child(b2)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _load_header() -> void:
	_id_edit.text = event_id
	_name_edit.text = str(event.get("name", ""))
	_notes_edit.text = str(event.get("notes", ""))
	dirty = false


func _rebuild_tabs() -> void:
	# Adding the first tab emits tab_changed(0); without the guard that showed page 1 and lost
	# the page asked for (New page stayed on page 1).
	var want := clampi(_page, 0, event.pages.size() - 1)
	_rebuilding_tabs = true
	_tabs.clear_tabs()
	for i in event.pages.size():
		_tabs.add_tab(str(i + 1))
	_tabs.current_tab = want
	_rebuilding_tabs = false
	_page = want


func _show_page(i: int) -> void:
	if i < 0 or i >= event.pages.size():
		return
	_page = i
	var pg: Variant = event.pages[i]
	if not (pg is Dictionary):
		event.pages[i] = RPGQuickEvents.complete_page({})
		pg = event.pages[i]
	_page_form.set_value(pg)
	if not (pg.get("commands") is Array):
		pg["commands"] = []
	_cmd_list.set_commands(pg.commands)


func _on_page_field(key: String, v: Variant) -> void:
	if _page < event.pages.size():
		event.pages[_page][key] = RPGJson.deep_copy(v)
		_mark_dirty()


func _mark_dirty() -> void:
	dirty = true
	title = _title()
	if _status != null and _status.text == "Saved.":
		_status.text = ""


func _title() -> String:
	var id := _id_edit.text if _id_edit else event_id
	var t := "%s: %s (%s)" % ["New event" if is_new else "Event", event.get("name", ""), id]
	return t + (" *" if dirty else "")


func _check_id() -> String:
	var id := _id_edit.text.strip_edges()
	var msg := ""
	if not RPGIds.is_valid(id):
		msg = "The ID must use lowercase letters, digits and _, and start with a letter."
	elif (id != event_id or is_new) and (file.has_event(id) or file.retired_ids().has(id)):
		msg = "Map '%s' already has (or had) an event '%s'. Pick another ID." % [map_id, id]
	# Only an ID message is cleared here; other status messages stay.
	if msg != "" or _id_status:
		_status.text = msg
	_id_status = msg != ""
	return msg


# ============================================================================================
# Pages
# ============================================================================================

func current_page() -> int:
	return _page


func new_page() -> void:
	event.pages.append(RPGQuickEvents.complete_page({}))
	_page = event.pages.size() - 1
	_rebuild_tabs()
	_show_page(_page)
	_mark_dirty()


func copy_page() -> void:
	_page_clipboard = RPGJson.deep_copy(event.pages[_page])


func paste_page() -> void:
	if not (_page_clipboard is Dictionary):
		return
	event.pages.insert(_page + 1, RPGJson.deep_copy(_page_clipboard))
	_page += 1
	_rebuild_tabs()
	_show_page(_page)
	_mark_dirty()


func _confirm_delete_page() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete page %d and its commands?" % (_page + 1)
	dlg.confirmed.connect(func(): delete_page(); dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func delete_page() -> void:
	if event.pages.size() <= 1:
		clear_page()
		return
	event.pages.remove_at(_page)
	_page = clampi(_page, 0, event.pages.size() - 1)
	_rebuild_tabs()
	_show_page(_page)
	_mark_dirty()


func clear_page() -> void:
	event.pages[_page] = RPGQuickEvents.complete_page({})
	_show_page(_page)
	_mark_dirty()


# ============================================================================================
# JSON view
# ============================================================================================

func _on_json_toggled(on: bool) -> void:
	_clear_json_status()
	if on:
		_json_edit.text = RPGJson.stringify(event)
		_json_msg.text = ""
		_main_box.visible = false
		_json_box.visible = true
	else:
		if not _take_json():
			_json_toggle.set_pressed_no_signal(true)
			return
		_main_box.visible = true
		_json_box.visible = false


func _on_json_text() -> void:
	var r := _parse_json(_json_edit.text)
	_json_msg.text = r.message
	_json_msg.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if not r.ok else Color(0.6, 1, 0.6))
	if r.ok:
		_clear_json_status()
	_mark_dirty()


## Clears "Fix the JSON first" once the JSON is valid again or the view changes.
func _clear_json_status() -> void:
	if _json_status:
		_status.text = ""
		_json_status = false


## {ok, data, message}: JSON errors give the line; shape errors give the field.
func _parse_json(text: String) -> Dictionary:
	var r := RPGJson.parse_text(text)
	if not r.ok:
		return {"ok": false, "data": null, "message": RPGFormBuilder.json_error_text(r)}
	if not (r.data is Dictionary):
		return {"ok": false, "data": null, "message": "The event must be a JSON object ({ ... })."}
	var probs := RPGValidator.event_structure(r.data, registry, "", "")
	var errs := probs.filter(func(p): return p.severity == "error")
	if not errs.is_empty():
		var lines := PackedStringArray()
		for p in errs.slice(0, 8):
			lines.append("%s: %s" % [p.path, p.message])
		return {"ok": false, "data": null, "message": "\n".join(lines)}
	return {"ok": true, "data": r.data, "message": "OK"}


## Takes the JSON text into the working copy. The last valid version stays when it is invalid.
func _take_json() -> bool:
	if not _json_box.visible:
		return true
	var r := _parse_json(_json_edit.text)
	if not r.ok:
		_json_msg.text = r.message
		return false
	event = r.data
	if not (event.get("pages") is Array) or event.pages.is_empty():
		event["pages"] = [RPGQuickEvents.complete_page({})]
	if typeof(event.get("id")) == TYPE_STRING and event.id != event_id:
		_id_edit.text = event.id
	event["id"] = event_id
	_name_edit.text = str(event.get("name", ""))
	_notes_edit.text = str(event.get("notes", ""))
	_rebuild_tabs()
	_show_page(clampi(_page, 0, event.pages.size() - 1))
	return true


# ============================================================================================
# Saving
# ============================================================================================

func set_event_name(n: String) -> void:
	_name_edit.text = n
	event["name"] = n
	_mark_dirty()


func set_event_id(new_id: String) -> void:
	_id_edit.text = new_id
	_mark_dirty()


## Reference problems of the working copy (whole map file, this event only).
func check_problems() -> Array:
	if data == null:
		return []
	var tmp := file.data.duplicate(true)
	var probe := RPGEventsFile.new()
	probe.data = tmp
	probe.set_event(event.duplicate(true), event_id)
	var files := RPGValidator.collect_files(data, {file.path: {"kind": "events", "map": map_id, "data": tmp}})
	var out := []
	for p in RPGValidator.event_structure(event, registry, file.path, ""):
		out.append(p)
	for p in RPGValidator.references(data, registry, files):
		if p.file == file.path and p.record == event_id:
			out.append(p)
	return out


func show_problems(probs: Array) -> void:
	if probs.is_empty():
		_problems.text = "[color=#8f8]No problems found.[/color]"
		return
	var lines := PackedStringArray()
	for p in probs.slice(0, 12):
		var col := "#f86" if p.severity == "error" else "#fc6"
		lines.append("[color=%s]%s[/color] %s  [i]%s[/i]" % [col, "⚠" if p.severity == "warning" else "✖", p.message, p.get("fix_hint", "")])
	if probs.size() > 12:
		lines.append("… and %d more" % (probs.size() - 12))
	_problems.text = "\n".join(lines)


## Writes the event. Returns true on success.
func apply() -> bool:
	if file.error != "":
		_status.text = "Cannot save: %s" % file.error
		return false
	if not _take_json():
		_status.text = "Fix the JSON first: %s" % _json_msg.text
		_json_status = true
		return false
	if _check_id() != "":
		return false
	var new_id := _id_edit.text.strip_edges()
	# Outside edits: start from what is on disk now; refuse silently overwriting a changed event.
	var base := RPGEventsFile.open(file.path, map_id)
	if base.error != "":
		_status.text = "The events file on disk is invalid (%s). Fix it or reload before saving." % base.error
		return false
	if is_new:
		# Something else may have taken the ID meanwhile (a paste, another window).
		if base.has_event(new_id) or base.retired_ids().has(new_id):
			new_id = RPGIds.unique(new_id, base.ids(), base.retired_ids())
		event_id = new_id
		event["id"] = new_id
	elif file.changed_on_disk():
		var disk_ev := base.get_event(event_id)
		if disk_ev.is_empty() and base.retired_ids().has(event_id):
			_status.text = "This event was deleted on the map after this window opened. Undo the delete (Ctrl+Z) to keep editing it, or close this window."
			return false
		if not disk_ev.is_empty() and not _same(disk_ev, _loaded_event):
			_ask_conflict()
			return false
	var old_text := base.disk_text
	base.set_event(event.duplicate(true), event_id)
	if new_id != event_id and not is_new:
		var files := RPGValidator.collect_files(data, {base.path: {"kind": "events", "map": map_id, "data": base.data}})
		var r := RPGValidator.rename_id(data, registry, "event", "%s/%s" % [map_id, event_id], new_id, files)
		if not r.ok:
			_status.text = r.error
			return false
		if r.data_by_file.has(base.path):
			base.data = r.data_by_file[base.path]
		base.retire(event_id)
	var new_text := base.to_text()
	# switch/variable definitions added with "New…" in this window.
	var state_dirty := RPGFormBuilder.dirty_files(data).has("state.json")
	if state_dirty:
		var err := RPGRefPicker.save_new_defs(data)
		if err != OK:
			_status.text = "Could not write state.json (error %d)." % err
			return false
		RPGFormBuilder.clear_dirty(data, "state.json")
	event_id = new_id
	_writer.on_written = func(): if on_saved.is_valid(): on_saved.call(new_id)
	var ok := true
	if undo_redo != null and undo_redo.has_method("create_action"):
		undo_redo.create_action(("New event %s" if is_new else "Edit event %s") % new_id)
		undo_redo.add_do_method(_writer, "write", base.path, new_text)
		undo_redo.add_undo_method(_writer, "write", base.path, old_text)
		undo_redo.commit_action(true)
		ok = _writer.last_error == OK
	else:
		ok = _writer.write(base.path, new_text) == OK
	if not ok:
		_status.text = "Could not write %s (error %d). Nothing was changed." % [base.path, _writer.last_error]
		return false
	file = RPGEventsFile.open(base.path, map_id)
	event = file.get_event_copy(new_id)
	_loaded_event = event.duplicate(true)
	is_new = false
	_id_edit.text = new_id
	dirty = false
	title = _title()
	_status.text = "Saved."
	_show_page(clampi(_page, 0, event.pages.size() - 1))
	show_problems(check_problems())
	saved.emit(new_id)
	return true


func _same(a: Variant, b: Variant) -> bool:
	return RPGJson.stringify(a) == RPGJson.stringify(b)


func _ask_conflict() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Changed on disk"
	dlg.dialog_text = "This event was changed outside the editor since you opened it.\nKeep your version (overwrite the file's copy of this event) or reload the file's version?"
	dlg.ok_button_text = "Keep mine"
	dlg.add_button("Reload theirs", true, "reload")
	dlg.confirmed.connect(func():
		_loaded_event = RPGEventsFile.open(file.path, map_id).get_event(event_id).duplicate(true)
		file.disk_text = FileAccess.get_file_as_string(file.path)
		dlg.queue_free()
		apply())
	dlg.custom_action.connect(func(a):
		if a == "reload":
			file = RPGEventsFile.open(file.path, map_id)
			event = file.get_event_copy(event_id)
			_loaded_event = event.duplicate(true)
			_load_header()
			_page = 0
			_rebuild_tabs()
			_show_page(0)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func ok() -> void:
	if apply():
		close()


## Closes the window without saving (a new event that was never saved is not created).
func close() -> void:
	hide()
	closed.emit()
	queue_free()


func cancel() -> void:
	if not dirty:
		close()
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Discard this new event?" if is_new else "Discard your changes to this event?"
	dlg.ok_button_text = "Discard"
	dlg.confirmed.connect(close)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


# ============================================================================================
# Location picks on the map
# ============================================================================================

## Forwards a location field's "Pick on map" to the host and steps aside (this window and its
## open dialogs hide) until the host answers through the callback.
func request_pick_location(callback: Callable, current: Variant = null) -> void:
	step_aside()
	pick_location_requested.emit(_on_pick_answer.bind(callback), current)


## Hides this window and its visible dialogs (remembered for come_back()).
func step_aside() -> void:
	if _pick_hidden.is_empty():
		_pick_hidden = hide_windows(self)


## Shows again what step_aside() hid. Safe to call when nothing is hidden.
func come_back() -> void:
	var wins := _pick_hidden
	_pick_hidden = []
	show_windows(wins)


## Hides `root` and every visible window inside it. Returns them, parents first.
static func hide_windows(root: Window) -> Array:
	var wins: Array = []
	var all: Array = [root]
	all.append_array(root.find_children("*", "Window", true, false))
	for w in all:
		if w.visible:
			wins.append(w)
	for w in wins:
		w.hide()
	return wins


## Shows windows hidden by hide_windows() again (those still alive).
static func show_windows(wins: Array) -> void:
	for w in wins:
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			w.show()


func is_stepped_aside() -> bool:
	return not _pick_hidden.is_empty()


func _on_pick_answer(p_map_id: String, cell: Vector2i, callback: Callable) -> void:
	come_back()
	if p_map_id != "" and callback.is_valid():
		callback.call(p_map_id, cell)


# Escape closes the window even while a text field has focus: text fields keep Escape for
# themselves in _gui_input, so it is caught here first.
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		var f := gui_get_focus_owner()
		if f != null and (f is LineEdit or f is TextEdit):
			set_input_as_handled()
			cancel()


func _shortcut_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			cancel()
			set_input_as_handled()
		elif ev.keycode == KEY_S and ev.is_command_or_control_pressed():
			apply()
			set_input_as_handled()
