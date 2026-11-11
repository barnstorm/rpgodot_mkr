class_name RPGGame
extends Node2D
## The game root (main scene). Shows the title, starts a new game, and performs map transfers
## as one complete step: check destination, stop the old map's tasks, fade out, load the new
## scene and events, place the player and followers, refresh pages, start music, give control back.
## If any step fails, the transfer returns an error and the previous map stays playable.

const PLAYTEST_FILE := "user://rpg_playtest.json"

var rpg: Node
var world: Node2D
var map: RPGMap
var player: RPGPlayer
var transferring := false
## When false (tests, battle test harnesses) the title screen is not shown on _ready.
var auto_start := true
## Set after a transfer when System > Auto-save is on; the save happens at the next safe point.
var autosave_pending := false
## Why the pending autosave was asked for ("transfer", "battle", "event", ...).
var autosave_reason := "transfer"
## Extension layers (overlay_layer): space -> Node.
var _overlays: Dictionary = {}


func _ready() -> void:
	if rpg == null:
		rpg = get_node("/root/RPG")
	rpg.game = self
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	if not rpg.is_booted:
		rpg.boot()
	_apply_window_title()
	# Player options (volume, text speed, always dash) saved by the options screen.
	var opts_path: String = rpg.ui.scene_path("options") if rpg.ui else ""
	if opts_path.ends_with(".gd") and ResourceLoader.exists(opts_path):
		var os_script: Script = load(opts_path)
		if os_script.has_method("apply_saved"):
			os_script.apply_saved(rpg)
	apply_display()
	if is_inside_tree():
		get_window().size_changed.connect(apply_display)
		if auto_start:
			get_tree().auto_accept_quit = false  # see _notification: the close button quits cleanly
	if not auto_start:
		return
	var playtest := start_request(OS.get_cmdline_user_args())
	if playtest.has("smoke"):
		_smoke_test.call_deferred()
		return
	if playtest.has("battle_test"):
		_battle_test.call_deferred(str(playtest.battle_test), playtest.get("party", []))
	elif playtest.has("map"):
		var pos: Variant = playtest.get("position")
		_start_from.call_deferred(str(playtest.map), pos, playtest.get("test_commands", []))
	else:
		show_title.call_deferred()


## `--rpg-smoke` (for CI and exported builds): starts a new game without the title screen, runs
## the start map until its autorun events finish, prints one result line and quits (0 = ok).
func _smoke_test() -> void:
	var failures := []
	if not rpg.data.load_errors.is_empty():
		failures.append("data: %s" % str(rpg.data.load_errors))
	rpg.ui.auto_advance = true
	await new_game()
	for i in 600:
		await get_tree().process_frame
		if not rpg.scheduler.is_main_busy() and not transferring:
			break
	if map == null:
		failures.append("no map loaded")
	if player == null or not player.is_inside_tree():
		failures.append("no player")
	if rpg.scheduler.is_main_busy():
		failures.append("the start map's events did not finish")
	var line := "RPG_SMOKE %s map=%s events=%d commands=%d" % ["OK" if failures.is_empty() else "FAIL", map.map_id if map else "-", map.events.size() if map else 0, rpg.registry.commands.size() if rpg.registry else 0]
	if not failures.is_empty():
		line += " problems=" + "; ".join(PackedStringArray(failures))
	print(line)
	quit_game(0 if failures.is_empty() else 1)


## How this launch should start, from the command line and the editor's playtest file:
## {smoke: true}, {battle_test: troop, party?}, {map, position, test_commands?} or {} (title).
## The editor's start hooks (--rpg-start, --rpg-battle-test, user://rpg_playtest.json) only work
## in playtest builds (rpg.playtest, a debug build): a shipped game ignores them, as RPG Maker's
## test modes only exist when launched from the editor. --rpg-smoke (CI) works everywhere.
func start_request(args: PackedStringArray) -> Dictionary:
	if args.has("--rpg-smoke"):
		return {"smoke": true}
	if not rpg.playtest:
		return {}
	var playtest := _read_playtest()
	for arg in args:
		if arg.begins_with("--rpg-start="):
			var parts := arg.substr(12).split(":")
			playtest = {"map": parts[0], "position": [int(parts[1]), int(parts[2])] if parts.size() >= 3 else null}
		elif arg.begins_with("--rpg-battle-test="):
			playtest = {"battle_test": arg.substr(18)}
	return playtest


func _read_playtest() -> Dictionary:
	if not FileAccess.file_exists(PLAYTEST_FILE):
		return {}
	var d: Variant = RPGJson.load_or(PLAYTEST_FILE, {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYTEST_FILE))
	return d if d is Dictionary else {}


## Quits after letting go of every sound and cached asset, so a normal quit logs no leaked
## instances or resources (the audio server drops stopped playbacks on its next mix steps).
func quit_game(code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	if rpg != null and rpg.has_signal("quitting"):
		rpg.quitting.emit()
	_stop_routes("quit")
	if rpg != null and rpg.has_method("release_caches"):
		rpg.release_caches()
	if is_inside_tree():
		# Nothing starts a new sound while the old ones are let go (stopped first: a paused
		# player keeps its playback).
		get_tree().paused = true
		# Wall-clock time: a frame delta can be large right after loading, ending a timer at once.
		var until := Time.get_ticks_msec() + QUIT_AUDIO_MS
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
	get_tree().quit(code)


var _quitting := false


## Cancels the move routes of the map's events and the player (their own tokens), so none is
## left waiting on a timer once the map is freed.
func _stop_routes(why: String) -> void:
	if map != null and is_instance_valid(map) and map.has_method("stop_routes"):
		map.stop_routes(why)
	if player != null and is_instance_valid(player) and player.has_method("cancel_route"):
		player.cancel_route(why)
## How long quit_game gives the audio server to drop the stopped playbacks.
const QUIT_AUDIO_MS := 150


## The window's close button quits the same clean way.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree() and not get_tree().auto_accept_quit:
		quit_game()


## The game window is named after the game (System > Game title), not the Godot project.
func _apply_window_title() -> void:
	if rpg.data == null or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var t := str(rpg.data.system.get("title", ""))
	if t != "":
		get_window().title = t + (" (playtest)" if rpg.playtest else "")


func show_title() -> void:
	rpg.audio.stop_all()
	var node: Node = rpg.ui.open_scene(rpg.ui.scene_path("title"))
	if node == null:
		new_game()
		return
	rpg.title_shown.emit()
	var choice: Variant = await node.chosen
	rpg.ui.close_scene(node)
	match str(choice):
		"new_game":
			new_game()
		"continue":
			var screen: Node = rpg.ui.open_scene(rpg.ui.scene_path("save"))
			if screen and screen.has_method("setup"):
				screen.setup("load")
				await screen.closed
			if map == null:
				show_title()
		"quit":
			quit_game()
		_:
			new_game()


func new_game() -> void:
	rpg.state.new_game()
	_started_new_game()
	_make_player()
	var start: Dictionary = rpg.data.system.get("start", {})
	var m: String = start.get("map", "")
	if m == "" and not rpg.data.maps.is_empty():
		m = rpg.data.maps.keys()[0]
	var pos: Array = start.get("position", [0, 0])
	var r: RPGResult = await transfer(m, Vector2i(int(pos[0]), int(pos[1])), str(start.get("facing", "down")), "none")
	if r.is_error():
		rpg.ui.show_error(r.message)


## Playtest "from here". `test_commands` (the event editor's Test button) run once the map is up.
## Without a cell: the System start cell on the start map, else the free cell nearest the map's
## middle. A start that fails shows why and goes to the title instead of a dead grey screen.
func _start_from(map_id: String, pos: Variant, test_commands: Array = []) -> void:
	rpg.state.new_game()
	_started_new_game()
	_make_player()
	var r: RPGResult
	if not rpg.data.maps.has(map_id):
		r = RPGResult.error("Start: map '%s' does not exist." % map_id)
	else:
		var p := start_cell(map_id, pos)
		var size: Vector2i = rpg.data.map_size(map_id)
		var fallback := 0 if pos is Array else maxi(size.x, size.y)
		r = await transfer(map_id, p, "down", "none", fallback)
		if r.is_ok() and not (pos is Array) and map != null and player != null and map.movement.passage(player.cell) == 0:
			var free: Vector2i = map.movement.nearest_free(player.cell, player, fallback)
			if free != Vector2i(-1, -1):
				map.add_player(player, free, "down")
	if r.is_error():
		push_error("RPG: " + r.message)
		rpg.ui.show_error(r.message)
		if map == null:
			show_title()
	elif not test_commands.is_empty():
		var t: RPGResult = await rpg.run_commands(test_commands, {"kind": "api", "id": "event_test"})
		if t.is_error():
			rpg.ui.show_error(t.message)


## The cell a playtest start uses: the given [x, y]; without one, the System start cell when it is
## on that map, else the middle of the map (the transfer then finds the nearest free cell).
func start_cell(map_id: String, pos: Variant) -> Vector2i:
	if pos is Array and pos.size() >= 2:
		return Vector2i(int(pos[0]), int(pos[1]))
	var start: Dictionary = rpg.data.system.get("start", {})
	if str(start.get("map", "")) == map_id:
		var sp: Array = start.get("position", [0, 0])
		if sp.size() >= 2 and rpg.data.cell_in_map(map_id, sp):
			return Vector2i(int(sp[0]), int(sp[1]))
	var s: Vector2i = rpg.data.map_size(map_id)
	return Vector2i(s.x / 2, s.y / 2)


## Battle test (Database > Enemy groups, or Game > Battle test). `party`: [{actor, level}] chosen in
## the editor (RPG Maker's battle test setup); empty = the starting party.
func _battle_test(troop: String, party: Array = []) -> void:
	rpg.state.new_game()
	setup_test_party(party)
	_started_new_game()
	_make_player()
	var r: RPGResult = await rpg.run_commands([{"type": "battle", "troop": troop, "can_escape": true, "can_lose": true}], {"kind": "api", "id": "battle_test"})
	quit_game()


## Tells extensions a new game began (fresh state, no map yet).
func _started_new_game() -> void:
	_first_map_after_start = true
	if rpg.has_method("reset_level_tracking"):
		rpg.reset_level_tracking()
	if rpg.has_signal("new_game_started"):
		rpg.new_game_started.emit()


## True until the first map of a new game or a load is entered (extensions use
## is_first_map() to skip, for example, an autosave on the start map).
var _first_map_after_start := false


func is_first_map() -> bool:
	return _first_map_after_start


func setup_test_party(party: Array) -> void:
	var members := party.filter(func(m): return m is Dictionary and rpg.data.has_record("actors", str(m.get("actor", ""))))
	if members.is_empty():
		return
	var st: RPGGameState = rpg.state
	for id in st.party.duplicate():
		st.remove_actor(id)
	st.actors.clear()
	for m in members:
		var id := str(m.actor)
		if st.rules != null and st.rules.has_method("new_actor_battler"):
			st.actors[id] = st.rules.new_actor_battler(id, clampi(int(m.get("level", 1)), 1, 99))
		st.add_actor(id)


func _make_player() -> void:
	if player != null:
		for f in player.followers:
			f.queue_free()
		player.queue_free()
	player = RPGPlayer.new()
	_apply_leader_graphic()
	for i in range(1, 4):
		var f := RPGCharacter.new()
		f.name = "Follower%d" % i
		f.z_index = 2
		f.through = true
		f.priority = "below"
		player.followers.append(f)


func _apply_leader_graphic() -> void:
	if player == null:
		return
	var party: Array = rpg.state.party
	apply_transparency()
	if map != null and rpg.state.riding != "":
		# Riding: the player is drawn as the vehicle (after a load or transfer too). A player not
		# yet placed on a map is boarded when the transfer adds it.
		if player.vehicle != rpg.state.riding and player.map != null:
			player._board(rpg.state.riding)
		return
	if map != null:
		var g := _actor_graphic(party[0] if party.size() > 0 else "")
		player.set_graphic(g)
		for i in player.followers.size():
			var f: RPGCharacter = player.followers[i]
			var idx := i + 1
			f.visible = rpg.state.followers_visible and idx < party.size()
			if f.visible:
				f.set_graphic(_actor_graphic(party[idx]))


func _actor_graphic(actor_id: String) -> Variant:
	if actor_id == "":
		return null
	# The record's charset, or the one "Change Actor Graphic" set.
	var look: Dictionary = rpg.state.actor_look(actor_id)
	if str(look.get("charset", "")) != "":
		return {"sheet": str(look.charset), "index": int(look.get("charset_index", 0))}
	return null


## "Change Transparency": hides the player and followers (they still move and trigger events).
func apply_transparency() -> void:
	if player == null:
		return
	var hide: bool = rpg.state.player_transparent
	for ch in [player] + player.followers:
		if ch.transparent != hide:
			ch.transparent = hide
			ch._update_frame()


func refresh_party_graphics() -> void:
	_apply_leader_graphic()


## Map transfer (spec "Transfers"). Returns RPGResult.
## `caller` is the interpreter running the Transfer Player command, if any (see cancel_owned).
func transfer(map_id: String, pos: Vector2i, facing := "keep", fade := "black", fallback_distance := 0, caller: RPGInterpreter = null) -> RPGResult:
	# 1. Check the destination.
	if not rpg.data.maps.has(map_id):
		return RPGResult.error("Transfer: map '%s' does not exist." % map_id)
	if not rpg.data.cell_in_map(map_id, [pos.x, pos.y]):
		var props: Dictionary = rpg.data.map_props(map_id)
		var loops: bool = str(props.get("scroll", "none")) != "none"
		if not loops:
			return RPGResult.error("Transfer: cell %s is outside map '%s'." % [pos, map_id])
		var s: Vector2i = rpg.data.map_size(map_id)
		pos = Vector2i(posmod(pos.x, s.x), posmod(pos.y, s.y))
	var scene_path: String = rpg.data.map_scene_path(map_id)
	var packed: PackedScene = null
	if ResourceLoader.exists(scene_path):
		packed = load(scene_path)
		if packed == null:
			return RPGResult.error("Transfer: map scene '%s' failed to load." % scene_path)
	if transferring:
		return RPGResult.error("Transfer: another transfer is in progress.")
	transferring = true
	rpg.scheduler.lock_input("transfer")
	var old_map := map
	var final_facing := facing if facing != "keep" else (player.facing if player else "down")
	# 2. Stop tasks owned by the current map.
	if old_map != null:
		await old_map.shutdown(caller)
	# 3. Fade out.
	if fade == "black" or fade == "white":
		await rpg.screen.fade_out(0.25, Color.WHITE if fade == "white" else Color.BLACK)
	# 4. Load the destination scene and events.
	var new_map: RPGMap
	if packed != null:
		var inst := packed.instantiate()
		if not (inst is RPGMap):
			inst.queue_free()
			_restore(old_map, fade)
			return RPGResult.error("Transfer: scene '%s' is not an RPG map (root needs rpg_map.gd)." % scene_path)
		new_map = inst
	else:
		new_map = RPGMap.new()
	new_map.map_id = map_id
	new_map.name = "Map_" + map_id
	if old_map != null:
		world.remove_child(old_map)
	world.add_child(new_map)
	new_map.start(rpg)
	# 5. Place the player and followers (a transfer onto an occupied cell fails unless it opts in).
	if player == null:
		_make_player()
	var target := pos
	if new_map.movement.is_occupied(pos, player):
		if fallback_distance > 0:
			target = new_map.movement.nearest_free(pos, player, fallback_distance)
		else:
			target = Vector2i(-1, -1)
	if target == Vector2i(-1, -1):
		# Stop the destination's parallel tasks before freeing it, so none is left behind.
		await new_map.shutdown()
		world.remove_child(new_map)
		new_map.queue_free()
		if old_map != null:
			world.add_child(old_map)
			old_map.add_player(player, player.cell, player.facing)
			old_map.resume()
		_restore(old_map, fade)
		return RPGResult.error("Transfer: cell %s on map '%s' is occupied." % [pos, map_id])
	if old_map != null:
		rpg.map_left.emit(old_map.map_id)
	map = new_map
	# Riding a vehicle through a transfer takes the vehicle along.
	if rpg.state.riding != "":
		load("res://addons/rpg/runtime/rpg_vehicles.gd").park(rpg.state, rpg.state.riding, map_id, target, final_facing)
	new_map.add_player(player, target, final_facing)
	_apply_leader_graphic()
	_sync_windowskin()
	if old_map != null:
		old_map.queue_free()
	# 6. Refresh pages.
	new_map.refresh_pages()
	# 7. Start the map's music.
	var props2: Dictionary = new_map.props
	var vehicle_music: bool = rpg.state.riding != "" and player.has_meta("map_bgm")
	if props2.get("music") is Dictionary and str(props2.music.get("file", "")) == "" and not vehicle_music:
		rpg.audio.stop_bgm()
	elif props2.get("music") is Dictionary and str(props2.music.get("file", "")) != "":
		if vehicle_music:
			# Keep the vehicle's music; the new map's music plays when the player gets off.
			player.set_meta("map_bgm", props2.music)
		else:
			rpg.audio.play_bgm(props2.music)
	if props2.get("bgs") is Dictionary:
		rpg.audio.play_bgs(props2.bgs)
	if fade == "black" or fade == "white" or rpg.screen.is_faded:
		if not rpg.screen.get_meta("hold_fade", false):
			await rpg.screen.fade_in(0.25)
	# 8. Give control back.
	transferring = false
	rpg.scheduler.unlock_input("transfer")
	rpg.request_refresh()
	_show_map_name(props2)
	if bool(rpg.data.system.get("auto_save", false)):
		request_autosave("transfer")
	rpg.map_entered.emit(map_id)
	_first_map_after_start = false
	return RPGResult.ok()


## Asks for an autosave at the next safe point (no event running, no transfer, no screen that
## blocks saving). `reason` is passed to RPG.autosaved.
func request_autosave(reason := "event") -> void:
	autosave_pending = true
	autosave_reason = reason


# --- extension layers ----------------------------------------------------------------------------

## A layer extensions draw on (RPG.map_overlay_layer): "map" (Node2D in map coordinates, above
## the characters), "screen" (CanvasLayer under the UI) or "hud" (a 320x240 Control above the UI,
## scaled like it). Made on first use; kept across transfers.
func overlay_layer(space := "map") -> Node:
	var n: Node = _overlays.get(space)
	if n != null and is_instance_valid(n):
		return n
	match space:
		"map":
			var n2 := Node2D.new()
			n2.name = "MapOverlay"
			n2.z_index = 100
			world.add_child(n2)
			n = n2
		"screen":
			var cl := CanvasLayer.new()
			cl.name = "ScreenOverlay"
			cl.layer = 10
			add_child(cl)
			n = cl
		"hud":
			var hl := CanvasLayer.new()
			hl.name = "HudOverlay"
			hl.layer = 21
			add_child(hl)
			var c := Control.new()
			c.name = "Root"
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.size = Vector2(320, 240)
			hl.add_child(c)
			_sync_hud(hl)
			_overlays["hud_layer"] = hl
			n = c
		_:
			push_warning("RPG: unknown overlay space '%s' (map, screen or hud)." % space)
			return null
	_overlays[space] = n
	return n


func _sync_hud(hl: CanvasLayer) -> void:
	if rpg != null and rpg.ui != null and hl.transform != rpg.ui.transform:
		hl.transform = rpg.ui.transform


## Adds `node` to a character ("player", "follower:N", or an event ID on this map).
func attach_to_character(char_id: String, node: Node) -> bool:
	var ch: Node = null
	if char_id == "player":
		ch = player
	elif char_id.begins_with("follower:") and player != null:
		var i := char_id.get_slice(":", 1).to_int() - 1
		if i >= 0 and i < player.followers.size():
			ch = player.followers[i]
	elif map != null:
		ch = map.get_event(char_id)
	if ch == null or not is_instance_valid(ch):
		return false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	ch.add_child(node)
	return true


## Re-applies the "Change Window Skin" choice after a new game or a load.
func _sync_windowskin() -> void:
	var ui: Node = rpg.ui
	if ui != null and ui.has_method("apply_windowskin") and str(ui.get_meta("rpg_skin", "")) != rpg.state.windowskin:
		ui.apply_windowskin(rpg.state.windowskin)


func _restore(old_map: RPGMap, fade: String) -> void:
	if old_map != null and old_map.get_parent() == null:
		world.add_child(old_map)
	if fade != "none" and rpg.screen.is_faded:
		rpg.screen.fade_in(0.2)
	transferring = false
	rpg.scheduler.unlock_input("transfer")


func _show_map_name(props: Dictionary) -> void:
	var dn: String = props.get("display_name", "")
	if dn == "" or not rpg.state.map_name_display:
		return
	var lab := Label.new()
	lab.text = dn
	lab.add_theme_font_size_override("font_size", 11)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a click there still reaches the map
	pc.add_child(lab)
	pc.position = Vector2(8, 8)
	rpg.ui.root.add_child(pc)
	var t := pc.create_tween()
	t.tween_interval(2.0)
	t.tween_property(pc, "modulate:a", 0.0, 0.5)
	t.tween_callback(pc.queue_free)


func open_menu() -> void:
	if rpg.ui.scene_open() or not rpg.data.system.get("menu_enabled", true) or not bool(rpg.state.access.get("menu", true)):
		return
	var node: Node = rpg.ui.open_scene(rpg.ui.scene_path("menu"))
	if node != null and node.has_signal("closed"):
		rpg.scheduler.lock_input("menu")
		rpg.menu_opened.emit(node)
		await node.closed
		rpg.scheduler.unlock_input("menu")
		rpg.ui.close_scene(node)
		refresh_party_graphics()
		rpg.menu_closed.emit()


func open_debug() -> void:
	if rpg.ui.scene_open():
		return
	var node: Node = rpg.ui.open_scene(rpg.ui.scene_path("debug"))
	if node != null and node.has_signal("closed"):
		rpg.scheduler.lock_input("debug")
		await node.closed
		rpg.scheduler.unlock_input("debug")
		rpg.ui.close_scene(node)


## RPG Maker's F12: reset to the title screen (a quick restart while testing). It also works
## from a start that never reached a map, but not on the title (no map, a screen open).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12 and not transferring and not (map == null and rpg.ui.scene_open()):
		get_viewport().set_input_as_handled()
		return_to_title()


## Alt+Enter and F4 switch between a window and full screen (MV's F4), and remember it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var alt_enter: bool = event.alt_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
	if event.keycode == KEY_F4 or alt_enter:
		get_viewport().set_input_as_handled()
		if alt_enter and InputMap.has_action("rpg_ok"):
			Input.action_release("rpg_ok")  # Enter is also OK; this press only toggles the window
		toggle_fullscreen()


func toggle_fullscreen() -> void:
	var opts := _options()
	opts["fullscreen"] = not bool(opts.get("fullscreen", false))
	var os_script := _options_script()
	if os_script != null and os_script.has_method("save_options"):
		os_script.save_options(opts)
	apply_display(opts)


func _options_script() -> Script:
	var opts_path: String = rpg.ui.scene_path("options") if rpg.ui else ""
	if opts_path.ends_with(".gd") and ResourceLoader.exists(opts_path):
		return load(opts_path)
	return null


func _options() -> Dictionary:
	var os_script := _options_script()
	if os_script != null and os_script.has_method("load_options"):
		return os_script.load_options()
	return {}


## Applies the window options: full screen, and the scaling ("fit": the largest size that keeps
## the aspect, black bars around it; "pixel": whole multiples only). A window smaller than the
## game screen always fits, so menus are never cut off.
func apply_display(opts: Variant = null) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var o: Dictionary = opts if opts is Dictionary else _options()
	var win := get_window()
	var want_full := bool(o.get("fullscreen", false))
	var is_full := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	if want_full != is_full:
		win.mode = Window.MODE_FULLSCREEN if want_full else Window.MODE_WINDOWED
	var base := Vector2(win.content_scale_size)
	if base.x <= 0 or base.y <= 0:
		base = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 320), ProjectSettings.get_setting("display/window/size/viewport_height", 240))
	var small := win.size.x < base.x or win.size.y < base.y
	var pixel := str(o.get("scale", "fit")) == "pixel" and not small
	var stretch := Window.CONTENT_SCALE_STRETCH_INTEGER if pixel else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if win.content_scale_stretch != stretch:
		win.content_scale_stretch = stretch


func _process(_delta: float) -> void:
	var hl: Variant = _overlays.get("hud_layer")
	if hl is CanvasLayer and is_instance_valid(hl):
		_sync_hud(hl)
	if autosave_pending and map != null and rpg.saves.save_blocked_reason() == "":
		autosave_pending = false
		rpg.saves.autosave(autosave_reason)
	if map != null:
		rpg.state.play_time += _delta
	# The save screen asked for by an event opens once the main event has finished (safe point).
	if rpg.ui.pending_save_screen and not rpg.scheduler.is_main_busy() and not rpg.ui.scene_open() and not transferring:
		rpg.ui.pending_save_screen = false
		var node: Node = rpg.ui.open_scene(rpg.ui.scene_path("save"))
		if node != null and node.has_method("setup"):
			node.setup("save")
			rpg.scheduler.lock_input("save")
			await node.closed
			rpg.scheduler.unlock_input("save")
			rpg.ui.close_scene(node)
	if Input.is_action_just_pressed("rpg_overlay") and rpg.playtest and map != null:
		_toggle_overlay()


func _toggle_overlay() -> void:
	var ov := map.get_node_or_null("DebugOverlay")
	if ov != null:
		ov.queue_free()
		return
	var o: Node2D = load("res://addons/rpg/runtime/rpg_debug_overlay.gd").new()
	o.name = "DebugOverlay"
	o.map = map
	map.add_child(o)


## Ends the current game and goes back to the title screen.
func return_to_title() -> void:
	await rpg.scheduler.cancel_all("return to title")
	rpg.ui.close_all()
	rpg.screen.clear_all()
	_stop_routes("return to title")
	if map != null:
		map.queue_free()
		map = null
	rpg.screen.set_faded(false)
	show_title()


func game_over() -> void:
	await rpg.scheduler.cancel_all("game over")
	rpg.audio.stop_all()
	var node: Node = rpg.ui.open_scene(rpg.ui.scene_path("game_over"))
	if node != null and node.has_signal("closed"):
		await node.closed
		rpg.ui.close_scene(node)
	return_to_title()


const LOAD_FALLBACK_DISTANCE := 64

## Loads a game from save data (already validated by the save service).
func load_from(save: Dictionary) -> RPGResult:
	await rpg.scheduler.cancel_all("load game")
	rpg.ui.close_all()
	rpg.screen.clear_all()
	_make_player()
	_first_map_after_start = true
	if rpg.has_method("reset_level_tracking"):
		rpg.reset_level_tracking()
	var m: Dictionary = save.get("map", {})
	var pos: Array = m.get("position", [0, 0])
	var old := map
	# An NPC rebuilt at its start cell may now stand where the player saved: use the nearest
	# free cell instead of failing half-way through a load.
	var r: RPGResult = await transfer(str(m.get("id", "")), Vector2i(int(pos[0]), int(pos[1])), str(m.get("facing", "down")), "none", LOAD_FALLBACK_DISTANCE)
	return r
