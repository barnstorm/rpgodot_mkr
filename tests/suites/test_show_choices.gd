extends "res://tests/rpg_test_case.gd"
## Show Choices as RPG Maker has it (#157): "When cancelled" can name one choice of the list, a
## choice with an empty label is not shown, cancel never takes a hidden or greyed-out choice, and
## a command inserted in the editor starts on "Last choice" while a stored command without the
## field keeps meaning Disallow.

const Env := preload("res://tests/rpg_test_env.gd")

var env
var box: Node


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())
	env.rpg.ui.auto_advance = false
	box = env.rpg.ui.message_box
	box.auto_advance = false


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _choice(label: String, value: int, extra: Dictionary = {}) -> Dictionary:
	var c := {"label": label, "then": [{"type": "set_variable", "id": "talks", "operation": "set", "value": value}]}
	c.merge(extra)
	return c


## Fight / Talk / Run setting talks to 1 / 2 / 3; the cancel branch sets 9.
func _fight_talk_run(extra: Dictionary = {}) -> Dictionary:
	var cmd := {"type": "show_choices", "choices": [_choice("Fight", 1), _choice("Talk", 2), _choice("Run", 3)],
		"cancel_then": [{"type": "set_variable", "id": "talks", "operation": "set", "value": 9}]}
	cmd.merge(extra)
	return cmd


## Starts the command and waits for the choice window. The returned Dictionary's "r" is the
## command's result once it ends.
func _open(cmd: Dictionary) -> Dictionary:
	env.rpg.state.set_variable("talks", 0)
	var out := {"r": null}
	var run := func() -> void: out.r = await env.rpg.run_commands([cmd])
	run.call()
	for i in 60:
		await frames(1)
		if box.mode == "choices":
			break
	assert_eq(box.mode, "choices", "the choice window opens")
	return out


func _done(out: Dictionary) -> void:
	for i in 120:
		if out.r != null:
			break
		await frames(1)
	assert_true(out.r != null and out.r.is_ok(), "the command ends: %s" % [out.r])


## What the cancel key does (rpg_message_box._process_choices): the cancel choice, or nothing.
func _press_cancel() -> bool:
	if box._cancel_index < 0:
		return false
	box._pick(box._cancel_index)
	return true


func test_cancel_takes_the_named_choice() -> void:
	var out := await _open(_fight_talk_run({"cancel": "choice", "cancel_choice": 2}))
	assert_true(_press_cancel(), "cancel is allowed")
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 3, "cancel picked Run, the third choice")
	out = await _open(_fight_talk_run({"cancel": "choice", "cancel_choice": 0}))
	assert_true(_press_cancel())
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 1, "choice 0 is the first")
	# The modes that were there before still do what they did.
	out = await _open(_fight_talk_run({"cancel": "last_choice"}))
	assert_true(_press_cancel())
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 3)
	out = await _open(_fight_talk_run({"cancel": "branch"}))
	assert_true(_press_cancel())
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 9, "the cancel branch")
	out = await _open(_fight_talk_run({"cancel": "disallow"}))
	assert_false(_press_cancel(), "disallow: cancel does nothing")
	box._try_pick(1)
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 2)


## The cancel choice is a choice of the list as written, whatever is hidden above it; one that
## is hidden itself (or names no choice) leaves cancel doing nothing.
func test_cancel_choice_counts_the_list_as_written() -> void:
	env.rpg.state.set_switch("key_given", false)
	var cmd := _fight_talk_run({"cancel": "choice", "cancel_choice": 2})
	cmd.choices[1]["show_switch"] = "key_given"
	var out := await _open(cmd)
	assert_eq(box._choices, ["Fight", "Run"], "Talk is hidden")
	assert_true(_press_cancel())
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 3, "still Run, now the second shown")
	cmd["cancel_choice"] = 1
	out = await _open(cmd)
	assert_false(_press_cancel(), "the cancel choice is hidden: cancel does nothing")
	box._try_pick(0)
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 1)
	cmd["cancel_choice"] = 7
	out = await _open(cmd)
	assert_false(_press_cancel(), "no such choice: cancel does nothing")
	box._try_pick(0)
	await _done(out)


func test_blank_choices_are_not_shown() -> void:
	var cmd := {"type": "show_choices", "cancel": "last_choice", "default": 2,
		"choices": [_choice("Yes", 1), _choice("", 2), _choice("No", 3), _choice("", 4)]}
	var out := await _open(cmd)
	assert_eq(box._choices, ["Yes", "No"], "only the choices with text")
	assert_eq(box._choice_index, 1, "the cursor starts on No (choice 2 as listed)")
	assert_true(_press_cancel())
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 3, "the last choice shown is No; its own branch runs")
	out = await _open(cmd)
	box._try_pick(1)
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 3, "picking the second row runs No's branch, not the blank's")
	# Nothing but blanks: no window, and the event goes on.
	env.rpg.state.set_variable("talks", 0)
	var r: RPGResult = await env.rpg.run_commands([
		{"type": "show_choices", "choices": [_choice("", 1), _choice("", 2)]},
		{"type": "set_variable", "id": "talks", "operation": "set", "value": 5}])
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("talks")), 5)


func test_cancel_never_takes_a_greyed_out_choice() -> void:
	env.rpg.state.set_switch("door_unlocked", false)
	var cmd := _fight_talk_run({"cancel": "last_choice"})
	cmd.choices[2]["enable_switch"] = "door_unlocked"
	var out := await _open(cmd)
	assert_true(box._disabled.has(2), "Run is greyed out")
	assert_false(_press_cancel(), "cancel does not pick what the cursor cannot")
	box._try_pick(0)
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 1)
	cmd = _fight_talk_run({"cancel": "choice", "cancel_choice": 2})
	cmd.choices[2]["enable_switch"] = "door_unlocked"
	out = await _open(cmd)
	assert_false(_press_cancel())
	box._try_pick(0)
	await _done(out)
	env.rpg.state.set_switch("door_unlocked", true)
	out = await _open(cmd)
	assert_true(_press_cancel(), "enabled again: cancel takes it")
	await _done(out)
	assert_eq(int(env.rpg.get_variable("talks")), 3)


## "default" is what a missing field means, so a stored command without "cancel" still disallows
## it; "new_default" is where a command inserted in the editor starts (RPG Maker's last choice).
func test_new_commands_start_on_last_choice_and_stored_ones_keep_disallow() -> void:
	var cmd: RPGCommand = env.rpg.registry.get_command("show_choices")
	assert_eq(str(cmd.with_defaults({"type": "show_choices"}).cancel), "disallow", "a missing field keeps its old meaning")
	var fresh: Dictionary = cmd.new_args()
	assert_eq(str(fresh.cancel), "last_choice", "the editor's new command cancels to the last choice")
	assert_eq(str(fresh.type), "show_choices")
	assert_eq(fresh.choices.size(), 2, "Yes / No as before")
	var out := await _open({"type": "show_choices", "choices": [_choice("Yes", 1), _choice("No", 2)]})
	assert_false(_press_cancel(), "stored without the field: cancel still does nothing")
	box._try_pick(0)
	await _done(out)
	# Commands without a "new_default" start exactly as before.
	var text: RPGCommand = env.rpg.registry.get_command("show_text")
	assert_eq(text.new_args(), text.with_defaults({"type": "show_text"}))
	# The new mode passes the structural check; a wrong mode still does not.
	var ok := _fight_talk_run({"cancel": "choice", "cancel_choice": 1})
	assert_eq(RPGValidator.command_structure(ok, env.rpg.registry).filter(func(x): return x.severity == "error"), [])
	var bad := _fight_talk_run({"cancel": "sometimes"})
	assert_false(RPGValidator.command_structure(bad, env.rpg.registry).filter(func(x): return x.severity == "error").is_empty())
