extends "res://tests/rpg_test_case.gd"
## Battle hooks (RPGBattleCore, the default battle scene, RPG.battle_hook) and the battle kit
## plugins built on them: enemy_gauges (W6), victory_aftermath (W7), party_formation (W9) and
## bestiary (W10). The hooks are checked with the battle_probe fixture extension; every plugin is
## off by default, saves what it should, and works in every battle view and system.

const Env := preload("res://tests/rpg_test_env.gd")
const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")
const EXT_ROOT := "res://tests/fixtures/extensions"
const PLUGINS := ["enemy_gauges", "victory_aftermath", "party_formation", "bestiary"]
const PLUGIN_COMMANDS := ["open_formation", "formation_member", "formation_size", "open_bestiary", "reveal_enemy"]
const SLOT := 92
const VIEWS := ["front", "side"]
const SYSTEMS := ["turn", "atb", "ctb"]

var env


## Passes every hook through unchanged, like an extension that changes nothing.
class PassHooks:
	extends RefCounted
	var calls: Array = []

	func battle_hook(hook: String, args: Array, _mode := "") -> Dictionary:
		calls.append(hook)
		return {"args": args, "cancel": false}


func after_each() -> void:
	Engine.time_scale = 1.0
	if env != null:
		await env.destroy()
		env = null
	var p := "user://saves/slot_%02d.json" % SLOT
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## The sample project with `ids` on (kit plugins, or the battle_probe fixture), settings for this
## run, and the party given (ids; levels 1).
func plugin_env(ids: Array, settings: Dictionary = {}, party: Array = ["hero", "mira"]) -> void:
	env = Env.create(tree, "res://rpg")
	var pj: Dictionary = env.rpg.data.project
	pj["extensions_root"] = EXT_ROOT
	pj["extensions"] = ["project"] + ids
	pj["disabled_extensions"] = []
	_add_actors()
	env.rpg.reload_extensions(settings)
	env.game.setup_test_party(party.map(func(id): return {"actor": id, "level": 1}))


## Three more actors (copies of the hero) for formation tests.
func _add_actors() -> void:
	var data: RPGProjectData = env.rpg.data
	for g in [["gus", "Gus"], ["pip", "Pip"], ["kai", "Kai"]]:
		if data.has_record("actors", g[0]):
			continue
		var r: Dictionary = data.record("actors", "hero").duplicate(true)
		r.id = g[0]
		r.name = g[1]
		data.db["actors"].by_id[g[0]] = r
		data.db["actors"].records.append(r)


## A new game on the start map (saving needs one), with this party.
func _on_map(party: Array) -> void:
	env.game.new_game()
	await env.settle()
	env.game.setup_test_party(party.map(func(id): return {"actor": id, "level": 1}))


func _run_battle(args: Dictionary) -> Dictionary:
	var rpg: Node = env.rpg
	return await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), args, {"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)


## Starts a battle without waiting; returns the scene. `out.r` is set when it ends, and
## `out.log` / `out.outcome` keep the scene's log and outcome (the scene is freed after).
func _start_battle(args: Dictionary, out: Dictionary) -> Node:
	var run := func():
		out.r = await _run_battle(args)
	run.call()
	var scene: Node = env.rpg.ui.scene_stack[-1]
	scene.finished.connect(func(_res: Variant) -> void:
		out["log"] = scene.log_lines.duplicate()
		out["outcome"] = scene.outcome)
	return scene


## Lets a battle that waits for the player play itself out (the open command is confirmed).
func _finish(scene: Node, out: Dictionary) -> void:
	env.rpg.ui.auto_advance = true
	var end := Time.get_ticks_msec() + 20000
	while not out.has("r") and Time.get_ticks_msec() < end:
		if is_instance_valid(scene) and scene.core != null:
			scene.auto = true
			if not scene.core.is_timed() and scene.phase != "":
				if scene.phase == "party":
					scene.cmd_list.select(0)
				scene.handle_action("ok")
		await tree.process_frame
	assert_eq(out.get("r", {}).get("status", ""), "finished", "the battle ends")


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func _auto_battle(troop := "slimes", extra := {}) -> Dictionary:
	var args := {"troop": troop, "auto": true, "can_escape": false, "can_lose": true}
	args.merge(extra, true)
	return await _run_battle(args)


## Everyone back to full health (party HP carries over from battle to battle).
func _heal() -> void:
	for b in env.rpg.state.party_battlers():
		env.rpg.rules.recover_all(b)


func _log(scene: Node, out: Dictionary) -> Array:
	return out.log if out.has("log") else (scene.log_lines if is_instance_valid(scene) else [])


func _probe() -> Object:
	return env.rpg.extension("battle_probe")


func _core(party_ids: Array, troop: String, rng_seed: int, rules: RPGRuleSystem, db) -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var core := RPGBattleCore.new(party, db.record("troops", troop), rules, RPGRandom.new(rng_seed))
	return core


## A turn battle played by the core alone: returns [outcome, HP after each action, RNG state].
func _play_core(core: RPGBattleCore) -> Array:
	core.start()
	var trace := []
	while core.battle_over() == "" and core.turn < 60:
		core.begin_turn()
		for i in core.inputs_needed():
			core.set_action(i, {"kind": "attack", "target": -1})
		var r := core.next_action()
		while not r.is_empty():
			var hp := []
			for b in core.all_battlers():
				hp.append(b.get_resource("hp"))
			trace.append(hp)
			r = core.next_action()
		core.end_turn()
	return [core.battle_over(), trace, core.rng.randi_range(0, 1 << 30)]


# --- hooks: determinism ----------------------------------------------------------------------------

func test_hooks_do_not_change_a_seeded_battle() -> void:
	var db = FakeDB.from_folder("res://rpg/database")
	for s in [3, 17, 4242]:
		var rules := RPGRuleSystem.load_rules("classic", db)
		var plain := _play_core(_core(["hero", "mira"], "goblin_boss", s, rules, db))
		var rules2 := RPGRuleSystem.load_rules("classic", db)
		var hooked_core := _core(["hero", "mira"], "goblin_boss", s, rules2, db)
		var hooks := PassHooks.new()
		hooked_core.hooks = hooks
		var hooked := _play_core(hooked_core)
		assert_eq(hooked, plain, "seed %d: the same battle with pass-through hooks" % s)
		assert_true(hooks.calls.has("turn_started") and hooks.calls.has("action_chosen") and hooks.calls.has("damage_calculated"), "the hooks were called")
		assert_false(rules2.damage_filter.is_valid(), "the damage filter is only set while an action is applied")


func test_seeded_scene_battle_is_the_same_with_plugins_and_handlers() -> void:
	# The same seed through the real battle scene: no extensions, every battle plugin on, and a probe
	# whose handlers return what they got. The log and the next random number must match.
	var runs := []
	for setup in [[], PLUGINS, ["battle_probe"]]:
		plugin_env(setup)
		if setup.has("battle_probe"):
			_probe().mode = "same"
		env.rpg.rng.seed = 777
		var out := {}
		var scene := _start_battle({"troop": "goblin_boss", "auto": true, "can_lose": true}, out)
		await _wait_until(func(): return out.has("r"))
		runs.append([out.log, env.rpg.rng.randi_range(0, 1 << 30), out.r.value.outcome])
		await env.destroy()
		env = null
	assert_eq(runs[1], runs[0], "the battle plugins leave a seeded battle as it was")
	assert_eq(runs[2], runs[0], "handlers that change nothing leave it as it was")


# --- hooks: core signals ---------------------------------------------------------------------------

func test_hook_signals_and_entry_scripts() -> void:
	plugin_env(["battle_probe"])
	var seen := {}
	for sig in ["battle_scene_ready", "turn_started", "action_chosen", "damage_calculated", "state_changed", "battler_defeated", "victory"]:
		var name_: String = sig
		var n: int = env.rpg.get_signal_list().filter(func(s): return s.name == name_)[0].args.size()
		match n:
			1: env.rpg.connect(sig, func(_a): seen[name_] = true)
			3: env.rpg.connect(sig, func(_a, _b, _c): seen[name_] = true)
			4: env.rpg.connect(sig, func(_a, _b, _c, _d): seen[name_] = true)
	var r := await _auto_battle()
	assert_eq(r.status, "finished")
	var names: Array = _probe().names()
	for h in ["ready", "turn", "chosen", "damage", "state", "defeated", "victory"]:
		assert_true(names.has(h), "entry script got %s: %s" % [h, names])
	assert_eq(seen.size(), 7, "every RPG signal was emitted: %s" % [seen.keys()])
	# A knockout is a state change (the death state) and a defeat, in that order.
	var ev: Array = _probe().events
	var first_defeat := -1
	for i in ev.size():
		if ev[i][0] == "defeated":
			first_defeat = i
			break
	assert_true(first_defeat > 0 and ev[first_defeat - 1][0] == "state" and ev[first_defeat - 1][3] == true, "knocked out, then defeated")
	assert_eq(ev.filter(func(e): return e[0] == "defeated").size(), 2, "two slimes defeated")
	assert_eq(ev[0][0], "ready", "the scene hook comes first")


func test_damage_hook_changes_the_damage() -> void:
	plugin_env(["battle_probe"])
	var probe := _probe()
	probe.mode = "zero"
	env.rpg.rng.seed = 5
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	await _wait_until(func(): return out.has("r") or scene.core.turn >= 3)
	for e in scene.core.enemies:
		assert_eq(e.get_resource("hp"), scene.max_res(e, "hp"), "no damage gets through")
	assert_true(probe.events.any(func(e): return e[0] == "damage" and e[3] > 0), "the rolls were reported before the change")
	scene.core.force_result("escape")
	await _wait_until(func(): return out.has("r"))
	# Doubled damage: the core result and the log show the doubled number.
	await env.destroy()
	plugin_env(["battle_probe"])
	_probe().mode = "double"
	env.rpg.rng.seed = 5
	var out2 := {}
	var scene2 := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out2)
	await _wait_until(func(): return out2.has("r"))
	var dmg: Array = _probe().events.filter(func(e): return e[0] == "damage")
	assert_false(dmg.is_empty())
	var rolled := int(dmg[0][3])
	var term: String = env.rpg.rules.term("damage", [dmg[0][2], rolled * 2])
	assert_true((out2.log as Array).has(term), "the log shows the doubled damage (%s)" % term)


func test_action_hook_cancels_changes_and_redirects() -> void:
	plugin_env(["battle_probe"])
	var probe := _probe()
	probe.mode = "cancel_actors"
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	await _wait_until(func(): return out.has("r") or scene.core.turn >= 3)
	for e in scene.core.enemies:
		assert_eq(e.get_resource("hp"), scene.max_res(e, "hp"), "cancelled actor actions do nothing")
	assert_false(_log(scene, out).has(env.rpg.rules.term("attack", ["Alex"])), "a cancelled action shows nothing")
	scene.core.force_result("escape")
	await _wait_until(func(): return out.has("r"))
	# A cancelled item is given back.
	await env.destroy()
	plugin_env(["battle_probe"])
	_probe().mode = "cancel_actors"
	env.rpg.state.change_items("potion", "increase", 2)
	var potions: int = env.rpg.state.item_count("potion")
	var db = env.rpg.data
	var rules: RPGRuleSystem = env.rpg.rules
	var core := RPGBattleCore.new([env.rpg.state.actor("hero")], db.record("troops", "slimes"), rules, RPGRandom.new(1))
	core.hooks = env.rpg
	core.item_consumer = func(id: String) -> bool:
		env.rpg.state.change_items(id, "decrease", 1)
		return true
	core.item_refund = func(id: String) -> void: env.rpg.state.change_items(id, "increase", 1)
	core.start()
	core.begin_turn()
	assert_true(core.set_action(0, {"kind": "item", "item": "potion", "target": 0}))
	var r := core.next_action()
	while not r.is_empty() and r.user.is_enemy():
		r = core.next_action()
	assert_true(r.get("cancelled", false), "the actor's action was cancelled")
	assert_eq(env.rpg.state.item_count("potion"), potions, "the potion came back")
	# Attacks turned into guards.
	await env.destroy()
	plugin_env(["battle_probe"])
	_probe().mode = "actors_guard"
	var out3 := {}
	var scene3 := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out3)
	await _wait_until(func(): return out3.has("r") or scene3.core.turn >= 2)
	assert_true(_log(scene3, out3).has(env.rpg.rules.term("guard", ["Alex"])), "the attack became a guard")
	scene3.core.force_result("escape")
	await _wait_until(func(): return out3.has("r"))
	# Enemies redirected onto themselves.
	await env.destroy()
	plugin_env(["battle_probe"])
	_probe().mode = "enemies_hit_themselves"
	var hero: Object = env.rpg.state.actor("hero")
	var out4 := {}
	var scene4 := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out4)
	await _wait_until(func(): return out4.has("r"))
	assert_eq(hero.get_resource("hp"), env.rpg.rules.max_resource(hero, "hp"), "no slime hit the hero")
	assert_eq(out4.outcome, "win")


func test_victory_hook_changes_rewards() -> void:
	plugin_env(["battle_probe"])
	_probe().mode = "bonus"
	var gold0: int = env.rpg.state.gold
	var hero: Object = env.rpg.state.actor("hero")
	var exp0: int = hero.exp
	var r := await _auto_battle()
	assert_eq(r.value.outcome, "win")
	assert_true(int(r.value.rewards.gold) >= 1000, "the changed rewards are reported")
	assert_eq(env.rpg.state.gold - gold0, int(r.value.rewards.gold), "and given")
	assert_eq(hero.exp, exp0, "no EXP (the hook set it to 0)")


func test_troop_pages_read_extension_conditions() -> void:
	plugin_env(["battle_probe"])
	var data: RPGProjectData = env.rpg.data
	var t: Dictionary = data.record("troops", "slimes").duplicate(true)
	t.id = "probe_troop"
	t.pages = [
		{"id": "flagged", "conditions": [{"kind": "probe_battle_flag"}], "span": "once_per_battle", "commands": [{"type": "set_variable", "id": "talks", "op": "set", "value": 5}]},
		{"id": "map_only", "conditions": [{"kind": "probe_map_flag"}], "span": "once_per_battle", "commands": [{"type": "set_variable", "id": "talks", "op": "set", "value": 9}]},
	]
	data.db["troops"].by_id["probe_troop"] = t
	data.db["troops"].records.append(t)
	env.rpg.state.set_variable("talks", 0)
	await _auto_battle("probe_troop")
	assert_eq(int(env.rpg.state.get_variable("talks")), 0, "the flag is off: no page")
	_probe().flag = true
	await _auto_battle("probe_troop")
	assert_eq(int(env.rpg.state.get_variable("talks")), 5, "a battle condition kind runs its page; a map-only kind does not")


func test_scene_hooks_nodes_members_popups_victory() -> void:
	plugin_env(["battle_probe"])
	var probe := _probe()
	# battler_node: one node per battler, following it in both views.
	for view in VIEWS:
		probe.mode = "nodes"
		var out := {}
		env.rpg.ui.auto_advance = false
		var scene := _start_battle({"troop": "slimes", "battle_view": view, "can_lose": true}, out)
		await frames(2)
		for b in scene.core.all_battlers():
			var n: Node2D = scene.battler_node(b)
			assert_true(n.has_node("ProbeMark"), "%s: a node for %s" % [view, b.name])
			assert_eq(scene.battler_node(b), n, "the same node every time")
			var r: Rect2 = scene.battler_rect(b)
			assert_eq(n.position, Vector2(round(r.position.x + r.size.x / 2.0), round(r.end.y)), "%s: at the bottom centre of %s" % [view, b.name])
		if view == "side":
			var a: RPGBattler = scene.core.party[0]
			var before: Vector2 = scene.battler_node(a).position
			scene.actor_nodes[a].offset = Vector2(-22, 0)
			await frames(2)
			assert_eq(scene.battler_node(a).position.x, before.x - 22, "the node follows the actor stepping forward")
		scene.auto = true
		env.rpg.ui.auto_advance = true
		scene.handle_action("ok")
		await _wait_until(func(): return out.has("r"))
	# battle_members: only the member the probe picks fights.
	_heal()
	probe.mode = "solo"
	var out2 := {}
	var s2 := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out2)
	assert_eq(s2.core.party.map(func(b): return b.id), ["mira"], "battle_members picked the fighters")
	await _wait_until(func(): return out2.has("r"))
	# battle_popup: the extension's node replaces the default label, with the style.
	_heal()
	probe.mode = "popup"
	probe.events.clear()
	var out3 := {}
	var s3 := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out3)
	await _wait_until(func(): return out3.has("r"))
	var styles: Array = probe.events.filter(func(e): return e[0] == "popup").map(func(e): return e[1])
	assert_true(styles.has("damage") or styles.has("critical"), "damage popups went to the extension: %s" % [styles])
	# victory_scene: the extension's node runs instead of the reward messages.
	_heal()
	probe.mode = "victory_node"
	var out4 := {}
	var s4 := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out4)
	await _wait_until(func(): return out4.has("r"))
	assert_eq(out4.r.status, "finished")
	assert_false((out4.log as Array).has(env.rpg.rules.term("victory")), "no reward messages")
	assert_true(probe.victory_info.has("actors") and probe.victory_info.has("battle"), "the node got the rewards, the actors and the battle")
	assert_eq(int(probe.victory_info.get("gold", -1)), int(out4.r.value.rewards.gold))


# --- off by default --------------------------------------------------------------------------------

func test_battle_plugins_are_off_by_default() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	for id in PLUGINS:
		assert_true(rpg.extension(id) == null, "%s not running" % id)
		assert_false(rpg.extension_enabled(id))
	for t in PLUGIN_COMMANDS:
		assert_false(rpg.registry.has_command(t), "%s not offered" % t)
	assert_false(rpg.saves.extension_hooks.has("enemy_records"))
	assert_false(rpg.saves.extension_hooks.has("party_formation"))
	var fields: Dictionary = rpg.registry.merged_custom_fields(rpg.data.project.get("custom_fields", {}))
	assert_false(fields.has("enemies"), "no enemy custom fields")
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	assert_eq(scene.battler_layer.get_child_count(), 0, "no battler nodes made")
	await _wait_until(func(): return out.has("r"))
	assert_true((out.log as Array).has(rpg.rules.term("victory")), "the reward messages as before")
	env.game.new_game()
	await env.settle()
	env.game.open_menu()
	await frames(2)
	var menu: Node = rpg.ui.scene_stack[-1]
	assert_eq(menu.command_ids(), menu.COMMANDS, "no Formation or Bestiary entry")
	menu.close()
	await frames(2)


# --- W6 enemy gauges -------------------------------------------------------------------------------

func _gauge(scene: Node, e: RPGBattler) -> Node:
	var n: Node2D = scene.battler_node(e)
	return n.get_node_or_null("HPGauge")


func test_w6_gauges_follow_settings_and_hide_for_bosses() -> void:
	plugin_env(["enemy_gauges"], {"enemy_gauges": {"show": "always", "numbers": "value_max"}})
	env.rpg.data.record("enemies", "goblin")["custom"] = {"hide_hp_gauge": true}
	env.rpg.ui.auto_advance = false
	var out := {}
	var scene := _start_battle({"troop": "goblin_boss", "can_lose": true}, out)
	await frames(3)
	var goblin: RPGBattler = scene.core.enemies[0]
	var slime: RPGBattler = scene.core.enemies[1]
	assert_true(_gauge(scene, goblin) == null, "no gauge for a boss (hide_hp_gauge)")
	var g: Node = _gauge(scene, slime)
	assert_true(g != null, "a slime has a gauge")
	assert_true(g.wanted(), "always shown")
	assert_eq(g._label.text, "40/40", "numbers")
	# Damage drains the bar towards the new value.
	slime.set_resource("hp", 10)
	await frames(2)
	assert_true(g.shown_ratio < 1.0 and g.shown_ratio > 0.25, "sliding: %s" % g.shown_ratio)
	await _wait_until(func(): return is_equal_approx(g.shown_ratio, 0.25), 2.0)
	assert_true(is_equal_approx(g.shown_ratio, 0.25), "settled at 10/40")
	assert_eq(g._label.text, "10/40")
	scene.auto = true
	env.rpg.ui.auto_advance = true
	scene.handle_action("ok")
	await _wait_until(func(): return out.has("r"))
	# "targeted": only while the player points at it.
	await env.destroy()
	plugin_env(["enemy_gauges"], {"enemy_gauges": {"show": "targeted"}})
	env.rpg.ui.auto_advance = false
	var out2 := {}
	var s2 := _start_battle({"troop": "slimes", "can_lose": true}, out2)
	await _wait_until(func(): return s2.phase == "party")
	var g0: Node = _gauge(s2, s2.core.enemies[0])
	var g1: Node = _gauge(s2, s2.core.enemies[1])
	assert_false(g0.wanted(), "hidden until targeted")
	s2.handle_action("ok")          # Fight
	s2.handle_action("ok")          # Attack -> target
	assert_eq(s2.phase, "target_enemy")
	assert_true(g0.wanted(), "the targeted slime shows its gauge")
	assert_false(g1.wanted(), "the other does not")
	s2.handle_action("right")
	assert_true(g1.wanted() and not g0.wanted(), "the gauge follows the target")
	s2.auto = true
	env.rpg.ui.auto_advance = true
	s2.handle_action("ok")
	await _wait_until(func(): return out2.has("r"))


func test_w6_records_defeats_and_shows_after_the_first() -> void:
	plugin_env(["enemy_gauges"], {"enemy_gauges": {"show": "defeated"}})
	await _on_map(["hero", "mira"])
	var eg: Object = env.rpg.extension("enemy_gauges")
	assert_false(eg.was_defeated("slime"))
	env.rpg.ui.auto_advance = false
	var out := {}
	var scene := _start_battle({"troop": "slimes", "can_lose": true}, out)
	await frames(2)
	var g: Node = _gauge(scene, scene.core.enemies[1])
	assert_false(g.wanted(), "never defeated: no gauge yet")
	scene.core.enemies[0].set_resource("hp", 0)
	env.rpg.rules.add_state(scene.core.enemies[0], "knockout")
	scene.core.report_changes()
	assert_eq(eg.defeated_count("slime"), 1, "the defeat is recorded")
	assert_true(g.wanted(), "now the other slime shows its gauge")
	await _finish(scene, out)
	assert_eq(eg.defeated_count("slime"), 2)
	assert_eq(int(eg.records().seen.slime), 1, "seen once per battle")
	# Saved with the game.
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	eg.records().clear()
	assert_true((await env.rpg.saves.load_slot(SLOT)).is_ok())
	assert_eq(env.rpg.extension("enemy_gauges").defeated_count("slime"), 2, "loaded back")


func test_w6_styled_popups() -> void:
	plugin_env(["enemy_gauges"])
	var eg: Object = env.rpg.extension("enemy_gauges")
	var hero: Object = env.rpg.state.actor("hero")
	var crit: Control = eg.battle_popup(hero, "25", "critical", null)
	assert_true(crit != null)
	var texts: Array = crit.get_children().map(func(l): return l.text)
	assert_true(texts.has("25") and texts.has("Critical!"), "the number and the tag: %s" % [texts])
	var miss: Control = eg.battle_popup(hero, "Miss", "miss", null)
	assert_eq(miss.get_child(0).text, "Miss")
	var heal: Control = eg.battle_popup(hero, "30", "heal", null)
	assert_eq(heal.get_child(0).text, "+30", "a + before recovery")
	assert_true(eg.battle_popup(hero, "1", "damage", Control.new()) == null, "an earlier extension's node is kept")
	for c in [crit, miss, heal]:
		c.free()
	# In a battle the scene shows them over the battlers.
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	var found := false
	for i in 600:
		for c in scene.popups.get_children():
			if str(c.name).begins_with("Popup_"):
				found = true
		if found or out.has("r"):
			break
		await tree.process_frame
	assert_true(found, "styled popups appear in the battle")
	await _wait_until(func(): return out.has("r"))
	# Off: the default label.
	await env.destroy()
	plugin_env(["enemy_gauges"], {"enemy_gauges": {"popups": false}})
	assert_true(env.rpg.extension("enemy_gauges").battle_popup(env.rpg.state.actor("hero"), "3", "damage", null) == null)


# --- W7 victory aftermath --------------------------------------------------------------------------

func _rich_slimes() -> void:
	env.rpg.data.record("enemies", "slime")["exp"] = 200


func test_w7_results_and_level_up_pages() -> void:
	plugin_env(["victory_aftermath"], {"victory_aftermath": {"skip_auto": false}})
	_rich_slimes()
	env.rpg.data.record("actors", "hero")["custom"] = {"level_up_quotes": "Stronger!\nOne more!", "new_skill_quotes": "A new move!"}
	var va: Object = env.rpg.extension("victory_aftermath")
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	await _wait_until(func(): return out.has("r"))
	assert_eq(out.r.status, "finished")
	assert_eq(va.shown_count, 1, "the aftermath ran")
	assert_eq(va.last_pages, ["results", "level:hero", "level:mira"], "results, then one page per actor who went up")
	assert_false((out.log as Array).has(env.rpg.rules.term("victory")), "instead of the reward messages")
	var info: Dictionary = va.last_info
	var hero_row: Dictionary = info.actors[0]
	assert_eq(hero_row.id, "hero")
	assert_true(int(hero_row.new_level) >= 3 and int(hero_row.old_level) == 1, "levels %s -> %s" % [hero_row.old_level, hero_row.new_level])
	assert_true((hero_row.learned as Array).has("power_strike"), "the new skill is listed")
	assert_true(int(hero_row.new_stats.mhp) > int(hero_row.old_stats.mhp), "stats went up")
	assert_true(va.quote_for("hero", true) == "A new move!", "a new-skill quote")
	assert_true(va.quote_for("hero", false) in ["Stronger!", "One more!"], "a level-up quote")
	assert_eq(va.quote_for("mira", false), "", "no quotes")
	assert_eq(env.rpg.state.actor("hero").level, int(hero_row.new_level), "the level is real")


func test_w7_screen_by_hand_fill_and_ok() -> void:
	plugin_env(["victory_aftermath"], {"victory_aftermath": {"fill_seconds": 1.0}})
	var va: Object = env.rpg.extension("victory_aftermath")
	var hero: Object = env.rpg.state.actor("hero")
	var rules: Object = env.rpg.rules
	var e2 := int(rules.exp_for_level(hero.class_id, 2))
	var e3 := int(rules.exp_for_level(hero.class_id, 3))
	var ups: Array = rules.gain_exp(hero, e3 + 1 - hero.exp)
	var info := {"exp": e3 + 1, "gold": 40, "items": [{"kind": "item", "id": "potion", "count": 2}], "auto": false,
		"actors": [{"actor": hero, "id": "hero", "name": hero.name, "old_level": 1, "new_level": hero.level, "old_exp": 0,
			"new_exp": hero.exp, "level_ups": ups, "old_stats": {"mhp": 10}, "new_stats": {"mhp": 20}, "gains": {"mhp": 10}, "learned": []}]}
	env.rpg.ui.auto_advance = false
	var screen: Node = va.victory_scene(info)
	assert_true(screen != null and screen.page == "results")
	screen.set_fill(0.0)
	assert_eq(screen.row_state(0).level, 1)
	assert_false(screen.row_state(0).tag)
	# Half way the bar has crossed level 2 (e2 of e3 + 1 EXP) on the way to 3.
	screen.set_fill(float(e2 + 1) / float(e3 + 1))
	assert_eq(screen.row_state(0).level, 2, "crossed level 2")
	assert_true(screen.row_state(0).tag, "LEVEL UP! shows")
	screen.handle_action("ok")
	assert_eq(screen.fill, 1.0, "OK fills the bars at once")
	assert_eq(screen.row_state(0).level, 3)
	screen.handle_action("ok")
	assert_eq(screen.page, "level", "then the level-up page")
	var finished := [false]
	screen.finished.connect(func(): finished[0] = true)
	screen.handle_action("ok")
	assert_true(finished[0], "the last OK finishes")
	env.rpg.ui.close_scene(screen)
	# Level-up screens off: results only.
	env.rpg.extensions.set_settings("victory_aftermath", {"level_up_screens": false})
	var s2: Node = va.victory_scene(info)
	s2.handle_action("ok")
	s2.handle_action("ok")
	assert_eq(s2.pages_shown, ["results"])
	assert_eq(s2.page, "done")
	env.rpg.ui.close_scene(s2)
	env.rpg.ui.auto_advance = true


func test_w7_skipped_in_auto_battle_by_default() -> void:
	plugin_env(["victory_aftermath"])
	var va: Object = env.rpg.extension("victory_aftermath")
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	await _wait_until(func(): return out.has("r"))
	assert_eq(va.shown_count, 0, "no aftermath in auto battle")
	assert_true((out.log as Array).has(env.rpg.rules.term("victory")), "the reward messages instead")


# --- W9 party formation ----------------------------------------------------------------------------

func test_w9_active_members_fight() -> void:
	plugin_env(["party_formation"], {"party_formation": {"max_battle": 3}}, ["hero", "mira", "gus", "pip", "kai"])
	var pf: Object = env.rpg.extension("party_formation")
	assert_eq(pf.active_ids(), ["hero", "mira", "gus"])
	assert_eq(pf.reserve_ids(), ["pip", "kai"])
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true}, out)
	assert_eq(scene.core.party.map(func(b): return b.id), ["hero", "mira", "gus"], "only the battle row fights")
	await _wait_until(func(): return out.has("r"))
	# A new member joins the reserve when the battle row is full; one leaving frees a place.
	env.rpg.state.remove_actor("mira")
	assert_eq(pf.active_ids(), ["hero", "gus", "pip"], "the first reserve member fills the gap")
	env.rpg.state.add_actor("mira")
	assert_eq(pf.reserve_ids(), ["kai", "mira"])
	assert_eq(Array(env.rpg.state.party), ["hero", "gus", "pip", "kai", "mira"], "the party order follows the formation")
	# Reserve members get their share of EXP.
	env.rpg.extensions.set_settings("party_formation", {"max_battle": 3, "reserve_exp": 50})
	var kai: Object = env.rpg.state.actor("kai")
	var exp0: int = kai.exp
	var r := await _auto_battle()
	assert_eq(kai.exp - exp0, int(int(r.value.rewards.exp) * 0.5), "half the EXP in reserve")


func test_w9_screen_swaps_locks_and_required() -> void:
	plugin_env(["party_formation"], {"party_formation": {"max_battle": 2, "allow_remove": true}}, ["hero", "mira", "gus", "pip"])
	var pf: Object = env.rpg.extension("party_formation")
	var screen: Node = pf.make_screen()
	await frames(1)
	assert_eq(screen.slots(0), ["hero", "mira"])
	assert_eq(screen.slots(1), ["gus", "pip", ""], "the reserve, plus a slot to move a member out")
	# Swap mira (battle row 1) with gus (reserve 0) by picking both.
	screen.col = 0
	screen.row = 1
	screen.choose()
	assert_eq(screen.picked.id, "mira")
	screen.col = 1
	screen.row = 0
	screen.choose()
	assert_eq(pf.active_ids(), ["hero", "gus"])
	assert_eq(pf.reserve_ids(), ["mira", "pip"])
	# Locked: cannot be picked or swapped with.
	pf.set_locked("hero", true)
	screen.col = 0
	screen.row = 0
	screen.choose()
	assert_true(screen.picked.is_empty(), "a locked member cannot be picked")
	assert_false(screen.try_place(1, 0, 0, 0), "nor swapped with")
	# Required: cannot go to the reserve.
	pf.set_required("gus", true)
	assert_false(screen.try_place(0, 1, 1, 0), "a required member stays in battle")
	assert_false(screen.try_place(0, 1, 1, 2), "nor moved out")
	pf.set_required("gus", false)
	assert_true(screen.try_place(0, 1, 1, 2), "moved out to the reserve")
	assert_eq(pf.active_ids(), ["hero"])
	var empty_at: int = screen.slots(1).size() - 1
	assert_eq(screen.slots(1)[empty_at], "")
	assert_false(screen.try_place(0, 0, 1, empty_at), "hero is locked")
	pf.set_locked("hero", false)
	assert_false(screen.try_place(0, 0, 1, empty_at), "the last member cannot leave")
	assert_true(screen.try_place(1, 0, 0, 1), "a reserve member into the empty battle slot")
	assert_eq(pf.active_ids(), ["hero", "mira"])
	# Remove not allowed: no slot to move a member out.
	env.rpg.extensions.set_settings("party_formation", {"max_battle": 2, "allow_remove": false})
	screen._reload()
	assert_eq(screen.slots(1), ["pip", "gus"], "no empty reserve slot")
	# Mouse: hovering a slot moves the cursor.
	var targets: Array = screen.pointer_targets()
	assert_eq(targets.size(), 4)
	targets[3].select.call()
	assert_eq([screen.col, screen.row], [1, 1])
	screen.handle_action("cancel")
	await frames(1)
	env.rpg.ui.close_scene(screen)


func test_w9_commands_menu_and_save() -> void:
	plugin_env(["party_formation"], {"party_formation": {"menu_icon": 158}}, ["hero", "mira", "gus", "pip", "kai"])
	var pf: Object = env.rpg.extension("party_formation")
	env.game.new_game()
	await env.settle()
	env.game.setup_test_party([{"actor": "hero"}, {"actor": "mira"}, {"actor": "gus"}, {"actor": "pip"}, {"actor": "kai"}])
	assert_eq(pf.active_ids(), ["hero", "mira", "gus", "pip"])
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "formation_size", "count": 2},
		{"type": "formation_member", "actor": "kai", "lock": "lock", "require": "require", "move": "keep"},
	])
	assert_true(r.is_ok(), str(r.message))
	assert_eq(pf.active_ids(), ["hero", "kai"], "a required member is made active")
	assert_true(pf.is_locked("kai"))
	r = await env.rpg.run_commands([{"type": "formation_member", "actor": "kai", "lock": "keep", "require": "keep", "move": "reserve"}])
	assert_true(r.is_error(), "a required member cannot be moved to the reserve")
	r = await env.rpg.run_commands([{"type": "formation_member", "actor": "pip", "lock": "keep", "require": "keep", "move": "active"}])
	assert_true(r.is_ok())
	assert_eq(pf.active_ids(), ["pip", "kai"], "pip took the place of the last member who was free to go")
	# Saved with the game.
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	r = await env.rpg.run_commands([{"type": "formation_size", "count": 0}, {"type": "formation_member", "actor": "kai", "lock": "unlock", "require": "release", "move": "keep"}])
	assert_eq(pf.max_battle(), 4)
	assert_true((await env.rpg.saves.load_slot(SLOT)).is_ok())
	pf = env.rpg.extension("party_formation")
	assert_eq(pf.max_battle(), 2, "the battle size came back")
	assert_eq(pf.active_ids(), ["pip", "kai"])
	assert_true(pf.is_locked("kai") and pf.is_required("kai"))
	# The main menu has Formation; choosing it opens the screen.
	env.game.open_menu()
	await frames(2)
	var menu: Node = env.rpg.ui.scene_stack[-1]
	assert_true(menu.command_ids().has("formation"), str(menu.command_ids()))
	var item: Dictionary = menu.menu_items[menu.command_ids().find("formation")]
	assert_eq(int(item.icon), 158, "the icon from the settings")
	menu.choose("formation")
	await frames(2)
	var screen: Node = env.rpg.ui.scene_stack[-1]
	assert_true(screen.has_method("try_place"), "the formation screen is open")
	screen.close()
	await frames(2)
	assert_eq(env.rpg.ui.scene_stack[-1], menu, "back to the menu")
	menu.close()
	await frames(2)


# --- W10 bestiary ----------------------------------------------------------------------------------

func test_w10_records_reveals_and_completion() -> void:
	plugin_env(["bestiary", "enemy_gauges"], {"bestiary": {"categories": [{"id": "ooze", "label": "Oozes"}], "seen_shows": "image"}})
	await _on_map(["hero", "mira"])
	var bk: Object = env.rpg.extension("bestiary")
	var eg: Object = env.rpg.extension("enemy_gauges")
	env.rpg.data.record("enemies", "slime")["custom"] = {"category": "ooze", "lore": "It wobbles."}
	env.rpg.data.record("enemies", "bat")["custom"] = {"hide_in_bestiary": true}
	assert_eq(bk.listed_ids(), ["slime", "goblin"], "bat is left out")
	assert_eq(bk.known("slime"), "none")
	assert_false(bk.reveals("slime", "name"))
	var won := await _auto_battle("slimes")
	assert_eq(won.value.outcome, "win")
	assert_eq(bk.known("slime"), "defeated")
	assert_eq(bk.defeated_count("slime"), 2, "both slimes, counted once (the gauges plugin does not count too)")
	assert_eq(eg.defeated_count("slime"), 2, "the gauges plugin reads the same record")
	assert_eq(bk.seen_count("slime"), 1, "seen once per battle")
	assert_eq(bk.known("goblin"), "none")
	assert_true(bk.reveals("slime", "all"))
	var c: Dictionary = bk.completion()
	assert_eq([c.total, c.seen, c.defeated, c.percent], [2, 1, 1, 50])
	assert_eq(bk.ids_in("ooze"), ["slime"])
	assert_eq(bk.completion("ooze").percent, 100)
	# Seen but not defeated shows the name and picture only (setting).
	env.rpg.data.record("enemies", "bat")["custom"] = {}
	var r: RPGResult = await env.rpg.run_commands([{"type": "reveal_enemy", "all": false, "enemy": "bat", "level": "seen"}])
	assert_true(r.is_ok(), str(r.message))
	assert_eq(bk.known("bat"), "seen")
	assert_true(bk.reveals("bat", "image"))
	assert_false(bk.reveals("bat", "stats"))
	# Weaknesses from the rule system: slimes take 150% from fire.
	var rates: Array = bk.element_rates("slime")
	assert_eq(rates.size(), 1)
	assert_eq(rates[0].id, "fire")
	assert_true(is_equal_approx(float(rates[0].rate), 1.5))
	var state0: Dictionary = env.rpg.rng.get_state()
	bk.element_rates("goblin")
	bk.enemy_battler("slime")
	assert_eq(env.rpg.rng.get_state(), state0, "reading the book does not move the game's RNG")
	assert_true(env.rpg.rules.rng == env.rpg.rng, "the rules have the game's RNG back")
	# Saved with the game.
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	bk.records().clear()
	assert_eq(bk.known("slime"), "none")
	assert_true((await env.rpg.saves.load_slot(SLOT)).is_ok())
	assert_eq(env.rpg.extension("bestiary").known("slime"), "defeated", "loaded back")
	# Reveal every enemy (testing).
	r = await env.rpg.run_commands([{"type": "reveal_enemy", "all": true, "enemy": "", "level": "defeated"}])
	assert_eq(env.rpg.extension("bestiary").completion().percent, 100)


func test_w10_screen_masks_and_tabs() -> void:
	plugin_env(["bestiary"], {"bestiary": {"categories": [{"id": "ooze", "label": "Oozes"}], "mask": "silhouette"}})
	var bk: Object = env.rpg.extension("bestiary")
	env.rpg.data.record("enemies", "slime")["custom"] = {"category": "ooze", "lore": "It wobbles."}
	bk.reveal("slime", "defeated")
	var screen: Node = bk.make_screen()
	await frames(1)
	var texts: Array = screen.list.items.map(func(it): return it.text)
	assert_eq(texts, ["001 Slime", "002 ??????", "003 ??????"], "unseen enemies are masked")
	assert_false(screen.list.items[1].enabled)
	assert_eq(screen.current_id(), "slime")
	assert_true(screen._completion.text.ends_with("33%"), screen._completion.text)
	screen.handle_action("right")
	assert_eq(screen.tab, 1, "the Oozes tab")
	assert_eq(screen.ids, ["slime"])
	assert_true(screen._completion.text.ends_with("100%"))
	# Mouse: the tabs and rows can be pointed at.
	var targets: Array = screen.pointer_targets()
	assert_true(targets.size() >= 3, "a row and two tabs")
	targets[-2].select.call()
	assert_eq(screen.tab, 0, "hovering a tab chooses it")
	screen.handle_action("cancel")
	await frames(1)
	env.rpg.ui.close_scene(screen)
	# The "hidden" mask leaves unseen enemies out of the list.
	env.rpg.extensions.set_settings("bestiary", {"mask": "hidden"})
	assert_eq(bk.listed_ids(), ["slime"])
	assert_eq(bk.completion().total, 3, "completion still counts every enemy")
	# The main menu entry opens the book.
	env.game.new_game()
	await env.settle()
	env.game.open_menu()
	await frames(2)
	var menu: Node = env.rpg.ui.scene_stack[-1]
	assert_true(menu.command_ids().has("bestiary"))
	menu.choose("bestiary")
	await frames(2)
	var book: Node = env.rpg.ui.scene_stack[-1]
	assert_true(book.has_method("set_tab"), "the bestiary is open")
	book.close()
	await frames(2)
	menu.close()
	await frames(2)


# --- every view and system with the plugins on -----------------------------------------------------

func test_all_views_and_systems_with_the_plugins_on() -> void:
	plugin_env(PLUGINS, {"party_formation": {"max_battle": 2}, "victory_aftermath": {"skip_auto": false}}, ["hero", "mira", "gus"])
	_rich_slimes()
	var n_runs := 0
	for view in VIEWS:
		for system in SYSTEMS:
			var label := "%s/%s" % [view, system]
			_heal()
			env.rpg.rng.seed = 99
			var out := {}
			var scene := _start_battle({"troop": "slimes", "auto": true, "can_lose": true, "battle_view": view, "battle_system": system}, out)
			assert_eq(scene.core.party.size(), 2, "%s: two battle members" % label)
			for e in scene.core.enemies:
				assert_true(_gauge(scene, e) != null, "%s: gauges" % label)
			await _wait_until(func(): return out.has("r"), 20.0)
			assert_eq(out.get("r", {}).get("status", ""), "finished", "%s: finished" % label)
			assert_eq(out.r.value.outcome, "win", label)
			assert_eq(env.rpg.extension("victory_aftermath").shown_count, n_runs + 1, "%s: the aftermath ran" % label)
			n_runs += 1
	assert_eq(env.rpg.extension("bestiary").defeated_count("slime"), 12, "two slimes in each of six battles")
