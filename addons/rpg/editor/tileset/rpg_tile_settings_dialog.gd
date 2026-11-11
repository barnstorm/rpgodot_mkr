@tool
class_name RPGTileSettingsDialog
extends AcceptDialog
## RPG Maker's tileset page as a dialog: passability and tile flags per tile.
##   Tileset picker (records in rpg/database/tilesets.json), zoom
##   Mode list (left): Passage (4-dir), Passable on/off, Star (above), Bush, Counter, Ladder,
##     Damage floor, Terrain tag
##   Tile grid (centre) with tabs Autotiles / Lower / Upper / Animated: every tile shows its value
##     for the mode (O/X marks, arrows, star, terrain number); overridden tiles have an orange corner
##   Selected tile (right): its values and defaults; copy its settings to the selected tiles
## Mouse: left-click sets or toggles the value (Passage 4-dir: the side of the tile you click picks
## the direction, the centre toggles all four); Shift/Ctrl-click selects tiles without changing them;
## right-click resets a tile to its default. Save writes rpg/tileset_overrides/<id>.json.

signal saved(tileset_id: String)

const MODES := [
	["passage4", "Passage (4-dir)", "Click the side of a tile to open or close that direction; the centre toggles all four."],
	["passable", "Passable on/off", "O passable in every direction, X blocked, triangle partly passable."],
	["star", "Star (above)", "Star tiles are drawn above characters and are ignored for passage."],
	["bush", "Bush", "Characters standing on a bush tile are drawn half hidden."],
	["counter", "Counter", "Events behind a counter can be talked to across it."],
	["ladder", "Ladder", "Characters keep facing up on ladder tiles."],
	["damage", "Damage floor", "Walking on these tiles hurts the party."],
	["terrain", "Terrain tag", "Click sets the tile to the terrain tag below; right-click resets."],
]
const MODE_FLAGS := {
	"star": RPGTilesetBuilder.FLAG_STAR, "bush": RPGTilesetBuilder.FLAG_BUSH,
	"counter": RPGTilesetBuilder.FLAG_COUNTER, "ladder": RPGTilesetBuilder.FLAG_LADDER,
	"damage": RPGTilesetBuilder.FLAG_DAMAGE,
}
const TABS := [
	# Named like the map palette's tabs (A, B, C, Anim), with what each sheet holds.
	[RPGTilesetBuilder.SOURCE_AUTOTILE, "A: Autotiles"],
	[RPGTilesetBuilder.SOURCE_LOWER, "B: Lower"],
	[RPGTilesetBuilder.SOURCE_UPPER, "C: Upper"],
	[RPGTilesetBuilder.SOURCE_ANIMATED, "Anim: Animated"],
]
const COLUMNS := 6
const CENTRE := 0.17
const COL_OPEN := Color(0.55, 0.9, 1.0)
const COL_BLOCK := Color(1.0, 0.4, 0.35)
const COL_STAR := Color(1.0, 0.85, 0.3)
const COL_OVERRIDE := Color(1.0, 0.55, 0.1)

var data: RPGProjectData
var tileset_id := ""
var settings: RPGTileSettings
var edit_mode := "passage4"
var zoom := 3
var selected_key := ""
## Tiles that "Copy to selected" writes to (Shift/Ctrl-click adds or removes).
var selection: Array = []

var picker: OptionButton
var tabs: TabBar
var grid: Control
var status: Label
var info: Label
var terrain_spin: SpinBox
var mode_buttons: Dictionary = {}
var _mode_help: Label
var _scroll: ScrollContainer
var _tab_sources: Array = []
var _message := ""


## Opens the dialog on `tileset_id` (or the first tileset when empty) as a child of `parent`.
static func open_for(p_data: RPGProjectData, p_tileset_id: String, parent: Node) -> RPGTileSettingsDialog:
	var d := RPGTileSettingsDialog.new()
	d.data = p_data
	d.tileset_id = p_tileset_id
	if d.tileset_id == "" or not p_data.has_record("tilesets", d.tileset_id):
		var recs: Array = p_data.records("tilesets")
		d.tileset_id = str(recs[0].get("id", "")) if not recs.is_empty() else ""
	parent.add_child(d)
	var avail := Vector2i(1000, 700)
	if parent.is_inside_tree():
		var vs: Vector2 = parent.get_viewport().get_visible_rect().size
		avail = Vector2i(mini(avail.x, int(vs.x) - 40), mini(avail.y, int(vs.y) - 40))
	d.popup_centered(avail)
	return d


func _init() -> void:
	title = "Tile settings"
	ok_button_text = "Close"
	dialog_hide_on_ok = false
	min_size = Vector2i(760, 520)


func _ready() -> void:
	_build_ui()
	add_button("Revert", false, "revert")
	add_button("Save", false, "save")
	custom_action.connect(_on_action)
	confirmed.connect(_request_close)
	canceled.connect(_request_close)
	load_tileset(tileset_id)


# --- layout --------------------------------------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_label("Tileset"))
	picker = OptionButton.new()
	picker.custom_minimum_size.x = 240
	for r in data.records("tilesets"):
		picker.add_item("%s (%s)" % [r.get("name", r.get("id", "")), r.get("id", "")])
		picker.set_item_metadata(picker.item_count - 1, str(r.get("id", "")))
	picker.item_selected.connect(_on_pick)
	top.add_child(picker)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_label("Zoom"))
	var zoom_opt := OptionButton.new()
	for z in [2, 3, 4]:
		zoom_opt.add_item("%d×" % z, z)
	zoom_opt.select(1)
	zoom_opt.item_selected.connect(func(i: int) -> void:
		zoom = zoom_opt.get_item_id(i)
		_layout_grid())
	top.add_child(zoom_opt)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)

	# Mode list.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 170
	body.add_child(left)
	left.add_child(_label("Mode"))
	var group := ButtonGroup.new()
	for m in MODES:
		var b := Button.new()
		b.text = m[1]
		b.tooltip_text = m[2]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var mid: String = m[0]
		b.pressed.connect(func() -> void: set_edit_mode(mid))
		left.add_child(b)
		mode_buttons[mid] = b
	left.add_child(HSeparator.new())
	left.add_child(_label("Terrain tag to set"))
	terrain_spin = SpinBox.new()
	terrain_spin.min_value = 0
	terrain_spin.max_value = 999
	terrain_spin.value = 1
	left.add_child(terrain_spin)
	left.add_child(HSeparator.new())
	_mode_help = _wrapped("", 170)
	left.add_child(_mode_help)

	# Tile grid.
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(centre)
	tabs = TabBar.new()
	tabs.clip_tabs = false
	tabs.tab_changed.connect(func(_i: int) -> void: _layout_grid())
	centre.add_child(tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	centre.add_child(_scroll)
	grid = Control.new()
	grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.draw.connect(_draw_grid)
	grid.gui_input.connect(_on_grid_input)
	_scroll.add_child(grid)

	# Selected tile.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 210
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_label("Selected tile"))
	info = _wrapped("", 210)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(info)
	var copy_btn := Button.new()
	copy_btn.text = "Copy to selected tiles"
	copy_btn.tooltip_text = "Copy every setting of the tile clicked last to the tiles picked with Shift/Ctrl-click"
	copy_btn.pressed.connect(copy_to_selection)
	right.add_child(copy_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to default"
	reset_btn.tooltip_text = "Remove the override of the selected tiles (right-click resets one tile)"
	reset_btn.pressed.connect(reset_selection)
	right.add_child(reset_btn)
	right.add_child(_wrapped("Left-click: set or toggle. Shift/Ctrl-click: select. Right-click: reset. Orange corner: overridden.", 210, 0.7))

	status = Label.new()
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(status)
	set_edit_mode(edit_mode)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## Wrapping label for a vertical box: it gets a fixed width so its wrapped height is sane.
func _wrapped(text: String, width: int, alpha := 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	l.modulate = Color(1, 1, 1, alpha)
	return l


# --- state ---------------------------------------------------------------------------------------

## Loads (or reloads) a tileset; unsaved edits of the previous one are dropped.
func load_tileset(id: String) -> void:
	tileset_id = id
	for i in picker.item_count:
		if str(picker.get_item_metadata(i)) == id:
			picker.select(i)
	selected_key = ""
	selection.clear()
	if id == "":
		settings = null
		_message = "No tilesets in the database."
	else:
		settings = RPGTileSettings.open(data, id)
		_message = "; ".join(PackedStringArray(settings.errors)) if not settings.errors.is_empty() else ""
		title = "Tile settings: %s" % data.record("tilesets", id).get("name", id)
	_rebuild_tabs()
	_refresh()


func set_edit_mode(m: String) -> void:
	edit_mode = m
	for k in mode_buttons:
		(mode_buttons[k] as Button).set_pressed_no_signal(k == m)
	for e in MODES:
		if e[0] == m:
			_mode_help.text = e[2]
	if grid != null:
		grid.queue_redraw()


func _rebuild_tabs() -> void:
	var keep := current_source()
	while tabs.tab_count > 0:
		tabs.remove_tab(0)
	_tab_sources.clear()
	if settings != null:
		for t in TABS:
			if not settings.keys_for_source(t[0]).is_empty():
				tabs.add_tab(t[1])
				_tab_sources.append(t[0])
	var idx := _tab_sources.find(keep)
	if idx >= 0:
		tabs.current_tab = idx
	_layout_grid()


## Atlas source shown by the current tab (-1 when none).
func current_source() -> int:
	if _tab_sources.is_empty() or tabs.current_tab < 0 or tabs.current_tab >= _tab_sources.size():
		return -1
	return _tab_sources[tabs.current_tab]


func show_source(source_id: int) -> void:
	var idx := _tab_sources.find(source_id)
	if idx >= 0:
		tabs.current_tab = idx
		_layout_grid()


func current_keys() -> Array:
	if settings == null:
		return []
	return settings.keys_for_source(current_source())


func cell_px() -> int:
	var ts := settings.base_tileset if settings != null else null
	return (ts.tile_size.x if ts != null else 16) * zoom


func _layout_grid() -> void:
	var n := current_keys().size()
	var c := cell_px()
	grid.custom_minimum_size = Vector2(COLUMNS * c, ceili(n / float(COLUMNS)) * c)
	# The scroll area hugs the grid so its scrollbar sits next to the tiles.
	_scroll.custom_minimum_size.x = COLUMNS * c + _scroll.get_v_scroll_bar().get_combined_minimum_size().x + 4
	grid.queue_redraw()


## Rect of a tile in grid coordinates (empty when it is not on the current tab).
func tile_rect(key: String) -> Rect2:
	var i := current_keys().find(key)
	if i < 0:
		return Rect2()
	var c := cell_px()
	return Rect2(Vector2(i % COLUMNS, i / COLUMNS) * c, Vector2(c, c))


func key_at(pos: Vector2) -> String:
	var c := cell_px()
	if pos.x < 0 or pos.y < 0 or pos.x >= COLUMNS * c:
		return ""
	var i := int(pos.y / c) * COLUMNS + int(pos.x / c)
	var keys := current_keys()
	return str(keys[i]) if i < keys.size() else ""


# --- editing -------------------------------------------------------------------------------------

func _on_grid_input(event: InputEvent) -> void:
	if settings == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	var key := key_at(mb.position)
	if key == "":
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.shift_pressed or mb.ctrl_pressed:
			if selection.has(key):
				selection.erase(key)
			else:
				selection.append(key)
			_message = "%d tile(s) selected" % selection.size()
		else:
			selected_key = key
			var r := tile_rect(key)
			apply_mode(key, (mb.position - r.position) / r.size)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		selected_key = key
		settings.reset(key)
		_message = "%s reset to its default" % key
	else:
		return
	grid.accept_event()
	_refresh()


## Applies the current mode to a tile; `uv` is the click position inside the tile (0..1).
func apply_mode(key: String, uv := Vector2(0.5, 0.5)) -> void:
	match edit_mode:
		"passage4":
			var dir := direction_at(uv)
			if dir == 0:
				settings.toggle_passable(key)
			else:
				settings.toggle_direction(key, dir)
		"passable":
			settings.toggle_passable(key)
		"terrain":
			settings.set_terrain(key, int(terrain_spin.value))
		_:
			if MODE_FLAGS.has(edit_mode):
				settings.toggle_flag(key, MODE_FLAGS[edit_mode])
	_message = "%s: %s" % [key, _describe(settings.effective(key))]


## Direction bit for a click inside a tile (uv 0..1), or 0 for the centre.
static func direction_at(uv: Vector2) -> int:
	var v := uv - Vector2(0.5, 0.5)
	if absf(v.x) < CENTRE and absf(v.y) < CENTRE:
		return 0
	if absf(v.x) > absf(v.y):
		return RPGTileSettings.DIR_RIGHT if v.x > 0 else RPGTileSettings.DIR_LEFT
	return RPGTileSettings.DIR_DOWN if v.y > 0 else RPGTileSettings.DIR_UP


func copy_to_selection() -> void:
	if settings == null or selected_key == "":
		_message = "Click the tile to copy from first."
	elif selection.is_empty():
		_message = "Shift/Ctrl-click the tiles to copy to."
	else:
		settings.copy_to(selected_key, selection)
		_message = "Copied %s to %d tile(s)" % [selected_key, selection.size()]
	_refresh()


func reset_selection() -> void:
	if settings == null:
		return
	var keys: Array = selection.duplicate()
	if keys.is_empty() and selected_key != "":
		keys = [selected_key]
	for k in keys:
		settings.reset(str(k))
	_message = "Reset %d tile(s)" % keys.size()
	_refresh()


func save() -> Error:
	if settings == null:
		return ERR_UNCONFIGURED
	var err := settings.save()
	_message = ("Saved %s" % settings.path()) if err == OK else ("Save failed (error %d)" % err)
	_refresh()
	if err == OK:
		saved.emit(tileset_id)
	return err


func revert() -> void:
	if settings == null:
		return
	settings.revert()
	_message = "Reverted to the saved file"
	_refresh()


func _on_action(action: StringName) -> void:
	match str(action):
		"save": save()
		"revert": revert()


func _on_pick(i: int) -> void:
	var id := str(picker.get_item_metadata(i))
	if id == tileset_id:
		return
	if settings != null and settings.dirty:
		for j in picker.item_count:
			if str(picker.get_item_metadata(j)) == tileset_id:
				picker.select(j)
		_message = "Save or revert the changes to '%s' first." % tileset_id
		_refresh()
		return
	load_tileset(id)


func _request_close() -> void:
	if settings == null or not settings.dirty:
		hide()
		queue_free()
		return
	var ask := ConfirmationDialog.new()
	ask.title = "Unsaved tile settings"
	ask.dialog_text = "Save the changes to the tileset '%s' before closing?" % _tileset_name()
	ask.ok_button_text = "Save"
	ask.cancel_button_text = "Keep editing"
	ask.add_button("Discard", true, "discard")
	ask.confirmed.connect(func() -> void:
		save()
		ask.queue_free()
		queue_free())
	ask.custom_action.connect(func(_a: StringName) -> void:
		ask.queue_free()
		queue_free())
	ask.canceled.connect(func() -> void:
		ask.queue_free()
		if not visible:
			popup())
	# While this dialog is open it is the exclusive child: the prompt goes on top of it. Escape
	# has already hidden it, so then the prompt goes on the parent, once the hide has finished.
	var host: Node = self if visible else (get_parent() if get_parent() != null else self)
	host.add_child(ask)
	ask.popup_centered.call_deferred()


func _tileset_name() -> String:
	var rec: Dictionary = data.record("tilesets", tileset_id) if data != null else {}
	var n := str(rec.get("name", ""))
	return n if n != "" else tileset_id


## A tile key as a maker reads it: "Autotile 8" for terrain_8, "Lower tile 12" for lower_12.
static func tile_label(key: String) -> String:
	var m := RegEx.create_from_string("^([a-z]+)_([0-9]+)$").search(key)
	if m == null:
		return key
	var kind := {"terrain": "Autotile", "water": "Water autotile", "lower": "Lower tile", "upper": "Upper tile", "anim": "Animated tile"}.get(m.get_string(1), m.get_string(1).capitalize())
	return "%s %d" % [kind, int(m.get_string(2))]


func _refresh() -> void:
	if grid != null:
		grid.queue_redraw()
	if settings == null:
		info.text = ""
		status.text = _message
		return
	if selected_key != "" and settings.has_key(selected_key):
		var eff := settings.effective(selected_key)
		var def := settings.default_settings(selected_key)
		var lines := ["%s  (%s)" % [tile_label(selected_key), selected_key], _describe(eff)]
		if settings.is_overridden(selected_key):
			lines.append("Overridden. Default: " + _describe(def))
		else:
			lines.append("Default value")
		if settings.review.has(selected_key):
			lines.append("Default was guessed from the pixels; check it.")
		info.text = "\n".join(PackedStringArray(lines))
	else:
		info.text = "Click a tile."
	if not selection.is_empty():
		info.text += "\n\nSelected for copy: " + ", ".join(PackedStringArray(selection))
	var overridden := 0
	for k in settings.tiles():
		if settings.is_overridden(str(k)):
			overridden += 1
	var s := "%s  |  %d overridden tile(s)%s" % [settings.path(), overridden, "  |  unsaved changes" if settings.dirty else ""]
	if _message != "":
		s += "  |  " + _message
	status.text = s


static func _describe(s: Dictionary) -> String:
	var p := int(s.get("passage", 0))
	var dirs := []
	for d in [[RPGTileSettings.DIR_UP, "up"], [RPGTileSettings.DIR_DOWN, "down"], [RPGTileSettings.DIR_LEFT, "left"], [RPGTileSettings.DIR_RIGHT, "right"]]:
		if p & d[0]:
			dirs.append(d[1])
	var pass_text := "passable" if p == RPGTileSettings.ALL_DIRS else ("blocked" if p == 0 else "only " + "/".join(PackedStringArray(dirs)))
	var flags := []
	var f := int(s.get("flags", 0))
	for e in [[RPGTilesetBuilder.FLAG_STAR, "star"], [RPGTilesetBuilder.FLAG_BUSH, "bush"], [RPGTilesetBuilder.FLAG_COUNTER, "counter"], [RPGTilesetBuilder.FLAG_LADDER, "ladder"], [RPGTilesetBuilder.FLAG_DAMAGE, "damage"], [RPGTilesetBuilder.FLAG_WALL, "wall"], [RPGTilesetBuilder.FLAG_EDGE, "edge"]]:
		if f & e[0]:
			flags.append(e[1])
	return "%s, %s, terrain %d" % [pass_text, ", ".join(PackedStringArray(flags)) if not flags.is_empty() else "no flags", int(s.get("terrain", 0))]


# --- drawing -------------------------------------------------------------------------------------

func _draw_grid() -> void:
	if settings == null or settings.base_tileset == null:
		return
	var ts := settings.base_tileset
	var font := grid.get_theme_default_font()
	var c := cell_px()
	var keys := current_keys()
	for i in keys.size():
		var key: String = keys[i]
		var r := Rect2(Vector2(i % COLUMNS, i / COLUMNS) * c, Vector2(c, c))
		var a := settings.atlas_of(key)
		grid.draw_rect(r, Color(0.12, 0.12, 0.14))
		var src: TileSetAtlasSource = null
		if ts.has_source(int(a.source)):
			src = ts.get_source(int(a.source)) as TileSetAtlasSource
		if src != null and src.texture != null:
			grid.draw_texture_rect_region(src.texture, r, src.get_tile_texture_region(a.coords, 0))
		grid.draw_rect(r, Color(0, 0, 0, 0.28))
		_draw_mark(r, settings.effective(key), font)
		if settings.is_overridden(key):
			var s := c * 0.28
			grid.draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(s, 0), r.position + Vector2(0, s)]), COL_OVERRIDE)
		grid.draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
		if selection.has(key):
			grid.draw_rect(r.grow(-2), Color(0.4, 0.75, 1.0), false, 2.0)
		if key == selected_key:
			grid.draw_rect(r.grow(-1), Color.WHITE, false, 2.0)


func _draw_mark(r: Rect2, s: Dictionary, font: Font) -> void:
	var ctr := r.get_center()
	var rad := r.size.x * 0.26
	var w := maxf(2.0, r.size.x / 16.0)
	var p := int(s.passage)
	var f := int(s.flags)
	match edit_mode:
		"passage4":
			var dirs := [
				[RPGTileSettings.DIR_UP, Vector2(0, -1)], [RPGTileSettings.DIR_DOWN, Vector2(0, 1)],
				[RPGTileSettings.DIR_LEFT, Vector2(-1, 0)], [RPGTileSettings.DIR_RIGHT, Vector2(1, 0)],
			]
			for d in dirs:
				var v: Vector2 = d[1]
				if p & int(d[0]):
					_arrow(ctr + v * r.size.x * 0.3, v, r.size.x * 0.14, COL_OPEN)
				else:
					var e := ctr + v * r.size.x * 0.38
					var t := Vector2(-v.y, v.x) * r.size.x * 0.12
					grid.draw_line(e - t, e + t, COL_BLOCK, w)
			if p == 0:
				grid.draw_circle(ctr, w * 1.2, COL_BLOCK)
		"passable":
			if p == RPGTileSettings.ALL_DIRS:
				_o(ctr, rad, w, COL_OPEN)
			elif p == 0:
				_x(ctr, rad, w, COL_BLOCK)
			else:
				var tri := PackedVector2Array([ctr + Vector2(0, -rad), ctr + Vector2(rad, rad * 0.8), ctr + Vector2(-rad, rad * 0.8), ctr + Vector2(0, -rad)])
				grid.draw_polyline(tri, COL_STAR, w)
		"star":
			if f & RPGTilesetBuilder.FLAG_STAR:
				_star(ctr, rad * 1.15, COL_STAR)
			else:
				_o(ctr, rad, w, Color(COL_OPEN, 0.8))
		"terrain":
			_number(ctr, str(int(s.terrain)), int(r.size.x * 0.42), font)
		_:
			if f & int(MODE_FLAGS.get(edit_mode, 0)):
				_o(ctr, rad, w, COL_OPEN)
			else:
				_x(ctr, rad * 0.7, w * 0.8, Color(COL_BLOCK, 0.55))


func _o(ctr: Vector2, rad: float, w: float, col: Color) -> void:
	grid.draw_arc(ctr, rad + 1, 0, TAU, 32, Color(0, 0, 0, 0.7), w + 2, true)
	grid.draw_arc(ctr, rad, 0, TAU, 32, col, w, true)


func _x(ctr: Vector2, rad: float, w: float, col: Color) -> void:
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		grid.draw_line(ctr - d * rad, ctr + d * rad, Color(0, 0, 0, 0.7 * col.a), w + 2, true)
		grid.draw_line(ctr - d * rad, ctr + d * rad, col, w, true)


func _arrow(tip: Vector2, dir: Vector2, size: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var base := tip - dir * size
	var pts := PackedVector2Array([tip, base + side * size * 0.8, base - side * size * 0.8])
	grid.draw_colored_polygon(pts, col)
	pts.append(tip)
	grid.draw_polyline(pts, Color(0, 0, 0, 0.7), 1.0, true)


func _star(ctr: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2 + i * PI / 5
		pts.append(ctr + Vector2(cos(ang), sin(ang)) * (rad if i % 2 == 0 else rad * 0.45))
	# Triangle fan from the centre: a star is concave, so draw it as ten triangles.
	for i in 10:
		grid.draw_colored_polygon(PackedVector2Array([ctr, pts[i], pts[(i + 1) % 10]]), col)
	pts.append(pts[0])
	grid.draw_polyline(pts, Color(0, 0, 0, 0.7), 1.0, true)


func _number(ctr: Vector2, text: String, size: int, font: Font) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := ctr + Vector2(-sz.x / 2, sz.y / 2 - font.get_descent(size))
	grid.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
	grid.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
