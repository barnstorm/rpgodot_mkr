@tool
class_name RPGResourcePicker
extends HBoxContainer
## Picker for an asset by kind (charset, faceset, picture, music, sound, scene, backdrop...).
## Images open a grid with previews; audio opens a list with a play button; scenes list
## res://scenes. Asset lookup goes through RPGAssets when it exists (loaded by path, duck typed),
## otherwise through a plain scan of res://assets/<pack>/<Folder>/.
## Kind "iconset" lists the icon sheets (System images named like IconSet); kind "system" (window
## styles) leaves them out. `store_path` keeps
## the chosen file's res:// path instead of its name and adds "Other file…" (tileset sheets);
## `empty_hint` says where assets come from when there are none.

signal value_changed(value: Variant)

const ASSETS_SCRIPT := "res://addons/rpg/core/rpg_assets.gd"
const IMAGE_KINDS := ["charset", "faceset", "picture", "battler", "backdrop", "panorama", "title", "gameover", "system", "chipset", "iconset", "sv_battler"]
const ICONSET_HINT := "No icon sheets yet. Icons come from an icon sheet such as RPG Maker VX/MV's IconSet.png in a pack's System folder: add one with Tools > Resources > Import."
const AUDIO_KINDS := ["music", "sound"]
const FOLDERS := {
	"charset": "CharSet", "faceset": "FaceSet", "chipset": "ChipSet", "system": "System",
	"picture": "Picture", "music": "Music", "sound": "Sound", "battler": "Monster",
	"backdrop": "Backdrop", "panorama": "Panorama", "title": "Title", "gameover": "GameOver",
}

var kind := "picture"
## Value used for "(none)": null or "".
var none_value: Variant = ""
## Keep the chosen file's res:// path (not its asset name), and offer "Other file…".
var store_path := false
## Shown in the list when there is nothing to pick.
var empty_hint := ""
var _value: Variant = ""
var _button: Button
var _preview: TextureRect
var _play: Button
var _player: AudioStreamPlayer
var _popup: PopupPanel
var _search: LineEdit
var _list: ItemList
var _names: Array = []


func _init(p_kind := "picture", p_none: Variant = "") -> void:
	kind = p_kind
	none_value = p_none
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(24, 24)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.visible = IMAGE_KINDS.has(kind)
	add_child(_preview)
	_button = Button.new()
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.clip_text = true
	_button.pressed.connect(_open)
	add_child(_button)
	if AUDIO_KINDS.has(kind):
		_play = Button.new()
		_play.text = "▶"
		_play.tooltip_text = "Play"
		_play.pressed.connect(func(): play(str(_value)))
		add_child(_play)
	_refresh()


func set_value(v: Variant) -> void:
	_value = v
	_refresh()


func get_value() -> Variant:
	return _value


## Shows or hides the small whole-image thumbnail (a face picker shows the chosen cell instead).
func set_preview_visible(on: bool) -> void:
	_preview.visible = on and IMAGE_KINDS.has(kind)
	_refresh()


## The asset name inside a value: plain names, or {sheet, index} (message faces, images).
static func asset_name_of(v: Variant) -> String:
	if v is Dictionary:
		return str(v.get("sheet", v.get("file", "")))
	return str(v) if v != null else ""


# --- asset access (RPGAssets when available) ---------------------------------------------

static func _assets() -> Variant:
	if ResourceLoader.exists(ASSETS_SCRIPT):
		return load(ASSETS_SCRIPT)
	return null


## The asset kind a picker kind reads from ("iconset" sheets live with the System images).
static func asset_kind(p_kind: String) -> String:
	return "system" if p_kind == "iconset" else p_kind


static func list_names(p_kind: String) -> Array:
	if p_kind == "scene":
		var out: Array = []
		_scan_scenes("res://scenes", out)
		return out
	# Icon sheets sit with the System images but are not window skins: each picker lists its own.
	if p_kind == "iconset":
		return _list_all("system").filter(func(n): return is_icon_sheet(str(n)))
	if p_kind == "system":
		return _list_all("system").filter(func(n): return not is_icon_sheet(str(n)))
	return _list_all(p_kind)


## A System image that is an icon sheet (named like IconSet).
static func is_icon_sheet(asset_name: String) -> bool:
	return asset_name.to_lower().get_file().contains("icon")


static func _list_all(p_kind: String) -> Array:
	var a: Variant = _assets()
	if a != null and a.has_method("list"):
		return Array(a.list(p_kind))
	var names := []
	var folder: String = FOLDERS.get(p_kind, p_kind.capitalize())
	var root := DirAccess.open("res://assets")
	if root == null:
		return names
	for pack in root.get_directories():
		var d := DirAccess.open("res://assets/%s/%s" % [pack, folder])
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".import") or f.ends_with(".uid"):
				continue
			var n := f.get_basename()
			if not names.has(n):
				names.append(n)
	names.sort()
	return names


static func _scan_scenes(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.ends_with(".tscn") and not out.has(path.path_join(fn)):
			out.append(path.path_join(fn))
	for sub in d.get_directories():
		_scan_scenes(path.path_join(sub), out)


static func texture(p_kind: String, asset_name: String) -> Texture2D:
	if asset_name == "":
		return null
	var a: Variant = _assets()
	if a != null and a.has_method("load_texture"):
		return a.load_texture(asset_kind(p_kind), asset_name)
	return null


static func exists(p_kind: String, asset_name: String) -> bool:
	if p_kind == "scene":
		return ResourceLoader.exists(asset_name)
	if asset_name.begins_with("res://"):
		return ResourceLoader.exists(asset_name) or FileAccess.file_exists(asset_name)
	var a: Variant = _assets()
	if a != null and a.has_method("find"):
		return str(a.find(asset_kind(p_kind), asset_name)) != ""
	return list_names(p_kind).has(asset_name)


func play(asset_name: String) -> void:
	if asset_name == "":
		return
	var a: Variant = _assets()
	if a == null or not a.has_method("load_audio"):
		return
	var s: AudioStream = a.load_audio(kind, asset_name)
	if s == null:
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		add_child(_player)
	_player.stream = s
	_player.play()


func play_with(asset_name: String, volume: float, pitch: float) -> void:
	play(asset_name)
	if _player:
		_player.volume_db = linear_to_db(clampf(volume / 100.0, 0.001, 1.0))
		_player.pitch_scale = clampf(pitch / 100.0, 0.5, 1.5)


# --- UI -----------------------------------------------------------------------------------

func _refresh() -> void:
	var v := asset_name_of(_value)
	_button.text = "(none)" if v == "" else (v.get_file() if v.begins_with("res://") else v)
	_button.tooltip_text = v
	if _value is Dictionary and _value.has("index") and v != "":
		_button.text = "%s  #%s" % [v, str(_value.index)]
	if v != "" and Engine.is_editor_hint() and not exists(kind, v):
		_button.text = "⚠ %s (missing)" % v
	if _preview.visible:
		_preview.texture = texture(kind, v) if v != "" else null


func _open() -> void:
	if _popup == null:
		_popup = PopupPanel.new()
		var vb := VBoxContainer.new()
		_popup.add_child(vb)
		_search = LineEdit.new()
		_search.placeholder_text = "Search %s…" % kind
		_search.clear_button_enabled = true
		_search.text_changed.connect(func(_t): _fill())
		_search.text_submitted.connect(func(_t): choose_highlighted())
		_search.gui_input.connect(func(ev: InputEvent) -> void:
			# Down arrow moves from the search box into the list.
			if ev is InputEventKey and ev.pressed and ev.keycode == KEY_DOWN and _list.item_count > 0:
				_list.grab_focus()
				if _list.get_selected_items().is_empty():
					_list.select(mini(1, _list.item_count - 1))
				_search.accept_event())
		vb.add_child(_search)
		_list = ItemList.new()
		_list.custom_minimum_size = Vector2(460, 320)
		if IMAGE_KINDS.has(kind):
			_list.icon_mode = ItemList.ICON_MODE_TOP
			_list.max_columns = 0
			_list.fixed_icon_size = Vector2i(64, 64)
			_list.fixed_column_width = 96
			_list.same_column_width = true
		_list.item_activated.connect(_choose)
		_list.item_selected.connect(func(i):
			if AUDIO_KINDS.has(kind) and i < _names.size() and _names[i] != "":
				play(_names[i]))
		vb.add_child(_list)
		var hint := Label.new()
		hint.name = "EmptyHint"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 440
		hint.modulate = Color(1, 0.85, 0.5)
		hint.visible = false
		vb.add_child(hint)
		var row := HBoxContainer.new()
		vb.add_child(row)
		var ok := Button.new()
		ok.text = "Choose"
		ok.pressed.connect(func():
			var sel := _list.get_selected_items()
			if not sel.is_empty():
				_choose(sel[0]))
		row.add_child(ok)
		if store_path:
			var other := Button.new()
			other.text = "Other file…"
			other.tooltip_text = "Pick any image in the project (res://)"
			other.pressed.connect(_browse)
			row.add_child(other)
		add_child(_popup)
	_search.text = ""
	_fill()
	_popup.popup_centered(Vector2i(480, 400))
	_search.grab_focus()


func _fill() -> void:
	_list.clear()
	_names.clear()
	var q := _search.text.strip_edges().to_lower()
	_names.append("")
	_list.add_item("(none)")
	for n in list_names(kind):
		if q != "" and str(n).to_lower().find(q) == -1:
			continue
		_names.append(str(n))
		var tex: Texture2D = texture(kind, str(n)) if IMAGE_KINDS.has(kind) else null
		_list.add_item(str(n).get_file() if kind == "scene" else str(n), tex)
		if str(n) == asset_name_of(_value):
			_list.select(_list.item_count - 1)
	var hint: Label = _popup.find_child("EmptyHint", true, false) if _popup != null else null
	if hint != null:
		var text := empty_hint if empty_hint != "" else (ICONSET_HINT if kind == "iconset" else "")
		hint.text = text
		hint.visible = text != "" and _names.size() <= 1 and q == ""
	# While searching, the first match is highlighted so Enter takes it (an exact name wins).
	if q != "" and _names.size() > 1:
		var best := 1
		for i in range(1, _names.size()):
			if str(_names[i]).to_lower() == q or str(_names[i]).get_file().get_basename().to_lower() == q:
				best = i
				break
		var sel := _list.get_selected_items()
		if sel.is_empty() or sel[0] == 0:
			_list.select(best)
			_list.ensure_current_is_visible()


## Enter in the search box: chooses the highlighted entry, or the only match.
func choose_highlighted() -> void:
	if _list == null:
		return
	var sel := _list.get_selected_items()
	if not sel.is_empty():
		_choose(sel[0])
	elif _names.size() == 2:
		_choose(1)


## Opens the picker with `query` typed into its search (tests, hosts).
func open_with_search(query: String) -> void:
	_open()
	_search.text = query
	_fill()


func _choose(i: int) -> void:
	if i < 0 or i >= _names.size():
		return
	_popup.hide()
	_value = none_value if _names[i] == "" else _names[i]
	if store_path and _names[i] != "":
		var a: Variant = _assets()
		var p := str(a.find(asset_kind(kind), _names[i])) if a != null else ""
		if p != "":
			_value = p
	_refresh()
	value_changed.emit(_value)


## "Other file…": any PNG in the project, stored as its res:// path.
func _browse() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.filters = PackedStringArray(["*.png ; PNG images"])
	fd.title = "Pick an image"
	fd.file_selected.connect(func(path: String) -> void:
		if _popup != null:
			_popup.hide()
		_value = path
		_refresh()
		value_changed.emit(_value)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)
