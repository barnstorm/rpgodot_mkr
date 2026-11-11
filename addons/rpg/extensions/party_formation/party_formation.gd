extends "res://addons/rpg/runtime/rpg_extension.gd"
## Party formation (kit plugin "party_formation").
## - Active (battle) and reserve members. Only active members fight (the battle scene's
##   battle_members query). The game's party order is kept as active, then reserve, so the
##   leader on the map and the menu follow the formation.
## - A Formation screen from the main menu (entry "formation") and the Open formation command.
## - Locked members cannot be moved by the player; required members cannot go to the reserve.
##   Both are set by the Change formation member command, which can also move a member.
## - The number of battle members (setting, changed by Change battle members).
## - Reserve members can get a share of the battle's EXP (setting).
## Saved with the game (section "party_formation": {active, reserve, locked, required, max}).
## New party members join the active row while it has room, else the reserve.

const SECTION := "party_formation"
const SCREEN := "res://addons/rpg/extensions/party_formation/formation_screen.gd"
const MAX_MEMBERS := 4

var _syncing := false


func _extension_ready() -> void:
	if rpg.state != null and not rpg.state.party_changed.is_connected(_on_party_changed):
		rpg.state.party_changed.connect(_on_party_changed)
	sync()


func _exit_tree() -> void:
	if rpg != null and rpg.state != null and rpg.state.party_changed.is_connected(_on_party_changed):
		rpg.state.party_changed.disconnect(_on_party_changed)


func on_new_game() -> void:
	sync()


func on_game_loaded() -> void:
	sync()


func _on_party_changed() -> void:
	if not _syncing:
		sync()


# --- formation data ------------------------------------------------------------------------------

## Battle members allowed now (1..4): an event's Change battle members, else the setting.
func max_battle() -> int:
	var s := section(SECTION)
	var n := int(s.get("max", 0))
	if n <= 0:
		n = int(setting("max_battle", MAX_MEMBERS))
	return clampi(n, 1, MAX_MEMBERS)


func active_ids() -> Array:
	return (section(SECTION).get("active", []) as Array).duplicate()


func reserve_ids() -> Array:
	return (section(SECTION).get("reserve", []) as Array).duplicate()


func is_locked(id: String) -> bool:
	return (section(SECTION).get("locked", []) as Array).has(id)


func is_required(id: String) -> bool:
	return (section(SECTION).get("required", []) as Array).has(id)


func is_active(id: String) -> bool:
	return active_ids().has(id)


## Brings the formation in line with the party: members who left are dropped, new ones join the
## active row while there is room, required members are made active, the row is cut to
## max_battle(), and the party order becomes active + reserve.
func sync() -> void:
	if rpg.state == null:
		return
	var s := section(SECTION)
	var party: Array = Array(rpg.state.party)
	var old_active: Array = s.get("active", [])
	var active: Array = old_active.filter(func(id): return party.has(id))
	var reserve: Array = (s.get("reserve", []) as Array).filter(func(id): return party.has(id) and not active.has(id))
	# A battle member who left the party: the first reserve member takes the place.
	for i in old_active.size() - active.size():
		if not reserve.is_empty() and active.size() < max_battle():
			active.append(reserve.pop_front())
	for id in party:
		if not active.has(id) and not reserve.has(id):
			if active.size() < max_battle():
				active.append(id)
			else:
				reserve.append(id)
	while active.size() > max_battle():
		# The last member who is not required goes to the front of the reserve.
		var k := active.size() - 1
		while k > 0 and is_required(str(active[k])):
			k -= 1
		reserve.push_front(active[k])
		active.remove_at(k)
	for id in reserve.duplicate():
		if is_required(str(id)):
			_make_active(str(id), active, reserve)
	if active.is_empty() and not reserve.is_empty():
		active.append(reserve.pop_front())
	s["active"] = active
	s["reserve"] = reserve
	_apply_order(active + reserve)


## Puts a reserve member into the active row (in place of the last active member who is neither
## required nor locked when the row is full). Returns false when nobody can make room.
func _make_active(id: String, active: Array, reserve: Array) -> bool:
	if active.has(id):
		return true
	if active.size() >= max_battle():
		var k := active.size() - 1
		while k >= 0 and (is_required(str(active[k])) or is_locked(str(active[k]))):
			k -= 1
		if k < 0:
			return false
		var out: String = active[k]
		active[k] = id
		reserve[reserve.find(id)] = out
		return true
	reserve.erase(id)
	active.append(id)
	return true


func _apply_order(order: Array) -> void:
	if Array(rpg.state.party) == order:
		return
	_syncing = true
	rpg.state.party.assign(order)
	rpg.state.party_changed.emit()
	rpg.state.changed.emit()
	_syncing = false
	if rpg.game != null and is_instance_valid(rpg.game) and rpg.game.has_method("refresh_party_graphics") and rpg.game.get("map") != null:
		rpg.game.refresh_party_graphics()


## Sets the rows (the formation screen and commands). Checks nothing; call sync() after.
func set_rows(active: Array, reserve: Array) -> void:
	var s := section(SECTION)
	s["active"] = active.duplicate()
	s["reserve"] = reserve.duplicate()
	sync()


## Moves a member to "active" or "reserve" (events: locks do not apply, required members cannot
## go to the reserve, the active row keeps at least one member). Returns "" or the reason.
func move(id: String, to: String) -> String:
	sync()
	var active := active_ids()
	var reserve := reserve_ids()
	if not active.has(id) and not reserve.has(id):
		return "'%s' is not in the party." % id
	if to == "active":
		if active.has(id):
			return ""
		if not _make_active(id, active, reserve):
			return "the battle row is full of required or locked members."
	elif to == "reserve":
		if reserve.has(id):
			return ""
		if is_required(id):
			return "'%s' is required and cannot go to the reserve." % id
		if active.size() <= 1:
			return "the battle row cannot be empty."
		active.erase(id)
		reserve.push_front(id)
	set_rows(active, reserve)
	return ""


func set_flag(list_key: String, id: String, on: bool) -> void:
	var s := section(SECTION)
	var list: Array = s.get(list_key, [])
	if on and not list.has(id):
		list.append(id)
	elif not on:
		list.erase(id)
	s[list_key] = list
	sync()


func set_locked(id: String, on: bool) -> void:
	set_flag("locked", id, on)


func set_required(id: String, on: bool) -> void:
	set_flag("required", id, on)


## Change battle members: 1..4, or 0 for the setting.
func set_max_battle(n: int) -> void:
	var s := section(SECTION)
	if n <= 0:
		s.erase("max")
	else:
		s["max"] = clampi(n, 1, MAX_MEMBERS)
	sync()


# --- battle --------------------------------------------------------------------------------------

## The battle scene's battle_members query: the active members, in formation order.
func battle_members(members: Array) -> Array:
	sync()
	var out := []
	for id in active_ids():
		for b in members:
			if b is Object and str(b.id) == str(id):
				out.append(b)
	return out


## Reserve members get reserve_exp % of the battle's EXP (victory hook; rewards unchanged).
func on_victory(rewards: Dictionary) -> void:
	var pct := clampi(int(setting("reserve_exp", 0)), 0, 100)
	var amount := int(int(rewards.get("exp", 0)) * pct / 100.0)
	if amount <= 0 or rpg.rules == null:
		return
	for id in reserve_ids():
		var b: Variant = rpg.state.actor(str(id))
		if b is Object and b.is_alive():
			rpg.rules.gain_exp(b, amount)


# --- menu and screen -----------------------------------------------------------------------------

func menu_entry_shown() -> bool:
	return bool(setting("menu_entry", true))


func adjust_menu(layout: Array, _config: Dictionary) -> void:
	for item in layout:
		if str(item.get("id", "")) == "formation" and str(item.get("ext", "")) == extension_id:
			item["label"] = str(setting("menu_label", "Formation"))
			var icon: Variant = setting("menu_icon", 0)
			if icon != null and int(icon) > 0:
				item["icon"] = int(icon)
			else:
				item.erase("icon")


## Main menu entry: the formation screen over the menu.
func open_from_menu(_menu: Node) -> String:
	await open_screen()
	return ""


## Opens the formation screen and waits until it closes.
func open_screen() -> void:
	var node := make_screen()
	if node == null:
		return
	await node.closed
	rpg.ui.close_scene(node)


## Opens the formation screen (the caller waits for `closed` and closes it). Null without a UI.
func make_screen() -> Node:
	if rpg.ui == null:
		return null
	sync()
	var node: Node = rpg.ui.open_scene(SCREEN)
	if node != null:
		node.setup(self)
	return node
