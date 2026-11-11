@tool
class_name RPGRefPicker
extends HBoxContainer
## Searchable dropdown of IDs from RPGProjectData (switches, variables, maps, database records...).
## Switch and variable pickers have a "New…" entry that adds a definition to state.json in memory
## (marked dirty through RPGFormBuilder.mark_dirty) without leaving the form.
## Values that no longer exist stay selected and are shown with a warning, never silently replaced.
## `entry_filter` (optional, Callable(id: String) -> String) marks entries that do not fit here
## (e.g. armour that does not fit an equipment slot): they are listed last with the reason.
## In the Database, New… also writes the new definition to state.json at once (the screen sets
## the "rpg_new_def_hook" meta on the project data).

signal value_changed(value: Variant)

const DB_KIND := {
	"actor": "actors", "class": "classes", "skill": "skills", "item": "items", "weapon": "weapons",
	"armor": "armors", "enemy": "enemies", "troop": "troops", "state": "states",
	"animation": "animations", "tileset": "tilesets",
}
## Names of special values in `allow` (others are capitalised).
const ALLOW_LABELS := {"this": "This event", "player": "Player", "party": "Whole party", "leader": "Party leader"}

var ref_kind := "switch"
var data: RPGProjectData
var allow: Array = []
## Labels of the special values in `allow` (others use ALLOW_LABELS or are capitalised).
var allow_labels: Dictionary = {}
var allow_empty := true
## Callable(id: String) -> String: why an entry does not fit here ("" when it does).
var entry_filter: Callable = Callable()
var map_id := ""
var _value: Variant = ""
var _button: Button
var _new_button: Button
var _popup: PopupPanel
var _search: LineEdit
var _list: ItemList
var _entries: Array = []   # [{id, label}]


func _init(p_kind := "switch", p_data: RPGProjectData = null, p_allow: Array = [], p_allow_empty := true) -> void:
	ref_kind = p_kind
	data = p_data
	allow = p_allow
	allow_empty = p_allow_empty
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button = Button.new()
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.clip_text = true
	_button.tooltip_text = "Click to choose. Type to search."
	_button.pressed.connect(_open)
	add_child(_button)
	_new_button = Button.new()
	_new_button.text = "New…"
	_new_button.tooltip_text = "Add a new %s to the project" % p_kind
	_new_button.pressed.connect(_new_definition)
	add_child(_new_button)
	_refresh_button()


func set_ref_kind(k: String) -> void:
	ref_kind = k
	_refresh_button()


func set_value(v: Variant) -> void:
	_value = v
	_refresh_button()


func get_value() -> Variant:
	return _value


## [{id, label}] for the current kind, without the empty/allow entries.
func entries() -> Array:
	var out := []
	if data == null:
		return out
	match ref_kind:
		"switch":
			for id in data.switches:
				out.append({"id": id, "label": str(data.switches[id].get("label", ""))})
		"variable":
			for id in data.variables:
				var v: Dictionary = data.variables[id]
				out.append({"id": id, "label": "%s (%s)" % [v.get("label", ""), v.get("type", "int")]})
		"map":
			for id in data.maps:
				out.append({"id": id, "label": str(data.maps[id].get("name", ""))})
		"common_event":
			for id in data.common_events:
				out.append({"id": id, "label": str(data.common_events[id].get("name", ""))})
		"event":
			if map_id != "":
				for e in data.map_events(map_id):
					if e is Dictionary:
						out.append({"id": str(e.get("id", "")), "label": str(e.get("name", ""))})
		_:
			var db_type := str(DB_KIND.get(ref_kind, RPGCommandRegistry.database_type_of(ref_kind)))
			if db_type != "":
				# A record type an extension owns (manifest "database_types") loads on first use.
				if not data.db.has(db_type):
					data.add_db_types([db_type])
				for r in data.records(db_type):
					if r is Dictionary and r.has("id"):
						out.append({"id": str(r.id), "label": str(r.get("name", ""))})
	return out


static func allow_label(v: String) -> String:
	return str(ALLOW_LABELS.get(v, v.capitalize()))


func _allow_label(v: String) -> String:
	return str(allow_labels.get(v, allow_label(v)))


## Why `id` does not fit here ("" when it does, or when there is no filter).
func misfit(id: String) -> String:
	if id == "" or not entry_filter.is_valid():
		return ""
	return str(entry_filter.call(id))


## Updates the button text of every picker under `node` (the records they name may have been
## renamed or edited in another tab).
static func refresh_all(node: Node) -> void:
	if node is RPGRefPicker:
		(node as RPGRefPicker)._refresh_button()
	for c in node.get_children():
		refresh_all(c)


func _exists(id: String) -> bool:
	for e in entries():
		if e.id == id:
			return true
	return false


func _refresh_button() -> void:
	if _new_button:
		_new_button.visible = ref_kind == "switch" or ref_kind == "variable"
	if _button == null:
		return
	var v := str(_value) if _value != null else ""
	if v == "":
		_button.text = "(none)"
		_button.remove_theme_color_override("font_color")
	elif allow.has(v):
		_button.text = _allow_label(v)
		_button.remove_theme_color_override("font_color")
	elif _exists(v):
		var label := ""
		for e in entries():
			if e.id == v:
				label = e.label
		_button.text = v if label == "" else "%s  —  %s" % [v, label]
		var why := misfit(v)
		if why != "":
			_button.text = "⚠ %s" % _button.text
			_button.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
		else:
			_button.remove_theme_color_override("font_color")
		_button.tooltip_text = why if why != "" else "Click to choose. Type to search."
	else:
		_button.text = "⚠ %s (missing)" % v
		_button.add_theme_color_override("font_color", Color(1, 0.6, 0.3))


func _open() -> void:
	if _popup == null:
		_popup = PopupPanel.new()
		var vb := VBoxContainer.new()
		_popup.add_child(vb)
		_search = LineEdit.new()
		_search.placeholder_text = "Search…"
		_search.clear_button_enabled = true
		_search.text_changed.connect(func(_t): _fill())
		_search.text_submitted.connect(func(_t): _choose_index(0 if _list.item_count > 0 else -1))
		vb.add_child(_search)
		_list = ItemList.new()
		_list.custom_minimum_size = Vector2(320, 260)
		_list.item_activated.connect(_choose_index)
		_list.item_clicked.connect(func(i, _p, _b): _choose_index(i))
		vb.add_child(_list)
		add_child(_popup)
	_search.text = ""
	_fill()
	# Under the button, in the right coordinates whether or not Godot embeds windows.
	preload("res://addons/rpg/editor/rpg_popup_place.gd").below(_button, _popup, Vector2i(340, 300))
	_search.grab_focus()


func _fill() -> void:
	_list.clear()
	_entries.clear()
	var q := _search.text.strip_edges().to_lower()
	var all := []
	if allow_empty:
		all.append({"id": "", "label": "(none)"})
	for a in allow:
		all.append({"id": a, "label": _allow_label(str(a)), "special": true})
	# Entries that do not fit here go last, marked with the reason.
	var misfits := []
	for e in entries():
		var why := misfit(str(e.id))
		if why == "":
			all.append(e)
		else:
			var m: Dictionary = e.duplicate()
			m["why"] = why
			misfits.append(m)
	all.append_array(misfits)
	for e in all:
		var text: String = e.id if e.label == "" else "%s  —  %s" % [e.id, e.label]
		if e.get("special", false):
			text = e.label
		if e.id == "":
			text = "(none)"
		if e.has("why"):
			text = "⚠ %s  (%s)" % [text, e.why]
		if q != "" and text.to_lower().find(q) == -1:
			continue
		_entries.append(e)
		_list.add_item(text)
		if e.has("why"):
			_list.set_item_custom_fg_color(_list.item_count - 1, Color(1, 0.8, 0.4))
		if str(_value) == e.id:
			_list.select(_list.item_count - 1)


func _choose_index(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	_popup.hide()
	_value = _entries[i].id
	_refresh_button()
	value_changed.emit(_value)


func _new_definition() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "New %s" % ref_kind
	var vb := VBoxContainer.new()
	var id_edit := LineEdit.new()
	id_edit.placeholder_text = "id, e.g. door_unlocked"
	var label_edit := LineEdit.new()
	label_edit.placeholder_text = "Label shown in lists"
	var type_opt := OptionButton.new()
	for t in ["int", "float", "bool", "string"]:
		type_opt.add_item(t)
	var msg := Label.new()
	msg.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	vb.add_child(_labelled("ID", id_edit))
	vb.add_child(_labelled("Label", label_edit))
	if ref_kind == "variable":
		vb.add_child(_labelled("Type", type_opt))
	vb.add_child(msg)
	dlg.add_child(vb)
	label_edit.text_changed.connect(func(t):
		if id_edit.text == "" or id_edit.has_meta("auto"):
			id_edit.text = RPGIds.slug(t)
			id_edit.set_meta("auto", true))
	dlg.get_ok_button().pressed.connect(func():
		var id := id_edit.text.strip_edges()
		var err := add_definition(data, ref_kind, id, label_edit.text, type_opt.get_item_text(type_opt.selected))
		if err != "":
			msg.text = err
			dlg.popup_centered.call_deferred()
			return
		_value = id
		_refresh_button()
		value_changed.emit(_value)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(360, 160))
	id_edit.grab_focus()


## Adds a switch or variable definition to the in-memory state.json. Returns "" or an error.
static func add_definition(p_data: RPGProjectData, kind: String, id: String, label := "", var_type := "int") -> String:
	if p_data == null:
		return "No project is open."
	if not RPGIds.is_valid(id):
		return "IDs use lowercase letters, digits and _, and start with a letter."
	var reg: Dictionary = p_data.switches if kind == "switch" else p_data.variables
	if reg.has(id):
		return "'%s' already exists." % id
	var def := {"id": id, "label": label if label != "" else id.capitalize(), "folder": "", "description": ""}
	var key := "switches"
	if kind == "variable":
		key = "variables"
		def["type"] = var_type
		def["default"] = {"int": 0, "float": 0.0, "bool": false, "string": ""}.get(var_type, 0)
	if not (p_data.state_defs.get(key) is Array):
		p_data.state_defs[key] = []
	p_data.state_defs[key].append(def)
	reg[id] = def
	var added: Array = p_data.get_meta("rpg_new_defs", [])
	added.append([key, def])
	p_data.set_meta("rpg_new_defs", added)
	RPGFormBuilder.mark_dirty(p_data, "state.json")
	# The Database writes it at once (its forms have no window Save of their own).
	var hook: Variant = p_data.get_meta("rpg_new_def_hook") if p_data.has_meta("rpg_new_def_hook") else null
	if hook is Callable and (hook as Callable).is_valid():
		(hook as Callable).call()
	return ""


## Writes the definitions added with "New…" into state.json as it is on disk now (the Database
## tab may have changed it since this window loaded), then refreshes the in-memory copy.
static func save_new_defs(p_data: RPGProjectData) -> Error:
	var path := p_data.root.path_join("state.json")
	var disk: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "switches": [], "variables": []})
	for key in ["switches", "variables"]:
		if not (disk.get(key) is Array):
			disk[key] = []
	for pair in p_data.get_meta("rpg_new_defs", []):
		var list: Array = disk[pair[0]]
		var exists := false
		for d in list:
			if d is Dictionary and str(d.get("id", "")) == str(pair[1].id):
				exists = true
		if not exists:
			list.append(pair[1])
	var err := RPGJson.save_file(path, disk)
	if err == OK:
		p_data.remove_meta("rpg_new_defs")
		p_data.state_defs = disk
		for key in ["switches", "variables"]:
			var reg: Dictionary = p_data.switches if key == "switches" else p_data.variables
			reg.clear()
			for d in disk[key]:
				if d is Dictionary and d.has("id"):
					reg[d.id] = d
	return err


func _labelled(text: String, c: Control) -> Control:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 60
	hb.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(c)
	return hb
