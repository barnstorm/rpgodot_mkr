@tool
extends EditorImportPlugin
## Imports .mid / .midi files as an AudioStreamWAV rendered with a General MIDI sound bank, once,
## at import time: exported games contain ordinary audio and need no synthesizer. The stream loops
## from the song's CC#111 (RPG Maker XP / VX / 2003, EasyRPG) or its start, to its end.
## Registered by addons/rpg/plugin.gd. Preloaded by path (no class_name):
##   const MidiImporter := preload("res://addons/rpg/import/midi/rpg_midi_importer.gd")
##
## Options:
##   sound_bank   .sf2 / .dls path; "" = the project setting rpg/audio/sound_bank ("" there =
##                Windows' gm.dls when present, else the built-in instruments). A bank that cannot
##                be opened falls back to the built-in instruments with a warning.
##   sample_rate  22050, 32000 (default) or 44100 Hz
##   loop         loop from the loop start to the end (off: play once, the last notes ring out)
##   volume_db    gain on top of the renderer's fixed master gain
##   compress     QOA (about 1/5 of 16-bit PCM) or 16-bit PCM


func _init() -> void:
	# Godot registers playback classes the first time one is made, and two import threads doing that
	# at once trip over each other ("Class 'AudioStreamPlaybackWAV' already exists"): make them here.
	RPGMidiRenderer.warm_up()


func _get_importer_name() -> String:
	return "rpg.midi"


func _get_visible_name() -> String:
	return "MIDI (rendered, RPG Kit)"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["mid", "midi"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "AudioStreamWAV"


func _get_format_version() -> int:
	return 1


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _can_import_threaded() -> bool:
	return true


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return import_options()


## The import options (EditorImportPlugin can only be made inside the editor, so tests use these).
static func import_options() -> Array[Dictionary]:
	return [
		{"name": "sound_bank", "default_value": "", "property_hint": PROPERTY_HINT_FILE, "hint_string": "*.sf2,*.dls"},
		{"name": "sample_rate", "default_value": RPGMidiRenderer.DEFAULT_RATE, "property_hint": PROPERTY_HINT_ENUM, "hint_string": "22050 Hz:22050,32000 Hz:32000,44100 Hz:44100"},
		{"name": "loop", "default_value": true},
		{"name": "volume_db", "default_value": 0.0, "property_hint": PROPERTY_HINT_RANGE, "hint_string": "-24,24,0.5,suffix:dB"},
		{"name": "compress", "default_value": true},
	]


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	return import_file(source_file, save_path, options)


## What _import does: renders `source_file` and saves the stream as <save_path>.res.
static func import_file(source_file: String, save_path: String, options: Dictionary) -> Error:
	var res := render(source_file, options)
	if res.stream == null:
		return ERR_PARSE_ERROR
	return ResourceSaver.save(res.stream, save_path + ".res")


## Bank warnings already printed this editor session (one per bank, not one per song).
static var _bank_warnings := {}
static var _warn_mutex := Mutex.new()


## Renders one file and prints what happened (warnings and errors name the file; a bank that
## cannot be used is reported once per session). Returns RPGMidiRenderer.render_file()'s dictionary.
static func render(source_file: String, options: Dictionary) -> Dictionary:
	var res := RPGMidiRenderer.render_file(source_file, {
		"sound_bank": str(options.get("sound_bank", "")),
		"sample_rate": int(options.get("sample_rate", RPGMidiRenderer.DEFAULT_RATE)),
		"loop": bool(options.get("loop", true)),
		"volume_db": float(options.get("volume_db", 0.0)),
		"compress": bool(options.get("compress", true)),
	})
	for w in res.warnings:
		if w.begins_with("Sound bank "):
			_warn_mutex.lock()
			var seen := _bank_warnings.has(w)
			_bank_warnings[w] = true
			_warn_mutex.unlock()
			if seen:
				continue
			push_warning("RPG Kit MIDI import: " + w)
		else:
			push_warning("RPG Kit MIDI import: %s: %s" % [source_file.get_file(), w])
	if res.stream == null:
		printerr("RPG Kit MIDI import failed: %s" % res.error)
		return res
	if res.error != "":
		printerr("RPG Kit MIDI import: %s: %s The song was imported silent." % [source_file.get_file(), res.error])
	var st: Dictionary = res.stats
	print("RPG Kit: rendered %s with %s: %.1f s of music in %.1f s, peak %.1f dBFS%s." % [
		source_file.get_file(), res.bank_name, float(st.get("seconds", 0.0)), float(st.get("render_ms", 0.0)) / 1000.0,
		float(st.get("peak_db", -INF)), " (limited)" if st.get("limited", false) else ""])
	return res
