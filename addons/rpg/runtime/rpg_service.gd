extends Node
## The `RPG` autoload: one global entry point for the runtime.
## Typed access to switches, variables, self switches, the party and inventory; common events;
## saving through the save service. All state changes go through methods that check values and
## emit change signals. Tests can create extra instances and call boot() with a fixture folder.

signal switch_changed(id: String, value: bool)
signal variable_changed(id: String, value: Variant)
signal self_switch_changed(key: String, value: bool)
signal error_reported(message: String, where: Dictionary)
## Emitted by the emit_signal command: (name, args).
signal event_signal(name: String, args: Dictionary)
signal booted()

# --- game lifecycle (extension entry scripts get these as on_<name> calls too) -----------------
## The title screen was shown.
signal title_shown()
## A new game started: the state is fresh, the start map is not loaded yet.
signal new_game_started()
## A save was loaded and applied (after the map is up).
signal game_loaded()
## The player arrived on a map (after a transfer, a new game or a load).
signal map_entered(map_id: String)
## The player left a map (before the next one loads).
signal map_left(map_id: String)
## The player finished a step on foot or in a vehicle.
signal player_stepped(cell: Vector2i, region: int, terrain: int)
## The main menu opened (`menu` is the screen node) or closed.
signal menu_opened(menu: Node)
signal menu_closed()
## Battle Processing starts a battle (`args`: troop, can_escape, can_lose, background) and gets
## its result ({outcome: win|escape|lose, rewards} or the scene's own value; outcome "" when the
## battle was cancelled).
signal battle_started(args: Dictionary)
signal battle_ended(outcome: String, result: Variant)
## An actor's level went up or down (checked when an actor changes and after a battle).
signal actor_levelled(actor_id: String, old_level: int, new_level: int)
## The game is about to quit.
signal quitting()
## An option row changed on the options screen ("music", or "<extension>.<key>").
signal option_changed(key: String, value: Variant)
## Message box: a message opened (its params), a character appeared (`instant` when shown by
## skipping), the message closed.
signal message_opened(params: Dictionary)
signal message_char(character: String, index: int, instant: bool)
signal message_closed()
## An autosave was attempted (RPGSaveService.autosave).
signal autosaved(slot: int, ok: bool, reason: String)

# --- battle hooks (battle_hook(); entry scripts get on_<name>, see docs/ARCHITECTURE.md) -------
## The default battle scene is built and about to start (`scene`: per-battler nodes, popups).
signal battle_scene_ready(scene: Node)
## A battler's action comes up (RPGBattleCore), each extra action too.
signal turn_started(battler: Object)
## An action is about to run on `targets` (entry scripts may change or cancel it).
signal action_chosen(user: Object, action: Dictionary, targets: Array)
## A damage roll (entry scripts may change the value).
signal damage_calculated(user: Object, target: Object, action: Dictionary, value: int)
## A state was added to or removed from a battler during a battle.
signal state_changed(battler: Object, state_id: String, added: bool)
## A battler was knocked out.
signal battler_defeated(battler: Object)
## A battle was won; `rewards` ({exp, gold, items}) is applied after this (it may be changed).
signal victory(rewards: Dictionary)

const RULES_SCRIPT := "res://addons/rpg/runtime/rules/rpg_rule_system.gd"
const RANDOM_SCRIPT := "res://addons/rpg/core/rpg_random.gd"
const BATTLER_SCRIPT := "res://addons/rpg/runtime/rpg_battler.gd"
const UI_SCREEN := preload("res://addons/rpg/runtime/ui/rpg_ui_screen.gd")

var data: RPGProjectData
var state: RPGGameState
var registry: RPGCommandRegistry
var scheduler: RPGScheduler
## RPGRuleSystem (loaded by path so the runtime still boots without it)
var rules: RefCounted = null
## RPGRandom
var rng: RefCounted = null
var screen: Node
var audio: Node
var ui: Node
var saves: RefCounted
## The running game root (RPGGame) when there is one.
var game: Node = null
## RPGBattleFacade while a battle runs (null otherwise): the public battle API. The battle
## scene assigns and clears it; see addons/rpg/runtime/battle/rpg_battle_facade.gd.
var battle: RPGBattleFacade = null
## Map used when no game root exists (tests).
var test_map: Node = null
## True in playtest/debug builds: errors pause and show where they happened.
var playtest := OS.is_debug_build()
## Debug: walk through walls while Ctrl is held.
var debug_through_enabled := OS.is_debug_build()
var is_booted := false
## Set false before adding to the tree to boot manually (tests).
var auto_boot := true
var last_error := ""
var extension_policies: Dictionary = {}
## Runs the enabled extensions' entry scripts, settings, menu and option entries, save sections
## and condition kinds (RPGExtensionHost).
var extensions: Node = null
## Message text codes added by extensions (register_text_code): CODE (upper case) -> Callable.
var text_codes: Dictionary = {}
## Message tags added by extensions (register_text_tag): "name" or "/name" -> Callable.
var text_tags: Dictionary = {}
## Callables(text: String, info: Dictionary) -> String run on message text before the codes.
var text_preprocessors: Array[Callable] = []
## Last level seen per actor (actor_levelled).
var _levels: Dictionary = {}

var _refresh_pending := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_register_input()
	if auto_boot and not is_booted and DirAccess.dir_exists_absolute("res://rpg"):
		boot("res://rpg")


func boot(root := "res://rpg") -> void:
	data = RPGProjectData.open(root)
	RPGIcons.use_project(data)
	for e in data.load_errors:
		push_error("RPG data: %s: %s" % [e.file, e.message])
	if ResourceLoader.exists(RANDOM_SCRIPT):
		rng = load(RANDOM_SCRIPT).new()  # seeds itself randomly; tests set rng.seed
	state = RPGGameState.new(data)
	state.rng = rng
	_load_rules()
	state.rules = rules
	registry = RPGCommandRegistry.new()
	var ext_root: String = data.project.get("extensions_root", "res://extensions")
	registry.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), ext_root)
	for p in registry.problems:
		push_warning("RPG extensions: %s: %s" % [p.file, p.message])
	for ext_id in registry.extensions:
		extension_policies[ext_id] = registry.extensions[ext_id].get("error_policy", "fail_event")
	if scheduler == null:
		scheduler = RPGScheduler.new(self)
		add_child(scheduler)
	if screen == null:
		screen = load("res://addons/rpg/runtime/rpg_screen.gd").new()
		add_child(screen)
	if audio == null:
		audio = load("res://addons/rpg/runtime/rpg_audio.gd").new()
		add_child(audio)
	if ui == null:
		ui = load("res://addons/rpg/runtime/ui/rpg_ui.gd").new()
		add_child(ui)
	saves = load("res://addons/rpg/runtime/rpg_save_service.gd").new(self)
	state.switch_changed.connect(func(id, v): switch_changed.emit(id, v))
	state.variable_changed.connect(func(id, v): variable_changed.emit(id, v))
	state.self_switch_changed.connect(func(k, v): self_switch_changed.emit(k, v))
	state.changed.connect(request_refresh)
	state.actor_changed.connect(check_levels)
	state.party_changed.connect(check_levels)
	state.new_game()
	_start_extensions()
	reset_level_tracking()
	is_booted = true
	booted.emit()


func _start_extensions(settings: Dictionary = {}) -> void:
	text_codes.clear()
	text_tags.clear()
	text_preprocessors.clear()
	if extensions != null and is_instance_valid(extensions):
		extensions.stop()
		remove_child(extensions)
		extensions.queue_free()
	extensions = load("res://addons/rpg/runtime/rpg_extension_host.gd").new(self)
	add_child(extensions)
	extensions.start(settings)


## Loads the extension list again from data.project (tests and tools turn plugins on this way)
## and restarts every entry script. `settings` (ext id -> {key: value}) replaces the project's
## saved settings of those extensions for this run.
func reload_extensions(settings: Dictionary = {}) -> void:
	var ext_root: String = data.project.get("extensions_root", "res://extensions")
	registry.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), ext_root)
	for p in registry.problems:
		push_warning("RPG extensions: %s: %s" % [p.file, p.message])
	for ext_id in registry.extensions:
		extension_policies[ext_id] = registry.extensions[ext_id].get("error_policy", "fail_event")
	_start_extensions(settings)


# --- extension API (see docs/ARCHITECTURE.md "Extension hooks") --------------------------------

## A setting of an extension (Tools > Extensions, saved in rpg/extensions.json); the manifest's
## default when the project never set it.
func extension_setting(ext_id: String, key: String, fallback: Variant = null) -> Variant:
	return extensions.setting(ext_id, key, fallback) if extensions != null else fallback


## The player's value of an extension option row (options screen, user://rpg_options.json).
func option(ext_id: String, key: String, fallback: Variant = null) -> Variant:
	return extensions.option(ext_id, key, fallback) if extensions != null else fallback


## The entry script instance of an enabled extension (null when it is off), so battle code and
## other extensions can call it: RPG.extension("gab").show_gab("Ouch!").
func extension(ext_id: String) -> Object:
	return extensions.instance(ext_id) if extensions != null else null


## True when an extension is listed and enabled in this project.
func extension_enabled(ext_id: String) -> bool:
	return registry != null and registry.is_enabled(ext_id)


## A node layer over the map. "map": in map coordinates above the characters (moves with the
## camera; lights, labels); "screen": fixed to the screen under the menus and messages;
## "hud": fixed to the screen above menus, messages and battle, laid out at 320x240 like the UI.
## Nodes added stay across map transfers; remove them in on_map_left when they belong to a map.
func map_overlay_layer(space := "map") -> Node:
	if game != null and is_instance_valid(game) and game.has_method("overlay_layer"):
		return game.overlay_layer(space)
	return null


## Adds `node` as a child of a character so it moves with it: "player", "follower:N" (1-based)
## or an event ID on the current map. Event attachments go with the map. Returns false when the
## character does not exist.
func attach_to_character(char_id: String, node: Node) -> bool:
	if game != null and is_instance_valid(game) and game.has_method("attach_to_character"):
		return game.attach_to_character(char_id, node)
	return false


## Adds a condition kind for page conditions and Conditional Branch (declare its fields in the
## manifest "conditions" so the editor offers it). `check`: Callable(cond, where) -> bool, where
## = {map_id, event_id, ctx, state}.
func register_condition_kind(kind: String, check: Callable) -> void:
	state.condition_kinds[kind] = check


## Adds a message text code: a backslash, NAME, and an optional [arg] (letters or one symbol,
## matched case-insensitively, longest first; built-in letters keep their meaning). `handler`:
## Callable(arg: String, info: Dictionary) returning a String (text inserted, its codes read
## too) or a Dictionary {text?, bbcode?, width?, action?: Callable, wait?: seconds} (RPGText).
func register_text_code(code: String, handler: Callable) -> void:
	text_codes[code.to_upper()] = handler


## Adds a message tag <name>, <name:arg> or </name> (register "/name" for the closing tag).
## Same handler contract as register_text_code.
func register_text_tag(tag_name: String, handler: Callable) -> void:
	text_tags[tag_name.to_lower()] = handler


## Adds a pass over message text before its codes are read (macros, keyword colouring).
## `fn`: Callable(text: String, info: Dictionary) -> String.
func register_text_preprocessor(fn: Callable) -> void:
	text_preprocessors.append(fn)


## A battle hook (RPGBattleCore and the default battle scene call this): each entry script's
## on_<hook>(...args) runs in load order, then the signal `hook` (when the service has one) is
## emitted with the final arguments. `mode`: "" notify only; "value": a handler's non-null return
## replaces the last argument for the next handler; "action": a handler may return {action?,
## targets?, cancel?} (action_chosen). Returns {args, cancel}.
func battle_hook(hook: String, args: Array, mode := "") -> Dictionary:
	var out := {"args": args, "cancel": false}
	if extensions != null and is_instance_valid(extensions) and extensions.has_method("run_hook"):
		out = extensions.run_hook("on_" + hook, args, mode)
	if has_signal(hook):
		callv("emit_signal", [hook] + (out.args as Array))
	return out


## Emits actor_levelled for every actor whose level differs from the last check. Runs when an
## actor or the party changes and after battles; cheap when nothing changed.
func check_levels(_id: Variant = null) -> void:
	if state == null:
		return
	var now := _current_levels()
	for id in now:
		var old := int(_levels.get(id, now[id]))
		_levels[id] = now[id]
		if old != int(now[id]):
			actor_levelled.emit(str(id), old, int(now[id]))


func _current_levels() -> Dictionary:
	var out := {}
	if state == null:
		return out
	for id in state.actors:
		var b: Variant = state.actors[id]
		if b is Object and "level" in b:
			out[str(id)] = int(b.level)
		elif b is Dictionary:
			out[str(id)] = int(b.get("level", 1))
	return out


## Forgets the levels seen so far (a new game or a load is not a level change).
func reset_level_tracking() -> void:
	_levels = _current_levels()


func _load_rules() -> void:
	rules = null
	if not ResourceLoader.exists(RULES_SCRIPT):
		return
	var rs: Script = load(RULES_SCRIPT)
	var rules_name: String = data.project.get("rules", "classic")
	if rs.has_method("load_rules"):
		rules = rs.load_rules(rules_name, data)
	if rules != null and rng != null and "rng" in rules:
		rules.rng = rng


func battler_script() -> Script:
	return load(BATTLER_SCRIPT) if ResourceLoader.exists(BATTLER_SCRIPT) else null


func current_map() -> Node:
	if game != null and is_instance_valid(game) and "map" in game:
		return game.map
	return test_map


# --- state API (spec: Extending with Godot, State API) ------------------------------------

func get_switch(id: String) -> bool:
	return state.get_switch(id)


func set_switch(id: String, value: bool) -> bool:
	return state.set_switch(id, value)


func get_variable(id: String) -> Variant:
	return state.get_variable(id)


func set_variable(id: String, value: Variant) -> bool:
	return state.set_variable(id, value)


func get_self_switch(map_id: String, event_id: String, letter: String) -> bool:
	return state.get_self_switch(map_id, event_id, letter)


func set_self_switch(map_id: String, event_id: String, letter: String, value: bool) -> bool:
	return state.set_self_switch(map_id, event_id, letter, value)


## Runs a common event. mode "main" joins the main queue (one main event at a time);
## mode "parallel" runs it as its own task. Returns the RPGResult when it finishes.
func run_common_event(id: String, mode := "main") -> RPGResult:
	var ce: Dictionary = data.common_events.get(id, {})
	if ce.is_empty():
		return RPGResult.error("Unknown common event '%s'." % id)
	var owner := {"kind": "common_event", "id": id, "map": "", "event": ""}
	if mode == "parallel":
		var interp := RPGInterpreter.new(self, owner, null)
		var r: RPGResult = await interp.run(ce.get("commands", []))
		if r.is_error():
			report_error(r, owner)
		return r
	var t: RPGScheduler.Ticket = scheduler.request_main("api:" + id + ":" + str(Time.get_ticks_usec()), ce.get("commands", []), owner, null)
	return await t.wait()


## Runs an arbitrary command list on the main interpreter (used by tests, battle test, event test).
func run_commands(commands: Array, owner: Dictionary = {"kind": "api"}, event: Node = null) -> RPGResult:
	var t: RPGScheduler.Ticket = scheduler.request_main("", commands, owner, event)
	return await t.wait()


# --- refresh -------------------------------------------------------------------------------------

## Marks pages for re-checking at the next safe point.
func request_refresh() -> void:
	_refresh_pending = true


## Called by the scheduler once per frame before it starts new work.
func process_refresh() -> void:
	if not _refresh_pending:
		_check_autoruns()
		return
	_refresh_pending = false
	var m := current_map()
	if m != null and m.has_method("refresh_pages"):
		m.refresh_pages()
	_refresh_common_events()
	_check_autoruns()


func _refresh_common_events() -> void:
	for id in data.common_events:
		var ce: Dictionary = data.common_events[id]
		if ce.get("trigger", "none") != "parallel":
			continue
		var key: String = "common:" + str(id)
		var ok := _common_active(ce)
		if ok and not scheduler.parallels.has(key) and _game_running():
			scheduler.start_parallel(key, ce.get("commands", []), {"kind": "common_event", "id": id, "map": "", "event": ""}, null, func(): return _common_active(ce))
		elif not ok and scheduler.parallels.has(key):
			scheduler.stop_parallel(key, "condition switch off")


func _common_active(ce: Dictionary) -> bool:
	var sw: String = ce.get("switch", "")
	return sw == "" or state.get_switch(sw)


func _game_running() -> bool:
	return current_map() != null


## Autoruns: checked in a fixed order (map events by ID, then common events by ID) whenever the
## main interpreter is idle. An autorun repeats while its conditions stay true.
func _check_autoruns() -> void:
	if scheduler.is_main_busy() or not scheduler.input_locks.is_empty():
		return
	var m := current_map()
	if m == null:
		return
	# Common events reserved by an item or skill (Common Event effect) run first, in order.
	var reserved: Array[String] = state.take_reserved_common_events()
	if not reserved.is_empty():
		for id in reserved:
			var ce: Dictionary = data.common_events.get(id, {})
			if ce.is_empty():
				report_error(RPGResult.error("Unknown common event '%s' (from an item or skill effect)." % id), {"kind": "common_event", "id": id})
				continue
			scheduler.request_main("", ce.get("commands", []), {"kind": "common_event", "id": id, "map": "", "event": ""}, null)
		return
	if m.has_method("autorun_candidates"):
		for ev in m.autorun_candidates():
			_note_autorun("%s/%s" % [m.map_id, ev.event_id], "map event '%s' on map '%s'" % [ev.event_id, m.map_id])
			ev.start_autorun()
			return
	var ids: Array = data.common_events.keys()
	ids.sort()
	for id in ids:
		var ce: Dictionary = data.common_events[id]
		if ce.get("trigger", "none") == "autorun" and _common_active(ce):
			_note_autorun("common:" + id, "common event '%s'" % id)
			scheduler.request_main("common:" + id, ce.get("commands", []), {"kind": "common_event", "id": id, "map": "", "event": ""}, null)
			return
	# Nothing to auto-run: the player has control again, so any autorun chain has ended.
	_autorun_last = ""
	_autorun_repeats = 0


## Debug warning (spec: Event execution semantics): an autorun that starts again right after it
## finished, many times in a row, never turns itself off and locks the player out.
const AUTORUN_LOOP_WARN := 30
var _autorun_last := ""
var _autorun_repeats := 0
var _autorun_warned := {}


func _note_autorun(key: String, label: String) -> void:
	if key == _autorun_last:
		_autorun_repeats += 1
	else:
		_autorun_repeats = 0
	_autorun_last = key
	if _autorun_repeats == AUTORUN_LOOP_WARN and not _autorun_warned.has(key):
		_autorun_warned[key] = true
		var msg := "The autorun %s has restarted %d times in a row without stopping. End it by turning a switch or self switch on that its page condition checks, or by Erase event." % [label, AUTORUN_LOOP_WARN]
		push_warning("RPG: " + msg)
		if playtest and ui != null and ui.has_method("show_error"):
			ui.show_error(msg)


# --- errors --------------------------------------------------------------------------------------

func report_error(r: RPGResult, owner: Dictionary = {}) -> void:
	var w := r.where if not r.where.is_empty() else owner
	var where_text := RPGInterpreter.describe_where(w)
	last_error = "%s%s" % [r.message, (" (" + where_text + ")") if where_text != "" else ""]
	push_error("RPG event error: " + last_error)
	error_reported.emit(r.message, w)
	if ui != null and ui.has_method("show_error") and playtest:
		ui.show_error(last_error)
	# Release builds: follow the extension's declared policy.
	if not playtest:
		var ext := ""
		var cmd_type: String = w.get("command", "")
		if registry and registry.providers.has(cmd_type):
			ext = registry.providers[cmd_type]
		if extension_policies.get(ext, "fail_event") == "abort_to_title" and game != null and game.has_method("return_to_title"):
			game.return_to_title()


# --- input ---------------------------------------------------------------------------------------

## Keys per action. rpg_menu (gamepad Start / Y) opens the menu on the map and cancels in menus.
const KEY_MAP := {
	"rpg_up": [KEY_UP, KEY_W, KEY_KP_8],
	"rpg_down": [KEY_DOWN, KEY_S, KEY_KP_2],
	"rpg_left": [KEY_LEFT, KEY_A, KEY_KP_4],
	"rpg_right": [KEY_RIGHT, KEY_D, KEY_KP_6],
	"rpg_ok": [KEY_Z, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER],
	"rpg_cancel": [KEY_X, KEY_ESCAPE, KEY_BACKSPACE, KEY_KP_0],
	"rpg_menu": [],
	"rpg_dash": [KEY_SHIFT],
	"rpg_debug": [KEY_F9],
	"rpg_through": [KEY_CTRL],
	"rpg_overlay": [KEY_F7],
}
## Gamepad buttons per action (MV: A ok, B cancel, X dash, Y menu; Start opens the menu too,
## Back cancels).
const PAD_BUTTONS := {
	"rpg_up": [JOY_BUTTON_DPAD_UP], "rpg_down": [JOY_BUTTON_DPAD_DOWN], "rpg_left": [JOY_BUTTON_DPAD_LEFT],
	"rpg_right": [JOY_BUTTON_DPAD_RIGHT], "rpg_ok": [JOY_BUTTON_A], "rpg_cancel": [JOY_BUTTON_B, JOY_BUTTON_BACK],
	"rpg_dash": [JOY_BUTTON_X], "rpg_menu": [JOY_BUTTON_START, JOY_BUTTON_Y],
}
## Left stick: [axis, direction] per action; read as a direction past STICK_DEADZONE (MV: 0.5).
const PAD_AXES := {
	"rpg_up": [JOY_AXIS_LEFT_Y, -1.0], "rpg_down": [JOY_AXIS_LEFT_Y, 1.0],
	"rpg_left": [JOY_AXIS_LEFT_X, -1.0], "rpg_right": [JOY_AXIS_LEFT_X, 1.0],
}
const STICK_DEADZONE := 0.5

## "keyboard", "pad" or "mouse": the device the player used last (button hints follow it).
var last_device := "keyboard"


## Adds the rpg_* actions. An action the project already defines keeps its own events; it still
## gets the default gamepad buttons and stick unless the project gave it gamepad events itself.
func _register_input() -> void:
	for action in KEY_MAP:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for k in KEY_MAP[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(action, ev)
		if _has_pad_events(action):
			continue
		for b in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
			InputMap.action_set_deadzone(action, STICK_DEADZONE)


static func _has_pad_events(action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return true
	return false


## Mouse and touch input (MV-style): on unless the project setting rpg/input/mouse or the System
## field "mouse_input" turns it off.
func pointer_enabled() -> bool:
	if not bool(ProjectSettings.get_setting("rpg/input/mouse", true)):
		return false
	return data == null or bool(data.system.get("mouse_input", true))


## A short name for the button behind an action ("ok", "cancel", "menu") on the device used last,
## for on-screen hints.
func button_label(action: String) -> String:
	var names: Dictionary = {
		"pad": {"ok": "A", "cancel": "B", "menu": "Start"},
		"mouse": {"ok": "Click", "cancel": "Right-click", "menu": "Right-click"},
	}.get(last_device, {"ok": "Z/Enter", "cancel": "X/Esc", "menu": "X/Esc"})
	return str(names.get(action, action))


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		last_device = "pad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= STICK_DEADZONE:
		last_device = "pad"
	elif event is InputEventKey and event.pressed:
		last_device = "keyboard"
	elif event is InputEventMouseButton and event.pressed:
		last_device = "mouse"
	# Actions held by a mouse button (see RPGUIScreen.inject_action) end with the button.
	if event is InputEventMouseButton and not event.pressed:
		_release_pointer_actions()


func _release_pointer_actions() -> void:
	UI_SCREEN.release_injected()


func _process(_delta: float) -> void:
	UI_SCREEN.release_due()


## Static caches hold streams, textures and TileSets; free them when the game quits so Godot
## reports no leaked instances or resources at exit.
func _exit_tree() -> void:
	if Engine.is_editor_hint() or not _is_autoload():
		return
	release_caches()


func _is_autoload() -> bool:
	return is_inside_tree() and get_parent() == get_tree().root and name == "RPG"


## Stops the sound players and clears the shared asset caches.
func release_caches() -> void:
	if audio != null and audio.has_method("stop_all"):
		audio.stop_all()
		if audio.has_method("release_streams"):
			audio.release_streams()
	RPGAssets.clear_cache()
	RPGMap.clear_tileset_cache()
	RPGProfile.clear_cache()
	RPGCharset.clear_cache()
	RPGIcons.clear_cache()
	RPGFormula._cache.clear()
