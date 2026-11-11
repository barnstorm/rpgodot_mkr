extends "res://tests/rpg_test_case.gd"
## Event editor, quick events, form widgets, event search and the Conditional Branch condition
## kinds (QA findings E13, E14, E16, E18, E20, E21, E22, E23).

const FIXTURE := "res://tests/fixtures/door_project"
const TMP := "user://rpg_event_editor_test"
const EXT_ROOT := "res://tests/fixtures/door_project/extensions"
const Env := preload("res://tests/rpg_test_env.gd")

var data: RPGProjectData
var registry: RPGCommandRegistry
var tpl: Dictionary


func before_each() -> void:
	_make_project()
	data = RPGProjectData.open(TMP + "/rpg")
	registry = RPGCommandRegistry.new()
	registry.load_all(["project", "broken_ext"], ["broken_ext"], EXT_ROOT)
	tpl = RPGQuickEvents.templates("res://nonexistent_quick_events")
	RPGQuickEventDialog.last_sounds.clear()


## A throwaway project: the door fixture plus the sample database.
func _make_project() -> void:
	_rm(TMP)
	var root := TMP + "/rpg"
	DirAccess.make_dir_recursive_absolute(root + "/maps")
	DirAccess.make_dir_recursive_absolute(root + "/database")
	for f in ["project.json", "state.json", "common_events.json"]:
		_copy(FIXTURE.path_join(f), root.path_join(f))
	for f in ["town.events.json", "town.map.json", "house_inside.events.json", "house_inside.map.json"]:
		_copy(FIXTURE.path_join("maps/" + f), root.path_join("maps/" + f))
	var d := DirAccess.open("res://rpg/database")
	for f in d.get_files():
		if f.ends_with(".json"):
			_copy("res://rpg/database/" + f, root.path_join("database/" + f))
	RPGJson.save_file(root.path_join("map_index.json"), {"schema_version": 1, "maps": [
		{"id": "town", "name": "Town", "parent": "", "order": 0},
		{"id": "house_inside", "name": "House", "parent": "town", "order": 1},
	], "favourites": []})


func _copy(from: String, to: String) -> void:
	var f := FileAccess.open(to, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(from))
	f.close()


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _events_path() -> String:
	return RPGValidator.events_path(data, "town")


func _open_editor(event_id: String) -> RPGEventEditor:
	return RPGEventEditor.open_for("town", event_id, data, registry, null, func(_id): pass)


## Replaces every {"role": from} in a deep copy of `v` with {"role": to}.
func _swap_role(v: Variant, from: String, to: String) -> Variant:
	if v is Dictionary:
		if v.size() == 1 and str(v.get("role", "")) == from:
			return {"role": to}
		var out := {}
		for k in v:
			out[k] = _swap_role(v[k], from, to)
		return out
	if v is Array:
		return v.map(func(x): return _swap_role(x, from, to))
	return v


# --------------------------------------------------------------------------------------------
# E14 quick event sounds
# --------------------------------------------------------------------------------------------

func test_e14_starter_sounds_found_by_role_name_in_mv_projects() -> void:
	data.profile["profile"] = "mv"
	data.project["sound_roles"] = {}
	var r := RPGQuickEventDialog.resolve_sound_role(data, "door_open")
	assert_eq(r.file, "door_open", "the starter pack's door_open.wav is used")
	# The role stays only when the runtime plays that same file for it; else the file is named.
	var runtime_plays := RPGQuickEventDialog.runtime_sound_file(data, "door_open")
	assert_eq(r.keep_role, runtime_plays == "door_open", "keep_role follows the runtime (%s)" % runtime_plays)
	var auto := RPGQuickEventDialog.auto_sound_answers(tpl.Door, data)
	assert_eq(auto.get("sound_door_open"), null if r.keep_role else "door_open")
	var d := RPGQuickEventDialog.new()
	d.setup("town", Vector2i(3, 3), tpl.Door, data, func(_id): pass)
	tree.root.add_child(d)
	await frames(1)
	assert_true(d._form.editor_for("sound_door_open") == null, "no sound question in an MV project")
	var answers := {"image": {"sheet": "objects", "index": 2}, "destination": {"map": "house_inside", "position": [5, 9]}}
	for k in answers:
		d._form.set_field(k, answers[k])
	var created := [""]
	d.on_created = func(id): created[0] = id
	d._create()
	assert_ne(created[0], "", "Create is not blocked: %s" % d.message_text())
	var ev := RPGEventsFile.open(_events_path(), "town").get_event(created[0])
	var by_file := JSON.stringify(ev).contains("\"file\":\"door_open\"")
	var by_role := JSON.stringify(ev).contains("\"role\":\"door_open\"") and runtime_plays == "door_open"
	assert_true(by_file or by_role, "the event plays door_open")


func test_e14_role_found_under_its_own_name_is_written_as_a_file() -> void:
	# A role whose mapped name is missing (like MV's Open1) falls back to door_open.wav, and the
	# event names that file so it plays whatever the runtime's role table says.
	data.project["sound_roles"] = {"door_open": "Open1"}
	var r := RPGQuickEventDialog.resolve_sound_role(data, "door_open")
	assert_eq(r, {"file": "door_open", "keep_role": false})
	assert_eq(RPGQuickEventDialog.auto_sound_answers(tpl.Door, data), {"sound_door_open": "door_open"})
	var answers := {"image": {"sheet": "objects", "index": 2}, "destination": {"map": "house_inside", "position": [5, 9]}, "sound_door_open": "door_open"}
	var res := RPGQuickEventDialog.create_event("town", Vector2i(2, 3), tpl.Door, answers, data, RPGQuickEventDialog.sound_resolver(data))
	assert_true(res.ok, str(res.errors))
	var ev := RPGEventsFile.open(_events_path(), "town").get_event(res.id)
	assert_true(JSON.stringify(ev).contains("\"file\":\"door_open\""), "the event names the file")


func test_e14_role_kept_when_profile_finds_it_and_project_mapping_wins() -> void:
	data.profile["profile"] = "rm2k"
	var r := RPGQuickEventDialog.resolve_sound_role(data, "step")
	assert_eq(r, {"file": "step", "keep_role": true}, "2000-style projects keep the role")
	data.project["sound_roles"] = {"step": "cursor"}
	assert_eq(RPGQuickEventDialog.resolve_sound_role(data, "step"), {"file": "cursor", "keep_role": true})
	data.project["sound_roles"] = {"step": "no_such_sound"}
	assert_eq(RPGQuickEventDialog.resolve_sound_role(data, "step"), {"file": "step", "keep_role": false}, "a broken mapping falls back, with the file named")
	assert_eq(RPGQuickEventDialog.resolve_sound_role(data, "zz_no_role"), {"file": "", "keep_role": false})


func test_e14_last_sound_for_a_role_is_remembered() -> void:
	var t: Dictionary = tpl.Door.duplicate(true)
	t["event"] = _swap_role(t.event, "door_open", "zz_creak")
	RPGQuickEventDialog.last_sounds["zz_creak"] = "cursor"
	var d := RPGQuickEventDialog.new()
	d.setup("town", Vector2i(4, 3), t, data, func(_id): pass)
	tree.root.add_child(d)
	await frames(1)
	assert_true(d._form.editor_for("sound_zz_creak") != null, "a role with no file is asked")
	assert_eq(d._form.get_field("sound_zz_creak"), "cursor", "prefilled with the last choice")
	d._form.set_field("image", {"sheet": "objects", "index": 2})
	d._form.set_field("destination", {"map": "house_inside", "position": [5, 9]})
	d._form.set_field("sound_zz_creak", "decision")
	var created := [""]
	d.on_created = func(id): created[0] = id
	d._create()
	assert_ne(created[0], "", d.message_text())
	assert_eq(RPGQuickEventDialog.last_sounds.get("zz_creak"), "decision", "the new choice is remembered")


# --------------------------------------------------------------------------------------------
# E16 quick event form messages, sound picker Enter
# --------------------------------------------------------------------------------------------

func test_e16_messages_do_not_move_fields_and_stale_errors_clear() -> void:
	var d := RPGQuickEventDialog.new()
	d.setup("town", Vector2i(5, 5), tpl.Transfer, data, func(_id): pass)
	tree.root.add_child(d)
	await frames(2)
	for k in d._form._editors:
		assert_false(d._form._editors[k].error.visible, "no message line under '%s'" % k)
	var row: Control = d._form._editors["facing"].row
	var y0 := row.position.y
	d._create()
	assert_true(d.message_text().contains("Where to?"), "Create names the missing answer: %s" % d.message_text())
	d._form.set_field("destination", {"map": "house_inside", "position": [2, 2]})
	await frames(2)
	assert_false(d.message_text().contains("Where to?"), "answered: the message is gone (%s)" % d.message_text())
	assert_eq(row.position.y, y0, "fields below did not move")
	d.queue_free()


func test_e16_enter_in_sound_search_chooses_the_match() -> void:
	var p := RPGResourcePicker.new("sound", "")
	tree.root.add_child(p)
	await frames(1)
	p.open_with_search("cursor")
	p._search.text_submitted.emit("cursor")
	assert_eq(p.get_value(), "cursor", "Enter chose the only match")
	p.open_with_search("de")
	p.choose_highlighted()
	assert_ne(str(p.get_value()), "", "Enter chose the highlighted match")
	assert_ne(str(p.get_value()), "cursor")
	p.queue_free()


# --------------------------------------------------------------------------------------------
# E13 / E22 location picks
# --------------------------------------------------------------------------------------------

func test_e13_quick_dialog_pick_on_map_reaches_the_host_and_fills_the_field() -> void:
	var d := RPGQuickEventDialog.new()
	d.setup("town", Vector2i(5, 5), tpl.Transfer, data, func(_id): pass)
	tree.root.add_child(d)
	d.popup_centered(Vector2i(560, 420))
	await frames(1)
	var asked := [null]
	d.pick_location_requested.connect(func(cb: Callable, _cur): asked[0] = cb)
	var loc: Control = d._form.editor_for("destination")
	var pick: Button = loc.get_child(loc.get_child_count() - 1)
	pick.pressed.emit()
	assert_true(asked[0] is Callable, "the host got the request")
	assert_false(d.visible, "the dialog steps aside while the map is clicked")
	asked[0].call("house_inside", Vector2i(3, 4))
	assert_true(d.visible, "and comes back")
	assert_eq(d._form.get_field("destination").get("map"), "house_inside")
	assert_eq(d._form.get_field("destination").get("position"), [3, 4])
	d.queue_free()


func test_e22_event_editor_and_command_dialog_step_aside_during_a_pick() -> void:
	var win := _open_editor("town_house_door")
	await frames(2)
	var dlg: ConfirmationDialog = win._cmd_list._open_command_dialog({"type": "transfer_player", "to": {"map": "town", "position": [1, 1]}}, func(_v): pass)
	await frames(1)
	assert_true(dlg.visible)
	var asked := [null]
	win.pick_location_requested.connect(func(cb: Callable, _cur): asked[0] = cb)
	var answered := [false]
	win._cmd_list.pick_location_requested.emit(func(_m, _c): answered[0] = true, null)
	assert_false(win.visible, "editor hidden")
	assert_false(dlg.visible, "command dialog hidden")
	asked[0].call("", Vector2i(-1, -1))
	assert_true(win.visible and dlg.visible, "a cancelled pick brings both back")
	assert_false(answered[0], "a cancel does not fill the field")
	win._cmd_list.pick_location_requested.emit(func(_m, _c): answered[0] = true, null)
	asked[0].call("town", Vector2i(2, 2))
	assert_true(answered[0] and win.visible and dlg.visible)
	dlg.queue_free()
	win.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# E18 new events
# --------------------------------------------------------------------------------------------

func test_e18_cancelled_new_event_is_never_created() -> void:
	var before := RPGEventsFile.open(_events_path(), "town").ids()
	var win := RPGEventEditor.open_new("town", Vector2i(15, 15), data, registry, null, func(_id): pass)
	await frames(2)
	assert_true(win.is_new)
	assert_eq(win.event_id, "event_15_15")
	assert_eq(RPGEventsFile.open(_events_path(), "town").ids(), before, "nothing written on open")
	var closed := [false]
	win.closed.connect(func(): closed[0] = true)
	win.cancel()
	assert_true(closed[0], "an untouched new event closes at once")
	assert_eq(RPGEventsFile.open(_events_path(), "town").ids(), before, "nothing written on cancel")
	await frames(1)


func test_e18_new_event_is_created_on_ok() -> void:
	var saved := [""]
	var win := RPGEventEditor.open_new("town", Vector2i(14, 2), data, registry, null, func(id): saved[0] = id)
	await frames(2)
	win.set_event_name("Old man")
	win.ok()
	var ev := RPGEventsFile.open(_events_path(), "town").get_event("event_14_2")
	assert_eq(ev.get("position"), [14, 2])
	assert_eq(ev.get("name"), "Old man")
	assert_eq(saved[0], "event_14_2")
	await frames(1)


# --------------------------------------------------------------------------------------------
# E20 footer messages and line numbers
# --------------------------------------------------------------------------------------------

func test_e20_check_uses_bbcode_and_json_messages_clear() -> void:
	var win := _open_editor("town_house_door")
	await frames(2)
	assert_true(win._problems.bbcode_enabled)
	win.show_problems([])
	assert_eq(win._problems.get_parsed_text(), "No problems found.", "no raw [color] tags")
	win._json_toggle.button_pressed = true
	var good: String = win._json_edit.text
	win._json_edit.text = "xx" + good
	win._on_json_text()
	assert_false(win.apply())
	assert_true(win._status.text.contains("Line 1:"), "lines count from 1: %s" % win._status.text)
	win._json_edit.text = good
	win._on_json_text()
	assert_eq(win._status.text, "", "fixed JSON clears the footer")
	win._json_toggle.button_pressed = false
	win.queue_free()
	await frames(1)


func test_e20_form_json_widget_counts_lines_from_one() -> void:
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup([{"key": "default", "kind": "json", "label": "Starting value"}], data)
	form.set_value({"default": 0})
	var te: TextEdit = form.editor_for("default").get_child(0)
	te.text = "abc"
	te.text_changed.emit()
	var msg: Label = form.editor_for("default").get_child(1)
	assert_true(msg.text.begins_with("Line 1:"), msg.text)
	form.queue_free()


# --------------------------------------------------------------------------------------------
# E21 event search
# --------------------------------------------------------------------------------------------

func test_e21_choice_branch_listed_once_and_conditions_readable() -> void:
	var f := RPGEventsFile.open(_events_path(), "town")
	f.events().append({"id": "old_man", "name": "Old man", "position": [9, 9], "notes": "", "pages": [
		RPGQuickEvents.complete_page({"commands": [{"type": "show_choices", "choices": [
			{"label": "Sure!", "then": [{"type": "set_switch", "id": "cat_quest", "value": "on"}]},
			{"label": "Sorry, no", "then": []}]}]}),
		RPGQuickEvents.complete_page({"conditions": [{"kind": "switch", "id": "cat_quest", "value": true}]}),
	]})
	assert_eq(f.save(), OK)
	var d2 := RPGProjectData.open(TMP + "/rpg")
	var hits := RPGProjectSearch.search(d2, registry, {"ref": "cat_quest"})
	assert_eq(hits.size(), 2, "the command and the page condition: %s" % str(hits.map(func(h): return h.summary)))
	var summaries := hits.map(func(h): return str(h.summary))
	assert_has(summaries, "Page 2 condition: Switch [cat_quest] is ON")
	assert_eq(RPGProjectSearch.search(d2, registry, {"text": "cat_quest"}).size(), 1, "text search lists it once")


# --------------------------------------------------------------------------------------------
# E23 event editor rough edges
# --------------------------------------------------------------------------------------------

func test_e23_new_page_switches_to_it() -> void:
	var win := _open_editor("town_house_door")
	await frames(2)
	var n: int = win.event.pages.size()
	win.new_page()
	assert_eq(win.current_page(), n, "the new page is shown")
	assert_eq(win._tabs.current_tab, n)
	win.queue_free()
	await frames(1)


func test_e23_show_text_needs_text() -> void:
	var cle := RPGCommandListEditor.new()
	tree.root.add_child(cle)
	cle.setup(data, registry, "town")
	var got := [null]
	var dlg := cle._open_command_dialog({"type": "show_text", "text": ""}, func(v): got[0] = v)
	await frames(1)
	dlg.get_ok_button().pressed.emit()
	assert_eq(got[0], null, "empty text is refused")
	assert_true(is_instance_valid(dlg) and dlg.visible, "the dialog stays open")
	var footer: Label = dlg.find_child("Problems", true, false)
	assert_true(footer.text.contains("required"), footer.text)
	var form: RPGFormBuilder = dlg.find_child("Form", true, false)
	form.set_field("text", "Hello")
	dlg.get_ok_button().pressed.emit()
	assert_eq(got[0].get("text") if got[0] is Dictionary else null, "Hello")
	cle.queue_free()
	await frames(1)


func test_e23_graphic_draws_the_chosen_frame() -> void:
	var tex := RPGFormBuilder.charset_frame_texture(data, "hero", 2, "left", 0)
	assert_true(tex is AtlasTexture, "a frame texture")
	if tex is AtlasTexture:
		var sheet := RPGResourcePicker.texture("charset", "hero")
		var prof := RPGAssets.sheet_profile("charset", "hero", "rm2k")
		assert_eq(Rect2i(tex.region), RPGCharset.frame_rect(prof, Vector2i(sheet.get_width(), sheet.get_height()), 2, "left", 0, false))
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup(RPGEventEditor.PAGE_FIELDS, data, registry, {"map_id": "town"})
	form.set_value({"graphic": {"sheet": "hero", "index": 1, "facing": "up", "frame": 1}})
	var pics := form.editor_for("graphic").find_children("*", "TextureRect", true, false).filter(func(t): return t.texture is AtlasTexture)
	assert_eq(pics.size(), 1, "the chosen character is drawn")
	var picked := [-1]
	var pop := form.pick_character(form, "hero", func(i): picked[0] = i)
	var buttons := pop.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), RPGFormBuilder.charset_count(data, "hero"), "one button per character")
	buttons[3].pressed.emit()
	assert_eq(picked[0], 3)
	form.queue_free()
	await frames(1)


func test_e23_move_route_character_is_a_dropdown() -> void:
	var form := RPGFormBuilder.for_command("move_route", registry, data, {"map_id": "town"})
	tree.root.add_child(form)
	form.set_value({"type": "move_route", "target": "this", "steps": []})
	var picker: Control = form.editor_for("target")
	assert_true(picker is RPGRefPicker, "a dropdown, not a text box")
	if picker is RPGRefPicker:
		assert_eq(picker._button.text, "This event")
		assert_eq(picker.allow, ["player", "this"])
		var ids: Array = picker.entries().map(func(e): return e.id)
		assert_has(ids, "town_house_door", "the map's events are listed")
	form.queue_free()


func test_e23_condition_kinds_and_choices_summary() -> void:
	var branch := RPGConditionEditor.new(data, registry, false, {}, true)
	var page := RPGConditionEditor.new(data, registry, false, {})
	for k in ["actor", "facing", "button", "item"]:
		assert_has(branch.kinds(), k)
	assert_false(page.kinds().has("facing"), "facing is a Conditional Branch condition")
	tree.root.add_child(branch)
	branch.set_value({"kind": "actor", "id": "hero", "check": "skill", "skill": "heal", "class": "warrior"})
	branch.form().set_field("skill", "fire")
	assert_eq(branch.get_value(), {"kind": "actor", "id": "hero", "check": "skill", "skill": "fire"}, "fields of other checks are dropped")
	branch.queue_free()
	page.free()
	var summary := registry.summary({"type": "show_choices", "choices": [{"label": "Sure!", "then": []}, {"label": "Sorry, no", "then": []}]})
	assert_eq(summary, "Choices: [Sure!] [Sorry, no]")
	var probs := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [{"id": "c", "name": "", "position": [0, 0], "notes": "",
		"pages": [RPGQuickEvents.complete_page({"commands": [
			{"type": "if", "condition": {"kind": "facing", "target": "player", "facing": "up"}, "then": [], "else": []},
			{"type": "if", "condition": {"kind": "actor", "id": "hero", "check": "state", "state": "poison"}, "then": [], "else": []},
			{"type": "if", "condition": {"kind": "button", "button": "ok"}, "then": [], "else": []}]})]}]}, registry, "test")
	assert_eq(probs, [], "the new kinds validate")


func test_e23_escape_closes_with_a_text_field_focused() -> void:
	var win := _open_editor("town_house_door")
	await frames(2)
	var closed := [false]
	win.closed.connect(func(): closed[0] = true)
	win._name_edit.grab_focus()
	await frames(1)
	assert_true(win.gui_get_focus_owner() == win._name_edit, "the name field has focus")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	win.push_input(ev)
	assert_true(closed[0], "Escape closed the editor")
	await frames(1)


# --------------------------------------------------------------------------------------------
# Runtime: new Conditional Branch kinds
# --------------------------------------------------------------------------------------------

func test_runtime_actor_facing_and_button_conditions() -> void:
	var env = Env.create(tree, TMP + "/rpg")   # the door fixture plus the sample database (actors)
	var r: RPGResult = await env.start_on("town", Vector2i(12, 8), "up")
	assert_true(r.is_ok(), str(r))
	var st: RPGGameState = env.rpg.state
	var b: Variant = st.actor("hero")
	b.class_id = "warrior"
	b.skills.append("heal")
	b.equips["weapon"] = "iron_sword"
	b.add_state("poison")
	b.name = "Alex"
	assert_true(st.check_condition({"kind": "actor", "id": "hero", "check": "class", "class": "warrior"}))
	assert_false(st.check_condition({"kind": "actor", "id": "hero", "check": "class", "class": "mage"}))
	assert_true(st.check_condition({"kind": "actor", "id": "hero", "check": "skill", "skill": "heal"}))
	assert_false(st.check_condition({"kind": "actor", "id": "hero", "check": "skill", "skill": "fire"}))
	assert_true(st.check_condition({"kind": "actor", "id": "hero", "check": "weapon", "weapon": "iron_sword"}))
	assert_true(st.check_condition({"kind": "actor", "id": "hero", "check": "state", "state": "poison"}))
	assert_true(st.check_condition({"kind": "actor", "id": "hero", "check": "name", "name": "Alex"}))
	assert_eq(st.check_condition({"kind": "actor", "id": "hero"}), st.in_party("hero"), "old actor conditions still mean 'in the party'")
	var cmds := [
		{"type": "if", "condition": {"kind": "facing", "target": "player", "facing": "up"},
			"then": [{"type": "set_variable", "id": "counter", "value": 1}], "else": [{"type": "set_variable", "id": "counter", "value": 2}]},
	]
	r = await env.rpg.run_commands(cmds)
	assert_true(r.is_ok(), str(r))
	assert_eq(int(env.rpg.get_variable("counter")), 1, "the player faces up")
	Input.action_press("rpg_ok")
	assert_true(st.check_condition({"kind": "button", "button": "ok"}))
	Input.action_release("rpg_ok")
	assert_false(st.check_condition({"kind": "button", "button": "ok"}))
	await env.destroy()
