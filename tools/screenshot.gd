extends SceneTree
## Runs the game (windowed, real rendering) and saves screenshots. Used to check visuals.
##   godot --path . --script res://tools/screenshot.gd -- --out=tools/shots/town.png --map=town --pos=14,12
##         [--script=keys] where keys is a comma list of steps: wait:1.5, press:rpg_ok, hold:rpg_right:0.6, shot:name
## --battle=troop starts a battle test. Without --map or --battle the title screen is shown.

var out_dir := "res://tools/shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if args.has("map"):
		var p: PackedStringArray = str(args.get("pos", "0,0")).split(",")
		RPGJson.save_file("user://rpg_playtest.json", {"map": args.map, "position": [int(p[0]), int(p[1])]})
	elif args.has("battle"):
		RPGJson.save_file("user://rpg_playtest.json", {"battle_test": args.battle})
	var game: Node = load("res://addons/rpg/runtime/game.tscn").instantiate()
	root.add_child(game)
	var steps: PackedStringArray = str(args.get("script", "wait:1.5,shot:" + str(args.get("name", "shot")))).split(",")
	for s in steps:
		var parts := s.split(":")
		match parts[0]:
			"wait":
				await create_timer(float(parts[1])).timeout
			"press":
				_action(parts[1], true)
				await process_frame
				await process_frame
				_action(parts[1], false)
				await process_frame
			"hold":
				_action(parts[1], true)
				await create_timer(float(parts[2])).timeout
				_action(parts[1], false)
			"shot":
				await process_frame
				var img := root.get_texture().get_image()
				var path := out_dir.path_join(parts[1] + ".png")
				img.save_png(ProjectSettings.globalize_path(path))
				print("saved ", path)
	quit(0)


## Sends a real input event (menus read events; movement polls the action state, which this also sets).
func _action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
