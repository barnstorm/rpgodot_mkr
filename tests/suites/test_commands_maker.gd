extends "res://tests/rpg_test_case.gd"
## RPG Maker VX / VX Ace event commands on the sample project: Show Animation, actor graphic /
## name / nickname, level, EXP, skills, equipment, class, transparency, battle music, map name
## display, tileset / parallax / battle background, Get Location Info, Stop Sound, Window Skin.
## Each runs through run_commands, rejects bad references and survives a save and load.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	await env.settle()


func after_each() -> void:
	await env.destroy()


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


func _hero() -> RPGBattler:
	return env.rpg.state.actor("hero")


func _save_load() -> void:
	var save: Dictionary = env.rpg.saves.build_save()
	# Reset to a fresh game first, so only what the save holds can bring the values back.
	env.rpg.state.new_game()
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	await env.settle()


func test_all_commands_are_registered() -> void:
	for t in ["show_animation", "change_actor_graphic", "change_name", "change_nickname", "change_level", "change_exp",
			"change_skills", "change_equipment", "change_class", "change_transparency", "change_battle_bgm", "change_victory_me",
			"change_map_name_display", "change_tileset", "change_parallax", "change_battle_back", "get_location_info",
			"stop_sound", "change_windowskin"]:
		assert_true(env.rpg.registry.has_command(t), t)
		var cmd: RPGCommand = env.rpg.registry.get_command(t)
		if cmd != null:
			var args := cmd.with_defaults({"type": t})
			assert_ne(env.rpg.registry.summary(args), "", t + " summary")


func test_show_animation() -> void:
	var r := await _run([{"type": "show_animation", "target": "player", "animation": "fire", "wait": true}])
	assert_true(r.is_ok(), str(r))
	var host: Node = env.rpg.ui.root.get_node_or_null("MapAnimations")
	assert_true(host != null, "the map animation layer exists")
	var ev_id := str(env.game.map.event_order[0])
	r = await _run([{"type": "show_animation", "target": ev_id, "animation": "heal"}])
	assert_true(r.is_ok(), str(r))
	assert_true(host.get_child_count() > 0, "an effect is playing without waiting")
	assert_true((await _run([{"type": "show_animation", "target": "player", "animation": "no_such_anim"}])).is_error(), "unknown animation")
	assert_true((await _run([{"type": "show_animation", "target": "nobody", "animation": "hit"}])).is_error(), "unknown character")
	# Effects remove themselves when done (and must not outlive the test's runtime).
	for i in 300:
		if host.get_child_count() == 0:
			break
		await tree.process_frame
	await tree.create_timer(0.2).timeout
	assert_eq(host.get_child_count(), 0, "finished effects are freed")


func test_actor_graphic_name_nickname() -> void:
	var r := await _run([
		{"type": "change_actor_graphic", "actor": "hero", "charset": "hero", "charset_index": 3, "face": "hero_face", "face_index": 2},
		{"type": "change_name", "actor": "hero", "name": "Ralph"},
		{"type": "change_nickname", "actor": "hero", "nickname": "the Brave"},
	])
	assert_true(r.is_ok(), str(r))
	var look: Dictionary = env.rpg.state.actor_look("hero")
	assert_eq(look.charset_index, 3)
	assert_eq(look.face_index, 2)
	assert_eq(look.nickname, "the Brave")
	assert_eq(_hero().name, "Ralph")
	assert_eq(env.game.player.graphic, {"sheet": "hero", "index": 3}, "the leader's map sprite updates")
	assert_eq(RPGText._actor_name(env.rpg, "hero"), "Ralph")
	await _save_load()
	assert_eq(env.rpg.state.actor_look("hero").charset_index, 3, "graphic survives a load")
	assert_eq(env.rpg.state.actor_look("hero").nickname, "the Brave")
	assert_eq(_hero().name, "Ralph")
	assert_eq(env.game.player.graphic, {"sheet": "hero", "index": 3})
	assert_true((await _run([{"type": "change_actor_graphic", "actor": "ghost", "charset": "hero"}])).is_error(), "unknown actor")
	assert_true((await _run([{"type": "change_actor_graphic", "actor": "hero", "charset": "no_such_sheet"}])).is_error(), "missing sheet")
	assert_true((await _run([{"type": "change_name", "actor": "ghost", "name": "x"}])).is_error())
	assert_true((await _run([{"type": "change_nickname", "actor": "ghost", "nickname": "x"}])).is_error())


func test_level_and_exp() -> void:
	var b := _hero()
	var lv := b.level
	var r := await _run([{"type": "change_level", "target": "hero", "operation": "increase", "amount": 2}])
	assert_true(r.is_ok(), str(r))
	assert_eq(b.level, lv + 2)
	assert_eq(b.exp, int(env.rpg.rules.exp_for_level(b.class_id, lv + 2)), "experience matches the new level")
	r = await _run([{"type": "change_level", "target": "leader", "operation": "decrease", "amount": 1}])
	assert_true(r.is_ok(), str(r))
	assert_eq(b.level, lv + 1)
	var need := int(env.rpg.rules.exp_for_level(b.class_id, b.level + 1)) - b.exp
	r = await _run([{"type": "change_exp", "target": "party", "operation": "increase", "amount": need}])
	assert_true(r.is_ok(), str(r))
	assert_eq(b.level, lv + 2, "enough EXP levels up")
	r = await _run([{"type": "change_exp", "target": "hero", "operation": "decrease", "amount": b.exp}])
	assert_true(r.is_ok(), str(r))
	assert_eq(b.level, 1, "losing all EXP drops to level 1")
	await _run([{"type": "change_level", "target": "hero", "operation": "increase", "amount": 4, "show_level_up": true}])
	assert_eq(b.level, 5)
	await _save_load()
	assert_eq(_hero().level, 5, "level survives a load")
	assert_true((await _run([{"type": "change_level", "target": "ghost", "operation": "increase", "amount": 1}])).is_error())
	assert_true((await _run([{"type": "change_exp", "target": "ghost", "operation": "increase", "amount": 1}])).is_error())


func test_skills_and_class() -> void:
	var r := await _run([{"type": "change_skills", "target": "hero", "operation": "learn", "skill": "fire"}])
	assert_true(r.is_ok(), str(r))
	assert_true(_hero().skills.has("fire"))
	r = await _run([{"type": "change_skills", "target": "hero", "operation": "learn", "skill": "fire"}])
	assert_eq(_hero().skills.count("fire"), 1, "learning twice keeps one copy")
	r = await _run([{"type": "change_class", "target": "hero", "class": "mage", "keep_exp": false}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_hero().class_id, "mage")
	await _save_load()
	assert_true(_hero().skills.has("fire"), "skills survive a load")
	assert_eq(_hero().class_id, "mage", "class survives a load")
	r = await _run([{"type": "change_skills", "target": "hero", "operation": "forget", "skill": "fire"}])
	assert_false(_hero().skills.has("fire"))
	assert_true((await _run([{"type": "change_skills", "target": "hero", "operation": "learn", "skill": "no_skill"}])).is_error())
	assert_true((await _run([{"type": "change_skills", "target": "ghost", "operation": "learn", "skill": "fire"}])).is_error())
	assert_true((await _run([{"type": "change_class", "target": "hero", "class": "no_class"}])).is_error())


func test_change_equipment() -> void:
	var st: RPGGameState = env.rpg.state
	st.change_items("iron_sword", "increase", 1, "weapons")
	var r := await _run([{"type": "change_equipment", "actor": "hero", "slot": "weapon", "kind": "weapon", "item": "iron_sword"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_hero().equips.weapon, "iron_sword")
	assert_eq(st.item_count("iron_sword", "weapons"), 0, "taken from the inventory")
	assert_eq(st.item_count("bronze_sword", "weapons"), 1, "the old weapon goes back")
	r = await _run([{"type": "change_equipment", "actor": "hero", "slot": "shield", "kind": "armor", "item": "wooden_shield"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_hero().equips.shield, "wooden_shield", "equipped even when the party has none (RPG Maker VX)")
	r = await _run([{"type": "change_equipment", "actor": "hero", "slot": "shield", "kind": "armor", "item": ""}])
	assert_eq(_hero().equips.shield, "", "blank item removes")
	assert_eq(st.item_count("wooden_shield", "armors"), 1)
	# Mira (mage) can't hold swords: ignored, as in RPG Maker.
	r = await _run([{"type": "change_equipment", "actor": "mira", "slot": "weapon", "kind": "weapon", "item": "bronze_sword"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(str(st.actor("mira").equips.get("weapon", "")), "")
	await _save_load()
	assert_eq(_hero().equips.weapon, "iron_sword", "equipment survives a load")
	assert_true((await _run([{"type": "change_equipment", "actor": "hero", "slot": "weapon", "kind": "weapon", "item": "no_sword"}])).is_error())
	assert_true((await _run([{"type": "change_equipment", "actor": "hero", "slot": "tail", "kind": "weapon", "item": "iron_sword"}])).is_error())
	assert_true((await _run([{"type": "change_equipment", "actor": "hero", "slot": "body", "kind": "weapon", "item": "iron_sword"}])).is_error(), "wrong kind for the slot")
	assert_true((await _run([{"type": "change_equipment", "actor": "ghost", "slot": "weapon", "kind": "weapon", "item": "iron_sword"}])).is_error())


func test_transparency_name_display_and_battle_music() -> void:
	var r := await _run([
		{"type": "change_transparency", "transparent": true},
		{"type": "change_map_name_display", "show": false},
		{"type": "change_battle_bgm", "sound": {"file": "field", "volume": 90, "pitch": 100, "pan": 0}},
		{"type": "change_victory_me", "sound": {"file": "inn", "volume": 100, "pitch": 100, "pan": 0}},
	])
	assert_true(r.is_ok(), str(r))
	var p: RPGPlayer = env.game.player
	assert_true(p.transparent)
	assert_false(p.sprite.visible, "the player is not drawn")
	assert_true(p.blocks() or p.priority != "same", "a transparent player still collides")
	await _save_load()
	assert_true(env.rpg.state.player_transparent, "transparency survives a load")
	assert_true(env.game.player.transparent)
	assert_false(env.rpg.state.map_name_display)
	assert_eq(env.rpg.state.music_overrides.battle.file, "field")
	assert_eq(env.rpg.state.music_overrides.victory.file, "inn")
	# The battle scene picks the override over the System record.
	var bs: Node = load("res://addons/rpg/runtime/ui/battle/battle_scene.gd").new()
	bs.rpg = env.rpg
	assert_eq(bs.battle_music("battle").file, "field")
	assert_eq(bs.battle_music("victory").file, "inn")
	bs.free()
	await _run([{"type": "change_transparency", "transparent": false}])
	assert_true(env.game.player.sprite.visible)
	assert_true((await _run([{"type": "change_battle_bgm", "sound": {"file": "no_such_song"}}])).is_error())
	assert_true((await _run([{"type": "change_victory_me", "sound": {"file": "no_such_song"}}])).is_error())


func test_tileset_parallax_battle_back_per_map() -> void:
	var r := await _run([
		{"type": "change_tileset", "tileset": "town"},
		{"type": "change_parallax", "image": "res://assets/starter/Backdrop/grass.png", "scroll_x": 0.25, "scroll_y": 0.0, "loop": true},
		{"type": "change_battle_back", "background": "res://assets/starter/Title/title.png"},
	])
	assert_true(r.is_ok(), str(r))
	var m: RPGMap = env.game.map
	assert_eq(m.tileset_override, "town")
	assert_true(m.parallax_layer != null, "the parallax is drawn")
	assert_eq(m.props.battle_background, "res://assets/starter/Title/title.png", "Battle Processing sees the new background")
	# Through a transfer away and back, then a save and load.
	var tr: RPGResult = await env.game.transfer("field", Vector2i(1, 1), "down", "none", 8)
	assert_true(tr.is_ok(), str(tr))
	assert_eq(env.game.map.props.get("battle_background"), "grass", "other maps keep their own background")
	tr = await env.game.transfer("town", Vector2i(14, 12), "down", "none", 8)
	assert_true(tr.is_ok(), str(tr))
	assert_eq(env.game.map.props.battle_background, "res://assets/starter/Title/title.png", "kept after a transfer")
	assert_true(env.game.map.parallax_layer != null)
	await _save_load()
	assert_eq(env.game.map.map_id, "town")
	assert_eq(env.game.map.tileset_override, "town", "tileset survives a load")
	assert_eq(env.game.map.props.parallax.scroll_x, 0.25, "parallax survives a load")
	assert_eq(env.game.map.props.battle_background, "res://assets/starter/Title/title.png", "battle background survives a load")
	r = await _run([{"type": "change_parallax", "image": ""}])
	assert_true(r.is_ok(), str(r))
	assert_true(env.game.map.parallax_layer == null, "blank removes the parallax")
	assert_true((await _run([{"type": "change_tileset", "tileset": "no_tiles"}])).is_error())
	assert_true((await _run([{"type": "change_parallax", "image": "no_such_image"}])).is_error())
	assert_true((await _run([{"type": "change_battle_back", "background": "no_such_image"}])).is_error())


func test_get_location_info() -> void:
	var m: RPGMap = env.game.map
	var ev: Node = null
	for id in m.event_order:
		var e: Node = m.events[id]
		if e.page_index >= 0 and not e.erased:
			ev = e
			break
	assert_true(ev != null, "the town has a visible event")
	if ev == null:
		return
	var r := await _run([{"type": "get_location_info", "result": "fishing_result", "info": "event_id", "x": ev.cell.x, "y": ev.cell.y}])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("fishing_result"), str(ev.event_id))
	var c := Vector2i(14, 12)
	r = await _run([{"type": "get_location_info", "result": "fish_caught", "info": "terrain_tag", "x": c.x, "y": c.y}])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("fish_caught"), m.terrain_at(c))
	r = await _run([{"type": "get_location_info", "result": "fish_caught", "info": "region_id", "x": c.x, "y": c.y}])
	assert_eq(env.rpg.state.get_variable("fish_caught"), m.region_at(c))
	r = await _run([{"type": "get_location_info", "result": "fish_caught", "info": "tile_id", "layer": 1, "x": c.x, "y": c.y}])
	assert_true(r.is_ok(), str(r))
	assert_true(int(env.rpg.state.get_variable("fish_caught")) > 0, "a painted cell has a tile id")
	r = await _run([{"type": "get_location_info", "result": "fishing_result", "info": "tile_key", "layer": 1, "x": c.x, "y": c.y}])
	assert_true(r.is_ok(), str(r))
	assert_true((await _run([{"type": "get_location_info", "result": "no_var", "info": "terrain_tag", "x": 0, "y": 0}])).is_error())
	assert_true((await _run([{"type": "get_location_info", "result": "fish_caught", "info": "terrain_tag", "x": 999, "y": 0}])).is_error(), "outside the map")
	assert_true((await _run([{"type": "get_location_info", "result": "fish_caught", "info": "tile_key", "x": 0, "y": 0}])).is_error(), "a tile key needs a text variable")


func test_stop_sound_and_windowskin() -> void:
	env.rpg.audio.play_se({"file": "cursor"})
	var r := await _run([{"type": "stop_sound", "what": "all"}])
	assert_true(r.is_ok(), str(r))
	for p in env.rpg.audio.se_pool:
		assert_false(p.playing)
	r = await _run([{"type": "change_windowskin", "skin": "system"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.windowskin, "system")
	assert_eq(env.rpg.ui.root.theme, env.rpg.ui.ui_theme, "the new theme is applied")
	await _save_load()
	assert_eq(env.rpg.state.windowskin, "system", "window skin survives a load")
	assert_true((await _run([{"type": "change_windowskin", "skin": "no_such_skin"}])).is_error())


func test_new_state_defaults_for_old_saves() -> void:
	var st := RPGGameState.new(env.rpg.data)
	st.from_dict({"switches": {}, "party": ["hero"]})
	assert_false(st.player_transparent)
	assert_true(st.map_name_display)
	assert_eq(st.music_overrides, {})
	assert_eq(st.map_overrides, {})
	assert_eq(st.windowskin, "")


func test_validator_sees_references() -> void:
	# The project validator reads ref fields from the descriptors, so new commands' IDs are checked.
	var cmd: RPGCommand = env.rpg.registry.get_command("change_class")
	var problems := cmd.validate({"type": "change_class", "target": "hero"})
	assert_true(problems.size() > 0, "a missing class is reported")
	var anim: RPGCommand = env.rpg.registry.get_command("show_animation")
	assert_has(anim.desc.fields[1].allow, "fire", "built-in effects are allowed animation names")
