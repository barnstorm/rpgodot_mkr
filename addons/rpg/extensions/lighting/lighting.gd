extends "res://addons/rpg/runtime/rpg_extension.gd"
## Lighting and time of day (kit plugin "lighting").
##   Darkness: a map is dark when its Map properties say so (Plugin fields > Darkness: colour and
##   strength) or a Set darkness command made it dark. Lights show through: events whose active
##   page has a Light (Plugin fields: radius in tiles, colour, brightness, flicker), a light
##   around the player and, optionally, a flashlight cone in the direction the player faces.
##   Time of day: a game clock (real minutes per game hour) tints outdoor maps by the hour, with
##   the colours of the "Outdoor colour by hour" table blended smoothly. Maps marked Indoor are
##   not tinted. Commands set, advance or pause the clock; the "time_of_day" condition tests
##   the hour; the hour can be copied into a variable and shown on screen.
## Drawing: one full-screen rectangle on a CanvasLayer (layer 1, above the map and its
## characters, under pictures, weather, menus and messages) that follows the camera, with a
## shader that multiplies the picture by the darkness and lights it up around each light. It works
## in map pixels, so it fits any screen size and the zoom of 16 px art in 48 px projects.
## Saved with the game: {minutes, day, paused, darkness: {map: {...}}, player: {...},
## events: {"map/event": {...}}}.

signal hour_changed(hour: int)

const SECTION := "lighting"
const MAX_LIGHTS := 48
const SHADER_CODE := """
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform vec4 ambient = vec4(1.0);
uniform int light_count = 0;
uniform vec4 light_pos[48];
uniform vec4 light_col[48];
uniform vec4 light_dir[48];
varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec3 c = ambient.rgb;
	for (int i = 0; i < 48; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 p = light_pos[i];
		vec2 d = world_pos - p.xy;
		float dist = length(d);
		float lin = clamp(1.0 - dist / max(p.z, 0.001), 0.0, 1.0);
		float f = lin * lin * (3.0 - 2.0 * lin);
		vec4 lc = light_col[i];
		if (lc.a > -1.5) {
			// A cone (flashlight): a beam that keeps its light further out, with soft sides.
			f = pow(lin, 0.6);
			vec2 nd = dist > 0.5 ? d / dist : light_dir[i].xy;
			float ca = dot(nd, light_dir[i].xy);
			float edge = smoothstep(lc.a - 0.04, min(lc.a + 0.06, 1.0), ca);
			// The cone starts at the holder: a little light all round close to it.
			float near = clamp(1.0 - dist / (p.z * 0.12), 0.0, 1.0);
			f *= max(edge, near);
		}
		f *= p.w;
		c = max(c, mix(c, lc.rgb, f));
	}
	COLOR = vec4(c, 1.0);
}
"""

## Lights drawn in the last frame (tests): [{pos: Vector2, radius, colour: Color, intensity, cone?}]
var last_lights: Array = []
## The colour the map was multiplied by in the last frame (Color.WHITE: nothing drawn).
var last_ambient := Color.WHITE
var _layer: CanvasLayer = null
var _rect: Node2D = null
var _material: ShaderMaterial = null
var _clock: Panel = null
var _last_hour := -1
var _time := 0.0


# --- state ---------------------------------------------------------------------------------------

func _data() -> Dictionary:
	var s := section(SECTION)
	if not s.has("minutes"):
		s["minutes"] = float(clampi(int(setting("start_hour", 8)), 0, 23) * 60)
		s["day"] = 1
		s["paused"] = false
	for k in ["darkness", "player", "events"]:
		if not (s.get(k) is Dictionary):
			s[k] = {}
	return s


func day_night() -> bool:
	return bool(setting("day_night", false))


## Minutes since midnight (0 - 1439.99).
func minutes() -> float:
	return fposmod(float(_data().minutes), 1440.0)


func hour() -> int:
	return int(minutes() / 60.0) % 24


func minute() -> int:
	return int(minutes()) % 60


func day() -> int:
	return int(_data().get("day", 1))


func paused() -> bool:
	return bool(_data().get("paused", false))


## Sets the clock (hour 0-23, minute 0-59).
func set_time(h: int, m: int = 0) -> void:
	_data().minutes = float(posmod(h, 24) * 60 + clampi(m, 0, 59))
	_clock_changed()


## Moves the clock on (or back, for negative values); passing midnight changes the day.
func add_minutes(amount: float) -> void:
	var d := _data()
	var total := float(d.minutes) + amount
	var days := int(floor(total / 1440.0))
	d.minutes = fposmod(total, 1440.0)
	d.day = maxi(1, int(d.get("day", 1)) + days)
	_clock_changed()


func set_paused(on: bool) -> void:
	_data().paused = on


func _clock_changed() -> void:
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		var v := str(setting("hour_variable", ""))
		if v != "" and rpg.state != null:
			rpg.state.set_variable(v, h)
		hour_changed.emit(h)
		if rpg.has_method("request_refresh"):
			rpg.request_refresh()
	_refresh_clock()


## Condition kind "time_of_day": {from, to}; true from `from` o'clock until `to` (not included),
## across midnight when `to` is not after `from`.
func check_condition(cond: Dictionary, _where: Variant = null) -> bool:
	var from := clampi(int(cond.get("from", 0)), 0, 24)
	var to := clampi(int(cond.get("to", 24)), 0, 24)
	var h := hour()
	if from == to:
		return true
	if from < to:
		return h >= from and h < to
	return h >= from or h < to


## The outdoor tint at a time of day (minutes since midnight), from the hour table.
func tint_at(mins: float) -> Color:
	var keys := []
	for e in setting("hour_tints", []):
		if e is Dictionary:
			keys.append([clampi(int(e.get("hour", 0)), 0, 23) * 60.0, _colour(e.get("colour"), Color.WHITE)])
	if keys.is_empty():
		return Color.WHITE
	keys.sort_custom(func(a, b): return a[0] < b[0])
	var m := fposmod(mins, 1440.0)
	var prev: Array = keys[-1]
	var next: Array = keys[0]
	for k in keys:
		if k[0] <= m:
			prev = k
		else:
			next = k
			break
	var span := fposmod(float(next[0]) - float(prev[0]), 1440.0)
	if span <= 0.0:
		return prev[1]
	var t := fposmod(m - float(prev[0]), 1440.0) / span
	t = t * t * (3.0 - 2.0 * t)
	return (prev[1] as Color).lerp(next[1], t)


static func _colour(v: Variant, fallback: Color) -> Color:
	if v is Array and v.size() >= 3:
		return Color8(int(v[0]), int(v[1]), int(v[2]), int(v[3]) if v.size() > 3 else 255)
	if v is Color:
		return v
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback


static func _colour_array(c: Color) -> Array:
	return [c.r8, c.g8, c.b8, c.a8]


# --- darkness ------------------------------------------------------------------------------------

func _map() -> Node:
	if rpg == null or rpg.game == null or not is_instance_valid(rpg.game):
		return null
	var m: Variant = rpg.game.get("map")
	return m if m is Node and is_instance_valid(m) else null


func _map_id() -> String:
	var m := _map()
	return str(m.map_id) if m != null and "map_id" in m else ""


func _map_custom(map_id: String) -> Dictionary:
	if map_id == "" or rpg.data == null:
		return {}
	var c: Variant = rpg.data.map_props(map_id).get("custom", {})
	return c if c is Dictionary else {}


## The darkness of a map: {colour: Color, strength: 0-1} or {} when it is not dark. A Set
## darkness command's choice wins over the map's own setting.
func darkness_of(map_id: String) -> Dictionary:
	var o: Variant = _data().darkness.get(map_id)
	var d: Variant = o if o is Dictionary else _map_custom(map_id).get("darkness")
	if not (d is Dictionary) or d.is_empty() or bool(d.get("off", false)):
		return {}
	return {"colour": _colour(d.get("colour"), _colour(setting("darkness_colour", [8, 8, 24, 255]), Color(0.03, 0.03, 0.1))),
		"strength": clampf(float(d.get("strength", 85)) / 100.0, 0.0, 1.0)}


## Changes a map's darkness for the rest of the game (saved): `mode` "dark" (colour, strength
## 0-100), "off" (never dark) or "map" (as its Map properties say).
func set_darkness(map_id: String, mode: String, colour: Variant = null, strength := 85) -> void:
	var d: Dictionary = _data().darkness
	match mode:
		"map":
			d.erase(map_id)
		"off":
			d[map_id] = {"off": true}
		_:
			var c: Variant = colour if colour != null else setting("darkness_colour", [8, 8, 24, 255])
			d[map_id] = {"colour": _colour_array(_colour(c, Color(0.03, 0.03, 0.1))), "strength": clampi(strength, 0, 100)}


func indoor(map_id: String) -> bool:
	return bool(_map_custom(map_id).get("indoor", false))


## What the map is multiplied by now: the outdoor tint (time of day, outdoor maps) times the
## darkness.
func ambient(map_id := "") -> Color:
	if map_id == "":
		map_id = _map_id()
	var c := Color.WHITE
	if day_night() and not indoor(map_id):
		c = tint_at(minutes())
	var dk := darkness_of(map_id)
	if not dk.is_empty():
		var dc: Color = Color.WHITE.lerp(dk.colour, dk.strength)
		c = Color(c.r * dc.r, c.g * dc.g, c.b * dc.b)
	c.a = 1.0
	return c


# --- lights --------------------------------------------------------------------------------------

## The player's light {on, radius (tiles), flashlight}: the settings, changed by Set player light.
func player_light() -> Dictionary:
	var p: Dictionary = _data().player
	return {
		"on": bool(p.get("on", setting("player_light", true))),
		"radius": float(p.get("radius", setting("player_radius", 3.5))),
		"flashlight": bool(p.get("flashlight", setting("flashlight", false))),
	}


## Changes the player's light: on (null = keep), radius in tiles (<= 0 = keep), flashlight
## (null = keep).
func set_player_light(on: Variant, radius := 0.0, flashlight: Variant = null) -> void:
	var p: Dictionary = _data().player
	if on is bool:
		p["on"] = on
	if radius > 0.0:
		p["radius"] = radius
	if flashlight is bool:
		p["flashlight"] = flashlight


## An event's light on this map: its active page's Light, unless Set event light changed it.
func event_light(map_id: String, ev: Node) -> Dictionary:
	var key := "%s/%s" % [map_id, str(ev.get("event_id"))]
	var o: Variant = _data().events.get(key)
	if o is Dictionary:
		return {} if bool(o.get("off", false)) else o
	var pg: Variant = ev.get("page")
	if not (pg is Dictionary):
		return {}
	var custom: Variant = pg.get("custom", {})
	var l: Variant = custom.get("light") if custom is Dictionary else null
	return l if l is Dictionary and not l.is_empty() else {}


## Set event light: mode "page" (as its page says), "off", or "on" with {radius, colour,
## intensity, flicker}.
func set_event_light(map_id: String, event_id: String, mode: String, light: Dictionary = {}) -> void:
	var key := "%s/%s" % [map_id, event_id]
	var e: Dictionary = _data().events
	match mode:
		"page":
			e.erase(key)
		"off":
			e[key] = {"off": true}
		_:
			var l := {"radius": 3.0, "colour": [255, 214, 150, 255], "intensity": 100, "flicker": false}
			l.merge(light, true)
			e[key] = l


## Every light on the current map in map pixels: [{pos, radius, colour, intensity, cone?, dir?}].
func lights() -> Array:
	var out := []
	var m := _map()
	if m == null:
		return out
	var ts := float(m.get("tile_size")) if m.get("tile_size") != null else 16.0
	var flick := bool(option("flicker", false))
	var map_id := _map_id()
	var evs: Variant = m.get("events")
	if evs is Dictionary:
		for id in evs:
			var ev: Variant = evs[id]
			if not (ev is Node2D) or not is_instance_valid(ev) or bool(ev.get("erased")) or not ev.visible:
				continue
			var l := event_light(map_id, ev)
			if l.is_empty():
				continue
			var r := float(l.get("radius", 3.0)) * ts
			var inten := clampf(float(l.get("intensity", 100)) / 100.0, 0.0, 1.0)
			if flick and bool(l.get("flicker", false)):
				var seed := float(hash(str(id)) % 997)
				var f := 0.6 * sin(_time * 9.0 + seed) + 0.4 * sin(_time * 23.0 + seed * 1.7)
				r *= 1.0 + 0.06 * f
				inten *= 0.92 + 0.08 * f
			out.append({"pos": ev.global_position - Vector2(0, ts * 0.5), "radius": r, "colour": _colour(l.get("colour"), Color(1, 0.84, 0.6)), "intensity": inten, "event": str(id)})
	var pl: Variant = rpg.game.get("player")
	if pl is Node2D and is_instance_valid(pl) and pl.is_inside_tree() and pl.visible:
		var pp: Vector2 = pl.global_position - Vector2(0, ts * 0.5)
		var me := player_light()
		if bool(me.on) and float(me.radius) > 0.0:
			out.append({"pos": pp, "radius": float(me.radius) * ts, "colour": _colour(setting("player_colour", [255, 240, 210, 255]), Color.WHITE), "intensity": 1.0, "player": true})
		if bool(me.flashlight):
			var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
			var dir: Vector2 = dirs.get(str(pl.get("facing")), Vector2.DOWN)
			var half := deg_to_rad(clampf(float(setting("flashlight_angle", 60)), 10.0, 170.0) / 2.0)
			out.append({"pos": pp, "radius": float(setting("flashlight_length", 7.0)) * ts, "colour": _colour(setting("player_colour", [255, 240, 210, 255]), Color.WHITE),
				"intensity": 1.0, "cone": cos(half), "dir": dir, "player": true})
	return out.slice(0, MAX_LIGHTS)


# --- drawing -------------------------------------------------------------------------------------

func _ensure_layer() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.name = "LightingLayer"
	_layer.layer = 1
	_layer.follow_viewport_enabled = true
	add_child(_layer)
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = sh
	_rect = Node2D.new()
	_rect.name = "Darkness"
	_rect.material = _material
	_rect.draw.connect(_draw_rect)
	_layer.add_child(_rect)


func _draw_rect() -> void:
	var vp := _rect.get_viewport()
	if vp == null:
		return
	var inv := vp.get_canvas_transform().affine_inverse()
	var r := inv * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	_rect.draw_rect(r.grow(8.0), Color.WHITE)


## The darkness node (tests and screenshots); null while nothing is drawn.
func darkness_node() -> Node2D:
	return _rect if _rect != null and is_instance_valid(_rect) and _layer.visible else null


func _process(delta: float) -> void:
	_time += delta
	var m := _map()
	if m == null:
		if _layer != null and is_instance_valid(_layer):
			_layer.visible = false
		last_ambient = Color.WHITE
		last_lights = []
		_refresh_clock()
		return
	if day_night() and not paused():
		var stop: bool = bool(setting("pause_in_menus", true)) and rpg.ui != null and rpg.ui.scene_open()
		if not stop:
			var per_hour := maxf(0.05, float(setting("minutes_per_hour", 1.0))) * 60.0
			add_minutes(delta * 60.0 / per_hour)
	update_lighting()
	_update_clock_visibility()


## Recomputes the ambient colour and the lights and draws them (called every frame).
func update_lighting() -> void:
	var amb := ambient()
	last_ambient = amb
	if amb.is_equal_approx(Color.WHITE):
		last_lights = []
		if _layer != null and is_instance_valid(_layer):
			_layer.visible = false
		return
	_ensure_layer()
	_layer.visible = true
	var ls := lights()
	# Lights show as much as it is dark: half strength at dusk, full on dark maps and at night.
	var dark_k := clampf((1.0 - amb.get_luminance()) * 1.6, 0.0, 1.0)
	for l in ls:
		l["intensity"] = float(l.intensity) * dark_k
	last_lights = ls
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	var dir := PackedVector4Array()
	pos.resize(MAX_LIGHTS)
	col.resize(MAX_LIGHTS)
	dir.resize(MAX_LIGHTS)
	for i in ls.size():
		var l: Dictionary = ls[i]
		var c: Color = l.colour
		pos[i] = Vector4(l.pos.x, l.pos.y, l.radius, l.intensity)
		col[i] = Vector4(c.r, c.g, c.b, float(l.get("cone", -2.0)))
		var dv: Vector2 = l.get("dir", Vector2.DOWN)
		dir[i] = Vector4(dv.x, dv.y, 0, 0)
	_material.set_shader_parameter("ambient", amb)
	_material.set_shader_parameter("light_count", ls.size())
	_material.set_shader_parameter("light_pos", pos)
	_material.set_shader_parameter("light_col", col)
	_material.set_shader_parameter("light_dir", dir)
	_rect.queue_redraw()


# --- clock on screen -----------------------------------------------------------------------------

func clock_text() -> String:
	return "%02d:%02d" % [hour(), minute()]


## The clock panel showing now, or null (tests and screenshots).
func clock_panel() -> Panel:
	return _clock if _clock != null and is_instance_valid(_clock) else null


func _refresh_clock() -> void:
	var want := day_night() and bool(setting("clock", false)) and _map() != null
	if not want:
		if _clock != null and is_instance_valid(_clock):
			_clock.queue_free()
		_clock = null
		return
	if clock_panel() == null:
		var layer: Variant = rpg.map_overlay_layer("hud")
		if not (layer is Control):
			return
		var p := Panel.new()
		p.name = "Clock"
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if rpg.ui != null and rpg.ui.get("ui_theme") is Theme:
			p.theme = rpg.ui.ui_theme
		p.self_modulate.a = 0.8
		p.size = Vector2(44, 18)
		var corner := str(setting("clock_corner", "bottom_right"))
		p.position = Vector2(4.0 if corner.ends_with("left") else 320.0 - 48.0, 4.0 if corner.begins_with("top") else 240.0 - 22.0)
		var l := Label.new()
		l.name = "Time"
		l.size = p.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 10)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)
		layer.add_child(p)
		_clock = p
	(_clock.get_node("Time") as Label).text = clock_text()


func _update_clock_visibility() -> void:
	var c := clock_panel()
	if c != null:
		c.visible = not (rpg.ui != null and (rpg.ui.scene_open() or (rpg.ui.message_box != null and rpg.ui.message_box.has_method("is_open") and rpg.ui.message_box.is_open())))


# --- lifecycle -----------------------------------------------------------------------------------

func _extension_ready() -> void:
	_data()
	_last_hour = -1
	_clock_changed()


func on_new_game() -> void:
	_data()
	_last_hour = -1
	_clock_changed()


func on_game_loaded() -> void:
	_data()
	_last_hour = -1
	_clock_changed()


func on_map_entered(_map_id: String) -> void:
	_refresh_clock()
	update_lighting()


func on_title_shown() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.visible = false
	if _clock != null and is_instance_valid(_clock):
		_clock.queue_free()
	_clock = null


func _exit_tree() -> void:
	if _clock != null and is_instance_valid(_clock):
		_clock.queue_free()
	_clock = null
