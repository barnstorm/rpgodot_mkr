@tool
class_name RPGExportCheck
extends RefCounted
## Headless-friendly export gate used by the editor export plugin, the Deploy dialog and the
## pre-playtest check: loads the project, its extensions and every command list, and returns
## problems. Any command whose type is unavailable (disabled or missing extension) is an error.

const VALIDATOR := "res://addons/rpg/core/rpg_validator.gd"


static func run_checks(root := "res://rpg") -> Array:
	var data := RPGProjectData.open(root)
	var reg := RPGCommandRegistry.new()
	reg.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), data.project.get("extensions_root", "res://extensions"))
	return problems(data, reg)


## Every problem of a loaded project: the full validation plus the rule-system capability checks.
## The export gate, Deploy's "Run export checks" and the pre-playtest check all use this list.
static func problems(data: RPGProjectData, reg: RPGCommandRegistry) -> Array:
	var out: Array = []
	var seen := {}
	var add := func(p: Dictionary) -> void:
		# Two references to the same missing ID give the same message: keep both (E34).
		var key := "%s|%s|%s|%s" % [p.get("file", ""), p.get("record", ""), p.get("path", ""), p.get("message", "")]
		if not seen.has(key):
			seen[key] = true
			out.append(p)
	if ResourceLoader.exists(VALIDATOR) and load(VALIDATOR).has_method("full"):
		var res: Variant = load(VALIDATOR).full(data, reg)
		for p in (res if res is Array else res.get("problems", [])):
			add.call(p)
	else:
		for p in _fallback_problems(data, reg):
			add.call(p)
	for p in capability_problems(data, reg):
		add.call(p)
	return out


## Without the validator: load errors, extension problems and unavailable commands.
static func _fallback_problems(data: RPGProjectData, reg: RPGCommandRegistry) -> Array:
	var problems: Array = []
	for e in data.load_errors:
		problems.append(e)
	for p in reg.problems:
		problems.append(p)
	# Unavailable commands anywhere block export.
	var lists := []
	for map_id in data.maps:
		for ev in data.map_events(map_id):
			for pi in ev.get("pages", []).size():
				lists.append({"file": data.map_entry(map_id).get("events", ""), "where": "event '%s' page %d" % [ev.get("id", ""), pi + 1], "list": ev.pages[pi].get("commands", [])})
	for id in data.common_events:
		lists.append({"file": data.root.path_join("common_events.json"), "where": "common event '%s'" % id, "list": data.common_events[id].get("commands", [])})
	for troop in data.records("troops"):
		for pg in troop.get("pages", troop.get("battle_events", [])):
			if pg is Dictionary:
				lists.append({"file": data.root.path_join("database/troops.json"), "where": "troop '%s'" % troop.get("id", ""), "list": pg.get("commands", [])})
	for l in lists:
		reg.walk(l.list, func(cmd: Dictionary, path: String):
			var t: String = str(cmd.get("type", ""))
			if not reg.has_command(t):
				problems.append({"severity": "error", "file": l.file, "record": l.where, "path": path, "blocks_export": true, "message": "Command '%s' is unavailable (%s). Enable or install its extension, or remove the command." % [t, reg.unavailable_reason(t)]}))
	return problems


## Capabilities the project's rule system offers (rules.json "capabilities").
static func rule_capabilities(data: RPGProjectData) -> Array:
	var rules_id := str(data.project.get("rules", "classic"))
	for base in [data.root.path_join("rules"), "res://addons/rpg/runtime/rules"]:
		var path: String = base.path_join(rules_id).path_join("rules.json")
		if FileAccess.file_exists(path):
			var r := RPGJson.parse_file(path)
			if r.ok and r.data is Dictionary:
				return r.data.get("capabilities", [])
	return []


## Capabilities a battle scene needs: a CAPABILITIES constant on its script (for a .tscn, on its
## root node's script). Returns null when the scene declares nothing.
static func scene_capabilities(path: String) -> Variant:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	var script: Script = null
	if res is Script:
		script = res
	elif res is PackedScene:
		var st: SceneState = (res as PackedScene).get_state()
		for i in st.get_node_property_count(0):
			if st.get_node_property_name(0, i) == "script":
				script = st.get_node_property_value(0, i)
	if script == null:
		return null
	var consts := script.get_script_constant_map()
	if consts.has("CAPABILITIES"):
		return consts.CAPABILITIES
	return null


## Spec: rules and battle screens meet through a contract. Every battle scene in use and every
## enabled extension must find the capabilities it needs in the selected rule system.
static func capability_problems(data: RPGProjectData, reg: RPGCommandRegistry = null) -> Array:
	var offered := rule_capabilities(data)
	var out := []
	var rules_id := str(data.project.get("rules", "classic"))
	var scenes := {}
	var sys_scene := str(data.system.get("battle_scene", data.system.get("default_battle_scene", "")))
	scenes[sys_scene if sys_scene != "" else "res://addons/rpg/runtime/ui/battle/battle_scene.gd"] = "System > Default battle scene"
	for map_id in data.maps:
		var ms := str(data.map_props(map_id).get("battle_scene", ""))
		if ms != "":
			scenes[ms] = "map '%s'" % map_id
	for path in scenes:
		var need: Variant = scene_capabilities(path)
		if need == null:
			continue
		for c in need:
			if not offered.has(c):
				out.append({"severity": "error", "file": path, "record": scenes[path], "path": "", "blocks_export": true,
					"message": "Battle scene %s needs the capability '%s', which rule system '%s' does not offer." % [path.get_file(), c, rules_id],
					"fix_hint": "Pick a battle scene made for this rule system, or add the capability to the rules."})
	if reg != null:
		for ext_id in reg.extensions:
			var m: Dictionary = reg.extensions[ext_id]
			if not m.get("_enabled", false):
				continue
			for c in m.get("requires_capabilities", []):
				if not offered.has(c):
					out.append({"severity": "error", "file": str(m.get("_dir", "")).path_join("manifest.json"), "record": "extension '%s'" % ext_id, "path": "", "blocks_export": true,
						"message": "Extension '%s' needs the capability '%s', which rule system '%s' does not offer." % [ext_id, c, rules_id],
						"fix_hint": "Switch to a rule system that offers it, or turn the extension off."})
	return out
