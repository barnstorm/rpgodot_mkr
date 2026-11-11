@tool
class_name RPGQuickEventDialog
extends ConfirmationDialog
## Asks a quick event template's questions (built with RPGFormBuilder) and adds the compiled
## event, with a new unique ID, to the map's events file.
##
##   RPGQuickEventDialog.open_for("town", Vector2i(4, 7), "Door", project_data, func(id): ...)
##
## create_event() is the same thing without UI (used by tests and tools).
##
## Sounds named by role (door_open, step...) are found without asking when possible: the
## project's sound_roles, then the profile's file for the role, then a file named like the role
## (the starter pack's door_open.wav). Only a role with no file at all becomes a question, filled
## in with the sound last chosen for that role in this editor session.

## "Pick on map" in a location field. Answer with callback.call(map_id, cell), or
## callback.call("", Vector2i(-1, -1)) when the pick is cancelled. The dialog hides while the
## pick is open and comes back with the answer.
signal pick_location_requested(callback: Callable, current: Variant)

## Last sound file chosen for each role in this editor session: {role: file}.
static var last_sounds: Dictionary = {}

var map_id := ""
var cell := Vector2i.ZERO
var template: Dictionary = {}
var data: RPGProjectData
var on_created: Callable
var undo_redo: Object
var _form: RPGFormBuilder
var _msg: Label
var _resolver: Callable
## {"sound_<role>": file} for roles found by file name rather than through the role table.
var _auto_sounds: Dictionary = {}
## Roles the maker is asked about.
var _asked_roles: Array = []
## Errors of the last Create attempt, dropped as their questions are answered.
var _errors: Array = []
var _hidden_for_pick: Array = []


static func open_for(p_map_id: String, p_cell: Vector2i, template_name: String, p_data: RPGProjectData, p_on_created: Callable, p_undo_redo: Object = null) -> RPGQuickEventDialog:
	var tpls := RPGQuickEvents.templates()
	if not tpls.has(template_name):
		push_error("RPG Kit: quick event template '%s' not found." % template_name)
		return null
	var d := RPGQuickEventDialog.new()
	d.setup(p_map_id, p_cell, tpls[template_name], p_data, p_on_created, p_undo_redo)
	var parent: Node = null
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		parent = Engine.get_singleton("EditorInterface").get_base_control()
	else:
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			parent = ml.root
	if parent != null:
		parent.add_child(d)
		d.popup_centered(Vector2i(560, 420))
	return d


## The file the runtime plays for a role (RPGAudio.role_file): the project's mapping, else the
## profile's first name for it, else the role itself.
static func runtime_sound_file(p_data: RPGProjectData, role: String) -> String:
	var roles: Dictionary = p_data.project.get("sound_roles", {}) if p_data != null else {}
	if roles.has(role):
		return str(roles[role])
	var prof := _profile(p_data)
	var f := str(prof.sound_role(role)) if prof != null else ""
	return f if f != "" else role


## How a sound role resolves in this project: {file, keep_role}. `file` is the first existing
## file of: the project's sound_roles, the profile's names for the role, a file named like the
## role ("" when none exists). `keep_role` is true when the runtime plays that same file for the
## role, so the event can keep {"role": ...}; otherwise the event should name the file.
static func resolve_sound_role(p_data: RPGProjectData, role: String) -> Dictionary:
	var cands: Array = []
	var roles: Dictionary = p_data.project.get("sound_roles", {}) if p_data != null else {}
	var mapped: Variant = roles.get(role)
	if mapped is String:
		cands.append(mapped)
	elif mapped is Array:
		cands.append_array(mapped)
	var prof := _profile(p_data)
	if prof != null:
		cands.append_array(Array(prof.sound_candidates(role)))
	cands.append(role)
	for c in cands:
		var f := str(c)
		if f != "" and RPGResourcePicker.exists("sound", f):
			return {"file": f, "keep_role": f == runtime_sound_file(p_data, role)}
	return {"file": "", "keep_role": false}


static func _profile(p_data: RPGProjectData) -> RPGProfile:
	var prof_name := str(p_data.profile.get("profile", "rm2k")) if p_data != null else "rm2k"
	return RPGProfile.load_profile(prof_name)


## Resolver for sound roles: role -> file name when the event can keep the role (the runtime
## finds that file for it), else "" (the event then needs an answer "sound_<role>").
static func sound_resolver(p_data: RPGProjectData) -> Callable:
	return func(role: String) -> String:
		var r := resolve_sound_role(p_data, role)
		return str(r.file) if r.keep_role else ""


## Answers {"sound_<role>": file} for the template's roles that exist only under another name
## (e.g. the starter pack's door_open.wav in an MV-style project whose profile says Open1).
static func auto_sound_answers(tpl: Dictionary, p_data: RPGProjectData) -> Dictionary:
	var out := {}
	for role in RPGQuickEvents.missing_sound_roles(tpl, func(_r): return ""):
		var r := resolve_sound_role(p_data, str(role))
		if str(r.file) != "" and not r.keep_role:
			out["sound_" + str(role)] = str(r.file)
	return out


## Compiles a template and appends the event to the map's events file (atomic write).
## Returns {ok, id, errors}.
static func create_event(p_map_id: String, p_cell: Vector2i, tpl: Dictionary, answers: Dictionary, p_data: RPGProjectData, resolver: Callable = Callable(), p_undo_redo: Object = null) -> Dictionary:
	var r := RPGQuickEvents.compile(tpl, answers, resolver, p_data)
	if not r.ok:
		return {"ok": false, "id": "", "errors": r.errors}
	var path := RPGValidator.events_path(p_data, p_map_id)
	var f := RPGEventsFile.open(path, p_map_id)
	if f.error != "":
		return {"ok": false, "id": "", "errors": [{"key": "", "message": f.error}]}
	var old_text := f.disk_text
	var ev: Dictionary = r.event
	ev["position"] = [p_cell.x, p_cell.y]
	var id := f.add_event(ev, RPGIds.slug("%s_%s" % [p_map_id, tpl.get("name", "event")]))
	var writer := RPGEventFileWriter.new()
	writer.data = p_data
	writer.map_id = p_map_id
	if p_undo_redo != null and p_undo_redo.has_method("create_action"):
		p_undo_redo.create_action("Quick event: %s" % tpl.get("name", ""))
		p_undo_redo.add_do_method(writer, "write", path, f.to_text())
		p_undo_redo.add_undo_method(writer, "write", path, old_text)
		p_undo_redo.commit_action(true)
	else:
		writer.write(path, f.to_text())
	if writer.last_error != OK:
		return {"ok": false, "id": "", "errors": [{"key": "", "message": "Could not write %s (error %d)." % [path, writer.last_error]}]}
	return {"ok": true, "id": id, "errors": []}


func setup(p_map_id: String, p_cell: Vector2i, tpl: Dictionary, p_data: RPGProjectData, p_on_created: Callable, p_undo_redo: Object = null) -> void:
	map_id = p_map_id
	cell = p_cell
	template = tpl
	data = p_data
	on_created = p_on_created
	undo_redo = p_undo_redo
	_resolver = sound_resolver(data)
	_auto_sounds = auto_sound_answers(tpl, data)
	title = "Quick event: %s" % tpl.get("name", "")
	ok_button_text = "Create"
	var vb := VBoxContainer.new()
	var intro := Label.new()
	intro.text = str(tpl.get("description", "")) + "\nCell (%d, %d) on map '%s'." % [cell.x, cell.y, map_id]
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrapping label needs a width, or the dialog measures it one word per line and
	# grows thousands of pixels tall.
	intro.custom_minimum_size.x = 520
	vb.add_child(intro)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 280)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var fields := RPGQuickEvents.form_fields(tpl)
	_asked_roles.clear()
	for role in RPGQuickEvents.missing_sound_roles(tpl, _resolver):
		if _auto_sounds.has("sound_" + str(role)):
			continue
		_asked_roles.append(role)
		var f := {"key": "sound_" + role, "kind": "resource", "res": "sound", "label": "Sound for '%s'" % role, "required": true,
			"help": "The asset pack has no sound for this role. Pick one."}
		var last := str(last_sounds.get(role, ""))
		if last != "" and RPGResourcePicker.exists("sound", last):
			f["default"] = last
		fields.append(f)
	_form = RPGFormBuilder.new()
	# Messages go to the fixed line below the form, so fields never move while it is filled.
	_form.setup(fields, data, null, {"map_id": map_id, "inline_errors": false})
	var defaults := {}
	for f in fields:
		if f.has("default"):
			defaults[f.key] = RPGJson.deep_copy(f.default)
	_form.set_value(defaults)
	_form.pick_location_requested.connect(request_pick_location)
	_form.value_changed.connect(_on_answer)
	sc.add_child(_form)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(520, 44)
	_msg.max_lines_visible = 2
	_msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_msg.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	vb.add_child(_msg)
	add_child(vb)
	get_ok_button().pressed.connect(_create)
	canceled.connect(queue_free)
	dialog_hide_on_ok = false
	_refresh_msg()


func answers() -> Dictionary:
	var out := _auto_sounds.duplicate()
	var v := _form.get_value()
	for k in v:
		out[k] = v[k]
	return out


## The message line: errors of the last Create still unanswered, then the form's own problems.
func message_text() -> String:
	return _msg.text


func _on_answer(key: String, _v: Variant) -> void:
	_errors = _errors.filter(func(e): return str(e.get("key", "")) != key and not str(e.get("key", "")).begins_with(key + "."))
	_refresh_msg()


func _refresh_msg() -> void:
	var lines := PackedStringArray()
	for e in _errors:
		lines.append(str(e.message))
	var keys := _errors.map(func(e): return str(e.get("key", "")))
	for p in _form.problems():
		if not keys.has(str(p.get("field", ""))):
			lines.append(str(p.message))
	_msg.text = "" if lines.is_empty() else lines[0] + ("  (and %d more)" % (lines.size() - 1) if lines.size() > 1 else "")


## Forwards "Pick on map" to the host and hides this dialog until the host answers.
func request_pick_location(callback: Callable, current: Variant = null) -> void:
	if _hidden_for_pick.is_empty():
		_hidden_for_pick = RPGEventEditor.hide_windows(self)
	pick_location_requested.emit(_on_pick_answer.bind(callback), current)


func _on_pick_answer(p_map_id: String, p_cell: Vector2i, callback: Callable) -> void:
	var wins := _hidden_for_pick
	_hidden_for_pick = []
	RPGEventEditor.show_windows(wins)
	if p_map_id != "" and callback.is_valid():
		callback.call(p_map_id, p_cell)


func _create() -> void:
	var given := answers()
	var r := create_event(map_id, cell, template, given, data, _resolver, undo_redo)
	if not r.ok:
		_errors = r.errors.duplicate()
		_refresh_msg()
		return
	for role in _asked_roles:
		var s: Variant = given.get("sound_" + str(role))
		var file := RPGResourcePicker.asset_name_of(s)
		if file != "":
			last_sounds[role] = file
	hide()
	if on_created.is_valid():
		on_created.call(r.id)
	queue_free()
