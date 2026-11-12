@tool
class_name RPGMainScreen
extends VBoxContainer
## The "RPG" main tab: RPG Maker's main window inside Godot.
##   Toolbar (top): mode, drawing tools, layer, zoom, overlays, Database, Playtest
##   Tile palette (left, upper) and map tree (left, lower)
##   Map view (centre), event list (right, Event mode)
##   Status bar (bottom): map name and size, tile under the cursor (position, region, terrain tag)

const EVENT_EDITOR := "res://addons/rpg/editor/event_editor/rpg_event_editor.gd"
const QUICK_DIALOG := "res://addons/rpg/editor/event_editor/rpg_quick_event_dialog.gd"
const QUICK_EVENTS := "res://addons/rpg/core/rpg_quick_events.gd"
const PLAYTEST_FILE := "user://rpg_playtest.json"
const RPGMakerView := preload("res://addons/rpg/editor/rpg_maker_view.gd")
const PopupPlace := preload("res://addons/rpg/editor/rpg_popup_place.gd")
const GAME_SCENE := "res://addons/rpg/runtime/game.tscn"
const TOOL_TABS := ["Event search", "Sound test", "Resources", "Extensions", "Deploy"]

var plugin: EditorPlugin
var data: RPGProjectData
var registry: RPGCommandRegistry
var undo: RPGUndo

var toolbar: HBoxContainer
var palette: RPGTilePalette
var tree: RPGMapTree
var view: RPGMapView
var event_list: ItemList
var right_panel: VBoxContainer
var status: Label
var mode_buttons: Dictionary = {}
var tool_buttons: Dictionary = {}
var layer_option: OptionButton
var current_map := ""
var clipboard_event: Dictionary = {}
var clipboard_map := ""
var _local_undo: UndoRedo


func _init() -> void:
	name = "RPG"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(p_plugin: EditorPlugin) -> void:
	plugin = p_plugin
	if plugin != null:
		undo = RPGUndo.new(plugin.get_undo_redo())
	else:
		_local_undo = UndoRedo.new()
		undo = RPGUndo.new(_local_undo)


func _ready() -> void:
	if undo == null:
		setup(plugin)
	_build_ui()
	reload_project()


func _exit_tree() -> void:
	if view and view.dirty:
		view.save()


# --- layout --------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_build_menubar()
	toolbar = HBoxContainer.new()
	add_child(toolbar)
	_button("", "Save the map (Ctrl+S)", save_current, ["Save"])
	_button("", "Undo (Ctrl+Z)", func(): history_step(true), ["UndoRedo", "Undo"])
	_button("", "Redo (Ctrl+Y)", func(): history_step(false), ["Redo"])
	toolbar.add_child(VSeparator.new())
	_mode_button("Map", "map", "Map mode: paint tiles (F5)", ["TileMapLayer", "TileMap"])
	_mode_button("Event", "event", "Event mode: place and edit events (F6)", ["CharacterBody2D", "Node2D"])
	_mode_button("Region", "region", "Region mode: paint region numbers (F7)", ["NavigationRegion2D", "Rectangle"])
	_mode_button("Navigation", "nav", NAV_TIP_OFF, ["NavigationPolygon", "NavigationRegion2D"])
	toolbar.add_child(VSeparator.new())
	for t in [["Pencil", "pencil", ["Edit"]], ["Rect", "rect", ["Rectangle", "RectangleShape2D"]], ["Ellipse", "ellipse", ["CircleShape2D"]], ["Fill", "fill", ["Bucket"]], ["Shadow", "shadow", ["LightOccluder2D", "GradientTexture2D"]]]:
		_tool_button(t[0], t[1], t[2])
	toolbar.add_child(VSeparator.new())
	layer_option = OptionButton.new()
	for l in ["Auto layer", "Layer 1", "Layer 2", "Layer 3", "Layer 4"]:
		layer_option.add_item(l)
	layer_option.tooltip_text = "Auto picks the layer from the tile type; Layer N edits one layer and dims the rest"
	layer_option.item_selected.connect(set_layer_mode)
	toolbar.add_child(layer_option)
	toolbar.add_child(VSeparator.new())
	_button("", "Zoom out (Ctrl+−)", func(): view.set_zoom(view.zoom / 1.25), ["ZoomLess"], "−")
	_button("", "Actual size: as big as in the game (Ctrl+0)", func(): view.set_zoom(view.game_zoom()), ["ZoomReset"], "1:1")
	_button("", "Zoom in (Ctrl+=)", func(): view.set_zoom(view.zoom * 1.25), ["ZoomMore"], "+")
	toolbar.add_child(VSeparator.new())
	var ov := MenuButton.new()
	ov.text = "Overlays"
	ov.icon = _icon(["Grid", "GuiVisibilityVisible"])
	ov.tooltip_text = "Show the grid, passability, regions and terrain tags (not in RPG Maker)"
	_overlay_menu = ov.get_popup()
	_overlay_menu.hide_on_checkable_item_selection = false
	_overlay_menu.add_check_item("Grid", 0)
	_overlay_menu.add_check_item("Passability", 1)
	_overlay_menu.add_check_item("Regions", 2)
	_overlay_menu.add_check_item("Terrain tags", 3)
	_overlay_menu.add_check_item("Navigation (image-backed maps)", 4)
	_overlay_menu.id_pressed.connect(toggle_overlay)
	toolbar.add_child(ov)
	foreground_option = OptionButton.new()
	for t in ["Foreground: show", "Foreground: dim", "Foreground: hide"]:
		foreground_option.add_item(t)
	foreground_option.tooltip_text = "How the foreground image looks while you edit (wall tops, tree crowns). The game always draws it in full. Events stay visible and clickable either way."
	foreground_option.focus_mode = Control.FOCUS_ALL
	foreground_option.item_selected.connect(func(i): view.set_foreground_view(["show", "dim", "hide"][i]))
	foreground_option.visible = false
	toolbar.add_child(foreground_option)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_button("Tiles", "Tile settings: passability and flags for this map's tileset", open_tile_settings, ["TileSet"])
	_button("", "Database (F8)", open_database, ["Object", "ResourcePreloader"], "Database")
	_button("", "Event search, sound test, resources, extensions, deploy", func(): open_tools("Event search"), ["Tools"], "Tools")
	var pt := _button("Playtest", "Run the game from the title screen (F9)", func(): playtest({}), ["Play"])
	pt.flat = false
	_button("From here", "Playtest from a tile: click this, then click the tile to start on", playtest_from_picked_tile, ["PlayStart", "PlayScene"])

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	split.add_child(left)
	palette = RPGTilePalette.new()
	palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette.brush_changed.connect(_on_brush)
	left.add_child(palette)
	tree = RPGMapTree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.map_selected.connect(open_map)
	tree.map_action.connect(_on_map_action)
	tree.reorder_requested.connect(_on_reorder)
	left.add_child(tree)
	var center := HSplitContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	view = RPGMapView.new()
	view.undo = undo
	view.cell_hovered.connect(_on_hover)
	view.event_activated.connect(edit_event)
	view.event_context.connect(_on_event_context)
	view.map_context.connect(_on_map_context)
	view.new_event_requested.connect(new_event)
	view.selection_changed.connect(_on_view_selection)
	view.brush_picked.connect(func(b): palette.set_brush_external(b); view.brush = b)
	view.modified.connect(_update_status)
	view.events_modified.connect(_refresh_event_list)
	view.events_modified.connect(remember_disk)
	center.add_child(view)
	right_panel = VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(180, 0)
	right_panel.visible = false
	var el := Label.new()
	el.text = "Events on this map"
	right_panel.add_child(el)
	event_list = ItemList.new()
	event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_list.item_selected.connect(func(i): view.select_event(str(event_list.get_item_metadata(i))))
	event_list.item_activated.connect(func(i): edit_event(str(event_list.get_item_metadata(i))))
	right_panel.add_child(event_list)
	center.add_child(right_panel)
	status = Label.new()
	status.text = "No map open"
	add_child(status)
	_select_mode("map")
	_select_tool("pencil")


## A toolbar button. `icons` are Godot editor icon names tried in order; without an icon (or
## outside the editor) the button shows `fallback` (or `text`).
func _button(text: String, tip: String, cb: Callable, icons: Array = [], fallback := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	var ic := _icon(icons)
	if ic != null:
		b.icon = ic
	elif text == "":
		b.text = fallback if fallback != "" else tip.get_slice(" ", 0)
	b.pressed.connect(cb)
	toolbar.add_child(b)
	return b


func _icon(names: Array) -> Texture2D:
	if plugin == null or names.is_empty():
		return null
	var th := EditorInterface.get_editor_theme()
	for n in names:
		if th.has_icon(n, "EditorIcons"):
			return th.get_icon(n, "EditorIcons")
	return null


func _mode_button(text: String, m: String, tip: String, icons: Array = []) -> void:
	var b := _button(text, tip, func(): _select_mode(m), icons)
	b.toggle_mode = true
	mode_buttons[m] = b


func _tool_button(text: String, t: String, icons: Array = []) -> void:
	var tip: String = {"pencil": "Pencil", "rect": "Rectangle", "ellipse": "Ellipse", "fill": "Flood fill", "shadow": "Shadow pen: click a quarter tile; Shift-drag for a rectangle"}[t]
	var b := _button("", tip, func(): _select_tool(t), icons, text)
	b.toggle_mode = true
	tool_buttons[t] = b


# --- RPG Maker style menu bar ------------------------------------------------------------------------

var menubar: MenuBar
var _overlay_menu: PopupMenu
var _menus: Dictionary = {}

const M_NEW_PROJECT := 1
const M_SAVE := 2
const M_RELOAD := 3
const M_OPEN_FOLDER := 4
const M_DEPLOY := 5
const M_MAKER_VIEW := 6
const M_UNDO := 10
const M_REDO := 11
const M_CUT := 12
const M_COPY := 13
const M_PASTE := 14
const M_DELETE := 15
const M_MODE := 20        # + 0 map, 1 event, 2 region, 3 navigation
const M_DRAW := 30        # + index in DRAW_TOOLS
const M_LAYER := 40       # + 0 auto, 1..4
const M_ZOOM_IN := 50
const M_ZOOM_OUT := 51
const M_ZOOM_1 := 52
const M_ZOOM_2 := 53
const M_DATABASE := 60
const M_TILES := 61
const M_TOOLS := 70       # + index in TOOL_TABS
const M_PLAY := 80
const M_PLAY_HERE := 81
const M_BATTLE_TEST := 82
const M_GUIDE := 90
const M_README := 91
const M_SPEC := 92
const M_TUTORIALS := 93
const M_TUTORIALS_WEB := 94
const DRAW_TOOLS := ["pencil", "rect", "ellipse", "fill", "shadow"]
const MODES := ["map", "event", "region", "nav"]
const NAV_TIP_ON := "Navigation mode: paint where characters can walk on this image-backed map (Shift+F7)"
const NAV_TIP_OFF := "Navigation mode is for image-backed maps (Shift+F7). Tile maps take passability from their tiles: see Tiles."
var foreground_option: OptionButton


func _build_menubar() -> void:
	menubar = MenuBar.new()
	menubar.flat = true
	# Accelerators are shown in the menus, but keys are handled once, in _shortcut_input (and by
	# Godot for Ctrl+Z / Ctrl+Y), not a second time by the menu bar.
	menubar.set_process_shortcut_input(false)
	add_child(menubar)
	var project := _menu("Project")
	project.add_item("New project...", M_NEW_PROJECT)
	project.add_separator()
	project.add_item("Save map", M_SAVE, KEY_MASK_CTRL | KEY_S)
	project.add_item("Reload from disk", M_RELOAD)
	project.add_item("Open the rpg/ folder", M_OPEN_FOLDER)
	project.add_separator()
	project.add_item("Deploy...", M_DEPLOY)
	project.add_separator()
	project.add_check_item("Maker view (hide Godot's docks on the RPG and Database tabs)", M_MAKER_VIEW)
	var edit := _menu("Edit")
	edit.add_item("Undo", M_UNDO, KEY_MASK_CTRL | KEY_Z)
	edit.add_item("Redo", M_REDO, KEY_MASK_CTRL | KEY_Y)
	edit.add_separator()
	edit.add_item("Cut event", M_CUT, KEY_MASK_CTRL | KEY_X)
	edit.add_item("Copy event", M_COPY, KEY_MASK_CTRL | KEY_C)
	edit.add_item("Paste event", M_PASTE, KEY_MASK_CTRL | KEY_V)
	edit.add_item("Delete event", M_DELETE, KEY_DELETE)
	var mode := _menu("Mode")
	mode.add_radio_check_item("Map", M_MODE + 0, KEY_F5)
	mode.add_radio_check_item("Event", M_MODE + 1, KEY_F6)
	mode.add_radio_check_item("Region", M_MODE + 2, KEY_F7)
	mode.add_radio_check_item("Navigation (image-backed maps)", M_MODE + 3, KEY_MASK_SHIFT | KEY_F7)
	var draw := _menu("Draw")
	for i in DRAW_TOOLS.size():
		draw.add_radio_check_item(["Pencil", "Rectangle", "Ellipse", "Fill", "Shadow pen"][i], M_DRAW + i)
	var layer := _menu("Layer")
	for i in 5:
		layer.add_radio_check_item("Auto" if i == 0 else "Layer %d" % i, M_LAYER + i)
	var scale := _menu("Scale")
	scale.add_item("Zoom in", M_ZOOM_IN, KEY_MASK_CTRL | KEY_EQUAL)
	scale.add_item("Zoom out", M_ZOOM_OUT, KEY_MASK_CTRL | KEY_MINUS)
	scale.add_item("Actual size", M_ZOOM_1, KEY_MASK_CTRL | KEY_0)
	scale.add_item("2x", M_ZOOM_2)
	var tools := _menu("Tools")
	tools.add_item("Database", M_DATABASE, KEY_F8)
	tools.add_item("Tile settings...", M_TILES)
	tools.add_separator()
	for i in TOOL_TABS.size():
		tools.add_item(TOOL_TABS[i] + "...", M_TOOLS + i)
	var game := _menu("Game")
	game.add_item("Playtest", M_PLAY, KEY_F9)
	game.add_item("Playtest from the selected tile", M_PLAY_HERE)
	game.add_item("Battle test...", M_BATTLE_TEST)
	var help := _menu("Help")
	help.add_item("Maker guide (your first game in 15 minutes)", M_GUIDE)
	help.add_item("Following the RPG Maker tutorials in RPG Kit", M_TUTORIALS)
	help.add_item("RPG Maker tutorials (rpgmakerweb.com)", M_TUTORIALS_WEB)
	# Docs that only exist in the kit's own repository are left out when the addon was copied alone.
	if FileAccess.file_exists(HELP_DOCS[M_README]):
		help.add_item("RPG Kit README", M_README)
	if FileAccess.file_exists(HELP_DOCS[M_SPEC]):
		help.add_item("Design spec", M_SPEC)
	_sync_menus()


const HELP_DOCS := {
	M_GUIDE: "res://addons/rpg/docs/MAKER_GUIDE.md",
	M_TUTORIALS: "res://addons/rpg/docs/RPG_MAKER_TUTORIALS.md",
	M_README: "res://README.md",
	M_SPEC: "res://Godot as RPG Maker Design Spec.md",
}


## Opens a Markdown doc. Godot can't show Markdown, so it opens in the system's app for .md
## files; the status bar says so (and says where it is, if nothing opens).
func open_doc(path: String) -> void:
	if not FileAccess.file_exists(path):
		status.text = "%s is not in this project." % path
		return
	var err := OS.shell_open(ProjectSettings.globalize_path(path))
	if err == OK:
		status.text = "Opened %s in your system's viewer for .md files." % path.get_file()
	else:
		status.text = "Couldn't open %s (no app for .md files?). It is at %s" % [path.get_file(), ProjectSettings.globalize_path(path)]


func _menu(title: String) -> PopupMenu:
	var pm := PopupMenu.new()
	pm.name = title
	pm.id_pressed.connect(menu_action)
	pm.about_to_popup.connect(_sync_menus)
	menubar.add_child(pm)
	_menus[title] = pm
	return pm


## Ticks the radio items to match the current mode, tool, layer and settings.
func _sync_menus() -> void:
	if _menus.is_empty() or view == null:
		return
	var mode: PopupMenu = _menus.Mode
	for i in MODES.size():
		mode.set_item_checked(mode.get_item_index(M_MODE + i), view.mode == MODES[i])
	var draw: PopupMenu = _menus.Draw
	for i in DRAW_TOOLS.size():
		draw.set_item_checked(draw.get_item_index(M_DRAW + i), view.tool == DRAW_TOOLS[i])
	var layer: PopupMenu = _menus.Layer
	for i in 5:
		layer.set_item_checked(layer.get_item_index(M_LAYER + i), view.layer_mode == i)
	var project: PopupMenu = _menus.Project
	project.set_item_checked(project.get_item_index(M_MAKER_VIEW), RPGMakerView.enabled())
	var edit: PopupMenu = _menus.Edit
	var has_sel := view.mode == "event" and view.selected_event != ""
	for id in [M_CUT, M_COPY, M_DELETE]:
		edit.set_item_disabled(edit.get_item_index(id), not has_sel)
	edit.set_item_disabled(edit.get_item_index(M_PASTE), clipboard_event.is_empty() or view.mode != "event")


func menu_action(id: int) -> void:
	if id >= M_MODE and id < M_MODE + MODES.size():
		_select_mode(MODES[id - M_MODE])
	elif id >= M_DRAW and id < M_DRAW + DRAW_TOOLS.size():
		_select_tool(DRAW_TOOLS[id - M_DRAW])
	elif id >= M_LAYER and id < M_LAYER + 5:
		set_layer_mode(id - M_LAYER)
	elif id >= M_TOOLS and id < M_TOOLS + TOOL_TABS.size():
		open_tools(TOOL_TABS[id - M_TOOLS])
	else:
		_menu_command(id)
	_sync_menus()


func _menu_command(id: int) -> void:
	match id:
		M_NEW_PROJECT:
			if data != null and FileAccess.file_exists(data.root.path_join("project.json")):
				status.text = "This Godot project already has an RPG project in %s. Make a new Godot project and enable RPG Kit there to start another." % data.root
			else:
				_show_welcome(true)
		M_SAVE: save_current()
		M_RELOAD: _reload_from_disk("Reloaded from disk.")
		M_OPEN_FOLDER: OS.shell_open(ProjectSettings.globalize_path(data.root))
		M_DEPLOY: open_tools("Deploy")
		M_MAKER_VIEW:
			if plugin != null:
				RPGMakerView.shared().set_enabled(not RPGMakerView.enabled())
		M_UNDO: history_step(true)
		M_REDO: history_step(false)
		M_CUT: edit_command("cut")
		M_COPY: edit_command("copy")
		M_PASTE: edit_command("paste")
		M_DELETE: edit_command("delete")
		M_ZOOM_IN: view.set_zoom(view.zoom * 1.25)
		M_ZOOM_OUT: view.set_zoom(view.zoom / 1.25)
		M_ZOOM_1: view.set_zoom(view.game_zoom())
		M_ZOOM_2: view.set_zoom(2.0)
		M_DATABASE: open_database()
		M_TILES: open_tile_settings()
		M_PLAY: playtest({})
		M_PLAY_HERE: playtest_from_picked_tile()
		M_BATTLE_TEST: _battle_test_dialog()
		M_GUIDE, M_README, M_SPEC, M_TUTORIALS: open_doc(HELP_DOCS[id])
		M_TUTORIALS_WEB:
			OS.shell_open("https://www.rpgmakerweb.com/tutorials")
			status.text = "Opened rpgmakerweb.com's tutorials in your web browser."


func set_layer_mode(i: int) -> void:
	view.set_layer_mode(i)
	if layer_option != null and layer_option.selected != i:
		layer_option.select(i)


func toggle_overlay(id: int) -> void:
	var idx := _overlay_menu.get_item_index(id)
	_overlay_menu.set_item_checked(idx, not _overlay_menu.is_item_checked(idx))
	var on := _overlay_menu.is_item_checked(idx)
	match id:
		0: view.show_grid = on
		1: view.show_passability = on
		2:
			view.show_regions = on
			view.set_mode(view.mode)
		3: view.show_terrain = on
		4: view.show_navigation = on
	view.overlay.queue_redraw()


func open_database() -> void:
	if plugin != null:
		EditorInterface.set_main_screen_editor("Database")


## Undo / redo in the history the map view's actions go to (Godot's editor history, or the local
## one when running outside the editor).
func history_step(back: bool) -> void:
	var ur: UndoRedo = _local_undo
	if plugin != null:
		var m := EditorInterface.get_editor_undo_redo()
		ur = m.get_history_undo_redo(m.get_object_history_id(view))
	if ur == null:
		return
	if back:
		ur.undo()
	else:
		ur.redo()
	view.overlay.queue_redraw()


## Edit menu: cut / copy / paste / delete the selected event (Event mode).
func edit_command(what: String) -> void:
	if view.mode != "event":
		status.text = "Switch to Event mode (F6) to cut, copy or paste events."
		return
	var sel := view.selected_event
	match what:
		"copy", "cut":
			if sel == "":
				return
			clipboard_event = view.find_event(sel).duplicate(true)
			if what == "cut":
				view.delete_event(sel)
			status.text = "%s event '%s'." % ["Cut" if what == "cut" else "Copied", sel]
		"delete":
			if sel != "":
				view.delete_event(sel)
		"paste":
			if clipboard_event.is_empty():
				status.text = "Nothing to paste: copy an event first (Ctrl+C)."
				return
			var c: Vector2i = view.hover_cell
			if not view.in_map(c) or not view.event_at(c).is_empty():
				c = _first_free_cell(current_map)
			var id := view.paste_event(clipboard_event, c)
			if id != "":
				view.select_event(id)


func _battle_test_dialog() -> void:
	var troops: Array = data.records("troops")
	if troops.is_empty():
		status.text = "There are no enemy groups yet. Add one in Database > Enemy groups."
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Battle test"
	dlg.ok_button_text = "Fight"
	var vb := VBoxContainer.new()
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(360, 160)
	for t in troops:
		list.add_item("%s — %s" % [t.get("id", ""), t.get("name", "")])
	list.select(0)
	vb.add_child(list)
	# RPG Maker's battle test setup: who fights, at which level.
	var hdr := Label.new()
	hdr.text = "Party (blank = the starting party)"
	vb.add_child(hdr)
	var actors: Array = data.records("actors")
	var start_party: Array = data.system.get("starting_party", [])
	var rows := []
	for i in 4:
		var hb := HBoxContainer.new()
		var who := OptionButton.new()
		who.add_item("(none)")
		who.set_item_metadata(0, "")
		for a in actors:
			who.add_item("%s (%s)" % [a.get("name", a.id), a.id])
			who.set_item_metadata(who.item_count - 1, str(a.id))
			if i < start_party.size() and str(start_party[i]) == str(a.id):
				who.select(who.item_count - 1)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lv := SpinBox.new()
		lv.min_value = 1
		lv.max_value = 99
		lv.prefix = "Lv"
		if i < start_party.size():
			lv.value = int(data.record("actors", str(start_party[i])).get("initial_level", 1))
		hb.add_child(who)
		hb.add_child(lv)
		vb.add_child(hb)
		rows.append([who, lv])
	dlg.add_child(vb)
	var go := func():
		var sel := list.get_selected_items()
		var tid := str(troops[sel[0] if not sel.is_empty() else 0].get("id", ""))
		var party := []
		for r in rows:
			var aid := str(r[0].get_item_metadata(r[0].selected))
			if aid != "":
				party.append({"actor": aid, "level": int(r[1].value)})
		dlg.queue_free()
		_start_playtest({"battle_test": tid, "party": party})
	dlg.confirmed.connect(go)
	list.item_activated.connect(func(_i): go.call())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _select_mode(m: String) -> void:
	if m == "nav" and not view.is_image_map():
		status.text = "Navigation mode is for image-backed maps. This map takes passability from its tiles (Tiles on the toolbar)."
		m = "map" if view.mode == "nav" else view.mode
	for k in mode_buttons:
		mode_buttons[k].set_pressed_no_signal(k == m)
	view.set_mode(m)
	right_panel.visible = m == "event"
	palette.show_regions(m == "region")
	palette.show_nav(m == "nav")
	if m == "region" and view.brush.get("kind", "") != "region":
		view.brush = {"kind": "region", "region": 1}
	if m == "nav" and view.brush.get("kind", "") != "nav":
		view.brush = {"kind": "nav", "bits": RPGImageMap.WALKABLE}
	_refresh_event_list()
	_sync_menus()


func _select_tool(t: String) -> void:
	for k in tool_buttons:
		tool_buttons[k].set_pressed_no_signal(k == t)
	view.tool = t


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_F5: _select_mode("map")
		KEY_F6: _select_mode("event")
		KEY_F7: _select_mode("nav" if event.shift_pressed else "region")
		KEY_F8: open_database()
		KEY_F9: playtest({})
		KEY_R:
			if event.ctrl_pressed:
				playtest({})
			else:
				return
		KEY_S:
			if event.ctrl_pressed:
				save_current()
			else:
				return
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			if event.ctrl_pressed:
				view.set_zoom(view.zoom * 1.25)
			else:
				return
		KEY_MINUS, KEY_KP_SUBTRACT:
			if event.ctrl_pressed:
				view.set_zoom(view.zoom / 1.25)
			else:
				return
		KEY_0, KEY_KP_0:
			if event.ctrl_pressed:
				view.set_zoom(view.game_zoom())
			else:
				return
		KEY_X, KEY_C, KEY_V:
			# The Edit menu's event cut / copy / paste. A text field with focus keeps its own.
			if not event.ctrl_pressed or event.shift_pressed or view.mode != "event" or _text_has_focus():
				return
			edit_command({KEY_X: "cut", KEY_C: "copy", KEY_V: "paste"}[event.keycode])
		_: return
	get_viewport().set_input_as_handled()


func _text_has_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


# --- project and maps ----------------------------------------------------------------------------------

var _welcome: Control


func reload_project() -> void:
	data = RPGProjectData.open()
	_show_welcome(not FileAccess.file_exists(data.root.path_join("project.json")))
	registry = RPGCommandRegistry.new()
	registry.load_all(data.project.get("extensions", []), data.project.get("disabled_extensions", []), data.project.get("extensions_root", "res://extensions"))
	if current_map == "":
		current_map = _last_map()
	tree.rebuild(data, current_map)
	if current_map != "" and data.maps.has(current_map):
		open_map(current_map)
	elif not data.maps.is_empty():
		open_map(data.map_index.maps[0].id)
	else:
		current_map = ""
	var db := _database_screen()
	if db != null and db.has_method("reload"):
		db.reload()


## The Database tab's screen (a sibling main screen), or null outside the editor.
func _database_screen() -> Node:
	if plugin == null:
		return null
	return EditorInterface.get_editor_main_screen().get_node_or_null("Database")


## The map that was open when the editor last closed (per project, in Godot's project metadata).
func _last_map() -> String:
	if plugin == null:
		return ""
	return str(EditorInterface.get_editor_settings().get_project_metadata("rpg_kit", "last_map", ""))


func open_map(id: String) -> void:
	if id == "" or not data.maps.has(id):
		return
	if view.map_node != null and view.dirty:
		view.save()
	current_map = id
	view.open_map(data, id)
	tree.select_map(id)
	if plugin != null:
		EditorInterface.get_editor_settings().set_project_metadata("rpg_kit", "last_map", id)
	palette.set_tile_set(view.tile_set(), data.tile_size())
	var image_map := view.is_image_map()
	palette.set_nav_enabled(image_map)
	if mode_buttons.has("nav"):
		mode_buttons.nav.disabled = not image_map
		mode_buttons.nav.tooltip_text = NAV_TIP_ON if image_map else NAV_TIP_OFF
	_sync_image_controls()
	remember_images()
	if view.mode == "nav" and not image_map:
		_select_mode("map")
	palette.show_regions(view.mode == "region")
	palette.show_nav(view.mode == "nav")
	_refresh_event_list()
	_update_status()
	remember_disk()


## Tile settings dialog for the current map's tileset; saving rebuilds the TileSet and reopens
## the map so the view and the passability overlay use it.
func open_tile_settings() -> RPGTileSettingsDialog:
	var ts_id := str(data.map_props(current_map).get("tileset", "")) if current_map != "" else ""
	var dlg := RPGTileSettingsDialog.open_for(data, ts_id, self)
	dlg.saved.connect(func(_id: String) -> void:
		RPGMap.clear_tileset_cache()
		if current_map != "":
			open_map(current_map))
	return dlg


func save_current() -> void:
	if view.map_node == null:
		return
	var err := view.save()
	status.text = ("Saved %s" % current_map) if err == OK else ("Save failed (%d)" % err)
	remember_disk()


func _on_brush(b: Dictionary) -> void:
	view.brush = b
	if b.get("kind", "") == "region" and view.mode != "region":
		_select_mode("region")
	elif b.get("kind", "") == "nav" and view.mode != "nav":
		_select_mode("nav")
	elif b.get("kind", "") == "tiles" and view.mode in ["region", "nav"]:
		_select_mode("map")


func _on_hover(cell: Vector2i) -> void:
	_update_status()


func _update_status() -> void:
	if view.map_node == null:
		status.text = "No map open"
		return
	var e: Dictionary = data.map_entry(current_map)
	var s := "%s (%s)  %d×%d%s" % [e.get("name", current_map), current_map, view.map_size.x, view.map_size.y, "  •" if view.dirty else ""]
	var c := view.hover_cell
	if view.in_map(c):
		var mv := RPGMovement.new(view.map_node)
		s += "   |   (%d, %d)  region %d  terrain %d  passage %d" % [c.x, c.y, view.map_node.region_at(c), mv.terrain(c), mv.passage(c)]
		if view.is_image_map():
			s += "  navigation: %s" % RPGImageMap.describe(RPGImageMap.nav_bits(view.map_node.navigation, c))
		var ev := view.event_at(c)
		if not ev.is_empty():
			s += "  event '%s'" % ev.get("id", "")
	status.text = s


func _on_map_action(action: String, id: String) -> void:
	match action:
		"new", "new_image":
			RPGMapPropertiesDialog.open_for(self, data, "", true, func(new_id, props, entry_name):
				create_map_from_props(new_id, props, entry_name if entry_name != "" else new_id, id), id, action == "new_image")
		"properties":
			RPGMapPropertiesDialog.open_for(self, data, id, false, func(_id, props, entry_name): apply_props_reviewed(id, props, entry_name))
		"start_here":
			open_map(id)
			var cell := _first_free_cell(id)
			if cell.x >= 0:
				set_start(cell)
			else:
				push_warning("Map '%s' has no passable tile for the start position." % id)
		"copy":
			# Copy takes the map as it is now, including unsaved painting.
			if id == current_map and view.dirty:
				view.save()
			clipboard_map = id
		"shift":
			_shift_dialog(id)
		"sample":
			_sample_map_dialog(id)
		"dungeon":
			_dungeon_dialog(id)
		"paste":
			if clipboard_map != "":
				var nid := RPGMapFiles.copy_map(data, clipboard_map)
				data.reload()
				tree.rebuild(data, nid)
		"delete":
			var dlg := ConfirmationDialog.new()
			dlg.dialog_text = "Delete map '%s'? Its scene, properties and events files are removed. This cannot be undone." % id
			dlg.confirmed.connect(func():
				var was_open := current_map == id
				if was_open:
					view.close_map()
					current_map = ""
				var parent := str(data.map_entry(id).get("parent", ""))
				RPGMapFiles.delete_map(data, id)
				data.reload()
				tree.rebuild(data)
				# Don't leave an empty canvas behind: open the parent map, or the first one left.
				if was_open:
					var left: Array = data.map_index.get("maps", [])
					var next := parent if data.maps.has(parent) else (str(left[0].id) if not left.is_empty() else "")
					if next != "":
						open_map(next)
					else:
						_refresh_event_list()
						_update_status()
				status.text = "Deleted map '%s'." % id
				dlg.queue_free())
			dlg.canceled.connect(dlg.queue_free)
			add_child(dlg)
			dlg.popup_centered()
		"favourite":
			var index: Dictionary = data.map_index.duplicate(true)
			var favs: Array = index.get("favourites", [])
			if favs.has(id):
				favs.erase(id)
			else:
				favs.append(id)
			index["favourites"] = favs
			RPGMapFiles.save_index(data, index)
			tree.rebuild(data, id)


## Map > Shift: moves the whole map's contents; things pushed off one edge come in at the other.
func _shift_dialog(id: String) -> void:
	if RPGImageMap.is_image_map(data.map_props(id)):
		status.text = "Shift contents is not available on image-backed maps: the picture can't move with the tiles and events. Edit the picture instead."
		return
	open_map(id)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Shift map contents"
	dlg.ok_button_text = "Shift"
	var g := GridContainer.new()
	g.columns = 2
	var dirs := OptionButton.new()
	for d in ["Up", "Down", "Left", "Right"]:
		dirs.add_item(d)
	var n := SpinBox.new()
	n.min_value = 1
	n.max_value = 500
	n.value = 1
	for pair in [["Direction", dirs], ["Tiles", n]]:
		var l := Label.new()
		l.text = pair[0]
		g.add_child(l)
		g.add_child(pair[1])
	var note := Label.new()
	note.text = "Tiles, shadows, regions and events all move.
What leaves one edge comes back at the opposite edge."
	var vb := VBoxContainer.new()
	vb.add_child(g)
	vb.add_child(note)
	dlg.add_child(vb)
	dlg.confirmed.connect(func():
		var off: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][dirs.selected] * int(n.value)
		shift_map(off)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func shift_map(offset: Vector2i) -> void:
	if view.map_node == null or offset == Vector2i.ZERO:
		return
	# Wrapping is reversible, so undo is simply the opposite shift.
	undo.create_action("RPG: Shift map")
	undo.add_do_method(self, "_do_shift", [current_map, offset])
	undo.add_undo_method(self, "_do_shift", [current_map, -offset])
	undo.commit_action(true)
	status.text = "Shifted %s by (%d, %d)." % [current_map, offset.x, offset.y]


func _do_shift(map_id: String, offset: Vector2i) -> void:
	if current_map != map_id:
		open_map(map_id)
	if view.map_node == null:
		return
	var ev := RPGMapFiles.shift_contents(data, view.map_node, offset)
	view.save()
	RPGMapFiles.save_events_file(data, map_id, ev)
	view.reload_events()
	view.queue_redraw()
	view.overlay.queue_redraw()
	remember_disk()


const DungeonGen := preload("res://addons/rpg/editor/map/rpg_dungeon_generator.gd")


## Map > Generate Dungeon: rooms and corridors over the whole map, one undo step.
func _dungeon_dialog(id: String) -> void:
	open_map(id)
	if view.map_node == null or view.tile_layers().is_empty():
		return
	var choices: Array = DungeonGen.tile_choices(view.tile_set())
	if choices.size() < 2:
		status.text = "This map's tileset has too few tiles for a dungeon."
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Generate dungeon: %s" % id
	dlg.ok_button_text = "Generate"
	var g := GridContainer.new()
	g.columns = 2
	var floor_o := OptionButton.new()
	var wall_o := OptionButton.new()
	for o in [floor_o, wall_o]:
		o.fit_to_longest_item = false
		o.custom_minimum_size.x = 260
		for c in choices:
			if c.size() > 3 and c[3] is Texture2D:
				o.add_icon_item(c[3], str(c[1]))
			else:
				o.add_item(str(c[1]))
			o.set_item_metadata(o.item_count - 1, c[0])
	# A walkable floor and a wall that blocks, so the default dungeon can be played.
	var defaults: Array = DungeonGen.default_pair(choices)
	floor_o.select(defaults[0])
	wall_o.select(defaults[1])
	var style := OptionButton.new()
	style.add_item("Rooms and corridors")
	style.add_item("Passages only")
	var width := SpinBox.new()
	width.min_value = 1
	width.max_value = 3
	var seed_box := SpinBox.new()
	seed_box.min_value = 0
	seed_box.max_value = 999999
	seed_box.value = randi() % 1000000
	for pair in [["Floor", floor_o], ["Wall", wall_o], ["Layout", style], ["Corridor width", width], ["Seed", seed_box]]:
		var l := Label.new()
		l.text = pair[0]
		g.add_child(l)
		g.add_child(pair[1])
	var note := Label.new()
	note.text = "Replaces every tile on this map (events stay). Undo restores it."
	var vb := VBoxContainer.new()
	vb.add_child(g)
	vb.add_child(note)
	dlg.add_child(vb)
	dlg.confirmed.connect(func():
		generate_dungeon(str(floor_o.get_item_metadata(floor_o.selected)), str(wall_o.get_item_metadata(wall_o.selected)), {"style": "rooms" if style.selected == 0 else "passages", "corridor_width": int(width.value)}, int(seed_box.value))
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func generate_dungeon(floor_key: String, wall_key: String, options: Dictionary, seed_value: int) -> Dictionary:
	var layout: Dictionary = DungeonGen.generate(view.map_size, seed_value, options)
	view._begin_stroke()
	DungeonGen.apply(view.map_node, layout, floor_key, wall_key)
	view._end_stroke("Generate dungeon")
	view.queue_redraw()
	status.text = "Generated a dungeon with %d rooms (seed %d)." % [layout.rooms.size(), seed_value]
	return layout


func _sample_map_dialog(parent: String) -> void:
	var samples := RPGMapFiles.sample_maps()
	if samples.is_empty():
		status.text = "No sample maps are installed (addons/rpg/templates/sample_maps)."
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Load sample map"
	dlg.ok_button_text = "Add map"
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 200)
	for m in samples:
		list.add_item("%s — %s" % [m.get("name", m.id), m.get("description", "")])
	list.select(0)
	dlg.add_child(list)
	var go := func():
		var sel := list.get_selected_items()
		var sid := str(samples[sel[0] if not sel.is_empty() else 0].id)
		dlg.queue_free()
		var nid := RPGMapFiles.load_sample_map(data, sid, parent)
		if nid == "":
			status.text = "Could not load sample map '%s'." % sid
			return
		data.reload()
		tree.rebuild(data, nid)
		open_map(nid)
	dlg.confirmed.connect(go)
	list.item_activated.connect(func(_i): go.call())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _on_reorder(index: Dictionary) -> void:
	RPGMapFiles.save_index(data, index)
	tree.rebuild(data, current_map)


## Shows the foreground control when the open map has a foreground image, and applies it.
func _sync_image_controls() -> void:
	if foreground_option != null:
		foreground_option.visible = view.is_image_map() and view.map_node.image_foreground != null
	view.apply_foreground_view()


## New map dialog result: a tile map, or an image-backed map sized from its base image with its
## navigation filled (RPGMapFiles.create_image_map). Opens the new map (image-backed ones in
## Navigation mode, with the navigation showing).
func create_map_from_props(new_id: String, props: Dictionary, entry_name: String, parent := "") -> Error:
	var err := OK
	var image_map := RPGImageMap.is_image_map(props)
	if image_map:
		var bits := RPGImageMap.WALKABLE if str(RPGImageMap.block(props).get("new_cells", "blocked")) == "walkable" else RPGImageMap.BLOCKED
		err = RPGMapFiles.create_image_map(data, new_id, entry_name, props, Vector2i(int(props.width), int(props.height)), bits, parent)
	else:
		err = RPGMapFiles.create_map(data, new_id, entry_name, str(props.tileset), int(props.width), int(props.height), parent)
		if err == OK:
			RPGMapFiles.save_props(data, new_id, props)
	if err != OK:
		status.text = "Could not create map '%s' (error %d)." % [new_id, err]
		push_error(status.text)
		return err
	data.reload()
	tree.rebuild(data, new_id)
	open_map(new_id)
	if image_map:
		_select_mode("nav")
		status.text = "Created image-backed map '%s' (%d×%d cells). Paint where characters can walk, then add events in Event mode (F6)." % [new_id, int(props.width), int(props.height)]
	return OK


## Map properties result. For an image-backed map whose new base image changes the map's size,
## shows the size review first (nothing changes until it is confirmed).
func apply_props_reviewed(id: String, props: Dictionary, entry_name: String) -> void:
	var old: Dictionary = data.map_props(id)
	var old_cells := Vector2i(int(old.get("width", 0)), int(old.get("height", 0)))
	var new_cells := Vector2i(int(props.get("width", 0)), int(props.get("height", 0)))
	if RPGImageMap.is_image_map(props) and old_cells != new_cells:
		review_image_resize(id, props, entry_name)
		return
	_apply_props(id, props, entry_name)
	if RPGImageMap.is_image_map(props) and current_map == id:
		view.refresh_images(true)
		_sync_image_controls()


## The size review for a base image that is a different size from the map. Lists everything
## that would fall outside a smaller map; nothing is changed unless the maker confirms.
## Returns the dialog (tests press its buttons).
func review_image_resize(id: String, props: Dictionary, entry_name: String) -> ConfirmationDialog:
	var old: Dictionary = data.map_props(id)
	var old_cells := Vector2i(int(old.get("width", 0)), int(old.get("height", 0)))
	var new_cells := Vector2i(int(props.get("width", 0)), int(props.get("height", 0)))
	if current_map != id:
		open_map(id)
	var outside := RPGMapFiles.outside_after_resize(data, id, view.map_node, new_cells)
	var dlg := ConfirmationDialog.new()
	dlg.title = "The base image is a different size"
	var text := "The new base image makes the map %d×%d cells; it is %d×%d now.\n\n" % [new_cells.x, new_cells.y, old_cells.x, old_cells.y]
	if outside.is_empty():
		if new_cells.x >= old_cells.x and new_cells.y >= old_cells.y:
			text += "The map grows. New cells start %s for walking; nothing is removed." % ("open" if str(RPGImageMap.block(props).get("new_cells", "blocked")) == "walkable" else "blocked")
		else:
			text += "The map shrinks, but nothing you placed or painted is outside the new size."
		dlg.ok_button_text = "Resize map"
	else:
		text += "These are outside the new size and would be deleted:\n• %s\n\nStarting positions outside are moved to the nearest cell inside. Undo is not available for this. Cancel keeps the map and its images as they are." % "\n• ".join(PackedStringArray(outside.slice(0, 20)))
		if outside.size() > 20:
			text += "\n(and %d more)" % (outside.size() - 20)
		dlg.ok_button_text = "Resize and delete these"
	dlg.dialog_text = text
	dlg.confirmed.connect(func():
		dlg.queue_free()
		apply_image_resize(id, props, entry_name))
	dlg.canceled.connect(func():
		status.text = "Kept map '%s' and its images as they were." % id
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
	return dlg


## Applies a reviewed image size change: resizes the map (removing what is outside a smaller
## one), moves starting positions inside, fills new navigation cells, then saves the properties.
func apply_image_resize(id: String, props: Dictionary, entry_name: String) -> void:
	var old: Dictionary = data.map_props(id)
	var old_cells := Vector2i(int(old.get("width", 0)), int(old.get("height", 0)))
	var new_cells := Vector2i(int(props.get("width", 0)), int(props.get("height", 0)))
	if current_map != id:
		open_map(id)
	_clamp_start_positions(id, new_cells)
	_apply_props(id, props, entry_name, true)
	if view.map_node != null and current_map == id and (new_cells.x > old_cells.x or new_cells.y > old_cells.y):
		RPGMapFiles.grow_navigation(view.map_node, props, old_cells, new_cells)
		view.save()
	view.refresh_images(true)
	_sync_image_controls()
	remember_disk()
	status.text = "Map '%s' is now %d×%d cells." % [id, new_cells.x, new_cells.y]


func _clamp_start_positions(id: String, cells: Vector2i) -> void:
	var file := RPGJson.load_or(data.root.path_join("database/system.json"), {})
	if not (file.get("system") is Dictionary):
		return
	var changed := false
	var clamp := func(holder: Variant) -> void:
		if holder is Dictionary and str(holder.get("map", "")) == id and holder.get("position") is Array:
			var p: Array = holder.position
			var q := [clampi(int(p[0]), 0, cells.x - 1), clampi(int(p[1]), 0, cells.y - 1)]
			if q[0] != int(p[0]) or q[1] != int(p[1]):
				holder["position"] = q
				changed = true
	clamp.call(file.system.get("start"))
	var vs: Variant = file.system.get("vehicles", {})
	if vs is Dictionary:
		for k in vs:
			if vs[k] is Dictionary:
				clamp.call(vs[k].get("start"))
	if changed:
		_write_system(file)


func _apply_props(id: String, props: Dictionary, entry_name: String, confirmed := false) -> void:
	var old: Dictionary = data.map_props(id)
	var w := int(props.width)
	var h := int(props.height)
	var old_w := int(old.get("width", w))
	var old_h := int(old.get("height", h))
	# Resizing works on the open map: open the one being changed first (saves the current one).
	if (w != old_w or h != old_h) and current_map != id:
		open_map(id)
	# Shrinking deletes the events outside the new size: name them and ask first.
	if not confirmed and current_map == id and (w < int(old.get("width", w)) or h < int(old.get("height", h))):
		var outside := []
		for ev in view.events():
			var p: Array = ev.get("position", [0, 0])
			if int(p[0]) >= w or int(p[1]) >= h:
				outside.append("%s (%s)" % [ev.get("name", ""), ev.get("id", "")])
		if not outside.is_empty():
			var dlg := ConfirmationDialog.new()
			dlg.title = "Shrink map"
			dlg.dialog_text = "Shrinking to %d×%d deletes %d event(s) outside the map:
%s

Tiles outside are removed too. Undo is not available for this." % [w, h, outside.size(), "
".join(PackedStringArray(outside.slice(0, 15)))]
			dlg.ok_button_text = "Shrink and delete"
			dlg.confirmed.connect(func():
				dlg.queue_free()
				_apply_props(id, props, entry_name, true))
			dlg.canceled.connect(dlg.queue_free)
			add_child(dlg)
			dlg.popup_centered()
			return
	if view.map_node != null and current_map == id and (w < int(old.get("width", w)) or h < int(old.get("height", h))):
		var res := RPGMapFiles.resize(data, view.map_node, w, h)
		RPGMapFiles.save_events_file(data, id, res.events_file)
		if not res.removed_events.is_empty():
			push_warning("Shrinking removed events: %s" % ", ".join(PackedStringArray(res.removed_events)))
		view.save()
	RPGMapFiles.save_props(data, id, props)
	if entry_name != "":
		var index: Dictionary = data.map_index.duplicate(true)
		for m in index.maps:
			if m.id == id:
				m["name"] = entry_name
		RPGMapFiles.save_index(data, index)
	RPGMap.clear_tileset_cache()
	data.reload()
	tree.rebuild(data, id)
	open_map(id)
	# Autotiles on the old right/bottom edge were drawn as map edges; re-join them with the
	# new space so they don't look cut off.
	if view.map_node != null and (w > old_w or h > old_h):
		view.rejoin_edges(Vector2i(old_w, old_h))
		view.save()
		remember_disk()


# --- events -------------------------------------------------------------------------------------------------

func _refresh_event_list() -> void:
	if event_list == null:
		return
	event_list.clear()
	for ev in view.events():
		var p: Array = ev.get("position", [0, 0])
		event_list.add_item("%s  [%s]  (%d, %d)" % [ev.get("name", ""), ev.get("id", ""), int(p[0]), int(p[1])])
		event_list.set_item_metadata(event_list.item_count - 1, ev.get("id", ""))
		if ev.get("id", "") == view.selected_event:
			event_list.select(event_list.item_count - 1)


func _on_view_selection(id: String) -> void:
	for i in event_list.item_count:
		if str(event_list.get_item_metadata(i)) == id:
			event_list.select(i)
			return
	event_list.deselect_all()


## Opens the event editor on event `id`, or (with `new_at` on the map) on a new event at that
## tile that is only written when the maker presses OK or Apply (Cancel leaves no empty event).
func edit_event(id: String, new_at := Vector2i(-1, -1)) -> void:
	if view.map_node == null or (id == "" and new_at.x < 0):
		return
	if ResourceLoader.exists(EVENT_EDITOR):
		var cls: Script = load(EVENT_EDITOR)
		if cls.has_method("open_for"):
			var on_saved := func(_a = null):
				view.reload_events()
				_refresh_event_list()
				remember_disk()
			var w: Node = null
			if new_at.x >= 0 and cls.has_method("open_new"):
				w = cls.open_new(current_map, new_at, data, registry, undo.manager if undo else null, on_saved)
			else:
				if id == "":
					id = view.new_event_at(new_at)
				w = cls.open_for(current_map, id, data, registry, undo.manager if undo else null, on_saved)
			if w != null and w.get_parent() == null:
				add_child(w)
			if w != null:
				var eid: String = str(w.get("event_id")) if w.get("event_id") != null else id
				var pos := new_at
				if pos.x < 0:
					var ev := view.find_event(eid)
					var p: Array = ev.get("position", [0, 0])
					pos = Vector2i(int(p[0]), int(p[1]))
				if w.has_signal("pick_location_requested"):
					w.pick_location_requested.connect(pick_location)
				if w.has_signal("route_preview_requested"):
					w.route_preview_requested.connect(func(route: Variant, target: String): preview_route(str(w.get("event_id")) if target == "this" else target, route))
				if w.has_signal("event_test_requested"):
					w.event_test_requested.connect(func(cmds: Array):
						playtest({"map": current_map, "position": [pos.x, pos.y + 1], "test_commands": cmds}))
				if w.has_signal("closed"):
					# The route preview and its status line belong to the editor that asked for them.
					w.closed.connect(func():
						view.show_route_preview({})
						_update_status())
			return
	if id == "":
		id = view.new_event_at(new_at)
	_json_fallback_editor(id)


## Location picker for forms (transfer targets, event locations): map + cell, prefilled with
## `current` ({map, position} or null). Calls `callback.call(map_id, Vector2i)` on OK.
func pick_location(callback: Callable, current: Variant = null) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Pick a location"
	var box := VBoxContainer.new()
	dlg.add_child(box)
	var maps := OptionButton.new()
	var ids: Array = data.maps.keys()
	ids.sort()
	for i in ids.size():
		var nm := str(data.map_entry(ids[i]).get("name", ""))
		if nm == "":
			nm = str(data.map_props(ids[i]).get("display_name", ""))
		maps.add_item(("%s (%s)" % [nm, ids[i]]) if nm != "" and nm != ids[i] else str(ids[i]))
		maps.set_item_metadata(i, ids[i])
	box.add_child(maps)
	var row := HBoxContainer.new()
	box.add_child(row)
	var xs := SpinBox.new()
	var ys := SpinBox.new()
	for sb in [xs, ys]:
		sb.min_value = 0
		sb.max_value = 999
	row.add_child(Label.new())
	row.get_child(0).text = "X"
	row.add_child(xs)
	var yl := Label.new()
	yl.text = "Y"
	row.add_child(yl)
	row.add_child(ys)
	var hint := Label.new()
	hint.text = "Tip: the status bar shows the tile under the mouse in the map view."
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	var cur_map := current_map
	var cur_pos := view.hover_cell if view.in_map(view.hover_cell) else Vector2i.ZERO
	if current is Dictionary:
		cur_map = str(current.get("map", cur_map))
		var p: Variant = current.get("position")
		if p is Array and p.size() >= 2:
			cur_pos = Vector2i(int(p[0]), int(p[1]))
	maps.select(maxi(0, ids.find(cur_map)))
	xs.value = cur_pos.x
	ys.value = cur_pos.y
	var clamp_to_map := func(_i = 0):
		var sz: Vector2i = data.map_size(str(maps.get_item_metadata(maps.selected)))
		xs.max_value = maxi(0, sz.x - 1)
		ys.max_value = maxi(0, sz.y - 1)
	maps.item_selected.connect(clamp_to_map)
	clamp_to_map.call()
	dlg.confirmed.connect(func():
		callback.call(str(maps.get_item_metadata(maps.selected)), Vector2i(int(xs.value), int(ys.value)))
		dlg.queue_free())
	# A cancel is answered too ("" map): the asking dialog hid itself and shows itself again.
	dlg.canceled.connect(func():
		callback.call("", Vector2i(-1, -1))
		dlg.queue_free())
	# Spec: the target map opens and you click the tile.
	var on_map := dlg.add_button("Click on the map...", true, "pick_on_map")
	on_map.tooltip_text = "Opens the map; click the tile (Esc or right click cancels)"
	dlg.custom_action.connect(func(action: StringName):
		if action != &"pick_on_map":
			return
		var target := str(maps.get_item_metadata(maps.selected))
		dlg.hide()
		var back_map := current_map
		open_map(target)
		_select_mode("event")
		status.text = "Click the tile for this location on '%s'. Esc or right click cancels." % target
		view.pick_callback = func(map_id: String, cell: Vector2i):
			callback.call(map_id, cell)
			_update_status()
			if back_map != "" and back_map != current_map:
				open_map(back_map)
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(360, 140))


## Minimal editor used until the full event editor is available: the event as JSON.
func _json_fallback_editor(id: String) -> void:
	var ev := view.find_event(id)
	var dlg := AcceptDialog.new()
	dlg.title = "Event %s (JSON)" % id
	var te := TextEdit.new()
	te.text = RPGJson.stringify(ev)
	te.custom_minimum_size = Vector2(640, 480)
	dlg.add_child(te)
	dlg.confirmed.connect(func():
		var r := RPGJson.parse_text(te.text)
		if r.ok and r.data is Dictionary:
			var before := view.events_file.duplicate(true)
			for i in view.events().size():
				if view.events()[i].get("id", "") == id:
					view.events_file.events[i] = r.data
			view.commit_events(before, "Edit event JSON")
		else:
			push_error("Event JSON is invalid (line %d): %s" % [r.line, r.error])
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


func _on_event_context(id: String, cell: Vector2i, screen_pos: Vector2) -> void:
	var m := PopupMenu.new()
	m.add_item("Edit...", 1)
	m.add_separator()
	m.add_item("Cut", 2)
	m.add_item("Copy", 3)
	m.add_item("Delete", 4)
	m.add_separator()
	m.add_item("Set starting position here", 5)
	m.id_pressed.connect(func(a):
		match a:
			1: edit_event(id)
			2:
				clipboard_event = view.find_event(id).duplicate(true)
				view.delete_event(id)
			3: clipboard_event = view.find_event(id).duplicate(true)
			4: view.delete_event(id)
			5: set_start(cell)
		m.queue_free())
	_popup(m, screen_pos)


## New event on an empty tile (double-click, or right-click > New event...): opens the editor.
func new_event(cell: Vector2i) -> void:
	if view.map_node == null or not view.in_map(cell) or not view.event_at(cell).is_empty():
		return
	edit_event("", cell)


func _on_map_context(cell: Vector2i, screen_pos: Vector2) -> void:
	if not view.in_map(cell):
		return
	if view.mode != "event":
		return
	var m := PopupMenu.new()
	m.add_item("New event...", 1)
	m.add_item("Paste", 2)
	m.set_item_disabled(1, clipboard_event.is_empty())
	var quick := PopupMenu.new()
	quick.name = "Quick"
	var templates := _quick_templates()
	for i in templates.size():
		quick.add_item(str(templates[i]), 100 + i)
	m.add_child(quick)
	m.add_submenu_item("Quick events", "Quick")
	m.add_separator()
	# RPG Maker's "Set Starting Position": the player, or where a vehicle starts the game.
	var start := PopupMenu.new()
	start.name = "Start"
	start.add_item("Player", 3)
	start.add_item("Boat", 50)
	start.add_item("Ship", 51)
	start.add_item("Airship", 52)
	m.add_child(start)
	m.add_submenu_item("Set starting position", "Start")
	m.add_item("▶ Playtest from here", 4)
	var handler := func(a: int):
		if a >= 50 and a <= 52:
			set_vehicle_start(["boat", "ship", "airship"][a - 50], cell)
			m.queue_free()
			return
		match a:
			1: new_event(cell)
			2: view.paste_event(clipboard_event, cell)
			3: set_start(cell)
			4: playtest({"map": current_map, "position": [cell.x, cell.y]})
			_:
				if a >= 100:
					_quick_event(str(templates[a - 100]), cell)
		m.queue_free()
	m.id_pressed.connect(handler)
	quick.id_pressed.connect(handler)
	start.id_pressed.connect(handler)
	_popup(m, screen_pos)


## `canvas_pos`: the click's global_position (in the map view's canvas).
func _popup(m: PopupMenu, canvas_pos: Vector2) -> void:
	m.close_requested.connect(m.queue_free)
	PopupPlace.at_point(view, m, canvas_pos)


func _quick_templates() -> Array:
	if ResourceLoader.exists(QUICK_EVENTS):
		var qe: Script = load(QUICK_EVENTS)
		if qe.has_method("template_names"):
			return qe.template_names()
		if qe.has_method("load_templates"):
			var t: Variant = qe.load_templates()
			if t is Dictionary:
				return t.keys()
			if t is Array:
				return t.map(func(x): return x.get("name", "") if x is Dictionary else str(x))
	return ["Transfer", "Door", "Treasure", "Inn", "Sign", "Shop"]


func _quick_event(template: String, cell: Vector2i) -> void:
	if ResourceLoader.exists(QUICK_DIALOG):
		var cls: Script = load(QUICK_DIALOG)
		if cls.has_method("open_for"):
			var w: Node = cls.open_for(current_map, cell, template, data, func(_a = null): view.reload_events(); _refresh_event_list(); remember_disk())
			if w != null and w.get_parent() == null:
				add_child(w)
			if w != null and w.has_signal("pick_location_requested"):
				w.pick_location_requested.connect(pick_location)
			return
	push_warning("Quick events need the event editor module.")


## Top-left tile the player can stand on (any passable direction, no event), or (-1, -1).
func _first_free_cell(id: String) -> Vector2i:
	if view.map_node == null or current_map != id:
		return Vector2i(-1, -1)
	var mv := RPGMovement.new(view.map_node)
	var sz: Vector2i = data.map_size(id)
	var taken := {}
	for ev in view.events():
		var p: Array = ev.get("position", [-1, -1])
		taken[Vector2i(int(p[0]), int(p[1]))] = true
	for y in sz.y:
		for x in sz.x:
			var c := Vector2i(x, y)
			if not taken.has(c) and mv.passage(c) != 0:
				return c
	return Vector2i(-1, -1)


## Move route Preview: traces the route from the character's position and draws it on the map.
## `who` is an event ID or "player" (the player starts at the map's start position or the hovered tile).
func preview_route(who: String, route: Variant) -> void:
	var start := Vector2i(-1, -1)
	var facing := "down"
	if who == "player":
		var sp: Dictionary = data.system.get("start", {})
		if str(sp.get("map", "")) == current_map:
			var p: Array = sp.get("position", [0, 0])
			start = Vector2i(int(p[0]), int(p[1]))
		elif view.in_map(view.hover_cell):
			start = view.hover_cell
	else:
		var ev := view.find_event(who)
		if not ev.is_empty():
			var p2: Array = ev.get("position", [0, 0])
			start = Vector2i(int(p2[0]), int(p2[1]))
			var pages: Array = ev.get("pages", [])
			if not pages.is_empty() and pages[0].get("graphic") is Dictionary:
				facing = str(pages[0].graphic.get("facing", "down"))
	if start.x < 0:
		status.text = "Route preview: '%s' is not on this map." % who
		return
	var tr := RPGRoutePreview.trace(start, facing, route)
	view.show_route_preview(tr)
	status.text = "Route preview: %d step(s)%s" % [tr.cells.size() - 1, (", then '%s' cannot be predicted" % tr.unknown) if tr.unknown != "" else ""]


## Shown instead of the map editor when the Godot project has no rpg/ data yet.
func _show_welcome(on: bool) -> void:
	# The main screen is a VBox: the welcome panel replaces the editor rather than overlaying it.
	for c in get_children():
		if c != _welcome and c is Control:
			c.visible = not on
	if not on:
		if _welcome:
			_welcome.queue_free()
			_welcome = null
		return
	if _welcome:
		return
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var centre := CenterContainer.new()
	panel.add_child(centre)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	centre.add_child(box)
	var title := Label.new()
	title.text = "Start a new RPG"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var info := Label.new()
	info.text = "This Godot project has no RPG data yet. Create it to get a starter database (hero, classes, skills, items, monsters), the Classic rules, the default menus and battle, and a first map to paint on. Everything goes in res://rpg/ as plain JSON."
	var style_note := Label.new()
	style_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_note.custom_minimum_size.x = 460
	style_note.modulate = Color(1, 1, 1, 0.7)
	style_note.text = "The style sets the screen size and how imported RPG Maker sheets are cut. The starter art is RPG Maker 2000 style (tile palette A, B, C); it is drawn larger to fit VX Ace and MV screens. For the VX Ace / MV palette (A, A5, B-E), import your own RPG Maker art afterwards with Tools > Resources."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 460
	box.add_child(info)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Game name"
	name_edit.text = str(ProjectSettings.get_setting("application/config/name", "My Game"))
	box.add_child(name_edit)
	var style_row := HBoxContainer.new()
	var style_lbl := Label.new()
	style_lbl.text = "Style"
	style_row.add_child(style_lbl)
	var style_pick := OptionButton.new()
	style_pick.tooltip_text = "How imported RPG Maker character and face sheets are cut, and the game's screen size.\nThe starter art works with every style; tilesets keep their own style."
	for k in RPGProjectTemplate.STYLES:
		var st: Dictionary = RPGProjectTemplate.STYLES[k]
		style_pick.add_item("%s (%d×%d)" % [st.name, st.screen.x, st.screen.y])
		style_pick.set_item_metadata(style_pick.item_count - 1, k)
	style_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_row.add_child(style_pick)
	box.add_child(style_row)
	box.add_child(style_note)
	var go := Button.new()
	go.text = "Create RPG project"
	box.add_child(go)
	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = 460
	box.add_child(msg)
	var create := func():
		var game_name := name_edit.text.strip_edges()
		if game_name == "":
			msg.text = "Give your game a name first (you can change it later in Database > System)."
			name_edit.grab_focus()
			return
		var r := RPGProjectTemplate.create("res://rpg", game_name, "res://extensions", str(style_pick.get_selected_metadata()))
		if r.error != OK:
			msg.text = "\n".join(PackedStringArray(r.messages))
			return
		apply_screen_size(r.screen)
		ensure_main_scene()
		if plugin != null:
			EditorInterface.get_resource_filesystem().scan()
		reload_project()
		if not r.messages.is_empty():
			status.text = " ".join(PackedStringArray(r.messages))
	go.pressed.connect(create)
	name_edit.text_submitted.connect(func(_t): create.call())
	_welcome = panel
	add_child(panel)


## Makes the RPG game scene the project's main scene when none is set, so Playtest and Battle test
## run the game instead of stopping at Godot's "No main scene" dialog. Returns true if it set it.
static func ensure_main_scene() -> bool:
	if not Engine.is_editor_hint():
		return false
	var cur := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if cur != "" and ResourceLoader.exists(cur):
		return false
	if not ResourceLoader.exists(GAME_SCENE):
		return false
	ProjectSettings.set_setting("application/run/main_scene", GAME_SCENE)
	ProjectSettings.save()
	return true


## Sets the game's screen (Godot's viewport size) and a window 1-3x larger, as a project style needs.
static func apply_screen_size(screen: Vector2i) -> void:
	if screen.x <= 0 or not Engine.is_editor_hint():
		return
	ProjectSettings.set_setting("display/window/size/viewport_width", screen.x)
	ProjectSettings.set_setting("display/window/size/viewport_height", screen.y)
	var k := 3 if screen.x <= 320 else 2 if screen.x <= 544 else 1
	ProjectSettings.set_setting("display/window/size/window_width_override", screen.x * k)
	ProjectSettings.set_setting("display/window/size/window_height_override", screen.y * k)
	ProjectSettings.save()


func _on_tools_menu(i: int) -> void:
	if i == 100:
		OS.shell_open(ProjectSettings.globalize_path("res://addons/rpg/docs/MAKER_GUIDE.md"))
	elif i == 101:
		OS.shell_open(ProjectSettings.globalize_path(data.root))
	elif i >= 0 and i < TOOL_TABS.size():
		open_tools(TOOL_TABS[i])


# --- outside edits ---------------------------------------------------------------------------------
# Spec: "The editor watches the disk." The open map's files and the project files are compared with
# the versions last loaded or written here whenever Godot regains focus or rescans the filesystem.

var _disk_stamps: Dictionary = {}
var _disk_prompt: ConfirmationDialog


func _watched_files() -> Array:
	var out := [data.root.path_join("project.json"), data.root.path_join("map_index.json"), data.root.path_join("database/system.json"), data.root.path_join("state.json"), data.root.path_join("common_events.json")]
	# The database files this tab reads (tilesets for map properties and New map, actors...).
	for t in RPGProjectData.DB_TYPES:
		out.append(_db_file(t))
	if current_map != "":
		var e: Dictionary = data.map_entry(current_map)
		for k in ["scene", "properties", "events"]:
			if str(e.get(k, "")) != "":
				out.append(str(e[k]))
	return out


## Image-backed maps: content hashes of the open map's base and foreground images. Kept apart
## from remember_disk(): the kit never writes these files, so only an outside edit changes them.
var _image_stamps: Dictionary = {}


func remember_images() -> void:
	_image_stamps.clear()
	if current_map == "":
		return
	var p: Dictionary = data.map_props(current_map)
	for f in [RPGImageMap.base_path(p), RPGImageMap.foreground_path(p)]:
		if f != "" and FileAccess.file_exists(f):
			_image_stamps[f] = FileAccess.get_md5(f)


## An image of the open map changed in a paint program: the same size is shown at once; a new
## size opens the size review; a broken file is reported (the map keeps its last good picture).
## Returns what happened: "", "refreshed", "review" or "invalid".
func check_image_changes() -> String:
	if current_map == "" or _image_stamps.is_empty():
		return ""
	var changed := false
	for f in _image_stamps:
		if FileAccess.file_exists(f) and FileAccess.get_md5(f) != _image_stamps[f]:
			changed = true
	if not changed:
		return ""
	remember_images()
	var p: Dictionary = data.map_props(current_map)
	var c := RPGImageMap.check_images(RPGImageMap.base_path(p), RPGImageMap.foreground_path(p), data.tile_size(), RPGImageMap.limits(data))
	if not c.ok:
		status.text = "The map's image changed but can't be used: %s" % " ".join(PackedStringArray(c.errors))
		return "invalid"
	if c.cells == view.map_size:
		view.refresh_images(true)
		_sync_image_controls()
		status.text = "Reloaded the images of '%s' (changed outside the editor)." % current_map
		return "refreshed"
	var p2 := p.duplicate(true)
	p2["width"] = c.cells.x
	p2["height"] = c.cells.y
	review_image_resize(current_map, p2, "")
	return "review"


## Records the current modification times (call after loading or writing the watched files).
func remember_disk() -> void:
	_disk_stamps.clear()
	for f in _watched_files():
		if FileAccess.file_exists(f):
			_disk_stamps[f] = FileAccess.get_md5(f)


## Files changed on disk since remember_disk().
func disk_changes() -> Array:
	var out := []
	for f in _disk_stamps:
		# Content hash: the Database tab can write within the same second as this tab.
		if FileAccess.file_exists(f) and FileAccess.get_md5(f) != _disk_stamps[f]:
			out.append(f)
	# Database files written for the first time (e.g. the first tileset of a project).
	for t in RPGProjectData.DB_TYPES:
		var p := _db_file(t)
		if not _disk_stamps.has(p) and FileAccess.file_exists(p):
			out.append(p)
	return out


func _db_file(type: String) -> String:
	return data.root.path_join("database/%s.json" % type)


## Database files (other than system.json) never conflict with edits on the map: the ones that
## changed are read again in place. Returns the changed paths that are not such files.
func _reload_database_files(changed: Array) -> Array:
	var rest := []
	var names := PackedStringArray()
	for f in changed:
		var t := str(f).get_file().get_basename()
		if str(f) == _db_file(t) and RPGProjectData.DB_TYPES.has(t):
			data.reload_db_type(t)
			names.append(str(f).get_file())
			if FileAccess.file_exists(str(f)):
				_disk_stamps[f] = FileAccess.get_md5(str(f))
		else:
			rest.append(f)
	if not names.is_empty():
		if names.has("tilesets.json"):
			RPGMap.clear_tileset_cache()
		status.text = "Reloaded %s (saved in the Database tab or outside the editor)." % ", ".join(names)
	return rest


## Reloads silently when nothing is unsaved here; otherwise asks which version wins. Database
## files are read again at once (they hold no map edits).
func check_disk_changes() -> void:
	if data == null or _disk_prompt != null:
		return
	check_image_changes()
	var changed := disk_changes()
	# A changed tileset the open map uses needs the map redrawn: a full reload when it can be.
	var map_ts := str(data.map_props(current_map).get("tileset", "")) if current_map != "" else ""
	var redraw := changed.has(_db_file("tilesets")) and map_ts != "" and (view == null or not view.dirty)
	if not redraw:
		changed = _reload_database_files(changed)
	if changed.is_empty():
		return
	var names := []
	for f in changed:
		names.append(str(f).get_file())
	if view == null or not view.dirty:
		_reload_from_disk("Reloaded %s (saved in the Database tab or outside the editor)." % ", ".join(PackedStringArray(names)))
		return
	_disk_prompt = ConfirmationDialog.new()
	_disk_prompt.title = "Files changed on disk"
	_disk_prompt.dialog_text = "%s changed outside the editor, and this map has unsaved changes.\n\nLoad the disk version (your unsaved changes are lost), or keep yours (saving will overwrite the disk version)?" % ", ".join(PackedStringArray(names))
	_disk_prompt.ok_button_text = "Load disk version"
	_disk_prompt.cancel_button_text = "Keep mine"
	_disk_prompt.confirmed.connect(func():
		view.dirty = false
		_reload_from_disk("Loaded the disk version.")
		_disk_prompt.queue_free()
		_disk_prompt = null)
	_disk_prompt.canceled.connect(func():
		remember_disk()
		_disk_prompt.queue_free()
		_disk_prompt = null)
	add_child(_disk_prompt)
	_disk_prompt.popup_centered()


func _reload_from_disk(message: String) -> void:
	var keep := current_map
	data.reload()
	RPGMap.clear_tileset_cache()
	tree.rebuild(data, keep)
	if keep != "" and data.maps.has(keep):
		current_map = ""
		open_map(keep)
	else:
		remember_disk()
	status.text = message


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_visible_in_tree():
		check_disk_changes.call_deferred()


## Switches to the Database tab and selects a record (file: database/<type>.json or common_events.json).
func open_database_record(file: String, id: String) -> void:
	if plugin == null:
		return
	EditorInterface.set_main_screen_editor("Database")
	var db: Node = EditorInterface.get_editor_main_screen().get_node_or_null("Database")
	if db != null and db.has_method("select_record_for_file"):
		db.select_record_for_file(file, id)


## Opens the Tools window on one of its tabs.
func open_tools(tab: String) -> Window:
	var w := RPGToolsWindow.new()
	w.setup(data, registry)
	w.open_record.connect(open_database_record)
	w.open_location.connect(func(map_id: String, event_id: String):
		if map_id != "":
			open_map(map_id)
			_select_mode("event")
			if event_id != "":
				view.select_event(event_id)
				edit_event(event_id))
	w.extensions_changed.connect(reload_project)
	add_child(w)
	w.show_tab(tab)
	# Most of the editor window (it can be resized; the size is remembered while the editor runs).
	var avail := get_viewport_rect().size
	w.popup_centered(Vector2i(clampi(int(avail.x * 0.7), mini(820, int(avail.x) - 40), 1600), clampi(int(avail.y * 0.75), mini(560, int(avail.y) - 40), 1100)))
	return w


## Set starting position: stored in the System record as {map, position, facing}.
func set_start(cell: Vector2i) -> void:
	var path := data.root.path_join("database/system.json")
	var file: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "system": {}})
	var before: Dictionary = file.duplicate(true)
	file.system["start"] = {"map": current_map, "position": [cell.x, cell.y], "facing": "down"}
	if undo != null:
		undo.create_action("RPG: Set starting position")
		undo.add_do_method(self, "_write_system", [file])
		undo.add_undo_method(self, "_write_system", [before])
		undo.commit_action(true)
	else:
		_write_system(file)


## Where a vehicle starts a new game (System record, vehicles.<kind>.start).
func set_vehicle_start(kind: String, cell: Vector2i) -> void:
	var path := data.root.path_join("database/system.json")
	var file: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "system": {}})
	var before: Dictionary = file.duplicate(true)
	if not (file.system.get("vehicles") is Dictionary):
		file.system["vehicles"] = {}
	if not (file.system.vehicles.get(kind) is Dictionary):
		file.system.vehicles[kind] = {}
	file.system.vehicles[kind]["start"] = {"map": current_map, "position": [cell.x, cell.y]}
	if undo != null:
		undo.create_action("RPG: Set %s starting position" % kind)
		undo.add_do_method(self, "_write_system", [file])
		undo.add_undo_method(self, "_write_system", [before])
		undo.commit_action(true)
	else:
		_write_system(file)
	status.text = "The %s starts the game at %s on %s." % [kind, cell, current_map]
	view.overlay.queue_redraw()


func _write_system(file: Dictionary) -> void:
	RPGJson.save_file(data.root.path_join("database/system.json"), file)
	data.reload()
	view.start_pos = data.system.get("start", {})
	view.overlay.queue_redraw()


# --- playtest -------------------------------------------------------------------------------------------------

## Runs the game. options: {} (from the start), {map, position} (from here) or {battle_test: troop}.
func playtest(options: Dictionary) -> void:
	if view.dirty:
		view.save()
	var problems := _validate_before_playtest()
	if problems.is_empty() or plugin == null:
		_start_playtest(options)
		return
	# Spec: the full check (including rule-system capabilities) runs before playtest.
	var dlg := ConfirmationDialog.new()
	dlg.title = "Playtest: %d problem(s)" % problems.size()
	dlg.dialog_text = "\n".join(PackedStringArray(problems.slice(0, 12))) + ("\n..." if problems.size() > 12 else "") + "\n\nThe game may stop with an error where these are used."
	dlg.ok_button_text = "Play anyway"
	dlg.cancel_button_text = "Cancel"
	# Escape and the close button only cancel; "Show problems" lists them in Tools > Deploy, where
	# each one can be double-clicked.
	dlg.add_button("Show problems", false, "show_problems")
	dlg.confirmed.connect(func():
		dlg.queue_free()
		_start_playtest(options))
	dlg.canceled.connect(dlg.queue_free)
	dlg.custom_action.connect(func(action: StringName):
		if action != &"show_problems":
			return
		dlg.hide()
		dlg.queue_free()
		_open_tools_checked.call_deferred())
	add_child(dlg)
	dlg.popup_centered(Vector2i(640, 0))


## Tools > Deploy with the export checks already run.
func _open_tools_checked() -> void:
	var w := open_tools("Deploy")
	if w != null and w.has_method("run_checks"):
		w.run_checks()


## "From here": the next click on the map picks the tile to start the playtest on.
func playtest_from_picked_tile() -> void:
	if view.map_node == null:
		status.text = "Open a map first."
		return
	status.text = "Click the tile to start the playtest on. Esc or right click cancels."
	view.grab_focus()
	view.pick_callback = func(map_id: String, cell: Vector2i):
		_update_status()
		if map_id != "":
			playtest({"map": map_id, "position": [cell.x, cell.y]})


func _start_playtest(options: Dictionary) -> void:
	RPGJson.save_file(PLAYTEST_FILE, options)
	if plugin != null:
		if ensure_main_scene():
			status.text = "Set the project's main scene to the RPG game (%s)." % GAME_SCENE
		EditorInterface.play_main_scene()


func _validate_before_playtest() -> Array:
	# The same list as Tools > Deploy's export checks (validator + rule-system capabilities).
	var out := []
	for p in RPGExportCheck.problems(data, registry):
		if p.get("severity", "") == "error":
			out.append("%s: %s" % [p.get("file", ""), p.get("message", "")])
	return out
