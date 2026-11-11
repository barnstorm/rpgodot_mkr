@tool
class_name RPGDatabaseScreen
extends Control
## The "Database" main screen: one sub-tab per record type (Actors ... Terms), plus Common
## events, Switches and variables (with "Used by") and System. Record types owned by enabled
## extensions (manifest "database_types") get a tab each, before Common events.
##
##   var screen := RPGDatabaseScreen.new()
##   screen.setup(editor_plugin_or_null)            # loads res://rpg
##   screen.battle_test = func(troop_id): ...       # the plugin starts a battle test
##   screen.reload()                                # any time; unsaved tabs keep their edits
##
## Before rpg/project.json exists the screen only says to create the project on the RPG tab
## (no New or Save); it fills in by itself once the files appear (check_disk_changes / reload).
## Saves are atomic and keep unknown fields. Each tab's Save (or Ctrl+S) also runs that tab's
## share of the project checks. Renaming an ID goes through RPGValidator.rename_id and writes
## every affected file as one transaction (rolled back if any write fails); the rename joins the
## editor's undo history (Ctrl+Z writes the files back). Switches and variables made with New…
## in any form here are written to state.json at once.

const FormColumn := preload("res://addons/rpg/editor/database/rpg_form_column.gd")
const Preview := preload("res://addons/rpg/editor/database/rpg_record_preview.gd")
const NO_PROJECT_TEXT := "This Godot project has no RPG project yet.\n\nCreate it on the RPG tab first (\"Create RPG project\"). This tab then shows the starter database: actors, classes, skills, items, monsters and the rest."

## Set by the plugin: called with the troop ID when "Battle test" is pressed.
var battle_test: Callable = Callable()
## Called with (map_id, event_id) to open a map event from a "Used by" entry (optional).
var open_location: Callable = Callable()

var plugin: Object
## Undo for renames: the editor's history inside Godot, a plain UndoRedo otherwise (tests).
var undo: RPGUndo
var _local_undo: UndoRedo
var data: RPGProjectData
var registry: RPGCommandRegistry
var rules: Variant = null
var root_dir := "res://rpg"

var _tabs: TabContainer
var _record_tabs: Array = []
var _status: Label
var _system_status: Label
var _system_file: Dictionary = {}
## System keys edited in the form since the last save (merged into the file on disk on save).
var _system_edits: Dictionary = {}
## The leaves of nested System values edited since the last save: "a/b/c" -> [path, value].
## Saving writes only these into the file on disk, so e.g. a vehicle start set on the map
## survives renaming the vehicle here.
var _system_paths: Dictionary = {}
## What the System form showed last, per key (to find which leaves an edit changed).
var _system_shown: Dictionary = {}
## Content hashes of the project files as this tab last read or wrote them.
var _stamps: Dictionary = {}


func setup(editor_plugin: Object = null, p_root := "res://rpg") -> void:
	plugin = editor_plugin
	root_dir = p_root
	if plugin != null and plugin.has_method("get_undo_redo"):
		undo = RPGUndo.new(plugin.get_undo_redo())
	else:
		_local_undo = UndoRedo.new()
		undo = RPGUndo.new(_local_undo)
	name = "Database"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	reload()


## True once rpg/project.json exists (the RPG tab's "Create RPG project" writes it).
func project_exists() -> bool:
	return FileAccess.file_exists(root_dir.path_join("project.json"))


## Reads the project again and rebuilds the tabs. Safe to call at any time (the RPG tab calls it
## after creating a project or changing extensions): tabs with unsaved edits keep them and stay
## marked unsaved, unless `keep_unsaved` is false (Reload > "Discard and reload").
func reload(keep_unsaved := true) -> void:
	var kept := {}          # file path -> the unsaved file Dictionary of a dirty tab
	var kept_types := {}    # tab type -> true
	var kept_labels := PackedStringArray()
	var kept_system := {}
	if keep_unsaved:
		for t in dirty_tabs():
			kept[str(t.config.get("path", ""))] = t.config.holder.call()
			kept_types[str(t.config.get("type", ""))] = true
			kept_labels.append(str(t.config.get("label", "")))
		if system_dirty():
			kept_system = {"edits": _system_edits, "paths": _system_paths}
			kept_labels.append("System")
	var selected := {}
	for t in _record_tabs:
		if is_instance_valid(t):
			selected[str(t.config.get("type", ""))] = str(t.current_record().get("id", ""))
	data = RPGProjectData.open(root_dir)
	# Switches and variables made with New… in a form are written at once (RPGRefPicker).
	data.set_meta("rpg_new_def_hook", _write_new_defs)
	registry = RPGCommandRegistry.new()
	registry.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), data.project.get("extensions_root", "res://extensions"))
	# Record types the enabled extensions own (manifest "database_types") get tabs too.
	data.add_db_types(registry.database_types())
	rules = null
	var rules_name := str(data.project.get("rules", "classic"))
	if ResourceLoader.exists("res://addons/rpg/runtime/rules/rpg_rule_system.gd"):
		var rs: Script = load("res://addons/rpg/runtime/rules/rpg_rule_system.gd")
		rules = rs.load_rules(rules_name, data)
	var sys_path := root_dir.path_join("database/system.json")
	_system_file = RPGJson.load_or(sys_path, {"schema_version": 1, "system": {}})
	if not (_system_file.get("system") is Dictionary):
		_system_file["system"] = {}
	_system_edits = {}
	_system_paths = {}
	for path in kept:
		_adopt(path, kept[path])
	if not kept_system.is_empty():
		_system_edits = kept_system.edits
		_system_paths = kept_system.paths
		_apply_system_edits(_system_file.system)
	_build()
	for t in _record_tabs:
		var type := str(t.config.get("type", ""))
		if kept_types.has(type):
			t.mark_dirty()
		if str(selected.get(type, "")) != "":
			_select_id(t, selected[type])
	if not kept_system.is_empty() and _system_status:
		_system_status.text = "Unsaved changes"
	_stamps = disk_stamps()
	if not kept_labels.is_empty() and _status:
		_status.text = "Reloaded. Unsaved changes kept in: %s." % ", ".join(kept_labels)


## Puts a dirty tab's unsaved file Dictionary into freshly loaded data.
## Writes the switches and variables added with New… (RPGRefPicker.add_definition) into
## state.json as it is on disk, keeping unsaved edits of the Switches tab where they are, and
## shows them in the Switches and variables tabs.
func _write_new_defs() -> void:
	var added: Array = data.get_meta("rpg_new_defs", [])
	if added.is_empty():
		return
	var path := root_dir.path_join("state.json")
	var disk: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "switches": [], "variables": []})
	var names := PackedStringArray()
	for pair in added:
		if not (disk.get(pair[0]) is Array):
			disk[pair[0]] = []
		if not disk[pair[0]].any(func(d): return d is Dictionary and str(d.get("id", "")) == str(pair[1].id)):
			disk[pair[0]].append(RPGJson.deep_copy(pair[1]))
		names.append(str(pair[1].id))
	var err := RPGJson.save_file(path, disk)
	if err != OK:
		if _status:
			_status.text = "Could not write state.json (error %d): %s is not saved yet." % [err, ", ".join(names)]
		return
	data.remove_meta("rpg_new_defs")
	RPGFormBuilder.clear_dirty(data, "state.json")
	_restamp([path])
	for t in _record_tabs:
		if is_instance_valid(t) and str(t.config.get("type", "")) in ["switches", "variables"]:
			t.refresh_list()
	if _status:
		_status.text = "Added %s to Switches and variables (state.json)." % ", ".join(names)


func _adopt(path: String, holder: Dictionary) -> void:
	if path == root_dir.path_join("state.json"):
		data.state_defs = holder
		_index_state()
	elif path == root_dir.path_join("common_events.json"):
		data.common_events_file = holder
		_index_common_events()
	else:
		for type in data.db:
			if _file_path(type) == path:
				data.db[type].file = holder
				_reindex(type)


func _select_id(tab: RPGRecordTab, id: String) -> void:
	var recs: Array = tab.records()
	for i in recs.size():
		if recs[i] is Dictionary and str(recs[i].get("id", "")) == id:
			tab.select(i)
			return


## Content hashes of every JSON file this tab edits.
func disk_stamps() -> Dictionary:
	var out := {}
	for f in _watched_files():
		if FileAccess.file_exists(f):
			out[f] = FileAccess.get_md5(f)
	return out


func _watched_files() -> Array:
	var files := [root_dir.path_join("state.json"), root_dir.path_join("common_events.json"), root_dir.path_join("project.json")]
	var dir := root_dir.path_join("database")
	for f in (DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()):
		if f.ends_with(".json"):
			files.append(dir.path_join(f))
	return files


## Records the current content of files this tab just wrote, so its own saves are never taken
## for changes made elsewhere.
func _restamp(paths: Array) -> void:
	for p in paths:
		var f := str(p)
		if f == "":
			continue
		if FileAccess.file_exists(f):
			_stamps[f] = FileAccess.get_md5(f)
		else:
			_stamps.erase(f)


## Called when the tab is shown: picks up files another tab (or tool) saved, including the first
## files ever written (a project created on the RPG tab). Reloads silently when nothing is
## unsaved here; otherwise says so and leaves the choice to Reload.
func check_disk_changes() -> bool:
	if disk_stamps() == _stamps:
		return false
	if dirty_tabs().is_empty() and not system_dirty():
		var had_project := _tabs != null
		reload()
		if _status:
			if not had_project and project_exists():
				_status.text = "Loaded the new project."
			else:
				_status.text = "Reloaded: project files changed in another tab or outside the editor."
		return true
	if _status:
		_status.text = "Project files changed elsewhere. Save or press Reload to see them."
	return false


func _build() -> void:
	var current := _tabs.current_tab if _tabs != null and is_instance_valid(_tabs) else 0
	for c in get_children():
		c.queue_free()
	_record_tabs.clear()
	_tabs = null
	_system_status = null
	if not project_exists():
		_build_no_project()
		return
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vb)
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	for spec in [["Save all", save_all, "Write every changed tab"], ["Reload", _confirm_reload, "Read the files again (asks first if something is unsaved)"],
			["Check project", _check_project, "Run the full project check"], ["JSON Schema", _write_schema, "Generate rpg/.schema/events.schema.json for code editors"],
			["Rule system: %s..." % str(data.project.get("rules", "classic")), _change_rules, "Switch the rule system (stats, formulas, battle maths), with a preview of what changes"]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.pressed.connect(spec[1])
		bar.add_child(b)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_tabs)
	# A tab shown again names the records of other tabs as they are now.
	_tabs.tab_changed.connect(func(_i): refresh_current_tab())
	var stats: Array = rules.stats() if rules != null else []
	var resources: Array = rules.resources() if rules != null else []
	var traits: Array = rules.trait_kinds() if rules != null and rules.has_method("trait_kinds") else []
	# The project's custom fields plus the ones its enabled extensions add (manifest custom_fields).
	var custom: Dictionary = registry.merged_custom_fields(data.project.get("custom_fields", {})) if registry != null else data.project.get("custom_fields", {})
	var rule_def: Dictionary = rules.definition if rules != null and "definition" in rules and rules.definition is Dictionary else {}
	var slots := []
	var types_rec := data.record("types", "equip_slots")
	if types_rec.get("entries") is Array:
		slots = types_rec.entries
	var type_lists := RPGRecordSchemas.type_lists(data)
	for t in RPGRecordSchemas.TABS:
		var type: String = t[0]
		match type:
			"common_events":
				# Extension record types (quests, ...) go after the built-in record tabs.
				for d in registry.database_types():
					_add_db_tab([d.type, d.label, d.ref], d.fields + RPGRecordSchemas.fields_for(d.type, stats, resources, traits, custom, slots, rule_def, type_lists))
				_add_common_events_tab(t, stats, resources, traits, custom, slots)
			"state":
				_add_state_tab()
			"system":
				_add_system_tab()
			_:
				_add_db_tab(t, RPGRecordSchemas.fields_for(type, stats, resources, traits, custom, slots, rule_def, type_lists))
	_tabs.current_tab = clampi(current, 0, _tabs.get_tab_count() - 1)


## Refreshes the pickers of the tab on show (records they name may have changed elsewhere).
func refresh_current_tab() -> void:
	if _tabs == null or not is_instance_valid(_tabs):
		return
	var cur: Control = _tabs.get_current_tab_control()
	if cur is TabContainer:
		cur = (cur as TabContainer).get_current_tab_control()
	if cur is RPGRecordTab:
		(cur as RPGRecordTab).refresh_refs()


## Before a project exists: no tabs, no New or Save; only what to do.
func _build_no_project() -> void:
	var centre := CenterContainer.new()
	centre.name = "NoProject"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	centre.add_child(box)
	var title := Label.new()
	title.text = "No RPG project yet"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var info := Label.new()
	info.text = NO_PROJECT_TEXT
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 460
	box.add_child(info)
	var again := Button.new()
	again.text = "Look again"
	again.tooltip_text = "Read %s again (this tab also does it each time it is shown)" % root_dir
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	again.pressed.connect(func(): check_disk_changes())
	box.add_child(again)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _file_path(type: String) -> String:
	return root_dir.path_join("database/%s.json" % type)


func _add_tab(cfg: Dictionary) -> RPGRecordTab:
	var tab := RPGRecordTab.new()
	_tabs.add_child(tab)
	tab.setup(cfg, data, registry, rules)
	_wire_tab(tab)
	return tab


func _wire_tab(tab: RPGRecordTab) -> void:
	tab.rename_requested.connect(_rename_id.bind(tab))
	tab.saved.connect(_restamp.bind([str(tab.config.get("path", ""))]))
	_record_tabs.append(tab)


func _add_db_tab(t: Array, fields: Array) -> void:
	var type: String = t[0]
	if not data.db.has(type):
		return
	var holder: Dictionary = data.db[type].file
	if not (holder.get("records") is Array):
		holder["records"] = []
	data.db[type].records = holder.records
	var path := _file_path(type)
	var ref_kind: String = t[2]
	var cfg := {
		"type": type, "label": t[1], "ref_kind": ref_kind, "fields": fields, "new_id_base": ref_kind if ref_kind != "" else type.trim_suffix("s"),
		"path": path,
		"records": func(): return data.db[type].file.records,
		"holder": func(): return data.db[type].file,
		"save": func() -> Error:
			var err := RPGJson.save_file(path, data.db[type].file)
			if err == OK:
				_reindex(type)
				if type == "types":
					_types_saved.call_deferred()
			return err,
		"validate": func() -> Array: return _problems_for(path, ref_kind),
	}
	if type == "actors":
		cfg["preview"] = func(rec: Dictionary) -> Control: return Preview.actor(data, rec)
	elif type == "enemies":
		cfg["preview"] = func(rec: Dictionary) -> Control: return Preview.enemy(data, rec)
	elif type == "animations":
		cfg["preview"] = func(rec: Dictionary) -> Control: return Preview.animation(data, rec)
	elif type == "tilesets":
		cfg["preview"] = func(rec: Dictionary) -> Control: return Preview.tileset(data, rec)
	elif type == "classes":
		cfg["new_record"] = _new_class_defaults
	elif type == "types":
		var tl := RPGRecordSchemas.type_lists(data)
		cfg["record_fields"] = func(rec: Dictionary) -> Array: return RPGRecordSchemas.types_fields(str(rec.get("id", "")), tl)
		cfg["extra"] = func(tab: RPGRecordTab, rec: Dictionary) -> Control: return _type_entry_tools(tab, rec)
	elif type == "terms":
		cfg["extra"] = func(_tab, rec: Dictionary) -> Control: return _currency_note(str(rec.get("id", "")))
	if type == "troops":
		cfg["form_options"] = {"battle_conditions": true}
		cfg["extra"] = func(_tab, rec: Dictionary) -> Control:
			var b := Button.new()
			b.text = "Battle test"
			b.tooltip_text = "Start this fight at once (save first)" if battle_test.is_valid() else "Battle test is available when the RPG plugin is active"
			b.disabled = not battle_test.is_valid()
			b.pressed.connect(func(): battle_test.call(str(rec.get("id", ""))))
			return b
	_add_tab(cfg)


## A new class starts with the first class's stat curves and experience curve (or, with no class
## yet, the lowest legal value of every stat), never all zeros.
func _new_class_defaults(rec: Dictionary) -> void:
	var first: Dictionary = {}
	for c in data.records("classes"):
		if c is Dictionary and c != rec and c.get("growth") is Dictionary and not c.growth.is_empty():
			first = c
			break
	if not first.is_empty():
		rec["growth"] = RPGJson.deep_copy(first.growth)
		if first.get("exp_curve") is Dictionary and not first.exp_curve.is_empty():
			rec["exp_curve"] = RPGJson.deep_copy(first.exp_curve)
		return
	var g := {}
	for s in (rules.stats() if rules != null else []):
		var lo := maxi(1, int(s.get("min", 1)))
		g[str(s.id)] = {"base": lo * 10 if str(s.id).begins_with("m") else lo * 5, "per_level": maxi(1, lo)}
	rec["growth"] = g


## Types tab, under the form: "Rename entry ID…" renames an entry and every record using it.
func _type_entry_tools(tab: RPGRecordTab, rec: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	var pick := OptionButton.new()
	pick.name = "EntryPick"
	for e in rec.get("entries", []):
		if e is Dictionary and e.has("id"):
			pick.add_item("%s  —  %s" % [e.id, e.get("name", "")])
			pick.set_item_metadata(pick.item_count - 1, str(e.id))
	var b := Button.new()
	b.text = "Rename entry ID…"
	b.tooltip_text = "Rename the chosen entry's ID and every record that uses it (skills, weapons, armour, classes, actors, traits)"
	b.disabled = pick.item_count == 0
	b.pressed.connect(func():
		if pick.selected >= 0:
			_rename_type_entry_dialog(str(rec.get("id", "")), str(pick.get_item_metadata(pick.selected)), tab))
	hb.add_child(pick)
	hb.add_child(b)
	return hb


func _rename_type_entry_dialog(list_id: String, old_id: String, from_tab: RPGRecordTab) -> ConfirmationDialog:
	var run := func(new_id: String) -> Dictionary:
		var r := RPGValidator.rename_type_entry(data, list_id, old_id, new_id)
		if r.ok:
			r = _write_transaction(r, "Rename %s entry %s to %s" % [list_id, old_id, new_id])
		return r
	return _id_dialog("Rename %s entry '%s'" % [list_id, old_id], old_id, run, from_tab, "types", list_id)


## Types changed: the type and element dropdowns of the other tabs are rebuilt.
func _types_saved() -> void:
	reload()
	if _status:
		_status.text = "Saved types.json. The type and element lists in the other tabs are updated."


## Terms > gold_unit: System > Currency unit wins while it is set (RPGProjectData.currency()).
func _currency_note(id: String) -> Control:
	if not ["gold_unit", "currency"].has(id):
		return null
	var l := Label.new()
	l.name = "CurrencyNote"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	var unit := str(_system_file.get("system", {}).get("currency", ""))
	if unit != "":
		l.text = "Not used: the game shows System > Currency unit ('%s'). Set the currency there, or clear it there to use this term." % unit
	else:
		l.text = "Used as the currency unit, because System > Currency unit is empty."
	return l


func _reindex(type: String) -> void:
	var by_id := {}
	for r in data.db[type].file.get("records", []):
		if r is Dictionary and r.has("id"):
			by_id[r.id] = r
	data.db[type].by_id = by_id
	data.db[type].records = data.db[type].file.get("records", [])


func _index_state() -> void:
	for k in ["switches", "variables"]:
		var reg: Dictionary = data.switches if k == "switches" else data.variables
		reg.clear()
		for d in data.state_defs.get(k, []):
			if d is Dictionary and d.has("id"):
				reg[d.id] = d


func _index_common_events() -> void:
	data.common_events.clear()
	for c in data.common_events_file.get("common_events", []):
		if c is Dictionary and c.has("id"):
			data.common_events[c.id] = c


func _add_common_events_tab(t: Array, stats: Array, resources: Array, traits: Array, custom: Dictionary, slots: Array) -> void:
	var holder: Dictionary = data.common_events_file
	if not (holder.get("common_events") is Array):
		holder["common_events"] = []
	var path := root_dir.path_join("common_events.json")
	var cfg := {
		"type": "common_events", "label": t[1], "ref_kind": "common_event", "new_id_base": "common_event",
		"path": path,
		"fields": RPGRecordSchemas.fields_for("common_events", stats, resources, traits, custom, slots),
		"records": func(): return holder.common_events,
		"holder": func(): return holder,
		"save": func() -> Error:
			var err := RPGJson.save_file(path, holder)
			if err == OK:
				_index_common_events()
			return err,
		"validate": func() -> Array: return _problems_for(path, "common_event"),
	}
	cfg["extra"] = func(tab: RPGRecordTab, rec: Dictionary) -> Control:
		var box := VBoxContainer.new()
		var l := Label.new()
		l.text = "Commands"
		box.add_child(l)
		if not (rec.get("commands") is Array):
			rec["commands"] = []
		var cle := RPGCommandListEditor.new()
		cle.custom_minimum_size = Vector2(400, 320)
		cle.setup(data, registry, "")
		cle.set_commands(rec.commands)
		cle.commands_changed.connect(tab.mark_dirty)
		box.add_child(cle)
		return box
	_add_tab(cfg)


func _add_state_tab() -> void:
	var tc := TabContainer.new()
	tc.name = "Switches and variables"
	_tabs.add_child(tc)
	var path := root_dir.path_join("state.json")
	var st: Dictionary = data.state_defs
	# Both tabs edit the same file (state.json): saving one writes both, so both become clean.
	var pair_tabs: Array = []
	for pair in [["switches", "Switches", "switch"], ["variables", "Variables", "variable"]]:
		var key: String = pair[0]
		if not (st.get(key) is Array):
			st[key] = []
		var kind: String = pair[2]
		var cfg := {
			"type": key, "label": pair[1], "ref_kind": kind, "new_id_base": kind,
			"path": path,
			"fields": RPGRecordSchemas.fields_for(key),
			"records": func(): return st[key],
			"holder": func(): return st,
			"save": func() -> Error:
				var err := RPGJson.save_file(path, st)
				if err == OK:
					_index_state()
					RPGFormBuilder.clear_dirty(data, "state.json")
				return err,
			"validate": func() -> Array: return _problems_for(path, kind),
			"extra": func(_tab, rec: Dictionary) -> Control: return _used_by_panel(kind, str(rec.get("id", ""))),
		}
		var tab := RPGRecordTab.new()
		tc.add_child(tab)
		tab.setup(cfg, data, registry, rules)
		_wire_tab(tab)
		tab.saved.connect(func():
			for other in pair_tabs:
				if other != tab and other.dirty:
					other.clear_dirty()
					other._status.text = "[color=#8f8]Saved together with %s (both live in state.json).[/color]" % tab.config.label)
		pair_tabs.append(tab)


func _used_by_panel(kind: String, id: String) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	box.add_child(l)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(300, 160)
	box.add_child(list)
	var uses := RPGValidator.used_by(data, registry, kind, id)
	l.text = "Used by (%d)" % uses.size()
	for u in uses:
		var where := str(u.file).get_file()
		list.add_item("%s  %s  %s  (%s)" % ["SET" if u.access == "set" else "read", where, u.record, u.path])
		list.set_item_metadata(list.item_count - 1, u)
	list.item_activated.connect(func(i):
		var u: Dictionary = list.get_item_metadata(i)
		if open_location.is_valid() and u.get("map", "") != "":
			open_location.call(u.map, u.record))
	return box


func _add_system_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "System"
	_tabs.add_child(box)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	sc.add_child(pad)
	var column := FormColumn.new()
	pad.add_child(column)
	var form := RPGFormBuilder.new()
	form.name = "SystemForm"
	form.setup(RPGRecordSchemas.fields_for("system"), data, registry)
	var shown: Dictionary = _system_file.system.duplicate()
	shown["start_facing"] = start_facing()
	form.set_value(shown)
	_system_shown = RPGJson.deep_copy(shown)
	column.add_child(form)
	_fit_spin_prefixes(form)
	form.pick_location_requested.connect(_pick_on_map)
	var status := Label.new()
	_system_status = status
	form.value_changed.connect(func(k, v):
		system_edited(str(k), v)
		status.text = "Unsaved changes")
	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Write system.json (Ctrl+S)"
	save.pressed.connect(func():
		var err := save_system())
	var hb := HBoxContainer.new()
	hb.add_child(save)
	hb.add_child(status)
	box.add_child(hb)


## SpinBoxes with a prefix ("Pitch 100") are only as wide as four digits by default, so their
## text scrolls and the label is cut ("itch 100"): make them as wide as their text.
static func _fit_spin_prefixes(node: Node) -> void:
	if node is SpinBox and (node as SpinBox).prefix != "":
		(node as SpinBox).get_line_edit().expand_to_text_length = true
	for c in node.get_children():
		_fit_spin_prefixes(c)


## The facing the party starts with (system.start.facing, "down" by default).
func start_facing() -> String:
	var start: Variant = _system_file.system.get("start")
	return str(start.get("facing", "down")) if start is Dictionary else "down"


## Records an edit of System field `key` (the form's new value). Object fields (music,
## vehicles) are recorded leaf by leaf; other fields as a whole. "start_facing" is stored as
## start.facing.
func system_edited(key: String, v: Variant) -> void:
	if key == "start_facing":
		_system_shown[key] = v
		if _system_file.system.get("start") is Dictionary:
			_system_file.system.start["facing"] = str(v)
		_system_paths["start/facing"] = [["start", "facing"], str(v)]
		return
	var before: Variant = _system_shown.get(key)
	_system_shown[key] = RPGJson.deep_copy(v)
	_system_file.system[key] = v
	_system_edits[key] = v
	_system_paths["%s/" % key] = null   # marks the key as recorded leaf by leaf
	var field := {}
	for f in RPGRecordSchemas.fields_for("system"):
		if str(f.get("key", "")) == key:
			field = f
	var leaves := []
	_leaf_edits(field, before, v, [key], leaves)
	for l in leaves:
		_system_paths["/".join(PackedStringArray(l[0]))] = l


## Which leaves differ between two values of a field. Keys the new value does not have are not
## edits (a form never deletes keys).
static func _leaf_edits(f: Dictionary, before: Variant, after: Variant, path: Array, out: Array) -> void:
	var subs: Array = f.get("fields", [])
	if str(f.get("kind", "")) != "object" or subs.is_empty() or not (after is Dictionary):
		if RPGJson.stringify(before) != RPGJson.stringify(after):
			out.append([path.duplicate(), RPGJson.deep_copy(after)])
		return
	var b: Dictionary = before if before is Dictionary else {}
	var known := {}
	for sf in subs:
		known[str(sf.get("key", ""))] = sf
	for k in after:
		var sf: Dictionary = known.get(str(k), {})
		_leaf_edits(sf, b.get(k), after[k], path + [k], out)


static func _set_path(root: Dictionary, path: Array, v: Variant) -> void:
	var d := root
	for i in path.size() - 1:
		if not (d.get(path[i]) is Dictionary):
			d[path[i]] = {}
		d = d[path[i]]
	d[path[path.size() - 1]] = RPGJson.deep_copy(v)


## Writes the System edits made here into `sys` (a system Dictionary): recorded leaves first
## (shallow before deep, so start.facing lands inside a new start), then whole keys set
## without the form (tools, tests).
func _apply_system_edits(sys: Dictionary) -> void:
	var by_leaf := {}
	var leaves := []
	for p in _system_paths:
		by_leaf[str(p).get_slice("/", 0)] = true
		if _system_paths[p] is Array:
			leaves.append(_system_paths[p])
	leaves.sort_custom(func(a: Array, b: Array) -> bool: return a[0].size() < b[0].size())
	for l in leaves:
		_set_path(sys, l[0], l[1])
	for k in _system_edits:
		if not by_leaf.has(k):
			sys[k] = RPGJson.deep_copy(_system_edits[k])


## "Pick on map…" in the System form: the RPG tab's location picker answers, then this tab is
## shown again.
func _pick_on_map(callback: Callable, current: Variant) -> void:
	if plugin == null:
		_status.text = "Pick on map works inside the Godot editor."
		return
	var back := func(map_id: String, cell: Vector2i) -> void:
		if callback.is_valid():
			callback.call(map_id, cell)
		EditorInterface.set_main_screen_editor("Database")
	EditorInterface.set_main_screen_editor("RPG")
	var main: Node = EditorInterface.get_editor_main_screen().get_node_or_null("RPG")
	if main != null and main.has_method("pick_location"):
		main.pick_location(back, current)


## Saves the System form: re-reads system.json and writes only what was edited here (nested
## values leaf by leaf), so a change made elsewhere (e.g. "Set starting position" on the map,
## for the party or a vehicle) is kept.
func save_system() -> Error:
	var path := root_dir.path_join("database/system.json")
	var disk: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "system": {}})
	if not (disk.get("system") is Dictionary):
		disk["system"] = {}
	_apply_system_edits(disk.system)
	var err := RPGJson.save_file(path, disk)
	if err == OK:
		_system_file = disk
		data.system = disk.system
		_system_edits = {}
		_system_paths = {}
		_restamp([path])
	if _system_status != null and is_instance_valid(_system_status):
		_system_status.text = _system_saved_text() if err == OK else "Could not save (error %d)." % err
	return err


## After a System save: "Saved." plus the System share of the project checks.
func _system_saved_text() -> String:
	var probs := _problems_for(root_dir.path_join("database/system.json"))
	if probs.is_empty():
		return "Saved. No problems found."
	var lines := PackedStringArray()
	for p in probs.slice(0, 4):
		lines.append("%s: %s" % [p.get("severity", ""), p.get("message", "")])
	return "Saved with %d problem(s): %s" % [probs.size(), " ".join(lines)]


## The problems a tab's Save reports: those in its own file, plus references elsewhere to a
## record of its kind that does not exist (e.g. an event still selling a deleted item).
func _problems_for(path: String, ref_kind := "") -> Array:
	var out := []
	for p in RPGValidator.full(data, registry):
		if p.file == path or (ref_kind != "" and str(p.get("ref_kind", "")) == ref_kind):
			out.append(p)
	return out


func dirty_tabs() -> Array:
	return _record_tabs.filter(func(t): return is_instance_valid(t) and t.dirty)


## True while the System form has edits that are not saved yet.
func system_dirty() -> bool:
	return not _system_edits.is_empty() or not _system_paths.is_empty()


## The labels of the tabs with unsaved edits that write `path` ("System" for system.json).
func unsaved_owners(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in dirty_tabs():
		if str(t.config.get("path", "")) == path and not out.has(str(t.config.label)):
			out.append(str(t.config.label))
	if path == root_dir.path_join("database/system.json") and system_dirty():
		out.append("System")
	return out


func save_all() -> void:
	var n := 0
	var failed := PackedStringArray()
	for t in dirty_tabs():
		# Switches and variables share a file: saving one already saved the other.
		if t.dirty:
			if t.save_now():
				n += 1
			else:
				failed.append(str(t.config.label))
	if system_dirty():
		if save_system() == OK:
			n += 1
		else:
			failed.append("System")
	_status.text = "Saved %d file(s)." % n + ("" if failed.is_empty() else " Not saved: %s (the tab says why)." % ", ".join(failed))


## Ctrl+S: saves the sub-tab on show. Returns true when it wrote its file.
func save_current_tab() -> bool:
	if _tabs == null or not is_instance_valid(_tabs):
		return false
	var cur: Control = _tabs.get_current_tab_control()
	if cur is TabContainer:
		cur = (cur as TabContainer).get_current_tab_control()
	if cur is RPGRecordTab:
		return (cur as RPGRecordTab).save_now()
	if cur != null and cur.name == "System":
		return save_system() == OK
	return false


func _confirm_reload() -> void:
	if dirty_tabs().is_empty() and not system_dirty():
		reload(false)
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = reload_prompt()
	dlg.ok_button_text = "Discard and reload"
	dlg.confirmed.connect(func(): dlg.queue_free(); reload(false))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## The Reload question, naming the tabs whose unsaved changes would be lost.
func reload_prompt() -> String:
	var names := PackedStringArray()
	for t in dirty_tabs():
		if not names.has(str(t.config.label)):
			names.append(str(t.config.label))
	if system_dirty():
		names.append("System")
	return "Unsaved changes in %s. Reload and discard them?" % ", ".join(names)


func _check_project() -> void:
	var probs := RPGValidator.full(data, registry)
	var errs := RPGValidator.count(probs, "error")
	var warns := RPGValidator.count(probs, "warning")
	var dlg := AcceptDialog.new()
	dlg.title = "Project check: %d error(s), %d warning(s)" % [errs, warns]
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(900, 400)
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for p in probs:
		var text := "%s  %s  %s  %s — %s" % [p.severity.to_upper(), str(p.file).get_file(), p.record, p.message, p.fix_hint]
		list.add_item(text)
		list.set_item_metadata(list.item_count - 1, p)
		# Long lines are cut at the edge: the tooltip has all of it.
		list.set_item_tooltip(list.item_count - 1, "%s\n%s\n%s\n\nDouble-click to open it." % [str(p.file), p.message, p.fix_hint])
	if probs.is_empty():
		list.add_item("No problems found.")
	list.item_activated.connect(func(i: int):
		var p: Variant = list.get_item_metadata(i)
		if p is Dictionary:
			dlg.hide()
			dlg.queue_free()
			go_to_problem(p))
	dlg.add_child(list)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## Switching rule systems: pick one, read the migration preview, confirm explicitly.
func _change_rules() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Change rule system"
	dlg.ok_button_text = "Switch rule system"
	var vb := VBoxContainer.new()
	dlg.add_child(vb)
	var pick := OptionButton.new()
	var systems := RPGRuleMigration.available(root_dir)
	var current := str(data.project.get("rules", "classic"))
	for i in systems.size():
		pick.add_item("%s (%s)%s" % [systems[i].name, systems[i].id, "  - current" if systems[i].id == current else ""])
		pick.set_item_metadata(i, systems[i].id)
	vb.add_child(pick)
	var text := TextEdit.new()
	text.editable = false
	text.custom_minimum_size = Vector2(700, 340)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(text)
	var confirm := CheckBox.new()
	confirm.text = "I have read the preview and want to switch"
	vb.add_child(confirm)
	var refresh := func(_i = 0):
		var to_id := str(pick.get_item_metadata(pick.selected))
		confirm.button_pressed = false
		if to_id == current:
			text.text = "'%s' is the current rule system." % current
			dlg.get_ok_button().disabled = true
			return
		var p := RPGRuleMigration.preview(data, to_id)
		text.text = RPGRuleMigration.describe(p)
		dlg.get_ok_button().disabled = true
	pick.item_selected.connect(refresh)
	confirm.toggled.connect(func(on: bool):
		dlg.get_ok_button().disabled = not on or str(pick.get_item_metadata(pick.selected)) == current)
	dlg.confirmed.connect(func():
		var err := RPGRuleMigration.apply(data, str(pick.get_item_metadata(pick.selected)))
		_status.text = "Rule system changed. Reloading." if err == OK else "Could not write project.json (error %d)." % err
		dlg.queue_free()
		if err == OK:
			reload())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	for i in systems.size():
		if systems[i].id != current:
			pick.select(i)
			break
	refresh.call()
	dlg.popup_centered()


## Jump-to-fix: map problems open the event in the RPG tab; database problems select the record.
func go_to_problem(p: Dictionary) -> void:
	var loc := RPGToolsWindow.problem_location(p)
	if str(loc.map) != "":
		if plugin == null:
			return
		EditorInterface.set_main_screen_editor("RPG")
		var main: Node = EditorInterface.get_editor_main_screen().get_node_or_null("RPG")
		if main != null and main.has_method("open_map"):
			main.open_map(loc.map)
			main._select_mode("event")
			if str(loc.event) != "":
				main.view.select_event(loc.event)
				main.edit_event(loc.event)
		return
	select_record_for_file(str(p.get("file", "")), str(loc.event))


## Selects the tab for database/<type>.json and the record with `id`. Returns true if found.
func select_record_for_file(file: String, id: String) -> bool:
	if _tabs == null or not is_instance_valid(_tabs):
		return false
	var type := file.get_file().get_basename()
	for t in _record_tabs:
		if str(t.config.get("type", "")) == type:
			_tabs.current_tab = t.get_index()
			var recs: Array = t.records()
			for i in recs.size():
				if str(recs[i].get("id", "")) == id:
					t.select(i)
					t.refresh_list()
					return true
			return true
	return false


func _write_schema() -> void:
	var err := RPGSchema.write(registry, root_dir.path_join(".schema"))
	_status.text = "Wrote %s/.schema/events.schema.json" % root_dir if err == OK else "Could not write the schema (error %d)." % err


## Why renaming `old_id` cannot run now: the unsaved tabs whose files the rename would rewrite,
## as a message ("" when it can run). Unsaved tabs the rename does not touch do not block it.
func rename_blocker(kind: String, old_id: String) -> String:
	var probe := RPGValidator.rename_id(data, registry, kind, old_id, "rename_probe_%d" % Time.get_ticks_usec())
	if not probe.ok:
		return ""   # the dialog shows the real error for the name the maker types
	return _blocker_text(probe.data_by_file.keys())


func _blocker_text(paths: Array) -> String:
	var owners := PackedStringArray()
	var files := PackedStringArray()
	for path in paths:
		var o := unsaved_owners(str(path))
		if o.is_empty():
			continue
		files.append(str(path).get_file())
		for l in o:
			if not owners.has(l):
				owners.append(l)
	if owners.is_empty():
		return ""
	return "Save or reload %s first: renaming rewrites %s, which has unsaved changes there." % [" and ".join(owners), ", ".join(files)]


## Renames an ID everywhere (one transaction): every changed file is written; if any write
## fails, the files already written are restored. Returns the dialog (null when blocked; the
## reason is shown under the tab's buttons).
func _rename_id(kind: String, old_id: String, from_tab: RPGRecordTab = null) -> ConfirmationDialog:
	var blocker := rename_blocker(kind, old_id)
	if blocker != "":
		if from_tab != null and is_instance_valid(from_tab):
			from_tab.show_note(blocker)
		else:
			_status.text = blocker
		return null
	if from_tab != null and is_instance_valid(from_tab):
		from_tab.show_note("")
	var type := str(from_tab.config.get("type", "")) if from_tab != null and is_instance_valid(from_tab) else ""
	var run := func(new_id: String) -> Dictionary:
		return rename_id_transaction(kind, old_id, new_id)
	return _id_dialog("Rename %s '%s'" % [kind, old_id], old_id, run, from_tab, type, "")


## The ID dialog of renames: a field, a message line (errors keep the focus in the field), OK.
## `run` (new ID -> result of a rename transaction) does the work. On success the tabs reload,
## the renamed record (`type`) or Types record (`keep_id`) is selected and the result is shown.
func _id_dialog(title: String, old_id: String, run: Callable, from_tab: RPGRecordTab, type: String, keep_id: String) -> ConfirmationDialog:
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	var vb := VBoxContainer.new()
	var le := LineEdit.new()
	le.name = "NewId"
	le.text = old_id
	le.placeholder_text = "new_id"
	vb.add_child(le)
	var msg := Label.new()
	msg.name = "Message"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A width for the wrapped text, or the label asks for one word per line (a very tall dialog).
	msg.custom_minimum_size = Vector2(360, 0)
	msg.text = "Lowercase letters, digits and _. Enter renames. Edit > Undo (Ctrl+Z) takes the rename back."
	vb.add_child(msg)
	dlg.add_child(vb)
	dlg.dialog_hide_on_ok = false
	# Enter in the ID field confirms, like OK.
	dlg.register_text_enter(le)
	dlg.confirmed.connect(func():
		var new_id := le.text.strip_edges()
		var r: Dictionary = run.call(new_id)
		if not r.ok:
			msg.text = r.error
			dlg.reset_size()
			# Keep typing in the field after an error.
			le.grab_focus.call_deferred()
			le.select_all.call_deferred()
			return
		dlg.queue_free()
		var warn := ""
		if not r.get("warnings", []).is_empty():
			warn = " %d place(s) in scripts or formulas mention it and were not changed." % r.warnings.size()
		var done := "Renamed '%s' to '%s' (%d reference(s) updated).%s" % [old_id, new_id, int(r.get("references", 0)), warn]
		reload()
		_status.text = done
		for t in _record_tabs:
			if str(t.config.get("type", "")) == type:
				_select_id(t, keep_id if keep_id != "" else new_id)
				t.show_note(done))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.min_size = Vector2i(400, 0)
	dlg.reset_size()
	dlg.popup_centered()
	# Typed keys go to the ID field, never to the Godot editor behind the dialog.
	le.grab_focus()
	le.select_all()
	return dlg


func rename_id_transaction(kind: String, old_id: String, new_id: String) -> Dictionary:
	var r := RPGValidator.rename_id(data, registry, kind, old_id, new_id)
	if not r.ok:
		return r
	return _write_transaction(r, "Rename %s %s to %s" % [kind, old_id, new_id])


## Writes a rename's files as one transaction: every file of r.data_by_file is written and every
## file of r.removes deleted; if a write fails, everything is put back. A success joins the undo
## history (undo writes the old files back, redo the new ones).
func _write_transaction(r: Dictionary, action: String) -> Dictionary:
	var blocker := _blocker_text(r.data_by_file.keys())
	if blocker != "":
		r.ok = false
		r.error = blocker
		return r
	var before := {}
	var after := {}
	for path in r.data_by_file:
		before[path] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		after[path] = RPGJson.stringify(r.data_by_file[path])
	for path in r.get("removes", []):
		before[path] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		after[path] = ""
	var err_path := write_texts(after, false)
	if err_path != "":
		write_texts(before, false)
		r.ok = false
		r.error = "Could not write %s. Every file was restored." % err_path
		return r
	if undo != null:
		undo.create_action(action)
		undo.add_do_method(self, "write_texts", [after])
		undo.add_undo_method(self, "write_texts", [before])
		undo.commit_action(false)
	return r


## Writes file texts ({path: text}; "" deletes the file) and, with `then_reload`, reloads the
## tabs (unsaved edits are kept). Returns the first path that could not be written, or "".
func write_texts(texts: Dictionary, then_reload := true) -> String:
	var failed := ""
	for path in texts:
		var text := str(texts[path])
		if text == "":
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		DirAccess.make_dir_recursive_absolute(str(path).get_base_dir())
		if RPGJson.write_atomic(path, text) != OK and failed == "":
			failed = str(path)
	_restamp(texts.keys())
	if then_reload:
		reload()
		if _status:
			_status.text = "Files written back: %s." % ", ".join(PackedStringArray(texts.keys().map(func(p): return str(p).get_file())))
	return failed


## Ctrl+S saves the sub-tab on show. Handled in _input, before the Godot editor's own Ctrl+S
## (Save Scene) takes the key, and only while focus is inside this screen (or nowhere, with the
## mouse over it).
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode != KEY_S or not k.is_command_or_control_pressed() or k.shift_pressed or k.alt_pressed:
		return
	if _tabs == null or not is_visible_in_tree() or not _focus_inside():
		return
	save_current_tab()
	get_viewport().set_input_as_handled()


func _focus_inside() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		return is_ancestor_of(f)
	return get_global_rect().has_point(get_global_mouse_position())
