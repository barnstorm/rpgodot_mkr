extends "res://addons/rpg/runtime/rpg_extension.gd"
## Item crafting (kit plugin "crafting").
##   A recipe is a custom field on the item, weapon or armour it makes (Database > Custom fields >
##   Recipe): ingredients (items, weapons or armour, each with an amount), how many one craft
##   makes, a crafting category and an optional switch that must be ON for the recipe to be
##   listed.
##   The Crafting screen (main menu "Crafting", or Open crafting with some categories only) lists
##   the recipes, how many of each ingredient the party has and needs, and makes as many as asked.
##   Recipes the party cannot afford are greyed out. A recipe is known once the party has held
##   every ingredient (or made it before); unknown ones are masked, greyed out, left out or shown
##   (a setting).
## Saved with the game: {crafted: {"items:potion": count}, seen: {"items:herb": true}}.

signal crafted(kind: String, id: String, count: int)

const SECTION := "crafting"
const SCREEN := "res://addons/rpg/extensions/crafting/crafting_screen.gd"
const KINDS := ["items", "weapons", "armors"]

var _state: Object = null


func _extension_ready() -> void:
	_watch_state()
	_scan_inventory()


func _exit_tree() -> void:
	if _state != null and is_instance_valid(_state) and _state.items_changed.is_connected(_on_items_changed):
		_state.items_changed.disconnect(_on_items_changed)
	_state = null


func _watch_state() -> void:
	if rpg == null or rpg.state == null or _state == rpg.state:
		return
	_exit_tree()
	_state = rpg.state
	_state.items_changed.connect(_on_items_changed)


func _data() -> Dictionary:
	var s := section(SECTION)
	for k in ["crafted", "seen"]:
		if not (s.get(k) is Dictionary):
			s[k] = {}
	return s


func on_new_game() -> void:
	_watch_state()
	_scan_inventory()


func on_game_loaded() -> void:
	_watch_state()
	_scan_inventory()


func _on_items_changed(kind: String, id: String, count: int) -> void:
	if count > 0:
		mark_seen(RPGGameState.kind_for(kind), id)


## Marks every item the party holds now, and the equipment party members wear, as seen.
func _scan_inventory() -> void:
	if rpg == null or rpg.state == null:
		return
	for b in rpg.state.party_battlers():
		if b is Object and "equips" in b and b.equips is Dictionary:
			for slot in b.equips:
				var eid := str(b.equips[slot])
				if eid != "":
					mark_seen("weapons" if rpg.data.has_record("weapons", eid) else "armors", eid)
	for kind in KINDS:
		var inv: Variant = rpg.state.inventory.get(kind, {})
		if inv is Dictionary:
			for id in inv:
				if int(inv[id]) > 0:
					mark_seen(kind, str(id))


static func key(kind: String, id: String) -> String:
	return "%s:%s" % [RPGGameState.kind_for(kind), id]


func mark_seen(kind: String, id: String) -> void:
	_data().seen[key(kind, id)] = true


func seen(kind: String, id: String) -> bool:
	return _data().seen.has(key(kind, id))


## How many of a thing the party has made so far.
func crafted_count(kind: String, id: String) -> int:
	return int(_data().crafted.get(key(kind, id), 0))


# --- recipes -------------------------------------------------------------------------------------

## The recipe of an item, weapon or armour ({} when it has none): {ingredients: [{kind, id,
## count}], yield, category, switch}.
func recipe(kind: String, id: String) -> Dictionary:
	kind = RPGGameState.kind_for(kind)
	var rec: Dictionary = rpg.data.record(kind, id) if rpg.data != null else {}
	var custom: Variant = rec.get("custom", {})
	var r: Variant = custom.get("recipe") if custom is Dictionary else null
	if not (r is Dictionary) or r.is_empty():
		return {}
	var ings := []
	for ing in r.get("ingredients", []):
		if ing is Dictionary and str(ing.get("id", "")) != "":
			ings.append({"kind": RPGGameState.kind_for(str(ing.get("kind", "items"))), "id": str(ing.id), "count": maxi(1, int(ing.get("count", 1)))})
	if ings.is_empty():
		return {}
	return {"ingredients": ings, "yield": maxi(1, int(r.get("yield", 1))), "category": str(r.get("category", "")), "switch": str(r.get("switch", ""))}


## Recipes listed now, in Database order (items, weapons, armour): [{kind, id, recipe}]. Only the
## listed categories when `categories` is not empty; recipes whose switch is OFF are left out.
func recipes(categories: Array = []) -> Array:
	var out := []
	var cats := categories.map(func(c): return str(c).strip_edges().to_lower()).filter(func(c): return c != "")
	for kind in KINDS:
		for rec in rpg.data.records(kind):
			if not (rec is Dictionary) or str(rec.get("id", "")) == "":
				continue
			var r := recipe(kind, str(rec.id))
			if r.is_empty():
				continue
			if not cats.is_empty() and not cats.has(r.category.to_lower()):
				continue
			if r.switch != "" and not rpg.state.get_switch(r.switch):
				continue
			out.append({"kind": kind, "id": str(rec.id), "recipe": r})
	return out


## Known: made before, or every ingredient has been held at some time.
func known(kind: String, id: String) -> bool:
	if crafted_count(kind, id) > 0:
		return true
	var r := recipe(kind, id)
	for ing in r.get("ingredients", []):
		if not seen(ing.kind, ing.id):
			return false
	return not r.is_empty()


## How many times the recipe can be made now (ingredients, and room in the bag for the result).
func max_crafts(kind: String, id: String) -> int:
	var r := recipe(kind, id)
	if r.is_empty():
		return 0
	var n := 9999
	for ing in r.ingredients:
		n = mini(n, rpg.state.item_count(ing.id, ing.kind) / int(ing.count))
	var room: int = RPGGameState.MAX_ITEMS - rpg.state.item_count(id, RPGGameState.kind_for(kind))
	n = mini(n, room / int(r.yield))
	return maxi(0, n)


## Makes the recipe `times` times: takes the ingredients, gives the result, plays the sound.
## Returns false (and changes nothing) when the party cannot.
func craft(kind: String, id: String, times := 1) -> bool:
	kind = RPGGameState.kind_for(kind)
	var r := recipe(kind, id)
	if r.is_empty() or times < 1 or times > max_crafts(kind, id):
		return false
	for ing in r.ingredients:
		rpg.state.change_items(ing.id, "decrease", int(ing.count) * times, ing.kind)
	var made := int(r.yield) * times
	rpg.state.change_items(id, "increase", made, kind)
	var d := _data()
	d.crafted[key(kind, id)] = crafted_count(kind, id) + made
	mark_seen(kind, id)
	var snd: Variant = setting("sound", {})
	if rpg.audio != null:
		if snd is Dictionary and str(snd.get("file", "")) != "":
			rpg.audio.play_se(snd)
		else:
			rpg.audio.play_role("chest_open")
	crafted.emit(kind, id, made)
	return true


# --- menu ----------------------------------------------------------------------------------------

func menu_entry_shown() -> bool:
	return bool(setting("menu_entry", true))


func adjust_menu(layout: Array, _config: Dictionary) -> void:
	for it in layout:
		if str(it.get("id", "")) == "crafting" and str(it.get("ext", "")) == extension_id:
			it["label"] = str(setting("menu_label", "Crafting"))
