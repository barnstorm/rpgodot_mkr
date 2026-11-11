@tool
extends RefCounted
## Deploy helpers for the Tools window (spec: Tools and playtest, Deploy): read Godot's export
## presets, work out the output path and command line, list unused assets to leave out, and
## temporarily add them to a preset's exclude_filter (the original file is always restored).
## Preloaded by path (no class_name):
##   const Deploy := preload("res://addons/rpg/editor/tools/rpg_deploy.gd")

const PRESETS_PATH := "res://export_presets.cfg"
const BACKUP_SUFFIX := ".rpgkit-backup"
const Vehicles := preload("res://addons/rpg/runtime/rpg_vehicles.gd")
## Godot platform name -> [build folder, file extension].
const PLATFORMS := {
	"Windows Desktop": ["windows", "exe"],
	"Linux": ["linux", "x86_64"],
	"Linux/X11": ["linux", "x86_64"],
	"macOS": ["macos", "zip"],
	"Web": ["web", "html"],
	"Android": ["android", "apk"],
	"iOS": ["ios", "ipa"],
}
## Images that the runtime loads by a fixed name when the project names none.
const RUNTIME_IMAGES := ["system"]


## Export presets in the project: [{index, name, platform, export_path, exclude_filter}] in file order.
static func presets(cfg_path := PRESETS_PATH) -> Array:
	var out := []
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return out
	for section in cfg.get_sections():
		var m := RegEx.create_from_string("^preset\\.(\\d+)$").search(section)
		if m == null:
			continue
		out.append({
			"index": int(m.get_string(1)),
			"section": section,
			"name": str(cfg.get_value(section, "name", "")),
			"platform": str(cfg.get_value(section, "platform", "")),
			"export_path": str(cfg.get_value(section, "export_path", "")),
			"exclude_filter": str(cfg.get_value(section, "exclude_filter", "")),
		})
	out.sort_custom(func(a, b): return a.index < b.index)
	return out


## The game title as a file name: "Sample Quest" -> "SampleQuest".
static func file_title(title: String) -> String:
	var out := ""
	for c in title:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
	return out if out != "" else "Game"


## Default output path, relative to the project: build/<platform>/<GameTitle>.<ext>.
static func default_output(platform: String, game_title: String) -> String:
	var p: Array = PLATFORMS.get(platform, [platform.to_snake_case().replace("/", "_"), "zip"])
	return "build/%s/%s.%s" % [p[0], file_title(game_title), p[1]]


## The executable to run the export with. On Windows the console build is preferred when it sits
## next to the editor, so its output can be read.
static func godot_executable() -> String:
	var exe := OS.get_executable_path()
	if exe.get_extension().to_lower() == "exe" and not exe.get_basename().ends_with("_console"):
		var console := exe.get_basename() + "_console.exe"
		if FileAccess.file_exists(console):
			return console
	return exe


## Command line for a headless export of one preset. Relative output paths are made absolute
## against the project folder.
static func build_args(preset_name: String, out_path: String, project_dir := "", debug := false) -> PackedStringArray:
	if project_dir == "":
		project_dir = ProjectSettings.globalize_path("res://")
	var out := out_path
	if out.begins_with("res://"):
		out = ProjectSettings.globalize_path(out)
	elif out.is_relative_path():
		out = project_dir.path_join(out)
	return PackedStringArray(["--headless", "--path", project_dir, "--export-debug" if debug else "--export-release", preset_name, out])


## Names (without extension) the runtime loads on its own: every sound role, the profile's sound
## and music roles, the project's sound roles and the default window skin. Files with these names
## are never left out or deleted, even when no project data mentions them.
static func runtime_names(data: RPGProjectData) -> Dictionary:
	var names := {}
	for n in RUNTIME_IMAGES:
		names[n] = true
	for r in RPGProfile.SOUND_ROLES:
		names[r] = true
	var prof := RPGProfile.load_profile(str(data.profile.get("profile", RPGProfile.DEFAULT_PROFILE)))
	if prof != null:
		for table in [prof.sound_roles, prof.music_roles]:
			for k in table:
				var v: Variant = table[k]
				for n in (v if v is Array else [v]):
					names[str(n)] = true
	var roles: Variant = data.project.get("sound_roles", {})
	if roles is Dictionary:
		for k in roles:
			names[str(roles[k])] = true
	# Vehicles left at their defaults (not written into System) still draw the default sheet.
	var vehicles: Variant = data.system.get("vehicles", {})
	for kind in Vehicles.DEFAULTS:
		var g: Variant = Vehicles.DEFAULTS[kind].get("graphic", {})
		var set: Variant = vehicles.get(kind, {}) if vehicles is Dictionary else {}
		if set is Dictionary and set.get("graphic") is Dictionary:
			g = set.graphic
		if g is Dictionary and str(g.get("sheet", "")) != "":
			names[str(g.sheet)] = true
	return names


## Where the project uses an asset file: a list of short descriptions ("map 'town' event 'elder'",
## "database/actors.json 'hero'", "runtime default 'cursor'"). Empty when nothing uses it.
## Matching follows RPGProjectSearch.asset_usage: full path, path under the asset root, file name
## or name without extension.
static func where_used(data: RPGProjectData, path: String, asset_root := "res://assets", limit := 8) -> Array:
	var keys := {path: true, path.trim_prefix(asset_root + "/"): true, path.get_file(): true, path.get_file().get_basename(): true}
	var out := []
	var base := path.get_file().get_basename()
	if runtime_names(data).has(base):
		out.append("runtime default '%s'" % base)
	var places: Array = [["project.json", data.project], ["profile.json", data.profile], ["System", data.system], ["state.json", data.state_defs]]
	for t in data.db:
		for r in data.db[t].records:
			if r is Dictionary:
				places.append(["database/%s.json '%s'" % [t, r.get("id", "")], r])
	for id in data.common_events:
		places.append(["common event '%s'" % id, data.common_events[id]])
	for map_id in data.maps:
		places.append(["map '%s' properties" % map_id, data.map_props(map_id)])
		for ev in data.map_events(map_id):
			if ev is Dictionary:
				places.append(["map '%s' event '%s'" % [map_id, ev.get("id", "")], ev])
	for p in places:
		if out.size() >= limit:
			break
		if _mentions(p[1], keys):
			out.append(p[0])
	return out


static func _mentions(v: Variant, keys: Dictionary) -> bool:
	if v is String:
		return keys.has(v)
	if v is Dictionary:
		for k in v:
			if _mentions(v[k], keys):
				return true
	elif v is Array:
		for x in v:
			if _mentions(x, keys):
				return true
	return false


## res:// paths of asset files the game never uses (not in project data, not a runtime default).
static func unused_asset_excludes(data: RPGProjectData, asset_root := "res://assets") -> PackedStringArray:
	var keep := runtime_names(data)
	var out := PackedStringArray()
	for u in RPGProjectSearch.asset_usage(data, asset_root):
		if u.used or keep.has(str(u.name)):
			continue
		var p := str(u.path)
		# Characters that would split or widen the filter list are not left out.
		if p.contains(",") or p.contains("*") or p.contains("?") or p.contains("["):
			continue
		out.append(p)
	return out


## Export filters for the plugins bundled with the kit (addons/rpg/extensions/<id>) that the
## project does not enable: the game never loads them, so the build can leave them out.
static func unused_extension_excludes(data: RPGProjectData) -> PackedStringArray:
	var out := PackedStringArray()
	var on: Array = data.project.get("extensions", [])
	var off: Array = data.project.get("disabled_extensions", [])
	for id in RPGCommandRegistry.bundled_ids():
		if not on.has(id) or off.has(id):
			out.append(RPGCommandRegistry.BUNDLED_ROOT.trim_prefix("res://").path_join(id) + "/*")
	return out


## Adds `excludes` to a preset's exclude_filter. The file's exact text is first copied to
## <cfg>.rpgkit-backup; restore_presets() puts it back. Returns {ok, message}.
static func apply_excludes(cfg_path: String, section: String, excludes: PackedStringArray) -> Dictionary:
	if excludes.is_empty():
		return {"ok": true, "message": ""}
	var original := FileAccess.get_file_as_string(cfg_path)
	if original == "":
		return {"ok": false, "message": "Cannot read %s." % cfg_path}
	var backup := cfg_path + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup):
		var bf := FileAccess.open(backup, FileAccess.WRITE)
		if bf == null:
			return {"ok": false, "message": "Cannot write %s." % backup}
		bf.store_string(original)
		bf.close()
	var cfg := ConfigFile.new()
	if cfg.parse(original) != OK or not cfg.has_section(section):
		restore_presets(cfg_path)
		return {"ok": false, "message": "Preset %s not found in %s." % [section, cfg_path]}
	var parts := PackedStringArray()
	var existing := str(cfg.get_value(section, "exclude_filter", "")).strip_edges()
	if existing != "":
		parts.append(existing)
	parts.append(", ".join(excludes))
	cfg.set_value(section, "exclude_filter", ", ".join(parts))
	if cfg.save(cfg_path) != OK:
		restore_presets(cfg_path)
		return {"ok": false, "message": "Cannot write %s." % cfg_path}
	return {"ok": true, "message": ""}


## Puts back the preset file saved by apply_excludes. Returns true when a backup was restored.
static func restore_presets(cfg_path := PRESETS_PATH) -> bool:
	var backup := cfg_path + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup):
		return false
	var text := FileAccess.get_file_as_string(backup)
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	return true


## Export log for the window: colour codes removed and the per-file "Storing File" lines dropped.
static func clean_log(output: String) -> String:
	var plain := RegEx.create_from_string(char(27) + "\\[[0-9;]*m").sub(output, "", true)
	var lines := PackedStringArray()
	var stored := 0
	for line in plain.split("\n"):
		if line.contains("Storing File:"):
			stored += 1
			continue
		lines.append(line)
	if stored > 0:
		lines.append("(%d files packed)" % stored)
	return "\n".join(lines)


## Turns the export's exit code and output into {ok, message} for the window. The build counts as
## done when the output file was written (at or after `since_unix`, when given) and Godot reported
## no export failure: Godot can crash while shutting down after a good export, giving a bad exit code.
static func summarize_output(exit_code: int, output: String, out_path := "", since_unix := 0) -> Dictionary:
	var plain := clean_log(output)
	var lower := plain.to_lower()
	var first_error := ""
	for line in plain.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("ERROR:") and not l.contains("leaked"):
			first_error = l.trim_prefix("ERROR:").strip_edges()
			break
	var said := ("\nGodot said: " + first_error) if first_error != "" else ""
	if lower.contains("no export template found") or (lower.contains("export template") and (lower.contains("not found") or lower.contains("missing"))):
		return {"ok": false, "message": "Export templates for this Godot version are not installed. Open Editor > Manage Export Templates, install them, then build again." + said}
	if lower.contains("invalid export preset name"):
		return {"ok": false, "message": "Godot does not know this preset. Check Project > Export." + said}
	var failed := lower.contains("cannot export project") or lower.contains("project export failed") or lower.contains("failed to export")
	var written := out_path == "" or (FileAccess.file_exists(out_path) and (since_unix <= 0 or FileAccess.get_modified_time(out_path) >= since_unix - 2))
	if not failed and written and (exit_code == 0 or out_path != ""):
		var msg := ("Built %s." % out_path.get_file()) if out_path != "" else "Build finished."
		if exit_code != 0:
			msg += " (Godot exited with code %d after writing it; the build is complete.)" % exit_code
		return {"ok": true, "message": msg}
	var why := first_error if first_error != "" else (("exit code %d" % exit_code) if exit_code != 0 else "no file was written")
	return {"ok": false, "message": "Export failed: %s. See the log for details." % why}
