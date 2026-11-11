extends "res://addons/rpg/runtime/rpg_extension.gd"
## Save & autosave plus (kit plugin "save_plus").
##   Autosave (to the last slot, shown as "Auto") after a map transfer (not the first map of a new
##   game or a load), after a battle won or escaped, and when the menu opens - each a setting.
##   Autosaves wait for a safe point (no event running) like System > Auto-save.
##   The player can turn autosave off (options row "Autosave"); events can too (Change autosave).
##   A short "Autosaved" note shows after each autosave.
##   Max slots: how many slots the save screen lists.
##   Set save description: a line the save screen shows for saves made afterwards.
##   Request autosave: an autosave once the event has finished.

const SECTION := "save_plus"
const TOAST_W := 90.0

var _toast: Panel = null
## Notes shown so far (tests).
var toasts_shown := 0


func _extension_ready() -> void:
	if rpg.saves == null:
		return
	rpg.saves.max_slots = clampi(int(setting("max_slots", 16)), 2, 99)
	rpg.saves.autosave_labelled = true
	rpg.saves.header_providers.append(_header)
	rpg.saves.autosave_allowed = autosave_enabled


## The plugin is stopped (extensions reloaded): give the save service its defaults back.
func _exit_tree() -> void:
	if rpg == null or rpg.saves == null:
		return
	rpg.saves.max_slots = rpg.saves.MAX_SLOTS
	rpg.saves.autosave_labelled = false
	rpg.saves.header_providers.erase(_header)
	if rpg.saves.autosave_allowed == Callable(self, "autosave_enabled"):
		rpg.saves.autosave_allowed = Callable()


func _header() -> Dictionary:
	var d := str(section(SECTION).get("description", ""))
	return {"description": d} if d != "" else {}


## Options row "Autosave" is offered when the settings let players choose.
func player_option_shown() -> bool:
	return bool(setting("player_option", true))


## False when an event or the player turned autosave off.
func autosave_enabled() -> bool:
	if bool(section(SECTION).get("disabled", false)):
		return false
	if player_option_shown() and not bool(option("autosave", true)):
		return false
	return true


## Asks the game for an autosave at the next safe point. Returns false when autosave is off or
## there is no game running.
func request(reason: String) -> bool:
	if not autosave_enabled():
		return false
	if rpg.game != null and is_instance_valid(rpg.game) and rpg.game.has_method("request_autosave"):
		rpg.game.request_autosave(reason)
		return true
	return false


func on_map_entered(_map_id: String) -> void:
	if not bool(setting("on_transfer", true)):
		return
	if rpg.game != null and rpg.game.has_method("is_first_map") and rpg.game.is_first_map():
		return
	request("transfer")


func on_battle_ended(outcome: String, _result: Variant) -> void:
	if bool(setting("after_battle", true)) and outcome in ["win", "escape"]:
		request("battle")


func on_menu_opened(_menu: Node) -> void:
	if bool(setting("on_menu", false)) and autosave_enabled():
		rpg.saves.autosave("menu")


func on_autosaved(_slot: int, ok: bool, _reason: String) -> void:
	if ok and bool(setting("toast", true)):
		show_toast(str(setting("toast_text", "Autosaved")))


## A small note at the top right that fades out.
func show_toast(text: String) -> void:
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	var layer: Variant = rpg.map_overlay_layer("hud")
	if not (layer is Control):
		return
	var p := Panel.new()
	p.name = "AutosaveToast"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rpg.ui != null and rpg.ui.get("ui_theme") is Theme:
		p.theme = rpg.ui.ui_theme
	p.position = Vector2(320 - TOAST_W - 4, 4)
	p.size = Vector2(TOAST_W, 18)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = p.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	layer.add_child(p)
	_toast = p
	toasts_shown += 1
	var t := p.create_tween()
	t.tween_interval(float(setting("toast_seconds", 1.6)))
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)


## The note showing now, or null (tests and screenshots).
func toast() -> Panel:
	return _toast if _toast != null and is_instance_valid(_toast) else null


func set_description(text: String) -> void:
	var s := section(SECTION)
	if text.strip_edges() == "":
		s.erase("description")
	else:
		s["description"] = text.strip_edges()


func set_disabled(off: bool) -> void:
	var s := section(SECTION)
	if off:
		s["disabled"] = true
	else:
		s.erase("disabled")
