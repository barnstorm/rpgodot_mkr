class_name RPGSaveService
extends RefCounted
## Versioned JSON saves, written atomically one slot at a time.
## A save holds the project ID, schema version, timestamp, play time, map/position/facing, game
## state (party, inventory, gold, switches, variables, self switches, per-event changes), audio,
## screen and extension sections. Saves never copy event pages or map tiles.
## Saving is only allowed at a safe point: no main event, no transfer, no open scene.
## Loading validates everything before touching live state; on failure the game continues.

const SCHEMA_VERSION := 2
const DIR := "user://saves"
const MAX_SLOTS := 16
## With System > Auto-save on, the game saves here after each map transfer, at the next safe point.
const AUTOSAVE_SLOT := MAX_SLOTS

var rpg: Node
## Extension save hooks: namespace -> {version, save: Callable() -> Dictionary,
## load: Callable(Dictionary), migrate: Callable(Dictionary, int) -> Dictionary}. A hook whose
## section is missing from a loaded save gets load({}) so no state leaks from the last game.
## Extensions declare these in their manifest ("save_sections"); RPGExtensionHost registers them.
var extension_hooks: Dictionary = {}
## Slots offered by the save screen (1..max_slots). Extensions may lower it (save_plus).
var max_slots := MAX_SLOTS
## True when the save screen should name the autosave slot "Auto" even without System
## Auto-save (an extension autosaves there).
var autosave_labelled := false
## Callables returning a Dictionary merged into the save's "header" (shown by the save screen
## through describe(): e.g. {"description": "Chapter 2"}).
var header_providers: Array[Callable] = []
## When valid and it returns false, autosave() does nothing (an extension's "Autosave: Off").
var autosave_allowed: Callable = Callable()


func _init(p_rpg: Node) -> void:
	rpg = p_rpg


func slot_path(slot: int) -> String:
	return "%s/slot_%02d.json" % [DIR, slot]


## Number of slots the save screen lists.
func slot_count() -> int:
	return clampi(max_slots, 1, 99)


## The slot autosaves write to: the last listed slot (as System Auto-save always did).
func autosave_slot() -> int:
	return slot_count()


## True when `slot` is shown as the autosave slot.
func is_autosave_slot(slot: int) -> bool:
	if slot != autosave_slot():
		return false
	return autosave_labelled or (rpg != null and rpg.data != null and bool(rpg.data.system.get("auto_save", false)))


## Saves to the autosave slot now when that is allowed. `reason` (transfer, battle, menu,
## event, ...) is passed on to RPG.autosaved. Returns the save's RPGResult.
func autosave(reason := "") -> RPGResult:
	if autosave_allowed.is_valid() and not bool(autosave_allowed.call()):
		return RPGResult.error("Autosave is turned off.")
	var r := save(autosave_slot())
	if rpg != null and rpg.has_signal("autosaved"):
		rpg.autosaved.emit(autosave_slot(), r.is_ok(), reason)
	if r.is_error():
		push_warning("Auto-save failed: %s" % r.message)
	return r


## Why saving is unavailable right now ("" when it is allowed).
func save_blocked_reason() -> String:
	if rpg.scheduler.main != null or not rpg.scheduler.queue.is_empty():
		return "You can't save while an event is running."
	if rpg.game != null and rpg.game.transferring:
		return "You can't save during a map transition."
	if rpg.current_map() == null:
		return "There is no game to save."
	for n in rpg.ui.scene_stack:
		if is_instance_valid(n) and n.get_meta("blocks_saving", false):
			return "You can't save right now."
	return ""


func build_save() -> Dictionary:
	var m: Node = rpg.current_map()
	var p: Node = m.player if m else null
	var ext: Dictionary = rpg.state.extension_sections.duplicate(true)
	for ns in extension_hooks:
		var h: Dictionary = extension_hooks[ns]
		if h.has("save"):
			ext[ns] = {"version": int(h.get("version", 1)), "data": h.save.call()}
	# Persist event positions that moved during play (set_event_location etc.).
	if m != null:
		for id in m.events:
			var ev: Node = m.events[id]
			if ev.has_meta("persist"):
				ev.save_change()
	return {
		"schema_version": SCHEMA_VERSION,
		"project_id": rpg.data.project.get("project_id", ""),
		"timestamp": Time.get_datetime_string_from_system(true),
		"unix_time": int(Time.get_unix_time_from_system()),
		"play_time": rpg.state.play_time,
		"map": {"id": m.map_id if m else "", "position": [p.cell.x, p.cell.y] if p else [0, 0], "facing": p.facing if p else "down"},
		"state": rpg.state.to_dict(),
		# With their positions (MV's saveBgm), so a load resumes the music where it was.
		"audio": {"bgm": rpg.audio.save_bgm(), "bgs": rpg.audio.save_bgs()},
		"screen": rpg.screen.to_dict(),
		"rng": rpg.rng.get_state() if rpg.rng != null and rpg.rng.has_method("get_state") else null,
		"extensions": ext,
		"header": _header(),
	}


func _header() -> Dictionary:
	var out := {}
	for c in header_providers:
		if c.is_valid():
			var h: Variant = c.call()
			if h is Dictionary:
				out.merge(h, true)
	return out


func save(slot: int) -> RPGResult:
	var why := save_blocked_reason()
	if why != "":
		return RPGResult.error(why)
	var data := build_save()
	DirAccess.make_dir_recursive_absolute(DIR)
	var err := RPGJson.save_file(slot_path(slot), data)
	if err != OK:
		return RPGResult.error("Could not write save slot %d (error %d)." % [slot, err])
	return RPGResult.ok(data)


func exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Summary for the save screen: {slot, exists, timestamp, play_time, map_name, party, error}.
func describe(slot: int) -> Dictionary:
	var info := {"slot": slot, "exists": exists(slot)}
	if not info.exists:
		return info
	var r := RPGJson.parse_file(slot_path(slot))
	if not r.ok:
		info["error"] = "Damaged save"
		return info
	var d: Dictionary = r.data
	info["timestamp"] = d.get("timestamp", "")
	info["local_time"] = local_time_text(d)
	info["play_time"] = float(d.get("play_time", 0))
	var mid: String = d.get("map", {}).get("id", "")
	var display := str(rpg.data.map_props(mid).get("display_name", ""))
	info["map_name"] = display if display != "" else str(rpg.data.map_entry(mid).get("name", mid))
	info["party"] = d.get("state", {}).get("party", [])
	info["header"] = d.get("header", {}) if d.get("header") is Dictionary else {}
	# What each member looked like in this save (name, Change Actor Graphic face), so the slot
	# shows the saved party rather than the live one.
	var actors: Variant = d.get("state", {}).get("actors", {})
	var members := []
	for id in info.party:
		var a: Variant = actors.get(str(id), {}) if actors is Dictionary else {}
		a = a if a is Dictionary else {}
		var custom: Variant = a.get("custom", {})
		var look: Variant = custom.get("look", {}) if custom is Dictionary else {}
		look = look if look is Dictionary else {}
		members.append({"id": str(id), "name": str(a.get("name", "")), "face": str(look.get("face", "")), "face_index": int(look.get("face_index", 0))})
	info["members"] = members
	return info


## When a save was made, as "YYYY-MM-DD HH:MM" in the player's local time ("timestamp" is UTC,
## so slots still sort the same in any time zone).
static func local_time_text(save: Dictionary) -> String:
	var unix := -1
	if save.has("unix_time"):
		unix = int(save.unix_time)
	elif str(save.get("timestamp", "")) != "":
		unix = int(Time.get_unix_time_from_datetime_string(str(save.timestamp)))
	if unix < 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_string_from_unix_time(unix + bias * 60, true).substr(0, 16)


## Runs migrations on a copy. Returns {ok, data, changes, error}.
func migrate(d: Dictionary) -> Dictionary:
	var data := d.duplicate(true)
	var v := int(data.get("schema_version", 0))
	var changes := []
	if v > SCHEMA_VERSION:
		return {"ok": false, "error": "This save was made by a newer version (schema %d)." % v}
	if v < 1:
		# v0 (prototype): state lived at the top level.
		data["state"] = {"switches": data.get("switches", {}), "variables": data.get("variables", {}), "gold": data.get("gold", 0), "party": data.get("party", [])}
		changes.append("moved state into 'state'")
		v = 1
	if v < 2:
		# v1 -> v2: screen and rng sections added.
		if not data.has("screen"):
			data["screen"] = {}
		if not data.has("rng"):
			data["rng"] = null
		changes.append("added screen and rng sections")
		v = 2
	data["schema_version"] = v
	for ns in data.get("extensions", {}):
		var h: Dictionary = extension_hooks.get(ns, {})
		if h.has("migrate"):
			var sec: Dictionary = data.extensions[ns]
			if int(sec.get("version", 1)) < int(h.get("version", 1)):
				sec["data"] = h.migrate.call(sec.get("data", {}), int(sec.get("version", 1)))
				sec["version"] = int(h.get("version", 1))
				changes.append("migrated extension section '%s'" % ns)
	return {"ok": true, "data": data, "changes": changes, "error": ""}


## Checks a (migrated) save against the project. Returns an Array of problem strings.
func validate(d: Dictionary) -> Array:
	var problems := []
	if str(d.get("project_id", "")) != str(rpg.data.project.get("project_id", "")):
		problems.append("This save belongs to another project ('%s')." % d.get("project_id", ""))
	var m: Dictionary = d.get("map", {})
	if not rpg.data.maps.has(str(m.get("id", ""))):
		problems.append("The saved map '%s' no longer exists." % m.get("id", ""))
	elif not rpg.data.cell_in_map(str(m.id), m.get("position", [])):
		problems.append("The saved position is outside map '%s'." % m.id)
	var st: Dictionary = d.get("state", {})
	for id in st.get("party", []):
		if not rpg.data.has_record("actors", str(id)) and not rpg.data.records("actors").is_empty():
			problems.append("Party member '%s' no longer exists." % id)
	return problems


## Loads a slot. Nothing changes unless every check passes.
func load_slot(slot: int) -> RPGResult:
	if not exists(slot):
		return RPGResult.error("Slot %d is empty." % slot)
	var r := RPGJson.parse_file(slot_path(slot))
	if not r.ok:
		return RPGResult.error("Save slot %d is damaged: %s" % [slot, r.error])
	return await load_data(r.data)


func load_data(raw: Dictionary) -> RPGResult:
	var mig := migrate(raw)
	if not mig.ok:
		return RPGResult.error(mig.error)
	var d: Dictionary = mig.data
	var problems := validate(d)
	if not problems.is_empty():
		return RPGResult.error(" ".join(problems))
	# Checks passed: apply. Keep the live state so a late failure (the map scene fails to load)
	# leaves the current game's data as it was.
	var before_state: Dictionary = rpg.state.to_dict()
	var before_ext: Dictionary = rpg.state.extension_sections.duplicate(true)
	rpg.state.from_dict(d.get("state", {}), rpg.battler_script())
	var ext: Dictionary = d.get("extensions", {})
	rpg.state.extension_sections = {}
	for ns in ext:
		var h: Dictionary = extension_hooks.get(ns, {})
		if h.has("load"):
			h.load.call(ext[ns].get("data", {}))
		else:
			# Kept so it becomes active again once the extension is installed.
			rpg.state.extension_sections[ns] = ext[ns]
	# Sections the save does not have (made before the extension was enabled) start empty.
	for ns in extension_hooks:
		if not ext.has(ns) and extension_hooks[ns].has("load"):
			extension_hooks[ns].load.call({})
	if d.get("rng") != null and rpg.rng != null and rpg.rng.has_method("set_state"):
		rpg.rng.set_state(d.rng)
	if rpg.game != null:
		var tr: RPGResult = await rpg.game.load_from(d)
		if tr.is_error():
			rpg.state.from_dict(before_state, rpg.battler_script())
			rpg.state.extension_sections = before_ext
			return tr
	var audio: Dictionary = d.get("audio", {})
	if audio.get("bgm") is Dictionary and not audio.bgm.is_empty():
		# The map's music has just started from 0: move it to the saved position.
		rpg.audio.play_bgm(audio.bgm, float(audio.bgm.get("pos", 0.0)))
	if audio.get("bgs") is Dictionary and not audio.bgs.is_empty():
		rpg.audio.play_bgs(audio.bgs, float(audio.bgs.get("pos", 0.0)))
	var scr: Dictionary = d.get("screen", {})
	if scr.get("weather", "none") != "none":
		rpg.screen.set_weather(scr.weather)
	if scr.get("tint") is Array and scr.tint.size() == 4:
		rpg.screen.tint_screen(Color(scr.tint[0], scr.tint[1], scr.tint[2], scr.tint[3]), 0.0)
	# Pictures shown when the game was saved (a missing image is skipped, not an error).
	var pics: Variant = scr.get("pictures", {})
	if pics is Dictionary:
		for n in pics:
			var pd: Variant = pics[n]
			if not (pd is Dictionary) or str(pd.get("name", "")) == "":
				continue
			var tex: Texture2D = rpg.ui.load_texture("picture", str(pd.name)) if rpg.ui != null else null
			if tex == null:
				continue
			var at: Array = pd.get("position", [0, 0])
			rpg.screen.show_picture(int(n), tex, Vector2(float(at[0]), float(at[1])), str(pd.get("origin", "top_left")), float(pd.get("scale", 100.0)), int(pd.get("opacity", 255)))
			rpg.screen.pictures[int(n)].set_meta("picture_name", str(pd.name))
	if rpg.has_signal("game_loaded"):
		rpg.game_loaded.emit()
	return RPGResult.ok(mig.changes)
