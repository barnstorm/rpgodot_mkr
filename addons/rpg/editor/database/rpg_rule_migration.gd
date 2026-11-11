@tool
class_name RPGRuleMigration
extends RefCounted
## Switching rule systems after content exists (spec: Decisions, "Changing rule system after content
## exists: needs a migration preview and explicit confirmation").
##
## preview() lists what the switch affects without changing anything:
##   - stats and resources that disappear or appear
##   - capabilities the new system lacks
##   - every database value, formula and event command that names a stat or resource the new
##     system does not have
##   - formula problems in the new system
## apply() only changes project.json "rules". Records keep their old fields (unknown fields are
## never deleted), so switching back restores everything.

const STAT_KEYS := ["base_stats", "stats", "growth", "params"]
const SHIPPED := "res://addons/rpg/runtime/rules"


## Rule systems available to the project: rpg/rules/* first, then the ones shipped in the addon.
## Returns [{id, name, description, dir}].
static func available(project_root := "res://rpg") -> Array:
	var out := []
	var seen := {}
	for base in [project_root.path_join("rules"), SHIPPED]:
		var d := DirAccess.open(base)
		if d == null:
			continue
		var dirs := Array(d.get_directories())
		dirs.sort()
		for sub in dirs:
			var path: String = base.path_join(sub)
			if seen.has(sub) or not FileAccess.file_exists(path.path_join("rules.json")):
				continue
			var r := RPGJson.parse_file(path.path_join("rules.json"))
			if not r.ok or not (r.data is Dictionary):
				continue
			seen[sub] = true
			out.append({"id": sub, "name": str(r.data.get("name", sub)), "description": str(r.data.get("description", "")), "dir": path})
	return out


static func _ids(defs: Variant) -> Array:
	var out := []
	if defs is Array:
		for s in defs:
			if s is Dictionary and s.has("id"):
				out.append(str(s.id))
			elif s is String:
				out.append(s)
	return out


static func _definition(project_root: String, rules_id: String) -> Dictionary:
	for e in available(project_root):
		if e.id == rules_id:
			var r := RPGJson.parse_file(e.dir.path_join("rules.json"))
			return r.data if r.ok and r.data is Dictionary else {}
	return {}


## Everything the switch from the project's current rules to `to_id` would affect.
static func preview(data: RPGProjectData, to_id: String) -> Dictionary:
	var from_id := str(data.project.get("rules", "classic"))
	var from_def := _definition(data.root, from_id)
	var to_def := _definition(data.root, to_id)
	var out := {"from": from_id, "to": to_id, "ok": not to_def.is_empty(), "stats_removed": [], "stats_added": [],
		"resources_removed": [], "resources_added": [], "capabilities_lost": [], "uses": [], "formula_problems": []}
	if to_def.is_empty():
		out["formula_problems"].append("Rule system '%s' was not found." % to_id)
		return out
	var old_stats := _ids(from_def.get("stats", []))
	var new_stats := _ids(to_def.get("stats", []))
	var old_res := _ids(from_def.get("resources", []))
	var new_res := _ids(to_def.get("resources", []))
	for s in old_stats:
		if not new_stats.has(s):
			out.stats_removed.append(s)
	for s in new_stats:
		if not old_stats.has(s):
			out.stats_added.append(s)
	for r in old_res:
		if not new_res.has(r):
			out.resources_removed.append(r)
	for r in new_res:
		if not old_res.has(r):
			out.resources_added.append(r)
	for c in from_def.get("capabilities", []):
		if not to_def.get("capabilities", []).has(c):
			out.capabilities_lost.append(c)
	var gone: Array = out.stats_removed + out.resources_removed
	if not gone.is_empty():
		_scan_database(data, gone, out.uses)
		_scan_commands(data, gone, out.uses)
	# Formulas in the new system must compile.
	var rs := RPGRuleSystem.new()
	rs.setup(to_def, data)
	for p in rs.validate():
		out.formula_problems.append(str(p.get("message", p)) if p is Dictionary else str(p))
	return out


## Database values keyed by a missing stat (actor base stats, enemy stats, class growth) and formulas
## that read one (a.atk, b.mdef, user.str, ...).
static func _scan_database(data: RPGProjectData, gone: Array, uses: Array) -> void:
	var tables: Array = data.db.keys()
	tables.sort()
	for table in tables:
		for rec in data.records(table):
			if not (rec is Dictionary):
				continue
			for key in STAT_KEYS:
				if rec.get(key) is Dictionary:
					for stat in rec[key]:
						if gone.has(str(stat)):
							uses.append({"file": "database/%s.json" % table, "record": str(rec.get("id", "")), "field": "%s.%s" % [key, stat],
								"detail": "value %s is kept but unused" % JSON.stringify(rec[key][stat])})
			_scan_formulas(rec, gone, "database/%s.json" % table, str(rec.get("id", "")), "", uses)


static func _scan_formulas(v: Variant, gone: Array, file: String, record: String, path: String, uses: Array) -> void:
	if v is String:
		for g in gone:
			var re := RegEx.create_from_string("\\b[a-z_]+\\.%s\\b" % g)
			if re.search(v) != null:
				uses.append({"file": file, "record": record, "field": path, "detail": "formula reads '%s': %s" % [g, v]})
				return
	elif v is Dictionary:
		for k in v:
			_scan_formulas(v[k], gone, file, record, (path + "." if path != "" else "") + str(k), uses)
	elif v is Array:
		for i in v.size():
			_scan_formulas(v[i], gone, file, record, "%s[%d]" % [path, i], uses)


## Event commands with a stat or resource field naming a missing one (roll_check, change_stat,
## change_hp_mp, conditions on actors).
static func _scan_commands(data: RPGProjectData, gone: Array, uses: Array) -> void:
	for l in RPGProjectSearch.command_lists(data):
		_scan_command_list(l.list, gone, l.label, uses)


static func _scan_command_list(list: Array, gone: Array, label: String, uses: Array) -> void:
	for cmd in list:
		if not (cmd is Dictionary):
			continue
		for key in ["stat", "resource"]:
			if cmd.has(key) and gone.has(str(cmd[key])):
				uses.append({"file": "", "record": label, "field": str(cmd.get("type", "")), "detail": "%s '%s' no longer exists" % [key, cmd[key]]})
		for k in cmd:
			var v: Variant = cmd[k]
			if v is Array:
				var sub := []
				for x in v:
					if x is Dictionary and x.has("then") and x.then is Array:
						_scan_command_list(x.then, gone, label, uses)
					elif x is Dictionary and x.has("type"):
						sub.append(x)
				if not sub.is_empty():
					_scan_command_list(sub, gone, label, uses)


## Human-readable summary of a preview, for the confirmation dialog.
static func describe(p: Dictionary) -> String:
	var lines := ["Switch rules from '%s' to '%s'." % [p.from, p.to], ""]
	if not p.ok:
		lines.append_array(p.formula_problems)
		return "\n".join(lines)
	if not p.stats_removed.is_empty():
		lines.append("Stats no longer used: %s" % ", ".join(p.stats_removed))
	if not p.stats_added.is_empty():
		lines.append("New stats (start from the new system's defaults): %s" % ", ".join(p.stats_added))
	if not p.resources_removed.is_empty():
		lines.append("Resources no longer used: %s" % ", ".join(p.resources_removed))
	if not p.resources_added.is_empty():
		lines.append("New resources: %s" % ", ".join(p.resources_added))
	if not p.capabilities_lost.is_empty():
		lines.append("The default battle needs capabilities the new system lacks: %s" % ", ".join(p.capabilities_lost))
	if not p.formula_problems.is_empty():
		lines.append("Formula problems in the new system: %d" % p.formula_problems.size())
	lines.append("")
	if p.uses.is_empty():
		lines.append("No database values, formulas or event commands name a removed stat or resource.")
	else:
		lines.append("%d place(s) name a removed stat or resource:" % p.uses.size())
		for i in mini(p.uses.size(), 40):
			var u: Dictionary = p.uses[i]
			lines.append("  • %s %s %s: %s" % [u.file, u.record, u.field, u.detail])
		if p.uses.size() > 40:
			lines.append("  ... and %d more" % (p.uses.size() - 40))
	lines.append("")
	lines.append("Nothing is deleted: old values stay in the files, so switching back restores them. A backup of project.json and the database is written to rpg/.backup/ first. Saved games made with the old rules may not load correctly.")
	return "\n".join(lines)


## Copies project.json and the database into rpg/.backup/rules_<from>_<time>/ before a switch.
## Returns the backup folder ("" on failure).
static func backup(data: RPGProjectData) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var dir := data.root.path_join(".backup/rules_%s_%s" % [str(data.project.get("rules", "classic")), stamp])
	if DirAccess.make_dir_recursive_absolute(dir.path_join("database")) != OK:
		return ""
	DirAccess.copy_absolute(data.root.path_join("project.json"), dir.path_join("project.json"))
	var d := DirAccess.open(data.root.path_join("database"))
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				DirAccess.copy_absolute(data.root.path_join("database").path_join(f), dir.path_join("database").path_join(f))
	return dir


## Writes project.json "rules" after making a backup. Call only after the user confirmed the preview.
static func apply(data: RPGProjectData, to_id: String) -> Error:
	if backup(data) == "":
		return ERR_CANT_CREATE
	var path := data.root.path_join("project.json")
	var file: Dictionary = RPGJson.load_or(path, data.project)
	file["rules"] = to_id
	var err := RPGJson.save_file(path, file)
	if err == OK:
		data.project = file
	return err
