@tool
extends RefCounted
## Vehicles, as in RPG Maker: a boat (shallow water), a ship (any water) and an airship (flies
## anywhere, lands on walkable ground). Settings live in the System record under "vehicles":
##   {boat: {name, graphic: {sheet, index}, start: {map, position}, bgm, speed}, ship: ..., airship: ...}
## Where each vehicle is now (and which one the player rides) is game state, saved with the game.
##
## Water comes from the tile keys of the bottom layer: water_a / water_b (2000/2003 shallow
## water) and the VX/MV A1 sheet are "shallow"; water_c and a1_1 (deep sea) are "deep".
## An upper-layer tile that blocks walking (a rock, a pier) also blocks boats and ships;
## star tiles (bridges drawn above) don't.

const KINDS := ["boat", "ship", "airship"]
const SHALLOW := 1
const DEEP := 2
const DEFAULTS := {
	"boat": {"name": "Boat", "graphic": {"sheet": "vehicles", "index": 0}, "speed": 4},
	"ship": {"name": "Ship", "graphic": {"sheet": "vehicles", "index": 1}, "speed": 4},
	"airship": {"name": "Airship", "graphic": {"sheet": "vehicles", "index": 2}, "speed": 5},
}


## Settings for one vehicle: the System record's values over the defaults.
static func config(data: RPGProjectData, kind: String) -> Dictionary:
	var out: Dictionary = DEFAULTS.get(kind, {}).duplicate(true)
	var sys: Dictionary = data.system if data != null else {}
	var v: Variant = sys.get("vehicles", {})
	if v is Dictionary and v.get(kind) is Dictionary:
		for k in v[kind]:
			if v[kind][k] != null:
				out[k] = v[kind][k]
	return out


## The vehicle's settings plus what Change Vehicle Graphic stored in the game state.
static func look(rpg: Node, kind: String) -> Dictionary:
	var cfg := config(rpg.data, kind)
	var v: Variant = rpg.state.vehicles.get(kind)
	if v is Dictionary:
		for k in ["graphic", "bgm"]:
			if v.has(k):
				cfg[k] = v[k]
	return cfg


## Records where a vehicle is (keeping any graphic or music override).
static func park(state: Object, kind: String, map_id: String, cell: Vector2i, facing: String) -> void:
	var v: Dictionary = state.vehicles.get(kind, {})
	v["map"] = map_id
	v["position"] = [cell.x, cell.y]
	v["facing"] = facing
	state.vehicles[kind] = v


## Where every vehicle starts a new game: {kind: {map, position, facing}} (map "" = nowhere yet).
static func initial_state(data: RPGProjectData) -> Dictionary:
	var out := {}
	for kind in KINDS:
		var start: Variant = config(data, kind).get("start")
		var m := ""
		var pos := [0, 0]
		if start is Dictionary and str(start.get("map", "")) != "" and start.get("position") is Array:
			m = str(start.map)
			pos = [int(start.position[0]), int(start.position[1])]
		out[kind] = {"map": m, "position": pos, "facing": "left"}
	return out


static func water_kind(movement: RPGMovement, cell: Vector2i) -> int:
	var layers: Array = movement.map.tile_layers
	if layers.is_empty():
		return 0
	var td: TileData = (layers[0] as TileMapLayer).get_cell_tile_data(cell)
	if td == null or not td.has_custom_data("tile_key"):
		return 0
	var key := str(td.get_custom_data("tile_key"))
	if key.begins_with("water_c") or key == "a1_1":
		return DEEP
	if key.begins_with("water_") or key.begins_with("a1_"):
		return SHALLOW
	return 0


## An upper-layer tile on the cell that blocks walking (not a star tile).
static func blocked_above(movement: RPGMovement, cell: Vector2i) -> bool:
	var layers: Array = movement.map.tile_layers
	for i in range(1, layers.size()):
		var td: TileData = (layers[i] as TileMapLayer).get_cell_tile_data(cell)
		if td == null:
			continue
		var flags := int(td.get_custom_data("flags")) if td.has_custom_data("flags") else 0
		if flags & RPGMovement.FLAG_STAR:
			continue
		var passage := int(td.get_custom_data("passage")) if td.has_custom_data("passage") else 15
		if passage == 0:
			return true
	return false


## Whether a vehicle of `kind` can be on `cell`.
static func can_enter(movement: RPGMovement, kind: String, cell: Vector2i, rider: Node = null) -> bool:
	var c := movement.normalize(cell)
	if c == Vector2i(-1, -1):
		return false
	if kind == "airship":
		return true
	var w := water_kind(movement, c)
	if w == 0 or (kind == "boat" and w != SHALLOW):
		return false
	if blocked_above(movement, c):
		return false
	return not movement.is_occupied(c, rider)


## Whether the player can stand on `cell` after leaving a vehicle (or where an airship lands).
static func can_land(movement: RPGMovement, cell: Vector2i, rider: Node = null) -> bool:
	var c := movement.normalize(cell)
	if c == Vector2i(-1, -1):
		return false
	if water_kind(movement, c) != 0 or movement.passage(c) == 0:
		return false
	return not movement.is_occupied(c, rider)


## Vehicle movement check (same contract as RPGMovement.check_move: "" when allowed).
static func check_move(movement: RPGMovement, kind: String, rider: Node, from: Vector2i, dir: Vector2i) -> String:
	if dir.x != 0 and dir.y != 0:
		return "vehicles move in four directions"
	var to := movement.normalize(from + dir)
	if to == Vector2i(-1, -1):
		return "edge of map"
	if not can_enter(movement, kind, to, rider):
		return "the %s can't go there" % kind
	return ""
