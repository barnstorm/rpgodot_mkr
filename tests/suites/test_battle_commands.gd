extends "res://tests/rpg_test_case.gd"
## Battle commands per class (issue #17): the battle menu an actor's or class's battle_commands
## list builds, the VX Ace default of one command per skill type, Skill type commands filtering
## the skill list, the Row command with the row damage rates, and Event commands firing troop
## pages through command_used.

const Env := preload("res://tests/rpg_test_env.gd")
const FakeDB := preload("res://tests/fixtures/rpg_fake_db.gd")

var env
var db
var rules: RPGRuleSystem


func after_each() -> void:
	Engine.time_scale = 1.0
	if env != null:
		await env.destroy()
		env = null


# --- rules: resolving the command list ----------------------------------------------------------------


func _rules_env() -> void:
	db = FakeDB.new()
	db.add("types", {"id": "skill_types", "entries": [
		{"id": "magic", "name": "Magic"}, {"id": "special", "name": "Special"}]})
	db.add("classes", {"id": "soldier", "name": "Soldier",
		"growth": {"mhp": 450, "mmp": 80, "atk": 20, "def": 10, "mat": 20, "mdf": 20, "agi": 30, "luk": 20},
		"traits": [{"kind": "add_skill_type", "id": "magic"}]})
	db.add("classes", {"id": "brawler", "name": "Brawler",
		"growth": {"mhp": 500, "mmp": 100, "atk": 50, "def": 20, "mat": 30, "mdf": 20, "agi": 20, "luk": 10}})
	db.add("actors", {"id": "eric", "name": "Eric", "class": "soldier", "equips": {}, "skills": ["fire"]})
	db.add("actors", {"id": "bruno", "name": "Bruno", "class": "brawler", "equips": {}})
	db.add("states", {"id": "knockout", "name": "Knockout"})
	db.add("states", {"id": "true_aim", "name": "True Aim", "traits": [{"kind": "hit_rate", "value": 100}]})
	db.add("states", {"id": "flat_footed", "name": "Flat-footed", "traits": [{"kind": "evasion_rate", "value": 0}]})
	db.add("skills", {"id": "stab100", "name": "Stab", "formula": "100", "hit_type": "physical", "variance": 0})
	db.add("skills", {"id": "bolt100", "name": "Bolt", "formula": "100", "hit_type": "magical", "variance": 0})
	db.add("skills", {"id": "fire", "name": "Fire", "skill_type": "magic", "formula": "100", "hit_type": "magical",
		"hit": 100, "variance": 0, "scope": "one_enemy"})
	rules = RPGRuleSystem.load_rules("vx_ace", db)
	rules.rng = RPGRandom.new(4242)


func _kinds(cmds: Array) -> Array:
	var out := []
	for c in cmds:
		out.append(str(c.get("kind", "")))
	return out


func test_classic_default_is_the_four_commands() -> void:
	var classic := RPGRuleSystem.load_rules("classic", FakeDB.from_folder("res://rpg/database"))
	var hero := classic.new_actor_battler("hero", 1)
	assert_eq(_kinds(classic.battle_commands(hero)), ["attack", "skill", "guard", "item"],
		"without a list every actor gets Attack, Skill, Guard, Item")


func test_vx_ace_default_is_one_command_per_skill_type() -> void:
	_rules_env()
	var eric := rules.new_actor_battler("eric", 1)
	assert_eq(_kinds(rules.battle_commands(eric)), ["attack", "skill_type", "guard", "item"],
		"a battler with skill type traits gets a command per type (VX Ace)")
	var magic: Dictionary = {}
	for c in rules.battle_commands(eric):
		if str(c.get("kind", "")) == "skill_type":
			magic = c
	assert_eq(str(magic.get("type", "")), "magic", "the command names the type")
	assert_eq(str(magic.get("name", "")), "Magic", "labelled from Types > Skill types")
	# A second granted type becomes another command, in trait order.
	(db.record("classes", "soldier").traits as Array).append({"kind": "add_skill_type", "id": "special"})
	var cmds := rules.battle_commands(eric)
	assert_eq(_kinds(cmds), ["attack", "skill_type", "skill_type", "guard", "item"], "both types are listed")
	assert_eq(str(cmds[2].get("type", "")), "special", "in trait order")
	var bruno := rules.new_actor_battler("bruno", 1)
	assert_eq(_kinds(rules.battle_commands(bruno)), ["attack", "skill", "guard", "item"],
		"without the traits it stays the classic menu")


func test_class_list_then_actor_list() -> void:
	_rules_env()
	var eric := rules.new_actor_battler("eric", 1)
	db.record("classes", "soldier")["battle_commands"] = [{"kind": "row"}, {"kind": "attack"}]
	assert_eq(_kinds(rules.battle_commands(eric)), ["row", "attack"], "the class record's list is used")
	db.record("actors", "eric")["battle_commands"] = [{"kind": "event", "id": "transform"}]
	assert_eq(_kinds(rules.battle_commands(eric)), ["event"], "the actor record's list wins over the class's")
	assert_eq(str(rules.battle_commands(eric)[0].get("id", "")), "transform", "the event id comes through")


# --- rules: rows ---------------------------------------------------------------------------------------


func test_rows_scale_physical_damage_both_ways() -> void:
	_rules_env()
	rules.definition["rows"] = {"back_attack": 0.5, "back_defence": 0.5}
	var eric := rules.new_actor_battler("eric", 1)
	var bruno := rules.new_actor_battler("bruno", 1)
	rules.add_state(eric, "true_aim")
	rules.add_state(bruno, "flat_footed")
	assert_eq(rules.row_rate(eric, "attack"), 1.0, "the front row fights at full strength")
	var stab := func(user, target): return rules.apply_action(user, target, {"kind": "skill", "skill": "stab100"})
	assert_eq(int(stab.call(eric, bruno).damage), 100, "front on front: unchanged")
	bruno.row = 1
	assert_eq(int(stab.call(eric, bruno).damage), 50, "a back-row target takes half")
	bruno.row = 0
	eric.row = 1
	assert_eq(int(stab.call(eric, bruno).damage), 50, "a back-row attacker deals half")
	bruno.row = 1
	assert_eq(int(stab.call(eric, bruno).damage), 25, "both in the back: a quarter")
	assert_eq(int(rules.apply_action(eric, bruno, {"kind": "skill", "skill": "bolt100"}).damage), 100,
		"magic is not scaled by rows")


# --- the scene: the menu the list builds ---------------------------------------------------------------


func _sample_env(prepare: Callable = Callable()) -> void:
	env = Env.create(tree, "res://rpg")
	if prepare.is_valid():
		prepare.call()
	# new_game caches the party battlers from the records, so record edits happen before it.
	env.rpg.state.new_game()
	env.rpg.ui.auto_advance = false


func _warrior_cmds(cmds: Array) -> void:
	var data: RPGProjectData = env.rpg.data
	data.db["classes"].by_id["warrior"]["battle_commands"] = cmds


func _start(battle_args: Dictionary, out: Dictionary) -> Node:
	var rpg: Node = env.rpg
	var run := func():
		out.r = await rpg.ui.run_contract_scene(rpg.ui.scene_path("battle"), battle_args,
			{"rpg": rpg, "state": rpg.state, "rules": rpg.rules, "interpreter": null}, RPGCancelToken.new(), 60.0)
	run.call()
	return env.rpg.ui.scene_stack[-1]


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func _texts(scene: Node) -> Array:
	var out := []
	for it in scene.cmd_list.items:
		out.append(str(it.get("text", "")))
	return out


func _enabled(scene: Node, i: int) -> bool:
	return bool(scene.cmd_list.items[i].get("enabled", true))


## Fight is confirmed and the first actor's command menu is open.
func _at_actor_menu(scene: Node) -> void:
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "party"), "the party command opens")
	scene.handle_action("ok")
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "actor"), "the actor command opens")


func _finish(scene, out: Dictionary) -> void:
	if not is_instance_valid(scene):
		assert_eq(out.get("r", {}).get("status", ""), "finished", "the battle ends")
		return
	scene.auto = true
	env.rpg.ui.auto_advance = true
	var end := Time.get_ticks_msec() + 20000
	while not out.has("r") and Time.get_ticks_msec() < end:
		if is_instance_valid(scene) and scene.phase != "":
			if scene.phase == "party":
				scene.cmd_list.select(0)
			scene.handle_action("ok")
		await tree.process_frame
	assert_eq(out.get("r", {}).get("status", ""), "finished", "the battle ends")


func test_default_menu_with_skill_disabled() -> void:
	_sample_env()
	var out := {}
	var scene := _start({"troop": "slimes", "can_escape": true, "can_lose": true}, out)
	await _at_actor_menu(scene)
	assert_eq(_texts(scene), ["Attack", "Skills", "Guard", "Items"], "the default menu, named by the terms table")
	assert_false(_enabled(scene, 1), "Skill is disabled while the hero knows no battle skills")
	await _finish(scene, out)


func test_class_list_builds_the_menu_and_row_swaps() -> void:
	_sample_env()
	_warrior_cmds([{"kind": "attack"}, {"kind": "skill_type", "type": "magic"}, {"kind": "guard"}, {"kind": "row"}])
	var out := {}
	var scene := _start({"troop": "slimes", "can_escape": true, "can_lose": true}, out)
	var hero = scene.core.party[0]
	assert_eq(hero.row, 0, "the hero starts in the front row")
	await _at_actor_menu(scene)
	assert_eq(_texts(scene), ["Attack", "Magic", "Guard", "Row"], "the class's list builds the menu")
	scene.cmd_list.select(3)
	scene.handle_action("ok")
	await _finish(scene, out)
	assert_eq(hero.row, 1, "the Row command moved the hero to the back row")


func test_skill_type_command_filters_the_skill_list() -> void:
	_sample_env(func():
		env.rpg.data.db["actors"].by_id["hero"]["skills"] = ["fire", "power_strike"])
	_warrior_cmds([{"kind": "attack"}, {"kind": "skill_type", "type": "special"}, {"kind": "skill"}])
	var out := {}
	var scene := _start({"troop": "slimes", "can_escape": true, "can_lose": true}, out)
	await _at_actor_menu(scene)
	assert_eq(_texts(scene), ["Attack", "Special", "Skills"], "skill type commands and the all-skills command mix")
	scene.cmd_list.select(1)
	scene.handle_action("ok")
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "skill"), "the skill list opens")
	if not is_instance_valid(scene):
		return
	var listed := []
	for it in scene.select_list.items:
		listed.append(str(it.get("data", "")))
	assert_eq(listed, ["power_strike"], "only the Special skill is listed")
	scene.handle_action("cancel")
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "actor"), "cancel returns to the menu")
	scene.cmd_list.select(2)
	scene.handle_action("ok")
	assert_true(await _wait_until(func(): return is_instance_valid(scene) and scene.phase == "skill"), "the plain Skill command opens too")
	if not is_instance_valid(scene):
		return
	listed = []
	for it in scene.select_list.items:
		listed.append(str(it.get("data", "")))
	assert_eq(listed, ["fire", "power_strike"], "and lists every skill")
	await _finish(scene, out)


func test_event_command_fires_command_used_pages() -> void:
	_sample_env()
	_warrior_cmds([{"kind": "attack"}, {"kind": "event", "id": "transform", "name": "Transform"}])
	var data: RPGProjectData = env.rpg.data
	data.db["troops"].by_id["slimes"]["pages"] = [
		{"id": "by_event_id", "at": ["after_action"], "span": "once_per_battle",
			"conditions": [{"kind": "command_used", "id": "hero", "command": "transform"}],
			"commands": [{"type": "set_switch", "id": "rain", "value": "on"}]},
		{"id": "any_event", "at": ["after_action"], "span": "once_per_battle",
			"conditions": [{"kind": "command_used", "id": "hero", "command": "event"}],
			"commands": [{"type": "set_switch", "id": "door_unlocked", "value": "on"}]},
	]
	var out := {}
	var scene := _start({"troop": "slimes", "can_escape": true, "can_lose": true}, out)
	await _at_actor_menu(scene)
	assert_eq(_texts(scene), ["Attack", "Transform"], "an Event command is named by its label")
	scene.cmd_list.select(1)
	scene.handle_action("ok")
	await _finish(scene, out)
	assert_true(env.rpg.get_switch("rain"), "the page conditioned on the event's id ran after the action")
	assert_true(env.rpg.get_switch("door_unlocked"), "and so did the page matching any Event command")


func test_actor_escape_command_uses_the_party_escape() -> void:
	_sample_env()
	_warrior_cmds([{"kind": "attack"}, {"kind": "escape"}])
	var out := {}
	var scene := _start({"troop": "slimes", "can_escape": true, "can_lose": true}, out)
	await _at_actor_menu(scene)
	assert_eq(_texts(scene), ["Attack", "Escape"], "Escape can sit in an actor's command list")
	scene.cmd_list.select(1)
	scene.handle_action("ok")
	# The chance-based attempt logs one of the two escape terms right away.
	assert_true(await _wait_until(func(): return not is_instance_valid(scene) or scene.log_label.text.to_lower().contains("escape"), 10.0),
		"the actor-level Escape runs the party escape")
	await _finish(scene, out)
