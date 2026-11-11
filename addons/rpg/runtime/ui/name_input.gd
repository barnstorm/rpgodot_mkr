extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default name input (Run Scene contract): start({actor, name, max_length}, context), then
## finished(new_name) or cancelled(reason). A letter grid with upper case, lower case and symbol
## pages; the bottom row switches pages, deletes a letter or confirms. Cancel deletes a letter
## (and cancels when the name is already empty).

signal finished(result: Variant)
signal cancelled(reason: String)

const COLS := 10
const PAGES := {
	"upper": ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ.,'-", "0123456789"],
	"lower": ["abcdefghij", "klmnopqrst", "uvwxyz.,'-", "0123456789"],
	"symbols": ["!?&#%+*/=:", "()[]<>~^@_", "ÀÁÉÈÍÓÚÜÑÇ", "àáéèíóúüñ "],
}
const PAGE_ORDER := ["upper", "lower", "symbols"]
const COMMANDS := ["upper", "lower", "symbols", "delete", "ok"]
const COMMAND_LABELS := {"upper": "ABC", "lower": "abc", "symbols": "!?#", "delete": "Del", "ok": "OK"}
const CELL_W := 28
const CELL_H := 16

var actor_id := ""
var text := ""
var max_length := 8
var page := "upper"
## Cursor: column 0..9, row 0..3 = letters, row 4 = commands (column / 2).
var cx := 0
var cy := 0
var grid: Control
var name_box: Control
var _t := 0.0
var _done := false
var _face: Control
var _title: Label
var _hint: Label


func start(args: Dictionary, _context: Variant = null) -> void:
	actor_id = str(args.get("actor", ""))
	max_length = clampi(int(args.get("max_length", 8)), 1, 16)
	text = str(args.get("name", "")).substr(0, max_length)
	if _face != null:
		_face.queue_free()
	_face = make_face(get_node("Top"), Vector2(8, 8), actor_id, 48)
	_title.text = "Name for %s" % actor_name(actor_id) if actor_id != "" else "Enter a name"
	_redraw()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var top := make_window(Rect2(0, 0, W, 64))
	top.name = "Top"
	_title = make_label(top, Vector2(64, 6), "Enter a name", SMALL, system_colour())
	name_box = Control.new()
	name_box.position = Vector2(64, 24)
	name_box.size = Vector2(248, 30)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.draw.connect(_draw_name)
	top.add_child(name_box)
	var gw := make_window(Rect2(0, 66, W, 174))
	grid = Control.new()
	grid.position = Vector2(20, 10)
	grid.size = Vector2(COLS * CELL_W, 5 * CELL_H + 30)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(_draw_grid)
	gw.add_child(grid)
	_hint = make_label(gw, Vector2(8, 150), "", SMALL, Color(1, 1, 1, 0.6), W - 16, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.size.y = 14
	_hint.text = hint_text()


## The button hint, named for the device used last (keyboard, gamepad or mouse).
func hint_text() -> String:
	var ok := "Z/Enter"
	var back := "X/Esc"
	if rpg != null and rpg.has_method("button_label"):
		ok = rpg.button_label("ok")
		back = rpg.button_label("cancel")
	return "%s: choose   %s: delete" % [ok, back]


func _update(delta: float) -> void:
	_t += delta
	if _hint:
		var h := hint_text()
		if _hint.text != h:
			_hint.text = h
	if name_box:
		name_box.queue_redraw()
	if grid:
		grid.queue_redraw()


func _redraw() -> void:
	if name_box:
		name_box.queue_redraw()
	if grid:
		grid.queue_redraw()


func _font() -> Font:
	var f := get_theme_default_font()
	return f if f != null else ThemeDB.fallback_font


func _draw_name() -> void:
	var f := _font()
	var cw := 14.0
	for i in max_length:
		var x := i * cw
		var ch := text[i] if i < text.length() else ""
		var under := Color(1, 1, 1, 0.8) if i == text.length() and int(_t * 3) % 2 == 0 else Color(1, 1, 1, 0.35)
		name_box.draw_rect(Rect2(x + 1, 24, cw - 3, 1), under)
		if ch != "":
			# Centred by hand: draw_string with a width drops a glyph wider than it ("W" in a
			# 10 px cell vanished), so measure the letter and let wide ones overhang the cell.
			var gx := x + (cw - 1) / 2.0 - f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / 2.0
			name_box.draw_string(f, Vector2(gx + 1, 19 + 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.7))
			name_box.draw_string(f, Vector2(gx, 19), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour(0))


func _cursor_style() -> StyleBox:
	if has_theme_stylebox("cursor", "RPGWindow"):
		return get_theme_stylebox("cursor", "RPGWindow")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.18)
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.set_border_width_all(1)
	return sb


func _draw_grid() -> void:
	var f := _font()
	var rows: Array = PAGES[page]
	var shadow := Color(0, 0, 0, 0.7)
	for r in rows.size():
		var line: String = rows[r]
		for c in COLS:
			var ch := line[c] if c < line.length() else ""
			var rect := Rect2(c * CELL_W, r * CELL_H, CELL_W, CELL_H)
			if r == cy and c == cx and cy < 4:
				grid.draw_style_box(_cursor_style(), rect.grow(-1))
			var shown := ch
			var fs := 12
			if ch == " ":
				shown = "Spc"
				fs = 8
			grid.draw_string(f, rect.position + Vector2(1, 13), shown, HORIZONTAL_ALIGNMENT_CENTER, CELL_W, fs, shadow)
			grid.draw_string(f, rect.position + Vector2(0, 12), shown, HORIZONTAL_ALIGNMENT_CENTER, CELL_W, fs, colour(0))
	var y := 4 * CELL_H + 8
	grid.draw_rect(Rect2(0, y - 4, COLS * CELL_W, 1), Color(1, 1, 1, 0.25))
	for k in COMMANDS.size():
		var rect2 := Rect2(k * CELL_W * 2, y, CELL_W * 2, CELL_H)
		if cy == 4 and cx / 2 == k:
			grid.draw_style_box(_cursor_style(), rect2.grow(-1))
		var cmd: String = COMMANDS[k]
		var c2 := colour(4) if cmd == page else (colour(C_GOOD) if cmd == "ok" else system_colour())
		grid.draw_string(f, rect2.position + Vector2(1, 13), COMMAND_LABELS[cmd], HORIZONTAL_ALIGNMENT_CENTER, CELL_W * 2, 11, shadow)
		grid.draw_string(f, rect2.position + Vector2(0, 12), COMMAND_LABELS[cmd], HORIZONTAL_ALIGNMENT_CENTER, CELL_W * 2, 11, c2)


func handle_action(a: String) -> void:
	if _done:
		return
	match a:
		"up":
			cy = posmod(cy - 1, 5)
			play("cursor")
		"down":
			cy = posmod(cy + 1, 5)
			play("cursor")
		"left":
			cx = posmod(cx - (2 if cy == 4 else 1), COLS)
			play("cursor")
		"right":
			cx = posmod(cx + (2 if cy == 4 else 1), COLS)
			play("cursor")
		"ok":
			press()
		"cancel":
			# As in RPG Maker: cancel deletes; with nothing left it buzzes rather than leaving
			# the screen with no name (an empty name is never accepted, see confirm()).
			delete_char()
	_redraw()


## Mouse: every letter cell and the command row.
func pointer_targets() -> Array:
	if _done or grid == null:
		return []
	var out := []
	var xf := local_xform(grid)
	for r in 4:
		for c in COLS:
			var rr := r
			var cc := c
			out.append({"rect": xf * Rect2(c * CELL_W, r * CELL_H, CELL_W, CELL_H), "selected": cy == r and cx == c, "select": func() -> void: _point_cell(cc, rr)})
	var y := 4 * CELL_H + 8
	for k in COMMANDS.size():
		var kk := k
		out.append({"rect": xf * Rect2(k * CELL_W * 2, y, CELL_W * 2, CELL_H), "selected": cy == 4 and cx / 2 == k, "select": func() -> void: _point_cell(kk * 2, 4)})
	return out


func _point_cell(c: int, r: int) -> void:
	cx = c
	cy = r
	play("cursor")
	_redraw()


## OK on the cell under the cursor.
func press() -> void:
	if cy < 4:
		var line: String = PAGES[page][cy]
		type_char(line[cx] if cx < line.length() else "")
		return
	var cmd: String = COMMANDS[cx / 2]
	match cmd:
		"delete":
			delete_char()
		"ok":
			confirm()
		_:
			page = cmd
			play("decision")
	_redraw()


func type_char(ch: String) -> bool:
	if ch == "" or text.length() >= max_length:
		play("buzzer")
		return false
	text += ch
	play("decision")
	if text.length() >= max_length:
		# Jump to OK like RPG Maker does once the name is full.
		cy = 4
		cx = 8
	_redraw()
	return true


func delete_char() -> void:
	if text == "":
		play("buzzer")
		return
	text = text.substr(0, text.length() - 1)
	play("cancel")
	_redraw()


func confirm() -> void:
	if text.strip_edges() == "":
		play("buzzer")
		return
	play("decision")
	_done = true
	finished.emit(text.strip_edges())
