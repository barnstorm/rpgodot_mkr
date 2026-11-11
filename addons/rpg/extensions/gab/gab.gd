extends "res://addons/rpg/runtime/rpg_extension.gd"
## Gab window (kit plugin "gab"): short lines in a strip at the top (or bottom) of the screen that
## slide in, stay for a while (base seconds + seconds per letter) and fade out. They never stop
## the player or an event. Gabs queue up and play one after another; with anti-repeat on, a gab
## equal to the one showing or waiting is skipped. The strip sits on the "hud" layer, above menus,
## messages and battles, so battle code can call RPG.extension("gab").show_gab("...") too.
## Commands: Show gab, Clear gabs, Wait for gabs.

signal gab_shown(text: String)
signal gab_finished(text: String)
## The queue is empty again.
signal all_finished()

const H := 32
const FACE := 24

## Gabs waiting: [{text, face?, name?, sound?, switch?}]
var queue: Array = []
## The gab showing ({} when none).
var current: Dictionary = {}
var phase := ""
var _t := 0.0
var _hold := 0.0
var _window: Panel = null
var _x0 := 10.0
## Text of every gab shown, newest last (tests).
var shown_log: Array = []


## Queues a gab. opts: face {sheet, index}, name, sound (a sound Dictionary; null = the
## setting's), switch (turned ON when it has faded). Returns false when it was skipped.
func show_gab(text: String, opts: Dictionary = {}) -> bool:
	text = text.strip_edges()
	if text == "":
		return false
	if bool(setting("anti_repeat", true)):
		if str(current.get("text", "")) == text:
			return false
		for g in queue:
			if str(g.get("text", "")) == text:
				return false
	var g2: Dictionary = opts.duplicate()
	g2["text"] = text
	queue.append(g2)
	while queue.size() > maxi(1, int(setting("max_queue", 6))):
		queue.pop_front()
	if current.is_empty():
		_next()
	return true


## Removes the gab showing and every gab waiting.
func clear_gabs() -> void:
	queue.clear()
	var was := not current.is_empty()
	current = {}
	phase = ""
	_free_window()
	if was:
		all_finished.emit()


func is_busy() -> bool:
	return not current.is_empty() or not queue.is_empty()


func on_new_game() -> void:
	clear_gabs()


func on_game_loaded() -> void:
	clear_gabs()


func on_title_shown() -> void:
	clear_gabs()


func _next() -> void:
	_free_window()
	if queue.is_empty():
		current = {}
		phase = ""
		all_finished.emit()
		return
	current = queue.pop_front()
	_build_window(current)
	phase = "in"
	_t = 0.0
	var plain := RPGText.strip_codes(str(current.text)).length()
	_hold = float(setting("base_seconds", 1.6)) + float(setting("per_char", 0.04)) * plain
	var snd: Variant = current.get("sound")
	if not (snd is Dictionary) or str(snd.get("file", "")) == "":
		snd = setting("sound", {})
	if snd is Dictionary and str(snd.get("file", "")) != "" and rpg.audio != null:
		rpg.audio.play_se(snd)
	shown_log.append(str(current.text))
	gab_shown.emit(str(current.text))


func _process(delta: float) -> void:
	if current.is_empty() or _window == null or not is_instance_valid(_window):
		return
	_t += delta
	var fade := maxf(0.001, float(setting("fade", 0.3)))
	match phase:
		"in":
			var a := clampf(_t / fade, 0.0, 1.0)
			_window.modulate.a = a
			_window.position.x = lerpf(_x0 - 16.0, _x0, a)
			if _t >= fade:
				phase = "hold"
				_t = 0.0
		"hold":
			if _t >= _hold:
				phase = "out"
				_t = 0.0
		"out":
			_window.modulate.a = 1.0 - clampf(_t / fade, 0.0, 1.0)
			if _t >= fade:
				_finish()


func _finish() -> void:
	var done := current
	var sw := str(done.get("switch", ""))
	if sw != "" and rpg.state != null:
		rpg.state.set_switch(sw, true)
	gab_finished.emit(str(done.get("text", "")))
	_next()


func _layer() -> Control:
	var l: Variant = rpg.map_overlay_layer("hud") if rpg.has_method("map_overlay_layer") else null
	if l is Control:
		return l
	# No game root (a test without one): a layer of our own.
	var own := get_node_or_null("OwnLayer")
	if own == null:
		var cl := CanvasLayer.new()
		cl.name = "OwnLayer"
		cl.layer = 21
		add_child(cl)
		var c := Control.new()
		c.size = Vector2(320, 240)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(c)
		own = cl
	return own.get_child(0)


func _build_window(g: Dictionary) -> void:
	var layer := _layer()
	var w := Panel.new()
	w.name = "Gab"
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rpg.ui != null and rpg.ui.get("ui_theme") is Theme:
		w.theme = rpg.ui.ui_theme
	w.self_modulate.a = clampf(float(setting("opacity", 85)) / 100.0, 0.0, 1.0)
	var y := 4.0 if str(setting("position", "top")) == "top" else 240.0 - H - 4.0
	_x0 = 10.0
	w.position = Vector2(_x0 - 16.0, y)
	w.size = Vector2(300, H)
	w.modulate.a = 0.0
	layer.add_child(w)
	var left := 6.0
	var face: Variant = g.get("face")
	if face is Dictionary and str(face.get("sheet", "")) != "" and rpg.ui != null:
		var tex: Texture2D = rpg.ui.face_texture(str(face.sheet), int(face.get("index", 0)))
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.position = Vector2(4, (H - FACE) / 2.0)
			tr.size = Vector2(FACE, FACE)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			w.add_child(tr)
			left = FACE + 9.0
	var label := RichTextLabel.new()
	label.name = "Text"
	label.bbcode_enabled = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 10)
	label.add_theme_constant_override("line_separation", 0)
	label.position = Vector2(left, 3)
	label.size = Vector2(300 - left - 6, H - 4)
	var bb := ""
	var who := str(g.get("name", ""))
	if who != "":
		bb += "[color=#8ab4ff]%s:[/color] " % RPGText.expand_plain(who, rpg).replace("[", "[lb]")
	bb += str(RPGText.expand(str(g.text), rpg).bbcode)
	label.text = bb
	w.add_child(label)
	_window = w


func _free_window() -> void:
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
	_window = null


## The strip showing now, or null (tests and screenshots).
func window() -> Panel:
	return _window if _window != null and is_instance_valid(_window) else null
