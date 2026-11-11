extends "res://tests/rpg_test_case.gd"
## The kit plugins of the second wave (addons/rpg/extensions): quests (W4), lighting (W12) and
## crafting (W11), plus the hooks they brought: extension record types (manifest
## "database_types") and custom fields on maps and event pages. Each plugin is off until a
## project enables it; features, commands, conditions, menu entries and what is saved with the
## game are checked on the sample project, with test records added in memory only.

const Env := preload("res://tests/rpg_test_env.gd")
const OPTIONS_FILE := "user://rpg_options.json"
const PLUGINS := ["quests", "lighting", "crafting"]
const PLUGIN_COMMANDS := ["set_quest_status", "set_objective_state", "track_quest", "open_quest_journal",
	"set_darkness", "set_player_light", "set_event_light", "set_time", "add_time", "pause_time", "open_crafting"]
const TEST_SLOT := 91
var TMP := "user://rpg_wave2_test_%d" % OS.get_process_id()

const QUESTS := [
	{"id": "lost_ring", "name": "The Lost Ring", "category": "Main", "icon": 104, "giver": "Elder", "location": "Oakvale",
		"description": "The elder lost her ring near the old well.",
		"objectives": [{"id": "ask", "text": "Ask around town"}, {"id": "well", "text": "Search the old well"}, {"id": "secret", "text": "Find who took it", "hidden": true}],
		"rewards": "200 G"},
	{"id": "herbs", "name": "Herbs for Mira", "category": "Side", "objectives": [{"id": "pick", "text": "Pick 3 herbs"}]},
	{"id": "wolves", "name": "Wolf Trouble", "category": "Main", "objectives": [{"id": "hunt", "text": "Drive off the wolves"}]},
]

var env
var _backups := {}


func before_each() -> void:
	for path in [OPTIONS_FILE, _slot(TEST_SLOT)]:
		_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null
	for path in _backups:
		var data: Variant = _backups[path]
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(data)
	_backups.clear()
	_rm(TMP)
	# Later suites load other projects: forget the record types declared here.
	RPGCommandRegistry.declared_database_types = {}


static func _slot(n: int) -> String:
	return "user://saves/slot_%02d.json" % n


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)


func plugin_env(ids: Array, settings: Dictionary = {}) -> void:
	env = Env.create(tree, "res://rpg")
	var pj: Dictionary = env.rpg.data.project
	pj["extensions"] = ["project"] + ids
	pj["disabled_extensions"] = []
	env.rpg.reload_extensions(settings)


func on_map() -> void:
	env.game.new_game()
	await env.settle()


func add_record(type: String, rec: Dictionary) -> void:
	var db: Dictionary = env.rpg.data.db[type]
	db.file.records.append(rec)
	db.records = db.file.records
	db.by_id[rec.id] = rec


func add_quests() -> void:
	for q in QUESTS:
		add_record("quests", q.duplicate(true))


func _menu() -> Node:
	env.game.open_menu()
	await frames(2)
	return env.rpg.ui.scene_stack[-1]


func save_and_load(mutate: Callable) -> void:
	var r: RPGResult = env.rpg.saves.save(TEST_SLOT)
	assert_true(r.is_ok(), str(r))
	mutate.call()
	r = await env.rpg.saves.load_slot(TEST_SLOT)
	assert_true(r.is_ok(), str(r))
	await env.settle()


# --- off by default ------------------------------------------------------------------------------

func test_wave2_plugins_are_off_by_default() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	for id in PLUGINS:
		assert_true(rpg.extension(id) == null, "%s not running" % id)
		assert_false(rpg.extension_enabled(id))
	for t in PLUGIN_COMMANDS:
		assert_false(rpg.registry.has_command(t), "%s not offered" % t)
	assert_false(rpg.data.db.has("quests"), "no quest records loaded")
	assert_true(rpg.registry.database_types().is_empty())
	assert_false(RPGValidator.db_kinds().has("quest"))
	assert_false(rpg.state.condition_kinds.has("quest"))
	assert_false(rpg.state.condition_kinds.has("time_of_day"))
	var custom: Dictionary = rpg.registry.merged_custom_fields(rpg.data.project.get("custom_fields", {}))
	assert_false(custom.has("maps") or custom.has("event_pages"), "no map or page fields")
	assert_false((custom.get("items", []) as Array).any(func(f): return str(f.get("key", "")) == "recipe"))
	await on_map()
	var menu: Node = await _menu()
	assert_eq(menu.command_ids(), menu.COMMANDS)
	menu.close()
	await frames(2)
	assert_true(env.game.get("_overlays").is_empty(), "no overlay layers made")
	assert_true(rpg.extensions.option_rows().is_empty())


# --- hooks: record types, map and page fields ----------------------------------------------------

func test_database_types_hook_registry_data_validator_and_rename() -> void:
	plugin_env(["quests"])
	var rpg: Node = env.rpg
	var types: Array = rpg.registry.database_types()
	assert_eq(types.size(), 1)
	assert_eq(types[0].type, "quests")
	assert_eq(types[0].ref, "quest")
	assert_eq(types[0].extension, "quests")
	assert_true(rpg.data.db.has("quests"), "loaded at start (empty: no file yet)")
	assert_has(rpg.data.all_db_types(), "quests")
	assert_eq(RPGCommandRegistry.database_type_of("quest"), "quests")
	assert_eq(RPGValidator.db_kinds().get("quest"), "quests")
	add_quests()
	# A command naming a missing quest is a reference error; an existing one is not.
	rpg.data.common_events_file.common_events.append({"id": "qtest", "name": "Q", "trigger": "none", "commands": [
		{"type": "set_quest_status", "quest": "lost_ring", "status": "active"},
		{"type": "set_quest_status", "quest": "nope", "status": "active"}]})
	rpg.data.common_events["qtest"] = rpg.data.common_events_file.common_events[-1]
	var files := RPGValidator.collect_files(rpg.data)
	var probs := RPGValidator.references(rpg.data, rpg.registry, files)
	var msgs := probs.map(func(p): return str(p.message))
	assert_true(msgs.any(func(m): return m.contains("Quest 'nope' does not exist")), str(msgs))
	assert_false(msgs.any(func(m): return m.contains("'lost_ring'")), str(msgs))
	# Renaming a quest renames the record and every reference to it.
	var r: Dictionary = RPGValidator.rename_id(rpg.data, rpg.registry, "quest", "lost_ring", "ring_quest")
	assert_true(r.ok, str(r.get("error", "")))
	var ce_file: Dictionary = r.data_by_file.get(rpg.data.root.path_join("common_events.json"), {})
	var ce: Array = ce_file.get("common_events", [])
	var cmd: Dictionary = ce.filter(func(c): return c.id == "qtest")[0].commands[0]
	assert_eq(cmd.quest, "ring_quest", "reference renamed")
	var qfile: Dictionary = r.data_by_file.get(rpg.data.root.path_join("database/quests.json"), {})
	assert_true(qfile.get("records", []).any(func(q): return q.id == "ring_quest"), "record renamed")
	# The ref picker lists the quests.
	var rp := RPGRefPicker.new("quest", rpg.data)
	var ids: Array = rp.entries().map(func(e): return str(e.id))
	rp.free()
	assert_has(ids, "herbs")
	assert_has(ids, "wolves")
	# Unusable types are refused.
	var reg := RPGCommandRegistry.new()
	reg.extensions = {"bad": {"_enabled": true, "_dir": "x", "database_types": [{"type": "items"}, {"type": "Bad Name"}, {"type": "notes_x"}]}}
	var ok_types: Array = reg.database_types(true)
	assert_eq(ok_types.map(func(d): return d.type), ["notes_x"])
	assert_eq(reg.problems.size(), 2)


func test_database_screen_gets_a_tab_for_extension_types() -> void:
	_rm(TMP)
	var root := TMP + "/rpg"
	DirAccess.make_dir_recursive_absolute(root + "/database")
	DirAccess.make_dir_recursive_absolute(root + "/maps")
	RPGJson.save_file(root + "/project.json", {"schema_version": 1, "project_id": "w2", "name": "W2", "extensions": ["quests"], "disabled_extensions": [], "rules": "classic"})
	RPGJson.save_file(root + "/map_index.json", {"schema_version": 1, "maps": []})
	RPGJson.save_file(root + "/database/quests.json", {"schema_version": 1, "records": [QUESTS[0].duplicate(true)]})
	var host := Control.new()
	host.size = Vector2(1400, 860)
	tree.root.add_child(host)
	var screen := RPGDatabaseScreen.new()
	host.add_child(screen)
	screen.setup(null, root)
	await frames(2)
	var tab: RPGRecordTab = null
	for t in screen._record_tabs:
		if str(t.config.get("type", "")) == "quests":
			tab = t
	assert_true(tab != null, "a Quests tab")
	if tab != null:
		assert_eq(str(tab.config.label), "Quests")
		assert_eq(str(tab.config.ref_kind), "quest")
		assert_eq(tab.records().size(), 1)
		var keys: Array = tab.config.fields.map(func(f): return str(f.get("key", "")))
		for k in ["name", "category", "icon", "objectives", "rewards", "notes"]:
			assert_has(keys, k)
		var types: Array = []
		for i in screen._tabs.get_tab_count():
			types.append(screen._tabs.get_tab_title(i))
		assert_true(types.find("Quests") < types.find("Common events"), "before Common events: %s" % str(types))
		# New and Save work as on the built-in tabs.
		tab.new_record()
		assert_eq(tab.records().size(), 2)
		assert_eq(str(tab.current_record().id).begins_with("quest"), true, str(tab.current_record()))
		assert_true(tab.current_record().has("objectives"), "defaults from the declared fields")
		assert_true(tab.save_now())
		var saved: Dictionary = RPGJson.load_or(root + "/database/quests.json", {})
		assert_eq(saved.get("records", []).size(), 2, "written to rpg/database/quests.json")
	host.queue_free()
	await frames(1)


func test_map_and_event_page_custom_fields_reach_the_editors() -> void:
	plugin_env(["lighting"])
	var rpg: Node = env.rpg
	var custom: Dictionary = rpg.registry.merged_custom_fields({})
	assert_true(custom.get("maps", []).any(func(f): return f.key == "darkness"))
	assert_true(custom.get("event_pages", []).any(func(f): return f.key == "light"))
	var page_fields: Array = RPGEventEditor.page_fields(rpg.registry, rpg.data)
	var pf: Array = page_fields.filter(func(f): return f.key == "custom")
	assert_eq(pf.size(), 1, "Plugin fields on event pages")
	assert_true(pf[0].fields.any(func(f): return f.key == "light"))
	assert_eq(RPGEventEditor.page_fields(null, rpg.data).filter(func(f): return f.key == "custom").size(), 0, "none without plugins")
	# The map properties dialog shows them and keeps them in the map's "custom".
	rpg.data.project["extensions"] = ["project", "lighting"]
	var mf: Array = RPGMapPropertiesDialog.custom_fields(rpg.data)
	assert_true(mf.any(func(f): return f.key == "darkness"))
	assert_true(mf.any(func(f): return f.key == "indoor"))
	var dlg := RPGMapPropertiesDialog.new()
	dlg.data = rpg.data
	dlg.map_id = "field"
	dlg.props = rpg.data.map_props("field").duplicate(true)
	dlg.props["custom"] = {"indoor": true}
	tree.root.add_child(dlg)
	await frames(1)
	assert_true(dlg._custom_form != null)
	assert_eq(dlg._custom_form.get_value().get("indoor"), true)
	var got := []
	dlg.saved.connect(func(_id, props, _n): got.append(props))
	dlg._on_ok()
	assert_eq(got.size(), 1)
	assert_eq(got[0].get("custom", {}).get("indoor"), true, "saved in the map's custom")
	await frames(1)


func test_tools_extensions_list_and_settings_layout() -> void:
	var data := RPGProjectData.open("res://rpg")
	var reg := RPGCommandRegistry.new()
	reg.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), "res://extensions")
	var w := RPGToolsWindow.new()
	w.setup(data, reg)
	var t: Tree = w._ext_tree
	assert_true(t.get_column_expand_ratio(0) > t.get_column_expand_ratio(3), "the name column takes the room")
	assert_true(t.is_column_clipping_content(0))
	var rows := {}
	var it: TreeItem = t.get_root().get_first_child()
	while it != null:
		rows[str(it.get_metadata(0))] = it
		it = it.get_next()
	for id in PLUGINS:
		assert_true(rows.has(id), "%s listed" % id)
		assert_false(rows[id].is_checked(0), "%s off" % id)
	assert_eq(rows.quests.get_text_overrun_behavior(0), TextServer.OVERRUN_TRIM_ELLIPSIS, "long names end in ...")
	assert_true(str(rows.quests.get_tooltip_text(0)).contains("Quest journal (quests)"), "full name in the tooltip")
	# Settings form: on/off rows start at the left edge, not under an empty label column.
	w.show_extension_settings("quests")
	var form: RPGFormBuilder = w._ext_settings_form
	assert_true(form != null)
	var row: Control = form._editors["menu_entry"].row
	var line: HBoxContainer = row.get_child(0)
	assert_eq(line.get_child_count(), 1, "only the check box")
	assert_true(line.get_child(0) is CheckBox)
	w.free()
	# Elsewhere (the Database) on/off rows still line up with the editors.
	var f2 := RPGFormBuilder.new()
	f2.setup([{"key": "b", "kind": "bool", "label": "B"}])
	assert_eq(f2._editors["b"].row.get_child(0).get_child_count(), 2)
	f2.free()


# --- W4 quests -----------------------------------------------------------------------------------

func test_w4_status_objectives_tracking_and_toasts() -> void:
	plugin_env(["quests"])
	add_quests()
	await on_map()
	var q: Object = env.rpg.extension("quests")
	assert_eq(q.status("lost_ring"), "unknown")
	assert_eq(q.objective_state("lost_ring", "ask"), "hidden", "unknown quest: nothing shown")
	assert_true(q.set_status("lost_ring", "active"))
	assert_eq(q.status("lost_ring"), "active")
	assert_eq(q.objective_state("lost_ring", "ask"), "shown")
	assert_eq(q.objective_state("lost_ring", "secret"), "hidden", "hidden objective")
	assert_eq(q.tracked(), "lost_ring", "auto-tracked")
	assert_has(q.toast_log, "New quest: The Lost Ring")
	assert_eq(q.toasts().size(), 1, "a note on the hud")
	assert_true(q.set_objective_state("lost_ring", "ask", "completed"))
	assert_has(q.toast_log, "Objective complete: Ask around town")
	assert_true(q.set_objective_state("lost_ring", "secret", "shown"))
	assert_has(q.toast_log, "New objective: Find who took it")
	assert_false(q.set_objective_state("lost_ring", "nope", "completed"), "unknown objective")
	assert_false(q.set_status("no_such", "active"), "unknown quest")
	assert_false(q.set_status("lost_ring", "weird"), "unknown status")
	# Tracker: the open objectives of the tracked quest, in a corner of the hud layer.
	assert_eq(q.tracker_lines(), ["Search the old well", "Find who took it"])
	var t: Panel = q.tracker()
	assert_true(t != null and t.get_parent() == env.rpg.map_overlay_layer("hud"))
	assert_true(t.position.x > 160, "top right by default")
	# Lists, completion, failure.
	q.set_status("herbs", "active")
	assert_eq(q.tracked(), "lost_ring", "a second quest does not take the tracker")
	q.set_status("wolves", "completed")
	assert_eq(q.quests_with("active"), ["lost_ring", "herbs"])
	assert_eq(q.quests_with("completed"), ["wolves"])
	q.set_status("herbs", "failed")
	assert_has(q.toast_log, "Quest failed: Herbs for Mira")
	assert_eq(q.quests_with("failed"), ["herbs"])
	q.track("")
	assert_true(q.tracker() == null, "nothing tracked: no tracker")
	q.track("lost_ring")
	q.set_status("lost_ring", "unknown")
	assert_eq(q.tracked(), "", "a forgotten quest is not tracked")
	assert_eq(q.objective_state("lost_ring", "ask"), "hidden")


func test_w4_tracker_corner_option_and_settings() -> void:
	plugin_env(["quests"], {"quests": {"tracker_corner": "bottom_left", "toast": false}})
	add_quests()
	await on_map()
	var q: Object = env.rpg.extension("quests")
	q.set_status("lost_ring", "active")
	assert_eq(q.toasts().size(), 0, "notes off")
	assert_has(q.toast_log, "New quest: The Lost Ring")
	var t: Panel = q.tracker()
	assert_true(t != null)
	assert_true(t.position.x < 20 and t.position.y > 120, "bottom left: %s" % str(t.position))
	var rows: Array = env.rpg.extensions.option_rows()
	assert_true(rows.any(func(r): return r.id == "quests.tracker"), "an options row")
	env.rpg.extensions.set_option("quests.tracker", false)
	assert_true(q.tracker() == null, "turned off by the player")
	env.rpg.extensions.set_option("quests.tracker", true)
	assert_true(q.tracker() != null)
	# The tracker hides under menus.
	var menu: Node = await _menu()
	await frames(2)
	assert_false(q.tracker().visible)
	menu.close()
	await frames(3)
	assert_true(q.tracker().visible)


func test_w4_commands_condition_and_save() -> void:
	plugin_env(["quests"])
	add_quests()
	await on_map()
	var q: Object = env.rpg.extension("quests")
	var st: RPGGameState = env.rpg.state
	await env.rpg.run_commands([
		{"type": "set_quest_status", "quest": "lost_ring", "status": "active"},
		{"type": "set_objective_state", "quest": "lost_ring", "objective": "well", "state": "completed"},
		{"type": "set_quest_status", "quest": "herbs", "status": "active"},
		{"type": "track_quest", "quest": "herbs"},
	])
	assert_eq(q.status("lost_ring"), "active")
	assert_eq(q.objective_state("lost_ring", "well"), "completed")
	assert_eq(q.tracked(), "herbs")
	# Condition kind "quest" in pages and Conditional Branch.
	assert_true(st.check_condition({"kind": "quest", "quest": "lost_ring", "check": "status", "status": "active"}))
	assert_false(st.check_condition({"kind": "quest", "quest": "wolves", "status": "active"}))
	assert_true(st.check_condition({"kind": "quest", "quest": "wolves", "status": "unknown"}))
	assert_true(st.check_condition({"kind": "quest", "quest": "lost_ring", "check": "objective", "objective": "well", "state": "completed"}))
	assert_false(st.check_condition({"kind": "quest", "quest": "lost_ring", "check": "objective", "objective": "ask", "state": "completed"}))
	await env.rpg.run_commands([{"type": "if", "condition": {"kind": "quest", "quest": "herbs", "status": "active"},
		"then": [{"type": "set_switch", "id": "key_given", "value": true}], "else": []}])
	assert_true(env.rpg.get_switch("key_given"), "branch on a quest")
	assert_has(RPGCommandRegistry.declared_condition_kinds, "quest")
	var probs := RPGValidator.event_structure({"id": "e", "position": [1, 1], "pages": [{"conditions": [{"kind": "quest", "quest": "herbs", "status": "active"}], "commands": []}]}, env.rpg.registry)
	assert_true(probs.filter(func(x): return x.severity == "error").is_empty(), str(probs))
	# Errors: unknown quest or objective.
	var r: RPGResult = await env.rpg.run_commands([{"type": "set_objective_state", "quest": "lost_ring", "objective": "zzz", "state": "completed"}])
	assert_true(r.is_error())
	# Saved with the game.
	await save_and_load(func():
		q.set_status("lost_ring", "failed")
		q.track(""))
	assert_eq(q.status("lost_ring"), "active")
	assert_eq(q.status("herbs"), "active")
	assert_eq(q.objective_state("lost_ring", "well"), "completed")
	assert_eq(q.tracked(), "herbs")
	var sec: Dictionary = env.rpg.extensions.section("quests")
	assert_eq(sec.quests.lost_ring.status, "active")
	# A new game forgets everything.
	env.game.new_game()
	await env.settle()
	assert_eq(q.status("lost_ring"), "unknown")
	assert_eq(q.tracked(), "")


func test_w4_journal_from_the_menu_tabs_detail_and_mouse() -> void:
	plugin_env(["quests"])
	add_quests()
	await on_map()
	var q: Object = env.rpg.extension("quests")
	q.set_status("lost_ring", "active")
	q.set_objective_state("lost_ring", "ask", "completed")
	q.set_status("herbs", "active")
	q.set_status("wolves", "failed")
	var menu: Node = await _menu()
	assert_has(menu.command_ids(), "quests")
	assert_true(menu.command_ids().find("quests") < menu.command_ids().find("options"), "before Options")
	menu.choose("quests")
	await frames(3)
	var j: Node = env.rpg.ui.scene_stack[-1]
	assert_true(j.has_method("show_detail"), "the journal is open")
	assert_eq(j.tab, "active")
	assert_eq(j.list.items.map(func(it): return it.data), ["lost_ring", "herbs"])
	assert_eq(str(j.tab_labels.active.text), "Active (2)")
	# Detail: objectives with marks; hidden ones are left out.
	assert_true(j.detail.get_node_or_null("Mark_ask") != null)
	assert_eq(j.detail.get_node("Mark_ask").state, "completed")
	assert_eq(j.detail.get_node("Mark_well").state, "shown")
	assert_true(j.detail.get_node_or_null("Mark_secret") == null, "hidden objective not listed")
	assert_eq(str(j.detail.get_node("Title").text), "The Lost Ring")
	# Keys: down, OK tracks; right goes to Completed, then Failed.
	j.handle_action("down")
	assert_eq(j.current_quest(), "herbs")
	j.handle_action("ok")
	assert_eq(q.tracked(), "herbs")
	j.handle_action("right")
	assert_eq(j.tab, "completed")
	assert_true(j.detail.get_node_or_null("Empty") != null, "nothing completed")
	j.handle_action("right")
	assert_eq(j.tab, "failed")
	assert_eq(j.current_quest(), "wolves")
	# Mouse: a click on a tab shows it; hovering a row moves the cursor; clicking it is OK.
	var tab_rect: Rect2 = j.local_xform(j.tab_labels.active) * Rect2(Vector2.ZERO, j.tab_labels.active.size)
	_click(j, tab_rect.get_center())
	assert_eq(j.tab, "active")
	var row0: Rect2 = j.local_xform(j.list) * j.list.item_rect(0)
	var move := InputEventMouseMotion.new()
	move.position = row0.get_center()
	j.pointer_event(move)
	assert_eq(j.current_quest(), "lost_ring")
	_click(j, row0.get_center())
	assert_eq(q.tracked(), "lost_ring", "click on the chosen row is OK")
	# Cancel closes it and the menu is back.
	j.handle_action("cancel")
	await frames(3)
	assert_true(env.rpg.ui.scene_stack[-1] == menu)
	menu.close()
	await frames(2)


func test_w4_menu_entry_setting_and_label() -> void:
	plugin_env(["quests"], {"quests": {"menu_label": "Journal"}})
	await on_map()
	var menu: Node = await _menu()
	var it: Array = menu.menu_items.filter(func(x): return x.id == "quests")
	assert_eq(it.size(), 1)
	assert_eq(str(it[0].label), "Journal")
	menu.close()
	await frames(2)
	env.rpg.extensions.set_settings("quests", {"menu_entry": false})
	menu = await _menu()
	assert_false(menu.command_ids().has("quests"), "entry off")
	menu.close()
	await frames(2)


func _click(screen: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	screen.pointer_event(ev)


# --- W12 lighting --------------------------------------------------------------------------------

func _light_env(settings: Dictionary = {}) -> Object:
	plugin_env(["lighting"], settings)
	var data: RPGProjectData = env.rpg.data
	data.map_props("field")["custom"] = {"darkness": {"colour": [0, 0, 20, 255], "strength": 80}}
	data.map_props("house_inside")["custom"] = {"indoor": true}
	for ev in data.map_events("field"):
		if ev.id == "field_sign":
			ev.pages[0]["custom"] = {"light": {"radius": 2.0, "colour": [255, 200, 120, 255], "intensity": 100, "flicker": true}}
	return env.rpg.extension("lighting")


func _go(map_id: String, cell: Vector2i) -> void:
	var r: RPGResult = await env.game.transfer(map_id, cell, "down", "none")
	assert_true(r.is_ok(), str(r))
	await env.settle()
	await frames(2)


func test_w12_dark_map_player_and_event_lights() -> void:
	var l: Object = _light_env()
	await on_map()
	assert_true(l.last_ambient.is_equal_approx(Color.WHITE), "the town is not dark")
	assert_true(l.darkness_node() == null, "nothing drawn")
	await _go("field", Vector2i(4, 9))
	assert_false(l.last_ambient.is_equal_approx(Color.WHITE), "the field is dark")
	assert_true(l.last_ambient.r < 0.3 and l.last_ambient.b > l.last_ambient.r)
	var dn: Node2D = l.darkness_node()
	assert_true(dn != null)
	assert_eq((dn.get_parent() as CanvasLayer).layer, 1)
	assert_true((dn.get_parent() as CanvasLayer).follow_viewport_enabled, "follows the camera")
	var lights: Array = l.last_lights
	var player_l: Array = lights.filter(func(x): return x.get("player", false))
	var sign_l: Array = lights.filter(func(x): return x.get("event", "") == "field_sign")
	assert_eq(player_l.size(), 1, "the player's light")
	assert_eq(sign_l.size(), 1, "the sign's light from its page")
	var ts := 16.0
	assert_eq(player_l[0].radius, 3.5 * ts, "radius in tiles x tile size")
	assert_eq(sign_l[0].radius, 2.0 * ts, "flicker is off by default")
	var sign_ev: Node2D = env.game.map.get_event("field_sign")
	assert_eq(sign_l[0].pos, sign_ev.global_position - Vector2(0, ts / 2.0))
	# Flashlight: a cone in the facing direction.
	l.set_player_light(null, 0.0, true)
	l.update_lighting()
	var cone: Array = l.last_lights.filter(func(x): return x.has("cone"))
	assert_eq(cone.size(), 1)
	assert_eq(cone[0].dir, Vector2.DOWN)
	env.game.player.facing = "left"
	l.update_lighting()
	assert_eq(l.last_lights.filter(func(x): return x.has("cone"))[0].dir, Vector2.LEFT)
	# Commands: an event's light off, the player's light off, darkness off.
	await env.rpg.run_commands([{"type": "set_event_light", "event": "field_sign", "mode": "off"}, {"type": "set_player_light", "light": "off", "flashlight": "off"}])
	l.update_lighting()
	assert_true(l.last_lights.is_empty())
	await env.rpg.run_commands([{"type": "set_darkness", "mode": "off"}])
	assert_true(l.last_ambient.is_equal_approx(Color.WHITE))
	await env.rpg.run_commands([{"type": "set_darkness", "mode": "dark", "colour": [0, 0, 0, 255], "strength": 50}])
	assert_true(l.last_ambient.is_equal_approx(Color(0.5, 0.5, 0.5)), str(l.last_ambient))
	await env.rpg.run_commands([{"type": "set_darkness", "mode": "map"}, {"type": "set_event_light", "event": "field_sign", "mode": "page"}, {"type": "set_player_light", "light": "on", "radius": 5.0}])
	l.update_lighting()
	assert_eq(l.last_lights.filter(func(x): return x.get("player", false))[0].radius, 5.0 * ts)
	assert_eq(l.last_lights.filter(func(x): return x.get("event", "") == "field_sign").size(), 1)


func test_w12_flicker_option_turns_flicker_on() -> void:
	var l: Object = _light_env()
	await on_map()
	await _go("field", Vector2i(4, 9))
	assert_eq(env.rpg.option("lighting", "flicker"), false, "off by default")
	var radii := {}
	for i in 6:
		l._time += 0.37
		l.update_lighting()
		radii[l.last_lights.filter(func(x): return x.get("event", "") == "field_sign")[0].radius] = true
	assert_eq(radii.size(), 1, "steady while the option is off")
	env.rpg.extensions.set_option("lighting.flicker", true)
	radii.clear()
	for i in 6:
		l._time += 0.37
		l.update_lighting()
		radii[l.last_lights.filter(func(x): return x.get("event", "") == "field_sign")[0].radius] = true
	assert_true(radii.size() > 1, "flickers with the option on")
	assert_eq(l.last_lights.filter(func(x): return x.get("player", false))[0].radius, 3.5 * 16.0, "the player's light never flickers")


func test_w12_time_of_day_tint_indoor_clock_and_condition() -> void:
	var l: Object = _light_env({"lighting": {"day_night": true, "start_hour": 18, "minutes_per_hour": 0.05, "clock": true, "hour_variable": "talks"}})
	await on_map()
	assert_eq(l.hour(), 18)
	assert_eq(env.rpg.get_variable("talks"), 18, "hour copied into the variable")
	# Dusk outdoors: the table colour at 18:00.
	l.set_time(18, 0)
	l.update_lighting()
	assert_true(l.last_ambient.is_equal_approx(Color8(255, 165, 110)), str(l.last_ambient))
	assert_true(l.darkness_node() != null, "tinted")
	assert_true(l.clock_panel() != null)
	assert_eq(str(l.clock_panel().get_node("Time").text), "18:00")
	# Blends between table hours.
	var mid: Color = l.tint_at(19 * 60.0)
	assert_true(mid.r < 1.0 and mid.r > 110.0 / 255.0, str(mid))
	assert_true(l.tint_at(12 * 60.0).is_equal_approx(Color.WHITE))
	# Indoor maps are not tinted.
	await _go("house_inside", Vector2i(5, 8))
	assert_true(l.last_ambient.is_equal_approx(Color.WHITE), "indoor")
	# The clock runs: 0.05 real minutes (3 s) per game hour.
	var before: float = l.minutes()
	l._process(1.5)
	assert_true(absf(l.minutes() - before - 30.0) < 0.01, "half an hour in 1.5 s")
	# Commands.
	await env.rpg.run_commands([{"type": "set_time", "hour": 21, "minute": 30}])
	assert_eq([l.hour(), l.minute()], [21, 30])
	var st: RPGGameState = env.rpg.state
	assert_true(st.check_condition({"kind": "time_of_day", "from": 18, "to": 6}))
	assert_false(st.check_condition({"kind": "time_of_day", "from": 6, "to": 18}))
	await env.rpg.run_commands([{"type": "add_time", "hours": 5, "minutes": 0}])
	assert_eq([l.hour(), l.minute(), l.day()], [2, 30, 2], "past midnight: the next day")
	assert_true(st.check_condition({"kind": "time_of_day", "from": 18, "to": 6}), "across midnight")
	await env.rpg.run_commands([{"type": "pause_time", "action": "pause"}])
	before = l.minutes()
	l._process(3.0)
	assert_eq(l.minutes(), before, "paused")
	await env.rpg.run_commands([{"type": "pause_time", "action": "resume"}])
	l._process(3.0)
	assert_true(l.minutes() > before)
	# The clock stops while a menu is open.
	var menu: Node = await _menu()
	before = l.minutes()
	l._process(3.0)
	assert_eq(l.minutes(), before, "stopped in the menu")
	assert_false(l.clock_panel().visible, "clock hidden under the menu")
	menu.close()
	await frames(2)
	# Saved with the game (paused first: at 3 s per game hour the clock would move during the save frames).
	await env.rpg.run_commands([{"type": "set_time", "hour": 13, "minute": 15}, {"type": "set_darkness", "mode": "dark", "strength": 40}, {"type": "pause_time", "action": "pause"}])
	await save_and_load(func():
		l.set_time(4, 0)
		l.set_paused(false)
		l.set_darkness("house_inside", "map"))
	assert_eq([l.hour(), l.minute()], [13, 15])
	assert_true(l.paused(), "paused came back")
	assert_false(l.darkness_of("house_inside").is_empty(), "the command's darkness came back")
	var sec: Dictionary = env.rpg.extensions.section("lighting")
	assert_true(sec.has("minutes") and sec.has("darkness") and sec.has("player"))


# --- W11 crafting --------------------------------------------------------------------------------

func _craft_env(settings: Dictionary = {}) -> Object:
	plugin_env(["crafting"], settings)
	var data: RPGProjectData = env.rpg.data
	data.record("items", "hi_potion")["custom"] = {"recipe": {"ingredients": [{"kind": "items", "id": "potion", "count": 2}, {"kind": "items", "id": "antidote", "count": 1}], "yield": 1, "category": "kitchen", "switch": ""}}
	data.record("weapons", "iron_sword")["custom"] = {"recipe": {"ingredients": [{"kind": "weapons", "id": "bronze_sword", "count": 1}, {"kind": "items", "id": "potion", "count": 1}], "yield": 1, "category": "forge", "switch": ""}}
	data.record("armors", "wooden_shield")["custom"] = {"recipe": {"ingredients": [{"kind": "items", "id": "potion", "count": 1}], "yield": 2, "category": "forge", "switch": "key_given"}}
	return env.rpg.extension("crafting")


func test_w11_recipes_known_craft_and_switch() -> void:
	var c: Object = _craft_env()
	await on_map()
	var st: RPGGameState = env.rpg.state
	assert_eq(st.item_count("potion"), 2, "the sample starts with 2 potions")
	# The recipe field is declared on items, weapons and armour.
	var custom: Dictionary = env.rpg.registry.merged_custom_fields({})
	for t in ["items", "weapons", "armors"]:
		assert_true(custom.get(t, []).any(func(f): return f.key == "recipe"), t)
	# Listed: the switch-bound shield is not, until its switch is ON.
	var listed: Array = c.recipes().map(func(r): return r.id)
	assert_eq(listed, ["hi_potion", "iron_sword"])
	assert_eq(c.recipes(["forge"]).map(func(r): return r.id), ["iron_sword"], "one category")
	st.set_switch("key_given", true)
	assert_eq(c.recipes(["FORGE"]).map(func(r): return r.id), ["iron_sword", "wooden_shield"])
	# Known once every ingredient has been held.
	assert_true(c.seen("items", "potion"))
	assert_false(c.known("items", "hi_potion"), "never had an antidote")
	assert_eq(c.max_crafts("items", "hi_potion"), 0)
	st.change_items("antidote", "increase", 1)
	assert_true(c.known("items", "hi_potion"))
	assert_eq(c.max_crafts("items", "hi_potion"), 1)
	assert_true(c.craft("items", "hi_potion", 1))
	assert_eq([st.item_count("potion"), st.item_count("antidote"), st.item_count("hi_potion")], [0, 0, 1])
	assert_eq(c.crafted_count("items", "hi_potion"), 1)
	assert_false(c.craft("items", "hi_potion", 1), "not enough any more")
	assert_eq(st.item_count("hi_potion"), 1, "nothing changed")
	# Yield: 2 shields per craft.
	st.change_items("potion", "increase", 3)
	assert_eq(c.max_crafts("armors", "wooden_shield"), 3)
	assert_true(c.craft("armors", "wooden_shield", 2))
	assert_eq(st.item_count("wooden_shield", "armors"), 4)
	# Ingredients are references: checked, and renamed with the item.
	var rn: Dictionary = RPGValidator.rename_id(env.rpg.data, env.rpg.registry, "item", "antidote", "remedy")
	assert_true(rn.ok, str(rn.get("error", "")))
	var items_file: Dictionary = rn.data_by_file.get(env.rpg.data.root.path_join("database/items.json"), {})
	var hp: Array = items_file.get("records", []).filter(func(x): return x.id == "hi_potion")
	assert_eq(hp[0].custom.recipe.ingredients[1].id, "remedy", "recipe ingredient renamed")
	env.rpg.data.record("weapons", "iron_sword").custom.recipe.ingredients[1].id = "no_such_item"
	var probs := RPGValidator.references(env.rpg.data, env.rpg.registry, RPGValidator.collect_files(env.rpg.data))
	assert_true(probs.any(func(p): return str(p.message).contains("'no_such_item' does not exist")), "a missing ingredient is reported")
	env.rpg.data.record("weapons", "iron_sword").custom.recipe.ingredients[1].id = "potion"
	# Saved with the game.
	await save_and_load(func():
		c.section("crafting").clear())
	assert_eq(c.crafted_count("items", "hi_potion"), 1)
	assert_eq(c.crafted_count("armors", "wooden_shield"), 4)
	assert_true(c.seen("items", "antidote"))


func test_w11_screen_masks_greys_and_makes() -> void:
	var c: Object = _craft_env()
	await on_map()
	var st: RPGGameState = env.rpg.state
	var menu: Node = await _menu()
	assert_has(menu.command_ids(), "crafting")
	menu.choose("crafting")
	await frames(3)
	var s: Node = env.rpg.ui.scene_stack[-1]
	assert_true(s.has_method("make_current"), "the crafting screen is open")
	var texts: Array = s.list.items.map(func(it): return str(it.text))
	assert_eq(texts, ["??????", "Iron Sword"], "unknown recipe masked")
	assert_false(bool(s.list.items[0].enabled))
	assert_false(bool(s.list.items[1].enabled), "no bronze sword: greyed out")
	assert_eq(str(s.info.get_node("Count_potion").text), "%d/2" % st.item_count("potion"))
	assert_eq(str(s.info.get_node("Ingredient_antidote").text), "??????", "unseen ingredient masked")
	s.handle_action("ok")
	assert_eq(s.mode, "list", "cannot choose a greyed recipe")
	s.handle_action("cancel")
	await frames(3)
	menu.close()
	await frames(2)
	# With the ingredients: OK, quantity, OK makes it.
	st.change_items("antidote", "increase", 2)
	st.change_items("potion", "increase", 2)
	var node: Node = env.rpg.ui.open_scene(c.SCREEN)
	node.start({}, {"rpg": env.rpg})
	await frames(2)
	assert_eq(str(node.list.items[0].text), "Hi-Potion")
	assert_true(bool(node.list.items[0].enabled))
	node.handle_action("ok")
	assert_eq(node.mode, "quantity")
	assert_eq(node.qty_max, 2)
	node.handle_action("up")
	assert_eq(node.qty, 2)
	node.handle_action("ok")
	assert_eq(st.item_count("hi_potion"), 2)
	assert_eq(node.made, [{"kind": "items", "id": "hi_potion", "count": 2}])
	assert_true(str(node.help.text).contains("Made Hi-Potion x2"))
	# Mouse: hovering the second row moves the cursor.
	var row1: Rect2 = node.local_xform(node.list) * node.list.item_rect(1)
	var move := InputEventMouseMotion.new()
	move.position = row1.get_center()
	node.pointer_event(move)
	assert_eq(node.list.index, 1)
	env.rpg.ui.close_scene(node)
	await frames(1)


func test_w11_unknown_setting_hide_and_categories_command() -> void:
	var c: Object = _craft_env({"crafting": {"unknown": "hide", "menu_entry": false}})
	await on_map()
	var node: Node = env.rpg.ui.open_scene(c.SCREEN)
	node.start({"categories": ["kitchen"]}, {"rpg": env.rpg})
	await frames(2)
	assert_true(node.list.items.is_empty(), "the only kitchen recipe is unknown: left out")
	env.rpg.ui.close_scene(node)
	var menu: Node = await _menu()
	assert_false(menu.command_ids().has("crafting"), "menu entry off")
	menu.close()
	await frames(2)
	# The command (headless runs skip the screen) and its error when the plugin is off.
	var r: RPGResult = await env.rpg.run_commands([{"type": "open_crafting", "categories": ["forge"]}])
	assert_true(r.is_ok(), str(r))
	var cmd: RPGCommand = env.rpg.registry.get_command("open_crafting")
	assert_eq(cmd.summary({"categories": ["forge", "kitchen"]}), "Open crafting: forge, kitchen")
