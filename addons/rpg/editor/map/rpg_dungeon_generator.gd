@tool
extends RefCounted
## RPG Maker's "Generate Dungeon": rooms joined by corridors, filling a whole map.
## generate() is pure (same seed, same layout) so it can be tested; apply() paints a map node.

## Returns {floor: Array[Array[bool]] (y, x), rooms: Array[Rect2i]}.
static func generate(size: Vector2i, seed_value: int, options: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var room_min := int(options.get("room_min", 4))
	var room_max := int(options.get("room_max", 8))
	var corridor := clampi(int(options.get("corridor_width", 1)), 1, 3)
	var style := str(options.get("style", "rooms"))   # "rooms" or "passages"
	var grid := []
	for y in size.y:
		var row := []
		row.resize(size.x)
		row.fill(false)
		grid.append(row)
	var rooms: Array[Rect2i] = []
	var target := maxi(2, int(size.x * size.y / float(maxi(room_max * room_max * 3, 1))))
	if style == "passages":
		room_min = 1
		room_max = 2
		target = maxi(4, target * 2)
	var tries := 0
	while rooms.size() < target and tries < target * 40:
		tries += 1
		var w := rng.randi_range(room_min, room_max)
		var h := rng.randi_range(room_min, room_max)
		if w > size.x - 2 or h > size.y - 2:
			continue
		var r := Rect2i(rng.randi_range(1, size.x - w - 1), rng.randi_range(1, size.y - h - 1), w, h)
		var ok := true
		for o in rooms:
			if o.grow(1).intersects(r):
				ok = false
				break
		if ok:
			rooms.append(r)
	# Join each room to the nearest earlier one, so everything is connected.
	for i in rooms.size():
		_carve(grid, rooms[i])
		if i == 0:
			continue
		var best := 0
		var bd := INF
		var ci := rooms[i].get_center()
		for j in i:
			var d := ci.distance_to(rooms[j].get_center())
			if d < bd:
				bd = d
				best = j
		_corridor(grid, ci, rooms[best].get_center(), corridor, rng.randi() % 2 == 0, size)
	return {"floor": grid, "rooms": rooms}


static func _carve(grid: Array, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			grid[y][x] = true


static func _corridor(grid: Array, a: Vector2i, b: Vector2i, width: int, horizontal_first: bool, size: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if horizontal_first else Vector2i(a.x, b.y)
	for seg in [[a, corner], [corner, b]]:
		var p: Vector2i = seg[0]
		var q: Vector2i = seg[1]
		var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
		while true:
			for k in width:
				var c := p + (Vector2i(0, k) if step.y == 0 else Vector2i(k, 0))
				if c.x >= 1 and c.y >= 1 and c.x < size.x - 1 and c.y < size.y - 1:
					grid[c.y][c.x] = true
			if p == q:
				break
			p += step


## Paints the layout onto a map: floor tiles where `floor` is true, wall tiles elsewhere, and
## clears the upper layers and shadows. `floor_key`/`wall_key` are tile keys of the tileset.
static func apply(map_node: Node, layout: Dictionary, floor_key: String, wall_key: String) -> void:
	var layers: Array = map_node.tile_layers
	if layers.is_empty():
		return
	var l0: TileMapLayer = layers[0]
	var fa: Dictionary = RPGTilesetBuilder.atlas_for_key(floor_key, l0.tile_set)
	var wa: Dictionary = RPGTilesetBuilder.atlas_for_key(wall_key, l0.tile_set)
	if fa.is_empty() or wa.is_empty():
		return
	var floors := []
	var walls := []
	var grid: Array = layout.floor
	for y in grid.size():
		for x in grid[y].size():
			(floors if grid[y][x] else walls).append(Vector2i(x, y))
	for i in range(1, layers.size()):
		(layers[i] as TileMapLayer).clear()
	if map_node.get("shadows") != null:
		(map_node.shadows as TileMapLayer).clear()
	l0.clear()
	for pair in [[floors, fa], [walls, wa]]:
		var cells: Array = pair[0]
		var a: Dictionary = pair[1]
		if cells.is_empty():
			continue
		if RPGAutotile.tile_group(l0.tile_set, a.source, a.coords) >= 0:
			RPGAutotile.paint_cells(l0, cells, a.source, a.coords)
		else:
			for c in cells:
				l0.set_cell(c, a.source, a.coords)


## Tile keys a dungeon can use, as [key, label]: autotiles first, then plain lower tiles.
static func tile_choices(tile_set: TileSet) -> Array:
	var out := []
	if tile_set == null:
		return out
	var seen := {}
	for s in tile_set.get_source_count():
		var src := tile_set.get_source(tile_set.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coords := src.get_tile_id(t)
			var td := src.get_tile_data(coords, 0)
			if td == null or not td.has_custom_data("tile_key"):
				continue
			var key := str(td.get_custom_data("tile_key"))
			# Autotile keys repeat per variant ("terrain_3" for each of its 47 shapes).
			if key == "" or seen.has(key) or key.begins_with("upper_") or key.begins_with("anim_"):
				continue
			seen[key] = true
			var passage := int(td.get_custom_data("passage")) if td.has_custom_data("passage") else 15
			var walk := "walkable" if passage != 0 else "blocks"
			# [key, label, passable, icon]: the label says whether the player can walk on it, and
			# the icon shows the tile, so a wall can be told from a floor without guessing.
			out.append([key, "%s (%s)" % [_label(key), walk], passage != 0, _icon(src, coords)])
	out.sort_custom(func(a, b): return _order(str(a[0])) < _order(str(b[0])))
	return out


## Index of a sensible default floor (walkable) and wall (blocks) in tile_choices(): [floor, wall].
static func default_pair(choices: Array) -> Array:
	var floor_i := -1
	var wall_i := -1
	for i in choices.size():
		var walkable: bool = choices[i][2] if choices[i].size() > 2 else true
		if walkable and floor_i < 0:
			floor_i = i
		elif not walkable and wall_i < 0:
			wall_i = i
	if floor_i < 0:
		floor_i = 0
	if wall_i < 0:
		wall_i = mini(1, choices.size() - 1)
	return [floor_i, wall_i]


static func _label(key: String) -> String:
	var m := RegEx.create_from_string("^([a-z]+)_([0-9]+)$").search(key)
	if m == null:
		return key.replace("_", " ").capitalize()
	var kind := {"terrain": "Autotile", "lower": "Lower tile", "upper": "Upper tile", "water": "Water"}.get(m.get_string(1), m.get_string(1).capitalize())
	return "%s %d" % [kind, int(m.get_string(2))]


static func _icon(src: TileSetAtlasSource, coords: Vector2i) -> Texture2D:
	if src.texture == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = src.get_tile_texture_region(coords)
	return at


## Autotiles first, then by kind and number (2 before 10).
static func _order(key: String) -> String:
	var auto := key.begins_with("terrain") or key.begins_with("water") or key.begins_with("a")
	var m := RegEx.create_from_string("^(.*?)([0-9]+)$").search(key)
	var natural := key if m == null else "%s%06d" % [m.get_string(1), int(m.get_string(2))]
	return ("0" if auto else "1") + natural
