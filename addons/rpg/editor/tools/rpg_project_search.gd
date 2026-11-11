@tool
class_name RPGProjectSearch
extends RefCounted
## Read-only project scans behind the Tools window (spec: Tools and playtest):
##   search()          the event searcher: commands by text, type or referenced ID, plus page conditions
##   asset_usage()     the resource manager: which asset files the project references, and which are unused
##   sound_files()     the sound test: playable audio files grouped by folder
## Everything works on RPGProjectData and plain JSON, so it is unit-tested without the editor.

## MIDI music is listed too: the editor imports it as rendered audio.
const AUDIO_EXT := ["wav", "ogg", "mp3", "mid", "midi"]
const IMAGE_EXT := ["png", "webp", "jpg", "jpeg", "bmp"]


## Every command list in the project: map event pages, common events and troop battle pages.
## Returns [{scope, map, event, event_name, page, list, label}].
static func command_lists(data: RPGProjectData) -> Array:
	var out := []
	var map_ids: Array = data.maps.keys()
	map_ids.sort()
	for map_id in map_ids:
		for ev in data.map_events(map_id):
			var pages: Array = ev.get("pages", [])
			for pi in pages.size():
				out.append({
					"scope": "map", "map": map_id, "event": str(ev.get("id", "")), "event_name": str(ev.get("name", "")),
					"page": pi, "list": pages[pi].get("commands", []), "conditions": pages[pi].get("conditions", []),
					"label": "%s / %s (%s), page %d" % [data.map_props(map_id).get("name", map_id), ev.get("name", ""), ev.get("id", ""), pi + 1],
				})
	var ce_ids: Array = data.common_events.keys()
	ce_ids.sort()
	for id in ce_ids:
		var ce: Dictionary = data.common_events[id]
		out.append({"scope": "common", "map": "", "event": id, "event_name": str(ce.get("name", id)), "page": 0,
			"list": ce.get("commands", []), "conditions": [], "label": "Common event: %s (%s)" % [ce.get("name", id), id]})
	for troop in data.records("troops"):
		var pages: Array = troop.get("pages", troop.get("battle_events", []))
		for pi in pages.size():
			if pages[pi] is Dictionary:
				out.append({"scope": "troop", "map": "", "event": str(troop.get("id", "")), "event_name": str(troop.get("name", "")),
					"page": pi, "list": pages[pi].get("commands", []), "conditions": pages[pi].get("conditions", []),
					"label": "Troop: %s, battle page %d" % [troop.get("name", troop.get("id", "")), pi + 1]})
	return out


## query: {text?: String, type?: String, ref?: String}. All given parts must match.
##   text  case-insensitive substring of the command's own fields (not its child lists)
##   type  exact command type, e.g. "transfer_player"
##   ref   an ID used by the command or by a page condition (switch, variable, item, map, troop, ...)
## Returns [{label, scope, map, event, page, path, type, summary}] in project order.
static func search(data: RPGProjectData, registry: RPGCommandRegistry, query: Dictionary) -> Array:
	var text := str(query.get("text", "")).strip_edges().to_lower()
	var type := str(query.get("type", "")).strip_edges()
	var ref := str(query.get("ref", "")).strip_edges()
	var results := []
	if text == "" and type == "" and ref == "":
		return results
	for l in command_lists(data):
		# Page conditions count as references (e.g. "where is switch door_unlocked used?").
		if ref != "" and text == "" and type == "":
			for cond in l.conditions:
				if _refers(cond, ref):
					var where := "Page %d condition" % (int(l.page) + 1) if l.scope != "common" else "Condition"
					results.append(_hit(l, "conditions", {"type": "(page condition)"}, "%s: %s" % [where, describe_condition(registry, cond)]))
		var hits := []
		walk_commands(registry, l.list, func(cmd: Dictionary, path: String):
			if type != "" and str(cmd.get("type", "")) != type:
				return
			var own := _own_fields(cmd, registry)
			if text != "" and not JSON.stringify(own).to_lower().contains(text):
				return
			if ref != "" and not _refers(own, ref):
				return
			hits.append(_hit(l, path, cmd, registry.summary(cmd))))
		results.append_array(hits)
	return results


## Calls visitor.call(cmd, path) once for every command in `list` and its branches. Unlike
## RPGCommandRegistry.walk it never visits a branch twice (that walk reaches Show Choices
## branches both through child_lists and through "choices").
static func walk_commands(registry: RPGCommandRegistry, list: Array, visitor: Callable, path := "", seen: Array = []) -> void:
	for x in seen:
		if is_same(x, list):
			return
	seen.append(list)
	for i in list.size():
		var c: Variant = list[i]
		if not (c is Dictionary):
			continue
		var p := "%s/%d" % [path, i]
		visitor.call(c, p)
		for child in registry.child_lists(c):
			if child.get("list") is Array:
				walk_commands(registry, child.list, visitor, p + "." + str(child.key), seen)
		if c.get("type", "") == "show_choices" and c.get("choices") is Array:
			for j in c.choices.size():
				var ch: Variant = c.choices[j]
				if ch is Dictionary and ch.get("then") is Array:
					walk_commands(registry, ch.then, visitor, "%s.choices/%d/then" % [p, j], seen)


## Readable text of a condition ("Switch [cat_quest] is ON"), as Conditional Branch shows it.
static func describe_condition(registry: RPGCommandRegistry, cond: Variant) -> String:
	var ifc: Variant = registry.get_command("if") if registry != null else null
	if ifc != null and ifc.has_method("describe_condition"):
		return str(ifc.describe_condition(cond))
	return JSON.stringify(cond)


static func _hit(l: Dictionary, path: String, cmd: Dictionary, summary: String) -> Dictionary:
	return {"label": l.label, "scope": l.scope, "map": l.map, "event": l.event, "page": l.page, "path": path,
		"type": str(cmd.get("type", "")), "summary": summary}


## The command without nested command lists, so a hit is reported on the command that holds it.
static func _own_fields(cmd: Dictionary, registry: RPGCommandRegistry) -> Dictionary:
	var own := cmd.duplicate()
	for child in registry.child_lists(cmd):
		own.erase(child.key)
	if own.get("type", "") == "show_choices" and own.get("choices") is Array:
		var labels := []
		for ch in own.choices:
			if ch is Dictionary:
				labels.append(ch.get("label", ""))
		own["choices"] = labels
	return own


static func _refers(v: Variant, ref: String) -> bool:
	if v is String or v is StringName:
		return str(v) == ref
	if v is Dictionary:
		for k in v:
			if k == "type" or k == "kind" or k == "operation":
				continue
			if _refers(v[k], ref):
				return true
	elif v is Array:
		for x in v:
			if _refers(x, ref):
				return true
	return false


# --- resources -----------------------------------------------------------------------------------

## Files under `roots` (default the project's asset folders), recursively, skipping .import files.
static func list_files(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if exts.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(list_files(dir.path_join(sub), exts))
	return out


## Every string in the project's JSON data, map scenes excluded (they reference only tiles).
static func project_strings(data: RPGProjectData) -> Dictionary:
	var seen := {}
	var blobs: Array = [data.project, data.profile, data.system, data.state_defs, data.common_events]
	for table in data.db:
		blobs.append(data.db[table])
	for map_id in data.maps:
		blobs.append(data.map_props(map_id))
		blobs.append(data.map_events(map_id))
	for b in blobs:
		_collect_strings(b, seen)
	return seen


static func _collect_strings(v: Variant, out: Dictionary) -> void:
	if v is String:
		if v != "":
			out[v] = true
	elif v is Dictionary:
		for k in v:
			_collect_strings(v[k], out)
	elif v is Array:
		for x in v:
			_collect_strings(x, out)


## Asset files with whether the project uses them. A file counts as used when its full path, its
## path relative to the asset root, or its name without extension (how CharSets, faces and sounds
## are referenced) appears anywhere in the project data.
## Returns [{path, folder, name, used}] sorted by path.
static func asset_usage(data: RPGProjectData, asset_root := "res://assets") -> Array:
	var strings := project_strings(data)
	var out := []
	for path in list_files(asset_root, IMAGE_EXT + AUDIO_EXT):
		var base := path.get_file().get_basename()
		var rel := path.trim_prefix(asset_root + "/")
		var used := strings.has(path) or strings.has(rel) or strings.has(base) or strings.has(path.get_file())
		out.append({"path": path, "folder": path.get_base_dir().get_file(), "name": base, "used": used})
	out.sort_custom(func(a, b): return a.path < b.path)
	return out


## {folder name: [paths]} of playable audio under the asset root.
static func sound_files(asset_root := "res://assets") -> Dictionary:
	var out := {}
	for path in list_files(asset_root, AUDIO_EXT):
		var folder := path.get_base_dir().get_file()
		if not out.has(folder):
			out[folder] = []
		out[folder].append(path)
	for k in out:
		out[k].sort()
	return out
