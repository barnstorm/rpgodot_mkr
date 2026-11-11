extends "res://tests/rpg_test_case.gd"
## Tools window (milestone 7): event search, resource usage, sound list, extensions and deploy
## checks, run on the sample project and the door fixture.

var data: RPGProjectData
var registry: RPGCommandRegistry


func before_each() -> void:
	data = RPGProjectData.open("res://rpg")
	registry = RPGCommandRegistry.new()
	registry.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), "res://extensions")


func test_search_by_text_finds_message() -> void:
	var r := RPGProjectSearch.search(data, registry, {"text": "finally awake"})
	assert_eq(r.size(), 1)
	assert_eq(r[0].map, "town")
	assert_eq(r[0].event, "elder")
	assert_eq(r[0].type, "show_text")


func test_search_by_type_and_inside_branches() -> void:
	var r := RPGProjectSearch.search(data, registry, {"type": "battle"})
	var troops := []
	for h in r:
		troops.append(h.summary)
	assert_true(r.size() >= 1, "the goblin battle is found")
	var nested := RPGProjectSearch.search(data, registry, {"type": "set_switch", "ref": "goblin_defeated"})
	assert_eq(nested.size(), 1, "a command inside the battle's on_win branch is found")
	assert_true(nested[0].path.contains("on_win"), nested[0].path)


func test_search_by_reference_includes_page_conditions() -> void:
	var r := RPGProjectSearch.search(data, registry, {"ref": "house_key"})
	var kinds := {}
	for h in r:
		kinds[h.type] = true
	assert_true(kinds.has("change_items"), "the elder gives the key")
	assert_true(kinds.has("(page condition)"), "the door page needs the key")


func test_empty_query_returns_nothing() -> void:
	assert_eq(RPGProjectSearch.search(data, registry, {}).size(), 0)


func test_asset_usage_marks_referenced_files() -> void:
	var usage := RPGProjectSearch.asset_usage(data)
	assert_true(usage.size() > 10)
	var by_name := {}
	for u in usage:
		by_name[u.path] = u.used
	assert_eq(by_name.get("res://assets/starter/ChipSet/town.png"), true, "the tileset sheet is used")


func test_sound_files_grouped_by_folder() -> void:
	var s := RPGProjectSearch.sound_files()
	assert_true(s.has("Music") and s.has("Sound"), str(s.keys()))
	assert_true(s.Sound.has("res://assets/starter/Sound/decision.wav"))


func test_tools_window_builds_and_searches() -> void:
	var w := RPGToolsWindow.new()
	w.setup(data, registry)
	tree.root.add_child(w)
	w.show_tab("Event search")
	assert_eq(w.tabs.get_tab_title(w.tabs.current_tab), "Event search")
	w._search_text.text = "goblin"
	assert_true(w.run_search().size() > 0)
	assert_eq(w.tabs.get_tab_count(), 5)
	w.free()


func test_set_extensions_writes_project_file() -> void:
	var root := "user://rpg_tools_test"
	DirAccess.make_dir_recursive_absolute(root)
	RPGJson.save_file(root + "/project.json", {"schema_version": 1, "project_id": "t", "extensions": ["project", "fx"]})
	var d := RPGProjectData.open(root)
	var w := RPGToolsWindow.new()
	w.data = d
	assert_eq(w.set_extensions(["project", "fx"], ["fx"]), OK)
	var back: Dictionary = RPGJson.load_or(root + "/project.json", {})
	assert_eq(back.disabled_extensions, ["fx"])
	assert_eq(w.set_extensions(["project", "fx"], []), OK)
	assert_false(RPGJson.load_or(root + "/project.json", {}).has("disabled_extensions"))
	w.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/project.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func test_rule_migration_preview_classic_to_osr() -> void:
	var systems := RPGRuleMigration.available("res://rpg")
	var ids := []
	for s in systems:
		ids.append(s.id)
	assert_true(ids.has("classic") and ids.has("osr_example"), str(ids))
	var p := RPGRuleMigration.preview(data, "osr_example")
	assert_true(p.ok)
	assert_true(p.stats_removed.has("atk"), "Classic attack power is not an OSR stat")
	assert_true(p.stats_added.has("ac"))
	assert_true(p.resources_removed.has("sp"))
	var fields := []
	for u in p.uses:
		fields.append(u.field)
	assert_true(p.uses.size() > 0, "database values using removed stats are listed")
	assert_true(RPGRuleMigration.describe(p).contains("Nothing is deleted"))
	assert_false(RPGRuleMigration.preview(data, "no_such_rules").ok)


func test_rule_migration_apply_only_changes_project_rules() -> void:
	var root := "user://rpg_rules_test"
	DirAccess.make_dir_recursive_absolute(root)
	RPGJson.save_file(root + "/project.json", {"schema_version": 1, "project_id": "t", "rules": "classic", "x_keep": 1})
	var d := RPGProjectData.open(root)
	assert_eq(RPGRuleMigration.apply(d, "osr_example"), OK)
	var back: Dictionary = RPGJson.load_or(root + "/project.json", {})
	assert_eq(back.rules, "osr_example")
	assert_eq(back.x_keep, 1, "other project fields are kept")
	var bd := DirAccess.open(root + "/.backup")
	assert_true(bd != null and bd.get_directories().size() == 1, "a backup is made first")
	if bd != null:
		for sub in bd.get_directories():
			var b := root + "/.backup/" + sub
			DirAccess.remove_absolute(ProjectSettings.globalize_path(b + "/project.json"))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(b + "/database"))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(b))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/.backup"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/project.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func test_default_asset_resolver_flags_missing_files() -> void:
	var r := RPGValidator.default_asset_resolver()
	assert_true(r.call("charset", "hero"), "a starter CharSet exists")
	assert_false(r.call("charset", "no_such_sheet"), "a missing CharSet is reported")
	assert_true(r.call("my_extension_kind", "anything"), "unknown kinds are not guessed at")
	assert_true(r.call("music", ""), "blank means none")


func test_recover_interrupted_writes() -> void:
	var root := "user://rpg_recover_test"
	DirAccess.make_dir_recursive_absolute(root)
	# A swap that died after the backup was made: only the .bak is left.
	RPGJson.save_file(root + "/a.json", {"v": 1})
	DirAccess.rename_absolute(root + "/a.json", root + "/a.json.bak")
	# An unfinished write next to a good file.
	RPGJson.save_file(root + "/b.json", {"v": 2})
	var f := FileAccess.open(root + "/b.json.tmp", FileAccess.WRITE)
	f.store_string("{\"v\": ")
	f.close()
	assert_eq(RPGJson.find_interrupted(root).size(), 2)
	var done := RPGJson.recover_interrupted(root)
	assert_eq(done.size(), 2, str(done))
	assert_eq(RPGJson.load_or(root + "/a.json", {}).get("v"), 1, "backup restored")
	assert_eq(RPGJson.load_or(root + "/b.json", {}).get("v"), 2, "the good version is kept")
	assert_true(FileAccess.file_exists(root + "/b.json.interrupted"), "the partial write is kept aside")
	assert_eq(RPGJson.find_interrupted(root).size(), 0)
	for n in ["a.json", "b.json", "b.json.interrupted"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/" + n))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func test_capability_checks() -> void:
	assert_eq(RPGExportCheck.capability_problems(data, registry), [], "the default battle fits the Classic rules")
	var caps: Variant = RPGExportCheck.scene_capabilities("res://addons/rpg/runtime/ui/battle/battle_scene.gd")
	assert_true(caps is Array and caps.has("turn_order"))
	# A rule system that offers almost nothing makes the default battle incompatible.
	var root := "user://rpg_caps_test"
	DirAccess.make_dir_recursive_absolute(root + "/rules/bare")
	RPGJson.save_file(root + "/project.json", {"schema_version": 1, "project_id": "t", "rules": "bare", "extensions": []})
	RPGJson.save_file(root + "/rules/bare/rules.json", {"schema_version": 1, "id": "bare", "capabilities": ["turn_order"]})
	var d := RPGProjectData.open(root)
	var probs := RPGExportCheck.capability_problems(d)
	assert_true(probs.size() >= 1)
	if not probs.is_empty():
		assert_true(str(probs[0].message).contains("does not offer"), str(probs[0].message))
	for f in ["/rules/bare/rules.json", "/rules/bare", "/rules", "/project.json", ""]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root + f))


func test_export_blocked_by_disabled_extension_command() -> void:
	# Acceptance 10: a command from a disabled extension in any event blocks export.
	var root := "user://rpg_block_test"
	DirAccess.make_dir_recursive_absolute(root + "/maps")
	var proj: Dictionary = RPGJson.load_or("res://tests/fixtures/door_project/project.json", {})
	RPGJson.save_file(root + "/project.json", proj)
	RPGJson.save_file(root + "/common_events.json", {"schema_version": 1, "common_events": [
		{"id": "uses_fancy", "name": "Uses fancy", "trigger": "none", "switch": "", "commands": [{"type": "fancy_effect"}]}]})
	var errors := []
	for p in RPGExportCheck.run_checks(root):
		if p.get("severity", "") == "error" and str(p.get("message", "")).contains("fancy"):
			errors.append(p)
	assert_true(errors.size() >= 1, "the disabled extension's command is an export error")
	proj["disabled_extensions"] = []
	RPGJson.save_file(root + "/project.json", proj)
	var after := []
	for p in RPGExportCheck.run_checks(root):
		if p.get("severity", "") == "error" and str(p.get("message", "")).contains("unavailable"):
			after.append(p)
	assert_eq(after, [], "turning the extension on again unblocks it")
	for f in ["/project.json", "/common_events.json", "/maps", ""]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root + f))


func test_problem_location_for_jump_to_fix() -> void:
	assert_eq(RPGToolsWindow.problem_location({"file": "res://rpg/maps/town.events.json", "record": "door"}), {"map": "town", "event": "door"})
	assert_eq(RPGToolsWindow.problem_location({"file": "res://rpg/maps/town.events.json", "record": "event 'chest' page 2"}), {"map": "town", "event": "chest"})
	assert_eq(RPGToolsWindow.problem_location({"file": "res://rpg/maps/field.map.json", "record": ""}), {"map": "field", "event": ""})
	assert_eq(RPGToolsWindow.problem_location({"file": "res://rpg/common_events.json", "record": "common event 'heal'"}), {"map": "", "event": "heal"})


func test_new_project_from_template_runs() -> void:
	var root := "user://rpg_new_project"
	var ext := "user://rpg_new_project_ext"
	var r := RPGProjectTemplate.create(root, "Moon Quest", ext)
	assert_eq(r.error, OK, str(r.messages))
	assert_eq(RPGProjectTemplate.create(root, "Again", ext).error, ERR_ALREADY_EXISTS, "an existing project is never overwritten")
	var d := RPGProjectData.open(root)
	assert_true(d.load_errors.is_empty(), str(d.load_errors))
	assert_eq(d.project.project_id, "moon_quest")
	assert_eq(d.system.start.map, "start")
	assert_true(d.maps.has("start"))
	assert_true(FileAccess.file_exists(ext + "/project/manifest.json"), "the project extension is created")
	var node := RPGMapFiles.load_map(d, "start")
	assert_eq(node.tile_layers[0].get_used_cells().size(), 300, "the first map is grass")
	node.free()
	var errors := []
	for p in RPGExportCheck.run_checks(root):
		if p.get("severity", "") == "error":
			errors.append(p)
	assert_eq(errors, [], "a new project passes the export checks")
	# It actually runs: boot the runtime on it and start a new game.
	var env = load("res://tests/rpg_test_env.gd").create(tree, root)
	await env.game.new_game()
	assert_true(await env.settle())
	assert_eq(env.game.map.map_id, "start")
	assert_eq(env.game.player.cell, Vector2i(10, 7))
	await env.destroy()
	_rm_tree(root)
	_rm_tree(ext)
	assert_eq(r.screen, Vector2i(320, 240), "2000-style screen by default")


## Create RPG project's style: a VX/Ace project cuts imported sheets the VX way and uses 544x416.
func test_new_project_style_vx() -> void:
	var root := "user://rpg_new_project_vx"
	var ext := "user://rpg_new_project_vx_ext"
	var r := RPGProjectTemplate.create(root, "Ace Quest", ext, "vx")
	assert_eq(r.error, OK, str(r.messages))
	assert_eq(r.screen, Vector2i(544, 416))
	var d := RPGProjectData.open(root)
	assert_eq(d.profile.profile, "vx")
	assert_eq(int(d.profile.tile_size), 32)
	assert_true(d.maps.has("start"), "the starter map still uses the starter (2000-style) tileset")
	assert_eq(RPGAssets.sheet_profile("charset", "hero", str(d.profile.profile)), "rm2k", "starter characters keep their own layout")
	_rm_tree(root)
	_rm_tree(ext)


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
		d.remove(sub)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_new_command_from_template_loads_and_runs() -> void:
	var ext := "user://rpg_newcmd_ext/project"
	DirAccess.make_dir_recursive_absolute(ext)
	RPGJson.save_file(ext + "/manifest.json", {"schema_version": 1, "id": "project", "api_versions": [1], "commands": []})
	var r := RPGToolsWindow.create_command(ext, "ring_bell", "Ring bell", "audio")
	assert_eq(r.error, OK, r.message)
	assert_eq(RPGToolsWindow.create_command(ext, "ring_bell").error, ERR_ALREADY_EXISTS)
	assert_eq(RPGToolsWindow.create_command(ext, "Bad Name").error, ERR_INVALID_PARAMETER)
	var reg := RPGCommandRegistry.new()
	reg.load_all(["project"], [], "user://rpg_newcmd_ext")
	assert_true(reg.has_command("ring_bell"), "the new command registers: %s" % str(reg.problems))
	assert_eq(reg.descriptor("ring_bell").label, "Ring bell")
	assert_eq(reg.summary({"type": "ring_bell", "message": "Ding"}), "Ring bell: Ding")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ext + "/commands/ring_bell.gd"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ext + "/commands"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ext + "/manifest.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ext))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rpg_newcmd_ext"))


func test_battle_effects_map_names_and_play() -> void:
	assert_eq(RPGBattleEffects.builtin_for("fire"), "fire")
	assert_eq(RPGBattleEffects.builtin_for("Big Flame 2"), "fire")
	assert_eq(RPGBattleEffects.builtin_for("power_strike"), "slash")
	assert_eq(RPGBattleEffects.builtin_for("cure_all"), "heal")
	assert_eq(RPGBattleEffects.builtin_for("whatever"), "hit")
	var layer := Control.new()
	layer.size = Vector2(320, 240)
	tree.root.add_child(layer)
	for n in RPGBattleEffects.BUILTIN:
		assert_true(RPGBattleEffects.play(layer, Vector2(100, 100), n) > 0.0, n)
	assert_eq(layer.get_child_count(), RPGBattleEffects.BUILTIN.size(), "each effect draws on its own layer")
	await tree.create_timer(1.2).timeout
	assert_eq(layer.get_child_count(), 0, "effects clean up after themselves")
	layer.queue_free()


func test_missing_asset_blocks_export_but_only_warns_on_save() -> void:
	var files := RPGValidator.collect_files(data)
	# Point one event graphic at a sheet that does not exist (in a copy; nothing is written).
	for path in files:
		if files[path].get("kind", "") == "events" and files[path].map == "town":
			var evs: Array = files[path].data.events
			for ev in evs:
				for pg in ev.get("pages", []):
					if pg.get("graphic") is Dictionary and pg.graphic.has("sheet"):
						pg.graphic.sheet = "no_such_sheet"
						break
	var full := RPGValidator.full(data, registry, files)
	var blocking := []
	for p in full:
		if str(p.message).contains("no_such_sheet"):
			blocking.append(p)
	assert_true(blocking.size() >= 1, "the missing sheet is reported")
	if not blocking.is_empty():
		assert_eq(blocking[0].severity, "error")
		assert_true(blocking[0].get("blocks_export", false), "it blocks release export")
	var refs := RPGValidator.references(data, registry, files, RPGValidator.default_asset_resolver())
	for p in refs:
		if str(p.message).contains("no_such_sheet"):
			assert_eq(p.severity, "warning", "while editing it is only a warning")


# --- deploy and resource manager helpers (no real export is run) ---------------------------------

const DeployHelpers := preload("res://addons/rpg/editor/tools/rpg_deploy.gd")
const ResourceFilesHelpers := preload("res://addons/rpg/editor/tools/rpg_resource_files.gd")


func test_deploy_presets_and_default_output() -> void:
	var presets := DeployHelpers.presets("res://export_presets.cfg")
	assert_true(presets.size() >= 1, "the project has an export preset")
	if not presets.is_empty():
		assert_eq(presets[0].name, "Windows Desktop")
		assert_eq(presets[0].section, "preset.0")
	assert_eq(DeployHelpers.default_output("Windows Desktop", "Sample Quest"), "build/windows/SampleQuest.exe")
	assert_eq(DeployHelpers.default_output("Web", "Moon: Quest!"), "build/web/MoonQuest.html")
	assert_eq(DeployHelpers.default_output("Linux", ""), "build/linux/Game.x86_64")
	assert_eq(DeployHelpers.presets("user://no_such_presets.cfg"), [])


func test_deploy_build_args() -> void:
	var a := DeployHelpers.build_args("Windows Desktop", "build/windows/X.exe", "C:/proj")
	assert_eq(a, PackedStringArray(["--headless", "--path", "C:/proj", "--export-release", "Windows Desktop", "C:/proj/build/windows/X.exe"]))
	var b := DeployHelpers.build_args("Web", "D:/out/index.html", "C:/proj", true)
	assert_eq(b[3], "--export-debug")
	assert_eq(b[5], "D:/out/index.html", "absolute output paths are kept")
	var c := DeployHelpers.build_args("Web", "res://build/web/index.html")
	assert_eq(c[2], ProjectSettings.globalize_path("res://"))
	assert_eq(c[5], ProjectSettings.globalize_path("res://build/web/index.html"))


func test_unused_asset_excludes_keep_runtime_defaults() -> void:
	var ex := DeployHelpers.unused_asset_excludes(data)
	for u in RPGProjectSearch.asset_usage(data):
		if u.used:
			assert_false(ex.has(u.path), "used file %s is kept" % u.path)
	# The battle plays "cursor" and "buzzer" by role even though no data names them.
	assert_false(ex.has("res://assets/starter/Sound/cursor.wav"))
	assert_false(ex.has("res://assets/starter/Sound/buzzer.wav"))
	assert_false(ex.has("res://assets/starter/System/system.png"))
	# A really unused file in a scratch asset root is listed.
	var root := "user://rpg_deploy_assets"
	DirAccess.make_dir_recursive_absolute(root + "/pack/Picture")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.save_png(root + "/pack/Picture/zz_never_used.png")
	img.save_png(root + "/pack/Picture/cursor.png")
	var ex2 := DeployHelpers.unused_asset_excludes(data, root)
	assert_true(ex2.has(root + "/pack/Picture/zz_never_used.png"), str(ex2))
	assert_false(ex2.has(root + "/pack/Picture/cursor.png"), "runtime role names are never left out")
	_rm_tree(root)


func test_apply_excludes_is_restored() -> void:
	var cfg := "user://rpg_deploy_presets.cfg"
	var original := FileAccess.get_file_as_string("res://export_presets.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string(original)
	f.close()
	var r := DeployHelpers.apply_excludes(cfg, "preset.0", PackedStringArray(["res://assets/a.png", "res://assets/b.wav"]))
	assert_true(r.ok, str(r.message))
	var during: Dictionary = DeployHelpers.presets(cfg)[0]
	assert_true(str(during.exclude_filter).begins_with("tests/*"), "the preset's own excludes are kept")
	assert_true(str(during.exclude_filter).ends_with("res://assets/a.png, res://assets/b.wav"), str(during.exclude_filter))
	assert_true(FileAccess.file_exists(cfg + DeployHelpers.BACKUP_SUFFIX))
	assert_true(DeployHelpers.restore_presets(cfg))
	assert_eq(FileAccess.get_file_as_string(cfg), original, "the preset file is back byte for byte")
	assert_false(FileAccess.file_exists(cfg + DeployHelpers.BACKUP_SUFFIX))
	assert_false(DeployHelpers.restore_presets(cfg), "nothing to restore twice")
	assert_false(DeployHelpers.apply_excludes(cfg, "preset.9", PackedStringArray(["x"])).ok)
	assert_eq(FileAccess.get_file_as_string(cfg), original, "a failed apply leaves the file as it was")
	assert_true(DeployHelpers.apply_excludes(cfg, "preset.0", PackedStringArray()).ok, "nothing to leave out is fine")
	assert_false(FileAccess.file_exists(cfg + DeployHelpers.BACKUP_SUFFIX))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg))


func test_summarize_export_output() -> void:
	var missing := DeployHelpers.summarize_output(1, "ERROR: Cannot export project with preset \"Windows Desktop\" due to configuration errors:\nNo export template found at the expected path:\nC:/x/templates/windows_release_x86_64.exe\n")
	assert_false(missing.ok)
	assert_true(str(missing.message).contains("Manage Export Templates"), str(missing.message))
	var bad := DeployHelpers.summarize_output(1, "ERROR: Invalid export preset name: Foo.\n")
	assert_true(str(bad.message).contains("preset"))
	var other := DeployHelpers.summarize_output(2, "hello\nERROR: Something broke.\n")
	assert_true(str(other.message).contains("Something broke"), str(other.message))
	assert_true(DeployHelpers.summarize_output(0, "done").ok)
	assert_false(DeployHelpers.summarize_output(0, "done", "user://no_such_build.exe").ok, "no file means no success")
	# Godot can crash on shutdown after a good export: the written file decides.
	var built := "user://rpg_fake_build.exe"
	var bf := FileAccess.open(built, FileAccess.WRITE)
	bf.store_string("x")
	bf.close()
	var esc := char(27)
	var log := esc + "[1msavepack" + esc + "[22m | Storing File: res://a.json\n[ DONE ] savepack\nERROR: 64 RID allocations of type 'X' were leaked at exit.\nCrashHandlerException: Program crashed with signal 11\n"
	var crashed := DeployHelpers.summarize_output(139, log, built, int(Time.get_unix_time_from_system()) - 5)
	assert_true(crashed.ok, str(crashed.message))
	assert_false(DeployHelpers.summarize_output(139, log, built, int(Time.get_unix_time_from_system()) + 3600).ok, "an old file from an earlier build does not count")
	assert_false(DeployHelpers.summarize_output(1, "ERROR: Cannot export project with preset \"X\".\n", built).ok)
	var cleaned := DeployHelpers.clean_log(log)
	assert_false(cleaned.contains(esc) or cleaned.contains("Storing File"), cleaned)
	assert_true(cleaned.contains("(1 files packed)"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(built))


func test_where_used_names_places() -> void:
	var hero := DeployHelpers.where_used(data, "res://assets/starter/CharSet/hero.png")
	assert_true(hero.size() >= 1, "the hero sheet is used")
	var cursor := DeployHelpers.where_used(data, "res://assets/starter/Sound/cursor.wav")
	assert_true(cursor.has("runtime default 'cursor'"), str(cursor))
	assert_eq(DeployHelpers.where_used(data, "res://assets/starter/Picture/zz_nothing.png"), [])


func test_resource_import_and_delete() -> void:
	var src_dir := "user://rpg_import_src"
	var root := "user://rpg_import_assets"
	DirAccess.make_dir_recursive_absolute(src_dir)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(src_dir + "/zz_new_face.png")
	var txt := FileAccess.open(src_dir + "/notes.txt", FileAccess.WRITE)
	txt.store_string("x")
	txt.close()
	assert_eq(ResourceFilesHelpers.folder_for("battler"), "Monster")
	assert_eq(ResourceFilesHelpers.TYPES.size(), 11)
	var face := root + "/project/FaceSet/zz_new_face.png"
	var r := ResourceFilesHelpers.import_files(PackedStringArray([src_dir + "/zz_new_face.png", src_dir + "/notes.txt"]), "faceset", "project", root)
	assert_eq(r.copied, [face])
	assert_eq(r.errors.size(), 1, "a .txt is not a FaceSet")
	assert_true(FileAccess.file_exists(face))
	var again := ResourceFilesHelpers.import_files(PackedStringArray([src_dir + "/zz_new_face.png"]), "faceset", "project", root)
	assert_eq(again.copied, [], "an existing file is not replaced without asking")
	assert_eq(again.conflicts, [face])
	assert_eq(ResourceFilesHelpers.import_files(PackedStringArray([src_dir + "/zz_new_face.png"]), "faceset", "project", root, true).copied.size(), 1)
	assert_eq(ResourceFilesHelpers.import_files(PackedStringArray([src_dir + "/zz_new_face.png"]), "music", "project", root).errors.size(), 1, "images are not music")
	assert_eq(ResourceFilesHelpers.import_files(PackedStringArray([src_dir + "/zz_new_face.png"]), "faceset", "Bad Pack", root).errors.size(), 1)
	var tex := ResourceFilesHelpers.load_preview_texture(face)
	assert_true(tex != null and tex.get_width() == 8, "an unimported image still previews")
	# Delete: unused goes; a used file is refused and the reason names where it is used.
	var used := ResourceFilesHelpers.delete_asset(data, "res://assets/starter/CharSet/hero.png", "res://assets", false)
	assert_false(used.ok)
	assert_true(used.used_by.size() >= 1 and str(used.message).contains("used by"), str(used.message))
	assert_true(FileAccess.file_exists("res://assets/starter/CharSet/hero.png"), "nothing was deleted")
	var gone := ResourceFilesHelpers.delete_asset(data, face, root, false)
	assert_true(gone.ok, str(gone.message))
	assert_false(FileAccess.file_exists(face))
	_rm_tree(root)
	_rm_tree(src_dir)


func test_tools_window_pan_preview_and_deploy_page() -> void:
	var w := RPGToolsWindow.new()
	w.presets_path = "user://rpg_no_presets_here.cfg"
	w.setup(data, registry)
	tree.root.add_child(w)
	w.set_pan(-50)
	assert_true(absf(w.get_pan() + 50.0) < 0.01, str(w.get_pan()))
	assert_true(AudioServer.get_bus_index(RPGToolsWindow.SOUND_TEST_BUS) > 0, "the sound test bus exists while the window is open")
	assert_true(w.deploy_build.disabled, "no presets: Build is disabled")
	w.preview_asset("res://assets/starter/CharSet/hero.png")
	assert_true(w.res_preview.texture != null)
	if w.res_preview.texture != null:
		assert_eq(w.res_preview.custom_minimum_size, w.res_preview.texture.get_size() * 2.0, "images preview at 2x")
	w.free()
	assert_eq(AudioServer.get_bus_index(RPGToolsWindow.SOUND_TEST_BUS), -1, "the bus is removed with the window")


# --- RPG Maker folder import (synthetic layouts under user://) ----------------------------------

const RMImportHelpers := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")
const RM_TMP := "user://rpg_rm_import"


func _rm_png(path: String, w: int, h: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.3))
	img.save_png(path)


## A tiny valid MIDI file (format 0, one empty track).
func _rm_midi(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(Marshalls.base64_to_raw("TVRoZAAAAAYAAAABAeBNVHJrAAAABAD/LwA="))
	f.close()


func _rm_bytes(path: String, text := "data") -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A 24-bit BMP (RPG Maker 2000 RTP files are often BMP).
func _rm_bmp(path: String, w: int, h: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var row := (w * 3 + 3) / 4 * 4
	var b := PackedByteArray()
	b.resize(54 + row * h)
	b.encode_u8(0, 0x42)
	b.encode_u8(1, 0x4D)
	b.encode_u32(2, b.size())
	b.encode_u32(10, 54)
	b.encode_u32(14, 40)
	b.encode_s32(18, w)
	b.encode_s32(22, h)
	b.encode_u16(26, 1)
	b.encode_u16(28, 24)
	b.encode_u32(34, row * h)
	for i in range(54, b.size()):
		b[i] = 200
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _rm_project(existing_records: Array) -> String:
	var root := RM_TMP + "/proj"
	DirAccess.make_dir_recursive_absolute(root + "/database")
	RPGJson.save_file(root + "/profile.json", {"schema_version": 1, "profile": "rm2k", "tile_size": 16})
	RPGJson.save_file(root + "/database/tilesets.json", {"schema_version": 1, "records": existing_records})
	return root


func test_rm_import_vx_ace_rtp() -> void:
	_rm_tree(RM_TMP)
	var rtp := RM_TMP + "/RPGVXAce/RTP"
	_rm_png(rtp + "/Graphics/Tilesets/Outside_A1.png", 512, 384)
	_rm_png(rtp + "/Graphics/Tilesets/Outside_A2.png", 512, 384)
	_rm_png(rtp + "/Graphics/Tilesets/Outside_B.png", 512, 512)
	_rm_png(rtp + "/Graphics/Tilesets/Inside_A5.png", 256, 512)
	_rm_png(rtp + "/Graphics/Tilesets/Castle.png", 64, 64)
	_rm_png(rtp + "/Graphics/Characters/Actor1.png", 384, 256)
	_rm_png(rtp + "/Graphics/Faces/Actor1.png", 384, 192)
	_rm_png(rtp + "/Graphics/Battlebacks1/Grassland.png", 580, 444)
	_rm_bytes(rtp + "/Audio/SE/Cursor1.ogg")
	_rm_bytes(rtp + "/Audio/BGM/Battle1.ogg")
	_rm_bytes(rtp + "/Audio/ME/Battle1.ogg")
	_rm_midi(rtp + "/Audio/BGM/Theme.mid")
	# Picking the Graphics folder itself still finds Audio next to it.
	var d := RMImportHelpers.detect(rtp + "/Graphics")
	assert_eq(d.profile, "vx", str(d))
	assert_eq(d.base, rtp)
	assert_eq(RMImportHelpers.suggest_pack_id(rtp + "/Graphics"), "rpgvxace_rtp")
	var proj := _rm_project([{"id": "outside", "name": "Taken", "profile": "rm2k", "sheet": "res://x.png"}])
	var assets := RM_TMP + "/assets"
	var p := RMImportHelpers.plan(rtp + "/Graphics", "vxace", assets, proj)
	var dsts := {}
	for f in p.files:
		dsts[str(f.dst).trim_prefix(assets + "/vxace/")] = f
	assert_true(dsts.has("Tilesets/Outside_A1.png") and dsts.has("CharSet/Actor1.png") and dsts.has("FaceSet/Actor1.png") and dsts.has("Backdrop/Grassland.png"), str(dsts.keys()))
	assert_true(dsts.has("Sound/Cursor1.ogg") and dsts.has("Music/Battle1.ogg"), str(dsts.keys()))
	assert_true(dsts.has("Music/Theme.mid"), "MIDI music is copied (rendered at import): %s" % str(dsts.keys()))
	var reasons := []
	for s in p.skipped:
		reasons.append(str(s.reason))
	assert_eq(p.skipped.size(), 1, "the second Battle1.ogg is skipped: %s" % str(reasons))
	var recs := {}
	for t in p.tilesets:
		recs[t.record.name] = t.record
	assert_eq(recs.keys().size(), 2, str(recs.keys()))
	assert_eq(recs.Outside.id, "outside_2", "an existing id is not reused")
	assert_eq(recs.Outside.profile, "vx")
	assert_eq(recs.Outside.sheets.keys().size(), 3)
	assert_eq(recs.Outside.sheets.a1, assets + "/vxace/Tilesets/Outside_A1.png")
	assert_eq(recs.Inside.sheets.keys(), ["a5"])
	assert_true(str(p.warnings).contains("Castle.png"), "an unnamed sheet is reported")
	assert_true(str(p.warnings).contains("Your project uses the"), "the profile mismatch is reported: %s" % str(p.warnings))
	# Import everything except the faces and the Inside tileset.
	var files := []
	for f in p.files:
		if f.folder != "FaceSet":
			files.append(f.dst)
	var r := RMImportHelpers.apply(p, files, ["outside_2"])
	assert_eq(r.errors, [])
	assert_eq(r.copied.size(), files.size())
	assert_false(FileAccess.file_exists(assets + "/vxace/FaceSet/Actor1.png"), "unticked files are not copied")
	assert_eq(r.records_added, ["outside_2"])
	var manifest: Dictionary = RPGJson.load_or(assets + "/vxace/pack.json", {})
	assert_true(str(manifest.get("license", "")).contains("RPG Maker EULA"), str(manifest))
	assert_eq(manifest.get("profile"), "vx")
	var back: Array = RPGJson.load_or(proj + "/database/tilesets.json", {}).records
	assert_eq(back.size(), 2)
	assert_eq(back[1].sheets.b, assets + "/vxace/Tilesets/Outside_B.png")
	var built := RPGTilesetBuilder.load_record_images(back[1])
	assert_eq(built.missing, [], "the record points at the copied sheets")
	# Again: existing files are not overwritten without asking, and the tileset is not duplicated.
	var p2 := RMImportHelpers.plan(rtp, "vxace", assets, proj)
	assert_eq(p2.tilesets.size(), 1, "only Inside is new")
	var again := RMImportHelpers.apply(p2)
	assert_eq(again.conflicts.size(), files.size())
	assert_eq(again.copied.size(), 1, "only the face is new")
	assert_eq(RPGJson.load_or(proj + "/database/tilesets.json", {}).records.size(), 3)
	var forced := RMImportHelpers.apply(p2, [files[0]], [], [files[0]])
	assert_eq(forced.copied, [files[0]], "replacing happens only for the files the maker confirmed")
	assert_true(RMImportHelpers.describe(p2, again).contains("left unchanged"))
	_rm_tree(RM_TMP)


## MV/MZ data/Tilesets.json: one record per RPG Maker tileset (sheets shared between tilesets
## too) and RPG Maker's own passability written as tile settings.
func test_rm_import_mv_tilesets_json() -> void:
	_rm_tree(RM_TMP)
	var proj := _rm_project([])
	var assets := RM_TMP + "/assets"
	var mv := RM_TMP + "/MVProj"
	_rm_png(mv + "/img/tilesets/Outside_A1.png", 768, 576)
	_rm_png(mv + "/img/tilesets/Outside_A2.png", 768, 576)
	_rm_png(mv + "/img/tilesets/Outside_B.png", 768, 768)
	_rm_png(mv + "/img/tilesets/SF_Outside_B.png", 768, 768)
	var flags := []
	flags.resize(8192)
	flags.fill(0)
	flags[0] = 0x10            # B 0: star
	flags[1] = 0x0f            # B 1: blocks every way
	flags[2] = 0x01 | 0x40     # B 2: blocks moving down, bush
	flags[2048] = 0x0f         # A1 kind 0 (sea)
	flags[2816 + 48] = 0x3000  # A2 kind 1: passable, terrain tag 3
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mv + "/data"))
	var f := FileAccess.open(mv + "/data/Tilesets.json", FileAccess.WRITE)
	f.store_string(JSON.stringify([null,
		{"id": 1, "name": "Outside", "mode": 1, "tilesetNames": ["Outside_A1", "Outside_A2", "", "", "", "Outside_B", "", "", ""], "flags": flags},
		{"id": 2, "name": "SF Outside", "mode": 1, "tilesetNames": ["Outside_A1", "", "", "", "", "SF_Outside_B", "", "", ""], "flags": flags}]))
	f.close()
	var p := RMImportHelpers.plan(mv, "mvp", assets, proj)
	assert_eq(p.tilesets.size(), 2, "one record per RPG Maker tileset")
	assert_eq(p.tilesets[1].record.id, "sf_outside")
	assert_eq((p.tilesets[1].record.sheets as Dictionary).keys(), ["a1", "b"], "SF Outside shares Outside_A1")
	var r := RMImportHelpers.apply(p)
	assert_eq(r.errors, [])
	var ov: Dictionary = RPGJson.load_or(proj + "/tileset_overrides/outside.json", {})
	var t: Dictionary = ov.get("tiles", {})
	assert_eq(t.get("b_0"), {"passage": 15, "flags": RPGMovement.FLAG_STAR, "terrain": 0})
	assert_eq(t.get("b_1"), {"passage": 0, "flags": 0, "terrain": 0})
	assert_eq(t.get("b_2"), {"passage": 14, "flags": RPGMovement.FLAG_BUSH, "terrain": 0}, "MV down bit = RPG Kit down bit")
	assert_eq(t.get("a1_0").passage, 0, "the sea blocks walking")
	assert_eq(t.get("a2_1"), {"passage": 15, "flags": 0, "terrain": 3})
	assert_false(t.has("c_0"), "no settings for sheets the tileset doesn't use")
	var built := RPGTilesetBuilder.build_with_report(p.tilesets[0].record, ov)
	assert_eq(built.errors, [])
	assert_eq(built.review, [], "nothing left to guess")
	_rm_tree(RM_TMP)


func test_rm_import_rm2k_mv_xp_and_unknown() -> void:
	_rm_tree(RM_TMP)
	var proj := _rm_project([])
	var assets := RM_TMP + "/assets"
	# 2000/2003: BMP ChipSet converted to PNG, one tileset record per ChipSet.
	var k2 := RM_TMP + "/RPG2000/RTP"
	_rm_bmp(k2 + "/ChipSet/World.bmp", 480, 256)
	_rm_png(k2 + "/CharSet/Hero.png", 288, 256)
	_rm_bytes(k2 + "/Sound/Cursor.wav")
	_rm_midi(k2 + "/Music/Field.mid")
	_rm_bytes(k2 + "/Music/Broken.mid")
	_rm_bytes(k2 + "/Picture/Map.xyz")
	var p := RMImportHelpers.plan(k2, "rm2k_rtp", assets, proj)
	assert_eq(p.profile, "rm2k")
	assert_eq(p.files.size(), 4, "the MIDI song is copied with the rest")
	assert_eq(p.skipped.size(), 2, "the unreadable MIDI file and the XYZ image are reported, not copied")
	assert_eq(p.tilesets.size(), 1)
	assert_eq(p.tilesets[0].record, {"id": "world", "name": "World", "notes": "Imported from an RPG Maker folder (pack 'rm2k_rtp').", "custom": {}, "profile": "rm2k", "sheet": assets + "/rm2k_rtp/ChipSet/World.png"})
	assert_eq(p.tilesets[0].warning, "", "480x256 fits the 2000/2003 ChipSet decoder")
	var r := RMImportHelpers.apply(p)
	assert_eq(r.errors, [])
	var img := Image.load_from_file(ProjectSettings.globalize_path(assets + "/rm2k_rtp/ChipSet/World.png"))
	assert_true(img != null and img.get_size() == Vector2i(480, 256), "the BMP became a PNG")
	assert_eq(RPGChipset2k.validate(RPGTilesetBuilder.load_sheet_image(assets + "/rm2k_rtp/ChipSet/World.png")), [])
	# MV / MZ: img/ and audio/, lower-case folders, M4A skipped.
	var mv := RM_TMP + "/MyMVGame"
	_rm_png(mv + "/img/tilesets/World_A1.png", 768, 576)
	_rm_png(mv + "/img/tilesets/World_B.png", 768, 768)
	_rm_png(mv + "/img/characters/Actor1.png", 576, 384)
	_rm_bytes(mv + "/audio/se/Cursor1.ogg")
	_rm_bytes(mv + "/audio/se/Cursor1.m4a")
	var pm := RMImportHelpers.plan(mv + "/img", "mv_game", assets, proj)
	assert_eq(pm.profile, "mv")
	assert_eq(pm.files.size(), 4)
	assert_eq(pm.skipped.size(), 1)
	assert_eq(pm.tilesets.size(), 1)
	assert_eq(pm.tilesets[0].record.profile, "mv")
	assert_eq(pm.tilesets[0].warning, "", "MV sheet sizes match the decoder")
	# XP: Autotiles folder; tilesets get an empty autotile list.
	var xp := RM_TMP + "/XPGame"
	_rm_png(xp + "/Graphics/Autotiles/Water.png", 96, 128)
	_rm_png(xp + "/Graphics/Tilesets/001-Grassland01.png", 256, 512)
	var px := RMImportHelpers.plan(xp, "xp_game", assets, proj)
	assert_eq(px.profile, "xp")
	assert_eq(px.tilesets.size(), 1)
	assert_eq(px.tilesets[0].record.sheet, assets + "/xp_game/Tilesets/001-Grassland01.png")
	assert_eq(px.tilesets[0].record.autotiles, [])
	assert_eq(px.tilesets[0].record.id, "tileset_001_grassland_01")
	# Not an RPG Maker folder, or a bad pack name: nothing to import.
	DirAccess.make_dir_recursive_absolute(RM_TMP + "/Photos")
	var none := RMImportHelpers.plan(RM_TMP + "/Photos", "photos", assets, proj)
	assert_eq(none.profile, "")
	assert_true(none.warnings.size() >= 1)
	assert_eq(RMImportHelpers.apply(none).copied, [])
	assert_eq(RMImportHelpers.plan(k2, "Bad Name", assets, proj).files, [])
	_rm_tree(RM_TMP)


func test_rm_import_preview_dialog() -> void:
	_rm_tree(RM_TMP)
	_rm_png(RM_TMP + "/Ace/Graphics/Tilesets/Dungeon_A2.png", 512, 384)
	_rm_png(RM_TMP + "/Ace/Graphics/Characters/Monster.png", 384, 256)
	var w := RPGToolsWindow.new()
	w.setup(data, registry)
	tree.root.add_child(w)
	var dlg := w.open_rm_import(RM_TMP + "/Ace")
	await tree.process_frame
	assert_false(dlg.get_ok_button().disabled, "a valid folder can be imported")
	var t: Tree = null
	for n in dlg.find_children("*", "Tree", true, false):
		t = n
	assert_true(t != null)
	if t != null:
		var tops := []
		for it in t.get_root().get_children():
			tops.append(it.get_text(0))
		assert_eq(tops, ["Files to copy (2)", "Tileset records (1)"])
		var files := []
		var ids := []
		w._collect_checked(t.get_root(), files, ids)
		assert_eq(files.size(), 2)
		assert_eq(ids, ["dungeon"])
		w._set_checked_down(t.get_root().get_child(0), false)
		files.clear()
		ids.clear()
		w._collect_checked(t.get_root(), files, ids)
		assert_eq(files, [], "unticking a group unticks its files")
	w.free()
	_rm_tree(RM_TMP)


# --- Editor QA pass (2026-11-10), EDITOR_GAPS.md --------------------------------------------------

## E40: the default vehicle sheet is used by the vehicles even when System doesn't name it.
func test_vehicle_sheet_is_not_unused() -> void:
	assert_true(DeployHelpers.runtime_names(data).has("vehicles"))
	assert_false(DeployHelpers.unused_asset_excludes(data).has("res://assets/starter/CharSet/vehicles.png"))


## E40 / E39: no export preset says what to do; New command keeps the dialog open on a bad ID.
func test_deploy_without_presets_and_new_command_errors() -> void:
	var w := RPGToolsWindow.new()
	w.presets_path = "user://rpg_no_presets_here.cfg"
	w.setup(data, registry)
	tree.root.add_child(w)
	assert_true(w.deploy_status.text.contains("Project > Export"), w.deploy_status.text)
	w.start_build()
	assert_true(w.deploy_status.text.contains("Project > Export"))
	w._new_command_dialog()
	var dlg: ConfirmationDialog = null
	for c in w.get_children():
		if c is ConfirmationDialog:
			dlg = c
	assert_true(dlg != null, "the New command dialog")
	if dlg != null:
		dlg.confirmed.emit()
		assert_false(dlg.is_queued_for_deletion(), "an empty ID keeps the dialog open")
		var texts := []
		for l in dlg.find_children("*", "Label", true, false):
			texts.append(l.text)
		assert_true(texts.any(func(t): return str(t).contains("ID for the command")), str(texts))
	w.free()


## E21 (shared walker): a command inside Show Choices is visited once, so export checks don't
## count it twice.
func test_registry_walk_visits_choice_branches_once() -> void:
	var list := [{"type": "show_choices", "choices": [{"label": "Sure!", "then": [{"type": "set_switch", "id": "s", "value": true}]}, {"label": "No", "then": []}]}]
	var seen := []
	registry.walk(list, func(c, _p): seen.append(c.type))
	assert_eq(seen, ["show_choices", "set_switch"])
