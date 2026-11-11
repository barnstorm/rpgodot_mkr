extends "res://tests/rpg_test_case.gd"
## Editor data layer: quick event compiler, validator, rename, schema, events file round trips,
## and the descriptor-driven form builder (headless).

const FIXTURE := "res://tests/fixtures/door_project"
const TMP := "user://rpg_editor_test"
const EXT_ROOT := "res://tests/fixtures/door_project/extensions"

var data: RPGProjectData
var registry: RPGCommandRegistry
var tpl: Dictionary


func before_each() -> void:
	_make_project()
	data = RPGProjectData.open(TMP + "/rpg")
	registry = RPGCommandRegistry.new()
	registry.load_all(["project", "broken_ext"], ["broken_ext"], EXT_ROOT)
	tpl = RPGQuickEvents.templates("res://nonexistent_quick_events")


## A throwaway project: the door fixture plus the sample database, without explicit map paths.
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


func _compile(name: String, answers: Dictionary) -> Dictionary:
	var r := RPGQuickEvents.compile(tpl[name], answers, Callable(), data)
	if not r.ok:
		fail("%s failed: %s" % [name, str(r.errors)])
	return r


func _answers() -> Dictionary:
	return {
		"Transfer": {"destination": {"map": "house_inside", "position": [5, 9]}, "facing": "up"},
		"Door": {"image": {"sheet": "objects", "index": 2}, "destination": {"map": "house_inside", "position": [5, 9]}},
		"Treasure": {"image": {"sheet": "objects", "index": 1}, "contents": {"kind": "items", "item": "potion", "amount": 2}},
		"Inn": {"image": {"sheet": "hero", "index": 3}, "price": 25},
		"Sign": {"text": "Welcome to town!", "read_by": "examined"},
		"Shop": {"image": {"sheet": "hero", "index": 4}, "goods": [{"kind": "items", "id": "potion"}, {"kind": "weapons", "id": "iron_sword", "price": 250}], "buy_only": false},
	}


func _with_event(ev: Dictionary, id: String, cell: Array) -> Dictionary:
	var e := ev.duplicate(true)
	e["id"] = id
	e["position"] = cell
	return e


func _events_files(extra_events: Array, map_id := "town") -> Dictionary:
	var path := RPGValidator.events_path(data, map_id)
	var f := RPGEventsFile.open(path, map_id)
	for e in extra_events:
		f.events().append(e)
	return RPGValidator.collect_files(data, {path: {"kind": "events", "map": map_id, "data": f.data}})


# --------------------------------------------------------------------------------------------
# Quick events
# --------------------------------------------------------------------------------------------

func test_six_templates_ship_and_load() -> void:
	for n in ["Transfer", "Door", "Treasure", "Inn", "Sign", "Shop"]:
		assert_true(tpl.has(n), "template %s" % n)
		if tpl.has(n):
			assert_eq(RPGQuickEvents.check_template(tpl[n]), [], n)
			assert_true(tpl[n].has("version") and tpl[n].has("author"), "%s has version/author" % n)


func test_compile_every_template_validates() -> void:
	var answers := _answers()
	var events := []
	var i := 0
	for n in answers:
		var r := _compile(n, answers[n])
		if not r.ok:
			continue
		var text := RPGJson.stringify(r.event)
		assert_eq(text.find("{{"), -1, "%s has no placeholders left" % n)
		assert_eq(r.event.editor_history.template, n)
		var ev := _with_event(r.event, RPGIds.slug(n), [i, 1])
		i += 1
		events.append(ev)
		var probs := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [ev]}, registry, "test")
		assert_eq(probs, [], "%s structure" % n)
	var files := _events_files(events)
	var refs := RPGValidator.references(data, registry, files)
	var errs := refs.filter(func(p): return p.severity == "error")
	assert_eq(errs, [], "references of compiled events")


func test_compiled_values_are_typed() -> void:
	var inn: Dictionary = _compile("Inn", _answers().Inn).event
	var cmds: Array = inn.pages[0].commands
	assert_eq(cmds[0].text, "Welcome! A night's stay is 25 gold. Would you like to rest?")
	var cond: Dictionary = cmds[1].choices[0].then[0].condition
	assert_eq(typeof(cond.value), TYPE_INT, "price is a number")
	assert_eq(cond.value, 25)
	assert_eq(cmds[1].choices[0].then[0].then[0].amount, 25)
	assert_eq(inn.pages[0].graphic, {"sheet": "hero", "index": 3, "facing": "down"})
	var tr: Dictionary = _compile("Transfer", _answers().Transfer).event
	assert_eq(tr.pages[0].commands[1].to, {"map": "house_inside", "position": [5, 9]})
	assert_eq(tr.pages[0].commands[1].facing, "up")
	assert_eq(tr.pages[0].priority, "below")
	assert_eq(tr.pages[0].movement, {"type": "fixed"}, "missing page fields are completed")
	var shop: Dictionary = _compile("Shop", _answers().Shop).event
	assert_eq(shop.pages[0].commands[1].goods, [{"kind": "items", "id": "potion"}, {"kind": "weapons", "id": "iron_sword", "price": 250}])
	assert_eq(shop.pages[0].commands[1].buy_only, false)


func test_treasure_item_and_gold_variants() -> void:
	var ch: Dictionary = _compile("Treasure", _answers().Treasure).event
	var c: Array = ch.pages[0].commands
	assert_eq(c[2], {"type": "change_items", "item_kind": "items", "item": "potion", "operation": "increase", "amount": 2})
	assert_eq(c[3].text, "Found 2 x Potion!")
	assert_eq(c[4], {"type": "set_self_switch", "switch": "A", "value": true})
	assert_eq(ch.pages[1].conditions, [{"kind": "self_switch", "id": "A"}])
	assert_eq(ch.pages[1].graphic.facing, "up")
	assert_eq(ch.pages[1].options.direction_fix, true)
	var gold := _compile("Treasure", {"image": {"sheet": "objects", "index": 1}, "contents.kind": "gold", "contents.amount": 50})
	var g: Array = gold.event.pages[0].commands
	assert_eq(g[2], {"type": "change_gold", "operation": "increase", "amount": 50})
	assert_eq(g[3].text, "Found 50 gold!")
	for cmd in g:
		assert_ne(cmd.type, "change_items", "gold chest has no change_items")


func test_sign_read_by_sets_priority_and_trigger() -> void:
	var a: Dictionary = _compile("Sign", {"text": "Hi", "read_by": "stepped_on"}).event
	assert_eq(a.pages[0].priority, "below")
	assert_eq(a.pages[0].trigger, "player_touch")
	assert_eq(a.pages[0].graphic, null, "no image -> no graphic")
	var b: Dictionary = _compile("Sign", {"text": "Hi", "image": {"sheet": "objects", "index": 5}}).event
	assert_eq(b.pages[0].priority, "same")
	assert_eq(b.pages[0].trigger, "action_button")
	assert_eq(b.pages[0].graphic, {"sheet": "objects", "index": 5})


func test_text_placeholders_escape_codes() -> void:
	var s: Dictionary = _compile("Sign", {"text": "Path C:\\games \\V[gold]", "read_by": "examined"}).event
	assert_eq(s.pages[0].commands[0].text, "Path C:\\\\games \\\\V[gold]", "backslashes doubled")
	var sub := {"schema_version": 1, "name": "T", "version": 1, "author": "", "asks": [{"key": "who", "type": "text", "label": "Who"}],
		"event": {"name": "T", "pages": [{"commands": [{"type": "show_text", "text": "Hello \\C[2]{{who}}\\C[0]!"}]}]}}
	var r := RPGQuickEvents.compile(sub, {"who": "a\\b"})
	assert_true(r.ok)
	assert_eq(r.event.pages[0].commands[0].text, "Hello \\C[2]a\\\\b\\C[0]!", "template codes kept, answer escaped")


func test_placeholder_must_be_whole_value_outside_text() -> void:
	var bad := {"schema_version": 1, "name": "Bad", "version": 1, "author": "", "asks": [{"key": "n", "type": "amount", "label": "N"}],
		"event": {"name": "Bad", "pages": [{"commands": [{"type": "wait", "seconds": "{{n}}0"}]}]}}
	var r := RPGQuickEvents.compile(bad, {"n": 1})
	assert_false(r.ok, "embedded placeholder in a number field is refused")
	var unknown := {"schema_version": 1, "name": "U", "version": 1, "author": "", "asks": [],
		"event": {"name": "U", "pages": [{"commands": [{"type": "wait", "seconds": "{{nope}}"}]}]}}
	assert_false(RPGQuickEvents.compile(unknown, {}).ok, "unknown placeholder is an error")


func test_missing_and_invalid_answers_error() -> void:
	var r := RPGQuickEvents.compile(tpl.Door, {"image": {"sheet": "objects", "index": 0}})
	assert_false(r.ok)
	assert_eq(r.errors.size(), 1)
	assert_eq(r.errors[0].key, "destination")
	var r2 := RPGQuickEvents.compile(tpl.Transfer, {"destination": {"map": "house_inside", "position": [99, 9]}}, Callable(), data)
	assert_false(r2.ok, "cell outside the map")
	var r3 := RPGQuickEvents.compile(tpl.Treasure, {"image": {"sheet": "x"}, "contents.kind": "items", "contents.item": "no_such_item"}, Callable(), data)
	assert_false(r3.ok, "unknown item")
	var r4 := RPGQuickEvents.compile(tpl.Inn, {"image": {"sheet": "x"}, "price": "lots"})
	assert_false(r4.ok, "price must be a number")


func test_sound_roles_resolver() -> void:
	var resolver := func(role: String) -> String: return "" if role == "door_open" else role
	assert_eq(RPGQuickEvents.missing_sound_roles(tpl.Door, resolver), ["door_open"])
	var a: Dictionary = _answers().Door.duplicate(true)
	var r := RPGQuickEvents.compile(tpl.Door, a, resolver)
	assert_false(r.ok, "a missing role asks for a sound")
	a["sound_door_open"] = "Door1"
	r = RPGQuickEvents.compile(tpl.Door, a, resolver)
	assert_true(r.ok)
	assert_eq(r.event.pages[0].commands[0].sound, {"file": "Door1", "volume": 100, "pitch": 100, "pan": 0})
	var ok := RPGQuickEvents.compile(tpl.Door, _answers().Door, func(role): return role)
	assert_eq(ok.event.pages[0].commands[0].sound, {"role": "door_open"}, "found roles stay roles")


func test_acceptance_1_door_chest_shop_inn_round_trip() -> void:
	var answers := _answers()
	var file := {"schema_version": 1, "map": "town", "events": []}
	var x := 0
	for n in ["Door", "Treasure", "Shop", "Inn"]:
		var r := _compile(n, answers[n])
		file.events.append(_with_event(r.event, RPGIds.slug(n), [x, 2]))
		x += 1
	var text1 := RPGJson.stringify(file)
	var parsed := RPGJson.parse_text(text1)
	assert_true(parsed.ok)
	var text2 := RPGJson.stringify(parsed.data)
	assert_eq(text2, text1, "stringify(parse(stringify(x))) is byte-identical")
	# Through the events file layer and the disk, too.
	var path := TMP + "/rpg/maps/roundtrip.events.json"
	var ef := RPGEventsFile.open(path, "town")
	ef.data = parsed.data
	assert_eq(ef.save(), OK)
	var back := RPGEventsFile.open(path, "town")
	assert_eq(back.to_text(), text1, "saved file reloads byte-identical")
	assert_eq(FileAccess.get_file_as_string(path), text1)


func test_acceptance_7_unknown_command_survives_edit() -> void:
	var path := TMP + "/rpg/maps/unknown.events.json"
	var src := {"schema_version": 1, "map": "town", "future_top": {"a": 1}, "events": [{
		"id": "oddity", "name": "Odd", "position": [1, 1], "notes": "", "x_custom": [1, 2, {"deep": true}],
		"pages": [{"conditions": [], "graphic": null, "priority": "same", "trigger": "action_button", "page_extra": "keep me",
			"commands": [
				{"type": "mystery_command", "power": 9000, "nested": [{"type": "show_text", "text": "inner"}]},
				{"type": "fancy_effect", "x": 1},
				{"type": "show_text", "text": "Hi", "unknown_flag": true},
			]}],
	}]}
	RPGJson.save_file(path, src)
	var before := FileAccess.get_file_as_string(path)
	var f := RPGEventsFile.open(path, "town")
	var ev := f.get_event_copy("oddity")
	ev.name = "Odder"
	ev.pages[0].commands[2].text = "Hello"
	f.set_event(ev)
	assert_eq(f.save(), OK)
	var after: Dictionary = RPGJson.parse_file(path).data
	assert_eq(after.events[0].name, "Odder")
	assert_eq(after.events[0].pages[0].commands[2].text, "Hello")
	assert_eq(after.future_top, src.future_top)
	assert_eq(after.events[0].x_custom, src.events[0].x_custom)
	assert_eq(after.events[0].pages[0].page_extra, "keep me")
	assert_eq(after.events[0].pages[0].commands[0], src.events[0].pages[0].commands[0], "unknown command kept")
	assert_eq(after.events[0].pages[0].commands[1], src.events[0].pages[0].commands[1], "disabled-extension command kept")
	assert_eq(after.events[0].pages[0].commands[2].unknown_flag, true)
	# Restoring the edited fields gives back the original bytes.
	var f2 := RPGEventsFile.open(path, "town")
	var ev2 := f2.get_event_copy("oddity")
	ev2.name = "Odd"
	ev2.pages[0].commands[2].text = "Hi"
	f2.set_event(ev2)
	assert_eq(f2.to_text(), before, "nothing else changed")
	# The validator flags them but keeps them.
	var files := RPGValidator.collect_files(data, {path: {"kind": "events", "map": "town", "data": after}})
	var probs := RPGValidator.references(data, registry, files)
	var types := probs.filter(func(p): return p.field == "type").map(func(p): return p.path)
	assert_has(types, "events/0/pages/0/commands/0")
	assert_has(types, "events/0/pages/0/commands/1")


func test_acceptance_7_through_event_editor() -> void:
	var path := RPGValidator.events_path(data, "town")
	var ef := RPGEventsFile.open(path, "town")
	var door := ef.get_event_copy("town_house_door")
	door.pages[0].commands.append({"type": "mystery_command", "power": 1})
	door["x_editor_unknown"] = {"k": [1, 2]}
	ef.set_event(door)
	ef.save()
	var script: Script = load("res://addons/rpg/editor/event_editor/rpg_event_editor.gd")
	if script == null:
		fail("event editor script failed to load")
		return
	var saved := [false]
	var win: Window = script.open_for("town", "town_house_door", data, registry, null, func(_id): saved[0] = true)
	await frames(2)
	assert_true(win != null, "editor opened")
	if win == null:
		return
	win.set_event_name("Front door")
	assert_true(win.apply(), "apply ok")
	assert_true(saved[0], "on_saved called")
	win.queue_free()
	var after := RPGEventsFile.open(path, "town").get_event("town_house_door")
	assert_eq(after.name, "Front door")
	assert_eq(after.x_editor_unknown, {"k": [1, 2]})
	assert_eq(after.pages[0].commands[1], {"type": "mystery_command", "power": 1})


# --------------------------------------------------------------------------------------------
# Validator
# --------------------------------------------------------------------------------------------

func test_validator_finds_broken_references() -> void:
	var bad := {
		"id": "broken", "name": "Broken", "position": [2, 2], "notes": "",
		"pages": [{"conditions": [{"kind": "switch", "id": "no_such_switch"}, {"kind": "self_switch", "id": "E"}],
			"graphic": null, "priority": "same", "trigger": "action_button",
			"commands": [
				{"type": "transfer_player", "to": {"map": "house_inside", "position": [50, 50]}, "facing": "up", "fade": "black"},
				{"type": "transfer_player", "to": {"map": "nowhere", "position": [1, 1]}},
				{"type": "set_switch", "id": "ghost_switch", "value": "on"},
				{"type": "fancy_effect"},
				{"type": "if", "condition": {"kind": "variable", "id": "flag", "op": ">", "value": 1}, "then": [
					{"type": "call_common_event", "id": "missing_ce"}], "else": []},
			]}],
	}
	var dup := {"id": "chest", "name": "Dup", "position": [3, 4], "pages": []}
	var files := _events_files([bad, dup])
	var probs := RPGValidator.full(data, registry, files)
	var msgs := "\n".join(probs.map(func(p): return "%s %s %s" % [p.severity, p.path, p.message]))
	var find := func(fragment: String) -> Dictionary:
		for p in probs:
			if p.message.find(fragment) != -1:
				return p
		return {}
	var p1: Dictionary = find.call("outside map 'house_inside'")
	assert_false(p1.is_empty(), "broken transfer destination\n" + msgs)
	assert_eq(p1.get("severity"), "error")
	assert_eq(p1.get("record"), "broken")
	assert_eq(p1.get("path"), "events/5/pages/0/commands/0/to")
	assert_true(str(p1.get("fix_hint", "")) != "", "has a fix hint")
	assert_false(find.call("Map 'nowhere' does not exist").is_empty(), "unknown map")
	assert_false(find.call("Switch 'no_such_switch' does not exist").is_empty(), "unknown switch in condition")
	assert_false(find.call("Switch 'ghost_switch' does not exist").is_empty(), "unknown switch in command")
	assert_false(find.call("Common event 'missing_ce' does not exist").is_empty(), "unknown common event in a branch")
	assert_false(find.call("used twice").is_empty(), "duplicate ID")
	assert_false(find.call("Self switch 'E'").is_empty(), "self switch letter")
	assert_false(find.call("compared with = or").is_empty(), "bool variable compared with >")
	var ext: Dictionary = find.call("'fancy_effect'")
	assert_false(ext.is_empty(), "disabled extension command")
	assert_true(ext.get("blocks_export", false), "blocks export")
	assert_true(RPGValidator.blocks_export(probs))
	# The fixture itself (no broken event) is clean apart from the disabled extension problems.
	var clean := RPGValidator.references(data, registry).filter(func(p): return p.severity == "error")
	assert_eq(clean, [], "fixture references are clean")


func test_structure_catches_shapes() -> void:
	var p := RPGValidator.structure("events", {"schema_version": 1, "map": "town", "events": [
		{"id": "Bad Id", "position": [0, 0], "pages": [{"trigger": "sometimes", "commands": [{"no_type": 1}]}]}]}, registry)
	var msgs := p.map(func(x): return x.message)
	assert_true(msgs.any(func(m): return m.find("not valid") != -1), "invalid id")
	assert_true(msgs.any(func(m): return m.find("unknown trigger") != -1 or m.find("Unknown trigger") != -1), "trigger")
	assert_true(msgs.any(func(m): return m.find("\"type\"") != -1), "command without type")
	var p2 := RPGValidator.structure("state", {"schema_version": 1, "switches": [{"id": "a"}, {"id": "a"}], "variables": [{"id": "v", "type": "complex"}]})
	assert_eq(p2.size(), 2, str(p2))
	var p3 := RPGValidator.structure("events", "not an object")
	assert_eq(p3.size(), 1)


func test_used_by_lists_reads_and_sets() -> void:
	var extra := {"id": "user", "name": "", "position": [4, 4], "pages": [{"commands": [
		{"type": "set_switch", "id": "door_unlocked", "value": "on"},
		{"type": "show_text", "text": "Door is \\S[door_unlocked]"}]}]}
	var files := _events_files([extra])
	var u := RPGValidator.used_by(data, registry, "switch", "door_unlocked", files)
	var access := u.map(func(x): return "%s:%s" % [x.record, x.access])
	assert_has(access, "town_house_door:read")
	assert_has(access, "user:set")
	assert_eq(u.size(), 3, str(u))
	var v := RPGValidator.used_by(data, registry, "variable", "counter")
	assert_true(v.size() >= 4, "counter is used in several places: %s" % str(v.size()))
	var items := RPGValidator.used_by(data, registry, "item", "potion")
	assert_true(items.size() >= 2, "potion: enemies drops and system starting items")


func test_rename_id_updates_every_typed_reference() -> void:
	var extra := {"id": "user", "name": "", "position": [4, 4], "pages": [
		{"conditions": [{"kind": "switch", "id": "door_unlocked"}], "commands": [
			{"type": "set_switch", "id": "door_unlocked", "value": "on"},
			{"type": "show_text", "text": "State: \\S[door_unlocked]"},
			{"type": "call_method", "method": "check", "args": ["door_unlocked"]},
			{"type": "show_choices", "choices": [{"label": "A", "then": [{"type": "set_switch", "id": "door_unlocked", "value": "off"}]}]},
		]}]}
	var path := RPGValidator.events_path(data, "town")
	var files := _events_files([extra])
	var r := RPGValidator.rename_id(data, registry, "switch", "door_unlocked", "door_open", files)
	assert_true(r.ok, r.error)
	var state: Dictionary = r.data_by_file[TMP + "/rpg/state.json"]
	assert_eq(state.switches[0].id, "door_open")
	var evs: Array = r.data_by_file[path].events
	var door: Dictionary = evs[0]
	assert_eq(door.pages[1].conditions[0].id, "door_open", "page condition")
	var user: Dictionary = evs[evs.size() - 1]
	assert_eq(user.pages[0].conditions[0].id, "door_open")
	assert_eq(user.pages[0].commands[0].id, "door_open", "set_switch")
	assert_eq(user.pages[0].commands[1].text, "State: \\S[door_open]", "text code")
	assert_eq(user.pages[0].commands[2].args, ["door_unlocked"], "scripts are not rewritten")
	assert_eq(user.pages[0].commands[3].choices[0].then[0].id, "door_open", "inside a choice branch")
	assert_eq(r.warnings.size(), 1, "script reference warned: %s" % str(r.warnings))
	assert_true(r.changes.size() >= 6, str(r.changes))
	# Inputs untouched (transaction returns new data only).
	assert_eq(data.state_defs.switches[0].id, "door_unlocked")
	assert_false(RPGValidator.rename_id(data, registry, "switch", "door_unlocked", "touched", files).ok, "target exists")
	assert_false(RPGValidator.rename_id(data, registry, "switch", "door_unlocked", "Bad Id", files).ok, "invalid id")
	# Database and map renames.
	var r2 := RPGValidator.rename_id(data, registry, "item", "potion", "red_potion")
	assert_true(r2.ok, r2.error)
	var sys: Dictionary = r2.data_by_file[TMP + "/rpg/database/system.json"]
	assert_true(sys.system.starting_items.has("red_potion"), "dictionary key renamed")
	var r3 := RPGValidator.rename_id(data, registry, "map", "house_inside", "house")
	assert_true(r3.ok, r3.error)
	var town: Dictionary = r3.data_by_file[path]
	assert_eq(town.events[0].pages[1].commands[1].to.map, "house")
	var idx: Dictionary = r3.data_by_file[TMP + "/rpg/map_index.json"]
	assert_eq(idx.maps[1].id, "house")
	assert_eq(idx.maps[1].events, TMP + "/rpg/maps/house_inside.events.json", "old files stay reachable")
	var r4 := RPGValidator.rename_id(data, registry, "event", "town/chest", "big_chest")
	assert_true(r4.ok, r4.error)
	assert_eq(r4.data_by_file[path].events[4].id, "big_chest")


# --------------------------------------------------------------------------------------------
# Schema
# --------------------------------------------------------------------------------------------

func test_schema_has_a_branch_per_command() -> void:
	var s := RPGSchema.events_schema(registry)
	var text := RPGJson.stringify(s)
	var back := RPGJson.parse_text(text)
	assert_true(back.ok, "schema is valid JSON")
	var descs := registry.all_descriptors()
	assert_eq(s["$defs"].command.oneOf.size(), descs.size() + 1, "one branch per command + kept unknowns")
	for d in descs:
		assert_true(s["$defs"].has("cmd_" + d.type), d.type)
		assert_eq(s["$defs"]["cmd_" + d.type].properties.type, {"const": d.type})
	assert_eq(s["$defs"].cmd_if.properties.then, {"$ref": "#/$defs/command_list", "description": "Then"})
	assert_eq(s["$schema"], "https://json-schema.org/draft/2020-12/schema")
	var dir := TMP + "/schema_out"
	assert_eq(RPGSchema.write(registry, dir), OK)
	assert_true(FileAccess.file_exists(dir + "/events.schema.json"))
	assert_true(FileAccess.file_exists(dir + "/README.md"))


# --------------------------------------------------------------------------------------------
# Form builder
# --------------------------------------------------------------------------------------------

func test_form_builder_round_trips_every_descriptor() -> void:
	var fb: Script = load("res://addons/rpg/editor/forms/rpg_form_builder.gd")
	assert_true(fb != null, "form builder loads")
	if fb == null:
		return
	var host := Control.new()
	tree.root.add_child(host)
	for d in registry.all_descriptors():
		var form: Control = fb.new()
		host.add_child(form)
		form.setup(d.get("fields", []), data, registry)
		var v := RPGCommand.apply_defaults(d, {"type": d.type})
		form.set_value(v)
		var out: Dictionary = form.get_value()
		assert_eq(out, v, "%s round trip" % d.type)
		form.queue_free()
	# Edited values come back typed.
	var form2: Control = fb.new()
	host.add_child(form2)
	var tp := registry.descriptor("transfer_player")
	form2.setup(tp.fields, data, registry)
	form2.set_value({"type": "transfer_player", "to": {"map": "town", "position": [1, 2]}, "facing": "keep", "fade": "black", "keep_me": 7})
	form2.set_field("facing", "left")
	form2.set_field("to", {"map": "house_inside", "position": [3, 4]})
	var got: Dictionary = form2.get_value()
	assert_eq(got.facing, "left")
	assert_eq(got.to, {"map": "house_inside", "position": [3, 4]})
	assert_eq(got.keep_me, 7, "unknown fields kept")
	assert_eq(RPGJson.parse_text(RPGJson.stringify(got)).data, got, "valid JSON")
	# Validation messages from RPGCommand.validate.
	var sw := registry.get_command("set_switch")
	var form3: Control = fb.new()
	host.add_child(form3)
	form3.setup(sw.desc.fields, data, registry)
	form3.command = sw
	form3.set_value({"type": "set_switch", "value": "on"})
	assert_true(form3.problems().size() >= 1, "required switch reported")
	host.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# Quick event dialog and command list editor
# --------------------------------------------------------------------------------------------

func test_quick_event_dialog_adds_events_with_new_ids() -> void:
	var r := RPGQuickEventDialog.create_event("town", Vector2i(6, 6), tpl.Door, _answers().Door, data)
	assert_true(r.ok, str(r.errors))
	assert_eq(r.id, "town_door")
	var path := RPGValidator.events_path(data, "town")
	var f := RPGEventsFile.open(path, "town")
	assert_eq(f.get_event("town_door").position, [6, 6])
	var r2 := RPGQuickEventDialog.create_event("town", Vector2i(7, 6), tpl.Door, _answers().Door, data)
	assert_eq(r2.id, "town_door_2")
	f = RPGEventsFile.open(path, "town")
	f.remove_event("town_door_2")
	f.save()
	var r3 := RPGQuickEventDialog.create_event("town", Vector2i(8, 6), tpl.Door, _answers().Door, data)
	assert_eq(r3.id, "town_door_3", "deleted IDs are never reused")
	var bad := RPGQuickEventDialog.create_event("town", Vector2i(8, 6), tpl.Door, {}, data)
	assert_false(bad.ok)
	# The dialog itself, headless.
	var created := [""]
	var d: RPGQuickEventDialog = RPGQuickEventDialog.open_for("town", Vector2i(9, 9), "Sign", data, func(id): created[0] = id)
	assert_true(d != null)
	if d == null:
		return
	await frames(1)
	d._form.set_field("text", "Beware of the dog.")
	d._create()
	assert_eq(created[0], "town_sign")
	var sign := RPGEventsFile.open(path, "town").get_event("town_sign")
	assert_eq(sign.pages[0].commands[0].text, "Beware of the dog.")
	assert_eq(sign.editor_history.template, "Sign")


func test_command_list_editor_operations() -> void:
	var cle := RPGCommandListEditor.new()
	tree.root.add_child(cle)
	cle.setup(data, registry, "town")
	var list := [
		{"type": "show_text", "text": "a"},
		{"type": "if", "condition": {"kind": "switch", "id": "door_unlocked"}, "then": [{"type": "show_text", "text": "inside"}], "else": []},
		{"type": "mystery_command", "power": 3},
	]
	cle.set_commands(list)
	var changes := [0]
	cle.commands_changed.connect(func(): changes[0] += 1)
	cle.select_lines(list, [0])
	cle.toggle_skip()
	assert_eq(list[0].get("skip"), true, "Ctrl+/ sets skip")
	cle.select_lines(list, [0])
	cle.toggle_skip()
	assert_false(list[0].has("skip"), "toggled back")
	cle.select_lines(list, [0])
	cle.copy_selected()
	cle.select_lines(list, [2])
	cle.paste()
	assert_eq(list.size(), 4)
	assert_eq(list[2], {"type": "show_text", "text": "a"}, "pasted before the selected line")
	assert_eq(list[3], {"type": "mystery_command", "power": 3}, "unknown command kept as-is")
	assert_true(cle.move_commands(list, [2], list[1].then, 1), "move into a branch")
	assert_eq(list.size(), 3)
	assert_eq(list[1].then.size(), 2)
	assert_false(cle.move_commands(list, [1], list[1].then, 0), "a command cannot move into itself")
	cle.clear_selection()
	var text := cle.copy_as_text()
	assert_true(text.find("Text: a") != -1, text)
	assert_true(text.find(": Then") != -1, text)
	assert_true(text.find("mystery_command (unknown") != -1, text)
	assert_true(cle.line_problems(list[2]).size() == 1, "unknown command flagged")
	assert_true(cle.line_problems({"type": "set_switch", "id": "ghost", "value": "on"}).size() >= 1, "missing switch flagged")
	assert_eq(cle.line_problems(list[0]), [], "valid line has no warning")
	cle.select_lines(list, [0, 2])
	assert_eq(cle.selection().indices, [0, 2])
	cle.delete_selected()
	assert_eq(list.size(), 1)
	cle.undo()
	assert_eq(list.size(), 3, "undo restores in place")
	assert_true(changes[0] >= 5)
	cle.insert_commands([{"type": "wait", "seconds": 1.0}], {"list": null, "owner": list[1], "key": "else", "index": 0})
	assert_eq(list[1]["else"], [{"type": "wait", "seconds": 1.0}], "insert creates a missing branch list")
	cle.queue_free()
	await frames(1)


func test_database_screen_edits_and_saves() -> void:
	# An unknown field on a record must survive a Database save.
	var items_path := TMP + "/rpg/database/items.json"
	var items: Dictionary = RPGJson.parse_file(items_path).data
	items.records[0]["x_plugin_data"] = {"keep": [1, 2]}
	RPGJson.save_file(items_path, items)
	var screen := RPGDatabaseScreen.new()
	tree.root.add_child(screen)
	screen.setup(null, TMP + "/rpg")
	await frames(1)
	assert_true(screen._record_tabs.size() >= 14, "a tab per record type (%d)" % screen._record_tabs.size())
	var items_tab: RPGRecordTab = null
	for t in screen._record_tabs:
		if t.config.type == "items":
			items_tab = t
	assert_true(items_tab != null)
	if items_tab == null:
		return
	items_tab.select(0)
	items_tab._form.set_field("price", 75)
	items_tab.new_record()
	var new_id: String = items_tab.current_record().id
	assert_eq(new_id, "item_%d" % items_tab.records().size(), "New numbers its ID: item_<n>")
	items_tab.select(0)
	items_tab.duplicate_record()
	assert_eq(items_tab.current_record().id, "potion_2", "duplicate gets a new ID")
	items_tab.delete_record()
	items_tab.new_record()
	assert_ne(items_tab.current_record().id, "potion_2", "deleted IDs are not reused")
	assert_true(items_tab.save_now())
	var saved: Dictionary = RPGJson.parse_file(items_path).data
	assert_eq(saved.records[0].price, 75)
	assert_eq(saved.records[0].x_plugin_data, {"keep": [1, 2]}, "unknown fields kept")
	assert_has(saved.retired_ids, "potion_2")
	assert_true(saved.records.any(func(r): return r.id == new_id))
	# Formula test with the rule system.
	var skills_tab: RPGRecordTab = null
	for t in screen._record_tabs:
		if t.config.type == "skills":
			skills_tab = t
	skills_tab.select(0)
	var res := skills_tab.test_formula("a.int * 2 + 20")
	assert_true(res.find("Error") == -1 and res.find(":") != -1, res)
	assert_true(skills_tab.test_formula("a.int +").begins_with("Error"), "bad formula reports an error")
	# The user, target and level are chosen, not fixed to the first records.
	var low := skills_tab.test_formula("a.mhp")
	skills_tab.test_level = 20
	var high := skills_tab.test_formula("a.mhp")
	assert_ne(low, high, "the chosen level changes the user's stats: %s / %s" % [low, high])
	assert_true(high.contains("Lv 20"), high)
	# Jump-to-fix selects the record a database problem points at.
	assert_true(screen.select_record_for_file(TMP + "/rpg/database/skills.json", str(skills_tab.records()[-1].id)))
	assert_eq(screen._tabs.current_tab, skills_tab.get_index())
	assert_eq(skills_tab.current_record().id, skills_tab.records()[-1].id)
	# Rename through the screen's transaction.
	var r := screen.rename_id_transaction("item", "potion", "red_potion")
	assert_true(r.ok, r.error)
	var sys: Dictionary = RPGJson.parse_file(TMP + "/rpg/database/system.json").data
	assert_true(sys.system.starting_items.has("red_potion"))
	screen.queue_free()
	await frames(1)


# --------------------------------------------------------------------------------------------
# Regressions from the editor review: the RPG and Database tabs each keep a copy of the data
# --------------------------------------------------------------------------------------------

func test_new_switch_from_event_window_keeps_database_switches() -> void:
	# The Database tab saved a switch after this window's data was loaded.
	var st_path := TMP + "/rpg/state.json"
	var disk: Dictionary = RPGJson.parse_file(st_path).data
	disk.switches.append({"id": "db_switch", "label": "From Database", "folder": "", "description": ""})
	RPGJson.save_file(st_path, disk)
	assert_eq(RPGRefPicker.add_definition(data, "switch", "event_switch", "From event"), "")
	assert_eq(RPGRefPicker.save_new_defs(data), OK)
	var after: Dictionary = RPGJson.parse_file(st_path).data
	var ids := []
	for s in after.switches:
		ids.append(s.id)
	assert_has(ids, "db_switch", "the Database switch survives")
	assert_has(ids, "event_switch", "the new switch is added")
	assert_true(data.switches.has("db_switch"), "in-memory list refreshed")


func test_system_save_keeps_start_position_set_on_the_map() -> void:
	var screen := RPGDatabaseScreen.new()
	tree.root.add_child(screen)
	screen.setup(null, TMP + "/rpg")
	await frames(1)
	# "Set starting position" on the RPG tab writes system.json directly.
	var sys_path := TMP + "/rpg/database/system.json"
	var sys: Dictionary = RPGJson.parse_file(sys_path).data
	sys.system["start"] = {"map": "house_inside", "position": [3, 4], "facing": "up"}
	RPGJson.save_file(sys_path, sys)
	# Then the maker edits the title in the System tab and saves.
	screen._system_edits["title"] = "Renamed Quest"
	assert_eq(screen.save_system(), OK)
	var after: Dictionary = RPGJson.parse_file(sys_path).data
	assert_eq(after.system.title, "Renamed Quest")
	assert_eq(after.system.start.map, "house_inside", "the start set on the map is kept")
	# A clean Database tab reloads when another tab changed its files.
	var st_path := TMP + "/rpg/state.json"
	var st: Dictionary = RPGJson.parse_file(st_path).data
	st.switches.append({"id": "late_switch", "label": "Late", "folder": "", "description": ""})
	RPGJson.save_file(st_path, st)
	assert_true(screen.check_disk_changes(), "reloaded")
	assert_true(screen.data.switches.has("late_switch"))
	assert_false(screen.check_disk_changes(), "nothing new the second time")
	screen.queue_free()
	await frames(1)


func test_event_window_does_not_resurrect_a_deleted_event() -> void:
	var path := RPGValidator.events_path(data, "town")
	var win: Window = load("res://addons/rpg/editor/event_editor/rpg_event_editor.gd").open_for("town", "chest", data, registry, null, func(_id): pass)
	await frames(2)
	# Meanwhile the event is deleted on the map.
	await tree.create_timer(1.05).timeout
	var ef := RPGEventsFile.open(path, "town")
	assert_true(ef.remove_event("chest"))
	assert_eq(ef.save(), OK)
	win.set_event_name("Still here?")
	assert_false(win.apply(), "apply refuses")
	assert_false(RPGEventsFile.open(path, "town").has_event("chest"), "the deleted event stays deleted")
	win.queue_free()
	await frames(1)
