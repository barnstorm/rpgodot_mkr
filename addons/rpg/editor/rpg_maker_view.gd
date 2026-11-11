@tool
extends RefCounted
## "Maker view": while the RPG or Database tab is shown, Godot's docks (scene tree, file system,
## inspector, bottom panel) are hidden with the editor's distraction-free mode, so the screen
## looks like RPG Maker's single window. Leaving both tabs restores what the maker had before.
## One shared instance is kept on Engine (both plugins use it). The setting is per project.

const SETTING := "rpg_kit/editor/maker_view"

var _visible: Dictionary = {}
var _active := false
var _before := false
var _pending := false


static func shared() -> RefCounted:
	if not Engine.has_meta("rpg_maker_view"):
		Engine.set_meta("rpg_maker_view", load("res://addons/rpg/editor/rpg_maker_view.gd").new())
	return Engine.get_meta("rpg_maker_view")


static func enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, true))


func set_enabled(on: bool) -> void:
	ProjectSettings.set_setting(SETTING, on)
	ProjectSettings.save()
	apply()


## Called from a plugin's _make_visible.
func tab_visible(tab: String, on: bool) -> void:
	_visible[tab] = on
	if on:
		apply()
	elif not _pending:
		# Switching RPG -> Database hides one tab before showing the other: wait a frame so the
		# docks don't flash back in between.
		_pending = true
		_apply_later.call_deferred()


func _apply_later() -> void:
	_pending = false
	apply()


## Drops the shared instance (plugins call this from _exit_tree): a script object left in Engine
## metadata outlives GDScript at editor shutdown and crashes it.
static func release() -> void:
	if Engine.has_meta("rpg_maker_view"):
		Engine.remove_meta("rpg_maker_view")


## Like tab_visible but applies at once (used when a plugin is leaving).
func apply_now(tab: String, on: bool) -> void:
	_visible[tab] = on
	apply()


func any_visible() -> bool:
	for k in _visible:
		if _visible[k]:
			return true
	return false


func apply() -> void:
	if not Engine.is_editor_hint():
		return
	var want := enabled() and any_visible()
	if want and not _active:
		_before = EditorInterface.distraction_free_mode
		EditorInterface.distraction_free_mode = true
		_active = true
	elif not want and _active:
		EditorInterface.distraction_free_mode = _before
		_active = false
