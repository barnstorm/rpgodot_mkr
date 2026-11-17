@tool
extends RPGCommand
## Key Input Processing (issue #14): stores the code of a pressed key in a variable, either
## waiting until one lands or reading what is held right now. The codes are RPG Maker 2003's:
## 1-4 the directions, 5 confirm, 6 cancel, 7 shift, 10-19 the digits, 20-24 + - * / ., and the
## kit's own rpg_* actions from 30; actions the author lists by name count from 100.
##
## Everything goes through the input map, so gamepads work the same as keyboards: the digits and
## operators are rpg_* actions too, registered on the number row and the numpad.

## The one-action keys in check order: two accepted keys held in the same frame report the
## earliest entry here (RPG Maker 2003 checks the pad keys after the digits, highest code first;
## the kit's own actions follow). The digit and operator rows are loops, not table entries.
const FIXED_KEYS := [
	{"field": "shift", "action": "rpg_dash", "code": 7},
	{"field": "cancel", "action": "rpg_cancel", "code": 6},
	{"field": "ok", "action": "rpg_ok", "code": 5},
	{"field": "up", "action": "rpg_up", "code": 4},
	{"field": "right", "action": "rpg_right", "code": 3},
	{"field": "left", "action": "rpg_left", "code": 2},
	{"field": "down", "action": "rpg_down", "code": 1},
	{"field": "overlay", "action": "rpg_overlay", "code": 33},
	{"field": "through", "action": "rpg_through", "code": 32},
	{"field": "debug", "action": "rpg_debug", "code": 31},
	{"field": "menu", "action": "rpg_menu", "code": 30},
]


static func descriptor() -> Dictionary:
	return {
		"type": "key_input", "schema_version": 1, "category": "message", "label": "Key Input Processing",
		"fields": [
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Store in", "required": true},
			{"key": "wait", "kind": "bool", "default": true, "label": "Wait until pressed"},
			{"key": "down", "kind": "bool", "default": false, "label": "Down (1)"},
			{"key": "left", "kind": "bool", "default": false, "label": "Left (2)"},
			{"key": "right", "kind": "bool", "default": false, "label": "Right (3)"},
			{"key": "up", "kind": "bool", "default": false, "label": "Up (4)"},
			{"key": "ok", "kind": "bool", "default": false, "label": "Confirm (5)"},
			{"key": "cancel", "kind": "bool", "default": false, "label": "Cancel (6)"},
			{"key": "shift", "kind": "bool", "default": false, "label": "Shift / Dash (7)"},
			{"key": "numbers", "kind": "bool", "default": false, "label": "Number row 0-9 (10-19)"},
			{"key": "operators", "kind": "bool", "default": false, "label": "+ - * / . (20-24)"},
			{"key": "menu", "kind": "bool", "default": false, "label": "Menu (30)"},
			{"key": "debug", "kind": "bool", "default": false, "label": "Debug (31)"},
			{"key": "through", "kind": "bool", "default": false, "label": "Through (32)"},
			{"key": "overlay", "kind": "bool", "default": false, "label": "Overlay (33)"},
			{"key": "time_variable", "kind": "ref", "ref": "variable", "default": "", "label": "Store time in", "show_if": {"key": "wait", "equals": true}},
			{"key": "actions", "kind": "text", "default": "", "label": "Extra actions", "help": "More input-map actions to accept, comma-separated (rpg_* or your own). They store 100, 101, ... in the order listed."},
		],
	}


func summary(args: Dictionary) -> String:
	return "Key Input: [%s] (%s)" % [args.get("variable", "?"), "wait" if bool(args.get("wait", true)) else "now"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var extras := _extra_actions(args)
	var keys := _accepted_keys(args, extras)
	if keys.is_empty():
		return RPGResult.error("Key Input Processing: no keys are accepted.")
	var vid := str(args.variable)
	if not ctx.state.set_variable(vid, 0):
		return RPGResult.error("Key Input Processing: unknown variable '%s'." % vid)
	var wait := bool(args.get("wait", true))
	# What is already down when the command starts does not count while waiting: like RPG
	# Maker 2003's "triggered", the key has to land anew.
	var held := _held(keys)
	var frames := 0
	while true:
		if ctx.is_cancelled():
			return RPGResult.cancelled()
		# Like RPG Maker 2003, the variable reads 0 for the whole wait, not the last code.
		ctx.state.set_variable(vid, 0)
		var now := _held(keys)
		var code := 0
		for k in keys:
			if now.has(k.action) and (not wait or not held.has(k.action)):
				code = int(k.code)
				break
		held = now
		if code != 0 or not wait:
			_finish(ctx, args, vid, code, frames)
			return RPGResult.ok()
		# Frame waits keep the parallel and autorun rules: no time passes while the map is
		# suspended (menu, battle) or the task is paused, and cancelling ends the wait.
		if not await ctx.wait_frames(1):
			return RPGResult.cancelled()
		frames += 1
	return RPGResult.ok()


## The accepted keys in check order: {action, code}, digits 9-0 then the operators . / * - +
## first, as RPG Maker 2003 checks them, then the one-action keys, then the named extras.
func _accepted_keys(args: Dictionary, extras: PackedStringArray) -> Array:
	var out := []
	if args.get("operators", false):
		for k in [["rpg_decimal", 24], ["rpg_divide", 23], ["rpg_multiply", 22], ["rpg_subtract", 21], ["rpg_add", 20]]:
			out.append({"action": str(k[0]), "code": int(k[1])})
	if args.get("numbers", false):
		for d in range(9, -1, -1):
			out.append({"action": "rpg_num%d" % d, "code": 10 + d})
	for k in FIXED_KEYS:
		if args.get(str(k.field), false):
			out.append({"action": str(k.action), "code": int(k.code)})
	for i in extras.size():
		out.append({"action": extras[i], "code": 100 + i})
	return out


## The accepted keys that are down right now, as {action: true}.
func _held(keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		var action := str(k.action)
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			out[action] = true
	return out


func _extra_actions(args: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for a in str(args.get("actions", "")).replace(",", " ").split(" ", false):
		out.append(a)
	return out


func _finish(ctx: RPGContext, args: Dictionary, vid: String, code: int, frames: int) -> void:
	ctx.state.set_variable(vid, code)
	var t := str(args.get("time_variable", ""))
	if t != "":
		# Tenths of a second of engine time, as 2003 records it (the clock is 60 frames to the
		# second). Without waiting there was no wait to measure, so it stores 0.
		ctx.state.set_variable(t, frames * 10 / 60)
