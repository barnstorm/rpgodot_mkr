extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default options screen: music volume, sound volume, text speed, always dash, full screen and
## window scaling. Saved to user://rpg_options.json and applied to the audio service, the message
## speed and the game window (RPGGame.apply_display; Alt+Enter / F4 also toggle full screen).
## Left/right change the selected value; OK toggles; Cancel (or "Done") saves and closes.
## Extensions add rows (RPGExtensionHost.option_rows: bool, choice or slider) between the
## built-in rows and Done; their values are kept in the same file as "<extension>.<key>".

signal closed()

const PATH := "user://rpg_options.json"
const SPEEDS := ["slow", "normal", "fast", "instant"]
const SPEED_CPS := {"slow": 20.0, "normal": 40.0, "fast": 80.0, "instant": 0.0}
const SPEED_LABELS := {"slow": "Slow", "normal": "Normal", "fast": "Fast", "instant": "Instant"}
const ROWS := ["music", "sound", "text_speed", "always_dash", "fullscreen", "scale", "done"]
const SCALES := ["fit", "pixel"]
const SCALE_LABELS := {"fit": "Fit", "pixel": "Pixel"}

var options := {}
var list: Control
var help: Label
var gauges := {}
var _row_y := 0.0
## Row ids shown, in order: ROWS without "done", the extension rows' "<ext>.<key>", "done".
var rows: Array = []
## Extension rows by id (RPGExtensionHost.option_rows).
var ext_rows: Dictionary = {}
## Rows shown at once (more scroll).
const MAX_VISIBLE_ROWS := 10


static func defaults() -> Dictionary:
	return {"music": 100, "sound": 100, "text_speed": "normal", "always_dash": false, "fullscreen": false, "scale": "fit"}


static func load_options() -> Dictionary:
	var out := defaults()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for k in out:
					if d.has(k):
						out[k] = d[k]
				# Extension option rows ("<extension>.<key>") are kept as they are.
				for k in d:
					if str(k).contains(".") and not out.has(k):
						out[k] = d[k]
	out.music = clampi(int(out.music), 0, 100)
	out.sound = clampi(int(out.sound), 0, 100)
	if not SPEEDS.has(str(out.text_speed)):
		out.text_speed = "normal"
	out.always_dash = bool(out.always_dash)
	out.fullscreen = bool(out.fullscreen)
	if not SCALES.has(str(out.scale)):
		out.scale = "fit"
	return out


static func save_options(opts: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(opts, "\t"))


## Applies options to a running service (audio volumes, message speed, always dash).
static func apply(p_rpg: Node, opts: Dictionary) -> void:
	if p_rpg == null:
		return
	if p_rpg.audio != null:
		var a: Node = p_rpg.audio
		a.master_music = clampf(float(opts.get("music", 100)) / 100.0, 0.0, 1.0)
		a.master_sound = clampf(float(opts.get("sound", 100)) / 100.0, 0.0, 1.0)
		# 0% is silence (-80 dB), never -inf.
		if a.bgm != null and a.bgm.playing:
			a.bgm.volume_db = a.bgm_db() if a.has_method("bgm_db") else a._vol(a.current_bgm) + linear_to_db(maxf(a.master_music, 0.0001))
		if a.bgs != null and a.bgs.playing:
			a.bgs.volume_db = a.bgs_db() if a.has_method("bgs_db") else a._vol(a.current_bgs) + linear_to_db(maxf(a.master_sound, 0.0001))
	if p_rpg.data != null:
		var sys: Dictionary = p_rpg.data.system
		if not p_rpg.has_meta("project_text_speed"):
			p_rpg.set_meta("project_text_speed", float(sys.get("text_speed", 40)))
		var sp := str(opts.get("text_speed", "normal"))
		var cps: float = SPEED_CPS.get(sp, 40.0)
		if sp == "normal":
			cps = float(p_rpg.get_meta("project_text_speed"))
		sys["text_speed"] = cps if cps > 0.0 else 0
		sys["always_dash"] = bool(opts.get("always_dash", false))
	if p_rpg.game != null and p_rpg.game.has_method("apply_display"):
		p_rpg.game.apply_display(opts)


static func apply_saved(p_rpg: Node) -> void:
	apply(p_rpg, load_options())


func _load_rows() -> void:
	rows = ROWS.slice(0, ROWS.size() - 1)
	ext_rows.clear()
	var host: Node = rpg.extensions if rpg != null and "extensions" in rpg else null
	if host != null and host.has_method("option_rows"):
		for r in host.option_rows():
			ext_rows[str(r.id)] = r
			rows.append(str(r.id))
			if not options.has(r.id):
				options[r.id] = host.option(str(r.ext), str(r.key), r.get("default"))
	rows.append("done")


func _build() -> void:
	options = load_options()
	_load_rows()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)  # the title or menu windows must not show through
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var shown := mini(rows.size(), MAX_VISIBLE_ROWS)
	var top := 12 if shown <= ROWS.size() else 4
	var head := make_window(Rect2(40, top, 240, 26))
	make_label(head, Vector2(0, 5), term("options", "Options"), FONT, system_colour(), 240, HORIZONTAL_ALIGNMENT_CENTER)
	var win := make_window(Rect2(40, top + 28, 240, 16 + shown * ROW))
	list = make_list(win, Rect2(8, 8, 224, shown * ROW))
	_row_y = 8
	for i in 2:
		var g := make_gauge(win, Rect2(104, 8 + i * ROW + 4, 72, 6), 1.0, Color(0.45, 0.8, 1.0) if i == 0 else Color(0.55, 1.0, 0.6))
		gauges[ROWS[i]] = g
	var hw := make_window(Rect2(40, top + 30 + 16 + shown * ROW, 240, 40))
	help = make_label(hw, Vector2(8, 6), "", SMALL, null, 224)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size.y = 28
	_refresh()


func _refresh() -> void:
	var on := "ON"
	var off := "OFF"
	var items := [
		{"text": "Music Volume", "right": "%d%%" % int(options.music)},
		{"text": "Sound Volume", "right": "%d%%" % int(options.sound)},
		{"text": "Text Speed", "right": "< %s >" % SPEED_LABELS.get(options.text_speed, "Normal")},
		{"text": "Always Dash", "right": on if options.always_dash else off, "right_colour": colour(4) if options.always_dash else colour(0)},
		{"text": "Full Screen", "right": on if options.fullscreen else off, "right_colour": colour(4) if options.fullscreen else colour(0)},
		{"text": "Scaling", "right": "< %s >" % SCALE_LABELS.get(options.scale, "Fit")},
	]
	var helps := [
		"Background music and jingles. Left/Right to change.",
		"Sound effects. Left/Right to change.",
		"How fast messages appear.",
		"Run without holding the dash button.",
		"Fill the screen (Alt+Enter or F4 also switch).",
		"Fit: as large as the window allows. Pixel: whole multiples only.",
	]
	for id in rows:
		if ext_rows.has(id):
			items.append(_ext_item(ext_rows[id]))
			helps.append(str(ext_rows[id].get("help", "")))
	items.append({"text": "Done", "colour": system_colour()})
	helps.append("Save the options and go back.")
	list.set_items(items)
	set_gauge(gauges.music, float(options.music) / 100.0)
	set_gauge(gauges.sound, float(options.sound) / 100.0)
	# The volume gauges belong to the first two rows; hide them once those scroll away.
	for i in 2:
		var g: ColorRect = gauges[ROWS[i]]
		var bar: Control = g.get_parent() if g.get_parent() is Control else g
		bar.visible = int(list.top_row) == 0
	help.text = helps[clampi(list.index, 0, helps.size() - 1)]


## One extension row: a bool shows ON/OFF, a choice "< label >", a slider its number.
func _ext_item(r: Dictionary) -> Dictionary:
	var v: Variant = options.get(r.id, r.get("default"))
	match str(r.get("kind", "bool")):
		"bool":
			var b := bool(v)
			return {"text": str(r.get("label", r.key)), "right": "ON" if b else "OFF", "right_colour": colour(4) if b else colour(0)}
		"choice":
			var opts: Array = r.get("options", [])
			var labels: Array = r.get("option_labels", opts)
			var i := opts.find(v)
			var shown := str(labels[i]) if i >= 0 and i < labels.size() else str(v)
			return {"text": str(r.get("label", r.key)), "right": "< %s >" % shown}
		_:
			var fmt := str(r.get("format", "%d" if float(r.get("step", 1)) == floorf(float(r.get("step", 1))) else "%.1f"))
			return {"text": str(r.get("label", r.key)), "right": (fmt % (float(v) if fmt.contains("f") else int(v))) + str(r.get("suffix", ""))}


func handle_action(a: String) -> void:
	match a:
		"up", "down":
			if list.move(0, -1 if a == "up" else 1):
				play("cursor")
			_refresh()
		"left", "right":
			change(rows[list.index], -1 if a == "left" else 1)
		"ok":
			var row: String = rows[list.index]
			if row == "done":
				play("decision")
				finish()
			elif row in ["always_dash", "text_speed", "fullscreen", "scale"]:
				change(row, 1)
			elif ext_rows.has(row) and str(ext_rows[row].get("kind", "bool")) != "slider":
				change(row, 1)
			else:
				play("buzzer")
		"cancel":
			play("cancel")
			finish()


# --- mouse ---------------------------------------------------------------------------------

## The option rows. A click on the selected volume row lowers it on the left half and raises it
## on the right half; other rows act as OK.
func pointer_targets() -> Array:
	var out := list_targets(list)
	for t in out:
		var row_rect: Rect2 = t.rect
		t["ok"] = func() -> void:
			var row: String = rows[list.index]
			if row == "music" or row == "sound" or (ext_rows.has(row) and str(ext_rows[row].get("kind", "")) == "slider"):
				change(row, 1 if pointer_pos.x >= row_rect.get_center().x else -1)
			else:
				handle_action("ok")
	return out


func on_pointer_moved(_l: Control) -> void:
	_refresh()


## Changes one option by a step (volumes in 10% steps). Applied immediately.
func change(row: String, dir: int) -> void:
	match row:
		"music", "sound":
			var before := int(options[row])
			options[row] = clampi(before + dir * 10, 0, 100)
			if options[row] == before:
				return
		"text_speed":
			var i := SPEEDS.find(str(options.text_speed))
			options.text_speed = SPEEDS[posmod(i + dir, SPEEDS.size())]
		"always_dash":
			options.always_dash = not bool(options.always_dash)
		"fullscreen":
			options.fullscreen = not bool(options.fullscreen)
		"scale":
			var k := SCALES.find(str(options.scale))
			options.scale = SCALES[posmod(k + dir, SCALES.size())]
		_:
			if not ext_rows.has(row) or not _change_ext(ext_rows[row], dir):
				return
	apply(rpg, options)
	play("cursor")
	_refresh()
	if rpg != null and rpg.has_signal("option_changed"):
		rpg.option_changed.emit(row, options.get(row))


## Steps an extension row. Returns false when the value did not change.
func _change_ext(r: Dictionary, dir: int) -> bool:
	var id := str(r.id)
	var before: Variant = options.get(id, r.get("default"))
	match str(r.get("kind", "bool")):
		"bool":
			options[id] = not bool(before)
		"choice":
			var opts: Array = r.get("options", [])
			if opts.is_empty():
				return false
			options[id] = opts[posmod(opts.find(before) + dir, opts.size())]
		_:
			var step := float(r.get("step", 1))
			var v := clampf(float(before) + dir * step, float(r.get("min", 0)), float(r.get("max", 100)))
			options[id] = int(v) if step == floorf(step) else v
	return options[id] != before


func finish() -> void:
	if not input_enabled:
		return
	input_enabled = false
	save_options(options)
	apply(rpg, options)
	closed.emit()
