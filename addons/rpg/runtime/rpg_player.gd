class_name RPGPlayer
extends RPGCharacter
## The player: four-direction grid movement, dash, action button, touch triggers, encounters.
## Mouse / touch (RPG Maker MV's "touch to move"): clicking a cell walks there along a path,
## clicking an adjacent event (or the player's own cell) talks to it, right click opens the menu.

const RPGVehicles := preload("res://addons/rpg/runtime/rpg_vehicles.gd")

var followers: Array = []
var camera: Camera2D
var encounter_count := 0
var _last_touch_key := ""
var _held: Array[String] = []
var trail: Array[Vector2i] = []
## The vehicle being ridden ("" on foot). Mirrors state.riding.
var vehicle := ""
## Touch to move: the cell the player walks to, or NO_DESTINATION.
var destination := NO_DESTINATION
const NO_DESTINATION := Vector2i(-1, -1)
## Cells looked at per path search (MV gives up and walks to the closest cell it found).
const PATH_SEARCH_LIMIT := 2500
var _marker: Node2D


func _init() -> void:
	super._init()
	name = "Player"
	z_index = 2
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	add_child(camera)


func _ready() -> void:
	camera.make_current()


func setup_camera() -> void:
	var s: Vector2i = map.size
	var px := s * tile_size
	camera.position = Vector2(0, -tile_size / 2.0)
	# A tileset drawn smaller than the project's tile size (the 16 px starter art in a 48 px MV
	# project) is zoomed so tiles fill the screen as they would in that RPG Maker.
	var k: int = map.display_scale() if map.has_method("display_scale") else 1
	camera.zoom = Vector2(k, k)
	# The game screen (320x240 for 2000-style projects, 544x416 for VX/Ace-style ones), in map pixels.
	var vs := Vector2i(Vector2(get_viewport().get_visible_rect().size) / k) if is_inside_tree() else Vector2i(320, 240)
	if not map.movement.loops_h():
		camera.limit_left = 0
		camera.limit_right = maxi(px.x, vs.x)
	if not map.movement.loops_v():
		camera.limit_top = 0
		camera.limit_bottom = maxi(px.y, vs.y)
	if px.x < vs.x:
		camera.limit_left = -(vs.x - px.x) / 2
		camera.limit_right = camera.limit_left + vs.x
	if px.y < vs.y:
		camera.limit_top = -(vs.y - px.y) / 2
		camera.limit_bottom = camera.limit_top + vs.y
	camera.reset_smoothing()


func debug_through() -> bool:
	var rpg: Node = map.rpg
	return rpg.debug_through_enabled and rpg.playtest and Input.is_action_pressed("rpg_through")


func input_allowed() -> bool:
	var rpg: Node = map.rpg
	return not rpg.scheduler.input_locked() and not rpg.ui.scene_open() and not (rpg.ui.message_box and rpg.ui.message_box.is_open()) and rpg.ui.input_settled()


func _process(delta: float) -> void:
	super._process(delta)
	_update_marker()
	if map == null:
		return
	if not input_allowed():
		if not moving:
			clear_destination()
		return
	if moving:
		return
	var rpg: Node = map.rpg
	# "Always dash" (options screen) inverts the dash button.
	dashing = (Input.is_action_pressed("rpg_dash") != bool(rpg.data.system.get("always_dash", false))) and not bool(map.props.get("disable_dash", false))
	if Input.is_action_just_pressed("rpg_ok"):
		clear_destination()
		check_action()
		return
	if Input.is_action_just_pressed("rpg_cancel") or (InputMap.has_action("rpg_menu") and Input.is_action_just_pressed("rpg_menu")):
		clear_destination()
		if rpg.game != null and rpg.game.has_method("open_menu"):
			rpg.game.open_menu()
		return
	if Input.is_action_just_pressed("rpg_debug") and rpg.playtest and rpg.game != null:
		rpg.game.open_debug()
		return
	var dir := _input_dir()
	if dir != Vector2i.ZERO:
		clear_destination()
	elif destination != NO_DESTINATION:
		dir = _destination_step()
	if dir != Vector2i.ZERO:
		var from := cell
		if not step(dir):
			_bump(dir)
			clear_destination()
		else:
			_last_touch_key = ""
			trail.push_front(from)
			if trail.size() > 8:
				trail.pop_back()
			_move_followers()


# --- mouse / touch to move ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if map == null or not (event is InputEventMouseButton) or not event.pressed or not is_inside_tree():
		return
	var rpg: Node = map.rpg
	if rpg == null or (rpg.has_method("pointer_enabled") and not rpg.pointer_enabled()):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if input_allowed():
			get_viewport().set_input_as_handled()
			touch_cell(cell_at(map.make_input_local(event).position))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		# MV: a right click (two-finger tap) on the map opens the menu.
		if input_allowed() and not moving and rpg.game != null and rpg.game.has_method("open_menu"):
			get_viewport().set_input_as_handled()
			clear_destination()
			rpg.game.open_menu()


## The map cell under a point in the map's coordinates (wrapped on looping maps).
func cell_at(p: Vector2) -> Vector2i:
	var c := Vector2i(floori(p.x / tile_size), floori(p.y / tile_size))
	var n: Vector2i = map.movement.normalize(c)
	return n if n != NO_DESTINATION else c


## A click on map cell `c`: the player's own cell, or an event next to it, gets the action button
## (facing it first), as MV's touch triggers do; any other cell is walked to.
func touch_cell(c: Vector2i) -> void:
	if not map.movement.in_bounds(c):
		return
	if c == cell:
		clear_destination()
		if not moving:
			check_action()
		return
	var d := c - cell
	if absi(d.x) + absi(d.y) == 1 and not moving and _has_talk_target(c):
		clear_destination()
		turn(RPGMovement.dir_name(d))
		check_action()
		return
	destination = c


func clear_destination() -> void:
	destination = NO_DESTINATION


## True when something the action button reaches stands on `c`: a same-level event, a vehicle,
## or a counter (with an event behind it).
func _has_talk_target(c: Vector2i) -> bool:
	for ev in map.events_at(c):
		if ev.priority == "same":
			return true
	if vehicle == "" and map.vehicle_at(c) != "":
		return true
	return map.movement.flags(c) & RPGMovement.FLAG_COUNTER != 0


## Next step toward `destination`. At it, or next to it when it cannot be entered, the walk ends
## facing it, and an event standing there gets the action button (tapping a far NPC walks up to
## it and talks, as in MV).
func _destination_step() -> Vector2i:
	if destination == cell:
		clear_destination()
		return Vector2i.ZERO
	var d := destination - cell
	if absi(d.x) + absi(d.y) == 1 and not map.movement.can_move(self, cell, d):
		var target := destination
		clear_destination()
		turn(RPGMovement.dir_name(d))
		_bump(d)
		for ev in map.events_at(target):
			if ev.priority == "same":
				check_action()
				break
		return Vector2i.ZERO
	var dir := find_direction_to(destination)
	if dir == Vector2i.ZERO:
		clear_destination()
	return dir


## First step of a shortest path to `goal` (breadth first over passable cells; characters
## block). When `goal` cannot be reached the path leads to the closest cell found, as in MV;
## ZERO when the player is already as close as it gets.
func find_direction_to(goal: Vector2i) -> Vector2i:
	var mv: RPGMovement = map.movement
	var start := cell
	var blocked := {}
	for other in map.characters():
		if other != self and is_instance_valid(other) and other.blocks():
			blocked[other.cell] = true
	for c in mv.reservations:
		var r: Variant = mv.reservations[c]
		if r != self and is_instance_valid(r) and r.blocks():
			blocked[c] = true
	var free_walk: bool = through or debug_through()
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	var best := start
	var best_d := _grid_dist(start, goal)
	var head := 0
	var dirs: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
	while head < queue.size() and head < PATH_SEARCH_LIMIT:
		var cur: Vector2i = queue[head]
		head += 1
		if cur == goal:
			best = cur
			break
		for dv in dirs:
			var nx: Vector2i = mv.normalize(cur + dv)
			if nx == NO_DESTINATION or came.has(nx):
				continue
			if vehicle != "":
				if not mv.can_move(self, cur, dv):
					continue
			elif not free_walk:
				var dn := RPGMovement.dir_name(dv)
				if (mv.passage(cur) & int(RPGMovement.BIT[dn])) == 0 or (mv.passage(nx) & int(RPGMovement.BIT[RPGMovement.OPPOSITE[dn]])) == 0:
					continue
				if blocked.has(nx):
					continue
			came[nx] = cur
			queue.append(nx)
			var dd := _grid_dist(nx, goal)
			if dd < best_d:
				best_d = dd
				best = nx
	if best == start:
		return Vector2i.ZERO
	var step_cell: Vector2i = best
	while came[step_cell] != start:
		step_cell = came[step_cell]
	var dir := step_cell - start
	# Looping maps: a step across the edge wraps around.
	if absi(dir.x) > 1:
		dir.x = -signi(dir.x)
	if absi(dir.y) > 1:
		dir.y = -signi(dir.y)
	return dir


func _grid_dist(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	if map.movement.loops_h():
		dx = mini(dx, map.size.x - dx)
	if map.movement.loops_v():
		dy = mini(dy, map.size.y - dy)
	return dx + dy


## A softly pulsing square on the touch-to-move destination (MV's Sprite_Destination).
func _update_marker() -> void:
	var show := destination != NO_DESTINATION and map != null and is_inside_tree()
	if not show:
		if _marker != null and is_instance_valid(_marker):
			_marker.visible = false
		return
	if _marker == null or not is_instance_valid(_marker) or _marker.get_parent() != map:
		if _marker != null and is_instance_valid(_marker):
			_marker.queue_free()
		_marker = Node2D.new()
		_marker.name = "TouchDestination"
		_marker.z_index = 1
		_marker.draw.connect(_draw_marker)
		map.add_child(_marker)
	_marker.visible = true
	_marker.position = Vector2(destination * tile_size)
	_marker.queue_redraw()


func _draw_marker() -> void:
	var a := 0.25 + 0.15 * sin(Time.get_ticks_msec() / 160.0)
	_marker.draw_rect(Rect2(Vector2.ZERO, Vector2(tile_size, tile_size)), Color(1, 1, 1, a))


func _exit_tree() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


func _input_dir() -> Vector2i:
	for a in ["rpg_down", "rpg_left", "rpg_right", "rpg_up"]:
		if Input.is_action_just_pressed(a):
			_held.erase(a)
			_held.push_front(a)
	var keep: Array[String] = []
	for a in _held:
		if Input.is_action_pressed(a):
			keep.append(a)
	_held = keep
	for a in ["rpg_down", "rpg_left", "rpg_right", "rpg_up"]:
		if Input.is_action_pressed(a) and not _held.has(a):
			_held.append(a)
	if _held.is_empty():
		return Vector2i.ZERO
	return {"rpg_down": Vector2i.DOWN, "rpg_left": Vector2i.LEFT, "rpg_right": Vector2i.RIGHT, "rpg_up": Vector2i.UP}[_held[0]]


## Action button: getting on or off a vehicle first (as in RPG Maker), then events of priority
## "same" in front (through a counter), or below/above here.
func check_action() -> bool:
	if get_on_off_vehicle():
		return true
	if vehicle != "":
		return false
	for ev in map.events_at(cell):
		if ev.priority != "same" and ev.trigger_action():
			return true
	var front: Vector2i = map.movement.normalize(front_cell())
	if front == Vector2i(-1, -1):
		return false
	for ev in map.events_at(front):
		if ev.priority == "same" and ev.trigger_action():
			return true
	if map.movement.flags(front) & RPGMovement.FLAG_COUNTER:
		var beyond: Vector2i = map.movement.normalize(front + RPGMovement.dir_vec(facing))
		for ev in map.events_at(beyond):
			if ev.priority == "same" and ev.trigger_action():
				return true
	return false


## Boards the vehicle in front (boat, ship) or underfoot (airship), or leaves the one being
## ridden. Returns true if something happened.
func get_on_off_vehicle() -> bool:
	var rpg: Node = map.rpg
	if vehicle != "":
		return _get_off()
	var kind: String = map.vehicle_at(cell)
	if kind != "airship":
		kind = map.vehicle_at(map.movement.normalize(front_cell()))
		if kind == "airship":
			kind = ""
	if kind == "":
		return false
	var node: Node = map.vehicle_nodes.get(kind)
	var at: Vector2i = node.cell
	rpg.state.riding = kind
	RPGVehicles.park(rpg.state, kind, map.map_id, at, facing)
	node.queue_free()
	map.vehicle_nodes.erase(kind)
	place(at)
	_board(kind)
	return true


func _get_off() -> bool:
	var rpg: Node = map.rpg
	var kind := vehicle
	var land: Vector2i = cell if kind == "airship" else map.movement.normalize(front_cell())
	if land == Vector2i(-1, -1) or not RPGVehicles.can_land(map.movement, land, self):
		return false
	if kind == "airship" and not map.events_at(cell).filter(func(e): return e.priority == "same").is_empty():
		return false
	RPGVehicles.park(rpg.state, kind, map.map_id, cell, facing)
	rpg.state.riding = ""
	_leave_vehicle()
	map.refresh_vehicles()
	if kind != "airship":
		place(land)
	return true


## Looks and moves like the vehicle; followers wait; the vehicle's music plays.
func _board(kind: String) -> void:
	var rpg: Node = map.rpg
	var cfg := RPGVehicles.look(rpg, kind)
	vehicle = kind
	set_meta("walk_speed", speed)
	speed = int(cfg.get("speed", 4))
	set_graphic(cfg.get("graphic"))
	step_anim = true
	z_index = 5 if kind == "airship" else 2
	for f in followers:
		f.visible = false
	trail.clear()
	var bgm: Variant = cfg.get("bgm")
	if bgm is Dictionary and str(bgm.get("file", "")) != "":
		# The map's music comes back where it was when the player gets off (MV's vehicle BGM).
		set_meta("map_bgm", rpg.audio.save_bgm())
		rpg.audio.play_bgm(bgm)


func _leave_vehicle() -> void:
	var rpg: Node = map.rpg
	vehicle = ""
	speed = int(get_meta("walk_speed", 4))
	step_anim = false
	z_index = 2
	if has_meta("map_bgm"):
		var prev: Dictionary = get_meta("map_bgm")
		remove_meta("map_bgm")
		if not prev.is_empty():
			rpg.audio.replay_bgm(prev)
	if rpg.game != null and rpg.game.has_method("refresh_party_graphics"):
		rpg.game.refresh_party_graphics()


## Walking into a same-priority event fires its touch trigger once until the player moves.
func _bump(dir: Vector2i) -> void:
	var target: Vector2i = map.movement.normalize(cell + dir)
	for ev in map.events_at(target):
		if ev.priority == "same":
			var key := "%s@%s" % [ev.event_id, cell]
			if key == _last_touch_key:
				return
			if ev.trigger_touch(false):
				_last_touch_key = key
				return


## Touch triggers fire when a step finishes, for below/above events on the new cell. Before them,
## a step on foot outside events has its walking effects (party_walk), as RPG Maker's
## on_player_walk runs before the touch events.
func _on_step_finished() -> void:
	var rpg: Node = map.rpg
	rpg.state.steps += 1
	if rpg.has_signal("player_stepped"):
		rpg.player_stepped.emit(cell, map.region_at(cell), map.terrain_at(cell))
	if vehicle != "":
		RPGVehicles.park(rpg.state, vehicle, map.map_id, cell, facing)
		# An airship flies over everything: no touch events, damage floors or encounters.
		if vehicle == "airship":
			return
	elif not rpg.scheduler.is_main_busy():
		# Steps in a vehicle or in an event's move route don't count (MV's isNormal()).
		var f: int = map.movement.flags(cell)
		show_party_walk(party_walk((f & RPGMovement.FLAG_DAMAGE) != 0 and not through))
	for ev in map.events_at(cell):
		if ev.priority != "same":
			ev.trigger_touch(false)
	_check_encounter()


# --- walking effects (states, slip damage, damage floors) -------------------------------------

## Red flash for damage taken on the map (MV's startFlashForDamage).
const MAP_DAMAGE_FLASH := Color(1, 0, 0, 0.5)


## One step on foot for every party member (RPG Maker's on_player_walk): a damage floor
## (System "damage_floor" HP, never a knockout), states removed by walking, and every
## RPGRuleSystem.map_turn_steps() steps regeneration, slip damage and state turns (MV/VX Ace),
## plus RPG Maker 2000-style "map_hp_change" states. System "slip_death" (Knockout by slip
## damage) lets the walking damage knock actors out. Counts state.walk_steps.
## Returns {damage, messages, knocked_out, all_dead}; show_party_walk shows it.
func party_walk(on_damage_floor := false) -> Dictionary:
	var rpg: Node = map.rpg
	var st: RPGGameState = rpg.state
	var out := {"damage": 0, "messages": [], "knocked_out": false, "all_dead": false}
	st.walk_steps += 1
	var rules: Variant = rpg.get("rules")
	if not (rules is RPGRuleSystem):
		return out
	var sys: Dictionary = rpg.data.system
	var slip_death := bool(sys.get("slip_death", false))
	var turn_steps: int = rules.map_turn_steps()
	for id in st.party:
		var b: Variant = st.actor(id)
		if not (b is RPGBattler):
			continue
		var before := [b.resources.duplicate(), b.state_ids()]
		var results := []
		if on_damage_floor:
			results.append(rules.floor_damage(b, int(sys.get("damage_floor", 5))))
		results.append(rules.walk_state_steps(b))
		if turn_steps > 0 and st.walk_steps % turn_steps == 0:
			results.append(rules.map_turn_end(b, slip_death))
		results.append(rules.map_step_changes(b, st.walk_steps, slip_death))
		for r in results:
			out.damage += int(r.damage)
			out.messages.append_array(r.messages)
			out.knocked_out = out.knocked_out or bool(r.knocked_out)
		if [b.resources, b.state_ids()] != before:
			st.notify_actor_changed(id)
	if out.knocked_out and not st.party.is_empty():
		out.all_dead = st.party_battlers().all(func(x): return x is RPGBattler and x.is_dead())
	return out


## Shows what party_walk did: a red flash and the damage sound for damage, the states' messages
## (as a message box, run as a main event), or the game over when walking knocked out the
## whole party.
func show_party_walk(r: Dictionary) -> void:
	var rpg: Node = map.rpg
	if int(r.get("damage", 0)) > 0:
		rpg.screen.flash(MAP_DAMAGE_FLASH, 0.25)
		rpg.audio.play_role("damage")
	if r.get("all_dead", false):
		if rpg.game != null and rpg.game.has_method("game_over"):
			rpg.game.game_over.call_deferred()
		return
	var msgs: Array = r.get("messages", [])
	if not msgs.is_empty():
		var cmds := []
		for m in msgs:
			cmds.append({"type": "show_text", "text": str(m)})
		rpg.scheduler.request_main("", cmds, {"kind": "map_event", "map": map.map_id, "event": "(states)"}, null)


func _check_encounter() -> void:
	var rpg: Node = map.rpg
	var enc: Dictionary = map.props.get("encounters", {})
	var groups: Array = enc.get("groups", [])
	if groups.is_empty() or rpg.scheduler.is_main_busy() or debug_through() or not bool(rpg.state.access.get("encounters", true)):
		return
	if encounter_count <= 0:
		reset_encounter()
		return
	encounter_count -= 1
	if encounter_count > 0:
		return
	reset_encounter()
	var region: int = map.region_at(cell)
	var pool := []
	for g in groups:
		var regions: Array = g.get("regions", [])
		if regions.is_empty() or regions.has(region):
			pool.append(g)
	if pool.is_empty():
		return
	var total := 0
	for g in pool:
		total += int(g.get("weight", 1))
	var roll := _rand(maxi(total, 1))
	for g in pool:
		roll -= int(g.get("weight", 1))
		if roll < 0:
			# Preemptive strike or surprise attack (RPGBattleCore.encounter_advantage: MV's 5% / 3%).
			var adv := "normal"
			if rpg.rules is RPGRuleSystem:
				adv = RPGBattleCore.encounter_advantage(rpg.rules, rpg.state.party_battlers(), rpg.data.record("troops", str(g.troop)), _randf_range(0.0, 1.0))
			rpg.scheduler.request_main("encounter", [{"type": "battle", "troop": g.troop, "can_escape": true, "can_lose": false, "advantage": adv}], {"kind": "map_event", "map": map.map_id, "event": "(encounter)"}, null)
			return


func reset_encounter() -> void:
	var steps := int(map.props.get("encounters", {}).get("steps", 30))
	encounter_count = maxi(1, int(steps * _randf_range(0.5, 1.5)))


# --- followers ---------------------------------------------------------------------------------

func _move_followers() -> void:
	if vehicle != "":
		return
	for i in followers.size():
		var f: RPGCharacter = followers[i]
		if i < trail.size() and f.visible:
			var target: Vector2i = trail[i]
			var d := target - f.cell
			if d != Vector2i.ZERO and absi(d.x) + absi(d.y) == 1:
				f.speed = speed
				f.dashing = dashing
				f.through = true
				f.step(d)
			elif d != Vector2i.ZERO:
				f.place(target)
