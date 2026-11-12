@tool
class_name RPGMapPropertiesDialog
extends ConfirmationDialog
## Map properties form: name, display name, tileset, size, scroll type, music and background sound,
## battle background, dashing, parallax, encounters, notes, and "Plugin fields": the map
## custom_fields ("maps") of enabled extensions and of the project, kept in the map's "custom".
## Opens on New map and from right-click > Properties. Shrinking warns first: what falls outside
## is deleted.
## Image-backed maps (RPGImageMap): New map offers "Tile map" or "Image-backed map". An image-backed
## map has a base image, an optional foreground image and (when new) a starting navigation; its
## width and height come from the base image and can't be typed. Images are checked as they are
## picked; the dialog stays open with the reason while they don't fit the tile grid.

signal saved(map_id: String, props: Dictionary, entry_name: String)

var data: RPGProjectData
var map_id := ""
var is_new := false
var props: Dictionary = {}
var _f: Dictionary = {}
var _enc_list: VBoxContainer
var _error: Label
## Plugin fields (custom_fields "maps"), or null when there are none.
var _custom_form: RPGFormBuilder = null
## The map is (or, when new, will be) image-backed.
var image_map := false
## Result of the last image check (RPGImageMap.check_images), {} before one.
var image_check: Dictionary = {}
var _image_rows: Array = []
var _image_info: Label


## `parent_map`: for a new map, the map it goes under; the new map starts with that map's
## tileset, size, music, background sound, battle background and encounters (as RPG Maker does).
static func open_for(parent: Node, p_data: RPGProjectData, id: String, new_map: bool, on_saved: Callable, parent_map := "", as_image_map := false) -> RPGMapPropertiesDialog:
	var d := RPGMapPropertiesDialog.new()
	d.data = p_data
	d.map_id = id
	d.is_new = new_map
	d.image_map = as_image_map if new_map else RPGImageMap.is_image_map(p_data.map_props(id))
	d.props = RPGMapFiles.default_props(id, "", _first_tileset(p_data), 20, 15) if new_map else p_data.map_props(id).duplicate(true)
	if new_map and parent_map != "" and p_data.maps.has(parent_map):
		var pp: Dictionary = p_data.map_props(parent_map)
		for k in ["tileset", "width", "height", "music", "bgs", "battle_background", "encounters", "scroll", "disable_dash"]:
			if pp.has(k):
				d.props[k] = RPGJson.deep_copy(pp[k])
	if d.image_map and new_map:
		d.props["image_map"] = RPGImageMap.new_block("", "", "blocked")
		d.props["tileset"] = ""
	d.saved.connect(on_saved)
	parent.add_child(d)
	d.popup_centered(Vector2i(560, 620))
	return d


static func _first_tileset(p_data: RPGProjectData) -> String:
	var recs: Array = p_data.records("tilesets")
	return str(recs[0].get("id", "")) if not recs.is_empty() else ""


func _ready() -> void:
	title = "New map" if is_new else "Map properties: %s" % map_id
	ok_button_text = "Create" if is_new else "Save"
	# A bad Map ID keeps the dialog open with the reason shown here (nothing typed is lost).
	dialog_hide_on_ok = false
	var outer := VBoxContainer.new()
	add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 520)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_error = Label.new()
	_error.add_theme_color_override("font_color", Color(1, 0.55, 0.5))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = 500
	outer.add_child(_error)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var entry: Dictionary = data.map_entry(map_id)
	if is_new:
		var kind := OptionButton.new()
		kind.add_item("Tile map")
		kind.add_item("Image-backed map")
		kind.select(1 if image_map else 0)
		kind.tooltip_text = "Tile map: paint the map from a tileset.\nImage-backed map: use one picture you drew elsewhere as the map, then paint where characters can walk."
		kind.item_selected.connect(func(i): _set_image_map(i == 1))
		_row(grid, "Map type", kind)
		_f["kind"] = kind
		_text(grid, "id", "Map ID", RPGIds.unique("new_map", data.maps))
		_f.id.tooltip_text = "The map's name in files and event commands: lowercase letters, digits and _ (e.g. town_inn). It can't be changed later."
		_f.id.text_changed.connect(func(_t): _error.text = _id_problem(_f.id.text.strip_edges()))
	else:
		var idl := Label.new()
		idl.text = map_id
		idl.tooltip_text = "The map's ID in files and event commands (fixed once the map exists)."
		idl.modulate = Color(1, 1, 1, 0.7)
		_row(grid, "Map ID", idl)
		_f["id"] = idl
	_text(grid, "name", "Name (editor only)", str(entry.get("name", "")))
	_text(grid, "display_name", "Display name", str(props.get("display_name", "")))
	var ts := OptionButton.new()
	# Image-backed maps need no tileset (tiles can still be added on top with one).
	ts.add_item("(none)")
	ts.set_item_metadata(0, "")
	for r in data.records("tilesets"):
		ts.add_item("%s (%s)" % [r.get("name", r.id), r.id])
		ts.set_item_metadata(ts.item_count - 1, r.id)
		if r.id == props.get("tileset", ""):
			ts.select(ts.item_count - 1)
	_row(grid, "Tileset", ts)
	_f["tileset"] = ts
	_spin(grid, "width", "Width (tiles)", int(props.get("width", 20)), 1, 500)
	_spin(grid, "height", "Height (tiles)", int(props.get("height", 15)), 1, 500)
	_build_image_rows(grid)
	_choice(grid, "scroll", "Scroll type", ["none", "loop_v", "loop_h", "loop_both"], ["No loop", "Loop vertically", "Loop horizontally", "Loop both ways"], str(props.get("scroll", "none")))
	# RPG Maker's "Auto-change BGM/BGS": keep what is playing, stop it, or play a file.
	var music: Variant = props.get("music")
	_choice(grid, "music", "Music", [KEEP, STOP] + RPGAssets.list("music"), ["(keep playing)", "(stop)"] + RPGAssets.list("music"), _sound_choice(music))
	var play := Button.new()
	play.text = "▶"
	play.tooltip_text = "Preview the music"
	play.pressed.connect(_preview_music)
	var stop := Button.new()
	stop.text = "■"
	stop.tooltip_text = "Stop the preview"
	stop.pressed.connect(func(): if _preview != null: _preview.stop())
	var mrow: OptionButton = _f.music
	var hb := HBoxContainer.new()
	mrow.get_parent().remove_child(mrow)
	mrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(mrow)
	hb.add_child(play)
	hb.add_child(stop)
	grid.add_child(hb)
	var bgs: Variant = props.get("bgs")
	_choice(grid, "bgs", "Background sound", [KEEP, STOP] + RPGAssets.list("sound"), ["(keep playing)", "(stop)"] + RPGAssets.list("sound"), _sound_choice(bgs))
	var bb: Variant = props.get("battle_background", "auto")
	_choice(grid, "battle_background", "Battle background", ["auto"] + RPGAssets.list("backdrop"), ["Automatic"] + RPGAssets.list("backdrop"), str(bb) if bb is String else str(bb.get("image", "auto")))
	_text(grid, "battle_scene", "Battle scene (blank = default)", str(props.get("battle_scene", "")))
	_f.battle_scene.placeholder_text = "res://scenes/my_battle.tscn"
	_f.battle_scene.tooltip_text = "A scene with start(args, context) that emits finished(result) or cancelled(reason)"
	var cb := CheckBox.new()
	cb.button_pressed = bool(props.get("disable_dash", false))
	_row(grid, "Disable dashing", cb)
	_f["disable_dash"] = cb
	var par: Variant = props.get("parallax")
	_choice(grid, "parallax", "Parallax background", [""] + RPGAssets.list("panorama"), ["(none)"] + RPGAssets.list("panorama"), str(par.get("image", "")) if par is Dictionary else "")
	var enc: Dictionary = props.get("encounters", {"steps": 30, "groups": []})
	_spin(grid, "enc_steps", "Encounter steps (average)", int(enc.get("steps", 30)), 1, 999)
	var lab := Label.new()
	lab.text = "Encounters"
	grid.add_child(lab)
	var box := VBoxContainer.new()
	grid.add_child(box)
	_enc_list = VBoxContainer.new()
	box.add_child(_enc_list)
	for g in enc.get("groups", []):
		_add_enc_row(g)
	var add := Button.new()
	add.text = "Add enemy group"
	add.pressed.connect(func(): _add_enc_row({"troop": "", "weight": 10, "regions": []}))
	box.add_child(add)
	var notes := TextEdit.new()
	notes.text = str(props.get("notes", ""))
	notes.custom_minimum_size = Vector2(300, 60)
	_row(grid, "Notes", notes)
	_f["notes"] = notes
	var custom := custom_fields(data)
	if not custom.is_empty():
		var head := Label.new()
		head.text = "Plugin fields"
		head.tooltip_text = "Fields that plugins (and the project's custom_fields \"maps\") add to maps."
		grid.add_child(head)
		_custom_form = RPGFormBuilder.new()
		_custom_form.name = "PluginFields"
		_custom_form.setup(custom, data, null, {"map_id": map_id})
		_custom_form.set_value(props.get("custom", {}) if props.get("custom") is Dictionary else {})
		_custom_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(_custom_form)
	confirmed.connect(_on_ok)
	canceled.connect(queue_free)
	_set_image_map(image_map)


# --- image-backed maps ---------------------------------------------------------------------------

func _build_image_rows(grid: GridContainer) -> void:
	var b := RPGImageMap.block(props)
	var base := RPGResourcePicker.new("map_image", "")
	base.store_path = true
	base.empty_hint = "No map images yet. Add PNGs with Tools > Resources > Import... (asset type \"Map image\"), or choose Other file…"
	base.set_value(RPGImageMap.base_path(props))
	base.tooltip_text = "The picture the map is drawn from. Its width and height must be whole numbers of %d px tiles." % data.tile_size()
	base.value_changed.connect(func(_v): _check_images())
	_image_row(grid, "Base image", base)
	_f["image_base"] = base
	var fg := RPGResourcePicker.new("map_image", "")
	fg.store_path = true
	fg.set_value(RPGImageMap.foreground_path(props))
	fg.tooltip_text = "Optional. A transparent picture the same size as the base image, drawn over the characters (wall tops, tree crowns, arches)."
	fg.value_changed.connect(func(_v): _check_images())
	_image_row(grid, "Foreground image (optional)", fg)
	_f["image_foreground"] = fg
	if is_new:
		var nav := OptionButton.new()
		nav.add_item("All blocked (paint the floor)")
		nav.add_item("All walkable (paint the walls)")
		nav.select(1 if str(b.get("new_cells", "blocked")) == "walkable" else 0)
		nav.tooltip_text = "How the navigation starts. All blocked suits rooms with a small floor; all walkable suits open fields. You then paint the rest in Navigation mode."
		_image_row(grid, "Navigation to start with", nav)
		_f["image_nav"] = nav
	_image_info = Label.new()
	_image_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_image_info.custom_minimum_size.x = 200
	_image_row(grid, "Size", _image_info)


func _image_row(grid: GridContainer, label: String, ctl: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)
	_image_rows.append(l)
	_image_rows.append(ctl)


func _set_image_map(on: bool) -> void:
	image_map = on
	for c in _image_rows:
		c.visible = on
	# The size of an image-backed map comes from its base image.
	_f.width.editable = not on
	_f.height.editable = not on
	var tip := ("Set by the base image (one cell per %d×%d px)." % [data.tile_size(), data.tile_size()]) if on else ""
	_f.width.tooltip_text = tip
	_f.height.tooltip_text = tip
	if on and is_new and str(_f.image_base.get_value()) == "":
		_select_tileset("")
	elif not on and is_new and str(_meta("tileset")) == "":
		_select_tileset(_first_tileset(data))
	_check_images()


func _select_tileset(id: String) -> void:
	var o: OptionButton = _f.tileset
	for i in o.item_count:
		if str(o.get_item_metadata(i)) == id:
			o.select(i)
			return


## Checks the chosen images and shows the resulting size (or what is wrong) under them.
func _check_images() -> void:
	image_check = {}
	if not image_map or _image_info == null:
		return
	var base := str(_f.image_base.get_value())
	var fg := str(_f.image_foreground.get_value())
	var tile := data.tile_size()
	if base == "":
		_image_info.text = "Tile size: %d px. Choose a base image." % tile
		_image_info.remove_theme_color_override("font_color")
		return
	image_check = RPGImageMap.check_images(base, fg, tile, RPGImageMap.limits(data))
	if image_check.ok:
		var c: Vector2i = image_check.cells
		var px: Vector2i = image_check.pixels
		var text := "Tile size: %d px. The image is %d×%d px, so the map is %d×%d cells." % [tile, px.x, px.y, c.x, c.y]
		var old := Vector2i(int(props.get("width", c.x)), int(props.get("height", c.y)))
		if not is_new and c != old:
			text += "\nThe map is now %d×%d cells: saving asks you to review the size change first." % [old.x, old.y]
		for w in image_check.warnings:
			text += "\n⚠ " + str(w)
		_image_info.text = text
		_image_info.add_theme_color_override("font_color", Color(1, 0.85, 0.45) if not image_check.warnings.is_empty() else Color(0.6, 0.95, 0.65))
		_f.width.value = c.x
		_f.height.value = c.y
	else:
		_image_info.text = "Tile size: %d px.\n%s" % [tile, "\n".join(PackedStringArray(image_check.errors))]
		_image_info.add_theme_color_override("font_color", Color(1, 0.55, 0.5))


## Why the chosen images can't be used, or "".
func _image_problem() -> String:
	if not image_map:
		return ""
	if str(_f.image_base.get_value()) == "":
		return "Choose a base image for the image-backed map."
	if image_check.is_empty():
		_check_images()
	if not image_check.get("ok", false):
		return "The images don't fit the tile grid; see Size above. Nothing has been written."
	return ""


## Map fields the project's enabled extensions declare (manifest custom_fields "maps") plus the
## project's own custom_fields "maps".
static func custom_fields(p_data: RPGProjectData) -> Array:
	var pf: Dictionary = p_data.project.get("custom_fields", {}) if p_data.project.get("custom_fields") is Dictionary else {}
	var reg := RPGCommandRegistry.new()
	reg.load_all(p_data.project.get("extensions", []), p_data.project.get("disabled_extensions", []), str(p_data.project.get("extensions_root", "res://extensions")))
	var list: Variant = reg.merged_custom_fields(pf).get("maps", [])
	return list if list is Array else []


func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


func _text(grid: GridContainer, key: String, label: String, value: String, read_only := false) -> void:
	var le := LineEdit.new()
	le.text = value
	le.editable = not read_only
	_row(grid, label, le)
	_f[key] = le


func _spin(grid: GridContainer, key: String, label: String, value: int, lo: int, hi: int) -> void:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	_row(grid, label, s)
	_f[key] = s


const KEEP := "<keep>"
const STOP := "<stop>"
var _preview: AudioStreamPlayer


static func _sound_choice(v: Variant) -> String:
	if not (v is Dictionary):
		return KEEP
	var f := str(v.get("file", ""))
	return STOP if f == "" else f


static func _sound_value(choice: String) -> Variant:
	if choice == KEEP or choice == "":
		return null
	if choice == STOP:
		return {"file": ""}
	return {"file": choice, "volume": 100, "pitch": 100, "pan": 0}


func _preview_music() -> void:
	var f := str(_meta("music"))
	if f == KEEP or f == STOP:
		return
	var path := RPGAssets.find("music", f)
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if _preview == null:
		_preview = AudioStreamPlayer.new()
		add_child(_preview)
	_preview.stream = stream
	_preview.play()


func _choice(grid: GridContainer, key: String, label: String, values: Array, labels: Array, current: String) -> void:
	var o := OptionButton.new()
	for i in values.size():
		o.add_item(str(labels[i]))
		o.set_item_metadata(i, values[i])
		if str(values[i]) == current:
			o.select(i)
	_row(grid, label, o)
	_f[key] = o


func _add_enc_row(g: Dictionary) -> void:
	var row := HBoxContainer.new()
	var troop := OptionButton.new()
	for r in data.records("troops"):
		troop.add_item(str(r.get("name", r.id)))
		troop.set_item_metadata(troop.item_count - 1, r.id)
		if r.id == g.get("troop", ""):
			troop.select(troop.item_count - 1)
	row.add_child(troop)
	var w := SpinBox.new()
	w.min_value = 1
	w.max_value = 100
	w.value = int(g.get("weight", 10))
	w.prefix = "Weight"
	w.tooltip_text = "How often this group appears compared with the others (RPG Maker's Weight)"
	row.add_child(w)
	var regions := LineEdit.new()
	regions.placeholder_text = "Regions: e.g. 1, 2 (blank: whole map)"
	regions.tooltip_text = "Region numbers where this group appears; leave blank for the whole map"
	regions.custom_minimum_size.x = 200
	regions.text = ", ".join(PackedStringArray(g.get("regions", []).map(func(x): return str(x))))
	regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(regions)
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(row.queue_free)
	row.add_child(del)
	_enc_list.add_child(row)


func _meta(key: String) -> Variant:
	var o: OptionButton = _f[key]
	return o.get_item_metadata(o.selected) if o.selected >= 0 else null


## Why `id` can't be a new map's ID, or "" when it can.
func _id_problem(id: String) -> String:
	if not is_new:
		return ""
	if id == "":
		return "Type a Map ID (lowercase letters, digits and _, e.g. town_inn)."
	if not RPGIds.is_valid(id):
		return "'%s' can't be a Map ID: use lowercase letters, digits and _, starting with a letter (e.g. %s)." % [id, RPGIds.slug(id) if RPGIds.is_valid(RPGIds.slug(id)) else "town_inn"]
	if data.maps.has(id):
		return "There is already a map with the ID '%s'." % id
	return ""


func _on_ok() -> void:
	var id: String = _f.id.text.strip_edges()
	var problem := _id_problem(id)
	if problem != "":
		_error.text = problem
		_f.id.grab_focus()
		return
	var img_problem := _image_problem()
	if img_problem != "":
		_error.text = img_problem
		return
	hide()
	var out := props.duplicate(true)
	out["id"] = id
	out["display_name"] = _f.display_name.text
	out["tileset"] = str(_meta("tileset")) if _meta("tileset") != null else ""
	out["width"] = int(_f.width.value)
	out["height"] = int(_f.height.value)
	out["scroll"] = str(_meta("scroll"))
	out["music"] = _sound_value(str(_meta("music")))
	out["bgs"] = _sound_value(str(_meta("bgs")))
	out["battle_background"] = str(_meta("battle_background"))
	var bs: String = _f.battle_scene.text.strip_edges()
	if bs != "":
		out["battle_scene"] = bs
	else:
		out.erase("battle_scene")
	out["disable_dash"] = _f.disable_dash.button_pressed
	var p := str(_meta("parallax"))
	out["parallax"] = {"image": p, "loop": true, "scroll_x": 0.5, "scroll_y": 0.5, "preview": true} if p != "" else null
	var groups := []
	for row in _enc_list.get_children():
		if row.is_queued_for_deletion():
			continue
		var troop: OptionButton = row.get_child(0)
		if troop.selected < 0:
			continue
		var regions := []
		for s in str(row.get_child(2).text).split(",", false):
			if s.strip_edges().is_valid_int():
				regions.append(s.strip_edges().to_int())
		groups.append({"troop": troop.get_item_metadata(troop.selected), "weight": int(row.get_child(1).value), "regions": regions})
	out["encounters"] = {"steps": int(_f.enc_steps.value), "groups": groups}
	out["notes"] = _f.notes.text
	if _custom_form != null:
		out["custom"] = _custom_form.get_value()
	if image_map:
		var old_block := RPGImageMap.block(props)
		var new_cells := str(old_block.get("new_cells", "blocked"))
		if _f.has("image_nav"):
			new_cells = "walkable" if _f.image_nav.selected == 1 else "blocked"
		out["image_map"] = RPGImageMap.new_block(str(_f.image_base.get_value()), str(_f.image_foreground.get_value()), new_cells)
		var c: Vector2i = image_check.get("cells", Vector2i(out.width, out.height))
		out["width"] = c.x
		out["height"] = c.y
	else:
		out.erase("image_map")
	saved.emit(id, out, _f.name.text)
	queue_free()
