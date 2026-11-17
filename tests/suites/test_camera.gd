extends "res://tests/rpg_test_case.gd"
## Pan Screen (#63): Scroll Map lock/unlock takes the camera off the player (pans still scroll a
## locked screen, unlock resumes following without a snap), pans queue one after another, a map
## change forgets the lock while a same-map transfer keeps it, and it all rides through a save.

const Env := preload("res://tests/rpg_test_env.gd")
const SLOT := 19

var env


func before_each() -> void:
	env = Env.create(tree)
	var r: RPGResult = await env.start_on("town", Vector2i(10, 7))
	assert_true(r.is_ok(), str(r))
	await env.settle()


func after_each() -> void:
	if FileAccess.file_exists(env.rpg.saves.slot_path(SLOT)):
		DirAccess.remove_absolute(env.rpg.saves.slot_path(SLOT))
	await env.destroy()


## Camera values pass through tweens and lerps, so compare with a tolerance instead of assert_eq.
func _near(actual: Vector2, expected: Vector2, msg := "") -> void:
	assert_true(actual.distance_to(expected) < 0.05, "%s expected <%s> got <%s>" % [msg, str(expected), str(actual)])


func _scroll(cmd: Dictionary) -> RPGResult:
	var p := {"type": "scroll_map"}
	p.merge(cmd)
	var r: RPGResult = await env.rpg.run_commands([p], {"kind": "api", "id": "t"})
	# The command's wait ends on process_frame, a hair before the player's _process applies the
	# finished pan to the camera; one more frame settles the read.
	await frames(1)
	return r


## Moves the player by whole cells (place, as the interpreter tests do) and lets frames pass so
## the lock compensation applies.
func _move_to(c: Vector2i) -> void:
	env.game.player.place(c)
	await frames(2)


func _await_pans() -> void:
	for i in 600:
		if not env.game.player.camera_panning():
			return
		await frames(1)


func test_lock_holds_the_screen_and_unlock_follows_without_snapping() -> void:
	var p: RPGPlayer = env.game.player
	var ts: int = p.tile_size
	var base_world := p.position + p.camera.position
	assert_true((await _scroll({"direction": "lock"})).is_ok())
	assert_true(p.camera_locked, "the camera is locked")
	await _move_to(Vector2i(12, 7))
	await _move_to(Vector2i(12, 9))
	_near(p.position + p.camera.position, base_world, "the screen stayed at the locked point")
	# Unlock does not snap, as in RPG Maker: the screen sits exactly where the lock held it.
	var held := p.camera.position
	assert_true((await _scroll({"direction": "unlock"})).is_ok())
	assert_false(p.camera_locked, "unlocked")
	_near(p.camera.position, held, "no snap on unlock")
	await _move_to(Vector2i(13, 9))
	_near(p.position + p.camera.position, base_world + Vector2(ts, 0), "the camera follows the player again")


func test_the_lock_persists_across_events_and_a_pan_scrolls_the_locked_screen() -> void:
	var p: RPGPlayer = env.game.player
	var ts: int = p.tile_size
	assert_true((await _scroll({"direction": "lock"})).is_ok())
	await _move_to(Vector2i(11, 7))
	assert_true(p.camera_locked, "still locked after the event ended")
	var world := p.position + p.camera.position
	assert_true((await _scroll({"direction": "right", "distance": 2, "wait": true})).is_ok())
	assert_false(p.camera_panning(), "the pan finished")
	assert_true(p.camera_locked, "a pan does not unlock")
	await _move_to(Vector2i(11, 9))
	_near(p.position + p.camera.position, world + Vector2(2 * ts, 0), "the pan scrolled the locked screen; the walk did not")


func test_unlock_mid_pan_carries_the_rest_of_the_scroll_over() -> void:
	var p: RPGPlayer = env.game.player
	var ts: int = p.tile_size
	var start_world := p.position + p.camera.position
	assert_true((await _scroll({"direction": "lock"})).is_ok())
	assert_true((await _scroll({"direction": "right", "distance": 6, "speed": 6, "wait": false})).is_ok())
	assert_true(p.camera_panning(), "the pan runs without its wait")
	await frames(6)
	assert_true((await _scroll({"direction": "unlock"})).is_ok())
	assert_true(p.camera_panning(), "the remainder of the pan carried over the unlock")
	await _await_pans()
	assert_false(p.camera_panning(), "the carried pan finished")
	_near(p.position + p.camera.position, start_world + Vector2(6 * ts, 0), "the pan still covered its full six tiles")


func test_pans_queue_up_and_one_wait_covers_the_whole_queue() -> void:
	var p: RPGPlayer = env.game.player
	var ts: int = p.tile_size
	var start := p.camera.position
	assert_true((await _scroll({"direction": "right", "distance": 2, "wait": false})).is_ok())
	assert_true(p.camera_panning(), "the first pan runs without its wait")
	assert_true((await _scroll({"direction": "down", "distance": 3, "wait": true})).is_ok())
	assert_false(p.camera_panning(), "the wait covered both pans")
	_near(p.camera.position, start + Vector2(2 * ts, 3 * ts), "right two, then down three")


func test_return_pans_back_onto_the_player() -> void:
	var p: RPGPlayer = env.game.player
	assert_true((await _scroll({"direction": "right", "distance": 3, "wait": true})).is_ok())
	assert_true((await _scroll({"direction": "return", "wait": true})).is_ok())
	_near(p.camera.position, Vector2(0, -p.tile_size / 2.0), "back to the hero-centred screen")
	# While locked, return pans onto the player even away from the lock point.
	assert_true((await _scroll({"direction": "lock"})).is_ok())
	await _move_to(Vector2i(12, 9))
	assert_true((await _scroll({"direction": "right", "distance": 2, "wait": true})).is_ok())
	assert_true((await _scroll({"direction": "return", "wait": true})).is_ok())
	_near(p.camera.position, Vector2(0, -p.tile_size / 2.0), "a locked return pans back onto the hero")
	assert_true(p.camera_locked, "return does not unlock")


func test_a_map_change_clears_the_lock_but_a_same_map_transfer_keeps_it() -> void:
	var p: RPGPlayer = env.game.player
	assert_true((await _scroll({"direction": "lock"})).is_ok())
	assert_true((await _scroll({"direction": "right", "distance": 2, "wait": true})).is_ok())
	# Same map: the lock, pan offset and frozen screen all survive the teleport.
	var world := p.position + p.camera.position
	var r: RPGResult = await env.game.transfer("town", Vector2i(4, 4), "down", "none")
	assert_true(r.is_ok(), str(r))
	await frames(1)
	assert_true(p.camera_locked, "a same-map transfer keeps the lock")
	_near(p.position + p.camera.position, world, "the screen stayed locked across the same-map teleport")
	# A different map forgets everything.
	var r2: RPGResult = await env.game.transfer("house_inside", Vector2i(5, 5), "down", "none")
	assert_true(r2.is_ok(), str(r2))
	assert_false(p.camera_locked, "a map change forgets the lock")
	assert_false(p.camera_panning(), "no pan carried over")
	_near(p.camera.position, Vector2(0, -p.tile_size / 2.0), "the new map centres the camera")


func test_a_locked_screen_rides_through_a_save_and_load() -> void:
	var p: RPGPlayer = env.game.player
	assert_true((await _scroll({"direction": "lock"})).is_ok())
	assert_true((await _scroll({"direction": "right", "distance": 2, "wait": true})).is_ok())
	await _move_to(Vector2i(12, 9))
	var world := p.position + p.camera.position
	assert_true(env.rpg.saves.save(SLOT).is_ok(), "save")
	# Wander off to another map, then load back into the locked screen.
	var r: RPGResult = await env.game.transfer("house_inside", Vector2i(5, 5), "down", "none")
	assert_true(r.is_ok(), str(r))
	var lr: RPGResult = await env.rpg.saves.load_slot(SLOT)
	assert_true(lr.is_ok(), str(lr))
	var q: RPGPlayer = env.game.player
	assert_true(q.camera_locked, "the lock is back")
	assert_false(q.camera_panning(), "the finished pan does not restart")
	_near(q.position + q.camera.position, world, "the screen is back where it was locked, pan and all")
	# And it follows the player again once unlocked.
	assert_true((await _scroll({"direction": "unlock"})).is_ok())
	await _move_to(Vector2i(10, 9))
	_near(q.position + q.camera.position, world + Vector2(-2 * q.tile_size, 0), "following again after the load")
