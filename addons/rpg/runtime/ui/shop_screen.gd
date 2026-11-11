extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default shop (Run Scene contract): start({goods: [{kind, id, price?}], buy_only}, context),
## then finished({bought: [...], sold: [...]}) when the player leaves.
## Buy / Sell / Leave; a quantity window with the total; the price comes from the database when
## a good has no price. The info window shows how many are owned and, for equipment, which
## party members can use it and whether it is better (+) or worse (-) than what they wear.

signal finished(result: Variant)
signal cancelled(reason: String)

const SELL_RATE := 0.5

var goods: Array = []
var buy_only := false
var mode := "command"          # command, buy, sell, quantity
var qty_for := ""              # buy or sell (while mode == quantity)
var qty := 1
var qty_max := 1
var bought: Array = []
var sold: Array = []

var help: Label
var message: Label
var commands: Control
var list: Control
var info_win: Panel
var info_box: Control
var gold_label: Label
var qty_win: Panel
var qty_name: Label
var qty_value: Label
var qty_total: Label
var _sell_entries: Array = []
var _done := false


func start(args: Dictionary, context: Variant = null) -> void:
	if rpg == null and context is Dictionary and context.has("rpg"):
		rpg = context.rpg
	goods = []
	for g in args.get("goods", []):
		if g is Dictionary:
			var kind := RPGGameState.kind_for(str(g.get("kind", "items")))
			var id := str(g.get("id", ""))
			if record(kind, id).is_empty():
				continue
			goods.append({"kind": kind, "id": id, "price": g.get("price")})
	buy_only = bool(args.get("buy_only", false))
	_refresh_commands()
	_set_mode("command")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var hw := make_window(Rect2(0, 0, W, 26))
	help = make_label(hw, Vector2(8, 5), "", FONT, null, W - 16)
	var lw := make_window(Rect2(0, 28, 200, 146))
	list = make_list(lw, Rect2(6, 8, 188, 130))
	info_win = make_window(Rect2(202, 28, 118, 118))
	info_box = Control.new()
	info_box.position = Vector2(6, 6)
	info_box.size = Vector2(106, 106)
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_win.add_child(info_box)
	var gw := make_window(Rect2(202, 148, 118, 26))
	gold_label = make_label(gw, Vector2(6, 5), "", FONT, null, 106, HORIZONTAL_ALIGNMENT_RIGHT)
	var mw := make_window(Rect2(0, 176, 220, 64))
	message = make_label(mw, Vector2(8, 8), "", FONT, null, 204)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size.y = 48
	var cw := make_window(Rect2(222, 176, 98, 64))
	commands = make_list(cw, Rect2(6, 8, 86, 3 * ROW))
	commands.show_inactive_cursor = true
	qty_win = make_window(Rect2(16, 84, 184, 52))
	qty_name = make_label(qty_win, Vector2(8, 6), "", FONT, null, 120)
	qty_value = make_label(qty_win, Vector2(128, 6), "", FONT, colour(4), 48, HORIZONTAL_ALIGNMENT_RIGHT)
	qty_total = make_label(qty_win, Vector2(8, 26), "", FONT, null, 168, HORIZONTAL_ALIGNMENT_RIGHT)
	qty_win.visible = false
	_refresh_commands()
	_set_mode("command")


func _refresh_commands() -> void:
	if commands == null:
		return
	commands.set_items([
		{"text": term("buy", "Buy")},
		{"text": term("sell", "Sell"), "enabled": not buy_only},
		{"text": term("leave", "Leave")},
	])


func _update(_delta: float) -> void:
	if gold_label and rpg and rpg.state:
		gold_label.text = "%d %s" % [rpg.state.gold, currency()]


# --- prices and lists ----------------------------------------------------------------------

func price_of(good: Dictionary) -> int:
	var p: Variant = good.get("price")
	if p == null or (p is String and p == ""):
		return int(record(good.kind, good.id).get("price", 0))
	return int(p)


func sell_price(kind: String, id: String) -> int:
	return int(floor(float(record(kind, id).get("price", 0)) * SELL_RATE))


func owned(kind: String, id: String) -> int:
	return rpg.state.item_count(id, kind)


func equipped_count(kind: String, id: String) -> int:
	if kind == "items":
		return 0
	var n := 0
	for b in party():
		for slot in b.equips:
			if str(b.equips[slot]) == id:
				n += 1
	return n


func _buy_items() -> Array:
	var out := []
	for g in goods:
		var rec := record(g.kind, g.id)
		var price := price_of(g)
		var can: bool = price <= rpg.state.gold and owned(g.kind, g.id) < RPGGameState.MAX_ITEMS
		out.append({"text": str(rec.get("name", g.id)), "right": str(price), "enabled": can, "data": g, "icon": record_icon(rec)})
	return out


func _sell_items() -> Array:
	_sell_entries = []
	var out := []
	for kind in ["items", "weapons", "armors"]:
		var inv: Dictionary = rpg.state.inventory.get(kind, {})
		for id in inv:
			var n := int(inv[id])
			if n <= 0:
				continue
			var rec := record(kind, id)
			var price := sell_price(kind, id)
			var ok := price > 0 and not bool(rec.get("key_item", false))
			out.append({"text": str(rec.get("name", id)), "right": "x%d" % n, "enabled": ok, "data": {"kind": kind, "id": id}, "icon": record_icon(rec)})
	return out


# --- modes ---------------------------------------------------------------------------------

func _set_mode(m: String) -> void:
	mode = m
	if commands == null:
		return
	commands.active = m == "command"
	list.active = m == "buy" or m == "sell"
	qty_win.visible = m == "quantity"
	match m:
		"command":
			list.set_items([], false)
			message.text = "Welcome! What would you like to do?" if bought.is_empty() and sold.is_empty() else "Is there anything else?"
			help.text = ""
			_show_info({})
		"buy":
			list.set_items(_buy_items())
			message.text = "What would you like to buy?"
		"sell":
			list.set_items(_sell_items())
			message.text = "What would you like to sell?"
		"quantity":
			message.text = "How many?"
	if m == "buy" or m == "sell":
		_on_list_moved()


func _on_list_moved() -> void:
	var it: Dictionary = list.current()
	if it.is_empty():
		help.text = "You have nothing to sell." if mode == "sell" else ""
		_show_info({})
		return
	var d: Dictionary = it.data
	help.text = str(record(d.kind, d.id).get("description", ""))
	_show_info(d)


## Info window: owned / equipped counts and per-actor equip indicators.
func _show_info(d: Dictionary) -> void:
	for c in info_box.get_children():
		c.queue_free()
	if d.is_empty():
		var y := 0.0
		for b in party():
			make_label(info_box, Vector2(0, y), b.name, SMALL)
			make_label(info_box, Vector2(56, y), "%s %d" % [term("level", "Lv"), b.level], SMALL, system_colour(), 50, HORIZONTAL_ALIGNMENT_RIGHT)
			y += 13
		return
	make_label(info_box, Vector2(0, 0), "Owned", SMALL, system_colour())
	make_label(info_box, Vector2(56, 0), str(owned(d.kind, d.id)), SMALL, null, 50, HORIZONTAL_ALIGNMENT_RIGHT)
	if d.kind == "items":
		return
	make_label(info_box, Vector2(0, 12), "Equipped", SMALL, system_colour())
	make_label(info_box, Vector2(56, 12), str(equipped_count(d.kind, d.id)), SMALL, null, 50, HORIZONTAL_ALIGNMENT_RIGHT)
	var y2 := 30.0
	for b in party():
		var cmp := compare_equip(b, d.kind, d.id)
		var mark := "--"
		var c := Color(1, 1, 1, 0.4)
		if cmp.can:
			if cmp.diff > 0:
				mark = "+%d" % cmp.diff
				c = colour(C_GOOD)
			elif cmp.diff < 0:
				mark = str(cmp.diff)
				c = colour(C_BAD)
			else:
				mark = "="
				c = colour(0)
		make_label(info_box, Vector2(0, y2), b.name, SMALL, colour(0) if cmp.can else Color(1, 1, 1, 0.4), 60)
		make_label(info_box, Vector2(60, y2), mark, SMALL, c, 46, HORIZONTAL_ALIGNMENT_RIGHT)
		y2 += 13


## Stats tried, in order, for the shop's comparison when the rule set names none
## (rules.json "shop_compare": {"weapons": "<stat>", "armors": "<stat>"}).
const COMPARE_STATS := {"weapons": ["atk", "attack_bonus", "str"], "armors": ["pdef", "def", "ac", "mdef"]}


## The stat the shop compares for weapons or armor in this rule set, or "" for none.
func compare_stat(kind: String) -> String:
	var r: RPGRuleSystem = rules()
	if r == null:
		return ""
	var named: Variant = r.definition.get("shop_compare", {})
	if named is Dictionary and named.has(kind):
		return str(named[kind])
	var have := {}
	for s in r.stats():
		have[str(s.get("id", ""))] = true
	for s in COMPARE_STATS.get(kind, []):
		if have.has(s):
			return s
	return ""


## Average roll of a dice string such as "2d6+1" (0 when there is none).
static func dice_average(dice: String) -> float:
	var m := RegEx.create_from_string("^\\s*(\\d*)d(\\d+)\\s*([+-]\\s*\\d+)?\\s*$").search(dice)
	if m == null:
		return 0.0
	var count := int(m.get_string(1)) if m.get_string(1) != "" else 1
	var bonus := int(m.get_string(3).replace(" ", "")) if m.get_string(3) != "" else 0
	return count * (int(m.get_string(2)) + 1) / 2.0 + bonus


## Whether actor `b` can equip the weapon/armor, and the change it makes compared with what is
## worn in that slot now: the rule set's compare stat (see compare_stat), plus, for weapons with
## damage dice, the change in their average roll.
func compare_equip(b: Object, kind: String, id: String) -> Dictionary:
	var slot := equip_slot_for(b, kind, id)
	if slot == "" or rules() == null:
		return {"can": false, "diff": 0, "slot": ""}
	var old: Variant = b.equips.get(slot, "")
	var diff := 0.0
	var stat := compare_stat(kind)
	if stat != "":
		var before: int = int(rules().effective_stat(b, stat))
		b.equips[slot] = id
		var after: int = int(rules().effective_stat(b, stat))
		b.equips[slot] = old
		diff += after - before
	if kind == "weapons":
		var new_dice := str(record(kind, id).get("dice", ""))
		if new_dice != "":
			var old_dice := str(record(kind, str(old)).get("dice", "")) if str(old) != "" else ""
			diff += dice_average(new_dice) - dice_average(old_dice)
	return {"can": true, "diff": int(round(diff)), "slot": slot}


## The slot of `b` that takes this weapon/armor, or "" when the actor cannot equip it.
func equip_slot_for(b: Object, kind: String, id: String) -> String:
	var rec := record(kind, id)
	if rec.is_empty() or kind == "items":
		return ""
	var cls := record("classes", b.class_id)
	var allowed: Variant = cls.get("equip")
	for e in record("types", "equip_slots").get("entries", []):
		var slot_kind := str(e.get("kind", ""))
		if kind == "weapons" and slot_kind == "weapon":
			if allowed is Dictionary and not (allowed.get("weapon_types", []) as Array).has(str(rec.get("weapon_type", ""))):
				return ""
			return str(e.id)
		if kind == "armors" and slot_kind == "armor":
			var rs := str(rec.get("slot", ""))
			if rs != "" and rs != str(e.id):
				continue
			var types: Array = e.get("armor_types", [])
			if rs == "" and not types.is_empty() and not types.has(str(rec.get("armor_type", ""))):
				continue
			if allowed is Dictionary and not (allowed.get("armor_types", []) as Array).has(str(rec.get("armor_type", ""))):
				return ""
			return str(e.id)
	return ""


# --- input ---------------------------------------------------------------------------------

func handle_action(a: String) -> void:
	if _done:
		return
	match mode:
		"command":
			match a:
				"up", "down":
					if commands.move(0, -1 if a == "up" else 1):
						play("cursor")
				"ok":
					match commands.index:
						0:
							play("decision")
							_set_mode("buy")
						1:
							if buy_only:
								play("buzzer")
							else:
								play("decision")
								_set_mode("sell")
						2:
							play("decision")
							leave()
				"cancel":
					play("cancel")
					leave()
		"buy", "sell":
			match a:
				"up", "down":
					if list.move(0, -1 if a == "up" else 1):
						play("cursor")
						_on_list_moved()
				"ok":
					_pick_from_list()
				"cancel":
					play("cancel")
					_set_mode("command")
		"quantity":
			match a:
				"up", "right":
					_set_qty(qty + (1 if a == "up" else 10))
				"down", "left":
					_set_qty(qty - (1 if a == "down" else 10))
				"ok":
					var d: Dictionary = list.current().get("data", {})
					if qty_for == "buy":
						buy(d, qty)
					else:
						sell(d.kind, d.id, qty)
					_set_mode(qty_for)
				"cancel":
					play("cancel")
					_set_mode(qty_for)


# --- mouse ---------------------------------------------------------------------------------

## The active list; while choosing a quantity, the quantity window (a click on it buys or sells).
func pointer_targets() -> Array:
	if _done:
		return []
	if mode == "quantity":
		return [{"rect": local_xform(qty_win) * Rect2(Vector2.ZERO, qty_win.size), "selected": true, "select": func() -> void: pass}]
	return super.pointer_targets()


func on_pointer_moved(l: Control) -> void:
	if l == list:
		_on_list_moved()


func _pick_from_list() -> void:
	var it: Dictionary = list.current()
	if it.is_empty() or not bool(it.get("enabled", true)):
		play("buzzer")
		return
	var d: Dictionary = it.data
	var rec := record(d.kind, d.id)
	if mode == "buy":
		var price := maxi(price_of(d), 0)
		qty_max = RPGGameState.MAX_ITEMS - owned(d.kind, d.id)
		if price > 0:
			qty_max = mini(qty_max, rpg.state.gold / price)
	else:
		qty_max = owned(d.kind, d.id)
	if qty_max <= 0:
		play("buzzer")
		return
	play("decision")
	qty_for = mode
	qty = 1
	qty_name.text = str(rec.get("name", d.id))
	_set_mode("quantity")
	_set_qty(1, false)


func _set_qty(n: int, sound := true) -> void:
	var before := qty
	qty = clampi(n, 1, maxi(qty_max, 1))
	if sound and qty != before:
		play("cursor")
	qty_value.text = "x %02d" % qty
	var d: Dictionary = list.current().get("data", {})
	var unit := price_of(d) if qty_for == "buy" else sell_price(str(d.get("kind", "items")), str(d.get("id", "")))
	qty_total.text = "Total %d %s" % [unit * qty, currency()]


## Buys `count` of a good. Returns false (and changes nothing) if the party cannot afford it.
func buy(good: Dictionary, count: int) -> bool:
	var kind := RPGGameState.kind_for(str(good.get("kind", "items")))
	var id := str(good.get("id", ""))
	var total := price_of({"kind": kind, "id": id, "price": good.get("price")}) * count
	if count <= 0 or total > rpg.state.gold or owned(kind, id) + count > RPGGameState.MAX_ITEMS:
		play("buzzer")
		return false
	rpg.state.change_gold("decrease", total)
	rpg.state.change_items(id, "increase", count, kind)
	bought.append({"kind": kind, "id": id, "count": count, "total": total})
	play("decision")
	return true


## Sells `count` of an owned item for half its database price.
func sell(kind: String, id: String, count: int) -> bool:
	kind = RPGGameState.kind_for(kind)
	var price := sell_price(kind, id)
	if count <= 0 or owned(kind, id) < count or price <= 0 or bool(record(kind, id).get("key_item", false)):
		play("buzzer")
		return false
	rpg.state.change_items(id, "decrease", count, kind)
	rpg.state.change_gold("increase", price * count)
	sold.append({"kind": kind, "id": id, "count": count, "total": price * count})
	play("decision")
	return true


func leave() -> void:
	if _done:
		return
	_done = true
	finished.emit({"bought": bought, "sold": sold})
