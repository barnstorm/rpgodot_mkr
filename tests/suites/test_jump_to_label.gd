extends "res://tests/rpg_test_case.gd"
## Jump to Label reaches a label anywhere in the event (#159): RPG Maker's command list is flat,
## so a jump can land inside a Conditional Branch, a Loop or a choice. The kit's lists are nested;
## a jump now enters the blocks that hold the label, runs the rest of that branch and goes on
## after the block as if it had been entered the usual way (a loop keeps looping, Break Loop
## leaves it). The search is nearest first: the list the jump is in, the blocks inside it, then
## outwards. Labels in a called common event belong to that event.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func before_each() -> void:
	env = Env.create(tree)
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8), "up")
	assert_true(r.is_ok(), "start transfer: %s" % r)
	env.rpg.state.set_variable("counter", 0)
	env.rpg.state.set_variable("order_var", 0)


func after_each() -> void:
	await env.destroy()


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "labels"})


func _add(n: int, id := "counter") -> Dictionary:
	return {"type": "set_variable", "id": id, "operation": "add", "value": n}


func _jump(name: String) -> Dictionary:
	return {"type": "jump_to_label", "name": name}


func _label(name: String) -> Dictionary:
	return {"type": "label", "name": name}


## A Conditional Branch on the counter (true while it is at least `at_least`).
func _if(at_least: int, then: Array, otherwise: Array = []) -> Dictionary:
	return {"type": "if", "condition": {"kind": "variable", "id": "counter", "op": ">=", "value": at_least}, "then": then, "else": otherwise}


func _counter() -> int:
	return int(env.rpg.get_variable("counter"))


func test_jump_into_a_conditional_branch() -> void:
	# The condition is false, and is not asked: the jump lands in "then" and finishes it.
	var r: RPGResult = await _run([
		_jump("inside"),
		_add(1000),
		_if(5, [_add(100), _label("inside"), _add(1)], [_add(50)]),
		_add(10)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 11, "the rest of the branch, then on after the block; not the else")
	# Into the else branch.
	env.rpg.state.set_variable("counter", 0)
	r = await _run([
		_jump("inside"),
		_add(1000),
		_if(0, [_add(100)], [_add(50), _label("inside"), _add(2)]),
		_add(10)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 12)


## The issue's story: from one branch to a label inside the other.
func test_jump_from_one_branch_into_the_other() -> void:
	var r: RPGResult = await _run([
		_if(0, [_add(1), _jump("other"), _add(100)], [_add(200), _label("other"), _add(2)]),
		_add(10)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 13, "then's start, else's end, then on")


func test_jump_into_a_loop_keeps_looping() -> void:
	var r: RPGResult = await _run([
		_jump("mid"),
		{"type": "loop", "commands": [
			_add(100),
			_label("mid"),
			_add(1),
			_if(203, [{"type": "break_loop"}])]},
		_add(1, "order_var")])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 203, "1, then two full passes: the loop went round after the jump")
	assert_eq(int(env.rpg.get_variable("order_var")), 1, "Break Loop left it and the event went on")


func test_break_loop_right_after_the_jump() -> void:
	var r: RPGResult = await _run([
		_jump("in"),
		{"type": "loop", "commands": [
			_add(1000),
			_label("in"),
			_add(5),
			{"type": "break_loop"}]},
		_add(7, "order_var")])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 5, "the loop's start never ran")
	assert_eq(int(env.rpg.get_variable("order_var")), 7, "the break left the loop that was jumped into")


func test_jump_into_a_choice_branch() -> void:
	# No choice window opens: the jump is already past it.
	var r: RPGResult = await _run([
		_jump("yes_again"),
		{"type": "show_choices", "cancel": "branch",
			"choices": [{"label": "Yes", "then": [_add(100), _label("yes_again"), _add(1)]}, {"label": "No", "then": [_add(50)]}],
			"cancel_then": [_add(500)]},
		_add(10)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 11)
	# The cancel branch is a block like the others.
	env.rpg.state.set_variable("counter", 0)
	r = await _run([
		_jump("cancelled"),
		{"type": "show_choices", "cancel": "branch",
			"choices": [{"label": "Yes", "then": [_add(100)]}],
			"cancel_then": [_add(500), _label("cancelled"), _add(3)]},
		_add(10)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 13)


## Three blocks deep: a branch in a loop in a branch. The break leaves that loop, and every
## block on the way out goes on as usual.
func test_jump_through_several_blocks() -> void:
	var r: RPGResult = await _run([
		_jump("deep"),
		_if(5000, [
			{"type": "loop", "commands": [
				_add(1000),
				_if(0, [_label("deep"), _add(1), {"type": "break_loop"}]),
				_add(5000)]},
			_add(10)]),
		_add(100)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 111, "1 at the label, 10 after the loop, 100 after the outer branch")


## Out of one block and into another: the search goes outwards, and each list looks through
## everything inside it.
func test_jump_from_inside_a_loop_into_a_later_branch() -> void:
	var r: RPGResult = await _run([
		{"type": "loop", "commands": [
			_add(1),
			_if(3, [_jump("after")])]},
		_add(1000),
		_if(9999, [_add(2000), _label("after"), _add(20)]),
		_add(100)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 123)


## A jump back into a block that already ran: the old "label at the top, jump below" loop works
## with the label inside a branch.
func test_jump_backwards_into_a_branch() -> void:
	var r: RPGResult = await _run([
		_if(0, [_add(100), _label("top"), _add(1)]),
		_if(104, [], [_jump("top")])])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 104, "100 + 1, then three more passes through the label")


func test_the_nearest_label_wins() -> void:
	# The jump's own list first, even when a block above holds the same name.
	var r: RPGResult = await _run([
		_if(9999, [_label("here"), _add(1000)]),
		_jump("here"),
		_add(100),
		_label("here"),
		_add(1)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 1)
	# Then the blocks of that list, before anything further out.
	env.rpg.state.set_variable("counter", 0)
	r = await _run([
		_label("here"),
		_add(1, "order_var"),
		_if(0, [
			_if(0, [_jump("here")]),
			_if(9999, [_label("here"), _add(5)]),
			_add(10)]),
		_add(100)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 115)
	assert_eq(int(env.rpg.get_variable("order_var")), 1, "the outer label was not used")


func test_labels_that_cannot_be_reached() -> void:
	# A block that is switched off (Toggle skip) hides its labels with it.
	var skipped := _if(0, [_label("ghost"), _add(1)])
	skipped["skip"] = true
	var r: RPGResult = await _run([_jump("ghost"), skipped])
	assert_true(r.is_error() and r.message.contains("ghost"), str(r))
	# So does a label that is switched off itself.
	var off := _label("ghost")
	off["skip"] = true
	r = await _run([_jump("ghost"), _if(0, [off, _add(1)])])
	assert_true(r.is_error() and r.message.contains("ghost"), str(r))
	assert_eq(_counter(), 0)
	# No label of that name anywhere.
	r = await _run([_if(0, [_jump("nowhere")])])
	assert_true(r.is_error() and r.message.contains("nowhere"), str(r))


## A common event's labels are its own: the caller cannot jump into it, a jump inside it reaches
## into its own blocks, and one that finds nothing there names the common event.
func test_labels_belong_to_their_common_event() -> void:
	var data: RPGProjectData = env.rpg.data
	data.common_events["nested"] = {"id": "nested", "name": "Nested", "trigger": "none", "switch": "", "commands": [
		_jump("inner"),
		_add(1000),
		{"type": "loop", "commands": [_add(100), _label("inner"), _add(1), {"type": "break_loop"}]},
		_add(10)]}
	var r: RPGResult = await _run([{"type": "call_common_event", "id": "nested"}, _add(100)])
	assert_true(r.is_ok(), str(r))
	assert_eq(_counter(), 111, "the jump entered the common event's own loop")
	env.rpg.state.set_variable("counter", 0)
	r = await _run([_jump("inner"), {"type": "call_common_event", "id": "nested"}])
	assert_true(r.is_error() and r.message.contains("inner"), "the caller does not see the common event's labels: %s" % r)
	data.common_events["lost"] = {"id": "lost", "name": "Lost", "trigger": "none", "switch": "", "commands": [_jump("outside")]}
	r = await _run([{"type": "call_common_event", "id": "lost"}, _if(0, [_label("outside")])])
	assert_true(r.is_error() and r.message.contains("lost"), "and the common event does not see the caller's: %s" % r)


## An error inside a block that was jumped into still says where it happened.
func test_an_error_after_the_jump_is_reported() -> void:
	var r: RPGResult = await _run([
		_jump("in"),
		_if(9999, [_label("in"), {"type": "set_variable", "id": "no_such_variable", "operation": "set", "value": 1}]),
		_add(1)])
	assert_true(r.is_error(), str(r))
	assert_true(r.message.contains("no_such_variable"), str(r))
	assert_eq(_counter(), 0, "the event stopped there")
