@tool
extends RefCounted
## Development aid: drives the real editor through a maker's first steps and saves a screenshot
## of every screen and dialog into a folder, then quits. Started by plugin.gd when the
## RPG_EDITOR_SHOT environment variable names that folder.

var plugin: EditorPlugin
var screen: Node
var folder := ""
var tree: SceneTree
var base: Control


func run(p_plugin: EditorPlugin, p_screen: Node, p_folder: String) -> void:
	plugin = p_plugin
	screen = p_screen
	folder = p_folder
	base = EditorInterface.get_base_control()
	tree = base.get_tree()
	await _wait(3.0)
	for tab in ["RPG", "Database"]:
		EditorInterface.set_main_screen_editor(tab)
		await _wait(1.5)
		_save(base.get_viewport().get_texture().get_image(), "editor_real_%s" % tab.to_lower())
	if screen == null:
		tree.quit()
		return
	EditorInterface.set_main_screen_editor("RPG")
	screen.open_map("town")
	await _wait(0.5)
	# Event mode on the town map.
	screen._select_mode("event")
	await _wait(0.6)
	_save(base.get_viewport().get_texture().get_image(), "editor_real_event_mode")
	# Event window, then the command picker and a command's form from inside it.
	var before := _windows(base)
	screen.edit_event("elder")
	await _wait(1.5)
	var ev_win := _new_window(base, before)
	_shot(ev_win, "editor_real_event")
	if ev_win != null and "_cmd_list" in ev_win and ev_win._cmd_list != null:
		var cl: Node = ev_win._cmd_list
		cl.select_lines(cl.get_commands(), [0])
		var b2 := _windows(ev_win)
		cl.edit_selected()
		await _wait(1.0)
		var form_win := _new_window(ev_win, b2)
		_shot(form_win, "editor_real_command_form")
		_close(form_win)
		cl.new_command()
		await _wait(1.0)
		var picker: Window = cl._picker if "_picker" in cl else null
		_shot(picker, "editor_real_command_picker")
		if picker != null:
			picker.hide()
	_close(ev_win)
	# Map properties.
	before = _windows(base) + _windows(screen)
	var props := RPGMapPropertiesDialog.open_for(screen, screen.data, "town", false, func(_a = null, _b = null, _c = null): pass)
	await _wait(1.0)
	_shot(props, "editor_real_map_properties")
	_close(props)
	# Quick event.
	var names: Array = RPGQuickEvents.template_names()
	if not names.is_empty():
		var qd := RPGQuickEventDialog.open_for("town", Vector2i(3, 3), str(names[0]), screen.data, func(_a = null): pass)
		await _wait(1.0)
		_shot(qd, "editor_real_quick_event")
		_close(qd)
	# Tools window tabs.
	for tab in ["Event search", "Sound test", "Resources", "Extensions", "Deploy"]:
		before = _windows(screen)
		screen.open_tools(tab)
		await _wait(1.0)
		var tw := _new_window(screen, before)
		_shot(tw, "editor_real_tools_%s" % tab.to_lower().replace(" ", "_"))
		_close(tw)
	# Database tabs.
	EditorInterface.set_main_screen_editor("Database")
	await _wait(0.8)
	var db: Node = EditorInterface.get_editor_main_screen().get_node_or_null("Database")
	if db != null and "_tabs" in db:
		for i in db._tabs.get_tab_count():
			var t: String = db._tabs.get_tab_title(i)
			if t in ["Classes", "Skills", "Enemies", "Enemy groups", "Common events", "System"]:
				db._tabs.current_tab = i
				await _wait(0.8)
				_save(base.get_viewport().get_texture().get_image(), "editor_real_db_%s" % t.to_lower().replace(" ", "_"))
	tree.quit()


func _wait(s: float) -> void:
	await tree.create_timer(s).timeout


func _save(img: Image, name: String) -> void:
	if img != null:
		img.save_png(folder.path_join(name + ".png"))


func _windows(n: Node) -> Array:
	return n.find_children("*", "Window", true, false)


func _new_window(n: Node, before: Array) -> Window:
	for w in _windows(n):
		if w not in before and w.visible:
			return w
	return null


func _shot(w: Window, name: String) -> void:
	if w == null:
		push_warning("RPG walkthrough: no window for %s" % name)
		return
	_save(w.get_texture().get_image(), name)


func _close(w: Window) -> void:
	if w != null and is_instance_valid(w):
		w.hide()
		w.queue_free()
