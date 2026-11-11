@tool
class_name RPGGameState
extends RefCounted
## Everything that changes during play: switches, typed variables, self switches, party,
## inventory, gold and per-event changes. All writes go through methods that check values and
## emit change signals. Do not edit the dictionaries directly.

signal switch_changed(id: String, value: bool)
signal variable_changed(id: String, value: Variant)
signal self_switch_changed(key: String, value: bool)
signal gold_changed(value: int)
signal items_changed(kind: String, id: String, count: int)
signal party_changed()
signal actor_changed(id: String)
## Emitted after any change that can affect page conditions.
signal changed()

## The project's seeded RNG (RPGRandom), set by the RPG service; random operands use it.
const RPGVehicles := preload("res://addons/rpg/runtime/rpg_vehicles.gd")

var rng: RefCounted = null

const MAX_GOLD := 9999999
const MAX_ITEMS := 99

var data: RPGProjectData
## Rule system (RPGRuleSystem) used to create actor battlers. May be null in tests.
var rules: RefCounted = null

var switches: Dictionary = {}
var variables: Dictionary = {}
var self_switches: Dictionary = {}
var gold := 0
## kind ("items", "weapons", "armors") -> {id: count}
var inventory: Dictionary = {"items": {}, "weapons": {}, "armors": {}}
var party: Array[String] = []
## actor id -> RPGBattler (or Dictionary when no rule system is loaded)
var actors: Dictionary = {}
## Persistent per-event changes: "map/event" -> {position, facing}
var event_changes: Dictionary = {}
var followers_visible := true
## Vehicles: {boat|ship|airship: {map, position: [x, y], facing}} and the one being ridden ("").
var vehicles: Dictionary = {}
var riding := ""
## Change Menu Access / Change Save Access / Change Encounter.
var access: Dictionary = {"menu": true, "save": true, "encounters": true}
var play_time := 0.0
var steps := 0
## Steps the party walked on foot outside events (RPG Maker's party steps): map turns and
## RPG Maker 2000-style "every N steps" state changes count these (RPGPlayer.party_walk).
var walk_steps := 0
## RPG Maker "Change Transparency": the player (and followers) drawn invisible.
var player_transparent := false
## RPG Maker "Change Map Name Display": show the map's display name after a transfer.
var map_name_display := true
## "Change Battle BGM" / "Change Victory ME": {"battle": sound, "victory": sound}. A missing key
## uses the System record's music.
var music_overrides: Dictionary = {}
## "Change Tileset" / "Change Parallax Background" / "Change Battle Background", per map:
## map id -> {tileset: id, parallax: {image, scroll_x, scroll_y, loop} or null, battle_background}.
var map_overrides: Dictionary = {}
## "Change Window Skin": System graphic used for windows ("" = the System record's).
var windowskin := ""
## Extension save sections: namespace -> Dictionary
var extension_sections: Dictionary = {}
## Condition kinds added by extensions (RPG.register_condition_kind): kind -> Callable(cond:
## Dictionary, where: Dictionary {map_id, event_id, ctx, state}) -> bool. Kept across new games.
var condition_kinds: Dictionary = {}
var errors: Array[String] = []
## Common events reserved by items and skills used outside battle ("Common Event" effects,
## RPGRuleSystem.common_events), run by the map once the menu has closed. Not saved.
var reserved_common_events: Array[String] = []


func _init(p_data: RPGProjectData = null) -> void:
	data = p_data


## Reserves a common event to run on the map after the current screen closes (RPG Maker's
## reserve_common_event).
func reserve_common_event(id: String) -> void:
	if id != "":
		reserved_common_events.append(id)


## The reserved common events, in order; the list is emptied.
func take_reserved_common_events() -> Array[String]:
	var out := reserved_common_events.duplicate()
	reserved_common_events.clear()
	return out


## Resets to a new game using definitions and the System record.
func new_game() -> void:
	switches.clear()
	variables.clear()
	self_switches.clear()
	event_changes.clear()
	extension_sections.clear()
	inventory = {"items": {}, "weapons": {}, "armors": {}}
	party.clear()
	actors.clear()
	play_time = 0.0
	steps = 0
	walk_steps = 0
	riding = ""
	vehicles = RPGVehicles.initial_state(data) if data else {}
	access = {"menu": true, "save": true, "encounters": true}
	player_transparent = false
	map_name_display = true
	music_overrides = {}
	map_overrides = {}
	windowskin = ""
	if data:
		for id in data.switches:
			switches[id] = false
		for id in data.variables:
			variables[id] = default_for(data.variables[id])
		var sys: Dictionary = data.system
		gold = int(sys.get("starting_gold", 0))
		for item_id in sys.get("starting_items", {}):
			inventory.items[item_id] = int(sys.starting_items[item_id])
		for actor_id in sys.get("starting_party", []):
			add_actor(actor_id)
	changed.emit()


static func default_for(def: Dictionary) -> Variant:
	var t: String = def.get("type", "int")
	var d: Variant = def.get("default", null)
	match t:
		"int":
			return int(d) if d != null else 0
		"float":
			return float(d) if d != null else 0.0
		"bool":
			return bool(d) if d != null else false
		"string":
			return str(d) if d != null else ""
	return 0


# --- switches ---------------------------------------------------------------------

func get_switch(id: String) -> bool:
	return bool(switches.get(id, false))


func set_switch(id: String, value: bool) -> bool:
	if data and not data.switches.is_empty() and not data.switches.has(id):
		_err("Unknown switch '%s'." % id)
		return false
	if switches.get(id, false) == value:
		return true
	switches[id] = value
	switch_changed.emit(id, value)
	changed.emit()
	return true


# --- variables --------------------------------------------------------------------

func variable_type(id: String) -> String:
	if data and data.variables.has(id):
		return data.variables[id].get("type", "int")
	var v: Variant = variables.get(id, 0)
	match typeof(v):
		TYPE_FLOAT: return "float"
		TYPE_BOOL: return "bool"
		TYPE_STRING: return "string"
	return "int"


func get_variable(id: String) -> Variant:
	if variables.has(id):
		return variables[id]
	if data and data.variables.has(id):
		return default_for(data.variables[id])
	return 0


## Sets a typed variable. Values are coerced to the declared type when that is lossless,
## otherwise the write is refused with an error.
func set_variable(id: String, value: Variant) -> bool:
	if data and not data.variables.is_empty() and not data.variables.has(id):
		_err("Unknown variable '%s'." % id)
		return false
	var t := variable_type(id)
	var coerced: Variant = coerce(t, value)
	if coerced == null:
		_err("Variable '%s' is %s; cannot store %s." % [id, t, var_to_str(value)])
		return false
	if variables.has(id) and typeof(variables[id]) == typeof(coerced) and variables[id] == coerced:
		return true
	variables[id] = coerced
	variable_changed.emit(id, coerced)
	changed.emit()
	return true


static func coerce(t: String, value: Variant) -> Variant:
	match t:
		"int":
			if typeof(value) == TYPE_INT:
				return value
			if typeof(value) == TYPE_FLOAT:
				return int(floor(value))
			if typeof(value) == TYPE_BOOL:
				return 1 if value else 0
			if typeof(value) == TYPE_STRING and value.is_valid_int():
				return value.to_int()
		"float":
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				return float(value)
			if typeof(value) == TYPE_STRING and value.is_valid_float():
				return value.to_float()
		"bool":
			if typeof(value) == TYPE_BOOL:
				return value
			if typeof(value) == TYPE_INT:
				return value != 0
		"string":
			return str(value)
	return null


# --- self switches ----------------------------------------------------------------

func get_self_switch(map_id: String, event_id: String, letter: String) -> bool:
	return bool(self_switches.get(RPGIds.self_switch_key(map_id, event_id, letter), false))


func set_self_switch(map_id: String, event_id: String, letter: String, value: bool) -> bool:
	if not RPGIds.SELF_SWITCHES.has(letter):
		_err("Self switch must be A, B, C or D (got '%s')." % letter)
		return false
	var key := RPGIds.self_switch_key(map_id, event_id, letter)
	if bool(self_switches.get(key, false)) == value:
		return true
	if value:
		self_switches[key] = true
	else:
		self_switches.erase(key)
	self_switch_changed.emit(key, value)
	changed.emit()
	return true


# --- gold and items -----------------------------------------------------------------

func change_gold(operation: String, amount: int) -> int:
	var before := gold
	match operation:
		"increase": gold += absi(amount)
		"decrease": gold -= absi(amount)
		"set": gold = amount
	gold = clampi(gold, 0, MAX_GOLD)
	if gold != before:
		gold_changed.emit(gold)
		changed.emit()
	return gold


static func kind_for(type_or_kind: String) -> String:
	match type_or_kind:
		"item", "items": return "items"
		"weapon", "weapons": return "weapons"
		"armor", "armors", "armour", "armours": return "armors"
	return "items"


func item_count(id: String, kind := "items") -> int:
	return int(inventory.get(kind_for(kind), {}).get(id, 0))


func has_item(id: String, kind := "items", include_equipped := false) -> bool:
	if item_count(id, kind) > 0:
		return true
	if include_equipped and kind_for(kind) != "items":
		for a in party:
			var b: Variant = actors.get(a)
			if b != null and "equips" in b and b.equips.values().has(id):
				return true
	return false


func change_items(id: String, operation: String, amount: int, kind := "items") -> int:
	var k := kind_for(kind)
	var cur := item_count(id, k)
	var n := cur
	match operation:
		"increase": n = cur + absi(amount)
		"decrease": n = cur - absi(amount)
		"set": n = amount
	n = clampi(n, 0, MAX_ITEMS)
	if n == cur:
		return n
	if n == 0:
		inventory[k].erase(id)
	else:
		inventory[k][id] = n
	items_changed.emit(k, id, n)
	changed.emit()
	return n


# --- party ------------------------------------------------------------------------------

func actor(id: String) -> Variant:
	if not actors.has(id):
		_ensure_actor(id)
	return actors.get(id)


func _ensure_actor(id: String) -> void:
	if actors.has(id):
		return
	var rec: Dictionary = data.record("actors", id) if data else {}
	if rules != null and rules.has_method("new_actor_battler"):
		actors[id] = rules.new_actor_battler(id, int(rec.get("initial_level", rec.get("level", 1))))
	else:
		actors[id] = {"id": id, "name": rec.get("name", id), "hp": 1, "level": 1}


func add_actor(id: String) -> bool:
	if party.has(id):
		return false
	if data and not data.has_record("actors", id) and not data.records("actors").is_empty():
		_err("Unknown actor '%s'." % id)
		return false
	_ensure_actor(id)
	party.append(id)
	party_changed.emit()
	changed.emit()
	return true


func remove_actor(id: String) -> bool:
	if not party.has(id):
		return false
	party.erase(id)
	party_changed.emit()
	changed.emit()
	return true


func in_party(id: String) -> bool:
	return party.has(id)


func party_battlers() -> Array:
	var out := []
	for id in party:
		out.append(actor(id))
	return out


## Map overrides set by event commands for `map_id` (see map_overrides), or {}.
func map_override(map_id: String) -> Dictionary:
	var o: Variant = map_overrides.get(map_id)
	return o if o is Dictionary else {}


func set_map_override(map_id: String, key: String, value: Variant) -> void:
	var o: Dictionary = map_override(map_id)
	o[key] = value
	map_overrides[map_id] = o


const LOOK_KEYS := ["charset", "charset_index", "face", "face_index", "battler", "nickname"]


## An actor's graphics and nickname: the database record overlaid with what "Change Actor
## Graphic" / "Change Nickname" stored on the actor (custom.look, so it is saved with the actor
## and reset when the actor is initialized).
func actor_look(id: String) -> Dictionary:
	var rec: Dictionary = data.record("actors", id) if data else {}
	var out := {}
	for k in LOOK_KEYS:
		out[k] = rec.get(k, 0 if k.ends_with("_index") else "")
	var cs: Variant = rec.get("charset", rec.get("walk_sprite", ""))
	if cs is Dictionary:
		out["charset"] = str(cs.get("sheet", ""))
		out["charset_index"] = int(cs.get("index", 0))
	var fc: Variant = rec.get("face", "")
	if fc is Dictionary:
		out["face"] = str(fc.get("sheet", ""))
		out["face_index"] = int(fc.get("index", 0))
	var look: Dictionary = actor_custom(id).get("look", {})
	for k in look:
		out[k] = look[k]
	return out


## Stores look fields (see actor_look) on the actor.
func set_actor_look(id: String, values: Dictionary) -> void:
	var c := actor_custom(id)
	var look: Dictionary = c.get("look", {})
	for k in values:
		look[k] = values[k]
	c["look"] = look
	notify_actor_changed(id)


## The actor's saved free-form `custom` dictionary (created if missing).
func actor_custom(id: String) -> Dictionary:
	var b: Variant = actor(id)
	if b is Object and "custom" in b:
		return b.custom
	if b is Dictionary:
		if not (b.get("custom") is Dictionary):
			b["custom"] = {}
		return b.custom
	return {}


func notify_actor_changed(id: String) -> void:
	actor_changed.emit(id)
	changed.emit()


# --- conditions ------------------------------------------------------------------------

static func compare(a: Variant, op: String, b: Variant) -> bool:
	match op:
		"==", "=": return a == b
		"!=", "≠": return a != b
		"<": return a < b
		"<=", "≤": return a <= b
		">": return a > b
		">=", "≥": return a >= b
	return false


func resolve_operand(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("variable"):
			return get_variable(v.variable)
		if v.has("random"):
			var r: Array = v.random
			return rng.randi_range(int(r[0]), int(r[1])) if rng != null else randi_range(int(r[0]), int(r[1]))
		if v.get("game_data") is Dictionary:
			return game_data(v.game_data)
	return v


## RPG Maker's "Game Data" operand: {kind: item|weapon|armor, id} (count held), gold, steps,
## play_time (seconds), party_size, or {kind: actor, id, field: level|exp|<resource>|<stat>}.
func game_data(g: Dictionary) -> Variant:
	var kind := str(g.get("kind", ""))
	match kind:
		"item", "items":
			return item_count(str(g.get("id", "")), "items")
		"weapon", "weapons":
			return item_count(str(g.get("id", "")), "weapons")
		"armor", "armors", "armour":
			return item_count(str(g.get("id", "")), "armors")
		"gold":
			return gold
		"steps":
			return steps
		"play_time":
			return int(play_time)
		"party_size":
			return party.size()
		"actor":
			var b: Variant = actor(str(g.get("id", "")))
			if b == null:
				_err("Game data: actor '%s' is not available." % g.get("id", ""))
				return 0
			var field := str(g.get("field", "level"))
			if field == "level":
				return int(b.level)
			if field == "exp":
				return int(b.exp)
			if b.resources.has(field):
				return int(b.resources[field])
			if rules != null and rules.has_method("stat_block"):
				var blk: Dictionary = rules.stat_block(b)
				if blk.has(field):
					return blk[field]
			_err("Game data: actors have no '%s'." % field)
			return 0
	_err("Game data: unknown kind '%s'." % kind)
	return 0


## Checks one condition object. `map_id`/`event_id` are needed for self switches; `ctx` (the
## running command's RPGContext) for Character facing.
func check_condition(cond: Dictionary, map_id := "", event_id := "", ctx: Object = null) -> bool:
	var kind: String = cond.get("kind", "")
	match kind:
		"switch":
			return get_switch(cond.get("id", "")) == bool(cond.get("value", true))
		"variable":
			var cur: Variant = get_variable(cond.get("id", ""))
			var rhs: Variant = resolve_operand(cond.get("value", 0))
			var t := variable_type(cond.get("id", ""))
			if t == "bool" or t == "string":
				var op: String = cond.get("op", "==")
				if not ["==", "=", "!=", "≠"].has(op):
					return false
				return compare(cur, op, coerce(t, rhs))
			return compare(float(cur), cond.get("op", "=="), float(rhs))
		"self_switch":
			var letter: String = cond.get("id", cond.get("switch", "A"))
			return get_self_switch(map_id, event_id, letter) == bool(cond.get("value", true))
		"item":
			var k: String = cond.get("item_kind", "items")
			return item_count(cond.get("id", ""), k) >= int(cond.get("count", 1)) or (int(cond.get("count", 1)) <= 1 and has_item(cond.get("id", ""), k, true))
		"actor":
			return _check_actor(cond)
		"facing":
			# Conditional Branch only: needs the running event's context (RPGContext.character).
			if ctx == null or not ctx.has_method("character"):
				_err("Character facing can only be checked in a Conditional Branch.")
				return false
			var ch: Variant = ctx.character(str(cond.get("target", "player")))
			if ch == null or not ("facing" in ch):
				_err("Character facing: '%s' is not on this map." % cond.get("target", "player"))
				return false
			return str(ch.facing) == str(cond.get("facing", "down"))
		"button":
			var action := "rpg_" + str(cond.get("button", "ok"))
			return InputMap.has_action(action) and Input.is_action_pressed(action)
		"vehicle":
			# Riding a given vehicle ("" / "none" = on foot).
			var want := str(cond.get("id", cond.get("vehicle", "")))
			return riding == ("" if want == "none" else want)
		"gold":
			return compare(gold, cond.get("op", ">="), int(resolve_operand(cond.get("value", 0))))
		"all":
			for c in cond.get("conditions", []):
				if not check_condition(c, map_id, event_id, ctx):
					return false
			return true
		"any":
			for c in cond.get("conditions", []):
				if check_condition(c, map_id, event_id, ctx):
					return true
			return false
		"not":
			return not check_condition(cond.get("condition", {}), map_id, event_id, ctx)
	if condition_kinds.has(kind):
		var r: Variant = (condition_kinds[kind] as Callable).call(cond, {"map_id": map_id, "event_id": event_id, "ctx": ctx, "state": self})
		return bool(r) if r != null else false
	_err("Unknown condition kind '%s'." % kind)
	return false


## Actor condition: in the party (default), or name / class / skill learned / weapon or armour
## equipped / state, by `check` ({kind: "actor", id, check, name | class | skill | weapon | armor | state}).
func _check_actor(cond: Dictionary) -> bool:
	var id := str(cond.get("id", ""))
	var check := str(cond.get("check", "in_party"))
	if check == "in_party":
		return in_party(id) == bool(cond.get("value", true))
	var b: Variant = actor(id)
	if b == null:
		return false
	match check:
		"name":
			return str(b.get("name") if b is Dictionary else b.name) == str(cond.get("name", ""))
		"class":
			return b is Object and "class_id" in b and str(b.class_id) == str(cond.get("class", ""))
		"skill":
			return b is Object and "skills" in b and b.skills.has(str(cond.get("skill", "")))
		"weapon", "armor":
			return b is Object and "equips" in b and b.equips.values().has(str(cond.get(check, "")))
		"state":
			return b is Object and b.has_method("has_state") and b.has_state(str(cond.get("state", "")))
	_err("Unknown actor check '%s'." % check)
	return false


func check_all(conds: Array, map_id := "", event_id := "") -> bool:
	for c in conds:
		if c is Dictionary and not check_condition(c, map_id, event_id):
			return false
	return true


# --- persistence --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var actor_data := {}
	for id in actors:
		var b: Variant = actors[id]
		actor_data[id] = b.to_dict() if b is Object and b.has_method("to_dict") else b
	return {
		"switches": switches.duplicate(),
		"variables": variables.duplicate(),
		"self_switches": self_switches.duplicate(),
		"gold": gold,
		"inventory": inventory.duplicate(true),
		"party": Array(party),
		"actors": actor_data,
		"event_changes": event_changes.duplicate(true),
		"followers_visible": followers_visible,
		"vehicles": vehicles.duplicate(true),
		"riding": riding,
		"access": access.duplicate(),
		"play_time": play_time,
		"steps": steps,
		"walk_steps": walk_steps,
		"player_transparent": player_transparent,
		"map_name_display": map_name_display,
		"music_overrides": music_overrides.duplicate(true),
		"map_overrides": map_overrides.duplicate(true),
		"windowskin": windowskin,
	}


func from_dict(d: Dictionary, battler_script: Script = null) -> void:
	switches = d.get("switches", {}).duplicate()
	variables = {}
	var vars: Dictionary = d.get("variables", {})
	for id in vars:
		var c: Variant = coerce(variable_type(id), vars[id])
		variables[id] = c if c != null else vars[id]
	self_switches = d.get("self_switches", {}).duplicate()
	gold = int(d.get("gold", 0))
	inventory = {"items": {}, "weapons": {}, "armors": {}}
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		inventory[k] = inv[k].duplicate()
	party.clear()
	for id in d.get("party", []):
		party.append(str(id))
	actors.clear()
	var actor_data: Dictionary = d.get("actors", {})
	for id in actor_data:
		if battler_script != null and battler_script.has_method("from_dict"):
			actors[id] = battler_script.from_dict(actor_data[id])
		else:
			actors[id] = actor_data[id]
	event_changes = d.get("event_changes", {}).duplicate(true)
	followers_visible = bool(d.get("followers_visible", true))
	# Saves from before vehicles existed start with the vehicles where a new game has them.
	vehicles = d.get("vehicles", {}).duplicate(true) if d.get("vehicles") is Dictionary else (RPGVehicles.initial_state(data) if data else {})
	riding = str(d.get("riding", ""))
	access = {"menu": true, "save": true, "encounters": true}
	if d.get("access") is Dictionary:
		for k in d.access:
			access[k] = bool(d.access[k])
	play_time = float(d.get("play_time", 0.0))
	steps = int(d.get("steps", 0))
	walk_steps = int(d.get("walk_steps", 0))
	player_transparent = bool(d.get("player_transparent", false))
	map_name_display = bool(d.get("map_name_display", true))
	music_overrides = d.get("music_overrides", {}).duplicate(true) if d.get("music_overrides") is Dictionary else {}
	map_overrides = d.get("map_overrides", {}).duplicate(true) if d.get("map_overrides") is Dictionary else {}
	windowskin = str(d.get("windowskin", ""))
	changed.emit()


func _err(msg: String) -> void:
	errors.append(msg)
	if errors.size() > 100:
		errors.pop_front()
	push_warning("RPG: " + msg)
