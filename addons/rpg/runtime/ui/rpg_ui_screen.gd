extends Control
## Shared base for the default UI screens (title, menu, shop, save, battle, ...).
##
## Screens are script-only Controls laid out on the 320x240 base resolution. They read input by
## polling the rpg_* actions and route each press to handle_action(action) where action is one of
## "up", "down", "left", "right", "ok", "cancel". Only the top-most open scene receives input,
## and one press is consumed by one screen only, so opening or closing a sub-screen never lets
## the same press leak into the screen below. Tests drive screens by calling handle_action().
##
## Mouse and touch work the RPG Maker MV/MZ way for every screen (see "mouse and touch" below):
## hovering an entry moves the cursor there, clicking the selected entry is OK, right click is
## Cancel and the wheel is up/down. A screen says what can be pointed at with pointer_targets();
## by default that is the rows of its active list.

const W := 320
const H := 240
const FONT := 11
const SMALL := 9
const ROW := 14
const ACTIONS := ["up", "down", "left", "right", "ok", "cancel"]
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.08
const ListBox := preload("res://addons/rpg/runtime/ui/rpg_ui_list.gd")
## Window-skin text colours (RPG Maker 2000 numbering) used by meaning.
const C_NORMAL := 0
const C_SYSTEM := 1
const C_CRISIS := 4
const C_BAD := 5
const C_GOOD := 9
const FALLBACK_COLOURS := {0: Color.WHITE, 1: Color(0.6, 0.8, 1.0), 3: Color(0.6, 0.6, 0.65), 4: Color(1.0, 0.85, 0.3), 5: Color(1.0, 0.45, 0.45), 9: Color(0.55, 1.0, 0.55)}

## The frame in which some screen last consumed a press (shared by every screen).
static var _consumed_frame := -1

var rpg: Node
## False while the screen waits for something (an animation, a sub-screen, a coroutine).
var input_enabled := true
var _opened_frame := -1
var _held := {}
## Where the mouse last was, in this screen's coordinates (for targets that care where in them).
var pointer_pos := Vector2.ZERO


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_opened_frame = Engine.get_process_frames()
	_build()
	cover_letterbox()


## The whole game screen in this screen's coordinates (see RPGUI.ui_visible_rect): wider or
## taller than W x H when the game's aspect isn't 4:3.
func cover_rect() -> Rect2:
	if rpg and rpg.ui and rpg.ui.has_method("ui_visible_rect"):
		return rpg.ui.ui_visible_rect()
	return Rect2(0, 0, W, H)


## Stretches this screen's full-screen backgrounds (ColorRect / TextureRect children placed at
## 0,0 with size W x H) over the letterbox bands, so no strip of the map shows around them.
func cover_letterbox() -> void:
	var r := cover_rect()
	if r == Rect2(0, 0, W, H):
		return
	for c in get_children():
		if (c is ColorRect or c is TextureRect) and c.position == Vector2.ZERO and c.size == Vector2(W, H):
			c.position = r.position
			c.size = r.size


## Builds the screen's nodes. Override.
func _build() -> void:
	pass


## Called every frame before input is read. Override for animation.
func _update(_delta: float) -> void:
	pass


## One input action ("up", "down", "left", "right", "ok", "cancel"). Override.
func handle_action(_action: String) -> void:
	pass


func _process(delta: float) -> void:
	_update(delta)
	if not input_enabled or not is_top():
		_held.clear()
		return
	var f := Engine.get_process_frames()
	if f == _opened_frame or f == _consumed_frame:
		return
	if rpg and rpg.ui and rpg.ui.message_box and rpg.ui.message_box.has_method("is_open") and rpg.ui.message_box.is_open():
		return
	for a in ACTIONS:
		var act: String = "rpg_" + a
		if not InputMap.has_action(act):
			continue
		var fire := false
		if Input.is_action_just_pressed(act):
			fire = true
			_held[a] = -REPEAT_DELAY
		elif a in ["up", "down", "left", "right"] and Input.is_action_pressed(act):
			_held[a] = float(_held.get(a, -REPEAT_DELAY)) + delta
			if _held[a] >= REPEAT_RATE:
				_held[a] = 0.0
				fire = true
		else:
			_held.erase(a)
		if fire:
			_consumed_frame = f
			handle_action(a)
			return
	# Gamepad Start / Y: closes menus like Cancel (it opens the menu on the map).
	if InputMap.has_action("rpg_menu") and Input.is_action_just_pressed("rpg_menu"):
		_consumed_frame = f
		handle_action("cancel")


## True when no other open scene sits above this one.
func is_top() -> bool:
	if rpg == null or rpg.ui == null:
		return true
	var stack: Array = rpg.ui.scene_stack
	if not stack.has(self):
		return true
	for i in range(stack.size() - 1, -1, -1):
		var n: Node = stack[i]
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			return n == self
	return true


## True when screens should run without waiting for the player (headless tests).
func auto_mode() -> bool:
	return rpg != null and rpg.ui != null and bool(rpg.ui.auto_advance)


# --- mouse and touch (RPG Maker MV/MZ style) ----------------------------------------------

## rpg_* actions held down by a mouse button (a click on a screen with nothing to point at is
## an OK press, so "press a button" waits and message pages react to it): action -> the process
## frame it was pressed in. Released with the button (RPG service), but never in the frame of the
## press: a quick tap delivers press and release together, and the press must still be seen.
static var _injected := {}
static var _release_pending := false


## Presses an rpg_* action for as long as the mouse button is held.
static func inject_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	Input.action_press(action)
	_injected[action] = Engine.get_process_frames()


## Releases the injected actions; one pressed in this very frame is released next frame (see
## release_due, called each frame by the RPG service).
static func release_injected() -> void:
	var now := Engine.get_process_frames()
	for a in _injected.keys():
		if int(_injected[a]) >= now:
			_release_pending = true
			continue
		if InputMap.has_action(a):
			Input.action_release(a)
		_injected.erase(a)


## Finishes a release that had to wait for the frame after the press.
static func release_due() -> void:
	if _release_pending:
		_release_pending = false
		release_injected()


## False when the project turned mouse input off (RPG service pointer_enabled).
func pointer_enabled() -> bool:
	if rpg != null and rpg.has_method("pointer_enabled"):
		return rpg.pointer_enabled()
	return bool(ProjectSettings.get_setting("rpg/input/mouse", true))


## What the mouse can point at in the current mode: [{rect: Rect2 in this screen's coordinates,
## selected: bool, select: Callable}]. Hovering a target that is not selected calls `select`
## (which plays the cursor sound); clicking the selected one is OK (or its own `ok` Callable).
## Default: the visible rows of focus_list(). Override for cursors that are not lists.
func pointer_targets() -> Array:
	var l := focus_list()
	return list_targets(l) if l != null else []


## The list that has the cursor now: the last active, visible list under this screen.
func focus_list() -> Control:
	var found: Control = null
	for n in find_children("*", "Control", true, false):
		if n.get_script() == ListBox and n.active and n.is_visible_in_tree():
			found = n
	return found


## One target per visible row of list `l`.
func list_targets(l: Control) -> Array:
	var out := []
	if l == null or not l.is_visible_in_tree():
		return out
	var first: int = l.top_row * l.columns
	var last: int = mini(l.items.size(), (l.top_row + l.rows_visible()) * l.columns)
	var xf := local_xform(l)
	for i in range(first, last):
		var idx := i
		out.append({"rect": xf * l.item_rect(i), "selected": l.index == i, "select": func() -> void: pointer_select(l, idx)})
	return out


## Transform from `c`'s coordinates to this screen's.
func local_xform(c: CanvasItem) -> Transform2D:
	return get_global_transform().affine_inverse() * c.get_global_transform()


## Moves list `l`'s cursor to row `i` by mouse: cursor sound, then on_pointer_moved(l).
func pointer_select(l: Control, i: int) -> void:
	if l.index == i:
		return
	l.select(i)
	play("cursor")
	on_pointer_moved(l)


## Called after the mouse moved a list's cursor: refresh what depends on it (help text, previews).
func on_pointer_moved(_list: Control) -> void:
	pass


func _target_at(pos: Vector2, targets: Array) -> Dictionary:
	for t in targets:
		if (t.rect as Rect2).has_point(pos):
			return t
	return {}


func _message_open() -> bool:
	return rpg != null and rpg.ui != null and rpg.ui.message_box != null and rpg.ui.message_box.has_method("is_open") and rpg.ui.message_box.is_open()


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton and not event.pressed:
		return
	if not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree() or not is_top():
		return
	if not pointer_enabled() or _message_open():
		return  # the message box above takes the mouse
	# A screen is modal: no click on it reaches the map below.
	get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and rpg != null and "last_device" in rpg:
		rpg.last_device = "mouse"  # the RPG service does not see a click a screen took
	if not input_enabled or Engine.get_process_frames() == _opened_frame:
		return
	pointer_event(make_input_local(event))


## Handles one mouse event in this screen's coordinates (tests may call it directly).
func pointer_event(ev: InputEvent) -> void:
	pointer_pos = ev.position
	if ev is InputEventMouseMotion:
		var hover := _target_at(ev.position, pointer_targets())
		if not hover.is_empty() and not bool(hover.selected):
			hover.select.call()
		return
	if not (ev is InputEventMouseButton) or not ev.pressed:
		return
	match ev.button_index:
		MOUSE_BUTTON_LEFT:
			var targets := pointer_targets()
			if targets.is_empty():
				inject_action("rpg_ok")
				return
			var t := _target_at(ev.position, targets)
			if t.is_empty():
				return
			if bool(t.selected):
				if t.has("ok"):
					_consumed_frame = Engine.get_process_frames()
					t.ok.call()
				else:
					_pointer_action("ok")
			else:
				t.select.call()
		MOUSE_BUTTON_RIGHT:
			if pointer_targets().is_empty():
				inject_action("rpg_cancel")
			else:
				_pointer_action("cancel")
		MOUSE_BUTTON_WHEEL_UP:
			_pointer_action("up")
		MOUSE_BUTTON_WHEEL_DOWN:
			_pointer_action("down")


func _pointer_action(a: String) -> void:
	_consumed_frame = Engine.get_process_frames()
	handle_action(a)


# --- sub-screens -------------------------------------------------------------------------

## Opens another default system (by scene key) above this one. Returns the node or null.
func open_sub(key: String) -> Node:
	if rpg == null or rpg.ui == null:
		return null
	return rpg.ui.open_scene(rpg.ui.scene_path(key))


func close_sub(node: Node) -> void:
	if node != null and rpg and rpg.ui:
		rpg.ui.close_scene(node)


# --- building blocks ---------------------------------------------------------------------

func make_window(rect: Rect2, parent: Node = null) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(p)
	return p


## Makes text that is too long for `width` fit: a smaller font first (down to 70%, not below 7),
## then an ellipsis, rather than cutting the word off mid-letter ("Moonveil Mano").
func fit_label(l: Label, text: String, width: float, font_size: int) -> void:
	# A glyph or two in a tight cell (name input letters, "Lv") is laid out to overhang; an
	# ellipsis there would replace the letter itself.
	if text.strip_edges().length() <= 2:
		l.clip_text = false
		return
	var font: Font = null
	if rpg and rpg.ui and rpg.ui.get("ui_theme") is Theme and rpg.ui.ui_theme.default_font != null:
		font = rpg.ui.ui_theme.default_font
	if font == null:
		font = ThemeDB.fallback_font
	var size := font_size
	var floor_size := maxi(7, int(ceil(font_size * 0.7)))
	while size > floor_size and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	if size != font_size:
		l.add_theme_font_size_override("font_size", size)
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func make_label(parent: Node, pos: Vector2, text: String, font_size := FONT, colour: Variant = null, width := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("line_spacing", 0)
	if colour != null:
		l.add_theme_color_override("font_color", colour)
	if width > 0.0:
		l.size = Vector2(width, font_size + 4)
		l.horizontal_alignment = align
		l.clip_text = true
		fit_label(l, text, width, font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func make_list(parent: Node, rect: Rect2, columns := 1) -> Control:
	var l: Control = ListBox.new()
	l.position = rect.position
	l.size = rect.size
	l.columns = columns
	parent.add_child(l)
	return l


## A gauge: dark track with a coloured fill. Returns the fill rect (resize with set_gauge).
func make_gauge(parent: Node, rect: Rect2, ratio: float, colour: Color) -> ColorRect:
	var track := ColorRect.new()
	track.position = rect.position
	track.size = rect.size
	track.color = Color(0, 0, 0, 0.55)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(track)
	var fill := ColorRect.new()
	fill.position = Vector2(1, 1)
	fill.color = colour
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_meta("full", rect.size.x - 2)
	fill.size = Vector2(0, rect.size.y - 2)
	track.add_child(fill)
	set_gauge(fill, ratio)
	return fill


func set_gauge(fill: ColorRect, ratio: float) -> void:
	fill.size.x = roundf(float(fill.get_meta("full", 10.0)) * clampf(ratio, 0.0, 1.0))


func gradient_texture(top: Color, bottom: Color, mid: Variant = null) -> GradientTexture2D:
	var g := Gradient.new()
	if mid is Color:
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([top, mid, bottom])
	else:
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([top, bottom])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 120
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	return t


func full_rect_texture(tex: Texture2D, parent: Node = null, rect := Rect2(0, 0, W, H)) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # before texture/size, see make_face
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = tex
	tr.position = rect.position
	tr.size = rect.size
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(tr)
	return tr


## A face graphic for an actor (48x48 scaled to `size_px`), or a lettered placeholder.
## A face texture drawn in a size_px square whatever its own size (48 px 2k faces, 144 px MV).
static func face_rect(parent: Node, tex: Texture2D, pos: Vector2, size_px: float) -> TextureRect:
	var tr := TextureRect.new()
	# Expand mode first: with a texture and the default mode, the minimum size is the texture's
	# own (144 px MV faces), and setting `size` smaller is silently ignored.
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = tex
	tr.position = pos
	tr.custom_minimum_size = Vector2(size_px, size_px)
	tr.size = Vector2(size_px, size_px)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if tex.get_width() > size_px else CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr


## `saved` (optional) is a save's {face, face_index, name} for the actor, used instead of the live
## game's look (save/load slots).
func make_face(parent: Node, pos: Vector2, actor_id: String, size_px := 48.0, saved := {}) -> Control:
	var rec := record("actors", actor_id)
	var tex: Texture2D = null
	var face: Variant = rec.get("face", "")
	var sheet := ""
	var idx := int(rec.get("face_index", 0))
	if face is Dictionary:
		sheet = str(face.get("sheet", ""))
		idx = int(face.get("index", idx))
	else:
		sheet = str(face)
	# Change Actor Graphic's face, when the game state has one.
	if saved.has("id"):
		if str(saved.get("face", "")) != "":
			sheet = str(saved.face)
			idx = int(saved.get("face_index", idx))
	elif rpg and rpg.state and rpg.state.has_method("actor_look"):
		var look: Dictionary = rpg.state.actor_look(actor_id)
		if str(look.get("face", "")) != "":
			sheet = str(look.face)
			idx = int(look.get("face_index", idx))
	if sheet != "" and rpg and rpg.ui:
		tex = rpg.ui.face_texture(sheet, idx)
	if tex != null:
		return face_rect(parent, tex, pos, size_px)
	var box := ColorRect.new()
	box.position = pos
	box.size = Vector2(size_px, size_px)
	var h := float(hash(actor_id) % 360) / 360.0
	box.color = Color.from_hsv(h, 0.45, 0.55)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	var l := make_label(box, Vector2.ZERO, actor_name(actor_id).substr(0, 1).to_upper(), int(size_px * 0.5), Color(1, 1, 1, 0.9), size_px, HORIZONTAL_ALIGNMENT_CENTER)
	l.size = Vector2(size_px, size_px)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return box


# --- data helpers ------------------------------------------------------------------------

func play(role: String) -> void:
	if rpg and rpg.audio:
		rpg.audio.play_role(role)


func term(key: String, fallback: String) -> String:
	if rpg and rpg.data:
		var t: String = rpg.data.term(key, fallback)
		return t if t != "" else fallback
	return fallback


func record(type: String, id: String) -> Dictionary:
	if rpg == null or rpg.data == null or id == "":
		return {}
	return rpg.data.record(type, id)


func currency() -> String:
	if rpg and rpg.data:
		return rpg.data.currency()
	return "G"


func actor_name(actor_id: String) -> String:
	var b: Variant = rpg.state.actors.get(actor_id) if rpg and rpg.state else null
	if b is Object and "name" in b and str(b.name) != "":
		return str(b.name)
	return str(record("actors", actor_id).get("name", actor_id))


func party() -> Array:
	return rpg.state.party_battlers() if rpg and rpg.state else []


func rules() -> Object:
	return rpg.rules if rpg else null


func life_res() -> String:
	return rules().life_resource() if rules() else "hp"


## Resource ids in display order (e.g. ["hp", "sp"]).
func resource_ids() -> Array:
	var out := []
	if rules():
		for r in rules().resources():
			out.append(str(r.get("id", "")))
	return out if not out.is_empty() else ["hp", "sp"]


func res_label(res_id: String) -> String:
	if rules():
		for r in rules().resources():
			if str(r.get("id", "")) == res_id:
				return term(res_id, str(r.get("label", res_id.to_upper())))
	return term(res_id, res_id.to_upper())


func stat_label(stat_id: String) -> String:
	if rules():
		for s in rules().stats():
			if str(s.get("id", "")) == stat_id:
				return term(stat_id, str(s.get("short", s.get("label", stat_id.to_upper()))))
	return term(stat_id, stat_id.to_upper())


func max_res(b: Object, res_id: String) -> int:
	return int(rules().max_resource(b, res_id)) if rules() else int(b.resources.get(res_id, 0))


## Text colour `i` from the System graphic, or a readable default without one.
func colour(i: int) -> Color:
	var n := "text_%d" % i
	var t: Theme = rpg.ui.ui_theme if rpg and rpg.ui and "ui_theme" in rpg.ui else null
	if t != null and t.has_meta("rpg_system_texture") and has_theme_color(n, "RPGWindow"):
		return get_theme_color(n, "RPGWindow")
	return FALLBACK_COLOURS.get(i, Color.WHITE)


func system_colour() -> Color:
	return colour(1)


## Display colour for a battler's name: knocked out, in crisis (< 1/4 life) or normal.
func status_colour(b: Object) -> Color:
	if b.is_dead():
		return colour(C_BAD)
	var m := max_res(b, life_res())
	if m > 0 and b.get_resource(life_res()) * 4 <= m:
		return colour(C_CRISIS)
	return colour(0)


func state_names(b: Object) -> String:
	var names := []
	for s in b.states:
		names.append(str(record("states", s.id).get("name", s.id)))
	return ", ".join(PackedStringArray(names))


## Icon of a database record for a list entry ({"icon": record_icon(rec)}): null when the
## record has none or System "show_icons" is off.
func record_icon(rec: Dictionary) -> Texture2D:
	if rpg == null or rpg.data == null or not RPGIcons.enabled(rpg.data):
		return null
	return RPGIcons.for_record(rec)


## A battler's states at `pos` in `width`: each state's icon and name when they all fit, else the
## icons alone (a state without an icon keeps its name). A single state whose name does not fit
## beside its icon shows the name alone, so "Knocked out" stays readable in a narrow column.
## With icons off (or no state has one) this is the plain names label, as before.
## Returns the label or the row (empty for no states).
func make_states(parent: Node, pos: Vector2, b: Object, width: float, font_size := SMALL, colour: Variant = null) -> Control:
	var recs := []
	for s in b.states:
		recs.append(record("states", str(s.id)).merged({"id": str(s.id)}))
	var icons := []
	for rec in recs:
		icons.append(record_icon(rec))
	if icons.all(func(t: Variant) -> bool: return t == null):
		return make_label(parent, pos, state_names(b), font_size, colour, width)
	var sz := float(ListBox.ICON)
	var names := recs.map(func(r: Dictionary) -> String: return str(r.get("name", r.id)))
	var full := 0.0
	for i in recs.size():
		full += (sz + 1 if icons[i] != null else 0.0) + _text_w(names[i], font_size) + 4
	var with_names := full <= width
	if recs.size() == 1 and not with_names:
		return make_label(parent, pos, names[0], font_size, colour, width)
	var row := Control.new()
	row.position = pos
	row.size = Vector2(width, sz)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var x := 0.0
	for i in recs.size():
		if x >= width:
			break
		if icons[i] != null:
			var tr := TextureRect.new()
			tr.texture = icons[i]
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.position = Vector2(x, 1)
			tr.size = Vector2(sz, sz)
			tr.tooltip_text = names[i]
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
			x += sz + 1
		if with_names or icons[i] == null:
			var w := minf(_text_w(names[i], font_size) + 2, width - x)
			if w > 6:
				make_label(row, Vector2(x, 0), names[i], font_size, colour, w)
			x += w + 2
	return row


func _text_w(text: String, font_size: int) -> float:
	var font: Font = null
	if rpg and rpg.ui and rpg.ui.get("ui_theme") is Theme and rpg.ui.ui_theme.default_font != null:
		font = rpg.ui.ui_theme.default_font
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## "Music" entries in system.json may be a file name or a sound dictionary.
func system_music(key: String) -> Variant:
	if rpg == null or rpg.data == null:
		return null
	var m: Variant = rpg.data.system.get("music", {})
	if not (m is Dictionary):
		return null
	var v: Variant = m.get(key)
	if v is String:
		return {"file": v} if v != "" else null
	if v is Dictionary and not v.is_empty():
		return v
	return null


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
