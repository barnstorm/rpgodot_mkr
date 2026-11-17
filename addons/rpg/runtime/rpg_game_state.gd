@tool
class_name RPGGameState
extends RefCounted
## Everything that changes during play: switches, typed variables, self switches, party,
## inventory, gold and per-event changes. All writes go through methods that check values and
## emit change signals. Do not edit the dictionaries directly.

signal switch_changed(id: String, value: bool)
signal variable_changed(id: String, value: Variant)
signal self_switch_changed(key: String, value: bool)
signal self_variable_changed(key: String, value: Variant)
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
## Per-event variables: "map/event/name" -> value. Untyped (they are not declared anywhere): the
## first write fixes the type, later writes must fit it. Reads of a never-set one give 0.
var self_variables: Dictionary = {}
var gold := 0
## kind ("items", "weapons", "armors") -> {id: count}
var inventory: Dictionary = {"items": {}, "weapons": {}, "armors": {}}
var party: Array[String] = []
## actor id -> RPGBattler (or Dictionary when no rule system is loaded)
var actors: Dictionary = {}
## Persistent per-event changes: "map/event" -> {position, facing}
var event_changes: Dictionary = {}
## Runtime-spawned event copies (#66): map id -> Array of event data. The map rebuilds these on
## top of the placed events, so a spawned copy survives map changes and saves like a placed one.
var spawned_events: Dictionary = {}
var followers_visible := true
## Vehicles: {boat|ship|airship: {map, position: [x, y], facing}} and the one being ridden ("").
var vehicles: Dictionary = {}
var riding := ""
## Change Menu Access / Change Save Access / Change Encounter.
var access: Dictionary = {"menu": true, "save": true, "encounters": true}
var play_time := 0.0
## Countdown timers 1 and 2 (RPG Maker 2003): "1"/"2" -> {seconds, running, visible, position,
## battle}. `battle` says what a timer does while a battle runs: "pause" (hold), "count" or
## "abort" (the battle ends, no rewards, when it reaches 0).
var timers: Dictionary = {}
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
## "Change Tile" operations with Keep (#15), per map: map id -> [{layer, mode, from?, to, cell?}],
## replayed by RPGMap.start() so kept tile changes survive map changes and loading.
var tile_changes: Dictionary = {}
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
## Play counters Game Data can read (RPG Maker's Other: saves, battles, wins, defeats, escapes).
var counters: Dictionary = {"saves": 0, "battles": 0, "victories": 0, "defeats": 0, "escapes": 0}
## Game Data "last used": what the most recent battle action used and targeted
## ({item, skill, actor, target_actor, target_enemy}). Battle actions fill it; the values stay
## until the next battle changes them.
var last_used: Dictionary = {}


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


## Increments a play counter (see `counters`) by one.
func bump_counter(key: String) -> void:
	if not counters.has(key):
		_err("Unknown counter '%s'." % key)
		return
	counters[key] = int(counters[key]) + 1


## Records Game Data "last used" values (see `last_used`); only the given keys change. Battle
## actions call this with what they used and targeted.
func record_last_used(values: Dictionary) -> void:
	for k in values:
		last_used[k] = values[k]


## Resets to a new game using definitions and the System record.
func new_game() -> void:
	switches.clear()
	variables.clear()
	self_switches.clear()
	self_variables.clear()
	event_changes.clear()
	spawned_events.clear()
	extension_sections.clear()
	inventory = {"items": {}, "weapons": {}, "armors": {}}
	party.clear()
	actors.clear()
	play_time = 0.0
	timers.clear()
	steps = 0
	walk_steps = 0
	last_used.clear()
	counters = {"saves": 0, "battles": 0, "victories": 0, "defeats": 0, "escapes": 0}
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


# --- self variables -----------------------------------------------------------------

## An event's variable. Never-set ones read as 0.
func get_self_variable(map_id: String, event_id: String, name: String) -> Variant:
	return self_variables.get(RPGIds.self_variable_key(map_id, event_id, name), 0)


## The type a self variable currently holds ("int" while it has never been set).
func self_variable_type(map_id: String, event_id: String, name: String) -> String:
	var v: Variant = self_variables.get(RPGIds.self_variable_key(map_id, event_id, name), null)
	match typeof(v):
		TYPE_FLOAT: return "float"
		TYPE_BOOL: return "bool"
		TYPE_STRING: return "string"
	return "int"


## Sets an event's variable. The first write fixes its type; later writes are coerced to it and
## refused when they do not fit (same rule as declared variables).
func set_self_variable(map_id: String, event_id: String, name: String, value: Variant) -> bool:
	if not RPGIds.is_valid(name):
		_err("Self variable names use lowercase letters, digits and _ (got '%s')." % name)
		return false
	var key := RPGIds.self_variable_key(map_id, event_id, name)
	if self_variables.has(key):
		var t := self_variable_type(map_id, event_id, name)
		var coerced: Variant = coerce(t, value)
		if coerced == null:
			_err("Self variable '%s' is %s; cannot store %s." % [name, t, var_to_str(value)])
			return false
		if typeof(coerced) == typeof(self_variables[key]) and coerced == self_variables[key]:
			return true
		self_variables[key] = coerced
	else:
		match typeof(value):
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING:
				pass
			_:
				_err("Self variable '%s' can hold a number, true/false or text." % name)
				return false
		self_variables[key] = value
	self_variable_changed.emit(key, self_variables[key])
	changed.emit()
	return true


## Clears every self switch and self variable of one event, or of a whole map when `event_id` is
## empty. Returns how many values were cleared.
func reset_self_state(map_id: String, event_id := "") -> int:
	var prefix := map_id + "/" + (event_id + "/" if event_id != "" else "")
	var n := 0
	for key in self_switches.keys():
		if str(key).begins_with(prefix):
			self_switches.erase(key)
			n += 1
	for key in self_variables.keys():
		if str(key).begins_with(prefix):
			self_variables.erase(key)
			n += 1
	if n > 0:
		changed.emit()
	return n


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


## A map is being set up for a new visit (a transfer, not a loaded game): its events go back to
## their editor positions and facings, as in RPG Maker, where only self switches outlive the map
## (issue #155). An event that a Set Event Location told to Keep its place returns there instead.
func reset_event_changes(map_id: String) -> void:
	var prefix := map_id + "/"
	for key in event_changes.keys():
		if not str(key).begins_with(prefix):
			continue
		var kept: Variant = event_changes[key].get("keep") if event_changes[key] is Dictionary else null
		if kept is Dictionary and kept.get("position") is Array and kept.position.size() >= 2:
			event_changes[key] = {"position": kept.position.duplicate(), "facing": str(kept.get("facing", "down")), "keep": kept}
		else:
			event_changes.erase(key)


## Map overrides set by event commands for `map_id` (see map_overrides), or {}.
func map_override(map_id: String) -> Dictionary:
	var o: Variant = map_overrides.get(map_id)
	return o if o is Dictionary else {}


func set_map_override(map_id: String, key: String, value: Variant) -> void:
	var o: Dictionary = map_override(map_id)
	o[key] = value
	map_overrides[map_id] = o


## Remembers a Change Tile operation for `map_id` (see tile_changes). A later operation with the
## same target replaces the earlier one, so a map's list stays bounded however often it runs.
func remember_tile_change(map_id: String, op: Dictionary) -> void:
	var list: Array = tile_changes.get(map_id, [])
	for i in list.size():
		var o: Dictionary = list[i]
		if str(o.get("layer", "")) == str(op.get("layer", "")) and str(o.get("mode", "")) == str(op.get("mode", "")) \
				and str(o.get("from", "")) == str(op.get("from", "")) and str(o.get("cell", "")) == str(op.get("cell", "")):
			list[i] = op
			tile_changes[map_id] = list
			return
	list.append(op)
	tile_changes[map_id] = list


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


## Resolves an operand ({variable}, {pointer}, {random}, {game_data}) to its value. `ctx` (the
## running command's context) is needed by game data that reads the map or the running battle.
func resolve_operand(v: Variant, ctx: Object = null) -> Variant:
	if v is Dictionary:
		if v.has("variable"):
			return get_variable(v.variable)
		if v.has("self_variable"):
			# An event's own variable: {self_variable: {map, event, name}}. Blank map/event is
			# the running command's map and event.
			var sv: Dictionary = v.self_variable
			var m := str(sv.get("map", ""))
			var e := str(sv.get("event", ""))
			if (m == "" or e == "") and ctx != null and ctx.has_method("map_id"):
				if m == "":
					m = ctx.map_id()
				if e == "":
					e = ctx.event_id()
			if m == "" or e == "":
				_err("Game data: an event's self variable needs a running event (or a map and event).")
				return 0
			return get_self_variable(m, e, str(sv.get("name", "")))
		if v.has("pointer"):
			# Indirect source: the value of the variable whose id another variable holds.
			return get_variable(str(get_variable(str(v.pointer))))
		if v.has("random"):
			var r: Array = v.random
			return rng.randi_range(int(r[0]), int(r[1])) if rng != null else randi_range(int(r[0]), int(r[1]))
		if v.get("game_data") is Dictionary:
			return game_data(v.game_data, ctx)
	return v


## RPG Maker's "Game Data" operand: {kind: item|weapon|armor, id} (count held), gold, steps,
## play_time (seconds), party_size, {kind: actor, id, field} (level, exp, a resource, an equip
## slot's item id, or a stat), {kind: character, target, field} (x, y, direction, screen_x,
## screen_y), map_id, {kind: party_member, slot} (the actor id in that slot), {kind: last_used,
## what}, {kind: counter, which}, {kind: enemy, index, field} (a stat of an enemy in the
## running battle), or {kind: hook[.field]} (the engine moment that started this common event).
## Kinds that read the map, the battle or the hook need `ctx`.
func game_data(g: Dictionary, ctx: Object = null) -> Variant:
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
			var fv: Variant = _battler_field(b, str(g.get("field", "level")))
			if fv == null:
				_err("Game data: actors have no '%s'." % g.get("field", "level"))
				return 0
			return fv
		"character":
			return _character_data(g, ctx)
		"map_id":
			if ctx == null or not ("map_id" in ctx):
				_err("Game data: the map id needs a running command (use it in an event).")
				return ""
			return str(ctx.map_id())
		"party_member":
			var slot := int(g.get("slot", 0))
			return str(party[slot]) if slot >= 0 and slot < party.size() else ""
		"last_used":
			return last_used.get(str(g.get("what", "item")), "")
		"counter":
			var which := str(g.get("which", "battles"))
			if not counters.has(which):
				_err("Game data: unknown counter '%s'." % which)
				return 0
			return int(counters[which])
		"enemy":
			var core: Variant = _battle_core(ctx)
			if core == null:
				_err("Game data: enemy stats only work in a battle.")
				return 0
			var idx := int(g.get("index", 0))
			var e: Array = core.enemies
			if idx < 0 or idx >= e.size():
				_err("Game data: there is no enemy number %d." % idx)
				return 0
			var ev: Variant = _battler_field(e[idx], str(g.get("field", "hp")))
			if ev == null:
				_err("Game data: enemies have no '%s'." % g.get("field", "hp"))
				return 0
			return ev
		_:
			if kind == "hook" or kind.begins_with("hook."):
				return _hook_data(kind, ctx)
	_err("Game data: unknown kind '%s'." % kind)
	return 0


## The engine moment that started the running common event (issue #52): Control Variables reads
## it as game data "hook" (the whole dictionary) or one field — "hook.actor", "hook.state",
## "hook.region", "hook.terrain", "hook.map", "hook.outcome", "hook.vehicle", "hook.x", "hook.y",
## "hook.old_level", "hook.new_level". Numeric fields default to 0, the rest to "".
func _hook_data(kind: String, ctx: Object) -> Variant:
	var hook: Variant = {}
	if ctx != null and "interpreter" in ctx and ctx.interpreter != null:
		hook = ctx.interpreter.owner.get("hook", {})
	if not (hook is Dictionary) or (hook as Dictionary).is_empty():
		_err("Game data: '%s' needs a common event started by an engine moment." % kind)
		return 0
	if kind == "hook":
		return hook
	var field := kind.substr(5)
	var h: Dictionary = hook
	if not h.has(field):
		return 0 if ["x", "y", "region", "terrain", "old_level", "new_level"].has(field) else ""
	return h[field]


## One value of an actor or enemy battler: level, exp, a resource, the item id in an equip slot
## (the slot's name is the field), or a base stat. Returns null when there is no such field.
func _battler_field(b: Variant, field: String) -> Variant:
	if field == "level":
		return int(b.level)
	if field == "exp":
		return int(b.exp)
	if b is Object and "resources" in b and b.resources.has(field):
		return int(b.resources[field])
	if b is Object and "equips" in b and b.equips.has(field):
		return str(b.equips[field])
	if rules != null and rules.has_method("stat_block"):
		var blk: Dictionary = rules.stat_block(b)
		if blk.has(field):
			return blk[field]
	return null


## The running battle's core through a command context, or null (no battle).
func _battle_core(ctx: Object) -> Variant:
	if ctx != null and "battle" in ctx and ctx.battle != null and ctx.battle.has_method("core"):
		return ctx.battle.core()
	return null


## Directions as RPG Maker numbers them (RM2000/2003 Control Variables), for ports and HUD math.
const RM_DIRECTIONS := {"down": 2, "left": 4, "right": 6, "up": 8}


## Game data "character": where a character is. `target` is "player", "this", an event id, or
## "follower" with `index` (0 = right behind the player). `field` is x, y (map cells), direction
## (the numbers above), or screen_x / screen_y (pixels on screen, for picture HUDs).
func _character_data(g: Dictionary, ctx: Object) -> Variant:
	if ctx == null or not ctx.has_method("character"):
		_err("Game data: character needs a running event (use it in a command).")
		return 0
	var target := str(g.get("target", "player"))
	var ch: Variant = null
	if target == "follower":
		var fs: Variant = ctx.map.player.followers if ctx.map != null and ctx.map.get("player") != null else []
		var fi := int(g.get("index", 0))
		ch = fs[fi] if fs is Array and fi >= 0 and fi < (fs as Array).size() else null
	else:
		ch = ctx.character(target)
	if ch == null:
		_err("Game data: '%s' is not on this map." % target)
		return 0
	var field := str(g.get("field", "x"))
	match field:
		"x":
			return int(ch.cell.x)
		"y":
			return int(ch.cell.y)
		"direction":
			return int(RM_DIRECTIONS.get(str(ch.facing), 0))
		"screen_x":
			return int(round(ch.global_position.x)) if ch is Node2D else 0
		"screen_y":
			return int(round(ch.global_position.y)) if ch is Node2D else 0
	_err("Game data: a character has no '%s'." % field)
	return 0


## The [map, event] a self switch or self variable condition reads. A missing, blank or "this"
## map/event is the one the condition belongs to (a page's event, the running branch's event),
## the same rule Control Self Switch uses. The condition editor saves blanks as "" (issue #141).
static func self_owner(cond: Dictionary, map_id: String, event_id: String) -> Array:
	var m := str(cond.get("map", ""))
	var e := str(cond.get("event", ""))
	if m == "" or m == "this":
		m = map_id
	if e == "" or e == "this":
		e = event_id
	return [m, e]


## Checks one condition object. `map_id`/`event_id` are needed for self switches; `ctx` (the
## running command's RPGContext) for Character facing.
func check_condition(cond: Dictionary, map_id := "", event_id := "", ctx: Object = null) -> bool:
	var kind: String = cond.get("kind", "")
	match kind:
		"switch":
			return get_switch(cond.get("id", "")) == bool(cond.get("value", true))
		"variable":
			var cur: Variant = get_variable(cond.get("id", ""))
			var rhs: Variant = resolve_operand(cond.get("value", 0), ctx)
			var t := variable_type(cond.get("id", ""))
			if t == "bool" or t == "string":
				var op: String = cond.get("op", "==")
				if not ["==", "=", "!=", "≠"].has(op):
					return false
				return compare(cur, op, coerce(t, rhs))
			return compare(float(cur), cond.get("op", "=="), float(rhs))
		"self_switch":
			var letter: String = cond.get("id", cond.get("switch", "A"))
			var who := self_owner(cond, map_id, event_id)
			return get_self_switch(who[0], who[1], letter) == bool(cond.get("value", true))
		"self_variable":
			var sname := str(cond.get("name", cond.get("id", "")))
			var swho := self_owner(cond, map_id, event_id)
			var sm: String = swho[0]
			var se: String = swho[1]
			var scur: Variant = get_self_variable(sm, se, sname)
			var srhs: Variant = resolve_operand(cond.get("value", 0), ctx)
			var st := self_variable_type(sm, se, sname)
			if st == "bool" or st == "string":
				var sop: String = cond.get("op", "==")
				if not ["==", "=", "!=", "≠"].has(sop):
					return false
				return compare(scur, sop, srhs)
			return compare(float(scur), cond.get("op", "=="), float(srhs))
		"timer":
			# RPG Maker 2003's timer condition: the whole seconds a timer has left versus a value
			# ("or less" is <=, "or more" is >=).
			var tid := str(cond.get("timer", cond.get("id", "1")))
			return compare(float(timer_seconds(tid)), cond.get("op", "<="), float(resolve_operand(cond.get("seconds", cond.get("value", 0)), ctx)))
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
			if not InputMap.has_action(action):
				return false
			match str(cond.get("mode", "held")):
				"pressed":
					return Input.is_action_just_pressed(action)
				"repeated":
					# Re-fires about every quarter second while held, like a text cursor.
					return Input.is_action_just_pressed(action) or (Input.is_action_pressed(action) and Engine.get_process_frames() % 15 == 0)
			return Input.is_action_pressed(action)
		"started_by":
			# Conditional Branch only: reads the event that is running the branch. A page runs either
			# through its trigger or because Call Event opened it; inside a called page only "call" holds.
			if ctx == null or not ctx.has_method("character"):
				_err("Started by can only be checked in a Conditional Branch.")
				return false
			var by := str(cond.get("by", "action_button"))
			if ctx.interpreter != null and ctx.interpreter.in_called_page > 0:
				return by == "call"
			var ev: Variant = ctx.character("this")
			if ev == null or not ("trigger" in ev):
				return false
			return by == str(ev.trigger)
		"formula":
			# The formula language with empty a/b/s and the project's variables and RNG.
			var r: Dictionary = RPGFormula.evaluate_text(str(cond.get("text", "")), {"a": {}, "b": {}, "v": variables, "s": {}, "rng": rng})
			if not r.ok:
				_err("Formula condition: %s." % r.error)
				return false
			var val: Variant = r.value
			return bool(val) if val is bool else float(val) != 0.0
		"can_pass":
			# Conditional Branch only: walks cells with the map's navigation rules.
			if ctx == null or not ctx.has_method("character"):
				_err("Can pass can only be checked in a Conditional Branch.")
				return false
			var walker: Variant = ctx.character(str(cond.get("target", "player")))
			if walker == null or not ("cell" in walker):
				_err("Can pass: '%s' is not on this map." % cond.get("target", "player"))
				return false
			var dirs := {"down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT, "up": Vector2i.UP}
			var d := Vector2i(dirs.get(str(cond.get("facing", "down")), Vector2i.ZERO))
			if d == Vector2i.ZERO:
				_err("Can pass: unknown facing '%s'." % cond.get("facing", "down"))
				return false
			var m: Node = ctx.map
			if m == null:
				return false
			var cell: Vector2i = walker.cell
			for i in clampi(int(cond.get("distance", 1)), 1, 20):
				if not m.movement.can_move(walker, cell, d):
					return false
				cell += d
			return true
		"vehicle":
			# Riding a given vehicle ("" / "none" = on foot).
			var want := str(cond.get("id", cond.get("vehicle", "")))
			return riding == ("" if want == "none" else want)
		"gold":
			return compare(gold, cond.get("op", ">="), int(resolve_operand(cond.get("value", 0), ctx)))
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
		"turn", "enemy_hp", "actor_hp", "actor_can_act", "enemy_can_act", "enemy_is_target":
			return _battle_condition(kind, cond, ctx)
	if condition_kinds.has(kind):
		var r: Variant = (condition_kinds[kind] as Callable).call(cond, {"map_id": map_id, "event_id": event_id, "ctx": ctx, "state": self})
		return bool(r) if r != null else false
	_err("Unknown condition kind '%s'." % kind)
	return false


## Battle kinds of a Conditional Branch (RM2000/2003): the troop page checks (turn, enemy HP,
## actor HP) and the branch-only can-act / is-target checks, read from the running battle
## through the running command's context. Outside a battle they are false with a warning.
func _battle_condition(kind: String, cond: Dictionary, ctx: Object) -> bool:
	var core: Variant = null
	if ctx != null and "battle" in ctx and ctx.battle != null and ctx.battle.has_method("core"):
		core = ctx.battle.core()
	if core == null:
		_err("Condition '%s' only works in a battle." % kind)
		return false
	if kind == "turn" or kind == "enemy_hp" or kind == "actor_hp":
		return core.page_conditions_met({"conditions": [cond]})
	return core.branch_check(kind, cond)


## Actor condition: in the party (default), or name / class / skill learned / weapon or armour
## equipped / state, or a level / HP / SP test (with `op` and `value`; HP and SP may compare
## percentages), by `check` ({kind: "actor", id, check, ...}).
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
		"level":
			var lv := 0
			if b is Dictionary:
				lv = int(b.get("level", 0))
			elif "level" in b:
				lv = int(b.level)
			return compare(lv, str(cond.get("op", ">=")), int(resolve_operand(cond.get("value", 1))))
		"hp", "sp":
			var res := RPGPartyUtil.get_res(b, check)
			var want := int(resolve_operand(cond.get("value", 1)))
			if cond.get("percent", false):
				var mx := 9999
				if rules != null and rules.has_method("max_resource"):
					mx = int(rules.max_resource(b, check))
				return compare(int(res * 100.0 / maxi(mx, 1)), str(cond.get("op", ">=")), want)
			return compare(res, str(cond.get("op", ">=")), want)
	_err("Unknown actor check '%s'." % check)
	return false


func check_all(conds: Array, map_id := "", event_id := "") -> bool:
	for c in conds:
		if c is Dictionary and not check_condition(c, map_id, event_id):
			return false
	return true


# --- timers ---------------------------------------------------------------------------------

## Where a visible timer is drawn (RPG Maker 2003 keeps timer 2 top left and timer 1 top right).
const TIMER_POSITIONS := ["top_right", "top_left", "bottom_left", "bottom_right"]
## What a timer does while a battle runs: hold, keep counting, or end the battle at 0.
const TIMER_BATTLE_MODES := ["pause", "count", "abort"]


## The dictionary of timer `id` ("1" or "2"; anything else reads timer 1), creating the default.
func timer(id) -> Dictionary:
	var key := "1" if str(id) != "2" else "2"
	if not timers.has(key):
		timers[key] = {"seconds": 0.0, "running": false, "visible": false,
			"position": "top_right" if key == "1" else "top_left", "battle": "pause"}
	return timers[key]


## Whole seconds a timer has left (0 once it has run out; never negative).
func timer_seconds(id) -> int:
	return maxi(0, ceili(float(timer(id).get("seconds", 0.0))))


## Control Timer's Set: stores the time and the display options. A running timer keeps running.
func set_timer(id, seconds: float, visible := true, position := "top_right", battle := "pause") -> void:
	var t := timer(id)
	t.seconds = maxf(0.0, seconds)
	t.visible = visible
	t.position = position if TIMER_POSITIONS.has(position) else "top_right"
	t.battle = battle if TIMER_BATTLE_MODES.has(battle) else "pause"
	changed.emit()


## Control Timer's Start: begins (or resumes) counting down. A timer at 0 does not start.
func start_timer(id) -> void:
	var t := timer(id)
	t.running = float(t.get("seconds", 0.0)) > 0.0
	changed.emit()


## Control Timer's Stop: holds the timer where it is (Set is what clears or re-arms it).
func stop_timer(id) -> void:
	timer(id).running = false
	changed.emit()


## Counts the running timers down and returns the ids that just reached 0 (those stop). In a
## battle a "pause" timer holds, "count" and "abort" keep going (rpg_game calls this every frame
## and ends the battle for an "abort" timer that ran out).
func tick_timers(delta: float, in_battle := false) -> Array[String]:
	var done: Array[String] = []
	for id in ["1", "2"]:
		var t: Dictionary = timer(id)
		if not bool(t.get("running", false)):
			continue
		if in_battle and str(t.get("battle", "pause")) == "pause":
			continue
		t.seconds = maxf(0.0, float(t.get("seconds", 0.0)) - maxf(0.0, delta))
		if float(t.seconds) <= 0.0:
			t.running = false
			done.append(id)
	return done


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
		"self_variables": self_variables.duplicate(),
		"gold": gold,
		"inventory": inventory.duplicate(true),
		"party": Array(party),
		"actors": actor_data,
		"event_changes": event_changes.duplicate(true),
		"spawned_events": spawned_events.duplicate(true),
		"followers_visible": followers_visible,
		"vehicles": vehicles.duplicate(true),
		"riding": riding,
		"access": access.duplicate(),
		"play_time": play_time,
		"timers": timers.duplicate(true),
		"steps": steps,
		"walk_steps": walk_steps,
		"player_transparent": player_transparent,
		"map_name_display": map_name_display,
		"music_overrides": music_overrides.duplicate(true),
		"map_overrides": map_overrides.duplicate(true),
		"tile_changes": tile_changes.duplicate(true),
		"windowskin": windowskin,
		"counters": counters.duplicate(),
		"last_used": last_used.duplicate(),
	}


func from_dict(d: Dictionary, battler_script: Script = null) -> void:
	switches = d.get("switches", {}).duplicate()
	variables = {}
	var vars: Dictionary = d.get("variables", {})
	for id in vars:
		var c: Variant = coerce(variable_type(id), vars[id])
		variables[id] = c if c != null else vars[id]
	self_switches = d.get("self_switches", {}).duplicate()
	self_variables = d.get("self_variables", {}).duplicate() if d.get("self_variables") is Dictionary else {}
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
	spawned_events = d.get("spawned_events", {}).duplicate(true) if d.get("spawned_events") is Dictionary else {}
	followers_visible = bool(d.get("followers_visible", true))
	# Saves from before vehicles existed start with the vehicles where a new game has them.
	vehicles = d.get("vehicles", {}).duplicate(true) if d.get("vehicles") is Dictionary else (RPGVehicles.initial_state(data) if data else {})
	riding = str(d.get("riding", ""))
	access = {"menu": true, "save": true, "encounters": true}
	if d.get("access") is Dictionary:
		for k in d.access:
			access[k] = bool(d.access[k])
	play_time = float(d.get("play_time", 0.0))
	# Saves from before timers existed start with both at their defaults.
	timers = d.get("timers", {}).duplicate(true) if d.get("timers") is Dictionary else {}
	timer("1")
	timer("2")
	steps = int(d.get("steps", 0))
	walk_steps = int(d.get("walk_steps", 0))
	player_transparent = bool(d.get("player_transparent", false))
	map_name_display = bool(d.get("map_name_display", true))
	music_overrides = d.get("music_overrides", {}).duplicate(true) if d.get("music_overrides") is Dictionary else {}
	map_overrides = d.get("map_overrides", {}).duplicate(true) if d.get("map_overrides") is Dictionary else {}
	tile_changes = d.get("tile_changes", {}).duplicate(true) if d.get("tile_changes") is Dictionary else {}
	windowskin = str(d.get("windowskin", ""))
	counters = {"saves": 0, "battles": 0, "victories": 0, "defeats": 0, "escapes": 0}
	if d.get("counters") is Dictionary:
		for k in counters:
			counters[k] = int(d.counters.get(k, 0))
	last_used = d.get("last_used", {}).duplicate() if d.get("last_used") is Dictionary else {}
	changed.emit()


func _err(msg: String) -> void:
	errors.append(msg)
	if errors.size() > 100:
		errors.pop_front()
	push_warning("RPG: " + msg)
