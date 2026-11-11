extends Control
## A selectable list drawn in the RPG Maker style: rows (or a grid of `columns`), a cursor
## highlight from the window skin, greyed-out disabled entries, right-aligned values and
## scroll arrows. Items: {text, right?, enabled? (true), colour?, right_colour?, icon?, right_icon?,
## data?}: icon (Texture2D) is drawn before the text (when any entry has one, every entry's text
## leaves room for it), right_icon before the right-aligned text.
## Movement is done by the owning screen through move(); the list only draws.

const ROW := 14
## Icon size in rows (24 px VX / 32 px MV icons are drawn at this size on the 320x240 layout).
const ICON := 12

var items: Array = []
var columns := 1
var row_h := ROW
var index := 0
var top_row := 0
var font_size := 11
## Draw the cursor even when the list does not have focus (dimmed).
var show_inactive_cursor := false
var active := true:
	set(v):
		active = v
		queue_redraw()
var _blink := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_items(list: Array, keep_index := true) -> void:
	items = list
	if not keep_index:
		index = 0
		top_row = 0
	index = clampi(index, 0, maxi(items.size() - 1, 0))
	_ensure_visible()
	queue_redraw()


func current() -> Dictionary:
	if index >= 0 and index < items.size():
		return items[index]
	return {}


func current_enabled() -> bool:
	var c := current()
	return not c.is_empty() and bool(c.get("enabled", true))


func rows_visible() -> int:
	return maxi(1, int(size.y / row_h))


func row_count() -> int:
	return int(ceil(float(items.size()) / float(columns)))


## Moves the cursor. Returns true when it moved (the caller plays the cursor sound).
func move(dx: int, dy: int) -> bool:
	if items.is_empty():
		return false
	var before := index
	if dx != 0 and columns > 1:
		index = clampi(index + dx, 0, items.size() - 1)
	elif dy != 0:
		var rows := row_count()
		var col := index % columns
		var row := index / columns
		row = posmod(row + dy, rows) if rows > 0 else 0
		var n := row * columns + col
		if n >= items.size():
			n = col if dy > 0 else items.size() - 1
		index = n
	_ensure_visible()
	queue_redraw()
	return index != before


func select(i: int) -> void:
	index = clampi(i, 0, maxi(items.size() - 1, 0))
	_ensure_visible()
	queue_redraw()


func _ensure_visible() -> void:
	var row := index / columns
	var vis := rows_visible()
	if row < top_row:
		top_row = row
	elif row >= top_row + vis:
		top_row = row - vis + 1
	top_row = clampi(top_row, 0, maxi(0, row_count() - vis))


## Rectangle of item `i` in local coordinates (for overlays such as gauges).
func item_rect(i: int) -> Rect2:
	var cw := size.x / columns
	return Rect2((i % columns) * cw, (i / columns - top_row) * row_h, cw - 2, row_h)


func _process(delta: float) -> void:
	if active and is_visible_in_tree():
		_blink += delta
		queue_redraw()


func _cursor_box() -> StyleBox:
	if has_theme_stylebox("cursor", "RPGWindow"):
		return get_theme_stylebox("cursor", "RPGWindow")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.18)
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	return sb


func _col(n: int, fallback: Color) -> Color:
	var key := "text_%d" % n
	return get_theme_color(key, "RPGWindow") if has_theme_color(key, "RPGWindow") else fallback


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var normal := _col(0, Color.WHITE)
	var shadow := Color(0, 0, 0, 0.7)
	var vis := rows_visible()
	var first := top_row * columns
	var last := mini(items.size(), (top_row + vis) * columns)
	if index >= first and index < last and (active or show_inactive_cursor) and not items.is_empty():
		var r := item_rect(index)
		var sb := _cursor_box()
		draw_style_box(sb, r)
		if active:
			draw_rect(r.grow(-1), Color(1, 1, 1, 0.07 + 0.07 * sin(_blink * 6.0)))
		if not active:
			draw_rect(r, Color(0, 0, 0, 0.25))
	var asc := font.get_ascent(font_size)
	var fh := font.get_height(font_size)
	# When any entry has an icon, every entry's text starts after the icon column (aligned).
	var icon_col := items.any(func(e: Variant) -> bool: return e is Dictionary and e.get("icon") is Texture2D)
	var icon_px := float(mini(row_h - 2, ICON))
	for i in range(first, last):
		var it: Dictionary = items[i]
		var r := item_rect(i)
		var enabled := bool(it.get("enabled", true))
		var c: Color = it.get("colour", normal)
		if not enabled:
			c = Color(c.r, c.g, c.b, 0.45)
		var x := r.position.x + 4
		var icon: Variant = it.get("icon")
		if icon is Texture2D:
			draw_texture_rect(icon, Rect2(x, r.position.y + floorf((row_h - icon_px) / 2.0), icon_px, icon_px), false, Color(1, 1, 1, c.a))
		if icon_col:
			x += icon_px + 2
		var y := r.position.y + (row_h - fh) / 2.0 + asc
		var right := str(it.get("right", ""))
		var rw := 0.0
		if right != "":
			rw = font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var rc: Color = it.get("right_colour", c)
			if not enabled:
				rc = Color(rc.r, rc.g, rc.b, 0.45)
			var rx := r.end.x - 4 - rw
			draw_string(font, Vector2(rx + 1, y + 1), right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(shadow, shadow.a * rc.a))
			draw_string(font, Vector2(rx, y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, rc)
			var ricon: Variant = it.get("right_icon")
			if ricon is Texture2D:
				draw_texture_rect(ricon, Rect2(rx - icon_px - 2, r.position.y + floorf((row_h - icon_px) / 2.0), icon_px, icon_px), false, Color(1, 1, 1, rc.a))
				rw += icon_px + 2
		var tw := maxf(8.0, r.end.x - x - rw - 8)
		var text := str(it.get("text", ""))
		draw_string(font, Vector2(x + 1, y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, tw, font_size, Color(shadow, shadow.a * c.a), TextServer.JUSTIFICATION_NONE)
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, tw, font_size, c, TextServer.JUSTIFICATION_NONE)
	# Scroll arrows.
	var bob := 1.0 if int(_blink * 3) % 2 == 0 else 0.0
	if top_row > 0:
		_arrow(Vector2(size.x / 2, 2 - bob), true)
	if top_row + vis < row_count():
		_arrow(Vector2(size.x / 2, size.y - 2 + bob), false)


func _arrow(p: Vector2, up: bool) -> void:
	var pts: PackedVector2Array
	if up:
		pts = PackedVector2Array([p + Vector2(-4, 3), p + Vector2(4, 3), p + Vector2(0, -1)])
	else:
		pts = PackedVector2Array([p + Vector2(-4, -3), p + Vector2(4, -3), p + Vector2(0, 1)])
	draw_colored_polygon(pts, Color(1, 1, 1, 0.9))
