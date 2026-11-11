extends "res://tests/rpg_test_case.gd"
## The kit plugins of the first wave (addons/rpg/extensions): menu_plus (W1), message_plus (W2),
## letter_sounds (W3), gab (W5) and save_plus (W8). Each is off until a project enables it; each
## feature is checked on the sample project, including what is saved with the game.

const Env := preload("res://tests/rpg_test_env.gd")
const OPTIONS_FILE := "user://rpg_options.json"
const WIN_SCENE := "res://tests/fixtures/extensions/probe/win_scene.gd"
const PLUGINS := ["menu_plus", "message_plus", "letter_sounds", "gab", "save_plus"]
const PLUGIN_COMMANDS := ["menu_entry_access", "message_style", "letter_sound_settings", "show_gab", "clear_gabs", "wait_for_gabs", "set_save_description", "request_autosave", "change_autosave"]
## save_plus tests use their own slots so a player's saves are never touched.
const SLOTS := 95
const TEST_SLOT := 94

var env
var _backups := {}


func before_each() -> void:
	for path in [OPTIONS_FILE, _slot(SLOTS), _slot(TEST_SLOT)]:
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


static func _slot(n: int) -> String:
	return "user://saves/slot_%02d.json" % n


## The sample project with these kit plugins on, and settings for this run.
func plugin_env(ids: Array, settings: Dictionary = {}) -> void:
	env = Env.create(tree, "res://rpg")
	var pj: Dictionary = env.rpg.data.project
	pj["extensions"] = ["project"] + ids
	pj["disabled_extensions"] = []
	env.rpg.reload_extensions(settings)


func on_map() -> void:
	env.game.new_game()
	await env.settle()


func _menu() -> Node:
	env.game.open_menu()
	await frames(2)
	return env.rpg.ui.scene_stack[-1]


## Lets the typewriter run until the page is fully shown.
func type_out(box: Node, params: Dictionary) -> void:
	env.rpg.ui.auto_advance = false
	box.open_text(params)
	for i in 600:
		await frames(1)
		if box._text_done():
			break
	box._finish_text()
	env.rpg.ui.auto_advance = true


# --- off by default ------------------------------------------------------------------------------

func test_plugins_are_off_by_default() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	for id in PLUGINS:
		assert_true(rpg.extension(id) == null, "%s not running" % id)
		assert_false(rpg.extension_enabled(id))
	for t in PLUGIN_COMMANDS:
		assert_false(rpg.registry.has_command(t), "%s not offered" % t)
	assert_true(rpg.extensions.option_rows().is_empty(), "no extra option rows")
	assert_eq(rpg.saves.slot_count(), RPGSaveService.MAX_SLOTS)
	assert_false(rpg.saves.autosave_labelled)
	assert_eq(RPGText.expand("\\{x<b>y</b>\\M[a]", rpg).bbcode, "\\{x<b>y</b>\\M[lb]a]", "codes are plain text without the plugin")
	await on_map()
	var menu: Node = await _menu()
	assert_eq(menu.command_ids(), menu.COMMANDS)
	assert_true(env.game.get("_overlays").is_empty(), "no overlay layers made")


# --- W1 menu_plus --------------------------------------------------------------------------------

const MENU_SETTINGS := {"menu_plus": {
	"order": [{"id": "status"}],
	"hidden": [{"id": "save"}],
	"entries": [{"id": "rest", "label": "Rest", "common_event": "full_heal", "after": "item", "icon": null, "scene": "", "show_switch": "", "enable_switch": ""}],
	"skip_single_actor": true,
	"option_rows": [
		{"key": "hints", "label": "Hints", "kind": "bool", "default": "true", "switch": "key_given"},
		{"key": "difficulty", "label": "Difficulty", "kind": "choice", "choices": "Easy, Normal, Hard", "default": "Normal", "variable": "talks"},
		{"key": "speed", "label": "Speed", "kind": "slider", "min": 0, "max": 50, "step": 10, "default": "20"},
	],
}}


func test_w1_menu_layout_entries_and_single_actor() -> void:
	plugin_env(["menu_plus"], MENU_SETTINGS)
	await on_map()
	var menu: Node = await _menu()
	assert_eq(menu.command_ids(), ["status", "item", "rest", "skill", "equip", "options", "game_end"])
	assert_eq(str(menu.menu_items[2].label), "Rest")
	# Party of one: Equip opens for the hero without choosing.
	await menu.choose("equip")
	assert_eq(menu.mode, "equip_slots")
	menu.close()
	await frames(2)
	# The extra entry runs its common event once the menu has closed.
	var hero: Object = env.rpg.state.actor("hero")
	hero.set_resource("hp", 1)
	menu = await _menu()
	await menu.choose("rest")
	await env.settle()
	assert_false(env.rpg.ui.scene_open())
	assert_eq(hero.get_resource("hp"), env.rpg.rules.max_resource(hero, "hp"), "Full heal ran")


func test_w1_change_menu_entry_command_is_saved() -> void:
	plugin_env(["menu_plus"], MENU_SETTINGS)
	await on_map()
	await env.rpg.run_commands([
		{"type": "menu_entry_access", "entry": "skill", "visible": "hide", "enabled": "keep"},
		{"type": "menu_entry_access", "entry": "save", "visible": "show", "enabled": "disable"},
	])
	var menu: Node = await _menu()
	var ids: Array = menu.command_ids()
	assert_false(ids.has("skill"), "hidden by the event")
	assert_true(ids.has("save"), "shown again by the event")
	assert_false(menu.menu_items[ids.find("save")].enabled, "but greyed out")
	menu.close()
	await frames(2)
	var r: RPGResult = env.rpg.saves.save(TEST_SLOT)
	assert_true(r.is_ok(), str(r))
	env.game.new_game()
	await env.settle()
	menu = await _menu()
	assert_true(menu.command_ids().has("skill"), "a new game starts as set up")
	menu.close()
	await frames(2)
	r = await env.rpg.saves.load_slot(TEST_SLOT)
	assert_true(r.is_ok(), str(r))
	menu = await _menu()
	assert_false(menu.command_ids().has("skill"), "the load brings the change back")


func test_w1_extra_option_rows_mirror_into_switch_and_variable() -> void:
	plugin_env(["menu_plus"], MENU_SETTINGS)
	await on_map()
	assert_true(env.rpg.get_switch("key_given"), "Hints ON by default, copied into the switch")
	assert_eq(env.rpg.get_variable("talks"), 1, "Normal is choice 1")
	var opts: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("options"))
	await frames(2)
	assert_has(opts.rows, "menu_plus.hints")
	assert_has(opts.rows, "menu_plus.speed")
	opts.list.select(opts.rows.find("menu_plus.hints"))
	opts.handle_action("ok")
	assert_false(env.rpg.get_switch("key_given"), "turned off from the options")
	opts.list.select(opts.rows.find("menu_plus.difficulty"))
	opts.handle_action("right")
	assert_eq(env.rpg.get_variable("talks"), 2, "Hard")
	opts.list.select(opts.rows.find("menu_plus.speed"))
	opts.handle_action("left")
	assert_eq(int(env.rpg.option("menu_plus", "speed")), 10)
	opts.finish()
	await frames(2)
	assert_eq(RPGJson.load_or(OPTIONS_FILE, {}).get("menu_plus.difficulty"), "Hard")


# --- W2 message_plus -----------------------------------------------------------------------------

const MSG_SETTINGS := {"message_plus": {
	"keywords": [{"word": "Crystal", "colour": [255, 0, 0, 255]}],
	"macros": [{"name": "town", "text": "\\C[2]Oakvale\\C[0]"}],
	"name_box": "right",
}}


func test_w2_word_wrap_setting_tags_and_command() -> void:
	plugin_env(["message_plus"], MSG_SETTINGS)
	var rpg: Node = env.rpg
	assert_eq(RPGText.expand("one\ntwo", rpg).bbcode, "one\ntwo", "off: lines as typed")
	assert_eq(RPGText.expand("<wordwrap>one\ntwo<br>three", rpg).bbcode, "one two\nthree", "per message on")
	await on_map()
	await rpg.run_commands([{"type": "message_style", "word_wrap": "on", "name_box": "keep"}])
	assert_eq(RPGText.expand("one\ntwo", rpg).bbcode, "one two", "on for the game")
	assert_eq(RPGText.expand("<nowrap>one\ntwo", rpg).bbcode, "one\ntwo", "per message off")
	# Saved with the game.
	assert_true(rpg.saves.save(TEST_SLOT).is_ok())
	env.game.new_game()
	await env.settle()
	assert_eq(RPGText.expand("a\nb", rpg).bbcode, "a\nb", "new game: as set up")
	assert_true((await rpg.saves.load_slot(TEST_SLOT)).is_ok())
	assert_eq(RPGText.expand("a\nb", rpg).bbcode, "a b", "load: the command's choice")


func test_w2_font_size_bold_italic_keywords_and_macros() -> void:
	plugin_env(["message_plus"], MSG_SETTINGS)
	var rpg: Node = env.rpg
	assert_eq(RPGText.expand("\\{Big\\}n", rpg).bbcode, "[font_size=13]Big[/font_size]n")
	assert_eq(RPGText.expand("\\FS[20]x\\FS[]y", rpg).bbcode, "[font_size=20]x[/font_size]y")
	assert_eq(RPGText.expand("<b>B</b><i>I</i>", rpg).bbcode, "[b]B[/b][i]I[/i]")
	assert_eq(RPGText.expand("the crystal glows", rpg).bbcode, "the [color=#ff0000]crystal[/color] glows", "keyword, any case")
	assert_eq(RPGText.expand("crystals", rpg).bbcode, "crystals", "whole words only")
	assert_eq(RPGText.expand("\\M[TOWN]!", rpg).bbcode, "[color=#%s]Oakvale[/color]!" % RPGText.PALETTE[2].to_html(false), "macro with codes")
	assert_eq(RPGText.expand("\\N[hero]", rpg).bbcode, "Alex", "names untouched without the actor setting")
	assert_eq(RPGText.expand_plain("Take the \\{Crystal", rpg), "Take the Crystal", "choice labels drop the formatting")


func test_w2_actor_names_coloured_when_set() -> void:
	plugin_env(["message_plus"], {"message_plus": {"colour_actor_names": true, "actor_colour": [0, 255, 0, 255]}})
	assert_eq(RPGText.expand("Hi \\N[hero], Alex!", env.rpg).bbcode, "Hi [color=#00ff00]Alex[/color], [color=#00ff00]Alex[/color]!")


func test_w2_name_box_position_and_fonts() -> void:
	plugin_env(["message_plus"], MSG_SETTINGS)
	var box: Node = env.rpg.ui.message_box
	box.open_text({"text": "Hello", "name": "Alex"})
	await frames(1)
	assert_true(box.name_label.position.x > 200, "right: %s" % box.name_label.position.x)
	var np: Node = box.panel.get_node_or_null("NameBox")
	assert_true(np != null and np.visible, "a window behind the name")
	assert_true(box.text_label.has_theme_font_override("bold_font"), "bold font made")
	box.open_text({"text": "\\NB[center]Hi", "name": "Alex"})
	await frames(1)
	var x: float = box.name_label.position.x
	assert_true(x > 100 and x < 200, "centre for this message: %s" % x)
	box.open_text({"text": "Hi", "name": "Alex"})
	await frames(1)
	assert_true(box.name_label.position.x > 200, "the next message uses the setting again")


# --- W3 letter_sounds ----------------------------------------------------------------------------

const LS_SETTINGS := {"letter_sounds": {"interval": 2, "silent_chars": " .,!?", "pitch_variance": 10, "volume_variance": 10}}


func test_w3_blips_every_n_letters_skip_silent_and_instant() -> void:
	plugin_env(["letter_sounds"], LS_SETTINGS)
	var ls: Object = env.rpg.extension("letter_sounds")
	var box: Node = env.rpg.ui.message_box
	await type_out(box, {"text": "Hello there."})
	assert_eq(ls.played.size(), 5, "10 letters, every 2nd, space and dot silent")
	assert_eq(str(ls.played[0].file), "", "built-in blip")
	var pitches: Array = ls.played.map(func(p): return snappedf(float(p.pitch_scale), 0.0001))
	assert_true(pitches.all(func(p): return p >= 0.9 and p <= 1.1), str(pitches))
	# Shown at once (auto advance / OK): no sound.
	ls.played.clear()
	box.open_text({"text": "Skipped text"})
	await frames(2)
	assert_eq(ls.played.size(), 0)


func test_w3_codes_actor_sound_option_and_command() -> void:
	plugin_env(["letter_sounds"], LS_SETTINGS)
	var ls: Object = env.rpg.extension("letter_sounds")
	var box: Node = env.rpg.ui.message_box
	# \LS[off] silences from that point, \LS[on] resumes.
	await type_out(box, {"text": "ab\\LS[off]cdef\\LS[on]gh"})
	assert_eq(ls.played.size(), 2, "a and g: %s" % str(ls.played))
	# The speaking actor's own sound (custom field), found by the face.
	var rec: Dictionary = env.rpg.data.record("actors", "hero")
	var had: Variant = rec.get("custom")
	rec["custom"] = {"letter_sound": {"file": "cursor", "volume": 50, "pitch": 150}}
	ls.played.clear()
	await type_out(box, {"text": "abc", "face": {"sheet": "hero_face", "index": 0}})
	assert_eq(str(ls.played[0].file), "cursor", "hero's sound")
	assert_true(float(ls.played[0].pitch_scale) > 1.3)
	assert_eq(ls.speaker_actor({"name": "Alex"}), "hero", "found by name too")
	rec["custom"] = had
	# The player's option turns it off.
	env.rpg.extensions.set_option("letter_sounds.enabled", false)
	ls.played.clear()
	await type_out(box, {"text": "abcdef"})
	assert_eq(ls.played.size(), 0, "option off")
	env.rpg.extensions.set_option("letter_sounds.enabled", true)
	# Change letter sound (saved): off for the game, then a sound and interval.
	await on_map()
	await env.rpg.run_commands([{"type": "letter_sound_settings", "enabled": "off", "sound_mode": "keep", "interval": 0}])
	ls.played.clear()
	await type_out(box, {"text": "abcdef"})
	assert_eq(ls.played.size(), 0, "turned off by an event")
	await env.rpg.run_commands([{"type": "letter_sound_settings", "enabled": "on", "sound_mode": "set", "sound": {"file": "decision", "volume": 40, "pitch": 100}, "interval": 3}])
	assert_true(env.rpg.saves.save(TEST_SLOT).is_ok())
	env.game.new_game()
	await env.settle()
	assert_true(ls.section("letter_sounds").is_empty(), "new game: as set up")
	assert_true((await env.rpg.saves.load_slot(TEST_SLOT)).is_ok())
	ls.played.clear()
	await type_out(box, {"text": "abcdef"})
	assert_eq(ls.played.size(), 2, "every 3rd letter after the load")
	assert_eq(str(ls.played[0].file), "decision")


func test_w3_option_row_and_custom_field_are_declared() -> void:
	plugin_env(["letter_sounds"])
	var rows: Array = env.rpg.extensions.option_rows()
	assert_eq(rows.map(func(r): return r.id), ["letter_sounds.enabled"])
	var cf: Dictionary = env.rpg.registry.merged_custom_fields({})
	assert_true(cf.get("actors", []).any(func(f): return str(f.key) == "letter_sound"))


# --- W5 gab --------------------------------------------------------------------------------------

func test_w5_gabs_queue_fade_and_do_not_block() -> void:
	plugin_env(["gab"], {"gab": {"base_seconds": 1.0, "per_char": 0.0, "fade": 0.2}})
	await on_map()
	var g: Object = env.rpg.extension("gab")
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "show_gab", "text": "Brr, it's cold.", "name": "Alex", "switch": "key_given"},
		{"type": "show_gab", "text": "Second"},
		{"type": "show_gab", "text": "Second"},
		{"type": "set_variable", "id": "talks", "operation": "set", "value": 5},
	])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.get_variable("talks"), 5, "the event went on at once")
	assert_false(env.rpg.scheduler.is_main_busy(), "nothing waits for the gab")
	assert_true(env.game.player.input_allowed(), "the player can move")
	assert_eq(str(g.current.text), "Brr, it's cold.")
	assert_eq(g.queue.size(), 1, "anti-repeat skipped the duplicate")
	var w: Panel = g.window()
	assert_true(w != null and w.get_parent() == env.rpg.map_overlay_layer("hud"), "on the hud layer")
	assert_true(w.position.y < 40, "top strip")
	# Time passes: fade in, stay, fade out, then the next one.
	g._process(0.25)
	g._process(1.05)
	g._process(0.25)
	assert_true(env.rpg.get_switch("key_given"), "switch turned on when it faded")
	assert_eq(str(g.current.get("text", "")), "Second")
	g._process(0.25)
	g._process(1.05)
	g._process(0.25)
	assert_false(g.is_busy())
	assert_eq(g.shown_log, ["Brr, it's cold.", "Second"])


func test_w5_wait_and_clear_commands_and_battle_layer() -> void:
	plugin_env(["gab"], {"gab": {"base_seconds": 0.3, "per_char": 0.0, "fade": 0.05, "position": "bottom"}})
	await on_map()
	var g: Object = env.rpg.extension("gab")
	var started := Time.get_ticks_msec()
	var r: RPGResult = await env.rpg.run_commands([{"type": "show_gab", "text": "Wait for me"}, {"type": "wait_for_gabs"}])
	assert_true(r.is_ok())
	assert_false(g.is_busy(), "Wait for gabs returned after the gab")
	assert_true(Time.get_ticks_msec() - started >= 300, "it really waited")
	g.show_gab("one")
	g.show_gab("two")
	await env.rpg.run_commands([{"type": "clear_gabs"}])
	assert_false(g.is_busy())
	await frames(1)
	assert_true(g.window() == null)
	# Battle code calls the API; the strip draws above the battle scene (a UI scene).
	assert_true(g.show_gab("Ouch!"))
	var hud: Node = env.rpg.map_overlay_layer("hud")
	assert_true(hud.get_parent().layer > env.rpg.ui.layer, "above every UI scene, battles included")
	assert_true(g.window().position.y > 150, "bottom strip")
	# A new game clears gabs.
	env.game.new_game()
	await env.settle()
	assert_false(g.is_busy())


# --- W8 save_plus --------------------------------------------------------------------------------

const SAVE_SETTINGS := {"save_plus": {"max_slots": SLOTS, "on_transfer": true, "after_battle": true, "on_menu": false, "toast": true, "toast_text": "Autosaved", "player_option": true}}


func _wait_saved(reasons: Array, n: int) -> void:
	for i in 120:
		if reasons.size() >= n:
			return
		await frames(1)


func test_w8_slots_transfer_autosave_and_toast() -> void:
	plugin_env(["save_plus"], SAVE_SETTINGS)
	var rpg: Node = env.rpg
	assert_eq(rpg.saves.slot_count(), SLOTS)
	assert_eq(rpg.saves.autosave_slot(), SLOTS)
	assert_true(rpg.saves.is_autosave_slot(SLOTS), "the save screen calls it Auto")
	var reasons := []
	rpg.autosaved.connect(func(_s, ok, why): reasons.append([why, ok]))
	if FileAccess.file_exists(_slot(SLOTS)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot(SLOTS)))
	await on_map()
	await frames(5)
	assert_eq(reasons, [], "no autosave on the first map of a new game")
	var r: RPGResult = await env.game.transfer("field", Vector2i(3, 3), "down", "none", 8)
	assert_true(r.is_ok())
	await _wait_saved(reasons, 1)
	assert_eq(reasons, [["transfer", true]])
	assert_true(rpg.saves.exists(SLOTS))
	var sp: Object = rpg.extension("save_plus")
	assert_eq(sp.toasts_shown, 1)
	assert_true(sp.toast() != null and str(sp.toast().get_child(0).text) == "Autosaved", "toast on the hud layer")
	# The save screen lists the plugin's number of slots.
	var screen: Node = rpg.ui.open_scene(rpg.ui.scene_path("save"))
	screen.setup("load")
	await frames(1)
	assert_eq(screen.slot_count(), SLOTS)
	rpg.ui.close_scene(screen)


func test_w8_player_option_and_change_autosave_command() -> void:
	plugin_env(["save_plus"], SAVE_SETTINGS)
	var rpg: Node = env.rpg
	var reasons := []
	rpg.autosaved.connect(func(_s, ok, why): reasons.append([why, ok]))
	await on_map()
	assert_has(rpg.extensions.option_rows().map(func(x): return x.id), "save_plus.autosave")
	rpg.extensions.set_option("save_plus.autosave", false)
	await env.game.transfer("field", Vector2i(3, 3), "down", "none", 8)
	await frames(10)
	assert_eq(reasons, [], "the player turned autosave off")
	rpg.extensions.set_option("save_plus.autosave", true)
	await rpg.run_commands([{"type": "change_autosave", "enabled": false}])
	await env.game.transfer("town", Vector2i(14, 12), "down", "none", 8)
	await frames(10)
	assert_eq(reasons, [], "an event turned autosave off")
	await rpg.run_commands([{"type": "change_autosave", "enabled": true}, {"type": "request_autosave"}])
	await _wait_saved(reasons, 1)
	assert_eq(reasons, [["event", true]], "Request autosave after the event")
	# Without the player option setting, there is no options row.
	await env.destroy()
	plugin_env(["save_plus"], {"save_plus": {"player_option": false, "max_slots": SLOTS}})
	assert_false(env.rpg.extensions.option_rows().map(func(x): return x.id).has("save_plus.autosave"))


func test_w8_after_battle_and_menu_autosave() -> void:
	var s: Dictionary = SAVE_SETTINGS.duplicate(true)
	s.save_plus.on_menu = true
	plugin_env(["save_plus"], s)
	var rpg: Node = env.rpg
	var reasons := []
	rpg.autosaved.connect(func(_s, ok, why): reasons.append([why, ok]))
	await on_map()
	await rpg.run_commands([{"type": "battle", "troop": "slimes", "scene": WIN_SCENE, "can_escape": true, "can_lose": true}])
	await _wait_saved(reasons, 1)
	assert_eq(reasons, [["battle", true]])
	env.game.open_menu()
	await frames(2)
	assert_eq(reasons.size(), 2)
	assert_eq(reasons[-1], ["menu", true], "autosaved as the menu opened")


func test_w8_save_description_in_header_and_slot() -> void:
	plugin_env(["save_plus"], SAVE_SETTINGS)
	var rpg: Node = env.rpg
	await on_map()
	await rpg.run_commands([{"type": "set_save_description", "text": "Chapter 2"}])
	assert_true(rpg.saves.save(TEST_SLOT).is_ok())
	var info: Dictionary = rpg.saves.describe(TEST_SLOT)
	assert_eq(str(info.header.get("description", "")), "Chapter 2")
	# The description is part of the game: a load brings it back for later saves.
	env.game.new_game()
	await env.settle()
	assert_eq(rpg.saves.build_save().header, {}, "new game: no description")
	assert_true((await rpg.saves.load_slot(TEST_SLOT)).is_ok())
	assert_eq(rpg.saves.build_save().header, {"description": "Chapter 2"})
	await rpg.run_commands([{"type": "set_save_description", "text": ""}])
	assert_eq(rpg.saves.build_save().header, {}, "empty text removes it")


func test_w8_turning_the_plugin_off_restores_the_save_service() -> void:
	plugin_env(["save_plus"], SAVE_SETTINGS)
	assert_eq(env.rpg.saves.slot_count(), SLOTS)
	env.rpg.data.project["extensions"] = ["project"]
	env.rpg.reload_extensions()
	await frames(2)
	assert_eq(env.rpg.saves.slot_count(), RPGSaveService.MAX_SLOTS)
	assert_false(env.rpg.saves.autosave_labelled)
	assert_true(env.rpg.saves.header_providers.is_empty())
