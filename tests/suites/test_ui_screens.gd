extends "res://tests/rpg_test_case.gd"
## Default UI screens: each one opens, renders, and its main flow works when driven by input
## actions. The battle scene runs in auto mode on the sample database with a fixed seed.

const Env := preload("res://tests/rpg_test_env.gd")
const UI := "res://addons/rpg/runtime/ui/"
const OPTIONS_FILE := "user://rpg_options.json"

var env
var _backups := {}


func after_each() -> void:
	for a in ["rpg_up", "rpg_down", "rpg_left", "rpg_right", "rpg_ok", "rpg_cancel"]:
		if InputMap.has_action(a):
			Input.action_release(a)
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


## Keeps a copy of a user:// file and restores it after the test.
func backup(path: String) -> void:
	if _backups.has(path):
		return
	_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func sample_env() -> void:
	env = Env.create(tree, "res://rpg")


func open(key: String) -> Node:
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path(key))
	assert_true(node != null, "%s opens" % key)
	await frames(2)
	return node


## Presses an input action for one frame, like a player would.
func press(action: String) -> void:
	Input.action_press("rpg_" + action)
	await frames(1)
	Input.action_release("rpg_" + action)
	await frames(1)


func test_default_scene_paths_exist() -> void:
	for key in RPGUI.DEFAULT_SCENES:
		var path: String = RPGUI.DEFAULT_SCENES[key]
		assert_true(ResourceLoader.exists(path), "%s: %s" % [key, path])


func test_title_screen_input() -> void:
	sample_env()
	var title: Node = await open("title")
	var got := []
	title.chosen.connect(func(c): got.append(c))
	assert_eq(title.list.items.size(), 4)
	title.list.select(0)
	await press("down")
	assert_eq(title.list.index, 1, "a real key press moves the cursor")
	title.list.select(0)
	await press("ok")
	assert_eq(got, ["new_game"])


func test_title_options_inline() -> void:
	backup(OPTIONS_FILE)
	sample_env()
	var title: Node = await open("title")
	title.list.select(2)
	title.handle_action("ok")
	await frames(2)
	var top: Node = env.rpg.ui.scene_stack[-1]
	assert_true(top != title and top.has_signal("closed"), "options opened above the title")
	assert_false(title.is_top())
	top.handle_action("cancel")
	await frames(2)
	assert_true(title.is_top(), "back on the title")
	assert_true(title.input_enabled)


func test_options_apply_and_persist() -> void:
	backup(OPTIONS_FILE)
	if FileAccess.file_exists(OPTIONS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_FILE))
	sample_env()
	var o: Node = await open("options")
	var closed := [false]
	o.closed.connect(func(): closed[0] = true)
	o.handle_action("left")
	o.handle_action("left")
	assert_eq(o.options.music, 80)
	assert_true(is_equal_approx(env.rpg.audio.master_music, 0.8), "music volume applied")
	o.handle_action("down")
	o.handle_action("left")
	assert_true(is_equal_approx(env.rpg.audio.master_sound, 0.9), "sound volume applied")
	o.handle_action("down")
	o.handle_action("right")
	assert_eq(o.options.text_speed, "fast")
	assert_eq(float(env.rpg.data.system.text_speed), 80.0)
	o.handle_action("down")
	o.handle_action("ok")
	assert_true(env.rpg.data.system.always_dash)
	o.handle_action("cancel")
	assert_true(closed[0])
	var saved: Dictionary = o.load_options()
	assert_eq(saved.music, 80)
	assert_eq(saved.always_dash, true)


func test_game_over_closes() -> void:
	sample_env()
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path("game_over"))
	var closed := [false]
	node.closed.connect(func(): closed[0] = true)
	await frames(2)
	assert_true(closed[0], "auto mode closes the game over screen")
	env.rpg.ui.close_scene(node)
	env.rpg.ui.auto_advance = false
	node = await open("game_over")
	closed[0] = false
	node.closed.connect(func(): closed[0] = true)
	node.handle_action("ok")
	assert_false(closed[0], "not before the short pause")
	node._t = 1.0
	node.handle_action("ok")
	assert_true(closed[0])


func test_shop_buy_and_sell() -> void:
	sample_env()
	var rpg: Node = env.rpg
	var shop: Node = await open("shop")
	var result := []
	shop.finished.connect(func(r): result.append(r))
	shop.start({"goods": [{"kind": "items", "id": "potion", "price": null}, {"kind": "weapons", "id": "iron_sword", "price": 40}], "buy_only": false}, {"rpg": rpg})
	await frames(1)
	assert_eq(rpg.state.gold, 100)
	assert_eq(rpg.state.item_count("potion"), 2)
	shop.handle_action("ok")                   # Buy
	assert_eq(shop.mode, "buy")
	assert_eq(shop.list.items[0].right, "50", "database price when the good has none")
	assert_eq(shop.list.items[1].right, "40", "price set in the event")
	shop.handle_action("ok")                   # potion -> quantity
	assert_eq(shop.mode, "quantity")
	assert_eq(shop.qty_max, 2, "100 G buys two potions")
	shop.handle_action("up")
	shop.handle_action("up")
	assert_eq(shop.qty, 2, "capped at what the party can afford")
	shop.handle_action("ok")
	assert_eq(rpg.state.gold, 0)
	assert_eq(rpg.state.item_count("potion"), 4)
	assert_eq(shop.mode, "buy")
	shop.handle_action("down")
	shop.handle_action("ok")
	assert_eq(shop.mode, "buy", "cannot afford the sword")
	var cmp: Dictionary = shop.compare_equip(rpg.state.actor("hero"), "weapons", "iron_sword")
	assert_true(cmp.can and cmp.diff > 0, "iron sword is better for the hero: %s" % cmp)
	shop.handle_action("cancel")
	shop.handle_action("down")
	shop.handle_action("ok")                   # Sell
	assert_eq(shop.mode, "sell")
	shop.list.select(0)
	shop.handle_action("ok")
	shop.handle_action("ok")                   # sell one potion for 25
	assert_eq(rpg.state.gold, 25)
	assert_eq(rpg.state.item_count("potion"), 3)
	shop.handle_action("cancel")
	shop.handle_action("cancel")               # leave
	assert_eq(result.size(), 1)
	assert_eq(result[0].bought.size(), 1)
	assert_eq(result[0].sold.size(), 1)


func test_shop_contract_via_run_scene() -> void:
	sample_env()
	var rpg: Node = env.rpg
	var out := {}
	var run := func():
		out.r = await rpg.ui.run_contract_scene(rpg.ui.scene_path("shop"), {"goods": [{"kind": "items", "id": "antidote"}], "buy_only": true}, {"rpg": rpg}, RPGCancelToken.new())
	run.call()
	await frames(2)
	var shop: Node = rpg.ui.scene_stack[-1]
	shop.handle_action("down")
	shop.handle_action("ok")
	assert_eq(shop.mode, "command", "sell is disabled in a buy-only shop")
	shop.list.select(0)
	shop.buy({"kind": "items", "id": "antidote"}, 1)
	shop.leave()
	await frames(2)
	assert_eq(out.get("r", {}).get("status", ""), "finished")
	assert_eq(rpg.state.gold, 70)
	assert_eq(rpg.state.item_count("antidote"), 1)


func test_save_screen_round_trip() -> void:
	env = Env.create(tree)
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8), "up")
	assert_true(r.is_ok(), "start: %s" % r)
	await env.settle()
	var rpg: Node = env.rpg
	var slot: int = rpg.saves.MAX_SLOTS
	backup(rpg.saves.slot_path(slot))
	rpg.state.change_gold("set", 321)
	rpg.set_variable("counter", 7)
	var screen: Node = await open("save")
	screen.setup("save")
	assert_eq(rpg.saves.save_blocked_reason(), "", "saving allowed with the save screen open")
	await screen.confirm(slot)
	assert_true(screen.last_result != null and screen.last_result.is_ok(), "saved: %s" % screen.last_result)
	assert_true(rpg.saves.exists(slot))
	assert_eq(rpg.saves.describe(slot).get("map_name", ""), "Town")
	await frames(2)
	rpg.state.change_gold("set", 5)
	rpg.set_variable("counter", 99)
	screen = await open("save")
	screen.setup("load")
	var closed := [false]
	screen.closed.connect(func(): closed[0] = true)
	await screen.confirm(slot)
	assert_true(screen.last_result.is_ok(), "loaded: %s" % screen.last_result)
	assert_true(closed[0], "closes after loading")
	assert_eq(rpg.state.gold, 321)
	assert_eq(rpg.get_variable("counter"), 7)
	assert_eq(env.game.map.map_id, "town")
	await frames(2)
	assert_false(rpg.ui.scene_open(), "screen removed itself")


func test_save_screen_load_failure_keeps_game() -> void:
	env = Env.create(tree)
	await env.start_on("town", Vector2i(12, 8), "up")
	await env.settle()
	var rpg: Node = env.rpg
	var slot: int = rpg.saves.MAX_SLOTS
	backup(rpg.saves.slot_path(slot))
	DirAccess.make_dir_recursive_absolute(rpg.saves.DIR)
	var f := FileAccess.open(rpg.saves.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 2, "project_id": "someone_else", "map": {"id": "town", "position": [1, 1]}, "state": {}}))
	f = null
	rpg.state.change_gold("set", 42)
	var screen: Node = await open("save")
	screen.setup("load")
	await screen.confirm(slot)
	assert_true(screen.last_result.is_error(), "load refused")
	assert_true(screen.help.text.contains("another project"), screen.help.text)
	assert_eq(rpg.state.gold, 42, "game unchanged")
	assert_true(screen.input_enabled and screen.is_inside_tree(), "screen stays open")


func test_name_input() -> void:
	sample_env()
	var node: Node = await open("name_input")
	var got := []
	node.finished.connect(func(n): got.append(n))
	node.start({"actor": "hero", "name": "Alex", "max_length": 6}, {"rpg": env.rpg})
	await frames(1)
	assert_eq(node.text, "Alex")
	for i in 4:
		node.handle_action("cancel")
	assert_eq(node.text, "")
	node.handle_action("ok")                  # A
	node.handle_action("right")
	node.handle_action("ok")                  # B
	node.handle_action("down")
	node.handle_action("down")
	node.handle_action("down")
	node.handle_action("down")                # command row
	node.cx = 2
	node.handle_action("ok")                  # lower case page
	assert_eq(node.page, "lower")
	node.cy = 0
	node.cx = 2
	node.handle_action("ok")                  # c
	assert_eq(node.text, "ABc")
	node.cy = 4
	node.cx = 8
	node.handle_action("ok")
	assert_eq(got, ["ABc"])


func test_main_menu_items_skills_equip() -> void:
	sample_env()
	var rpg: Node = env.rpg
	rpg.state.add_actor("mira")
	var hero: RPGBattler = rpg.state.actor("hero")
	var mira: RPGBattler = rpg.state.actor("mira")
	var menu: Node = await open("menu")
	var closed := [false]
	menu.closed.connect(func(): closed[0] = true)
	# Items: a potion heals 50 HP and is used up.
	hero.set_resource("hp", 10)
	menu.choose("item")
	assert_eq(menu.mode, "items")
	assert_eq(menu.list.items.size(), 1)
	menu.handle_action("ok")
	assert_eq(menu.mode, "target")
	menu.handle_action("ok")
	assert_eq(hero.get_resource("hp"), 60)
	assert_eq(rpg.state.item_count("potion"), 1)
	menu.handle_action("cancel")
	menu.handle_action("cancel")
	assert_eq(menu.mode, "command")
	# Key items have their own tab.
	rpg.state.change_items("house_key", "increase", 1)
	menu.choose("item")
	menu.handle_action("right")
	assert_eq(menu.item_tab, "key")
	assert_eq(menu.list.items.size(), 1)
	assert_false(menu.list.items[0].enabled, "key items are listed but not usable")
	menu.handle_action("cancel")
	# Skills: Mira casts Heal on the hero.
	menu.choose("skill")
	assert_eq(menu.mode, "actor")
	menu.handle_action("down")
	menu.handle_action("ok")
	assert_eq(menu.mode, "skills")
	var heal_index := -1
	for i in menu.list.items.size():
		if menu.list.items[i].data == "heal":
			heal_index = i
	assert_true(heal_index >= 0, "heal listed")
	assert_true(menu.list.items[heal_index].enabled)
	var fire_ok := true
	for it in menu.list.items:
		if it.data == "fire":
			fire_ok = it.enabled
	assert_false(fire_ok, "battle-only skills are greyed out")
	menu.list.select(heal_index)
	menu.handle_action("ok")
	menu.target_index = 0
	var sp_before := mira.get_resource("sp")
	menu.handle_action("ok")
	assert_true(hero.get_resource("hp") > 60, "healed")
	assert_eq(mira.get_resource("sp"), sp_before - 5, "cost paid once")
	menu.handle_action("cancel")
	menu.handle_action("cancel")
	menu.handle_action("cancel")
	assert_eq(menu.mode, "command")
	# Equipment: swap the bronze sword for an iron sword.
	rpg.state.change_items("iron_sword", "increase", 1, "weapons")
	var atk_before: int = rpg.rules.effective_stat(hero, "atk")
	menu.choose("equip")
	menu.actor_index = 0
	menu.handle_action("ok")
	assert_eq(menu.mode, "equip_slots")
	assert_eq(menu.current_slot(), "weapon")
	menu.handle_action("ok")
	assert_eq(menu.mode, "equip_items")
	assert_eq(menu.cand_list.current().data, "iron_sword")
	menu.handle_action("ok")
	assert_eq(hero.equips.weapon, "iron_sword")
	assert_eq(rpg.state.item_count("bronze_sword", "weapons"), 1, "old weapon back in the bag")
	assert_eq(rpg.state.item_count("iron_sword", "weapons"), 0)
	assert_eq(rpg.rules.effective_stat(hero, "atk"), atk_before + 12)
	assert_eq(menu.candidates(mira, "weapon"), [], "mages cannot use swords")
	# Dual Wield and Seal Equip traits (VX Ace Features): the shield slot takes a weapon, and a
	# sealed slot can't be changed.
	var hero_rec: Dictionary = rpg.data.record("actors", "hero")
	var old_traits: Variant = hero_rec.get("traits")
	hero_rec["traits"] = [{"kind": "dual_wield", "id": "shield"}, {"kind": "seal_equip", "id": "body"}]
	menu.equip_actor = hero
	assert_true(menu.candidates(hero, "shield").has("bronze_sword"), "a weapon in the shield slot with Dual Wield")
	assert_true(menu._sealed("body"))
	assert_false(menu._sealed("weapon"))
	if old_traits == null:
		hero_rec.erase("traits")
	else:
		hero_rec["traits"] = old_traits
	assert_false(menu.candidates(hero, "shield").has("bronze_sword"), "no weapons in the shield slot without it")
	menu.handle_action("cancel")
	menu.handle_action("cancel")
	# Status, with the actor's profile (Description) on OK.
	rpg.data.record("actors", "hero")["description"] = "A farm boy from Riverside."
	menu.choose("status")
	menu.handle_action("ok")
	assert_eq(menu.mode, "status")
	assert_true(menu.profile_win != null and not menu.profile_win.visible, "profile window ready, hidden")
	menu.handle_action("ok")
	assert_true(menu.profile_win.visible, "OK shows the profile")
	menu.handle_action("ok")
	assert_eq(menu.mode, "status", "OK again hides it and stays on the status screen")
	rpg.data.record("actors", "hero").erase("description")
	await frames(1)
	menu.handle_action("right")
	assert_eq(menu.status_actor, 1)
	menu.handle_action("cancel")
	menu.handle_action("cancel")
	# Save is blocked without a map: the reason is shown, nothing opens.
	menu.choose("save")
	assert_true(menu.notice != null and is_instance_valid(menu.notice), "reason shown")
	assert_eq(rpg.ui.scene_stack.size(), 1)
	# Game End -> Cancel, then close.
	menu.choose("game_end")
	menu.handle_action("down")
	menu.handle_action("ok")
	assert_eq(menu.mode, "command")
	await frames(1)
	await press("cancel")
	assert_true(closed[0], "cancel closes the menu")


func test_main_menu_opens_save_screen() -> void:
	env = Env.create(tree)
	await env.start_on("town", Vector2i(12, 8), "up")
	await env.settle()
	var menu: Node = await open("menu")
	assert_true(menu.commands.items[5].enabled, "save enabled on the map")
	menu.choose("save")
	await frames(2)
	var top: Node = env.rpg.ui.scene_stack[-1]
	assert_true(top != menu and top.has_method("setup"), "save screen above the menu")
	assert_eq(top.mode, "save")
	top.handle_action("cancel")
	await frames(3)
	assert_true(menu.is_top())
	assert_true(menu.input_enabled)


func test_debug_screen() -> void:
	env = Env.create(tree)
	await env.start_on("town", Vector2i(12, 8), "up")
	await env.settle()
	var rpg: Node = env.rpg
	var dbg: Node = await open("debug")
	var closed := [false]
	dbg.closed.connect(func(): closed[0] = true)
	assert_eq(dbg.page, "switches")
	dbg.handle_action("ok")
	assert_eq(dbg.current_id(), "door_unlocked")
	dbg.handle_action("ok")
	assert_true(rpg.get_switch("door_unlocked"), "toggled on")
	dbg.handle_action("ok")
	assert_false(rpg.get_switch("door_unlocked"), "toggled off")
	dbg.handle_action("cancel")
	dbg.handle_action("down")
	assert_eq(dbg.page, "variables")
	dbg.handle_action("ok")
	assert_eq(dbg.current_id(), "counter")
	dbg.handle_action("right")
	assert_eq(rpg.get_variable("counter"), 1)
	dbg.handle_action("ok")
	dbg.handle_action("up")
	assert_eq(rpg.get_variable("counter"), 11)
	dbg.handle_action("ok")
	dbg.handle_action("down")
	dbg.handle_action("down")
	assert_eq(dbg.current_id(), "flag")
	dbg.handle_action("ok")
	assert_eq(rpg.get_variable("flag"), true)
	dbg.handle_action("down")
	dbg.handle_action("ok")
	assert_true(dbg.line_edit != null, "strings are edited in a text field")
	dbg.line_edit.text = "Bob"
	dbg._end_text_edit(true)
	assert_eq(rpg.get_variable("hero_name"), "Bob")
	await frames(2)
	dbg.handle_action("cancel")
	dbg.handle_action("down")
	assert_eq(dbg.page, "events")
	assert_true(dbg.info.text.contains("Main:"), dbg.info.text)
	dbg.handle_action("cancel")
	assert_true(closed[0])


func _run_battle(rpg: Node, battle_args: Dictionary) -> Dictionary:
	return await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), battle_args, {"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)


func test_battle_auto_win_vs_slimes() -> void:
	sample_env()
	var rpg: Node = env.rpg
	rpg.rng.seed = 12345
	var hero: RPGBattler = rpg.state.actor("hero")
	var r := await _run_battle(rpg, {"troop": "slimes", "can_escape": true, "can_lose": true, "background": "", "auto": true})
	assert_eq(r.status, "finished", str(r))
	assert_eq(r.value.outcome, "win")
	assert_eq(r.value.rewards.exp, 12)
	assert_eq(r.value.rewards.gold, 16)
	assert_eq(rpg.state.gold, 116, "gold awarded")
	assert_eq(hero.exp, 12, "exp awarded to the real party battler")
	assert_true(hero.get_resource("hp") < rpg.rules.max_resource(hero, "hp"), "damage persists after the battle")
	assert_false(rpg.ui.scene_open(), "battle scene removed")
	# Same seed, same battle.
	var hp_after := hero.get_resource("hp")
	await sample_env_again()
	env.rpg.rng.seed = 12345
	await _run_battle(env.rpg, {"troop": "slimes", "auto": true})
	assert_eq(env.rpg.state.actor("hero").get_resource("hp"), hp_after, "deterministic with a fixed seed")


func sample_env_again() -> void:
	await env.destroy()
	sample_env()


func test_battle_events_and_defeat() -> void:
	sample_env()
	var rpg: Node = env.rpg
	rpg.rng.seed = 7
	var shown := [0]
	rpg.ui.message_box.closed.connect(func(): shown[0] += 1)
	var r := await _run_battle(rpg, {"troop": "goblin_boss", "can_escape": false, "can_lose": true, "background": "grass"})
	assert_eq(r.status, "finished", str(r))
	assert_eq(r.value.outcome, "lose", "a lone hero loses to the goblin")
	assert_eq(shown[0], 1, "the turn-2 battle page showed its message once")
	assert_true(rpg.state.actor("hero").is_dead())
	assert_eq(rpg.ui.message_box.get_index(), 0, "message box back under the overlay scenes")


func test_battle_player_input() -> void:
	sample_env()
	var rpg: Node = env.rpg
	rpg.ui.auto_advance = false
	rpg.rng.seed = 99
	rpg.state.add_actor("mira")
	var out := {}
	var run := func():
		out.r = await _run_battle(rpg, {"troop": "slimes", "can_escape": true, "can_lose": true, "background": ""})
	run.call()
	var scene: Node = rpg.ui.scene_stack[-1]
	for i in 600:
		if scene.phase == "party":
			break
		await frames(1)
	assert_eq(scene.phase, "party", "waiting for the party command")
	scene.handle_action("ok")                 # Fight
	assert_eq(scene.phase, "actor")
	scene.handle_action("ok")                 # Attack
	assert_eq(scene.phase, "target_enemy")
	scene.handle_action("right")
	assert_eq(scene.target_index, 1)
	scene.handle_action("ok")                 # hero attacks Slime B
	assert_eq(scene.phase, "actor", "next actor")
	scene.handle_action("down")
	scene.handle_action("ok")                 # Skill
	assert_eq(scene.phase, "skill")
	var fire := -1
	for i in scene.select_list.items.size():
		if scene.select_list.items[i].data == "fire":
			fire = i
	scene.select_list.select(fire)
	scene.handle_action("ok")
	assert_eq(scene.phase, "target_enemy")
	scene.handle_action("cancel")
	assert_eq(scene.phase, "skill", "cancel goes back to the skill list")
	scene.handle_action("ok")
	scene.handle_action("ok")                 # Mira casts Fire
	assert_eq(scene.core.party[0].action.get("target"), 1)
	assert_eq(scene.core.party[1].action.get("skill"), "fire")
	var lines: Array = scene.log_lines
	scene.auto = true                         # finish the rest without waiting
	for i in 600:
		if out.has("r"):
			break
		await frames(1)
	assert_eq(out.get("r", {}).get("status", ""), "finished")
	assert_true(lines.has("Mira casts Fire!"), "fire was cast: %s" % str(lines))


## Two choice menus opened in the same frame (a choice whose branch opens another): the first
## menu's labels must be gone at once, or the cursor indexes past the new, shorter list.
func test_back_to_back_choices_replace_labels_at_once() -> void:
	sample_env()
	var mb: Control = env.rpg.ui.message_box
	mb.auto_advance = false
	mb.open_choices(["One", "Two", "Three", "Four"])
	mb.open_choices(["Only"])
	var labels := 0
	for c in mb.choice_box.get_children():
		if c is Label:
			labels += 1
	assert_eq(labels, 1, "only the new menu's labels")


## A VX/MV face (96/144 px) shrinks into the message box's 48 px slot instead of growing over the text.
func test_large_face_fits_the_message_box() -> void:
	sample_env()
	var mb: Control = env.rpg.ui.message_box
	var img := Image.create(576, 288, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var at := AtlasTexture.new()
	at.atlas = ImageTexture.create_from_image(img)
	at.region = Rect2(0, 0, 144, 144)
	mb.face_rect.texture = at
	await tree.process_frame
	assert_eq(mb.face_rect.size, Vector2(mb.FACE, mb.FACE), "face keeps the slot size")


## After a transfer the whole party stands on one cell: the leader must be drawn on top.
func test_leader_draws_above_followers_on_a_shared_cell() -> void:
	sample_env()
	await env.start_on("town", Vector2i(14, 12), "up")
	await env.settle()
	var p: Node = env.game.player
	for f in p.followers:
		assert_true(f.get_index() < p.get_index(), "follower %s before the leader in draw order" % f.name)
	assert_true(p.followers[0].get_index() > p.followers[2].get_index(), "the first follower above the last")


## The cancel press that closes the menu must not reach the player in the same frame and open a
## fresh menu (the menu looked impossible to leave with X/Esc).
func test_cancel_closes_the_menu_for_good() -> void:
	sample_env()
	await env.start_on("town", Vector2i(14, 12), "up")
	await env.settle()
	env.rpg.ui.auto_advance = false
	await frames(2)
	await press("cancel")
	assert_true(env.rpg.ui.scene_open(), "cancel on the map opens the menu")
	var first: Node = env.rpg.ui.scene_stack[0]
	await press("cancel")
	await frames(3)
	assert_false(env.rpg.ui.scene_open(), "cancel closes it and nothing reopens (was a new menu: %s)" % [env.rpg.ui.scene_stack])
	assert_false(is_instance_valid(first) and not first.is_queued_for_deletion(), "the first menu is gone")
	await press("cancel")
	assert_true(env.rpg.ui.scene_open(), "a later press opens it again")


## The ok press that closes the last message of a conversation must not start the same
## conversation again.
func test_ok_that_ends_a_message_does_not_talk_again() -> void:
	sample_env()
	await env.start_on("town", Vector2i(13, 10), "up")
	await env.settle()
	env.rpg.ui.auto_advance = false
	env.rpg.ui.message_box.auto_advance = false
	await frames(2)
	await press("ok")
	var box: Control = env.rpg.ui.message_box
	assert_true(box.is_open(), "the sign's message shows")
	for i in 600:
		if box._text_done():
			break
		await frames(1)
	await press("ok")
	await frames(5)
	assert_false(box.is_open(), "the message closed and the sign wasn't read again")
