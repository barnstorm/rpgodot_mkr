extends "res://tests/rpg_test_case.gd"
## Smoke test over the shipped sample project (res://rpg): the intro autorun, the locked door,
## Mira joining, the field, the goblin battle and a save/load round trip. If this fails, the
## sample a new user opens first is broken.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.rng.seed = 2024


func after_each() -> void:
	await env.destroy()


func test_sample_data_validates() -> void:
	assert_true(env.rpg.data.load_errors.is_empty(), str(env.rpg.data.load_errors))
	var errors := []
	for p in RPGExportCheck.run_checks("res://rpg"):
		if p.get("severity", "error") == "error":
			errors.append(p)
	assert_eq(errors, [], "the sample project exports cleanly")


func test_intro_door_mira_and_goblin() -> void:
	var rpg: Node = env.rpg
	var game: RPGGame = env.game
	await env.start_on("town", Vector2i(14, 12), "up")
	assert_true(await env.settle(), "intro autorun finishes")
	assert_eq(rpg.state.item_count("house_key"), 1, "the elder hands over the house key")
	assert_true(rpg.state.get_self_switch("town", "elder", "A"))

	# The elder's door opens with the key.
	game.player.place(Vector2i(5, 6))
	game.player.turn("up")
	var door: Node = game.map.get_event("elder_door")
	assert_true(game.player.check_action(), "the door reacts to the action button (page %d best %d trigger %s cell %s events_at %s)" % [door.page_index, door.best_page(), door.trigger, door.cell, game.map.events_at(Vector2i(5, 5))])
	assert_true(await env.settle())
	assert_eq(game.map.map_id, "house_inside")
	assert_eq(game.player.cell, Vector2i(5, 8))

	# Mira joins and her event is erased.
	var mira: Node = game.map.get_event("mira")
	assert_true(mira.trigger_action())
	assert_true(await env.settle())
	assert_true(rpg.state.in_party("mira"), "Mira joined")
	var shown := 0
	for f in game.player.followers:
		if f.visible:
			shown += 1
	assert_eq(shown, 1, "a follower walks behind the hero")

	# A slime fight on the field road, then some grinding (as a player would) before the boss.
	var tr: RPGResult = await game.transfer("field", Vector2i(10, 10), "right", "none")
	assert_true(tr.is_ok(), "transfer to the field: %s" % tr.message)
	var fight: RPGResult = await rpg.run_commands([{"type": "battle", "troop": "slimes", "can_escape": false, "can_lose": true, "result": "battle_outcome"}], {"kind": "api", "id": "smoke"})
	assert_true(fight.is_ok(), fight.message)
	assert_eq(rpg.get_variable("battle_outcome"), "win", "two level-1 heroes beat two slimes")
	assert_true(rpg.state.actor("hero").exp > 0, "the win gives experience")
	for id in ["hero", "mira"]:
		var b: RPGBattler = rpg.state.actor(id)
		while b.level < 6:
			rpg.rules.gain_exp(b, maxi(1, rpg.rules.exp_for_level(b.class_id, b.level + 1) - b.exp))
		rpg.rules.recover_all(b)

	# On to the goblin.
	tr = await game.transfer("field", Vector2i(25, 10), "right", "none")
	assert_true(tr.is_ok(), "transfer to the field: %s" % tr.message)
	assert_true(await env.settle())
	if game.map == null:
		fail("map gone after field transfer: outcome=%s defeated=%s hp=%s" % [rpg.get_variable("battle_outcome"), rpg.get_switch("goblin_defeated"), rpg.state.actor("hero").get_resource("hp")])
		return
	assert_eq(game.map.map_id, "field")
	var goblin: Node = game.map.get_event("goblin")
	assert_true(goblin != null)
	goblin.trigger_touch(false)
	assert_true(await env.settle(3000), "the battle finishes in auto mode")
	assert_true(rpg.get_switch("goblin_defeated"), "the party beats the goblin")
	assert_eq(rpg.get_variable("battle_outcome"), "win")


func test_save_and_load_round_trip_on_sample() -> void:
	var rpg: Node = env.rpg
	await env.start_on("town", Vector2i(14, 12), "up")
	await env.settle()
	rpg.state.change_gold("increase", 37)
	var gold: int = rpg.state.gold
	assert_true(rpg.saves.save(9).is_ok())
	rpg.state.change_gold("decrease", gold)
	var r: RPGResult = await rpg.saves.load_slot(9)
	assert_true(r.is_ok(), "load succeeds: %s" % r.message)
	await env.settle()
	assert_eq(rpg.state.gold, gold)
	assert_eq(env.game.map.map_id, "town")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://saves/slot_09.json"))


func test_battle_test_party_setup() -> void:
	env.rpg.state.new_game()
	env.game.setup_test_party([{"actor": "mira", "level": 7}, {"actor": "nobody", "level": 3}])
	assert_eq(Array(env.rpg.state.party), ["mira"], "only the chosen, existing actors")
	assert_eq(int(env.rpg.state.actor("mira").level), 7)
	env.rpg.state.new_game()
	env.game.setup_test_party([])
	assert_eq(Array(env.rpg.state.party), Array(env.rpg.data.system.get("starting_party", [])), "empty = the starting party")
