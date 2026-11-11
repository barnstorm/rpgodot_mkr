class_name RPGExtensionHost
extends Node
## Runs the enabled extensions of a game (a child of the RPG service, made at boot):
##   - entry scripts (manifest "entry_scripts"): one instance each, told about the game's
##     lifecycle through on_<event> methods (see RPGExtension);
##   - settings (manifest "settings_schema", values in rpg/extensions.json from Tools > Extensions);
##   - save sections (manifest "save_sections") wired to RPGSaveService.extension_hooks;
##   - main-menu entries (manifest "menu_entries" plus the project.json "menu" block);
##   - option rows (manifest "options" plus entry scripts' option_entries()), kept in the options
##     file under "<extension>.<key>";
##   - condition kinds (manifest "conditions" with a "method" on an entry script);
##   - record types (manifest "database_types"), loaded into RPG.data at start.
## Disabled or unlisted extensions are never loaded.

const SETTINGS_FILE := "extensions.json"
const OPTIONS_SCRIPT := "res://addons/rpg/runtime/ui/options_screen.gd"
## RPG service signal -> entry script method.
const LIFECYCLE := {
	"title_shown": "on_title_shown", "game_loaded": "on_game_loaded",
	"map_entered": "on_map_entered", "map_left": "on_map_left", "player_stepped": "on_player_stepped",
	"menu_opened": "on_menu_opened", "menu_closed": "on_menu_closed",
	"battle_started": "on_battle_started", "battle_ended": "on_battle_ended",
	"actor_levelled": "on_actor_levelled", "quitting": "on_quitting",
	"message_opened": "on_message_opened", "message_char": "on_message_char", "message_closed": "on_message_closed",
	"autosaved": "on_autosaved",
}
## Built-in main-menu commands (RPG Maker order); extension entries go before "options".
const BUILTIN_MENU := ["item", "skill", "equip", "status", "options", "save", "game_end"]

var rpg: Node
## ext id -> [instances] in manifest order.
var instances_by_ext: Dictionary = {}
## Every entry script instance as [ext_id, Object], in load order.
var entries: Array = []
## ext id -> settings saved for this project (missing keys use the manifest default).
var settings: Dictionary = {}
## "<ext>.<key>" -> the player's option value (from the options file).
var option_values: Dictionary = {}
## Save sections the host keeps itself: namespace -> Dictionary.
var sections: Dictionary = {}
## namespace -> {ext, version}
var section_defs: Dictionary = {}
## Problems met while starting (missing scripts...), also pushed as warnings.
var problems: Array = []
## [signal name, Callable] connected to the RPG service, undone by stop().
var _connections: Array = []


func _init(p_rpg: Node = null) -> void:
	rpg = p_rpg
	name = "Extensions"


func registry() -> RPGCommandRegistry:
	return rpg.registry if rpg != null else null


## Loads settings and options, makes the entry scripts, registers save sections and condition
## kinds, and connects the lifecycle signals.
func start(override: Dictionary = {}) -> void:
	var reg := registry()
	if reg == null:
		return
	settings = load_settings_file(rpg.data.root) if rpg.data != null else {}
	# Record types the extensions own (manifest "database_types"): rpg/database/<type>.json.
	if rpg.data != null:
		rpg.data.add_db_types(reg.database_types())
	for ext_id in override:
		settings[ext_id] = override[ext_id].duplicate(true)
	_load_options()
	for ext_id in reg.enabled_ids():
		var m: Dictionary = reg.extensions[ext_id]
		instances_by_ext[ext_id] = []
		for rel in m.get("entry_scripts", []):
			var obj := _make_entry(ext_id, m, str(rel))
			if obj != null:
				instances_by_ext[ext_id].append(obj)
				entries.append([ext_id, obj])
		_register_sections(ext_id, m)
		_register_conditions(ext_id, m)
	for sig in LIFECYCLE:
		if rpg.has_signal(sig):
			_connect(sig, _relay_for(sig, str(LIFECYCLE[sig])))
	_connect("new_game_started", _on_new_game)
	_connect("option_changed", _on_option_changed)
	for e in entries:
		if e[1].has_method("_extension_ready"):
			e[1]._extension_ready()


## Disconnects and frees the entry scripts (before a reload).
func stop() -> void:
	for c in _connections:
		if rpg.is_connected(c[0], c[1]):
			rpg.disconnect(c[0], c[1])
	_connections.clear()
	if rpg.saves != null:
		for ns in section_defs:
			rpg.saves.extension_hooks.erase(ns)
	for e in entries:
		if e[1] is Node and is_instance_valid(e[1]):
			e[1].queue_free()
	entries.clear()
	instances_by_ext.clear()


func _make_entry(ext_id: String, m: Dictionary, rel: String) -> Object:
	var path: String = rel if rel.begins_with("res://") else str(m.get("_dir", "")).path_join(rel)
	if not ResourceLoader.exists(path):
		_problem("Entry script '%s' of extension '%s' is missing." % [path, ext_id])
		return null
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		_problem("Entry script '%s' failed to load (parse error?)." % path)
		return null
	var obj: Object = script.new()
	if "rpg" in obj:
		obj.rpg = rpg
	if "extension_id" in obj:
		obj.extension_id = ext_id
	if "manifest" in obj:
		obj.manifest = m
	if obj is Node:
		obj.name = ext_id.to_pascal_case() + str(entries.size())
		add_child(obj)
	return obj


func _problem(msg: String) -> void:
	problems.append(msg)
	push_warning("RPG extensions: " + msg)


## The first entry script instance of an extension (null when it has none or is off).
func instance(ext_id: String) -> Object:
	var list: Array = instances_by_ext.get(ext_id, [])
	return list[0] if not list.is_empty() else null


func _connect(sig: String, c: Callable) -> void:
	rpg.connect(sig, c)
	_connections.append([sig, c])


## A Callable for `sig` that calls `method` on every entry script with the signal's arguments.
func _relay_for(sig: String, method: String) -> Callable:
	var n := 0
	for s in rpg.get_signal_list():
		if s.name == sig:
			n = s.args.size()
	match n:
		0: return func() -> void: call_all(method, [])
		1: return func(a: Variant) -> void: call_all(method, [a])
		2: return func(a: Variant, b: Variant) -> void: call_all(method, [a, b])
		_: return func(a: Variant, b: Variant, c: Variant) -> void: call_all(method, [a, b, c])


## Calls `method` with `args` on every entry script that has it, in load order.
func call_all(method: String, args: Array = []) -> void:
	for e in entries.duplicate():
		var obj: Object = e[1]
		if is_instance_valid(obj) and obj.has_method(method):
			obj.callv(method, args)


## A battle hook (RPG.battle_hook): calls `method` with `args` on every entry script that has it,
## in load order. `mode` "value": a non-null return replaces the last argument for the next
## script; "action": a Dictionary return may set "action" (args[1]) and "targets" (args[2]), and
## "cancel": true stops there. Returns {args, cancel}.
func run_hook(method: String, args: Array, mode := "") -> Dictionary:
	var out := {"args": args.duplicate(), "cancel": false}
	for e in entries.duplicate():
		var obj: Object = e[1]
		if not is_instance_valid(obj) or not obj.has_method(method):
			continue
		var r: Variant = obj.callv(method, out.args)
		if r == null or mode == "":
			continue
		if mode == "value":
			out.args[-1] = r
		elif mode == "action" and r is Dictionary:
			if r.get("action") is Dictionary:
				out.args[1] = r.action
			if r.get("targets") is Array:
				out.args[2] = r.targets
			if bool(r.get("cancel", false)):
				out.cancel = true
				break
	return out


func _on_new_game() -> void:
	for ns in section_defs:
		_reset_section(ns)
	call_all("on_new_game")


# --- settings ------------------------------------------------------------------------------------

## ext id -> {key: value} from <root>/extensions.json ({} when the file is missing).
static func load_settings_file(root: String) -> Dictionary:
	var d: Variant = RPGJson.load_or(root.path_join(SETTINGS_FILE), {})
	var s: Variant = d.get("settings", {}) if d is Dictionary else {}
	return s if s is Dictionary else {}


## Writes one extension's settings into <root>/extensions.json (other extensions' are kept).
static func save_settings(root: String, ext_id: String, values: Dictionary) -> Error:
	var path := root.path_join(SETTINGS_FILE)
	var d: Variant = RPGJson.load_or(path, {})
	if not (d is Dictionary):
		d = {}
	d["schema_version"] = 1
	var all: Dictionary = d.get("settings", {}) if d.get("settings") is Dictionary else {}
	all[ext_id] = values.duplicate(true)
	d["settings"] = all
	return RPGJson.save_file(path, d)


func setting(ext_id: String, key: String, fallback: Variant = null) -> Variant:
	var s: Variant = settings.get(ext_id, {})
	if s is Dictionary and s.has(key) and s[key] != null:
		return s[key]
	var reg := registry()
	if reg != null and reg.extensions.has(ext_id):
		var defaults := RPGCommandRegistry.settings_defaults(reg.extensions[ext_id])
		if defaults.has(key) and defaults[key] != null:
			return defaults[key]
	return fallback


## Replaces an extension's settings for this run only (tests, previews).
func set_settings(ext_id: String, values: Dictionary) -> void:
	settings[ext_id] = values.duplicate(true)


# --- options ---------------------------------------------------------------------------------------

func _load_options() -> void:
	option_values.clear()
	if not ResourceLoader.exists(OPTIONS_SCRIPT):
		return
	var os: Script = load(OPTIONS_SCRIPT)
	if not os.has_method("load_options"):
		return
	var all: Dictionary = os.load_options()
	for k in all:
		if str(k).contains("."):
			option_values[str(k)] = all[k]


## Option rows of the enabled extensions: [{id: "<ext>.<key>", ext, key, kind: bool|choice|slider,
## label, default, options?, option_labels?, min?, max?, step?, help?}].
func option_rows() -> Array:
	var out := []
	var reg := registry()
	if reg == null:
		return out
	for ext_id in reg.enabled_ids():
		var rows: Array = []
		for o in reg.extensions[ext_id].get("options", []):
			rows.append(o)
		for obj in instances_by_ext.get(ext_id, []):
			if obj.has_method("option_entries"):
				var extra: Variant = obj.option_entries()
				if extra is Array:
					rows.append_array(extra)
		for o in rows:
			if not (o is Dictionary) or str(o.get("key", "")) == "":
				continue
			var row: Dictionary = o.duplicate(true)
			row["ext"] = ext_id
			row["id"] = "%s.%s" % [ext_id, o.key]
			if not row.has("kind"):
				row["kind"] = "bool"
			if str(row.get("show_method", "")) != "":
				var obj2 := instance(ext_id)
				if obj2 != null and obj2.has_method(str(row.show_method)) and not bool(obj2.call(str(row.show_method))):
					continue
			out.append(row)
	return out


func _row(ext_id: String, key: String) -> Dictionary:
	for r in option_rows():
		if r.ext == ext_id and str(r.key) == key:
			return r
	return {}


func option(ext_id: String, key: String, fallback: Variant = null) -> Variant:
	var id := "%s.%s" % [ext_id, key]
	if option_values.has(id):
		return option_values[id]
	var row := _row(ext_id, key)
	if row.has("default"):
		return row.default
	return fallback


## Sets an option row's value (the options screen saves the file itself) and tells the game.
func set_option(id: String, value: Variant) -> void:
	option_values[id] = value
	rpg.option_changed.emit(id, value)


func _on_option_changed(id: String, value: Variant) -> void:
	if not id.contains("."):
		return
	option_values[id] = value
	var ext_id := id.get_slice(".", 0)
	var key := id.substr(ext_id.length() + 1)
	for obj in instances_by_ext.get(ext_id, []):
		if obj.has_method("on_option_changed"):
			obj.on_option_changed(key, value)


# --- save sections ---------------------------------------------------------------------------------

func _register_sections(ext_id: String, m: Dictionary) -> void:
	if rpg.saves == null:
		return
	for s in m.get("save_sections", []):
		var ns := ""
		var version := 1
		if s is String:
			ns = s
		elif s is Dictionary:
			ns = str(s.get("namespace", s.get("id", "")))
			version = int(s.get("version", 1))
		if ns == "":
			continue
		section_defs[ns] = {"ext": ext_id, "version": version}
		sections[ns] = {}
		rpg.saves.extension_hooks[ns] = {
			"version": version,
			"save": _save_section.bind(ns),
			"load": _load_section.bind(ns),
			"migrate": _migrate_section.bind(ns),
		}


func _owner_of(ns: String) -> Object:
	var ext_id := str(section_defs.get(ns, {}).get("ext", ""))
	for obj in instances_by_ext.get(ext_id, []):
		if obj.has_method("save_section"):
			return obj
	return null


func _save_section(ns: String) -> Dictionary:
	var obj := _owner_of(ns)
	if obj != null:
		var d: Variant = obj.save_section(ns)
		return d if d is Dictionary else {}
	return sections.get(ns, {}).duplicate(true)


func _load_section(data: Dictionary, ns: String) -> void:
	var obj := _owner_of(ns)
	if obj != null and obj.has_method("load_section"):
		obj.load_section(ns, data.duplicate(true))
	else:
		sections[ns] = data.duplicate(true)


func _migrate_section(data: Dictionary, from_version: int, ns: String) -> Dictionary:
	var ext_id := str(section_defs.get(ns, {}).get("ext", ""))
	for obj in instances_by_ext.get(ext_id, []):
		if obj.has_method("migrate_section"):
			var d: Variant = obj.migrate_section(ns, data, from_version)
			return d if d is Dictionary else data
	return data


func _reset_section(ns: String) -> void:
	_load_section({}, ns)


## The live Dictionary of a host-kept save section (made on first use).
func section(ns: String) -> Dictionary:
	if not sections.has(ns):
		sections[ns] = {}
	return sections[ns]


# --- conditions ------------------------------------------------------------------------------------

func _register_conditions(ext_id: String, m: Dictionary) -> void:
	for c in m.get("conditions", []):
		if not (c is Dictionary) or str(c.get("kind", "")) == "" or str(c.get("method", "")) == "":
			continue
		var method := str(c.method)
		var kind := str(c.kind)
		var found := false
		for obj in instances_by_ext.get(ext_id, []):
			if obj.has_method(method):
				rpg.register_condition_kind(kind, Callable(obj, method))
				found = true
				break
		if not found:
			_problem("Condition kind '%s' of extension '%s': no entry script has the method '%s'." % [kind, ext_id, method])


# --- main menu ---------------------------------------------------------------------------------------

## The main menu's entries in order, visible ones only: [{id, label, enabled, builtin, icon,
## entry, ext}]. Built from the built-in commands, extension manifest entries, the project.json
## "menu" block {order, hidden, entries, skip_single_actor}, then each entry script's
## adjust_menu(layout, config). `labels`: built-in id -> shown name.
func menu_layout(builtins: Array = BUILTIN_MENU, labels: Dictionary = {}) -> Array:
	var cfg := menu_config()
	var layout: Array = []
	for id in builtins:
		layout.append({"id": str(id), "label": str(labels.get(id, str(id).capitalize())), "builtin": true, "entry": {}, "ext": ""})
	var reg := registry()
	if reg != null:
		for ext_id in reg.enabled_ids():
			for e in reg.extensions[ext_id].get("menu_entries", []):
				if e is Dictionary and str(e.get("id", "")) != "":
					_insert_entry(layout, e, ext_id)
	var pm: Dictionary = _project_menu()
	for e in pm.get("entries", []):
		if e is Dictionary and str(e.get("id", "")) != "":
			_insert_entry(layout, e, "")
	_apply_order(layout, pm.get("order", []), pm.get("hidden", []))
	for e2 in entries.duplicate():
		if e2[1].has_method("adjust_menu"):
			e2[1].adjust_menu(layout, cfg)
	var out := []
	for item in layout:
		if bool(item.get("hidden", false)) or not _entry_check(item, "show", true):
			continue
		var it: Dictionary = item.duplicate()
		it["enabled"] = bool(item.get("enabled", true)) and _entry_check(item, "enable", true)
		out.append(it)
	return out


## Menu behaviour flags: {skip_single_actor} from project.json "menu" and adjust_menu hooks.
func menu_config() -> Dictionary:
	var pm := _project_menu()
	var cfg := {"skip_single_actor": bool(pm.get("skip_single_actor", false))}
	for e in entries:
		if e[1].has_method("menu_config"):
			var extra: Variant = e[1].menu_config()
			if extra is Dictionary:
				cfg.merge(extra, true)
	return cfg


func _project_menu() -> Dictionary:
	if rpg == null or rpg.data == null:
		return {}
	var pm: Variant = rpg.data.project.get("menu", {})
	return pm if pm is Dictionary else {}


## Inserts an entry {id, label, icon?, after?, before?, ...} into a layout (replacing an entry
## with the same id). Without after/before it goes before "options" (or at the end).
static func _insert_entry(layout: Array, e: Dictionary, ext_id: String) -> void:
	var item: Dictionary = {"id": str(e.id), "label": str(e.get("label", str(e.id).capitalize())), "builtin": false, "entry": e.duplicate(true), "ext": ext_id}
	if e.has("icon"):
		item["icon"] = e.icon
	for i in layout.size():
		if layout[i].id == item.id:
			layout[i] = item
			return
	var at := -1
	if str(e.get("after", "")) != "":
		at = _index_of(layout, str(e.after))
		if at != -1:
			at += 1
	elif str(e.get("before", "")) != "":
		at = _index_of(layout, str(e.before))
	if at == -1:
		at = _index_of(layout, "options")
	if at == -1:
		at = layout.size()
	layout.insert(at, item)


static func _index_of(layout: Array, id: String) -> int:
	for i in layout.size():
		if layout[i].id == id:
			return i
	return -1


## Puts the listed ids first, in that order (others keep theirs), and marks `hidden` ones.
static func _apply_order(layout: Array, order: Variant, hidden: Variant) -> void:
	if order is Array and not order.is_empty():
		var first := []
		for id in order:
			var i := _index_of(layout, str(id))
			if i != -1:
				first.append(layout[i])
		var rest := layout.filter(func(it): return not first.has(it))
		layout.clear()
		layout.append_array(first)
		layout.append_array(rest)
	if hidden is Array:
		for it in layout:
			if hidden.has(it.id):
				it["hidden"] = true


## show / enable checks of an entry: "<what>_if" (a condition, {"switch": id} or a switch ID),
## "<what>_switch" (a switch ID) and "<what>_method" (an entry script method returning bool).
func _entry_check(item: Dictionary, what: String, fallback: bool) -> bool:
	var e: Dictionary = item.get("entry", {})
	var ok := fallback
	var sw := str(e.get(what + "_switch", ""))
	if sw != "" and not rpg.state.get_switch(sw):
		return false
	var cond: Variant = e.get(what + "_if")
	if cond is String and str(cond) != "":
		ok = rpg.state.get_switch(str(cond))
	elif cond is Dictionary and not cond.is_empty():
		if cond.has("kind"):
			ok = rpg.state.check_condition(cond)
		elif cond.has("switch"):
			ok = rpg.state.get_switch(str(cond.switch))
	if not ok:
		return false
	var method := str(e.get(what + "_method", ""))
	if method != "":
		var obj := instance(str(item.get("ext", "")))
		if obj != null and obj.has_method(method):
			return bool(obj.call(method))
	return ok


## Runs a non-built-in menu entry's action for the default main menu: an entry script method
## (method(menu) or method(menu, actor)), a scene (opened over the menu until it emits closed,
## finished or cancelled) or a common event (the menu closes, the event runs on the map).
## Returns "close" when the menu should close, else "".
func run_menu_entry(item: Dictionary, menu: Node, actor: Variant = null) -> String:
	var e: Dictionary = item.get("entry", {})
	var method := str(e.get("method", ""))
	if method != "":
		var obj := instance(str(item.get("ext", "")))
		if obj != null and obj.has_method(method):
			var r: Variant = null
			if bool(e.get("needs_actor", false)):
				r = await obj.call(method, menu, actor)
			else:
				r = await obj.call(method, menu)
			return "close" if str(r) == "close" else ""
		return ""
	var scene := str(e.get("scene", ""))
	if scene != "":
		var node: Node = rpg.ui.open_scene(scene)
		if node == null:
			return ""
		if node.has_method("start") and node.has_signal("finished"):
			node.start(e.get("args", {}), {"rpg": rpg, "menu": menu, "actor": actor})
		var sigs: Array = []
		for s in ["closed", "finished", "cancelled"]:
			if node.has_signal(s):
				sigs.append(Signal(node, s))
		if not sigs.is_empty():
			await RPGWaiter.any(sigs).done
		rpg.ui.close_scene(node)
		return ""
	var ce := str(e.get("common_event", ""))
	if ce != "":
		rpg.state.reserve_common_event(ce)
		return "close"
	return ""


# --- database custom fields --------------------------------------------------------------------------

## A record's custom field: the record's "custom" value, else the declared default (project or
## extension custom_fields), else `fallback`.
func custom_field(type: String, id: String, key: String, fallback: Variant = null) -> Variant:
	var rec: Dictionary = rpg.data.record(type, id) if rpg.data != null else {}
	var custom: Variant = rec.get("custom", {})
	if custom is Dictionary and custom.has(key) and custom[key] != null:
		return custom[key]
	var reg := registry()
	if reg != null:
		for f in reg.merged_custom_fields(rpg.data.project.get("custom_fields", {})).get(type, []):
			if f is Dictionary and str(f.get("key", "")) == key and f.has("default"):
				return f.default
	return fallback
