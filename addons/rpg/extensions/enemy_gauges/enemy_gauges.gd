extends "res://addons/rpg/runtime/rpg_extension.gd"
## Enemy HP gauges and popups (kit plugin "enemy_gauges").
## - An HP bar under each enemy (the battle scene's battler_node), shown always, while the enemy
##   is targeted (and a moment after it is hit), or once that enemy type has been defeated. It
##   drains smoothly; the lost part fades in its own colour. Enemies with the custom field
##   "hide_hp_gauge" (bosses) get none.
## - Styled damage popups (battle_popup): critical hits, misses and recovery each have a look,
##   and numbers pop in.
## - Enemy records: which enemy types were seen and defeated, in the save section
##   "enemy_records" {seen: {id: count}, defeated: {id: count}}. The bestiary plugin declares the
##   same section, so both read one Dictionary. The bestiary writes it when it is on (it counts
##   every battle); this plugin writes it only when the bestiary is off, so nothing counts twice.

const SECTION := "enemy_records"
const Gauge := preload("res://addons/rpg/extensions/enemy_gauges/enemy_gauge.gd")
const DamagePopup := preload("res://addons/rpg/extensions/enemy_gauges/damage_popup.gd")

## The battle scene running now (null outside battles).
var scene: Node = null
## RPGBattler -> gauge node, for the battle running now.
var gauges: Dictionary = {}
## Enemy types counted as seen in this battle (each counts once per battle).
var _seen_now: Dictionary = {}


# --- battle hooks ------------------------------------------------------------------------------

func on_battle_scene_ready(p_scene: Node) -> void:
	scene = p_scene
	gauges.clear()
	_seen_now.clear()
	if p_scene == null or not p_scene.has_method("battler_node") or p_scene.get("core") == null:
		return
	for e in p_scene.core.enemies:
		if not e.hidden:
			_see(e.id)
		if gauge_hidden_for(e.id):
			continue
		var g: Node2D = Gauge.new()
		g.setup(self, p_scene, e)
		p_scene.battler_node(e).add_child(g)
		gauges[e] = g


func on_turn_started(b: Object) -> void:
	# An enemy that appears during the battle (troop member "hidden") has been seen once it acts.
	if b != null and b.is_enemy():
		_see(b.id)


func on_battler_defeated(b: Object) -> void:
	if b != null and b.is_enemy():
		_note(b.id, "defeated")


func on_battle_ended(_outcome: String, _result: Variant) -> void:
	scene = null
	gauges.clear()


## Styled popups (the battle scene's battle_popup query). `node`: one an earlier extension made.
func battle_popup(battler: Object, text: String, style: String, node: Variant) -> Variant:
	if node != null or not bool(setting("popups", true)):
		return null
	var small: bool = battler != null and battler.is_actor() and scene != null and not scene.actor_nodes.has(battler)
	return DamagePopup.make(style, text, popup_settings(), rpg, small)


func popup_settings() -> Dictionary:
	return {
		"critical_text": str(setting("critical_text", "Critical!")),
		"miss_text": str(setting("miss_text", "Miss")),
		"heal_sign": bool(setting("heal_sign", true)),
		"damage": colour("colour_damage", Color.WHITE),
		"critical": colour("colour_critical", Color(1.0, 0.77, 0.25)),
		"heal": colour("colour_heal", Color(0.47, 1.0, 0.55)),
		"miss": colour("colour_miss", Color(0.75, 0.75, 0.78)),
	}


# --- gauges --------------------------------------------------------------------------------------

## True when the enemy record asks for no gauge (custom field "hide_hp_gauge").
func gauge_hidden_for(enemy_id: String) -> bool:
	return bool(rpg.extensions.custom_field("enemies", enemy_id, "hide_hp_gauge", false))


## "always", "targeted" or "defeated" (settings).
func show_mode() -> String:
	var m := str(setting("show", "always"))
	return m if m in ["always", "targeted", "defeated"] else "always"


## A colour setting ([r, g, b, a] 0-255, as the colour field stores it).
func colour(key: String, fallback: Color) -> Color:
	var v: Variant = setting(key, null)
	if v is Array and v.size() >= 3:
		return Color8(int(v[0]), int(v[1]), int(v[2]), int(v[3]) if v.size() > 3 else 255)
	if v is Color:
		return v
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback


func gauge_style() -> Dictionary:
	return {
		"width": clampi(int(setting("width", 40)), 16, 160),
		"height": clampi(int(setting("height", 4)), 2, 12),
		"numbers": str(setting("numbers", "none")),
		"full": colour("colour_full", Color(0.41, 0.85, 0.38)),
		"low": colour("colour_low", Color(0.91, 0.28, 0.22)),
		"drain": colour("colour_drain", Color(1.0, 0.89, 0.55)),
		"back": colour("colour_back", Color(0.05, 0.05, 0.09, 0.82)),
	}


# --- enemy records (shared with the bestiary) ----------------------------------------------------

## The shared record {seen: {id: n}, defeated: {id: n}} (the live save section).
func records() -> Dictionary:
	return section(SECTION)


## Times enemy type `enemy_id` has been defeated (all saves of this game so far).
func defeated_count(enemy_id: String) -> int:
	return int(records().get("defeated", {}).get(enemy_id, 0))


func was_defeated(enemy_id: String) -> bool:
	return defeated_count(enemy_id) > 0


func _see(enemy_id: String) -> void:
	if _seen_now.has(enemy_id):
		return
	_seen_now[enemy_id] = true
	_note(enemy_id, "seen")


## Counts a sighting (once per battle) or a defeat, unless the bestiary is on (it keeps the
## counts then).
func _note(enemy_id: String, what: String) -> void:
	if rpg.extension("bestiary") != null or enemy_id == "":
		return
	var rec := records()
	var d: Dictionary = rec.get(what, {})
	d[enemy_id] = int(d.get(enemy_id, 0)) + 1
	rec[what] = d
