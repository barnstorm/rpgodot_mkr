extends "res://tests/rpg_test_case.gd"
## Database tab UI: the visual troop editor, the starting-items list, the face picker for
## {sheet, index} values, the capped form column with record previews, the enemy action
## condition / slip editors, ID retirement on rename, and Switches + Variables sharing state.json.

const FIXTURE := "res://tests/fixtures/door_project"
## Per process: other runs of this suite (in parallel) must not share the project folder.
var TMP := "user://rpg_database_ui_test_%d" % OS.get_process_id()
const EXT_ROOT := "res://tests/fixtures/door_project/extensions"
const TroopEditor := preload("res://addons/rpg/editor/database/rpg_troop_editor.gd")

var screen: RPGDatabaseScreen
var host: Control


func before_each() -> void:
	_make_project()


func after_each() -> void:
	if host != null and is_instance_valid(host):
		host.queue_free()
		host = null
		screen = null
		await frames(1)
	_rm(TMP)


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


func _open_screen() -> void:
	# A fixed-size host: the headless window is small.
	host = Control.new()
	host.size = Vector2(1400, 860)
	tree.root.add_child(host)
	screen = RPGDatabaseScreen.new()
	host.add_child(screen)
	screen.setup(null, TMP + "/rpg")
	await frames(2)


func _tab(type: String) -> RPGRecordTab:
	for t in screen._record_tabs:
		if str(t.config.get("type", "")) == type:
			return t
	return null


func _select_id(tab: RPGRecordTab, id: String) -> void:
	var recs := tab.records()
	for i in recs.size():
		if str(recs[i].get("id", "")) == id:
			tab.select(i)
			return
	fail("no record %s" % id)


func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out


func _click(te: Control, at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	te._canvas_input(ev)


func _motion(te: Control, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	te._canvas_input(ev)


# --------------------------------------------------------------------------------------------
# Visual troop editor
# --------------------------------------------------------------------------------------------

func test_troop_editor_draws_like_the_battle_scene_and_drags() -> void:
	await _open_screen()
	var tab := _tab("troops")
	_select_id(tab, "slimes")
	var te: Control = tab._form.editor_for("members")
	assert_true(te != null and te.get_script() == TroopEditor, "Enemy groups use the visual troop editor")
	if te == null or te.get_script() != TroopEditor:
		return
	assert_eq(te.members.size(), 2)
	# battle_scene.gd: centred on the position, kept above the party windows (y <= 160 - 4 - h).
	var slime := RPGResourcePicker.texture("battler", "slime")
	assert_true(slime != null, "slime battler loads")
	var sz := slime.get_size()
	var r: Rect2 = te.member_rect(0)
	assert_eq(r, Rect2(120 - sz.x / 2, minf(150 - sz.y / 2, 160 - 4 - sz.y), sz.x, sz.y), "drawn where the battle draws it")
	assert_eq(te.member_at(r.get_center()), 0)
	assert_false(tab.dirty)
	# Drag the first slime.
	var start: Vector2 = r.get_center() * TroopEditor.SCALE
	_click(te, start, true)
	assert_eq(te.selected, 0, "click selects")
	_motion(te, start + Vector2(61, -40.6))
	_motion(te, start + Vector2(61.4, -41))
	_click(te, start + Vector2(61.4, -41), false)
	var pos: Array = tab.current_record().members[0].position
	assert_eq(typeof(pos[0]), TYPE_INT, "snapped to whole pixels")
	assert_eq(pos, [roundi(r.get_center().x + 30.7), roundi(r.get_center().y - 20.5)], "position written to the record")
	assert_true(tab.dirty, "tab marked dirty")
	assert_eq(tab.current_record().members[1].position, [200, 150], "other enemy unchanged")
	# The list below follows.
	var list: RPGListEditor = te.list
	assert_eq(list.get_value()[0].position, pos, "list in sync")
	# Add from the picker, then remove with Delete.
	te.add_enemy("bat")
	assert_eq(tab.current_record().members.size(), 3)
	assert_eq(tab.current_record().members[2].enemy, "bat")
	assert_eq(te.selected, 2, "new enemy selected")
	assert_eq(list.get_value().size(), 3)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_DELETE
	te._canvas_input(key)
	assert_eq(tab.current_record().members.size(), 2, "Delete removes the selected enemy")
	assert_eq(list.get_value().size(), 2)
	# Arrow keys nudge.
	te.select_member(1)
	var before: Array = tab.current_record().members[1].position.duplicate()
	var right := InputEventKey.new()
	right.pressed = true
	right.keycode = KEY_LEFT
	te._canvas_input(right)
	assert_eq(tab.current_record().members[1].position[0], int(before[0]) - 1, "arrow key nudges")
	# "Appears later" stays in the list rows.
	var hidden_boxes := _find(list, func(n): return n is CheckBox and n.text.begins_with("Appears later"))
	assert_eq(hidden_boxes.size(), 2, "Appears later per row")
	# Editing in the list redraws the picture.
	var edited: Array = list.get_value()
	edited[1].position = [250, 100]
	list.set_value(edited)
	list.value_changed.emit(list.get_value())
	assert_eq(te.members[1].position, [250, 100])
	assert_eq(tab.current_record().members[1].position, [250, 100])
	# Save writes the new positions.
	assert_true(tab.save_now())
	var saved: Dictionary = RPGJson.parse_file(TMP + "/rpg/database/troops.json").data
	assert_eq(saved.records[0].members[0].position, pos)


func test_troop_editor_auto_arrange_spreads_evenly() -> void:
	await _open_screen()
	var tab := _tab("troops")
	_select_id(tab, "goblin_boss")
	var te: Control = tab._form.editor_for("members")
	te.auto_arrange()
	var m: Array = tab.current_record().members
	assert_eq(m.size(), 3)
	var xs := []
	for x in m:
		xs.append(x.position[0])
		assert_eq(typeof(x.position[1]), TYPE_INT)
	assert_eq(xs, [80, 160, 240], "evenly spaced across 320 pixels")
	# Feet on one line: bottoms of the drawn rectangles match.
	var bottoms := []
	for i in m.size():
		var r: Rect2 = te.member_rect(i)
		bottoms.append(r.position.y + r.size.y)
		assert_true(r.position.y + r.size.y <= 156, "above the party windows")
	assert_true(absf(bottoms[0] - bottoms[1]) <= 1 and absf(bottoms[1] - bottoms[2]) <= 1, str(bottoms))
	# Many enemies: two rows, still inside the field.
	for i in 5:
		te.add_enemy("slime")
	te.auto_arrange()
	for i in te.members.size():
		var r: Rect2 = te.member_rect(i)
		assert_true(r.position.x >= -1 and r.end.x <= 321 and r.position.y >= 0, "row %d inside: %s" % [i, str(r)])
	assert_true(tab.dirty)


func test_troop_editor_without_a_battler_image_uses_a_placeholder() -> void:
	var te: Control = TroopEditor.new()
	var data := RPGProjectData.open(TMP + "/rpg")
	te.setup({"key": "members", "item_fields": []}, data)
	tree.root.add_child(te)
	te.set_value([{"enemy": "missing_enemy", "position": [0, 0]}])
	var r: Rect2 = te.member_rect(0)
	assert_eq(r.size, TroopEditor.SILHOUETTE)
	assert_eq(r.get_center(), Vector2(160, 100), "no position: the battle scene's default spot")
	te.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# System: starting items
# --------------------------------------------------------------------------------------------

func test_starting_items_is_a_list_not_json() -> void:
	await _open_screen()
	var form: RPGFormBuilder = _find(screen, func(n): return n is RPGFormBuilder and n.name == "SystemForm")[0]
	var ed := form.editor_for("starting_items")
	assert_true(ed != null)
	assert_eq(_find(ed, func(n): return n is TextEdit).size(), 0, "no raw JSON box")
	var pickers := _find(ed, func(n): return n is RPGRefPicker)
	assert_eq(pickers.size(), 1, "one row for {potion: 2}")
	assert_eq(pickers[0].get_value(), "potion")
	var spins := _find(ed, func(n): return n is SpinBox)
	assert_eq(int(spins[0].value), 2)
	# Change the count, add a row (first unused item), remove the first row.
	spins[0].value = 5
	assert_eq(screen._system_edits.starting_items, {"potion": 5})
	var add: Button = _find(ed, func(n): return n is Button and n.text == "+ Add")[0]
	add.pressed.emit()
	var v: Dictionary = screen._system_edits.starting_items
	assert_eq(v.size(), 2, "a new item row counts at once: %s" % str(v))
	assert_eq(v.potion, 5)
	var second := ""
	for k in v:
		if k != "potion":
			second = k
	assert_true(screen.data.has_record("items", second), "the new row picked an existing item")
	var remove: Button = _find(ed, func(n): return n is Button and n.text == "✕")[0]
	remove.pressed.emit()
	assert_eq(screen._system_edits.starting_items, {second: 1})
	assert_eq(screen.save_system(), OK)
	var sys: Dictionary = RPGJson.parse_file(TMP + "/rpg/database/system.json").data
	assert_eq(sys.system.starting_items, {second: 1})
	assert_eq(typeof(sys.system.starting_items[second]), TYPE_INT)


func test_enemy_conditions_and_slip_have_forms() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var states := RPGRecordSchemas.fields_for("states", [], [{"id": "hp"}, {"id": "mp"}])
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup(states, data)
	form.set_value({"id": "poison", "slip": {"can_kill": false, "percent": 10, "resource": "hp"}})
	var slip := form.editor_for("slip")
	assert_eq(_find(slip, func(n): return n is TextEdit).size(), 0, "slip is a form")
	var on: CheckBox = _find(slip, func(n): return n is CheckBox and n.text.begins_with("Takes damage"))[0]
	assert_true(on.button_pressed)
	on.button_pressed = false
	assert_eq(form.get_value().slip, {}, "off = no slip damage (runtime reads an empty dictionary)")
	on.button_pressed = true
	assert_eq(form.get_value().slip.percent, 10)
	form.set_value({"id": "sleep"})
	assert_false(on.button_pressed, "no slip key = off")
	assert_eq(form.get_value().has("slip"), false, "untouched value unchanged")
	form.queue_free()
	var enemies := RPGRecordSchemas.fields_for("enemies")
	var actions: Dictionary = enemies.filter(func(f): return f.key == "actions")[0]
	var cond: Dictionary = actions.item_fields.filter(func(f): return f.key == "condition")[0]
	assert_false(cond.fields.is_empty(), "action condition has fields")
	var le := RPGListEditor.new(actions, data)
	tree.root.add_child(le)
	le.set_value([{"condition": {"kind": "turn", "every": 3, "n": 3}, "rating": 6, "skill": "attack"}])
	assert_eq(_find(le, func(n): return n is TextEdit).size(), 0, "no raw JSON in action patterns")
	assert_eq(le.get_value()[0].condition, {"kind": "turn", "every": 3, "n": 3}, "round trip")
	le.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# Face picker with {sheet, index} (Show Text)
# --------------------------------------------------------------------------------------------

func test_show_text_face_shows_the_chosen_face() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var reg := RPGCommandRegistry.new()
	reg.load_all(["project"], [], EXT_ROOT)
	var form := RPGFormBuilder.for_command("show_text", reg, data)
	tree.root.add_child(form)
	var cmd := {"type": "show_text", "face": {"sheet": "hero_face", "index": 6}, "text": "Hi"}
	form.set_value(cmd)
	var ed := form.editor_for("face")
	var picker: RPGResourcePicker = _find(ed, func(n): return n is RPGResourcePicker)[0]
	var btn: Button = picker._button
	assert_eq(btn.text.find("{"), -1, "no raw JSON: %s" % btn.text)
	assert_eq(btn.text.find("missing"), -1, btn.text)
	assert_true(btn.text.begins_with("hero_face"), btn.text)
	assert_true(RPGResourcePicker.exists("faceset", RPGResourcePicker.asset_name_of(cmd.face)), "the sheet is found")
	var thumbs := _find(ed, func(n): return n is TextureRect and n.texture is AtlasTexture)
	assert_eq(thumbs.size(), 1, "face thumbnail")
	if thumbs.size() == 1:
		assert_eq(thumbs[0].texture.region, Rect2(96, 48, 48, 48), "face #6 of a 4x4 sheet")
	var idx: SpinBox = _find(ed, func(n): return n is SpinBox)[0]
	assert_true(idx.visible)
	assert_eq(int(idx.value), 6)
	assert_eq(form.get_value(), cmd, "round trip unchanged")
	idx.value = 2
	assert_eq(form.get_value().face, {"sheet": "hero_face", "index": 2})
	# null stays null; the actor form's plain sheet name stays a string.
	form.set_value({"type": "show_text", "face": null, "text": "x"})
	assert_eq(form.get_value().face, null)
	form.queue_free()
	var actor_fields := RPGRecordSchemas.fields_for("actors")
	var af := RPGFormBuilder.new()
	tree.root.add_child(af)
	af.setup(actor_fields, data)
	af.set_value({"id": "hero", "face": "hero_face", "face_index": 0})
	var aed := af.editor_for("face")
	var aidx: SpinBox = _find(aed, func(n): return n is SpinBox)[0]
	assert_false(aidx.visible, "actors keep the index in Face #")
	af.set_field("face_index", 5)
	var athumbs := _find(aed, func(n): return n is TextureRect and n.texture is AtlasTexture)
	assert_eq(athumbs.size(), 1)
	if athumbs.size() == 1:
		assert_eq(athumbs[0].texture.region, Rect2(48, 48, 48, 48), "thumbnail follows Face #")
	var ap: RPGResourcePicker = _find(aed, func(n): return n is RPGResourcePicker)[0]
	ap.value_changed.emit("hero_face")
	assert_eq(af.get_value().face, "hero_face", "still a plain name")
	af.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------------------------

func test_form_column_is_capped_and_actors_get_a_preview() -> void:
	await _open_screen()
	var tab := _tab("actors")
	screen._tabs.current_tab = tab.get_index()
	_select_id(tab, "hero")
	await frames(3)
	assert_true(tab.size.x > 1000, "wide screen: %s" % str(tab.size))
	assert_true(tab._form.size.x <= 721, "form column capped: %s" % str(tab._form.size))
	assert_true(tab._preview_box.visible, "actor preview shown")
	var pics := _find(tab._preview_box, func(n): return n is TextureRect and n.texture != null)
	assert_true(pics.size() >= 5, "4 facings + face: %d" % pics.size())
	assert_true(tab._preview_box.position.x >= tab._form.size.x, "preview beside the form")
	# Changing the sprite index rebuilds the preview.
	tab._form.set_field("charset_index", 1)
	var pics2 := _find(tab._preview_box, func(n): return n is TextureRect and n.texture is AtlasTexture)
	assert_true(not pics2.is_empty())
	var en := _tab("enemies")
	_select_id(en, "slime")
	assert_true(en._preview_box.visible, "enemy preview")
	assert_false(_tab("items")._preview_box.visible, "no preview for items")


# --------------------------------------------------------------------------------------------
# Bugs: rename retires the old ID; Switches + Variables share state.json
# --------------------------------------------------------------------------------------------

func test_rename_retires_the_old_id() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var reg := RPGCommandRegistry.new()
	reg.load_all(["project"], [], EXT_ROOT)
	var r := RPGValidator.rename_id(data, reg, "item", "potion", "red_potion")
	assert_true(r.ok, r.error)
	var items: Dictionary = r.data_by_file[TMP + "/rpg/database/items.json"]
	assert_has(items.retired_ids, "potion", "old ID retired")
	var r2 := RPGValidator.rename_id(data, reg, "switch", "door_unlocked", "door_open")
	assert_true(r2.ok, r2.error)
	assert_has(r2.data_by_file[TMP + "/rpg/state.json"].retired_ids, "door_unlocked")
	# Through the Database screen: after the rename, New never hands out the old ID.
	await _open_screen()
	var res := screen.rename_id_transaction("item", "potion", "red_potion")
	assert_true(res.ok, res.error)
	screen.reload()
	await frames(1)
	var tab := _tab("items")
	tab.config.new_id_base = "potion"
	tab.new_record()
	assert_ne(tab.current_record().id, "potion", "renamed-away ID is not reused")
	screen.reload(false)
	# Another record cannot take a retired ID (D10: only the record that had it can go back).
	var back := screen.rename_id_transaction("item", "hi_potion", "potion")
	assert_false(back.ok, "retired ID refused as a new name")
	assert_true(str(back.error).contains("never reused"), back.error)


func test_switches_and_variables_save_together() -> void:
	await _open_screen()
	var sw := _tab("switches")
	var va := _tab("variables")
	assert_true(sw != null and va != null)
	sw.select(0)
	sw._form.set_field("label", "Edited switch")
	va.new_record()
	var new_var: String = va.current_record().id
	assert_true(sw.dirty and va.dirty)
	assert_true(sw.save_now())
	assert_false(sw.dirty)
	assert_false(va.dirty, "the variables tab was written too, so it is not unsaved")
	var st: Dictionary = RPGJson.parse_file(TMP + "/rpg/state.json").data
	assert_eq(st.switches[0].label, "Edited switch")
	assert_true(st.variables.any(func(v): return v.id == new_var), "variable edit saved")
	assert_true(screen.data.variables.has(new_var), "variable registry refreshed too")
	assert_true(screen.dirty_tabs().is_empty())


# --------------------------------------------------------------------------------------------
# VX/Ace tutorial items: vehicles, vehicle condition, operands, description, autoname, tiles
# --------------------------------------------------------------------------------------------

func _system_form() -> RPGFormBuilder:
	return _find(screen, func(n): return n is RPGFormBuilder and n.name == "SystemForm")[0]


func test_vehicles_in_system_tab_merge_leaf_by_leaf() -> void:
	await _open_screen()
	var form := _system_form()
	var ed := form.editor_for("vehicles")
	assert_true(ed != null, "Vehicles section")
	var subs := _find(ed, func(n): return n is RPGFormBuilder and n.fields.any(func(f): return f.key == "speed"))
	assert_eq(subs.size(), 3, "boat, ship, airship")
	var boat: RPGFormBuilder = subs[0]
	assert_true(boat.editor_for("graphic") != null and boat.editor_for("start") != null and boat.editor_for("bgm") != null)
	assert_eq(_find(boat, func(n): return n is Button and n.text.begins_with("Pick on map")).size(), 1, "start has Pick on map")
	# Meanwhile the RPG tab sets the boat's start on disk ("Set starting position > Boat").
	var sys_path := TMP + "/rpg/database/system.json"
	var disk: Dictionary = RPGJson.parse_file(sys_path).data
	disk.system["vehicles"] = {"boat": {"start": {"map": "town", "position": [3, 4]}}}
	RPGJson.save_file(sys_path, disk)
	# The maker renames the boat and changes its speed here.
	boat.set_field("name", "Raft")
	boat.set_field("speed", 2)
	assert_eq(screen.save_system(), OK)
	var after: Dictionary = RPGJson.parse_file(sys_path).data.system
	assert_eq(after.vehicles.boat.name, "Raft")
	assert_eq(after.vehicles.boat.speed, 2)
	assert_eq(after.vehicles.boat.get("start"), {"map": "town", "position": [3, 4]}, "the start set on the map is kept")
	assert_false(after.vehicles.has("ship"), "untouched vehicles write nothing (runtime defaults apply)")
	assert_eq(after.starting_items, {"potion": 2}, "other keys kept")
	# A second edit after saving still keeps the start (the form never saw it).
	var ship: RPGFormBuilder = subs[1]
	ship.set_field("start", {"map": "house_inside", "position": [1, 2]})
	assert_eq(screen.save_system(), OK)
	after = RPGJson.parse_file(sys_path).data.system
	assert_eq(after.vehicles.ship.start, {"map": "house_inside", "position": [1, 2]})
	assert_eq(after.vehicles.boat.get("start"), {"map": "town", "position": [3, 4]})
	assert_eq(after.vehicles.boat.name, "Raft")
	# Runtime view of the settings.
	var data := RPGProjectData.open(TMP + "/rpg")
	var cfg: Dictionary = load("res://addons/rpg/runtime/rpg_vehicles.gd").config(data, "boat")
	assert_eq(cfg.graphic, {"sheet": "vehicles", "index": 0}, "default graphic still applies")
	assert_eq(cfg.name, "Raft")


func test_vehicle_condition() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var ce := RPGConditionEditor.new(data)
	tree.root.add_child(ce)
	assert_has(ce._kinds, "vehicle")
	ce.set_value({"kind": "vehicle", "id": "ship"})
	assert_eq(ce.get_value(), {"kind": "vehicle", "id": "ship"}, "round trip")
	var ob: OptionButton = ce._form.editor_for("id")
	ob.select(3)
	ob.item_selected.emit(3)
	assert_eq(ce.get_value(), {"kind": "vehicle", "id": "none"})
	ce._on_kind(ce._kinds.find("vehicle"))
	assert_eq(ce.get_value(), {"kind": "vehicle", "id": "boat"}, "new vehicle condition")
	var out := []
	RPGValidator._condition_structure({"kind": "vehicle", "id": "airship"}, "f", "r", "p", out, false)
	assert_eq(out.size(), 0, str(out))
	RPGValidator._condition_structure({"kind": "vehicle", "id": "car"}, "f", "r", "p", out, false)
	assert_eq(out.size(), 1, "unknown vehicle reported")
	ce.queue_free()
	await frames(1)


func test_operand_editor_random_and_game_data() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup([{"key": "value", "kind": "operand", "default": 0, "label": "Value"}], data)
	var ed := form.editor_for("value")
	var mode: OptionButton = ed.get_child(0)
	# {random: [a, b]} round trips and edits.
	form.set_value({"value": {"random": [1, 6]}})
	assert_eq(form.get_value().value, {"random": [1, 6]})
	assert_eq(mode.selected, 2)
	var from: SpinBox = _find(ed, func(n): return n is SpinBox and n.prefix == "from")[0]
	from.value = 2
	assert_eq(form.get_value().value, {"random": [2, 6]})
	# Game data: actor field.
	var gd := {"game_data": {"kind": "actor", "id": "hero", "field": "level"}}
	form.set_value({"value": gd})
	assert_eq(form.get_value().value, gd, "round trip")
	assert_eq(mode.selected, 3)
	var gk: OptionButton = ed.get_child(5)
	var gref: RPGRefPicker = ed.get_child(6)
	var gfield: OptionButton = ed.get_child(7)
	assert_true(gfield.visible, "actor field shown")
	var labels := []
	for i in gfield.item_count:
		labels.append(gfield.get_item_text(i))
	assert_true(labels.size() > 3, "level, exp, resources and stats: %s" % str(labels))
	gfield.select(1)
	gfield.item_selected.emit(1)
	assert_eq(form.get_value().value, {"game_data": {"kind": "actor", "id": "hero", "field": "exp"}})
	# Switching kind to gold drops id and field.
	var gi := RPGFormBuilder.GAME_DATA_KINDS.find("gold")
	gk.select(gi)
	gk.item_selected.emit(gi)
	assert_eq(form.get_value().value, {"game_data": {"kind": "gold"}})
	assert_false(gref.visible)
	# From a plain number to Game data (items held).
	form.set_value({"value": 5})
	mode.select(3)
	mode.item_selected.emit(3)
	gk.select(0)
	gk.item_selected.emit(0)
	assert_eq(gref.ref_kind, "item")
	gref.set_value("potion")
	gref.value_changed.emit("potion")
	assert_eq(form.get_value().value, {"game_data": {"kind": "item", "id": "potion"}})
	# The validator accepts both.
	var out := []
	RPGValidator._operand_structure({"random": [1, 6]}, "f", "r", "p", out)
	RPGValidator._operand_structure(form.get_value().value, "f", "r", "p", out)
	assert_eq(out.size(), 0, str(out))
	RPGValidator._operand_structure({"game_data": {"kind": "bogus"}}, "f", "r", "p", out)
	assert_eq(out.size(), 1)
	form.queue_free()
	await frames(1)


func test_actor_description_and_troop_autoname() -> void:
	var actor_fields := RPGRecordSchemas.fields_for("actors")
	var desc: Array = actor_fields.filter(func(f): return f.key == "description")
	assert_eq(desc.size(), 1)
	assert_eq(desc[0].kind, "multiline")
	await _open_screen()
	var tab := _tab("troops")
	_select_id(tab, "goblin_boss")
	var te: Control = tab._form.editor_for("members")
	assert_eq(TroopEditor.autoname(te.members, screen.data), "Goblin, Slime x2")
	var b: Button = _find(te, func(n): return n is Button and n.text == "Autoname")[0]
	b.pressed.emit()
	assert_eq(tab.current_record().name, "Goblin, Slime x2")
	assert_true(tab.dirty)
	assert_eq((tab._form.editor_for("name") as LineEdit).text, "Goblin, Slime x2", "name box updated")


func test_graphic_tile_mode_picks_from_the_tileset() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup([{"key": "graphic", "kind": "graphic", "default": null, "label": "Graphic"}], data, null, {"map_id": "town"})
	form.set_value({"graphic": {"tile": "lower_3"}})
	var ed := form.editor_for("graphic")
	var picker: Control = _find(ed, func(n): return n.has_method("tiles_of"))[0]
	assert_true(picker.is_visible_in_tree(), "tile picker shown in Tile mode")
	var tiles: Array = picker.tiles_of(picker.tile_set())
	assert_true(tiles.size() > 20, "tiles listed: %d" % tiles.size())
	var keys := tiles.map(func(t): return t.key)
	assert_has(keys, "lower_3")
	assert_has(keys, "water_a", "autotiles listed")
	assert_eq(keys.count("water_a"), 1, "once each")
	assert_true(picker._thumb.texture != null, "current tile shown")
	picker.open()
	var i: int = picker._keys.find("upper_5")
	assert_true(i >= 0)
	picker.choose(i)
	assert_eq(form.get_value().graphic, {"tile": "upper_5"})
	form.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# Classes: stat curves and the experience curve of the rule system
# --------------------------------------------------------------------------------------------

func _rules_def(name: String) -> Dictionary:
	return RPGJson.parse_file("res://rpg/rules/%s/rules.json" % name).data


func test_class_exp_curve_follows_the_rule_system() -> void:
	var stats := [{"id": "mhp", "label": "Max HP"}]
	var vx := RPGRecordSchemas.fields_for("classes", stats, [], [], {}, [], _rules_def("vx_ace"))
	var exp_f: Dictionary = vx.filter(func(f): return f.key == "exp_curve")[0]
	assert_eq(exp_f.fields.map(func(f): return f.key), ["basis", "extra", "acc_a", "acc_b"], "VX Ace curve")
	var classic := RPGRecordSchemas.fields_for("classes", stats, [], [], {}, [], _rules_def("classic"))
	var exp_c: Dictionary = classic.filter(func(f): return f.key == "exp_curve")[0]
	assert_eq(exp_c.fields.map(func(f): return f.key), ["basis", "inflation"], "XP-style curve")
	var growth: Dictionary = vx.filter(func(f): return f.key == "growth")[0]
	assert_eq(growth.fields[0].kind, "growth")
	assert_true(growth.fields[0].shapes.has("very_fast"), "rules.json growth_shapes offered")


func test_class_growth_editor_modes_and_curve() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	var def := _rules_def("vx_ace")
	var shapes := RPGRecordSchemas.growth_shapes(def)
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup([{"key": "mhp", "kind": "growth", "default": {}, "label": "Max HP", "shapes": shapes, "max_level": 99}], data)
	var ed := form.editor_for("mhp")
	var mode: OptionButton = _find(ed, func(n): return n is OptionButton)[0]
	var shape_ob: OptionButton = _find(ed, func(n): return n is OptionButton)[1]
	form.set_value({"mhp": {"base": 120, "per_level": 25}})
	assert_eq(form.get_value().mhp, {"base": 120, "per_level": 25}, "round trip")
	assert_eq(mode.selected, 0)
	# Switch to a curve: the numbers carry over.
	mode.select(1)
	mode.item_selected.emit(1)
	assert_eq(form.get_value().mhp, {"at_1": 120, "at_99": 120 + 25 * 98, "shape": "linear"})
	var early := shapes.keys().find("very_fast")
	shape_ob.select(early)
	shape_ob.item_selected.emit(early)
	var v: Dictionary = form.get_value().mhp
	assert_eq(v.shape, "very_fast")
	# The preview maths is the runtime's.
	var rs: Object = load("res://addons/rpg/runtime/rules/rpg_rule_system.gd").load_rules_from_dir("res://rpg/rules/vx_ace", data)
	for lv in [1, 20, 50, 99]:
		assert_eq(RPGFormBuilder.growth_value(v, lv, shapes), rs._growth_value(v, lv), "level %d" % lv)
	# A numeric shape and an unknown one survive.
	form.set_value({"mhp": {"at_1": 10, "at_99": 500, "shape": 0.6}})
	assert_eq(form.get_value().mhp, {"at_1": 10, "at_99": 500, "shape": 0.6})
	var expo: SpinBox = _find(ed, func(n): return n is SpinBox and n.step < 1.0)[0]
	assert_true(expo.visible, "custom exponent shown")
	form.set_value({"mhp": {"at_1": 10, "at_99": 500, "shape": "wobbly"}})
	var spins := _find(ed, func(n): return n is SpinBox and n.prefix == "Lv 99")
	spins[0].value = 600
	assert_eq(form.get_value().mhp, {"at_1": 10, "at_99": 600, "shape": "wobbly"}, "unknown shape kept")
	# Back to per level.
	mode.select(0)
	mode.item_selected.emit(0)
	assert_eq(form.get_value().mhp, {"base": 10, "per_level": 6})
	# Tables stay as they are.
	form.set_value({"mhp": [100, 120, 140]})
	assert_eq(form.get_value().mhp, [100, 120, 140])
	assert_false(mode.visible)
	form.queue_free()
	await frames(1)


## Editor QA: a project with no rpg/ folder yet (before "Create RPG project") loads quietly.
func test_database_tab_on_a_project_with_no_rpg_folder() -> void:
	_rm("user://rpg_no_project_yet")
	host = Control.new()
	tree.root.add_child(host)
	screen = RPGDatabaseScreen.new()
	host.add_child(screen)
	screen.setup(null, "user://rpg_no_project_yet/rpg")
	assert_false(DirAccess.dir_exists_absolute("user://rpg_no_project_yet/rpg/database"), "nothing created just by looking")
	assert_true(screen.disk_stamps() is Dictionary)
	assert_false(screen.check_disk_changes(), "no files, no changes")


## Editor QA: the shared "maker view" object lived in Engine metadata and a hide left a pending
## await on it; both outlived GDScript at editor shutdown and crashed every quit.
func test_maker_view_is_released_and_hiding_does_not_await() -> void:
	var mv: Script = load("res://addons/rpg/editor/rpg_maker_view.gd")
	var v: RefCounted = mv.shared()
	v.tab_visible("RPG", false)
	assert_false(mv.source_code.contains("await "), "hiding a tab is not a coroutine")
	v.apply_now("Database", false)
	assert_false(v.any_visible())
	mv.release()
	assert_false(Engine.has_meta("rpg_maker_view"), "released on plugin exit")
	await frames(2)


# --------------------------------------------------------------------------------------------
# Editor QA 2026-11-10: Database tab and project checks (E1, E20, E27-E34)
# --------------------------------------------------------------------------------------------

## Adds an event with `commands` to the test project's town map.
func _add_town_event(id: String, commands: Array) -> void:
	var path := TMP + "/rpg/maps/town.events.json"
	var f: Dictionary = RPGJson.parse_file(path).data
	f.events.append({"id": id, "name": id, "position": [1, 1], "pages": [{"conditions": [], "trigger": "action_button", "priority": "same", "commands": commands}]})
	RPGJson.save_file(path, f)


func _key_ctrl_s() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.ctrl_pressed = true
	ev.pressed = true
	return ev


## E1: before "Create RPG project" there is nothing to press; the first files ever written are
## picked up when the tab is shown again.
func test_e1_no_project_state_then_the_new_project_is_picked_up() -> void:
	_rm(TMP)
	await _open_screen()
	assert_false(screen.project_exists())
	assert_eq(screen._record_tabs.size(), 0, "no record tabs before a project exists")
	assert_eq(_find(screen, func(n): return n is Button and n.text in ["New", "Save", "Save all"] and not n.is_queued_for_deletion()).size(), 0, "no New or Save")
	assert_eq(_find(screen, func(n): return n is Label and n.text.contains("RPG tab")).size(), 1, "says to create the project on the RPG tab")
	assert_false(screen.check_disk_changes(), "still nothing")
	_make_project()
	assert_true(screen.check_disk_changes(), "the first files ever written are noticed")
	await frames(1)
	assert_true(screen.project_exists())
	var items := _tab("items")
	assert_true(items != null and items.records().size() > 0, "the starter items show")
	assert_true(screen._status.text.contains("new project"), screen._status.text)


## E1: reload() is safe at any time: unsaved tabs keep their edits; Reload's discard drops them.
func test_e1_reload_keeps_unsaved_edits_unless_discarded() -> void:
	await _open_screen()
	var items := _tab("items")
	_select_id(items, "potion")
	items._form.set_field("price", 777)
	assert_true(items.dirty)
	screen.reload()
	await frames(1)
	items = _tab("items")
	assert_true(items.dirty, "still marked unsaved after reload()")
	assert_eq(items.current_record().id, "potion", "the selection is kept")
	assert_eq(int(items.current_record().price), 777, "the unsaved edit is kept")
	assert_true(screen._status.text.contains("Items"), screen._status.text)
	screen.reload(false)
	await frames(1)
	items = _tab("items")
	assert_false(items.dirty, "discarded")
	assert_ne(int(items.current_record().price), 777)


## E29: Ctrl+S saves the tab on show (handled before the editor's own Ctrl+S).
func test_e29_ctrl_s_saves_the_current_tab() -> void:
	await _open_screen()
	var items := _tab("items")
	screen._tabs.current_tab = items.get_index()
	await frames(1)
	_select_id(items, "potion")
	items._form.set_field("price", 321)
	assert_true(items.dirty)
	items._search.grab_focus()
	await frames(1)
	screen._input(_key_ctrl_s())
	assert_false(items.dirty, "saved by Ctrl+S")
	var disk: Dictionary = RPGJson.parse_file(TMP + "/rpg/database/items.json").data
	assert_eq(int(disk.records.filter(func(r): return r.id == "potion")[0].price), 321)
	assert_true(screen.get_viewport().is_input_handled(), "the key is consumed")
	assert_false(screen.has_method("_unhandled_key_input"), "no late handler the editor could pre-empt")


## E30: Rename ID runs while only an unrelated tab is unsaved, and names the tab that blocks it.
func test_e30_rename_with_unrelated_unsaved_tab_and_blocking_message() -> void:
	await _open_screen()
	var items := _tab("items")
	_select_id(items, "potion")
	items._form.set_field("price", 555)
	var sw := _tab("switches")
	_select_id(sw, "door_unlocked")
	var dlg := screen._rename_id("switch", "door_unlocked", sw)
	assert_true(dlg != null, "an unsaved Items tab does not block renaming a switch")
	if dlg == null:
		return
	await frames(1)
	var le: LineEdit = dlg.find_child("NewId", true, false)
	assert_true(le.has_focus(), "the ID field has the focus, so typed keys never reach the editor")
	le.text = "cat_found"
	le.text_submitted.emit(le.text)
	await frames(1)
	var st: Dictionary = RPGJson.parse_file(TMP + "/rpg/state.json").data
	assert_true(st.switches.any(func(s): return s.id == "cat_found"), "Enter confirms the rename")
	items = _tab("items")
	assert_true(items.dirty, "the unrelated unsaved tab keeps its edits")
	_select_id(items, "potion")
	assert_eq(int(items.current_record().price), 555)
	# Now the Variables tab (same file, state.json) has unsaved edits: the rename is blocked and
	# the message beside the buttons says which tab.
	var va := _tab("variables")
	va.new_record()
	sw = _tab("switches")
	_select_id(sw, "cat_found")
	assert_eq(screen._rename_id("switch", "cat_found", sw), null, "blocked")
	assert_true(sw._note.visible and sw._note.text.contains("Variables"), sw._note.text)
	assert_true(sw._note.text.contains("state.json"), sw._note.text)


## E28: Save reports dangling references, broken formulas and types not in types.json; the
## delete confirmation counts the references; types are dropdowns.
func test_e28_save_runs_the_tabs_checks() -> void:
	_add_town_event("town_shop", [{"type": "shop", "goods": [{"kind": "items", "id": "antidote"}]}])
	await _open_screen()
	var items := _tab("items")
	_select_id(items, "antidote")
	var prompt := items.delete_prompt(items.current_record())
	assert_true(prompt.contains("2 place(s)"), prompt)
	assert_true(prompt.contains("town.events.json") and prompt.contains("enemies.json"), prompt)
	items.delete_record()
	assert_true(items.save_now())
	var st := items.status_text()
	assert_false(st.contains("No problems"), st)
	assert_true(st.contains("town.events.json") and st.contains("enemies.json") and st.contains("antidote"), st)
	assert_false(st.contains("[color"), "BBCode is rendered, not shown (E20)")
	assert_true(items._status.bbcode_enabled)
	# A damage formula that does not parse.
	var skills := _tab("skills")
	_select_id(skills, "fire")
	skills._form.set_field("formula", "a.int * 2 - b.mdef / 2 (")
	assert_true(skills.save_now())
	assert_true(skills.status_text().contains("formula"), skills.status_text())
	# Weapon type: a dropdown of Types > Weapon types; a value not in the list is reported.
	var weapons := _tab("weapons")
	_select_id(weapons, "bronze_sword")
	assert_true(weapons._form.editor_for("weapon_type") is OptionButton, "weapon type is a dropdown")
	assert_true(skills._form.editor_for("element") is OptionButton, "element is a dropdown")
	assert_true(skills._form.editor_for("skill_type") is OptionButton, "skill type is a dropdown")
	weapons.current_record()["weapon_type"] = "staff"
	weapons.mark_dirty()
	assert_true(weapons.save_now())
	assert_true(weapons.status_text().contains("staff") and weapons.status_text().contains("Types"), weapons.status_text())
	# Saving Types rebuilds the dropdowns.
	var types := _tab("types")
	_select_id(types, "weapon_types")
	types.current_record().entries.append({"id": "staff", "name": "Staff"})
	types.mark_dirty()
	assert_true(types.save_now())
	await frames(2)
	weapons = _tab("weapons")
	_select_id(weapons, "bronze_sword")
	var ob: OptionButton = weapons._form.editor_for("weapon_type")
	var labels := []
	for i in ob.item_count:
		labels.append(ob.get_item_text(i))
	assert_has(labels, "Staff", "the new weapon type is offered")


## E31: the list shows labels; Starting value is a plain value field that never saves bad text;
## New numbers its IDs.
func test_e31_switch_labels_starting_values_and_new_ids() -> void:
	await _open_screen()
	var sw := _tab("switches")
	sw.new_record()
	var sid: String = sw.current_record().id
	assert_eq(sid, "switch_%d" % sw.records().size(), "New gives switch_<n>")
	assert_false(sw.current_record().has("name"), "switches have no name field")
	sw._form.set_field("label", "Found the cat")
	assert_true(sw._tree.get_selected().get_text(0).contains("Found the cat"), "the list shows the label")
	sw.refresh_list()
	var shown := []
	var it := sw._tree.get_root().get_first_child()
	while it != null:
		shown.append(it.get_text(0))
		it = it.get_next()
	assert_true(shown.any(func(t): return t.contains("Found the cat")), str(shown))
	assert_true(sw.save_now())
	var va := _tab("variables")
	va.new_record()
	var vid: String = va.current_record().id
	assert_true(va._form.editor_for("default") is LineEdit, "a plain value field, not a JSON box")
	va._form.set_field("default", "abc")
	assert_true(va.dirty, "bad input marks the tab unsaved")
	assert_false(va.save_now(), "and is never saved")
	assert_true(va.status_text().contains("whole number"), va.status_text())
	assert_false(va.status_text().contains("No problems"))
	va._form.set_field("default", "42")
	assert_true(va.save_now(), va.status_text())
	var st: Dictionary = RPGJson.parse_file(TMP + "/rpg/state.json").data
	var v: Dictionary = st.variables.filter(func(x): return x.id == vid)[0]
	assert_eq(v.default, 42)
	assert_eq(typeof(v.default), TYPE_INT, "stored as a number")
	va._form.set_field("type", "string")
	va._form.set_field("default", "abc")
	assert_true(va.save_now())
	st = RPGJson.parse_file(TMP + "/rpg/state.json").data
	assert_eq(st.variables.filter(func(x): return x.id == vid)[0].default, "abc")
	assert_eq(RPGRecordTab.coerce("true", "bool").value, true)
	assert_false(RPGRecordTab.coerce("maybe", "bool").ok)
	assert_eq(RPGRecordTab.coerce("1.5", "float").value, 1.5)


## E32: Terms > gold_unit says that System > Currency unit wins while it is set.
func test_e32_currency_term_names_the_system_setting() -> void:
	await _open_screen()
	screen.system_edited("currency", "Coins")
	var terms := _tab("terms")
	_select_id(terms, "gold_unit")
	var notes := _find(terms, func(n): return n is Label and n.text.contains("System > Currency unit") and not n.is_queued_for_deletion())
	assert_eq(notes.size(), 1, "gold_unit explains where the currency comes from")
	if notes.size() == 1:
		assert_true(notes[0].text.contains("Coins") and notes[0].text.contains("System"), notes[0].text)
	var cur: Dictionary = RPGRecordSchemas.fields_for("system").filter(func(f): return f.key == "currency")[0]
	assert_true(str(cur.get("help", "")).contains("gold_unit"), "System's field says it wins")


## E33: title image and start facing in System; own saves are not "changed elsewhere"; the
## Pitch boxes are wide enough for their label.
func test_e33_system_fields_and_own_saves() -> void:
	await _open_screen()
	var form := _system_form()
	assert_true(form.editor_for("title_image") != null, "title screen image")
	assert_true(form.editor_for("start_facing") != null, "start facing")
	form.set_field("start_facing", "left")
	assert_eq(screen.save_system(), OK)
	var sys: Dictionary = RPGJson.parse_file(TMP + "/rpg/database/system.json").data.system
	assert_eq(sys.start.facing, "left")
	assert_eq(sys.start.map, "town", "the start position is kept")
	var pitch := _find(form, func(n): return n is SpinBox and n.prefix == "Pitch")
	assert_true(pitch.size() > 0 and pitch.all(func(s): return s.get_line_edit().expand_to_text_length), "Pitch boxes fit their label")
	# Saving Items, then Weapons while Items has unsaved changes: neither save looks like a
	# change made elsewhere when the tab is shown again.
	var items := _tab("items")
	_select_id(items, "potion")
	items._form.set_field("price", 12)
	assert_true(items.save_now())
	assert_false(screen.check_disk_changes(), "own save is not an outside change")
	items._form.set_field("price", 13)
	var weapons := _tab("weapons")
	_select_id(weapons, "bronze_sword")
	weapons._form.set_field("price", 99)
	assert_true(weapons.save_now())
	assert_false(screen.check_disk_changes())
	assert_false(screen._status.text.contains("elsewhere"), screen._status.text)
	assert_true(items.dirty, "nothing was reloaded")


## E27: a jingle may be a sound effect file (the Inn quick event picks "inn_rest").
func test_e27_jingle_with_a_sound_effect_file_is_not_missing_music() -> void:
	_add_town_event("town_inn", [{"type": "play_jingle", "sound": {"file": "inn_rest", "volume": 100, "pitch": 100, "pan": 0}},
		{"type": "play_jingle", "sound": {"file": "no_such_jingle", "volume": 100, "pitch": 100, "pan": 0}}])
	var data := RPGProjectData.open(TMP + "/rpg")
	var reg := RPGCommandRegistry.new()
	reg.load_all(["project"], [], EXT_ROOT)
	var msgs := RPGValidator.full(data, reg).map(func(p): return str(p.message))
	assert_false(msgs.any(func(m): return m.contains("'inn_rest'")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("'no_such_jingle'")), "a jingle that is nowhere is still reported")
	var audio := RPGAudio.new()
	tree.root.add_child(audio)
	audio.play_me({"file": "inn_rest"})
	assert_true(audio.me.stream != null, "the game plays it too")
	audio.queue_free()
	await frames(1)


## E34: Deploy's export checks and the pre-playtest check list the same problems: two places
## naming the same deleted item are both listed.
func test_e34_export_checks_keep_every_dangling_reference() -> void:
	_add_town_event("town_shop", [{"type": "shop", "goods": [{"kind": "items", "id": "antidote"}]}])
	var items_path := TMP + "/rpg/database/items.json"
	var items: Dictionary = RPGJson.parse_file(items_path).data
	items.records = items.records.filter(func(r): return r.id != "antidote")
	RPGJson.save_file(items_path, items)
	var hits := RPGExportCheck.run_checks(TMP + "/rpg").filter(func(p): return str(p.message).contains("'antidote'"))
	var files := hits.map(func(p): return str(p.file).get_file())
	assert_eq(hits.size(), 2, str(files))
	assert_true(files.has("town.events.json") and files.has("enemies.json"), str(files))
	var data := RPGProjectData.open(TMP + "/rpg")
	var reg := RPGCommandRegistry.new()
	reg.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), data.project.get("extensions_root", "res://extensions"))
	var full_errors := RPGValidator.full(data, reg).filter(func(p): return p.severity == "error").size()
	var gate_errors := RPGExportCheck.problems(data, reg).filter(func(p): return p.severity == "error").size()
	assert_eq(gate_errors, full_errors + RPGExportCheck.capability_problems(data, reg).size(), "the gate is the validator plus the capability checks")



# --------------------------------------------------------------------------------------------
# Database QA pass 2 (D1-D18)
# --------------------------------------------------------------------------------------------

## Changes one database file of the test project before the screen opens.
func _edit_db(type: String, change: Callable) -> void:
	var path := TMP + "/rpg/database/%s.json" % type
	var f: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "records": []})
	change.call(f)
	RPGJson.save_file(path, f)


func _db(type: String) -> Dictionary:
	return RPGJson.parse_file(TMP + "/rpg/database/%s.json" % type).data


func _rec_of(file: Dictionary, id: String) -> Dictionary:
	for r in file.get("records", []):
		if str(r.get("id", "")) == id:
			return r
	return {}


func _forms_in(node: Node) -> Array:
	return _find(node, func(n): return n is RPGFormBuilder)


## The row forms of a list field of the tab's form.
func _row_forms(tab: RPGRecordTab, key: String) -> Array:
	var le: RPGListEditor = tab._form.editor_for(key)
	return _find(le._rows, func(n): return n is RPGFormBuilder and n.get_parent() is HBoxContainer)


func _registry() -> RPGCommandRegistry:
	var reg := RPGCommandRegistry.new()
	reg.load_all(["project"], [], EXT_ROOT)
	return reg


func _visible_pickers(node: Node) -> Array:
	return _find(node, func(n): return n is RPGRefPicker and n.visible)


func _has_visible_option(node: Node) -> bool:
	return node.get_children().any(func(c): return c is OptionButton and c.visible)


## D1: a switch made with New... in a Database form is written to state.json at once and shows
## in the Switches tab; Check project reports a switch that exists nowhere.
func test_d1_new_switch_from_a_database_form_is_saved() -> void:
	await _open_screen()
	var ce := _tab("common_events")
	ce.select(0)
	ce._form.set_field("trigger", "parallel")
	assert_eq(RPGRefPicker.add_definition(screen.data, "switch", "fog_on", "Swamp fog active"), "")
	var st: Dictionary = RPGJson.parse_file(TMP + "/rpg/state.json").data
	assert_true(st.switches.any(func(s): return s.id == "fog_on"), "written to state.json at once")
	var sw := _tab("switches")
	assert_true(sw.ids().has("fog_on"), "the Switches tab lists it")
	assert_false(sw.dirty, "and has nothing unsaved")
	assert_false(screen.data.has_meta("rpg_new_defs"), "nothing left to write")
	# A condition switch that exists nowhere (a common event and an enemy action) is reported.
	var data := RPGProjectData.open(TMP + "/rpg")
	data.common_events_file.common_events[0]["trigger"] = "parallel"
	data.common_events_file.common_events[0]["switch"] = "ghost_switch"
	data.db.enemies.records[0]["actions"] = [{"skill": "attack", "rating": 5, "condition": {"kind": "switch", "id": "ghost_switch2", "value": true}}]
	var msgs := RPGValidator.full(data, _registry()).map(func(p): return str(p.message))
	assert_true(msgs.any(func(m): return m.contains("'ghost_switch'") and m.contains("does not exist")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("'ghost_switch2'")), "enemy action conditions too")


## D2 / D3: effect and trait "Of" states, skill animations and map tilesets are references:
## rename updates them, and Delete counts them (naming the records, D18).
func test_d2_d3_effect_trait_animation_and_tileset_references() -> void:
	_edit_db("animations", func(f): f.records.append({"id": "venom_hit", "name": "Venom", "sheet": "", "flashes": [{"frame": 0, "color": [0, 255, 0, 170]}]}))
	_edit_db("skills", func(f): _rec_of(f, "fire")["animation"] = "venom_hit")
	_edit_db("armors", func(f): _rec_of(f, "wooden_shield")["traits"] = [{"kind": "state_resist", "id": "poison"}])
	var map_path := TMP + "/rpg/maps/town.map.json"
	var mp: Dictionary = RPGJson.parse_file(map_path).data
	mp["tileset"] = "town"
	RPGJson.save_file(map_path, mp)
	await _open_screen()
	var states := _tab("states")
	_select_id(states, "poison")
	var prompt := states.delete_prompt(states.current_record())
	assert_true(prompt.contains("2 place(s)"), prompt)
	assert_true(prompt.contains("items.json (antidote)") and prompt.contains("armors.json (wooden_shield)"), prompt)
	var tilesets := _tab("tilesets")
	_select_id(tilesets, "town")
	prompt = tilesets.delete_prompt(tilesets.current_record())
	assert_true(prompt.contains("town.map.json"), prompt)
	var anims := _tab("animations")
	_select_id(anims, "venom_hit")
	assert_true(anims.delete_prompt(anims.current_record()).contains("skills.json (fire)"))
	# Renames follow them, and count only the real references.
	var r := screen.rename_id_transaction("state", "poison", "toxin")
	assert_true(r.ok, r.error)
	assert_eq(int(r.references), 2)
	assert_eq(_rec_of(_db("items"), "antidote").effects[0].id, "toxin")
	assert_eq(_rec_of(_db("armors"), "wooden_shield").traits[0].id, "toxin")
	screen.reload()
	r = screen.rename_id_transaction("state", "sleep", "slumber")
	assert_true(r.ok, r.error)
	assert_eq(_rec_of(_db("classes"), "warrior").traits[0].id, "slumber", "trait Of (state_rate) followed")
	screen.reload()
	r = screen.rename_id_transaction("animation", "venom_hit", "venom_flash")
	assert_true(r.ok, r.error)
	assert_eq(_rec_of(_db("skills"), "fire").animation, "venom_flash")
	screen.reload()
	r = screen.rename_id_transaction("tileset", "town", "town_field")
	assert_true(r.ok, r.error)
	assert_eq(str(RPGJson.parse_file(map_path).data.tileset), "town_field")
	# An animation that is no record and no built-in effect is a warning; built-ins are fine.
	var data := RPGProjectData.open(TMP + "/rpg")
	data.db.skills.by_id["fire"]["animation"] = "big_blaze"
	var probs := RPGValidator.full(data, _registry())
	assert_true(probs.any(func(p): return p.severity == "warning" and str(p.message).contains("'big_blaze'") and str(p.message).contains("fire")), str(probs.map(func(p): return p.message)))
	assert_false(probs.any(func(p): return str(p.message).contains("Animation 'slash'")), "built-in names are not problems")


## D4: each effect kind shows only its own fields; the "Of" field is picked by kind.
func test_d4_effect_rows_show_the_fields_of_their_kind() -> void:
	await _open_screen()
	var skills := _tab("skills")
	_select_id(skills, "fire")
	var le: RPGListEditor = skills._form.editor_for("effects")
	le._add_row()
	var row: RPGFormBuilder = _row_forms(skills, "effects")[0]
	var shown := func(k: String) -> bool: return row._editors[k].row.visible
	assert_true(shown.call("resource") and shown.call("percent") and shown.call("amount"), "Recover: resource, % and amount")
	assert_false(shown.call("chance") or shown.call("id"), "Recover has no chance or Of")
	row.set_field("kind", "add_state")
	assert_true(shown.call("chance") and shown.call("id"), "Add State: chance and the state")
	assert_false(shown.call("amount") or shown.call("resource"))
	assert_eq(row._editors["id"].label.text, "State")
	var pickers := _visible_pickers(row._editors["id"].control)
	assert_eq(pickers.size(), 1)
	assert_eq(pickers[0].ref_kind, "state")
	row.set_field("kind", "common_event")
	pickers = _visible_pickers(row._editors["id"].control)
	assert_eq(pickers[0].ref_kind, "common_event", "Common Event picks a common event")
	row.set_field("kind", "grow")
	assert_true(_has_visible_option(row._editors["id"].control), "Grow picks a stat")
	assert_eq(row._editors["amount"].label.text, "Raise by")
	# Traits: Of and Value follow the kind (rules.json id_ref / value).
	var armors := _tab("armors")
	_select_id(armors, "wooden_shield")
	(armors._form.editor_for("traits") as RPGListEditor)._add_row()
	var tr: RPGFormBuilder = _row_forms(armors, "traits")[0]
	tr.set_field("kind", "state_resist")
	assert_eq(_visible_pickers(tr._editors["id"].control).size(), 1, "State Resist picks a state")
	assert_false(tr._editors["value"].row.visible, "State Resist has no value")
	tr.set_field("kind", "element_rate")
	assert_true(_has_visible_option(tr._editors["id"].control), "Element Rate picks an element")
	assert_eq(tr.get_field("value"), 100, "its rate starts at 100")


## D5: armour slots leave out Weapon; starting equipment marks items that do not fit; class
## "Can equip" lists are dropdowns; Save warns.
func test_d5_equipment_rules() -> void:
	await _open_screen()
	var armors := _tab("armors")
	_select_id(armors, "wooden_shield")
	var slot: OptionButton = armors._form.editor_for("slot")
	var labels := []
	for i in slot.item_count:
		labels.append(slot.get_item_text(i))
	assert_false(labels.has("Weapon"), str(labels))
	var actors := _tab("actors")
	_select_id(actors, "hero")
	var shield: RPGRefPicker = _find(actors._form, func(n): return n is RPGRefPicker and n.get_meta("equip_slot", "") == "shield")[0]
	assert_eq(shield.misfit("wooden_shield"), "", "a shield fits the shield slot")
	assert_true(shield.misfit("leather_armor") != "", "body armour does not")
	var weapon: RPGRefPicker = _find(actors._form, func(n): return n is RPGRefPicker and n.get_meta("equip_slot", "") == "weapon")[0]
	assert_eq(weapon.misfit("bronze_sword"), "")
	actors._form.set_field("class", "mage")
	assert_true(weapon.misfit("bronze_sword").contains("cannot equip"), "the class's Can equip counts")
	actors.current_record()["equips"]["shield"] = "leather_armor"
	actors.mark_dirty()
	assert_true(actors.save_now())
	assert_true(actors.status_text().contains("leather_armor"), actors.status_text())
	_edit_db("armors", func(f): _rec_of(f, "wooden_shield")["slot"] = "weapon")
	var data := RPGProjectData.open(TMP + "/rpg")
	var msgs := RPGValidator.full(data, _registry()).map(func(p): return str(p.message))
	assert_true(msgs.any(func(m): return m.contains("wooden_shield") and m.contains("holds weapons")), str(msgs))
	# Classes > Can equip: one dropdown per row, of the Types entries.
	var classes := _tab("classes")
	_select_id(classes, "warrior")
	var obs := []
	for f in _forms_in(classes._form.editor_for("equip")):
		if f._editors.has("value"):
			obs.append(f._editors["value"].control)
	assert_true(not obs.is_empty() and obs.all(func(o): return o is OptionButton), "type rows are dropdowns")


## D6: the RPG tab reads a database file again when it changed on disk.
func test_d6_project_data_reloads_one_database_file() -> void:
	var data := RPGProjectData.open(TMP + "/rpg")
	assert_false(data.has_record("tilesets", "dungeon"))
	_edit_db("tilesets", func(f): f.records.append({"id": "dungeon", "name": "Dungeon", "profile": "rm2k", "sheet": "res://assets/starter/ChipSet/town.png"}))
	data.reload_db_type("tilesets")
	assert_true(data.has_record("tilesets", "dungeon"))
	var main := RPGMainScreen.new()
	main.data = data
	main.status = Label.new()
	main.add_child(main.status)
	main.remember_disk()
	_edit_db("tilesets", func(f): f.records.append({"id": "cave", "name": "Cave", "profile": "rm2k", "sheet": "res://assets/starter/ChipSet/town.png"}))
	var path := TMP + "/rpg/database/tilesets.json"
	assert_has(main.disk_changes(), path)
	assert_eq(main._reload_database_files([path]), [], "read again in place")
	assert_true(data.has_record("tilesets", "cave"), "Map properties now lists it")
	main.free()


## D7: Types entry IDs are checked, can be renamed with their references, and equipment slots
## show their kind and armour types.
func test_d7_types_entries() -> void:
	_edit_db("types", func(f):
		_rec_of(f, "elements").entries.append({"id": "Poison", "name": "Poison"})
		_rec_of(f, "elements").entries.append({"id": "fire", "name": "Fire again"}))
	var data := RPGProjectData.open(TMP + "/rpg")
	var msgs := RPGValidator.full(data, _registry()).map(func(p): return str(p.message))
	assert_true(msgs.any(func(m): return m.contains("'Poison'") and m.contains("not valid")), str(msgs))
	assert_true(msgs.any(func(m): return m.contains("'fire'") and m.contains("twice")), str(msgs))
	_edit_db("types", func(f): _rec_of(f, "elements").entries.resize(3))
	await _open_screen()
	var r := RPGValidator.rename_type_entry(screen.data, "elements", "fire", "flame")
	assert_true(r.ok, r.error)
	r = screen._write_transaction(r, "test")
	assert_true(r.ok, r.error)
	assert_eq(_rec_of(_db("skills"), "fire").element, "flame", "skill element followed")
	assert_eq(_rec_of(_db("enemies"), "slime").traits[0].id, "flame", "Element Rate trait followed")
	assert_eq(str(_rec_of(_db("types"), "elements").entries[0].id), "flame")
	r = RPGValidator.rename_type_entry(screen.data, "armor_types", "shield", "shields")
	assert_true(r.ok, r.error)
	var classes: Dictionary = r.data_by_file[TMP + "/rpg/database/classes.json"]
	assert_has(_rec_of(classes, "warrior").equip.armor_types, "shields")
	var types: Dictionary = r.data_by_file[TMP + "/rpg/database/types.json"]
	assert_has(_rec_of(types, "equip_slots").entries[1].armor_types, "shields", "slot armour types followed")
	screen.reload()
	await frames(1)
	var tt := _tab("types")
	_select_id(tt, "equip_slots")
	var entry: RPGFormBuilder = _row_forms(tt, "entries")[1]
	assert_true(entry._editors.has("kind") and entry._editors.has("armor_types"), "slot kind and armour types are editable")
	assert_true(tt._extra_box.find_child("EntryPick", true, false) != null, "Rename entry ID... is offered")


## D8: states say "until removed" or "for a number of turns", and min <= max holds.
func test_d8_state_duration() -> void:
	await _open_screen()
	var states := _tab("states")
	_select_id(states, "poison")
	assert_eq(states._form.get_field("duration"), "until_removed")
	assert_false(states._form._editors["turns_min"].row.visible)
	_select_id(states, "sleep")
	assert_eq(states._form.get_field("duration"), "turns")
	states._form.set_field("turns_min", 9)
	assert_eq(int(states.current_record().turns_max), 9, "at most follows at least")
	states._form.set_field("duration", "until_removed")
	assert_false(states.current_record().has("turns_min") or states.current_record().has("turns_max"), "until removed stores no turns")
	states._form.set_field("duration", "turns")
	assert_true(int(states.current_record().turns_max) >= 1)
	states.new_record()
	assert_false(states.current_record().has("turns_min"), "a new state lasts until removed")
	_edit_db("states", func(f):
		_rec_of(f, "sleep")["turns_min"] = 9
		_rec_of(f, "sleep")["turns_max"] = 5)
	var data := RPGProjectData.open(TMP + "/rpg")
	assert_true(RPGValidator.full(data, _registry()).any(func(p): return str(p.message).contains("at least 9 turns but at most 5")))


## D9: the Animations tab previews, labels frames, explains sheets and warns about empty ones.
func test_d9_animation_preview_and_checks() -> void:
	_edit_db("animations", func(f): f.records.append({"id": "spark", "name": "Spark", "sheet": "", "frames": [0, 1]}))
	await _open_screen()
	var anims := _tab("animations")
	_select_id(anims, "spark")
	var play: Button = anims._preview_box.find_child("Play", true, false)
	assert_true(play != null, "a Play button")
	var stage: Control = anims._preview_box.find_child("Stage", true, false)
	play.pressed.emit()
	assert_true(stage.get_child_count() > 0, "plays the game's battle effect")
	# Let the effect end (its clean-up timer refers to it).
	await tree.create_timer(0.8).timeout
	var rows := _row_forms(anims, "frames")
	assert_eq(rows.size(), 2)
	assert_eq(rows[1]._editors["value"].label.text, "Frame 2 shows cell")
	var sheet: RPGResourcePicker = anims._form.editor_for("sheet")
	assert_true(sheet.empty_hint.contains("Tools > Resources > Import"))
	anims.mark_dirty()
	assert_true(anims.save_now())
	assert_true(anims.status_text().contains("no sprite sheet"), anims.status_text())


## D10: a rename can be taken back (same record), counts real references and can be undone.
func test_d10_rename_back_count_and_undo() -> void:
	await _open_screen()
	var r := screen.rename_id_transaction("class", "warrior", "knight")
	assert_true(r.ok, r.error)
	assert_eq(int(r.references), 1, "hero's class")
	screen.reload()
	r = screen.rename_id_transaction("class", "knight", "paladin")
	assert_true(r.ok, r.error)
	screen.reload()
	r = screen.rename_id_transaction("class", "paladin", "warrior")
	assert_true(r.ok, "back to an ID the same record had: " + str(r.error))
	assert_eq(_rec_of(_db("actors"), "hero")["class"], "warrior")
	screen.reload()
	assert_false(screen.rename_id_transaction("class", "mage", "knight").ok, "another record cannot take it")
	# Undo puts the files back.
	r = screen.rename_id_transaction("class", "mage", "wizard")
	assert_true(r.ok, r.error)
	assert_eq(_rec_of(_db("actors"), "mira")["class"], "wizard")
	screen.undo.manager.undo()
	assert_eq(_rec_of(_db("actors"), "mira")["class"], "mage", "undo wrote the old files back")
	assert_false(_rec_of(_db("classes"), "mage").is_empty())
	screen.undo.manager.redo()
	assert_eq(_rec_of(_db("actors"), "mira")["class"], "wizard", "redo")


## D11: the Rename dialog is a normal size and keeps the focus in its field after an error.
func test_d11_rename_dialog_size_and_focus() -> void:
	await _open_screen()
	var classes := _tab("classes")
	_select_id(classes, "warrior")
	var dlg := screen._rename_id("class", "warrior", classes)
	await frames(1)
	assert_true(dlg.size.y < 400, "dialog height %d" % dlg.size.y)
	var le: LineEdit = dlg.find_child("NewId", true, false)
	le.text = "Knight Class!"
	le.text_submitted.emit(le.text)
	await frames(2)
	assert_true(dlg.visible, "an error keeps the dialog open")
	assert_true(le.has_focus(), "and the focus in the field")
	assert_true(dlg.size.y < 400, "dialog height %d after the error" % dlg.size.y)
	dlg.queue_free()


## D12: a choice with no value shows "(not set)" instead of selecting nothing (engine error).
func test_d12_choice_without_a_value() -> void:
	var form := RPGFormBuilder.new()
	form.setup([{"key": "resource", "kind": "choice", "options": ["hp", "sp"], "default": null, "label": "Resource"}])
	form.set_value({})
	var ob: OptionButton = form.editor_for("resource")
	assert_eq(ob.get_item_text(ob.selected), "(not set)")
	assert_eq(form.get_field("resource"), null)
	form.free()


## D13: a new class copies the first class's stat curves.
func test_d13_new_class_has_stats() -> void:
	await _open_screen()
	var classes := _tab("classes")
	classes.new_record()
	var g: Dictionary = classes.current_record().get("growth", {})
	assert_false(g.is_empty(), "growth filled in")
	assert_eq(g, _rec_of(_db("classes"), "warrior").growth)


## D14: the tileset form picks images with a preview, labels profiles, hides other profiles'
## fields, points to Tiles; a missing sheet is an error.
func test_d14_tileset_form() -> void:
	await _open_screen()
	var ts := _tab("tilesets")
	_select_id(ts, "town")
	assert_true(ts._form.editor_for("sheet") is RPGResourcePicker)
	assert_true((ts._form.editor_for("sheet") as RPGResourcePicker).store_path)
	var prof: OptionButton = ts._form.editor_for("profile")
	assert_eq(prof.get_item_text(0), "RPG Maker 2000/2003")
	assert_false(ts._form._editors["autotiles"].row.visible or ts._form._editors["sheets"].row.visible, "XP and VX fields hidden")
	assert_true(ts._form._editors["tiles_note"].row.visible, "a pointer to RPG tab > Tiles")
	assert_true(ts._preview_box.visible, "a sheet preview")
	ts._form.set_field("profile", "vx")
	assert_true(ts._form._editors["sheets"].row.visible and not ts._form._editors["sheet"].row.visible)
	ts._form.set_field("profile", "rm2k")
	ts.current_record()["sheet"] = "res://assets/starter/ChipSet/nope.png"
	ts.mark_dirty()
	assert_true(ts.save_now())
	assert_true(ts.status_text().contains("nope.png") and ts.status_text().contains("error"), ts.status_text())


## D15: the Icon field picks an icon index from the icon sheet (a grid, searchable by name); the
## icon sheet pickers offer icon sheets, never the window skin, and the window style picker no
## icon sheets. (More in test_icons.gd.)
func test_d15_icon_picker() -> void:
	assert_false(RPGResourcePicker.list_names("iconset").has("system"))
	assert_true(RPGResourcePicker.list_names("iconset").has("IconSet24"), "the starter icon sheets are offered")
	assert_false(RPGResourcePicker.list_names("system").has("IconSet24"), "an icon sheet is not a window style")
	var f: Dictionary = RPGRecordSchemas.fields_for("armors").filter(func(x): return x.key == "icon")[0]
	assert_eq(f.kind, "icon")
	assert_eq(f.default, 0)
	var p := RPGIconPicker.new(null)
	tree.root.add_child(p)
	p.open_popup()
	var info: Label = p._popup.find_child("Info", true, false)
	assert_true(info.text.contains("IconSet24"), info.text)
	p.search("shield")
	assert_true(p.matches().has(RPGIcons.find("shield_round")), str(p.matches()))
	p.queue_free()
	await frames(1)


## D16: Save warns about an empty name; other tabs' pickers show the current names.
func test_d16_empty_names_and_fresh_picker_labels() -> void:
	await _open_screen()
	var classes := _tab("classes")
	_select_id(classes, "warrior")
	classes._form.set_field("name", "")
	assert_true(classes.save_now())
	assert_true(classes.status_text().contains("has no name"), classes.status_text())
	var actors := _tab("actors")
	_select_id(actors, "hero")
	var cls: RPGRefPicker = actors._form.editor_for("class")
	classes._form.set_field("name", "Knight")
	actors.refresh_refs()
	assert_true(cls._button.text.contains("Knight"), cls._button.text)


## D17: a picker inside a window inside a window opens under its field.
func test_d17_popup_under_a_field_in_nested_windows() -> void:
	var place: GDScript = load("res://addons/rpg/editor/rpg_popup_place.gd")
	for outer_embeds in [true, false]:
		var outer := Window.new()
		outer.gui_embed_subwindows = outer_embeds
		outer.position = Vector2i(300, 200)
		outer.size = Vector2i(800, 600)
		tree.root.add_child(outer)
		var inner := Window.new()
		inner.position = Vector2i(40, 60)
		inner.size = Vector2i(400, 300)
		outer.add_child(inner)
		var field := Button.new()
		field.position = Vector2(10, 20)
		field.size = Vector2(120, 30)
		inner.add_child(field)
		var pop := PopupPanel.new()
		pop.size = Vector2i(100, 80)
		await frames(1)
		place.below(field, pop)
		# Embedded by the outer window: positions are in its coordinates. Otherwise the root
		# embeds both windows, and only the inner window's own position counts.
		var want := Vector2i(10, 50) + inner.position
		assert_eq(pop.position, want, "outer embeds: %s" % outer_embeds)
		outer.queue_free()
		await frames(1)


## D18: Reload names the unsaved tabs.
func test_d18_reload_prompt_names_tabs() -> void:
	await _open_screen()
	var armors := _tab("armors")
	armors._form.set_field("price", 12)
	assert_true(screen.reload_prompt().contains("Armour"), screen.reload_prompt())
