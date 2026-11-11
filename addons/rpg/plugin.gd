@tool
extends EditorPlugin
## RPG Kit editor entry point: adds the "RPG" main tab (map editor), enables the companion
## "Database" main tab plugin, and registers the export check that blocks exports while a
## disabled or missing extension's command is in use. Also registers the MIDI import plugin
## (.mid / .midi rendered to an AudioStreamWAV with the project's sound bank).

const MainScreen := preload("res://addons/rpg/editor/main_screen/rpg_main_screen.gd")
const ExportCheck := preload("res://addons/rpg/editor/rpg_export_check.gd")
const MidiImporter := preload("res://addons/rpg/import/midi/rpg_midi_importer.gd")
const DATABASE_PLUGIN := "rpg_database"

var screen: Control
var export_check: EditorExportPlugin
var midi_importer: EditorImportPlugin


func _enter_tree() -> void:
	screen = MainScreen.new()
	screen.setup(self)
	EditorInterface.get_editor_main_screen().add_child(screen)
	screen.visible = false
	export_check = ExportCheck.new()
	add_export_plugin(export_check)
	midi_importer = MidiImporter.new()
	add_import_plugin(midi_importer)
	if not ProjectSettings.has_setting("autoload/RPG"):
		add_autoload_singleton("RPG", "res://addons/rpg/runtime/rpg_service.gd")
	_register_settings()
	_enable_database.call_deferred()
	_offer_recovery.call_deferred()
	if OS.get_environment("RPG_EDITOR_SHOT") != "":
		_editor_shot.call_deferred(OS.get_environment("RPG_EDITOR_SHOT"))
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


## Shows the kit's project settings in Project Settings:
##   rpg/input/mouse        mouse and touch input in the game, on by default (RPG service pointer_enabled)
##   rpg/audio/sound_bank   the .sf2 / .dls that MIDI music is rendered with at import; "" = Windows'
##                          gm.dls when present, else the built-in instruments (RPGSoundBank.default_path())
func _register_settings() -> void:
	const MOUSE := "rpg/input/mouse"
	if not ProjectSettings.has_setting(MOUSE):
		ProjectSettings.set_setting(MOUSE, true)
	ProjectSettings.set_initial_value(MOUSE, true)
	ProjectSettings.add_property_info({"name": MOUSE, "type": TYPE_BOOL})
	const BANK := RPGMidiRenderer.SOUND_BANK_SETTING
	if not ProjectSettings.has_setting(BANK):
		ProjectSettings.set_setting(BANK, "")
	ProjectSettings.set_initial_value(BANK, "")
	ProjectSettings.add_property_info({"name": BANK, "type": TYPE_STRING, "hint": PROPERTY_HINT_FILE, "hint_string": "*.sf2,*.dls"})


## Spec: "On startup, it detects interrupted writes ... and offers to recover from backups."
func _offer_recovery() -> void:
	var found := RPGJson.find_interrupted("res://rpg")
	if found.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "RPG Kit: interrupted save found"
	var names := []
	for f in found:
		names.append(f.trim_prefix("res://"))
	dlg.dialog_text = "These project files were being written when Godot stopped:

%s

Recover them? Finished backups are restored; unfinished writes are kept beside the file as .interrupted so nothing is lost." % "
".join(names)
	dlg.ok_button_text = "Recover"
	dlg.confirmed.connect(func():
		for r in RPGJson.recover_interrupted("res://rpg"):
			print("RPG Kit: %s: %s" % [r.file, r.action])
		EditorInterface.get_resource_filesystem().scan()
		if screen:
			screen.reload_project()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


## The Database tab is a second plugin. Checked after every plugin has loaded, so an already
## enabled Database plugin is not enabled twice.
func _enable_database() -> void:
	if not EditorInterface.is_plugin_enabled(DATABASE_PLUGIN) and FileAccess.file_exists("res://addons/rpg_database/plugin.cfg"):
		EditorInterface.set_plugin_enabled(DATABASE_PLUGIN, true)


## Development aid: with RPG_EDITOR_SHOT=<folder> set, the editor walks through the main screens
## and dialogs, saves a screenshot of each into that folder and quits.
func _editor_shot(folder: String) -> void:
	var walk: RefCounted = load("res://addons/rpg/editor/dev/rpg_editor_walkthrough.gd").new()
	await walk.run(self, screen, folder)


func _on_filesystem_changed() -> void:
	if screen and screen.is_visible_in_tree():
		screen.check_disk_changes()


func _exit_tree() -> void:
	if EditorInterface.get_resource_filesystem().filesystem_changed.is_connected(_on_filesystem_changed):
		EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_on_filesystem_changed)
	if export_check:
		remove_export_plugin(export_check)
	if midi_importer:
		remove_import_plugin(midi_importer)
		midi_importer = null
	if screen:
		screen.queue_free()
	var mv: Script = load("res://addons/rpg/editor/rpg_maker_view.gd")
	mv.shared().apply_now("RPG", false)
	mv.release()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if screen:
		screen.visible = visible
		# The Database tab keeps its own copy of the data; pick up what it saved.
		if visible and screen.data != null:
			screen.check_disk_changes.call_deferred()
	load("res://addons/rpg/editor/rpg_maker_view.gd").shared().tab_visible("RPG", visible)


func _get_plugin_name() -> String:
	return "RPG"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMapLayer", "EditorIcons")


func _save_external_data() -> void:
	if screen and screen.view and screen.view.dirty:
		screen.save_current()


## Godot asks about an unsaved map before quitting or closing the project.
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene != "" or screen == null or screen.view == null or not screen.view.dirty:
		return ""
	return "Save changes to map '%s' before closing?" % screen.current_map
