class_name RPGCharacter
extends Node2D
## A grid mover: player, follower or event. Moves one tile at a time with RPG Maker's speed
## (1-6) and frequency (1-5) settings, draws a CharSet frame or a tile, and runs move routes.

signal step_finished(cell: Vector2i)
signal step_blocked(dir: Vector2i)
signal route_done()

## RPG Maker speeds 1..6 in tiles per second (index 0 is unused) for a character with no
## project to ask: VX / VX Ace / MV's scale, each speed twice the one before. In a game the
## project's table is used (RPGProjectData.move_speeds: the profile's RPG Maker scale, or the
## project's own); see move_speed().
const SPEEDS := [0.0, 0.46875, 0.9375, 1.875, 3.75, 7.5, 15.0]
## RPG Maker's names for speeds 1..6.
const SPEED_LABELS := ["1: x8 Slower", "2: x4 Slower", "3: x2 Slower", "4: Normal", "5: x2 Faster", "6: x4 Faster"]
const CHARSET_SCRIPT := "res://addons/rpg/import/rpg_charset.gd"

var map: Node
var cell := Vector2i.ZERO
var facing := "down"
var speed := 4
var frequency := 3
var walk_anim := true
var step_anim := false
var direction_fix := false
var through := false
var priority := "same"
var is_hidden := false
## "Change Transparency": drawn invisible but still moves, blocks and triggers like normal.
var transparent := false
var opacity := 255
var graphic: Variant = null
var dashing := false

var moving := false
var jumping := false
var move_from := Vector2.ZERO
var move_to := Vector2.ZERO
var move_t := 0.0
var jump_height := 0.0
var target_cell := Vector2i.ZERO
var pattern := 1
var anim_time := 0.0
var stop_time := 0.0
var _anim_index := 0

var sprite: Sprite2D
var tile_sprite: Sprite2D
var bush_sprite: Sprite2D
var tile_size := 16
var _frame_size := Vector2i(24, 32)

var _sheet_tex: Texture2D
var _route_token: RPGCancelToken = null
## The forced route (Set Move Route) playing now, or null: this character's own movement
## pauses while it runs (MV's isMoveRouteForcing).
var _forced_token: RPGCancelToken = null
## Whether the playing forced route repeats: a repeating route never blocks Wait for All
## Movement (RPG Maker's Proceed with Movement ignores looping routes).
var _forced_repeat := false
## The cell a move-route step is parked on, waiting for the way to clear ((-1, -1) = not
## waiting) — shown by the debug inspector.
var _blocked_step_at := Vector2i(-1, -1)
## How long a blocked step is retried before a debug warning is logged. The step is never
## dropped: RPG Maker retries it until it succeeds or the route is cancelled.
var _blocked_warn_after := 8.0


func _init() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	bush_sprite = Sprite2D.new()
	bush_sprite.centered = false
	bush_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bush_sprite.visible = false
	bush_sprite.modulate.a = 0.5
	add_child(bush_sprite)


func setup_on_map(p_map: Node, p_cell: Vector2i) -> void:
	map = p_map
	tile_size = map.tile_size
	place(p_cell)


func place(p_cell: Vector2i) -> void:
	cell = p_cell
	moving = false
	jumping = false
	position = _cell_pos(cell)
	_update_frame()


func _cell_pos(c: Vector2i) -> Vector2:
	return Vector2(c.x * tile_size + tile_size / 2.0, c.y * tile_size + tile_size)


func blocks() -> bool:
	return priority == "same" and not through and not is_hidden and visible


func debug_through() -> bool:
	return false


## Tiles per second at the character's speed (twice that while dashing).
func move_speed() -> float:
	var s: float = SPEEDS[clampi(speed, 1, 6)]
	if map != null and map.get("rpg") != null and map.rpg.get("data") != null:
		s = map.rpg.data.move_speed(speed)
	if dashing:
		s *= 2.0
	return s


# --- graphics ----------------------------------------------------------------------------

## graphic: {sheet, index, facing, frame} | {tile: tile_key or [source, x, y]} | null
func set_graphic(g: Variant) -> void:
	graphic = g
	_sheet_tex = null
	sprite.texture = null
	sprite.region_enabled = false
	if g is Dictionary and str(g.get("sheet", "")) != "":
		var tex: Texture2D = map.load_charset(g.sheet) if map != null else null
		if tex == null:
			_placeholder(g)
		else:
			_sheet_tex = tex
			_sheet_index = int(g.get("index", 0))
			_sheet_single = RPGCharset.is_single_character(str(g.sheet), _charset_profile())
			_frame_size = RPGCharset.frame_size(_charset_profile(), Vector2i(tex.get_size()), _sheet_single)
			sprite.texture = tex
			sprite.region_enabled = true
		if g.has("facing") and str(g.facing) != "" and str(g.facing) != "keep":
			facing = g.facing
		if g.has("frame"):
			pattern = int(g.frame)
	elif g is Dictionary and g.has("tile"):
		var tex2: Texture2D = map.tile_texture(g.tile) if map != null else null
		sprite.texture = tex2
		_frame_size = Vector2i(tile_size, tile_size)
	_update_frame()


func _placeholder(g: Dictionary) -> void:
	# Missing asset: show a visible placeholder instead of nothing.
	var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 0.7))
	for i in tile_size:
		img.set_pixel(i, i, Color.BLACK)
		img.set_pixel(tile_size - 1 - i, i, Color.BLACK)
	sprite.texture = ImageTexture.create_from_image(img)
	_frame_size = Vector2i(tile_size, tile_size)


var _sheet_index := 0
var _sheet_single := false


## Profile id for CharSet layouts: the sheet's pack profile, else the project's (rm2k when unknown).
func _charset_profile() -> String:
	var fallback := str(map.profile_id) if map != null and "profile_id" in map else "rm2k"
	if graphic is Dictionary and str(graphic.get("sheet", "")) != "":
		if _profile_sheet != str(graphic.sheet) or _profile_fallback != fallback:
			_profile_sheet = str(graphic.sheet)
			_profile_fallback = fallback
			_profile_cached = RPGAssets.sheet_profile("charset", _profile_sheet, fallback)
		return _profile_cached
	return fallback


var _profile_sheet := ""
var _profile_fallback := ""
var _profile_cached := "rm2k"


## Standing frame and walk cycle from the profile's charset sheet (rm2k: 1 and 0,1,2,1).
func _idle_frame() -> int:
	var p := RPGProfile.load_profile(_charset_profile())
	return int(p.sheet("charset").get("idle_frame", 1)) if p != null else 1


func _walk_pattern() -> Array:
	var p := RPGProfile.load_profile(_charset_profile())
	var w: Array = p.sheet("charset").get("walk_pattern", [0, 1, 2, 1]) if p != null else [0, 1, 2, 1]
	return w if not w.is_empty() else [0, 1, 2, 1]


func _update_frame() -> void:
	sprite.visible = not is_hidden and not transparent
	sprite.modulate.a = opacity / 255.0
	if _sheet_tex != null:
		# CharSet layout (rows, frames, characters per sheet) comes from the profile.
		var r := RPGCharset.frame_rect(_charset_profile(), Vector2i(_sheet_tex.get_size()), _sheet_index, facing, pattern, _sheet_single)
		sprite.region_rect = Rect2(r)
		_frame_size = r.size
	sprite.position = Vector2(-_frame_size.x / 2.0, -_frame_size.y)
	if jumping:
		sprite.position.y -= jump_height
	_update_bush()


func _update_bush() -> void:
	var on_bush: bool = map != null and not moving and not jumping and map.movement != null and (map.movement.flags(cell) & RPGMovement.FLAG_BUSH) != 0 and priority != "above"
	if on_bush and sprite.texture != null and _sheet_tex != null:
		var lower := maxi(8, tile_size / 4)  # 8 px at 16/32 px tiles, 12 px at 48 px
		sprite.region_rect.size.y -= lower
		bush_sprite.texture = sprite.texture
		bush_sprite.region_enabled = true
		bush_sprite.region_rect = Rect2(sprite.region_rect.position.x, sprite.region_rect.position.y + sprite.region_rect.size.y, sprite.region_rect.size.x, lower)
		bush_sprite.position = sprite.position + Vector2(0, sprite.region_rect.size.y)
		bush_sprite.visible = not is_hidden and not transparent
	else:
		bush_sprite.visible = false


# --- movement --------------------------------------------------------------------------------

func turn(dir_name: String) -> void:
	if direction_fix or dir_name == "" or dir_name == "keep":
		return
	facing = dir_name
	_update_frame()


func force_turn(dir_name: String) -> void:
	if dir_name == "" or dir_name == "keep":
		return
	facing = dir_name
	_update_frame()


## Starts a one-tile step. Returns false when blocked (and emits step_blocked).
func step(dir: Vector2i) -> bool:
	if moving:
		return false
	var dn := RPGMovement.dir_name(dir)
	if dn != "":
		turn(dn)
	elif dir.x != 0 and not direction_fix:
		facing = "left" if dir.x < 0 else "right"
	var mv: RPGMovement = map.movement
	if not mv.can_move(self, cell, dir):
		_update_frame()
		step_blocked.emit(dir)
		return false
	var to := mv.normalize(cell + dir)
	mv.reserve(self, to)
	target_cell = to
	move_from = position
	move_to = position + Vector2(dir * tile_size)
	move_t = 0.0
	moving = true
	return true


func jump(offset: Vector2i) -> bool:
	if moving:
		return false
	var mv: RPGMovement = map.movement
	var to := mv.normalize(cell + offset)
	if offset != Vector2i.ZERO:
		if to == Vector2i(-1, -1) or (not through and (mv.passage(to) == 0 or mv.is_occupied(to, self))):
			return false
	mv.reserve(self, to)
	target_cell = to
	move_from = position
	move_to = position + Vector2(offset * tile_size)
	move_t = 0.0
	moving = true
	jumping = true
	return true


func _process(delta: float) -> void:
	if moving:
		var dist := maxf(1.0, (move_to - move_from).length() / tile_size)
		if jumping:
			dist = maxf(dist, 1.5)
		move_t += delta * move_speed() / dist
		if move_t >= 1.0:
			_arrive()
		else:
			position = move_from.lerp(move_to, move_t)
			if jumping:
				jump_height = sin(move_t * PI) * tile_size * 0.75
		_animate(delta, true)
		_update_frame()
	else:
		_animate(delta, false)


func _arrive() -> void:
	var mv: RPGMovement = map.movement
	mv.release(self, target_cell)
	cell = target_cell
	position = _cell_pos(cell)
	moving = false
	jumping = false
	jump_height = 0.0
	_update_frame()
	_on_step_finished()
	step_finished.emit(cell)


func _on_step_finished() -> void:
	pass


func _animate(delta: float, is_moving: bool) -> void:
	var animate := (is_moving and walk_anim) or step_anim
	if not animate:
		var idle := _idle_frame()
		if pattern != idle and not (graphic is Dictionary and graphic.has("frame")):
			stop_time += delta
			if stop_time > 0.15:
				pattern = idle
				_update_frame()
		return
	stop_time = 0.0
	anim_time += delta * move_speed() * 1.6
	if anim_time >= 1.0:
		anim_time -= 1.0
		var walk := _walk_pattern()
		_anim_index = (_anim_index + 1) % walk.size()
		pattern = int(walk[(_anim_index + 1) % walk.size()])
		_update_frame()


## Direction from this character toward another cell (4 directions, larger axis first).
func dir_toward(target: Vector2i, away := false) -> Vector2i:
	var d := target - cell
	if away:
		d = -d
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


func front_cell() -> Vector2i:
	return cell + RPGMovement.dir_vec(facing)


# --- move routes -----------------------------------------------------------------------------

## Runs a move route. route: {steps: [...], repeat, skip_if_blocked}. Returns false if cancelled.
## Steps: {step: dir|forward|backward|random|toward_player|away_from_player|down_left...},
## {turn: dir|left_90|right_90|around|random|toward_player|away_from_player}, {jump: [dx, dy]},
## {wait: seconds}, {speed: n}, {frequency: n}, {graphic: {...}}, {opacity: 0-255},
## {switch: id, value}, {sound: {...}}, {walk_anim|step_anim|direction_fix|through|hide: bool},
## {slide: dir|forward} (ice: keep moving until blocked), {move_to: [x, y]|player|event_id}
## (shortest way around walls), {call: {method, args}} (extension hook on this character),
## {speed_up|speed_down|frequency_up|frequency_down|opacity_up|opacity_down: true}.
func run_route(route: Dictionary, token: RPGCancelToken) -> bool:
	var steps: Array = route.get("steps", [])
	var repeat: bool = route.get("repeat", false)
	var skip: bool = route.get("skip_if_blocked", false)
	if steps.is_empty():
		return true
	_route_token = token
	while true:
		for s in steps:
			if token.is_cancelled or not is_inside_tree():
				return false
			if _forced_token != null and token != _forced_token and not await _pause_for_forced(token):
				return false
			if not await _route_step(s, skip, token):
				return false
		if not repeat:
			break
		await get_tree().process_frame
	return not token.is_cancelled


## A forced route (Set Move Route) takes over the character: this route — the event's custom
## autonomous one — pauses while it plays, then resumes from the same step (MV's
## restoreMoveRoute). False when this route was cancelled while waiting.
func _pause_for_forced(token: RPGCancelToken) -> bool:
	while _forced_token != null and _forced_token != token:
		if token.is_cancelled or not is_inside_tree():
			return false
		await get_tree().process_frame
	return true


## Set Move Route: like run_route, but marks the route as forced, so the character's own
## movement pauses while it plays. The route runs on the token given (its own, never the
## calling event's), so cancel_forced_route() ends just the route, not the event.
func run_forced_route(route: Dictionary, token: RPGCancelToken) -> bool:
	if _forced_token != null and not _forced_token.is_cancelled:
		_forced_token.cancel("replaced by a new move route")
	_forced_token = token
	_forced_repeat = bool(route.get("repeat", false))
	var ok: bool = await run_route(route, token)
	if _forced_token == token:
		_forced_token = null
		_forced_repeat = false
	return ok


## True while a forced route (Set Move Route) is playing.
func is_route_forced() -> bool:
	return _forced_token != null and not _forced_token.is_cancelled


## True while a forced route plays that Wait for All Movement must wait for: a one-pass route.
## Repeating routes are ignored, as RPG Maker's Proceed with Movement ignores looping routes.
func has_waitable_forced_route() -> bool:
	return is_route_forced() and not _forced_repeat


## Ends the forced route early (a page change under the VX Ace style rules does).
func cancel_forced_route(why := "page changed") -> void:
	if _forced_token != null:
		_forced_token.cancel(why)


## Stops the move route running on its own token (an autonomous custom route, or a Move Route
## that does not wait). Used when the map is unloaded: a route parked on a {wait} step otherwise
## keeps its timer, waiter and suspended function alive after the map is gone (a leak at exit).
func cancel_route(why := "map unloaded") -> void:
	if _forced_token != null:
		_forced_token.cancel(why)
	if _route_token != null:
		_route_token.cancel(why)


func _route_step(s: Dictionary, skip: bool, token: RPGCancelToken) -> bool:
	var rpg: Node = map.rpg
	if s.has("step"):
		var dir := _route_dir(str(s.step))
		if dir == Vector2i.ZERO:
			return true
		return await _step_cell(dir, skip, token)
	if s.has("slide"):
		# Ice slide: keep stepping one cell in the direction until something stops the character.
		var sdir := _route_dir(str(s.slide))
		while sdir != Vector2i.ZERO and not token.is_cancelled and step(sdir):
			while moving:
				await get_tree().process_frame
		return true
	if s.has("move_to"):
		return await _move_to_step(s.move_to, skip, token)
	if s.has("turn"):
		var t := str(s.turn)
		match t:
			"left_90": turn({"down": "right", "right": "up", "up": "left", "left": "down"}[facing])
			"right_90": turn({"down": "left", "left": "up", "up": "right", "right": "down"}[facing])
			"around": turn(RPGMovement.OPPOSITE[facing])
			"random": turn(["down", "left", "right", "up"][_rand(4)])
			"toward_player": turn(RPGMovement.dir_name(dir_toward(map.player.cell)))
			"away_from_player": turn(RPGMovement.dir_name(dir_toward(map.player.cell, true)))
			_: turn(t)
		return true
	if s.has("jump"):
		var j: Array = s.jump
		if not jump(Vector2i(int(j[0]), int(j[1]))) and not skip:
			return true
		while moving:
			await get_tree().process_frame
		return true
	if s.has("wait"):
		var timer := get_tree().create_timer(float(s.wait), false)
		var w := RPGWaiter.any([timer.timeout, token.cancelled])
		var r: Array = await w.done
		return r[0] == 0
	if s.has("speed"):
		speed = clampi(int(s.speed), 1, 6)
	if s.has("frequency"):
		frequency = clampi(int(s.frequency), 1, 5)
	# RM2000/2003's Speed/Frequency/Transparency Up and Down steps, one notch each, clamped.
	if s.has("speed_up"):
		speed = clampi(speed + 1, 1, 6)
	if s.has("speed_down"):
		speed = clampi(speed - 1, 1, 6)
	if s.has("frequency_up"):
		frequency = clampi(frequency + 1, 1, 5)
	if s.has("frequency_down"):
		frequency = clampi(frequency - 1, 1, 5)
	if s.has("opacity_up") or s.has("opacity_down"):
		# Transparency UP means more visible: 8 notches over the 0-255 range, as RM's 8 steps.
		opacity = clampi(opacity + (32 if s.has("opacity_up") else -32), 0, 255)
		_update_frame()
	if s.has("call"):
		# The kit's Script step: a hook on this character for extensions (a custom event node's
		# own methods). A missing method is an error, not a cancelled route: the step is skipped.
		var c: Variant = s.call
		var m := str(c.method) if c is Dictionary else str(c)
		if not has_method(m):
			push_error("RPG: move route of '%s': no method '%s' to call." % [name, m])
		else:
			var call_args: Array = c.get("args", []) if c is Dictionary else []
			await callv(m, call_args)
	if s.has("graphic"):
		set_graphic(s.graphic)
	if s.has("opacity"):
		opacity = clampi(int(s.opacity), 0, 255)
		_update_frame()
	if s.has("switch"):
		rpg.state.set_switch(str(s.switch), bool(s.get("value", true)))
	if s.has("sound"):
		rpg.audio.play_se(s.sound)
	for flag in ["walk_anim", "step_anim", "direction_fix", "through"]:
		if s.has(flag):
			set(flag, bool(s[flag]))
	if s.has("hide"):
		is_hidden = bool(s.hide)
		_update_frame()
	return true


## One step of a route in direction `dir`, with RPG Maker's retry rules: a blocked step is
## retried every frame until the way clears — or skipped at once with 'Skip if cannot move'.
## False only when the route was cancelled while waiting.
func _step_cell(dir: Vector2i, skip: bool, token: RPGCancelToken) -> bool:
	var waited := 0.0
	var warned := false
	while not step(dir):
		if skip:
			return true
		_blocked_step_at = cell
		await get_tree().process_frame
		waited += get_process_delta_time()
		if token.is_cancelled:
			_blocked_step_at = Vector2i(-1, -1)
			return false
		# No timeout drops the step: with 'Skip if cannot move' off it is retried until it
		# succeeds (RPG Maker), however long that takes. A long block only logs a warning.
		if not warned and waited > _blocked_warn_after:
			warned = true
			if OS.is_debug_build():
				push_warning("RPG: move route of '%s' blocked at %s for %.1f s (waiting for the way to clear)." % [name, cell, waited])
	_blocked_step_at = Vector2i(-1, -1)
	while moving:
		await get_tree().process_frame
	return true


## A {move_to} step: walks to [x, y], "player" or an event id by the shortest way (walls are
## gone around, characters are not — a blocked step follows the route's skip rules). A moving
## goal is re-aimed at every cell; a goal held by a blocking character is arrived at from
## beside it, as close as the way allows.
func _move_to_step(goal_v: Variant, skip: bool, token: RPGCancelToken) -> bool:
	var waited := 0
	while true:
		if token.is_cancelled or not is_inside_tree():
			return false
		var goal := _move_to_goal(goal_v)
		if goal == Vector2i(-1, -1) or goal == cell:
			return true
		var way: Array = map.movement.path(cell, goal)
		if way.is_empty():
			# No way there at all (walls, a locked door). 'Skip if cannot move' gives up on the
			# step; otherwise it waits like a blocked step, in case the way opens.
			if skip:
				return true
			_blocked_step_at = cell
			await get_tree().process_frame
			waited += 1
			if waited == 480 and OS.is_debug_build():
				push_warning("RPG: move route of '%s' cannot reach %s from %s (waiting for a way)." % [name, goal, cell])
			continue
		if way.size() == 1 and map.movement.is_occupied(goal, self):
			return true
		if not await _step_cell(way[0] - cell, skip, token):
			return false
		if cell != way[0]:
			return true  # the step was skipped (blocked): give up on the goal, like RPG Maker
	return true  # unreachable: the loop only leaves through the returns above


## The cell a {move_to} step aims at: [x, y] directly, or the live cell of "player" / an event.
func _move_to_goal(v: Variant) -> Vector2i:
	if v is Array and v.size() >= 2:
		return map.movement.normalize(Vector2i(int(v[0]), int(v[1])))
	var who := str(v)
	if who == "player" and map.player != null:
		return map.player.cell
	var ev: Node = map.get_event(who) if map != null else null
	if ev != null:
		return ev.cell
	push_error("RPG: move route of '%s': move_to target '%s' not found." % [name, who])
	return Vector2i(-1, -1)


func _route_dir(name_: String) -> Vector2i:
	match name_:
		"forward": return RPGMovement.dir_vec(facing)
		"backward":
			var d := -RPGMovement.dir_vec(facing)
			var keep := direction_fix
			direction_fix = true
			call_deferred("set", "direction_fix", keep)
			return d
		"random": return [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP][_rand(4)]
		"toward_player": return dir_toward(map.player.cell) if map.player else Vector2i.ZERO
		"away_from_player": return dir_toward(map.player.cell, true) if map.player else Vector2i.ZERO
		"down_left": return Vector2i(-1, 1)
		"down_right": return Vector2i(1, 1)
		"up_left": return Vector2i(-1, -1)
		"up_right": return Vector2i(1, -1)
	return RPGMovement.dir_vec(name_)


## 0..n-1 from the project's seeded RNG (RPG.rng), so seeded runs repeat exactly.
func _rand(n: int) -> int:
	if map != null and map.rpg != null and map.rpg.rng != null:
		return map.rpg.rng.randi_range(0, n - 1)
	return randi() % n


func _randf_range(lo: float, hi: float) -> float:
	if map != null and map.rpg != null and map.rpg.rng != null:
		return map.rpg.rng.randf_range(lo, hi)
	return randf_range(lo, hi)
