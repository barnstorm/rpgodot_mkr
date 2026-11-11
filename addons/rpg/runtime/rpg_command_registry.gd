@tool
class_name RPGCommandRegistry
extends RefCounted
## Loads command descriptors and command objects from manifests: the addon's built-in manifest
## plus each enabled extension's manifest.json. Extensions are never discovered by scanning:
## a project lists the ones it uses in project.json "extensions". An ID is looked up in the
## project's extensions folder first, then among the plugins bundled with the kit
## (BUNDLED_ROOT/<id>/manifest.json, all off until a project lists them).
##
## Besides commands, a manifest may declare (see docs/ARCHITECTURE.md "Extension hooks"):
## entry_scripts, settings_schema, save_sections, menu_entries, options, conditions,
## custom_fields and database_types. The registry reads the declarations; RPGExtensionHost runs
## them in a game.

const API_VERSION := 1
const BUILTIN_MANIFEST := "res://addons/rpg/runtime/commands/manifest.json"
## Plugins shipped inside the addon. Listed in Tools > Extensions; loaded only when enabled.
const BUNDLED_ROOT := "res://addons/rpg/extensions"

## Condition kinds declared by the enabled extensions of the last load_all (any registry):
## kind -> {kind, label, fields, battle, extension}. Read by RPGValidator, which has no registry.
static var declared_condition_kinds: Dictionary = {}
## Record types declared by the enabled extensions of the last load_all (manifest
## "database_types"): reference kind (e.g. "quest") -> {type, label, ref, fields, extension}.
## Read by RPGValidator and RPGRefPicker, which have no registry.
static var declared_database_types: Dictionary = {}

## type -> RPGCommand
var commands: Dictionary = {}
## type -> extension id that provides it (also for disabled extensions)
var providers: Dictionary = {}
## extension id -> manifest Dictionary (with "_dir" and "_enabled")
var extensions: Dictionary = {}
## Problems found while loading: [{severity, file, message}]
var problems: Array = []
## Types provided by disabled or missing extensions -> reason
var unavailable: Dictionary = {}


func load_all(extension_ids: Array = [], disabled: Array = [], extensions_root := "res://extensions") -> void:
	commands.clear()
	providers.clear()
	extensions.clear()
	problems.clear()
	unavailable.clear()
	_load_manifest(BUILTIN_MANIFEST, "builtin", true)
	# Load manifests first so dependency checks can see everything.
	for ext_id in extension_ids:
		var path := manifest_path(str(ext_id), extensions_root)
		var r := RPGJson.parse_file(path)
		if not r.ok:
			problems.append({"severity": "error", "file": path, "message": "Extension '%s' is missing or invalid: %s" % [ext_id, r.error]})
			continue
		var m: Dictionary = r.data
		m["_dir"] = path.get_base_dir()
		m["_enabled"] = not disabled.has(ext_id)
		m["_bundled"] = path.begins_with(BUNDLED_ROOT + "/")
		extensions[ext_id] = m
	_check_dependencies()
	for ext_id in extensions:
		var m: Dictionary = extensions[ext_id]
		var api: Array = m.get("api_versions", [API_VERSION])
		if not api.has(API_VERSION):
			problems.append({"severity": "error", "file": m._dir + "/manifest.json", "message": "Extension '%s' supports API %s, this addon provides API %d." % [ext_id, str(api), API_VERSION]})
			m._enabled = false
		_load_extension_commands(ext_id, m)
	declared_condition_kinds = condition_kinds()
	declared_database_types = {}
	for d in database_types(true):
		declared_database_types[str(d.ref)] = d


## Where an extension's manifest is: the project's extensions folder, else a bundled plugin.
static func manifest_path(ext_id: String, extensions_root := "res://extensions") -> String:
	var own := "%s/%s/manifest.json" % [extensions_root, ext_id]
	if FileAccess.file_exists(own):
		return own
	var bundled := "%s/%s/manifest.json" % [BUNDLED_ROOT, ext_id]
	if FileAccess.file_exists(bundled):
		return bundled
	return own


## IDs of the plugins bundled with the kit (folders under BUNDLED_ROOT with a manifest).
static func bundled_ids() -> Array:
	var out := []
	var d := DirAccess.open(BUNDLED_ROOT)
	if d == null:
		return out
	for sub in d.get_directories():
		if FileAccess.file_exists("%s/%s/manifest.json" % [BUNDLED_ROOT, sub]):
			out.append(sub)
	out.sort()
	return out


## The manifest of an extension that is not loaded (a bundled plugin a project has not enabled).
static func read_manifest(ext_id: String, extensions_root := "res://extensions") -> Dictionary:
	var path := manifest_path(ext_id, extensions_root)
	var r := RPGJson.parse_file(path)
	if not r.ok or not (r.data is Dictionary):
		return {}
	var m: Dictionary = r.data
	m["_dir"] = path.get_base_dir()
	m["_bundled"] = path.begins_with(BUNDLED_ROOT + "/")
	return m


## True for loaded, enabled extensions (not "builtin").
func is_enabled(ext_id: String) -> bool:
	return ext_id != "builtin" and extensions.has(ext_id) and bool(extensions[ext_id].get("_enabled", false))


## IDs of the enabled extensions in load order (not "builtin").
func enabled_ids() -> Array:
	var out := []
	for ext_id in extensions:
		if is_enabled(ext_id):
			out.append(ext_id)
	return out


## The settings form of a manifest: its settings_schema as a list of form fields
## (RPGFormBuilder kinds). Accepts an Array of fields or {"fields": [...]}; {} means none.
static func settings_fields(m: Dictionary) -> Array:
	var s: Variant = m.get("settings_schema", [])
	if s is Dictionary:
		s = s.get("fields", [])
	var out := []
	if s is Array:
		for f in s:
			if f is Dictionary and str(f.get("key", "")) != "":
				out.append(f)
	return out


## Default setting values from a manifest's settings_schema.
static func settings_defaults(m: Dictionary) -> Dictionary:
	var out := {}
	for f in settings_fields(m):
		out[str(f.key)] = RPGJson.deep_copy(f.get("default"))
	return out


## Condition kinds declared by enabled extensions (manifest "conditions"):
## kind -> {kind, label, fields, battle, method, extension}.
func condition_kinds() -> Dictionary:
	var out := {}
	for ext_id in enabled_ids():
		for c in extensions[ext_id].get("conditions", []):
			if c is Dictionary and str(c.get("kind", "")) != "":
				var d: Dictionary = c.duplicate(true)
				d["extension"] = ext_id
				if not d.has("fields"):
					d["fields"] = []
				out[str(c.kind)] = d
	return out


## Record types owned by enabled extensions (manifest "database_types": [{type, label, ref,
## fields}]), in load order: [{type, label, ref, fields, extension}]. `type` is the database
## file (rpg/database/<type>.json) and must be a valid ID that is not a built-in type; `ref` is
## the reference kind used by "ref" fields (default: the type without its last "s").
func database_types(report := false) -> Array:
	var out := []
	var seen := {}
	for ext_id in enabled_ids():
		var list: Variant = extensions[ext_id].get("database_types", [])
		if not (list is Array):
			continue
		for d in list:
			if not (d is Dictionary):
				continue
			var type := str(d.get("type", ""))
			if not RPGIds.is_valid(type) or RPGProjectData.DB_TYPES.has(type) or seen.has(type) or type in ["common_events", "state", "system", "switches", "variables", "maps"]:
				if report:
					problems.append({"severity": "error", "file": str(extensions[ext_id].get("_dir", "")) + "/manifest.json",
						"message": "Extension '%s': database type '%s' is not a usable new type." % [ext_id, type]})
				continue
			seen[type] = true
			var e: Dictionary = d.duplicate(true)
			e["type"] = type
			e["label"] = str(d.get("label", type.capitalize()))
			e["ref"] = str(d.get("ref", type.trim_suffix("s")))
			e["fields"] = d.get("fields", []) if d.get("fields") is Array else []
			e["extension"] = ext_id
			out.append(e)
	return out


## The database type of a reference kind declared by an extension ("" when none).
static func database_type_of(ref_kind: String) -> String:
	var d: Variant = declared_database_types.get(ref_kind)
	return str(d.type) if d is Dictionary else ""


## The project's custom_fields (project.json) plus the ones enabled extensions declare for
## existing record types (manifest "custom_fields": {type: [field, ...]}). The project's own
## field wins when both use the same key. Besides database types, two more targets exist:
## "maps" (Map properties, stored in the map's "custom") and "event_pages" (each event page,
## stored in the page's "custom").
func merged_custom_fields(project_fields: Dictionary) -> Dictionary:
	var out: Dictionary = project_fields.duplicate(true)
	for ext_id in enabled_ids():
		var cf: Variant = extensions[ext_id].get("custom_fields", {})
		if not (cf is Dictionary):
			continue
		for type in cf:
			var list: Array = out.get(type, [])
			var keys := {}
			for f in list:
				if f is Dictionary:
					keys[str(f.get("key", ""))] = true
			for f in cf[type]:
				if f is Dictionary and not keys.has(str(f.get("key", ""))):
					var g: Dictionary = f.duplicate(true)
					g["extension"] = ext_id
					list.append(g)
			out[type] = list
	return out


func _load_manifest(path: String, ext_id: String, enabled: bool) -> void:
	var r := RPGJson.parse_file(path)
	if not r.ok:
		problems.append({"severity": "error", "file": path, "message": r.error})
		return
	var m: Dictionary = r.data
	m["_dir"] = path.get_base_dir()
	m["_enabled"] = enabled
	extensions[ext_id] = m
	_load_extension_commands(ext_id, m)


func _load_extension_commands(ext_id: String, m: Dictionary) -> void:
	for rel in m.get("commands", []):
		var script_path: String = rel if str(rel).begins_with("res://") else m._dir.path_join(rel)
		if not ResourceLoader.exists(script_path):
			problems.append({"severity": "error", "file": script_path, "message": "Command script listed by '%s' is missing." % ext_id})
			continue
		var script: Script = load(script_path)
		if script == null or not script.can_instantiate():
			problems.append({"severity": "error", "file": script_path, "message": "Command script failed to load (parse error?)."})
			continue
		var cmd: Variant = script.new()
		if not (cmd is RPGCommand):
			problems.append({"severity": "error", "file": script_path, "message": "Command script must extend RPGCommand."})
			continue
		var d: Dictionary = cmd.descriptor()
		var type: String = d.get("type", "")
		if type == "":
			problems.append({"severity": "error", "file": script_path, "message": "Descriptor has no type."})
			continue
		if providers.has(type) and providers[type] != ext_id:
			problems.append({"severity": "error", "file": script_path, "message": "Command type '%s' is provided by both '%s' and '%s'." % [type, providers[type], ext_id]})
			continue
		cmd.desc = d
		cmd.extension_id = ext_id
		providers[type] = ext_id
		if m.get("_enabled", true):
			commands[type] = cmd
		else:
			unavailable[type] = "extension '%s' is disabled" % ext_id


func _check_dependencies() -> void:
	for ext_id in extensions:
		var seen := {}
		if _has_loop(ext_id, seen, []):
			problems.append({"severity": "error", "file": extensions[ext_id]._dir + "/manifest.json", "message": "Extension '%s' has a dependency loop." % ext_id})
			extensions[ext_id]._enabled = false
		for dep in extensions[ext_id].get("dependencies", []):
			if not extensions.has(dep):
				problems.append({"severity": "error", "file": extensions[ext_id]._dir + "/manifest.json", "message": "Extension '%s' needs '%s', which is not installed." % [ext_id, dep]})
				extensions[ext_id]._enabled = false


func _has_loop(ext_id: String, seen: Dictionary, path: Array) -> bool:
	if path.has(ext_id):
		return true
	if not extensions.has(ext_id):
		return false
	path.append(ext_id)
	for dep in extensions[ext_id].get("dependencies", []):
		if _has_loop(dep, seen, path):
			return true
	path.pop_back()
	return false


func get_command(type: String) -> RPGCommand:
	return commands.get(type)


func has_command(type: String) -> bool:
	return commands.has(type)


func unavailable_reason(type: String) -> String:
	if unavailable.has(type):
		return unavailable[type]
	if not providers.has(type):
		return "no installed extension provides it"
	return ""


func descriptor(type: String) -> Dictionary:
	var c: RPGCommand = commands.get(type)
	return c.desc if c else {}


func all_descriptors() -> Array:
	var out := []
	for t in commands:
		out.append(commands[t].desc)
	out.sort_custom(func(a, b): return [a.get("category", ""), a.get("label", "")] < [b.get("category", ""), b.get("label", "")])
	return out


func summary(cmd_data: Dictionary) -> String:
	var c: RPGCommand = commands.get(cmd_data.get("type", ""))
	if c == null:
		return "?? %s (unavailable)" % cmd_data.get("type", "")
	return c.summary(c.with_defaults(cmd_data))


func child_lists(cmd_data: Dictionary) -> Array:
	var c: RPGCommand = commands.get(cmd_data.get("type", ""))
	if c == null:
		return []
	return c.child_lists(cmd_data)


## Calls `visitor.call(cmd_data, path)` for every command in a list, recursively.
func walk(list: Array, visitor: Callable, path := "") -> void:
	for i in list.size():
		var c: Variant = list[i]
		if not (c is Dictionary):
			continue
		var p := "%s/%d" % [path, i]
		visitor.call(c, p)
		var children := child_lists(c)
		for child in children:
			walk(child.list, visitor, p + "." + child.key)
		# Choices hold nested lists inside an array of objects. The Show Choices command reports
		# them itself; only walk them here when it isn't registered (else they'd be visited twice).
		if c.get("type", "") == "show_choices" and children.is_empty():
			for j in c.get("choices", []).size():
				var ch: Variant = c.choices[j]
				if ch is Dictionary and ch.get("then") is Array:
					walk(ch.then, visitor, "%s.choices/%d" % [p, j])
