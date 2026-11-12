@tool
class_name RPGImageMapDialog
extends ConfirmationDialog
## New image-backed map (map tree > New image-backed map...). Picks the base image, shows the map
## tile size and where it comes from, the image size and the map size in cells, or why the image
## cannot be used (RPGImageMap.check_size). Takes an optional foreground of the same size and the
## first state of the passability mask (all blocked or all walkable). Nothing is written until
## Create is pressed; then `create_requested` is emitted and the caller creates the map through
## RPGMapFiles.create_image_map.

signal create_requested(options: Dictionary)

const IMAGE_FILTERS := ["*.png ; PNG images", "*.webp ; WebP images", "*.jpg, *.jpeg ; JPEG images"]

var data: RPGProjectData
var parent_map := ""
var _f: Dictionary = {}
var _info: Label
var _error: Label
var _picker: FileDialog
var _picking := ""
## The last check of the base image (RPGImageMap.check_size), {} before one is picked.
var check: Dictionary = {}


static func open_for(parent: Node, p_data: RPGProjectData, on_create: Callable, p_parent_map := "") -> RPGImageMapDialog:
	var d := RPGImageMapDialog.new()
	d.data = p_data
	d.parent_map = p_parent_map
	d.create_requested.connect(on_create)
	parent.add_child(d)
	d.popup_centered(Vector2i(560, 0))
	return d


func _ready() -> void:
	title = "New image-backed map"
	ok_button_text = "Create"
	dialog_hide_on_ok = false
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	add_child(vb)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Build a map on one prepared image. Its size must be a whole number of map tiles; the map gets one cell per tile. You then paint where characters can walk (Passability mode, F4) and place events as usual."
	vb.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	vb.add_child(grid)
	var id_edit := LineEdit.new()
	id_edit.text = RPGIds.unique("image_map", data.maps)
	id_edit.tooltip_text = "The map's name in files and event commands: lowercase letters, digits and _ (e.g. harbour). It can't be changed later."
	id_edit.text_changed.connect(func(_t): refresh())
	_row(grid, "Map ID", id_edit)
	_f["id"] = id_edit
	var name_edit := LineEdit.new()
	name_edit.tooltip_text = "The map's name in the map tree (editor only)."
	_row(grid, "Name", name_edit)
	_f["name"] = name_edit
	var ts := OptionButton.new()
	ts.tooltip_text = "The tileset for tiles painted on top of the image. Its tile size is the map tile size; with (none) the project tile size is used and tile painting is off."
	for r in data.records("tilesets"):
		ts.add_item("%s (%s)" % [r.get("name", r.id), r.id])
		ts.set_item_metadata(ts.item_count - 1, str(r.id))
	ts.add_item("(none)")
	ts.set_item_metadata(ts.item_count - 1, "")
	ts.select(0)
	ts.item_selected.connect(func(_i): refresh())
	_row(grid, "Tileset", ts)
	_f["tileset"] = ts
	_f["base"] = _path_row(grid, "Base image", "The image drawn under everything on the map. Pick a PNG from the project.", "base")
	_f["foreground"] = _path_row(grid, "Foreground image (optional)", "A transparent image of the same size, drawn above the characters (wall tops, tree crowns, door frames).", "foreground")
	var state := OptionButton.new()
	state.tooltip_text = "Where characters can walk before you paint: nowhere (paint the floor) or everywhere (paint the walls)."
	state.add_item("All blocked (paint the floor)")
	state.add_item("All walkable (paint the walls)")
	_row(grid, "Start with", state)
	_f["state"] = state
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 500
	vb.add_child(_info)
	_error = Label.new()
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = 500
	_error.add_theme_color_override("font_color", Color(1, 0.55, 0.5))
	vb.add_child(_error)
	confirmed.connect(_on_ok)
	canceled.connect(queue_free)
	refresh()


func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


func _path_row(grid: GridContainer, label: String, tip: String, key: String) -> LineEdit:
	var hb := HBoxContainer.new()
	var le := LineEdit.new()
	le.placeholder_text = "res://assets/maps/room.png"
	le.tooltip_text = tip
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(_t): refresh())
	hb.add_child(le)
	var browse := Button.new()
	browse.text = "Browse..."
	browse.tooltip_text = "Pick the image from the project's files"
	browse.pressed.connect(func(): _browse(key))
	hb.add_child(browse)
	if key == "foreground":
		var clear := Button.new()
		clear.text = "Clear"
		clear.tooltip_text = "No foreground image"
		clear.pressed.connect(func():
			le.text = ""
			refresh())
		hb.add_child(clear)
	_row(grid, label, hb)
	return le


func _browse(key: String) -> void:
	if _picker == null:
		_picker = FileDialog.new()
		_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_picker.access = FileDialog.ACCESS_RESOURCES
		_picker.filters = PackedStringArray(IMAGE_FILTERS)
		_picker.file_selected.connect(func(path: String):
			_f[_picking].text = path
			refresh())
		add_child(_picker)
	_picking = key
	_picker.title = "Pick the %s image" % key
	_picker.popup_centered(Vector2i(720, 480))


## Sets the fields from code (tests, or a caller that already knows the images).
func set_values(values: Dictionary) -> void:
	for k in ["id", "name", "base", "foreground"]:
		if values.has(k):
			_f[k].text = str(values[k])
	if values.has("tileset"):
		var o: OptionButton = _f.tileset
		for i in o.item_count:
			if str(o.get_item_metadata(i)) == str(values.tileset):
				o.select(i)
	if values.has("walkable"):
		_f.state.select(1 if values.walkable else 0)
	refresh()


func tileset_id() -> String:
	var o: OptionButton = _f.tileset
	return str(o.get_item_metadata(o.selected)) if o.selected >= 0 else ""


## Re-checks every field; Create is enabled only when the map can be made. Returns the problem ("" = fine).
func refresh() -> String:
	if _f.is_empty():
		return ""
	var tile := RPGImageMap.tile_size_for_tileset(data, tileset_id())
	var lines := ["Map tile size: %d px (%s)." % [tile, RPGImageMap.tile_size_source(data, tileset_id())]]
	var problem := _id_problem(str(_f.id.text).strip_edges())
	var base := str(_f.base.text).strip_edges()
	check = {}
	if base == "":
		lines.append("Pick a base image.")
		if problem == "":
			problem = "No base image is selected."
	else:
		check = RPGImageMap.check_image(base, tile)
		if check.size != Vector2i.ZERO:
			lines.append("Image: %d×%d pixels." % [check.size.x, check.size.y])
		if check.ok:
			lines.append("Map size: %d×%d cells." % [check.cells.x, check.cells.y])
			if check.warning != "":
				lines.append("Warning: " + check.warning)
		elif problem == "":
			problem = check.error
	var fg := str(_f.foreground.text).strip_edges()
	if fg != "" and problem == "":
		var fr := RPGImageMap.read_size(fg)
		if not fr.ok:
			problem = "Foreground: " + str(fr.error)
		elif check.get("ok", false):
			var mm := RPGImageMap.foreground_mismatch(check.size, fr.size)
			if mm != "":
				problem = mm
	_info.text = "\n".join(PackedStringArray(lines))
	_error.text = problem
	get_ok_button().disabled = problem != ""
	return problem


func _id_problem(id: String) -> String:
	if id == "":
		return "Type a Map ID (lowercase letters, digits and _, e.g. harbour)."
	if not RPGIds.is_valid(id):
		return "'%s' can't be a Map ID: use lowercase letters, digits and _, starting with a letter." % id
	if data.maps.has(id):
		return "There is already a map with the ID '%s'." % id
	return ""


## What Create sends: {id, name, tileset, base, foreground, walkable, parent, cells}.
func values() -> Dictionary:
	return {
		"id": str(_f.id.text).strip_edges(), "name": str(_f.name.text).strip_edges(), "tileset": tileset_id(),
		"base": str(_f.base.text).strip_edges(), "foreground": str(_f.foreground.text).strip_edges(),
		"walkable": _f.state.selected == 1, "parent": parent_map, "cells": check.get("cells", Vector2i.ZERO),
	}


func _on_ok() -> void:
	if refresh() != "":
		return
	hide()
	create_requested.emit(values())
	queue_free()
