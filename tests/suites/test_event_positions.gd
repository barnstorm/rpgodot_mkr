extends "res://tests/rpg_test_case.gd"
## Event positions belong to the visit (#155): RPG Maker sets every event up at its editor position
## and facing each time a map loads, so an event moved by Set Event Location or a move route is
## back in place when the player returns. A game saved on the map still loads with the events
## where they stood, a transfer inside the map moves nothing, and Set Event Location's Keep is
## the opt-in for a move that should stick.

const Env := preload("res://tests/rpg_test_env.gd")
const HOME := Vector2i(13, 9)  # the village sign's editor position (facing down)

var env


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null


func _sign() -> RPGEvent:
	return env.game.map.get_event("village_sign")


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


func _move_sign(cell: Vector2i, extra: Dictionary = {}) -> void:
	var cmd := {"type": "set_event_location", "event": "village_sign", "mode": "position", "position": [cell.x, cell.y], "facing": "left"}
	cmd.merge(extra, true)
	var r: RPGResult = await _run([cmd])
	assert_true(r.is_ok(), str(r))
	assert_eq(_sign().cell, cell)


func _leave_and_return() -> void:
	var r: RPGResult = await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	assert_true(r.is_ok(), str(r))
	r = await env.game.transfer("town", Vector2i(14, 12), "down", "none")
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


func test_a_moved_event_is_back_in_place_on_the_next_visit() -> void:
	assert_eq(_sign().cell, HOME)
	await _move_sign(Vector2i(16, 12))
	assert_eq(_sign().facing, "left")
	await _leave_and_return()
	assert_eq(_sign().cell, HOME, "the map was set up afresh: the sign is where the editor put it")
	assert_eq(_sign().facing, "down", "and faces as the editor set it")
	assert_false(env.rpg.state.event_changes.has("town/village_sign"), "nothing of the last visit is left")


func test_a_transfer_inside_the_map_keeps_events_where_they_are() -> void:
	await _move_sign(Vector2i(16, 12))
	var r: RPGResult = await env.game.transfer("town", Vector2i(15, 13), "down", "none")
	assert_true(r.is_ok(), str(r))
	assert_eq(_sign().cell, Vector2i(16, 12), "RPG Maker only sets a map up when the map changes")


## A game saved on the map loads with the events where they stood (RPG Maker saves the map as
## it is); the visit after that starts from the editor positions again.
func test_saving_and_loading_on_the_map_restores_the_positions() -> void:
	await _move_sign(Vector2i(16, 12))
	var save: Dictionary = env.rpg.saves.build_save()
	await _move_sign(Vector2i(17, 12))
	env.rpg.state.new_game()
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	assert_true(await env.settle())
	assert_eq(env.game.map.map_id, "town")
	assert_eq(_sign().cell, Vector2i(16, 12), "loaded where it stood when the game was saved")
	assert_eq(_sign().facing, "left")
	await _leave_and_return()
	assert_eq(_sign().cell, HOME, "the next visit starts from the editor position")


## A move route's result is stored when the game is saved (for the load above). It used to stay
## in the save for good; now it lasts for the visit like any other move.
func test_an_event_moved_by_a_route_resets_too_even_after_a_save() -> void:
	var r: RPGResult = await _run([{"type": "move_route", "target": "village_sign", "wait": true, "steps": [{"step": "down"}]}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_sign().cell, HOME + Vector2i(0, 1), "the route moved it one step")
	env.rpg.saves.build_save()
	assert_true(env.rpg.state.event_changes.has("town/village_sign"), "saving stores where it stands")
	await _leave_and_return()
	assert_eq(_sign().cell, HOME)
	assert_false(env.rpg.state.event_changes.has("town/village_sign"))


## Keep: the place the event returns to instead of its editor position, until another Keep.
func test_keep_makes_a_move_stick() -> void:
	await _move_sign(Vector2i(16, 12), {"keep": true})
	await _leave_and_return()
	assert_eq(_sign().cell, Vector2i(16, 12), "kept across the map load")
	assert_eq(_sign().facing, "left")
	# A later move without Keep is for that visit only: the kept place is where it returns.
	await _move_sign(Vector2i(17, 12), {"facing": "up"})
	var save: Dictionary = env.rpg.saves.build_save()
	await _leave_and_return()
	assert_eq(_sign().cell, Vector2i(16, 12), "back at the kept place, not the editor's and not the last move's")
	assert_eq(_sign().facing, "left")
	# The save made in between still loads with the event where it stood then.
	env.rpg.state.new_game()
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	assert_true(await env.settle())
	assert_eq(_sign().cell, Vector2i(17, 12))
	assert_eq(_sign().facing, "up")
	await _leave_and_return()
	assert_eq(_sign().cell, Vector2i(16, 12), "and the kept place survived the save")
	# Another Keep replaces it.
	await _move_sign(Vector2i(18, 12), {"keep": true})
	await _leave_and_return()
	assert_eq(_sign().cell, Vector2i(18, 12))


func test_swapped_events_go_home_unless_kept() -> void:
	var elder: RPGEvent = env.game.map.get_event("elder")
	var elder_home: Vector2i = elder.cell
	var swap := {"type": "set_event_location", "event": "village_sign", "mode": "swap", "swap_with": "elder"}
	var r: RPGResult = await _run([swap])
	assert_true(r.is_ok(), str(r))
	assert_eq(_sign().cell, elder_home)
	assert_eq(elder.cell, HOME)
	await _leave_and_return()
	assert_eq(_sign().cell, HOME, "both are back")
	assert_eq(env.game.map.get_event("elder").cell, elder_home)
	swap["keep"] = true
	r = await _run([swap])
	assert_true(r.is_ok(), str(r))
	await _leave_and_return()
	assert_eq(_sign().cell, elder_home, "a kept swap holds for both")
	assert_eq(env.game.map.get_event("elder").cell, HOME)


## A save from before this change has plain entries: they load as the positions of that visit.
func test_entries_of_older_saves_apply_once() -> void:
	var save: Dictionary = env.rpg.saves.build_save()
	_plant_old_entry(save)
	env.rpg.state.new_game()
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	assert_true(await env.settle())
	assert_eq(_sign().cell, Vector2i(16, 12), "the old entry places the event when the save loads")
	await _leave_and_return()
	assert_eq(_sign().cell, HOME, "and is gone at the next visit")


## Writes an old-style event_changes entry wherever the save keeps them.
func _plant_old_entry(d: Dictionary) -> bool:
	for k in d.keys():
		if str(k) == "event_changes" and d[k] is Dictionary:
			d[k]["town/village_sign"] = {"position": [16, 12], "facing": "left"}
			return true
		if d[k] is Dictionary and _plant_old_entry(d[k]):
			return true
	return false
