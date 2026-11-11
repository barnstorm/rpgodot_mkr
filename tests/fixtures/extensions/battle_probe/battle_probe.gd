extends "res://addons/rpg/runtime/rpg_extension.gd"
## Records every battle hook and, by `mode`, changes what happens (tests/suites/test_plugins_battle.gd).

## "" (record only), "same" (handlers return the values they got), "double", "zero",
## "cancel_actors", "actors_guard", "enemies_hit_themselves", "bonus", "solo", "victory_node",
## "popup", "nodes".
var mode := ""
var events: Array = []
var flag := false
var scene: Node = null
var victory_info: Dictionary = {}


func check_flag(_cond: Dictionary, _where: Dictionary) -> bool:
	return flag


func names() -> Array:
	return events.map(func(e): return e[0])


func on_battle_scene_ready(p_scene: Node) -> void:
	scene = p_scene
	events.append(["ready"])
	if mode == "nodes":
		for b in p_scene.core.all_battlers():
			var n := Node2D.new()
			n.name = "ProbeMark"
			p_scene.battler_node(b).add_child(n)


func on_turn_started(b: Object) -> void:
	events.append(["turn", b.name])


func on_action_chosen(user: Object, action: Dictionary, targets: Array) -> Variant:
	events.append(["chosen", user.name, str(action.get("kind", "")), targets.size()])
	match mode:
		"same":
			return {"action": action, "targets": targets}
		"cancel_actors":
			if user.is_actor():
				return {"cancel": true}
		"actors_guard":
			if user.is_actor():
				return {"action": {"kind": "guard"}}
		"enemies_hit_themselves":
			if user.is_enemy() and str(action.get("kind", "")) == "attack":
				return {"targets": [user]}
	return null


func on_damage_calculated(user: Object, target: Object, _action: Dictionary, value: int) -> Variant:
	events.append(["damage", user.name, target.name, value])
	match mode:
		"same":
			return value
		"double":
			return value * 2
		"zero":
			return 0
	return null


func on_state_changed(b: Object, state_id: String, added: bool) -> void:
	events.append(["state", b.name, state_id, added])


func on_battler_defeated(b: Object) -> void:
	events.append(["defeated", b.name])


func on_victory(rewards: Dictionary) -> Variant:
	events.append(["victory", int(rewards.get("exp", 0)), int(rewards.get("gold", 0))])
	if mode == "bonus":
		var r := rewards.duplicate(true)
		r["gold"] = int(r.get("gold", 0)) + 1000
		r["exp"] = 0
		return r
	return rewards if mode == "same" else null


func battle_members(members: Array) -> Variant:
	if mode == "solo" and members.size() > 1:
		return [members[1]]
	return null


func battle_popup(_battler: Object, text: String, style: String, _node: Variant) -> Variant:
	if mode != "popup":
		return null
	events.append(["popup", style, text])
	var c := Control.new()
	c.name = "ProbePopup"
	c.set_meta("style", style)
	return c


func victory_scene(info: Dictionary) -> Node:
	if mode != "victory_node":
		return null
	victory_info = info
	var n: Node = load("res://tests/fixtures/extensions/battle_probe/victory_node.gd").new()
	return n
