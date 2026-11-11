@tool
class_name RPGFormBuilder
extends VBoxContainer
## Descriptor-driven form: builds one row per field description (docs/ARCHITECTURE.md field kinds)
## and edits a Dictionary.
##
##   var form := RPGFormBuilder.new()
##   form.setup(descriptor.fields, project_data, registry, {"map_id": "town"})
##   form.command = registry.get_command(type)     # optional: inline validation messages
##   form.set_value(cmd_dict)
##   form.value_changed.connect(func(key, v): ...)
##   var out := form.get_value()                   # original dict + edited fields
##
## Field kinds: int, float, bool, text, multiline, choice, ref, resource, location, facing, sound,
## condition, operand, operand_pair, color, list, object, commands, route, plus editor kinds
## image ({sheet, index}), graphic (page graphic), point ([x, y] in whole numbers), count_map
## ({id: count}, e.g. starting items; `ref` names the ID kind), troop_members (the visual
## Enemy groups editor) and icon (an index into the project's icon sheet, picked from a grid of
## the sheet with search by name; RPGIconPicker). A `resource` field with `res: "faceset"` gets
## a face picker: it shows the chosen face and, for {sheet, index} values (message faces), the
## index. An `object` field whose default is null gets an on/off box. Any field may carry
## show_if, default, min, max, required, label, help, options/option_labels.
## More field keys: "variant" fields change with a sibling ({"kind": "variant", "by": "kind",
## "cases": {kind value: field description}}; no case = hidden, and a new case starts from its
## default), "not_above": "<key>" / "not_below": "<key>" keep a number at most / at least a
## sibling (the sibling follows), a "note" field is a line of text with no value, and a ref field
## may carry "allow_labels" ({value: label}) for its special values.
##
## The form never produces malformed JSON: values start as a deep copy of the input, a field only
## changes when its widget is edited, every widget returns a typed value, and unknown keys are kept.
## Options: hide_command_lists (nested lists are edited in the command tree instead), map_id,
## battle_conditions (condition kinds of battle pages), compact, flush_checks (on/off boxes start
## at the left edge, not under an empty label column), inline_errors (default true;
## false: no message line under a field, so nothing moves while the form is filled. The field's
## label turns red and the host shows problems() in one fixed line of its own).

signal value_changed(key: String, value: Variant)
## The location picker's "Pick on map" button. The map editor answers by calling
## callback.call(map_id: String, cell: Vector2i); map_id "" means the pick was cancelled.
signal pick_location_requested(callback: Callable, current: Variant)
## A nested command list or route asked for something the host may answer (preview etc.).
signal route_preview_requested(route: Variant)

const COMMAND_LIST_SCRIPT := "res://addons/rpg/editor/event_editor/rpg_command_list_editor.gd"
const TROOP_EDITOR_SCRIPT := "res://addons/rpg/editor/database/rpg_troop_editor.gd"
const TILE_PICKER_SCRIPT := "res://addons/rpg/editor/forms/rpg_tile_picker.gd"
## Operand modes (RPGGameState.resolve_operand): a number, {variable}, {random: [a, b]},
## {game_data: {kind, id?, field?}} (RPGGameState.game_data).
const OPERAND_MODES := ["Number", "Variable", "Random", "Game data"]
const GAME_DATA_KINDS := ["item", "weapon", "armor", "gold", "steps", "play_time", "party_size", "actor"]
const GAME_DATA_LABELS := ["Items held", "Weapons held", "Armour held", "Gold", "Steps", "Play time (seconds)", "Party size", "Actor"]

## Rule-system stat and resource lists per project root (actor fields of Game data operands).
static var _rule_lists_cache: Dictionary = {}
const FACINGS := ["down", "left", "right", "up", "keep"]
const OPS := ["==", "!=", "<", "<=", ">", ">="]
const OP_LABELS := ["=", "≠", "<", "≤", ">", "≥"]

## Condition kinds and their fields (page conditions and the `if` command).
const CONDITION_FIELDS := {
	"switch": [{"key": "id", "kind": "ref", "ref": "switch", "label": "Switch", "required": true}, {"key": "value", "kind": "bool", "default": true, "label": "is ON"}],
	"variable": [{"key": "id", "kind": "ref", "ref": "variable", "label": "Variable", "required": true}, {"key": "op", "kind": "choice", "options": OPS, "option_labels": OP_LABELS, "default": "==", "label": "Compare"}, {"key": "value", "kind": "operand", "default": 0, "label": "Value"}],
	"self_switch": [{"key": "id", "kind": "choice", "options": ["A", "B", "C", "D"], "default": "A", "label": "Self switch"}, {"key": "value", "kind": "bool", "default": true, "label": "is ON"}],
	"item": [{"key": "item_kind", "kind": "choice", "options": ["items", "weapons", "armors"], "option_labels": ["Item", "Weapon", "Armour"], "default": "items", "label": "Kind"}, {"key": "id", "kind": "ref", "ref": "item", "ref_from": "item_kind", "label": "Which one", "required": true}, {"key": "count", "kind": "int", "default": 1, "min": 1, "label": "At least"}],
	"actor": [
		{"key": "id", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
		{"key": "check", "kind": "choice", "options": ["in_party", "name", "class", "skill", "weapon", "armor", "state"], "option_labels": ["Is in the party", "Name is", "Class is", "Has learned a skill", "Has a weapon equipped", "Has armour equipped", "Is affected by a state"], "default": "in_party", "label": "Check"},
		{"key": "value", "kind": "bool", "default": true, "label": "is in the party", "show_if": {"key": "check", "equals": ["in_party", null]}},
		{"key": "name", "kind": "text", "label": "Name", "required": true, "show_if": {"key": "check", "equals": "name"}},
		{"key": "class", "kind": "ref", "ref": "class", "label": "Class", "required": true, "show_if": {"key": "check", "equals": "class"}},
		{"key": "skill", "kind": "ref", "ref": "skill", "label": "Skill", "required": true, "show_if": {"key": "check", "equals": "skill"}},
		{"key": "weapon", "kind": "ref", "ref": "weapon", "label": "Weapon", "required": true, "show_if": {"key": "check", "equals": "weapon"}},
		{"key": "armor", "kind": "ref", "ref": "armor", "label": "Armour", "required": true, "show_if": {"key": "check", "equals": "armor"}},
		{"key": "state", "kind": "ref", "ref": "state", "label": "State", "required": true, "show_if": {"key": "check", "equals": "state"}},
	],
	"gold": [{"key": "op", "kind": "choice", "options": OPS, "option_labels": OP_LABELS, "default": ">=", "label": "Gold"}, {"key": "value", "kind": "operand", "default": 0, "min": 0, "label": "Amount"}],
	"vehicle": [{"key": "id", "kind": "choice", "options": ["boat", "ship", "airship", "none"], "option_labels": ["Boat", "Ship", "Airship", "On foot (no vehicle)"], "default": "boat", "label": "Player is riding"}],
	"facing": [{"key": "target", "kind": "character", "default": "player", "label": "Character"}, {"key": "facing", "kind": "facing", "allow_keep": false, "default": "down", "label": "is facing"}],
	"button": [{"key": "button", "kind": "choice", "options": ["ok", "cancel", "dash", "up", "down", "left", "right"], "option_labels": ["OK (Z, Enter, Space)", "Cancel (X, Esc)", "Dash (Shift)", "Up", "Down", "Left", "Right"], "default": "ok", "label": "Button held down"}],
}
## Condition kinds offered only in Conditional Branch (they need a running event), not on pages.
const BRANCH_ONLY_CONDITIONS := ["facing", "button"]
## Command fields that name a character on the map ("player", "this" or an event ID) and get a
## dropdown instead of a text box: {command type: [field keys]}.
const CHARACTER_FIELDS := {"move_route": ["target"], "show_animation": ["target"], "show_balloon": ["target"]}
const BATTLE_CONDITION_FIELDS := {
	"turn": [{"key": "n", "kind": "int", "default": 1, "min": 0, "label": "Turn"}, {"key": "every", "kind": "int", "default": 0, "min": 0, "label": "Then every (0 = once)"}],
	"enemy_hp": [{"key": "index", "kind": "int", "default": 0, "min": 0, "label": "Enemy #"}, {"key": "op", "kind": "choice", "options": OPS, "option_labels": OP_LABELS, "default": "<=", "label": "HP %"}, {"key": "percent", "kind": "int", "default": 50, "min": 0, "max": 100, "label": "Percent"}],
	"actor_hp": [{"key": "id", "kind": "ref", "ref": "actor", "label": "Actor", "required": true}, {"key": "op", "kind": "choice", "options": OPS, "option_labels": OP_LABELS, "default": "<=", "label": "HP %"}, {"key": "percent", "kind": "int", "default": 50, "min": 0, "max": 100, "label": "Percent"}],
	"switch": [{"key": "id", "kind": "ref", "ref": "switch", "label": "Switch", "required": true}, {"key": "value", "kind": "bool", "default": true, "label": "is ON"}],
}

var fields: Array = []
var data: RPGProjectData
var registry: RPGCommandRegistry
var options: Dictionary = {}
## Optional: the command whose validate() feeds the inline messages.
var command: RPGCommand

var _value: Dictionary = {}
## key -> {control, get: Callable, set: Callable, row: Control, error: Label, field}
var _editors: Dictionary = {}
var _building := false


func setup(p_fields: Array, p_data: RPGProjectData = null, p_registry: RPGCommandRegistry = null, p_options: Dictionary = {}) -> void:
	fields = p_fields
	data = p_data
	registry = p_registry
	options = p_options
	for c in get_children():
		c.queue_free()
	_editors.clear()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building = true
	for f in fields:
		var key := str(f.get("key", ""))
		if key == "":
			continue
		var ed := _make_editor(f)
		var row := VBoxContainer.new()
		var line := HBoxContainer.new()
		row.add_child(line)
		var kind := str(f.get("kind", ""))
		var wide := kind in ["list", "commands", "route", "multiline", "object", "condition", "count_map", "troop_members", "growth", "note"]
		var label := Label.new()
		label.text = str(f.get("label", key.capitalize()))
		if f.get("required", false):
			label.text += " *"
		label.tooltip_text = str(f.get("help", ""))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.custom_minimum_size.x = 150
		if kind == "bool":
			ed.control.text = label.text
			ed.control.tooltip_text = label.tooltip_text
			label.free()   # only its text is used; a Label outside the tree would leak
			label = null
			# Lined up with the other rows' editors, or (flush_checks) at the left edge where
			# the labels start, for forms of short settings.
			if not bool(options.get("flush_checks", false)):
				var spacer := Control.new()
				spacer.custom_minimum_size.x = 150
				line.add_child(spacer)
			line.add_child(ed.control)
		elif wide:
			line.add_child(label)
			row.add_child(ed.control)
		else:
			line.add_child(label)
			ed.control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(ed.control)
		if f.has("help"):
			ed.control.tooltip_text = str(f.help)
		var err := Label.new()
		err.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.visible = false
		row.add_child(err)
		add_child(row)
		ed["row"] = row
		ed["error"] = err
		ed["field"] = f
		ed["label"] = label
		_editors[key] = ed
	_building = false
	_update_visibility()


## Builds a form for one command type.
static func for_command(type: String, p_registry: RPGCommandRegistry, p_data: RPGProjectData, p_options: Dictionary = {}) -> RPGFormBuilder:
	var form := RPGFormBuilder.new()
	var d := p_registry.descriptor(type)
	form.setup(editor_fields(type, d.get("fields", [])), p_data, p_registry, p_options)
	form.command = p_registry.get_command(type)
	return form


## A command's fields as the editor shows them: text fields that name a character on the map
## (CHARACTER_FIELDS, or help "player, this, or an event ID") become Player / This event / event
## dropdowns. The stored value is the same string.
static func editor_fields(type: String, p_fields: Array) -> Array:
	var out := []
	for f in p_fields:
		var g: Variant = f
		if f is Dictionary and str(f.get("kind", "")) == "text":
			var named: bool = CHARACTER_FIELDS.get(type, []).has(str(f.get("key", "")))
			if named or str(f.get("help", "")).begins_with("player, this, or an event ID"):
				g = f.duplicate(true)
				g["kind"] = "character"
		out.append(g)
	return out


func set_value(v: Dictionary) -> void:
	_value = v.duplicate(true)
	_building = true
	for key in _editors:
		var ed: Dictionary = _editors[key]
		var f: Dictionary = ed.field
		var x: Variant = _value[key] if _value.has(key) else RPGJson.deep_copy(f.get("default"))
		ed.set.call(x)
	_building = false
	_sync_ref_kinds()
	_update_visibility()
	_update_messages()


func get_value() -> Dictionary:
	return _value.duplicate(true)


func set_field(key: String, v: Variant) -> void:
	_value[key] = RPGJson.deep_copy(v)
	if _editors.has(key):
		_building = true
		_editors[key].set.call(v)
		_building = false
	_after_change(key)


func get_field(key: String) -> Variant:
	return _value.get(key)


## Field editor control for a key (for hosts and tests).
func editor_for(key: String) -> Control:
	return _editors[key].control if _editors.has(key) else null


## Current validation problems: [{severity, field, message}].
func problems() -> Array:
	var out: Array = command.validate(_value) if command != null else []
	for k in missing_required():
		if not out.any(func(p): return str(p.get("field", "")) == k):
			out.append({"severity": "error", "field": k, "message": "'%s' is required." % _field(k).get("label", k)})
	return out


## Keys of shown required fields that are still blank (no value, or only spaces).
func missing_required() -> Array:
	var out := []
	for f in fields:
		var k := str(f.get("key", ""))
		if k == "" or not f.get("required", false) or not RPGCommand._visible(f, _value):
			continue
		var v: Variant = _value[k] if _value.has(k) else f.get("default")
		if v == null or (typeof(v) == TYPE_STRING and str(v).strip_edges() == ""):
			out.append(k)
	return out


## The first problem as one line ("" when there is none), for a host's fixed message line.
func problems_text() -> String:
	var probs := problems()
	if probs.is_empty():
		return ""
	var more := "  (and %d more)" % (probs.size() - 1) if probs.size() > 1 else ""
	return str(probs[0].message) + more


func _field(key: String) -> Dictionary:
	for f in fields:
		if str(f.get("key", "")) == key:
			return f
	return {}


func _edited(key: String, v: Variant) -> void:
	if _building:
		return
	_value[key] = v
	_after_change(key)


func _after_change(key: String) -> void:
	_follow_change(key)
	_sync_ref_kinds()
	_update_visibility()
	_update_messages()
	value_changed.emit(key, _value.get(key))


## What an edit of `key` does to other fields: variant fields that follow it start from the new
## case's default (unless both cases edit the same kind of value), and numbers that must stay at
## most / at least it follow it.
func _follow_change(key: String) -> void:
	if _building:
		return
	for k in _editors:
		var f: Dictionary = _editors[k].field
		if str(f.get("kind", "")) == "variant" and str(f.get("by", "")) == key:
			var now := variant_case(f, _value)
			if not _editors[k].has("case_shown") or _case_sig(_editors[k].case_shown) != _case_sig(now):
				_value[k] = RPGJson.deep_copy(now.get("default", f.get("default")))
				_building = true
				_editors[k].set.call(_value[k])
				_building = false
	var cur: Variant = _value.get(key)
	if typeof(cur) not in [TYPE_INT, TYPE_FLOAT]:
		return
	var mine := _field(key)
	for spec in [["not_above", 1.0], ["not_below", -1.0]]:
		var other := str(mine.get(spec[0], ""))
		if other == "" or not _editors.has(other):
			continue
		var ov: Variant = _value.get(other, _field(other).get("default"))
		if typeof(ov) in [TYPE_INT, TYPE_FLOAT] and (float(cur) - float(ov)) * float(spec[1]) > 0.0:
			_value[other] = cur
			_building = true
			_editors[other].set.call(cur)
			_building = false


## The field description a variant field uses for the current values ({} when it is hidden).
static func variant_case(f: Dictionary, values: Dictionary) -> Dictionary:
	var cases: Dictionary = f.get("cases", {})
	return cases.get(str(values.get(str(f.get("by", "")), "")), {})


static func _case_sig(c: Dictionary) -> String:
	var d := c.duplicate()
	d.erase("label")
	d.erase("help")
	return JSON.stringify(d)


func _sync_ref_kinds() -> void:
	for key in _editors:
		var f: Dictionary = _editors[key].field
		# Editors that follow another field (a face thumbnail following "Face #").
		if _editors[key].has("sync"):
			_editors[key].sync.call(_value)
		if f.has("ref_from") and _editors[key].control is RPGRefPicker:
			var kv: Variant = _value.get(f.ref_from, _default_of(f.ref_from))
			_editors[key].control.set_ref_kind(RPGValidator.item_kind_to_ref(str(kv), str(f.get("ref", "item"))))


func _default_of(key: String) -> Variant:
	for f in fields:
		if f.get("key", "") == key:
			return f.get("default")
	return null


func _update_visibility() -> void:
	for key in _editors:
		var ed: Dictionary = _editors[key]
		var f: Dictionary = ed.field
		var vis := RPGCommand._visible(f, _value)
		if f.get("kind", "") == "commands" and options.get("hide_command_lists", false):
			vis = false
		if f.get("kind", "") == "variant" and variant_case(f, _value).is_empty():
			vis = false
		if ed.has("row"):
			ed.row.visible = vis


func _update_messages() -> void:
	var by_field := {}
	for p in problems():
		var k := str(p.get("field", ""))
		by_field[k] = (by_field.get(k, "") + "\n" if by_field.has(k) else "") + str(p.message)
	var inline: bool = options.get("inline_errors", true)
	for key in _editors:
		var ed: Dictionary = _editors[key]
		if not ed.has("error"):
			continue
		var msg: String = by_field.get(key, "")
		if inline:
			ed.error.text = msg
			ed.error.visible = msg != ""
			continue
		# Fixed layout: only the label's colour and tooltip change.
		ed.error.visible = false
		var lbl: Variant = ed.get("label")
		if lbl is Label and is_instance_valid(lbl):
			if msg != "":
				lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
			else:
				lbl.remove_theme_color_override("font_color")
			lbl.tooltip_text = msg if msg != "" else str(ed.field.get("help", ""))


static func mark_dirty(p_data: Object, rel_file: String) -> void:
	if p_data == null:
		return
	var d: Dictionary = p_data.get_meta("rpg_dirty_files", {})
	d[rel_file] = true
	p_data.set_meta("rpg_dirty_files", d)


static func dirty_files(p_data: Object) -> Array:
	if p_data == null or not p_data.has_meta("rpg_dirty_files"):
		return []
	return p_data.get_meta("rpg_dirty_files").keys()


static func clear_dirty(p_data: Object, rel_file := "") -> void:
	if p_data == null or not p_data.has_meta("rpg_dirty_files"):
		return
	if rel_file == "":
		p_data.remove_meta("rpg_dirty_files")
	else:
		p_data.get_meta("rpg_dirty_files").erase(rel_file)


# ============================================================================================
# Field editors. Each returns {control, get: Callable, set: Callable}.
# ============================================================================================

func _make_editor(f: Dictionary) -> Dictionary:
	var key := str(f.key)
	var on_edit := func(v: Variant) -> void: _edited(key, v)
	match str(f.get("kind", "")):
		"int", "float":
			return _number_editor(f, on_edit)
		"bool":
			var cb := CheckBox.new()
			cb.toggled.connect(func(on): on_edit.call(on))
			return {"control": cb, "get": func(): return cb.button_pressed, "set": func(v): cb.set_pressed_no_signal(bool(v) if v != null else false)}
		"text":
			var le := LineEdit.new()
			le.text_changed.connect(func(t): on_edit.call(t))
			return {"control": le, "get": func(): return le.text, "set": func(v): le.text = str(v) if v != null else ""}
		"multiline":
			return _multiline_editor(f, on_edit)
		"choice":
			return _choice_editor(f, f.get("options", []), f.get("option_labels", []), on_edit)
		"facing":
			var opts: Array = FACINGS if f.get("allow_keep", true) else FACINGS.slice(0, 4)
			return _choice_editor(f, opts, [], on_edit)
		"ref":
			var rp := RPGRefPicker.new(str(f.get("ref", "switch")), data, f.get("allow", []), not f.get("required", false))
			rp.allow_labels = f.get("allow_labels", {})
			if f.has("equip_slot"):
				rp.set_meta("equip_slot", str(f.equip_slot))
			rp.map_id = str(options.get("map_id", ""))
			rp.value_changed.connect(func(v): on_edit.call(v))
			return {"control": rp, "get": rp.get_value, "set": rp.set_value}
		"character":
			# Player, This event, then the events of the map (stored as "player", "this", an ID).
			var cp := RPGRefPicker.new("event", data, ["player", "this"], false)
			cp.map_id = str(options.get("map_id", ""))
			cp.value_changed.connect(func(v): on_edit.call(v))
			return {"control": cp, "get": cp.get_value, "set": func(v): cp.set_value(str(v) if v != null and str(v) != "" else "this")}
		"resource":
			if str(f.get("res", "")) == "faceset":
				return _face_editor(f, on_edit)
			var res := RPGResourcePicker.new(str(f.get("res", "picture")), null if f.has("default") and f.default == null else "")
			res.store_path = bool(f.get("store_path", false))
			res.empty_hint = str(f.get("empty_hint", ""))
			res.value_changed.connect(func(v): on_edit.call(v))
			return {"control": res, "get": res.get_value, "set": res.set_value}
		"icon":
			var ip := RPGIconPicker.new(data)
			ip.value_changed.connect(func(v): on_edit.call(v))
			return {"control": ip, "get": ip.get_value, "set": ip.set_value}
		"location":
			return _location_editor(f, on_edit)
		"sound":
			return _sound_editor(f, on_edit)
		"condition":
			return _condition_editor(f, on_edit)
		"operand":
			return _operand_editor(f, on_edit)
		"operand_pair":
			return _operand_pair_editor(f, on_edit)
		"point":
			return _point_editor(f, on_edit)
		"count_map":
			return _count_map_editor(f, on_edit)
		"growth":
			return _growth_editor(f, on_edit)
		"troop_members":
			if ResourceLoader.exists(TROOP_EDITOR_SCRIPT):
				var te: Control = load(TROOP_EDITOR_SCRIPT).new()
				te.setup(f, data, registry, options)
				te.value_changed.connect(func(v): on_edit.call(v))
				if te.has_signal("autoname_requested"):
					te.autoname_requested.connect(func(n: String) -> void:
						if _editors.has("name"):
							set_field("name", n))
				return {"control": te, "get": Callable(te, "get_value"), "set": Callable(te, "set_value")}
			return _list_editor(f, on_edit)
		"color":
			return _color_editor(f, on_edit)
		"list":
			return _list_editor(f, on_edit)
		"object":
			return _object_editor(f, on_edit)
		"commands":
			return _commands_editor(f, on_edit)
		"route":
			var re := RPGRouteEditor.new(data, bool(f.get("route_options", false)))
			re.value_changed.connect(func(v): on_edit.call(v))
			re.preview_requested.connect(func(r): route_preview_requested.emit(r))
			return {"control": re, "get": re.get_value, "set": re.set_value}
		"image":
			return _image_editor(f, on_edit)
		"graphic":
			return _graphic_editor(f, on_edit)
		"variant":
			return _variant_editor(f)
		"note":
			var nl := Label.new()
			nl.text = str(f.get("text", ""))
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.custom_minimum_size.x = 260
			nl.modulate = Color(1, 1, 1, 0.75)
			return {"control": nl, "get": func(): return null, "set": func(_v): pass}
	return _json_editor(f, on_edit)


## A field whose editor depends on a sibling (see "variant" in the header): one editor per case,
## made when first needed, the one for the current case shown; the row label follows the case.
func _variant_editor(f: Dictionary) -> Dictionary:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ctx := {"eds": {}, "shown": ""}
	var key := str(f.key)
	var setter := func(v: Variant) -> void:
		if ctx.eds.has(ctx.shown):
			ctx.eds[ctx.shown].set.call(v)
	var sync := func(all: Dictionary) -> void:
		var c := variant_case(f, all)
		var case_key := str(all.get(str(f.get("by", "")), "")) if not c.is_empty() else ""
		if case_key != "" and not ctx.eds.has(case_key):
			var cf: Dictionary = c.duplicate(true)
			cf["key"] = key
			var ed := _make_editor(cf)
			ed.control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(ed.control)
			ctx.eds[case_key] = ed
		for k in ctx.eds:
			ctx.eds[k].control.visible = k == case_key
		ctx.shown = case_key
		if ctx.eds.has(case_key):
			var was := _building
			_building = true
			ctx.eds[case_key].set.call(all[key] if all.has(key) else RPGJson.deep_copy(c.get("default")))
			_building = was
		if _editors.has(key):
			_editors[key]["case_shown"] = c
			var lbl: Variant = _editors[key].get("label")
			if lbl is Label and is_instance_valid(lbl):
				lbl.text = str(c.get("label", f.get("label", key)))
				lbl.tooltip_text = str(c.get("help", f.get("help", "")))
	return {"control": box, "get": func(): return null, "set": setter, "sync": sync}


func _number_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var is_float := str(f.get("kind", "")) == "float"
	var hb := HBoxContainer.new()
	var sb := SpinBox.new()
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.step = 0.01 if is_float else 1.0
	sb.rounded = not is_float
	sb.min_value = float(f.get("min", -999999))
	sb.max_value = float(f.get("max", 999999))
	sb.allow_greater = not f.has("max")
	sb.allow_lesser = not f.has("min")
	var nullable := f.has("default") and f.default == null
	var use := CheckBox.new()
	use.tooltip_text = "Set a value (unchecked = blank)"
	use.visible = nullable
	hb.add_child(use)
	hb.add_child(sb)
	var note := Label.new()
	note.visible = false
	hb.add_child(note)
	var state := {"raw": null}
	var read := func() -> Variant:
		if nullable and not use.button_pressed:
			return null
		return sb.value if is_float else int(sb.value)
	sb.value_changed.connect(func(_x):
		if nullable and not use.button_pressed:
			use.set_pressed_no_signal(true)
		on_edit.call(read.call()))
	use.toggled.connect(func(_on):
		sb.editable = use.button_pressed or not nullable
		on_edit.call(read.call()))
	var setter := func(v: Variant) -> void:
		state.raw = v
		note.visible = v is Dictionary
		note.text = "(%s)" % RPGCommand.describe_operand(v) if v is Dictionary else ""
		use.set_pressed_no_signal(v != null)
		sb.editable = v != null or not nullable
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			sb.set_value_no_signal(float(v))
		else:
			sb.set_value_no_signal(maxf(sb.min_value, minf(0.0, sb.max_value)) if f.has("min") or f.has("max") else 0.0)
	return {"control": hb, "get": read, "set": setter}


func _choice_editor(f: Dictionary, opts: Array, labels: Array, on_edit: Callable) -> Dictionary:
	var ob := OptionButton.new()
	var state := {"opts": opts.duplicate(), "extra": null}
	var fill := func(current: Variant) -> void:
		ob.clear()
		for i in opts.size():
			var text := str(labels[i]) if i < labels.size() else str(opts[i]).replace("_", " ").capitalize()
			if str(opts[i]) in ["==", "!=", "<", "<=", ">", ">=", "A", "B", "C", "D"] and i >= labels.size():
				text = str(opts[i])
			ob.add_item(text)
		state.opts = opts.duplicate()
		if current != null and not opts.has(current):
			# Keep values the descriptor does not list; never replace them silently.
			ob.add_item("⚠ %s" % str(current))
			state.opts.append(current)
		elif current == null and not opts.has(null):
			# No value yet: say so (select(-1) is an engine error) and keep it null until picked.
			ob.add_item("(not set)")
			state.opts.append(null)
		var idx: int = state.opts.find(current)
		if idx >= 0:
			ob.select(idx)
	ob.item_selected.connect(func(i): on_edit.call(state.opts[i]))
	return {"control": ob, "get": func(): return state.opts[ob.selected] if ob.selected >= 0 else null, "set": fill}


func _multiline_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(300, 80)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.scroll_fit_content_height = true
	vb.add_child(te)
	var preview := Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(preview)
	var upd := func() -> void:
		var p := preview_text(te.text, data)
		preview.text = "Preview: " + p if p != te.text or te.text.find("\\") != -1 else ""
		preview.visible = preview.text != ""
	te.text_changed.connect(func():
		upd.call()
		on_edit.call(te.text))
	var setter := func(v: Variant) -> void:
		te.text = str(v) if v != null else ""
		upd.call()
	return {"control": vb, "get": func(): return te.text, "set": setter}


## Live preview of message text codes (\V[id], \S[id], \N[actor], \G, \C[n], \I[n], waits).
static func preview_text(text: String, p_data: RPGProjectData) -> String:
	var re := RegEx.create_from_string("\\\\(\\\\|[A-Za-z])(?:\\[([^\\]]*)\\])?|\\\\[.|!><$^]")
	var out := ""
	var last := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		last = m.get_end()
		var code := m.get_string(1).to_upper()
		var arg := m.get_string(2)
		match code:
			"\\":
				out += "\\"
			"V":
				out += "«%s»" % (str(p_data.variables[arg].get("label", arg)) if p_data != null and p_data.variables.has(arg) else "?" + arg)
			"S":
				out += "«%s ON/OFF»" % arg
			"N":
				out += str(p_data.record("actors", arg).get("name", arg)) if p_data != null and p_data.has_record("actors", arg) else "«%s»" % arg
			"P":
				out += "«party %s»" % arg
			"G":
				out += str(p_data.system.get("currency", "G")) if p_data != null else "G"
			"I":
				var icon_name := RPGIcons.name_of(arg.to_int()) if arg.is_valid_int() else ""
				out += "«icon %s»" % (icon_name.replace("_", " ") if icon_name != "" else arg)
			_:
				pass
	out += text.substr(last)
	return out


func _location_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var hb := HBoxContainer.new()
	var map := RPGRefPicker.new("map", data, [], false)
	map.custom_minimum_size.x = 140
	var x := SpinBox.new()
	var y := SpinBox.new()
	for sb in [x, y]:
		sb.min_value = 0
		sb.max_value = 9999
		sb.rounded = true
	x.prefix = "x"
	y.prefix = "y"
	var pick := Button.new()
	pick.text = "Pick on map…"
	pick.tooltip_text = "Open the destination map and click the tile to land on"
	hb.add_child(map)
	hb.add_child(x)
	hb.add_child(y)
	hb.add_child(pick)
	var state := {"v": null}
	var read := func() -> Variant:
		var out: Dictionary = state.v.duplicate(true) if state.v is Dictionary else {}
		out["map"] = str(map.get_value())
		out["position"] = [int(x.value), int(y.value)]
		return out
	var emit := func(_a = null) -> void:
		state.v = read.call()
		on_edit.call(state.v)
	map.value_changed.connect(emit)
	x.value_changed.connect(emit)
	y.value_changed.connect(emit)
	var setter := func(v: Variant) -> void:
		state.v = v
		if v is Dictionary:
			map.set_value(str(v.get("map", "")))
			var p: Variant = v.get("position", [0, 0])
			if p is Array and p.size() == 2:
				x.set_value_no_signal(float(p[0]))
				y.set_value_no_signal(float(p[1]))
		else:
			map.set_value("")
			x.set_value_no_signal(0)
			y.set_value_no_signal(0)
	pick.pressed.connect(func():
		var cb := func(map_id: String, cell: Vector2i) -> void:
			if map_id == "":
				return   # the pick was cancelled
			setter.call({"map": map_id, "position": [cell.x, cell.y]} if not (state.v is Dictionary) else _merged(state.v, {"map": map_id, "position": [cell.x, cell.y]}))
			emit.call()
		pick_location_requested.emit(cb, state.v))
	return {"control": hb, "get": func(): return state.v, "set": setter}


static func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		out[k] = b[k]
	return out


func _sound_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var vb := VBoxContainer.new()
	var top := HBoxContainer.new()
	vb.add_child(top)
	var role := Label.new()
	role.visible = false
	top.add_child(role)
	var file := RPGResourcePicker.new(str(f.get("res", "sound")), "")
	top.add_child(file)
	var nums := HBoxContainer.new()
	vb.add_child(nums)
	var vol := SpinBox.new()
	vol.prefix = "Vol"
	vol.min_value = 0
	vol.max_value = 100
	var pitch := SpinBox.new()
	pitch.prefix = "Pitch"
	pitch.min_value = 50
	pitch.max_value = 150
	var pan := SpinBox.new()
	pan.prefix = "Pan"
	pan.min_value = -100
	pan.max_value = 100
	for sb in [vol, pitch, pan]:
		sb.rounded = true
		# Room for the "Pitch 100" prefix and value (it was cut to "itch 100").
		sb.get_line_edit().expand_to_text_length = true
		nums.add_child(sb)
	var play := Button.new()
	play.text = "▶ Play"
	nums.add_child(play)
	var state := {"v": null}
	var read := func() -> Variant:
		var out: Dictionary = state.v.duplicate(true) if state.v is Dictionary else {}
		var fv := str(file.get_value()) if file.get_value() != null else ""
		if fv != "" or not out.has("role"):
			out["file"] = fv
		out["volume"] = int(vol.value)
		out["pitch"] = int(pitch.value)
		out["pan"] = int(pan.value)
		return out
	var emit := func(_a = null) -> void:
		state.v = read.call()
		on_edit.call(state.v)
	file.value_changed.connect(emit)
	vol.value_changed.connect(emit)
	pitch.value_changed.connect(emit)
	pan.value_changed.connect(emit)
	play.pressed.connect(func(): file.play_with(str(file.get_value()), vol.value, pitch.value))
	var setter := func(v: Variant) -> void:
		state.v = v
		var d: Dictionary = v if v is Dictionary else {}
		file.set_value(str(d.get("file", "")))
		role.visible = d.has("role")
		role.text = "Role: %s" % d.get("role", "")
		role.tooltip_text = "The asset profile maps this role to a file. Choose a file to override it."
		vol.set_value_no_signal(float(d.get("volume", 100)))
		pitch.set_value_no_signal(float(d.get("pitch", 100)))
		pan.set_value_no_signal(float(d.get("pan", 0)))
	return {"control": vb, "get": func(): return state.v, "set": setter}


func _condition_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	# A single condition field is Conditional Branch's (page conditions are lists).
	var ce := RPGConditionEditor.new(data, registry, bool(options.get("battle_conditions", f.get("battle", false))), options, true)
	ce.value_changed.connect(func(v): on_edit.call(v))
	ce.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
	return {"control": ce, "get": ce.get_value, "set": ce.set_value}


func _operand_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var hb := HBoxContainer.new()
	var mode := OptionButton.new()
	for m in OPERAND_MODES:
		mode.add_item(m)
	mode.tooltip_text = "A fixed number, a variable's value, a random number, or game data (items held, gold, an actor's level...)"
	var sb := SpinBox.new()
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.min_value = float(f.get("min", -9999999))
	sb.max_value = float(f.get("max", 9999999))
	sb.allow_lesser = not f.has("min")
	sb.allow_greater = not f.has("max")
	var is_float := typeof(f.get("default")) == TYPE_FLOAT
	sb.step = 0.01 if is_float else 1.0
	sb.rounded = not is_float
	var vp := RPGRefPicker.new("variable", data, [], false)
	# Random: from .. to (inclusive).
	var rlo := SpinBox.new()
	var rhi := SpinBox.new()
	for r in [rlo, rhi]:
		r.min_value = -9999999
		r.max_value = 9999999
		r.rounded = true
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rlo.prefix = "from"
	rhi.prefix = "to"
	# Game data: kind, record, actor field.
	var gk := OptionButton.new()
	for i in GAME_DATA_KINDS.size():
		gk.add_item(GAME_DATA_LABELS[i])
	var gref := RPGRefPicker.new("item", data, [], false)
	var gfield := OptionButton.new()
	gfield.tooltip_text = "Which number of the actor"
	var lists := rule_lists(data)
	var field_ids: Array = ["level", "exp"]
	var field_labels: Array = ["Level", "Experience"]
	for r in lists.resources:
		field_ids.append(str(r.id))
		field_labels.append(str(r.get("label", r.id)))
	for st in lists.stats:
		if not field_ids.has(str(st.id)):
			field_ids.append(str(st.id))
			field_labels.append(str(st.get("label", st.id)))
	for i in field_ids.size():
		gfield.add_item(field_labels[i])
	for c in [mode, sb, vp, rlo, rhi, gk, gref, gfield]:
		hb.add_child(c)
	var state := {"v": null, "fields": field_ids}
	var gkind := func() -> String:
		return GAME_DATA_KINDS[gk.selected] if gk.selected >= 0 else "gold"
	var show := func() -> void:
		var m := mode.selected
		sb.visible = m == 0
		vp.visible = m == 1
		rlo.visible = m == 2
		rhi.visible = m == 2
		gk.visible = m == 3
		var k: String = gkind.call()
		gref.visible = m == 3 and k in ["item", "weapon", "armor", "actor"]
		gfield.visible = m == 3 and k == "actor"
		if gref.visible:
			gref.set_ref_kind(k)
	var read := func() -> Variant:
		match mode.selected:
			1:
				var out: Dictionary = state.v.duplicate(true) if state.v is Dictionary and state.v.has("variable") else {}
				out["variable"] = str(vp.get_value())
				return out
			2:
				var out2: Dictionary = state.v.duplicate(true) if state.v is Dictionary and state.v.has("random") else {}
				out2["random"] = [int(rlo.value), int(rhi.value)]
				return out2
			3:
				var out3: Dictionary = state.v.duplicate(true) if state.v is Dictionary and state.v.get("game_data") is Dictionary else {}
				var g: Dictionary = out3.get("game_data", {})
				var k: String = gkind.call()
				g["kind"] = k
				if k in ["item", "weapon", "armor", "actor"]:
					g["id"] = str(gref.get_value()) if gref.get_value() != null else ""
				else:
					g.erase("id")
				if k == "actor":
					g["field"] = str(state.fields[gfield.selected]) if gfield.selected >= 0 else "level"
				else:
					g.erase("field")
				out3["game_data"] = g
				return out3
		return sb.value if is_float else int(sb.value)
	var emit := func(_a = null) -> void:
		show.call()
		state.v = read.call()
		on_edit.call(state.v)
	mode.item_selected.connect(emit)
	sb.value_changed.connect(emit)
	vp.value_changed.connect(emit)
	rlo.value_changed.connect(emit)
	rhi.value_changed.connect(emit)
	gk.item_selected.connect(func(_i):
		# A new kind starts without the old kind's record.
		gref.set_value("")
		emit.call())
	gref.value_changed.connect(emit)
	gfield.item_selected.connect(emit)
	var setter := func(v: Variant) -> void:
		state.v = v
		if v is Dictionary and v.get("random") is Array:
			mode.select(2)
			var r: Array = v.random
			rlo.set_value_no_signal(float(r[0]) if r.size() > 0 and typeof(r[0]) in [TYPE_INT, TYPE_FLOAT] else 0.0)
			rhi.set_value_no_signal(float(r[1]) if r.size() > 1 and typeof(r[1]) in [TYPE_INT, TYPE_FLOAT] else 0.0)
		elif v is Dictionary and v.get("game_data") is Dictionary:
			mode.select(3)
			var g: Dictionary = v.game_data
			var ki := GAME_DATA_KINDS.find(str(g.get("kind", "gold")))
			gk.select(ki if ki >= 0 else GAME_DATA_KINDS.find("gold"))
			gref.set_ref_kind(gkind.call())
			gref.set_value(str(g.get("id", "")))
			var fld := str(g.get("field", "level"))
			if not state.fields.has(fld):
				# Keep fields the rule system does not list; never replace them silently.
				state.fields.append(fld)
				gfield.add_item("⚠ %s" % fld)
			gfield.select(state.fields.find(fld))
		elif v is Dictionary:
			mode.select(1)
			vp.set_value(str(v.get("variable", "")))
		else:
			mode.select(0)
			sb.set_value_no_signal(float(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0.0)
		show.call()
	return {"control": hb, "get": func(): return state.v, "set": setter}


## {stats: [{id, label}], resources: [{id, label}]} of the project's rule system (rules.json),
## for pickers that list them. Empty lists when there is none.
static func rule_lists(p_data: RPGProjectData) -> Dictionary:
	var out := {"stats": [], "resources": []}
	if p_data == null:
		return out
	var name := str(p_data.project.get("rules", "classic"))
	var key := "%s|%s" % [p_data.root, name]
	if _rule_lists_cache.has(key):
		return _rule_lists_cache[key]
	for dir in [p_data.root.path_join("rules"), "res://rpg/rules", "res://addons/rpg/runtime/rules"]:
		var path: String = dir.path_join(name).path_join("rules.json")
		if FileAccess.file_exists(path):
			var parsed := RPGJson.parse_file(path)
			if parsed.ok and parsed.data is Dictionary:
				for k in ["stats", "resources"]:
					for x in parsed.data.get(k, []):
						if x is Dictionary and x.has("id"):
							out[k].append(x)
			break
	_rule_lists_cache[key] = out
	return out


func _operand_pair_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var hb := HBoxContainer.new()
	var state := {"v": [0, 0]}
	var a := _operand_editor({"key": "x", "min": 0}, func(v): state.v[0] = v; on_edit.call(state.v.duplicate(true)))
	var b := _operand_editor({"key": "y", "min": 0}, func(v): state.v[1] = v; on_edit.call(state.v.duplicate(true)))
	hb.add_child(a.control)
	hb.add_child(b.control)
	var setter := func(v: Variant) -> void:
		state.v = v.duplicate(true) if v is Array and v.size() == 2 else [0, 0]
		a.set.call(state.v[0])
		b.set.call(state.v[1])
	return {"control": hb, "get": func(): return state.v, "set": setter}


func _color_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(80, 24)
	var state := {"len": 4}
	var read := func() -> Variant:
		var c := cp.color
		var out := [int(round(c.r * 255)), int(round(c.g * 255)), int(round(c.b * 255))]
		if state.len >= 4:
			out.append(int(round(c.a * 255)))
		return out
	cp.color_changed.connect(func(_c): on_edit.call(read.call()))
	var setter := func(v: Variant) -> void:
		if v is Array and v.size() >= 3:
			state.len = v.size()
			cp.color = Color8(int(v[0]), int(v[1]), int(v[2]), int(v[3]) if v.size() > 3 else 255)
		cp.edit_alpha = state.len >= 4
	return {"control": cp, "get": read, "set": setter}


func _list_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var le := RPGListEditor.new(f, data, registry, options)
	le.value_changed.connect(func(v): on_edit.call(v))
	le.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
	return {"control": le, "get": le.get_value, "set": le.set_value}


func _object_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	if f.get("fields", []).is_empty():
		return _json_editor(f, on_edit)
	var sub := RPGFormBuilder.new()
	sub.setup(f.fields, data, registry, options)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_child(sub)
	var state := {"v": null}
	sub.value_changed.connect(func(_k, _v):
		state.v = sub.get_value()
		on_edit.call(state.v))
	sub.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
	# default null: an on/off box. Off stores `off_value` (null unless the field says otherwise).
	var nullable := f.has("default") and f.default == null
	var box := VBoxContainer.new()
	var use := CheckBox.new()
	use.text = str(f.get("toggle_label", "On"))
	use.visible = nullable
	box.add_child(use)
	box.add_child(margin)
	use.toggled.connect(func(on: bool):
		margin.visible = on
		if on:
			var d: Dictionary = sub.get_value()
			for sf in f.fields:
				if sf is Dictionary and not d.has(sf.get("key", "")) and sf.get("default") != null:
					d[sf.key] = RPGJson.deep_copy(sf.default)
			sub.set_value(d)
			state.v = d
		else:
			state.v = RPGJson.deep_copy(f.get("off_value"))
		on_edit.call(state.v))
	var setter := func(v: Variant) -> void:
		state.v = v
		var on: bool = not nullable or (v is Dictionary and not v.is_empty())
		use.set_pressed_no_signal(on)
		margin.visible = on
		sub.set_value(v if v is Dictionary else {})
	return {"control": box, "get": func(): return state.v, "set": setter}


## A class stat's growth (RPGRuleSystem._growth_value): "Per level" {base, per_level, accel?}
## or "Curve" {at_1, at_99, shape} where shape is a name from the field's `shapes`
## ({name: exponent}) or a number. Switching converts the numbers so the stat stays close.
## Tables and flat numbers are kept as they are (edited as JSON). A small graph shows the
## value from level 1 to `max_level`, like RPG Maker's parameter curves.
func _growth_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var shapes: Dictionary = f.get("shapes", {"linear": 1.0, "early": 0.75, "late": 1.5})
	var max_level := int(f.get("max_level", 99))
	var vb := VBoxContainer.new()
	var row := HBoxContainer.new()
	vb.add_child(row)
	var mode := OptionButton.new()
	mode.add_item("Per level")
	mode.add_item("Curve")
	mode.tooltip_text = "Per level: base + per level x (level - 1). Curve: level 1 and level 99 values joined by a shape."
	row.add_child(mode)
	var spins := {}
	for spec in [["base", "Lv 1"], ["per_level", "+"], ["at_1", "Lv 1"], ["at_99", "Lv 99"]]:
		var sb := SpinBox.new()
		sb.min_value = -999999
		sb.max_value = 9999999
		sb.rounded = true
		sb.prefix = spec[1]
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sb)
		spins[spec[0]] = sb
	spins.per_level.suffix = "/ level"
	var shape := OptionButton.new()
	var shape_ids: Array = shapes.keys()
	for n in shape_ids:
		shape.add_item(str(n).replace("_", " ").capitalize())
	shape.add_item("Custom exponent")
	shape.tooltip_text = "How the value grows between level 1 and 99: early shapes grow fast at first"
	row.add_child(shape)
	var expo := SpinBox.new()
	expo.min_value = 0.05
	expo.max_value = 10.0
	expo.step = 0.05
	expo.value = 1.0
	expo.tooltip_text = "Exponent: below 1 grows early, above 1 grows late"
	row.add_child(expo)
	var note := Label.new()
	note.text = "(a per-level table or a fixed number; edit it in the JSON file)"
	note.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(note)
	var graph := Control.new()
	graph.custom_minimum_size = Vector2(260, 64)
	graph.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	graph.tooltip_text = "Level 1 to %d" % max_level
	vb.add_child(graph)
	var state := {"v": null, "fixed": false, "shape_ids": shape_ids}
	var shape_value := func() -> Variant:
		var i := shape.selected
		if i >= 0 and i < state.shape_ids.size():
			return str(state.shape_ids[i])
		return snappedf(expo.value, 0.01)
	var read := func() -> Variant:
		if state.fixed:
			return state.v
		var out: Dictionary = state.v.duplicate(true) if state.v is Dictionary else {}
		if mode.selected == 0:
			for k in ["at_1", "at_99", "shape"]:
				out.erase(k)
			out["base"] = int(spins.base.value)
			out["per_level"] = int(spins.per_level.value)
		else:
			for k in ["base", "per_level", "accel"]:
				out.erase(k)
			out["at_1"] = int(spins.at_1.value)
			out["at_99"] = int(spins.at_99.value)
			out["shape"] = shape_value.call()
		return out
	var show := func() -> void:
		var curve := mode.selected == 1
		mode.visible = not state.fixed
		note.visible = state.fixed
		spins.base.visible = not state.fixed and not curve
		spins.per_level.visible = not state.fixed and not curve
		spins.at_1.visible = not state.fixed and curve
		spins.at_99.visible = not state.fixed and curve
		shape.visible = not state.fixed and curve
		expo.visible = not state.fixed and curve and shape.selected == state.shape_ids.size()
		graph.queue_redraw()
	var emit := func(_a = null) -> void:
		state.v = read.call()
		show.call()
		on_edit.call(state.v)
	graph.draw.connect(func() -> void:
		var w := graph.size.x
		var h := graph.size.y
		graph.draw_rect(Rect2(Vector2.ZERO, graph.size), Color(0.08, 0.09, 0.12))
		var vals := PackedFloat32Array()
		var top := 1.0
		for lv in range(1, max_level + 1):
			var x := growth_value(state.v, lv, shapes)
			vals.append(x)
			top = maxf(top, absf(x))
		var pts := PackedVector2Array()
		for i in vals.size():
			pts.append(Vector2(2 + (w - 4) * i / maxf(1.0, vals.size() - 1.0), h - 2 - (h - 14) * clampf(vals[i] / top, 0.0, 1.0)))
		if pts.size() >= 2:
			graph.draw_polyline(pts, Color(1.0, 0.62, 0.25), 1.5, true)
		var font := graph.get_theme_default_font()
		var txt := "Lv 1: %d   Lv %d: %d" % [int(vals[0]) if not vals.is_empty() else 0, max_level, int(vals[vals.size() - 1]) if not vals.is_empty() else 0]
		graph.draw_string(font, Vector2(4, 11), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.75)))
	mode.item_selected.connect(func(i: int):
		# Convert, so the stat stays about the same.
		if i == 1:
			var b: float = spins.base.value
			spins.at_1.set_value_no_signal(b)
			spins.at_99.set_value_no_signal(b + spins.per_level.value * 98.0)
			shape.select(maxi(0, state.shape_ids.find("linear")))
		else:
			spins.base.set_value_no_signal(spins.at_1.value)
			spins.per_level.set_value_no_signal(roundf((spins.at_99.value - spins.at_1.value) / 98.0))
		emit.call())
	for k in spins:
		spins[k].value_changed.connect(emit)
	shape.item_selected.connect(emit)
	expo.value_changed.connect(emit)
	var setter := func(v: Variant) -> void:
		state.v = v
		state.fixed = v != null and not (v is Dictionary)
		var d: Dictionary = v if v is Dictionary else {}
		var curve: bool = d.has("at_1") or d.has("at_99")
		mode.select(1 if curve else 0)
		for k in spins:
			var n: Variant = d.get(k, 0)
			spins[k].set_value_no_signal(float(n) if typeof(n) in [TYPE_INT, TYPE_FLOAT] else 0.0)
		if curve and not d.has("at_99"):
			spins.at_99.set_value_no_signal(spins.at_1.value)
		var sh: Variant = d.get("shape", "linear")
		if typeof(sh) in [TYPE_INT, TYPE_FLOAT]:
			shape.select(state.shape_ids.size())
			expo.set_value_no_signal(float(sh))
		else:
			var si: int = state.shape_ids.find(str(sh))
			if si == -1:
				# Keep names the rule system does not list.
				state.shape_ids.append(str(sh))
				shape.clear()
				for n in state.shape_ids:
					shape.add_item(str(n).replace("_", " ").capitalize() if shapes.has(n) else "⚠ %s" % n)
				shape.add_item("Custom exponent")
				si = state.shape_ids.size() - 1
			shape.select(si)
		show.call()
	return {"control": vb, "get": func(): return state.v, "set": setter}


## A growth entry's value at `level` (same maths as RPGRuleSystem._growth_value).
static func growth_value(g: Variant, level: int, shapes: Dictionary = {}) -> float:
	if g is Dictionary and (g.has("at_1") or g.has("at_99")):
		var lo := float(g.get("at_1", 0))
		var hi := float(g.get("at_99", lo))
		var t := clampf(float(level - 1) / 98.0, 0.0, 1.0)
		var sh: Variant = g.get("shape", "linear")
		var e := 1.0
		if typeof(sh) in [TYPE_INT, TYPE_FLOAT]:
			e = maxf(0.01, float(sh))
		elif shapes.has(str(sh)):
			e = maxf(0.01, float(shapes[str(sh)]))
		return lo + (hi - lo) * pow(t, e)
	if g is Dictionary:
		var n := float(level - 1)
		return float(g.get("base", 0)) + float(g.get("per_level", 0)) * n + float(g.get("accel", 0)) * n * n
	if g is Array:
		return 0.0 if g.is_empty() else float(g[clampi(level - 1, 0, g.size() - 1)])
	if typeof(g) in [TYPE_INT, TYPE_FLOAT]:
		return float(g)
	return 0.0


## Two whole numbers [x, y] (e.g. an enemy's position in battle pixels).
func _point_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var hb := HBoxContainer.new()
	var x := SpinBox.new()
	var y := SpinBox.new()
	for sb in [x, y]:
		sb.min_value = float(f.get("min", 0))
		sb.max_value = float(f.get("max", 9999))
		sb.rounded = true
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(sb)
	x.prefix = "x"
	y.prefix = "y"
	var state := {"v": null}
	var emit := func(_a = null) -> void:
		state.v = [int(x.value), int(y.value)]
		on_edit.call(state.v)
	x.value_changed.connect(emit)
	y.value_changed.connect(emit)
	var setter := func(v: Variant) -> void:
		state.v = v
		var ok: bool = v is Array and v.size() >= 2 and typeof(v[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(v[1]) in [TYPE_INT, TYPE_FLOAT]
		x.set_value_no_signal(float(v[0]) if ok else 0.0)
		y.set_value_no_signal(float(v[1]) if ok else 0.0)
	return {"control": hb, "get": func(): return state.v, "set": setter}


## {id: count} (e.g. starting items): rows of [ID picker][count][remove] plus "+ Add". A row
## whose ID is still blank is left out of the value; the same ID twice adds the counts.
## (Row callbacks share a plain context Dictionary; no lambda refers to itself, so nothing leaks.)
func _count_map_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows_box := VBoxContainer.new()
	vb.add_child(rows_box)
	var add := Button.new()
	add.text = "+ Add"
	add.tooltip_text = "Add a row"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(add)
	var empty := Label.new()
	empty.text = "(none)"
	empty.modulate = Color(1, 1, 1, 0.6)
	rows_box.add_child(empty)
	# rows: [[id, count], ...]
	var ctx := {"v": null, "rows": [], "box": rows_box, "empty": empty, "on_edit": on_edit,
		"ref": str(f.get("ref", "item")), "lo": float(f.get("min", 1)), "hi": float(f.get("max", 9999))}
	add.pressed.connect(_count_map_add.bind(ctx))
	var setter := func(v: Variant) -> void:
		ctx.v = v
		ctx.rows = []
		if v is Dictionary:
			for k in v:
				var n: Variant = v[k]
				ctx.rows.append([str(k), int(n) if typeof(n) in [TYPE_INT, TYPE_FLOAT] or (n is String and n.is_valid_int()) else 1])
		_count_map_rebuild(ctx)
	return {"control": vb, "get": func(): return ctx.v, "set": setter}


static func _count_map_read(ctx: Dictionary) -> Dictionary:
	var out := {}
	for r in ctx.rows:
		var id := str(r[0])
		if id != "":
			out[id] = int(out.get(id, 0)) + int(r[1])
	return out


func _count_map_emit(ctx: Dictionary) -> void:
	ctx.v = _count_map_read(ctx)
	ctx.on_edit.call(ctx.v)


func _count_map_add(ctx: Dictionary) -> void:
	# Start with the first ID not listed yet, so the row counts at once.
	var used := _count_map_read(ctx)
	var pick := ""
	var probe := RPGRefPicker.new(str(ctx.ref), data, [], false)
	for e in probe.entries():
		if not used.has(str(e.id)):
			pick = str(e.id)
			break
	probe.free()
	ctx.rows.append([pick, int(maxf(float(ctx.lo), 1.0))])
	_count_map_rebuild(ctx)
	if pick != "":
		_count_map_emit(ctx)


func _count_map_remove(ctx: Dictionary, row: Array) -> void:
	var i: int = ctx.rows.find(row)
	if i >= 0:
		ctx.rows.remove_at(i)
	_count_map_rebuild.call_deferred(ctx)
	_count_map_emit(ctx)


func _count_map_set(v: Variant, ctx: Dictionary, row: Array, col: int) -> void:
	if col == 0:
		row[0] = str(v) if v != null else ""
	else:
		row[1] = int(v)
	_count_map_emit(ctx)


func _count_map_rebuild(ctx: Dictionary) -> void:
	var box: VBoxContainer = ctx.box
	if not is_instance_valid(box):
		return
	for c in box.get_children():
		if c != ctx.empty:
			box.remove_child(c)
			c.queue_free()
	ctx.empty.visible = ctx.rows.is_empty()
	for row in ctx.rows:
		var hb := HBoxContainer.new()
		var rp := RPGRefPicker.new(str(ctx.ref), data, [], false)
		rp.set_value(str(row[0]))
		rp.value_changed.connect(_count_map_set.bind(ctx, row, 0))
		hb.add_child(rp)
		var sb := SpinBox.new()
		sb.min_value = float(ctx.lo)
		sb.max_value = float(ctx.hi)
		sb.rounded = true
		sb.custom_minimum_size.x = 90
		sb.tooltip_text = "How many"
		sb.set_value_no_signal(float(row[1]))
		sb.value_changed.connect(_count_map_set.bind(ctx, row, 1))
		hb.add_child(sb)
		var rm := Button.new()
		rm.text = "✕"
		rm.flat = true
		rm.tooltip_text = "Remove this row"
		rm.pressed.connect(_count_map_remove.bind(ctx, row))
		hb.add_child(rm)
		box.add_child(hb)


## A face from a FaceSet. Command fields (default null, e.g. Show Text) hold {sheet, index};
## record fields (default "", e.g. an actor's face) hold the sheet name and keep the index in a
## separate field. The thumbnail shows the chosen face, not the whole sheet.
func _face_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var hb := HBoxContainer.new()
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(48, 48)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(thumb)
	var sheet := RPGResourcePicker.new("faceset", "")
	sheet.set_preview_visible(false)
	hb.add_child(sheet)
	var idx := SpinBox.new()
	idx.prefix = "#"
	idx.min_value = 0
	idx.max_value = 15
	idx.rounded = true
	idx.tooltip_text = "Which face on the sheet (counted from 0, left to right, top to bottom)"
	hb.add_child(idx)
	var dict_default := f.has("default") and f.default == null
	# "index_from": the sibling field holding the index when the value is a plain sheet name.
	var state := {"v": null, "dict": dict_default, "sibling_index": 0}
	var show := func() -> void:
		var s := str(sheet.get_value()) if sheet.get_value() != null else ""
		idx.visible = state.dict
		thumb.texture = face_texture(data, s, int(idx.value) if state.dict else int(state.sibling_index)) if s != "" else null
		thumb.visible = s != ""
	var read := func() -> Variant:
		var s := str(sheet.get_value()) if sheet.get_value() != null else ""
		if not state.dict:
			return s
		if s == "":
			return null
		var out: Dictionary = state.v.duplicate(true) if state.v is Dictionary else {}
		out["sheet"] = s
		out["index"] = int(idx.value)
		return out
	var emit := func(_a = null) -> void:
		show.call()
		state.v = read.call()
		on_edit.call(state.v)
	sheet.value_changed.connect(emit)
	idx.value_changed.connect(emit)
	var setter := func(v: Variant) -> void:
		state.v = v
		if v is Dictionary:
			state.dict = true
			sheet.set_value(str(v.get("sheet", "")))
			var n: Variant = v.get("index", 0)
			idx.set_value_no_signal(float(n) if typeof(n) in [TYPE_INT, TYPE_FLOAT] else 0.0)
		else:
			state.dict = dict_default if v == null else false
			sheet.set_value(str(v) if v != null else "")
			idx.set_value_no_signal(0.0)
		show.call()
	var sync := func(all: Dictionary) -> void:
		if not f.has("index_from"):
			return
		var n: Variant = all.get(f.index_from, 0)
		var i := int(n) if typeof(n) in [TYPE_INT, TYPE_FLOAT] else 0
		if i != int(state.sibling_index):
			state.sibling_index = i
			show.call()
	return {"control": hb, "get": func(): return state.v, "set": setter, "sync": sync}


## One face cell of a FaceSet as a texture (size from the project's asset profile), or null.
static func face_texture(p_data: RPGProjectData, sheet_name: String, index: int) -> Texture2D:
	var tex := RPGResourcePicker.texture("faceset", sheet_name)
	if tex == null:
		return null
	var prof := str(p_data.profile.get("profile", "rm2k")) if p_data != null else "rm2k"
	# A sheet from an imported pack keeps its own layout (e.g. VX faces in a 2000 project).
	prof = RPGAssets.sheet_profile("faceset", sheet_name, prof)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(RPGCharset.face_rect(prof, Vector2i(tex.get_width(), tex.get_height()), index))
	return at


## "Line 3: Expected ..." for a failed RPGJson.parse_text result. Godot counts lines from 0;
## makers count from 1.
static func json_error_text(r: Dictionary) -> String:
	if int(r.get("line", -1)) < 0:
		return str(r.get("error", ""))
	return "Line %d: %s" % [int(r.line) + 1, str(r.get("error", ""))]


## Free-form JSON value (object fields with no declared sub-fields, unknown kinds).
## Invalid text never reaches the value: the last valid value is kept and the error is shown.
func _json_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var vb := VBoxContainer.new()
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(260, 60)
	te.scroll_fit_content_height = true
	var msg := Label.new()
	msg.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	msg.visible = false
	vb.add_child(te)
	vb.add_child(msg)
	var state := {"v": null}
	te.text_changed.connect(func():
		var r := RPGJson.parse_text(te.text)
		if r.ok:
			msg.visible = false
			state.v = r.data
			on_edit.call(r.data)
		else:
			msg.text = "%s (not saved until fixed)" % json_error_text(r)
			msg.visible = true)
	var setter := func(v: Variant) -> void:
		state.v = v
		te.text = RPGJson.stringify(v).strip_edges()
		msg.visible = false
	return {"control": vb, "get": func(): return state.v, "set": setter}


func _commands_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var state := {"v": []}
	if options.get("hide_command_lists", false) or not ResourceLoader.exists(COMMAND_LIST_SCRIPT):
		var l := Label.new()
		l.text = "(edited in the command list)"
		return {"control": l, "get": func(): return state.v, "set": func(v): state.v = v}
	var cle: Control = load(COMMAND_LIST_SCRIPT).new()
	cle.custom_minimum_size = Vector2(320, 120)
	cle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cle.setup(data, registry, str(options.get("map_id", "")))
	cle.commands_changed.connect(func():
		state.v = cle.get_commands()
		on_edit.call(state.v))
	var setter := func(v: Variant) -> void:
		state.v = v
		cle.set_commands(v if v is Array else [])
	return {"control": cle, "get": func(): return state.v, "set": setter}


## {sheet, index} picked from character sheets (quick event "image" answers).
func _image_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var hb := HBoxContainer.new()
	var sheet := RPGResourcePicker.new(str(f.get("res", "charset")), "")
	var idx := SpinBox.new()
	idx.prefix = "#"
	idx.min_value = 0
	idx.max_value = 7
	idx.rounded = true
	idx.tooltip_text = "Character index in the sheet (0-7)"
	sheet.set_preview_visible(false)
	var pic := _char_preview(func(i: int): idx.value = i)
	hb.add_child(pic.control)
	hb.add_child(sheet)
	hb.add_child(idx)
	var state := {"v": null}
	var show := func() -> void:
		var s := str(sheet.get_value()) if sheet.get_value() != null else ""
		pic.update.call(s, int(idx.value), "down", 1)
	var emit := func(_a = null) -> void:
		var s := str(sheet.get_value()) if sheet.get_value() != null else ""
		state.v = {"sheet": s, "index": int(idx.value)} if s != "" else null
		show.call()
		on_edit.call(state.v)
	sheet.value_changed.connect(emit)
	idx.value_changed.connect(emit)
	var setter := func(v: Variant) -> void:
		state.v = v
		sheet.set_value(str(v.get("sheet", "")) if v is Dictionary else "")
		idx.set_value_no_signal(float(v.get("index", 0)) if v is Dictionary else 0.0)
		show.call()
	return {"control": hb, "get": func(): return state.v, "set": setter}


## A clickable picture of the chosen character (the frame the map shows). Clicking it lists every
## character on the sheet; on_pick.call(index) receives the choice. Returns {control, update}
## where update.call(sheet, index, facing, frame) redraws it.
func _char_preview(on_pick: Callable) -> Dictionary:
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(48, 48)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_STOP
	pic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pic.tooltip_text = "The chosen character. Click to pick another one from the sheet."
	var state := {"sheet": ""}
	var update := func(sheet_name: String, index: int, facing: String, frame: int) -> void:
		state.sheet = sheet_name
		pic.texture = charset_frame_texture(data, sheet_name, index, facing, frame) if sheet_name != "" else null
	pic.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and str(state.sheet) != "":
			pick_character(pic, str(state.sheet), on_pick))
	return {"control": pic, "update": update}


## Popup grid of the characters on a sheet (facing down). Returns the popup (tests).
func pick_character(anchor: Control, sheet_name: String, on_pick: Callable) -> PopupPanel:
	var pop := PopupPanel.new()
	var grid := GridContainer.new()
	grid.columns = 4
	pop.add_child(grid)
	for i in charset_count(data, sheet_name):
		var b := Button.new()
		b.icon = charset_frame_texture(data, sheet_name, i, "down", 1)
		b.expand_icon = true
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.custom_minimum_size = Vector2(56, 56)
		b.tooltip_text = "#%d" % i
		b.pressed.connect(func() -> void:
			pop.hide()
			on_pick.call(i))
		grid.add_child(b)
	pop.popup_hide.connect(pop.queue_free)
	anchor.add_child(pop)
	pop.popup_centered()
	return pop


static func _charset_profile(p_data: RPGProjectData, sheet_name: String) -> String:
	var prof := str(p_data.profile.get("profile", "rm2k")) if p_data != null else "rm2k"
	# A sheet from an imported pack keeps its own layout (as on the map and in game).
	return RPGAssets.sheet_profile("charset", sheet_name, prof)


## One frame of a character on a CharSet sheet, laid out like the map view draws it, or null.
static func charset_frame_texture(p_data: RPGProjectData, sheet_name: String, index: int, facing: String, frame: int) -> Texture2D:
	var tex := RPGResourcePicker.texture("charset", sheet_name)
	if tex == null:
		return null
	var prof := _charset_profile(p_data, sheet_name)
	var f := facing if facing in ["down", "left", "right", "up"] else "down"
	return RPGCharset.frame_texture(tex, index, f, frame, prof, RPGCharset.is_single_character(sheet_name, prof))


## How many characters a CharSet sheet holds (0 when it cannot be loaded).
static func charset_count(p_data: RPGProjectData, sheet_name: String) -> int:
	var tex := RPGResourcePicker.texture("charset", sheet_name)
	if tex == null:
		return 0
	var prof := _charset_profile(p_data, sheet_name)
	return maxi(1, RPGCharset.character_count(prof, Vector2i(tex.get_width(), tex.get_height()), RPGCharset.is_single_character(sheet_name, prof)))


## Page graphic: none, a character (sheet, index, facing, frame) or a tile.
func _graphic_editor(f: Dictionary, on_edit: Callable) -> Dictionary:
	var vb := VBoxContainer.new()
	var mode := OptionButton.new()
	for t in ["None", "Character", "Tile"]:
		mode.add_item(t)
	vb.add_child(mode)
	var ch := VBoxContainer.new()
	var ch_row := HBoxContainer.new()
	var sheet := RPGResourcePicker.new("charset", "")
	var idx := SpinBox.new()
	idx.prefix = "#"
	idx.max_value = 7
	var facing := OptionButton.new()
	for d in FACINGS.slice(0, 4):
		facing.add_item(d.capitalize())
	var frame := SpinBox.new()
	frame.prefix = "frame"
	frame.max_value = 2
	sheet.set_preview_visible(false)
	var pic := _char_preview(func(i: int): idx.value = i)
	pic.control.custom_minimum_size = Vector2(64, 64)
	ch.add_child(sheet)
	ch.add_child(ch_row)
	ch_row.add_child(pic.control)
	ch_row.add_child(idx)
	ch_row.add_child(facing)
	ch_row.add_child(frame)
	vb.add_child(ch)
	var tile := LineEdit.new()
	tile.placeholder_text = "tile key, e.g. lower_17"
	tile.tooltip_text = "The tile's key (chosen in the picture above)"
	var tile_pick: Control = load(TILE_PICKER_SCRIPT).new()
	tile_pick.setup(data, str(options.get("map_id", "")))
	var tile_box := VBoxContainer.new()
	tile_box.add_child(tile_pick)
	tile_box.add_child(tile)
	vb.add_child(tile_box)
	var state := {"v": null}
	var show := func() -> void:
		ch.visible = mode.selected == 1
		tile_box.visible = mode.selected == 2
		if tile_box.visible:
			tile_pick.set_value(tile.text)
		if ch.visible:
			var s := str(sheet.get_value()) if sheet.get_value() != null else ""
			pic.update.call(s, int(idx.value), FACINGS[maxi(0, facing.selected)], int(frame.value))
	var read := func() -> Variant:
		match mode.selected:
			1:
				var out: Dictionary = state.v.duplicate(true) if state.v is Dictionary and state.v.has("sheet") else {}
				out.erase("tile")
				out["sheet"] = str(sheet.get_value()) if sheet.get_value() != null else ""
				out["index"] = int(idx.value)
				out["facing"] = FACINGS[facing.selected]
				if frame.value != 1 or out.has("frame"):
					out["frame"] = int(frame.value)
				return out
			2:
				var t: Variant = tile.text
				if state.v is Dictionary and state.v.get("tile") is Array:
					var parsed := RPGJson.parse_text(tile.text)
					if parsed.ok and parsed.data is Array:
						t = parsed.data
				return {"tile": t}
		return null
	var emit := func(_a = null) -> void:
		show.call()
		state.v = read.call()
		on_edit.call(state.v)
	mode.item_selected.connect(emit)
	sheet.value_changed.connect(emit)
	idx.value_changed.connect(emit)
	facing.item_selected.connect(emit)
	frame.value_changed.connect(emit)
	tile.text_changed.connect(emit)
	tile_pick.value_changed.connect(func(key: String):
		tile.text = key
		emit.call())
	var setter := func(v: Variant) -> void:
		state.v = v
		if v is Dictionary and v.has("tile"):
			mode.select(2)
			tile.text = JSON.stringify(v.tile) if v.tile is Array else str(v.tile)
		elif v is Dictionary:
			mode.select(1)
			sheet.set_value(str(v.get("sheet", "")))
			idx.set_value_no_signal(float(v.get("index", 0)))
			facing.select(maxi(0, FACINGS.find(str(v.get("facing", "down")))))
			frame.set_value_no_signal(float(v.get("frame", 1)))
		else:
			mode.select(0)
		show.call()
	return {"control": vb, "get": func(): return state.v, "set": setter}
