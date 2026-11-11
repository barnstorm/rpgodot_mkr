extends "res://addons/rpg/runtime/rpg_extension.gd"
## Test extension: records every hook call so test_extension_hooks can check them.

## [method name, args] in call order.
var calls: Array = []
var flag := false
var unlocked := false
var owned := {"value": 0}
var migrated_from := -1
var actions_fired := 0
var chars: Array = []


func _extension_ready() -> void:
	calls.append(["_extension_ready", []])
	rpg.register_text_code("PX", func(arg: String, _info: Dictionary) -> Variant: return "<%s>" % arg)
	rpg.register_text_code("PA", func(_arg: String, _info: Dictionary) -> Variant: return {"action": func() -> void: actions_fired += 1})
	rpg.register_text_tag("probe", func(_arg: String, _info: Dictionary) -> Variant: return {"bbcode": "[u]"})
	rpg.register_text_tag("/probe", func(_arg: String, _info: Dictionary) -> Variant: return {"bbcode": "[/u]"})
	rpg.register_text_preprocessor(func(text: String, _info: Dictionary) -> String: return text.replace("@@", "probe"))


func _rec(m: String, args: Array = []) -> void:
	calls.append([m, args])


func names() -> Array:
	return calls.map(func(c): return c[0])


func on_title_shown() -> void: _rec("on_title_shown")
func on_new_game() -> void: _rec("on_new_game")
func on_game_loaded() -> void: _rec("on_game_loaded")
func on_map_entered(map_id: String) -> void: _rec("on_map_entered", [map_id])
func on_map_left(map_id: String) -> void: _rec("on_map_left", [map_id])
func on_player_stepped(cell: Vector2i, region: int, terrain: int) -> void: _rec("on_player_stepped", [cell, region, terrain])
func on_menu_opened(menu: Node) -> void: _rec("on_menu_opened", [menu != null])
func on_menu_closed() -> void: _rec("on_menu_closed")
func on_battle_started(args: Dictionary) -> void: _rec("on_battle_started", [str(args.get("troop", ""))])
func on_battle_ended(outcome: String, _result: Variant) -> void: _rec("on_battle_ended", [outcome])
func on_actor_levelled(actor_id: String, old_level: int, new_level: int) -> void: _rec("on_actor_levelled", [actor_id, old_level, new_level])
func on_quitting() -> void: _rec("on_quitting")
func on_option_changed(key: String, value: Variant) -> void: _rec("on_option_changed", [key, value])
func on_message_opened(params: Dictionary) -> void: _rec("on_message_opened", [str(params.get("text", ""))])
func on_message_char(character: String, _index: int, instant: bool) -> void: chars.append([character, instant])
func on_message_closed() -> void: _rec("on_message_closed")
func on_autosaved(slot: int, ok: bool, reason: String) -> void: _rec("on_autosaved", [slot, ok, reason])


# "probe_owned" is saved by the script itself; "probe" by the host (section()).
func save_section(ns: String) -> Dictionary:
	if ns == "probe_owned":
		return owned.duplicate()
	return section(ns).duplicate()


func load_section(ns: String, data: Dictionary) -> void:
	if ns == "probe_owned":
		owned = data.duplicate() if not data.is_empty() else {"value": 0}
	else:
		var s := section(ns)
		s.clear()
		s.merge(data)


func migrate_section(_ns: String, data: Dictionary, from_version: int) -> Dictionary:
	migrated_from = from_version
	var d := data.duplicate()
	d["value"] = int(d.get("old_value", 0)) * 10
	d.erase("old_value")
	return d


func menu_probe(_menu: Node) -> String:
	_rec("menu_probe")
	return ""


func menu_actor(_menu: Node, actor: Variant) -> String:
	_rec("menu_actor", [str(actor.id) if actor is Object else str(actor)])
	return "close"


func probe_unlocked() -> bool:
	return unlocked


func check_probe(cond: Dictionary, _where: Dictionary) -> bool:
	return flag == bool(cond.get("value", true))
