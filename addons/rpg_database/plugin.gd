@tool
extends EditorPlugin
## Companion plugin that gives RPG Kit its second main tab, "Database" (enabled automatically by
## the RPG Kit plugin). The screen itself lives in addons/rpg/editor/database/.

const SCREEN := "res://addons/rpg/editor/database/rpg_database_screen.gd"

var screen: Control


func _enter_tree() -> void:
	if ResourceLoader.exists(SCREEN):
		screen = load(SCREEN).new()
	else:
		var l := Label.new()
		l.text = "The Database screen is not installed."
		screen = l
	screen.name = "Database"
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(screen)
	if screen.has_method("setup"):
		screen.setup(self)
	if "battle_test" in screen:
		screen.battle_test = _battle_test
	screen.visible = false


func _exit_tree() -> void:
	if screen:
		screen.queue_free()
	if ResourceLoader.exists("res://addons/rpg/editor/rpg_maker_view.gd"):
		var mv: Script = load("res://addons/rpg/editor/rpg_maker_view.gd")
		mv.shared().apply_now("Database", false)
		mv.release()


## Unsaved Database tabs: their names (and "System" for unsaved System edits).
func _unsaved_tabs() -> PackedStringArray:
	var out := PackedStringArray()
	if screen == null or not screen.has_method("dirty_tabs"):
		return out
	for t in screen.dirty_tabs():
		out.append(str(t.get("title") if t.get("title") != null else t.name).trim_suffix(" *"))
	var sys: Variant = screen.get("_system_edits")
	if sys is Dictionary and not sys.is_empty():
		out.append("System")
	return out


## Godot asks about these before quitting or closing the project; "Save" calls _save_external_data.
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene != "":
		return ""
	var tabs := _unsaved_tabs()
	if tabs.is_empty():
		return ""
	return "Save changes to the RPG Database (%s) before closing?" % ", ".join(tabs)


## Godot's Save (Ctrl+S on a scene, Save & Quit, running the game) saves unsaved Database tabs too.
func _save_external_data() -> void:
	if not _unsaved_tabs().is_empty() and screen.has_method("save_all"):
		screen.save_all()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if screen:
		screen.visible = visible
		# The RPG tab keeps its own copy of the data; pick up what it saved.
		if visible and screen.has_method("check_disk_changes"):
			screen.check_disk_changes.call_deferred()
	if ResourceLoader.exists("res://addons/rpg/editor/rpg_maker_view.gd"):
		load("res://addons/rpg/editor/rpg_maker_view.gd").shared().tab_visible("Database", visible)


func _get_plugin_name() -> String:
	return "Database"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Database", "EditorIcons") if EditorInterface.get_editor_theme().has_icon("Database", "EditorIcons") else EditorInterface.get_editor_theme().get_icon("ResourcePreloader", "EditorIcons")


## Battle test from the Enemy groups tab: starts the game straight into the fight.
func _battle_test(troop_id: String) -> void:
	RPGJson.save_file("user://rpg_playtest.json", {"battle_test": troop_id})
	EditorInterface.play_main_scene()
