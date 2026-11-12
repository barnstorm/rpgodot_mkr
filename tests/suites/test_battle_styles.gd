extends "res://tests/rpg_test_case.gd"
## Battle view (front / side) and battle system (turn / ATB / CTB): data defaults, side-view
## placement, the side-view battler graphic chain and motions, ATB fill order, wait versus active
## time, the turn counter for troop pages, escape, and auto battles in every combination.

const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")
const Env := preload("res://tests/rpg_test_env.gd")
const ActorSprite := preload("res://addons/rpg/runtime/ui/battle/rpg_battle_actor_sprite.gd")
const Scene := preload("res://addons/rpg/runtime/ui/battle/battle_scene.gd")
const ASSET_ROOT := "user://test_battle_styles_assets"

var db
var rules: RPGRuleSystem
var env


func before_each() -> void:
	db = FakeDB.from_folder("res://rpg/database")
	rules = RPGRuleSystem.load_rules("classic", db)


func after_each() -> void:
	Engine.time_scale = 1.0
	if RPGAssets.root != RPGAssets.ASSETS_ROOT:
		RPGAssets.root = RPGAssets.ASSETS_ROOT
		RPGAssets.clear_cache()
	if env != null:
		await env.destroy()
		env = null


func _core(party_ids: Array, troop: Variant, system: String, rng_seed: int, advantage := "normal") -> RPGBattleCore:
	var party := []
	for id in party_ids:
		party.append(rules.new_actor_battler(id, 1))
	var t: Dictionary = troop if troop is Dictionary else db.record("troops", str(troop))
	var core := RPGBattleCore.new(party, t, rules, RPGRandom.new(rng_seed))
	core.battle_system = system
	core.advantage = advantage
	core.start()
	return core


## Plays a timed battle with the core alone: actors use `actor_action` (or attack). Returns the
## battlers in the order they took their turns.
func _timed_battle(core: RPGBattleCore, max_turns := 40, actor_action := {}) -> Array:
	var order := []
	core.begin_turn()
	var guard := 0
	while core.battle_over() == "" and core.turn <= max_turns and guard < 5000:
		guard += 1
		var b := core.next_auto_ready()
		if b == null:
			var a := core.next_input_actor()
			if a != null:
				var act: Dictionary = actor_action if not actor_action.is_empty() else {"kind": "attack", "target": -1}
				assert_true(core.set_action(core.party.find(a), act), "the full actor takes a command")
				continue
			core.atb_advance_to_next()
			continue
		order.append(b)
		var r := core.act(b)
		if r.get("turn_end", false):
			core.begin_turn()
	return order


func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")


func _run_battle(battle_args: Dictionary) -> Dictionary:
	var rpg: Node = env.rpg
	return await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), battle_args, {"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)


## Starts a battle without waiting for it; returns the scene.
func _start_battle(battle_args: Dictionary, out: Dictionary) -> Node:
	var run := func():
		out.r = await _run_battle(battle_args)
	run.call()
	return env.rpg.ui.scene_stack[-1]


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


## Lets the battle play itself out (in the turn system the open command is confirmed first).
func _finish(scene: Node, out: Dictionary) -> void:
	scene.auto = true
	var end := Time.get_ticks_msec() + 20000
	while not out.has("r") and Time.get_ticks_msec() < end:
		if is_instance_valid(scene) and scene.core != null and not scene.core.is_timed() and scene.phase != "":
			if scene.phase == "party":
				scene.cmd_list.select(0)
			scene.handle_action("ok")
		await tree.process_frame
	assert_eq(out.get("r", {}).get("status", ""), "finished", "the battle ends")


# --- data defaults ---------------------------------------------------------------------------------

func test_defaults_keep_the_classic_battle() -> void:
	var sys := RPGRecordSchemas.fields_for("system")
	var defaults := {}
	for f in sys:
		defaults[f.key] = f.get("default")
	assert_eq(defaults.get("battle_view"), "front", "System: front view by default")
	assert_eq(defaults.get("battle_system"), "turn", "System: turn based by default")
	assert_eq(defaults.get("atb_mode"), "wait")
	var troop_defaults := {}
	for f in RPGRecordSchemas.fields_for("troops"):
		troop_defaults[f.key] = f.get("default")
	assert_eq(troop_defaults.get("battle_view"), "", "an enemy group follows the System setting")
	assert_eq(troop_defaults.get("battle_system"), "")
	var actor_fields := {}
	for f in RPGRecordSchemas.fields_for("actors"):
		actor_fields[f.key] = f
	assert_true(actor_fields.has("sv_battler"), "actors have a side-view battler field")
	assert_eq(actor_fields.sv_battler.get("res"), "sv_battler")
	assert_eq(RPGAssets.folder_for("sv_battler"), "BattleCharSet")
	# A new core is the turn system, and nothing timed happens in it.
	var core := _core(["hero"], "slimes", "turn", 1)
	assert_eq(core.battle_system, "turn")
	assert_false(core.is_timed())
	assert_true(core.gauges.is_empty(), "no gauges in the turn system")
	# Unknown values fall back to the turn system.
	var odd := _core(["hero"], "slimes", "chess", 1)
	assert_eq(odd.battle_system, "turn")


func test_style_comes_from_args_troop_map_then_system() -> void:
	var allowed := ["front", "side"]
	assert_eq(Scene._first_valid("battle_view", [{}, {}, {}, {}], allowed, "front"), "front", "nothing set: front")
	assert_eq(Scene._first_valid("battle_view", [{}, {}, {}, {"battle_view": "side"}], allowed, "front"), "side", "System")
	assert_eq(Scene._first_valid("battle_view", [{}, {}, {"battle_view": "front"}, {"battle_view": "side"}], allowed, "front"), "front", "the map wins over System")
	assert_eq(Scene._first_valid("battle_view", [{}, {"battle_view": "side"}, {"battle_view": "front"}, {}], allowed, "front"), "side", "the troop wins over the map")
	assert_eq(Scene._first_valid("battle_view", [{"battle_view": "front"}, {"battle_view": "side"}, {}, {}], allowed, "front"), "front", "battle args win")
	assert_eq(Scene._first_valid("battle_view", [{}, {"battle_view": ""}, {}, {"battle_view": "side"}], allowed, "front"), "side", "a blank troop value passes it on")
	# Through a real battle: the System record decides when nothing else does.
	_sample_env()
	env.rpg.data.system["battle_view"] = "side"
	env.rpg.data.system["battle_system"] = "ctb"
	var out := {}
	var scene := _start_battle({"troop": "slimes", "auto": true}, out)
	assert_eq(scene.battle_view, "side")
	assert_eq(scene.battle_system, "ctb")
	assert_eq(scene.core.battle_system, "ctb")
	await _wait_until(func(): return out.has("r"))
	env.rpg.data.system.erase("battle_view")
	env.rpg.data.system.erase("battle_system")


# --- side view ---------------------------------------------------------------------------------------

func test_side_positions_and_mirroring() -> void:
	# Enemies move into the left part of the stage, keeping their order and height.
	var xs := []
	for x in [40, 90, 160, 230, 280]:
		var p: Vector2 = Scene.side_enemy_position(Vector2(x, 120))
		xs.append(p.x)
		assert_eq(p.y, 120.0, "height kept")
	for i in range(1, xs.size()):
		assert_true(xs[i] > xs[i - 1], "left-to-right order kept: %s" % str(xs))
	# The party stands on the right, in a diagonal: each actor further right and lower.
	var homes: Array = Scene.side_layout([44.0, 44.0, 44.0, 44.0], [30.0, 30.0, 30.0, 30.0]).homes
	assert_true(xs[-1] < homes[0].x - 30, "even the rightmost enemy stays clear of the party (%s vs %s)" % [xs[-1], homes[0].x])
	for i in range(1, 4):
		assert_true(homes[i].x > homes[i - 1].x and homes[i].y > homes[i - 1].y, "diagonal row: %s" % str(homes))
	for h in homes:
		assert_true(h.x > Scene.W * 0.6 and h.y <= Scene.FIELD_H, "inside the stage, on the right: %s" % h)
	# In a real side-view battle the sprites are placed there and enemies are on the left.
	_sample_env()
	env.rpg.state.add_actor("mira")
	env.rpg.ui.auto_advance = false
	var out := {}
	var scene := _start_battle({"troop": "slimes", "battle_view": "side", "can_escape": true, "can_lose": true}, out)
	assert_eq(scene.actor_nodes.size(), 2, "one sprite per actor")
	for b in scene.core.party:
		var spr: Control = scene.actor_nodes[b]
		assert_true(spr.home.x > Scene.W * 0.6, "the party stands on the right")
		assert_eq(scene.battler_point(b), spr.point(), "popups and animations go to the figure")
	for e in scene.core.enemies:
		var s: TextureRect = scene.enemy_nodes[e]
		assert_true(s.position.x + s.size.x / 2.0 < Scene.W / 2.0, "enemies on the left half")
		assert_false(s.flip_h, "enemy images are not flipped")
	await _finish(scene, out)
	# The front view draws no actors.
	var out2 := {}
	var front := _start_battle({"troop": "slimes", "auto": true}, out2)
	assert_eq(front.battle_view, "front")
	assert_true(front.actor_nodes.is_empty(), "front view: no actor sprites")
	await _wait_until(func(): return out2.has("r"))


## Synthetic sheets: an MV-shaped sv_actors sheet, a 2003 A/B BattleCharSet pair and a CharSet,
## each cell a different colour so the source rectangles can be checked.
func _make_assets() -> void:
	var base := ASSET_ROOT.path_join("qa")
	DirAccess.make_dir_recursive_absolute(base.path_join("BattleCharSet"))
	DirAccess.make_dir_recursive_absolute(base.path_join("CharSet"))
	var mv := Image.create(576, 384, false, Image.FORMAT_RGBA8)
	mv.fill(Color(1, 0, 0))
	mv.save_png(base.path_join("BattleCharSet/mv_hero.png"))
	var a := Image.create(144, 384, false, Image.FORMAT_RGBA8)
	a.fill(Color(0, 1, 0))
	a.save_png(base.path_join("BattleCharSet/Fighter A.png"))
	a.save_png(base.path_join("BattleCharSet/Fighter B.png"))
	a.save_png(base.path_join("BattleCharSet/Lone A.png"))
	var odd := Image.create(100, 50, false, Image.FORMAT_RGBA8)
	odd.save_png(base.path_join("BattleCharSet/odd.png"))
	var cs := Image.create(288, 256, false, Image.FORMAT_RGBA8)
	cs.fill(Color(0, 0, 1))
	cs.save_png(base.path_join("CharSet/walker.png"))
	RPGAssets.root = ASSET_ROOT
	RPGAssets.clear_cache()


func test_battler_graphic_fallback_chain() -> void:
	_make_assets()
	var mv := ActorSprite.resolve({"sv_battler": "mv_hero", "charset": "walker"})
	assert_eq(mv.kind, "mv", "an MV sv_actors sheet comes first")
	assert_eq(mv.cell, Vector2i(64, 64))
	var k3 := ActorSprite.resolve({"sv_battler": "Fighter A", "charset": "walker"})
	assert_eq(k3.kind, "2k3", "a 2003 BattleCharSet")
	assert_eq(k3.cell, Vector2i(48, 48))
	assert_true(k3.texture_b is Texture2D, "its B file (attacks, item) is found by name")
	assert_eq(ActorSprite.companion_b("Lone A"), "", "no B file: none")
	var lone := ActorSprite.resolve({"sv_battler": "Lone A"})
	assert_eq(lone.kind, "2k3")
	assert_eq(lone.texture_b, null)
	var from_look := ActorSprite.resolve({"sv_battler": "", "battler": "mv_hero", "charset": "walker"})
	assert_eq(from_look.kind, "mv", "Change Actor Graphic's battler image counts when it is a side-view sheet")
	var cs := ActorSprite.resolve({"sv_battler": "missing", "charset": "walker", "charset_index": 2})
	assert_eq(cs.kind, "charset", "a missing sheet falls back to the walk sprite")
	assert_eq(cs.index, 2)
	assert_eq(cs.cell, Vector2i(24, 32))
	var bad := ActorSprite.resolve({"sv_battler": "odd", "charset": "walker"})
	assert_eq(bad.kind, "charset", "a sheet of another shape is not used")
	var none := ActorSprite.resolve({"sv_battler": "", "charset": ""})
	assert_eq(none.kind, "none", "nothing at all: a placeholder figure")
	assert_true(none.texture is Texture2D)
	# Source rectangles.
	var spr: Control = ActorSprite.new()
	spr.setup(mv, 320.0)
	assert_eq(spr.frame_source("wait", 0)[1], Rect2(0, 64, 64, 64), "MV wait: block 0, row 1")
	assert_eq(spr.frame_source("swing", 2)[1], Rect2(5 * 64, 64, 64, 64), "MV swing: block 1, row 1, frame 2")
	assert_eq(spr.frame_source("dead", 1)[1], Rect2(7 * 64, 5 * 64, 64, 64), "MV dead: block 2, row 5")
	assert_eq(spr.frame_source("victory", 0)[1], Rect2(6 * 64, 64, 64, 64), "MV victory: block 2, row 1")
	assert_true(spr.size.x < 64, "MV battlers shrink on the 320 px stage (%s)" % spr.size)
	spr.free()
	var spr2: Control = ActorSprite.new()
	spr2.setup(k3, 320.0)
	assert_eq(spr2.size, Vector2(48, 48), "2003 battlers keep their size")
	assert_eq(spr2.frame_source("wait", 1)[1], Rect2(48, 6 * 48, 48, 48), "2003 idle: A row 6")
	assert_eq(spr2.frame_source("dead", 0)[1], Rect2(0, 3 * 48, 48, 48), "2003 dead: A row 3")
	assert_eq(spr2.frame_source("item", 0)[0], k3.texture_b, "2003 item use: the B file")
	assert_eq(spr2.frame_source("item", 0)[1], Rect2(0, 2 * 48, 48, 48), "B row 2")
	spr2.free()
	var spr3: Control = ActorSprite.new()
	spr3.setup(lone, 320.0)
	assert_eq(spr3.frame_source("swing", 0)[0], lone.texture, "no B file: the A file is used")
	spr3.free()
	var spr4: Control = ActorSprite.new()
	spr4.setup(cs, 320.0)
	var expect := Rect2(RPGCharset.frame_rect("rm2k", Vector2i(288, 256), 2, "left", 1))
	assert_eq(spr4.frame_source("wait", 0)[1], expect, "walk sprite: facing left, standing frame")
	spr4.free()


func test_motion_state_changes() -> void:
	var spr: Control = ActorSprite.new()
	spr.setup(ActorSprite.resolve({"sv_battler": "", "charset": ""}), 320.0)
	assert_eq(spr.motion, "wait")
	spr.play_motion("swing")
	assert_eq(spr.motion, "swing", "an attack motion plays")
	for i in 5:
		spr._process(ActorSprite.ONE_SHOT_FRAME_SECONDS)
	assert_eq(spr.motion, "wait", "a one-shot motion returns to the resting motion")
	spr.play_motion("walk")
	spr.set_base("dead")
	assert_eq(spr.motion, "walk", "a motion played on purpose is not cut off by a new resting motion")
	spr.clear_motion()
	assert_eq(spr.motion, "dead")
	spr.set_base("guard")
	assert_eq(spr.motion, "guard", "resting motions change at once")
	assert_eq(ActorSprite.frame_at("wait", 3), 1, "loops go 0,1,2,1")
	assert_eq(ActorSprite.frame_at("swing", 5), 2, "one-shots stop on the last frame")
	spr.free()
	# In a battle: the actor choosing steps forward, steps back on cancel, and cheers on a win.
	_sample_env()
	env.rpg.ui.auto_advance = false
	env.rpg.rng.seed = 5
	var out := {}
	var scene := _start_battle({"troop": "slimes", "battle_view": "side", "can_escape": true, "can_lose": true}, out)
	assert_true(await _wait_until(func(): return scene.phase == "party"), "party command")
	var hero: RPGBattler = scene.core.party[0]
	var hs: Control = scene.actor_nodes[hero]
	assert_eq(scene.resting_motion(hero), "wait")
	scene.handle_action("ok")                  # Fight
	await _wait_until(func(): return hs.offset.x <= -Scene.STEP_X + 0.01, 2.0)
	assert_eq(hs.offset, Vector2(-Scene.STEP_X, 0), "the choosing actor stands one step forward")
	assert_eq(hs.motion, "walk")
	scene.handle_action("cancel")              # back to the party command
	await _wait_until(func(): return hs.offset == Vector2.ZERO, 2.0)
	assert_eq(hs.offset, Vector2.ZERO, "and steps back")
	await _wait_until(func(): return hs.motion == "wait", 1.0)
	assert_eq(hs.motion, "wait")
	hero.guarding = true
	assert_eq(scene.resting_motion(hero), "guard")
	hero.guarding = false
	var hp := hero.get_resource("hp")
	hero.set_resource("hp", 1)
	assert_eq(scene.resting_motion(hero), "dying", "low HP")
	hero.set_resource("hp", hp)
	var at_end := {}
	scene.finished.connect(func(_r): at_end.motion = hs.motion)
	await _finish(scene, out)
	assert_eq(out.r.value.outcome, "win")
	assert_eq(at_end.get("motion", ""), "victory", "the winners cheer")


# --- ATB / CTB core ---------------------------------------------------------------------------------

func test_atb_fill_order_follows_agility() -> void:
	var core := _core(["hero", "mira"], "bats", "atb", 11)
	for b in core.all_battlers():
		var g := core.gauge(b)
		assert_true(g >= RPGBattleCore.ATB_START and g <= RPGBattleCore.ATB_START + RPGBattleCore.ATB_START_SPREAD, "a fixed start with a small random offset (%s)" % g)
	var hero: RPGBattler = core.party[0]
	var mira: RPGBattler = core.party[1]
	hero.base["agi"] = 200
	mira.base["agi"] = 1
	core.start()
	assert_true(rules.atb_speed(hero) > rules.atb_speed(mira), "speed from agility")
	assert_true(core.atb_rate(hero) > core.atb_rate(mira) * 5.0, "the fast actor fills much sooner")
	core.begin_turn()
	core.atb_advance_to_next()
	assert_eq(core.ready_queue, [hero], "the fastest fills first")
	assert_eq(core.next_input_actor(), hero)
	assert_eq(core.next_auto_ready(), null, "a full actor waits for its command")
	# Over a long fight the fast actor takes far more turns.
	var order := _timed_battle(core, 6, {"kind": "guard"})
	var hero_turns := order.count(hero)
	var mira_turns := order.count(mira)
	assert_true(hero_turns > mira_turns, "hero %d turns, Mira %d" % [hero_turns, mira_turns])
	# Equal speeds: the gauges fill in step, earlier fill first.
	var c2 := _core(["hero"], "slimes", "atb", 3)
	var s0: RPGBattler = c2.enemies[0]
	var s1: RPGBattler = c2.enemies[1]
	c2.gauges[s0] = 0.5
	c2.gauges[s1] = 0.6
	c2.gauges[c2.party[0]] = 0.0
	c2.atb_advance(10.0)
	assert_eq(c2.ready_queue.slice(0, 2), [s1, s0], "the one that would have filled first goes first")


func test_preemptive_and_surprise() -> void:
	var pre := _core(["hero", "mira"], "slimes", "atb", 2, "preemptive")
	for a in pre.party:
		assert_eq(pre.gauge(a), 1.0, "preemptive: the party starts full")
	for e in pre.enemies:
		assert_eq(pre.gauge(e), 0.0, "and the enemies empty")
	assert_true(pre.next_input_actor() != null)
	var sur := _core(["hero"], "slimes", "atb", 2, "surprise")
	assert_eq(sur.gauge(sur.party[0]), 0.0)
	assert_true(sur.next_auto_ready() != null and sur.next_auto_ready().is_enemy(), "surprise: an enemy is ready at once")
	# The turn system: the other side sits out turn 1.
	var t := _core(["hero"], "slimes", "turn", 2, "surprise")
	t.begin_turn()
	assert_eq(t.inputs_needed(), [], "surprised: no commands on turn 1")
	var users := []
	var r := t.next_action()
	while not r.is_empty():
		users.append(r.user)
		r = t.next_action()
	assert_true(users.all(func(u): return u.is_enemy()) and not users.is_empty(), "only the enemies act")
	t.end_turn()
	t.begin_turn()
	assert_eq(t.inputs_needed(), [0], "turn 2 is normal")
	var p := _core(["hero"], "slimes", "turn", 2, "preemptive")
	p.begin_turn()
	p.set_action(0, {"kind": "guard"})
	var users2 := []
	var r2 := p.next_action()
	while not r2.is_empty():
		users2.append(r2.user)
		r2 = p.next_action()
	assert_eq(users2, [p.party[0]], "preemptive: only the party acts on turn 1")


func test_states_that_skip_turns_still_work() -> void:
	var core := _core(["hero"], "slimes", "atb", 4)
	var hero: RPGBattler = core.party[0]
	hero.add_state("sleep", 1)
	core.gauges[hero] = 0.99
	for e in core.enemies:
		core.gauges[e] = 0.0
	core.begin_turn()
	core.atb_advance_to_next()
	assert_eq(core.ready_queue, [hero])
	assert_eq(core.next_input_actor(), null, "an actor that cannot act gets no command")
	assert_eq(core.next_auto_ready(), hero, "it still takes (loses) its turn")
	var r := core.act(hero)
	assert_true(r.skipped, "the turn is skipped")
	assert_false(hero.has_state("sleep"), "and the state wears off at the end of it")
	assert_eq(core.gauge(hero), 0.0, "the gauge starts again")
	assert_false(r.ticks.is_empty(), "the state's end is reported with the turn")


func test_atb_turn_counter_for_troop_pages() -> void:
	var troop := {"id": "t", "can_escape": true, "members": [
		{"enemy": "slime", "position": [100, 120]}, {"enemy": "bat", "position": [200, 120]}],
		"pages": [{"id": "turn2", "conditions": [{"kind": "turn", "n": 2}], "span": "once_per_battle", "commands": []},
			{"id": "every", "conditions": [{"kind": "turn", "n": 1, "every": 1}], "span": "once_per_turn", "commands": []}]}
	var core := _core(["hero", "mira"], troop, "atb", 8)
	var page_turns := []
	var every_turns := []
	var acted := {}
	core.checkpoint.connect(func(kind: String):
		for p in core.eligible_battle_pages(kind):
			if p.id == "turn2":
				page_turns.append(core.turn)
			else:
				every_turns.append(core.turn))
	core.begin_turn()
	var guard := 0
	var turns_seen := 0
	while core.battle_over() == "" and core.turn <= 4 and guard < 2000:
		guard += 1
		var b := core.next_auto_ready()
		if b == null:
			var a := core.next_input_actor()
			if a != null:
				core.set_action(core.party.find(a), {"kind": "guard"})
				continue
			core.atb_advance_to_next()
			continue
		acted[b] = true
		var r := core.act(b)
		if r.turn_end:
			for x in core.all_battlers():
				if x.is_active():
					assert_true(acted.has(x), "turn %d ends only after %s has had a turn" % [core.turn, x.name])
			acted.clear()
			turns_seen += 1
			core.begin_turn()
	assert_true(turns_seen >= 3, "several turns pass (%d)" % turns_seen)
	assert_eq(page_turns, [2], "a 'turn 2' page runs once, in turn 2")
	assert_eq(every_turns.slice(0, 3), [1, 2, 3], "an 'every turn' page runs once per turn")


func test_ctb_turn_order_is_shown_and_kept() -> void:
	var core := _core(["hero", "mira"], "bats", "ctb", 21)
	core.begin_turn()
	var predicted := core.turn_order(6)
	assert_eq(predicted.size(), 6)
	var actual := []
	var guard := 0
	while actual.size() < 6 and guard < 500:
		guard += 1
		core.atb_advance_to_next()
		var b := core.next_auto_ready()
		if b == null:
			var a := core.next_input_actor()
			core.set_action(core.party.find(a), {"kind": "guard"})
			b = a
		actual.append(b)
		var r := core.act(b)
		if r.turn_end:
			core.begin_turn()
	assert_eq(actual, predicted, "battlers act in the order shown")
	# The scene draws the order strip.
	_sample_env()
	var out := {}
	env.rpg.ui.auto_advance = false
	var scene := _start_battle({"troop": "slimes", "battle_system": "ctb", "can_escape": true, "can_lose": true}, out)
	assert_true(scene._order_strip != null, "CTB shows the turn order")
	assert_eq(scene.shown_order().size(), Scene.ORDER_COUNT)
	assert_true(await _wait_until(func(): return scene.input_actor != null), "a command window opens")
	var g0 := []
	for e in scene.core.enemies:
		g0.append(scene.core.gauge(e))
	await _wait_until(func(): return false, 0.3)
	var g1 := []
	for e in scene.core.enemies:
		g1.append(scene.core.gauge(e))
	assert_eq(g1, g0, "CTB: time never runs while a command is chosen")
	await _finish(scene, out)


func test_atb_escape_works_as_in_the_turn_system() -> void:
	rules.definition["escape"] = {"chance": 0}
	var core := _core(["hero", "mira"], "slimes", "atb", 9, "preemptive")
	core.begin_turn()
	var e := core.attempt_escape()
	assert_false(e.success)
	core.lose_party_turns()
	for a in core.party:
		assert_eq(core.gauge(a), 0.0, "a failed escape costs the party its turns")
		assert_false(core.ready_queue.has(a))
	assert_eq(core.battle_over(), "")
	rules.definition["escape"] = {"chance": 100}
	assert_true(core.attempt_escape().success)
	assert_eq(core.battle_over(), "escape")
	var boss := _core(["hero"], "goblin_boss", "atb", 9)
	assert_false(boss.attempt_escape().success, "no escape from the boss, as before")
	# Through the scene: Cancel on the first command opens Fight / Escape; Escape gets away.
	_sample_env()
	env.rpg.ui.auto_advance = false
	env.rpg.rules.definition["escape"] = {"chance": 100}
	var out := {}
	var scene := _start_battle({"troop": "slimes", "battle_system": "atb", "battle_view": "side", "can_escape": true, "can_lose": true}, out)
	Engine.time_scale = 4.0
	assert_true(await _wait_until(func(): return scene.phase == "actor"), "the first full actor gets its command")
	scene.handle_action("cancel")
	assert_eq(scene.phase, "party", "Cancel: the party command")
	scene.handle_action("down")
	scene.handle_action("ok")
	await _wait_until(func(): return out.has("r"), 10.0)
	assert_eq(out.get("r", {}).get("value", {}).get("outcome", ""), "escape", "the party escaped")
	env.rpg.rules.definition.erase("escape")


func test_atb_wait_and_active_modes() -> void:
	for mode in ["wait", "active"]:
		_sample_env()
		env.rpg.ui.auto_advance = false
		env.rpg.rng.seed = 13
		var out := {}
		var scene := _start_battle({"troop": "slimes", "battle_system": "atb", "atb_mode": mode, "can_escape": true, "can_lose": true}, out)
		Engine.time_scale = 4.0
		assert_eq(scene.atb_mode, mode)
		assert_true(await _wait_until(func(): return scene.input_actor != null and scene.phase == "actor"), "%s: a command window opens" % mode)
		var before := 0.0
		for e in scene.core.enemies:
			before += scene.core.gauge(e)
		var lines_before: int = scene.log_lines.size()
		await _wait_until(func(): return false, 0.5)
		var after := 0.0
		for e in scene.core.enemies:
			after += scene.core.gauge(e)
		if mode == "wait":
			assert_true(scene.time_stopped, "wait: time is stopped")
			assert_eq(after, before, "wait: the enemy gauges do not move while choosing")
			assert_eq(scene.log_lines.size(), lines_before, "wait: nobody acts")
		else:
			assert_false(scene.time_stopped, "active: time runs")
			assert_true(after != before or scene.log_lines.size() > lines_before, "active: the enemies keep filling (%s -> %s)" % [before, after])
		assert_true(scene._atb_fills.size() == scene.core.party.size(), "ATB gauges in the status window")
		Engine.time_scale = 1.0
		await _finish(scene, out)
		await env.destroy()
		env = null


# --- every combination ------------------------------------------------------------------------------

func test_auto_battle_in_each_system_and_view() -> void:
	for view in ["front", "side"]:
		for system in ["turn", "atb", "ctb"]:
			_sample_env()
			env.rpg.rng.seed = 12345
			env.rpg.state.add_actor("mira")
			var r := await _run_battle({"troop": "slimes", "can_escape": true, "can_lose": true, "background": "", "auto": true, "battle_view": view, "battle_system": system})
			assert_eq(r.status, "finished", "%s/%s: %s" % [view, system, str(r)])
			assert_eq(r.get("value", {}).get("outcome", ""), "win", "%s/%s: the party wins" % [view, system])
			assert_eq(r.get("value", {}).get("rewards", {}).get("exp", 0), 12, "%s/%s: rewards" % [view, system])
			assert_eq(env.rpg.state.actor("hero").exp, 12, "%s/%s: experience reaches the real party" % [view, system])
			await env.destroy()
			env = null
	# The core alone: timed auto battles are deterministic for a seed.
	var a := _timed_battle(_core(["hero"], "slimes", "atb", 77))
	var b := _timed_battle(_core(["hero"], "slimes", "atb", 77))
	assert_eq(a.size(), b.size(), "same seed, same timed battle")
	var c := _core(["hero"], "slimes", "ctb", 77)
	_timed_battle(c)
	assert_eq(c.battle_over(), "win", "CTB auto battle won")


# --- follow-ups: spacing, mixed sources, advantage, passing the turn -----------------------------

## Share of `back`'s visible figure hidden by `front` (drawn over it).
func _covered(back: Rect2, front: Rect2) -> float:
	var i := back.intersection(front)
	return (i.size.x * i.size.y) / maxf(1.0, back.size.x * back.size.y)


func test_side_spacing_keeps_every_actor_visible() -> void:
	for heights in [[44.0, 44.0, 44.0, 44.0], [24.0, 45.0, 45.0, 29.0], [62.0, 62.0, 62.0, 62.0], [30.0], [45.0, 20.0]]:
		var widths := []
		for h in heights:
			widths.append(h * 0.7)
		var l: Dictionary = Scene.side_layout(heights, widths)
		var k: float = l.scale
		var rects := []
		for i in heights.size():
			var hm: Vector2 = l.homes[i]
			var w: float = widths[i] * k
			var h: float = heights[i] * k
			rects.append(Rect2(hm.x - w / 2.0, hm.y - h, w, h))
			assert_true(hm.y - h >= Scene.SIDE_TOP - 0.5 and hm.y <= Scene.SIDE_FLOOR + 0.5, "%s: inside the stage band (%s)" % [str(heights), rects[i]])
		for i in range(1, rects.size()):
			var cover := _covered(rects[i - 1], rects[i])
			assert_true(cover <= Scene.SIDE_COVER_TIGHT + 0.01, "%s: actor %d hidden %.2f by the next" % [str(heights), i - 1, cover])
			# Stepping forward (to the left) must not land on the actor before it either.
			var stepped: Rect2 = rects[i]
			stepped.position.x -= Scene.STEP_X
			assert_true(_covered(rects[i - 1], stepped) <= Scene.SIDE_COVER_TIGHT + 0.01, "%s: stepped actor %d covers its neighbour" % [str(heights), i])
	# With room to spare the limit is a third.
	var roomy: Dictionary = Scene.side_layout([30.0, 30.0, 30.0], [20.0, 20.0, 20.0])
	assert_eq(roomy.scale, 1.0)
	assert_true(roomy.homes[1].y - roomy.homes[0].y >= 30.0 * 2.0 / 3.0 - 0.5, "at most a third hidden: %s" % str(roomy.homes))


func test_mixed_sources_share_one_height() -> void:
	_make_assets()
	_sample_env()
	env.rpg.data.record("actors", "hero")["sv_battler"] = "mv_hero"
	env.rpg.data.record("actors", "mira")["sv_battler"] = "Fighter A"
	env.rpg.state.add_actor("mira")
	env.rpg.ui.auto_advance = false
	var out := {}
	var scene := _start_battle({"troop": "slimes", "battle_view": "side", "can_escape": true, "can_lose": true}, out)
	var hero: Control = scene.actor_nodes[scene.core.party[0]]
	var mira: Control = scene.actor_nodes[scene.core.party[1]]
	assert_eq(hero.kind, "mv")
	assert_eq(mira.kind, "2k3")
	assert_true(absf(hero.figure_height() - mira.figure_height()) <= 1.0, "an MV sheet and a 2003 sheet are drawn the same height (%s, %s)" % [hero.figure_height(), mira.figure_height()])
	assert_true(_covered(hero.figure_rect(), mira.figure_rect()) <= Scene.SIDE_COVER + 0.02, "the actor behind stays visible")
	await _finish(scene, out)
	env.rpg.data.record("actors", "hero")["sv_battler"] = ""
	env.rpg.data.record("actors", "mira")["sv_battler"] = ""


func test_encounter_advantage_rolls() -> void:
	var party := [rules.new_actor_battler("hero", 1)]
	var troop: Dictionary = db.record("troops", "slimes")
	var rates := RPGBattleCore.encounter_rates(rules, party, troop)
	assert_eq(RPGBattleCore.encounter_advantage(rules, party, troop, 0.0), "preemptive", "the lowest rolls: preemptive")
	assert_eq(RPGBattleCore.encounter_advantage(rules, party, troop, float(rates.preemptive) + 0.001), "surprise")
	assert_eq(RPGBattleCore.encounter_advantage(rules, party, troop, 0.5), "normal")
	party[0].base["agi"] = 999
	assert_eq(RPGBattleCore.encounter_rates(rules, party, troop), {"preemptive": 0.05, "surprise": 0.03}, "a quicker party: MV's 5% / 3%")
	party[0].base["agi"] = -999
	assert_eq(RPGBattleCore.encounter_rates(rules, party, troop), {"preemptive": 0.03, "surprise": 0.05}, "a slower party: 3% / 5%")
	# Battle Processing: the new field defaults to normal and is passed on otherwise.
	var desc: Dictionary = load("res://addons/rpg/runtime/commands/battle.gd").descriptor()
	var field := {}
	for f in desc.fields:
		if f.key == "advantage":
			field = f
	assert_eq(field.get("default"), "normal", "old Battle Processing data stays normal")
	_sample_env()
	var done := {}
	var run := func():
		done.r = await env.rpg.run_commands([{"type": "battle", "troop": "slimes", "can_escape": true, "can_lose": true, "advantage": "surprise"}], {"kind": "api", "id": "t"})
	run.call()
	assert_true(await _wait_until(func(): return not env.rpg.ui.scene_stack.is_empty()), "the battle opens")
	var scene: Node = env.rpg.ui.scene_stack[-1]
	assert_eq(scene.core.advantage, "surprise", "Battle Processing passes the advantage on")
	await _wait_until(func(): return done.has("r"), 20.0)
	assert_true(done.has("r"), "the battle ends")


func test_atb_pass_turn_to_the_next_actor() -> void:
	var core := _core(["hero", "mira"], "slimes", "atb", 6, "preemptive")
	var hero: RPGBattler = core.party[0]
	var mira: RPGBattler = core.party[1]
	assert_eq(core.input_actors().size(), 2, "both full")
	var first := core.next_input_actor()
	var other := mira if first == hero else hero
	assert_eq(core.pass_turn(first), other, "passing gives the other actor the command")
	assert_eq(core.next_input_actor(), other)
	assert_eq(core.pass_turn(other), first, "and back again")
	core.set_action(core.party.find(first), {"kind": "guard"})
	assert_eq(core.pass_turn(other), null, "nobody else waiting: no pass")
	# In the scene: Tab / Shift (pass_turn) and a click on the other actor's row.
	_sample_env()
	env.rpg.state.add_actor("mira")
	env.rpg.ui.auto_advance = false
	var out := {}
	var scene := _start_battle({"troop": "slimes", "battle_system": "atb", "advantage": "preemptive", "battle_view": "side", "can_escape": true, "can_lose": true}, out)
	assert_true(await _wait_until(func(): return scene.input_actor != null and scene.phase == "actor"), "a command window opens")
	var a0: RPGBattler = scene.input_actor
	assert_true(scene.pass_turn(), "pass")
	assert_ne(scene.input_actor, a0, "the other actor chooses now")
	assert_eq(scene.phase, "actor")
	assert_eq(scene.log_label.text, scene.input_actor.name)
	# Mouse: the passed actor's row is a click target that switches back.
	var back := {}
	for t in scene.pointer_targets():
		if t.has("ok"):
			back = t
			break
	assert_false(back.is_empty(), "the other full actor's row can be clicked")
	scene.pointer_event(_click(back.rect.get_center()))
	assert_eq(scene.input_actor, a0, "a click on its row gives it the command")
	await _finish(scene, out)


func _click(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


# --- Enemy Appear ---------------------------------------------------------------------------------

## Two slimes; the second is marked "Appears later" (hidden). `pages`: the troop's battle events.
func _later_troop(pages: Array = []) -> Dictionary:
	return {"id": "later", "name": "Later", "can_escape": true, "members": [
		{"enemy": "slime", "hidden": false, "position": [120, 150]},
		{"enemy": "slime", "hidden": true, "position": [200, 150]}], "pages": pages}


func _add_troop(t: Dictionary) -> void:
	var data: RPGProjectData = env.rpg.data
	data.db["troops"].by_id[t.id] = t
	data.db["troops"].records.append(t)


func test_core_appear_brings_hidden_members_in() -> void:
	var core := _core(["hero"], _later_troop(), "turn", 3)
	var later: RPGBattler = core.enemies[1]
	assert_true(later.hidden and not later.is_active(), "hidden at the start")
	assert_eq(core.active_enemies().size(), 1)
	assert_eq(core.resolve_targets(core.party[0], {"scope": "one_enemy"}, 1), [core.enemies[0]], "a hidden enemy cannot be targeted")
	assert_eq(core.appear(0), [], "a member already in the battle: nothing")
	assert_eq(core.appear(1), [later], "the hidden member appears")
	assert_false(later.hidden)
	assert_eq(core.active_enemies().size(), 2)
	assert_eq(core.resolve_targets(core.party[0], {"scope": "one_enemy"}, 1), [later], "and can be targeted")
	assert_eq(core.appear(1), [], "only once")
	# It takes its turns from the next turn on.
	core.begin_turn()
	var users := []
	var r := core.next_action()
	while not r.is_empty():
		users.append(r.user)
		r = core.next_action()
	assert_true(users.has(later), "the new enemy acts")
	# -1: every hidden member.
	var two := _later_troop()
	two.members.append({"enemy": "bat", "hidden": true, "position": [260, 120]})
	var c2 := _core(["hero"], two, "turn", 3)
	assert_eq(c2.appear(-1).size(), 2, "all hidden members")
	assert_eq(c2.active_enemies().size(), 3)


func test_core_appear_takes_back_a_win() -> void:
	var core := _core(["hero"], _later_troop(), "turn", 4)
	core.enemies[0].set_resource("hp", 0)
	assert_eq(core.battle_over(), "win", "every visible enemy has fallen")
	assert_eq(core.appear(1).size(), 1)
	assert_eq(core.battle_over(), "", "reinforcements: the battle goes on")
	core.enemies[1].set_resource("hp", 0)
	assert_eq(core.battle_over(), "win")
	assert_eq(int(core.rewards().exp), 12, "both slimes give their EXP")
	# A result set from outside (abort battle) stays.
	var c2 := _core(["hero"], _later_troop(), "turn", 4)
	c2.force_result("win")
	c2.appear(1)
	assert_eq(c2.battle_over(), "win", "a forced result is kept")
	# A hidden member that never appears gives nothing.
	var c3 := _core(["hero"], _later_troop(), "turn", 4)
	c3.enemies[0].set_resource("hp", 0)
	assert_eq(c3.battle_over(), "win")
	assert_eq(int(c3.rewards().exp), 6, "only the slime that fought")


func test_core_appear_in_timed_battles() -> void:
	for system in ["atb", "ctb"]:
		var core := _core(["hero"], _later_troop(), system, 5)
		var later: RPGBattler = core.enemies[1]
		core.begin_turn()
		var order := _timed_turns(core, 4)
		assert_false(order.has(later), "%s: no turn while hidden" % system)
		core.appear(1)
		assert_eq(core.gauge(later), RPGBattleCore.ATB_START, "%s: the gauge starts from ATB_START" % system)
		assert_true(core.turn_order(6).has(later), "%s: it is in the turn order" % system)
		order = _timed_turns(core, 8)
		assert_true(order.has(later), "%s: it takes turns once it has appeared" % system)


## Plays `n` timed turns (actors guard). Returns who acted.
func _timed_turns(core: RPGBattleCore, n: int) -> Array:
	var order := []
	var guard := 0
	while order.size() < n and core.battle_over() == "" and guard < 500:
		guard += 1
		var b := core.next_auto_ready()
		if b == null:
			var a := core.next_input_actor()
			if a != null:
				core.set_action(core.party.find(a), {"kind": "guard"})
				continue
			core.atb_advance_to_next()
			continue
		order.append(b)
		var r := core.act(b)
		if r.get("turn_end", false):
			core.begin_turn()
	return order


func test_enemy_appear_command_in_each_system_and_view() -> void:
	var appear_page := {"id": "appear", "conditions": [{"kind": "turn", "n": 1}], "span": "once_per_battle",
		"commands": [{"type": "enemy_appear", "which": "one", "enemy": 2}]}
	var reinforce_page := {"id": "reinforce", "conditions": [{"kind": "enemy_hp", "index": 0, "op": "<=", "percent": 0}], "span": "once_per_battle",
		"commands": [{"type": "enemy_appear", "which": "all"}]}
	for view in ["front", "side"]:
		for system in ["turn", "atb", "ctb"]:
			for page in [appear_page, reinforce_page]:
				var what := "%s/%s/%s" % [view, system, page.id]
				_sample_env()
				env.rpg.rng.seed = 2024
				_add_troop(_later_troop([page]))
				var out := {}
				var scene := _start_battle({"troop": "later", "can_escape": false, "can_lose": true, "auto": true, "battle_view": view, "battle_system": system}, out)
				var core: RPGBattleCore = scene.core
				var lines: Array = scene.log_lines
				assert_true(await _wait_until(func(): return out.has("r"), 20.0), "%s: the battle ends" % what)
				assert_eq(out.r.get("value", {}).get("outcome", ""), "win", "%s: %s" % [what, str(out.r)])
				assert_false(core.enemies[1].hidden, "%s: the second slime appeared" % what)
				assert_true(core.enemies[1].is_dead(), "%s: and was defeated" % what)
				assert_eq(lines.count("Slime A appears!"), 1, "%s: %s" % [what, str(lines)])
				assert_eq(lines.count("Slime B appears!"), 1, "%s: announced once, when it appears" % what)
				assert_true(lines.find("Slime B appears!") > lines.find("Slime A appears!"), what)
				assert_eq(int(out.r.value.rewards.exp), 12, "%s: both give EXP" % what)
				await env.destroy()
				env = null


func test_enemy_appear_shows_the_enemy_and_its_target() -> void:
	for view in ["front", "side"]:
		_sample_env()
		_add_troop(_later_troop())
		env.rpg.ui.auto_advance = false
		var out := {}
		var scene := _start_battle({"troop": "later", "can_escape": true, "can_lose": true, "battle_view": view}, out)
		assert_true(await _wait_until(func(): return scene.phase == "party"), "%s: the party command opens" % view)
		var later: RPGBattler = scene.core.enemies[1]
		var spr: TextureRect = scene.enemy_nodes[later]
		var node: Node2D = scene.battler_node(later)
		assert_false(spr.visible, "%s: not on screen yet" % view)
		assert_false(node.visible, "%s: its battler node is hidden too" % view)
		var shown: Array = await scene.enemy_appear(1)
		assert_eq(shown, [later])
		assert_true(spr.visible, "%s: on screen" % view)
		await _wait_until(func(): return spr.modulate.a >= 1.0, 2.0)
		assert_eq(spr.modulate.a, 1.0, "%s: faded in" % view)
		await frames(1)
		assert_true(node.visible, "%s: the battler node follows" % view)
		assert_eq(scene.log_lines[-1], "Slime B appears!")
		scene.handle_action("ok")          # Fight
		scene.handle_action("ok")          # Attack -> target
		assert_eq(scene.phase, "target_enemy")
		scene.handle_action("right")
		assert_eq(scene.target_index, 1, "%s: the arrow reaches the new enemy" % view)
		var rects: Array = scene.pointer_targets().filter(func(x): return x.has("select"))
		assert_eq(rects.size(), 2, "%s: both enemies can be pointed at" % view)
		await _finish(scene, out)
		await env.destroy()
		env = null


func test_enemy_appear_outside_a_battle_fails() -> void:
	_sample_env()
	env.rpg.state.new_game()
	var r: RPGResult = await env.rpg.run_commands([{"type": "enemy_appear", "which": "one", "enemy": 1}], {"kind": "api", "id": "t"})
	assert_true(r.is_error(), "no battle: an error")
	assert_true(str(r).contains("only works in a battle"), str(r))
	var cmd: RPGCommand = env.rpg.registry.get_command("enemy_appear")
	assert_eq(cmd.summary({"which": "one", "enemy": 2}), "Enemy Appear: enemy #2")
	assert_eq(cmd.summary({"which": "all"}), "Enemy Appear: every hidden enemy")


func test_validator_checks_enemy_appear() -> void:
	_sample_env()
	var reg: RPGCommandRegistry = env.rpg.registry
	var cmd_ok := {"type": "enemy_appear", "which": "one", "enemy": 2}
	var t := _later_troop([{"id": "p", "conditions": [{"kind": "turn", "n": 1}], "commands": [cmd_ok, {"type": "enemy_appear", "which": "all"}]}])
	var probs := RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json")
	assert_eq(probs, [], "a hidden member in a battle event: no problem")
	t.pages[0].commands = [{"type": "enemy_appear", "which": "one", "enemy": 1}, {"type": "enemy_appear", "which": "one", "enemy": 5}]
	probs = RPGValidator.structure("database:troops", {"schema_version": 1, "records": [t]}, reg, "troops.json")
	var msgs := probs.map(func(p): return "%s %s" % [p.severity, p.message])
	assert_true(msgs.any(func(m): return m.begins_with("warning") and m.contains("#1 is not marked")), str(msgs))
	assert_true(msgs.any(func(m): return m.begins_with("error") and m.contains("no enemy #5")), str(msgs))
	# On a map it can never work: flagged, also inside a branch.
	var ev := {"id": "e", "position": [1, 1], "pages": [{"commands": [
		{"type": "if", "condition": {"kind": "switch", "id": "s"}, "then": [cmd_ok], "else": []}]}]}
	var p2 := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, reg, "events.json")
	var w := p2.filter(func(p): return str(p.message).contains("only works in a battle event"))
	assert_eq(w.size(), 1, str(p2))
	assert_eq(w[0].severity, "warning")
	assert_eq(w[0].path, "events/0/pages/0/commands/0/then/0")
