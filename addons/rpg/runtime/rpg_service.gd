extends Node
## The `RPG` autoload: one global entry point for the runtime.
## Typed access to switches, variables, self switches, self variables, the party and inventory; common events;
## saving through the save service. All state changes go through methods that check values and
## emit change signals. Tests can create extra instances and call boot() with a fixture folder.

signal switch_changed(id: String, value: bool)
signal variable_changed(id: String, value: Variant)
signal self_switch_changed(key: String, value: bool)
signal self_variable_changed(key: String, value: Variant)
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
## The game is about to end in a Game Over, before the screen (hooked common events ran already).
signal game_over_started()
## A state was added to or removed from an actor, wherever it happened (a map command, an item
## or skill effect, the battle rules). `battler` is the RPGBattler (or fallback Dictionary).
signal actor_state_changed(battler: Variant, state_id: String, added: bool)
## The player boarded or got off a vehicle (`kind`: boat, ship or airship).
signal vehicle_entered(kind: String)
signal vehicle_exited(kind: String)

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

# --- engine-moment hooks (common events) --------------------------------------------------------
## Common event triggers that run on engine moments instead of polling: the editor's Trigger
## dropdown offers these below none/autorun/parallel (the hooks of YEP Utility Common Events,
## Galv Auto Common Events and friends, built in). A trigger may also be an Array of hook names
## to run one common event on several moments.
const HOOK_TRIGGERS := [
	"on_new_game", "on_load", "on_map_enter", "on_map_leave", "on_step", "on_region_enter",
	"on_region_leave", "on_terrain_enter", "on_level_up", "on_state_added", "on_state_removed",
	"on_actor_ko", "on_battle_start", "on_battle_end", "on_game_over", "on_menu_open",
	"on_menu_close", "on_party_change", "on_vehicle_enter", "on_vehicle_exit",
]
## Steps counted towards each "every N steps" common event (id -> steps since it last fired).
var _hook_steps: Dictionary = {}
## Region and terrain the player is standing in, for the enter/leave moments (-1: not on a map).
var _hook_region := -1
var _hook_terrain := -1

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
	state.self_variable_changed.connect(func(k, v): self_variable_changed.emit(k, v))
	state.changed.connect(request_refresh)
	state.actor_changed.connect(check_levels)
	state.party_changed.connect(check_levels)
	_connect_moment_hooks()
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
	if rules != null and "rpg" in rules:
		rules.rpg = self


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


func get_self_variable(map_id: String, event_id: String, name: String) -> Variant:
	return state.get_self_variable(map_id, event_id, name)


func set_self_variable(map_id: String, event_id: String, name: String, value: Variant) -> bool:
	return state.set_self_variable(map_id, event_id, name, value)


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


# --- engine-moment hooks (issue #52) -------------------------------------------------------------

## Connects the engine's moment signals to the common event hooks. Each handler feeds
## trigger_hook(), which queues the matching common events on the main interpreter.
func _connect_moment_hooks() -> void:
	new_game_started.connect(func(): trigger_hook("on_new_game"))
	game_loaded.connect(func(): trigger_hook("on_load"))
	map_entered.connect(_on_hook_map_entered)
	map_left.connect(_on_hook_map_left)
	player_stepped.connect(_on_hook_player_stepped)
	menu_opened.connect(func(_menu): trigger_hook("on_menu_open"))
	menu_closed.connect(func(): trigger_hook("on_menu_close"))
	actor_levelled.connect(_on_hook_actor_levelled)
	actor_state_changed.connect(_on_hook_actor_state_changed)
	state.party_changed.connect(func(): trigger_hook("on_party_change"))
	vehicle_entered.connect(func(kind): trigger_hook("on_vehicle_enter", {"vehicle": kind, "map": _hook_map_now()}))
	vehicle_exited.connect(func(kind): trigger_hook("on_vehicle_exit", {"vehicle": kind, "map": _hook_map_now()}))


## The map the moment happened on ("" off the maps).
func _hook_map_now() -> String:
	var m := current_map()
	return str(m.map_id) if m != null and "map_id" in m else ""


func _on_hook_map_entered(map_id: String) -> void:
	# Seed the region/terrain trackers with where the player stands, so the first step does not
	# falsely "enter" the region they are already in.
	var m := current_map()
	if m != null and game != null and is_instance_valid(game) and game.player != null and m.has_method("region_at"):
		_hook_region = int(m.region_at(game.player.cell))
		_hook_terrain = int(m.terrain_at(game.player.cell))
	else:
		_hook_region = -1
		_hook_terrain = -1
	_hook_steps.clear()
	trigger_hook("on_map_enter", {"map": map_id})


func _on_hook_map_left(map_id: String) -> void:
	# Leaving a map is covered by on_map_leave; the region trackers just reset.
	_hook_region = -1
	_hook_terrain = -1
	trigger_hook("on_map_leave", {"map": map_id})


func _on_hook_player_stepped(cell: Vector2i, region: int, terrain: int) -> void:
	var map_id := _hook_map_now()
	if region != _hook_region:
		# Region 0 is "no region": stepping out of a real one fires on_region_leave for the old
		# one, stepping into a real one fires on_region_enter.
		if _hook_region > 0:
			trigger_hook("on_region_leave", {"region": _hook_region, "map": map_id, "x": cell.x, "y": cell.y})
		if region > 0:
			trigger_hook("on_region_enter", {"region": region, "map": map_id, "x": cell.x, "y": cell.y})
		_hook_region = region
	if terrain != _hook_terrain:
		if terrain > 0:
			trigger_hook("on_terrain_enter", {"terrain": terrain, "map": map_id, "x": cell.x, "y": cell.y})
		_hook_terrain = terrain
	trigger_hook("on_step", {"map": map_id, "region": region, "terrain": terrain, "x": cell.x, "y": cell.y})


func _on_hook_actor_levelled(actor_id: String, old_level: int, new_level: int) -> void:
	if new_level > old_level:
		trigger_hook("on_level_up", {"actor": actor_id, "old_level": old_level, "new_level": new_level, "map": _hook_map_now()})


func _on_hook_actor_state_changed(battler: Variant, state_id: String, added: bool) -> void:
	var actor_id := ""
	var is_actor := true
	var death := "knockout"
	if battler is Object:
		if "kind" in battler:
			is_actor = str(battler.kind) == "actor"
		if "id" in battler:
			actor_id = str(battler.id)
		if "death_state" in battler:
			death = str(battler.death_state)
	elif battler is Dictionary:
		actor_id = str(battler.get("id", ""))
		is_actor = str(battler.get("kind", "actor")) == "actor"
	if not is_actor:
		return
	var info := {"actor": actor_id, "state": state_id, "map": _hook_map_now()}
	# Knockout is its own moment, and it fires first: the state-added hook of the death state
	# then still tells the whole story.
	if added and state_id == death:
		trigger_hook("on_actor_ko", info)
	trigger_hook("on_state_added" if added else "on_state_removed", info)


## Queues every common event whose trigger names `hook` (and whose switch condition and filters
## match) on the main interpreter. The events queue in common_events.json order and never
## overwrite each other; the moment's data is readable in the event through game data "hook.*".
func trigger_hook(hook: String, info: Dictionary = {}) -> void:
	if data == null or data.common_events.is_empty():
		return
	for id in data.common_events:
		var ce: Dictionary = data.common_events[id]
		if not _ce_hooks(ce).has(hook) or not _common_active(ce) or not _hook_filters_match(ce, hook, info):
			continue
		if hook == "on_step":
			# "Every N steps": the counter is per common event, so events with different
			# intervals coexist. The step that reaches N fires the event and resets the count.
			var every := maxi(1, int(ce.get("hook_every", 1)))
			var n := int(_hook_steps.get(id, 0)) + 1
			if n < every:
				_hook_steps[id] = n
				continue
			_hook_steps[id] = 0
		_queue_hook(id, ce, hook, info)


## The moments that cannot wait for the main interpreter to free up (by the time a queued run
## got its turn, the battle would already be over, the Game Over screen already up): each
## matching common event runs to completion, in file order, before this returns. Battle
## Processing and the game-over flow call this.
func run_hook_common_events(hook: String, info: Dictionary = {}) -> void:
	if data == null or data.common_events.is_empty():
		return
	for id in data.common_events:
		var ce: Dictionary = data.common_events[id]
		if not _ce_hooks(ce).has(hook) or not _common_active(ce) or not _hook_filters_match(ce, hook, info):
			continue
		var owner := _hook_owner(id, hook, info)
		var interp := RPGInterpreter.new(self, owner, null)
		var r: RPGResult = await interp.run(ce.get("commands", []))
		if r.is_error():
			report_error(r, owner)


## One matched common event, queued. The key holds the same moment's duplicate at bay (step spam
## queues one run, not one per step) while different moments and events each keep their ticket.
func _queue_hook(id: String, ce: Dictionary, hook: String, info: Dictionary) -> void:
	scheduler.request_main("hook:%s:%s" % [hook, id], ce.get("commands", []), _hook_owner(id, hook, info), null)


func _hook_owner(id: String, hook: String, info: Dictionary) -> Dictionary:
	return {"kind": "common_event", "id": id, "map": "", "event": "", "hook": info.duplicate(true).merged({"name": hook}, true)}


## A common event's hook triggers: `trigger` is one hook name, or an Array of them (a classic
## none/autorun/parallel trigger names no hooks).
func _ce_hooks(ce: Dictionary) -> Array:
	var t: Variant = ce.get("trigger", "none")
	var out: Array = []
	if t is Array:
		for h in t:
			if str(h).begins_with("on_"):
				out.append(str(h))
	elif str(t).begins_with("on_"):
		out.append(str(t))
	return out


## The filter fields of a hooked common event against the moment's data. Blank and 0 filters
## match anything; hook_map applies to every moment that happens on a map.
func _hook_filters_match(ce: Dictionary, hook: String, info: Dictionary) -> bool:
	var only_map := str(ce.get("hook_map", ""))
	if only_map != "" and str(info.get("map", "")) != only_map:
		return false
	match hook:
		"on_region_enter", "on_region_leave":
			var want_region := int(ce.get("hook_region", 0))
			return want_region <= 0 or int(info.get("region", 0)) == want_region
		"on_terrain_enter":
			var want_terrain := int(ce.get("hook_terrain", 0))
			return want_terrain <= 0 or int(info.get("terrain", 0)) == want_terrain
		"on_level_up", "on_actor_ko":
			var want_actor := str(ce.get("hook_actor", ""))
			return want_actor == "" or str(info.get("actor", "")) == want_actor
		"on_state_added", "on_state_removed":
			var want_state := str(ce.get("hook_state", ""))
			if want_state != "" and str(info.get("state", "")) != want_state:
				return false
			var want_actor := str(ce.get("hook_actor", ""))
			return want_actor == "" or str(info.get("actor", "")) == want_actor
		"on_battle_end":
			var want_outcome := str(ce.get("hook_outcome", ""))
			return want_outcome == "" or str(info.get("outcome", "")) == want_outcome
		"on_vehicle_enter", "on_vehicle_exit":
			var want_vehicle := str(ce.get("hook_vehicle", ""))
			return want_vehicle == "" or str(info.get("vehicle", "")) == want_vehicle
	return true


# --- refresh -------------------------------------------------------------------------------------

## Marks pages for re-checking at the next safe point.
func request_refresh() -> void:
	_refresh_pending = true


## True when a page refresh is pending: it runs on the next frame, or before the next command
## that needs it (see RPGInterpreter.execute).
func refresh_pending() -> bool:
	return _refresh_pending


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
		if str(ce.get("trigger", "none")) != "parallel":
			continue
		var key: String = "common:" + str(id)
		var ok := _common_active(ce)
		var task: RPGScheduler.ParallelTask = scheduler.parallels.get(key)
		if ok and task == null and _game_running():
			scheduler.start_parallel(key, ce.get("commands", []), {"kind": "common_event", "id": id, "map": "", "event": ""}, null, func(): return _common_active(ce))
		elif ok and task != null and task.paused:
			# The condition switch came back on: a paused run carries on at its command.
			scheduler.resume_parallel(key)
		elif not ok and task != null:
			# The condition switch went off: the classic rules pause the run in place and resume
			# it when the switch returns; MV-style rules discard it (a later switch-on then starts
			# the event from the top again).
			if _parallel_switch_off() == "pause":
				scheduler.pause_parallel(key)
			else:
				scheduler.stop_parallel(key, "condition switch off")


## What a parallel common event's condition switch going off does to its run, per the rule system
## (RPGRuleSystem.parallel_switch_off): "pause" (RM2000/2003) or "restart" (MV).
func _parallel_switch_off() -> String:
	if rules != null and rules.has_method("parallel_switch_off"):
		return str(rules.parallel_switch_off())
	return "restart"


func _common_active(ce: Dictionary) -> bool:
	var sw: String = ce.get("switch", "")
	return sw == "" or state.get_switch(sw)


func _game_running() -> bool:
	return current_map() != null


## Autoruns: checked in a fixed order (map events in file order, then common events in file
## order — creation order, as in RPG Maker) whenever the main interpreter is idle. An autorun
## repeats while its conditions stay true.
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
	# common_events.json's order is the run order (#73): no sorting, as with map events.
	var ids: Array = data.common_events.keys()
	for id in ids:
		var ce: Dictionary = data.common_events[id]
		if str(ce.get("trigger", "none")) == "autorun" and _common_active(ce):
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
