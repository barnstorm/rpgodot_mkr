extends SceneTree
## Shows the RPG main screen (map editor) outside the Godot editor and saves screenshots, so the
## layout can be checked headless-ish. Undo uses a local UndoRedo here.
##   godot --path . --script res://tools/editor_preview.gd -- --map=town --mode=event --out=name  [--tools=Deploy]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	root.size = Vector2i(1400, 860)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var screen := RPGMainScreen.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.setup(null)
	bg.add_child(screen)
	await process_frame
	await process_frame
	screen.open_map(str(args.get("map", "town")))
	screen._select_mode(str(args.get("mode", "map")))
	if args.has("overlay"):
		screen.view.show_passability = true
	screen.view.set_zoom(float(args.get("zoom", "2")))
	screen.view.world.position = Vector2(10, 10)
	screen.view.hover_cell = Vector2i(10, 10)
	screen.view.overlay.queue_redraw()
	screen._update_status()
	if args.has("welcome"):
		screen._show_welcome(true)
	if args.has("tools"):
		screen.open_tools(str(args.tools))
		await process_frame
		for w in screen.get_children():
			if w is RPGToolsWindow:
				if str(args.tools) == "Event search":
					w._search_ref.text = "house_key"
					w.run_search()
				elif str(args.tools) == "Deploy":
					var page: Control = w.tabs.get_current_tab_control()
					(page.get_child(page.get_child_count() - 1) as Button).pressed.emit()
				elif str(args.tools) == "Extensions" and args.has("ext"):
					w.show_extension_settings(str(args.ext))  # --ext=<id>: its settings form
	if args.has("tiles"):  # --tiles=<mode>[:<tab>], e.g. --tiles=passage4:Lower
		var parts := str(args.tiles).split(":")
		var dlg := screen.open_tile_settings()
		await process_frame
		dlg.set_edit_mode(parts[0])
		if parts.size() > 1:
			for t in dlg.TABS:
				if t[1] == parts[1]:
					dlg.show_source(t[0])
		# Unsaved demo edits so overridden tiles show (nothing is written).
		dlg.settings.toggle_direction("lower_0", 8)
		dlg.settings.set_terrain("lower_1", 3)
		dlg.settings.set_passage("terrain_1", 0)
		dlg.selected_key = "lower_0"
		dlg._refresh()
	for i in 20:
		await process_frame
	var out := "res://tools/shots/%s.png" % str(args.get("out", "editor"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out))
	print("saved ", out)
	quit(0)
