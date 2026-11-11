extends "res://tests/rpg_test_case.gd"
## Regressions from the runtime review: transfers started by parallel events, failed transfers
## and loads, fades that outlive their game, self switches after a fading transfer, and saves
## that made Erase Event permanent.

const Env := preload("res://tests/rpg_test_env.gd")

var env


func before_each() -> void:
	env = Env.create(tree)


func after_each() -> void:
	await env.destroy()


## Adds an event to a map's event list in memory (before the map is loaded).
func _add_event(map_id: String, id: String, pos: Array, trigger: String, commands: Array, priority := "below") -> void:
	var list: Array = env.rpg.data.map_events(map_id)
	list.append({"id": id, "name": id, "position": pos, "notes": "", "pages": [{
		"conditions": [], "graphic": null, "movement": {"type": "fixed"}, "options": {},
		"priority": priority, "trigger": trigger, "commands": commands}]})


func _wait_until(cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func test_parallel_event_can_transfer_the_player() -> void:
	# "A parallel event checks the player's position, then teleports": used to deadlock, since the
	# map shutdown waited for the very task that was running the transfer.
	_add_event("town", "porter_none", [9, 0], "parallel", [
		{"type": "transfer_player", "to": {"map": "house_inside", "position": [1, 1]}, "fade": "none"}])
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok(), str(r))
	var arrived: bool = await _wait_until(func(): return env.game.map != null and env.game.map.map_id == "house_inside" and not env.game.transferring)
	assert_true(arrived, "parallel transfer finished (map=%s transferring=%s)" % [env.game.map.map_id if env.game.map else "?", env.game.transferring])
	assert_false(env.rpg.scheduler.input_locked(), "input lock released")
	assert_eq(env.game.player.cell, Vector2i(1, 1))
	assert_false(env.rpg.scheduler.parallels.has("town/porter_none"), "the porter's task ended with its map")


func test_parallel_transfer_with_fade() -> void:
	_add_event("town", "porter", [9, 0], "parallel", [
		{"type": "transfer_player", "to": {"map": "house_inside", "position": [1, 1]}, "fade": "black"}])
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok(), str(r))
	var arrived: bool = await _wait_until(func(): return env.game.map.map_id == "house_inside" and not env.game.transferring)
	assert_true(arrived, "faded parallel transfer finished")
	assert_false(env.rpg.scheduler.input_locked())
	assert_false(env.rpg.screen.is_faded, "screen faded back in")


func test_failed_transfer_leaves_no_dead_parallel() -> void:
	_add_event("house_inside", "ticker", [5, 5], "parallel", [
		{"type": "set_variable", "id": "ticks", "operation": "add", "value": 1},
		{"type": "wait", "seconds": 0.02}])
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok())
	var bad: RPGResult = await env.game.transfer("house_inside", Vector2i(2, 2), "down", "none")
	assert_true(bad.is_error(), "occupied cell fails")
	await frames(5)
	for key in env.rpg.scheduler.parallels:
		assert_false(str(key).begins_with("house_inside/"), "no task left from the rolled-back map: %s" % key)
	var good: RPGResult = await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	assert_true(good.is_ok(), str(good))
	var ticked: bool = await _wait_until(func(): return int(env.rpg.get_variable("ticks")) >= 2)
	assert_true(ticked, "the destination's parallel runs on the next, successful visit")


func test_load_onto_occupied_cell_uses_nearest_free_cell() -> void:
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok())
	env.rpg.set_variable("counter", 7)
	var save: Dictionary = env.rpg.saves.build_save()
	# The chest now stands where the player was saved.
	save.map.position = [5, 5]
	env.rpg.set_variable("counter", 3)
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), "load succeeds: %s" % lr)
	assert_eq(int(env.rpg.get_variable("counter")), 7, "saved state applied")
	assert_ne(env.game.player.cell, Vector2i(5, 5), "not on top of the chest")
	assert_true(env.game.player.cell.distance_to(Vector2i(5, 5)) <= 2.0, "next to the saved cell: %s" % env.game.player.cell)
	assert_true(is_instance_valid(env.game.player) and env.game.player.is_inside_tree(), "player on the map")


func test_load_failure_keeps_live_state() -> void:
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok())
	env.rpg.set_variable("counter", 7)
	var save: Dictionary = env.rpg.saves.build_save()
	env.rpg.set_variable("counter", 3)
	# Make the transfer fail after validation: the map's scene path points at a non-map scene.
	var entry: Dictionary = env.rpg.data.map_entry("town")
	var had_scene := entry.has("scene")
	var old_scene: Variant = entry.get("scene")
	entry["scene"] = "res://tests/fixtures/not_a_map.tscn"
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	if had_scene:
		entry["scene"] = old_scene
	else:
		entry.erase("scene")
	assert_true(lr.is_error(), "a non-map scene fails the load")
	assert_eq(int(env.rpg.get_variable("counter")), 3, "live state restored after a failed load")


func test_fade_hold_does_not_outlive_its_game() -> void:
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok())
	var save: Dictionary = env.rpg.saves.build_save()
	var fr: RPGResult = await env.rpg.run_commands([{"type": "fade_out", "seconds": 0.0}], {"kind": "api", "id": "t"})
	assert_true(fr.is_ok(), str(fr))
	assert_true(env.rpg.screen.is_faded)
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	assert_false(env.rpg.screen.is_faded, "loading an unfaded save shows the map")
	# After a reset (as on return to title), black transfers fade back in again.
	await env.rpg.run_commands([{"type": "fade_out", "seconds": 0.0}], {"kind": "api", "id": "t"})
	env.rpg.screen.clear_all()
	env.rpg.screen.set_faded(false)
	var tr: RPGResult = await env.game.transfer("house_inside", Vector2i(1, 1), "down", "black")
	assert_true(tr.is_ok())
	assert_false(env.rpg.screen.is_faded, "transfer faded back in")
	assert_eq(env.rpg.screen.fade_rect.color.a, 0.0)


func test_self_switch_after_fading_transfer() -> void:
	_add_event("town", "guide", [10, 10], "action_button", [
		{"type": "transfer_player", "to": {"map": "house_inside", "position": [1, 1]}, "fade": "black"},
		{"type": "set_self_switch", "switch": "B", "value": true}], "same")
	var r: RPGResult = await env.start_on("town", Vector2i(10, 11), "up")
	assert_true(r.is_ok())
	var p: RPGPlayer = env.game.player
	assert_true(p.check_action(), "guide starts")
	assert_true(await env.settle())
	await frames(2)
	assert_eq(env.game.map.map_id, "house_inside")
	assert_true(env.rpg.state.get_self_switch("town", "guide", "B"), "self switch B of town/guide is ON")


func test_save_keeps_erase_event_temporary() -> void:
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok())
	var chest: Node = env.game.map.get_event("chest")
	chest.set_meta("persist", true)
	chest.erased = true
	env.rpg.saves.build_save()
	assert_false(env.rpg.state.event_changes.get("town/chest", {}).has("erased"), "erase is not stored")
	await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	await env.game.transfer("town", Vector2i(12, 8), "down", "none")
	var again: Node = env.game.map.get_event("chest")
	assert_false(again.erased, "the chest is back on the next visit")
	assert_true(again.page_index >= 0)


func test_load_restores_pictures_and_bgs() -> void:
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok())
	var pic := "res://assets/starter/System/system.png"
	var sr: RPGResult = await env.rpg.run_commands([{"type": "show_picture", "number": 3, "picture": pic, "x": 40, "y": 50, "origin": "top_left", "scale": 150.0, "opacity": 200}], {"kind": "api", "id": "t"})
	assert_true(sr.is_ok(), str(sr))
	env.rpg.audio.play_bgs({"file": "res://assets/starter/Sound/cancel.wav", "volume": 80})
	var save: Dictionary = env.rpg.saves.build_save()
	env.rpg.screen.erase_picture(3)
	env.rpg.audio.play_bgs(null)
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	assert_true(env.rpg.screen.pictures.has(3), "picture 3 restored")
	var s: Sprite2D = env.rpg.screen.pictures.get(3)
	if s != null:
		assert_eq(s.position, Vector2(40, 50))
		assert_true(absf(s.scale.x - 1.5) < 0.01, "scale kept")
		assert_eq(str(s.get_meta("picture_name", "")), pic)
	assert_eq(str(env.rpg.audio.current_bgs.get("file", "")), "res://assets/starter/Sound/cancel.wav", "BGS restored")
