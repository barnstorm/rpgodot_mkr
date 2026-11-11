extends "res://tests/rpg_test_case.gd"
## Extension hooks: lifecycle entry scripts, settings, save sections, main-menu entries, option
## rows, message text codes and box callbacks, condition kinds and custom fields, the map overlay
## layers and character attachments. Uses the probe extension in tests/fixtures/extensions on the
## sample project.

const Env := preload("res://tests/rpg_test_env.gd")
const Host := preload("res://addons/rpg/runtime/rpg_extension_host.gd")
const EXT_ROOT := "res://tests/fixtures/extensions"
const OPTIONS_FILE := "user://rpg_options.json"
const SLOT := 97
const WIN_SCENE := "res://tests/fixtures/extensions/probe/win_scene.gd"

var env
var _options_backup: Variant = null


func before_each() -> void:
	_options_backup = FileAccess.get_file_as_bytes(OPTIONS_FILE) if FileAccess.file_exists(OPTIONS_FILE) else null


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null
	if _options_backup == null:
		if FileAccess.file_exists(OPTIONS_FILE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_FILE))
	else:
		var f := FileAccess.open(OPTIONS_FILE, FileAccess.WRITE)
		f.store_buffer(_options_backup)
	var p := "user://saves/slot_%02d.json" % SLOT
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## The sample project with only the probe extension (plus `more`) enabled.
func probe_env(more: Array = [], project_extra: Dictionary = {}) -> Object:
	env = Env.create(tree, "res://rpg")
	var pj: Dictionary = env.rpg.data.project
	pj["extensions"] = ["probe"] + more
	pj["disabled_extensions"] = []
	pj["extensions_root"] = EXT_ROOT
	for k in project_extra:
		pj[k] = project_extra[k]
	env.rpg.reload_extensions()
	return env.rpg.extension("probe")


func on_map(cell := Vector2i(14, 12)) -> void:
	env.game.new_game()
	await env.settle()
	if env.game.map == null or env.game.player.cell != cell:
		await env.start_on("town", cell, "up")
		await env.settle()


# --- registry ------------------------------------------------------------------------------------

func test_registry_reads_manifest_declarations() -> void:
	var reg := RPGCommandRegistry.new()
	reg.load_all(["probe"], [], EXT_ROOT)
	assert_true(reg.problems.is_empty(), str(reg.problems))
	assert_true(reg.is_enabled("probe"))
	assert_true(reg.has_command("probe_mark"))
	assert_eq(RPGCommandRegistry.settings_defaults(reg.extensions.probe), {"greeting": "hello", "count": 3})
	assert_has(reg.condition_kinds(), "probe_flag")
	assert_has(RPGCommandRegistry.declared_condition_kinds, "probe_flag", "validator sees the kind")
	var cf := reg.merged_custom_fields({"actors": [{"key": "mine", "kind": "int"}]})
	assert_eq(cf.actors.size(), 2, "project fields plus the extension's")
	assert_eq(str(cf.actors[1].key), "probe_note")
	# A disabled extension declares nothing.
	reg.load_all(["probe"], ["probe"], EXT_ROOT)
	assert_false(reg.is_enabled("probe"))
	assert_true(reg.condition_kinds().is_empty())
	assert_false(reg.has_command("probe_mark"))


func test_bundled_plugins_resolve_and_stay_off() -> void:
	var ids := RPGCommandRegistry.bundled_ids()
	for id in ["menu_plus", "message_plus", "letter_sounds", "gab", "save_plus"]:
		assert_has(ids, id, "bundled")
	assert_eq(RPGCommandRegistry.manifest_path("gab", "res://extensions"), "res://addons/rpg/extensions/gab/manifest.json")
	var reg := RPGCommandRegistry.new()
	reg.load_all(["project"], [], "res://extensions")
	for id in ids:
		assert_false(reg.extensions.has(id), "%s is not loaded unless listed" % id)
	reg.load_all(["project", "gab"], [], "res://extensions")
	assert_true(reg.is_enabled("gab"))
	assert_true(reg.extensions.gab._bundled)
	assert_true(reg.has_command("show_gab"))


func test_tools_window_lists_kit_plugins_and_edits_settings() -> void:
	var data := RPGProjectData.open("res://rpg")
	var reg := RPGCommandRegistry.new()
	reg.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), "res://extensions")
	var w := RPGToolsWindow.new()
	w.setup(data, reg)
	var rows := {}
	var it: TreeItem = w._ext_tree.get_root().get_first_child()
	while it != null:
		rows[str(it.get_metadata(0))] = it
		it = it.get_next()
	for id in ["menu_plus", "message_plus", "letter_sounds", "gab", "save_plus"]:
		assert_true(rows.has(id), "%s listed" % id)
		assert_false(rows[id].is_checked(0), "%s off" % id)
	assert_true(str(rows.gab.get_text(3)).contains("show_gab"), "its commands are named")
	w.show_extension_settings("gab")
	assert_true(w._ext_settings_form != null, "settings form built from settings_schema")
	assert_eq(w._ext_settings_form.get_value().get("position"), "top", "manifest default")
	w.show_extension_settings("project")
	assert_true(w._ext_settings_form == null, "no settings: no form")
	# Save writes <root>/extensions.json.
	var root := "user://ext_tools_test"
	DirAccess.make_dir_recursive_absolute(root)
	data.root = root
	assert_eq(w.save_extension_settings("gab", {"position": "bottom"}), OK)
	assert_eq(Host.load_settings_file(root).gab, {"position": "bottom"})
	w.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("extensions.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func test_unused_kit_plugins_are_left_out_of_exports() -> void:
	var data := RPGProjectData.open("res://rpg")
	data.project["extensions"] = ["project", "gab"]
	data.project["disabled_extensions"] = []
	var Deploy: Script = load("res://addons/rpg/editor/tools/rpg_deploy.gd")
	var ex: PackedStringArray = Deploy.unused_extension_excludes(data)
	assert_true(ex.has("addons/rpg/extensions/save_plus/*"), str(ex))
	assert_false(ex.has("addons/rpg/extensions/gab/*"), "an enabled plugin is exported")


# --- lifecycle -----------------------------------------------------------------------------------

func test_entry_script_gets_lifecycle_calls() -> void:
	var p: Object = probe_env()
	assert_true(p != null, "entry script made")
	assert_eq(p.extension_id, "probe")
	assert_has(p.names(), "_extension_ready")
	await on_map()
	assert_has(p.names(), "on_new_game")
	assert_has(p.calls, ["on_map_entered", ["town"]])
	# A step.
	p.calls.clear()
	env.game.player._on_step_finished()
	var stepped: Array = p.calls.filter(func(c): return c[0] == "on_player_stepped")
	assert_eq(stepped.size(), 1, "one step")
	assert_eq(stepped[0][1][0], env.game.player.cell)
	# A transfer: left, then entered.
	p.calls.clear()
	var r: RPGResult = await env.game.transfer("field", Vector2i(3, 3), "down", "none", 8)
	assert_true(r.is_ok(), str(r))
	assert_eq(p.names().filter(func(n): return n in ["on_map_left", "on_map_entered"]), ["on_map_left", "on_map_entered"])
	assert_has(p.calls, ["on_map_left", ["town"]])
	assert_has(p.calls, ["on_map_entered", ["field"]])
	# Menu.
	p.calls.clear()
	env.game.open_menu()
	await frames(2)
	assert_has(p.calls, ["on_menu_opened", [true]])
	env.rpg.ui.scene_stack[-1].close()
	await frames(2)
	assert_has(p.names(), "on_menu_closed")
	# Level up / down.
	p.calls.clear()
	var hero: Object = env.rpg.state.actor("hero")
	var before: int = hero.level
	await env.rpg.run_commands([{"type": "change_level", "target": "hero", "operation": "increase", "amount": 2}])
	assert_has(p.calls, ["on_actor_levelled", ["hero", before, before + 2]])
	# Title and quitting are relayed too.
	p.calls.clear()
	env.rpg.title_shown.emit()
	env.rpg.quitting.emit()
	assert_eq(p.names(), ["on_title_shown", "on_quitting"])


func test_battle_hooks_come_from_battle_processing() -> void:
	var p: Object = probe_env()
	await on_map()
	p.calls.clear()
	var r: RPGResult = await env.rpg.run_commands([{"type": "battle", "troop": "slimes", "scene": WIN_SCENE, "can_escape": true, "can_lose": true}])
	assert_true(r.is_ok(), str(r))
	assert_has(p.calls, ["on_battle_started", ["slimes"]])
	assert_has(p.calls, ["on_battle_ended", ["win"]])
	var names: Array = p.names()
	assert_true(names.find("on_battle_started") < names.find("on_battle_ended"))


func test_extension_commands_run() -> void:
	var p: Object = probe_env()
	await on_map()
	await env.rpg.run_commands([{"type": "probe_mark", "mark": "m1"}])
	assert_has(p.calls, ["probe_mark", ["m1"]])


# --- settings ------------------------------------------------------------------------------------

func test_settings_defaults_file_and_override() -> void:
	probe_env()
	assert_eq(env.rpg.extension_setting("probe", "greeting"), "hello", "manifest default")
	assert_eq(env.rpg.extension_setting("probe", "missing", 7), 7, "fallback")
	env.rpg.extensions.set_settings("probe", {"greeting": "hi"})
	assert_eq(env.rpg.extension_setting("probe", "greeting"), "hi")
	assert_eq(env.rpg.extension_setting("probe", "count"), 3, "unset keys keep the default")
	assert_eq(env.rpg.extension("probe").setting("greeting"), "hi", "RPGExtension.setting")
	# The project file (rpg/extensions.json) round trip, in a scratch folder.
	var root := "user://ext_settings_test"
	DirAccess.make_dir_recursive_absolute(root)
	assert_eq(Host.save_settings(root, "probe", {"greeting": "yo"}), OK)
	assert_eq(Host.save_settings(root, "other", {"x": 1}), OK)
	var all: Dictionary = Host.load_settings_file(root)
	assert_eq(all.probe, {"greeting": "yo"})
	assert_eq(int(all.other.x), 1, "other extensions' settings kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("extensions.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


# --- save sections -------------------------------------------------------------------------------

func test_save_sections_save_reset_load_and_migrate() -> void:
	var p: Object = probe_env()
	await on_map()
	assert_true(env.rpg.saves.extension_hooks.has("probe"))
	assert_true(env.rpg.saves.extension_hooks.has("probe_owned"))
	p.section("probe")["found"] = 3
	p.owned = {"value": 42}
	var r: RPGResult = env.rpg.saves.save(SLOT)
	assert_true(r.is_ok(), str(r))
	var raw: Dictionary = RPGJson.load_or(env.rpg.saves.slot_path(SLOT), {})
	assert_eq(int(raw.extensions.probe.data.found), 3)
	assert_eq(int(raw.extensions.probe_owned.version), 2)
	# A new game empties both sections.
	env.game.new_game()
	await env.settle()
	assert_true(p.section("probe").is_empty(), "host section reset")
	assert_eq(p.owned, {"value": 0}, "owned section reset")
	# Loading brings them back and calls on_game_loaded.
	p.calls.clear()
	var lr: RPGResult = await env.rpg.saves.load_slot(SLOT)
	assert_true(lr.is_ok(), str(lr))
	assert_eq(int(p.section("probe").found), 3)
	assert_eq(int(p.owned.value), 42)
	assert_has(p.names(), "on_game_loaded")
	# An old save: the owned section is migrated from version 1.
	raw.extensions.probe_owned = {"version": 1, "data": {"old_value": 5}}
	raw.extensions.erase("probe")
	lr = await env.rpg.saves.load_data(raw)
	assert_true(lr.is_ok(), str(lr))
	assert_eq(p.migrated_from, 1)
	assert_eq(int(p.owned.value), 50)
	assert_true(p.section("probe").is_empty(), "a section missing from the save starts empty")


# --- main menu -----------------------------------------------------------------------------------

func _menu() -> Node:
	env.game.open_menu()
	await frames(2)
	return env.rpg.ui.scene_stack[-1]


func test_menu_entries_order_hide_and_conditions() -> void:
	var p: Object = probe_env([], {"menu": {"order": ["status", "item"], "hidden": ["game_end"]}})
	await on_map()
	var menu: Node = await _menu()
	var ids: Array = menu.command_ids()
	assert_eq(ids.slice(0, 2), ["status", "item"], "project order first")
	assert_false(ids.has("game_end"), "hidden by the project")
	assert_false(ids.has("probe_hidden"), "switch off: not shown")
	assert_true(ids.find("probe_method") == ids.find("status") + 1 or ids.find("probe_method") > ids.find("status"), "after status")
	assert_true(ids.find("probe_ce") < ids.find("options"), "default place: before Options")
	var locked: Dictionary = menu.menu_items[ids.find("probe_off")]
	assert_false(locked.enabled, "enable_method false: greyed out")
	# A method entry runs and the menu stays.
	await menu.choose("probe_method")
	assert_has(p.names(), "menu_probe")
	assert_eq(menu.mode, "command")
	# Disabled: nothing runs.
	p.calls.clear()
	await menu.choose("probe_off")
	assert_false(p.names().has("menu_probe"))
	# needs_actor: the actor is chosen first; the method gets it and closes the menu.
	await menu.choose("probe_actor")
	assert_eq(menu.mode, "actor")
	menu.handle_action("ok")
	await frames(2)
	assert_has(p.calls, ["menu_actor", ["hero"]])
	await frames(2)
	assert_false(env.rpg.ui.scene_open(), "closed by the entry")
	# Switch ON shows the hidden entry; unlocking enables the other.
	env.rpg.state.set_switch("key_given", true)
	p.unlocked = true
	menu = await _menu()
	assert_true(menu.command_ids().has("probe_hidden"))
	assert_true(menu.menu_items[menu.command_ids().find("probe_off")].enabled)
	# A common-event entry closes the menu and reserves the event.
	await menu.choose("probe_ce")
	await frames(2)
	assert_false(env.rpg.ui.scene_open(), "menu closed for the common event")


func test_menu_skip_single_actor() -> void:
	probe_env([], {"menu": {"skip_single_actor": true}})
	await on_map()
	assert_eq(env.rpg.state.party.size(), 1)
	var menu: Node = await _menu()
	await menu.choose("status")
	assert_eq(menu.mode, "status", "a party of one opens Status straight away")
	menu.close()
	await frames(2)
	env.rpg.state.add_actor("mira")
	menu = await _menu()
	await menu.choose("status")
	assert_eq(menu.mode, "actor", "two members: choose one")


func test_menu_without_extensions_is_the_builtin_list() -> void:
	env = Env.create(tree, "res://rpg")
	await on_map()
	var menu: Node = await _menu()
	assert_eq(menu.command_ids(), menu.COMMANDS)


# --- options -------------------------------------------------------------------------------------

func test_option_rows_change_and_persist() -> void:
	var p: Object = probe_env()
	assert_eq(env.rpg.option("probe", "mode"), "a", "default")
	assert_eq(env.rpg.option("probe", "level"), 4)
	var opts: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("options"))
	await frames(2)
	for id in ["probe.flag", "probe.mode", "probe.level"]:
		assert_has(opts.rows, id)
	assert_eq(opts.rows[-1], "done", "Done stays last")
	opts.list.select(opts.rows.find("probe.flag"))
	opts.handle_action("ok")
	assert_eq(env.rpg.option("probe", "flag"), true)
	assert_has(p.calls, ["on_option_changed", ["flag", true]])
	opts.list.select(opts.rows.find("probe.mode"))
	opts.handle_action("right")
	assert_eq(env.rpg.option("probe", "mode"), "b")
	opts.list.select(opts.rows.find("probe.level"))
	opts.handle_action("right")
	opts.handle_action("right")
	opts.handle_action("right")
	assert_eq(int(env.rpg.option("probe", "level")), 10, "slider stops at max")
	opts.finish()
	await frames(2)
	var saved: Dictionary = RPGJson.load_or(OPTIONS_FILE, {})
	assert_eq(saved.get("probe.mode"), "b", "saved in the options file")
	assert_true(saved.has("music"), "built-in options kept")
	# A fresh boot reads them back.
	await env.destroy()
	var p2: Object = probe_env()
	assert_eq(env.rpg.option("probe", "mode"), "b")
	assert_true(p2 != null)


# --- text codes ----------------------------------------------------------------------------------

func test_text_codes_tags_preprocessors_and_actions() -> void:
	var p: Object = probe_env()
	var r := RPGText.expand("A\\PX[hi]B<probe>u</probe>@@ \\V[talks]", env.rpg)
	assert_true(str(r.bbcode).begins_with("A<hi>B[u]u[/u]probe "), r.bbcode)
	assert_eq(r.plain_length, "A<hi>Buprobe 0".length())
	# A code inserting text with codes reads them (\N inside the inserted text).
	env.rpg.register_text_code("PN", func(_a: String, _i: Dictionary) -> Variant: return "\\N[hero]")
	assert_eq(RPGText.expand("\\PN", env.rpg).bbcode, "Alex")
	# Built-in letters cannot be replaced.
	env.rpg.register_text_code("V", func(_a: String, _i: Dictionary) -> Variant: return "nope")
	assert_eq(RPGText.expand("\\V[talks]", env.rpg).bbcode, "0")
	# Actions are placed where the code is.
	var a := RPGText.expand("ab\\PAcd", env.rpg)
	assert_eq(a.actions.size(), 1)
	assert_eq(int(a.actions[0].at), 2)
	# Plain labels (choices) expand extension codes and drop formatting.
	assert_eq(RPGText.expand_plain("<probe>\\PX[x]</probe>", env.rpg), "<x>")
	# The message box fires the action and reports characters, open and close.
	env.rpg.ui.auto_advance = false
	var box: Node = env.rpg.ui.message_box
	box.open_text({"text": "hi\\PA!"})
	assert_has(p.calls, ["on_message_opened", ["hi\\PA!"]])
	for i in 200:
		await frames(1)
		if box._text_done():
			break
	assert_eq(p.actions_fired, 1, "action fired when typing reached it")
	assert_eq(p.chars.map(func(c): return c[0]), ["h", "i", "!"])
	assert_false(p.chars[0][1], "typed, not instant")
	box._finish_text()
	assert_has(p.names(), "on_message_closed")


func test_skipped_text_reports_characters_as_instant() -> void:
	var p: Object = probe_env()
	var box: Node = env.rpg.ui.message_box
	box.open_text({"text": "xyz\\PA"})
	await frames(2)
	assert_eq(p.chars.map(func(c): return c[1]), [true, true, true], "auto-advance shows the page at once")
	assert_eq(p.actions_fired, 1, "actions at the end still fire")


# --- conditions and custom fields ----------------------------------------------------------------

func test_condition_kind_in_pages_branches_and_editor() -> void:
	var p: Object = probe_env()
	await on_map()
	var st: RPGGameState = env.rpg.state
	assert_false(st.check_condition({"kind": "probe_flag", "value": true}))
	p.flag = true
	assert_true(st.check_condition({"kind": "probe_flag", "value": true}))
	# Conditional Branch.
	await env.rpg.run_commands([{"type": "if", "condition": {"kind": "probe_flag", "value": true}, "then": [{"type": "probe_mark", "mark": "yes"}], "else": [{"type": "probe_mark", "mark": "no"}]}])
	assert_has(p.calls, ["probe_mark", ["yes"]])
	# The validator accepts the kind on an event page; an unknown kind is still an error.
	var probs := RPGValidator.event_structure({"id": "e", "position": [1, 1], "pages": [{"conditions": [{"kind": "probe_flag", "value": true}], "commands": []}]}, env.rpg.registry)
	assert_true(probs.filter(func(x): return x.severity == "error").is_empty(), str(probs))
	var bad := RPGValidator.event_structure({"id": "e", "position": [1, 1], "pages": [{"conditions": [{"kind": "nope"}], "commands": []}]}, env.rpg.registry)
	assert_false(bad.is_empty())
	# The condition editor offers it with its fields.
	var ce := RPGConditionEditor.new(env.rpg.data, env.rpg.registry, false, {}, true)
	assert_has(ce.kinds(), "probe_flag")
	ce.set_value({"kind": "probe_flag", "value": false})
	assert_eq(ce.get_value(), {"kind": "probe_flag", "value": false})
	ce.free()


func test_custom_fields_from_extensions() -> void:
	probe_env()
	var custom: Dictionary = env.rpg.registry.merged_custom_fields(env.rpg.data.project.get("custom_fields", {}))
	var fields: Array = RPGRecordSchemas.fields_for("actors", [], [], [], custom)
	var cf: Array = fields.filter(func(f): return str(f.get("key", "")) == "custom")
	assert_eq(cf.size(), 1)
	assert_true(cf[0].fields.any(func(f): return str(f.key) == "probe_note"), "the Database form shows the field")
	assert_eq(env.rpg.extensions.custom_field("actors", "hero", "probe_note"), "none", "default when unset")


# --- overlays and attachments --------------------------------------------------------------------

func test_overlay_layers_and_character_attachments() -> void:
	probe_env()
	await on_map()
	var m: Node = env.rpg.map_overlay_layer("map")
	assert_true(m is Node2D and m.get_parent() == env.game.world, "map layer in the world")
	assert_true(m.z_index >= 50, "above the characters")
	var s: Node = env.rpg.map_overlay_layer("screen")
	assert_true(s is CanvasLayer and s.layer < env.rpg.ui.layer, "screen layer under the UI")
	var h: Node = env.rpg.map_overlay_layer("hud")
	assert_true(h is Control and h.get_parent() is CanvasLayer and h.get_parent().layer > env.rpg.ui.layer, "hud above the UI")
	assert_true(env.rpg.map_overlay_layer("map") == m, "made once")
	var light := Node2D.new()
	m.add_child(Node2D.new())
	assert_true(env.rpg.attach_to_character("player", light))
	assert_eq(light.get_parent(), env.game.player)
	var tag := Node2D.new()
	var ev_id: String = env.game.map.events.keys()[0]
	assert_true(env.rpg.attach_to_character(ev_id, tag))
	assert_eq(tag.get_parent(), env.game.map.get_event(ev_id))
	var nope := Node2D.new()
	assert_false(env.rpg.attach_to_character("no_such_event", nope))
	nope.free()
	# Layers survive a transfer; the player keeps its attachment.
	var r: RPGResult = await env.game.transfer("field", Vector2i(3, 3), "down", "none", 8)
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.map_overlay_layer("map"), m)
	assert_true(is_instance_valid(light) and light.get_parent() == env.game.player)


# --- choices (core: shown / enabled by a switch) -------------------------------------------------

func test_choices_hidden_and_disabled_by_switches() -> void:
	env = Env.create(tree, "res://rpg")
	await on_map()
	var rpg: Node = env.rpg
	rpg.state.set_switch("key_given", false)
	var cmd := {"type": "show_choices", "cancel": "branch", "choices": [
		{"label": "A", "then": [{"type": "set_variable", "id": "talks", "operation": "set", "value": 1}]},
		{"label": "B", "show_switch": "key_given", "then": [{"type": "set_variable", "id": "talks", "operation": "set", "value": 2}]},
		{"label": "C", "then": [{"type": "set_variable", "id": "talks", "operation": "set", "value": 3}]}],
		"cancel_then": [{"type": "set_variable", "id": "talks", "operation": "set", "value": 9}]}
	var box: Node = rpg.ui.message_box
	box.auto_choice = 1
	await rpg.run_commands([cmd])
	assert_eq(rpg.get_variable("talks"), 3, "B hidden: the second shown choice is C")
	rpg.state.set_switch("key_given", true)
	await rpg.run_commands([cmd])
	assert_eq(rpg.get_variable("talks"), 2, "B shown again")
	# Disabled: shown greyed, picking it buzzes and nothing is chosen.
	rpg.ui.auto_advance = false
	var cmd2: Dictionary = cmd.duplicate(true)
	cmd2.choices[0]["enable_switch"] = "door_unlocked"
	rpg.state.set_switch("door_unlocked", false)
	var t: RPGResult = null
	var run := func() -> void: t = await rpg.run_commands([cmd2])
	run.call()
	await frames(2)
	assert_eq(box.mode, "choices")
	assert_true(box._disabled.has(0))
	box._try_pick(0)
	assert_eq(box.mode, "choices", "a disabled choice is not picked")
	box._try_pick(2)
	for i in 30:
		await frames(1)
		if t != null:
			break
	assert_eq(rpg.get_variable("talks"), 3)
	# Old data (no switch fields) is unchanged.
	assert_eq(RPGValidator.command_structure(cmd, rpg.registry).filter(func(x): return x.severity == "error"), [])
