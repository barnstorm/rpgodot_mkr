@tool
class_name RPGRecordTab
extends HSplitContainer
## One Database sub-tab: a searchable, reorderable list of records on the left and a form on the
## right (built from RPGRecordSchemas). Copy, paste and duplicate make new IDs and never reuse
## deleted ones; reordering never changes IDs; deleting asks first. Records are edited in place
## in the file's Dictionary, so unknown fields are kept; Save writes the file atomically.
##
## config keys:
##   type, label, ref_kind (for renames/used-by), fields (Array),
##   records: Callable() -> Array          the live records array
##   holder: Callable() -> Dictionary      the file Dictionary (keeps "retired_ids")
##   save: Callable() -> Error
##   validate: Callable() -> Array         problems for this file
##   extra: Callable(tab, record) -> Control (optional, shown under the form)
##   preview: Callable(record) -> Control  (optional, a large picture beside the form; rebuilt
##                                          when the record changes)
##   form_options: Dictionary              (optional, passed to RPGFormBuilder)
##   new_id_base: String                   (optional; New makes "<base>_<n>")
##   path: String                          (optional) the file this tab writes; problems in
##                                          other files are shown with their file name
##   record_fields: Callable(record) -> Array (optional) the form's fields for one record (the
##                                          Types tab: equipment slots have more per entry)
##   new_record: Callable(record) (optional)  fills in a record New just made (class stats)
## A field with "coerce_by": "<key>" is typed as text and converted to the record's <key> type
## (int, float, bool, string) on every edit; text that does not convert is reported, never saved.
## A "virtual" field is not stored: RPGRecordSchemas.virtual_value() derives it from the record
## and apply_virtual() writes its effect. A "drop_hidden" field is removed from the record while
## its show_if hides it. Equipment pickers (fields with "equip_slot") mark items that do not fit
## the slot or the actor's class. Save warns about records without a name.

signal dirty_changed(dirty: bool)
## After a successful save_now().
signal saved()
signal rename_requested(kind: String, old_id: String)

const FormColumn := preload("res://addons/rpg/editor/database/rpg_form_column.gd")

static var _clipboards: Dictionary = {}

var config: Dictionary = {}
var data: RPGProjectData
var registry: RPGCommandRegistry
var rules: Variant = null
var dirty := false

var _search: LineEdit
var _tree: Tree
var _form: RPGFormBuilder
var _extra_box: VBoxContainer
var _formula_box: VBoxContainer
var _preview_box: VBoxContainer
var _title: Label
var _status: RichTextLabel
## Messages about the list buttons (e.g. why Rename ID cannot run yet), under the buttons.
var _note: Label
var _current := -1
## Field key -> message, for text a "coerce_by" field could not convert.
var _invalid: Dictionary = {}
## The fields the form shows now (config "fields", or config "record_fields" for this record).
var _fields: Array = []


func setup(p_config: Dictionary, p_data: RPGProjectData, p_registry: RPGCommandRegistry, p_rules: Variant) -> void:
	config = p_config
	data = p_data
	registry = p_registry
	rules = p_rules
	name = str(config.get("label", config.get("type", "Records")))
	for c in get_children():
		c.queue_free()
	split_offset = 260
	# Left: search, list, buttons.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Search…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): refresh_list())
	left.add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_selected)
	_tree.set_drag_forwarding(_get_drag, _can_drop, _drop)
	left.add_child(_tree)
	var row1 := HFlowContainer.new()
	left.add_child(row1)
	for spec in [["New", new_record, "Add a record"], ["Duplicate", duplicate_record, "Copy this record with a new ID"],
			["Copy", copy_record, "Copy to the clipboard"], ["Paste", paste_record, "Paste as a new record (new ID)"],
			["Delete", _confirm_delete, "Delete this record"], ["▲", move_record.bind(-1), "Move up (IDs never change)"],
			["▼", move_record.bind(1), "Move down (IDs never change)"], ["Rename ID…", _rename_dialog, "Rename the ID and every reference to it"]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.pressed.connect(spec[1])
		row1.add_child(b)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 200
	_note.add_theme_color_override("font_color", Color(1, 0.8, 0.45))
	_note.visible = false
	left.add_child(_note)
	# Right: form.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	right.add_child(_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	var column := FormColumn.new()
	sc.add_child(column)
	var inner := VBoxContainer.new()
	column.add_child(inner)
	_preview_box = VBoxContainer.new()
	_preview_box.visible = false
	column.add_child(_preview_box)
	_form = RPGFormBuilder.new()
	_fields = config.get("fields", [])
	_form.setup(_fields, data, registry, config.get("form_options", {}))
	_form.value_changed.connect(_on_form_changed)
	inner.add_child(_form)
	_formula_box = VBoxContainer.new()
	inner.add_child(_formula_box)
	_extra_box = VBoxContainer.new()
	inner.add_child(_extra_box)
	var bottom := HBoxContainer.new()
	right.add_child(bottom)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)
	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Write this tab's file (Ctrl+S)"
	save.pressed.connect(func(): save_now())
	bottom.add_child(save)
	refresh_list()
	if not records().is_empty():
		select(0)
	else:
		_show_empty()


func records() -> Array:
	return config.records.call()


func ids() -> Array:
	var out := []
	for r in records():
		if r is Dictionary:
			out.append(str(r.get("id", "")))
	return out


func _retired() -> Array:
	var h: Dictionary = config.holder.call()
	if not (h.get("retired_ids") is Array):
		h["retired_ids"] = []
	return h.retired_ids


func current_record() -> Dictionary:
	var list := records()
	return list[_current] if _current >= 0 and _current < list.size() and list[_current] is Dictionary else {}


func refresh_list() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var q := _search.text.strip_edges().to_lower()
	var list := records()
	for i in list.size():
		var r: Variant = list[i]
		if not (r is Dictionary):
			continue
		var text := list_text(r)
		if q != "" and text.to_lower().find(q) == -1:
			continue
		var it := _tree.create_item(root)
		it.set_text(0, text)
		it.set_metadata(0, i)
		if not RPGIds.is_valid(r.get("id")):
			it.set_custom_color(0, Color(1, 0.5, 0.4))
			it.set_tooltip_text(0, "This ID is not valid.")
		if i == _current:
			it.select(0)


## The list line of a record: its ID and its name (or label, for switches and variables).
static func list_text(r: Dictionary) -> String:
	var shown := str(r.get("name", ""))
	if shown == "":
		shown = str(r.get("label", ""))
	return "%s  —  %s" % [r.get("id", "?"), shown]


## Shows a message under the list buttons ("" hides it).
func show_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""


func select(i: int) -> void:
	_current = i
	_invalid.clear()
	show_note("")
	var r := current_record()
	if r.is_empty():
		_show_empty()
		return
	_title.text = "%s: %s" % [config.get("label", ""), r.get("id", "")]
	_form.visible = true
	if config.has("record_fields") and config.record_fields.is_valid():
		var want: Array = config.record_fields.call(r)
		if JSON.stringify(want) != JSON.stringify(_fields):
			_fields = want
			_form.setup(_fields, data, registry, config.get("form_options", {}))
	_form.set_value(form_value(r))
	_apply_equip_filters()
	_build_formula_tests(r)
	refresh_preview()
	for c in _extra_box.get_children():
		c.queue_free()
	if config.has("extra") and config.extra.is_valid():
		var ex: Variant = config.extra.call(self, r)
		if ex is Control:
			_extra_box.add_child(ex)
	var it := _tree.get_root().get_first_child() if _tree.get_root() else null
	while it != null:
		if it.get_metadata(0) == i:
			it.select(0)
			_tree.scroll_to_item(it)
		it = it.get_next()


func _show_empty() -> void:
	_title.text = "%s: no records yet. Press New." % config.get("label", "")
	_form.visible = false
	for c in _extra_box.get_children():
		c.queue_free()
	refresh_preview()


func _on_selected() -> void:
	var it := _tree.get_selected()
	if it:
		select(int(it.get_metadata(0)))


## What the form shows for a record: the record plus its "virtual" fields.
func form_value(r: Dictionary) -> Dictionary:
	var v := r.duplicate()
	for f in _fields:
		if f.get("virtual", false):
			v[str(f.key)] = RPGRecordSchemas.virtual_value(str(config.get("type", "")), str(f.key), r)
	return v


func _on_form_changed(key: String, _v: Variant) -> void:
	var list := records()
	if _current < 0 or _current >= list.size():
		return
	var merged: Dictionary = _form.get_value()
	# Edit in place, only the form's own fields, so other editors of the same record (e.g. a
	# command list) and unknown fields stay as they are.
	var rec: Dictionary = list[_current]
	for f in _fields:
		var k := str(f.get("key", ""))
		if f.get("virtual", false):
			if k == key:
				for sk in RPGRecordSchemas.apply_virtual(str(config.get("type", "")), k, merged[k], rec):
					_form.set_field(sk, rec[sk])
				merged = _form.get_value()
			continue
		if f.get("drop_hidden", false) and not RPGCommand._visible(f, merged):
			rec.erase(k)
			continue
		if not merged.has(k):
			continue
		if f.has("coerce_by"):
			var c := coerce(merged[k], str(merged.get(f.coerce_by, rec.get(f.coerce_by, "string"))))
			if not c.ok:
				_invalid[k] = "%s: %s" % [f.get("label", k), c.error]
				continue
			_invalid.erase(k)
			rec[k] = c.value
		else:
			rec[k] = merged[k]
	mark_dirty()
	if not _invalid.is_empty():
		_status.text = "[color=#f86]%s Not saved until fixed.[/color]" % _esc(" ".join(PackedStringArray(_invalid.values())))
	refresh_preview()
	if key == "class":
		_apply_equip_filters()
	var it := _tree.get_selected()
	if it:
		it.set_text(0, list_text(rec))


## Equipment pickers (fields with "equip_slot") mark the items that do not fit the slot or the
## class of the record shown (RPGValidator.equip_problem, the same rule as Save and the game).
func _apply_equip_filters() -> void:
	var rec := current_record()
	var cls := data.record("classes", str(rec.get("class", ""))) if data != null else {}
	var slots := {}
	if data != null:
		for e in data.record("types", "equip_slots").get("entries", []):
			if e is Dictionary and e.has("id"):
				slots[str(e.id)] = e
	for rp: RPGRefPicker in _find_pickers(_form):
		if not rp.has_meta("equip_slot"):
			continue
		var slot := str(rp.get_meta("equip_slot"))
		var kind: String = rp.ref_kind
		rp.entry_filter = func(id: String) -> String:
			var item := data.record("weapons" if kind == "weapon" else "armors", id)
			return RPGValidator.equip_problem(slot, slots.get(slot, {}), kind, item, cls)
		rp._refresh_button()


static func _find_pickers(node: Node) -> Array:
	var out := []
	if node is RPGRefPicker:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_pickers(c))
	return out


## Updates every picker's text (a record it names may have changed in another tab).
func refresh_refs() -> void:
	if _form != null:
		RPGRefPicker.refresh_all(_form)
	if _extra_box != null:
		RPGRefPicker.refresh_all(_extra_box)


## Turns typed text into a value of `type` (int, float, bool, string): {ok, value, error}.
## Values that are not text (already typed) are kept.
static func coerce(v: Variant, type: String) -> Dictionary:
	if typeof(v) != TYPE_STRING:
		return {"ok": true, "value": v, "error": ""}
	var t := str(v).strip_edges()
	match type:
		"int":
			if t.is_valid_int():
				return {"ok": true, "value": int(t), "error": ""}
			return {"ok": false, "value": null, "error": "'%s' is not a whole number." % t}
		"float":
			if t.is_valid_float() or t.is_valid_int():
				return {"ok": true, "value": float(t), "error": ""}
			return {"ok": false, "value": null, "error": "'%s' is not a number." % t}
		"bool":
			if t.to_lower() in ["true", "on", "yes", "1"]:
				return {"ok": true, "value": true, "error": ""}
			if t.to_lower() in ["false", "off", "no", "0", ""]:
				return {"ok": true, "value": false, "error": ""}
			return {"ok": false, "value": null, "error": "type true or false, not '%s'." % t}
	return {"ok": true, "value": str(v), "error": ""}


## Escapes text for the BBCode status line.
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


## Rebuilds the side preview (config "preview") for the current record.
func refresh_preview() -> void:
	if _preview_box == null:
		return
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	var r := current_record()
	_preview_box.visible = false
	if r.is_empty() or not config.has("preview") or not config.preview.is_valid():
		return
	var pv: Variant = config.preview.call(r)
	if pv is Control:
		_preview_box.add_child(pv)
		_preview_box.visible = true


func mark_dirty() -> void:
	if not dirty:
		dirty = true
		dirty_changed.emit(true)
	if get_parent() is TabContainer:
		var tc: TabContainer = get_parent()
		tc.set_tab_title(get_index(), str(config.get("label", name)) + " *")


## Marks the tab saved without writing (another tab wrote the same file).
func clear_dirty() -> void:
	_clear_dirty()


func _clear_dirty() -> void:
	dirty = false
	dirty_changed.emit(false)
	if get_parent() is TabContainer:
		var tc: TabContainer = get_parent()
		tc.set_tab_title(get_index(), str(config.get("label", name)))


func save_now() -> bool:
	if not _invalid.is_empty():
		_status.text = "[color=#f86]Not saved. %s[/color]" % _esc(" ".join(PackedStringArray(_invalid.values())))
		return false
	var err: Error = config.save.call()
	if err != OK:
		_status.text = "[color=#f86]Could not save (error %d). The file on disk is unchanged.[/color]" % err
		return false
	_clear_dirty()
	saved.emit()
	show_problems(name_problems() + (config.validate.call() if config.has("validate") else []), "Saved")
	return true


## Records of this tab with an empty name (a warning on Save; switches and variables have labels).
func name_problems() -> Array:
	var out := []
	if not _fields.any(func(f): return str(f.get("key", "")) == "name"):
		return out
	for r in records():
		if r is Dictionary and str(r.get("name", "")).strip_edges() == "":
			out.append({"severity": "warning", "file": str(config.get("path", "")), "record": str(r.get("id", "")),
				"message": "'%s' has no name, so the game shows an empty name." % r.get("id", ""), "fix_hint": "Type a name."})
	return out


## Shows problems in the status line, after `prefix` ("Saved"). Problems in other files (e.g.
## an event that still uses a deleted item) name their file.
func show_problems(probs: Array, prefix: String) -> void:
	if probs.is_empty():
		_status.text = "[color=#8f8]%s. No problems found.[/color]" % prefix
		return
	var own := str(config.get("path", ""))
	var lines := PackedStringArray()
	for p in probs.slice(0, 6):
		var where := str(p.get("record", ""))
		var file := str(p.get("file", ""))
		if own != "" and file != own:
			where = ("%s %s" % [file.get_file(), where]).strip_edges()
		lines.append("[color=%s]%s[/color] %s: %s" % ["#f86" if p.get("severity", "") == "error" else "#fc6", p.get("severity", ""), _esc(where), _esc(str(p.get("message", "")))])
	if probs.size() > 6:
		lines.append("… %d more (Check project lists them all)" % (probs.size() - 6))
	_status.text = "%s with %d problem(s):\n%s" % [prefix, probs.size(), "\n".join(lines)]


## The status line as plain text (for tests and tooltips).
func status_text() -> String:
	return _status.get_parsed_text()


# --- record operations -----------------------------------------------------------------

func _new_id(base: String) -> String:
	return RPGIds.unique(base, ids(), _retired())


## The ID New gives: "<base>_<n>" (n = the record count + 1, then the next free number).
func new_id() -> String:
	var base := str(config.get("new_id_base", config.get("ref_kind", "record")))
	if base == "":
		base = "record"
	return _new_id("%s_%d" % [base, records().size() + 1])


func new_record() -> void:
	var r := RPGRecordSchemas.new_record(str(config.get("type", "")), new_id(), _fields)
	if config.has("new_record") and config.new_record.is_valid():
		config.new_record.call(r)
	var list := records()
	var at := _current + 1 if _current >= 0 else list.size()
	list.insert(at, r)
	mark_dirty()
	_current = at
	refresh_list()
	select(at)


func duplicate_record() -> void:
	var r := current_record()
	if r.is_empty():
		return
	var copy: Dictionary = r.duplicate(true)
	copy["id"] = _new_id(str(r.get("id", "record")))
	var list := records()
	list.insert(_current + 1, copy)
	mark_dirty()
	refresh_list()
	select(_current + 1)


func copy_record() -> void:
	var r := current_record()
	if r.is_empty():
		return
	_clipboards[config.get("type", "")] = r.duplicate(true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(RPGJson.stringify(r))


func paste_record() -> void:
	var src: Variant = _clipboards.get(config.get("type", ""))
	if DisplayServer.get_name() != "headless":
		var parsed := RPGJson.parse_text(DisplayServer.clipboard_get())
		if parsed.ok and parsed.data is Dictionary and parsed.data.has("id"):
			src = parsed.data
	if not (src is Dictionary):
		return
	var copy: Dictionary = src.duplicate(true)
	copy["id"] = _new_id(str(copy.get("id", "record")))
	var list := records()
	var at := _current + 1 if _current >= 0 else list.size()
	list.insert(at, copy)
	mark_dirty()
	refresh_list()
	select(at)


func _confirm_delete() -> void:
	var r := current_record()
	if r.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = delete_prompt(r)
	dlg.confirmed.connect(func(): delete_record(); dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## The delete confirmation, with how many places use the record.
func delete_prompt(r: Dictionary) -> String:
	var id := str(r.get("id", ""))
	var text := "Delete '%s'? Its ID will not be reused." % id
	var kind := str(config.get("ref_kind", ""))
	if kind == "" or data == null:
		return text
	var uses := RPGValidator.used_by(data, registry, kind, id)
	if uses.is_empty():
		return text + "\nNothing in the project refers to it."
	# Per file, the records (or map events) that use it: "actors.json (rin)".
	var files := {}
	for u in uses:
		var f := str(u.get("file", "")).get_file()
		if not files.has(f):
			files[f] = []
		var who := str(u.get("record", ""))
		if who != "" and not files[f].has(who):
			files[f].append(who)
	var parts := PackedStringArray()
	for f in files:
		var who: Array = files[f]
		parts.append(f if who.is_empty() else "%s (%s)" % [f, ", ".join(PackedStringArray(who.slice(0, 6))) + (", …" if who.size() > 6 else "")])
	return text + "\n\nIt is used in %d place(s): %s.\nThose references will show as problems until you change them." % [uses.size(), "; ".join(parts)]


func delete_record() -> void:
	var r := current_record()
	if r.is_empty():
		return
	var id := str(r.get("id", ""))
	if id != "" and not _retired().has(id):
		_retired().append(id)
	records().remove_at(_current)
	mark_dirty()
	_current = mini(_current, records().size() - 1)
	refresh_list()
	if _current >= 0:
		select(_current)
	else:
		_show_empty()


func move_record(d: int) -> void:
	var list := records()
	var j := _current + d
	if _current < 0 or j < 0 or j >= list.size():
		return
	var t: Variant = list[_current]
	list[_current] = list[j]
	list[j] = t
	_current = j
	mark_dirty()
	refresh_list()


func _get_drag(_pos: Vector2) -> Variant:
	var it := _tree.get_selected()
	if it == null:
		return null
	_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
	var l := Label.new()
	l.text = it.get_text(0)
	_tree.set_drag_preview(l)
	return {"rpg_record": int(it.get_metadata(0)), "tab": self}


func _can_drop(_pos: Vector2, d: Variant) -> bool:
	return d is Dictionary and d.get("tab") == self


func _drop(pos: Vector2, d: Variant) -> void:
	_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
	var from: int = d.rpg_record
	var it := _tree.get_item_at_position(pos)
	var list := records()
	var to := list.size()
	if it != null:
		to = int(it.get_metadata(0)) + (1 if _tree.get_drop_section_at_position(pos) > 0 else 0)
	var rec: Variant = list[from]
	list.remove_at(from)
	if from < to:
		to -= 1
	list.insert(clampi(to, 0, list.size()), rec)
	_current = clampi(to, 0, list.size() - 1)
	mark_dirty()
	refresh_list()


func _rename_dialog() -> void:
	var r := current_record()
	if r.is_empty() or str(config.get("ref_kind", "")) == "":
		return
	rename_requested.emit(str(config.ref_kind), str(r.get("id", "")))


# --- formula tests -----------------------------------------------------------------------

## Who the formula Test uses: "actor:<id>" or "enemy:<id>" for the user (a) and the target (b),
## plus the user's level. Kept while the tab is open.
var test_user := ""
var test_target := ""
var test_level := 1


func _build_formula_tests(r: Dictionary) -> void:
	for c in _formula_box.get_children():
		c.queue_free()
	var has_formula := false
	for f in config.get("fields", []):
		if f.get("formula", false):
			has_formula = true
	if not has_formula:
		return
	# User / target pickers (spec: test formulas with chosen sample battlers).
	var pick := HBoxContainer.new()
	var choices := _battler_choices()
	if test_user == "" and not choices.is_empty():
		test_user = choices[0][1]
	if test_target == "":
		for ch in choices:
			if str(ch[1]).begins_with("enemy:"):
				test_target = ch[1]
				break
	for spec in [["User (a)", "test_user"], ["Target (b)", "test_target"]]:
		var l := Label.new()
		l.text = spec[0]
		pick.add_child(l)
		var ob := OptionButton.new()
		for i in choices.size():
			ob.add_item(choices[i][0])
			ob.set_item_metadata(i, choices[i][1])
			if choices[i][1] == get(spec[1]):
				ob.select(i)
		var prop: String = spec[1]
		ob.item_selected.connect(func(i: int): set(prop, str(ob.get_item_metadata(i))))
		pick.add_child(ob)
	var lv_label := Label.new()
	lv_label.text = "Lv"
	pick.add_child(lv_label)
	var lv := SpinBox.new()
	lv.min_value = 1
	lv.max_value = 99
	lv.value = test_level
	lv.value_changed.connect(func(v: float): test_level = int(v))
	pick.add_child(lv)
	_formula_box.add_child(pick)
	for f in config.get("fields", []):
		if not f.get("formula", false):
			continue
		var hb := HBoxContainer.new()
		var b := Button.new()
		b.text = "Test %s" % f.get("label", f.key)
		b.tooltip_text = "Evaluate with the chosen user (a) and target (b)"
		var out := Label.new()
		out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): out.text = test_formula(str(current_record().get(f.key, ""))))
		hb.add_child(b)
		hb.add_child(out)
		_formula_box.add_child(hb)


func _battler_choices() -> Array:
	var out := []
	for a in data.records("actors"):
		out.append(["Actor: %s" % a.get("name", a.get("id", "")), "actor:%s" % a.get("id", "")])
	for e in data.records("enemies"):
		out.append(["Enemy: %s" % e.get("name", e.get("id", "")), "enemy:%s" % e.get("id", "")])
	return out


func _make_battler(spec: String) -> Variant:
	if rules == null:
		return null
	var parts := spec.split(":", true, 1)
	if parts.size() < 2:
		return null
	if parts[0] == "actor" and rules.has_method("new_actor_battler") and data.has_record("actors", parts[1]):
		return rules.new_actor_battler(parts[1], test_level)
	if parts[0] == "enemy" and rules.has_method("new_enemy_battler") and data.has_record("enemies", parts[1]):
		return rules.new_enemy_battler(parts[1])
	return null


## Evaluates a formula with a sample actor and enemy. Returns readable text.
func test_formula(text: String) -> String:
	if rules == null or not rules.has_method("evaluate_formula"):
		return "No rule system is loaded."
	if text.strip_edges() == "":
		return "The formula is empty."
	var choices := _battler_choices()
	if test_user == "" and not choices.is_empty():
		test_user = choices[0][1]
	if test_target == "":
		for ch in choices:
			if str(ch[1]).begins_with("enemy:"):
				test_target = ch[1]
				break
	var a: Variant = _make_battler(test_user)
	var b: Variant = _make_battler(test_target)
	var prev: bool = rules.report_errors
	rules.report_errors = false
	var r: Dictionary = rules.evaluate_formula(text, a, b, {"s": current_record(), "where": str(current_record().get("id", ""))})
	rules.report_errors = prev
	var who := "%s (Lv %d) vs %s" % [a.name if a != null else "nobody", test_level, b.name if b != null else "nobody"]
	if r.get("ok", false):
		return "%s: %s" % [who, str(r.value)]
	return "Error: %s" % r.get("error", "?")
