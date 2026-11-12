@tool
class_name RPGMap
extends Node2D
## Root script of every map scene (rpg/maps/<id>.tscn). The scene owns painted tiles
## (TileMapLayer nodes Layer1..Layer4, Regions, Shadows) and any extra Godot nodes. Events are
## NOT stored here: at runtime they are created from <id>.events.json.
## Layer1Base (optional, drawn just below Layer1) holds the hidden base tiles of VX Ace / MV
## overlay autotiles (the sea under deep sea, the ground under a bush; see RPGAutotile). It is
## not in tile_layers: passability, terrain and events read the visible layers only.
## Image-backed maps (RPGImageMap) also have a hidden Navigation layer that decides passability,
## and draw their base and foreground images as unsaved Sprite2D children (setup_images).

@export var map_id := ""

const RPGVehicles := preload("res://addons/rpg/runtime/rpg_vehicles.gd")

var rpg: Node
var props: Dictionary = {}
var size := Vector2i(20, 15)
var tile_size := 16
## Asset profile of the project (CharSet layout); set from rpg/profile.json.
var profile_id := "rm2k"
var scroll_type := "none"
var tile_layers: Array = []
## Hidden base layer under Layer1 (null until something needs it; ensure_base_layer).
var base_layer: TileMapLayer
var regions: TileMapLayer
var shadows: TileMapLayer
## Image-backed maps: the hidden passability layer (null on tile maps).
var navigation: TileMapLayer
## Image-backed maps: the base image (under the tiles) and the foreground (above characters).
var image_base: Sprite2D
var image_foreground: Sprite2D
var events_root: Node2D
var events: Dictionary = {}
var event_order: Array[String] = []
var player: RPGPlayer
var movement: RPGMovement
var started := false
var parallax: Sprite2D
## The ParallaxBackground built from props.parallax (rebuilt by set_parallax).
var parallax_layer: ParallaxBackground
## Tileset chosen by "Change Tileset" (overrides the map properties' tileset; "" = none).
var tileset_override := ""
var _charset_cache: Dictionary = {}


func _ready() -> void:
	_collect_layers()
	if Engine.is_editor_hint() and map_id != "" and _needs_tilesets():
		# Opened directly in Godot's 2D editor: show the tiles using the cached TileSets.
		assign_tilesets(RPGProjectData.open())


func _needs_tilesets() -> bool:
	for l in tile_layers:
		if l.tile_set == null:
			return true
	return false


## Map scenes store painted cells only; TileSets are generated caches assigned on load, so they
## can always be deleted and rebuilt.
func assign_tilesets(data: RPGProjectData) -> Array:
	_collect_layers()
	var warnings := []
	var p: Dictionary = data.map_props(map_id)
	var ts_id: String = tileset_override if tileset_override != "" else str(p.get("tileset", ""))
	var ts_size: int = data.tile_size()
	profile_id = str(data.profile.get("profile", "rm2k"))
	if ts_id != "":
		var ts: TileSet = RPGMap.tileset_for(data, ts_id)
		if ts == null:
			warnings.append("Tileset '%s' could not be built." % ts_id)
		else:
			# The TileSet's own tile size (from its profile) wins over the project setting.
			ts_size = ts.tile_size.x
			for l in tile_layers:
				l.tile_set = ts
			if base_layer != null:
				base_layer.tile_set = ts
	if regions != null and regions.tile_set == null:
		regions.tile_set = RPGTilesetBuilder.region_tileset(ts_size)
	if shadows != null and shadows.tile_set == null:
		shadows.tile_set = RPGTilesetBuilder.shadow_tileset(ts_size)
	if navigation != null and navigation.tile_set == null:
		navigation.tile_set = RPGImageMap.navigation_tileset(ts_size)
	warnings.append_array(setup_images(data, p, ts_size))
	return warnings


## Image-backed maps: (re)creates the base and foreground sprites from the map properties `p`.
## They are not saved with the scene (no owner). One image pixel is one project-tile-size pixel;
## when the map's tileset is drawn smaller (16 px art in a 48 px project) the images are scaled
## down by the same factor, so the camera's zoom brings them back to 1:1 on screen.
## `fresh` reloads the files (they changed on disk).
func setup_images(data: RPGProjectData, p: Dictionary, cell_px: int, fresh := false) -> Array:
	var warnings := []
	for n in [image_base, image_foreground]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.free()
	image_base = null
	image_foreground = null
	if not RPGImageMap.is_image_map(p):
		return warnings
	var image_px: int = data.tile_size() if data != null else cell_px
	var k := float(cell_px) / float(maxi(1, image_px))
	var base := RPGImageMap.base_path(p)
	var tex := RPGImageMap.load_texture(base, fresh)
	if tex == null:
		warnings.append("Base image '%s' could not be loaded." % base)
	else:
		image_base = _image_sprite(RPGImageMap.BASE_NODE, tex, k, RPGImageMap.BASE_Z)
		move_child(image_base, 0)
	var fg := RPGImageMap.foreground_path(p)
	if fg != "":
		var ftex := RPGImageMap.load_texture(fg, fresh)
		if ftex == null:
			warnings.append("Foreground image '%s' could not be loaded." % fg)
		else:
			image_foreground = _image_sprite(RPGImageMap.FOREGROUND_NODE, ftex, k, RPGImageMap.FOREGROUND_Z)
			# Before the events: a flying airship (same z) is drawn after it, so on top.
			if events_root != null and events_root.get_parent() == self:
				move_child(image_foreground, events_root.get_index())
	return warnings


func _image_sprite(n: String, tex: Texture2D, k: float, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = n
	s.texture = tex
	s.centered = false
	s.position = Vector2.ZERO
	s.scale = Vector2(k, k)
	# Pixel art: never smoothed, whatever the project's default filter is.
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	s.z_index = z
	s.z_as_relative = false
	add_child(s)
	return s


func is_image_map() -> bool:
	return navigation != null or RPGImageMap.is_image_map(props)


static var _tileset_cache: Dictionary = {}


## Shared TileSet for a tileset record (cached per session; rebuilt when overrides change).
static func tileset_for(data: RPGProjectData, ts_id: String) -> TileSet:
	var rec: Dictionary = data.record("tilesets", ts_id)
	if rec.is_empty():
		return null
	var ov_path: String = data.root.path_join("tileset_overrides/%s.json" % ts_id)
	var overrides: Dictionary = RPGJson.load_or(ov_path, {})
	var key: String = ts_id + ":" + RPGJson.stringify(overrides).md5_text() + ":" + str(rec.get("sheet", ""))
	if _tileset_cache.has(key):
		return _tileset_cache[key]
	var report: Dictionary = RPGTilesetBuilder.cached_or_build(rec, overrides)
	var ts: TileSet = report.get("tileset")
	if ts != null:
		_tileset_cache[key] = ts
	return ts


static func clear_tileset_cache() -> void:
	_tileset_cache.clear()


func _collect_layers() -> void:
	tile_layers.clear()
	for n in ["Layer1", "Layer2", "Layer3", "Layer4"]:
		var l := get_node_or_null(n)
		if l is TileMapLayer:
			tile_layers.append(l)
	base_layer = get_node_or_null(RPGAutotile.BASE_LAYER) as TileMapLayer
	regions = get_node_or_null("Regions") as TileMapLayer
	shadows = get_node_or_null("Shadows") as TileMapLayer
	navigation = get_node_or_null(RPGImageMap.NAV_LAYER) as TileMapLayer
	if regions != null and not Engine.is_editor_hint():
		regions.visible = false
	if navigation != null:
		navigation.visible = false


## The hidden base layer under Layer1, created (empty, just below Layer1, saved with the scene)
## when missing. Null when the map has no Layer1.
func ensure_base_layer() -> TileMapLayer:
	if base_layer != null and is_instance_valid(base_layer):
		return base_layer
	base_layer = get_node_or_null(RPGAutotile.BASE_LAYER) as TileMapLayer
	if base_layer != null:
		return base_layer
	var top := get_node_or_null(RPGAutotile.TOP_LAYER) as TileMapLayer
	if top == null:
		return null
	var b := TileMapLayer.new()
	b.name = RPGAutotile.BASE_LAYER
	b.z_index = top.z_index
	b.z_as_relative = top.z_as_relative
	add_child(b)
	move_child(b, top.get_index())
	b.owner = self
	b.tile_set = top.tile_set
	b.modulate = top.modulate
	if top.has_meta(RPGAutotile.MAP_SIZE_META):
		b.set_meta(RPGAutotile.MAP_SIZE_META, top.get_meta(RPGAutotile.MAP_SIZE_META))
	base_layer = b
	return b


## Starts the map at runtime: reads properties and events and creates one node per event.
func start(p_rpg: Node) -> void:
	if started:
		return
	rpg = p_rpg
	# Event-command overrides saved per map (Change Tileset / Parallax / Battle Background).
	var ov: Dictionary = rpg.state.map_override(map_id) if rpg.state != null and rpg.state.has_method("map_override") else {}
	tileset_override = str(ov.get("tileset", ""))
	for w in assign_tilesets(rpg.data):
		push_warning("RPG map '%s': %s" % [map_id, w])
	props = rpg.data.map_props(map_id)
	if not ov.is_empty():
		props = props.duplicate(true)
		for k in ["parallax", "battle_background"]:
			if ov.has(k):
				props[k] = ov[k]
	tile_size = rpg.data.tile_size()
	if not tile_layers.is_empty() and tile_layers[0].tile_set != null:
		tile_size = (tile_layers[0].tile_set as TileSet).tile_size.x
	size = Vector2i(int(props.get("width", 20)), int(props.get("height", 15)))
	scroll_type = str(props.get("scroll", "none"))
	movement = RPGMovement.new(self)
	_setup_parallax()
	events_root = Node2D.new()
	events_root.name = "Events"
	events_root.y_sort_enabled = true
	events_root.z_index = 0
	events_root.z_as_relative = false
	add_child(events_root)
	events.clear()
	event_order.clear()
	for ev_data in rpg.data.map_events(map_id):
		var ev := RPGEvent.new()
		ev.setup(self, ev_data)
		events_root.add_child(ev)
		events[ev.event_id] = ev
		event_order.append(ev.event_id)
	event_order.sort()
	refresh_vehicles()
	started = true
	refresh_pages()


## How many times the map is magnified on screen: the project's tile size over the tileset's
## (1 when they match; 3 for 16 px art in a 48 px MV-style project).
func display_scale() -> int:
	if rpg == null or rpg.data == null or tile_size <= 0:
		return 1
	return maxi(1, int(rpg.data.tile_size()) / tile_size)


## "Change Tileset": swaps the TileSet of every tile layer (cells keep their tile coordinates).
func change_tileset(ts_id: String) -> bool:
	if rpg == null:
		return false
	var ts: TileSet = RPGMap.tileset_for(rpg.data, ts_id)
	if ts == null:
		return false
	tileset_override = ts_id
	for l in tile_layers:
		l.tile_set = ts
	if base_layer != null:
		base_layer.tile_set = ts
	if movement != null:
		movement.invalidate()
	return true


## "Change Parallax Background": p = {image, scroll_x, scroll_y, loop} or null (none).
func set_parallax(p: Variant) -> void:
	props = props.duplicate(true)
	props["parallax"] = p
	if parallax_layer != null and is_instance_valid(parallax_layer):
		parallax_layer.queue_free()
	parallax_layer = null
	_setup_parallax()


func _setup_parallax() -> void:
	var p: Variant = props.get("parallax")
	if not (p is Dictionary) or str(p.get("image", "")) == "":
		return
	var tex: Texture2D = rpg.ui.load_texture("panorama", p.image)
	if tex == null:
		return
	var layer := ParallaxBackground.new()
	var pl := ParallaxLayer.new()
	pl.motion_scale = Vector2(float(p.get("scroll_x", 0.5)), float(p.get("scroll_y", 0.5)))
	pl.motion_mirroring = tex.get_size() if p.get("loop", true) else Vector2.ZERO
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	pl.add_child(s)
	layer.add_child(pl)
	layer.layer = -10
	add_child(layer)
	parallax_layer = layer


func add_player(p: RPGPlayer, at: Vector2i, facing: String) -> void:
	player = p
	if p.get_parent() != null:
		p.get_parent().remove_child(p)
	events_root.add_child(p)
	p.setup_on_map(self, at)
	p.force_turn(facing)
	p.setup_camera()
	p.reset_encounter()
	# Followers start on the leader's cell: add them back to front and the leader last, so on a
	# shared cell the leader draws on top and each follower above the ones behind it.
	for i in range(p.followers.size() - 1, -1, -1):
		var f: RPGCharacter = p.followers[i]
		if f.get_parent() != null:
			f.get_parent().remove_child(f)
		events_root.add_child(f)
		f.setup_on_map(self, at)
		f.force_turn(facing)
	events_root.move_child(p, events_root.get_child_count() - 1)
	p.trail.clear()


func remove_player() -> void:
	if player != null and player.get_parent() == events_root:
		events_root.remove_child(player)
		for f in player.followers:
			if f.get_parent() == events_root:
				events_root.remove_child(f)


## Re-checks every event's page (highest eligible page wins).
func refresh_pages() -> void:
	for id in event_order:
		var ev: RPGEvent = events.get(id)
		if ev != null:
			ev.refresh()


func autorun_candidates() -> Array:
	var out := []
	for id in event_order:
		var ev: RPGEvent = events.get(id)
		if ev != null and ev.autorun_ready() and ev.best_page() == ev.page_index:
			out.append(ev)
	return out


func get_event(id: String) -> Node:
	return events.get(id)


func events_at(c: Vector2i) -> Array:
	var out := []
	for id in event_order:
		var ev: RPGEvent = events.get(id)
		if ev != null and ev.page_index >= 0 and not ev.erased and ev.cell == c:
			out.append(ev)
	return out


## Vehicles parked on this map (the one being ridden is drawn as the player instead).
var vehicle_nodes: Dictionary = {}


func refresh_vehicles() -> void:
	for k in vehicle_nodes:
		var n: Node = vehicle_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
	vehicle_nodes.clear()
	if rpg == null:
		return
	for kind in RPGVehicles.KINDS:
		var v: Variant = rpg.state.vehicles.get(kind)
		if not (v is Dictionary) or str(v.get("map", "")) != map_id or rpg.state.riding == kind:
			continue
		var cfg := RPGVehicles.look(rpg, kind)
		var ch := RPGCharacter.new()
		ch.name = "Vehicle_" + kind
		# Boats and ships block like characters; a landed airship is walked onto.
		ch.priority = "below" if kind == "airship" else "same"
		ch.step_anim = true
		ch.set_meta("rpg_vehicle", kind)
		events_root.add_child(ch)
		var pos: Array = v.get("position", [0, 0])
		ch.setup_on_map(self, Vector2i(int(pos[0]), int(pos[1])))
		ch.set_graphic(cfg.get("graphic"))
		ch.force_turn(str(v.get("facing", "left")))
		vehicle_nodes[kind] = ch


## The parked vehicle on `c` (or "").
func vehicle_at(c: Vector2i) -> String:
	for k in vehicle_nodes:
		var n: Node = vehicle_nodes[k]
		if is_instance_valid(n) and n.cell == c:
			return k
	return ""


func characters() -> Array:
	var out: Array = []
	for k in vehicle_nodes:
		if is_instance_valid(vehicle_nodes[k]):
			out.append(vehicle_nodes[k])
	if player != null:
		out.append(player)
		for f in player.followers:
			if f.visible:
				out.append(f)
	for id in event_order:
		var ev: Node = events.get(id)
		if ev != null:
			out.append(ev)
	return out


func region_at(c: Vector2i) -> int:
	if regions == null:
		return 0
	var src := regions.get_cell_source_id(c)
	if src < 0:
		return 0
	var ac := regions.get_cell_atlas_coords(c)
	return ac.x + ac.y * 16


func terrain_at(c: Vector2i) -> int:
	return movement.terrain(c) if movement else 0


func load_charset(sheet: String) -> Texture2D:
	if _charset_cache.has(sheet):
		return _charset_cache[sheet]
	var tex: Texture2D = RPGCharset.prepared_texture(RPGAssets.load_texture("charset", sheet))
	_charset_cache[sheet] = tex
	return tex


## Texture of one tile, for events whose graphic is a tile. key: tile_key or [source, x, y].
func tile_texture(key: Variant) -> Texture2D:
	for layer in tile_layers:
		var ts: TileSet = layer.tile_set
		if ts == null:
			continue
		for si in ts.get_source_count():
			var sid := ts.get_source_id(si)
			var src := ts.get_source(sid) as TileSetAtlasSource
			if src == null:
				continue
			if key is Array and key.size() == 3 and int(key[0]) != sid:
				continue
			for ti in src.get_tiles_count():
				var coords := src.get_tile_id(ti)
				var match_ := false
				if key is Array and key.size() == 3:
					match_ = coords == Vector2i(int(key[1]), int(key[2]))
				else:
					var td := src.get_tile_data(coords, 0)
					match_ = _tile_key(ts, td) == str(key)
				if match_:
					var at := AtlasTexture.new()
					at.atlas = src.texture
					at.region = src.get_tile_texture_region(coords)
					return at
	return null


static func _tile_key(ts: TileSet, td: TileData) -> String:
	for i in ts.get_custom_data_layers_count():
		if ts.get_custom_data_layer_name(i) == "tile_key":
			return str(td.get_custom_data_by_layer_id(i))
	return ""


## Cancels every task this map owns and waits for cleanup (called before unloading).
func shutdown(caller: RPGInterpreter = null) -> void:
	if rpg == null:
		return
	var id := map_id
	var mine := func(owner: Dictionary): return owner.get("kind", "") == "map_event" and owner.get("map", "") == id
	await rpg.scheduler.cancel_owned(mine, "map unloaded", caller)
	stop_routes()
	remove_player()


## Cancels the events' own move routes (autonomous custom routes, Move Routes that do not wait).
## The player's route is left alone: the player moves on to the next map.
func stop_routes(why := "map unloaded") -> void:
	for id in events:
		var ev: Variant = events[id]
		if ev != null and is_instance_valid(ev) and ev.has_method("cancel_route"):
			ev.cancel_route(why)


## Restarts this map's parallel events after a failed transfer away from it.
func resume() -> void:
	for id in event_order:
		var ev: RPGEvent = events.get(id)
		if ev != null and ev.trigger == "parallel":
			ev._start_parallel()
	refresh_pages()
