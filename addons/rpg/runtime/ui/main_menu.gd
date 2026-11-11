extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default main menu: Items, Skills, Equip, Status, Options, Save and Game End, with the party
## window (faces, level, states, HP/SP gauges) and a gold and play-time window.
##   Items  - heal or cure with usable items (rules.use_item); key items on their own tab
##   Skills - field skills that target allies (rules.apply_action, the cost is paid once)
##   Equip  - change equipment from the inventory, previewing stats (rules.effective_stat)
##   Status - stats, experience and experience to the next level, equipment
##   Save   - the save screen; when saving is blocked the reason is shown instead
## Emits closed when the player leaves (the host removes the scene).
##
## The command list is data (RPGExtensionHost.menu_layout): the built-ins in COMMANDS, entries
## from extension manifests ("menu_entries") and the project.json "menu" block {order, hidden,
## entries, skip_single_actor}. An extra entry runs an extension method, opens a scene or runs
## a common event (the menu closes first). With skip_single_actor, Skills, Equip and Status
## open straight away for a party of one.

signal closed()

## Set when the last item or skill use reserved a Common Event (the menu then closes).
var _reserved_ce := false

const COMMANDS := ["item", "skill", "equip", "status", "options", "save", "game_end"]
## Command rows shown at most (more scroll).
const MAX_COMMAND_ROWS := 12
const COMMAND_FALLBACK := {"item": "Items", "skill": "Skills", "equip": "Equip", "status": "Status", "options": "Options", "save": "Save", "game_end": "Game End"}
const HP_COLOUR := Color(1.0, 0.62, 0.25)
const SP_COLOUR := Color(0.38, 0.68, 1.0)
const FIELD_OCCASIONS := ["always", "menu", "field"]
const ALLY_SCOPES := ["one_ally", "all_allies", "one_dead_ally", "all_dead_allies", "self", "user"]

var mode := "command"
var pending := ""                # skill, equip or status while choosing an actor
var commands: Control
var party_win: Panel
var party_rows: Control
var party_cursor: Panel
var actor_index := 0
var gold_label: Label
var time_label: Label
var view: Control                # the open sub-view (items, skills, equip, status, game end)
var notice: Panel

# items / skills
var item_tab := "items"
var list: Control
var help: Label
var tab_labels := {}
var target_win: Panel
var target_row_h := 44.0
var target_rows: Control
var target_cursor: Panel
var target_index := 0
var using := {}                  # {kind: "item"|"skill", id, scope}
var skill_actor: Object = null
var skill_header: Control

# equip
var equip_actor: Object = null
var slot_list: Control
var cand_list: Control
var stat_box: Control
var slot_ids: Array = []

# status
var status_actor := 0
# game end
var end_list: Control
var _done := false
## The commands shown, in order: [{id, label, enabled, builtin, entry, ext}].
var menu_items: Array = []
## Menu flags (skip_single_actor).
var menu_config: Dictionary = {}


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_load_layout()
	var rows := clampi(menu_items.size(), 1, MAX_COMMAND_ROWS)
	var cw := make_window(Rect2(0, 0, 88, 16 + rows * ROW))
	commands = make_list(cw, Rect2(5, 8, 78, rows * ROW))
	commands.show_inactive_cursor = true
	_refresh_commands()
	var gw := make_window(Rect2(0, 190, 88, 50))
	make_label(gw, Vector2(6, 4), "Time", SMALL, system_colour())
	time_label = make_label(gw, Vector2(6, 4), "", FONT, null, 76, HORIZONTAL_ALIGNMENT_RIGHT)
	time_label.position.y = 15
	gold_label = make_label(gw, Vector2(6, 30), "", FONT, null, 76, HORIZONTAL_ALIGNMENT_RIGHT)
	party_win = make_window(Rect2(90, 0, 230, 240))
	party_cursor = _cursor_panel(party_win)
	party_rows = Control.new()
	party_rows.position = Vector2(6, 6)
	party_rows.size = Vector2(218, 228)
	party_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	party_win.add_child(party_rows)
	_refresh_party()
	_update(0.0)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


## Reads the command list: built-ins, extension and project entries (see the top of this file).
func _load_layout() -> void:
	var labels := {}
	for c in COMMANDS:
		labels[c] = term(c, COMMAND_FALLBACK[c])
	var host: Node = rpg.extensions if rpg != null and "extensions" in rpg else null
	if host != null and host.has_method("menu_layout"):
		menu_items = host.menu_layout(COMMANDS, labels)
		menu_config = host.menu_config()
	else:
		menu_items = []
		for c in COMMANDS:
			menu_items.append({"id": c, "label": labels[c], "enabled": true, "builtin": true, "entry": {}, "ext": ""})
		menu_config = {}


## IDs of the commands shown, in order.
func command_ids() -> Array:
	return menu_items.map(func(it): return str(it.id))


func _refresh_commands() -> void:
	var items := []
	for it in menu_items:
		var enabled := bool(it.get("enabled", true))
		if str(it.id) == "save" and bool(it.get("builtin", false)):
			enabled = enabled and save_reason() == ""
		var row := {"text": str(it.get("label", it.id)), "enabled": enabled}
		var icon: Variant = it.get("icon")
		if icon != null and str(icon) != "" and str(icon).is_valid_int():
			var tex: Texture2D = RPGIcons.texture(int(icon), 12) if RPGIcons.enabled() else null
			if tex is Texture2D:
				row["icon"] = tex
		items.append(row)
	commands.set_items(items)


func save_reason() -> String:
	if rpg == null or rpg.saves == null:
		return "Saving is not available."
	if rpg.data and not bool(rpg.data.system.get("save_enabled", true)):
		return "Saving is disabled here."
	if rpg.state and not bool(rpg.state.access.get("save", true)):
		return "Saving is disabled here."
	if save_waits_for_event():
		return ""
	return rpg.saves.save_blocked_reason()


## Set by the Open Menu Screen command: the menu sits inside a running event.
var opened_by_event := false


## True when Save should hand over to the save screen once the event that opened this menu
## ends (the same safe point Open Save Screen uses), instead of being refused.
func save_waits_for_event() -> bool:
	if not opened_by_event or rpg == null or rpg.saves == null:
		return false
	if rpg.game != null and rpg.game.get("transferring"):
		return false
	return rpg.scheduler.main != null or not rpg.scheduler.queue.is_empty()


func _update(_delta: float) -> void:
	if rpg and rpg.state and gold_label:
		gold_label.text = "%d %s" % [rpg.state.gold, currency()]
		time_label.text = format_time(rpg.state.play_time)


func _cursor_panel(parent: Control) -> Panel:
	var p := Panel.new()
	var sb: StyleBox
	if has_theme_stylebox("cursor", "RPGWindow"):
		sb = get_theme_stylebox("cursor", "RPGWindow")
	else:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(1, 1, 1, 0.15)
		f.border_color = Color(1, 1, 1, 0.85)
		f.set_border_width_all(1)
		f.set_corner_radius_all(2)
		sb = f
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	parent.add_child(p)
	return p


# --- party rows (shared by the party window and the target window) -------------------------

## Rebuilds rows of party members into `parent`: face, name, level, states and resource gauges.
func build_party_rows(parent: Control, width: float, row_h: float, face: float, compact: bool) -> void:
	for c in parent.get_children():
		c.queue_free()
	var y := 0.0
	for b in party():
		var row := Control.new()
		row.position = Vector2(0, y)
		row.size = Vector2(width, row_h)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(row)
		make_face(row, Vector2(0, (row_h - face) / 2.0 - (2 if not compact else 0)), b.id, face)
		var x := face + 6
		var w := width - x
		make_label(row, Vector2(x, 0), b.name, FONT, status_colour(b), w - 40)
		make_label(row, Vector2(width - 40, 1), term("level", "Lv"), SMALL, system_colour())
		make_label(row, Vector2(width - 26, 0), str(b.level), FONT, null, 24, HORIZONTAL_ALIGNMENT_RIGHT)
		var ry := 13.0
		if not compact:
			var st := state_names(b)
			var cls := str(record("classes", b.class_id).get("name", ""))
			if st != "":
				make_states(row, Vector2(x, 13), b, w, SMALL, colour(C_BAD))
			else:
				make_label(row, Vector2(x, 13), cls, SMALL, Color(1, 1, 1, 0.75), w)
			ry = 27.0
		var shown := 0
		for res in resource_ids():
			if shown >= 2:
				break
			var m := max_res(b, res)
			var v: int = b.get_resource(res)
			make_label(row, Vector2(x, ry), res_label(res), SMALL, system_colour(), 22)
			make_gauge(row, Rect2(x + 22, ry + 6, w - 22 - 62, 4), float(v) / float(maxi(m, 1)), HP_COLOUR if shown == 0 else SP_COLOUR)
			var vc := colour(0)
			if shown == 0 and v * 4 <= m:
				vc = colour(C_CRISIS) if v > 0 else colour(C_BAD)
			make_label(row, Vector2(width - 60, ry - 1), "%d/%d" % [v, m], SMALL, vc, 60, HORIZONTAL_ALIGNMENT_RIGHT)
			ry += 13.0
			shown += 1
		y += row_h


func _refresh_party() -> void:
	build_party_rows(party_rows, 218, 57, 48, false)
	_place_party_cursor()


func _place_party_cursor() -> void:
	party_cursor.visible = mode == "actor"
	party_cursor.position = Vector2(3, 3 + actor_index * 57)
	party_cursor.size = Vector2(224, 57)


# --- input ---------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done:
		return
	match mode:
		"command":
			_input_command(a)
		"actor":
			_input_actor(a)
		"items", "skills":
			_input_list(a)
		"target":
			_input_target(a)
		"equip_slots", "equip_items":
			_input_equip(a)
		"status":
			_input_status(a)
		"end":
			_input_end(a)


# --- mouse ---------------------------------------------------------------------------------

## What the mouse can point at in each mode: the command list, the party rows (choosing an
## actor or a target), the item/skill list and its tabs, the equipment lists, Game End.
func pointer_targets() -> Array:
	if _done:
		return []
	match mode:
		"command":
			return list_targets(commands)
		"actor":
			var out := []
			for i in party().size():
				var idx := i
				out.append({"rect": local_xform(party_win) * Rect2(3, 3 + i * 57, 224, 57), "selected": actor_index == i, "select": func() -> void: _point_actor(idx)})
			return out
		"items", "skills":
			var out2 := list_targets(list)
			if mode == "items":
				for k in tab_labels:
					var tab: Control = tab_labels[k]
					var key: String = k
					out2.append({"rect": local_xform(tab) * Rect2(Vector2.ZERO, tab.size), "selected": item_tab == key, "select": func() -> void: _point_tab(key), "ok": func() -> void: pass})
			return out2
		"target":
			if target_win == null or not is_instance_valid(target_win):
				return []
			var xf := local_xform(target_win)
			var n := party().size()
			if _all_targets() or str(using.get("scope", "")) in ["self", "user"]:
				return [{"rect": xf * Rect2(3, 3, 174, n * target_row_h + 6), "selected": true, "select": func() -> void: pass}]
			var out3 := []
			for i in n:
				var idx2 := i
				out3.append({"rect": xf * Rect2(3, 3 + i * target_row_h, 174, target_row_h), "selected": target_index == i, "select": func() -> void: _point_target(idx2)})
			return out3
		"equip_slots":
			return list_targets(slot_list)
		"equip_items":
			return list_targets(cand_list)
		"end":
			return list_targets(end_list)
	return []


func on_pointer_moved(l: Control) -> void:
	if l == list and (mode == "items" or mode == "skills"):
		_update_list_help()
	elif l == slot_list:
		_refresh_slots()
		_refresh_candidates(false)
	elif l == cand_list:
		_preview_candidate()


func _point_actor(i: int) -> void:
	if i == actor_index:
		return
	actor_index = i
	play("cursor")
	_place_party_cursor()


func _point_target(i: int) -> void:
	if i == target_index:
		return
	target_index = i
	play("cursor")
	_place_target_cursor()


func _point_tab(key: String) -> void:
	if key == item_tab:
		return
	item_tab = key
	play("cursor")
	_refresh_items(false)


func _input_command(a: String) -> void:
	match a:
		"up", "down":
			if commands.move(0, -1 if a == "up" else 1):
				play("cursor")
		"ok":
			if commands.index >= 0 and commands.index < menu_items.size():
				choose(str(menu_items[commands.index].id))
		"cancel":
			play("cancel")
			close()


func _item(cmd: String) -> Dictionary:
	for it in menu_items:
		if str(it.id) == cmd:
			return it
	return {}


## Runs a menu command as if the player chose it.
func choose(cmd: String) -> void:
	var item := _item(cmd)
	var pos := command_ids().find(cmd)
	if pos != -1:
		commands.select(pos)
	if not item.is_empty() and not bool(item.get("builtin", false)):
		await _choose_entry(item)
		return
	if not item.is_empty() and not bool(item.get("enabled", true)):
		play("buzzer")
		return
	match cmd:
		"item":
			play("decision")
			open_items()
		"skill", "equip", "status":
			if party().is_empty():
				play("buzzer")
				return
			play("decision")
			if bool(menu_config.get("skip_single_actor", false)) and party().size() == 1:
				# A party of one: no actor to choose (Main Menu Core's solo quick mode).
				actor_index = 0
				pending = cmd
				commands.active = false
				_open_for_actor(cmd, 0)
				return
			pending = cmd
			mode = "actor"
			actor_index = clampi(actor_index, 0, party().size() - 1)
			commands.active = false
			_place_party_cursor()
		"options":
			play("decision")
			await _run_sub("options")
		"save":
			var why := save_reason()
			if why != "":
				play("buzzer")
				show_notice(why)
				return
			play("decision")
			if save_waits_for_event():
				rpg.ui.pending_save_screen = true
				close()
				return
			await _run_sub("save", "save")
			_refresh_commands()
		"game_end":
			play("decision")
			open_game_end()


## An extension or project entry: buzzes when disabled; asks for an actor first when it says
## needs_actor; otherwise runs it (RPGExtensionHost.run_menu_entry).
func _choose_entry(item: Dictionary, actor: Variant = null) -> void:
	if not bool(item.get("enabled", true)):
		play("buzzer")
		return
	var e: Dictionary = item.get("entry", {})
	if bool(e.get("needs_actor", false)) and actor == null:
		if party().is_empty():
			play("buzzer")
			return
		play("decision")
		if bool(menu_config.get("skip_single_actor", false)) and party().size() == 1:
			await _choose_entry(item, party()[0])
			return
		pending = str(item.id)
		mode = "actor"
		actor_index = clampi(actor_index, 0, party().size() - 1)
		commands.active = false
		_place_party_cursor()
		return
	if actor == null:
		play("decision")
	var host: Node = rpg.extensions if rpg != null and "extensions" in rpg else null
	if host == null:
		return
	input_enabled = false
	var r: String = await host.run_menu_entry(item, self, actor)
	if not is_inside_tree() or _done:
		return
	input_enabled = true
	if r == "close":
		close()
		return
	_load_layout()
	_refresh_commands()
	_refresh_party()


func _run_sub(key: String, setup_mode := "") -> void:
	input_enabled = false
	var node := open_sub(key)
	if node != null:
		if setup_mode != "" and node.has_method("setup"):
			node.setup(setup_mode)
		if node.has_signal("closed"):
			await node.closed
		close_sub(node)
	_refresh_party()
	input_enabled = true


func show_notice(text: String) -> void:
	if notice != null and is_instance_valid(notice):
		notice.queue_free()
	notice = make_window(Rect2(20, 100, 280, 30))
	make_label(notice, Vector2(8, 7), text, FONT, null, 264, HORIZONTAL_ALIGNMENT_CENTER)
	var t := notice.create_tween()
	t.tween_interval(1.6)
	t.tween_property(notice, "modulate:a", 0.0, 0.3)
	t.tween_callback(notice.queue_free)


func _input_actor(a: String) -> void:
	var n := party().size()
	match a:
		"up", "down":
			var i := posmod(actor_index + (-1 if a == "up" else 1), n)
			if i != actor_index:
				actor_index = i
				play("cursor")
				_place_party_cursor()
		"ok":
			play("decision")
			_open_for_actor(pending, actor_index)
		"cancel":
			play("cancel")
			_back_to_commands()


## Opens Skills, Equip or Status (or an extension entry that needs an actor) for party member i.
func _open_for_actor(cmd: String, i: int) -> void:
	var b: Object = party()[i]
	match cmd:
		"skill":
			open_skills(b)
		"equip":
			open_equip(b)
		"status":
			open_status(i)
		_:
			var item := _item(cmd)
			if not item.is_empty():
				_back_to_commands()
				await _choose_entry(item, b)


func _back_to_commands() -> void:
	if view != null and is_instance_valid(view):
		view.queue_free()
	view = null
	target_win = null
	mode = "command"
	pending = ""
	commands.active = true
	_refresh_party()


func _new_view() -> Control:
	if view != null and is_instance_valid(view):
		view.queue_free()
	view = Control.new()
	view.size = Vector2(W, H)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.94)  # hides the main menu under a sub-view (translucent window skins)
	var cover := cover_rect()                # past 320x240 into any letterbox bands
	shade.position = cover.position
	shade.size = cover.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(shade)
	return view


# --- items ---------------------------------------------------------------------------------

func open_items() -> void:
	var v := _new_view()
	var hw := make_window(Rect2(0, 0, W, 26), v)
	help = make_label(hw, Vector2(8, 5), "", FONT, null, W - 16)
	var tw := make_window(Rect2(0, 28, W, 24), v)
	tab_labels = {
		"items": make_label(tw, Vector2(0, 5), term("item", "Items"), FONT, null, W / 2.0, HORIZONTAL_ALIGNMENT_CENTER),
		"key": make_label(tw, Vector2(W / 2.0, 5), term("key_items", "Key Items"), FONT, null, W / 2.0, HORIZONTAL_ALIGNMENT_CENTER),
	}
	var lw := make_window(Rect2(0, 54, W, 186), v)
	list = make_list(lw, Rect2(6, 8, W - 12, 170), 2)
	mode = "items"
	commands.active = false
	_refresh_items(false)


func _item_entries() -> Array:
	var out := []
	var inv: Dictionary = rpg.state.inventory.get("items", {})
	for id in inv:
		var n := int(inv[id])
		if n <= 0:
			continue
		var rec := record("items", id)
		var key := bool(rec.get("key_item", false))
		if (item_tab == "key") != key:
			continue
		out.append({"text": str(rec.get("name", id)), "right": ":%d" % n, "enabled": item_usable(id), "data": id, "icon": record_icon(rec)})
	return out


func item_usable(id: String) -> bool:
	var rec := record("items", id)
	if rec.is_empty() or bool(rec.get("key_item", false)):
		return false
	return str(rec.get("occasion", "always")) in FIELD_OCCASIONS and str(rec.get("scope", "one_ally")) in ALLY_SCOPES


func _refresh_items(keep := true) -> void:
	list.set_items(_item_entries(), keep)
	for k in tab_labels:
		tab_labels[k].add_theme_color_override("font_color", colour(4) if k == item_tab else Color(1, 1, 1, 0.5))
	_update_list_help()


func _update_list_help() -> void:
	var it: Dictionary = list.current()
	if it.is_empty():
		help.text = "No items." if mode == "items" else ""
		return
	var type := "items" if mode == "items" else "skills"
	help.text = str(record(type, str(it.data)).get("description", ""))


func _input_list(a: String) -> void:
	match a:
		"up", "down", "left", "right":
			var dx := -1 if a == "left" else (1 if a == "right" else 0)
			var dy := -1 if a == "up" else (1 if a == "down" else 0)
			if mode == "items" and dx != 0 and ((dx < 0 and list.index % 2 == 0) or (dx > 0 and (list.index % 2 == 1 or list.index == list.items.size() - 1) or list.items.is_empty())):
				# Past the edge of the grid: switch between Items and Key Items.
				item_tab = "key" if item_tab == "items" else "items"
				play("cursor")
				_refresh_items(false)
				return
			if list.move(dx, dy):
				play("cursor")
				_update_list_help()
		"ok":
			var it: Dictionary = list.current()
			if it.is_empty() or not bool(it.get("enabled", true)):
				play("buzzer")
				return
			play("decision")
			if mode == "items":
				var rec := record("items", str(it.data))
				open_target({"kind": "item", "id": str(it.data), "scope": str(rec.get("scope", "one_ally"))})
			else:
				var srec := record("skills", str(it.data))
				open_target({"kind": "skill", "id": str(it.data), "scope": str(srec.get("scope", "one_ally"))})
		"cancel":
			play("cancel")
			if mode == "skills":
				view.queue_free()
				view = null
				mode = "actor"
				_refresh_party()
			else:
				_back_to_commands()


func open_target(u: Dictionary) -> void:
	using = u
	if u.scope in ["self", "user"] and skill_actor != null:
		target_index = party().find(skill_actor)
	target_index = clampi(target_index, 0, maxi(0, party().size() - 1))
	var rows := party().size()
	# Below the help window (which ends at y 78), rows shrinking to fit, so the target window
	# never covers the description of what is being used.
	var top_y := 80.0
	target_row_h = clampf(floor((H - 4 - top_y - 12) / maxf(1.0, rows)), 30.0, 44.0)
	target_win = make_window(Rect2(140, top_y, 180, 12 + rows * target_row_h), view)
	target_cursor = _cursor_panel(target_win)
	target_rows = Control.new()
	target_rows.position = Vector2(6, 6)
	target_rows.size = Vector2(168, rows * target_row_h)
	target_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_win.add_child(target_rows)
	build_party_rows(target_rows, 168, target_row_h, minf(32.0, target_row_h - 4), true)
	mode = "target"
	list.active = false
	_place_target_cursor()


func _all_targets() -> bool:
	return str(using.get("scope", "")) in ["all_allies", "all_dead_allies"]


func _place_target_cursor() -> void:
	target_cursor.visible = true
	if _all_targets():
		target_cursor.position = Vector2(3, 3)
		target_cursor.size = Vector2(174, party().size() * target_row_h + 6)
	else:
		target_cursor.position = Vector2(3, 3 + target_index * target_row_h)
		target_cursor.size = Vector2(174, target_row_h + 2)


func _input_target(a: String) -> void:
	match a:
		"up", "down":
			if _all_targets() or str(using.get("scope", "")) in ["self", "user"]:
				return
			var n := party().size()
			var i := posmod(target_index + (-1 if a == "up" else 1), n)
			if i != target_index:
				target_index = i
				play("cursor")
				_place_target_cursor()
		"ok":
			var targets := []
			if _all_targets():
				targets = party()
			else:
				targets = [party()[target_index]]
			_reserved_ce = false
			var ok := use_item(using.id, targets) if using.kind == "item" else use_skill(skill_actor, using.id, targets)
			if not ok:
				play("buzzer")
				show_notice("It would have no effect.")
				return
			if _reserved_ce:
				# A Common Event effect runs on the map, so the menu closes first (as in RPG Maker).
				close()
				return
			build_party_rows(target_rows, 168, target_row_h, minf(32.0, target_row_h - 4), true)
			if using.kind == "item":
				_refresh_items()
				if rpg.state.item_count(using.id) <= 0:
					_close_target()
			else:
				_refresh_skill_header()
				_refresh_skills()
				if not rules().can_use(skill_actor, {"kind": "skill", "skill": using.id}):
					_close_target()
		"cancel":
			play("cancel")
			_close_target()


func _close_target() -> void:
	if target_win != null and is_instance_valid(target_win):
		target_win.queue_free()
	target_win = null
	mode = "items" if using.get("kind", "") == "item" else "skills"
	list.active = true
	_refresh_party()


## Uses an item on targets from the menu. Consumes it only when it had an effect; a Common Event
## effect always counts, and the event is reserved to run on the map once the menu has closed.
func use_item(id: String, targets: Array) -> bool:
	if rpg.state.item_count(id) <= 0 or not item_usable(id) or targets.is_empty() or rules() == null:
		return false
	var user: Object = party()[0] if not party().is_empty() else targets[0]
	var effect := false
	for t in targets:
		var r: Dictionary = rules().use_item(user, t, id)
		if _had_effect(r):
			effect = true
	if _reserve_common_events(user, {"kind": "item", "item": id}):
		effect = true
	if not effect:
		return false
	if bool(record("items", id).get("consumable", true)):
		rpg.state.change_items(id, "decrease", 1)
	for t in targets:
		rpg.state.notify_actor_changed(t.id)
	play("heal")
	return true


## Uses a field skill. The cost is paid once when it affected at least one target.
func use_skill(user: Object, skill_id: String, targets: Array) -> bool:
	var action := {"kind": "skill", "skill": skill_id}
	if user == null or rules() == null or not skill_usable(user, skill_id) or not rules().can_use(user, action):
		return false
	var effect := false
	for t in targets:
		if _had_effect(rules().apply_action(user, t, action)):
			effect = true
	if _reserve_common_events(user, action):
		effect = true
	if not effect:
		return false
	rules().pay_cost(user, action)
	for t in targets:
		rpg.state.notify_actor_changed(t.id)
	rpg.state.notify_actor_changed(user.id)
	play("heal")
	return true


func _had_effect(r: Dictionary) -> bool:
	return RPGRuleSystem.had_effect(r)


## Reserves the action's Common Event effects (once per use, not per target). True when any.
func _reserve_common_events(user: Object, action: Dictionary) -> bool:
	if not rules().has_method("common_events"):
		return false
	var ids: Array = rules().common_events(user, action)
	for id in ids:
		rpg.state.reserve_common_event(str(id))
	if not ids.is_empty():
		_reserved_ce = true
	return not ids.is_empty()


# --- skills --------------------------------------------------------------------------------

func open_skills(b: Object) -> void:
	skill_actor = b
	var v := _new_view()
	var head := make_window(Rect2(0, 0, W, 50), v)
	skill_header = Control.new()
	skill_header.position = Vector2(6, 6)
	skill_header.size = Vector2(W - 12, 38)
	head.add_child(skill_header)
	var hw := make_window(Rect2(0, 52, W, 26), v)
	help = make_label(hw, Vector2(8, 5), "", FONT, null, W - 16)
	var lw := make_window(Rect2(0, 80, W, 160), v)
	list = make_list(lw, Rect2(6, 8, W - 12, 144), 2)
	mode = "skills"
	party_cursor.visible = false
	_refresh_skill_header()
	_refresh_skills(false)


func _refresh_skill_header() -> void:
	for c in skill_header.get_children():
		c.queue_free()
	var b := skill_actor
	make_face(skill_header, Vector2(0, 0), b.id, 38)
	make_label(skill_header, Vector2(46, 0), b.name, FONT, status_colour(b))
	make_label(skill_header, Vector2(46, 16), "%s %d" % [term("level", "Lv"), b.level], SMALL, system_colour())
	var x := 140.0
	for res in resource_ids().slice(0, 2):
		make_label(skill_header, Vector2(x, 2), res_label(res), SMALL, system_colour())
		make_label(skill_header, Vector2(x, 16), "%d/%d" % [b.get_resource(res), max_res(b, res)], FONT, null, 70, HORIZONTAL_ALIGNMENT_RIGHT)
		x += 80


func skill_usable(b: Object, id: String) -> bool:
	var rec := record("skills", id)
	if rec.is_empty():
		return false
	return str(rec.get("occasion", "always")) in FIELD_OCCASIONS and str(rec.get("scope", "")) in ALLY_SCOPES and rules() != null and rules().can_use(b, {"kind": "skill", "skill": id})


func _refresh_skills(keep := true) -> void:
	var out := []
	for id in skill_actor.skills:
		var rec := record("skills", str(id))
		var cost: Dictionary = rec.get("cost", {})
		var cost_text := ""
		for res in cost:
			cost_text = "%d %s" % [int(cost[res]), res_label(str(res))]
		out.append({"text": str(rec.get("name", id)), "right": cost_text, "enabled": skill_usable(skill_actor, str(id)), "data": str(id), "icon": record_icon(rec)})
	list.set_items(out, keep)
	_update_list_help()


# --- equipment -----------------------------------------------------------------------------

func open_equip(b: Object) -> void:
	equip_actor = b
	var v := _new_view()
	var hw := make_window(Rect2(0, 0, W, 26), v)
	help = make_label(hw, Vector2(8, 5), "", FONT, null, W - 16)
	var sw := make_window(Rect2(0, 28, 128, 114), v)
	stat_box = Control.new()
	stat_box.position = Vector2(6, 4)
	stat_box.size = Vector2(116, 106)
	sw.add_child(stat_box)
	var lw := make_window(Rect2(130, 28, 190, 114), v)
	slot_ids = []
	for e in record("types", "equip_slots").get("entries", []):
		slot_ids.append(str(e.get("id", "")))
	for s in b.equips:
		if not slot_ids.has(str(s)):
			slot_ids.append(str(s))
	slot_list = make_list(lw, Rect2(6, 8, 178, 98))
	slot_list.show_inactive_cursor = true
	var cw := make_window(Rect2(0, 144, W, 96), v)
	cand_list = make_list(cw, Rect2(6, 8, W - 12, 80), 2)
	cand_list.active = false
	mode = "equip_slots"
	party_cursor.visible = false
	_refresh_slots()
	_refresh_candidates()
	_refresh_equip_stats()


func _slot_name(slot: String) -> String:
	for e in record("types", "equip_slots").get("entries", []):
		if str(e.get("id", "")) == slot:
			return str(e.get("name", slot.capitalize()))
	return slot.capitalize()


func _slot_kind(slot: String) -> String:
	# Dual Wield (VX Ace rules): the actor's shield slot holds a second weapon.
	if equip_actor != null and rules() != null and rules().has_method("dual_wield_slots") and equip_actor.has_method("is_actor"):
		if (rules().dual_wield_slots(equip_actor) as Array).has(slot):
			return "weapons"
	for e in record("types", "equip_slots").get("entries", []):
		if str(e.get("id", "")) == slot:
			return "weapons" if str(e.get("kind", "")) == "weapon" else "armors"
	return "weapons" if slot == "weapon" else "armors"


func _refresh_slots() -> void:
	var items := []
	for s in slot_ids:
		var id := str(equip_actor.equips.get(s, ""))
		var nm := str(record(_slot_kind(s), id).get("name", "")) if id != "" else "-"
		var sealed := _sealed(s)
		items.append({"text": _slot_name(s), "right": nm, "colour": system_colour() if not sealed else Color(1, 1, 1, 0.45), "right_colour": colour(0) if not sealed else Color(1, 1, 1, 0.45),
			"right_icon": record_icon(record(_slot_kind(s), id)) if id != "" else null})
	slot_list.set_items(items)
	var cur := str(equip_actor.equips.get(current_slot(), ""))
	help.text = str(record(_slot_kind(current_slot()), cur).get("description", "")) if cur != "" else ""


## Seal Equip (VX Ace rules): the slot can't be changed.
func _sealed(slot: String) -> bool:
	return equip_actor != null and rules() != null and rules().has_method("is_slot_sealed") and equip_actor.has_method("is_actor") and bool(rules().is_slot_sealed(equip_actor, slot))


func current_slot() -> String:
	return slot_ids[slot_list.index] if slot_list.index < slot_ids.size() else ""


## Inventory weapons/armor that `b` can wear in `slot`.
func candidates(b: Object, slot: String) -> Array:
	var kind := _slot_kind(slot)
	var out := []
	var inv: Dictionary = rpg.state.inventory.get(kind, {})
	for id in inv:
		if int(inv[id]) > 0 and can_equip(b, slot, kind, str(id)):
			out.append(str(id))
	return out


func can_equip(b: Object, slot: String, kind: String, id: String) -> bool:
	var rec := record(kind, id)
	if rec.is_empty():
		return false
	var allowed: Variant = record("classes", b.class_id).get("equip")
	if kind == "weapons":
		if allowed is Dictionary and not (allowed.get("weapon_types", []) as Array).has(str(rec.get("weapon_type", ""))):
			return false
		return true
	var rs := str(rec.get("slot", ""))
	if rs != "" and rs != slot:
		return false
	if rs == "":
		for e in record("types", "equip_slots").get("entries", []):
			if str(e.get("id", "")) == slot:
				var types: Array = e.get("armor_types", [])
				if not types.is_empty() and not types.has(str(rec.get("armor_type", ""))):
					return false
	if allowed is Dictionary and not (allowed.get("armor_types", []) as Array).has(str(rec.get("armor_type", ""))):
		return false
	return true


func _refresh_candidates(keep := true) -> void:
	var slot := current_slot()
	var kind := _slot_kind(slot)
	var items := []
	for id in candidates(equip_actor, slot):
		items.append({"text": str(record(kind, id).get("name", id)), "right": ":%d" % rpg.state.item_count(id, kind), "data": id, "icon": record_icon(record(kind, id))})
	items.append({"text": "(Remove)", "colour": Color(1, 1, 1, 0.7), "data": ""})
	cand_list.set_items(items, keep)


func _refresh_equip_stats(preview_id: Variant = null) -> void:
	for c in stat_box.get_children():
		c.queue_free()
	var b := equip_actor
	make_label(stat_box, Vector2(0, 0), b.name, FONT, status_colour(b), 116)
	var after := {}
	if preview_id != null:
		var slot := current_slot()
		var old: Variant = b.equips.get(slot, "")
		b.equips[slot] = str(preview_id)
		for s in rules().stats():
			after[s.id] = rules().effective_stat(b, s.id)
		b.equips[slot] = old
	var y := 16.0
	# Rows close up when the rule set has many stats, so the last one isn't cut by the border.
	var shown: Array = rules().stats().filter(func(s): return not (str(s.id) in ["mhp", "msp", "mmp"]))
	var box_h: float = stat_box.size.y if stat_box.size.y > 0 else 120.0
	var step := clampf((box_h - 16.0) / maxf(1.0, shown.size()), 9.0, 12.0)
	for s in shown:
		var sid := str(s.id)
		var cur: Variant = rules().effective_stat(b, sid)
		make_label(stat_box, Vector2(0, y), stat_label(sid), SMALL, system_colour(), 40)
		make_label(stat_box, Vector2(36, y), str(cur), SMALL, null, 30, HORIZONTAL_ALIGNMENT_RIGHT)
		if after.has(sid):
			var nv: Variant = after[sid]
			var c := colour(0)
			if nv > cur:
				c = colour(C_GOOD)
			elif nv < cur:
				c = colour(C_BAD)
			make_label(stat_box, Vector2(68, y), ">", SMALL, Color(1, 1, 1, 0.6))
			make_label(stat_box, Vector2(78, y), str(nv), SMALL, c, 30, HORIZONTAL_ALIGNMENT_RIGHT)
		y += step


func _input_equip(a: String) -> void:
	if mode == "equip_slots":
		match a:
			"up", "down":
				if slot_list.move(0, -1 if a == "up" else 1):
					play("cursor")
					_refresh_slots()
					_refresh_candidates(false)
			"ok":
				if _sealed(current_slot()):
					play("buzzer")
					return
				play("decision")
				mode = "equip_items"
				slot_list.active = false
				cand_list.active = true
				cand_list.select(0)
				_preview_candidate()
			"cancel":
				play("cancel")
				view.queue_free()
				view = null
				mode = "actor"
				_refresh_party()
			"left", "right":
				# Next / previous party member.
				var n := party().size()
				if n > 1:
					actor_index = posmod(actor_index + (-1 if a == "left" else 1), n)
					play("cursor")
					var keep: int = slot_list.index
					open_equip(party()[actor_index])
					slot_list.select(keep)
					_refresh_slots()
					_refresh_candidates(false)
		return
	match a:
		"up", "down", "left", "right":
			var dx := -1 if a == "left" else (1 if a == "right" else 0)
			var dy := -1 if a == "up" else (1 if a == "down" else 0)
			if cand_list.move(dx, dy):
				play("cursor")
				_preview_candidate()
		"ok":
			var id := str(cand_list.current().get("data", ""))
			if equip(equip_actor, current_slot(), id):
				play("decision")
			else:
				play("buzzer")
			_end_candidates()
		"cancel":
			play("cancel")
			_end_candidates()


func _preview_candidate() -> void:
	var id := str(cand_list.current().get("data", ""))
	_refresh_equip_stats(id)
	help.text = str(record(_slot_kind(current_slot()), id).get("description", "")) if id != "" else "Take off the equipment."


func _end_candidates() -> void:
	mode = "equip_slots"
	slot_list.active = true
	cand_list.active = false
	_refresh_slots()
	_refresh_candidates(false)
	_refresh_equip_stats()


## Puts item `id` (or nothing, "") into `slot`. The old item goes back to the inventory.
func equip(b: Object, slot: String, id: String) -> bool:
	var kind := _slot_kind(slot)
	var old := str(b.equips.get(slot, ""))
	if id == old:
		return true
	if id != "" and (rpg.state.item_count(id, kind) <= 0 or not can_equip(b, slot, kind, id)):
		return false
	if old != "":
		rpg.state.change_items(old, "increase", 1, kind)
	if id != "":
		rpg.state.change_items(id, "decrease", 1, kind)
	b.equips[slot] = id
	if rules() != null:
		rules().clamp_resources(b)
	rpg.state.notify_actor_changed(b.id)
	return true


# --- status --------------------------------------------------------------------------------

func open_status(i: int) -> void:
	status_actor = i
	var b: Object = party()[i]
	var v := _new_view()
	mode = "status"
	party_cursor.visible = false
	var top := make_window(Rect2(0, 0, W, 66), v)
	make_face(top, Vector2(8, 8), b.id, 48)
	make_label(top, Vector2(64, 6), b.name, FONT, status_colour(b))
	make_label(top, Vector2(64, 21), str(record("classes", b.class_id).get("name", "")), SMALL, Color(1, 1, 1, 0.8))
	make_label(top, Vector2(64, 35), term("level", "Lv"), SMALL, system_colour())
	make_label(top, Vector2(80, 34), str(b.level), FONT)
	var st := state_names(b)
	if st != "":
		make_states(top, Vector2(64, 48), b, 108, SMALL, colour(C_BAD))
	else:
		make_label(top, Vector2(64, 48), "Normal", SMALL, colour(0))
	var y := 8.0
	var shown := 0
	for res in resource_ids():
		if shown >= 2:
			break
		var m := max_res(b, res)
		make_label(top, Vector2(176, y), res_label(res), SMALL, system_colour())
		make_label(top, Vector2(236, y - 1), "%d/%d" % [b.get_resource(res), m], FONT, null, 76, HORIZONTAL_ALIGNMENT_RIGHT)
		make_gauge(top, Rect2(176, y + 14, 136, 4), float(b.get_resource(res)) / float(maxi(m, 1)), HP_COLOUR if shown == 0 else SP_COLOUR)
		y += 26
		shown += 1
	var sw := make_window(Rect2(0, 68, 150, 172), v)
	var sy := 6.0
	make_label(sw, Vector2(8, sy), "Parameters", SMALL, system_colour())
	sy += 14
	for s in rules().stats():
		make_label(sw, Vector2(12, sy), str(s.get("label", s.id)), SMALL, null, 90)
		make_label(sw, Vector2(96, sy), str(rules().effective_stat(b, str(s.id))), SMALL, null, 44, HORIZONTAL_ALIGNMENT_RIGHT)
		sy += 14
	var ew := make_window(Rect2(152, 68, 168, 66), v)
	var next_total: int = rules().exp_for_level(b.class_id, b.level + 1)
	var at_max: bool = b.level >= rules().max_level(b)
	make_label(ew, Vector2(8, 6), term("exp", "EXP"), SMALL, system_colour())
	make_label(ew, Vector2(60, 5), str(b.exp), FONT, null, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	make_label(ew, Vector2(8, 22), "Next level", SMALL, system_colour())
	make_label(ew, Vector2(60, 21), "-" if at_max else str(maxi(0, next_total - b.exp)), FONT, null, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	var prev_total: int = rules().exp_for_level(b.class_id, b.level)
	var ratio := 1.0 if at_max else float(b.exp - prev_total) / float(maxi(1, next_total - prev_total))
	make_gauge(ew, Rect2(8, 42, 152, 5), ratio, Color(0.7, 0.55, 1.0))
	var qw := make_window(Rect2(152, 136, 168, 104), v)
	make_label(qw, Vector2(8, 6), "Equipment", SMALL, system_colour())
	var qy := 20.0
	var slots := []
	for e in record("types", "equip_slots").get("entries", []):
		slots.append(str(e.get("id", "")))
	for s in b.equips:
		if not slots.has(str(s)):
			slots.append(str(s))
	for s in slots:
		var id := str(b.equips.get(s, ""))
		make_label(qw, Vector2(8, qy), _slot_name(str(s)), SMALL, Color(1, 1, 1, 0.7), 56)
		make_label(qw, Vector2(64, qy), str(record(_slot_kind(str(s)), id).get("name", "-")) if id != "" else "-", SMALL, null, 96)
		qy += 14
	if party().size() > 1:
		make_label(v, Vector2(0, 226), "< >", SMALL, Color(1, 1, 1, 0.5), 150, HORIZONTAL_ALIGNMENT_CENTER)
	# The actor's profile (Database > Actors > Description), shown over the lower windows with OK.
	var desc := str(record("actors", b.id).get("description", "")).strip_edges()
	profile_win = null
	if desc != "":
		profile_win = make_window(Rect2(0, 68, W, 172), v)
		make_label(profile_win, Vector2(8, 6), "Profile", SMALL, system_colour())
		var lab := make_label(profile_win, Vector2(8, 22), desc, SMALL, null, W - 16)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size.y = 140
		profile_win.visible = false
		make_label(v, Vector2(170, 226), "OK: profile", SMALL, Color(1, 1, 1, 0.5), 150, HORIZONTAL_ALIGNMENT_CENTER)


## The status screen's profile window (null when the actor has no description).
var profile_win: Control = null


func _input_status(a: String) -> void:
	match a:
		"left", "right", "up", "down":
			var n := party().size()
			if n > 1:
				play("cursor")
				open_status(posmod(status_actor + (-1 if a in ["left", "up"] else 1), n))
		"ok" when profile_win != null:
			play("decision")
			profile_win.visible = not profile_win.visible
		"cancel", "ok":
			play("cancel")
			view.queue_free()
			view = null
			mode = "actor"
			actor_index = status_actor
			_refresh_party()


# --- game end ------------------------------------------------------------------------------

func open_game_end() -> void:
	var v := _new_view()
	var w := make_window(Rect2(110, 92, 100, 44), v)
	end_list = make_list(w, Rect2(6, 8, 88, 2 * ROW))
	end_list.set_items([{"text": "To Title"}, {"text": term("cancel", "Cancel")}])
	mode = "end"
	commands.active = false


func _input_end(a: String) -> void:
	match a:
		"up", "down":
			if end_list.move(0, -1 if a == "up" else 1):
				play("cursor")
		"ok":
			if end_list.index == 0:
				play("decision")
				to_title()
			else:
				play("cancel")
				_back_to_commands()
		"cancel":
			play("cancel")
			_back_to_commands()


func to_title() -> void:
	close()
	if rpg and rpg.game != null and rpg.game.has_method("return_to_title"):
		rpg.game.return_to_title.call_deferred()


func close() -> void:
	if _done:
		return
	_done = true
	input_enabled = false
	closed.emit()
