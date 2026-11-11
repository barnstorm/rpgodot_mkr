class_name RPGEvent
extends RPGCharacter
## A map event created from the map's events file. While the game runs, the highest-numbered page
## whose conditions are all true is active; if none qualifies the event does nothing.
## A custom node can replace this one by implementing: event_id, map_id, cell, priority, blocks(),
## refresh(), trigger_action(), trigger_touch(by), start_autorun(), autorun_ready().

var event_id := ""
var map_id := ""
var data: Dictionary = {}
var page_index := -1
var page: Dictionary = {}
var trigger := ""
var erased := false
var move_type := "fixed"
var custom_route: Dictionary = {}
var _move_wait := 0.0
var _running_ticket: RPGScheduler.Ticket = null
var _route_running := false
var _locked_facing := ""
## What last started this event (debug inspector).
var last_trigger := ""


func setup(p_map: Node, p_data: Dictionary) -> void:
	data = p_data
	event_id = str(p_data.get("id", ""))
	map_id = p_map.map_id
	name = "Event_" + event_id
	var pos: Array = p_data.get("position", [0, 0])
	setup_on_map(p_map, Vector2i(int(pos[0]), int(pos[1])))
	var change: Dictionary = p_map.rpg.state.event_changes.get(map_id + "/" + event_id, {})
	if change.has("position"):
		place(Vector2i(int(change.position[0]), int(change.position[1])))
	if change.has("facing"):
		facing = change.facing
	# Older saves stored "erased" here by mistake; it is ignored (erasing is temporary).


func rpg() -> Node:
	return map.rpg


func best_page() -> int:
	if erased:
		return -1
	var pages: Array = data.get("pages", [])
	var state: RPGGameState = map.rpg.state
	for i in range(pages.size() - 1, -1, -1):
		var p: Dictionary = pages[i]
		if state.check_all(p.get("conditions", []), map_id, event_id):
			return i
	return -1


## Re-checks pages (called at a safe point after state changes).
func refresh() -> void:
	var idx := best_page()
	if idx != page_index:
		apply_page(idx)


func apply_page(idx: int) -> void:
	var old_trigger := trigger
	page_index = idx
	page = data.pages[idx] if idx >= 0 else {}
	var key := parallel_key()
	# A parallel interpreter is cancelled and restarted when its page changes.
	if old_trigger == "parallel":
		map.rpg.scheduler.stop_parallel(key, "page changed")
	if idx < 0:
		trigger = ""
		set_graphic(null)
		is_hidden = true
		priority = "below"
		_update_frame()
		return
	is_hidden = false
	var opts: Dictionary = page.get("options", {})
	walk_anim = bool(opts.get("walk_anim", true))
	step_anim = bool(opts.get("step_anim", false))
	direction_fix = false
	set_graphic(page.get("graphic"))
	direction_fix = bool(opts.get("direction_fix", false))
	through = bool(opts.get("through", false))
	priority = str(page.get("priority", "same"))
	trigger = str(page.get("trigger", "action_button"))
	var mvt: Dictionary = page.get("movement", {})
	move_type = str(mvt.get("type", "fixed"))
	speed = int(mvt.get("speed", 3))
	frequency = int(mvt.get("frequency", 3))
	custom_route = mvt.get("route", {})
	z_index = {"below": 1, "same": 2, "above": 4}.get(priority, 2)
	if trigger == "parallel":
		_start_parallel()


func parallel_key() -> String:
	return "event:%s:%s" % [map_id, event_id]


func _owner(idx: int) -> Dictionary:
	return {"kind": "map_event", "map": map_id, "event": event_id, "page": idx}


func _start_parallel() -> void:
	var idx := page_index
	map.rpg.scheduler.start_parallel(parallel_key(), page.get("commands", []), _owner(idx), self, func(): return is_inside_tree() and page_index == idx and not erased)


func _start_main() -> RPGScheduler.Ticket:
	var key := "event:%s:%s:%d" % [map_id, event_id, page_index]
	var t: RPGScheduler.Ticket = map.rpg.scheduler.request_main(key, page.get("commands", []), _owner(page_index), self)
	_running_ticket = t
	return t


func is_running() -> bool:
	return _running_ticket != null and not _running_ticket.done


## Action button: accepted only if this page is eligible at that moment and uses action_button.
func trigger_action() -> bool:
	if page_index < 0 or trigger != "action_button" or best_page() != page_index:
		return false
	if page.get("commands", []).is_empty():
		return false
	_lock_toward_player()
	_start_main()
	last_trigger = "action button"
	return true


## Touch: player_touch fires when the player touches it; event_touch also when it touches the player.
func trigger_touch(by_event: bool) -> bool:
	if page_index < 0 or best_page() != page_index:
		return false
	if by_event and trigger != "event_touch":
		return false
	if not by_event and trigger != "player_touch" and trigger != "event_touch":
		return false
	if page.get("commands", []).is_empty():
		return false
	if map.rpg.scheduler.is_main_busy():
		return false
	_lock_toward_player()
	_start_main()
	last_trigger = "event touched the player" if by_event else "player touch"
	return true


func autorun_ready() -> bool:
	return page_index >= 0 and trigger == "autorun" and not page.get("commands", []).is_empty() and not erased


func start_autorun() -> void:
	_start_main()
	last_trigger = "autorun"


func _lock_toward_player() -> void:
	if map.player != null and not direction_fix and graphic is Dictionary and graphic.has("sheet"):
		_locked_facing = facing
		var d := dir_toward(map.player.cell)
		if d != Vector2i.ZERO:
			turn(RPGMovement.dir_name(d))


func blocks() -> bool:
	return page_index >= 0 and super.blocks()


func erase_event() -> void:
	erased = true
	apply_page(-1)


func _process(delta: float) -> void:
	super._process(delta)
	if moving or page_index < 0 or erased:
		return
	if is_running():
		return
	if _locked_facing != "" and not is_running():
		_locked_facing = ""
	_autonomous(delta)


## Autonomous movement: random, approach the player, or a custom route.
func _autonomous(delta: float) -> void:
	if move_type == "fixed" or _route_running:
		return
	_move_wait -= delta
	if _move_wait > 0.0:
		return
	_move_wait = [0.0, 3.0, 2.0, 1.2, 0.6, 0.15][clampi(frequency, 1, 5)] * _randf_range(0.6, 1.4)
	match move_type:
		"random":
			step([Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP][_rand(4)])
		"approach":
			if map.player != null:
				var d := dir_toward(map.player.cell)
				if d != Vector2i.ZERO and not step(d):
					if _rand(2) == 0:
						step(Vector2i(d.y, d.x))
		"custom":
			_run_custom_route()


func _run_custom_route() -> void:
	_route_running = true
	var tok := RPGCancelToken.new()
	var r := custom_route.duplicate()
	r["repeat"] = false
	await run_route(r, tok)
	_route_running = false
	if not custom_route.get("repeat", true):
		move_type = "fixed"


func _on_step_finished() -> void:
	# An event walking into the player fires event_touch.
	pass


func _ready() -> void:
	step_blocked.connect(_on_blocked)


func _on_blocked(dir: Vector2i) -> void:
	if map.player != null and map.movement.normalize(cell + dir) == map.player.cell and trigger == "event_touch":
		trigger_touch(true)


func save_change() -> void:
	# Erase Event lasts until the map reloads, so "erased" is not persisted.
	map.rpg.state.event_changes[map_id + "/" + event_id] = {"position": [cell.x, cell.y], "facing": facing}


## For the debug screen's event inspector ("why doesn't my event start?"): the active page and,
## for every page, whether its conditions hold and which condition fails first.
func debug_info() -> Dictionary:
	var state: RPGGameState = map.rpg.state
	var pages_info := []
	var pages: Array = data.get("pages", [])
	for i in pages.size():
		var failing := ""
		for c in pages[i].get("conditions", []):
			if c is Dictionary and not state.check_condition(c, map_id, event_id):
				failing = _describe_condition(c)
				break
		pages_info.append({"index": i, "ok": failing == "", "failing": failing, "trigger": str(pages[i].get("trigger", "action_button"))})
	var running := ""
	var interp_state := ""
	if is_running() and _running_ticket.interpreter != null:
		var it: RPGInterpreter = _running_ticket.interpreter
		interp_state = RPGInterpreter.State.keys()[it.state]
		var w := it.where()
		running = "%s at %s" % [w.get("command", ""), w.get("path", "")]
	var blocked := ""
	if move_type != "fixed" and not moving and map.movement != null:
		var free := false
		for d in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			if map.movement.can_move(self, cell, d):
				free = true
				break
		if not free:
			blocked = "boxed in on all four sides"
	return {"id": event_id, "name": str(data.get("name", event_id)), "cell": cell, "page": page_index, "trigger": trigger,
		"priority": priority, "erased": erased, "running": is_running(), "running_command": running,
		"interpreter": interp_state, "move_type": move_type, "movement_blocked": blocked, "last_trigger": last_trigger, "pages": pages_info}


static func _describe_condition(c: Dictionary) -> String:
	match str(c.get("kind", "")):
		"switch": return "switch %s is %s" % [c.get("id", ""), "ON" if c.get("value", true) else "OFF"]
		"self_switch": return "self switch %s" % c.get("id", "")
		"variable": return "variable %s %s %s" % [c.get("id", ""), c.get("op", ">="), c.get("value", "")]
		"item": return "has item %s" % c.get("id", "")
		"actor": return "%s in party" % c.get("id", "")
		"gold": return "gold %s %s" % [c.get("op", ">="), c.get("value", "")]
	return JSON.stringify(c)
