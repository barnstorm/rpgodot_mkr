@tool
class_name RPGIconPicker
extends HBoxContainer
## Picks an icon index from the project's icon sheet (RPGIcons: System "icon_sheet", else the
## starter set for the profile). Shows the chosen icon and its number and name; the button opens
## the whole sheet as a grid: click an icon to choose it. The search box finds icons by name or
## category from the starter set's icons.json ("potion", "sword", "state"...) or by number, and
## dims the rest; Enter takes the first match. Index 0 is "no icon".
## The value is an int. Old data (an icon sheet's name, or "") reads as 0 (RPGIcons.icon_index).

signal value_changed(value: Variant)

var data: RPGProjectData
var _value := 0
var _thumb: TextureRect
var _button: Button
var _popup: PopupPanel
var _search: LineEdit
var _info: Label
var _grid: Control
var _sheet := ""
## Indices the search matches (all when the search is empty).
var _match: Dictionary = {}
var _hover := -1


func _init(p_data: RPGProjectData = null) -> void:
	data = p_data
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(24, 24)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_thumb)
	_button = Button.new()
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.clip_text = true
	_button.tooltip_text = "Choose an icon from the icon sheet"
	_button.pressed.connect(open_popup)
	add_child(_button)
	_refresh()


func set_value(v: Variant) -> void:
	_value = RPGIcons.icon_index({"icon": v})
	_refresh()


func get_value() -> Variant:
	return _value


## The icon sheet shown (RPGAssets "system" name).
func sheet() -> String:
	return RPGIcons.sheet_name(data)


## "#64 potion red" for a starter icon, "#64" for another sheet, "(none)" for 0.
func label_for(index: int) -> String:
	if index <= 0:
		return "(none)"
	var n := RPGIcons.name_of(index) if RPGIcons.is_starter_sheet(sheet()) else ""
	return "#%d %s" % [index, n.replace("_", " ")] if n != "" else "#%d" % index


func _refresh() -> void:
	_thumb.texture = RPGIcons.sheet_icon(sheet(), _value) if _value > 0 else null
	_thumb.visible = _thumb.texture != null
	_button.text = label_for(_value)


# --- popup ---------------------------------------------------------------------------------

func open_popup() -> void:
	_sheet = sheet()
	if _popup == null:
		_build_popup()
	_search.text = ""
	search("")
	_update_info()
	var tex := _sheet_texture()
	var cell := _display_cell()
	_grid.custom_minimum_size = Vector2(RPGIcons.COLUMNS * cell, _rows() * cell) if tex != null else Vector2(320, 40)
	var want := Vector2i(int(RPGIcons.COLUMNS * cell) + 40, 520)
	if is_inside_tree():
		_popup.popup(Rect2i(Vector2i(get_screen_position()) + Vector2i(0, int(size.y)), want))
		_search.grab_focus()
	else:
		_popup.size = want


func _build_popup() -> void:
	_popup = PopupPanel.new()
	_popup.name = "IconPopup"
	add_child(_popup)
	var vb := VBoxContainer.new()
	_popup.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search icons by name (potion, sword, poison…) or number"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(search)
	_search.text_submitted.connect(func(_t: String) -> void:
		var m := matches()
		if not m.is_empty():
			pick(m[0]))
	top.add_child(_search)
	var none := Button.new()
	none.text = "No icon"
	none.pressed.connect(func() -> void: pick(0))
	top.add_child(none)
	_info = Label.new()
	_info.name = "Info"
	_info.modulate = Color(1, 1, 1, 0.75)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 360)
	vb.add_child(sc)
	_grid = Control.new()
	_grid.name = "Grid"
	_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_grid_input)
	_grid.mouse_exited.connect(func() -> void:
		_hover = -1
		_grid.queue_redraw())
	sc.add_child(_grid)


func _update_info() -> void:
	var tex := _sheet_texture()
	if tex == null:
		_info.text = "No icon sheet: set System > Icon sheet, or keep the starter icons (assets/starter/System/IconSet24 and IconSet32, made by tools/generate_icons.gd)."
		return
	var names := "Names from the starter set." if RPGIcons.is_starter_sheet(_sheet) else "This sheet has no names: search by number."
	_info.text = "%s: %d icons of %d px. %s Click an icon to choose it." % [_sheet, RPGIcons.count(tex), RPGIcons.cell_size(tex), names]


func _sheet_texture() -> Texture2D:
	return RPGAssets.load_texture("system", _sheet if _sheet != "" else sheet())


func _rows() -> int:
	var tex := _sheet_texture()
	var cell := RPGIcons.cell_size(tex)
	return tex.get_height() / cell if cell > 0 else 0


## On-screen size of one icon in the grid: 24 px icons at 2x, 32 px and larger at 1x.
func _display_cell() -> float:
	var cell := RPGIcons.cell_size(_sheet_texture())
	if cell <= 0:
		return 32.0
	return float(cell * maxi(1, roundi(40.0 / cell)))


## Grid rectangle of an icon index (in the grid's coordinates).
func cell_rect(index: int) -> Rect2:
	var c := _display_cell()
	return Rect2((index % RPGIcons.COLUMNS) * c, (index / RPGIcons.COLUMNS) * c, c, c)


func index_at(pos: Vector2) -> int:
	var c := _display_cell()
	var col := int(pos.x / c)
	var row := int(pos.y / c)
	if pos.x < 0 or pos.y < 0 or col >= RPGIcons.COLUMNS or row >= _rows():
		return -1
	return row * RPGIcons.COLUMNS + col


## Filters the grid: a number matches that index; text matches starter names and categories
## (words in any order, "red potion" finds potion_red).
func search(text: String) -> void:
	_match.clear()
	var q := text.strip_edges().to_lower()
	var total := RPGIcons.count(_sheet_texture())
	if q == "":
		for i in total:
			_match[i] = true
	elif q.is_valid_int():
		if q.to_int() >= 0 and q.to_int() < total:
			_match[q.to_int()] = true
	elif RPGIcons.is_starter_sheet(_sheet if _sheet != "" else sheet()):
		var words := q.replace("_", " ").split(" ", false)
		for e in RPGIcons.entries():
			if e.index <= 0 or e.index >= total or str(e.name).begins_with("blank"):
				continue
			var hay := "%s %s" % [str(e.name).replace("_", " "), e.category]
			var ok := true
			for w in words:
				if not hay.contains(w):
					ok = false
					break
			if ok:
				_match[e.index] = true
	if _grid != null:
		_grid.queue_redraw()


## Indices matching the current search, in order.
func matches() -> Array:
	var out := _match.keys()
	out.sort()
	return out


## Chooses an icon (0: none), closes the popup and reports the change.
func pick(index: int) -> void:
	_value = maxi(0, index)
	_refresh()
	if _popup != null:
		_popup.hide()
	value_changed.emit(_value)


func _grid_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var i := index_at(ev.position)
		if i != _hover:
			_hover = i
			_grid.tooltip_text = label_for(i) if i > 0 else ""
			_grid.queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := index_at(ev.position)
		if i >= 0:
			pick(i)


func _draw_grid() -> void:
	var tex := _sheet_texture()
	if tex == null:
		return
	var c := _display_cell()
	var total := RPGIcons.count(tex)
	for i in total:
		var r := cell_rect(i)
		_grid.draw_rect(r, Color(0.2, 0.21, 0.27) if (i % RPGIcons.COLUMNS + i / RPGIcons.COLUMNS) % 2 == 0 else Color(0.16, 0.17, 0.22))
	_grid.draw_texture_rect(tex, Rect2(0, 0, RPGIcons.COLUMNS * c, (total / RPGIcons.COLUMNS) * c), false)
	if _match.size() < total:
		for i in total:
			if not _match.has(i):
				_grid.draw_rect(cell_rect(i), Color(0, 0, 0, 0.72))
	if _value > 0 and _value < total:
		_grid.draw_rect(cell_rect(_value).grow(-1), Color(1, 0.85, 0.2), false, 2.0)
	if _hover >= 0 and _hover < total:
		_grid.draw_rect(cell_rect(_hover), Color(1, 1, 1, 0.9), false, 1.0)
