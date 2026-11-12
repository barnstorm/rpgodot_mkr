@tool
class_name RPGValidator
extends RefCounted
## Project checks at three levels (spec "Validation, usability and accessibility"):
##   structure(file_kind, data)          JSON shape of one file (on every edit)
##   references(project_data, registry)  IDs, locations, assets and links between files (on save)
##   full(project_data, registry)        everything, incl. extension availability (before playtest/export)
## Every problem: {severity: "error"|"warning", file, record, field, path, message, fix_hint}
## (+ "blocks_export": true for problems that stop an export).
##
## Also: used_by() lists where an ID is read or set, and rename_id() renames an ID together with
## every typed reference, returning the new file contents as one transaction (the caller writes).
##
## Most functions take an optional `files` set {path: {kind, data, map?, db_type?}} so the editor
## can check unsaved, in-memory copies. collect_files() builds it from an RPGProjectData.

const PAGE_PRIORITIES := ["below", "same", "above"]
const PAGE_TRIGGERS := ["action_button", "player_touch", "event_touch", "autorun", "parallel"]
const MOVE_TYPES := ["fixed", "random", "approach", "custom"]
const CE_TRIGGERS := ["none", "autorun", "parallel"]
const VAR_TYPES := ["int", "float", "bool", "string"]
const OPS := ["==", "=", "!=", "≠", "<", "<=", "≤", ">", ">=", "≥"]
const EQ_OPS := ["==", "=", "!=", "≠"]
const FACINGS := ["down", "left", "right", "up", "keep"]
const CONDITION_KINDS := ["switch", "variable", "self_switch", "item", "actor", "gold", "vehicle", "facing", "button", "all", "any", "not"]
## Actor condition checks ({kind: "actor", check}); the target sits under the check's own key.
const ACTOR_CHECKS := ["in_party", "name", "class", "skill", "weapon", "armor", "state"]
## Button condition names (input actions rpg_<name>).
const CONDITION_BUTTONS := ["ok", "cancel", "dash", "up", "down", "left", "right"]
## Vehicle condition ids ("none" / "" = on foot).
const VEHICLE_IDS := ["boat", "ship", "airship", "none", ""]
## Game data operand kinds (RPGGameState.game_data).
const GAME_DATA_KINDS := ["item", "items", "weapon", "weapons", "armor", "armors", "armour", "gold", "steps", "play_time", "party_size", "actor"]
const BATTLE_CONDITION_KINDS := ["turn", "enemy_hp", "actor_hp", "switch"]
const SPANS := ["once_per_battle", "once_per_turn", "every_check"]

## Singular reference kind -> database type.
const DB_KIND := {
	"actor": "actors", "class": "classes", "skill": "skills", "item": "items", "weapon": "weapons",
	"armor": "armors", "enemy": "enemies", "troop": "troops", "state": "states",
	"animation": "animations", "tileset": "tilesets",
}
const KIND_LABEL := {
	"switch": "Switch", "variable": "Variable", "map": "Map", "common_event": "Common event",
	"event": "Event", "actor": "Actor", "class": "Class", "skill": "Skill", "item": "Item",
	"weapon": "Weapon", "armor": "Armour", "enemy": "Enemy", "troop": "Enemy group",
	"state": "State", "animation": "Animation", "tileset": "Tileset",
}
const FIX_HINT := {
	"switch": "Create the switch in Database > Switches and variables, or pick another one.",
	"variable": "Create the variable in Database > Switches and variables, or pick another one.",
	"map": "Pick an existing map, or create the map first.",
	"common_event": "Create the common event in Database > Common events, or pick another one.",
}
## Command fields that write the referenced switch/variable (everything else reads).
const SETTER_FIELDS := {"set_switch": ["id"], "set_variable": ["id"], "input_number": ["variable"]}
const SETTER_KEYS := ["result", "roll_into"]
## Commands whose free-form strings may mention IDs (renames warn instead of rewriting).
const SCRIPT_COMMANDS := ["call_method", "emit_signal", "run_scene"]
## Effect kind -> what its "id" names (RPGRuleSystem.apply_action).
const EFFECT_REFS := {"add_state": "state", "remove_state": "state", "learn_skill": "skill", "common_event": "common_event", "grow": "stat"}
## Trait kind -> what its "id" names, for rule systems whose rules.json does not say ("id_ref").
const TRAIT_REFS := {"element_rate": "element", "state_rate": "state", "state_resist": "state", "stat_rate": "stat",
	"attack_element": "element", "attack_state": "state", "add_skill_type": "skill_type", "seal_skill_type": "skill_type",
	"dual_wield": "equip_slot", "seal_equip": "equip_slot"}
## id_ref values that name an entry of a Types list -> the Types record holding the list.
const TYPE_LISTS := {"element": "elements", "skill_type": "skill_types", "equip_slot": "equip_slots", "weapon_type": "weapon_types", "armor_type": "armor_types"}
## Built-in battle effects (RPGBattleEffects.BUILTIN): an `animation` may name one instead of a record.
const BUILTIN_ANIMATIONS := ["hit", "slash", "fire", "ice", "thunder", "heal"]


static func problem(severity: String, file: String, record: String, field: String, path: String, message: String, fix_hint := "") -> Dictionary:
	return {"severity": severity, "file": file, "record": record, "field": field, "path": path, "message": message, "fix_hint": fix_hint}


# ============================================================================================
# File set
# ============================================================================================

## Reference kind -> database type: DB_KIND plus the record types the enabled extensions own
## (RPGCommandRegistry.declared_database_types, e.g. "quest" -> "quests").
static func db_kinds() -> Dictionary:
	var out := DB_KIND.duplicate()
	for k in RPGCommandRegistry.declared_database_types:
		out[k] = str(RPGCommandRegistry.declared_database_types[k].type)
	return out


## Every authored file of a project: {path: {kind, data, map?, db_type?}}.
## kind: project, state, map_index, common_events, database, system, map, events.
static func collect_files(data: RPGProjectData, overrides: Dictionary = {}) -> Dictionary:
	var files := {}
	var root := data.root
	files[root.path_join("project.json")] = {"kind": "project", "data": data.project}
	files[root.path_join("state.json")] = {"kind": "state", "data": data.state_defs}
	files[root.path_join("map_index.json")] = {"kind": "map_index", "data": data.map_index}
	files[root.path_join("common_events.json")] = {"kind": "common_events", "data": data.common_events_file}
	for t in RPGProjectData.DB_TYPES:
		var p := root.path_join("database/%s.json" % t)
		if FileAccess.file_exists(p) or not data.records(t).is_empty():
			files[p] = {"kind": "database", "db_type": t, "data": data.db[t].file}
	# Record types owned by enabled extensions (loaded into the data when it lacks them).
	for d in RPGCommandRegistry.declared_database_types.values():
		var et := str(d.type)
		var ep := root.path_join("database/%s.json" % et)
		if not data.db.has(et) and FileAccess.file_exists(ep):
			data.add_db_types([et])
		if data.db.has(et) and (FileAccess.file_exists(ep) or not data.records(et).is_empty()):
			files[ep] = {"kind": "database", "db_type": et, "data": data.db[et].file}
	var sys_path := root.path_join("database/system.json")
	if FileAccess.file_exists(sys_path):
		var r := RPGJson.parse_file(sys_path)
		if r.ok:
			files[sys_path] = {"kind": "system", "data": r.data}
	for map_id in data.maps:
		var e: Dictionary = data.maps[map_id]
		var ep: String = e.get("events", root.path_join("maps/%s.events.json" % map_id))
		if FileAccess.file_exists(ep):
			var r2 := RPGJson.parse_file(ep)
			if r2.ok:
				files[ep] = {"kind": "events", "map": map_id, "data": r2.data}
		var pp: String = e.get("properties", root.path_join("maps/%s.map.json" % map_id))
		if FileAccess.file_exists(pp):
			var r3 := RPGJson.parse_file(pp)
			if r3.ok:
				files[pp] = {"kind": "map", "map": map_id, "data": r3.data}
	for k in overrides:
		files[k] = overrides[k]
	return files


static func events_path(data: RPGProjectData, map_id: String) -> String:
	var e: Dictionary = data.maps.get(map_id, {})
	return e.get("events", data.root.path_join("maps/%s.events.json" % map_id))


# ============================================================================================
# Level 1: structure
# ============================================================================================

## Checks the JSON shape of one file. file_kind: events, state, map_index, common_events,
## database (or "database:<type>"), system, map, project. `registry` (optional) adds per-command
## descriptor checks.
static func structure(file_kind: String, data: Variant, registry: RPGCommandRegistry = null, file := "") -> Array:
	var out := []
	if not (data is Dictionary):
		out.append(problem("error", file, "", "", "", "The file must contain a JSON object ({ ... }).", "Open the file and wrap its contents in { }."))
		return out
	if not data.has("schema_version"):
		out.append(problem("warning", file, "", "schema_version", "schema_version", "The file has no schema_version.", "Add \"schema_version\": 1 at the top."))
	elif typeof(data.schema_version) != TYPE_INT:
		out.append(problem("error", file, "", "schema_version", "schema_version", "schema_version must be a whole number.", ""))
	var kind := file_kind
	var db_type := ""
	if kind.begins_with("database:"):
		db_type = kind.substr(9)
		kind = "database"
	match kind:
		"events":
			_events_structure(data, registry, file, out)
		"state":
			_state_structure(data, file, out)
		"map_index":
			_id_list_structure(data, "maps", "map", file, out)
		"common_events":
			var list: Variant = data.get("common_events", [])
			if _id_list_structure(data, "common_events", "common event", file, out):
				for i in list.size():
					var ce: Variant = list[i]
					if not (ce is Dictionary):
						continue
					var rec := str(ce.get("id", ""))
					var base := "common_events/%d" % i
					if not CE_TRIGGERS.has(str(ce.get("trigger", "none"))):
						out.append(problem("error", file, rec, "trigger", base + "/trigger", "Common event '%s' has an unknown trigger '%s'." % [rec, ce.get("trigger")], "Use none, autorun or parallel."))
					_commands_structure(ce.get("commands", []), registry, file, rec, base + "/commands", out)
		"database":
			if _id_list_structure(data, "records", "record", file, out) and db_type == "troops":
				for i in data.records.size():
					var tr: Variant = data.records[i]
					if tr is Dictionary:
						_troop_structure(tr, registry, file, "records/%d" % i, out)
		"system":
			if not (data.get("system", null) is Dictionary):
				out.append(problem("error", file, "", "system", "system", "system.json needs a \"system\" object.", ""))
			else:
				_system_walk_problems(data.system, file, out)
		"map":
			for k in ["width", "height"]:
				var v: Variant = data.get(k, null)
				if typeof(v) != TYPE_INT or int(v) < 1:
					out.append(problem("error", file, str(data.get("id", "")), k, k, "Map %s must be a whole number of at least 1." % k, ""))
		"project":
			pass
	return out


static func _id_list_structure(data: Dictionary, key: String, what: String, file: String, out: Array) -> bool:
	var list: Variant = data.get(key, null)
	if not (list is Array):
		out.append(problem("error", file, "", key, key, "\"%s\" must be a list." % key, ""))
		return false
	var seen := {}
	for i in list.size():
		var r: Variant = list[i]
		var p := "%s/%d" % [key, i]
		if not (r is Dictionary):
			out.append(problem("error", file, "", "", p, "Entry %d of \"%s\" must be an object." % [i, key], ""))
			continue
		var id: Variant = r.get("id", null)
		if not RPGIds.is_valid(id):
			out.append(problem("error", file, str(id), "id", p + "/id", "The %s ID '%s' is not valid. IDs use lowercase letters, digits and _, and start with a letter." % [what, id], "Rename it, e.g. to '%s'." % RPGIds.slug(str(id if id != null else what))))
		elif seen.has(id):
			out.append(problem("error", file, str(id), "id", p + "/id", "The %s ID '%s' is used twice." % [what, id], "Give one of them a new ID."))
		else:
			seen[id] = true
	return true


static func _state_structure(data: Dictionary, file: String, out: Array) -> void:
	_id_list_structure(data, "switches", "switch", file, out)
	if _id_list_structure(data, "variables", "variable", file, out):
		for i in data.variables.size():
			var v: Variant = data.variables[i]
			if v is Dictionary and not VAR_TYPES.has(str(v.get("type", "int"))):
				out.append(problem("error", file, str(v.get("id", "")), "type", "variables/%d/type" % i, "Variable '%s' has an unknown type '%s'." % [v.get("id", ""), v.get("type")], "Use int, float, bool or string."))


static func _events_structure(data: Dictionary, registry: RPGCommandRegistry, file: String, out: Array) -> void:
	if typeof(data.get("map", "")) != TYPE_STRING:
		out.append(problem("error", file, "", "map", "map", "\"map\" must be the map ID.", ""))
	if not _id_list_structure(data, "events", "event", file, out):
		return
	for i in data.events.size():
		var ev: Variant = data.events[i]
		if ev is Dictionary:
			event_structure(ev, registry, file, "events/%d" % i, out)


## Checks one event object. Appends problems to `out` and returns it.
static func event_structure(ev: Dictionary, registry: RPGCommandRegistry = null, file := "", base := "", out: Array = []) -> Array:
	var rec := str(ev.get("id", ""))
	var pre := (base + "/") if base != "" else ""
	var pos: Variant = ev.get("position", null)
	if not (pos is Array) or pos.size() != 2 or typeof(pos[0]) != TYPE_INT or typeof(pos[1]) != TYPE_INT:
		out.append(problem("error", file, rec, "position", pre + "position", "Event '%s' needs a position [x, y] in whole tiles." % rec, "Move the event on the map to fix its position."))
	elif pos[0] < 0 or pos[1] < 0:
		out.append(problem("error", file, rec, "position", pre + "position", "Event '%s' is placed outside the map." % rec, "Move the event onto the map."))
	if ev.has("name") and typeof(ev.name) != TYPE_STRING:
		out.append(problem("error", file, rec, "name", pre + "name", "The event name must be text.", ""))
	var pages: Variant = ev.get("pages", null)
	if not (pages is Array):
		out.append(problem("error", file, rec, "pages", pre + "pages", "Event '%s' needs a list of pages." % rec, ""))
		return out
	if pages.is_empty():
		out.append(problem("warning", file, rec, "pages", pre + "pages", "Event '%s' has no pages, so it never does anything." % rec, "Add a page."))
	for j in pages.size():
		var pg: Variant = pages[j]
		var pp := "%spages/%d" % [pre, j]
		if not (pg is Dictionary):
			out.append(problem("error", file, rec, "", pp, "Page %d must be an object." % (j + 1), ""))
			continue
		page_structure(pg, registry, file, rec, pp, out)
	return out


static func page_structure(pg: Dictionary, registry: RPGCommandRegistry, file: String, rec: String, pp: String, out: Array) -> void:
	var conds: Variant = pg.get("conditions", [])
	if not (conds is Array):
		out.append(problem("error", file, rec, "conditions", pp + "/conditions", "Page conditions must be a list.", ""))
	else:
		for k in conds.size():
			_condition_structure(conds[k], file, rec, "%s/conditions/%d" % [pp, k], out, false)
	var g: Variant = pg.get("graphic", null)
	if g != null and not (g is Dictionary):
		out.append(problem("error", file, rec, "graphic", pp + "/graphic", "The page graphic must be an object or null.", "Pick a graphic again in the page settings."))
	elif g is Dictionary and g.has("facing") and not FACINGS.has(str(g.facing)):
		out.append(problem("error", file, rec, "graphic", pp + "/graphic/facing", "Unknown facing '%s'." % g.facing, "Use down, left, right or up."))
	var mv: Variant = pg.get("movement", {})
	if not (mv is Dictionary):
		out.append(problem("error", file, rec, "movement", pp + "/movement", "Movement must be an object.", ""))
	else:
		if not MOVE_TYPES.has(str(mv.get("type", "fixed"))):
			out.append(problem("error", file, rec, "movement", pp + "/movement/type", "Unknown movement type '%s'." % mv.get("type"), "Use fixed, random, approach or custom."))
		if mv.has("speed") and (typeof(mv.speed) != TYPE_INT or mv.speed < 1 or mv.speed > 6):
			out.append(problem("error", file, rec, "movement", pp + "/movement/speed", "Movement speed must be 1 to 6.", ""))
		if mv.has("frequency") and (typeof(mv.frequency) != TYPE_INT or mv.frequency < 1 or mv.frequency > 5):
			out.append(problem("error", file, rec, "movement", pp + "/movement/frequency", "Movement frequency must be 1 to 5.", ""))
	var opts: Variant = pg.get("options", {})
	if not (opts is Dictionary):
		out.append(problem("error", file, rec, "options", pp + "/options", "Options must be an object.", ""))
	else:
		for k in ["walk_anim", "step_anim", "direction_fix", "through"]:
			if opts.has(k) and typeof(opts[k]) != TYPE_BOOL:
				out.append(problem("error", file, rec, "options", "%s/options/%s" % [pp, k], "Option '%s' must be true or false." % k, ""))
	if not PAGE_PRIORITIES.has(str(pg.get("priority", "same"))):
		out.append(problem("error", file, rec, "priority", pp + "/priority", "Unknown priority '%s'." % pg.get("priority"), "Use below, same or above."))
	if not PAGE_TRIGGERS.has(str(pg.get("trigger", "action_button"))):
		out.append(problem("error", file, rec, "trigger", pp + "/trigger", "Unknown trigger '%s'." % pg.get("trigger"), "Use action_button, player_touch, event_touch, autorun or parallel."))
	_commands_structure(pg.get("commands", []), registry, file, rec, pp + "/commands", out)
	_battle_only_outside(pg.get("commands", []), registry, file, rec, pp + "/commands", out)


## Map event pages: commands whose descriptor says "battle_only" (Enemy Appear) never find a
## battle there, so they would stop the event with an error.
static func _battle_only_outside(list: Variant, registry: RPGCommandRegistry, file: String, rec: String, path: String, out: Array) -> void:
	if registry == null or not (list is Array):
		return
	registry.walk(list, func(c: Dictionary, p: String) -> void:
		var d: Dictionary = registry.descriptor(str(c.get("type", "")))
		if bool(d.get("battle_only", false)):
			out.append(problem("warning", file, rec, "type", path + p.replace(".", "/"),
				"%s only works in a battle event; on a map it stops the event with an error." % d.get("label", c.type),
				"Move it to an enemy group's battle events (Database > Enemy groups), or to a common event called from one.")))


## Enemy Appear in a troop's battle events: the enemy number must be a member of the group, and
## that member should be marked "Appears later" (else the command does nothing).
static func _enemy_appear_checks(tr: Dictionary, list: Variant, registry: RPGCommandRegistry, file: String, path: String, out: Array) -> void:
	if registry == null or not (list is Array):
		return
	var rec := str(tr.get("id", ""))
	var members: Variant = tr.get("members", [])
	if not (members is Array):
		return
	registry.walk(list, func(c: Dictionary, p: String) -> void:
		if str(c.get("type", "")) != "enemy_appear" or str(c.get("which", "one")) == "all":
			return
		var n := int(c.get("enemy", 1)) if typeof(c.get("enemy", 1)) in [TYPE_INT, TYPE_FLOAT] else 0
		var cp := path + p.replace(".", "/") + "/enemy"
		if n < 1 or n > members.size():
			out.append(problem("error", file, rec, "enemy", cp, "Enemy Appear: enemy group '%s' has no enemy #%d." % [rec, n], "Pick a number from 1 to %d." % members.size()))
		elif not (members[n - 1] is Dictionary and bool(members[n - 1].get("hidden", false))):
			out.append(problem("warning", file, rec, "enemy", cp, "Enemy Appear: enemy #%d is not marked \"Appears later\", so it is already in the battle." % n, "Tick \"Appears later\" for that enemy, or pick another number."))
		)


static func _troop_structure(tr: Dictionary, registry: RPGCommandRegistry, file: String, base: String, out: Array) -> void:
	var rec := str(tr.get("id", ""))
	var pages: Variant = tr.get("pages", [])
	if not (pages is Array):
		out.append(problem("error", file, rec, "pages", base + "/pages", "Battle event pages must be a list.", ""))
		return
	for j in pages.size():
		var pg: Variant = pages[j]
		var pp := "%s/pages/%d" % [base, j]
		if not (pg is Dictionary):
			continue
		if not SPANS.has(str(pg.get("span", "once_per_battle"))):
			out.append(problem("error", file, rec, "span", pp + "/span", "Unknown span '%s'." % pg.get("span"), "Use once_per_battle, once_per_turn or every_check."))
		for k in pg.get("conditions", []).size():
			_condition_structure(pg.conditions[k], file, rec, "%s/conditions/%d" % [pp, k], out, true)
		_commands_structure(pg.get("commands", []), registry, file, rec, pp + "/commands", out)
		_enemy_appear_checks(tr, pg.get("commands", []), registry, file, pp + "/commands", out)


static func _condition_structure(c: Variant, file: String, rec: String, path: String, out: Array, battle: bool) -> void:
	if not (c is Dictionary):
		out.append(problem("error", file, rec, "condition", path, "A condition must be an object with a \"kind\".", ""))
		return
	var kind := str(c.get("kind", ""))
	var kinds: Array = BATTLE_CONDITION_KINDS if battle else CONDITION_KINDS
	# Kinds an enabled extension declares (manifest "conditions") are checked by the extension.
	var ext_kind: Variant = RPGCommandRegistry.declared_condition_kinds.get(kind)
	if ext_kind is Dictionary and (not battle or bool(ext_kind.get("battle", false))):
		return
	if not kinds.has(kind):
		out.append(problem("error", file, rec, "condition", path + "/kind", "Unknown condition kind '%s'." % kind, "Use one of: %s." % ", ".join(PackedStringArray(kinds))))
		return
	match kind:
		"self_switch":
			var letter := str(c.get("id", c.get("switch", "")))
			if not RPGIds.SELF_SWITCHES.has(letter):
				out.append(problem("error", file, rec, "condition", path + "/id", "Self switch '%s' does not exist. Self switches are A, B, C and D." % letter, "Pick A, B, C or D."))
		"variable", "gold", "enemy_hp", "actor_hp":
			var op := str(c.get("op", "=="))
			if not OPS.has(op):
				out.append(problem("error", file, rec, "condition", path + "/op", "Unknown comparison '%s'." % op, "Use ==, !=, <, <=, > or >=."))
			if kind != "enemy_hp" and kind != "actor_hp":
				_operand_structure(c.get("value", 0), file, rec, path + "/value", out)
		"actor":
			var check := str(c.get("check", "in_party"))
			if not ACTOR_CHECKS.has(check):
				out.append(problem("error", file, rec, "condition", path + "/check", "Unknown actor check '%s'." % check, "Use one of: %s." % ", ".join(PackedStringArray(ACTOR_CHECKS))))
			elif check != "in_party" and str(c.get(check, "")) == "":
				out.append(problem("error", file, rec, "condition", path + "/" + check, "This actor condition has no %s to check." % check, "Pick one in the condition."))
		"facing":
			if not FACINGS.slice(0, 4).has(str(c.get("facing", ""))):
				out.append(problem("error", file, rec, "condition", path + "/facing", "Unknown facing '%s'." % c.get("facing", ""), "Use down, left, right or up."))
		"button":
			if not CONDITION_BUTTONS.has(str(c.get("button", ""))):
				out.append(problem("error", file, rec, "condition", path + "/button", "Unknown button '%s'." % c.get("button", ""), "Use one of: %s." % ", ".join(PackedStringArray(CONDITION_BUTTONS))))
		"vehicle":
			var vid := str(c.get("id", c.get("vehicle", "")))
			if not VEHICLE_IDS.has(vid):
				out.append(problem("error", file, rec, "condition", path + "/id", "Unknown vehicle '%s'." % vid, "Use boat, ship, airship or none."))
		"all", "any":
			for i in c.get("conditions", []).size():
				_condition_structure(c.conditions[i], file, rec, "%s/conditions/%d" % [path, i], out, battle)
		"not":
			_condition_structure(c.get("condition"), file, rec, path + "/condition", out, battle)
	if kind in ["switch", "variable", "item", "actor"] and not RPGIds.is_valid(c.get("id")):
		out.append(problem("error", file, rec, "condition", path + "/id", "This %s condition has no valid ID." % kind, "Pick a %s from the list." % kind))


static func _operand_structure(v: Variant, file: String, rec: String, path: String, out: Array) -> void:
	if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]:
		return
	if v is Dictionary and RPGIds.is_valid(v.get("variable")):
		return
	if v is Dictionary and v.get("random") is Array and v.random.size() == 2 and typeof(v.random[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(v.random[1]) in [TYPE_INT, TYPE_FLOAT]:
		return
	if v is Dictionary and v.get("game_data") is Dictionary:
		if GAME_DATA_KINDS.has(str(v.game_data.get("kind", ""))):
			return
		out.append(problem("error", file, rec, "value", path + "/game_data/kind", "Unknown game data '%s'." % v.game_data.get("kind", ""), "Use item, weapon, armor, gold, steps, play_time, party_size or actor."))
		return
	out.append(problem("error", file, rec, "value", path, "A value must be a number, {\"variable\": id}, {\"random\": [a, b]} or {\"game_data\": {...}}.", ""))


static func _commands_structure(list: Variant, registry: RPGCommandRegistry, file: String, rec: String, path: String, out: Array) -> void:
	if not (list is Array):
		out.append(problem("error", file, rec, "commands", path, "Commands must be a list.", ""))
		return
	for i in list.size():
		var c: Variant = list[i]
		var cp := "%s/%d" % [path, i]
		if not (c is Dictionary) or typeof(c.get("type", null)) != TYPE_STRING:
			out.append(problem("error", file, rec, "type", cp, "Every command must be an object with a \"type\".", "Delete this line or open it as JSON to fix it."))
			continue
		out.append_array(command_structure(c, registry, file, rec, cp))
		if registry == null:
			continue
		var cmd: RPGCommand = registry.get_command(c.type)
		if cmd == null:
			continue
		_nested_structure(cmd.desc.get("fields", []), c, registry, file, rec, cp, out)


static func _nested_structure(fields: Array, holder: Dictionary, registry: RPGCommandRegistry, file: String, rec: String, cp: String, out: Array) -> void:
	for f in fields:
		var k: String = f.get("key", "")
		var v: Variant = holder.get(k)
		match str(f.get("kind", "")):
			"commands":
				if v != null:
					_commands_structure(v, registry, file, rec, cp + "/" + k, out)
			"list":
				if v is Array:
					for j in v.size():
						if v[j] is Dictionary:
							_nested_structure(f.get("item_fields", []), v[j], registry, file, rec, "%s/%s/%d" % [cp, k, j], out)
			"object":
				if v is Dictionary:
					_nested_structure(f.get("fields", []), v, registry, file, rec, cp + "/" + k, out)
			"condition":
				if v != null:
					_condition_structure(v, file, rec, cp + "/" + k, out, false)


## Checks one command's own fields against its descriptor (not its nested lists).
static func command_structure(c: Dictionary, registry: RPGCommandRegistry, file := "", rec := "", path := "") -> Array:
	var out := []
	if registry == null:
		return out
	var type := str(c.get("type", ""))
	if c.has("skip") and typeof(c.skip) != TYPE_BOOL:
		out.append(problem("error", file, rec, "skip", path + "/skip", "\"skip\" must be true or false.", ""))
	var cmd: RPGCommand = registry.get_command(type)
	if cmd == null:
		return out
	for p in cmd.validate(c):
		out.append(problem(p.get("severity", "error"), file, rec, str(p.get("field", "")), "%s/%s" % [path, p.get("field", "")], "%s: %s" % [cmd.desc.get("label", type), p.message], "Double-click the line to edit it."))
	for f in cmd.desc.get("fields", []):
		var k: String = f.get("key", "")
		if not c.has(k) or c[k] == null or not RPGCommand._visible(f, c):
			continue
		match str(f.get("kind", "")):
			"operand":
				_operand_structure(c[k], file, rec, "%s/%s" % [path, k], out)
			"facing":
				if not FACINGS.has(str(c[k])):
					out.append(problem("error", file, rec, k, "%s/%s" % [path, k], "Unknown facing '%s'." % c[k], "Use down, left, right, up or keep."))
			"ref":
				if typeof(c[k]) != TYPE_STRING:
					out.append(problem("error", file, rec, k, "%s/%s" % [path, k], "'%s' must be an ID." % f.get("label", k), ""))
	return out


# ============================================================================================
# Traversal: every typed reference in the project
# ============================================================================================

## Walks every file and returns {refs, locations, commands, texts, scripts, assets}.
##  refs:      {kind, id, file, record, field, path, holder, key, access: "read"|"set", hidden, map, is_key?}
##  locations: {map, position, file, record, path, hidden}
##  commands:  {cmd, file, record, path, map}
##  texts:     {holder, key, file, record, path}      (message text that may hold \V[id] codes)
##  scripts:   {holder, key, file, record, path}      (free-form strings: formulas, call_method...)
##  assets:    {kind, name, file, record, path, hidden}
static func traverse(files: Dictionary, registry: RPGCommandRegistry) -> Dictionary:
	var acc := {"refs": [], "locations": [], "commands": [], "texts": [], "scripts": [], "assets": []}
	var trait_map := trait_refs(files)
	for path in files:
		var entry: Dictionary = files[path]
		var d: Variant = entry.get("data")
		if not (d is Dictionary):
			continue
		var ctx := {"file": path, "record": "", "map": str(entry.get("map", "")), "hidden": false, "no_descend": false, "trait_refs": trait_map}
		match str(entry.get("kind", "")):
			"map":
				# A map's tileset is a reference to the Tilesets record.
				ctx.record = str(entry.get("map", d.get("id", "")))
				if d.has("tileset"):
					_add_ref(acc, ctx, "tileset", d, "tileset", "tileset", "read")
			"events":
				var evs: Variant = d.get("events", [])
				if not (evs is Array):
					continue
				for i in evs.size():
					var ev: Variant = evs[i]
					if ev is Dictionary:
						ctx.record = str(ev.get("id", ""))
						_event_refs(ev, "events/%d" % i, ctx, registry, acc)
			"common_events":
				var ces: Variant = d.get("common_events", [])
				if not (ces is Array):
					continue
				for i in ces.size():
					var ce: Variant = ces[i]
					if not (ce is Dictionary):
						continue
					ctx.record = str(ce.get("id", ""))
					var sw: Variant = ce.get("switch", "")
					if typeof(sw) == TYPE_STRING and sw != "":
						var hid := str(ce.get("trigger", "none")) == "none"
						_add_ref(acc, ctx, "switch", ce, "switch", "common_events/%d/switch" % i, "read", hid)
					_cmds(ce.get("commands", []), "common_events/%d/commands" % i, ctx, registry, acc)
			"database":
				_db_refs(str(entry.get("db_type", "")), d, ctx, registry, acc)
			"system":
				_system_refs(d, ctx, acc)
	return acc


static func _add_ref(acc: Dictionary, ctx: Dictionary, kind: String, holder: Variant, key: Variant, path: String, access: String, hidden := false, field := "") -> void:
	var id: Variant = holder[key]
	if typeof(id) != TYPE_STRING or id == "":
		return
	acc.refs.append({"kind": kind, "id": id, "file": ctx.file, "record": ctx.record, "field": field if field != "" else str(key),
		"path": path, "holder": holder, "key": key, "access": access, "hidden": hidden or ctx.hidden, "map": ctx.map})


static func _event_refs(ev: Dictionary, base: String, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	var pages: Variant = ev.get("pages", [])
	if not (pages is Array):
		return
	for j in pages.size():
		var pg: Variant = pages[j]
		if not (pg is Dictionary):
			continue
		var pp := "%s/pages/%d" % [base, j]
		page_refs(pg, pp, ctx, registry, acc)


static func page_refs(pg: Dictionary, pp: String, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	var conds: Variant = pg.get("conditions", [])
	if conds is Array:
		for k in conds.size():
			_cond_refs(conds[k], "%s/conditions/%d" % [pp, k], ctx, acc)
	var g: Variant = pg.get("graphic")
	if g is Dictionary and typeof(g.get("sheet")) == TYPE_STRING and g.sheet != "":
		acc.assets.append({"kind": "charset", "name": g.sheet, "file": ctx.file, "record": ctx.record, "path": pp + "/graphic/sheet", "hidden": ctx.hidden})
	var mv: Variant = pg.get("movement", {})
	if mv is Dictionary and mv.get("route") != null:
		_route_refs(mv.route, pp + "/movement/route", ctx, acc)
	_cmds(pg.get("commands", []), pp + "/commands", ctx, registry, acc)


static func _cmds(list: Variant, path: String, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	if not (list is Array):
		return
	for i in list.size():
		var c: Variant = list[i]
		if not (c is Dictionary):
			continue
		var cp := "%s/%d" % [path, i]
		acc.commands.append({"cmd": c, "file": ctx.file, "record": ctx.record, "path": cp, "map": ctx.map})
		var type := str(c.get("type", ""))
		var cmd: RPGCommand = registry.get_command(type) if registry != null else null
		if cmd == null:
			# Unknown or unavailable: kept as-is; its strings are only searched for renames.
			_script_strings(c, cp, ctx, acc)
			continue
		var sub := ctx.duplicate()
		sub["cmd_type"] = type
		_fields(cmd.desc.get("fields", []), c, cp, sub, registry, acc)


static func _fields(fields: Array, holder: Dictionary, path: String, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	for f in fields:
		var k: String = f.get("key", "")
		if k == "" or not holder.has(k):
			continue
		var sub := ctx
		if not RPGCommand._visible(f, holder) and not ctx.hidden:
			sub = ctx.duplicate()
			sub.hidden = true
		_field(f, fields, holder, k, path + "/" + k, sub, registry, acc)


static func _field(f: Dictionary, siblings: Array, holder: Variant, key: Variant, path: String, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	var v: Variant = holder[key]
	var ctype := str(ctx.get("cmd_type", ""))
	match str(f.get("kind", "")):
		"ref":
			if typeof(v) != TYPE_STRING or v == "" or f.get("allow", []).has(v):
				return
			var kind := str(f.get("ref", ""))
			if f.has("ref_from") and holder is Dictionary:
				var kv: Variant = holder.get(f.ref_from, _default_of(siblings, f.ref_from))
				kind = item_kind_to_ref(str(kv), kind)
			var access := "read"
			if SETTER_FIELDS.get(ctype, []).has(str(key)) or SETTER_KEYS.has(str(key)):
				access = "set"
			if kind == "event":
				return
			_add_ref(acc, ctx, kind, holder, key, path, access, false, str(f.get("key", key)))
		"location":
			if v is Dictionary:
				_add_ref(acc, ctx, "map", v, "map", path + "/map", "read", false, str(f.get("key", key)))
				acc.locations.append({"map": str(v.get("map", "")), "position": v.get("position"), "file": ctx.file, "record": ctx.record, "path": path, "hidden": ctx.hidden})
		"condition":
			_cond_refs(v, path, ctx, acc)
		"operand":
			if v is Dictionary and v.has("variable"):
				_add_ref(acc, ctx, "variable", v, "variable", path + "/variable", "read", false, str(f.get("key", key)))
		"operand_pair":
			if v is Array:
				for i in v.size():
					if v[i] is Dictionary and v[i].has("variable"):
						_add_ref(acc, ctx, "variable", v[i], "variable", "%s/%d/variable" % [path, i], "read", false, str(f.get("key", key)))
		"sound":
			if v is Dictionary and typeof(v.get("file")) == TYPE_STRING and v.file != "":
				acc.assets.append({"kind": str(f.get("res", "sound")), "also": f.get("res_also", []), "name": v.file, "file": ctx.file, "record": ctx.record, "path": path + "/file", "hidden": ctx.hidden})
		"resource":
			if typeof(v) == TYPE_STRING and v != "":
				acc.assets.append({"kind": str(f.get("res", "")), "name": v, "file": ctx.file, "record": ctx.record, "path": path, "hidden": ctx.hidden})
		"list":
			if v is Array:
				var item_fields: Array = f.get("item_fields", [])
				for i in v.size():
					if item_fields.is_empty() or f.has("item_kind"):
						if f.get("item_kind", "") == "condition":
							_cond_refs(v[i], "%s/%d" % [path, i], ctx, acc)
						elif SCRIPT_COMMANDS.has(ctype):
							if typeof(v[i]) == TYPE_STRING:
								acc.scripts.append({"holder": v, "key": i, "file": ctx.file, "record": ctx.record, "path": "%s/%d" % [path, i]})
							else:
								_script_strings(v[i], "%s/%d" % [path, i], ctx, acc)
					elif v[i] is Dictionary:
						_fields(item_fields, v[i], "%s/%d" % [path, i], ctx, registry, acc)
		"object":
			if v is Dictionary:
				if f.get("fields", []).is_empty():
					_script_strings(v, path, ctx, acc)
				else:
					_fields(f.fields, v, path, ctx, registry, acc)
		"commands":
			if not ctx.get("no_descend", false):
				var sub := ctx.duplicate()
				sub.erase("cmd_type")
				_cmds(v, path, sub, registry, acc)
		"route":
			_route_refs(v, path, ctx, acc)
		"text", "multiline":
			if typeof(v) == TYPE_STRING:
				if SCRIPT_COMMANDS.has(ctype):
					acc.scripts.append({"holder": holder, "key": key, "file": ctx.file, "record": ctx.record, "path": path})
				else:
					acc.texts.append({"holder": holder, "key": key, "file": ctx.file, "record": ctx.record, "path": path})


static func _default_of(fields: Array, key: String) -> Variant:
	for f in fields:
		if f.get("key", "") == key:
			return f.get("default")
	return null


## "items"/"item" -> "item", "weapons"/"weapon" -> "weapon", "armors"/"armor" -> "armor".
static func item_kind_to_ref(kind: String, fallback := "item") -> String:
	match kind:
		"items", "item": return "item"
		"weapons", "weapon": return "weapon"
		"armors", "armor", "armours", "armour": return "armor"
	return fallback


static func _cond_refs(c: Variant, path: String, ctx: Dictionary, acc: Dictionary) -> void:
	if not (c is Dictionary):
		return
	match str(c.get("kind", "")):
		"switch":
			_add_ref(acc, ctx, "switch", c, "id", path + "/id", "read", false, "condition")
		"variable":
			_add_ref(acc, ctx, "variable", c, "id", path + "/id", "read", false, "condition")
			var v: Variant = c.get("value")
			if v is Dictionary and v.has("variable"):
				_add_ref(acc, ctx, "variable", v, "variable", path + "/value/variable", "read", false, "condition")
		"item":
			_add_ref(acc, ctx, item_kind_to_ref(str(c.get("item_kind", "items"))), c, "id", path + "/id", "read", false, "condition")
		"actor", "actor_hp":
			_add_ref(acc, ctx, "actor", c, "id", path + "/id", "read", false, "condition")
			var check := str(c.get("check", "in_party"))
			if check in ["class", "skill", "weapon", "armor", "state"] and str(c.get(check, "")) != "":
				_add_ref(acc, ctx, check, c, check, path + "/" + check, "read", false, "condition")
		"gold":
			var g: Variant = c.get("value")
			if g is Dictionary and g.has("variable"):
				_add_ref(acc, ctx, "variable", g, "variable", path + "/value/variable", "read", false, "condition")
		"all", "any":
			var list: Variant = c.get("conditions", [])
			if list is Array:
				for i in list.size():
					_cond_refs(list[i], "%s/conditions/%d" % [path, i], ctx, acc)
		"not":
			_cond_refs(c.get("condition"), path + "/condition", ctx, acc)
		var other:
			# An extension's condition kind: its declared ref fields (switch, item, ...).
			var decl: Variant = RPGCommandRegistry.declared_condition_kinds.get(other)
			if decl is Dictionary:
				for f in decl.get("fields", []):
					if f is Dictionary and str(f.get("kind", "")) == "ref" and str(c.get(str(f.get("key", "")), "")) != "":
						_add_ref(acc, ctx, str(f.get("ref", "switch")), c, str(f.key), path + "/" + str(f.key), "read", false, "condition")


static func _route_refs(v: Variant, path: String, ctx: Dictionary, acc: Dictionary) -> void:
	var steps: Variant = v
	var base := path
	if v is Dictionary:
		steps = v.get("steps", [])
		base = path + "/steps"
	if not (steps is Array):
		return
	for i in steps.size():
		var s: Variant = steps[i]
		if not (s is Dictionary):
			continue
		var sp := "%s/%d" % [base, i]
		if s.has("switch"):
			_add_ref(acc, ctx, "switch", s, "switch", sp + "/switch", "set", false, "route")
		if s.get("sound") is Dictionary and typeof(s.sound.get("file")) == TYPE_STRING and s.sound.file != "":
			acc.assets.append({"kind": "sound", "name": s.sound.file, "file": ctx.file, "record": ctx.record, "path": sp + "/sound/file", "hidden": ctx.hidden})
		if s.get("graphic") is Dictionary and typeof(s.graphic.get("sheet")) == TYPE_STRING and s.graphic.sheet != "":
			acc.assets.append({"kind": "charset", "name": s.graphic.sheet, "file": ctx.file, "record": ctx.record, "path": sp + "/graphic/sheet", "hidden": ctx.hidden})


static func _script_strings(v: Variant, path: String, ctx: Dictionary, acc: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			if typeof(v[k]) == TYPE_STRING:
				acc.scripts.append({"holder": v, "key": k, "file": ctx.file, "record": ctx.record, "path": "%s/%s" % [path, k]})
			else:
				_script_strings(v[k], "%s/%s" % [path, k], ctx, acc)
	elif v is Array:
		for i in v.size():
			if typeof(v[i]) == TYPE_STRING:
				acc.scripts.append({"holder": v, "key": i, "file": ctx.file, "record": ctx.record, "path": "%s/%d" % [path, i]})
			else:
				_script_strings(v[i], "%s/%d" % [path, i], ctx, acc)


static func _db_refs(t: String, d: Dictionary, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	var recs: Variant = d.get("records", [])
	if not (recs is Array):
		return
	for i in recs.size():
		var r: Variant = recs[i]
		if not (r is Dictionary):
			continue
		ctx.record = str(r.get("id", ""))
		var base := "records/%d" % i
		match t:
			"actors":
				_add_ref(acc, ctx, "class", r, "class", base + "/class", "read")
				var eq: Variant = r.get("equips", {})
				if eq is Dictionary:
					for slot in eq:
						_add_ref(acc, ctx, "weapon" if slot == "weapon" else "armor", eq, slot, "%s/equips/%s" % [base, slot], "read", false, "equips")
				var sk: Variant = r.get("skills", [])
				if sk is Array:
					for j in sk.size():
						if typeof(sk[j]) == TYPE_STRING:
							_add_ref(acc, ctx, "skill", sk, j, "%s/skills/%d" % [base, j], "read", false, "skills")
			"classes":
				var ls: Variant = r.get("learnings", [])
				if ls is Array:
					for j in ls.size():
						if ls[j] is Dictionary:
							_add_ref(acc, ctx, "skill", ls[j], "skill", "%s/learnings/%d/skill" % [base, j], "read", false, "learnings")
			"enemies":
				var acts: Variant = r.get("actions", [])
				if acts is Array:
					for j in acts.size():
						if acts[j] is Dictionary and not ["attack", "guard", "wait", "escape"].has(str(acts[j].get("skill", ""))):
							_add_ref(acc, ctx, "skill", acts[j], "skill", "%s/actions/%d/skill" % [base, j], "read", false, "actions")
						var cond: Variant = acts[j].get("condition") if acts[j] is Dictionary else null
						if cond is Dictionary and str(cond.get("kind", "")) == "switch" and cond.has("id"):
							_add_ref(acc, ctx, "switch", cond, "id", "%s/actions/%d/condition/id" % [base, j], "read", false, "actions")
				var drops: Variant = r.get("drops", [])
				if drops is Array:
					for j in drops.size():
						if drops[j] is Dictionary:
							_add_ref(acc, ctx, item_kind_to_ref(str(drops[j].get("kind", "item"))), drops[j], "id", "%s/drops/%d/id" % [base, j], "read", false, "drops")
			"troops":
				var mem: Variant = r.get("members", [])
				if mem is Array:
					for j in mem.size():
						if mem[j] is Dictionary:
							_add_ref(acc, ctx, "enemy", mem[j], "enemy", "%s/members/%d/enemy" % [base, j], "read", false, "members")
				var pages: Variant = r.get("pages", [])
				if pages is Array:
					for j in pages.size():
						var pg: Variant = pages[j]
						if not (pg is Dictionary):
							continue
						var pp := "%s/pages/%d" % [base, j]
						for k in pg.get("conditions", []).size():
							_cond_refs(pg.conditions[k], "%s/conditions/%d" % [pp, k], ctx, acc)
						_cmds(pg.get("commands", []), pp + "/commands", ctx, registry, acc)
		_usable_refs(t, r, base, ctx, acc)
		_formula_strings(r, base, ctx, acc)
		_extension_field_refs(t, r, base, ctx, registry, acc)


## References inside fields extensions declare: every field of a record type an extension owns
## (manifest "database_types") and the extensions' custom fields (manifest "custom_fields") of
## any record, so ref checks and renames reach them too.
static func _extension_field_refs(t: String, r: Dictionary, base: String, ctx: Dictionary, registry: RPGCommandRegistry, acc: Dictionary) -> void:
	for d in RPGCommandRegistry.declared_database_types.values():
		if str(d.get("type", "")) == t:
			_fields(d.get("fields", []), r, base, ctx, registry, acc)
	if registry == null or not (r.get("custom") is Dictionary):
		return
	var ext_fields := []
	for f in registry.merged_custom_fields({}).get(t, []):
		if f is Dictionary and f.has("extension"):
			ext_fields.append(f)
	if not ext_fields.is_empty():
		_fields(ext_fields, r.custom, base + "/custom", ctx, registry, acc)


## References every kind of record may hold: trait and effect "Of" IDs (picked by kind) and the
## battle animation of skills, items and weapons (an Animations record or a built-in effect).
static func _usable_refs(t: String, r: Dictionary, base: String, ctx: Dictionary, acc: Dictionary) -> void:
	var trait_map: Dictionary = ctx.get("trait_refs", TRAIT_REFS)
	var tr: Variant = r.get("traits", [])
	if tr is Array:
		for j in tr.size():
			if tr[j] is Dictionary and tr[j].has("id"):
				var ref := str(trait_map.get(str(tr[j].get("kind", "")), ""))
				if DB_KIND.has(ref) or ref == "common_event":
					_add_ref(acc, ctx, ref, tr[j], "id", "%s/traits/%d/id" % [base, j], "read", false, "traits")
	var ef: Variant = r.get("effects", [])
	if ef is Array:
		for j in ef.size():
			if ef[j] is Dictionary and ef[j].has("id"):
				var ref2 := str(EFFECT_REFS.get(str(ef[j].get("kind", "")), ""))
				if DB_KIND.has(ref2) or ref2 == "common_event":
					_add_ref(acc, ctx, ref2, ef[j], "id", "%s/effects/%d/id" % [base, j], "read", false, "effects")
	if t in ["skills", "items", "weapons"] and r.has("animation"):
		var n: int = acc.refs.size()
		_add_ref(acc, ctx, "animation", r, "animation", base + "/animation", "read")
		if acc.refs.size() > n:
			# Not an Animations record: the battle falls back to a built-in effect (a warning).
			acc.refs[n]["fallback"] = true


## Trait kind -> what its "id" names ("state", "element", "stat"...; "" for none): TRAIT_REFS,
## overridden by the "id_ref" of the project's rule system traits (rules.json "traits").
static func trait_refs(files: Dictionary) -> Dictionary:
	var out := TRAIT_REFS.duplicate()
	for path in files:
		var e: Dictionary = files[path]
		if str(e.get("kind", "")) == "project" and e.get("data") is Dictionary:
			for td in rule_traits(str(path).get_base_dir(), str(e.data.get("rules", "classic"))):
				if td is Dictionary and td.has("kind"):
					out[str(td.kind)] = str(td.get("id_ref", ""))
	return out


static var _rule_traits_cache: Dictionary = {}


## The "traits" list of a rule system's rules.json (the project's copy first, then the shipped one).
static func rule_traits(root: String, rules_name: String) -> Array:
	var key := "%s|%s" % [root, rules_name]
	if _rule_traits_cache.has(key):
		return _rule_traits_cache[key]
	var out: Array = []
	for dir in [root.path_join("rules"), "res://rpg/rules", "res://addons/rpg/runtime/rules"]:
		var p: String = dir.path_join(rules_name).path_join("rules.json")
		if FileAccess.file_exists(p):
			var r := RPGJson.parse_file(p)
			if r.ok and r.data is Dictionary and r.data.get("traits") is Array:
				out = r.data.traits
			break
	_rule_traits_cache[key] = out
	return out


static func _formula_strings(v: Variant, path: String, ctx: Dictionary, acc: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			var x: Variant = v[k]
			if typeof(x) == TYPE_STRING and (str(k) == "formula" or str(k).ends_with("_formula")):
				acc.scripts.append({"holder": v, "key": k, "file": ctx.file, "record": ctx.record, "path": "%s/%s" % [path, k]})
			elif x is Dictionary or x is Array:
				_formula_strings(x, "%s/%s" % [path, k], ctx, acc)
	elif v is Array:
		for i in v.size():
			if v[i] is Dictionary or v[i] is Array:
				_formula_strings(v[i], "%s/%d" % [path, i], ctx, acc)


static func _system_refs(d: Dictionary, ctx: Dictionary, acc: Dictionary) -> void:
	var s: Variant = d.get("system", {})
	if not (s is Dictionary):
		return
	ctx.record = "system"
	var party: Variant = s.get("starting_party", [])
	if party is Array:
		for i in party.size():
			_add_ref(acc, ctx, "actor", party, i, "system/starting_party/%d" % i, "read", false, "starting_party")
	var items: Variant = s.get("starting_items", {})
	if items is Dictionary:
		for k in items:
			acc.refs.append({"kind": "item", "id": str(k), "file": ctx.file, "record": "system", "field": "starting_items",
				"path": "system/starting_items/%s" % k, "holder": items, "key": k, "access": "read", "hidden": false, "map": "", "is_key": true})
	var start: Variant = s.get("start", null)
	if start is Dictionary and start.has("map"):
		_add_ref(acc, ctx, "map", start, "map", "system/start/map", "read", false, "start")
		acc.locations.append({"map": str(start.map), "position": start.get("position"), "file": ctx.file, "record": "system", "path": "system/start", "hidden": false})


# ============================================================================================
# Registries (what exists)
# ============================================================================================

## kind -> {id: definition}. Built from the file set, falling back to the project data.
static func registries(files: Dictionary, data: RPGProjectData = null) -> Dictionary:
	var reg := {"switch": {}, "variable": {}, "map": {}, "common_event": {}, "event": {}, "map_size": {}}
	var kinds := db_kinds()
	for k in DB_KIND:
		reg[k] = {}
	if data != null:
		reg.switch = data.switches.duplicate()
		reg.variable = data.variables.duplicate()
		reg.map = data.maps.duplicate()
		reg.common_event = data.common_events.duplicate()
		# Extension record kinds are checked only when their records are loaded.
		for k in kinds:
			if data.db.has(kinds[k]):
				reg[k] = data.db[kinds[k]].by_id.duplicate()
	for path in files:
		var e: Dictionary = files[path]
		var d: Variant = e.get("data")
		if not (d is Dictionary):
			continue
		match str(e.get("kind", "")):
			"state":
				reg.switch = _by_id(d.get("switches", []))
				reg.variable = _by_id(d.get("variables", []))
			"map_index":
				reg.map = _by_id(d.get("maps", []))
			"common_events":
				reg.common_event = _by_id(d.get("common_events", []))
			"database":
				var t := str(e.get("db_type", ""))
				for k in kinds:
					if kinds[k] == t:
						reg[k] = _by_id(d.get("records", []))
			"events":
				for ev in d.get("events", []):
					if ev is Dictionary:
						reg.event["%s/%s" % [e.get("map", ""), ev.get("id", "")]] = ev
			"map":
				reg.map_size[str(e.get("map", ""))] = Vector2i(int(d.get("width", 20)), int(d.get("height", 15)))
	return reg


static func _by_id(list: Variant) -> Dictionary:
	var out := {}
	if list is Array:
		for r in list:
			if r is Dictionary and r.has("id"):
				out[str(r.id)] = r
	return out


static func _map_size(reg: Dictionary, data: RPGProjectData, map_id: String) -> Vector2i:
	if reg.map_size.has(map_id):
		return reg.map_size[map_id]
	if data != null and data.maps.has(map_id):
		return data.map_size(map_id)
	return Vector2i(20, 15)


# ============================================================================================
# Level 2: references
# ============================================================================================

## Looks assets up in the project's packs (RPGAssets) or by res:// path. Kinds RPGAssets does not
## know are assumed present, so extension-specific kinds never raise false warnings.
static func default_asset_resolver() -> Callable:
	return func(kind: String, asset_name: Variant) -> bool:
		var n := str(asset_name)
		if n == "" or n == "<null>":
			return true
		if n.begins_with("res://") or n.begins_with("user://"):
			return ResourceLoader.exists(n) or FileAccess.file_exists(n)
		if not RPGAssets.kinds().has(kind):
			return true
		return RPGAssets.find(kind, n) != ""


## Checks IDs, transfer destinations and links between files. `asset_resolver` (optional):
## (kind: String, name: String) -> bool, true when the asset exists.
static func references(data: RPGProjectData, registry: RPGCommandRegistry, files: Dictionary = {}, asset_resolver: Callable = Callable()) -> Array:
	if files.is_empty():
		files = collect_files(data)
	var acc := traverse(files, registry)
	var reg := registries(files, data)
	return _reference_problems(acc, reg, data, registry, asset_resolver, false)


static func _reference_problems(acc: Dictionary, reg: Dictionary, data: RPGProjectData, registry: RPGCommandRegistry, asset_resolver: Callable, full_level: bool) -> Array:
	var out := []
	for r in acc.refs:
		if r.hidden:
			continue
		var kind: String = r.kind
		if not reg.has(kind):
			continue
		if not reg[kind].has(r.id):
			if r.get("fallback", false):
				# An animation name that is no Animations record plays a built-in effect.
				if BUILTIN_ANIMATIONS.has(str(r.id)):
					continue
				var fp := problem("warning", r.file, r.record, r.field, r.path,
					"Animation '%s' is not in Animations, so the battle shows the built-in '%s' effect instead." % [r.id, RPGBattleEffects.builtin_for(str(r.id))],
					"Pick an Animations record or a built-in effect (hit, slash, fire, ice, thunder, heal).")
				fp["ref_kind"] = kind
				fp["ref_id"] = r.id
				out.append(fp)
				continue
			var label: String = KIND_LABEL.get(kind, kind.capitalize())
			var mp := problem("error", r.file, r.record, r.field, r.path,
				"%s '%s' does not exist." % [label, r.id],
				FIX_HINT.get(kind, "Pick an existing %s, or add '%s' in the Database." % [label.to_lower(), r.id]))
			# Lets a Database tab list the dangling references to its own kind of record.
			mp["ref_kind"] = kind
			mp["ref_id"] = r.id
			out.append(mp)
	for l in acc.locations:
		if l.hidden or not reg.map.has(l.map):
			continue
		var pos: Variant = l.position
		if not (pos is Array) or pos.size() != 2:
			out.append(problem("error", l.file, l.record, "position", l.path, "The destination on map '%s' has no valid cell." % l.map, "Pick the cell again."))
			continue
		var size := _map_size(reg, data, l.map)
		var x := int(pos[0])
		var y := int(pos[1])
		if x < 0 or y < 0 or x >= size.x or y >= size.y:
			out.append(problem("error", l.file, l.record, "position", l.path,
				"The destination (%d, %d) is outside map '%s', which is %d x %d tiles." % [x, y, l.map, size.x, size.y],
				"Pick a cell inside the map."))
	# Variable comparisons on true/false or text variables only allow = and !=.
	for r in acc.refs:
		if r.kind == "variable" and r.field == "condition" and r.key == "id" and r.holder is Dictionary and reg.variable.has(r.id):
			var t := str(reg.variable[r.id].get("type", "int"))
			var op := str(r.holder.get("op", "=="))
			if (t == "bool" or t == "string") and not EQ_OPS.has(op):
				out.append(problem("error", r.file, r.record, "condition", r.path.get_base_dir() + "/op",
					"Variable '%s' holds %s, so it can only be compared with = or ≠." % [r.id, "true/false" if t == "bool" else "text"],
					"Change the comparison to = or ≠."))
	for c in acc.commands:
		var type := str(c.cmd.get("type", ""))
		if registry == null or registry.has_command(type):
			continue
		var unavailable := registry.unavailable.has(type)
		var reason := registry.unavailable_reason(type)
		var msg := ""
		var hint := ""
		if unavailable:
			msg = "Command '%s' comes from an extension that is turned off (%s). It is kept, but cannot run." % [type, reason]
			hint = "Turn the extension on in Tools > Extensions, or delete the command."
		else:
			msg = "Unknown command '%s' (%s). It is kept as-is and flagged." % [type, reason]
			hint = "Install the extension that provides it, or delete the command."
		var p := problem("error" if full_level else "warning", c.file, c.record, "type", c.path, msg, hint)
		if full_level:
			p["blocks_export"] = true
		out.append(p)
	if asset_resolver.is_valid():
		for a in acc.assets:
			if a.hidden or a.kind == "scene":
				continue
			var found := bool(asset_resolver.call(a.kind, a.name))
			# Fields that also accept other kinds (a jingle may be a sound effect file).
			for k in a.get("also", []):
				if not found:
					found = bool(asset_resolver.call(str(k), a.name))
			if not found:
				# Spec: missing assets show placeholders while editing, but block release export.
				var ap := problem("error" if full_level else "warning", a.file, a.record, a.kind, a.path, "The %s '%s' was not found. A placeholder is shown." % [a.kind, a.name], "Import the asset or pick another one.")
				if full_level:
					ap["blocks_export"] = true
				out.append(ap)
	for a in acc.assets:
		if a.kind == "scene" and not a.hidden and str(a.name).begins_with("res://") and not ResourceLoader.exists(a.name):
			out.append(problem("error", a.file, a.record, "scene", a.path, "The scene '%s' does not exist." % a.name, "Pick an existing scene."))
	return out


## Reference problems for one command line (own fields only), for the editor's warning icons.
static func command_problems(cmd: Dictionary, data: RPGProjectData, registry: RPGCommandRegistry, map_id := "", files: Dictionary = {}, reg: Dictionary = {}) -> Array:
	var out := command_structure(cmd, registry)
	if registry != null and not registry.has_command(str(cmd.get("type", ""))):
		var t := str(cmd.get("type", ""))
		if registry.unavailable.has(t):
			out.append(problem("error", "", "", "type", "", "Command '%s' comes from a disabled extension (%s). It is kept but cannot run." % [t, registry.unavailable_reason(t)], "Turn the extension on, or delete the line."))
		else:
			out.append(problem("warning", "", "", "type", "", "Unknown command '%s'. It is kept as-is." % t, "Install the extension that provides it."))
		return out
	var acc := {"refs": [], "locations": [], "commands": [], "texts": [], "scripts": [], "assets": []}
	var ctx := {"file": "", "record": "", "map": map_id, "hidden": false, "no_descend": true}
	_cmds([cmd], "", ctx, registry, acc)
	if reg.is_empty():
		reg = registries(files, data)
	for p in _reference_problems(acc, reg, data, registry, Callable(), false):
		if p.field != "type":
			out.append(p)
	return out


# ============================================================================================
# Level 3: full project
# ============================================================================================

static func full(data: RPGProjectData, registry: RPGCommandRegistry, files: Dictionary = {}, asset_resolver: Callable = Callable()) -> Array:
	if files.is_empty():
		files = collect_files(data)
	if not asset_resolver.is_valid():
		asset_resolver = default_asset_resolver()
	var out := []
	for e in data.load_errors:
		out.append(problem("error", str(e.get("file", "")), "", "", "", str(e.get("message", "")), "Fix the file, or restore it from the .bak copy."))
	if registry != null:
		for p in registry.problems:
			var pr := problem("error", str(p.get("file", "")), "", "", "", str(p.get("message", "")), "Check the extension in Tools > Extensions.")
			pr["blocks_export"] = true
			out.append(pr)
	for path in files:
		var e: Dictionary = files[path]
		var kind := str(e.get("kind", ""))
		if kind == "database":
			kind = "database:" + str(e.get("db_type", ""))
		out.append_array(structure(kind, e.get("data"), registry, path))
		if e.get("kind", "") == "events" and e.get("data") is Dictionary:
			var m: Variant = e.data.get("map", "")
			if typeof(m) == TYPE_STRING and m != "" and m != e.get("map", ""):
				out.append(problem("warning", path, "", "map", "map", "This events file says it belongs to map '%s', but the map index uses it for '%s'." % [m, e.get("map", "")], "Fix the \"map\" field."))
	var acc := traverse(files, registry)
	var reg := registries(files, data)
	out.append_array(_reference_problems(acc, reg, data, registry, asset_resolver, true))
	# Autorun common events need a switch.
	for path in files:
		var e2: Dictionary = files[path]
		if e2.get("kind", "") == "common_events" and e2.get("data") is Dictionary:
			var ces: Variant = e2.data.get("common_events", [])
			if ces is Array:
				for i in ces.size():
					var ce: Variant = ces[i]
					if ce is Dictionary and str(ce.get("trigger", "none")) != "none" and str(ce.get("switch", "")) == "":
						out.append(problem("warning", path, str(ce.get("id", "")), "switch", "common_events/%d/switch" % i,
							"Common event '%s' runs as %s but has no condition switch, so it always runs." % [ce.get("id", ""), ce.get("trigger")],
							"Pick a condition switch."))
	out.append_array(database_values(files))
	out.append_array(image_map_problems(files, data))
	return out


## Image-backed maps: missing, unreadable, misaligned, oversized or mismatched images, and a map
## size that no longer matches its base image (RPGImageMap). Errors block playtest and export.
static func image_map_problems(files: Dictionary, data: RPGProjectData) -> Array:
	var out := []
	if data == null:
		return out
	var lim := RPGImageMap.limits(data)
	for path in files:
		var e: Dictionary = files[path]
		if e.get("kind", "") == "map" and e.get("data") is Dictionary:
			out.append_array(RPGImageMap.problems_for(str(e.get("map", "")), e.data, path, data.tile_size(), lim))
	return out


## Database fields whose value is an entry of a Types list (types.json record -> fields).
const TYPED_FIELDS := {
	"skills": {"skill_type": "skill_types", "element": "elements"},
	"weapons": {"weapon_type": "weapon_types"},
	"armors": {"armor_type": "armor_types", "slot": "equip_slots"},
}


## Every place a database record names an entry of a Types list:
## [{list, id, holder, key, file, record, field, path, is_key}]. Used by the checks below and by
## rename_type_entry(), so both see the same references.
static func type_refs(files: Dictionary) -> Array:
	var out := []
	var trait_map := trait_refs(files)
	for path in files:
		var e: Dictionary = files[path]
		if e.get("kind", "") != "database" or not (e.get("data") is Dictionary) or not (e.data.get("records") is Array):
			continue
		var t := str(e.get("db_type", ""))
		var recs: Array = e.data.records
		for i in recs.size():
			var r: Variant = recs[i]
			if not (r is Dictionary):
				continue
			var rec := str(r.get("id", ""))
			var base := "records/%d" % i
			var typed: Dictionary = TYPED_FIELDS.get(t, {})
			for key in typed:
				if r.has(key):
					_type_ref(out, typed[key], r, key, path, rec, key, "%s/%s" % [base, key])
			if t == "classes" and r.get("equip") is Dictionary:
				for key in ["weapon_types", "armor_types"]:
					var vals: Variant = r.equip.get(key, [])
					if vals is Array:
						for j in vals.size():
							_type_ref(out, key, vals, j, path, rec, "equip", "%s/equip/%s/%d" % [base, key, j])
			if t == "actors" and r.get("equips") is Dictionary:
				for slot in r.equips.keys():
					_type_ref(out, "equip_slots", r.equips, slot, path, rec, "equips", "%s/equips/%s" % [base, slot], true)
			if t == "types" and rec == "equip_slots" and r.get("entries") is Array:
				for k in r.entries.size():
					var en: Variant = r.entries[k]
					if en is Dictionary and en.get("armor_types") is Array:
						for j in en.armor_types.size():
							_type_ref(out, "armor_types", en.armor_types, j, path, rec, "entries", "%s/entries/%d/armor_types/%d" % [base, k, j])
			var tr: Variant = r.get("traits", [])
			if tr is Array:
				for j in tr.size():
					if tr[j] is Dictionary and tr[j].has("id"):
						var list := str(TYPE_LISTS.get(str(trait_map.get(str(tr[j].get("kind", "")), "")), ""))
						if list != "":
							_type_ref(out, list, tr[j], "id", path, rec, "traits", "%s/traits/%d/id" % [base, j])
	return out


static func _type_ref(out: Array, list: String, holder: Variant, key: Variant, file: String, rec: String, field: String, path: String, is_key := false) -> void:
	var id: Variant = key if is_key else holder[key]
	if typeof(id) == TYPE_STRING and id != "":
		out.append({"list": list, "id": id, "holder": holder, "key": key, "file": file, "record": rec, "field": field, "path": path, "is_key": is_key})


## The Types lists of a file set: {list id: {ids: {id: entry}, name, entries}}.
static func type_lists(files: Dictionary) -> Dictionary:
	var lists := {}
	for path in files:
		var e: Dictionary = files[path]
		if e.get("kind", "") == "database" and e.get("db_type", "") == "types" and e.get("data") is Dictionary:
			for r in e.data.get("records", []):
				if r is Dictionary and r.get("entries") is Array:
					var ids := {}
					for en in r.entries:
						if en is Dictionary and en.has("id"):
							ids[str(en.id)] = en
					lists[str(r.get("id", ""))] = {"ids": ids, "name": str(r.get("name", r.get("id", ""))), "entries": r.entries}
	return lists


## Why `item` (a weapon or armour record; `kind` "weapon" or "armor") cannot start in equipment
## slot `slot_id` of an actor of class `class_rec` ("" when it can). `slot` is the slot's Types
## entry ({kind, armor_types}; may be empty). Same rules as the game's Equip screen: the slot
## holds weapons or armour, an armour's own slot, the slot's armour types and the class's
## "Can equip" types.
static func equip_problem(slot_id: String, slot: Dictionary, kind: String, item: Dictionary, class_rec: Dictionary) -> String:
	if item.is_empty():
		return ""
	var slot_kind := str(slot.get("kind", "weapon" if slot_id == "weapon" else "armor"))
	var allowed: Variant = class_rec.get("equip")
	var cls := str(class_rec.get("name", class_rec.get("id", "")))
	if kind == "weapon" or slot_kind == "weapon":
		if kind != "weapon":
			return "the %s slot holds weapons." % slot_id
		var wt := str(item.get("weapon_type", ""))
		if allowed is Dictionary and not (allowed.get("weapon_types", []) as Array).has(wt):
			return "class %s cannot equip weapon type '%s' (Classes > Can equip)." % [cls, wt]
		return ""
	var rs := str(item.get("slot", ""))
	if rs != "" and rs != slot_id:
		return "this armour goes in the %s slot, not %s." % [rs, slot_id]
	var at := str(item.get("armor_type", ""))
	if rs == "" and slot.get("armor_types") is Array and not slot.armor_types.is_empty() and not slot.armor_types.has(at):
		return "the %s slot does not take armour type '%s'." % [slot_id, at]
	if allowed is Dictionary and not (allowed.get("armor_types", []) as Array).has(at):
		return "class %s cannot equip armour type '%s' (Classes > Can equip)." % [cls, at]
	return ""


## Values inside database records: damage formulas that do not compile, types or elements that
## types.json does not list (checked only when types.json has that list), Types entry IDs,
## starting equipment that breaks the equipment rules, state durations, animations that show
## nothing, and tileset sheets that do not exist.
static func database_values(files: Dictionary) -> Array:
	var out := []
	var lists := type_lists(files)
	for tr in type_refs(files):
		var list: Dictionary = lists.get(tr.list, {})
		if list.is_empty() or list.ids.has(tr.id):
			continue
		out.append(problem("warning", tr.file, tr.record, tr.field, tr.path,
			"'%s' is not in Types > %s." % [tr.id, list.name], "Pick one from the list, or add '%s' in Types > %s." % [tr.id, list.name]))
	var by_type := {}
	for path in files:
		var e: Dictionary = files[path]
		if e.get("kind", "") == "database" and e.get("data") is Dictionary:
			by_type[str(e.get("db_type", ""))] = _by_id(e.data.get("records", []))
	var slots: Dictionary = lists.get("equip_slots", {}).get("ids", {})
	for path in files:
		var e: Dictionary = files[path]
		if e.get("kind", "") != "database" or not (e.get("data") is Dictionary):
			continue
		var recs: Variant = e.data.get("records", [])
		if not (recs is Array):
			continue
		var t := str(e.get("db_type", ""))
		for i in recs.size():
			var r: Variant = recs[i]
			if not (r is Dictionary):
				continue
			var rec := str(r.get("id", ""))
			var base := "records/%d" % i
			match t:
				"types":
					_type_entry_problems(r, path, rec, base, out)
				"actors":
					var eq: Variant = r.get("equips", {})
					var cls: Dictionary = by_type.get("classes", {}).get(str(r.get("class", "")), {})
					if eq is Dictionary:
						for slot in eq:
							var item_id := str(eq[slot]) if eq[slot] != null else ""
							if item_id == "":
								continue
							var slot_entry: Dictionary = slots.get(str(slot), {})
							var kind := "weapon" if str(slot_entry.get("kind", "weapon" if slot == "weapon" else "armor")) == "weapon" else "armor"
							var item: Dictionary = by_type.get(DB_KIND[kind], {}).get(item_id, {})
							var why := equip_problem(str(slot), slot_entry, kind, item, cls)
							if why != "":
								out.append(problem("warning", path, rec, "equips", "%s/equips/%s" % [base, slot],
									"Starting equipment '%s' in the %s slot: %s" % [item_id, slot, why], "Pick an item that fits the slot and the class."))
				"armors":
					var s := str(r.get("slot", ""))
					var se: Dictionary = slots.get(s, {})
					if s != "" and str(se.get("kind", "weapon" if s == "weapon" else "armor")) == "weapon":
						out.append(problem("warning", path, rec, "slot", base + "/slot",
							"Armour '%s' is set to the %s slot, which holds weapons." % [rec, s], "Pick an armour slot (shield, body, accessory...)."))
				"states":
					var lo: Variant = r.get("turns_min")
					var hi: Variant = r.get("turns_max")
					if typeof(lo) in [TYPE_INT, TYPE_FLOAT] and typeof(hi) in [TYPE_INT, TYPE_FLOAT] and float(lo) > float(hi):
						out.append(problem("error", path, rec, "turns_min", base + "/turns_min",
							"State '%s' lasts at least %d turns but at most %d." % [rec, int(lo), int(hi)], "Make 'at least' no more than 'at most'."))
					_state_walk_problems(r, path, rec, base, out)
				"animations":
					var flashes: Variant = r.get("flashes", [])
					var sounds: Variant = r.get("sounds", [])
					if str(r.get("sheet", "")) == "" and not (flashes is Array and not flashes.is_empty()) and not (sounds is Array and not sounds.is_empty()):
						out.append(problem("warning", path, rec, "sheet", base + "/sheet",
							"Animation '%s' has no sprite sheet, flashes or sounds, so battles show a built-in effect chosen by its ID instead." % rec,
							"Pick a sprite sheet (Picture folder; add one with Tools > Resources > Import)."))
				"tilesets":
					for sp in tileset_sheet_paths(r):
						var p := str(sp[1])
						if p != "" and not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
							out.append(problem("error", path, rec, "sheet", "%s/%s" % [base, sp[0]],
								"Tileset '%s': the sheet '%s' does not exist." % [rec, p], "Pick an existing image for the sheet."))
			_formula_problems(r, base, path, rec, out)
	return out


## Types entries: IDs follow the record ID rules and are unique within their list.
static func _type_entry_problems(r: Dictionary, path: String, rec: String, base: String, out: Array) -> void:
	var seen := {}
	var entries: Variant = r.get("entries", [])
	if not (entries is Array):
		return
	var list_name := str(r.get("name", rec))
	for k in entries.size():
		var en: Variant = entries[k]
		var eid: Variant = en.get("id") if en is Dictionary else null
		if not RPGIds.is_valid(eid):
			out.append(problem("error", path, rec, "entries", "%s/entries/%d/id" % [base, k],
				"The ID '%s' in Types > %s is not valid. IDs use lowercase letters, digits and _, and start with a letter." % [eid, list_name],
				"Use e.g. '%s' (Rename entry ID updates the records that use it)." % RPGIds.slug(str(eid if eid != null else "entry"))))
		elif seen.has(eid):
			out.append(problem("error", path, rec, "entries", "%s/entries/%d/id" % [base, k],
				"The ID '%s' is used twice in Types > %s." % [eid, list_name], "Give one of them another ID."))
		else:
			seen[eid] = true


## States and map walking: "remove_by_walking" with a whole number of steps (at least 1), and a
## "map_hp_change" with a known effect and kind, an amount of 0 or more and steps of at least 1.
static func _state_walk_problems(r: Dictionary, path: String, rec: String, base: String, out: Array) -> void:
	var rbw: Variant = r.get("remove_by_walking", false)
	if typeof(rbw) != TYPE_BOOL:
		out.append(problem("error", path, rec, "remove_by_walking", base + "/remove_by_walking",
			"State '%s': 'Removed by walking' must be true or false." % rec, "Tick or untick Removed by walking."))
	elif rbw:
		var n: Variant = r.get("steps_to_remove")
		if not _is_whole(n) or int(n) < 1:
			out.append(problem("error", path, rec, "steps_to_remove", base + "/steps_to_remove",
				"State '%s' is removed by walking, but its steps to remove (%s) are not a whole number of at least 1." % [rec, n],
				"Set Steps to remove to 1 or more."))
	var c: Variant = r.get("map_hp_change")
	if c == null or (c is Dictionary and c.is_empty()):
		return
	if not (c is Dictionary):
		out.append(problem("error", path, rec, "map_hp_change", base + "/map_hp_change",
			"State '%s': 'Change while walking' must be an object." % rec, "Turn Change while walking off and on again."))
		return
	if not str(c.get("effect", "damage")) in ["damage", "recover"]:
		out.append(problem("error", path, rec, "map_hp_change", base + "/map_hp_change/effect",
			"State '%s': the change while walking has an unknown effect '%s'." % [rec, c.get("effect")], "Pick Damage or Recover."))
	if not str(c.get("kind", "flat")) in ["flat", "percent"]:
		out.append(problem("error", path, rec, "map_hp_change", base + "/map_hp_change/kind",
			"State '%s': the change while walking has an unknown kind '%s'." % [rec, c.get("kind")], "Pick a fixed amount or % of maximum."))
	var v: Variant = c.get("value", 0)
	if not _is_whole(v) or int(v) < 0:
		out.append(problem("error", path, rec, "map_hp_change", base + "/map_hp_change/value",
			"State '%s': the change while walking needs an amount of 0 or more (got %s)." % [rec, v], "Set Amount to a whole number."))
	elif str(c.get("kind", "flat")) == "percent" and int(v) > 100:
		out.append(problem("warning", path, rec, "map_hp_change", base + "/map_hp_change/value",
			"State '%s': the change while walking is %d%% of the maximum, more than all of it." % [rec, int(v)], "Use 100 or less."))
	var st: Variant = c.get("steps", 1)
	if not _is_whole(st) or int(st) < 1:
		out.append(problem("error", path, rec, "map_hp_change", base + "/map_hp_change/steps",
			"State '%s': the change while walking needs a step count of at least 1 (got %s)." % [rec, st], "Set Every N steps to 1 or more."))


## System options for map walking: "slip_death" is true or false, "damage_floor" a whole number
## of 0 or more.
static func _system_walk_problems(s: Dictionary, file: String, out: Array) -> void:
	if s.has("slip_death") and typeof(s.slip_death) != TYPE_BOOL:
		out.append(problem("error", file, "system", "slip_death", "system/slip_death",
			"System 'Knockout by slip damage' must be true or false.", "Tick or untick it in the System tab."))
	if s.has("damage_floor") and (not _is_whole(s.damage_floor) or int(s.damage_floor) < 0):
		out.append(problem("error", file, "system", "damage_floor", "system/damage_floor",
			"System 'Damage floor' must be a whole number of 0 or more (got %s)." % [s.damage_floor], "Set it in the System tab."))


static func _is_whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_equal_approx(v, roundf(v)))


## [[field path, res:// path], ...] of every image a tileset record names (sheet, XP autotiles,
## VX/MV sheets).
static func tileset_sheet_paths(r: Dictionary) -> Array:
	var out := []
	if typeof(r.get("sheet")) == TYPE_STRING:
		out.append(["sheet", r.sheet])
	if r.get("autotiles") is Array:
		for j in r.autotiles.size():
			if typeof(r.autotiles[j]) == TYPE_STRING:
				out.append(["autotiles/%d" % j, r.autotiles[j]])
	if r.get("sheets") is Dictionary:
		for k in r.sheets:
			if typeof(r.sheets[k]) == TYPE_STRING:
				out.append(["sheets/%s" % k, r.sheets[k]])
	return out


static func _formula_problems(v: Variant, path: String, file: String, rec: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			var x: Variant = v[k]
			if typeof(x) == TYPE_STRING and (str(k) == "formula" or str(k).ends_with("_formula")):
				if x.strip_edges() == "":
					continue
				var err := RPGFormula.check(x)
				if err != "":
					out.append(problem("error", file, rec, str(k), "%s/%s" % [path, k],
						"The formula '%s' of '%s' does not work: %s." % [x, rec, err], "Fix the formula; Test shows what it gives."))
			elif x is Dictionary or x is Array:
				_formula_problems(x, "%s/%s" % [path, k], file, rec, out)
	elif v is Array:
		for i in v.size():
			if v[i] is Dictionary or v[i] is Array:
				_formula_problems(v[i], "%s/%d" % [path, i], file, rec, out)


static func blocks_export(problems: Array) -> bool:
	for p in problems:
		if p.get("blocks_export", false):
			return true
	return false


static func count(problems: Array, severity := "error") -> int:
	var n := 0
	for p in problems:
		if p.get("severity", "") == severity:
			n += 1
	return n


# ============================================================================================
# Used by
# ============================================================================================

## Where an ID is read or set: [{file, record, path, field, access, map}].
## kind: switch, variable, item, weapon, armor, actor, common_event, map, ...
static func used_by(data: RPGProjectData, registry: RPGCommandRegistry, kind: String, id: String, files: Dictionary = {}) -> Array:
	if files.is_empty():
		files = collect_files(data)
	var acc := traverse(files, registry)
	var out := []
	for r in acc.refs:
		if r.kind == kind and r.id == id:
			out.append({"file": r.file, "record": r.record, "path": r.path, "field": r.field, "access": r.access, "map": r.map})
	var code := _text_code_for(kind)
	if code != "":
		for t in acc.texts:
			var s := str(t.holder[t.key])
			if s.findn("\\%s[%s]" % [code, id]) != -1:
				out.append({"file": t.file, "record": t.record, "path": t.path, "field": str(t.key), "access": "read", "map": ""})
	return out


static func _text_code_for(kind: String) -> String:
	match kind:
		"variable": return "V"
		"switch": return "S"
		"actor": return "N"
	return ""


# ============================================================================================
# Rename
# ============================================================================================

## Renames an ID and every typed reference to it, as one transaction.
## kind: switch, variable, map, common_event, actor, class, skill, item, weapon, armor, enemy,
## troop, state, animation, tileset, or "event" (old = "map_id/event_id", new = new event ID).
## The old ID goes into the defining file's "retired_ids" (never reused, like a deleted ID), and
## a retired ID is refused as the new one. (Map IDs have no retired list.)
## Returns {ok, error, changes: [{file, path}], warnings: [{file, path, message}],
##          data_by_file: {path: new file data}} -- only changed files are listed.
static func rename_id(data: RPGProjectData, registry: RPGCommandRegistry, kind: String, old: String, new: String, files: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "error": "", "changes": [], "warnings": [], "data_by_file": {}}
	if files.is_empty():
		files = collect_files(data)
	var copy := {}
	for p in files:
		var e: Dictionary = files[p].duplicate()
		e.data = RPGJson.deep_copy(e.get("data"))
		copy[p] = e
	var reg := registries(copy, data)
	var map_of_event := ""
	var old_id := old
	if kind == "event":
		var parts := old.split("/")
		if parts.size() != 2:
			res.error = "Event renames need old = \"map_id/event_id\"."
			return res
		map_of_event = parts[0]
		old_id = parts[1]
		if not reg.event.has(old):
			res.error = "Event '%s' does not exist on map '%s'." % [old_id, map_of_event]
			return res
		if reg.event.has("%s/%s" % [map_of_event, new]):
			res.error = "Map '%s' already has an event '%s'." % [map_of_event, new]
			return res
	else:
		if not reg.has(kind):
			res.error = "Unknown ID kind '%s'." % kind
			return res
		if not reg[kind].has(old):
			res.error = "%s '%s' does not exist." % [KIND_LABEL.get(kind, kind), old]
			return res
		if reg[kind].has(new):
			res.error = "%s '%s' already exists." % [KIND_LABEL.get(kind, kind), new]
			return res
	if not RPGIds.is_valid(new):
		res.error = "'%s' is not a valid ID. Use lowercase letters, digits and _, starting with a letter." % new
		return res
	if old_id == new:
		res.ok = true
		return res
	var changed := {}
	var change := func(file: String, path: String) -> void:
		res.changes.append({"file": file, "path": path})
		changed[file] = true
	# IDs are never reused: the file that defines the ID retires the old one (as a delete does),
	# and a retired ID cannot come back through a rename -- except to the record that had it:
	# "renamed_ids" ({old: new}) follows each record's renames, so a rename can be taken back.
	var retire := func(file: String, d: Dictionary) -> bool:
		if not (d.get("retired_ids") is Array):
			d["retired_ids"] = []
		var renamed: Dictionary = d.renamed_ids if d.get("renamed_ids") is Dictionary else {}
		if d.retired_ids.has(new):
			if rename_chain_end(renamed, new) != old_id:
				res.error = "'%s' was used before and deleted or renamed; IDs are never reused. Choose another ID." % new
				return false
			d.retired_ids.erase(new)
			renamed.erase(new)
		if not d.retired_ids.has(old_id):
			d.retired_ids.append(old_id)
		renamed[old_id] = new
		d["renamed_ids"] = renamed
		change.call(file, "retired_ids")
		return true
	# 1. The definition itself.
	for p in copy:
		var e: Dictionary = copy[p]
		var d: Variant = e.data
		if not (d is Dictionary):
			continue
		match str(e.get("kind", "")):
			"state":
				if kind == "switch" or kind == "variable":
					var key := "switches" if kind == "switch" else "variables"
					var list: Array = d.get(key, [])
					for i in list.size():
						if list[i] is Dictionary and list[i].get("id") == old:
							list[i].id = new
							change.call(p, "%s/%d/id" % [key, i])
							if not retire.call(p, d):
								return res
			"map_index":
				if kind == "map":
					var maps: Array = d.get("maps", [])
					for i in maps.size():
						var m: Variant = maps[i]
						if not (m is Dictionary):
							continue
						if m.get("id") == old:
							# Keep the existing files reachable: write their paths explicitly.
							var root := data.root if data != null else "res://rpg"
							for pk in [["scene", "maps/%s.tscn"], ["properties", "maps/%s.map.json"], ["events", "maps/%s.events.json"]]:
								if not m.has(pk[0]):
									m[pk[0]] = root.path_join(pk[1] % old)
							m.id = new
							change.call(p, "maps/%d/id" % i)
						if m.get("parent") == old:
							m.parent = new
							change.call(p, "maps/%d/parent" % i)
			"common_events":
				if kind == "common_event":
					var ces: Array = d.get("common_events", [])
					for i in ces.size():
						if ces[i] is Dictionary and ces[i].get("id") == old:
							ces[i].id = new
							change.call(p, "common_events/%d/id" % i)
							if not retire.call(p, d):
								return res
			"database":
				if db_kinds().get(kind, "") == str(e.get("db_type", "")):
					var recs: Array = d.get("records", [])
					for i in recs.size():
						if recs[i] is Dictionary and recs[i].get("id") == old:
							recs[i].id = new
							change.call(p, "records/%d/id" % i)
							if not retire.call(p, d):
								return res
			"events":
				if kind == "map" and d.get("map") == old:
					d.map = new
					change.call(p, "map")
				if kind == "event" and e.get("map", "") == map_of_event:
					var evs: Array = d.get("events", [])
					for i in evs.size():
						if evs[i] is Dictionary and evs[i].get("id") == old_id:
							evs[i].id = new
							change.call(p, "events/%d/id" % i)
							if not retire.call(p, d):
								return res
			"map":
				if kind == "map" and e.get("map", "") == old and d.get("id") == old:
					d.id = new
					change.call(p, "id")
	# 2. Typed references (the same scan as used_by() and the checks).
	var refs := 0
	var acc := traverse(copy, registry)
	for r in acc.refs:
		if kind == "event" or r.kind != kind or r.id != old:
			continue
		if r.get("is_key", false):
			var h: Dictionary = r.holder
			var val: Variant = h[old]
			h.erase(old)
			h[new] = val
		else:
			r.holder[r.key] = new
		change.call(r.file, r.path)
		refs += 1
	# Events are referenced by text targets inside their own map (move_route target, etc.).
	if kind == "event":
		for c in acc.commands:
			if c.map != map_of_event:
				continue
			for k in ["target", "event", "swap_with"]:
				if c.cmd.get(k) == old_id:
					c.cmd[k] = new
					change.call(c.file, "%s/%s" % [c.path, k])
					refs += 1
	# 3. Text codes (\V[id], \S[id], \N[id]) are typed references inside message text.
	var code := _text_code_for(kind)
	if code != "":
		var re := RegEx.create_from_string("\\\\([%s%s])\\[%s\\]" % [code, code.to_lower(), old])
		for t in acc.texts:
			var s := str(t.holder[t.key])
			var ns := re.sub(s, "\\$1[%s]" % new, true)
			if ns != s:
				t.holder[t.key] = ns
				change.call(t.file, t.path)
				refs += 1
	res["references"] = refs
	# A tileset's per-tile settings file is named after its ID: it moves with the rename.
	if kind == "tileset" and data != null:
		var ov_old := data.root.path_join("tileset_overrides/%s.json" % old)
		if FileAccess.file_exists(ov_old):
			var ov := RPGJson.parse_file(ov_old)
			if ov.ok:
				res.data_by_file[data.root.path_join("tileset_overrides/%s.json" % new)] = ov.data
				res["removes"] = [ov_old]
	# 4. Free-form scripts are not rewritten: warn instead.
	var word := RegEx.create_from_string("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % old_id)
	for s in acc.scripts:
		var text := str(s.holder[s.key])
		if word.search(text) != null:
			res.warnings.append({"file": s.file, "path": s.path, "record": s.record,
				"message": "'%s' appears in free-form text or a formula (\"%s\"). It was not changed; check it by hand." % [old_id, text.left(60)]})
	for p in changed:
		res.data_by_file[p] = copy[p].data
	res.ok = true
	return res


## Where the renames of an ID led: follows "renamed_ids" ({old: new}) from `id` to the ID the
## record has now (or had when it was deleted).
static func rename_chain_end(renamed: Dictionary, id: String) -> String:
	var cur := id
	for i in 1000:
		if not renamed.has(cur):
			return cur
		cur = str(renamed[cur])
	return cur


## Renames an entry of a Types list (`list_id`: elements, skill_types, weapon_types,
## armor_types, equip_slots, ...) and every record that names it (type_refs()), as one
## transaction. Returns the same shape as rename_id() (plus "references").
static func rename_type_entry(data: RPGProjectData, list_id: String, old: String, new: String, files: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "error": "", "changes": [], "warnings": [], "data_by_file": {}, "references": 0}
	if files.is_empty():
		files = collect_files(data)
	var copy := {}
	for p in files:
		var e: Dictionary = files[p].duplicate()
		e.data = RPGJson.deep_copy(e.get("data"))
		copy[p] = e
	var entry: Dictionary = {}
	var types_path := ""
	for p in copy:
		var e: Dictionary = copy[p]
		if e.get("kind", "") == "database" and e.get("db_type", "") == "types" and e.get("data") is Dictionary:
			for r in e.data.get("records", []):
				if r is Dictionary and str(r.get("id", "")) == list_id and r.get("entries") is Array:
					types_path = p
					for en in r.entries:
						if en is Dictionary and str(en.get("id", "")) == new:
							res.error = "Types > %s already has an entry '%s'." % [r.get("name", list_id), new]
							return res
						if en is Dictionary and str(en.get("id", "")) == old:
							entry = en
	if types_path == "" or entry.is_empty():
		res.error = "Types > %s has no entry '%s'." % [list_id, old]
		return res
	if not RPGIds.is_valid(new):
		res.error = "'%s' is not a valid ID. Use lowercase letters, digits and _, starting with a letter." % new
		return res
	if old == new:
		res.ok = true
		return res
	var changed := {types_path: true}
	entry["id"] = new
	res.changes.append({"file": types_path, "path": list_id})
	for tr in type_refs(copy):
		if tr.list != list_id or tr.id != old:
			continue
		if tr.is_key:
			var h: Dictionary = tr.holder
			var val: Variant = h[old]
			h.erase(old)
			h[new] = val
		else:
			tr.holder[tr.key] = new
		res.changes.append({"file": tr.file, "path": tr.path})
		changed[tr.file] = true
		res.references += 1
	for p in changed:
		res.data_by_file[p] = copy[p].data
	res.ok = true
	return res
