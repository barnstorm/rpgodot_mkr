class_name RPGRuleSystem
extends RefCounted
## Generic, data-driven rule system (stats, combat math, progression).
##
## The behaviour comes from `rpg/rules/<name>/rules.json` (see rules/classic/rules.json for a
## documented example). A project may add `rules.gd` next to it: a script that extends
## RPGRuleSystem and overrides any public step (hit_check, damage, apply_action, gain_exp...).
## apply_action() calls the public steps through `self`, so overrides take effect everywhere.
##
## `db` is duck-typed: it needs `record(type: String, id: String) -> Dictionary` (empty when
## missing) and `records(type: String) -> Array`. The runtime passes RPGProjectData.
##
## Formula environments: a = user snapshot, b = target snapshot, v = `variables`,
## s = the action being used (resolved skill/item/attack fields), rng = `rng`.
## Formula errors are reported with push_error naming the record, field and formula text and
## stored in `last_error`; they never silently count as 0.

const RULES_DIR := "res://rpg/rules"
const SHIPPED_DIR := "res://addons/rpg/runtime/rules"

## Built-in English fallbacks for battle text. Projects override them in terms.json with
## records {id: "battle_<key>", text}.
const DEFAULT_TERMS := {
	"attack": "%1 attacks!",
	"guard": "%1 is guarding.",
	"wait": "%1 waits.",
	"use_skill": "%1 uses %2!",
	"use_item": "%1 uses %2!",
	"cannot_use": "%1 can't use %2!",
	"damage": "%1 takes %2 damage!",
	"no_damage": "%1 takes no damage.",
	"recover": "%1 recovers %2 %3!",
	"resource_damage": "%1 loses %2 %3!",
	"miss": "%1 missed!",
	"evade": "%1 dodged the attack!",
	"critical": "A critical hit!",
	"state_added": "%1 is affected by %2!",
	"state_removed": "%1 is no longer affected by %2.",
	"state_resisted": "%1 resisted %2.",
	"knockout": "%1 falls!",
	"revive": "%1 is revived!",
	"escape": "The party escaped!",
	"escape_fail": "Couldn't escape!",
	"no_escape": "There is no escape!",
	"appear": "%1 appears!",
	"victory": "Victory!",
	"defeat": "The party has fallen...",
	"exp": "Gained %1 EXP!",
	"gold": "Found %1 gold!",
	"item_found": "Found %1!",
	"level_up": "%1 is now level %2!",
	"learned": "%1 learned %2!",
	"stat_up": "%1's %2 went up by %3!",
	"slip": "%1 takes %2 damage from %3!",
	"nothing": "Nothing happened.",
}

var definition := {}
var db = null
var rng := RPGRandom.new()
var variables := {}            ## formula `v` (the runtime may share its variables dict)
var rules_id := ""
var last_error := ""
var report_errors := true      ## push_error on formula failures
## Battle hook (set by RPGBattleCore only while it applies an action): called as
## (user, target, action, value) -> new value for every damage roll, after variance, critical and
## guard. Unset: no change.
var damage_filter: Callable

var _stat_defs := {}
var _stat_order: Array = []
var _res_defs := {}
var _res_order: Array = []


# --------------------------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------------------------

## Loads `rpg/rules/<name>/` (falling back to the copy shipped in the addon).
static func load_rules(rule_name: String, p_db) -> RPGRuleSystem:
	for base_dir in [RULES_DIR, SHIPPED_DIR]:
		var dir: String = base_dir.path_join(rule_name)
		if FileAccess.file_exists(dir.path_join("rules.json")):
			return load_rules_from_dir(dir, p_db)
	push_error("Rule system '%s' not found in %s or %s" % [rule_name, RULES_DIR, SHIPPED_DIR])
	return null


## Loads rules.json from `dir`; if `dir/rules.gd` exists it is instantiated instead of the
## base class (it must extend RPGRuleSystem).
static func load_rules_from_dir(dir: String, p_db) -> RPGRuleSystem:
	var parsed := RPGJson.parse_file(dir.path_join("rules.json"))
	if not parsed.ok:
		push_error("Rule system: %s" % parsed.error)
		return null
	if not (parsed.data is Dictionary):
		push_error("Rule system: %s/rules.json must hold an object" % dir)
		return null
	var rs: RPGRuleSystem = null
	var script_path := dir.path_join("rules.gd")
	if ResourceLoader.exists(script_path):
		var script: Script = load(script_path)
		var inst: Variant = script.new() if script != null else null
		if inst is RPGRuleSystem:
			rs = inst
		else:
			push_error("Rule system: %s must extend RPGRuleSystem" % script_path)
			return null
	else:
		rs = RPGRuleSystem.new()
	rs.setup(parsed.data, p_db)
	return rs


func setup(p_definition: Dictionary, p_db) -> void:
	definition = p_definition
	db = p_db
	rules_id = str(definition.get("id", ""))
	_stat_defs.clear()
	_stat_order.clear()
	for s in definition.get("stats", []):
		_stat_defs[s.id] = s
		_stat_order.append(s.id)
	_res_defs.clear()
	_res_order.clear()
	for r in definition.get("resources", []):
		_res_defs[r.id] = r
		_res_order.append(r.id)


## Checks that every formula in the definition compiles. Returns readable problems.
func validate() -> Array:
	var problems := []
	_collect_formula_problems(definition, "rules", problems)
	for r in _res_order:
		var ms: String = _res_defs[r].get("max_stat", "")
		if ms != "" and not _stat_defs.has(ms):
			problems.append("resource '%s' uses unknown max_stat '%s'" % [r, ms])
	if not _res_defs.has(life_resource()):
		problems.append("life_resource '%s' is not a declared resource" % life_resource())
	return problems


func _collect_formula_problems(v: Variant, path: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			var p := "%s.%s" % [path, k]
			if v[k] is String and _is_formula_key(k):
				var err := RPGFormula.check(v[k])
				if err != "":
					out.append("%s formula '%s': %s" % [p, v[k], err])
			else:
				_collect_formula_problems(v[k], p, out)
	elif v is Array:
		for i in v.size():
			if v[i] is String and path.ends_with(".steps"):
				var err2 := RPGFormula.check(v[i])
				if err2 != "":
					out.append("%s[%d] formula '%s': %s" % [path, i, v[i], err2])
			else:
				_collect_formula_problems(v[i], "%s[%d]" % [path, i], out)


static func _is_formula_key(k: String) -> bool:
	return k in ["formula", "chance", "bonus", "target", "speed",
		"battle_start", "battle_end", "gain_on_damage", "gain_on_use", "regen"]


# --------------------------------------------------------------------------------------------
# Declarations
# --------------------------------------------------------------------------------------------

func stats() -> Array:
	return definition.get("stats", []).duplicate(true)


func resources() -> Array:
	return definition.get("resources", []).duplicate(true)


func capabilities() -> Array:
	return definition.get("capabilities", []).duplicate()


func trait_kinds() -> Array:
	return definition.get("traits", []).duplicate(true)


func life_resource() -> String:
	return str(definition.get("life_resource", "hp"))


func death_state() -> String:
	return str(definition.get("death_state", "knockout"))


func has_capability(cap: String) -> bool:
	return capabilities().has(cap)


# --------------------------------------------------------------------------------------------
# Database helpers
# --------------------------------------------------------------------------------------------

func _rec(type: String, id: String) -> Dictionary:
	if db == null or id == "":
		return {}
	var r: Variant = db.record(type, id)
	return r if r is Dictionary else {}


## Battle text from terms.json record "battle_<key>" (field "text"), falling back to
## DEFAULT_TERMS. %1, %2, %3 are replaced by args.
func term(key: String, args: Array = []) -> String:
	var t := _rec("terms", "battle_" + key)
	var text: String = str(t.get("text", DEFAULT_TERMS.get(key, key)))
	for i in range(args.size() - 1, -1, -1):
		text = text.replace("%" + str(i + 1), str(args[i]))
	# \G is the currency unit, as in messages (one source: RPGProjectData.currency()).
	if text.contains("\\G"):
		text = text.replace("\\G", db.currency() if db != null and db.has_method("currency") else "G")
	return text


func _slot_kind(slot: String) -> String:
	var types := _rec("types", "equip_slots")
	for e in types.get("entries", []):
		if e is Dictionary and e.get("id", "") == slot:
			return str(e.get("kind", ""))
	return "weapon" if slot == "weapon" else ""


## The weapon or armor record equipped in `slot`.
func equip_record(slot: String, item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	match _slot_kind(slot):
		"weapon":
			return _rec("weapons", item_id)
		"armor":
			return _rec("armors", item_id)
	var r := _rec("weapons", item_id)
	return r if not r.is_empty() else _rec("armors", item_id)


## The weapon or armor record equipped in `slot` of `b`, honouring dual wield.
func equip_record_of(b: RPGBattler, slot: String, item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	if equip_slot_kind(b, slot) == "weapon":
		return _rec("weapons", item_id)
	return equip_record(slot, item_id)


## "weapon" or "armor" for `slot` of `b`. A "dual_wield" trait {kind: "dual_wield", id: slot}
## (on the actor, class or a state; id defaults to "shield") turns that slot into a weapon slot.
func equip_slot_kind(b: RPGBattler, slot: String) -> String:
	if b != null and b.is_actor() and dual_wield_slots(b).has(slot):
		return "weapon"
	return _slot_kind(slot)


## Slots that hold a second weapon (trait "dual_wield").
func dual_wield_slots(b: RPGBattler) -> Array:
	var out := []
	for t in _intrinsic_traits(b, "dual_wield"):
		var s := str(t.get("id", ""))
		out.append(s if s != "" else "shield")
	return out


## True when a "seal_equip" trait {kind: "seal_equip", id: slot} (actor, class or state) seals
## `slot`: whatever is in it does not count, and menus should not let it change.
func is_slot_sealed(b: RPGBattler, slot: String) -> bool:
	for t in _intrinsic_traits(b, "seal_equip"):
		if str(t.get("id", "")) == slot:
			return true
	return false


## Traits of `kind` from the battler's own record, class and states (not equipment, so the
## equipment list itself can depend on them).
func _intrinsic_traits(b: RPGBattler, kind: String) -> Array:
	var out := []
	if b == null:
		return out
	var srcs := []
	if b.is_actor():
		srcs.append(_rec("actors", b.id))
		srcs.append(_rec("classes", b.class_id))
	else:
		srcs.append(_rec("enemies", b.id))
	for s in b.states:
		srcs.append(_rec("states", s.id))
	for src in srcs:
		for t in src.get("traits", []):
			if t is Dictionary and t.get("kind", "") == kind:
				out.append(t)
	return out


func _equip_records(b: RPGBattler) -> Array:
	var out := []
	if not b.is_actor():
		return out
	var sealed := []
	for t in _intrinsic_traits(b, "seal_equip"):
		sealed.append(str(t.get("id", "")))
	var dual := dual_wield_slots(b)
	for slot in b.equips:
		if sealed.has(slot):
			continue
		var item_id := str(b.equips[slot])
		var r := _rec("weapons", item_id) if dual.has(slot) else equip_record(slot, item_id)
		if not r.is_empty():
			out.append(r)
	return out


func battler_record(b: RPGBattler) -> Dictionary:
	return _rec("actors" if b.is_actor() else "enemies", b.id)


# --------------------------------------------------------------------------------------------
# Traits
# --------------------------------------------------------------------------------------------

## Records whose "traits" apply to `b`: actor, class, equipment (or enemy), then states.
func trait_sources(b: RPGBattler) -> Array:
	var out := []
	if b.is_actor():
		out.append(_rec("actors", b.id))
		out.append(_rec("classes", b.class_id))
		out.append_array(_equip_records(b))
	else:
		out.append(_rec("enemies", b.id))
	for s in b.states:
		out.append(_rec("states", s.id))
	return out


## Every trait on `b`, optionally only of `kind`. Trait shape: {kind, id?, value?}.
func traits(b: RPGBattler, kind: String = "") -> Array:
	var out := []
	for src in trait_sources(b):
		for t in src.get("traits", []):
			if t is Dictionary and (kind == "" or t.get("kind", "") == kind):
				out.append(t)
	return out


## Product of percent traits (value 150 = x1.5) of `kind` for `id`. 1.0 when none.
func trait_rate(b: RPGBattler, kind: String, id: String = "") -> float:
	var rate := 1.0
	for t in traits(b, kind):
		if id == "" or str(t.get("id", "")) == id:
			rate *= float(t.get("value", 100)) / 100.0
	return rate


func trait_sum(b: RPGBattler, kind: String, id: String = "") -> float:
	var total := 0.0
	for t in traits(b, kind):
		if id == "" or str(t.get("id", "")) == id:
			total += float(t.get("value", 0))
	return total


func has_trait(b: RPGBattler, kind: String, id: String = "") -> bool:
	for t in traits(b, kind):
		if id == "" or str(t.get("id", "")) == id:
			return true
	return false


func attack_element(b: RPGBattler) -> String:
	for t in traits(b, "attack_element"):
		return str(t.get("id", ""))
	return ""


# --------------------------------------------------------------------------------------------
# Stats and snapshots
# --------------------------------------------------------------------------------------------

## All effective stats of `b` in declaration order:
## base (battler) + class growth (actors) + derived formula + equipment params, times
## stat_rate traits, clamped to the stat's min/max, int unless the stat says "float".
func stat_block(b: RPGBattler) -> Dictionary:
	var out := {}
	var growth: Dictionary = _rec("classes", b.class_id).get("growth", {}) if b.is_actor() else {}
	var equips := _equip_records(b)
	var rate_traits := traits(b, "stat_rate")
	var extra := {}
	for sid in _stat_order:
		var def: Dictionary = _stat_defs[sid]
		var has_base: bool = b.base.has(sid)
		var value := float(b.base.get(sid, 0))
		if growth.has(sid):
			value += _growth_value(growth[sid], b.level)
		# Derived stats: an enemy record that states the value directly wins.
		if def.has("formula") and not (b.is_enemy() and has_base):
			if extra.is_empty():
				extra = _snapshot_fields(b)
			var partial := _partial_snapshot(b, out, extra)
			var r := _eval(str(def.formula), {"a": partial, "v": variables, "s": {}, "rng": rng}, "stat '%s'" % sid)
			if r.ok:
				value += float(r.value)
		for e in equips:
			value += float(e.get("params", {}).get(sid, 0))
		for t in rate_traits:
			if str(t.get("id", "")) == sid:
				value *= float(t.get("value", 100)) / 100.0
		value = clampf(value, float(def.get("min", -1.0e9)), float(def.get("max", 1.0e9)))
		out[sid] = value if def.get("type", "int") == "float" else roundi(value)
	return out


func effective_stat(b: RPGBattler, stat: String) -> Variant:
	if not _stat_defs.has(stat):
		push_error("[rules %s] unknown stat '%s'" % [rules_id, stat])
		return 0
	return stat_block(b)[stat]


func max_resource(b: RPGBattler, res: String, block: Dictionary = {}) -> int:
	var def: Dictionary = _res_defs.get(res, {})
	var ms: String = def.get("max_stat", "")
	if ms != "":
		if block.is_empty():
			block = stat_block(b)
		return int(block.get(ms, 0))
	return int(def.get("max", 0))


## Built-in growth shapes (exponents) for curve entries; rules.json "growth_shapes" adds more.
const GROWTH_SHAPES := {"linear": 1.0, "early": 0.75, "late": 1.5}


## A class growth entry for one stat at `level`. Accepted forms:
##   {base, per_level, accel?}            base + per_level * (level - 1) (+ accel * (level - 1)^2)
##   {at_1, at_99, shape?}                parameter curve: at_1 + (at_99 - at_1) * t^exponent,
##                                        t = (level - 1) / 98 clamped to 0..1; shape is a name
##                                        (linear, early, late or rules.json "growth_shapes") or
##                                        an exponent number (< 1 grows early, > 1 grows late)
##   [v1, v2, ...]                        per-level table (index = level - 1)
##   number                               flat value
func _growth_value(g: Variant, level: int) -> float:
	if g is Dictionary and (g.has("at_1") or g.has("at_99")):
		var lo := float(g.get("at_1", 0))
		var hi := float(g.get("at_99", lo))
		var t := clampf(float(level - 1) / 98.0, 0.0, 1.0)
		return lo + (hi - lo) * pow(t, growth_exponent(g.get("shape", "linear")))
	if g is Dictionary:
		var n := float(level - 1)
		return float(g.get("base", 0)) + float(g.get("per_level", 0)) * n + float(g.get("accel", 0)) * n * n
	if g is Array:
		if g.is_empty():
			return 0.0
		return float(g[clampi(level - 1, 0, g.size() - 1)])
	if g is int or g is float:
		return float(g)
	return 0.0


## Exponent of a growth shape: a number, or a name from rules.json "growth_shapes" / GROWTH_SHAPES.
func growth_exponent(shape: Variant) -> float:
	if shape is int or shape is float:
		return maxf(0.01, float(shape))
	var name := str(shape)
	var shapes: Dictionary = definition.get("growth_shapes", {})
	if shapes.has(name):
		return maxf(0.01, float(shapes[name]))
	if GROWTH_SHAPES.has(name):
		return float(GROWTH_SHAPES[name])
	push_warning("[rules %s] unknown growth shape '%s', using linear" % [rules_id, name])
	return 1.0


## Extra snapshot values declared in rules.json "snapshot_fields", e.g. weapon dice:
## {"weapon_dice": {"equip_slot": "weapon", "field": "dice", "record_field": "dice", "default": "1d2"}}
func _snapshot_fields(b: RPGBattler) -> Dictionary:
	var out := {}
	var fields: Dictionary = definition.get("snapshot_fields", {})
	for name in fields:
		var def: Dictionary = fields[name]
		var value: Variant = def.get("default", 0)
		var found := false
		if b.is_actor() and def.has("equip_slot"):
			var slot: String = def.equip_slot
			var er := equip_record_of(b, slot, str(b.equips.get(slot, "")))
			if er.has(def.get("field", name)):
				value = er[def.get("field", name)]
				found = true
		if not found and b.is_actor() and def.has("class_field"):
			var cls := _rec("classes", b.class_id)
			if cls.has(def.class_field):
				value = cls[def.class_field]
				found = true
		if not found and def.has("record_field"):
			var rec := battler_record(b)
			if rec.has(def.record_field):
				value = rec[def.record_field]
		out[name] = value
	return out


func _partial_snapshot(b: RPGBattler, stats_so_far: Dictionary, extra: Dictionary) -> Dictionary:
	var snap := {"id": b.id, "kind": b.kind, "level": b.level, "class": b.class_id,
		"stats": stats_so_far.duplicate(), "resources": b.resources.duplicate(), "states": b.state_ids()}
	for k in extra:
		snap[k] = extra[k]
	for k in stats_so_far:
		snap[k] = stats_so_far[k]
	return snap


## Frozen view of `b` for formulas: stats as flat keys (a.atk), resources (a.hp),
## maxima (a.max_hp), level, states, guarding, snapshot_fields; plus "stats",
## "resources" and "max" tables for stat()/resource().
func snapshot(b: RPGBattler) -> Dictionary:
	var block := stat_block(b)
	var snap := {
		"id": b.id, "kind": b.kind, "name": b.name, "class": b.class_id, "level": b.level,
		"exp": b.exp, "guarding": b.guarding, "index": b.index, "states": b.state_ids(),
		"stats": block, "resources": b.resources.duplicate(), "max": {},
	}
	var extra := _snapshot_fields(b)
	for k in extra:
		snap[k] = extra[k]
	for k in block:
		snap[k] = block[k]
	for rid in _res_order:
		var m := max_resource(b, rid, block)
		snap[rid] = int(b.resources.get(rid, 0))
		snap["max_" + rid] = m
		snap.max[rid] = m
	var trait_fields: Dictionary = definition.get("snapshot_traits", {})
	if not trait_fields.is_empty():
		var all := traits(b)
		for name in trait_fields:
			snap[name] = _trait_field(b, all, trait_fields[name])
	return snap


## A snapshot value computed from traits (rules.json "snapshot_traits"):
##   {"hit": {"kind": "hit_rate", "mode": "sum", "default": 95, "enemy_default": 95, "id"?: ""}}
## "sum" adds the trait values; "rate" multiplies them as percents (150 = x1.5) and gives a percent.
## When the battler has no trait of that kind, "default" (or "enemy_default" for enemies) is used:
## like the default features of a new class in RPG Maker VX Ace.
func _trait_field(b: RPGBattler, all: Array, def: Dictionary) -> int:
	var kind := str(def.get("kind", ""))
	var id_filter := str(def.get("id", ""))
	var rate_mode := str(def.get("mode", "sum")) == "rate"
	var found := false
	var total := 1.0 if rate_mode else 0.0
	for t in all:
		if str(t.get("kind", "")) != kind or (id_filter != "" and str(t.get("id", "")) != id_filter):
			continue
		found = true
		if rate_mode:
			total *= float(t.get("value", 100)) / 100.0
		else:
			total += float(t.get("value", 0))
	if not found:
		var d: Variant = def.get("enemy_default", def.get("default", 100 if rate_mode else 0)) if b.is_enemy() else def.get("default", 100 if rate_mode else 0)
		return int(d)
	return roundi(total * 100.0) if rate_mode else roundi(total)


func _snap_of(x: Variant) -> Dictionary:
	if x is RPGBattler:
		return x.snapshot()
	if x is Dictionary:
		return x
	return {}


func _env(user: Variant, target: Variant, usable: Dictionary) -> Dictionary:
	return {"a": _snap_of(user), "b": _snap_of(target), "v": variables, "s": usable, "rng": rng}


## Evaluates `text` with a = user, b = target (battlers or snapshots). {ok, value, error}
func evaluate_formula(text: String, user: Variant = null, target: Variant = null, extra: Dictionary = {}) -> Dictionary:
	var env := _env(user, target, extra.get("s", {}))
	return _eval(text, env, str(extra.get("where", "formula")))


func _eval(text: String, env: Dictionary, where: String) -> Dictionary:
	var r := RPGFormula.evaluate_text(text, env)
	if not r.ok:
		last_error = "%s formula '%s': %s" % [where, text, r.error]
		if report_errors:
			push_error("[rules %s] %s" % [rules_id, last_error])
	return r


## Evaluates a field that may be a number or a formula string.
func _num_or_formula(v: Variant, env: Dictionary, where: String) -> Dictionary:
	if v is int or v is float:
		return {"ok": true, "value": v, "error": ""}
	if v is bool:
		return {"ok": true, "value": 1 if v else 0, "error": ""}
	return _eval(str(v), env, where)


# --------------------------------------------------------------------------------------------
# Battlers
# --------------------------------------------------------------------------------------------

## Connects a battler (e.g. one loaded from a save) to this rule system.
func attach(b: RPGBattler) -> void:
	b.rules = self
	b.life_resource = life_resource()
	b.death_state = death_state()


func new_actor_battler(actor_id: String, level: int = 0) -> RPGBattler:
	var rec := _rec("actors", actor_id)
	if rec.is_empty():
		push_error("[rules %s] unknown actor '%s'" % [rules_id, actor_id])
		return null
	var b := RPGBattler.new()
	attach(b)
	b.kind = "actor"
	b.id = actor_id
	b.name = str(rec.get("name", actor_id))
	b.class_id = str(rec.get("class", ""))
	b.base = (rec.get("base_stats", {}) as Dictionary).duplicate(true)
	b.equips = (rec.get("equips", {}) as Dictionary).duplicate(true)
	b.skills = (rec.get("skills", []) as Array).duplicate()
	var target_level := level if level > 0 else int(rec.get("initial_level", 1))
	target_level = clampi(target_level, 1, max_level(b))
	b.level = 1
	_apply_level_formulas(b, "on_create")
	_learn_skills(b, 1)
	for lv in range(2, target_level + 1):
		b.level = lv
		_apply_level_formulas(b, "on_level_up")
		_learn_skills(b, lv)
	b.exp = exp_for_level(b.class_id, b.level)
	recover_all(b)
	return b


func new_enemy_battler(enemy_id: String) -> RPGBattler:
	var rec := _rec("enemies", enemy_id)
	if rec.is_empty():
		push_error("[rules %s] unknown enemy '%s'" % [rules_id, enemy_id])
		return null
	var b := RPGBattler.new()
	attach(b)
	b.kind = "enemy"
	b.id = enemy_id
	b.name = str(rec.get("name", enemy_id))
	b.level = int(rec.get("level", 1))
	b.base = (rec.get("stats", {}) as Dictionary).duplicate(true)
	for a in rec.get("actions", []):
		var sk := str(a.get("skill", ""))
		if sk != "" and not sk in ["attack", "guard", "wait", "escape"] and not b.skills.has(sk):
			b.skills.append(sk)
	_apply_level_formulas(b, "on_create_enemy")
	recover_all(b)
	return b


## Restores every resource to its maximum and removes all states. A resource declared with
## "full_on_recover": false (e.g. TP) is only kept inside its limits.
func recover_all(b: RPGBattler) -> void:
	b.states.clear()
	var block := stat_block(b)
	for rid in _res_order:
		var m := max_resource(b, rid, block)
		if _res_defs[rid].get("full_on_recover", true):
			b.resources[rid] = m
		else:
			b.resources[rid] = clampi(int(b.resources.get(rid, 0)), 0, m)


## Battle setup for one battler (RPGBattleCore.start calls it). A resource with "battle_start"
## (a number or formula, a = the battler) is set to that value, e.g. TP "rand(0, 25)". A
## battler with a trait named by the resource's "keep_trait" (e.g. "preserve_tp") keeps its value.
func start_battle(b: RPGBattler) -> void:
	_reset_resources(b, "battle_start")


func _reset_resources(b: RPGBattler, key: String) -> void:
	for rid in _res_order:
		var def: Dictionary = _res_defs[rid]
		if not def.has(key):
			continue
		if str(def.get("keep_trait", "")) != "" and has_trait(b, str(def.keep_trait)):
			continue
		var env := {"a": snapshot(b), "b": {}, "v": variables, "s": {}, "rng": rng}
		var r := _num_or_formula(def[key], env, "resource '%s' %s" % [rid, key])
		if r.ok:
			b.set_resource(rid, clampi(int(r.value), 0, max_resource(b, rid)))


## Resources declared with a formula under `key` ("gain_on_damage", "gain_on_use", "regen")
## change `b` by the formula's result. `env` already holds a, b and s. Returns {resource: delta}.
func _gain_resources(b: RPGBattler, key: String, env: Dictionary, floor_life := false) -> Dictionary:
	var out := {}
	for rid in _res_order:
		var def: Dictionary = _res_defs[rid]
		if not def.has(key):
			continue
		var r := _num_or_formula(def[key], env, "resource '%s' %s" % [rid, key])
		if not r.ok or int(r.value) == 0:
			continue
		var cur := b.get_resource(rid)
		var low := mini(1, cur) if floor_life and rid == life_resource() else 0
		var new_value := clampi(cur + int(r.value), low, max_resource(b, rid))
		if new_value != cur:
			b.set_resource(rid, new_value)
			out[rid] = new_value - cur
	return out


## Keeps resources inside 0..max (after equipment or level changes).
func clamp_resources(b: RPGBattler) -> void:
	var block := stat_block(b)
	for rid in _res_order:
		b.resources[rid] = clampi(int(b.resources.get(rid, 0)), 0, max_resource(b, rid, block))


# --------------------------------------------------------------------------------------------
# States
# --------------------------------------------------------------------------------------------

## Chance multiplier for adding `state_id` to `b` (0 when resisted).
func state_chance_rate(b: RPGBattler, state_id: String) -> float:
	if has_trait(b, "state_resist", state_id):
		return 0.0
	return trait_rate(b, "state_rate", state_id)


## Adds a state with its record's duration. Adding the death state zeroes the life resource
## and clears other states. Returns true if the state was added.
func add_state(b: RPGBattler, state_id: String) -> bool:
	if b.has_state(state_id):
		return false
	if b.is_dead() and state_id != death_state():
		return false
	var rec := _rec("states", state_id)
	var turns := -1
	if rec.has("turns_min") or rec.has("turns_max"):
		var lo := int(rec.get("turns_min", rec.get("turns_max", 1)))
		var hi := int(rec.get("turns_max", lo))
		if hi > 0:
			# RPG Maker reading (VX Ace's remove_states_auto): a state whose roll is 0 still ends
			# at the end of the turn it was added in, like a roll of 1, so a duration of "0 to N
			# turns" can never make it permanent. Only "at most 0" (or no duration) means
			# "until removed".
			turns = maxi(1, rng.randi_range(mini(lo, hi), hi))
	if state_id == death_state():
		b.states.clear()
		b.resources[life_resource()] = 0
		b.guarding = false
	b.add_state(state_id, turns)
	return true


## Removes a state. Removing the death state revives with at least 1 life point.
func remove_state(b: RPGBattler, state_id: String) -> bool:
	if not b.remove_state(state_id):
		return false
	if state_id == death_state():
		b.resources[life_resource()] = maxi(1, int(b.resources.get(life_resource(), 0)))
	return true


func _state_name(state_id: String) -> String:
	return str(_rec("states", state_id).get("name", state_id))


## Restriction of the strongest state: "none", "cannot_use_skills" or "cannot_act".
func restriction(b: RPGBattler) -> String:
	var worst := "none"
	for s in b.states:
		var r := str(_rec("states", s.id).get("restriction", "none"))
		if r == "cannot_act":
			return r
		if r == "cannot_use_skills":
			worst = r
	return worst


func can_act(b: RPGBattler) -> bool:
	return b.is_alive() and restriction(b) != "cannot_act"


## End-of-turn processing for one battler: slip damage and state durations.
## Returns {damage, removed_states, lines, knocked_out}.
func tick_states(b: RPGBattler) -> Dictionary:
	var out := {"damage": 0, "removed_states": [], "lines": [], "knocked_out": false}
	if b.is_dead():
		return out
	# Regeneration: resources with a "regen" formula (a = the battler), e.g. HP Regen traits.
	# Negative regeneration never knocks out.
	if _has_resource_key("regen"):
		var env := {"a": snapshot(b), "b": {}, "v": variables, "s": {}, "rng": rng}
		var regen := _gain_resources(b, "regen", env, true)
		for rid in regen:
			var delta: int = regen[rid]
			if delta > 0:
				out.lines.append(term("recover", [b.name, delta, _resource_label(rid)]))
			else:
				out.lines.append(term("resource_damage", [b.name, -delta, _resource_label(rid)]))
				if rid == life_resource():
					out.damage += -delta
		if not regen.is_empty():
			out["regen"] = regen
	for s in b.states.duplicate():
		var rec := _rec("states", s.id)
		var slip: Dictionary = rec.get("slip", {})
		if not slip.is_empty() and b.is_alive():
			var res_id: String = slip.get("resource", life_resource())
			var m := max_resource(b, res_id)
			var amount := int(slip.get("amount", 0)) + int(float(m) * float(slip.get("percent", 0)) / 100.0)
			amount = maxi(amount, 1)
			var cur := b.get_resource(res_id)
			var floor_value := 0 if slip.get("can_kill", false) else 1
			var new_value := clampi(cur - amount, mini(floor_value, cur), m)
			b.set_resource(res_id, new_value)
			if res_id == life_resource():
				out.damage += cur - new_value
			out.lines.append(term("slip", [b.name, cur - new_value, rec.get("name", s.id)]))
			if res_id == life_resource() and new_value <= 0:
				add_state(b, death_state())
				out.knocked_out = true
				out.lines.append(term("knockout", [b.name]))
				return out
		if s.turns > 0:
			s.turns -= 1
			if s.turns == 0:
				remove_state(b, s.id)
				out.removed_states.append(s.id)
				out.lines.append(_state_message(rec, "removed", b.name, s.id))
	return out


## Battle cleanup: drop battle-only states and flags; resources with "battle_end" (a number or
## formula) are reset to it, e.g. TP back to 0.
func end_battle(b: RPGBattler) -> void:
	for s in b.states.duplicate():
		if _rec("states", s.id).get("remove_at_battle_end", false):
			b.remove_state(s.id)
	b.guarding = false
	b.action = {}
	_reset_resources(b, "battle_end")


func _has_resource_key(key: String) -> bool:
	for rid in _res_order:
		if _res_defs[rid].has(key):
			return true
	return false


# --------------------------------------------------------------------------------------------
# Map walking (RPG Maker's on_player_walk; RPGPlayer.party_walk calls these once per step)
# --------------------------------------------------------------------------------------------

## Steps between "turns" on the map (MV/MZ and VX Ace's turn_end_on_map: every 20 steps each
## actor regenerates, takes slip damage and counts down state turns). rules.json
## "map_turn_steps" sets it (0 = never). Without it, rule systems whose resources regenerate
## (VX Ace style) use 20, others 0: RPG Maker 2000/2003 states change HP per N steps instead
## (map_step_changes).
func map_turn_steps() -> int:
	if definition.has("map_turn_steps"):
		return maxi(0, int(definition.map_turn_steps))
	return 20 if _has_resource_key("regen") else 0


## Steps after which a state wears off while walking (state "remove_by_walking" and
## "steps_to_remove"), or 0 when walking doesn't remove it.
func state_walk_steps(state_id: String) -> int:
	var rec := _rec("states", state_id)
	if not bool(rec.get("remove_by_walking", false)):
		return 0
	return maxi(1, int(rec.get("steps_to_remove", 1)))


## One step on foot for `b`: counts down the states removed by walking. The count is kept on
## the state entry ("steps", saved with the battler) and starts with the first step after the
## state was added, so a state with N steps is gone after N steps.
## Returns a map result (see _map_result); `messages` holds the states' own "removed" messages.
func walk_state_steps(b: RPGBattler) -> Dictionary:
	var out := _map_result()
	for s in b.states.duplicate():
		var n := state_walk_steps(str(s.id))
		if n <= 0:
			s.erase("steps")
			continue
		var left := int(s.get("steps", n)) - 1
		if left > 0:
			s["steps"] = left
			continue
		if remove_state(b, str(s.id)):
			out.removed_states.append(str(s.id))
			_map_message(out, _rec("states", str(s.id)), "removed", b.name)
	return out


## The map's end of turn for `b` (MV's turnEndOnMap), every map_turn_steps() steps:
## regeneration ("regen" resources, e.g. HP Regen traits), the states' "slip" damage, and state
## turns counting down (a state whose turns run out is removed, with its "removed" message).
## `slip_death` is the System option "Knockout by slip damage": when it is off, this damage leaves
## at least 1 point of the life resource. Returns a map result (see _map_result).
func map_turn_end(b: RPGBattler, slip_death := false) -> Dictionary:
	var out := _map_result()
	if b.is_dead():
		return out
	if _has_resource_key("regen"):
		var env := {"a": snapshot(b), "b": {}, "v": variables, "s": {}, "rng": rng}
		var regen := _gain_resources(b, "regen", env, not slip_death)
		for rid in regen:
			_note_map_change(out, rid, int(regen[rid]))
	for s in b.states.duplicate():
		if b.is_dead() or not b.has_state(str(s.id)):
			continue
		var rec := _rec("states", str(s.id))
		var slip: Variant = rec.get("slip", {})
		if slip is Dictionary and not slip.is_empty():
			var res_id := str(slip.get("resource", life_resource()))
			if _res_defs.has(res_id):
				var m := max_resource(b, res_id)
				var amount := maxi(int(slip.get("amount", 0)) + int(float(m) * float(slip.get("percent", 0)) / 100.0), 1)
				_map_change(b, res_id, -amount, slip_death, out)
		if int(s.turns) > 0:
			s.turns = int(s.turns) - 1
			if s.turns == 0 and remove_state(b, str(s.id)):
				out.removed_states.append(str(s.id))
				_map_message(out, rec, "removed", b.name)
	_check_map_knockout(b, out)
	return out


## RPG Maker 2000/2003 states: "map_hp_change" {resource, effect: damage|recover,
## kind: flat|percent (of the resource's maximum), value, steps} changes the resource every
## `steps` steps the party walks. `walk_steps` is the party's count of steps on foot.
## Damage leaves at least 1 life point unless `slip_death` is on. Returns a map result.
func map_step_changes(b: RPGBattler, walk_steps: int, slip_death := false) -> Dictionary:
	var out := _map_result()
	if b.is_dead():
		return out
	for s in b.states.duplicate():
		if b.is_dead() or not b.has_state(str(s.id)):
			continue
		var c: Variant = _rec("states", str(s.id)).get("map_hp_change")
		if not (c is Dictionary) or c.is_empty():
			continue
		var every := int(c.get("steps", 1))
		if every <= 0 or walk_steps % every != 0:
			continue
		var res_id := str(c.get("resource", life_resource()))
		if not _res_defs.has(res_id):
			continue
		var value := maxi(0, int(c.get("value", 0)))
		if str(c.get("kind", "flat")) == "percent" and value > 0:
			value = maxi(1, int(float(max_resource(b, res_id)) * float(value) / 100.0))
		if value == 0:
			continue
		_map_change(b, res_id, -value if str(c.get("effect", "damage")) == "damage" else value, slip_death, out)
	_check_map_knockout(b, out)
	return out


## A damage floor: `amount` off the life resource of a living battler. As in RPG Maker, a floor
## never knocks anyone out (at least 1 point is left). Returns a map result.
func floor_damage(b: RPGBattler, amount: int) -> Dictionary:
	var out := _map_result()
	if b.is_dead() or amount <= 0:
		return out
	_map_change(b, life_resource(), -amount, false, out)
	return out


## What a map step did to one battler: {damage (life points lost), changes {resource: delta},
## removed_states, messages, knocked_out}.
static func _map_result() -> Dictionary:
	return {"damage": 0, "changes": {}, "removed_states": [], "messages": [], "knocked_out": false}


func _note_map_change(out: Dictionary, res_id: String, delta: int) -> void:
	if delta == 0:
		return
	out.changes[res_id] = int(out.changes.get(res_id, 0)) + delta
	if res_id == life_resource() and delta < 0:
		out.damage += -delta


## Changes a resource by `delta` inside 0..max; damage to the life resource stops at 1 unless
## `can_kill`.
func _map_change(b: RPGBattler, res_id: String, delta: int, can_kill: bool, out: Dictionary) -> void:
	var cur := b.get_resource(res_id)
	var low := 0
	if delta < 0 and res_id == life_resource() and not can_kill:
		low = mini(1, cur)
	var new_value := clampi(cur + delta, low, max_resource(b, res_id))
	if new_value != cur:
		b.set_resource(res_id, new_value)
		_note_map_change(out, res_id, new_value - cur)


## A battler whose life reached 0 on the map gets the death state (and its "added" message).
func _check_map_knockout(b: RPGBattler, out: Dictionary) -> void:
	if b.has_state(death_state()) or not b.resources.has(life_resource()) or b.get_resource(life_resource()) > 0:
		return
	add_state(b, death_state())
	out.knocked_out = true
	_map_message(out, _rec("states", death_state()), "added", b.name)


## On the map, a state's message shows only when its record has one (as in RPG Maker, where
## an empty message shows nothing); %1 is the battler's name.
func _map_message(out: Dictionary, rec: Dictionary, which: String, who: String) -> void:
	var msgs: Variant = rec.get("messages", {})
	if msgs is Dictionary and str(msgs.get(which, "")) != "":
		out.messages.append(str(msgs[which]).replace("%1", who))


func _state_message(rec: Dictionary, which: String, who: String, state_id: String) -> String:
	var msgs: Dictionary = rec.get("messages", {})
	if msgs.has(which) and str(msgs[which]) != "":
		return str(msgs[which]).replace("%1", who)
	return term("state_added" if which == "added" else "state_removed", [who, rec.get("name", state_id)])


# --------------------------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------------------------

## Turns an action {kind: attack|skill|item, skill, item} into the fields the rules use
## (s in formulas): {kind, id, name, formula, damage_type, resource, element, hit, hit_type,
## variance, critical, effects, scope, cost, message, speed}. Empty for guard/escape/wait.
func resolve_action(user: RPGBattler, action: Dictionary) -> Dictionary:
	var u := {}
	match str(action.get("kind", "")):
		"attack":
			u = (definition.get("attack", {}) as Dictionary).duplicate(true)
			u.kind = "attack"
			u.id = "attack"
			if str(u.get("element", "")) == "" and user != null:
				u.element = attack_element(user)
			if not u.has("name"):
				u.name = "Attack"
		"skill":
			var sid := str(action.get("skill", ""))
			var rec := _rec("skills", sid)
			if rec.is_empty():
				return {}
			u = rec.duplicate(true)
			u.kind = "skill"
		"item":
			var iid := str(action.get("item", ""))
			var rec2 := _rec("items", iid)
			if rec2.is_empty():
				return {}
			u = rec2.duplicate(true)
			u.kind = "item"
		_:
			return {}
	# Extra fields every action has in formulas (rules.json "usable_defaults", e.g. tp_gain: 0).
	var defaults: Dictionary = definition.get("usable_defaults", {})
	for k in defaults:
		if not u.has(k):
			u[k] = defaults[k]
	var dmg_cfg: Dictionary = definition.get("damage", {})
	u.id = str(u.get("id", ""))
	u.name = str(u.get("name", u.id))
	u.formula = str(u.get("formula", ""))
	if not u.has("damage_type"):
		u.damage_type = "damage" if u.formula != "" else "none"
	u.resource = str(u.get("resource", life_resource()))
	u.element = str(u.get("element", ""))
	u.hit = u.get("hit", 100)
	u.hit_type = str(u.get("hit_type", "certain"))
	u.variance = u.get("variance", dmg_cfg.get("variance", 0))
	u.critical = bool(u.get("critical", false))
	u.effects = u.get("effects", [])
	u.scope = str(u.get("scope", "one_enemy"))
	u.cost = u.get("cost", {})
	u.speed = u.get("speed", 0)
	return u


## Whether `user` may use the action now (alive, not restricted, can pay the cost).
func can_use(user: RPGBattler, action: Dictionary) -> bool:
	if not can_act(user):
		return false
	var kind := str(action.get("kind", ""))
	if kind in ["guard", "wait", "escape", "attack"]:
		return true
	var u := resolve_action(user, action)
	if u.is_empty():
		return false
	if kind == "skill":
		if restriction(user) == "cannot_use_skills":
			return false
		if not skill_type_usable(user, str(u.get("skill_type", ""))):
			return false
		var cost: Dictionary = u.cost
		for res_id in cost:
			if user.get_resource(res_id) < int(cost[res_id]):
				return false
	return true


## Skill types. A "seal_skill_type" trait (id = skill type) blocks that type. When the rule system
## declares the trait kind "add_skill_type", actors may only use skills whose skill_type they
## were given by such a trait (skills without a type stay usable; enemies are not limited).
func skill_type_usable(b: RPGBattler, skill_type: String) -> bool:
	if skill_type == "":
		return true
	if has_trait(b, "seal_skill_type", skill_type):
		return false
	if b.is_actor() and declares_trait("add_skill_type"):
		return has_trait(b, "add_skill_type", skill_type)
	return true


## True when rules.json "traits" declares `kind`.
func declares_trait(kind: String) -> bool:
	for t in definition.get("traits", []):
		if t is Dictionary and str(t.get("kind", "")) == kind:
			return true
	return false


## How many actions `b` takes this turn: 1, plus 1 for each "action_times" trait whose value
## (a percent chance) passes.
func action_times(b: RPGBattler) -> int:
	var n := 1
	for t in traits(b, "action_times"):
		if rng.chance_percent(float(t.get("value", 100))):
			n += 1
	return n


func pay_cost(user: RPGBattler, action: Dictionary) -> void:
	if str(action.get("kind", "")) != "skill":
		return
	var u := resolve_action(user, action)
	var cost: Dictionary = u.get("cost", {})
	for res_id in cost:
		user.set_resource(res_id, maxi(0, user.get_resource(res_id) - int(cost[res_id])))


## Order value for the turn queue (higher acts first): rules "turn_order.speed" formula plus
## the action's own "speed" field.
func action_speed(b: RPGBattler, action: Dictionary) -> int:
	var cfg: Dictionary = definition.get("turn_order", {})
	var speed := 0
	var u := resolve_action(b, action)
	if cfg.has("speed"):
		var r := _eval(str(cfg.speed), _env(b, null, u), "turn_order.speed")
		if r.ok:
			speed = int(r.value)
	return speed + int(u.get("speed", 0))


## Hit resolution. rules.json "hit_check" maps a hit_type ("physical", "magical", ...) to:
##   {"type": "percent", "steps": [formula, ...]}  every step is a percent chance that must pass
##     (step 1 failing = miss, later steps failing = evaded)
##   {"type": "roll", "roll": "1d20", "bonus": formula, "target": formula,
##     "natural_hit": 20, "natural_miss": 1}  hit when roll + bonus >= target
## A hit_type with no entry (e.g. "certain") always hits.
## Returns {hit, evaded, roll, natural, target, chance}.
func hit_check(user: RPGBattler, target: RPGBattler, action: Dictionary) -> Dictionary:
	var u := resolve_action(user, action)
	var out := {"hit": true, "evaded": false, "roll": 0, "natural": 0, "target": 0, "chance": 100}
	var cfg: Dictionary = definition.get("hit_check", {}).get(u.get("hit_type", "certain"), {})
	if cfg.is_empty():
		return out
	var env := _env(user, target, u)
	var where := "hit_check.%s" % u.hit_type
	match str(cfg.get("type", "percent")):
		"percent":
			var steps: Array = cfg.get("steps", [])
			for i in steps.size():
				var r := _num_or_formula(steps[i], env, where)
				if not r.ok:
					out.hit = false
					out.error = r.error
					return out
				var chance := float(r.value)
				if i == 0:
					out.chance = chance
				if not rng.chance_percent(chance):
					out.hit = false
					out.evaded = i > 0
					return out
		"roll":
			var d := RPGFormula.parse_dice(str(cfg.get("roll", "1d20")))
			if not d.ok:
				out.hit = false
				out.error = d.error
				return out
			var rolled := RPGFormula.roll_parsed(d, rng)
			out.natural = rolled.naturals[0] if rolled.naturals.size() == 1 else rolled.total
			var bonus := _num_or_formula(cfg.get("bonus", 0), env, where + ".bonus")
			var tgt := _num_or_formula(cfg.get("target", 10), env, where + ".target")
			if not bonus.ok or not tgt.ok:
				out.hit = false
				out.error = bonus.error if not bonus.ok else tgt.error
				return out
			out.roll = rolled.total + int(bonus.value)
			out.target = int(tgt.value)
			if cfg.has("natural_hit") and out.natural >= int(cfg.natural_hit):
				out.hit = true
			elif cfg.has("natural_miss") and out.natural <= int(cfg.natural_miss):
				out.hit = false
			else:
				out.hit = out.roll >= out.target
	return out


## Damage or recovery amount (before it is applied). rules.json "damage":
## {variance (default %), min, guard_percent (damage taken while guarding, default 50)} and
## "critical": {chance: formula (percent), multiplier, on_natural}.
## Returns {ok, value (int, >= 0), type ("damage"|"recover"|"none"), resource, critical,
## element, element_rate, error}.
func damage(user: RPGBattler, target: RPGBattler, action: Dictionary, hit_info: Dictionary = {}) -> Dictionary:
	var u := resolve_action(user, action)
	var out := {"ok": true, "value": 0, "type": str(u.get("damage_type", "none")), "resource": str(u.get("resource", life_resource())),
		"critical": false, "element": str(u.get("element", "")), "element_rate": 1.0, "error": ""}
	if out.type == "none" or str(u.get("formula", "")) == "":
		out.type = "none"
		return out
	var env := _env(user, target, u)
	var r := _eval(u.formula, env, "%s '%s' damage" % [u.kind, u.id])
	if not r.ok:
		out.ok = false
		out.error = last_error
		return out
	if r.value is bool:
		out.ok = false
		out.error = "%s '%s' damage formula '%s' gave true/false instead of a number" % [u.kind, u.id, u.formula]
		return out
	var value := float(r.value)
	var cfg: Dictionary = definition.get("damage", {})
	if out.element != "":
		out.element_rate = trait_rate(target, "element_rate", out.element)
		value *= out.element_rate
	if out.type == "damage" and u.critical:
		var crit_cfg: Dictionary = definition.get("critical", {})
		var crit := false
		if crit_cfg.has("on_natural") and hit_info.has("natural") and int(hit_info.natural) > 0:
			crit = int(hit_info.natural) >= int(crit_cfg.on_natural)
		elif crit_cfg.has("chance"):
			var c := _num_or_formula(crit_cfg.chance, env, "critical.chance")
			crit = c.ok and rng.chance_percent(float(c.value))
		if crit:
			out.critical = true
			value *= float(crit_cfg.get("multiplier", 2))
	var variance := float(u.get("variance", cfg.get("variance", 0)))
	if variance > 0.0:
		var amp := int(absf(value) * variance / 100.0)
		if amp > 0:
			value += rng.randi_range(-amp, amp)
	if out.type == "damage" and target.guarding and value > 0.0:
		value = value * float(cfg.get("guard_percent", 50)) / 100.0
	var final_value := roundi(value)
	if out.type == "damage":
		final_value = maxi(final_value, int(cfg.get("min", 0)))
		if damage_filter.is_valid():
			var f: Variant = damage_filter.call(user, target, action, final_value)
			if typeof(f) in [TYPE_INT, TYPE_FLOAT]:
				final_value = maxi(0, roundi(float(f)))
	else:
		final_value = maxi(final_value, 0)
	out.value = final_value
	return out


## Resolves one action from `user` on `target`: hit check, damage/recovery, effects
## (recover, add_state, remove_state), knockout. Returns
## {hit, evaded, damage, recovered, resource, critical, element_rate, added_states,
##  removed_states, resisted_states, knocked_out, revived, lines: [String], text, error}.
## `damage` is life lost (>= 0), `recovered` is life regained; `changes` maps every resource
## to its net change. Only when non-empty: `charged` (target resources gained from taking damage,
## included in `changes`) and `user_changes` (user resources gained from the hit, e.g. TP).
func apply_action(user: RPGBattler, target: RPGBattler, action: Dictionary) -> Dictionary:
	var res := {"hit": false, "evaded": false, "damage": 0, "recovered": 0, "resource": life_resource(),
		"critical": false, "element_rate": 1.0, "added_states": [], "removed_states": [], "resisted_states": [],
		"knocked_out": false, "revived": false, "changes": {}, "lines": [], "text": "", "error": ""}
	var u := resolve_action(user, action)
	if u.is_empty():
		res.error = "unknown action %s" % str(action)
		return _finish(res)
	var for_dead: bool = u.scope in ["one_dead_ally", "all_dead_allies"]
	if target.is_dead() and not for_dead:
		res.lines.append(term("nothing"))
		return _finish(res)
	var before := {}
	for rid in _res_order:
		before[rid] = target.get_resource(rid)
	var h := hit_check(user, target, action)
	if h.has("error"):
		res.error = h.error
	if not h.hit:
		res.evaded = h.evaded
		res.lines.append(term("evade", [target.name]) if h.evaded else term("miss", [user.name]))
		return _finish(res)
	res.hit = true
	# Damage / recovery from the formula.
	var d := damage(user, target, action, h)
	if not d.ok:
		res.error = d.error
		return _finish(res)
	res.critical = d.critical
	res.element_rate = d.element_rate
	res.resource = d.resource
	if d.type == "damage":
		if d.critical:
			res.lines.append(term("critical"))
		_change(target, d.resource, -int(d.value))
	elif d.type == "recover" and not (target.is_dead() and d.resource == life_resource()):
		_change(target, d.resource, int(d.value))
	# Effects (RPG Maker's item/skill effects). recover / damage: `percent` of the maximum plus a
	# flat `amount`; add_state / remove_state: `chance` % (default 100); grow: a permanent stat
	# increase (`id` = stat, `amount`); learn_skill: `id` = skill; common_event: run once after the
	# action by the caller (common_events()).
	for e in u.effects:
		if not (e is Dictionary):
			continue
		match str(e.get("kind", "")):
			"recover", "damage":
				var rid := str(e.get("resource", life_resource())) if e.get("resource") != null else life_resource()
				if target.is_dead() and rid == life_resource():
					continue
				var amount := int(_num(e.get("amount"), 0.0)) + int(float(max_resource(target, rid)) * _num(e.get("percent"), 0.0) / 100.0)
				_change(target, rid, -amount if str(e.kind) == "damage" else amount)
			"add_state":
				var sid := str(e.get("id", ""))
				var chance := _num(e.get("chance"), 100.0) * state_chance_rate(target, sid)
				if rng.chance_percent(chance):
					if add_state(target, sid):
						res.added_states.append(sid)
				else:
					res.resisted_states.append(sid)
			"remove_state":
				var sid2 := str(e.get("id", ""))
				if not target.has_state(sid2) or not rng.chance_percent(_num(e.get("chance"), 100.0)):
					continue
				if remove_state(target, sid2):
					res.removed_states.append(sid2)
					if sid2 == death_state():
						res.revived = true
			"grow":
				var stat := str(e.get("id", ""))
				var by := int(_num(e.get("amount"), 0.0))
				if _stat_defs.has(stat) and by != 0:
					target.base[stat] = int(target.base.get(stat, 0)) + by
					if not res.has("grown"):
						res["grown"] = {}
					res.grown[stat] = int(res.grown.get(stat, 0)) + by
			"learn_skill":
				var sk := str(e.get("id", ""))
				if sk != "" and target.is_actor() and not target.skills.has(sk) and not _rec("skills", sk).is_empty():
					target.skills.append(sk)
					if not res.has("learned"):
						res["learned"] = []
					res.learned.append(sk)
	# States that end when hit (sleep).
	var life_lost: int = before.get(life_resource(), 0) - target.get_resource(life_resource())
	if life_lost > 0:
		for s in target.states.duplicate():
			var chance2 := float(_rec("states", s.id).get("remove_on_damage", 0))
			if chance2 > 0.0 and rng.chance_percent(chance2):
				target.remove_state(s.id)
				res.removed_states.append(s.id)
	# Knockout.
	if target.get_resource(life_resource()) <= 0 and not target.has_state(death_state()):
		add_state(target, death_state())
		res.added_states.append(death_state())
		res.knocked_out = true
	# Resources charged by taking damage (e.g. TP): "gain_on_damage" formula, a = the target,
	# b = the user, s = {damage: life lost, max: target's max life}.
	if life_lost > 0 and target.is_alive() and _has_resource_key("gain_on_damage"):
		var cenv := {"a": target.snapshot(), "b": _snap_of(user), "v": variables, "rng": rng,
			"s": {"damage": life_lost, "max": max_resource(target, life_resource())}}
		var charged := _gain_resources(target, "gain_on_damage", cenv)
		if not charged.is_empty():
			res["charged"] = charged
	for rid in _res_order:
		var delta: int = target.get_resource(rid) - int(before[rid])
		if delta != 0:
			res.changes[rid] = delta
	if d.type == "damage":
		res.damage = int(d.value)
	res.recovered = maxi(0, int(res.changes.get(life_resource(), 0)))
	_describe(user, target, u, d, res)
	# Resources the user gains when the action hits: "gain_on_use" formula, a = the user,
	# b = the target, s = the action (e.g. TP "s.tp_gain * a.tcr / 100").
	if _has_resource_key("gain_on_use"):
		var uenv := {"a": _snap_of(user), "b": target.snapshot(), "v": variables, "s": u, "rng": rng}
		var gained := _gain_resources(user, "gain_on_use", uenv)
		if not gained.is_empty():
			res["user_changes"] = gained
	return _finish(res)


## A number from an effect field (`fallback` when it is missing, null or not a number).
static func _num(v: Variant, fallback: float) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


## The common events an action runs after it is used (its "common_event" effects, in order).
## As in RPG Maker they run once per use, not once per target: the battle runs them after the
## action, the menu after closing.
func common_events(user: RPGBattler, action: Dictionary) -> Array:
	var out := []
	for e in resolve_action(user, action).get("effects", []):
		if e is Dictionary and str(e.get("kind", "")) == "common_event" and str(e.get("id", "")) != "":
			out.append(str(e.id))
	return out


## True when an apply_action() result changed something (resources, states, a stat from Grow,
## a skill from Learn Skill): the menu uses an item only then.
static func had_effect(r: Dictionary) -> bool:
	for k in ["changes", "added_states", "removed_states", "grown", "learned"]:
		var v: Variant = r.get(k)
		if (v is Dictionary or v is Array) and not v.is_empty():
			return true
	return false


func _change(b: RPGBattler, res_id: String, delta: int) -> void:
	var m := max_resource(b, res_id)
	b.set_resource(res_id, clampi(b.get_resource(res_id) + delta, 0, m))


func _describe(_user: RPGBattler, target: RPGBattler, _u: Dictionary, d: Dictionary, res: Dictionary) -> void:
	var label := _resource_label(d.resource)
	if d.type == "damage":
		if d.resource == life_resource():
			res.lines.append(term("damage", [target.name, d.value]) if d.value > 0 else term("no_damage", [target.name]))
		else:
			res.lines.append(term("resource_damage", [target.name, d.value, label]))
	var charged: Dictionary = res.get("charged", {})
	for rid in res.changes:
		var delta: int = res.changes[rid] - int(charged.get(rid, 0))
		if delta > 0 and not (d.type == "damage" and rid == d.resource):
			res.lines.append(term("recover", [target.name, delta, _resource_label(rid)]))
	for sid in res.added_states:
		if sid == death_state():
			res.lines.append(term("knockout", [target.name]))
		else:
			res.lines.append(_state_message(_rec("states", sid), "added", target.name, sid))
	for sid in res.removed_states:
		if sid == death_state():
			res.lines.append(term("revive", [target.name]))
		else:
			res.lines.append(_state_message(_rec("states", sid), "removed", target.name, sid))
	var grown: Dictionary = res.get("grown", {})
	for stat in grown:
		res.lines.append(term("stat_up", [target.name, str(_stat_defs.get(stat, {}).get("label", stat)), grown[stat]]))
	for sk in res.get("learned", []):
		res.lines.append(term("learned", [target.name, str(_rec("skills", sk).get("name", sk))]))
	if res.lines.is_empty():
		res.lines.append(term("nothing"))


func _resource_label(res_id: String) -> String:
	return str(_res_defs.get(res_id, {}).get("label", res_id.to_upper()))


func _finish(res: Dictionary) -> Dictionary:
	res.text = "\n".join(PackedStringArray(res.lines))
	return res


## Uses an item on a target (in battle or from the menu). Consuming it from the inventory is
## the caller's job.
func use_item(user: RPGBattler, target: RPGBattler, item_id: String) -> Dictionary:
	return apply_action(user, target, {"kind": "item", "item": item_id})


# --------------------------------------------------------------------------------------------
# Progression
# --------------------------------------------------------------------------------------------

func max_level(b: RPGBattler) -> int:
	var lv_cfg: Dictionary = definition.get("levels", {})
	var cap := int(lv_cfg.get("max", 99))
	if b != null and b.is_actor():
		cap = mini(cap, int(_rec("actors", b.id).get("max_level", cap)))
	return cap


## Total experience needed to reach `level`. rules.json "exp_curve":
##   {"type": "basis_inflation", "basis", "inflation"}  XP-style curve; a class may override
##       basis/inflation in its "exp_curve" object
##   {"type": "table"}  class "exp_table": [0, 2000, 4000, ...] (index = level - 1); levels past
##       the table add "after_table" (or the last step) per level
##   {"type": "formula", "formula": "..."}  s.level is the level asked for
##   {"type": "basis_extra_acceleration", "basis", "extra", "acc_a", "acc_b"}  RPG Maker VX Ace
##       curve; a class may override any of the four in its "exp_curve" object
func exp_for_level(class_id: String, level: int) -> int:
	if level <= 1:
		return 0
	var curve: Dictionary = definition.get("exp_curve", {})
	var cls := _rec("classes", class_id)
	match str(curve.get("type", "basis_inflation")):
		"basis_extra_acceleration":
			var cc: Dictionary = cls.get("exp_curve", {})
			var basis_a := float(cc.get("basis", curve.get("basis", 30)))
			var extra := float(cc.get("extra", curve.get("extra", 20)))
			var acc_a := float(cc.get("acc_a", curve.get("acc_a", 30)))
			var acc_b := maxf(1.0, float(cc.get("acc_b", curve.get("acc_b", 30))))
			var lv := float(level)
			return roundi(basis_a * pow(lv - 1.0, 0.9 + acc_a / 250.0) * lv * (lv + 1.0)
				/ (6.0 + lv * lv / 50.0 / acc_b) + (lv - 1.0) * extra)
		"table":
			var table: Array = cls.get("exp_table", curve.get("table", []))
			if table.is_empty():
				return 0
			var idx := level - 1
			if idx < table.size():
				return int(table[idx])
			var last := int(table[-1])
			var step := int(curve.get("after_table", last - (int(table[-2]) if table.size() > 1 else 0)))
			return last + step * (idx - table.size() + 1)
		"formula":
			var r := _eval(str(curve.get("formula", "0")), {"a": {}, "b": {}, "v": variables, "s": {"level": level, "class": class_id}, "rng": rng}, "exp_curve")
			return int(r.value) if r.ok else 0
	var own: Dictionary = cls.get("exp_curve", {})
	var basis := float(own.get("basis", curve.get("basis", 25)))
	var inflation := float(own.get("inflation", curve.get("inflation", 30)))
	var p := 2.4 + inflation / 100.0
	var total := 0
	for i in range(2, level + 1):
		total += int(basis * pow(i + 3, p) / pow(5.0, p))
	return total


## Adds experience and levels up as often as needed. Returns one entry per new level:
## {level, gains: {stat: delta}, learned: [skill ids]}.
func gain_exp(b: RPGBattler, amount: int) -> Array:
	var ups := []
	b.exp = maxi(0, b.exp + amount)
	var cap := max_level(b)
	while b.level < cap and b.exp >= exp_for_level(b.class_id, b.level + 1):
		var before := stat_block(b)
		b.level += 1
		_apply_level_formulas(b, "on_level_up")
		var learned := _learn_skills(b, b.level)
		var after := stat_block(b)
		var gains := {}
		for k in after:
			if after[k] != before.get(k, 0):
				gains[k] = after[k] - before.get(k, 0)
		ups.append({"level": b.level, "gains": gains, "learned": learned})
	clamp_resources(b)
	return ups


## Runs rules.json formula lists such as "on_create" / "on_level_up":
## [{"stat": "mhp", "formula": "roll(1, a.hit_die) + mod(a.con)", "min": 1}] — each result is
## added to the battler's base stat.
func _apply_level_formulas(b: RPGBattler, key: String) -> void:
	for entry in definition.get(key, []):
		var stat := str(entry.get("stat", ""))
		var env := {"a": snapshot(b), "b": {}, "v": variables, "s": {}, "rng": rng}
		var r := _eval(str(entry.get("formula", "0")), env, "%s '%s'" % [key, stat])
		if r.ok:
			var gain := int(r.value)
			if entry.has("min"):
				gain = maxi(gain, int(entry.min))
			b.base[stat] = int(b.base.get(stat, 0)) + gain


func _learn_skills(b: RPGBattler, level: int) -> Array:
	var learned := []
	if not b.is_actor():
		return learned
	for l in _rec("classes", b.class_id).get("learnings", []):
		if int(l.get("level", 1)) == level:
			var sk := str(l.get("skill", ""))
			if sk != "" and not b.skills.has(sk):
				b.skills.append(sk)
				learned.append(sk)
	return learned


# --------------------------------------------------------------------------------------------
# Escape and checks
# --------------------------------------------------------------------------------------------

## Escape chance in percent. rules.json "escape": {"chance": formula} where a and b are the
## averaged stats of the active party and enemies.
func escape_chance(party: Array, enemies: Array) -> int:
	var cfg: Dictionary = definition.get("escape", {})
	var env := {"a": _average_snapshot(party), "b": _average_snapshot(enemies), "v": variables, "s": {}, "rng": rng}
	var r := _num_or_formula(cfg.get("chance", 50), env, "escape.chance")
	return clampi(int(r.value), 0, 100) if r.ok else 0


func _average_snapshot(list: Array) -> Dictionary:
	var sums := {}
	var n := 0
	for b in list:
		if b is RPGBattler and b.is_active():
			n += 1
			var block := stat_block(b)
			for k in block:
				sums[k] = float(sums.get(k, 0.0)) + float(block[k])
			sums["level"] = float(sums.get("level", 0.0)) + b.level
	var out := {"count": n, "stats": {}}
	for k in sums:
		out[k] = int(sums[k] / maxf(1.0, float(n)))
		if k != "level":
			out.stats[k] = out[k]
	if not out.has("level"):
		out["level"] = 0
	for sid in _stat_order:
		if not out.has(sid):
			out[sid] = 0
			out.stats[sid] = 0
	return out


## A check outside (or inside) battle, e.g. forcing a door.
##   {stat: "str", dc: 15, bonus?: 0}  rolls rules.json "roll_check": {roll, bonus (s.value =
##       the stat), compare: ">=" (default) or "<=" for roll-under, natural_success, natural_failure}
##   {formula: "...", dc: n}            the formula is the roll (it may call roll())
##   {formula: "..."}                   the formula returns true/false
## dc may be a number or a formula. Returns {success, roll, target, natural, error}.
func roll_check(b: RPGBattler, check: Dictionary) -> Dictionary:
	var out := {"success": false, "roll": 0, "target": 0, "natural": 0, "error": ""}
	var env := _env(b, null, {})
	if check.has("dc"):
		var t := _num_or_formula(check.dc, env, "check dc")
		if not t.ok:
			out.error = t.error
			return out
		out.target = int(t.value)
	if check.has("stat"):
		var stat := str(check.stat)
		var value: Variant
		if _stat_defs.has(stat):
			value = effective_stat(b, stat)
		elif _res_defs.has(stat):
			value = b.get_resource(stat)
		else:
			out.error = "unknown stat '%s' in check" % stat
			if report_errors:
				push_error("[rules %s] %s" % [rules_id, out.error])
			return out
		var cfg: Dictionary = definition.get("roll_check", {})
		var rolled := RPGFormula.roll_dice(str(cfg.get("roll", "1d20")), rng)
		if not rolled.ok:
			out.error = rolled.error
			return out
		out.natural = rolled.naturals[0] if rolled.naturals.size() == 1 else rolled.value
		env.s = {"value": value, "stat": stat}
		var bonus := _num_or_formula(cfg.get("bonus", 0), env, "roll_check.bonus")
		if not bonus.ok:
			out.error = bonus.error
			return out
		out.roll = int(rolled.value) + int(bonus.value) + int(check.get("bonus", 0))
		if str(cfg.get("compare", ">=")) == "<=":
			out.success = out.roll <= out.target
		else:
			out.success = out.roll >= out.target
		if cfg.has("natural_success") and out.natural == int(cfg.natural_success):
			out.success = true
		elif cfg.has("natural_failure") and out.natural == int(cfg.natural_failure):
			out.success = false
		return out
	if check.has("formula"):
		var r := _eval(str(check.formula), env, "check")
		if not r.ok:
			out.error = r.error
			return out
		if r.value is bool:
			out.success = r.value
			out.roll = 1 if r.value else 0
		else:
			out.roll = int(r.value)
			out.success = out.roll >= out.target
		return out
	out.error = "check needs a 'stat' or a 'formula'"
	return out


# --------------------------------------------------------------------------------------------
# Time-based battles (ATB / CTB)
# --------------------------------------------------------------------------------------------

## How fast `b`'s time gauge fills in ATB and CTB battles (higher = sooner turns). rules.json
## "atb": {"speed": formula} (a = the battler) decides it; without one, the battler's agility
## (the first of agi, agility, spd, speed, dex the rules define), else 1. The battle core turns this into a
## fill rate relative to the battle's average, so only the ratios matter. Never below 1.
func atb_speed(b: RPGBattler) -> float:
	var cfg: Variant = definition.get("atb", {})
	if cfg is Dictionary and (cfg as Dictionary).has("speed"):
		var r := _eval(str(cfg.speed), _env(b, null, {}), "atb.speed")
		if r.ok:
			return maxf(1.0, float(r.value))
	for sid in ["agi", "agility", "spd", "speed", "dex"]:
		if _stat_defs.has(sid):
			return maxf(1.0, float(stat_block(b).get(sid, 1)))
	return 1.0
