@tool
class_name RPGListEditor
extends VBoxContainer
## A list field: rows with add / remove / reorder. Rows are sub-forms built from the field's
## item_fields; `item_kind: "condition"` rows are condition editors; `item_ref: "<kind>"` rows are
## ID pickers (e.g. a list of actor IDs); `item_field: {kind, label, options...}` rows hold one
## plain value edited with that field (a dropdown of types, a cell number; "%d" in the label is
## the row number); lists with none of these hold free JSON values (one per row).
## New rows get the defaults of the fields shown for them (show_if) and of their variant cases.

signal value_changed(value: Variant)
signal pick_location_requested(callback: Callable, current: Variant)

var field: Dictionary
var data: RPGProjectData
var registry: RPGCommandRegistry
var options: Dictionary
var _items: Array = []
var _rows: VBoxContainer
var _add: Button


func _init(p_field: Dictionary = {}, p_data: RPGProjectData = null, p_registry: RPGCommandRegistry = null, p_options: Dictionary = {}) -> void:
	field = p_field
	data = p_data
	registry = p_registry
	options = p_options
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows = VBoxContainer.new()
	add_child(_rows)
	_add = Button.new()
	_add.text = "+ Add"
	_add.tooltip_text = "Add a row (there is no limit)"
	_add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add.pressed.connect(_add_row)
	add_child(_add)


func set_value(v: Variant) -> void:
	_items = v.duplicate(true) if v is Array else []
	_rebuild()


func get_value() -> Variant:
	return _items.duplicate(true)


func _new_item() -> Variant:
	if field.get("item_kind", "") == "condition":
		return {"kind": "switch", "id": "", "value": true}
	if field.has("item_ref"):
		return ""
	if field.has("item_field"):
		var itf: Dictionary = field.item_field
		if itf.has("default"):
			return RPGJson.deep_copy(itf.default)
		var opts: Array = itf.get("options", [])
		return opts[0] if not opts.is_empty() else ""
	var fs: Array = field.get("item_fields", [])
	if fs.is_empty():
		return ""
	var d := {}
	for f in fs:
		if str(f.get("kind", "")) == "variant":
			var c := RPGFormBuilder.variant_case(f, d)
			if not c.is_empty() and c.get("default") != null:
				d[f.key] = RPGJson.deep_copy(c.default)
		elif f.has("default") and RPGCommand._visible(f, d):
			d[f.key] = RPGJson.deep_copy(f.default)
	return d


func _add_row() -> void:
	_items.append(_new_item())
	_rebuild()
	_emit()


func _emit() -> void:
	value_changed.emit(get_value())


func _rebuild() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for i in _items.size():
		_rows.add_child(_make_row(i))


func _make_row(i: int) -> Control:
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	panel.add_child(hb)
	var editor: Control
	var item: Variant = _items[i]
	if field.get("item_kind", "") == "condition":
		var ce := RPGConditionEditor.new(data, registry, bool(options.get("battle_conditions", field.get("battle", false))), options)
		ce.set_value(item)
		ce.value_changed.connect(func(v): _items[i] = v; _emit())
		ce.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
		editor = ce
	elif field.has("item_ref"):
		var rp := RPGRefPicker.new(str(field.item_ref), data, [], false)
		rp.set_value(item)
		rp.value_changed.connect(func(v): _items[i] = v; _emit())
		editor = rp
	elif field.has("item_field"):
		var itf: Dictionary = field.item_field.duplicate(true)
		itf["key"] = "value"
		var lbl := str(itf.get("label", ""))
		itf["label"] = lbl % (i + 1) if lbl.contains("%d") else lbl
		var vf := RPGFormBuilder.new()
		vf.setup([itf], data, registry, options)
		vf.set_value({"value": item})
		vf.value_changed.connect(func(_k, v): _items[i] = v; _emit())
		editor = vf
	elif field.get("item_fields", []).is_empty():
		var le := LineEdit.new()
		le.text = JSON.stringify(item) if typeof(item) != TYPE_STRING else str(item)
		le.tooltip_text = "Text, a number, true/false, or JSON"
		le.text_changed.connect(func(t):
			var r := RPGJson.parse_text(t)
			_items[i] = r.data if r.ok and typeof(r.data) != TYPE_STRING else t
			_emit())
		editor = le
	else:
		var form := RPGFormBuilder.new()
		form.setup(field.item_fields, data, registry, options)
		form.set_value(item if item is Dictionary else {})
		form.value_changed.connect(func(_k, _v): _items[i] = form.get_value(); _emit())
		form.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
		editor = form
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(editor)
	# One-line rows (ID pickers, plain values) keep their buttons on the same line.
	var one_line: bool = field.has("item_ref") or field.has("item_field") or (field.get("item_kind", "") != "condition" and field.get("item_fields", []).is_empty())
	var tools: BoxContainer = HBoxContainer.new() if one_line else VBoxContainer.new()
	hb.add_child(tools)
	for spec in [["▲", "Move up", _move.bind(i, -1)], ["▼", "Move down", _move.bind(i, 1)], ["✕", "Delete row", _remove.bind(i)]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[1]
		b.flat = true
		b.pressed.connect(spec[2])
		tools.add_child(b)
	return panel


func _move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= _items.size():
		return
	var t: Variant = _items[i]
	_items[i] = _items[j]
	_items[j] = t
	_rebuild.call_deferred()
	_emit()


func _remove(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	_items.remove_at(i)
	_rebuild.call_deferred()
	_emit()
