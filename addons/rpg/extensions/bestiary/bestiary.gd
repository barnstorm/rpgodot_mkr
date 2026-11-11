extends "res://addons/rpg/runtime/rpg_extension.gd"
## Bestiary (kit plugin "bestiary").
## - Records every enemy type seen in battle (once per battle) and every defeat, in the save
##   section "enemy_records" {seen: {id: count}, defeated: {id: count}}. The enemy_gauges plugin
##   declares the same section and reads it (its "after the first defeat" gauges); while the
##   bestiary is on, only the bestiary writes it.
## - A Bestiary screen from the main menu and the Open bestiary command: category tabs,
##   completion, and per enemy the picture, stats, weaknesses and resistances (element rates
##   from the rule system), EXP and gold, drops and lore. What a seen or a defeated enemy shows is
##   a setting; never-seen enemies are masked (silhouette, ?????? or not listed).
## - Enemy custom fields: category (a category ID from the settings), lore, hide_in_bestiary.
## - Reveal enemy (command): marks one enemy, or every enemy, as seen or defeated.

const SECTION := "enemy_records"
const SCREEN := "res://addons/rpg/extensions/bestiary/bestiary_screen.gd"
## Detail levels, least to most.
const PARTS := ["name", "image", "stats", "all"]

var _seen_now: Dictionary = {}


# --- recording -----------------------------------------------------------------------------------

func on_battle_scene_ready(scene: Node) -> void:
	_seen_now.clear()
	if scene == null or scene.get("core") == null:
		return
	for e in scene.core.enemies:
		if not e.hidden:
			see(e.id)


func on_turn_started(b: Object) -> void:
	if b != null and b.is_enemy():
		see(b.id)


func on_battler_defeated(b: Object) -> void:
	if b != null and b.is_enemy():
		see(b.id)
		_add("defeated", b.id, 1)


## Counts a sighting of `enemy_id` (once per battle).
func see(enemy_id: String) -> void:
	if enemy_id == "" or _seen_now.has(enemy_id):
		return
	_seen_now[enemy_id] = true
	_add("seen", enemy_id, 1)


func _add(what: String, enemy_id: String, n: int) -> void:
	var rec := records()
	var d: Dictionary = rec.get(what, {})
	d[enemy_id] = int(d.get(enemy_id, 0)) + n
	rec[what] = d


func records() -> Dictionary:
	return section(SECTION)


func seen_count(enemy_id: String) -> int:
	return int(records().get("seen", {}).get(enemy_id, 0))


func defeated_count(enemy_id: String) -> int:
	return int(records().get("defeated", {}).get(enemy_id, 0))


## Reveal enemy: "seen" or "defeated" (a defeat counts as seen too); `enemy_id` "" = all.
func reveal(enemy_id: String, level := "seen") -> void:
	var ids: Array = [enemy_id] if enemy_id != "" else listed_ids(true)
	for id in ids:
		if seen_count(id) <= 0:
			_add("seen", id, 1)
		if level == "defeated" and defeated_count(id) <= 0:
			_add("defeated", id, 1)


# --- the book ------------------------------------------------------------------------------------

## Enemy IDs in the book, in Database order (hide_in_bestiary left out). With the "hidden" mask,
## enemies never seen are left out too unless `all`.
func listed_ids(all := false) -> Array:
	var out := []
	var hide_unseen := str(setting("mask", "silhouette")) == "hidden" and not all
	for rec in rpg.data.records("enemies"):
		var id := str(rec.get("id", ""))
		if id == "" or bool(custom(id, "hide_in_bestiary", false)):
			continue
		if hide_unseen and seen_count(id) <= 0 and defeated_count(id) <= 0:
			continue
		out.append(id)
	return out


func custom(enemy_id: String, key: String, fallback: Variant) -> Variant:
	return rpg.extensions.custom_field("enemies", enemy_id, key, fallback)


## [{id, label}]: "all" first, then the settings' categories.
func categories() -> Array:
	var out := [{"id": "", "label": "All"}]
	for c in setting("categories", []):
		if c is Dictionary and str(c.get("id", "")).strip_edges() != "":
			var cid := str(c.id).strip_edges()
			out.append({"id": cid, "label": str(c.get("label", cid)) if str(c.get("label", "")) != "" else cid})
	return out


## Enemy IDs of a category ("" = all).
func ids_in(category: String) -> Array:
	var all_ids := listed_ids()
	if category == "":
		return all_ids
	return all_ids.filter(func(id): return str(custom(id, "category", "")).strip_edges() == category)


## "none", "seen" or "defeated".
func known(enemy_id: String) -> String:
	if defeated_count(enemy_id) > 0:
		return "defeated"
	if seen_count(enemy_id) > 0:
		return "seen"
	return "none"


## True when `part` ("name", "image", "stats" or "all": drops, weaknesses, lore) of the enemy is
## shown, from what is known of it and the settings.
func reveals(enemy_id: String, part: String) -> bool:
	var k := known(enemy_id)
	if k == "none":
		return false
	var limit := str(setting("defeated_shows" if k == "defeated" else "seen_shows", "all" if k == "defeated" else "image"))
	return PARTS.find(part) <= maxi(0, PARTS.find(limit))


## {total, seen, defeated, percent} for a category ("" = all); percent = defeated / total.
## Counted over every enemy of the category, also those the "hidden" mask leaves out.
func completion(category := "") -> Dictionary:
	var ids := listed_ids(true)
	if category != "":
		ids = ids.filter(func(id): return str(custom(id, "category", "")).strip_edges() == category)
	var seen := 0
	var beaten := 0
	for id in ids:
		if seen_count(id) > 0 or defeated_count(id) > 0:
			seen += 1
		if defeated_count(id) > 0:
			beaten += 1
	var pct := 0 if ids.is_empty() else int(floor(100.0 * beaten / ids.size()))
	return {"total": ids.size(), "seen": seen, "defeated": beaten, "percent": pct}


## Weaknesses and resistances from the rule system's element rates: [{id, name, rate (x1.0),
## icon}] for every element whose rate is not 1. Sorted strongest weakness first.
func element_rates(enemy_id: String) -> Array:
	var out := []
	var b: Object = enemy_battler(enemy_id)
	if b == null:
		return out
	var types: Dictionary = rpg.data.record("types", "elements")
	for el in types.get("entries", []):
		if not (el is Dictionary):
			continue
		var eid := str(el.get("id", ""))
		var rate := float(rpg.rules.trait_rate(b, "element_rate", eid))
		if not is_equal_approx(rate, 1.0):
			out.append({"id": eid, "name": str(el.get("name", eid)), "rate": rate, "icon": el.get("icon", 0)})
	out.sort_custom(func(x, y): return float(x.rate) > float(y.rate))
	return out


## The enemy as a battler (its stats), made with a private RNG so looking at the book never moves
## the game's random numbers.
func enemy_battler(enemy_id: String) -> Object:
	if rpg.rules == null:
		return null
	var saved: Variant = rpg.rules.rng
	rpg.rules.rng = RPGRandom.new(hash(enemy_id))
	var b: Object = rpg.rules.new_enemy_battler(enemy_id)
	rpg.rules.rng = saved
	return b


# --- menu ----------------------------------------------------------------------------------------

func menu_entry_shown() -> bool:
	return bool(setting("menu_entry", true))


func adjust_menu(layout: Array, _config: Dictionary) -> void:
	for item in layout:
		if str(item.get("id", "")) == "bestiary" and str(item.get("ext", "")) == extension_id:
			item["label"] = str(setting("menu_label", "Bestiary"))
			var icon: Variant = setting("menu_icon", 0)
			if icon != null and int(icon) > 0:
				item["icon"] = int(icon)
			else:
				item.erase("icon")


func open_from_menu(_menu: Node) -> String:
	await open_screen()
	return ""


func open_screen() -> void:
	var node := make_screen()
	if node == null:
		return
	await node.closed
	rpg.ui.close_scene(node)


func make_screen() -> Node:
	if rpg.ui == null:
		return null
	var node: Node = rpg.ui.open_scene(SCREEN)
	if node != null:
		node.setup(self)
	return node
