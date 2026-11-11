class_name RPGMessageBox
extends Control
## Default message box: face, name, typewriter text with text codes, choices, number input and
## a gold window. Replace it by pointing project.json "scenes.message_box" at a scene whose root
## implements the same methods and signals.
##
## Input as in RPG Maker MV: OK (or a click) while text types shows the rest of the page at once,
## the next one closes it, silently unless System "message_advance_sound" names a sound role.
## Choices and the number dial repeat while a direction is held. Mouse: hover/click choices
## (right click cancels when allowed); click a digit to select it, click it again above or below
## its middle (or use the wheel) to change it, click elsewhere to enter the number.

signal closed()
signal choice_made(index: int)
signal number_entered(value: int)

const BOX_H := 76
const FACE := 48
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.08

var rpg: Node
var panel: Panel
var face_rect: TextureRect
var name_label: Label
var text_label: RichTextLabel
var choice_panel: Panel
var choice_box: VBoxContainer
var number_label: Label
var gold_panel: Panel
var gold_label: Label
var arrow: Label

var mode := ""            # "", "text", "choices", "number"
var chars_per_sec := 40.0
var _visible_f := 0.0
var _waits: Array = []
var _wait_left := 0.0
var _await_key := false
var _choices: Array = []
var _choice_index := 0
var _cancel_index := -1
var _digits := 1
var _number := 0
var _number_pos := 0
var _blink := 0.0
## OK while typing: the rest of the page (up to a wait code) appears at once.
var _show_fast := false
## Hold-to-repeat state per direction action (see _repeat).
var _held := {}
## A mouse click to act on in this frame's _process (text mode).
var _clicked := false
var closed_frame := -1     # process frame of the last press that closed text/choices/number
## Extension hooks: timed actions from text codes ([{at, call}]) and characters reported so far
## (RPG.message_char).
var _actions: Array = []
var _revealed := 0
var _plain := ""
## Choices that can't be picked (Show Choices "enable" switch): index -> true.
var _disabled: Dictionary = {}
## Tests: when true, text closes at once and choices pick `auto_choice`.
var auto_advance := false
var auto_choice := 0


func _init() -> void:
	name = "MessageBox"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	panel = Panel.new()
	panel.position = Vector2(0, 240 - BOX_H)
	panel.size = Vector2(320, BOX_H)
	add_child(panel)
	face_rect = TextureRect.new()
	face_rect.position = Vector2(8, (BOX_H - FACE) / 2.0)
	face_rect.size = Vector2(FACE, FACE)
	face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # VX/MV faces (96/144 px) fit the 48 px slot
	face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(face_rect)
	name_label = Label.new()
	name_label.position = Vector2(8, -14)
	name_label.add_theme_font_size_override("font_size", 10)
	panel.add_child(name_label)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.scroll_active = false
	text_label.fit_content = false
	text_label.add_theme_font_size_override("normal_font_size", 11)
	text_label.add_theme_constant_override("line_separation", 1)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text_label)
	arrow = Label.new()
	arrow.text = "▼"
	arrow.add_theme_font_size_override("font_size", 8)
	arrow.position = Vector2(304, BOX_H - 14)
	panel.add_child(arrow)
	choice_panel = Panel.new()
	choice_panel.visible = false
	add_child(choice_panel)
	choice_box = VBoxContainer.new()
	choice_box.position = Vector2(8, 6)
	choice_box.add_theme_constant_override("separation", 0)
	choice_panel.add_child(choice_box)
	number_label = Label.new()
	number_label.visible = false
	number_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(number_label)
	gold_panel = Panel.new()
	gold_panel.position = Vector2(224, 4)
	gold_panel.size = Vector2(92, 24)
	gold_panel.visible = false
	add_child(gold_panel)
	gold_label = Label.new()
	gold_label.position = Vector2(6, 3)
	gold_label.size = Vector2(80, 18)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", 11)
	gold_panel.add_child(gold_label)
	visible = false


func is_open() -> bool:
	return mode != ""


## Shows a message. params: text, face {sheet, index}, name, position (bottom|middle|top),
## background (window|dim|transparent), gold_window (bool).
func open_text(params: Dictionary) -> void:
	_layout(params)
	var parsed := RPGText.expand(str(params.get("text", "")), rpg, {"params": params})
	text_label.text = parsed.bbcode
	text_label.visible_characters = 0
	_visible_f = 0.0
	_waits = parsed.waits
	_actions = parsed.get("actions", [])
	_revealed = 0
	_plain = text_label.get_parsed_text()
	_wait_left = 0.0
	_await_key = false
	_show_fast = false
	mode = "text"
	visible = true
	if rpg and rpg.data:
		var speed: float = float(rpg.data.system.get("text_speed", 40))
		chars_per_sec = speed if speed > 0 else 1000.0
	if rpg != null and rpg.has_signal("message_opened"):
		var p := params.duplicate()
		p["flags"] = parsed.get("flags", {})
		rpg.message_opened.emit(p)
	_reveal_to(0, false)
	if auto_advance:
		_finish_text.call_deferred()


## Fires the timed actions and RPG.message_char for characters up to `count` (exclusive).
func _reveal_to(count: int, instant: bool) -> void:
	var total := text_label.get_total_character_count()
	count = mini(count, total)
	while true:
		for a in _actions:
			if int(a.at) == _revealed and a.get("call") is Callable:
				var c: Callable = a.call
				a.erase("call")
				if c.is_valid():
					c.call()
		if _revealed >= count:
			break
		if rpg != null and rpg.has_signal("message_char"):
			rpg.message_char.emit(_plain[_revealed] if _revealed < _plain.length() else "", _revealed, instant)
		_revealed += 1


func _layout(params: Dictionary) -> void:
	var pos: String = params.get("position", "bottom")
	var y := 240 - BOX_H
	if pos == "top":
		y = 0
	elif pos == "middle":
		y = (240 - BOX_H) / 2
	panel.position.y = y
	match params.get("background", "window"):
		"transparent":
			panel.self_modulate.a = 0.0
		"dim":
			panel.self_modulate = Color(0, 0, 0, 0.6)
		_:
			panel.self_modulate = Color.WHITE
	var face: Variant = params.get("face")
	var tex: Texture2D = null
	if face is Dictionary and str(face.get("sheet", "")) != "" and rpg and rpg.ui:
		tex = rpg.ui.face_texture(face.sheet, int(face.get("index", 0)))
	face_rect.texture = tex
	face_rect.visible = tex != null
	face_rect.size = Vector2(FACE, FACE)
	# Large faces are drawn smaller than the source: smooth them; 48 px faces stay crisp.
	face_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if tex != null and tex.get_width() > FACE else CanvasItem.TEXTURE_FILTER_NEAREST
	var left := 8 + (FACE + 8 if tex != null else 0)
	text_label.position = Vector2(left, 6)
	text_label.size = Vector2(320 - left - 10, BOX_H - 12)
	var nm: String = str(params.get("name", ""))
	name_label.text = nm
	name_label.visible = nm != ""
	gold_panel.visible = bool(params.get("gold_window", false))
	if gold_panel.visible:
		gold_panel.position.y = 4 if y > 60 else 240 - 28
		_update_gold()
	panel.visible = true


func _update_gold() -> void:
	if rpg and rpg.state:
		gold_label.text = "%d %s" % [rpg.state.gold, rpg.data.currency()]


## Shows choices (the message box may stay open above them). Emits choice_made(index), or
## choice_made(cancel_index) on cancel when cancel_index >= 0. params.disabled: indices shown
## greyed out that buzz instead of being picked.
func open_choices(labels: Array, params: Dictionary = {}) -> void:
	_choices = labels
	_choice_index = clampi(int(params.get("default", 0)), 0, maxi(labels.size() - 1, 0))
	_cancel_index = int(params.get("cancel_index", -1))
	_disabled.clear()
	for d in params.get("disabled", []):
		_disabled[int(d)] = true
	for c in choice_box.get_children():
		choice_box.remove_child(c)  # out now: queue_free alone leaves it a child until the frame ends
		c.queue_free()
	var w := 60.0
	for l in labels:
		var lab := Label.new()
		lab.text = "  " + RPGText.expand_plain(str(l), rpg)
		lab.add_theme_font_size_override("font_size", 11)
		choice_box.add_child(lab)
		w = maxf(w, 12 + lab.text.length() * 6.5)
	var h := 12 + labels.size() * 15
	choice_panel.size = Vector2(minf(w + 16, 300), h)
	var base_y := panel.position.y if mode == "text" or panel.visible else 240
	choice_panel.position = Vector2(320 - choice_panel.size.x - 4, base_y - h - 2)
	if choice_panel.position.y < 0:
		choice_panel.position.y = panel.position.y + BOX_H + 2
	choice_panel.visible = true
	visible = true
	mode = "choices"
	_held.clear()
	_refresh_choice_cursor()
	if auto_advance:
		_pick.call_deferred(clampi(auto_choice, 0, labels.size() - 1))


func _refresh_choice_cursor() -> void:
	var i := 0
	for c in choice_box.get_children():
		if c is Label:
			c.text = ("▶ " if i == _choice_index else "  ") + RPGText.expand_plain(str(_choices[i]), rpg)
			c.modulate = Color(1, 1, 0.6) if i == _choice_index else Color.WHITE
			if _disabled.has(i):
				c.modulate = Color(0.6, 0.6, 0.65, 0.9) if i == _choice_index else Color(0.55, 0.55, 0.6, 0.7)
			i += 1


## Picks a choice unless it is disabled (then the buzzer plays).
func _try_pick(i: int) -> void:
	if _disabled.has(i):
		_play("buzzer")
		return
	_play("decision")
	_pick(i)


func open_number(digits: int, initial := 0) -> void:
	_digits = clampi(digits, 1, 8)
	_number = clampi(initial, 0, int(pow(10, _digits)) - 1)
	_number_pos = _digits - 1
	_held.clear()
	number_label.visible = true
	number_label.position = Vector2(200, BOX_H - 30)
	visible = true
	panel.visible = true
	mode = "number"
	_refresh_number()
	if auto_advance:
		_submit_number.call_deferred()


func _refresh_number() -> void:
	var s := str(_number).pad_zeros(_digits)
	var shown := ""
	for i in s.length():
		shown += ("[%s]" % s[i]) if i == _number_pos else (" %s " % s[i])
	number_label.text = shown


func force_close() -> void:
	mode = ""
	visible = false
	choice_panel.visible = false
	number_label.visible = false
	gold_panel.visible = false


## Hides the text window but keeps the box alive (between consecutive messages).
func hide_box() -> void:
	force_close()


func _process(delta: float) -> void:
	if mode == "":
		_clicked = false
		return
	_blink += delta
	arrow.visible = mode == "text" and _text_done() and int(_blink * 3) % 2 == 0
	if gold_panel.visible:
		_update_gold()
	match mode:
		"text":
			_process_text(delta)
		"choices":
			_process_choices(delta)
		"number":
			_process_number(delta)
	_clicked = false


func _text_done() -> bool:
	return text_label.visible_characters < 0 or text_label.visible_characters >= text_label.get_total_character_count()


## OK pressed this frame by key, pad or mouse click.
func _ok_pressed() -> bool:
	return _clicked or Input.is_action_just_pressed("rpg_ok")


func _process_text(delta: float) -> void:
	var ok := _ok_pressed()
	if not _text_done():
		if _wait_left > 0.0:
			_wait_left -= delta
			if ok:
				_wait_left = 0.0
			return
		if _await_key:
			if ok:
				_await_key = false
			return
		if ok:
			_show_fast = true
		var fast := Input.is_action_pressed("rpg_ok") or Input.is_action_pressed("rpg_cancel")
		_visible_f += delta * chars_per_sec * (4.0 if fast else 1.0)
		if _show_fast:
			_visible_f = float(text_label.get_total_character_count())
		var target := int(_visible_f)
		for w in _waits:
			if w.at > text_label.visible_characters and w.at <= target:
				target = w.at
				_visible_f = float(target)
				if w.has("key"):
					_await_key = true
				else:
					_wait_left = w.seconds
				w.at = -1
				break
		text_label.visible_characters = target
		_reveal_to(target, _show_fast)
		if _text_done():
			text_label.visible_characters = -1
		return
	if ok:
		_finish_text()


func _finish_text() -> void:
	_reveal_to(text_label.get_total_character_count(), true)
	text_label.visible_characters = -1
	mode = ""
	closed_frame = Engine.get_process_frames()
	var se := advance_sound()
	if se != "":
		_play(se)
	if rpg != null and rpg.has_signal("message_closed"):
		rpg.message_closed.emit()
	closed.emit()


## Sound role played when a page closes: none, as in RPG Maker MV, unless System
## "message_advance_sound" (or the project profile's) names one (true means "decision").
func advance_sound() -> String:
	if rpg == null or rpg.data == null:
		return ""
	var v: Variant = rpg.data.system.get("message_advance_sound", rpg.data.profile.get("message_advance_sound", false))
	if v is bool:
		return "decision" if v else ""
	return str(v) if v != null else ""


## True once when `action` is pressed, then again every REPEAT_RATE seconds after REPEAT_DELAY
## while it is held (as menu screens do).
func _repeat(action: String, delta: float) -> bool:
	if not InputMap.has_action(action):
		return false
	if Input.is_action_just_pressed(action):
		_held[action] = -REPEAT_DELAY
		return true
	if Input.is_action_pressed(action):
		_held[action] = float(_held.get(action, -REPEAT_DELAY)) + delta
		if _held[action] >= REPEAT_RATE:
			_held[action] = 0.0
			return true
		return false
	_held.erase(action)
	return false


func _process_choices(delta: float) -> void:
	if _repeat("rpg_down", delta):
		_move_choice(1)
	elif _repeat("rpg_up", delta):
		_move_choice(-1)
	elif Input.is_action_just_pressed("rpg_ok"):
		_try_pick(_choice_index)
	elif Input.is_action_just_pressed("rpg_cancel") and _cancel_index >= 0:
		_play("cancel")
		_pick(_cancel_index)


func _move_choice(d: int) -> void:
	if _choices.is_empty():
		return
	_choice_index = posmod(_choice_index + d, _choices.size())
	_play("cursor")
	_refresh_choice_cursor()


func _pick(i: int) -> void:
	mode = ""
	closed_frame = Engine.get_process_frames()
	choice_panel.visible = false
	choice_made.emit(i)


## Number dial (MV's Window_NumberInput): up/down change the digit under the cursor (9 wraps
## to 0), left/right move the cursor and never change a digit.
func _process_number(delta: float) -> void:
	if _repeat("rpg_up", delta):
		change_digit(1)
	elif _repeat("rpg_down", delta):
		change_digit(-1)
	elif _repeat("rpg_left", delta):
		move_digit(-1)
	elif _repeat("rpg_right", delta):
		move_digit(1)
	elif Input.is_action_just_pressed("rpg_ok"):
		_play("decision")
		_submit_number()


## Adds `d` (+1 / -1) to the digit under the cursor, wrapping 9 <-> 0.
func change_digit(d: int) -> void:
	var s := str(_number).pad_zeros(_digits)
	s[_number_pos] = str(posmod(s[_number_pos].to_int() + d, 10))
	_number = s.to_int()
	_play("cursor")
	_refresh_number()


## Moves the cursor `d` digits (wrapping at the ends, as in MV).
func move_digit(d: int) -> void:
	if _digits <= 1:
		return
	_number_pos = posmod(_number_pos + d, _digits)
	_play("cursor")
	_refresh_number()


# --- mouse ---------------------------------------------------------------------------------

func _pointer_enabled() -> bool:
	if rpg != null and rpg.has_method("pointer_enabled"):
		return rpg.pointer_enabled()
	return true


func _input(event: InputEvent) -> void:
	if mode == "" or not is_visible_in_tree():
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if (event is InputEventMouseButton and not event.pressed) or not _pointer_enabled():
		return
	get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and rpg != null and "last_device" in rpg:
		rpg.last_device = "mouse"
	pointer_event(make_input_local(event))


## One mouse event in the message box's coordinates (tests may call it directly).
func pointer_event(ev: InputEvent) -> void:
	var button: int = ev.button_index if ev is InputEventMouseButton and ev.pressed else MOUSE_BUTTON_NONE
	match mode:
		"text":
			if button == MOUSE_BUTTON_LEFT:
				_clicked = true
		"choices":
			var i := _choice_at(ev.position)
			if ev is InputEventMouseMotion:
				if i >= 0 and i != _choice_index:
					_move_choice(i - _choice_index)
			elif button == MOUSE_BUTTON_LEFT and i >= 0:
				if i == _choice_index:
					_try_pick(i)
				else:
					_move_choice(i - _choice_index)
			elif button == MOUSE_BUTTON_RIGHT and _cancel_index >= 0:
				_play("cancel")
				_pick(_cancel_index)
			elif button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
				_move_choice(-1 if button == MOUSE_BUTTON_WHEEL_UP else 1)
		"number":
			if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
				change_digit(1 if button == MOUSE_BUTTON_WHEEL_UP else -1)
			elif button == MOUSE_BUTTON_LEFT:
				var d := _digit_at(ev.position)
				if d < 0:
					_play("decision")
					_submit_number()
				elif d != _number_pos:
					move_digit(d - _number_pos)
				else:
					var r := digit_rect(d)
					change_digit(1 if ev.position.y < r.get_center().y else -1)


func _local_rect(c: Control, r: Rect2) -> Rect2:
	return (get_global_transform().affine_inverse() * c.get_global_transform()) * r


## Index of the choice under `pos` (message box coordinates), or -1.
func _choice_at(pos: Vector2) -> int:
	var i := 0
	for c in choice_box.get_children():
		if c is Label:
			var r := _local_rect(c, Rect2(Vector2.ZERO, c.size))
			r.size.x = maxf(r.size.x, choice_panel.size.x - 16)
			if r.has_point(pos):
				return i
			i += 1
	return -1


## Rectangle of digit `i` of the number dial, in message box coordinates.
func digit_rect(i: int) -> Rect2:
	var f: Font = number_label.get_theme_font("font")
	var fs: int = number_label.get_theme_font_size("font_size")
	var t := number_label.text
	var x0 := f.get_string_size(t.substr(0, i * 3), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x1 := f.get_string_size(t.substr(0, i * 3 + 3), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := maxf(number_label.size.y, float(fs) + 4.0)
	return _local_rect(number_label, Rect2(x0, -4, x1 - x0, h + 8))


func _digit_at(pos: Vector2) -> int:
	for i in _digits:
		if digit_rect(i).has_point(pos):
			return i
	return -1


func _submit_number() -> void:
	mode = ""
	closed_frame = Engine.get_process_frames()
	number_label.visible = false
	number_entered.emit(_number)


func _play(role: String) -> void:
	if rpg and rpg.audio:
		rpg.audio.play_role(role)
