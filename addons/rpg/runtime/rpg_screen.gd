class_name RPGScreen
extends Node
## Screen effects: fade, tint (colour tone), flash, shake, weather and numbered pictures.
## Every effect returns a Signal that fires when it is done, so commands can await it.

signal effect_done()

var fade_rect: ColorRect
var flash_rect: ColorRect
var tint: CanvasModulate
var pictures_layer: CanvasLayer
var weather_layer: CanvasLayer
var fx_layer: CanvasLayer
var fade_layer: CanvasLayer
var pictures: Dictionary = {}
var weather_node: CPUParticles2D
var weather_type := "none"
var shake_power := 0.0
var shake_time := 0.0
var shake_offset := Vector2.ZERO
var is_faded := false
var tint_color := Color.WHITE


func _init() -> void:
	name = "Screen"


func _ready() -> void:
	tint = CanvasModulate.new()
	tint.color = Color.WHITE
	add_child(tint)
	pictures_layer = _layer(3)
	weather_layer = _layer(4)
	fx_layer = _layer(5)
	fade_layer = _layer(15)
	flash_rect = _full_rect(Color(1, 1, 1, 0))
	fx_layer.add_child(flash_rect)
	fade_rect = _full_rect(Color(0, 0, 0, 0))
	fade_layer.add_child(fade_rect)


func _layer(n: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.layer = n
	add_child(l)
	return l


func _full_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	return r


func _done_after(t: Tween) -> Signal:
	return t.finished


func _instant() -> Signal:
	var t := create_tween()
	t.tween_interval(0.0)
	return t.finished


func fade_out(seconds := 0.5, color := Color.BLACK) -> Signal:
	is_faded = true
	fade_rect.color = Color(color.r, color.g, color.b, fade_rect.color.a)
	var t := create_tween()
	t.tween_property(fade_rect, "color:a", 1.0, maxf(seconds, 0.01))
	return t.finished


func fade_in(seconds := 0.5) -> Signal:
	is_faded = false
	var t := create_tween()
	t.tween_property(fade_rect, "color:a", 0.0, maxf(seconds, 0.01))
	return t.finished


func set_faded(on: bool) -> void:
	is_faded = on
	if not on:
		set_meta("hold_fade", false)
	fade_rect.color.a = 1.0 if on else 0.0


func tint_screen(color: Color, seconds := 0.5) -> Signal:
	tint_color = color
	var t := create_tween()
	t.tween_property(tint, "color", color, maxf(seconds, 0.01))
	return t.finished


func flash(color: Color, seconds := 0.5) -> Signal:
	flash_rect.color = color
	var t := create_tween()
	t.tween_property(flash_rect, "color:a", 0.0, maxf(seconds, 0.01))
	return t.finished


func shake(power: float, seconds: float) -> Signal:
	shake_power = power
	shake_time = seconds
	var t := create_tween()
	t.tween_interval(maxf(seconds, 0.01))
	return t.finished


func _process(delta: float) -> void:
	if shake_time > 0.0:
		shake_time -= delta
		shake_offset = Vector2(randf_range(-shake_power, shake_power), randf_range(-shake_power, shake_power) * 0.5)
		if shake_time <= 0.0:
			shake_offset = Vector2.ZERO
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.offset = shake_offset


func set_weather(type: String, power := 5) -> void:
	weather_type = type
	if weather_node != null:
		weather_node.queue_free()
		weather_node = null
	if type == "none" or type == "":
		return
	var p := CPUParticles2D.new()
	p.position = Vector2(160, -10)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(200, 4)
	p.amount = 20 + power * 20
	p.lifetime = 2.0
	p.preprocess = 2.0
	match type:
		"rain":
			p.direction = Vector2(-0.3, 1)
			p.spread = 2
			p.initial_velocity_min = 220
			p.initial_velocity_max = 260
			p.gravity = Vector2.ZERO
			p.scale_amount_min = 1
			p.color = Color(0.7, 0.8, 1.0, 0.6)
			var img := Image.create(1, 6, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			p.texture = ImageTexture.create_from_image(img)
		"snow":
			p.direction = Vector2(0.1, 1)
			p.spread = 25
			p.initial_velocity_min = 25
			p.initial_velocity_max = 50
			p.gravity = Vector2.ZERO
			p.color = Color(1, 1, 1, 0.9)
			var img2 := Image.create(2, 2, false, Image.FORMAT_RGBA8)
			img2.fill(Color.WHITE)
			p.texture = ImageTexture.create_from_image(img2)
			p.lifetime = 5.0
			p.preprocess = 5.0
		_:
			p.queue_free()
			return
	weather_layer.add_child(p)
	weather_node = p


# --- pictures -----------------------------------------------------------------------

func show_picture(number: int, texture: Texture2D, pos: Vector2, origin := "top_left", scale_pct := 100.0, opacity := 255) -> void:
	erase_picture(number)
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = origin == "center"
	s.position = pos
	s.scale = Vector2.ONE * scale_pct / 100.0
	s.modulate.a = opacity / 255.0
	s.z_index = number
	pictures_layer.add_child(s)
	pictures[number] = s


func move_picture(number: int, pos: Vector2, scale_pct: float, opacity: int, seconds: float) -> Signal:
	var s: Sprite2D = pictures.get(number)
	var t := create_tween()
	if s == null:
		t.tween_interval(0.0)
		return t.finished
	t.set_parallel(true)
	t.tween_property(s, "position", pos, maxf(seconds, 0.01))
	t.tween_property(s, "scale", Vector2.ONE * scale_pct / 100.0, maxf(seconds, 0.01))
	t.tween_property(s, "modulate:a", opacity / 255.0, maxf(seconds, 0.01))
	return t.finished


func erase_picture(number: int) -> void:
	if pictures.has(number):
		pictures[number].queue_free()
		pictures.erase(number)


func clear_all() -> void:
	# A Fade Out command's "stay faded through transfers" ends with the game it belonged to.
	set_meta("hold_fade", false)
	for n in pictures.keys():
		erase_picture(n)
	set_weather("none")
	tint.color = Color.WHITE
	tint_color = Color.WHITE
	flash_rect.color.a = 0.0
	shake_time = 0.0
	shake_offset = Vector2.ZERO


func to_dict() -> Dictionary:
	var pics := {}
	for n in pictures:
		var s: Sprite2D = pictures[n]
		pics[str(n)] = {"name": s.get_meta("picture_name", ""), "position": [s.position.x, s.position.y], "origin": "center" if s.centered else "top_left", "scale": s.scale.x * 100.0, "opacity": int(s.modulate.a * 255)}
	return {"tint": [tint_color.r, tint_color.g, tint_color.b, tint_color.a], "weather": weather_type, "pictures": pics}
