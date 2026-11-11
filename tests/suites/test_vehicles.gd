extends "res://tests/rpg_test_case.gd"
## Vehicles on the sample town (it has a pond): boarding a boat from the shore, sailing only on
## water, getting off onto land, the airship flying over water and landing only on ground,
## Set Vehicle Location, and riding through a save and load.

const Env := preload("res://tests/rpg_test_env.gd")
const V := preload("res://addons/rpg/runtime/rpg_vehicles.gd")

var env


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	await env.settle()


func after_each() -> void:
	await env.destroy()


## A water cell next to a free land cell, and the direction from land to water.
func _shore() -> Dictionary:
	var mv: RPGMovement = env.game.map.movement
	var s: Vector2i = env.game.map.size
	for y in s.y:
		for x in s.x:
			var w := Vector2i(x, y)
			if V.water_kind(mv, w) != V.SHALLOW:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var land: Vector2i = w - d
				if mv.in_bounds(land) and V.can_land(mv, land) and env.game.map.events_at(land).is_empty():
					var deeper: Vector2i = w + d
					if mv.in_bounds(deeper) and V.water_kind(mv, deeper) == V.SHALLOW:
						return {"water": w, "land": land, "dir": d}
	return {}


func _face(d: Vector2i) -> void:
	env.game.player.force_turn({Vector2i.LEFT: "left", Vector2i.RIGHT: "right", Vector2i.UP: "up", Vector2i.DOWN: "down"}[d])


func _walk(d: Vector2i) -> bool:
	var p: RPGPlayer = env.game.player
	var ok := p.step(d)
	await env.walk_done(p)
	return ok


func test_boat_boards_sails_and_lands() -> void:
	var sh := _shore()
	assert_false(sh.is_empty(), "the sample town has shallow water next to land")
	if sh.is_empty():
		return
	var run: RPGResult = await env.rpg.run_commands([{"type": "set_vehicle_location", "vehicle": "boat", "to": {"map": "town", "position": [sh.water.x, sh.water.y]}}], {"kind": "api", "id": "t"})
	assert_true(run.is_ok(), str(run))
	assert_true(env.game.map.vehicle_nodes.has("boat"), "the boat is drawn on the map")
	var p: RPGPlayer = env.game.player
	p.place(sh.land)
	assert_false(await _walk(sh.dir), "the boat blocks walking into it")
	_face(sh.dir)
	assert_true(p.check_action(), "action button boards the boat")
	assert_eq(p.vehicle, "boat")
	assert_eq(env.rpg.state.riding, "boat")
	assert_eq(p.cell, sh.water)
	assert_false(env.game.map.vehicle_nodes.has("boat"), "the parked sprite is gone while riding")
	assert_true(await _walk(sh.dir), "sails on water")
	assert_eq(p.cell, sh.water + sh.dir)
	# Back towards the shore: the boat can't go on land, but the player can get off there.
	assert_true(await _walk(-sh.dir))
	assert_false(await _walk(-sh.dir), "the boat can't go onto land")
	_face(-sh.dir)
	assert_true(p.check_action(), "action button gets off onto land")
	assert_eq(p.vehicle, "")
	assert_eq(p.cell, sh.land)
	assert_eq(env.rpg.state.vehicles.boat.position, [sh.water.x, sh.water.y], "the boat stays where it was left")
	assert_true(env.game.map.vehicle_nodes.has("boat"))


func test_airship_flies_over_water_and_lands_on_ground() -> void:
	var sh := _shore()
	if sh.is_empty():
		fail("no shore on the sample town")
		return
	var p: RPGPlayer = env.game.player
	await env.rpg.run_commands([{"type": "set_vehicle_location", "vehicle": "airship", "to": {"map": "town", "position": [sh.land.x, sh.land.y]}}], {"kind": "api", "id": "t"})
	p.place(sh.land)
	assert_true(p.check_action(), "standing on the airship and pressing OK boards it")
	assert_eq(p.vehicle, "airship")
	assert_true(await _walk(sh.dir), "flies over the water")
	assert_false(p.check_action(), "can't land on water")
	assert_eq(p.vehicle, "airship")
	assert_true(await _walk(-sh.dir))
	assert_true(p.check_action(), "lands on ground")
	assert_eq(p.vehicle, "")
	assert_eq(p.cell, sh.land)
	assert_true(env.game.map.vehicle_nodes.has("airship"))


func test_riding_survives_save_and_load() -> void:
	var sh := _shore()
	if sh.is_empty():
		fail("no shore on the sample town")
		return
	var p: RPGPlayer = env.game.player
	await env.rpg.run_commands([{"type": "set_vehicle_location", "vehicle": "boat", "to": {"map": "town", "position": [sh.water.x, sh.water.y]}}], {"kind": "api", "id": "t"})
	p.place(sh.land)
	_face(sh.dir)
	assert_true(p.check_action())
	var save: Dictionary = env.rpg.saves.build_save()
	assert_eq(save.state.riding, "boat")
	# Get off, then load: back on the boat at sea.
	_face(-sh.dir)
	p.check_action()
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	assert_eq(env.game.player.vehicle, "boat", "riding again after load")
	assert_eq(env.game.player.cell, sh.water)


func test_vehicle_condition_and_commands_validate() -> void:
	assert_true(env.rpg.state.check_condition({"kind": "vehicle", "id": "none"}))
	assert_false(env.rpg.state.check_condition({"kind": "vehicle", "id": "boat"}))
	var bad: RPGResult = await env.rpg.run_commands([{"type": "set_vehicle_location", "vehicle": "ship", "to": {"map": "nowhere", "position": [0, 0]}}], {"kind": "api", "id": "t"})
	assert_true(bad.is_error(), "unknown map is an error")
	var g: RPGResult = await env.rpg.run_commands([{"type": "change_vehicle_graphic", "vehicle": "ship", "graphic": {"sheet": "vehicles", "index": 0}}], {"kind": "api", "id": "t"})
	assert_true(g.is_ok(), str(g))
	assert_eq(V.look(env.rpg, "ship").graphic.index, 0, "the override is kept in the game state")
