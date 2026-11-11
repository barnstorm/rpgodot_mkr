extends "res://tests/rpg_test_case.gd"
## Engine bugs found by the human-style QA playthrough of Murder at Moonveil Manor (an RPG Maker
## MV RTP project): see moonveil/GAPS.md section G. One test per finding, named after it.

const Env := preload("res://tests/rpg_test_env.gd")
const UIScreen := preload("res://addons/rpg/runtime/ui/rpg_ui_screen.gd")
const Audio := preload("res://addons/rpg/runtime/rpg_audio.gd")
const Shop := preload("res://addons/rpg/runtime/ui/shop_screen.gd")
const RMImport := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")

var env
var _slot_files := []


func before_each() -> void:
	env = Env.create(tree, "res://rpg")


func after_each() -> void:
	for a in ["rpg_up", "rpg_down", "rpg_left", "rpg_right", "rpg_ok", "rpg_cancel"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	for p in _slot_files:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_slot_files.clear()
	await env.destroy()


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


# --- G1: MV wall tops block their outer edges ---------------------------------------------------

func test_g1_importer_marks_mv_wall_tops_edge_blocking() -> void:
	var flags := []
	flags.resize(5888 + 48 * 3)
	flags.fill(0)
	for s in 48:
		flags[5888 + s] = 0                       # a4_0: a floor-like kind, open on every shape
		flags[5888 + 48 + s] = 0 if s < 32 else (6 if s < 47 else 15)   # a4_1: a wall top
	var out: Dictionary = RMImport.mv_flags_to_tiles(flags, ["a4"])
	assert_eq(int(out["a4_0"].flags) & RPGTilesetBuilder.FLAG_EDGE, 0, "same passage on every shape: no edge flag")
	assert_ne(int(out["a4_1"].flags) & RPGTilesetBuilder.FLAG_EDGE, 0, "wall top: edge-blocking")
	assert_eq(int(out["a4_1"].passage), 15, "open inside, as MV's shape 0")


func test_g1_edge_blocking_tiles_close_their_outer_edges() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	for l in [["passage", TYPE_INT], ["flags", TYPE_INT], ["tile_key", TYPE_STRING]]:
		ts.add_custom_data_layer()
		ts.set_custom_data_layer_name(ts.get_custom_data_layers_count() - 1, l[0])
		ts.set_custom_data_layer_type(ts.get_custom_data_layers_count() - 1, l[1])
	var src := TileSetAtlasSource.new()
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src, 0)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	var floor_td := src.get_tile_data(Vector2i(0, 0), 0)
	floor_td.set_custom_data("passage", 15)
	floor_td.set_custom_data("tile_key", "floor")
	var wall_td := src.get_tile_data(Vector2i(1, 0), 0)
	wall_td.set_custom_data("passage", 15)
	wall_td.set_custom_data("flags", RPGMovement.FLAG_EDGE)
	wall_td.set_custom_data("tile_key", "a4_7")
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	for y in 4:
		for x in 5:
			layer.set_cell(Vector2i(x, y), 0, Vector2i(1, 0) if y == 1 and x >= 1 and x <= 3 else Vector2i(0, 0))
	var fake := GDScript.new()
	fake.source_code = "extends Node\nvar tile_layers := []\nvar size := Vector2i(5, 4)\nvar scroll_type := \"none\"\n"
	fake.reload()
	var map: Node = fake.new()
	map.tile_layers = [layer]
	var mov := RPGMovement.new(map)
	var lr: int = RPGMovement.BIT.left | RPGMovement.BIT.right
	assert_eq(mov.passage(Vector2i(2, 1)), lr, "a wall-top line: open along it, closed above and below")
	assert_eq(mov.passage(Vector2i(1, 1)), RPGMovement.BIT.right, "its left end is closed on the left too")
	assert_eq(mov.passage(Vector2i(2, 0)), 15, "plain floor is unaffected")
	map.free()
	layer.free()


# --- G2/G21: big faces fit their slot -------------------------------------------------------------

func test_g2_a_144px_face_fits_a_48px_slot() -> void:
	var holder := Control.new()
	tree.root.add_child(holder)
	var img := Image.create(144, 144, false, Image.FORMAT_RGBA8)
	var tr: TextureRect = UIScreen.face_rect(holder, ImageTexture.create_from_image(img), Vector2(4, 4), 48)
	await frames(1)
	assert_eq(tr.size, Vector2(48, 48), "MV face drawn at the slot size, not its own 144 px")
	assert_eq(tr.get_combined_minimum_size(), Vector2(48, 48))
	holder.queue_free()


# --- G3: a screen closing itself after its host freed it -----------------------------------------

func test_g3_close_scene_accepts_a_freed_screen() -> void:
	var n := Control.new()
	env.rpg.ui.root.add_child(n)
	env.rpg.ui.scene_stack.append(n)
	n.free()
	env.rpg.ui.close_scene(n)
	assert_false(env.rpg.ui.scene_open(), "no stale entry left")


# --- G15: jingles play once ------------------------------------------------------------------------

func test_g15_jingle_stream_does_not_loop() -> void:
	var ogg := AudioStreamOggVorbis.new()
	ogg.loop = true
	var j: AudioStream = Audio.jingle_stream(ogg)
	assert_false(j.loop, "an OGG jingle plays once, so 'wait' ends")
	assert_true(ogg.loop, "the cached music stream keeps looping for BGM use")
	var wav := AudioStreamWAV.new()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	assert_eq((Audio.jingle_stream(wav) as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED, "WAV as before")


# --- G16: the shop compares with the rule set's own stats ----------------------------------------

func test_g16_shop_compare_stat_follows_the_rules() -> void:
	var shop: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("shop"))
	await frames(1)
	assert_eq(shop.compare_stat("weapons"), "atk", "classic rules")
	assert_eq(shop.compare_stat("armors"), "pdef")
	var defn: Dictionary = env.rpg.rules.definition
	var saved_stats: Variant = defn.get("stats")
	defn["stats"] = [{"id": "str"}, {"id": "ac"}]
	assert_eq(shop.compare_stat("weapons"), "str", "a d20-style set without atk")
	assert_eq(shop.compare_stat("armors"), "ac")
	defn["stats"] = [{"id": "luck"}]
	assert_eq(shop.compare_stat("armors"), "", "nothing to compare: no error, no stat")
	defn["shop_compare"] = {"armors": "luck"}
	assert_eq(shop.compare_stat("armors"), "luck", "a rule set can name it")
	defn.erase("shop_compare")
	defn["stats"] = saved_stats
	assert_eq(Shop.dice_average("1d8"), 4.5)
	assert_eq(Shop.dice_average("2d6+1"), 8.0)
	assert_eq(Shop.dice_average(""), 0.0)
	env.rpg.ui.close_scene(shop)


# --- G17: Change State with the death state ------------------------------------------------------

func test_g17_change_state_knockout_zeroes_hp_and_revive_restores_one() -> void:
	var hero: RPGBattler = env.rpg.state.actor("hero")
	assert_true(hero.get_resource("hp") > 0)
	var r := await _run([{"type": "change_state", "target": "hero", "state": "knockout", "operation": "add"}])
	assert_true(r.is_ok(), str(r))
	assert_true(hero.has_state("knockout"))
	assert_eq(hero.get_resource("hp"), 0, "knocked out means 0 HP, as in battle")
	r = await _run([{"type": "change_state", "target": "hero", "state": "knockout", "operation": "remove"}])
	assert_false(hero.has_state("knockout"))
	assert_eq(hero.get_resource("hp"), 1, "back up with 1 HP")


# --- G18: save slots show what was saved ---------------------------------------------------------

func test_g18_save_slot_describes_the_saved_names() -> void:
	await env.start_on("town", Vector2i(12, 8))
	await env.settle()
	var slot := 14
	_slot_files.append(env.rpg.saves.slot_path(slot))
	var hero: RPGBattler = env.rpg.state.actor("hero")
	var before := hero.name
	assert_true(env.rpg.saves.save(slot).is_ok())
	hero.name = "Renamed"
	var info: Dictionary = env.rpg.saves.describe(slot)
	assert_eq(info.members[0].name, before, "the slot keeps the name it was saved with")
	assert_eq(info.members[0].id, "hero")


# --- G19: codes in choice labels ------------------------------------------------------------------

func test_g19_choice_labels_expand_value_codes() -> void:
	env.rpg.state.set_variable("qa_n", 7) if env.rpg.state.has_method("set_variable") else null
	var name := RPGText._actor_name(env.rpg, "hero")
	var cur: String = env.rpg.data.currency()
	assert_eq(RPGText.expand_plain("Stay (20\\G)", env.rpg), "Stay (20%s)" % cur)
	assert_eq(RPGText.expand_plain("\\C[2]Ask \\N[hero]\\C[0]\\.", env.rpg), "Ask " + name, "formatting and waits dropped")
	assert_eq(RPGText.expand_plain("a \\\\ b", env.rpg), "a \\ b")


# --- G20: one currency ---------------------------------------------------------------------------

func test_g20_one_currency_everywhere() -> void:
	var sys: Dictionary = env.rpg.data.system
	var saved: Variant = sys.get("currency")
	sys["currency"] = "gp"
	assert_eq(env.rpg.data.currency(), "gp")
	assert_eq(RPGText.expand_plain("\\G", env.rpg), "gp", "messages")
	assert_true(env.rpg.rules.term("gold", [5]).contains("gp") or not env.rpg.rules.term("gold", [5]).contains("G"), "battle rewards: %s" % env.rpg.rules.term("gold", [5]))
	var menu: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("menu"))
	await frames(1)
	assert_eq(menu.currency(), "gp", "menu and shop")
	env.rpg.ui.close_scene(menu)
	sys["currency"] = saved


# --- G22: full-screen backgrounds reach the letterbox --------------------------------------------

func test_g22_visible_rect_covers_the_letterbox() -> void:
	var ui: Node = env.rpg.ui
	var saved: Transform2D = ui.transform
	# MV: 816x624 shows the 320x240 layout at 2.55x, 6 px bands above and below.
	ui.transform = Transform2D(0.0, Vector2(2.55, 2.55), 0.0, Vector2(0, 6))
	var r: Rect2 = ui.ui_visible_rect(Vector2(816, 624))
	assert_true(r.position.y < 0.0 and r.end.y > 240.0, "reaches into both bands: %s" % r)
	assert_eq(r.position.x, 0.0)
	assert_true(absf(r.size.x - 320.0) < 0.01, "full width")
	ui.transform = saved


# --- G23: Save in a menu opened by an event ------------------------------------------------------

func test_g23_event_menu_save_hands_over_to_the_save_screen() -> void:
	await env.start_on("town", Vector2i(12, 8))
	await env.settle()
	env.rpg.ui.auto_advance = false
	var done := {}
	var run := func():
		done.r = await _run([{"type": "open_menu"}])
	run.call()
	await frames(2)
	var menu: Node = env.rpg.ui.scene_stack[-1]
	assert_true(menu.opened_by_event, "the command marks its menu")
	assert_eq(menu.save_reason(), "", "Save is offered, not greyed out")
	menu.choose("save")
	await frames(2)
	assert_true(env.rpg.ui.pending_save_screen or env.rpg.ui.scene_open(), "the save screen is queued for the end of the event")
	for i in 60:
		if done.has("r"):
			break
		await frames(1)
	assert_true(done.has("r"), "the event finished")


# --- G24: an empty name is never accepted --------------------------------------------------------

func test_g24_cancel_on_an_empty_name_stays() -> void:
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("name_input"))
	await frames(1)
	var got := []
	node.finished.connect(func(n): got.append(n))
	node.cancelled.connect(func(n): got.append("cancelled"))
	node.start({"actor": "hero", "name": "Al", "max_length": 6}, {"rpg": env.rpg})
	for i in 3:
		node.handle_action("cancel")
	assert_eq(node.text, "")
	assert_eq(got, [], "cancel with nothing left doesn't leave the screen")
	node.confirm()
	assert_eq(got, [], "OK on an empty name is refused")
	env.rpg.ui.close_scene(node)


# --- G6: long labels shrink to fit ----------------------------------------------------------------

func test_g6_long_labels_shrink_instead_of_clipping() -> void:
	var menu: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("menu"))
	await frames(1)
	var l: Label = menu.make_label(menu, Vector2.ZERO, "Moonveil Manor, upper floor", 11, null, 60)
	assert_true(l.get_theme_font_size("font_size") < 11 or l.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "shrunk or ellipsized")
	var s: Label = menu.make_label(menu, Vector2.ZERO, "Hi", 11, null, 60)
	assert_eq(s.get_theme_font_size("font_size"), 11, "short text untouched")
	env.rpg.ui.close_scene(menu)


# --- G8: the battle cursor stays on the command after cancelling ----------------------------------

func test_g8_battle_cursor_stays_on_skill_after_cancel() -> void:
	var rpg: Node = env.rpg
	rpg.ui.auto_advance = false
	rpg.state.add_actor("mira")
	var run := func():
		await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), {"troop": "slimes", "can_escape": true, "can_lose": true, "background": ""}, {"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)
	run.call()
	var scene: Node = rpg.ui.scene_stack[-1]
	for i in 600:
		if scene.phase == "party":
			break
		await frames(1)
	scene.handle_action("ok")                 # Fight
	scene.handle_action("ok")                 # hero: Attack
	scene.handle_action("ok")                 # on the first slime
	assert_eq(scene.phase, "actor", "Mira's turn")
	scene.handle_action("down")
	scene.handle_action("ok")                 # Skill
	assert_eq(scene.phase, "skill")
	scene.handle_action("cancel")
	assert_eq(scene.phase, "actor")
	assert_eq(scene.cmd_list.index, 1, "still on Skill")
	scene.handle_action("cancel")             # back to the hero: a fresh turn starts on Attack
	assert_eq(scene.cmd_list.index, 0)
	scene._done = true
	rpg.ui.close_all()


# --- Editor QA E36: small tiles in a bigger-tiled project fill the screen ------------------------

func test_e36_small_tiles_are_zoomed_to_the_project_tile_size() -> void:
	await env.start_on("town", Vector2i(12, 8))
	var map: Node = env.game.map
	assert_eq(map.display_scale(), 1, "16 px tiles in a 16 px project")
	env.rpg.data.profile["tile_size"] = 48
	assert_eq(map.display_scale(), 3, "16 px starter tiles in an MV-style (48 px) project")
	map.player.setup_camera()
	assert_eq(map.player.camera.zoom, Vector2(3, 3), "the camera zooms to match")
	env.rpg.data.profile["tile_size"] = 16
	map.player.setup_camera()
	assert_eq(map.player.camera.zoom, Vector2.ONE)
