extends "res://tests/rpg_test_case.gd"
## Change Tile (#15): bulk tile-key replacement and the one-cell mode, passability following the
## new tile, the RM-style reset on map reload, the Keep option surviving transfers and a save and
## load, operand coordinates, and the error cases (unknown tile key, missing layer).

const Env := preload("res://tests/rpg_test_env.gd")

var env


func before_each() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	await env.settle()


func after_each() -> void:
	await env.destroy()


func _run(cmds: Array) -> RPGResult:
	return await env.rpg.run_commands(cmds, {"kind": "api", "id": "t"})


func _save_load() -> void:
	var save: Dictionary = env.rpg.saves.build_save()
	env.rpg.state.new_game()
	var lr: RPGResult = await env.rpg.saves.load_data(save)
	assert_true(lr.is_ok(), str(lr))
	await env.settle()


## The tile key a layer's cell holds ("" when empty).
func _key_at(layer: TileMapLayer, cell: Vector2i) -> String:
	var ts: TileSet = layer.tile_set
	var td := layer.get_cell_tile_data(cell)
	return RPGMap._tile_key(ts, td) if td != null else ""


## Every used cell of a layer holding `key`.
func _cells_with(layer: TileMapLayer, key: String) -> Array:
	var out := []
	for cell in layer.get_used_cells():
		if _key_at(layer, cell) == key:
			out.append(cell)
	return out


## A key the layer really paints (the most common one), so bulk tests change real cells.
func _painted_key(layer: TileMapLayer) -> String:
	var counts := {}
	for cell in layer.get_used_cells():
		var k := _key_at(layer, cell)
		if k != "":
			counts[k] = int(counts.get(k, 0)) + 1
	var best := ""
	var n := 0
	for k in counts:
		if int(counts[k]) > n:
			best = str(k)
			n = int(counts[k])
	return best


func test_bulk_replace_swaps_every_matching_cell() -> void:
	var m: RPGMap = env.game.map
	var layer: TileMapLayer = m.tile_layers[0]
	var from := _painted_key(layer)
	assert_true(from != "", "the town paints Layer1 tiles")
	var cells := _cells_with(layer, from)
	assert_true(cells.size() >= 2, "a key the map paints repeatedly: %d cells" % cells.size())
	var r := await _run([{"type": "change_tile", "layer": "Layer1", "mode": "all", "from": from, "to": "lower_0"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_cells_with(layer, from).size(), 0, "no cell keeps the old key")
	for cell in cells:
		assert_eq(_key_at(layer, cell), "lower_0")


func test_single_cell_mode_sets_one_cell() -> void:
	var m: RPGMap = env.game.map
	var layer: TileMapLayer = m.tile_layers[0]
	var cell := Vector2i(14, 12)
	var around := [cell + Vector2i(1, 0), cell + Vector2i(0, 1)]
	var before := {}
	for c in around:
		before[c] = _key_at(layer, c)
	var r := await _run([{"type": "change_tile", "layer": "Layer1", "mode": "cell", "x": cell.x, "y": cell.y, "to": "lower_1"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_key_at(layer, cell), "lower_1")
	for c in around:
		assert_eq(_key_at(layer, c), before[c], "the neighbour %s keeps its tile" % c)


func test_cell_coordinates_can_come_from_variables() -> void:
	env.rpg.state.set_variable("fish_caught", 14)
	var r := await _run([{"type": "change_tile", "layer": "Layer1", "mode": "cell",
		"x": {"variable": "fish_caught"}, "y": 12, "to": "lower_2"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_key_at(env.game.map.tile_layers[0], Vector2i(14, 12)), "lower_2")


func test_passability_follows_the_new_tile() -> void:
	# The sample project's tileset comes from art, so passage values are not pinned; the fixture
	# project with a hand-built tileset is (floor: passable 15, wall: blocked 0).
	await env.destroy()
	env = Env.create(tree)
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8))
	assert_true(r.is_ok(), str(r))
	await env.settle()
	var map: Node = env.game.map
	if map.tile_layers.is_empty():
		var fresh := TileMapLayer.new()
		fresh.name = "Layer1"
		map.add_child(fresh)
		map.tile_layers.append(fresh)
		map.movement.invalidate()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(32, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "passage")
	ts.set_custom_data_layer_type(0, TYPE_INT)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(1, "tile_key")
	ts.set_custom_data_layer_type(1, TYPE_STRING)
	var sid := ts.add_source(src)
	src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("passage", 15)
	src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("tile_key", "t_floor")
	src.get_tile_data(Vector2i(1, 0), 0).set_custom_data("passage", 0)
	src.get_tile_data(Vector2i(1, 0), 0).set_custom_data("tile_key", "t_wall")
	var layer: TileMapLayer = map.tile_layers[0]
	layer.tile_set = ts
	var at := Vector2i(12, 9)
	layer.set_cell(at, sid, Vector2i(0, 0))
	map.movement.invalidate()
	assert_eq(map.movement.passage(at), 15, "the floor tile is open")
	var cr := await _run([{"type": "change_tile", "layer": "Layer1", "mode": "all", "from": "t_floor", "to": "t_wall"}])
	assert_true(cr.is_ok(), str(cr))
	assert_eq(map.movement.passage(at), 0, "the wall tile blocks the cell")


func test_changes_reset_when_the_map_reloads() -> void:
	var layer: TileMapLayer = env.game.map.tile_layers[0]
	var cell := Vector2i(14, 12)
	var original := _key_at(layer, cell)
	var r := await _run([{"type": "change_tile", "layer": "Layer1", "mode": "cell", "x": 14, "y": 12, "to": "lower_3"}])
	assert_true(r.is_ok(), str(r))
	assert_eq(_key_at(env.game.map.tile_layers[0], cell), "lower_3")
	var tr: RPGResult = await env.game.transfer("field", Vector2i(1, 1), "down", "none", 8)
	assert_true(tr.is_ok(), str(tr))
	tr = await env.game.transfer("town", Vector2i(14, 12), "down", "none", 8)
	assert_true(tr.is_ok(), str(tr))
	assert_eq(_key_at(env.game.map.tile_layers[0], cell), original, "the map came back from disk, as in RPG Maker")


func test_keep_survives_a_reload_and_a_save_load() -> void:
	var cell := Vector2i(14, 12)
	var r := await _run([{"type": "change_tile", "layer": "Layer1", "mode": "cell", "x": 14, "y": 12, "to": "lower_4", "keep": true}])
	assert_true(r.is_ok(), str(r))
	var tr: RPGResult = await env.game.transfer("field", Vector2i(1, 1), "down", "none", 8)
	assert_true(tr.is_ok(), str(tr))
	tr = await env.game.transfer("town", Vector2i(14, 12), "down", "none", 8)
	assert_true(tr.is_ok(), str(tr))
	assert_eq(_key_at(env.game.map.tile_layers[0], cell), "lower_4", "kept through a transfer")
	await _save_load()
	assert_eq(env.game.map.map_id, "town")
	assert_eq(_key_at(env.game.map.tile_layers[0], cell), "lower_4", "kept through a save and load")
	# The stored list replaces an operation with the same target instead of growing.
	env.rpg.state.remember_tile_change("town", {"layer": "Layer1", "mode": "cell", "cell": [14, 12], "to": "lower_5"})
	assert_eq(env.rpg.state.tile_changes["town"].size(), 1)
	assert_eq(env.rpg.state.tile_changes["town"][0].to, "lower_5")


func test_errors_on_unknown_tile_key_or_layer() -> void:
	assert_true((await _run([{"type": "change_tile", "layer": "Layer1", "mode": "all", "from": "lower_0", "to": "no_such_key"}])).is_error())
	assert_true((await _run([{"type": "change_tile", "layer": "NoLayer", "mode": "cell", "x": 0, "y": 0, "to": "lower_0"}])).is_error(), "no such layer node")
