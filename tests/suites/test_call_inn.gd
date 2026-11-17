extends "res://tests/rpg_test_case.gd"
## Call Inn (issue #18): the whole RM inn stay as one command — the ask message from the two
## System styles (Terms inn_1 / inn_2), a Yes/No where cancel counts as No, gold taken on a stay,
## the System can't-afford message and the didn't-stay branch when the price can't be paid, and a
## full Recover All recovery behind a fade and the inn jingle.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _sample_env() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


func _wait_until(cond: Callable, seconds := 10.0) -> bool:
	var left := seconds * 60.0
	while left > 0:
		if cond.call():
			return true
		await frames(1)
		left -= 1
	return cond.call()


## Runs a Call Inn in the background and returns when it has finished. The message box drives
## itself (auto_advance) and picks `choice` (0 = Yes, 1 = No); every message it shows is
## collected in `asked` through RPG.message_opened.
func _inn(out: Dictionary, asked: Array, extra: Dictionary, choice := 0) -> void:
	env.rpg.ui.message_box.auto_advance = true
	env.rpg.ui.message_box.auto_choice = choice
	if not env.rpg.message_opened.is_connected(_on_open):
		env.rpg.message_opened.connect(_on_open)
	_asked = asked
	var run := func():
		var cmd := {"type": "call_inn", "price": 20}
		for k in extra:
			cmd[k] = extra[k]
		out.r = await env.rpg.run_commands([cmd], {"kind": "api", "id": "t"})
	run.call()
	assert_true(await _wait_until(func(): return out.has("r")), "the command finishes: %s" % str(out.get("r")))


var _asked: Array = []


func _on_open(params: Dictionary) -> void:
	if _asked != null:
		_asked.append(str(params.get("text", "")))


## Both branch lists, as the event editor needs them.
func test_registered_summary_and_branches() -> void:
	await _sample_env()
	assert_true(env.rpg.registry.has_command("call_inn"), "registered")
	var cmd: RPGCommand = env.rpg.registry.get_command("call_inn")
	var args := cmd.with_defaults({"type": "call_inn", "price": 20})
	assert_eq(env.rpg.registry.summary(args), "Inn: 20 \\G (style 1)", str(args))
	assert_eq(cmd.child_lists(args).size(), 2, "a stayed and a left branch")


func test_stay_charges_gold_and_recovers() -> void:
	await _sample_env()
	var hero: Variant = env.rpg.state.actor("hero")
	var max_hp: int = hero.get_resource("hp")
	var max_sp: int = hero.get_resource("sp")
	hero.set_resource("hp", maxi(1, max_hp - 40))
	hero.set_resource("sp", maxi(0, max_sp - 3))
	RPGPartyUtil.states_of(hero).append("poison")
	var out := {}
	var asked: Array = []
	await _inn(out, asked, {"stayed": [{"type": "set_switch", "id": "intro_done", "value": "on"}],
		"left": [{"type": "set_switch", "id": "door_unlocked", "value": "on"}]})
	assert_true(out.r.is_ok(), str(out.r))
	assert_eq(env.rpg.state.gold, 80, "the price was taken")
	assert_eq(hero.get_resource("hp"), max_hp, "Recover All semantics: HP back to max")
	assert_eq(hero.get_resource("sp"), max_sp, "SP back to max")
	assert_true(RPGPartyUtil.states_of(hero).is_empty(), "states cleared")
	assert_true(env.rpg.state.get_switch("intro_done"), "the stayed branch ran")
	assert_false(env.rpg.state.get_switch("door_unlocked"), "the left branch did not")
	assert_false(bool(env.rpg.screen.get_meta("hold_fade", false)), "the fade hold is released afterwards")
	assert_has(asked, "Welcome! A room is 20 G a night. Will you be staying?", str(asked))


func test_no_takes_the_left_branch() -> void:
	await _sample_env()
	var hero: Variant = env.rpg.state.actor("hero")
	hero.set_resource("hp", 10)
	for pick in [1, 1]:
		var out := {}
		var asked: Array = []
		await _inn(out, asked, {"left": [{"type": "set_switch", "id": "door_unlocked", "value": "on"}]}, pick)
		assert_true(out.r.is_ok(), str(out.r))
		assert_eq(env.rpg.state.gold, 100, "no gold changes hands")
		assert_eq(hero.get_resource("hp"), 10, "no recovery")
		assert_true(env.rpg.state.get_switch("door_unlocked"), "the left branch ran")
		env.rpg.state.set_switch("door_unlocked", false)


func test_not_enough_gold_shows_the_system_message() -> void:
	await _sample_env()
	env.rpg.state.change_gold("set", 5)
	var out := {}
	var asked: Array = []
	await _inn(out, asked, {"left": [{"type": "set_switch", "id": "door_unlocked", "value": "on"}]})
	assert_true(out.r.is_ok(), str(out.r))
	assert_eq(env.rpg.state.gold, 5, "the little there is stays")
	assert_has(asked, "Sorry, you don't have enough G.", str(asked))
	assert_true(env.rpg.state.get_switch("door_unlocked"), "not being able to pay counts as not staying")


func test_style_two_and_per_call_overrides() -> void:
	await _sample_env()
	var out := {}
	var asked: Array = []
	await _inn(out, asked, {"style": "2"})
	assert_has(asked, "A room costs 20 G. Stay the night?", str(asked))

	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())
	var out2 := {}
	var asked2: Array = []
	await _inn(out2, asked2, {"message": "Our best suite, %1 \\G. Take it?",
		"no_gold_message": "No coin, no suite."})
	assert_has(asked2, "Our best suite, 20 G. Take it?", str(asked2))
	env.rpg.state.change_gold("set", 3)
	var out3 := {}
	var asked3: Array = []
	await _inn(out3, asked3, {"message": "Again?", "no_gold_message": "No coin, no suite."})
	assert_has(asked3, "No coin, no suite.", str(asked3))


func test_price_from_a_variable_and_a_free_stay() -> void:
	await _sample_env()
	env.rpg.state.set_variable("fish_caught", 30)
	var out := {}
	var asked: Array = []
	await _inn(out, asked, {"price": {"variable": "fish_caught"}})
	assert_true(out.r.is_ok(), str(out.r))
	assert_eq(env.rpg.state.gold, 70, "the variable price was taken")
	assert_has(asked, "Welcome! A room is 30 G a night. Will you be staying?", str(asked))

	var out2 := {}
	var asked2: Array = []
	await _inn(out2, asked2, {"price": 0})
	assert_true(out2.r.is_ok(), str(out2.r))
	assert_eq(env.rpg.state.gold, 70, "a free stay charges nothing")
	assert_has(asked2, "Welcome! A room is 0 G a night. Will you be staying?", str(asked2))
