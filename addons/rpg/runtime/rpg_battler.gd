class_name RPGBattler
extends RefCounted
## Runtime data for one actor or enemy. Plain data plus small helpers; all game math
## (effective stats, damage, levels) lives in the rule system, which fills `rules` when it
## creates the battler so snapshot() can ask it for effective values.
##
## Saved fields round-trip through to_dict()/from_dict(). Battle-only fields (guarding,
## index, screen_position, action, troop_member) are not saved.

var id := ""                 ## actor or enemy record id
var kind := "actor"          ## "actor" or "enemy"
var name := ""
var class_id := ""
var level := 1
var exp := 0
var resources := {}          ## current values, e.g. {"hp": 120, "sp": 20}
var base := {}               ## base stats owned by this battler (actor base_stats + level-up gains, enemy stats)
var equips := {}             ## slot id -> weapon/armor id ("" = empty)
var skills: Array = []       ## skill ids
var states: Array = []       ## [{id, turns, steps?}] ; turns < 0 = until removed; steps = steps left (removed by walking)
var custom := {}             ## free per-battler data for extensions (saved)

## Set by the rule system that created the battler.
var life_resource := "hp"
var death_state := "knockout"
var rules = null             ## RPGRuleSystem (untyped to avoid a load-order cycle)

# ---- battle-only ----
var guarding := false
var index := -1              ## position in its side (party index or troop member index)
var screen_position := Vector2.ZERO
var hidden := false          ## enemy not yet appeared (troop member "hidden")
var action := {}             ## action chosen for the current turn
var escaped := false


func is_actor() -> bool:
	return kind == "actor"


func is_enemy() -> bool:
	return kind == "enemy"


func has_state(state_id: String) -> bool:
	for s in states:
		if s.id == state_id:
			return true
	return false


func state_ids() -> Array:
	var out := []
	for s in states:
		out.append(s.id)
	return out


## Adds a state (or refreshes its turns if already present, keeping the longer duration).
func add_state(state_id: String, turns: int = -1) -> void:
	for s in states:
		if s.id == state_id:
			if turns < 0 or (s.turns >= 0 and turns > s.turns):
				s.turns = turns
			return
	states.append({"id": state_id, "turns": turns})


func remove_state(state_id: String) -> bool:
	for i in states.size():
		if states[i].id == state_id:
			states.remove_at(i)
			return true
	return false


func get_resource(res_id: String) -> int:
	return int(resources.get(res_id, 0))


func set_resource(res_id: String, value: int) -> void:
	resources[res_id] = value


func is_dead() -> bool:
	return has_state(death_state) or (resources.has(life_resource) and int(resources[life_resource]) <= 0)


func is_alive() -> bool:
	return not is_dead()


## True while the battler takes part in the fight (alive, present, not escaped).
func is_active() -> bool:
	return is_alive() and not hidden and not escaped


## Effective values for formulas. Filled by the rule system; falls back to raw data.
func snapshot() -> Dictionary:
	if rules != null:
		return rules.snapshot(self)
	var snap := {"id": id, "kind": kind, "name": name, "class": class_id, "level": level,
		"stats": base.duplicate(), "resources": resources.duplicate(), "states": state_ids(),
		"guarding": guarding, "index": index}
	for k in base:
		snap[k] = base[k]
	for k in resources:
		snap[k] = resources[k]
	return snap


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "name": name, "class": class_id, "level": level, "exp": exp,
		"resources": resources.duplicate(true), "base": base.duplicate(true),
		"equips": equips.duplicate(true), "skills": skills.duplicate(),
		"states": states.duplicate(true), "custom": custom.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RPGBattler:
	var b := RPGBattler.new()
	b.id = str(d.get("id", ""))
	b.kind = str(d.get("kind", "actor"))
	b.name = str(d.get("name", ""))
	b.class_id = str(d.get("class", ""))
	b.level = int(d.get("level", 1))
	b.exp = int(d.get("exp", 0))
	b.resources = (d.get("resources", {}) as Dictionary).duplicate(true)
	b.base = (d.get("base", {}) as Dictionary).duplicate(true)
	b.equips = (d.get("equips", {}) as Dictionary).duplicate(true)
	b.skills = (d.get("skills", []) as Array).duplicate()
	b.states = []
	for s in d.get("states", []):
		if s is Dictionary and s.has("id"):
			var entry := {"id": str(s.id), "turns": int(s.get("turns", -1))}
			# Steps left before a state removed by walking wears off (RPGRuleSystem.walk_state_steps).
			if s.has("steps"):
				entry["steps"] = int(s.steps)
			b.states.append(entry)
	b.custom = (d.get("custom", {}) as Dictionary).duplicate(true)
	return b
