@tool
extends VBoxContainer
## Enemy groups: a visual troop editor, like RPG Maker's. The battle screen is drawn as the
## default battle scene draws it (addons/rpg/runtime/ui/battle/battle_scene.gd: 320x240, the
## enemy field is the top 160 pixels, each enemy's battler is centred on its position and kept
## above the party windows, hue applied). Click an enemy to select it, drag to move it (positions
## snap to whole pixels), Delete removes it, arrow keys nudge it. "Add enemy" and "Auto-arrange"
## work on the same members array as the list below, which stays in sync.
##
## Used by RPGFormBuilder for the field kind "troop_members" (loaded by path, no class_name):
##   var te = load(".../rpg_troop_editor.gd").new()
##   te.setup(field, data, registry, options)
##   te.set_value(members); te.value_changed.connect(...)

signal value_changed(value: Variant)
## "Autoname" was pressed: the host sets the group's name (RPGFormBuilder sets the "name" field).
signal autoname_requested(group_name: String)

const BATTLE_W := 320
const BATTLE_H := 240
## battle_scene.gd FIELD_H: enemies stand above the party windows.
const FIELD_H := 160
const SCALE := 2
## Placeholder size when an enemy has no battler image (battle_scene.gd _silhouette).
const SILHOUETTE := Vector2(40, 32)

## Backdrop shown behind the enemies (editor preview only, never saved). "" = the default
## gradient the battle scene uses when no backdrop is set. Kept while the editor runs.
static var preview_backdrop: Variant = null

var data: RPGProjectData
var registry: RPGCommandRegistry
var field: Dictionary = {}
var members: Array = []
var selected := -1

var canvas: Control
var list: RPGListEditor
var enemy_picker: RPGRefPicker
var _bg_pick: OptionButton
var _remove_button: Button
var _info: Label
var _drag: Dictionary = {}
var _sky: GradientTexture2D
var _ground: GradientTexture2D
var _tex_cache: Dictionary = {}


func setup(p_field: Dictionary, p_data: RPGProjectData, p_registry: RPGCommandRegistry = null, p_options: Dictionary = {}) -> void:
	field = p_field
	data = p_data
	registry = p_registry
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in get_children():
		c.queue_free()
	if preview_backdrop == null:
		preview_backdrop = str(data.system.get("battle_background", "")) if data != null else ""
	_sky = _gradient(Color(0.22, 0.38, 0.72), Color(0.18, 0.32, 0.14), Color(0.62, 0.78, 0.95))
	_ground = _gradient(Color(0.36, 0.55, 0.25), Color(0.16, 0.28, 0.1))
	# Toolbar.
	var bar := HFlowContainer.new()
	add_child(bar)
	enemy_picker = RPGRefPicker.new("enemy", data, [], false)
	enemy_picker.custom_minimum_size.x = 150
	enemy_picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var first: Array = data.records("enemies") if data != null else []
	if not first.is_empty() and first[0] is Dictionary:
		enemy_picker.set_value(str(first[0].get("id", "")))
	bar.add_child(enemy_picker)
	var add := Button.new()
	add.text = "+ Add enemy"
	add.tooltip_text = "Add the chosen enemy to the group"
	add.pressed.connect(func(): add_enemy(str(enemy_picker.get_value())))
	bar.add_child(add)
	_remove_button = Button.new()
	_remove_button.text = "Remove"
	_remove_button.tooltip_text = "Remove the selected enemy (Delete)"
	_remove_button.pressed.connect(remove_selected)
	bar.add_child(_remove_button)
	var arrange := Button.new()
	arrange.text = "Auto-arrange"
	arrange.tooltip_text = "Spread the enemies evenly across the battle field"
	arrange.pressed.connect(auto_arrange)
	bar.add_child(arrange)
	var auto := Button.new()
	auto.text = "Autoname"
	auto.tooltip_text = "Name the group after its enemies, e.g. \"Slime x2, Goblin\""
	auto.pressed.connect(func(): autoname_requested.emit(autoname(members, data)))
	bar.add_child(auto)
	var bl := Label.new()
	bl.text = "  Backdrop:"
	bar.add_child(bl)
	_bg_pick = OptionButton.new()
	_bg_pick.tooltip_text = "Only for this preview. The battle uses the map's battle background."
	_bg_pick.add_item("(default sky)")
	_bg_pick.set_item_metadata(0, "")
	for n in RPGResourcePicker.list_names("backdrop"):
		_bg_pick.add_item(str(n))
		_bg_pick.set_item_metadata(_bg_pick.item_count - 1, str(n))
		if str(n) == str(preview_backdrop):
			_bg_pick.select(_bg_pick.item_count - 1)
	_bg_pick.item_selected.connect(func(i: int):
		preview_backdrop = str(_bg_pick.get_item_metadata(i))
		canvas.queue_redraw())
	bar.add_child(_bg_pick)
	# The battle screen.
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(frame)
	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(BATTLE_W * SCALE, BATTLE_H * SCALE)
	canvas.clip_contents = true
	canvas.focus_mode = Control.FOCUS_ALL
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_canvas_input)
	frame.add_child(canvas)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.modulate = Color(1, 1, 1, 0.75)
	add_child(_info)
	# The same members as a list (enemy, position, appears later).
	list = RPGListEditor.new(field, data, registry, p_options)
	list.value_changed.connect(_on_list_changed)
	add_child(list)
	_update_info()


func set_value(v: Variant) -> void:
	members = RPGJson.deep_copy(v) if v is Array else []
	selected = clampi(selected, -1, members.size() - 1)
	_drag = {}
	if list != null:
		list.set_value(members)
	_update_info()
	if canvas != null:
		canvas.queue_redraw()


func get_value() -> Variant:
	return RPGJson.deep_copy(members)


# --- operations (also used by tests) ----------------------------------------------------------

## RPG Maker's Autoname: enemy names in order of first appearance, "x2" for repeats.
static func autoname(p_members: Array, p_data: RPGProjectData) -> String:
	var order: Array = []
	var counts: Dictionary = {}
	for m in p_members:
		if not (m is Dictionary):
			continue
		var id := str(m.get("enemy", ""))
		if id == "":
			continue
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var parts := PackedStringArray()
	for id in order:
		var n := str(p_data.record("enemies", id).get("name", "")) if p_data != null else ""
		if n == "":
			n = str(id).capitalize()
		parts.append(n if int(counts[id]) == 1 else "%s x%d" % [n, counts[id]])
	return ", ".join(parts)


func select_member(i: int) -> void:
	selected = i if i >= 0 and i < members.size() else -1
	_update_info()
	canvas.queue_redraw()


## Moves member i so its centre is at `pos` (battle pixels, snapped to whole numbers and kept
## where the battle scene would draw it), then reports the change.
func move_member(i: int, pos: Vector2) -> void:
	if not _place(i, pos):
		return
	_commit()


func add_enemy(enemy_id: String) -> void:
	if enemy_id == "":
		return
	var m := {"enemy": enemy_id, "position": [BATTLE_W / 2, 120], "hidden": false}
	members.append(m)
	var i := members.size() - 1
	var h := _sprite_size(i).y
	var y := roundi(FIELD_H - 12 - h / 2.0)
	# First free spot from the centre outwards.
	var x := BATTLE_W / 2
	for step in range(0, 9):
		var cand: int = BATTLE_W / 2 + (step + 1) / 2 * 48 * (1 if step % 2 == 1 else -1)
		var free := true
		for j in members.size() - 1:
			if absf(_center(j).x - cand) < 32.0:
				free = false
				break
		if free:
			x = clampi(cand, 16, BATTLE_W - 16)
			break
	m.position = [x, y]
	selected = i
	_commit()


func remove_selected() -> void:
	if selected < 0 or selected >= members.size():
		return
	members.remove_at(selected)
	selected = mini(selected, members.size() - 1)
	_commit()


## Lays the enemies out evenly: one row (feet on the same line), or two staggered rows when
## there are more than five.
func auto_arrange() -> void:
	var n := members.size()
	if n == 0:
		return
	var front := n if n <= 5 else int(ceil(n / 2.0))
	for i in n:
		if not (members[i] is Dictionary):
			continue
		var back := i >= front
		var k := i - front if back else i
		var count := n - front if back else front
		var x := roundi(BATTLE_W * (k + 1) / float(count + 1))
		var bottom := FIELD_H - 40 if back else FIELD_H - 12
		var y := roundi(bottom - _sprite_size(i).y / 2.0)
		members[i]["position"] = [x, y]
	_commit()


## Where the battle scene draws member i: the battler's rectangle in battle pixels.
func member_rect(i: int) -> Rect2:
	var s := _sprite_size(i)
	var c := _center(i)
	return Rect2(roundf(c.x - s.x / 2.0), roundf(minf(c.y - s.y / 2.0, FIELD_H - 4 - s.y)), s.x, s.y)


## Index of the topmost enemy at a point in battle pixels, or -1.
func member_at(p: Vector2) -> int:
	for i in range(members.size() - 1, -1, -1):
		if member_rect(i).grow(2).has_point(p):
			return i
	return -1


# --- internals -------------------------------------------------------------------------------

func _commit() -> void:
	_drag = {}
	list.set_value(members)
	_update_info()
	canvas.queue_redraw()
	value_changed.emit(get_value())


func _on_list_changed(v: Variant) -> void:
	members = RPGJson.deep_copy(v) if v is Array else []
	selected = clampi(selected, -1, members.size() - 1)
	_update_info()
	canvas.queue_redraw()
	value_changed.emit(get_value())


## Sets member i's centre without reporting. Returns false when nothing changed.
func _place(i: int, pos: Vector2) -> bool:
	if i < 0 or i >= members.size() or not (members[i] is Dictionary):
		return false
	var s := _sprite_size(i)
	var x := clampi(roundi(pos.x), 0, BATTLE_W)
	# Below this the battle scene clamps the sprite anyway; keep the data where it is drawn.
	var y := clampi(roundi(pos.y), 0, maxi(0, roundi(FIELD_H - 4 - s.y / 2.0)))
	var old: Variant = members[i].get("position")
	if old is Array and old.size() >= 2 and typeof(old[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(old[1]) in [TYPE_INT, TYPE_FLOAT] and int(old[0]) == x and int(old[1]) == y:
		return false
	members[i]["position"] = [x, y]
	return true


func _center(i: int) -> Vector2:
	var m: Variant = members[i]
	var p: Variant = m.get("position") if m is Dictionary else null
	var c := Vector2.ZERO
	if p is Array and p.size() >= 2 and typeof(p[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(p[1]) in [TYPE_INT, TYPE_FLOAT]:
		c = Vector2(float(p[0]), float(p[1]))
	if c == Vector2.ZERO:
		# battle_scene.gd: no position = spread around the middle.
		c = Vector2(BATTLE_W / 2.0 + (i - (members.size() - 1) / 2.0) * 64, 100)
	return c


func _enemy(i: int) -> Dictionary:
	var m: Variant = members[i]
	if not (m is Dictionary) or data == null:
		return {}
	return data.record("enemies", str(m.get("enemy", "")))


func _texture(i: int) -> Texture2D:
	var b := str(_enemy(i).get("battler", ""))
	if b == "":
		return null
	if not _tex_cache.has(b):
		_tex_cache[b] = RPGResourcePicker.texture("battler", b)
	return _tex_cache[b]


func _sprite_size(i: int) -> Vector2:
	var t := _texture(i)
	return t.get_size() if t != null else SILHOUETTE


func _backdrop() -> Texture2D:
	var n := str(preview_backdrop) if preview_backdrop != null else ""
	if n == "":
		return null
	if not _tex_cache.has("bg:" + n):
		_tex_cache["bg:" + n] = RPGResourcePicker.texture("backdrop", n)
	return _tex_cache["bg:" + n]


static func _gradient(top: Color, bottom: Color, mid: Variant = null) -> GradientTexture2D:
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


func _update_info() -> void:
	if _info == null:
		return
	if _remove_button != null:
		_remove_button.disabled = selected < 0
	if members.is_empty():
		_info.text = "No enemies yet: choose one and press + Add enemy."
		return
	if selected >= 0 and selected < members.size():
		var m: Variant = members[selected]
		var c := _center(selected)
		var later := " (appears later)" if m is Dictionary and bool(m.get("hidden", false)) else ""
		_info.text = "#%d %s at %d, %d%s. Drag to move, arrow keys nudge, Delete removes." % [selected + 1, str(_enemy(selected).get("name", m.get("enemy", "?") if m is Dictionary else "?")), int(c.x), int(c.y), later]
	else:
		_info.text = "Click an enemy to select it, drag to move it. Positions are the enemy's centre on the 320x240 battle screen."


func _draw_canvas() -> void:
	var font := canvas.get_theme_default_font()
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
	canvas.draw_rect(Rect2(0, 0, BATTLE_W, BATTLE_H), Color.BLACK)
	var bg := _backdrop()
	if bg != null:
		var rect := Rect2(0, 0, BATTLE_W, BATTLE_H) if bg.get_height() > FIELD_H else Rect2(0, 0, BATTLE_W, FIELD_H)
		canvas.draw_texture_rect(bg, rect, false)
	else:
		canvas.draw_texture_rect(_sky, Rect2(0, 0, BATTLE_W, FIELD_H), false)
		canvas.draw_texture_rect(_ground, Rect2(0, 96, BATTLE_W, FIELD_H - 96), false)
	# Where the party windows go.
	canvas.draw_rect(Rect2(0, FIELD_H, BATTLE_W, BATTLE_H - FIELD_H), Color(0.05, 0.07, 0.12, 0.85))
	canvas.draw_rect(Rect2(0.5, FIELD_H + 0.5, 79, BATTLE_H - FIELD_H - 1), Color(1, 1, 1, 0.25), false, 1.0)
	canvas.draw_rect(Rect2(80.5, FIELD_H + 0.5, 239, BATTLE_H - FIELD_H - 1), Color(1, 1, 1, 0.25), false, 1.0)
	for i in members.size():
		var r := member_rect(i)
		var m: Variant = members[i]
		var hidden := m is Dictionary and bool(m.get("hidden", false))
		var mod := Color.WHITE
		var hue := float(_enemy(i).get("battler_hue", 0))
		if hue != 0.0:
			mod = Color.from_hsv(fposmod(hue / 360.0, 1.0), 0.35, 1.0)
		if hidden:
			mod.a = 0.45
		var t := _texture(i)
		if t != null:
			canvas.draw_texture_rect(t, r, false, mod)
		else:
			var base := Color.from_hsv(float(hash(str(m.get("enemy", "")) if m is Dictionary else "") % 360) / 360.0, 0.55, 0.8)
			base.a = mod.a
			canvas.draw_rect(r.grow(-2), base)
		if i == selected:
			canvas.draw_rect(r.grow(1.5), Color(1, 0.9, 0.2), false, 1.0)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Labels at screen resolution so they stay readable.
	for i in members.size():
		var r := member_rect(i)
		var tag := str(i + 1)
		var m: Variant = members[i]
		if m is Dictionary and bool(m.get("hidden", false)):
			tag += " (later)"
		var p := Vector2(r.position.x * SCALE + 2, (r.position.y + r.size.y) * SCALE + 13)
		canvas.draw_string_outline(font, p, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
		canvas.draw_string(font, p, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.2) if i == selected else Color.WHITE)
	canvas.draw_string(font, Vector2(8, FIELD_H * SCALE + 20), "Party windows", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.4))


func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = ev.position / float(SCALE)
		if ev.pressed:
			canvas.grab_focus()
			var i := member_at(p)
			select_member(i)
			if i >= 0:
				# Grab where it is drawn, even when the stored centre is below the clamp line.
				_drag = {"index": i, "offset": member_rect(i).get_center() - p, "moved": false}
		elif not _drag.is_empty():
			var moved: bool = _drag.get("moved", false)
			_drag = {}
			if moved:
				_commit()
		canvas.accept_event()
	elif ev is InputEventMouseMotion and not _drag.is_empty():
		if _place(int(_drag.index), ev.position / float(SCALE) + _drag.offset):
			_drag.moved = true
			_update_info()
			canvas.queue_redraw()
		canvas.accept_event()
	elif ev is InputEventKey and ev.pressed and selected >= 0:
		var step := 8 if ev.shift_pressed else 1
		var d := Vector2.ZERO
		match ev.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				remove_selected()
				canvas.accept_event()
				return
			KEY_LEFT:
				d = Vector2(-step, 0)
			KEY_RIGHT:
				d = Vector2(step, 0)
			KEY_UP:
				d = Vector2(0, -step)
			KEY_DOWN:
				d = Vector2(0, step)
		if d != Vector2.ZERO:
			var c := member_rect(selected).get_center()
			move_member(selected, c + d)
			canvas.accept_event()
