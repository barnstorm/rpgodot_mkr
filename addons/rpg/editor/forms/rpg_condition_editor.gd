@tool
class_name RPGConditionEditor
extends VBoxContainer
## One condition: a kind dropdown plus that kind's fields (built with RPGFormBuilder).
## Same shape on pages and in `if` commands: {kind, ...}. Compound kinds (all/any/not) and
## unknown kinds are edited as JSON so nothing is lost. Character facing and Button held are
## offered only in Conditional Branch (`branch`), as in RPG Maker.

signal value_changed(value: Variant)
signal pick_location_requested(callback: Callable, current: Variant)

const KIND_LABELS := {
	"switch": "Switch", "variable": "Variable", "self_switch": "Self switch", "item": "Item / weapon / armour held",
	"actor": "Actor", "gold": "Gold", "turn": "Turn", "enemy_hp": "Enemy HP", "actor_hp": "Actor HP",
	"vehicle": "Vehicle", "facing": "Character facing", "button": "Button held down",
}

var data: RPGProjectData
var registry: RPGCommandRegistry
var battle := false
var branch := false
var options: Dictionary = {}
var _kinds: Array = []
## Kinds with a form here (_kinds also lists unknown kinds that were loaded).
var _offered: Array = []
var _kind_opt: OptionButton
## kind -> declaration of the extension condition kinds offered here.
var _ext_kinds: Dictionary = {}
var _form: RPGFormBuilder
var _value: Variant = null


func _init(p_data: RPGProjectData = null, p_registry: RPGCommandRegistry = null, p_battle := false, p_options: Dictionary = {}, p_branch := false) -> void:
	data = p_data
	registry = p_registry
	battle = p_battle
	branch = p_branch
	options = p_options
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table: Dictionary = RPGFormBuilder.BATTLE_CONDITION_FIELDS if battle else RPGFormBuilder.CONDITION_FIELDS
	for k in table.keys():
		if branch or not RPGFormBuilder.BRANCH_ONLY_CONDITIONS.has(k):
			_kinds.append(k)
	# Kinds the project's enabled extensions declare (manifest "conditions").
	_ext_kinds = registry.condition_kinds() if registry != null else {}
	for k in _ext_kinds:
		var d: Dictionary = _ext_kinds[k]
		if (not battle or bool(d.get("battle", false))) and (branch or not bool(d.get("branch_only", false))) and not _kinds.has(k):
			_kinds.append(k)
	_offered = _kinds.duplicate()
	_kind_opt = OptionButton.new()
	for k in _kinds:
		var lbl: String = KIND_LABELS.get(k, str(k).capitalize())
		if _ext_kinds.has(k):
			lbl = str(_ext_kinds[k].get("label", lbl))
		_kind_opt.add_item(lbl)
	_kind_opt.item_selected.connect(_on_kind)
	add_child(_kind_opt)


## Condition kinds this editor offers (tests).
func kinds() -> Array:
	return _offered.duplicate()


func _fields_for(kind: String) -> Array:
	var table: Dictionary = RPGFormBuilder.BATTLE_CONDITION_FIELDS if battle else RPGFormBuilder.CONDITION_FIELDS
	if table.has(kind) and _offered.has(kind):
		return table[kind]
	if _ext_kinds.has(kind) and _offered.has(kind) and not (_ext_kinds[kind].get("fields", []) as Array).is_empty():
		return _ext_kinds[kind].fields
	return [{"key": "_json", "kind": "json", "label": "Condition (JSON)"}]


func _build(kind: String) -> void:
	if _form:
		_form.queue_free()
	_form = RPGFormBuilder.new()
	var opts := options.duplicate()
	opts["battle_conditions"] = battle
	_form.setup(_fields_for(kind), data, registry, opts)
	_form.value_changed.connect(_on_form_changed)
	_form.pick_location_requested.connect(func(cb, cur): pick_location_requested.emit(cb, cur))
	add_child(_form)


func set_value(v: Variant) -> void:
	_value = v.duplicate(true) if v is Dictionary else {"kind": _kinds[0]}
	var kind := str(_value.get("kind", ""))
	var i := _kinds.find(kind)
	if i == -1:
		_kind_opt.add_item("⚠ %s" % kind)
		_kinds.append(kind)
		i = _kinds.size() - 1
	_kind_opt.select(i)
	_build(kind)
	if _fields_for(kind)[0].key == "_json":
		_form.set_value({"_json": _value})
	else:
		_form.set_value(_value)


func get_value() -> Variant:
	return _value.duplicate(true) if _value is Dictionary else _value


## The kind's form (tests and hosts).
func form() -> RPGFormBuilder:
	return _form


func _on_kind(i: int) -> void:
	var kind: String = _kinds[i]
	var v := {"kind": kind}
	for f in _fields_for(kind):
		if f.has("default") and f.key != "_json":
			v[f.key] = RPGJson.deep_copy(f.default)
	_value = v
	_build(kind)
	_form.set_value(_value)
	value_changed.emit(get_value())


func _on_form_changed(_key: String, _v: Variant) -> void:
	var out: Dictionary = _form.get_value()
	if out.has("_json"):
		if out._json is Dictionary:
			_value = out._json
	else:
		# Fields hidden by the current choice (e.g. an actor check's other targets) are left out.
		for f in _fields_for(str(out.get("kind", ""))):
			if f.has("show_if") and not RPGCommand._visible(f, out):
				out.erase(f.key)
		_value = out
	value_changed.emit(get_value())
