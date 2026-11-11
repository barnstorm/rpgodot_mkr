extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## The victory aftermath (victory_aftermath plugin), opened over the won battle by the plugin's
## victory_scene. Pages:
##   results   a row per actor (face, name, level, an EXP bar that fills from the old to the new
##             amount, "LEVEL UP!" when it crosses a level), then the gold and the items found;
##   level     one per actor who went up (when the setting is on): old -> new level and stats,
##             new skills, a quote.
## OK (or a click) fills the bars at once, then moves on; after the last page `finished` is
## emitted and the battle closes this screen. In auto mode (tests) the pages pass at once.

signal finished()

const ROW_H := 36.0
const EXP_COLOUR := Color(0.5, 0.82, 1.0)
const TAG_COLOUR := Color(1.0, 0.9, 0.35)
const UP_COLOUR := Color(0.55, 1.0, 0.55)

var plugin: Object
var info: Dictionary = {}
## "results", "level" or "done".
var page := ""
## Pages shown so far: "results", then "level:<actor id>" (tests).
var pages_shown: Array = []
## Results page: fill progress 0..1.
var fill := 0.0
var fill_seconds := 1.2
## Results rows: [{data, bar, level_label, tag, next_label, shown_level, sounded}].
var rows: Array = []
## Actors still to get a level-up page (info.actors entries).
var level_queue: Array = []
var _page_root: Control
var _done := false
var _t := 0.0


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


func setup(p_plugin: Object, p_info: Dictionary) -> void:
	plugin = p_plugin
	info = p_info
	fill_seconds = maxf(0.0, float(plugin.setting("fill_seconds", 1.2)))
	level_queue.clear()
	if bool(plugin.setting("level_up_screens", true)):
		for a in info.get("actors", []):
			if int(a.get("new_level", 0)) > int(a.get("old_level", 0)):
				level_queue.append(a)
	_show_results()
	if auto_mode() or bool(info.get("auto", false)):
		_auto_run.call_deferred()


## Auto mode: every page in turn, then finished (deferred, so the battle is already waiting).
func _auto_run() -> void:
	set_fill(1.0)
	while not _done:
		advance()


func _new_page() -> Control:
	if _page_root != null and is_instance_valid(_page_root):
		_page_root.queue_free()
	rows.clear()
	_page_root = Control.new()
	_page_root.size = Vector2(W, H)
	_page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_root)
	return _page_root


# --- results page --------------------------------------------------------------------------------

func _show_results() -> void:
	page = "results"
	pages_shown.append("results")
	var root := _new_page()
	var top := make_window(Rect2(0, 0, W, 24), root)
	make_label(top, Vector2(8, 4), str(plugin.setting("title", "Victory!")), FONT, TAG_COLOUR, W - 16, HORIZONTAL_ALIGNMENT_CENTER)
	var gained := int(info.get("exp", 0))
	make_label(top, Vector2(W - 112, 5), "+%d %s" % [gained, term("exp", "EXP")], SMALL, EXP_COLOUR, 104, HORIZONTAL_ALIGNMENT_RIGHT)
	var actors: Array = info.get("actors", [])
	var aw := make_window(Rect2(0, 24, W, 152), root)
	rows.clear()
	for i in mini(actors.size(), 4):
		var a: Dictionary = actors[i]
		var row := Control.new()
		row.position = Vector2(6, 4 + i * ROW_H)
		row.size = Vector2(W - 12, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aw.add_child(row)
		make_face(row, Vector2(0, 1), str(a.id), 32)
		make_label(row, Vector2(38, 0), str(a.name), FONT, null, 100)
		make_label(row, Vector2(142, 2), term("level", "Lv"), SMALL, system_colour())
		var lv := make_label(row, Vector2(156, 0), str(a.old_level), FONT, null, 22, HORIZONTAL_ALIGNMENT_RIGHT)
		var tag := make_label(row, Vector2(184, 0), str(plugin.setting("level_up_text", "LEVEL UP!")), FONT, TAG_COLOUR, 120)
		tag.visible = false
		var bar := make_gauge(row, Rect2(38, 17, 200, 6), 0.0, EXP_COLOUR)
		make_label(row, Vector2(244, 12), "+%d" % (int(a.new_exp) - int(a.old_exp)), SMALL, EXP_COLOUR, 52, HORIZONTAL_ALIGNMENT_RIGHT)
		var next := make_label(row, Vector2(38, 23), "", SMALL, Color(1, 1, 1, 0.75), 200)
		rows.append({"data": a, "bar": bar, "level_label": lv, "tag": tag, "next_label": next, "shown_level": int(a.old_level), "sounded": false})
	var bw := make_window(Rect2(0, 176, W, 64), root)
	var coin: Texture2D = _icon("coin_gold")
	var gx := 8.0
	if coin != null:
		_icon_rect(bw, coin, Vector2(8, 7))
		gx = 24.0
	make_label(bw, Vector2(gx, 5), "+%d %s" % [int(info.get("gold", 0)), currency()], FONT, null, 90)
	var items: Array = info.get("items", [])
	make_label(bw, Vector2(112, 4), term("found", "Found") if not items.is_empty() else "", SMALL, system_colour())
	var y := 4.0
	var shown := 0
	for it in items:
		if shown >= 3:
			make_label(bw, Vector2(150, y), "+%d more" % (items.size() - shown), SMALL, Color(1, 1, 1, 0.75), 160)
			break
		var kind := RPGGameState.kind_for(str(it.get("kind", "item")))
		var rec := record(kind, str(it.get("id", "")))
		var x := 150.0
		var ic := record_icon(rec)
		if ic != null:
			_icon_rect(bw, ic, Vector2(x, y + 1))
			x += 14
		var n := int(it.get("count", 1))
		make_label(bw, Vector2(x, y), str(rec.get("name", it.get("id", ""))) + ("" if n <= 1 else " x%d" % n), FONT, null, W - x - 10)
		y += 14
		shown += 1
	set_fill(0.0 if fill_seconds > 0.0 else 1.0)


## The EXP bars at progress `p` (0..1 of the way from the old to the new EXP).
func set_fill(p: float) -> void:
	fill = clampf(p, 0.0, 1.0)
	var rules: Object = plugin.rpg.rules
	for row in rows:
		var a: Dictionary = row.data
		var b: Object = a.actor
		var cls := str(b.class_id) if b != null else ""
		var exp_now := int(round(lerpf(float(a.old_exp), float(a.new_exp), fill)))
		var lvl := int(a.old_level)
		while lvl < int(a.new_level) and exp_now >= int(rules.exp_for_level(cls, lvl + 1)):
			lvl += 1
		var lo := int(rules.exp_for_level(cls, lvl))
		var hi := int(rules.exp_for_level(cls, lvl + 1))
		var at_max: bool = b != null and lvl >= int(rules.max_level(b))
		var ratio := 1.0 if at_max or hi <= lo else clampf(float(exp_now - lo) / float(hi - lo), 0.0, 1.0)
		set_gauge(row.bar, ratio)
		row.next_label.text = "" if at_max else "%s %d" % [term("to_next", "To next level:"), maxi(0, hi - exp_now)]
		if lvl > int(row.shown_level):
			row.shown_level = lvl
			row.level_label.text = str(lvl)
			row.tag.visible = true
			if not row.sounded:
				row.sounded = true
				play("level_up")


## Level shown in results row `i` and its bar (0..1) (tests).
func row_state(i: int) -> Dictionary:
	var row: Dictionary = rows[i]
	return {"level": int(row.shown_level), "bar": float(row.bar.size.x) / maxf(1.0, float(row.bar.get_meta("full", 1.0))), "tag": bool(row.tag.visible)}


# --- level-up page -------------------------------------------------------------------------------

func _show_level(a: Dictionary) -> void:
	page = "level"
	pages_shown.append("level:%s" % a.id)
	var root := _new_page()
	var win := make_window(Rect2(8, 6, W - 16, H - 12), root)
	make_face(win, Vector2(10, 10), str(a.id), 48)
	make_label(win, Vector2(66, 8), str(a.name), FONT + 2, null, 140)
	make_label(win, Vector2(200, 9), str(plugin.setting("level_up_text", "LEVEL UP!")), FONT, TAG_COLOUR, 94, HORIZONTAL_ALIGNMENT_RIGHT)
	make_label(win, Vector2(66, 28), term("level", "Lv"), SMALL, system_colour())
	make_label(win, Vector2(80, 26), "%d  →  %d" % [int(a.old_level), int(a.new_level)], FONT, UP_COLOUR, 120)
	var b: Object = a.actor
	if b != null:
		make_label(win, Vector2(66, 42), str(record("classes", str(b.class_id)).get("name", "")), SMALL, Color(1, 1, 1, 0.75), 200)
	# Stats in two columns.
	var old_stats: Dictionary = a.get("old_stats", {})
	var new_stats: Dictionary = a.get("new_stats", {})
	var ids := []
	for s in plugin.rpg.rules.stats() if plugin.rpg.rules != null else []:
		var sid := str(s.get("id", ""))
		if new_stats.has(sid):
			ids.append(sid)
	var per_col := int(ceil(ids.size() / 2.0))
	for i in ids.size():
		var sid: String = ids[i]
		var x := 10.0 + (i / per_col) * 146.0 if per_col > 0 else 10.0
		var y := 64.0 + (i % per_col) * 13.0 if per_col > 0 else 64.0
		var o := int(old_stats.get(sid, new_stats[sid]))
		var n := int(new_stats[sid])
		make_label(win, Vector2(x, y + 1), stat_label(sid), SMALL, system_colour(), 40)
		make_label(win, Vector2(x + 38, y), str(o), FONT, null, 28, HORIZONTAL_ALIGNMENT_RIGHT)
		make_label(win, Vector2(x + 70, y), "→", SMALL, Color(1, 1, 1, 0.6))
		make_label(win, Vector2(x + 80, y), str(n), FONT, UP_COLOUR if n > o else null, 28, HORIZONTAL_ALIGNMENT_RIGHT)
		if n != o:
			make_label(win, Vector2(x + 110, y + 1), ("+%d" if n > o else "%d") % (n - o), SMALL, UP_COLOUR if n > o else colour(C_BAD), 30)
	var y2 := 64.0 + per_col * 13.0 + 4.0
	var learned: Array = a.get("learned", [])
	if not learned.is_empty():
		make_label(win, Vector2(10, y2), term("new_skills", "New skills"), SMALL, system_colour())
		var x2 := 70.0
		for sk in learned:
			var rec := record("skills", str(sk))
			var nm := str(rec.get("name", sk))
			var w := _text_w(nm, FONT) + 22
			if x2 + w > W - 26:
				break
			var ic := record_icon(rec)
			if ic != null:
				_icon_rect(win, ic, Vector2(x2, y2 + 1))
			make_label(win, Vector2(x2 + (14 if ic != null else 0), y2 - 1), nm, FONT, TAG_COLOUR)
			x2 += w
	# The quote, in a box at the bottom.
	var q: String = plugin.quote_for(str(a.id), not learned.is_empty())
	if q != "":
		var box := ColorRect.new()
		box.color = Color(0, 0, 0, 0.35)
		box.position = Vector2(8, H - 12 - 58)
		box.size = Vector2(W - 32, 50)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(box)
		var l := make_label(box, Vector2(6, 4), "“%s”" % RPGText.expand_plain(q, plugin.rpg), FONT, null)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.clip_text = true
		l.size = Vector2(box.size.x - 12, box.size.y - 8)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# --- input ---------------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done or a not in ["ok", "cancel"]:
		return
	if page == "results" and fill < 1.0:
		set_fill(1.0)
		return
	play("decision")
	advance()


## The next page (or the end).
func advance() -> void:
	if _done:
		return
	if page == "results" and fill < 1.0:
		set_fill(1.0)
	if not level_queue.is_empty():
		_show_level(level_queue.pop_front())
		return
	page = "done"
	_done = true
	finished.emit()


func _update(delta: float) -> void:
	_t += delta
	if page == "results" and fill < 1.0 and not _done:
		set_fill(fill + (delta / fill_seconds if fill_seconds > 0.0 else 1.0))
	for row in rows:
		if row.tag.visible:
			row.tag.modulate.a = 0.6 + 0.4 * absf(sin(_t * 5.0))


# --- helpers -------------------------------------------------------------------------------------

func _icon(icon_name: String) -> Texture2D:
	if plugin == null or plugin.rpg == null or not RPGIcons.enabled(plugin.rpg.data):
		return null
	var i := RPGIcons.find(icon_name)
	return RPGIcons.texture(i, 12) if i > 0 else null


func _icon_rect(parent: Node, tex: Texture2D, pos: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = pos
	tr.size = Vector2(12, 12)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr
