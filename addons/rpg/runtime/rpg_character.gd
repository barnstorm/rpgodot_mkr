class_name RPGCharacter
extends Node2D
## A grid mover: player, follower or event. Moves one tile at a time with RPG Maker's speed
## (1-6) and frequency (1-5) settings, draws a CharSet frame or a tile, and runs move routes.

signal step_finished(cell: Vector2i)
signal step_blocked(dir: Vector2i)
signal route_done()

## RPG Maker speeds 1..6 in tiles per second.
const SPEEDS := [0.0, 1.0, 2.0, 3.0, 4.2, 6.0, 9.0]
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


func move_speed() -> float:
	var s: float = SPEEDS[clampi(speed, 1, 6)]
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
## {switch: id, value}, {sound: {...}}, {walk_anim|step_anim|direction_fix|through|hide: bool}.
func run_route(route: Dictionary, token: RPGCancelToken, timeout := 8.0) -> bool:
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
			if not await _route_step(s, skip, token, timeout):
				return false
		if not repeat:
			break
		await get_tree().process_frame
	return not token.is_cancelled


## Stops the move route running on its own token (an autonomous custom route, or a Move Route
## that does not wait). Used when the map is unloaded: a route parked on a {wait} step otherwise
## keeps its timer, waiter and suspended function alive after the map is gone (a leak at exit).
func cancel_route(why := "map unloaded") -> void:
	if _route_token != null:
		_route_token.cancel(why)


func _route_step(s: Dictionary, skip: bool, token: RPGCancelToken, timeout: float) -> bool:
	var rpg: Node = map.rpg
	if s.has("step"):
		var dir := _route_dir(str(s.step))
		if dir == Vector2i.ZERO:
			return true
		var waited := 0.0
		while not step(dir):
			if skip:
				return true
			await get_tree().process_frame
			waited += get_process_delta_time()
			if token.is_cancelled:
				return false
			if waited > timeout:
				if OS.is_debug_build():
					push_warning("RPG: move route of '%s' blocked for %.1f s at %s." % [name, waited, cell])
				return true
		while moving:
			await get_tree().process_frame
		return true
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
