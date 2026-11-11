extends "res://addons/rpg/runtime/rpg_extension.gd"
## Quest journal (kit plugin "quests").
##   Quests are Database records (type "quests", added by this plugin): name, category, icon, who
##   gave it, where, a description, objectives (each with an ID, a text and whether it starts
##   hidden) and a rewards text.
##   A quest's status is unknown (not started), active, completed or failed; each objective is
##   hidden, shown (open), completed or failed. Events change them with Set quest status and Set
##   objective state; the "quest" condition kind tests them on event pages and in Conditional
##   Branch.
##   The journal (main menu "Quests", or Open quest journal) lists active, completed and failed
##   quests; OK on an active quest tracks it. The tracker shows the tracked quest's open
##   objectives in a corner of the map (an options row turns it off), and a short note appears
##   when a quest or objective changes.
## Saved with the game: {quests: {id: {status, objectives: {objective id: state}}}, tracked}.

signal quest_changed(quest_id: String, status: String)
signal objective_changed(quest_id: String, objective_id: String, state: String)
signal tracked_changed(quest_id: String)

const SECTION := "quests"
const STATUSES := ["unknown", "active", "completed", "failed"]
const OBJECTIVE_STATES := ["hidden", "shown", "completed", "failed"]
const JOURNAL := "res://addons/rpg/extensions/quests/quest_journal.gd"
const MARK := preload("res://addons/rpg/extensions/quests/quest_mark.gd")
const TRACKER_W := 136.0
const LINE_H := 11.0
const TOAST_H := 18.0

## Every note shown so far, newest last (tests).
var toast_log: Array = []
var _tracker: Panel = null
var _tracker_key := ""
var _toasts: Array = []


# --- data --------------------------------------------------------------------------------------

func _data() -> Dictionary:
	var s := section(SECTION)
	if not (s.get("quests") is Dictionary):
		s["quests"] = {}
	if not s.has("tracked"):
		s["tracked"] = ""
	return s


## The quest record ({} when there is none).
func quest(quest_id: String) -> Dictionary:
	return rpg.data.record("quests", quest_id) if rpg != null and rpg.data != null else {}


func quest_name(quest_id: String) -> String:
	var n := str(quest(quest_id).get("name", ""))
	return RPGText.expand_plain(n, rpg) if n != "" else quest_id


## A quest's status: unknown, active, completed or failed.
func status(quest_id: String) -> String:
	var q: Variant = _data().quests.get(quest_id)
	return str(q.get("status", "unknown")) if q is Dictionary else "unknown"


## Sets a quest's status. "unknown" forgets the quest (and its objectives). Starting a quest shows
## its objectives that are not hidden. Returns false (and changes nothing) for an unknown quest
## or status.
func set_status(quest_id: String, new_status: String) -> bool:
	if quest(quest_id).is_empty() or not STATUSES.has(new_status):
		return false
	var d := _data()
	var old := status(quest_id)
	if old == new_status:
		return true
	if new_status == "unknown":
		d.quests.erase(quest_id)
		if str(d.tracked) == quest_id:
			d.tracked = ""
	else:
		var q: Dictionary = d.quests.get(quest_id, {})
		if not (q.get("objectives") is Dictionary):
			q["objectives"] = {}
		q["status"] = new_status
		d.quests[quest_id] = q
		if new_status == "active" and bool(setting("auto_track", true)) and status(str(d.tracked)) != "active":
			d.tracked = quest_id
	quest_changed.emit(quest_id, new_status)
	_changed()
	# The note comes after the tracker is up to date, so it can sit below it.
	match new_status:
		"active":
			_toast(("New quest: %s" if old == "unknown" else "Quest updated: %s") % quest_name(quest_id))
		"completed":
			_toast("Quest completed: %s" % quest_name(quest_id))
		"failed":
			_toast("Quest failed: %s" % quest_name(quest_id))
	return true


## The objectives of a quest as the journal shows them: [{id, text, state}] in record order.
func objectives(quest_id: String) -> Array:
	var out := []
	for o in quest(quest_id).get("objectives", []):
		if o is Dictionary and str(o.get("id", "")) != "":
			out.append({"id": str(o.id), "text": str(o.get("text", o.id)), "state": objective_state(quest_id, str(o.id))})
	return out


func _objective_rec(quest_id: String, objective_id: String) -> Dictionary:
	for o in quest(quest_id).get("objectives", []):
		if o is Dictionary and str(o.get("id", "")) == objective_id:
			return o
	return {}


## An objective's state: hidden, shown, completed or failed. Until an event sets it, it is
## "shown" once the quest is known (or "hidden" when the objective starts hidden).
func objective_state(quest_id: String, objective_id: String) -> String:
	var q: Variant = _data().quests.get(quest_id)
	if q is Dictionary and q.get("objectives") is Dictionary and q.objectives.has(objective_id):
		return str(q.objectives[objective_id])
	if not (q is Dictionary):
		return "hidden"
	return "hidden" if bool(_objective_rec(quest_id, objective_id).get("hidden", false)) else "shown"


## Sets an objective's state. Returns false for a quest or objective that does not exist.
func set_objective_state(quest_id: String, objective_id: String, state: String) -> bool:
	var rec := _objective_rec(quest_id, objective_id)
	if rec.is_empty() or not OBJECTIVE_STATES.has(state):
		return false
	var old := objective_state(quest_id, objective_id)
	var d := _data()
	var q: Dictionary = d.quests.get(quest_id, {"status": "unknown"})
	if not (q.get("objectives") is Dictionary):
		q["objectives"] = {}
	q.objectives[objective_id] = state
	d.quests[quest_id] = q
	objective_changed.emit(quest_id, objective_id, state)
	_changed()
	if old != state and status(quest_id) == "active":
		var text := str(rec.get("text", objective_id))
		match state:
			"completed":
				_toast("Objective complete: %s" % text)
			"failed":
				_toast("Objective failed: %s" % text)
			"shown":
				if old == "hidden":
					_toast("New objective: %s" % text)
	return true


## The quest the tracker follows ("" for none).
func tracked() -> String:
	return str(_data().get("tracked", ""))


## Tracks a quest ("" stops tracking). Returns false for a quest that does not exist.
func track(quest_id: String) -> bool:
	if quest_id != "" and quest(quest_id).is_empty():
		return false
	_data().tracked = quest_id
	tracked_changed.emit(quest_id)
	_refresh_tracker()
	return true


## IDs of the quests with a status, in journal order (Categories setting, then Database order).
func quests_with(wanted: String) -> Array:
	var order := category_order()
	var list := []
	var recs: Array = rpg.data.records("quests") if rpg.data != null else []
	for i in recs.size():
		var r: Variant = recs[i]
		if r is Dictionary and str(r.get("id", "")) != "" and status(str(r.id)) == wanted:
			var cat := str(r.get("category", ""))
			var ci := order.find(cat)
			list.append([ci if ci != -1 else order.size(), i, str(r.id)])
	list.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return list.map(func(e): return e[2])


func category_order() -> Array:
	var out := []
	for c in setting("categories", []):
		var n := str(c.get("name", "")) if c is Dictionary else str(c)
		if n != "":
			out.append(n)
	return out


## Condition kind "quest": {quest, check: status|objective, status, objective, state}.
func check_condition(cond: Dictionary, _where: Variant = null) -> bool:
	var qid := str(cond.get("quest", ""))
	if str(cond.get("check", "status")) == "objective":
		return objective_state(qid, str(cond.get("objective", ""))) == str(cond.get("state", "completed"))
	return status(qid) == str(cond.get("status", "active"))


func _changed() -> void:
	if rpg != null and rpg.has_method("request_refresh"):
		rpg.request_refresh()
	_refresh_tracker()


# --- menu and options --------------------------------------------------------------------------

func menu_entry_shown() -> bool:
	return bool(setting("menu_entry", true))


func adjust_menu(layout: Array, _config: Dictionary) -> void:
	for it in layout:
		if str(it.get("id", "")) == "quests" and str(it.get("ext", "")) == extension_id:
			it["label"] = str(setting("menu_label", "Quests"))


func option_entries() -> Array:
	if not bool(setting("tracker", true)):
		return []
	return [{"key": "tracker", "kind": "bool", "label": "Quest Tracker", "default": true, "help": "Show the tracked quest's objectives on the map."}]


func on_option_changed(_key: String, _value: Variant) -> void:
	_refresh_tracker()


## True when the tracker may show (setting and the player's option).
func tracker_enabled() -> bool:
	return bool(setting("tracker", true)) and bool(option("tracker", true))


# --- lifecycle -----------------------------------------------------------------------------------

func on_new_game() -> void:
	_clear_toasts()
	_refresh_tracker()


func on_game_loaded() -> void:
	_clear_toasts()
	_refresh_tracker()


func on_map_entered(_map_id: String) -> void:
	_refresh_tracker()


func on_title_shown() -> void:
	_clear_toasts()
	_free_tracker()


func _exit_tree() -> void:
	_free_tracker()
	_clear_toasts()


# --- tracker -------------------------------------------------------------------------------------

func _layer() -> Control:
	var l: Variant = rpg.map_overlay_layer("hud") if rpg != null and rpg.has_method("map_overlay_layer") else null
	return l if l is Control else null


func _free_tracker() -> void:
	if _tracker != null and is_instance_valid(_tracker):
		_tracker.queue_free()
	_tracker = null
	_tracker_key = ""


## The tracker panel showing now, or null (tests and screenshots).
func tracker() -> Panel:
	return _tracker if _tracker != null and is_instance_valid(_tracker) else null


## The open objectives the tracker lists for the tracked quest ([] when it shows nothing).
func tracker_lines() -> Array:
	var qid := tracked()
	if qid == "" or status(qid) != "active" or not tracker_enabled():
		return []
	var out := []
	for o in objectives(qid):
		if o.state == "shown":
			out.append(str(o.text))
	return out.slice(0, maxi(1, int(setting("tracker_lines", 4))))


func _refresh_tracker() -> void:
	var qid := tracked()
	var lines := tracker_lines()
	var show := qid != "" and status(qid) == "active" and tracker_enabled() and rpg != null and rpg.game != null and is_instance_valid(rpg.game) and rpg.game.get("map") != null
	if not show:
		_free_tracker()
		return
	var key := "%s|%s|%s" % [qid, "\n".join(PackedStringArray(lines)), str(setting("tracker_corner", "top_right"))]
	if key == _tracker_key and tracker() != null:
		return
	var layer := _layer()
	if layer == null:
		return
	_free_tracker()
	_tracker_key = key
	var h := 6.0 + 12.0 + maxf(1, lines.size()) * LINE_H + 4.0
	var p := Panel.new()
	p.name = "QuestTracker"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rpg.ui != null and rpg.ui.get("ui_theme") is Theme:
		p.theme = rpg.ui.ui_theme
	p.self_modulate.a = 0.8
	p.size = Vector2(TRACKER_W, h)
	var corner := str(setting("tracker_corner", "top_right"))
	var x := 4.0 if corner.ends_with("left") else 320.0 - TRACKER_W - 4.0
	var y := 4.0 if corner.begins_with("top") else 240.0 - h - 4.0
	p.position = Vector2(x, y)
	var title := _label(p, Vector2(6, 3), quest_name(qid), 9, TRACKER_W - 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	var ly := 16.0
	if lines.is_empty():
		var none := _label(p, Vector2(8, ly), "(no open objectives)", 8, TRACKER_W - 14)
		none.modulate.a = 0.6
	for t in lines:
		var m: Control = MARK.new()
		m.state = "shown"
		m.position = Vector2(6, ly + 2)
		m.size = Vector2(7, 7)
		p.add_child(m)
		_label(p, Vector2(16, ly), str(t), 8, TRACKER_W - 22)
		ly += LINE_H
	layer.add_child(p)
	_tracker = p


func _label(parent: Control, pos: Vector2, text: String, font_size: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(width, font_size + 3)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	var t := tracker()
	if t == null:
		return
	# Hidden under menus, scenes and messages (the hud layer draws above them).
	var busy: bool = rpg.ui != null and (rpg.ui.scene_open() or (rpg.ui.message_box != null and rpg.ui.message_box.has_method("is_open") and rpg.ui.message_box.is_open()))
	t.visible = not busy
	var target := 1.0
	if bool(setting("tracker_fade", true)) and _player_under(t.get_rect()):
		target = 0.3
	t.modulate.a = move_toward(t.modulate.a, target, delta * 4.0)


## True when the player stands under `rect` (hud coordinates).
func _player_under(rect: Rect2) -> bool:
	var g: Node = rpg.game if rpg != null else null
	if g == null or not is_instance_valid(g) or g.get("player") == null or not is_instance_valid(g.player) or not g.player.is_inside_tree():
		return false
	var p: Vector2 = g.player.get_global_transform_with_canvas().origin
	var to_ui: Transform2D = rpg.ui.transform.affine_inverse() if rpg.ui != null else Transform2D.IDENTITY
	var feet := to_ui * p
	var head := to_ui * (p - Vector2(0, float(g.player.tile_size) * 1.5))
	var r := rect.grow(2)
	return r.has_point(feet) or r.has_point(head)


# --- notes ---------------------------------------------------------------------------------------

## A short note at the top of the screen ("New quest: ..."); notes shown together stack up.
func _toast(text: String) -> void:
	toast_log.append(text)
	if not bool(setting("toast", true)):
		return
	var layer := _layer()
	if layer == null:
		return
	_toasts = _toasts.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
	var p := Panel.new()
	p.name = "QuestToast"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rpg.ui != null and rpg.ui.get("ui_theme") is Theme:
		p.theme = rpg.ui.ui_theme
	layer.add_child(p)
	var l := _label(p, Vector2(8, 3), text, 9, 10)
	# Measured in the tree with the label's own font, then sized to fit (at most 300 px).
	l.clip_text = false
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var w := clampf(l.get_minimum_size().x + 18.0, 80.0, 300.0)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size = Vector2(w - 16, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.size = Vector2(w, TOAST_H)
	var top := 4.0
	var t := tracker()
	if t != null and t.position.y < 120.0:
		top = t.position.y + t.size.y + 4.0
	p.position = Vector2((320.0 - w) / 2.0, top + _toasts.size() * (TOAST_H + 2.0))
	_toasts.append(p)
	var snd: Variant = setting("toast_sound", {})
	if snd is Dictionary and str(snd.get("file", "")) != "" and rpg.audio != null:
		rpg.audio.play_se(snd)
	var tw := p.create_tween()
	tw.tween_interval(float(setting("toast_seconds", 2.2)))
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


## The notes showing now (tests and screenshots).
func toasts() -> Array:
	return _toasts.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())


func _clear_toasts() -> void:
	for n in _toasts:
		if is_instance_valid(n):
			n.queue_free()
	_toasts.clear()
