@tool
class_name RPGRouteEditor
extends VBoxContainer
## Move route editor: a list of steps built with buttons, with reorder and delete.
## Step shapes follow RPGCharacter.run_route():
##   {step: dir|forward|backward|random|toward_player|away_from_player|down_left...}
##   {turn: dir|left_90|right_90|around|random|toward_player|away_from_player}, {jump: [dx, dy]},
##   {wait: seconds}, {speed: n}, {frequency: n}, {graphic: {...}}, {opacity: 0-255},
##   {switch: id, value}, {sound: {...}}, {walk_anim|step_anim|direction_fix|through|hide: bool}
## Value: an Array of steps, or (when `with_options`) {steps, repeat, skip_if_blocked}; unknown
## keys of the route object and unknown steps are kept.

signal value_changed(value: Variant)
## Asks the map editor to preview the route (the map editor connects this when it can).
signal preview_requested(route: Variant)

const BUTTONS := [
	["Move", [["↓ Down", {"step": "down"}], ["← Left", {"step": "left"}], ["→ Right", {"step": "right"}], ["↑ Up", {"step": "up"}],
		["↙ Down-left", {"step": "down_left"}], ["↘ Down-right", {"step": "down_right"}], ["↖ Up-left", {"step": "up_left"}], ["↗ Up-right", {"step": "up_right"}],
		["Forward", {"step": "forward"}], ["Backward", {"step": "backward"}], ["Random", {"step": "random"}],
		["Toward player", {"step": "toward_player"}], ["Away from player", {"step": "away_from_player"}]]],
	["Turn", [["Down", {"turn": "down"}], ["Left", {"turn": "left"}], ["Right", {"turn": "right"}], ["Up", {"turn": "up"}],
		["90° left", {"turn": "left_90"}], ["90° right", {"turn": "right_90"}], ["Around", {"turn": "around"}], ["Random", {"turn": "random"}],
		["Toward player", {"turn": "toward_player"}], ["Away from player", {"turn": "away_from_player"}]]],
	["Other", [["Jump…", {"jump": [0, 0]}], ["Wait…", {"wait": 0.5}], ["Speed…", {"speed": 4}], ["Frequency…", {"frequency": 3}],
		["Graphic…", {"graphic": {"sheet": "", "index": 0}}], ["Opacity…", {"opacity": 255}],
		["Switch ON…", {"switch": "", "value": true}], ["Switch OFF…", {"switch": "", "value": false}], ["Sound…", {"sound": {"file": "", "volume": 100, "pitch": 100, "pan": 0}}],
		["Walk anim ON", {"walk_anim": true}], ["Walk anim OFF", {"walk_anim": false}],
		["Step anim ON", {"step_anim": true}], ["Step anim OFF", {"step_anim": false}],
		["Dir. fix ON", {"direction_fix": true}], ["Dir. fix OFF", {"direction_fix": false}],
		["Through ON", {"through": true}], ["Through OFF", {"through": false}],
		["Hide", {"hide": true}], ["Show", {"hide": false}]]],
]
## Steps whose value needs a small form when added or edited.
const STEP_FIELDS := {
	"jump": [{"key": "jump", "kind": "operand_pair_int", "label": "Offset [dx, dy]"}],
	"wait": [{"key": "wait", "kind": "float", "min": 0.0, "max": 60.0, "label": "Seconds"}],
	"speed": [{"key": "speed", "kind": "int", "min": 1, "max": 6, "label": "Speed"}],
	"frequency": [{"key": "frequency", "kind": "int", "min": 1, "max": 5, "label": "Frequency"}],
	"graphic": [{"key": "graphic", "kind": "graphic", "label": "Graphic"}],
	"opacity": [{"key": "opacity", "kind": "int", "min": 0, "max": 255, "label": "Opacity"}],
	"switch": [{"key": "switch", "kind": "ref", "ref": "switch", "label": "Switch"}, {"key": "value", "kind": "bool", "label": "ON"}],
	"sound": [{"key": "sound", "kind": "sound", "res": "sound", "label": "Sound"}],
}

var data: RPGProjectData
var with_options := false
var _route: Dictionary = {}
var _steps: Array = []
var _list: ItemList
var _repeat: CheckBox
var _skip: CheckBox
var _options_box: HBoxContainer


func _init(p_data: RPGProjectData = null, p_with_options := false) -> void:
	data = p_data
	with_options = p_with_options
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hb)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(left)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(220, 160)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.item_activated.connect(_edit_step)
	left.add_child(_list)
	var tools := HBoxContainer.new()
	left.add_child(tools)
	for spec in [["▲", _move.bind(-1), "Move up"], ["▼", _move.bind(1), "Move down"], ["Edit", func(): _edit_selected(), "Edit step"], ["✕", _remove, "Delete step"], ["Preview", func(): preview_requested.emit(get_value()), "Play the route on the map"]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.pressed.connect(spec[1])
		tools.add_child(b)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(260, 160)
	hb.add_child(tabs)
	for group in BUTTONS:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.name = group[0]
		for b in group[1]:
			var btn := Button.new()
			btn.text = b[0]
			btn.pressed.connect(_add_step.bind(b[1]))
			grid.add_child(btn)
		var sc := ScrollContainer.new()
		sc.name = group[0]
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(grid)
		tabs.add_child(sc)
	_options_box = HBoxContainer.new()
	_repeat = CheckBox.new()
	_repeat.text = "Repeat"
	_repeat.toggled.connect(func(on): _route["repeat"] = on; _emit())
	_skip = CheckBox.new()
	_skip.text = "Skip if blocked"
	_skip.toggled.connect(func(on): _route["skip_if_blocked"] = on; _emit())
	_options_box.add_child(_repeat)
	_options_box.add_child(_skip)
	_options_box.visible = with_options
	add_child(_options_box)


func set_value(v: Variant) -> void:
	if v is Dictionary or (with_options and not (v is Array)):
		with_options = true
		_route = v.duplicate(true) if v is Dictionary else {}
		_steps = _route.get("steps", []) if _route.get("steps") is Array else []
		_route["steps"] = _steps
	else:
		_route = {}
		_steps = (v as Array).duplicate(true) if v is Array else []
	_options_box.visible = with_options
	_repeat.set_pressed_no_signal(bool(_route.get("repeat", true)))
	_skip.set_pressed_no_signal(bool(_route.get("skip_if_blocked", false)))
	_rebuild()


func get_value() -> Variant:
	if with_options:
		var r := _route.duplicate(true)
		r["steps"] = _steps.duplicate(true)
		return r
	return _steps.duplicate(true)


static func describe(s: Variant) -> String:
	if not (s is Dictionary):
		return "? %s" % str(s)
	if s.has("step"):
		return "Move %s" % str(s.step).replace("_", " ")
	if s.has("turn"):
		return "Turn %s" % str(s.turn).replace("_", " ")
	if s.has("jump"):
		return "Jump %s" % str(s.jump)
	if s.has("wait"):
		return "Wait %s s" % str(s.wait)
	if s.has("speed"):
		return "Speed %s" % str(s.speed)
	if s.has("frequency"):
		return "Frequency %s" % str(s.frequency)
	if s.has("graphic"):
		var g: Variant = s.graphic
		return "Graphic %s" % (("%s #%s" % [g.get("sheet", ""), g.get("index", 0)]) if g is Dictionary else "none")
	if s.has("opacity"):
		return "Opacity %s" % str(s.opacity)
	if s.has("switch"):
		return "Switch [%s] %s" % [s.switch, "ON" if s.get("value", true) else "OFF"]
	if s.has("sound"):
		var snd: Variant = s.sound
		return "Sound %s" % (snd.get("file", snd.get("role", "")) if snd is Dictionary else str(snd))
	for k in ["walk_anim", "step_anim", "direction_fix", "through"]:
		if s.has(k):
			return "%s %s" % [k.replace("_", " ").capitalize(), "ON" if s[k] else "OFF"]
	if s.has("hide"):
		return "Hide" if s.hide else "Show"
	return "? %s" % JSON.stringify(s)


func _rebuild() -> void:
	var sel := _list.get_selected_items()
	_list.clear()
	for s in _steps:
		_list.add_item("◇ " + describe(s))
	if not sel.is_empty() and sel[0] < _list.item_count:
		_list.select(sel[0])


func _emit() -> void:
	value_changed.emit(get_value())


func _insert_at() -> int:
	var sel := _list.get_selected_items()
	return sel[0] + 1 if not sel.is_empty() else _steps.size()


func _add_step(step: Dictionary) -> void:
	var s := step.duplicate(true)
	var at := _insert_at()
	_steps.insert(at, s)
	_rebuild()
	_list.select(at)
	_emit()
	var key: String = s.keys()[0]
	if STEP_FIELDS.has(key):
		_edit_step(at)


func _edit_selected() -> void:
	var sel := _list.get_selected_items()
	if not sel.is_empty():
		_edit_step(sel[0])


func _edit_step(i: int) -> void:
	if i < 0 or i >= _steps.size() or not (_steps[i] is Dictionary):
		return
	var s: Dictionary = _steps[i]
	var key := ""
	for k in STEP_FIELDS:
		if s.has(k):
			key = k
	if key == "":
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Route step"
	var fields: Array = STEP_FIELDS[key].duplicate(true)
	if key == "jump":
		fields = [{"key": "dx", "kind": "int", "min": -20, "max": 20, "label": "dx"}, {"key": "dy", "kind": "int", "min": -20, "max": 20, "label": "dy"}]
	var form := RPGFormBuilder.new()
	form.setup(fields, data, null)
	var v := s.duplicate(true)
	if key == "jump":
		var j: Array = s.jump if s.jump is Array and s.jump.size() == 2 else [0, 0]
		v = {"dx": j[0], "dy": j[1]}
	form.set_value(v)
	dlg.add_child(form)
	dlg.confirmed.connect(func():
		var out: Dictionary = form.get_value()
		if key == "jump":
			_steps[i] = {"jump": [int(out.get("dx", 0)), int(out.get("dy", 0))]}
		else:
			_steps[i] = out
		_rebuild()
		_emit()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(380, 160))


func _move(dir: int) -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var i: int = sel[0]
	var j := i + dir
	if j < 0 or j >= _steps.size():
		return
	var t: Variant = _steps[i]
	_steps[i] = _steps[j]
	_steps[j] = t
	_rebuild()
	_list.select(j)
	_emit()


func _remove() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	_steps.remove_at(sel[0])
	_rebuild()
	_emit()
