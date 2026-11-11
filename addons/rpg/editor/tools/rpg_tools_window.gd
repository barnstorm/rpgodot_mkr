@tool
class_name RPGToolsWindow
extends AcceptDialog
## The Tools window (spec: Tools and playtest, milestone 7):
##   Event search   find commands by text, command type or referenced ID; double-click opens the event
##   Sound test     every audio file and sound role: play/stop, volume, pitch, pan; Space plays
##   Resources      asset files and whether the project uses them; preview, import, delete unused;
##                  the sound bank MIDI music is rendered with
##   Extensions     installed extensions, their commands and problems; enable or disable per project
##   Deploy         pick an export preset and build (checks first; unused assets can be left out)

signal open_location(map_id: String, event_id: String)
## A database or common-event record to open in the Database tab (file is e.g. database/troops.json).
signal open_record(file: String, id: String)
signal extensions_changed()

var data: RPGProjectData
var registry: RPGCommandRegistry
var tabs: TabContainer
var player: AudioStreamPlayer

var _search_text: LineEdit
var _search_type: OptionButton
var _search_ref: LineEdit
var _search_results: Tree
var _search_count: Label

const Deploy := preload("res://addons/rpg/editor/tools/rpg_deploy.gd")
const ResourceFiles := preload("res://addons/rpg/editor/tools/rpg_resource_files.gd")
const RMImport := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")
const ExtensionHost := preload("res://addons/rpg/runtime/rpg_extension_host.gd")

## Sound test
var sound_list: Tree
## Resources
var res_only_unused: CheckBox
var res_files: Tree
var res_preview: TextureRect
var res_info: Label
var res_summary: Label
var res_play: Button
var res_bank_label: Label
var res_gm_button: Button
## Where a sound bank picked from outside the project is copied ("Copy into project").
const SOUNDFONT_DIR := "res://audio/soundfonts"
const BANK_HINT := "MIDI music (.mid) is rendered to audio with this General MIDI sound bank when Godot imports it; games contain only the audio. Windows' gm.dls is Microsoft's and exists only on Windows: the kit never copies it, Linux and macOS editors render with the built-in instruments instead, and you should check Microsoft's terms before selling a game whose music was rendered with it. GeneralUser GS (an .sf2 soundfont) is a free alternative; copy it into the project so every computer renders the same music."
## Deploy
var presets_path := Deploy.PRESETS_PATH
var deploy_presets: Array = []
var deploy_preset: OptionButton
var deploy_out: LineEdit
var deploy_leave_out: CheckBox
var deploy_build: Button
var deploy_open: Button
var deploy_progress: ProgressBar
var deploy_problems: Tree
var deploy_log: TextEdit
var deploy_status: Label
var _build_thread: Thread
const NO_PRESETS_HELP := "No export presets yet, so Build is off. In Godot, open Project > Export..., press Add... and pick a platform (e.g. Windows Desktop); install the export templates if Godot asks. Then reopen this window and press Build."
var _ext_tree: Tree
var _ext_note: Label
## Settings form of the extension selected in Tools > Extensions (settings_schema).
var _ext_settings_box: VBoxContainer
var _ext_settings_form: RPGFormBuilder
var _ext_settings_id := ""
var _build_started := 0
var _build_started_unix := 0
var _build_out := ""
var _close_after_build := false


func _init() -> void:
	title = "RPG Tools"
	ok_button_text = "Close"
	min_size = Vector2i(600, 380)
	unresizable = false


func setup(p_data: RPGProjectData, p_registry: RPGCommandRegistry) -> void:
	data = p_data
	registry = p_registry
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 320)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	player = AudioStreamPlayer.new()
	add_child(player)
	_build_search()
	_build_sound_test()
	_build_resources()
	_build_extensions()
	_build_deploy()
	confirmed.connect(_close)
	canceled.connect(_close)
	set_process(false)


func show_tab(tab_name: String) -> void:
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == tab_name:
			tabs.current_tab = i


func _page(tab_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = tab_name
	tabs.add_child(v)
	tabs.set_tab_title(tabs.get_tab_count() - 1, tab_name)
	return v


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	# Wrapping only in vertical boxes: in a row the label would get no width and grow very tall.
	# A width is given so the wrapped height is computed from it, not from zero width.
	if not (parent is HBoxContainer):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
	l.modulate = Color(1, 1, 1, 0.75)
	parent.add_child(l)
	return l


func _tree(parent: Control, columns: Array) -> Tree:
	var t := Tree.new()
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.columns = columns.size()
	t.column_titles_visible = true
	t.hide_root = true
	for i in columns.size():
		t.set_column_title(i, columns[i])
		t.set_column_expand(i, true)
	t.create_item()
	parent.add_child(t)
	return t


# --- event search --------------------------------------------------------------------------------

func _build_search() -> void:
	var v := _page("Event search")
	var row := HBoxContainer.new()
	v.add_child(row)
	_search_text = LineEdit.new()
	_search_text.placeholder_text = "Text (message words, names, file names...)"
	_search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_text.text_submitted.connect(func(_t): run_search())
	row.add_child(_search_text)
	_search_type = OptionButton.new()
	_search_type.add_item("Any command")
	_search_type.set_item_metadata(0, "")
	var types := []
	for d in registry.all_descriptors():
		types.append([str(d.get("category", "")), str(d.get("label", d.get("type", ""))), str(d.get("type", ""))])
	types.sort()
	for t in types:
		_search_type.add_item("%s: %s" % [t[0], t[1]] if t[0] != "" else t[1])
		_search_type.set_item_metadata(_search_type.item_count - 1, t[2])
	row.add_child(_search_type)
	_search_ref = LineEdit.new()
	_search_ref.placeholder_text = "Uses ID (switch, item...)"
	_search_ref.custom_minimum_size.x = 170
	_search_ref.text_submitted.connect(func(_t): run_search())
	row.add_child(_search_ref)
	var go := Button.new()
	go.text = "Search"
	go.pressed.connect(run_search)
	row.add_child(go)
	_search_results = _tree(v, ["Where", "Command"])
	_search_results.item_activated.connect(func():
		var it := _search_results.get_selected()
		if it:
			var m: Dictionary = it.get_metadata(0)
			# Map results open the event; common-event and battle results open the Database tab.
			match str(m.get("scope", "")):
				"map": open_location.emit(m.map, m.event)
				"common": open_record.emit("common_events.json", m.event)
				"troop": open_record.emit("database/troops.json", m.event)
			hide()
			queue_free())
	_search_count = _note(v, "Search map events, common events and battle pages. Double-click a result to open it (map events in the map editor, the rest in the Database tab).")


func run_search() -> Array:
	var q := {"text": _search_text.text, "type": str(_search_type.get_item_metadata(_search_type.selected)), "ref": _search_ref.text}
	var results := RPGProjectSearch.search(data, registry, q)
	_search_results.clear()
	var root := _search_results.create_item()
	for r in results:
		var it := _search_results.create_item(root)
		it.set_text(0, r.label)
		it.set_text(1, r.summary)
		it.set_tooltip_text(1, "%s  (path %s)" % [r.type, r.path])
		it.set_metadata(0, r)
	_search_count.text = "%d result(s)." % results.size() if q.text != "" or q.type != "" or q.ref != "" else "Enter text, pick a command type or an ID."
	return results


# --- sound test ----------------------------------------------------------------------------------

## Name of the bus the Sound test plays on; it carries an AudioEffectPanner for the Pan slider.
## Added when the window opens and removed when it closes, so the project's bus layout is unchanged.
const SOUND_TEST_BUS := "RPG Sound Test"


func _ensure_sound_bus() -> int:
	var idx := AudioServer.get_bus_index(SOUND_TEST_BUS)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, SOUND_TEST_BUS)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
	return idx


func _remove_sound_bus() -> void:
	var idx := AudioServer.get_bus_index(SOUND_TEST_BUS)
	if idx > 0:
		if player != null:
			player.stop()
		AudioServer.remove_bus(idx)
		# Godot's Audio panel saves the bus layout whenever it changes. Adding and removing the
		# temporary bus would leave a default_bus_layout.tres the maker never asked for.
		if not _had_bus_layout and Engine.is_editor_hint():
			_drop_bus_layout_file.call_deferred()


var _had_bus_layout := FileAccess.file_exists("res://default_bus_layout.tres")


static func _drop_bus_layout_file() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(1.0).timeout
	var path := "res://default_bus_layout.tres"
	if FileAccess.file_exists(path):
		var layout: Resource = load(path)
		# Only an empty layout (just Master) is removed; a real one stays.
		if layout is AudioBusLayout and (layout.get("bus/1/name") == null):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if Engine.is_editor_hint():
				EditorInterface.get_resource_filesystem().scan()


## Pan in RPG Maker's -100 (left) .. 100 (right).
## The temporary bus is only made when the pan is off centre.
func set_pan(value: float) -> void:
	if is_zero_approx(value) and AudioServer.get_bus_index(SOUND_TEST_BUS) < 0:
		return
	var idx := _ensure_sound_bus()
	if player != null:
		player.bus = SOUND_TEST_BUS
	var fx := AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
	if fx != null:
		fx.pan = clampf(value / 100.0, -1.0, 1.0)


func get_pan() -> float:
	var idx := AudioServer.get_bus_index(SOUND_TEST_BUS)
	if idx < 0:
		return 0.0
	var fx := AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
	return fx.pan * 100.0 if fx != null else 0.0


func _build_sound_test() -> void:
	var v := _page("Sound test")
	var t := _tree(v, ["Sound", "Role / folder"])
	sound_list = t
	var root := t.get_root()
	var roles: Dictionary = data.project.get("sound_roles", {})
	if not roles.is_empty():
		var rnode := t.create_item(root)
		rnode.set_text(0, "Project sound roles")
		var names: Array = roles.keys()
		names.sort()
		for r in names:
			var it := t.create_item(rnode)
			it.set_text(0, str(roles[r]))
			it.set_text(1, r)
			it.set_metadata(0, str(roles[r]))
	var files := RPGProjectSearch.sound_files()
	var folders: Array = files.keys()
	folders.sort()
	for f in folders:
		var fnode := t.create_item(root)
		fnode.set_text(0, f)
		for path in files[f]:
			var it := t.create_item(fnode)
			it.set_text(0, path.get_file())
			it.set_text(1, f)
			it.set_metadata(0, path)
			it.set_tooltip_text(0, path)
	var row := HBoxContainer.new()
	v.add_child(row)
	var play := Button.new()
	play.text = "▶ Play"
	play.tooltip_text = "Play the selected sound (Space or double-click in the list)"
	row.add_child(play)
	var stop := Button.new()
	stop.text = "■ Stop"
	row.add_child(stop)
	var vol := _labeled_slider(row, "Volume", 0, 100, 80, 100)
	var pan := _labeled_slider(row, "Pan", -100, 100, 0, 100)
	pan.tooltip_text = "Pan: -100 left, 0 centre, 100 right (double-click to centre)"
	pan.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.double_click:
			pan.value = 0)
	var pl := Label.new()
	pl.text = "Pitch"
	row.add_child(pl)
	var pitch := SpinBox.new()
	pitch.min_value = 50
	pitch.max_value = 150
	pitch.step = 5
	pitch.value = 100
	pitch.suffix = "%"
	pitch.tooltip_text = "Pitch (RPG Maker's 50-150%)"
	pitch.value_changed.connect(func(x): player.pitch_scale = x / 100.0)
	row.add_child(pitch)
	var playing := Label.new()
	playing.clip_text = true
	playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playing.modulate = Color(1, 1, 1, 0.75)
	row.add_child(playing)
	_note(v, "Space plays the selected sound while the list has focus. Pan uses a temporary audio bus that is removed when this window closes.")
	var do_play := func():
		var it := t.get_selected()
		if it == null or it.get_metadata(0) == null:
			return
		var stream := _load_audio(str(it.get_metadata(0)))
		if stream == null:
			playing.text = "Cannot load %s" % it.get_metadata(0)
			return
		player.bus = &"Master"
		set_pan(pan.value)
		player.stream = stream
		player.volume_db = linear_to_db(maxf(vol.value, 0.001) / 100.0)
		player.pitch_scale = pitch.value / 100.0
		player.play()
		playing.text = "Playing %s" % str(it.get_metadata(0)).get_file()
		playing.tooltip_text = str(it.get_metadata(0))
	play.pressed.connect(do_play)
	t.item_activated.connect(do_play)
	# Space plays, as in RPG Maker's sound test (handled before the Tree's own Space handling).
	t.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
			do_play.call()
			t.accept_event())
	stop.pressed.connect(func():
		player.stop()
		playing.text = "")
	vol.value_changed.connect(func(x): player.volume_db = linear_to_db(maxf(x, 0.001) / 100.0))
	pan.value_changed.connect(set_pan)


func _labeled_slider(row: HBoxContainer, label: String, lo: float, hi: float, value: float, width: float) -> HSlider:
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.custom_minimum_size.x = width
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = label
	row.add_child(s)
	return s


func _load_audio(name_or_path: String) -> AudioStream:
	if name_or_path.begins_with("res://") and ResourceLoader.exists(name_or_path):
		return load(name_or_path) as AudioStream
	for f in RPGProjectSearch.sound_files().values():
		for p in f:
			if p.get_file().get_basename() == name_or_path:
				return load(p) as AudioStream
	return null


# --- resources -----------------------------------------------------------------------------------

func _build_resources() -> void:
	var v := _page("Resources")
	# Asset packs: licence and detected profile (spec: art is used only where its licence allows).
	var packs := _tree(v, ["Pack", "Licence", "Profile", "Notes"])
	packs.custom_minimum_size.y = 76
	packs.size_flags_vertical = Control.SIZE_FILL
	for rep in RPGAssets.scan_packs():
		var it := packs.create_item(packs.get_root())
		it.set_text(0, str(rep.name))
		it.set_tooltip_text(0, str(rep.path))
		it.set_text(1, str(rep.license) if rep.license_verified else "UNVERIFIED")
		if not rep.license_verified:
			it.set_custom_color(1, Color(1, 0.6, 0.3))
		it.set_text(2, ", ".join(PackedStringArray(rep.profile_candidates)))
		var notes: Array = rep.conflicts + rep.warnings
		it.set_text(3, "; ".join(PackedStringArray(notes)) if not notes.is_empty() else "ok")
		it.set_tooltip_text(3, "\n".join(PackedStringArray(notes)))
	var top := HBoxContainer.new()
	v.add_child(top)
	res_only_unused = CheckBox.new()
	res_only_unused.text = "Only files the project does not use"
	res_only_unused.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(res_only_unused)
	var import_btn := Button.new()
	import_btn.text = "Import..."
	import_btn.tooltip_text = "Copy image or audio files into a pack's asset folder for one asset type"
	import_btn.pressed.connect(_import_dialog)
	top.add_child(import_btn)
	var rm_btn := Button.new()
	rm_btn.text = "Import an RPG Maker project or RTP folder..."
	rm_btn.tooltip_text = "Copy your own RPG Maker art and audio (2000/2003, XP, VX, VX Ace, MV, MZ) into a pack and create tileset records. Nothing is downloaded."
	rm_btn.pressed.connect(_rm_import_pick)
	top.add_child(rm_btn)
	_build_bank_row(v)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(split)
	res_files = _tree(split, ["File", "Folder", "Used"])
	res_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_files.set_column_expand_ratio(0, 3)
	# Preview: images at 2x (pixel art stays sharp), sounds with play/stop; then Delete.
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 230
	split.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	res_preview = TextureRect.new()
	res_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	res_preview.stretch_mode = TextureRect.STRETCH_SCALE
	res_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scroll.add_child(res_preview)
	res_info = Label.new()
	res_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_info.custom_minimum_size.x = 220
	res_info.modulate = Color(1, 1, 1, 0.75)
	side.add_child(res_info)
	var actions := HBoxContainer.new()
	side.add_child(actions)
	var play := Button.new()
	play.text = "▶ Play"
	play.disabled = true
	res_play = play
	actions.add_child(play)
	var stop := Button.new()
	stop.text = "■ Stop"
	actions.add_child(stop)
	var del := Button.new()
	del.text = "Delete..."
	del.tooltip_text = "Delete a file the project does not use (it goes to the system trash)"
	actions.add_child(del)
	res_summary = _note(v, "")
	res_files.item_selected.connect(_preview_selected)
	res_files.item_activated.connect(func(): play.pressed.emit())
	play.pressed.connect(func():
		var p := _selected_asset()
		if p != "" and ResourceFiles.AUDIO_EXT.has(p.get_extension().to_lower()):
			var s := ResourceFiles.load_preview_audio(p)
			if s != null:
				player.bus = "Master"
				player.stream = s
				player.volume_db = 0.0
				player.pitch_scale = 1.0
				player.play())
	stop.pressed.connect(func(): player.stop())
	del.pressed.connect(func(): _confirm_delete(_selected_asset()))
	res_only_unused.toggled.connect(func(_on): refresh_resources())
	refresh_resources()


# --- MIDI sound bank ------------------------------------------------------------------------------

## One row: the bank MIDI is rendered with, and Pick / gm.dls / Built-in.
func _build_bank_row(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.tooltip_text = BANK_HINT
	v.add_child(row)
	var l := Label.new()
	l.text = "MIDI sound bank:"
	l.tooltip_text = BANK_HINT
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	res_bank_label = Label.new()
	res_bank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_bank_label.clip_text = true
	res_bank_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(res_bank_label)
	var pick := Button.new()
	pick.text = "Pick .sf2 / .dls..."
	pick.tooltip_text = BANK_HINT
	pick.pressed.connect(_pick_sound_bank)
	row.add_child(pick)
	res_gm_button = Button.new()
	res_gm_button.text = "Use Windows gm.dls"
	res_gm_button.tooltip_text = "Microsoft's GS Wavetable set, as RPG Maker 2000/2003 and XP played MIDI. Windows only; never copied into the project. Check Microsoft's terms before selling a game whose music was rendered with it."
	res_gm_button.visible = windows_gm_dls() != ""
	res_gm_button.pressed.connect(func(): set_sound_bank(windows_gm_dls()))
	row.add_child(res_gm_button)
	var builtin := Button.new()
	builtin.text = "Built-in"
	builtin.tooltip_text = "Simple instruments made in code: the same on every computer, no files, no licence."
	builtin.pressed.connect(func(): set_sound_bank("builtin"))
	row.add_child(builtin)
	_update_bank_label()


## Windows' gm.dls path, or "" when this computer has none.
static func windows_gm_dls() -> String:
	var p := RPGSoundBank.default_path()
	return p if p != "builtin" else ""


## Text for the current bank: what the setting says and what renders with it on this computer.
static func sound_bank_text() -> String:
	var setting := str(ProjectSettings.get_setting(RPGMidiRenderer.SOUND_BANK_SETTING, "")).strip_edges()
	var path := RPGMidiRenderer.bank_path_for("")
	var shown := "built-in instruments" if path == "builtin" else path
	if setting == "":
		shown += " (default)"
	elif path != "builtin" and not FileAccess.file_exists(path):
		shown += " (missing here: the built-in instruments are used)"
	return shown


func _update_bank_label() -> void:
	if res_bank_label != null:
		res_bank_label.text = sound_bank_text()
		res_bank_label.tooltip_text = RPGMidiRenderer.bank_path_for("") + "\n\n" + BANK_HINT


func _pick_sound_bank() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.sf2 ; SoundFont", "*.dls ; DLS sound bank"])
	fd.title = "Pick the sound bank MIDI music is rendered with"
	fd.file_selected.connect(func(file: String):
		fd.hide()
		fd.queue_free()
		_bank_picked.call_deferred(file.replace("\\", "/")))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


## A picked bank: one inside the project is used as it is; an .sf2 from outside can be copied in
## first (gm.dls never is).
func _bank_picked(file: String) -> void:
	var local := ProjectSettings.localize_path(file)
	if local.begins_with("res://") or file.get_extension().to_lower() != "sf2":
		set_sound_bank(local)
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Sound bank outside the project"
	dlg.dialog_text = "%s is outside the project, so another computer (or Linux / macOS) would render the MIDI music with the built-in instruments instead.\n\nCopy it into the project (%s/) so every computer renders the same music? It is not put into exported games." % [file.get_file(), SOUNDFONT_DIR]
	dlg.get_ok_button().text = "Copy into project"
	dlg.get_cancel_button().text = "Use it where it is"
	dlg.confirmed.connect(func():
		dlg.queue_free()
		var r := copy_bank_into_project(file)
		if r.error != "":
			_message("Sound bank", r.error)
			return
		ResourceFiles.rescan()
		set_sound_bank(r.path))
	dlg.canceled.connect(func():
		dlg.queue_free()
		set_sound_bank(file))
	add_child(dlg)
	dlg.popup_centered()


## Copies a soundfont into `dir` (SOUNDFONT_DIR). Returns {path, error}. Refused for anything but
## .sf2 (gm.dls is Microsoft's and stays where it is).
static func copy_bank_into_project(src: String, dir := SOUNDFONT_DIR) -> Dictionary:
	if src.get_extension().to_lower() != "sf2":
		return {"path": "", "error": "Only .sf2 soundfonts are copied into the project."}
	var dst := dir.path_join(src.get_file())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
	if err != OK:
		return {"path": "", "error": "Cannot copy %s (error %d)." % [src.get_file(), err]}
	return {"path": dst, "error": ""}


## Sets rpg/audio/sound_bank ("" = default, "builtin", a res:// or absolute path); with `save` the
## project settings are saved and re-rendering the project's MIDI files is offered.
func set_sound_bank(path: String, save := true) -> void:
	ProjectSettings.set_setting(RPGMidiRenderer.SOUND_BANK_SETTING, path)
	_update_bank_label()
	if not save:
		return
	ProjectSettings.save()
	var files := midi_files()
	if files.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "MIDI sound bank changed"
	dlg.dialog_text = "MIDI music is now rendered with %s.\nRender the project's %d MIDI file(s) again now? (This can take a while.)" % [sound_bank_text(), files.size()]
	dlg.get_ok_button().text = "Re-render all MIDI"
	dlg.get_cancel_button().text = "Later"
	dlg.confirmed.connect(func():
		dlg.queue_free()
		rerender_midi())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## Every .mid / .midi file in the project.
static func midi_files(root := "res://") -> PackedStringArray:
	return RPGProjectSearch.list_files(root, ["mid", "midi"])


## Asks the editor to import every MIDI file again (with the current sound bank). Returns how many.
static func rerender_midi() -> int:
	var files := midi_files()
	if files.is_empty() or not Engine.has_singleton("EditorInterface"):
		return 0
	var ei: Object = Engine.get_singleton("EditorInterface")
	ei.get_resource_filesystem().reimport_files(files)
	return files.size()


## Refills the Resources file list (after toggling the filter, importing or deleting).
func refresh_resources() -> void:
	res_files.clear()
	var root := res_files.create_item()
	var usage := RPGProjectSearch.asset_usage(data)
	var defaults := Deploy.runtime_names(data)
	var unused := 0
	for u in usage:
		var by_default: bool = not u.used and defaults.has(str(u.name))
		var used: bool = u.used or by_default
		if not used:
			unused += 1
		if res_only_unused.button_pressed and used:
			continue
		var it := res_files.create_item(root)
		it.set_text(0, u.path.get_file())
		it.set_tooltip_text(0, u.path)
		it.set_text(1, u.folder)
		it.set_text(2, "default" if by_default else ("yes" if used else "no"))
		if by_default:
			it.set_tooltip_text(2, "Not named in project data, but the game loads it by default (sound role or window skin).")
		elif not used:
			it.set_custom_color(2, Color(1, 0.75, 0.4))
		it.set_metadata(0, u.path)
	res_summary.text = "%d asset files, %d unused (\"default\" files are loaded by the game itself; ChipSets used through tilesets.json count as used). Deploy can leave unused files out." % [usage.size(), unused]
	res_preview.texture = null
	res_preview.custom_minimum_size = Vector2.ZERO
	res_info.text = "Select a file to preview it."


func _selected_asset() -> String:
	var it: TreeItem = res_files.get_selected() if res_files != null else null
	return str(it.get_metadata(0)) if it != null and it.get_metadata(0) != null else ""


## Shows the selected file: images at 2x, sounds with their length.
func preview_asset(p: String) -> void:
	res_preview.texture = null
	res_preview.custom_minimum_size = Vector2.ZERO
	var is_audio := ResourceFiles.AUDIO_EXT.has(p.get_extension().to_lower())
	res_play.disabled = not is_audio
	if p == "":
		return
	var info := p.trim_prefix("res://")
	if is_audio:
		var s := ResourceFiles.load_preview_audio(p)
		info += ("\nSound, %.1f s. Play or double-click." % s.get_length()) if s != null else "\nCannot load this sound."
	else:
		var tex := ResourceFiles.load_preview_texture(p)
		if tex != null:
			res_preview.texture = tex
			res_preview.custom_minimum_size = tex.get_size() * 2.0
			info += "\n%d x %d px (shown at 2x)" % [tex.get_width(), tex.get_height()]
		else:
			info += "\nCannot load this image."
	res_info.text = info


func _preview_selected() -> void:
	preview_asset(_selected_asset())


func _confirm_delete(path: String) -> void:
	if path == "":
		return
	var used := Deploy.where_used(data, path)
	if not used.is_empty():
		_message("Cannot delete %s" % path.get_file(), "%s is used by:\n  %s\n\nRemove those uses first." % [path.get_file(), "\n  ".join(PackedStringArray(used))])
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete file"
	dlg.dialog_text = "Delete %s?\nThe project does not use it. It is moved to the system trash." % path.trim_prefix("res://")
	dlg.get_ok_button().text = "Delete"
	dlg.confirmed.connect(func():
		var r := ResourceFiles.delete_asset(data, path)
		ResourceFiles.rescan()
		refresh_resources()
		res_info.text = str(r.message)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _message(p_title: String, text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = p_title
	dlg.dialog_text = text
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## Import: pick an asset type and a pack, then files. Existing files are only replaced after asking.
func _import_dialog() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Import assets"
	var grid := GridContainer.new()
	grid.columns = 2
	dlg.add_child(grid)
	var tl := Label.new()
	tl.text = "Asset type"
	grid.add_child(tl)
	var type_opt := OptionButton.new()
	for t in ResourceFiles.TYPES:
		type_opt.add_item("%s  ->  %s/" % [t[0], RPGAssets.folder_for(t[1])])
		type_opt.set_item_metadata(type_opt.item_count - 1, t[1])
	grid.add_child(type_opt)
	var pl := Label.new()
	pl.text = "Pack"
	grid.add_child(pl)
	var pack_opt := OptionButton.new()
	var packs := RPGAssets.packs()
	if not packs.has(ResourceFiles.DEFAULT_PACK):
		packs.push_front(ResourceFiles.DEFAULT_PACK)
	for p in packs:
		pack_opt.add_item(p + " (your own files)" if p == ResourceFiles.DEFAULT_PACK else p)
		pack_opt.set_item_metadata(pack_opt.item_count - 1, p)
	grid.add_child(pack_opt)
	dlg.get_ok_button().text = "Choose files..."
	dlg.confirmed.connect(func():
		var kind := str(type_opt.get_item_metadata(type_opt.selected))
		var pack := str(pack_opt.get_item_metadata(pack_opt.selected))
		dlg.queue_free()
		_pick_import_files(kind, pack))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(420, 0))


func _pick_import_files(kind: String, pack: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Import %s files" % RPGAssets.folder_for(kind)
	var filters := PackedStringArray()
	for e in ResourceFiles.allowed_extensions(kind):
		filters.append("*.%s" % e)
	fd.filters = PackedStringArray([", ".join(filters) + " ; " + RPGAssets.folder_for(kind)])
	fd.files_selected.connect(func(paths: PackedStringArray):
		fd.queue_free()
		_do_import(paths, kind, pack))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _do_import(paths: PackedStringArray, kind: String, pack: String, overwrite := false) -> void:
	var r := ResourceFiles.import_files(paths, kind, pack, "res://assets", overwrite)
	if not r.copied.is_empty():
		ResourceFiles.rescan()
		refresh_resources()
	var lines := PackedStringArray()
	if not r.copied.is_empty():
		lines.append("Imported %d file(s) into assets/%s/%s/." % [r.copied.size(), pack, RPGAssets.folder_for(kind)])
	for e in r.errors:
		lines.append(str(e))
	res_info.text = "\n".join(lines)
	if r.conflicts.is_empty():
		return
	var names := PackedStringArray()
	var again := PackedStringArray()
	for c in r.conflicts:
		names.append(str(c).get_file())
		for p in paths:
			if p.get_file() == str(c).get_file():
				again.append(p)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Replace files?"
	dlg.dialog_text = "These files already exist in assets/%s/%s/:\n  %s\n\nReplace them?" % [pack, RPGAssets.folder_for(kind), "\n  ".join(names)]
	dlg.get_ok_button().text = "Replace"
	dlg.confirmed.connect(func():
		dlg.queue_free()
		_do_import(again, kind, pack, true))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## RPG Maker folder import: pick a folder, review what will be copied and created, then import.
func _rm_import_pick() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Pick an RPG Maker project or RTP folder"
	fd.dir_selected.connect(func(dir: String):
		# The file dialog is still the exclusive child here: let it go first, then open the preview.
		fd.hide()
		fd.queue_free()
		open_rm_import.call_deferred(dir))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


## The preview dialog for one folder (returned so tests and screenshots can look at it).
func open_rm_import(dir: String) -> ConfirmationDialog:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Import RPG Maker files"
	dlg.get_ok_button().text = "Import"
	var v := VBoxContainer.new()
	dlg.add_child(v)
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size.x = 600
	v.add_child(head)
	var row := HBoxContainer.new()
	v.add_child(row)
	var pl := Label.new()
	pl.text = "Pack name"
	row.add_child(pl)
	var pack := LineEdit.new()
	pack.text = RMImport.suggest_pack_id(dir)
	pack.custom_minimum_size.x = 200
	pack.tooltip_text = "Files go to assets/<pack name>/ (lowercase letters, digits and _)"
	row.add_child(pack)
	var refresh := Button.new()
	refresh.text = "Update list"
	row.add_child(refresh)
	var t := Tree.new()
	t.columns = 2
	t.hide_root = true
	t.column_titles_visible = true
	t.set_column_title(0, "Will be imported (untick to leave out)")
	t.set_column_title(1, "Into / note")
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(600, 260)
	v.add_child(t)
	var warn := Label.new()
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size.x = 600
	warn.modulate = Color(1, 0.8, 0.5)
	v.add_child(warn)
	var state := {"plan": {}}
	var fill := func():
		var p := RMImport.plan(dir, pack.text.strip_edges())
		state.plan = p
		t.clear()
		var root := t.create_item()
		var ok := str(p.profile) != "" and RPGIds.is_valid(pack.text.strip_edges())
		head.text = ("Found an RPG Maker %s folder: %s\n(%s)" % [RMImport._profile_name(str(p.profile)), str(p.base), ", ".join(PackedStringArray(p.evidence))]) if str(p.profile) != "" else "No RPG Maker folder layout found in %s." % dir
		dlg.get_ok_button().disabled = not ok or p.files.is_empty()
		var files_node := _check_item(t, root, "Files to copy (%d)" % p.files.size(), null)
		var by_folder := {}
		for f in p.files:
			if not by_folder.has(f.folder):
				by_folder[f.folder] = _check_item(t, files_node, str(f.folder), null)
				by_folder[f.folder].collapsed = true
			var it := _check_item(t, by_folder[f.folder], str(f.src).get_file(), str(f.dst))
			it.set_text(1, ("replaces existing file (asks first)" if f.exists else str(f.dst).trim_prefix("res://")) + (" (%s -> PNG)" % str(f.src).get_extension().to_upper() if f.convert else ""))
			if f.exists:
				it.set_custom_color(1, Color(1, 0.7, 0.4))
		for folder in by_folder:
			by_folder[folder].set_text(1, "%d file(s)" % by_folder[folder].get_child_count())
		var ts_node := _check_item(t, root, "Tileset records (%d)" % p.tilesets.size(), null)
		ts_node.set_text(1, "added to database/tilesets.json")
		for ts in p.tilesets:
			var rec: Dictionary = ts.record
			var it := _check_item(t, ts_node, "%s (%s)" % [rec.name, rec.id], str(rec.id))
			var sheets := RPGTilesetBuilder.record_sheet_paths(rec)
			var names := PackedStringArray()
			for k in sheets:
				names.append(str(sheets[k]).get_file())
			it.set_text(1, "%s: %s" % [rec.profile, ", ".join(names)])
			it.set_tooltip_text(1, str(ts.warning) if str(ts.warning) != "" else ", ".join(names))
		if not p.skipped.is_empty():
			var sk := t.create_item(root)
			sk.set_text(0, "Skipped (%d)" % p.skipped.size())
			sk.collapsed = true
			for s in p.skipped:
				var it := t.create_item(sk)
				it.set_text(0, str(s.src).get_file())
				it.set_text(1, str(s.reason))
				it.set_tooltip_text(0, str(s.src))
				it.set_tooltip_text(1, str(s.reason))
		warn.text = "\n".join(PackedStringArray(p.warnings)) + ("\n" if not p.warnings.is_empty() else "") + "These are your own RPG Maker files: check the RPG Maker EULA before you share a game that uses them."
	t.item_edited.connect(func():
		var it := t.get_edited()
		if it != null:
			_set_checked_down(it, it.is_checked(0)))
	refresh.pressed.connect(fill)
	pack.text_submitted.connect(func(_x): fill.call())
	fill.call()
	dlg.confirmed.connect(func():
		var files := []
		var ids := []
		_collect_checked(t.get_root(), files, ids)
		var p: Dictionary = state.plan
		dlg.queue_free()
		_rm_import_apply(p, files, ids))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(660, 500))
	return dlg


func _check_item(t: Tree, parent: TreeItem, text: String, meta: Variant) -> TreeItem:
	var it := t.create_item(parent)
	it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	it.set_editable(0, true)
	it.set_checked(0, true)
	it.set_text(0, text)
	it.set_metadata(0, meta)
	return it


func _set_checked_down(it: TreeItem, on: bool) -> void:
	for c in it.get_children():
		if c.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK:
			c.set_checked(0, on)
			_set_checked_down(c, on)


## Ticked leaves: file dst paths go to `files`, tileset ids to `ids` (ids never start with res://).
func _collect_checked(it: TreeItem, files: Array, ids: Array) -> void:
	for c in it.get_children():
		if c.get_child_count() > 0:
			_collect_checked(c, files, ids)
		elif c.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK and c.is_checked(0) and c.get_metadata(0) != null:
			var m := str(c.get_metadata(0))
			if m.contains("://"):
				files.append(m)
			else:
				ids.append(m)


func _rm_import_apply(p: Dictionary, files: Array, ids: Array, overwrite: Array = []) -> void:
	var r := RMImport.apply(p, files, ids, overwrite)
	ResourceFiles.rescan()
	refresh_resources()
	if not r.records_added.is_empty():
		extensions_changed.emit()  # the main screen reloads the project, so the new tilesets appear
	if r.conflicts.is_empty() or not overwrite.is_empty():
		_message("RPG Maker import", RMImport.describe(p, r))
		return
	var names := PackedStringArray()
	for c in r.conflicts:
		names.append(str(c).trim_prefix("res://"))
	var dlg := ConfirmationDialog.new()
	dlg.title = "Replace files?"
	dlg.dialog_text = "%s\n\n%d file(s) already exist:\n  %s\n\nReplace them with the RPG Maker files?" % [RMImport.describe(p, r), names.size(), "\n  ".join(names.slice(0, 12)) + ("\n  ..." if names.size() > 12 else "")]
	dlg.get_ok_button().text = "Replace"
	dlg.get_cancel_button().text = "Keep mine"
	dlg.confirmed.connect(func():
		dlg.queue_free()
		_rm_import_apply(p, r.conflicts, [], r.conflicts))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


# --- extensions ----------------------------------------------------------------------------------

func _build_extensions() -> void:
	var v := _page("Extensions")
	var t := _tree(v, ["Extension", "Version", "Status", "Commands"])
	_ext_tree = t
	# The name takes the room (long names end in "..." with the full name as a tooltip); the
	# command list, also a tooltip, gets the rest.
	t.set_column_expand_ratio(0, 5)
	t.set_column_expand(1, false)
	t.set_column_custom_minimum_width(1, 76)
	t.set_column_expand(2, false)
	t.set_column_custom_minimum_width(2, 84)
	t.set_column_expand_ratio(3, 2)
	t.set_column_clip_content(0, true)
	t.set_column_clip_content(3, true)
	var enabled: Array = data.project.get("extensions", [])
	var disabled: Array = data.project.get("disabled_extensions", [])
	var root := t.get_root()
	var ext_root := str(data.project.get("extensions_root", "res://extensions"))
	var ids: Array = registry.extensions.keys()
	# Plugins bundled with the kit are listed even when the project does not use them (off).
	for b in RPGCommandRegistry.bundled_ids():
		if not ids.has(b):
			ids.append(b)
	ids.sort()
	for id in ids:
		var m: Dictionary = registry.extensions.get(id, {})
		if m.is_empty():
			m = RPGCommandRegistry.read_manifest(id, ext_root)
		var it := t.create_item(root)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_checked(0, enabled.has(id) and not disabled.has(id))
		it.set_editable(0, id != "builtin")
		it.set_text(0, "%s (%s)%s" % [m.get("name", id), id, " [kit plugin]" if m.get("_bundled", false) else ""])
		it.set_metadata(0, id)
		it.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
		it.set_text(1, str(m.get("version", "")))
		it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_text(2, "enabled" if m.get("_enabled", false) else ("off" if not enabled.has(id) else "disabled"))
		it.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_text_overrun_behavior(3, TextServer.OVERRUN_TRIM_ELLIPSIS)
		var cmds := []
		for type in registry.providers:
			if registry.providers[type] == id:
				cmds.append(type)
		if not registry.extensions.has(id):
			for rel in m.get("commands", []):
				cmds.append(str(rel).get_file().get_basename())
		cmds.sort()
		it.set_text(3, ", ".join(cmds))
		var tip := str(m.get("description", ""))
		it.set_tooltip_text(0, it.get_text(0) + ("\n" + tip if tip != "" else ""))
		it.set_tooltip_text(3, ", ".join(cmds))
	t.item_selected.connect(func():
		var sel := t.get_selected()
		if sel != null:
			show_extension_settings(str(sel.get_metadata(0))))
	_ext_settings_box = VBoxContainer.new()
	v.add_child(_ext_settings_box)
	var probs := _note(v, "")
	_ext_note = _note(v, "")
	var lines := []
	for p in registry.problems:
		lines.append("%s: %s" % [p.get("severity", "error"), p.get("message", "")])
	probs.text = "Problems: none." if lines.is_empty() else "Problems:\n" + "\n".join(lines)
	var save := Button.new()
	save.text = "Apply (writes rpg/project.json)"
	save.tooltip_text = "Disabling an extension keeps its commands in your events; they show as unavailable and block export until it is enabled again."
	var new_cmd := Button.new()
	new_cmd.text = "New command..."
	new_cmd.tooltip_text = "Create a custom event command script in the project extension (extensions/project/commands/)"
	new_cmd.pressed.connect(_new_command_dialog)
	v.add_child(new_cmd)
	save.pressed.connect(func():
		var on := []
		var off := []
		var bundled := RPGCommandRegistry.bundled_ids()
		var it := root.get_first_child()
		while it:
			var id: String = it.get_metadata(0)
			if id != "builtin":
				# A kit plugin the project never used stays out of project.json when unchecked;
				# one it used is listed as disabled, so its commands show as unavailable.
				var listed: bool = enabled.has(id) or not bundled.has(id)
				if it.is_checked(0) or listed:
					on.append(id)
				if not it.is_checked(0) and listed:
					off.append(id)
			it = it.get_next()
		for id in enabled:
			if not on.has(id):
				on.append(id)
		set_extensions(on, off)
		extensions_changed.emit())
	v.add_child(save)


## Shows the settings form of an extension (its manifest settings_schema) below the list, with
## a button that writes the values to rpg/extensions.json.
func show_extension_settings(ext_id: String) -> void:
	_ext_settings_id = ext_id
	for c in _ext_settings_box.get_children():
		c.queue_free()
	_ext_settings_form = null
	var ext_root := str(data.project.get("extensions_root", "res://extensions"))
	var m: Dictionary = registry.extensions.get(ext_id, {})
	if m.is_empty():
		m = RPGCommandRegistry.read_manifest(ext_id, ext_root)
	var fields := RPGCommandRegistry.settings_fields(m)
	if fields.is_empty():
		return
	var head := Label.new()
	head.text = "Settings: %s" % m.get("name", ext_id)
	_ext_settings_box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ext_settings_box.add_child(scroll)
	var form := RPGFormBuilder.new()
	form.setup(fields, data, registry, {"flush_checks": true})
	scroll.add_child(form)
	var values := RPGCommandRegistry.settings_defaults(m)
	values.merge(ExtensionHost.load_settings_file(data.root).get(ext_id, {}), true)
	form.set_value(values)
	_ext_settings_form = form
	var save := Button.new()
	save.text = "Save settings (writes rpg/extensions.json)"
	save.pressed.connect(func():
		var err := save_extension_settings(ext_id, form.get_value())
		if _ext_note != null:
			_ext_note.text = ("Saved the settings of %s." % ext_id) if err == OK else ("Cannot write rpg/extensions.json (error %d)." % err))
	_ext_settings_box.add_child(save)


## Writes an extension's settings for this project.
func save_extension_settings(ext_id: String, values: Dictionary) -> Error:
	return ExtensionHost.save_settings(data.root, ext_id, values)


func _new_command_dialog() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "New event command"
	var grid := GridContainer.new()
	grid.columns = 2
	dlg.add_child(grid)
	var fields := {}
	for spec in [["type", "Type ID", "play_cutscene"], ["label", "Label", "Play cutscene"], ["category", "Category", "project"]]:
		var l := Label.new()
		l.text = spec[1]
		grid.add_child(l)
		var e := LineEdit.new()
		e.placeholder_text = spec[2]
		e.custom_minimum_size.x = 260
		grid.add_child(e)
		fields[spec[0]] = e
	var msg := Label.new()
	msg.add_theme_color_override("font_color", Color(1, 0.55, 0.5))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = 260
	grid.add_child(Control.new())
	grid.add_child(msg)
	fields.type.tooltip_text = "Lowercase letters, digits and _, starting with a letter (e.g. play_cutscene)"
	dlg.get_ok_button().text = "Create"
	# The dialog stays open until the command is made, so a bad ID can be corrected in place.
	dlg.dialog_hide_on_ok = false
	var create := func():
		var ext_root := str(data.project.get("extensions_root", "res://extensions"))
		var type: String = fields.type.text.strip_edges()
		if type == "":
			msg.text = "Type an ID for the command (e.g. play_cutscene)."
			fields.type.grab_focus()
			return
		var r := create_command(ext_root.path_join("project"), type, fields.label.text.strip_edges(), fields.category.text.strip_edges())
		if r.error != OK:
			msg.text = str(r.message)
			fields.type.grab_focus()
			return
		dlg.hide()
		dlg.queue_free()
		var opened := false
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
			var scr: Variant = load(r.path)
			if scr is Script:
				EditorInterface.edit_script(scr)
				opened = true
		extensions_changed.emit()
		if _ext_note != null:
			_ext_note.text = "Created %s%s. It is listed in the event editor's Insert command list." % [r.path, " and opened it in the Script tab" if opened else ""]
	dlg.confirmed.connect(create)
	for e in fields.values():
		e.text_submitted.connect(func(_t): create.call())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(420, 0))


## Writes a command script from the template and lists it in the extension's manifest.json.
## Returns {error, path, message}.
static func create_command(ext_dir: String, type: String, label := "", category := "project") -> Dictionary:
	if not RPGIds.is_valid(type):
		return {"error": ERR_INVALID_PARAMETER, "path": "", "message": "'%s' is not a valid ID (lowercase letters, digits and _; starts with a letter)." % type}
	var manifest_path := ext_dir.path_join("manifest.json")
	var manifest: Dictionary = RPGJson.load_or(manifest_path, {})
	if manifest.is_empty():
		return {"error": ERR_FILE_NOT_FOUND, "path": "", "message": "%s does not exist." % manifest_path}
	var rel := "commands/%s.gd" % type
	var path := ext_dir.path_join(rel)
	if FileAccess.file_exists(path) or (manifest.get("commands", []) as Array).has(rel):
		return {"error": ERR_ALREADY_EXISTS, "path": path, "message": "%s already exists." % path}
	if label == "":
		label = type.capitalize()
	if category == "":
		category = "project"
	var src := COMMAND_TEMPLATE.replace("{type}", type).replace("{label}", label.c_escape()).replace("{category}", category.c_escape())
	DirAccess.make_dir_recursive_absolute(ext_dir.path_join("commands"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"error": FileAccess.get_open_error(), "path": path, "message": "Cannot write %s." % path}
	f.store_string(src)
	f.close()
	var cmds: Array = manifest.get("commands", [])
	cmds.append(rel)
	manifest["commands"] = cmds
	var err := RPGJson.save_file(manifest_path, manifest)
	return {"error": err, "path": path, "message": "" if err == OK else "Cannot update the manifest (error %d)." % err}


const COMMAND_TEMPLATE := """@tool
extends RPGCommand
## {label}: a custom event command. Its form in the event editor is built from descriptor().
## Edit run() to make it do something. Every wait must go through `ctx` so the event can be
## cancelled (ctx.wait_seconds, ctx.wait_signal, ctx.wait_frames).


static func descriptor() -> Dictionary:
	return {
		"type": "{type}",
		"schema_version": 1,
		"category": "{category}",
		"label": "{label}",
		"fields": [
			{"key": "message", "kind": "text", "default": "Hello!", "label": "Message"},
			{"key": "seconds", "kind": "float", "default": 0.5, "min": 0.0, "max": 10.0, "label": "Wait (seconds)"},
		],
	}


func summary(args: Dictionary) -> String:
	return "{label}: %s" % args.message


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	print("{type}: ", args.message, " (event ", ctx.event_id(), " on map ", ctx.map_id(), ")")
	if not await ctx.wait_seconds(float(args.seconds)):
		return RPGResult.cancelled()
	return RPGResult.ok()
"""


## Writes the enabled/disabled extension lists to project.json.
func set_extensions(enabled_ids: Array, disabled_ids: Array) -> Error:
	var path := data.root.path_join("project.json")
	var file: Dictionary = RPGJson.load_or(path, data.project)
	file["extensions"] = enabled_ids
	if disabled_ids.is_empty():
		file.erase("disabled_extensions")
	else:
		file["disabled_extensions"] = disabled_ids
	var err := RPGJson.save_file(path, file)
	if err == OK:
		data.project = file
	return err


# --- deploy --------------------------------------------------------------------------------------

func _build_deploy() -> void:
	var v := _page("Deploy")
	# A preset file left modified by an interrupted build is put back first.
	if Deploy.restore_presets(presets_path):
		push_warning("RPG Deploy: restored %s after an interrupted build." % presets_path)
	_note(v, "Pick a platform and press Build. The export checks run first; errors stop the build, warnings do not.")
	var row := HBoxContainer.new()
	v.add_child(row)
	var pl := Label.new()
	pl.text = "Platform"
	row.add_child(pl)
	deploy_preset = OptionButton.new()
	deploy_preset.custom_minimum_size.x = 150
	deploy_preset.tooltip_text = "Godot export presets (Project > Export)"
	row.add_child(deploy_preset)
	var ol := Label.new()
	ol.text = "Output"
	row.add_child(ol)
	deploy_out = LineEdit.new()
	deploy_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_out.tooltip_text = "Where the game is written, relative to the project folder"
	row.add_child(deploy_out)
	deploy_build = Button.new()
	deploy_build.text = "Build"
	deploy_build.pressed.connect(start_build)
	row.add_child(deploy_build)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	deploy_leave_out = CheckBox.new()
	deploy_leave_out.button_pressed = true
	var unused := Deploy.unused_asset_excludes(data)
	deploy_leave_out.text = "Leave out unused assets (%d file(s))" % unused.size()
	deploy_leave_out.tooltip_text = "Asset files that no project data uses and the runtime never loads by default:\n" + ("\n".join(unused) if not unused.is_empty() else "(none)")
	deploy_leave_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(deploy_leave_out)
	deploy_progress = ProgressBar.new()
	deploy_progress.custom_minimum_size = Vector2(140, 0)
	deploy_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	deploy_progress.indeterminate = true
	deploy_progress.visible = false
	row2.add_child(deploy_progress)
	deploy_open = Button.new()
	deploy_open.text = "Open folder"
	deploy_open.disabled = true
	deploy_open.pressed.connect(func():
		var abs_out := _abs_output()
		if FileAccess.file_exists(abs_out):
			OS.shell_show_in_file_manager(abs_out)
		else:
			OS.shell_open(abs_out.get_base_dir()))
	row2.add_child(deploy_open)
	deploy_presets = Deploy.presets(presets_path)
	var title := str(data.project.get("name", data.system.get("title", "Game")))
	for p in deploy_presets:
		deploy_preset.add_item("%s (%s)" % [p.name, p.platform] if p.name != p.platform else str(p.name))
	deploy_preset.item_selected.connect(func(i: int):
		deploy_out.text = Deploy.default_output(str(deploy_presets[i].platform), title))
	if deploy_presets.is_empty():
		deploy_preset.add_item("(no presets)")
		deploy_preset.disabled = true
		deploy_build.disabled = true
		deploy_build.tooltip_text = "Add an export preset in Project > Export first."
	else:
		deploy_out.text = Deploy.default_output(str(deploy_presets[0].platform), title)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(split)
	deploy_problems = _tree(split, ["Severity", "Where", "Problem"])
	deploy_problems.custom_minimum_size.y = 80
	deploy_log = TextEdit.new()
	deploy_log.editable = false
	deploy_log.custom_minimum_size.y = 70
	deploy_log.placeholder_text = "Build log"
	deploy_log.visible = false
	split.add_child(deploy_log)
	deploy_status = _note(v, "")
	if deploy_presets.is_empty():
		# The Build button is off: say why and what to do, where the maker is looking.
		deploy_status.text = NO_PRESETS_HELP
	deploy_problems.item_activated.connect(func():
		var it := deploy_problems.get_selected()
		if it != null and it.get_metadata(0) is Dictionary:
			var p: Dictionary = it.get_metadata(0)
			var loc := problem_location(p)
			if str(loc.map) != "":
				open_location.emit(loc.map, loc.event)
			else:
				open_record.emit(str(p.get("file", "")), str(loc.event))
			hide()
			queue_free())
	# Kept as the page's last child: tools/editor_preview.gd presses it for the Deploy screenshot.
	var run := Button.new()
	run.text = "Run export checks"
	v.add_child(run)
	run.pressed.connect(func(): run_deploy_checks())


## Shows the Deploy tab with the checks run (the playtest dialog's "Show problems").
func run_checks() -> int:
	show_tab("Deploy")
	return run_deploy_checks()


## Runs the export checks and lists the problems. Returns the number of errors.
func run_deploy_checks() -> int:
	deploy_problems.clear()
	var root := deploy_problems.create_item()
	var problems := RPGExportCheck.run_checks(data.root)
	var errors := 0
	for p in problems:
		var it := deploy_problems.create_item(root)
		var sev := str(p.get("severity", "error"))
		if sev == "error":
			errors += 1
			it.set_custom_color(0, Color(1, 0.45, 0.4))
		it.set_text(0, sev)
		it.set_text(1, "%s %s" % [str(p.get("file", "")).get_file(), p.get("record", p.get("where", ""))])
		it.set_text(2, str(p.get("message", "")))
		it.set_tooltip_text(2, str(p.get("message", "")) + ("\nFix: " + str(p.fix_hint) if str(p.get("fix_hint", "")) != "" else "") + "\nDouble-click to open it.")
		it.set_metadata(0, p)
	deploy_status.text = "Ready to export: no errors (%d warnings)." % (problems.size() - errors) if errors == 0 else "%d error(s) block export. Fix them (double-click to open), then try again." % errors
	return errors


func _abs_output() -> String:
	var out := deploy_out.text.strip_edges()
	if out.begins_with("res://"):
		return ProjectSettings.globalize_path(out)
	if out.is_relative_path():
		return ProjectSettings.globalize_path("res://").path_join(out)
	return out


## Build: checks, then (optionally) unused assets added to a temporary copy of the preset's
## exclude list, then a headless `godot --export-release` on a thread so the editor stays usable.
func start_build() -> void:
	if _build_thread != null:
		return
	if deploy_presets.is_empty():
		deploy_status.text = NO_PRESETS_HELP
		return
	deploy_open.disabled = true
	if run_deploy_checks() > 0:
		deploy_status.text += " The build was not started."
		return
	var preset: Dictionary = deploy_presets[deploy_preset.selected]
	if deploy_out.text.strip_edges() == "":
		deploy_out.text = Deploy.default_output(str(preset.platform), str(data.project.get("name", "Game")))
	var abs_out := _abs_output()
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var note := ""
	if deploy_leave_out.button_pressed:
		var excludes := Deploy.unused_asset_excludes(data)
		# Kit plugins the project does not use stay out of the build.
		excludes.append_array(Deploy.unused_extension_excludes(data))
		var r := Deploy.apply_excludes(presets_path, str(preset.section), excludes)
		if not r.ok:
			deploy_status.text = "Cannot prepare the preset: %s" % r.message
			return
		note = "Leaving out %d unused asset file(s).\n" % excludes.size()
	var exe := Deploy.godot_executable()
	var args := Deploy.build_args(str(preset.name), abs_out)
	deploy_log.visible = true
	deploy_log.text = note + "%s %s\n" % [exe.get_file(), " ".join(args)]
	deploy_progress.visible = true
	deploy_build.disabled = true
	_build_started = Time.get_ticks_msec()
	_build_started_unix = int(Time.get_unix_time_from_system())
	_build_out = abs_out
	_build_thread = Thread.new()
	_build_thread.start(_run_export.bind(exe, args))
	set_process(true)


## Runs on the build thread. Returns [exit code, output].
func _run_export(exe: String, args: PackedStringArray) -> Array:
	var output := []
	var code := OS.execute(exe, args, output, true)
	return [code, "".join(PackedStringArray(output))]


func _process(_delta: float) -> void:
	if _build_thread == null:
		set_process(false)
		return
	if _build_thread.is_alive():
		deploy_status.text = "Building %s... %ds" % [_build_out.get_file(), (Time.get_ticks_msec() - _build_started) / 1000]
		return
	_finish_build()


func _finish_build() -> void:
	var res: Array = _build_thread.wait_to_finish()
	_build_thread = null
	set_process(false)
	Deploy.restore_presets(presets_path)
	deploy_progress.visible = false
	deploy_build.disabled = false
	var code: int = res[0] if res.size() > 0 else -1
	var out: String = res[1] if res.size() > 1 else ""
	deploy_log.text += Deploy.clean_log(out)
	deploy_log.scroll_vertical = deploy_log.get_line_count()
	var s := Deploy.summarize_output(code, out, _build_out, _build_started_unix)
	deploy_status.text = str(s.message)
	deploy_open.disabled = not s.ok
	if _close_after_build:
		queue_free()


func _close() -> void:
	if _build_thread != null:
		# Never leave a build half-done with the preset changed: close when it finishes.
		_close_after_build = true
		hide()
		return
	queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _build_thread != null:
			_build_thread.wait_to_finish()
			_build_thread = null
			Deploy.restore_presets(presets_path)
		_remove_sound_bus()


## Where a problem can be fixed: {map, event} for map files (event "" for map properties), or
## {map: "", event: record} for database, common event and project files (opened in Database).
static func problem_location(p: Dictionary) -> Dictionary:
	var file := str(p.get("file", ""))
	var record := str(p.get("record", ""))
	var re := RegEx.create_from_string("'([^']+)'")
	var m := re.search(record)
	var id := m.get_string(1) if m != null else record
	var fm := RegEx.create_from_string("maps/([a-z0-9_]+)\\.(events|map)\\.json$").search(file)
	if fm != null:
		return {"map": fm.get_string(1), "event": id if fm.get_string(2) == "events" else ""}
	return {"map": "", "event": id}
