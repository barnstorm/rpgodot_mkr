extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default battle scene, driven by RPGBattleCore (all game math lives in the rule system).
## Battle contract:
##   start({troop, can_escape, can_lose, background, auto?, battle_view?, battle_system?,
##          atb_mode?, advantage?}, {rpg, state, rules, interpreter})
##   finished({outcome: "win"|"lose"|"escape", rewards: {exp, gold, items}}) or cancelled(reason)
## Capabilities: turn order, action selection, target choice, battle events, escape, defeat.
##
## Two independent choices, each taken from the battle args, else the troop record, else the
## current map's properties, else Database > System (a blank value passes it on):
##   battle_view    "front" (2000 / VX Ace: enemies only) or "side" (2003 / MV: enemies on the
##                  left, the party on the right drawn with RPGBattleActorSprite).
##   battle_system  "turn" (everyone picks, then everyone acts), "atb" (2003 / MZ Time Progress:
##                  gauges fill by agility; atb_mode "wait" stops time while a command window is
##                  open, "active" does not) or "ctb" (the same gauges, time jumps to the next
##                  turn and the coming turn order is shown).
## args.advantage: "preemptive" (the party moves first) or "surprise" (the enemies do).
## The defaults (front, turn) are the battle as it always was.
##
## Extension hooks (docs/ARCHITECTURE.md "Battle hooks"): the core reports through rpg.battle_hook
## (turn_started, action_chosen, damage_calculated, state_changed, battler_defeated); the scene adds
##   battle_scene_ready(scene)        once the stage is built (entry scripts: on_battle_scene_ready)
##   victory(rewards)                 before the rewards are applied; may change them
##   battler_node(b) -> Node2D        a node per battler that follows it (both views)
##   entry-script queries: battle_members(members) -> Array (who fights), victory_scene(info) ->
##   Node (replaces the reward messages), battle_popup(battler, text, style, node) -> Control
##   (replaces a damage popup).
##
## Party battlers are the RPGBattler objects in rpg.state.actors, so HP/SP and states persist.
## Battle events: at each core checkpoint the eligible troop pages run through an
## RPGInterpreter (owner kind "battle_event") while the battle waits; the message box shows on
## top of the battle. Enemy Appear calls enemy_appear(member_index) on the scene (a custom battle
## scene that wants the command implements the same method). Auto mode (args.auto or
## rpg.ui.auto_advance): every actor attacks the first living enemy and text waits are skipped
## (headless tests); timed battles then jump straight from one turn to the next.

signal finished(result: Variant)
signal cancelled(reason: String)
signal _input_done(choice: String)

const CAPABILITIES := ["turn_order", "action_selection", "target_choice", "battle_events", "escape", "defeat"]
const FIELD_H := 160
const HP_COLOUR := Color(1.0, 0.62, 0.25)
const SP_COLOUR := Color(0.38, 0.68, 1.0)
const BATTLE_OCCASIONS := ["always", "battle"]
const ENEMY_SCOPES := ["one_enemy"]
const ALLY_PICK_SCOPES := ["one_ally", "one_dead_ally"]
## Status window columns: name, then the two resources (gauge widths), then states in the rest.
const STATUS_ROW_W := 228.0
const STATUS_NAME_W := 60.0
const STATUS_RES_W := [64.0, 50.0]
const ActorSprite := preload("res://addons/rpg/runtime/ui/battle/rpg_battle_actor_sprite.gd")
const VIEWS := ["front", "side"]
const ATB_COLOUR := Color(0.45, 0.9, 0.55)
const ATB_FULL_COLOUR := Color(1.0, 0.95, 0.5)
## Side view: how far an actor steps forward to act or choose, and how long the step takes.
const STEP_X := 22.0
const STEP_SECONDS := 0.14
## CTB: turns shown in the order strip.
const ORDER_COUNT := 6

var core: RPGBattleCore
## "front" or "side"; "turn", "atb" or "ctb"; "wait" or "active" (see the class notes).
var battle_view := "front"
var battle_system := "turn"
var atb_mode := "wait"
## Side view: RPGBattler (actor) -> its sprite.
var actor_nodes: Dictionary = {}
## Timed battles: the actor whose command window is open, or null.
var input_actor: RPGBattler = null
## Timed battles: true while time is frozen for the open command window (ATB wait mode, CTB).
var time_stopped := false
var args: Dictionary = {}
var context: Dictionary = {}
var auto := false
var troop: Dictionary = {}
var outcome := ""
var rewards: Dictionary = {}
## [{actor, level_ups}] after a win (tests / extensions).
var level_ups: Array = []
## Every line shown in the log, in order (tests / debugging).
var log_lines: Array = []

var stage: Control
var field: Control
var popups: Control
var enemy_nodes: Dictionary = {}       # RPGBattler -> TextureRect
var log_win: Panel
var log_label: Label
var cmd_win: Panel
var cmd_list: Control
var status_win: Panel
var status_rows: Control
var status_cursor: Panel
var select_win: Panel
var select_list: Control
var target_arrow: Control

# input state
var phase := ""                        # party, actor, skill, item, target_enemy, target_ally
var inputs: Array = []
var input_pos := 0
var pending: Dictionary = {}
var target_index := 0
var _target_return := ""
var _pending_checkpoints: Array = []
var _t := 0.0
var _started := false
var _done := false
var _atb_fills: Dictionary = {}        # RPGBattler -> gauge fill ColorRect (ATB)
var _timed_escape := false             # the party command chose Escape (timed battles)
var _inputting: RPGBattler = null      # side view: the actor standing forward to choose
var _order_strip: Control              # CTB turn order
var _tab_down := false                 # Tab held (ATB: pass the turn on the press)
var _shown_count := 0                  # CTB: tags that fit in the strip
## Extension nodes, one per battler (battler_node): RPGBattler -> Node2D, under battler_layer.
var battler_layer: Control
var _battler_nodes: Dictionary = {}
## After a win: one entry per living actor {actor, id, name, old_level, new_level, old_exp,
## new_exp, level_ups, old_stats, new_stats, learned} (victory_scene, tests).
var victory_actors: Array = []
## True when the battle was ended with rewards withheld (battle facade end("win", false)).
var skip_rewards := false
## Actors added mid-battle "only for this battle" (removed again when it ends).
var _temp_actors: Array[String] = []


func _build() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(W, H)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	stage = Control.new()
	stage.size = Vector2(W, H)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	field = Control.new()
	field.size = Vector2(W, FIELD_H)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(field)
	popups = Control.new()
	popups.size = Vector2(W, H)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popups.z_index = 5
	log_win = make_window(Rect2(0, 0, W, 24))
	log_label = make_label(log_win, Vector2(8, 4), "", FONT, null, W - 16)
	log_win.visible = false
	cmd_win = make_window(Rect2(0, FIELD_H, 80, 80))
	cmd_list = make_list(cmd_win, Rect2(5, 8, 70, 4 * ROW))
	cmd_win.visible = true
	status_win = make_window(Rect2(80, FIELD_H, 240, 80))
	status_cursor = Panel.new()
	if has_theme_stylebox("cursor", "RPGWindow"):
		status_cursor.add_theme_stylebox_override("panel", get_theme_stylebox("cursor", "RPGWindow"))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.15)
		sb.border_color = Color(1, 1, 1, 0.85)
		sb.set_border_width_all(1)
		status_cursor.add_theme_stylebox_override("panel", sb)
	status_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_cursor.visible = false
	status_win.add_child(status_cursor)
	status_rows = Control.new()
	status_rows.position = Vector2(6, 6)
	status_rows.size = Vector2(228, 68)
	status_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_win.add_child(status_rows)
	select_win = make_window(Rect2(0, FIELD_H, W, 80))
	select_list = make_list(select_win, Rect2(6, 8, W - 12, 64), 2)
	select_win.visible = false
	# Above the stage and the windows, under the target arrow, the popups and the message box.
	battler_layer = Control.new()
	battler_layer.name = "BattlerNodes"
	battler_layer.size = Vector2(W, H)
	battler_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(battler_layer)
	target_arrow = Control.new()
	target_arrow.size = Vector2(10, 8)
	target_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_arrow.draw.connect(func():
		target_arrow.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(5, 7)]), Color(1, 1, 0.6))
		target_arrow.draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(5, 7), Vector2(0, 0)]), Color(0, 0, 0, 0.8), 1.0))
	target_arrow.visible = false
	target_arrow.z_index = 6
	add_child(target_arrow)
	add_child(popups)


func capabilities() -> Array:
	return CAPABILITIES.duplicate()


## Battle contract entry point.
func start(p_args: Dictionary, p_context: Variant = null) -> void:
	args = p_args
	context = p_context if p_context is Dictionary else {}
	if rpg == null and context.has("rpg"):
		rpg = context.rpg
	auto = bool(args.get("auto", false)) or auto_mode()
	troop = record("troops", str(args.get("troop", "")))
	if troop.is_empty() or rules() == null:
		_fail.call_deferred("Battle: enemy group '%s' does not exist." % args.get("troop", "") if troop.is_empty() else "Battle: no rule system.")
		return
	var members: Array = battle_members()
	var rng: RPGRandom = rpg.rng if rpg.rng is RPGRandom else RPGRandom.new()
	core = RPGBattleCore.new(members, troop, rules(), rng)
	core.item_consumer = func(id: String) -> bool:
		if rpg.state.item_count(id) <= 0:
			return false
		rpg.state.change_items(id, "decrease", 1)
		return true
	core.item_refund = func(id: String) -> void: rpg.state.change_items(id, "increase", 1)
	core.switch_reader = func(id: String) -> bool: return rpg.state.get_switch(id)
	core.condition_reader = extension_condition
	if rpg.has_method("battle_hook"):
		core.hooks = rpg
	core.checkpoint.connect(func(kind: String): _pending_checkpoints.append(kind))
	_resolve_style()
	core.battle_system = battle_system
	core.atb_mode = atb_mode
	core.advantage = str(args.get("advantage", "normal"))
	core.start()
	core.can_escape = core.can_escape and bool(args.get("can_escape", true))
	_make_backdrop(str(args.get("background", "")))
	_make_enemies()
	if battle_view == "side":
		_make_party()
	if battle_system == "ctb":
		_make_order_strip()
	_refresh_status()
	_idle_command_window()
	var music: Variant = battle_music("battle")
	if music != null and rpg.audio:
		rpg.audio.play_bgm(music)
	_started = true
	# The public battle API (rpg.battle): valid from now until the battle ends.
	if rpg != null and "battle" in rpg:
		rpg.battle = RPGBattleFacade.new(self)
	_hook("battle_scene_ready", [self])
	_place_battler_nodes()
	_run.call_deferred()


func _exit_tree() -> void:
	if rpg != null and "battle" in rpg and rpg.battle != null and rpg.battle.scene() == self:
		rpg.battle = null


# --- extension hooks -----------------------------------------------------------------------------

## rpg.battle_hook when the service has it; {args, cancel}.
func _hook(hook_name: String, args: Array, mode := "") -> Dictionary:
	if rpg != null and rpg.has_method("battle_hook"):
		return rpg.battle_hook(hook_name, args, mode)
	return {"args": args, "cancel": false}


## The extension host when it can run entry-script queries, else null.
func _ext_host() -> Node:
	var host: Variant = rpg.get("extensions") if rpg != null else null
	return host if host is Node and is_instance_valid(host) and host.has_method("run_hook") else null


## The actors who fight: the party, filtered by entry scripts' battle_members(members) -> Array
## (party formation), at most 4.
func battle_members() -> Array:
	var members: Array = party()
	var host := _ext_host()
	if host != null:
		var m: Variant = host.run_hook("battle_members", [members], "value").args[0]
		if m is Array:
			var picked: Array = (m as Array).filter(func(x): return x is RPGBattler)
			if not picked.is_empty():
				members = picked
	return members.slice(0, 4)


## Troop page conditions the core does not know: extension kinds marked "battle": true and the
## game state's own kinds (variable, item, gold, actor...) through rpg.state.check_condition.
func extension_condition(c: Dictionary) -> bool:
	var kind := str(c.get("kind", ""))
	var decl: Dictionary = rpg.registry.condition_kinds().get(kind, {}) if rpg != null and rpg.registry != null else {}
	if not decl.is_empty() and not bool(decl.get("battle", false)):
		push_warning("Battle page: condition kind '%s' (extension '%s') is not marked \"battle\": true." % [kind, decl.get("extension", "")])
		return false
	if rpg == null or rpg.state == null:
		return false
	return rpg.state.check_condition(c)


## A node that follows battler `b` (made on first use, freed with the battle), for extensions:
## HP and ATB gauges, cast bars, icons. Its origin is the bottom centre of battler_rect(b): under
## an enemy's image, at a side-view actor's feet, at the bottom of a front-view actor's status
## row. It is hidden while the battler is (not yet appeared, collapsed, escaped) and fades with
## the status window in the front view.
func battler_node(b: RPGBattler) -> Node2D:
	var n: Variant = _battler_nodes.get(b)
	if n is Node2D and is_instance_valid(n):
		return n
	var node := Node2D.new()
	node.name = "%s_%d" % [b.kind.capitalize(), b.index]
	battler_layer.add_child(node)
	_battler_nodes[b] = node
	_place_battler_node(b, node)
	return node


## The battler's figure in this scene's coordinates: an enemy's image, a side-view actor's
## figure, or a front-view actor's status row.
func battler_rect(b: RPGBattler) -> Rect2:
	var off := stage.position + field.position
	if b.is_enemy() and enemy_nodes.has(b):
		var s: TextureRect = enemy_nodes[b]
		return Rect2(off + s.position, s.size)
	if actor_nodes.has(b):
		var r: Rect2 = actor_nodes[b].figure_rect()
		return Rect2(off + r.position, r.size)
	var i := core.party.find(b) if core != null else -1
	return Rect2(status_win.position + status_rows.position + Vector2(0, maxi(i, 0) * 17), Vector2(STATUS_ROW_W, 17))


func _battler_shown(b: RPGBattler) -> bool:
	if b.is_enemy():
		var s: Variant = enemy_nodes.get(b)
		return s is TextureRect and s.visible and not b.hidden
	if actor_nodes.has(b):
		return actor_nodes[b].visible
	return status_win.visible and core != null and core.party.has(b)


func _place_battler_node(b: RPGBattler, n: Node2D) -> void:
	var r := battler_rect(b)
	n.position = Vector2(round(r.position.x + r.size.x / 2.0), round(r.end.y))
	n.visible = _battler_shown(b)
	if b.is_actor() and not actor_nodes.has(b):
		n.modulate.a = status_win.modulate.a


func _place_battler_nodes() -> void:
	for b in _battler_nodes:
		var n: Variant = _battler_nodes[b]
		if n is Node2D and is_instance_valid(n):
			_place_battler_node(b, n)


## Battle view, system and ATB mode: battle args, then the troop, then the current map's
## properties, then Database > System; blank or unknown values pass the choice on.
func _resolve_style() -> void:
	var map_props: Dictionary = {}
	if rpg != null and rpg.has_method("current_map"):
		var m: Node = rpg.current_map()
		if m != null and "props" in m and m.props is Dictionary:
			map_props = m.props
	var system: Dictionary = rpg.data.system if rpg != null and rpg.data != null and rpg.data.system is Dictionary else {}
	battle_view = _first_valid("battle_view", [args, troop, map_props, system], VIEWS, "front")
	battle_system = _first_valid("battle_system", [args, troop, map_props, system], RPGBattleCore.BATTLE_SYSTEMS, "turn")
	atb_mode = _first_valid("atb_mode", [args, troop, map_props, system], ["wait", "active"], "wait")


static func _first_valid(key: String, sources: Array, allowed: Array, fallback: String) -> String:
	for s in sources:
		if s is Dictionary and allowed.has(str(s.get(key, ""))):
			return str(s[key])
	return fallback


func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	push_error(reason)
	cancelled.emit(reason)


# --- visuals -------------------------------------------------------------------------------

func _make_backdrop(bg_name: String) -> void:
	var tex: Texture2D = null
	if bg_name != "" and rpg and rpg.ui:
		tex = rpg.ui.load_texture("backdrop", bg_name)
	if tex == null:
		var sky := full_rect_texture(gradient_texture(Color(0.22, 0.38, 0.72), Color(0.18, 0.32, 0.14), Color(0.62, 0.78, 0.95)), stage, Rect2(0, 0, W, FIELD_H))
		stage.move_child(sky, 0)
		var ground := full_rect_texture(gradient_texture(Color(0.36, 0.55, 0.25), Color(0.16, 0.28, 0.1)), stage, Rect2(0, 96, W, FIELD_H - 96))
		stage.move_child(ground, 1)
		var bottom := ColorRect.new()
		bottom.color = Color(0.05, 0.07, 0.05)
		bottom.position = Vector2(0, FIELD_H)
		bottom.size = Vector2(W, H - FIELD_H)
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(bottom)
		stage.move_child(bottom, 2)
		return
	var rect := Rect2(0, 0, W, H) if tex.get_height() > FIELD_H else Rect2(0, 0, W, FIELD_H)
	var tr := full_rect_texture(tex, stage, rect)
	stage.move_child(tr, 0)


func _make_enemies() -> void:
	for e in core.enemies:
		var rec := record("enemies", e.id)
		var tex: Texture2D = rpg.ui.load_texture("battler", str(rec.get("battler", ""))) if rpg.ui and str(rec.get("battler", "")) != "" else null
		if tex != null and RPGAssets.sheet_profile("battler", str(rec.get("battler", "")), str(rpg.data.profile.get("profile", "rm2k"))) == "rm2k":
			# 2000/2003 Monster graphics copied in by hand (not through the importer) have no alpha:
			# their background is palette colour 0, which is the top-left pixel. Key it.
			tex = RPGCharset.prepared_texture(tex)
		if tex == null:
			tex = _silhouette(e.id)
		var spr := TextureRect.new()
		spr.texture = tex
		# Battlers are painted for their maker's screen (2k 320, VX 544, MV 816 px wide); the stage
		# is laid out at W, so VX/MV battlers shrink to keep their on-screen proportions.
		var k := battler_scale(str(rec.get("battler", "")))
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_SCALE
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if k >= 1.0 else CanvasItem.TEXTURE_FILTER_LINEAR
		# A battler taller than the stage is shrunk to fit it (keeping its aspect).
		var max_h := float(FIELD_H - 6)
		if tex.get_height() * k > max_h:
			k = max_h / tex.get_height()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.size = (tex.get_size() * k).round()
		var c: Vector2 = e.screen_position
		if c == Vector2.ZERO:
			c = Vector2(W / 2.0 + (e.index - (core.enemies.size() - 1) / 2.0) * 64, 100)
		if battle_view == "side":
			c = side_enemy_position(c)
		# Centred on its troop position, but never below the stage floor or above its top edge.
		var top := clampf(c.y - spr.size.y / 2, 2.0, maxf(2.0, FIELD_H - 4 - spr.size.y))
		spr.position = Vector2(round(c.x - spr.size.x / 2), round(top))
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.visible = not e.hidden
		var hue := float(rec.get("battler_hue", 0))
		if hue != 0.0:
			spr.self_modulate = Color.from_hsv(fposmod(hue / 360.0, 1.0), 0.35, 1.0)
		field.add_child(spr)
		enemy_nodes[e] = spr


## Side view: a troop position (laid out for the front view across the whole 320 px stage) moved
## into the left part of the stage, keeping the enemies' order and spacing, so they face the party
## on the right.
static func side_enemy_position(c: Vector2) -> Vector2:
	return Vector2(round(18.0 + c.x * 0.52), c.y)


## Side view: the band of the stage the party stands in (below the message line).
const SIDE_TOP := 24.0
const SIDE_FLOOR := FIELD_H - 1.0
## At most this share of an actor's figure may be hidden by the actor in front of it (drawn later,
## lower and further right). Only when the stage is too short is SIDE_COVER_TIGHT allowed, and
## after that every figure shrinks.
const SIDE_COVER := 1.0 / 3.0
const SIDE_COVER_TIGHT := 0.4


## Side view: where each actor stands (feet), in a diagonal row on the right as in RPG Maker MV,
## from the figures' visible heights and widths (stage pixels, party order). Each actor stands low
## enough below the one before that it hides at most SIDE_COVER of that one's height, whatever the
## horizontal positions, so an actor stepping forward does not cover its neighbour either.
## Returns {homes: [Vector2], scale: float}; scale < 1 means every figure must shrink by it.
static func side_layout(heights: Array, widths: Array = []) -> Dictionary:
	var n := heights.size()
	if n == 0:
		return {"homes": [], "scale": 1.0}
	var avail := SIDE_FLOOR - SIDE_TOP
	var scale := 1.0
	var feet := _side_feet(heights, SIDE_COVER)
	if _side_span(heights, feet) > avail:
		feet = _side_feet(heights, SIDE_COVER_TIGHT)
	var span := _side_span(heights, feet)
	if span > avail:
		scale = avail / span
		for i in n:
			feet[i] = float(feet[i]) * scale
		span = avail
	var top := 0.0
	for i in n:
		top = minf(top, float(feet[i]) - float(heights[i]) * scale)
	var y0 := SIDE_TOP + (avail - span) * 0.5 - top
	var avg_w := 24.0
	if not widths.is_empty():
		avg_w = 0.0
		for w in widths:
			avg_w += float(w)
		avg_w = avg_w * scale / widths.size()
	var dx := clampf(avg_w * 0.65, 10.0, 22.0)
	var homes := []
	for i in n:
		homes.append(Vector2(round(W * 0.66 + i * dx), round(y0 + float(feet[i]))))
	return {"homes": homes, "scale": scale}


## Feet heights relative to the first actor: each one low enough to hide at most `cover` of the
## one before it (and at least 10 px lower, so the row stays diagonal).
static func _side_feet(heights: Array, cover: float) -> Array:
	var feet := [0.0]
	for i in range(1, heights.size()):
		var dy := maxf(10.0, float(heights[i]) - cover * float(heights[i - 1]))
		feet.append(float(feet[i - 1]) + dy)
	return feet


static func _side_span(heights: Array, feet: Array) -> float:
	var top := 0.0
	for i in heights.size():
		top = minf(top, float(feet[i]) - float(heights[i]))
	return float(feet[-1]) - top


## Side view: the actor sprites, in party order. A party mixing sources (an MV sheet, a 2003
## BattleCharSet, a walk sprite) is evened out to the tallest figure's height, so nobody looks
## half-size next to the others; one source keeps its maker's own proportions.
func _make_party() -> void:
	_sync_actor_nodes()


## Side view: brings the actor sprites in step with core.party (Change Party Member during the
## battle), then lays the field out again so the actors never overlap. Called by _make_party().
func _sync_actor_nodes() -> void:
	var sprites := []
	var prof := str(rpg.data.profile.get("profile", "rm2k")) if rpg != null and rpg.data != null else "rm2k"
	var sources := {}
	var tallest := 0.0
	for b in actor_nodes.keys():
		if not core.party.has(b):
			var stale: Variant = actor_nodes[b]
			if stale is Node and is_instance_valid(stale):
				stale.queue_free()
			actor_nodes.erase(b)
	for b in core.party:
		if not actor_nodes.has(b):
			var fresh: Control = ActorSprite.new()
			fresh.actor_id = b.id
			fresh.setup(ActorSprite.resolve(actor_battle_look(b.id), prof), W)
			fresh.name = "Actor_%s" % b.id
			field.add_child(fresh)
			actor_nodes[b] = fresh
		var spr: Control = actor_nodes[b]
		sprites.append(spr)
		sources["%s@%s" % [spr.kind, spr.native_k]] = true
		tallest = maxf(tallest, spr.figure_height())
	if sources.size() > 1:
		for spr in sprites:
			if spr.figure_height() > 0.0:
				spr.set_scale_k(spr.native_k * tallest / spr.figure_height())
	var heights := []
	var widths := []
	for spr in sprites:
		heights.append(spr.figure_height())
		widths.append(spr.figure_width())
	var layout := side_layout(heights, widths)
	for i in sprites.size():
		if float(layout.scale) < 1.0:
			sprites[i].set_scale_k(sprites[i].scale_k * float(layout.scale))
		sprites[i].home = layout.homes[i]
	_refresh_actor_motions()


## An actor's graphics for battle: its look (record + Change Actor Graphic) plus "sv_battler".
func actor_battle_look(actor_id: String) -> Dictionary:
	var look: Dictionary = {}
	if rpg != null and rpg.state != null and rpg.state.has_method("actor_look"):
		look = rpg.state.actor_look(actor_id).duplicate()
	var rec := record("actors", actor_id)
	if not look.has("charset"):
		look["charset"] = rec.get("charset", "")
		look["charset_index"] = rec.get("charset_index", 0)
	var stored: Variant = null
	if rpg != null and rpg.state != null and rpg.state.has_method("actor_custom"):
		stored = rpg.state.actor_custom(actor_id).get("look", {}).get("sv_battler")
	look["sv_battler"] = str(stored) if stored != null and str(stored) != "" else str(rec.get("sv_battler", ""))
	return look


## Side view: each actor's resting motion from its condition (dead, guarding, low HP or a bad
## state, else waiting). Motions playing on purpose (attacks, stepping) are left alone.
func _refresh_actor_motions() -> void:
	for b in actor_nodes:
		var spr: Control = actor_nodes[b]
		spr.set_base(resting_motion(b))
		spr.visible = not b.escaped


func resting_motion(b: RPGBattler) -> String:
	if b.is_dead():
		return "dead"
	if b.guarding:
		return "guard"
	for s in b.states:
		var r := str(record("states", str(s.id)).get("restriction", "none"))
		if r == "cannot_act":
			return "sleep" if str(s.id).contains("sleep") else "abnormal"
	var m := max_res(b, life_res())
	if m > 0 and b.get_resource(life_res()) * 4 <= m:
		return "dying"
	if b.states.size() > 0:
		return "abnormal"
	return "wait"


## Side view: the motion an action plays (MV's rules: weapon swing, unarmed thrust, magic spell,
## other skills, item).
func action_motion(r: Dictionary) -> String:
	var u: RPGBattler = r.user
	match str(r.get("kind", "")):
		"attack":
			return "swing" if str(u.equips.get("weapon", "")) != "" else "thrust"
		"skill":
			var rec := record("skills", str(r.action.get("skill", "")))
			return "spell" if str(rec.get("hit_type", "")) == "magical" else "skill"
		"item":
			return "item"
		"guard":
			return "guard"
		"escape":
			return "escape"
	return ""


## Side view: steps actor `b` forward (or back to its place) in a short walk.
func _step(b: RPGBattler, forward: bool) -> void:
	var spr: Control = actor_nodes.get(b)
	if spr == null:
		return
	var to := Vector2(-STEP_X if forward else 0.0, 0.0)
	# Compare with where it is going, not where it is: commands confirmed within one frame must
	# not leave an actor standing forward (its step forward still running).
	var going: Vector2 = spr.get_meta("step_to", spr.offset)
	if going == to:
		return
	spr.set_meta("step_to", to)
	if spr.has_meta("step_tween"):
		var old: Variant = spr.get_meta("step_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	spr.play_motion("walk")
	if auto or not is_inside_tree():
		spr.offset = to
	else:
		var t := spr.create_tween()
		spr.set_meta("step_tween", t)
		t.tween_property(spr, "offset", to, STEP_SECONDS)
		# Not `await t.finished`: a step replaced by another is killed and never finishes.
		while t.is_valid() and t.is_running() and is_inside_tree():
			await get_tree().process_frame
	if not forward and is_instance_valid(spr) and spr.get_meta("step_to", to) == to:
		spr.clear_motion()


## Side view: the actor choosing a command stands one step forward (as in RPG Maker MV).
## `step_back`: false when the actor goes on to act at once (timed battles), so it stays forward.
func _set_inputting(b: RPGBattler, step_back := true) -> void:
	if battle_view != "side" or b == _inputting:
		return
	var old := _inputting
	_inputting = b
	if old != null and actor_nodes.has(old) and step_back:
		_step(old, false)
	if b != null and actor_nodes.has(b):
		_step(b, true)


## Screen width each maker paints battlers for, by profile.
const BATTLER_SCREEN := {"rm2k": 320.0, "xp": 640.0, "vx": 544.0, "mv": 816.0}


## Scale for a battler image: the stage width over its pack's screen width (1.0 for 2k art).
func battler_scale(battler: String) -> float:
	if battler == "" or rpg == null or rpg.data == null:
		return 1.0
	var prof := RPGAssets.sheet_profile("battler", battler, str(rpg.data.profile.get("profile", "rm2k")))
	return minf(1.0, W / float(BATTLER_SCREEN.get(prof, W)))


## A generated blob with eyes for enemies without a battler graphic.
func _silhouette(id: String) -> Texture2D:
	var w := 40
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := Color.from_hsv(float(hash(id) % 360) / 360.0, 0.55, 0.8)
	var dark := base.darkened(0.55)
	var cx := w / 2.0
	var cy := h * 0.6
	for y in h:
		for x in w:
			var dx := (x + 0.5 - cx) / (w / 2.0)
			var dy := (y + 0.5 - cy) / (h * 0.42)
			var d := dx * dx + dy * dy
			if y < cy and d < 1.0 or y >= cy and dx * dx + pow((y + 0.5 - cy) / (h * 0.4 - 0.5), 2) < 1.0:
				var shade := base.lightened(0.25 * (1.0 - clampf((y as float) / h, 0, 1))) if d < 0.72 else dark
				img.set_pixel(x, y, shade)
	for ex in [-7, 7]:
		for yy in range(-2, 3):
			for xx in range(-2, 2):
				img.set_pixel(int(cx) + ex + xx, int(cy) - 3 + yy, Color.WHITE if abs(yy) < 2 else dark)
		img.set_pixel(int(cx) + ex, int(cy) - 3, Color.BLACK)
		img.set_pixel(int(cx) + ex - 1, int(cy) - 3, Color.BLACK)
	return ImageTexture.create_from_image(img)


func _refresh_status() -> void:
	if status_rows == null or core == null:
		return
	for c in status_rows.get_children():
		c.queue_free()
	_atb_fills.clear()
	var y := 0.0
	for b in core.party:
		var row := Control.new()
		row.position = Vector2(0, y)
		row.size = Vector2(228, 17)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_rows.add_child(row)
		make_label(row, Vector2(0, 0), b.name, FONT, status_colour(b), STATUS_NAME_W - 2)
		if battle_system == "atb":
			# The time gauge sits under the name, so the HP/SP columns keep their places.
			_atb_fills[b] = make_gauge(row, Rect2(0, 13, STATUS_NAME_W - 6, 3), core.gauge(b), ATB_COLOUR)
		var x := STATUS_NAME_W
		var k := 0
		for res in resource_ids().slice(0, 2):
			var m := max_res(b, res)
			var v: int = b.get_resource(res)
			var w: float = STATUS_RES_W[k]
			make_label(row, Vector2(x, 1), res_label(res), SMALL, system_colour())
			var vc := colour(0)
			if k == 0 and v * 4 <= m:
				vc = colour(C_CRISIS) if v > 0 else colour(C_BAD)
			make_label(row, Vector2(x + 12, 0), str(v) if k > 0 else "%d/%d" % [v, m], SMALL if k == 0 else FONT, vc, w - 14, HORIZONTAL_ALIGNMENT_RIGHT)
			make_gauge(row, Rect2(x, 13, w - 4, 3), float(v) / float(maxi(m, 1)), HP_COLOUR if k == 0 else SP_COLOUR)
			x += w + 4
			k += 1
		if not b.states.is_empty():
			# Icons when there is room for them; a long name ("Knocked out") shrinks to fit.
			make_states(row, Vector2(x, 2), b, STATUS_ROW_W - x, SMALL, colour(C_BAD))
		y += 17
	_refresh_actor_motions()
	_refresh_order_strip()


## CTB: the coming turns, left to right, as small name tags along the top of the stage, under
## the message line (party blue, enemies red; the first one is next).
func _make_order_strip() -> void:
	_order_strip = Control.new()
	_order_strip.position = Vector2(4, 26)
	# Side view: only over the enemies' part of the stage, so no actor's head is covered.
	_order_strip.size = Vector2((W * 0.6 if battle_view == "side" else W) - 8, 13)
	_order_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_strip.z_index = 4
	stage.add_child(_order_strip)


func _refresh_order_strip() -> void:
	if _order_strip == null or core == null:
		return
	for c in _order_strip.get_children():
		c.queue_free()
	var x := 0.0
	var order := core.turn_order(ORDER_COUNT)
	_shown_count = 0
	for i in order.size():
		var b: RPGBattler = order[i]
		var w := 44.0 if i == 0 else 34.0
		var tag := ColorRect.new()
		tag.position = Vector2(x, 0)
		tag.size = Vector2(w, 12)
		tag.color = (Color(0.15, 0.3, 0.65, 0.85) if b.is_actor() else Color(0.6, 0.15, 0.15, 0.85))
		if i == 0:
			tag.color = tag.color.lightened(0.25)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_order_strip.add_child(tag)
		make_label(tag, Vector2(2, -1), b.name, SMALL, Color.WHITE, w - 4)
		_shown_count += 1
		x += w + 3
		if x + 34.0 > _order_strip.size.x:
			break


## The coming turn order shown on screen (CTB), as battlers (tests).
func shown_order() -> Array:
	return core.turn_order(ORDER_COUNT).slice(0, _shown_count) if _order_strip != null and core != null else []


func _row_center(b: RPGBattler) -> Vector2:
	var i := core.party.find(b)
	return status_win.position + status_rows.position + Vector2(110, i * 17 + 8)  # middle of the 17 px row


func battler_point(b: RPGBattler) -> Vector2:
	if b.is_enemy() and enemy_nodes.has(b):
		var s: TextureRect = enemy_nodes[b]
		return s.position + Vector2(s.size.x / 2, s.size.y * 0.3)
	if actor_nodes.has(b):
		return actor_nodes[b].point()
	return _row_center(b)


## Popup styles passed to battle_popup: "damage", "critical", "miss", "heal", "resource_up",
## "resource_down", "slip" ("" for others).
func popup(b: RPGBattler, text: String, col: Color, style := "") -> void:
	var host := _ext_host() if style != "" else null
	if host != null:
		var made: Variant = host.run_hook("battle_popup", [b, text, style, null], "value").args[-1]
		if made is Control and is_instance_valid(made):
			# The extension's node animates and frees itself; its origin sits on the popup point
			# (placed before it enters the tree, so its _ready sees where it is).
			made.position = battler_point(b).round()
			if made.get_parent() == null:
				popups.add_child(made)
			return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(60, 18)
	var p := battler_point(b)
	l.position = p - Vector2(30, 9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popups.add_child(l)
	# Enemies bounce well above the sprite; party rows are only 17 px apart, so a party
	# number hops a little and stays on the hit actor's row.
	var rise := 12.0 if b.is_enemy() or actor_nodes.has(b) else 4.0
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - rise, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(l, "position:y", l.position.y - rise / 2.0, 0.14).set_ease(Tween.EASE_IN)
	t.tween_interval(0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.25)
	t.tween_callback(l.queue_free)


func flash(b: RPGBattler, col := Color(2.2, 2.2, 2.2)) -> void:
	if b.is_enemy() and enemy_nodes.has(b):
		var s: TextureRect = enemy_nodes[b]
		var t := s.create_tween()
		for i in 2:
			t.tween_property(s, "modulate", col, 0.05)
			t.tween_property(s, "modulate", Color.WHITE, 0.07)
	elif actor_nodes.has(b):
		# Side view: the hit actor flinches (damage motion) instead of the screen shaking.
		var a: Control = actor_nodes[b]
		a.play_motion("damage")
		var t2 := a.create_tween()
		t2.tween_property(a, "modulate", col, 0.05)
		t2.tween_property(a, "modulate", Color.WHITE, 0.1)
	else:
		_shake()


func _shake() -> void:
	var t := stage.create_tween()
	for x in [4, -4, 3, -2, 0]:
		t.tween_property(stage, "position:x", float(x), 0.04)


## Enemy Appear (event command): brings troop member `member_index` (-1: every hidden member)
## into the battle. Each one's image fades in and "%1 appears!" shows; target lists, the CTB order
## strip and battler_node(b) follow. Returns the battlers that appeared.
func enemy_appear(member_index: int) -> Array:
	if core == null:
		return []
	var shown: Array = core.appear(member_index)
	for e in shown:
		var s: TextureRect = enemy_nodes.get(e)
		if s == null:
			continue
		s.modulate = Color(1, 1, 1, 0)
		s.visible = true
		if auto or not is_inside_tree():
			s.modulate.a = 1.0
		else:
			s.create_tween().tween_property(s, "modulate:a", 1.0, 0.3)
	_place_battler_nodes()
	_refresh_order_strip()
	for e in shown:
		await say(rules().term("appear", [e.name]), 0.45)
	if not shown.is_empty():
		log_win.visible = false
	return shown


func _collapse(b: RPGBattler) -> void:
	if not enemy_nodes.has(b):
		return
	var s: TextureRect = enemy_nodes[b]
	var t := s.create_tween()
	t.tween_property(s, "modulate", Color(1.6, 0.3, 0.3, 0.8), 0.12)
	t.tween_property(s, "modulate", Color(1, 0.2, 0.2, 0.0), 0.35)
	t.tween_callback(func(): s.visible = false)


func _update(delta: float) -> void:
	_t += delta
	# The skill/item list and the message box sit over the command and status windows; with a
	# translucent window skin their text would show through, so fade those out underneath.
	if cmd_win and status_win:
		var covered: bool = (select_win != null and select_win.visible) or (rpg != null and rpg.ui != null and rpg.ui.message_box != null and rpg.ui.message_box.has_method("is_open") and rpg.ui.message_box.is_open())
		var a := 0.0 if covered else 1.0
		cmd_win.modulate.a = a
		status_win.modulate.a = a
	if target_arrow and target_arrow.visible:
		target_arrow.position.y = target_arrow.get_meta("base_y", 0.0) + (1.0 if int(_t * 4) % 2 == 0 else 0.0)
	_update_gauges()
	_place_battler_nodes()
	_poll_pass_key()


## ATB: Shift (rpg_dash, gamepad X) or Tab on an actor's command passes the turn to the next full
## actor, as in RPG Maker 2003.
func _poll_pass_key() -> void:
	var tab := Input.is_physical_key_pressed(KEY_TAB)
	var tab_pressed := tab and not _tab_down
	_tab_down = tab
	if input_actor == null or phase != "actor" or not input_enabled or not is_top() or _message_open():
		return
	if tab_pressed or (InputMap.has_action("rpg_dash") and Input.is_action_just_pressed("rpg_dash")):
		pass_turn()


## ATB: lets the next full actor choose first (the current one keeps its full gauge and gets its
## command after the others). Returns false (buzzer) when no other actor is waiting.
func pass_turn() -> bool:
	if input_actor == null or not core.is_timed():
		return false
	var next := core.pass_turn(input_actor)
	if next == null:
		play("buzzer")
		return false
	play("cursor")
	_switch_input(next)
	return true


## Moves the command window to another full actor (Tab / Shift, or a click on its row).
func _switch_input(a: RPGBattler) -> void:
	if a == input_actor or not core.needs_input(a):
		return
	input_actor = a
	inputs = [core.party.find(a)]
	input_pos = 0
	select_win.visible = false
	target_arrow.visible = false
	_show_actor_command()


## Mouse: a click on another full actor's status row or figure gives it the command window.
func _switch_targets() -> Array:
	var out := []
	if input_actor == null or not core.is_timed():
		return out
	for a in core.input_actors():
		if a == input_actor:
			continue
		var who: RPGBattler = a
		var i := core.party.find(a)
		var r := Rect2(status_rows.position + Vector2(0, i * 17), Vector2(STATUS_ROW_W, 17))
		var go := func() -> void:
			play("cursor")
			_switch_input(who)
		# "selected": hovering does not switch; only a click does ("ok").
		out.append({"rect": local_xform(status_win) * r, "selected": true, "ok": go})
		var spr: Control = actor_nodes.get(a)
		if spr != null and spr.visible:
			out.append({"rect": local_xform(field) * spr.figure_rect(), "selected": true, "ok": go})
	return out


## ATB: the time gauges under the party names follow the core every frame; a full gauge blinks.
func _update_gauges() -> void:
	if core == null or _atb_fills.is_empty():
		return
	for b in _atb_fills:
		var fill: ColorRect = _atb_fills[b]
		if not is_instance_valid(fill):
			continue
		var g := core.gauge(b)
		set_gauge(fill, g)
		fill.color = (ATB_FULL_COLOUR if int(_t * 6) % 2 == 0 else Color.WHITE) if g >= 1.0 else ATB_COLOUR


# --- text ----------------------------------------------------------------------------------

func say(text: String, seconds := 0.55) -> void:
	if text == "":
		return
	log_lines.append(text)
	log_label.text = text
	log_win.visible = true
	await _wait(seconds)


func _wait(seconds: float) -> void:
	if auto or not is_inside_tree():
		return
	var fast := Input.is_action_pressed("rpg_ok") or Input.is_action_pressed("rpg_cancel")
	await get_tree().create_timer(seconds * (0.35 if fast else 1.0)).timeout


func _wait_key() -> void:
	if auto:
		return
	while is_inside_tree():
		await get_tree().process_frame
		if Input.is_action_just_pressed("rpg_ok") or Input.is_action_just_pressed("rpg_cancel"):
			play("decision")
			return


# --- main loop -----------------------------------------------------------------------------

func _run() -> void:
	if _done:
		return
	var names := []
	for e in core.enemies:
		if not e.hidden:
			names.append(e.name)
	for n in names:
		await say(rules().term("appear", [n]), 0.45)
	match core.advantage:
		"preemptive":
			await say(_battle_term("preemptive", "%1 got the jump on the enemy!", [_party_name()]), 0.6)
		"surprise":
			await say(_battle_term("surprise", "%1 was taken by surprise!", [_party_name()]), 0.6)
	log_win.visible = false
	if core.is_timed():
		await _run_timed()
		return
	var safety := 0
	while core.battle_over() == "":
		safety += 1
		if safety > 999:
			core.force_result("escape")
			break
		core.begin_turn()
		await _flush_checkpoints()
		if core.battle_over() != "":
			break
		var choice := "fight"
		if auto:
			_auto_actions()
		else:
			choice = await _input_phase()
		if choice == "escape":
			var e: Dictionary = core.attempt_escape()
			for l in e.lines:
				await say(l)
			if e.success:
				play("escape")
				await _party_escape_motion()
				break
			for i in core.inputs_needed():
				core.party[i].action = {"kind": "wait", "silent": true}
		var r: Dictionary = core.next_action()
		while not r.is_empty():
			await show_action(r)
			# Common Event effects of the action run right after it, as a battle event would.
			for ce_id in r.get("common_events", []):
				var ce: Dictionary = rpg.data.common_events.get(str(ce_id), {})
				if not ce.is_empty():
					await run_page({"id": "common:" + str(ce_id), "commands": ce.get("commands", [])})
				if not is_inside_tree():
					return
			await _flush_checkpoints()
			if r.escaped or core.battle_over() != "":
				break
			r = core.next_action()
		if core.battle_over() != "":
			break
		for t in core.end_turn():
			for l in t.lines:
				await say(l, 0.45)
			if int(t.get("damage", 0)) > 0:
				popup(t.battler, str(t.damage), Color.WHITE, "slip")
			if t.get("knocked_out", false) and t.battler.is_enemy():
				_collapse(t.battler)
			_refresh_status()
		await _flush_checkpoints()
		_refresh_status()
		log_win.visible = false
		if auto and is_inside_tree():
			await get_tree().process_frame
	outcome = core.battle_over()
	await _end_battle()


## A battle term from the rule system (Terms record "battle_<key>"), or `fallback` when the
## rules have none.
func _battle_term(key: String, fallback: String, a: Array = []) -> String:
	var t: String = rules().term(key, a)
	if t != key:
		return t
	for i in range(a.size() - 1, -1, -1):
		fallback = fallback.replace("%" + str(i + 1), str(a[i]))
	return fallback


func _party_name() -> String:
	return core.party[0].name if not core.party.is_empty() else "The party"


# --- timed battles (ATB / CTB) -------------------------------------------------------------

## The ATB / CTB loop: gauges fill (in real time for ATB, jumping for CTB and auto battles);
## a full enemy acts, a full actor gets the command window. See RPGBattleCore for the turn rules.
func _run_timed() -> void:
	core.begin_turn()
	await _flush_checkpoints()
	var safety := 0
	while core.battle_over() == "" and is_inside_tree() and not _done:
		safety += 1
		if safety > 200000:
			core.force_result("escape")
			break
		if _timed_escape:
			_timed_escape = false
			if await _timed_try_escape():
				break
			continue
		if input_actor != null and not core.needs_input(input_actor):
			_close_timed_input()       # knocked out or put to sleep while choosing (active mode)
		if input_actor != null and auto:
			var waiting := input_actor  # auto battle switched on while a command window is open
			_close_timed_input(false)
			_auto_action_for(waiting)
		time_stopped = input_actor != null and (battle_system == "ctb" or atb_mode == "wait")
		var b: RPGBattler = null if time_stopped else core.next_auto_ready()
		if b != null:
			await _timed_turn(b)
			continue
		if input_actor == null:
			var a := core.next_input_actor()
			if a != null:
				if auto:
					_auto_action_for(a)
				else:
					_open_timed_input(a)
				continue
		if not time_stopped:
			if auto or battle_system == "ctb":
				if input_actor == null:
					core.atb_advance_to_next()
					_refresh_order_strip()
			else:
				core.atb_advance(get_process_delta_time() if is_inside_tree() else 0.016)
		if auto:
			if safety % 8 == 0 and is_inside_tree():
				await get_tree().process_frame
		elif is_inside_tree():
			await get_tree().process_frame
	_close_timed_input()
	if _done:
		return
	outcome = core.battle_over()
	await _end_battle()


## One battler's turn in a timed battle: its action, its state ticks, battle events, and the
## turn counter moving on.
func _timed_turn(b: RPGBattler) -> void:
	var r: Dictionary = core.act(b)
	if r.is_empty():
		return
	await show_action(r)
	for ce_id in r.get("common_events", []):
		var ce: Dictionary = rpg.data.common_events.get(str(ce_id), {})
		if not ce.is_empty():
			await run_page({"id": "common:" + str(ce_id), "commands": ce.get("commands", [])})
		if not is_inside_tree():
			return
	for t in r.get("ticks", []):
		for l in t.lines:
			await say(l, 0.45)
		if int(t.get("damage", 0)) > 0:
			popup(t.battler, str(t.damage), Color.WHITE, "slip")
		if t.get("knocked_out", false) and t.battler.is_enemy():
			_collapse(t.battler)
	_refresh_status()
	await _flush_checkpoints()
	if r.get("turn_end", false) and core.battle_over() == "":
		core.begin_turn()
		await _flush_checkpoints()
	_refresh_status()
	if input_actor != null:
		_restore_input_hint()
	else:
		log_win.visible = false


## Escape chosen from the party command of a timed battle: the same chance as in the turn
## system; on failure every party member loses its turn. Returns true when the party got away.
func _timed_try_escape() -> bool:
	var e: Dictionary = core.attempt_escape()
	for l in e.lines:
		await say(l)
	if e.success:
		play("escape")
		await _party_escape_motion()
		return true
	if core.lose_party_turns():
		await _flush_checkpoints()
		if core.battle_over() == "":
			core.begin_turn()
			await _flush_checkpoints()
	log_win.visible = false
	_refresh_status()
	return false


func _auto_action_for(a: RPGBattler) -> void:
	var target := -1
	for i in core.enemies.size():
		if core.enemies[i].is_active():
			target = i
			break
	core.set_action(core.party.find(a), {"kind": "attack", "target": target})


## Opens the command window for a full actor (timed battles).
func _open_timed_input(a: RPGBattler) -> void:
	input_actor = a
	inputs = [core.party.find(a)]
	input_pos = 0
	play("cursor")
	_show_actor_command()


## Closes the command window of a timed battle (after a command, or when the actor can no
## longer choose).
func _close_timed_input(step_back := true) -> void:
	if input_actor == null:
		return
	input_actor = null
	phase = ""
	_idle_command_window()
	select_win.visible = false
	status_cursor.visible = false
	target_arrow.visible = false
	log_win.visible = false
	_set_inputting(null, step_back)


## Active ATB: an action shown while the player chooses overwrote the help line; put it back.
func _restore_input_hint() -> void:
	if input_actor == null:
		return
	match phase:
		"actor":
			log_win.visible = true
			log_label.text = input_actor.name
		"skill", "item":
			_select_help()
		"target_enemy":
			if target_index >= 0 and target_index < core.enemies.size() and core.enemies[target_index].is_active():
				_show_enemy_target()
			else:
				_cycle_enemy(1, false)
		"target_ally":
			log_win.visible = true
			log_label.text = core.party[target_index].name


func _auto_actions() -> void:
	var target := -1
	for i in core.enemies.size():
		if core.enemies[i].is_active():
			target = i
			break
	for i in core.inputs_needed():
		core.set_action(i, {"kind": "attack", "target": target})


## Runs the battle pages that became eligible at the checkpoints seen so far.
func _flush_checkpoints() -> void:
	while not _pending_checkpoints.is_empty():
		var kind: String = _pending_checkpoints.pop_front()
		for page in core.eligible_battle_pages(kind):
			await run_page(page)
			if not is_inside_tree():
				return


## Runs one troop page's commands with the battle paused and the message box on top.
func run_page(page: Dictionary) -> RPGResult:
	var cmds: Array = page.get("commands", [])
	if cmds.is_empty():
		return RPGResult.ok()
	var was_enabled := input_enabled
	input_enabled = false
	log_win.visible = false
	var mb: Control = rpg.ui.message_box if rpg.ui else null
	var old_index := -1
	if mb != null and mb.get_parent() != null:
		old_index = mb.get_index()
		mb.get_parent().move_child(mb, -1)
		if rpg.ui.toast:
			rpg.ui.toast.get_parent().move_child(rpg.ui.toast, -1)
	var owner := {"kind": "battle_event", "id": str(page.get("id", "page")), "troop": str(troop.get("id", ""))}
	var interp := RPGInterpreter.new(rpg, owner)
	var r: RPGResult = await interp.run(cmds)
	if r.is_error():
		rpg.report_error(r, owner)
	refresh_after_event()          # states, defeats and display changed by the page's commands
	if mb != null and old_index >= 0 and is_instance_valid(mb) and mb.get_parent() != null:
		mb.get_parent().move_child(mb, old_index)
	input_enabled = was_enabled
	return r


## After a battle event or a common event it called changed battlers (Change HP/SP, Change
## State, Enemy Appear, Change Party Member...): reports the changes (hooks), collapses enemies
## the commands defeated, and redraws the status display and battler visuals. The battle facade
## exposes this as rpg.battle.refresh().
func refresh_after_event() -> void:
	if core == null:
		return
	core.report_changes()
	for e in core.enemies:
		if e.is_dead() and enemy_nodes.has(e) and enemy_nodes[e].visible:
			_collapse(e)
	_refresh_status()


## Change Party Member during the battle: puts the field in step with the game state's party
## (through battle_members(), so the size limit and the extension hook still apply). Added
## actors get a gauge and act in the normal order; removed actors leave it, and both views
## re-flow. `temporary` actor ids (the command's "only for this battle") are removed again when
## the battle ends.
func refresh_party(temporary: Array = []) -> void:
	if core == null:
		return
	core.refresh_party(battle_members())
	for b in core.party:
		if temporary.has(b.id) and not _temp_actors.has(b.id):
			_temp_actors.append(b.id)
	if input_actor != null and not core.party.has(input_actor):
		_close_timed_input()
	_sync_actor_nodes()
	refresh_after_event()


## Shows one action result: announcement, hit effects, popups and the remaining lines.
func show_action(r: Dictionary) -> void:
	var user: RPGBattler = r.user
	if r.action.get("silent", false):
		return
	var lines: Array = r.lines
	var side_actor := actor_nodes.has(user)
	if user.is_enemy():
		flash(user, Color(1.8, 1.8, 1.8))
	elif side_actor:
		# Side view: the actor steps forward and plays its attack / skill / item motion.
		await _step(user, true)
		var m := action_motion(r)
		if m != "" and is_instance_valid(actor_nodes.get(user)):
			actor_nodes[user].play_motion(m)
	if not lines.is_empty():
		await say(lines[0], 0.35)
	# Battle animation on every target that was hit (non-blocking; a short beat before the numbers).
	var anim := str(r.get("animation", ""))
	if anim != "" and not auto:
		var longest := 0.0
		for eff in r.effects:
			if eff.result.get("hit", false):
				longest = maxf(longest, RPGBattleEffects.play(popups, battler_point(eff.target), anim, rpg))
		if longest > 0.0:
			await _wait(minf(longest, 0.45))
	for eff in r.effects:
		var t: RPGBattler = eff.target
		var res: Dictionary = eff.result
		if not res.get("hit", false):
			if str(res.get("error", "")) == "":
				popup(t, "Miss", Color(0.85, 0.85, 0.85), "miss")
				if actor_nodes.has(t):
					actor_nodes[t].play_motion("evade")
			continue
		var dmg := int(res.get("damage", 0))
		var rec := int(res.get("recovered", 0))
		if dmg > 0:
			play("damage" if t.is_actor() else "attack")
			popup(t, str(dmg), Color(1, 1, 0.75) if res.get("critical", false) else Color.WHITE, "critical" if res.get("critical", false) else "damage")
			flash(t)
		elif rec > 0:
			play("heal")
			popup(t, str(rec), Color(0.55, 1.0, 0.6), "heal")
		else:
			for rid in res.get("changes", {}):
				var d := int(res.changes[rid])
				popup(t, ("+" if d > 0 else "") + str(d), SP_COLOUR if d > 0 else Color(0.8, 0.6, 1.0), "resource_up" if d > 0 else "resource_down")
				break
		if res.get("knocked_out", false) and t.is_enemy():
			_collapse(t)
		_refresh_status()
	await _wait(0.2)
	for i in range(1, lines.size()):
		await say(lines[i], 0.5)
	if side_actor and not r.get("escaped", false):
		await _step(user, false)
	_refresh_status()


## Side view: the party turns and runs off to the right.
func _party_escape_motion() -> void:
	if actor_nodes.is_empty():
		return
	var tween: Tween = null
	for b in actor_nodes:
		var spr: Control = actor_nodes[b]
		if b.is_dead():
			continue
		spr.play_motion("escape")
		if not auto and is_inside_tree():
			tween = spr.create_tween()
			tween.tween_property(spr, "offset", Vector2(90, 0), 0.5)
	if tween != null:
		await tween.finished


func _end_battle() -> void:
	_set_inputting(null)
	if _order_strip != null:
		_order_strip.visible = false
	target_arrow.visible = false
	_idle_command_window()
	select_win.visible = false
	status_cursor.visible = false
	match outcome:
		"win":
			await _victory()
		"lose":
			_defeat_audio()
			await say(rules().term("defeat"), 1.0)
			await _wait_key()
		"escape":
			await _wait(0.4)
	core.finish()
	for b in core.party:
		rpg.state.notify_actor_changed(b.id)
	# Battle-only party members leave again, and the public battle API goes away with the fight.
	for id in _temp_actors:
		rpg.state.remove_actor(id)
	_temp_actors.clear()
	if rpg != null and "battle" in rpg and rpg.battle != null and rpg.battle.scene() == self:
		rpg.battle = null
	if _done:
		return
	_done = true
	finished.emit({"outcome": outcome, "rewards": rewards if outcome == "win" else {}})


## MV's replayBgmAndBgs at the end of a won (or survivable lost) battle: the map's music, saved
## with its position when the battle began (context.map_bgm), takes the battle music's place. With
## a jingle playing it starts once the jingle ends, where it was.
func _replay_map_audio() -> void:
	if rpg == null or rpg.audio == null or not rpg.audio.has_method("replay_bgm") or not context.has("map_bgm"):
		return
	var saved: Variant = context.get("map_bgm")
	rpg.audio.replay_bgm(saved if saved is Dictionary else {})


## Defeat (MV's processDefeat): the battle music stops and the defeat jingle plays; the map music
## comes back only when the battle may be lost (otherwise the game over screen follows).
func _defeat_audio() -> void:
	if rpg == null or rpg.audio == null:
		return
	var me: Variant = system_music("defeat")
	if me != null:
		rpg.audio.play_me(me)
	if bool(args.get("can_lose", false)):
		_replay_map_audio()
	else:
		rpg.audio.stop_bgm()


## Battle BGM / victory ME: "Change Battle BGM" / "Change Victory ME" (game state) win over the
## System record.
func battle_music(key: String) -> Variant:
	if rpg != null and rpg.state != null and "music_overrides" in rpg.state and rpg.state.music_overrides.has(key):
		var m: Variant = rpg.state.music_overrides[key]
		if m is Dictionary and str(m.get("file", "")) != "":
			return m
		return null
	return system_music(key)


func _victory() -> void:
	for b in actor_nodes:
		if b.is_alive() and not b.escaped:
			actor_nodes[b].offset = Vector2.ZERO
			actor_nodes[b].play_motion("victory")
	var me: Variant = battle_music("victory")
	if me != null and rpg.audio:
		rpg.audio.play_me(me)
	_replay_map_audio()
	var give_rewards := not skip_rewards
	rewards = core.rewards().duplicate(true)
	if not give_rewards:
		rewards = {}
	# victory(rewards): extensions may change the rewards before they are given.
	var changed: Variant = _hook("victory", [rewards], "value").args[0]
	if changed is Dictionary:
		rewards = changed
	var before := {}
	for a in core.party:
		if a.is_alive():
			before[a] = {"level": a.level, "exp": a.exp}
	level_ups = core.award_exp(maxi(0, int(rewards.get("exp", 0))))
	if int(rewards.get("gold", 0)) > 0:
		rpg.state.change_gold("increase", int(rewards.gold))
	for it in rewards.get("items", []):
		rpg.state.change_items(str(it.id), "increase", int(it.count), str(it.kind))
	# Stats are read only for a victory_scene (a stat formula may draw from the game's RNG).
	var wants_stats := _victory_scene_offered()
	victory_actors = []
	for up in level_ups:
		var a: RPGBattler = up.actor
		var b4: Dictionary = before.get(a, {})
		var learned := []
		var gains := {}
		for lv in up.level_ups:
			learned.append_array(lv.get("learned", []))
			for k in lv.get("gains", {}):
				gains[k] = gains.get(k, 0) + lv.gains[k]
		var now_stats: Dictionary = rules().stat_block(a) if wants_stats else {}
		var old_stats := {}
		for k in now_stats:
			old_stats[k] = now_stats[k] - gains.get(k, 0)
		victory_actors.append({"actor": a, "id": a.id, "name": a.name, "old_level": int(b4.get("level", a.level)),
			"new_level": a.level, "old_exp": int(b4.get("exp", a.exp)), "new_exp": a.exp, "level_ups": up.level_ups,
			"old_stats": old_stats, "new_stats": now_stats, "gains": gains, "learned": learned})
	# A replaceable victory step: an entry script's victory_scene(info) -> Node runs instead of the
	# reward messages (the battle waits for its finished / closed signal).
	var info: Dictionary = rewards.duplicate(true)
	info["actors"] = victory_actors
	info["battle"] = self
	info["auto"] = auto
	var node := _victory_node(info)
	if node != null:
		_refresh_status()
		await _run_victory_node(node)
		return
	var lines := [rules().term("victory")]
	if int(rewards.get("exp", 0)) > 0:
		lines.append(rules().term("exp", [rewards.exp]))
	if int(rewards.get("gold", 0)) > 0:
		lines.append(rules().term("gold", [rewards.gold]))
	for it in rewards.get("items", []):
		var kind := RPGGameState.kind_for(str(it.kind))
		var nm := str(record(kind, str(it.id)).get("name", it.id))
		lines.append(rules().term("item_found", [nm if int(it.count) <= 1 else "%s x%d" % [nm, int(it.count)]]))
	for up in level_ups:
		var a: RPGBattler = up.actor
		for lv in up.level_ups:
			lines.append(rules().term("level_up", [a.name, lv.level]))
			for sk in lv.get("learned", []):
				lines.append(rules().term("learned", [a.name, str(record("skills", str(sk)).get("name", sk))]))
	var leveled := false
	for up in level_ups:
		if not (up.level_ups as Array).is_empty():
			leveled = true
	if leveled:
		play("level_up")
	_refresh_status()
	for l in lines:
		await say(l, 0.7)
	await _wait_key()


func _victory_scene_offered() -> bool:
	var host := _ext_host()
	if host == null:
		return false
	for e in host.entries:
		if is_instance_valid(e[1]) and e[1].has_method("victory_scene"):
			return true
	return false


## The first node an entry script's victory_scene(info) returns, or null.
func _victory_node(info: Dictionary) -> Node:
	var host := _ext_host()
	if host == null:
		return null
	for e in host.entries.duplicate():
		var obj: Object = e[1]
		if is_instance_valid(obj) and obj.has_method("victory_scene"):
			var n: Variant = obj.victory_scene(info)
			if n is Node and is_instance_valid(n):
				return n
	return null


## Shows an extension's victory node (added over the battle unless it is already in the tree)
## until it emits finished, closed or cancelled, then removes it.
func _run_victory_node(node: Node) -> void:
	if node.get_parent() == null:
		add_child(node)
	var sigs: Array = []
	for s in ["finished", "closed", "cancelled"]:
		if node.has_signal(s):
			sigs.append(Signal(node, s))
	if not sigs.is_empty():
		await RPGWaiter.any(sigs).done
	if not is_instance_valid(node):
		return
	if rpg != null and rpg.ui != null and rpg.ui.scene_stack.has(node):
		rpg.ui.close_scene(node)
	else:
		node.queue_free()


# --- player input --------------------------------------------------------------------------

func _input_phase() -> String:
	inputs = core.inputs_needed()
	if inputs.is_empty():
		return "fight"
	_show_party_command()
	var choice: String = await _input_done
	phase = ""
	_set_inputting(null)
	_idle_command_window()
	select_win.visible = false
	status_cursor.visible = false
	target_arrow.visible = false
	log_win.visible = false
	return choice


## Outside player input the command window stays on screen, empty.
func _idle_command_window() -> void:
	cmd_list.set_items([], false)
	cmd_list.active = false
	cmd_win.visible = true


func _show_party_command() -> void:
	phase = "party"
	_set_inputting(null)
	cmd_win.visible = true
	select_win.visible = false
	status_cursor.visible = false
	cmd_list.set_items([
		{"text": term("fight", "Fight")},
		{"text": term("escape", "Escape"), "enabled": core.can_escape},
	], false)
	cmd_list.active = true
	log_win.visible = false


## `keep_cursor`: coming back from a sub-list or a target (cancel), the cursor stays on the
## command the player had picked, as in RPG Maker; a new actor's turn starts on Attack.
func _show_actor_command(keep_cursor := false) -> void:
	phase = "actor"
	cmd_win.visible = true
	select_win.visible = false
	target_arrow.visible = false
	var b: RPGBattler = core.party[inputs[input_pos]]
	_set_inputting(b)
	var has_skills := false
	for s in b.skills:
		if str(record("skills", str(s)).get("occasion", "always")) in BATTLE_OCCASIONS:
			has_skills = true
	cmd_list.set_items([
		{"text": term("attack", "Attack")},
		{"text": term("skill", "Skill"), "enabled": has_skills and rules().restriction(b) != "cannot_use_skills"},
		{"text": term("guard", "Guard")},
		{"text": term("item", "Item")},
	], keep_cursor)
	cmd_list.active = true
	_place_status_cursor(core.party.find(b))
	log_win.visible = true
	log_label.text = b.name


## Side view: the target arrow over the actor picked as a target (the status row is highlighted too).
func _ally_arrow() -> void:
	var b: RPGBattler = core.party[target_index] if target_index >= 0 and target_index < core.party.size() else null
	if b == null or not actor_nodes.has(b):
		return
	var p: Vector2 = actor_nodes[b].figure_rect().position
	target_arrow.position = Vector2(round(actor_nodes[b].point().x) - 5, maxf(p.y - 10, 26))
	target_arrow.set_meta("base_y", target_arrow.position.y)
	target_arrow.visible = true
	target_arrow.queue_redraw()


func _place_status_cursor(i: int) -> void:
	status_cursor.visible = i >= 0
	status_cursor.position = Vector2(3, 5 + i * 17)
	status_cursor.size = Vector2(234, 17)


func current_actor() -> RPGBattler:
	return core.party[inputs[input_pos]] if input_pos < inputs.size() else null


func handle_action(a: String) -> void:
	if _done or not _started:
		return
	match phase:
		"party":
			match a:
				"up", "down":
					if cmd_list.move(0, -1 if a == "up" else 1):
						play("cursor")
				"ok":
					if cmd_list.index == 0:
						play("decision")
						input_pos = 0
						_show_actor_command()
					elif core.can_escape:
						play("decision")
						if core.is_timed():
							# The loop tries to escape once the command window is closed.
							_close_timed_input()
							_timed_escape = true
						else:
							_input_done.emit("escape")
					else:
						play("buzzer")
				"cancel":
					if core.is_timed() and input_actor != null:
						play("cancel")
						_show_actor_command(true)
		"actor":
			match a:
				"up", "down":
					if cmd_list.move(0, -1 if a == "up" else 1):
						play("cursor")
				"ok":
					_actor_command(cmd_list.index)
				"cancel":
					play("cancel")
					if input_pos == 0:
						_show_party_command()
					else:
						input_pos -= 1
						current_actor().action = {}
						_show_actor_command()
		"skill", "item":
			match a:
				"up", "down", "left", "right":
					var dx := -1 if a == "left" else (1 if a == "right" else 0)
					var dy := -1 if a == "up" else (1 if a == "down" else 0)
					if select_list.move(dx, dy):
						play("cursor")
						_select_help()
				"ok":
					var it: Dictionary = select_list.current()
					if it.is_empty() or not bool(it.get("enabled", true)):
						play("buzzer")
						return
					play("decision")
					var id := str(it.data)
					var rec := record("skills" if phase == "skill" else "items", id)
					pending = {"kind": phase, phase: id}
					_choose_target(str(rec.get("scope", "one_enemy")), phase)
				"cancel":
					play("cancel")
					_show_actor_command(true)
		"target_enemy":
			match a:
				"left", "right", "up", "down":
					_cycle_enemy(-1 if a in ["left", "up"] else 1)
				"ok":
					play("decision")
					pending["target"] = target_index
					_commit(pending)
				"cancel":
					play("cancel")
					_back_from_target()
		"target_ally":
			match a:
				"up", "down", "left", "right":
					target_index = posmod(target_index + (-1 if a in ["up", "left"] else 1), core.party.size())
					play("cursor")
					_place_status_cursor(target_index)
					_ally_arrow()
					log_label.text = core.party[target_index].name
				"ok":
					play("decision")
					pending["target"] = target_index
					_commit(pending)
				"cancel":
					play("cancel")
					_back_from_target()


# --- mouse ---------------------------------------------------------------------------------

## What the mouse can point at in each input phase: the command or skill/item list, the enemies
## (click one to target it), or the party rows. Outside input a click is OK (skips waits).
func pointer_targets() -> Array:
	if _done or not _started:
		return []
	match phase:
		"party":
			return list_targets(cmd_list)
		"actor":
			return list_targets(cmd_list) + _switch_targets()
		"skill", "item":
			return list_targets(select_list)
		"target_enemy":
			var out := []
			for i in core.enemies.size():
				var e: RPGBattler = core.enemies[i]
				var spr: TextureRect = enemy_nodes.get(e)
				if not e.is_active() or spr == null or not spr.visible:
					continue
				var idx := i
				out.append({"rect": local_xform(spr) * Rect2(Vector2.ZERO, spr.size), "selected": target_index == i, "select": func() -> void: _point_enemy(idx)})
			return out
		"target_ally":
			var out2 := []
			for i in core.party.size():
				var idx2 := i
				var r := Rect2(status_rows.position + Vector2(0, i * 17), Vector2(STATUS_ROW_W, 17))
				out2.append({"rect": local_xform(status_win) * r, "selected": target_index == i, "select": func() -> void: _point_ally(idx2)})
				# Side view: the actor's figure can be pointed at too.
				var spr: Control = actor_nodes.get(core.party[i])
				if spr != null and spr.visible:
					out2.append({"rect": local_xform(spr) * Rect2(Vector2.ZERO, spr.size), "selected": target_index == i, "select": func() -> void: _point_ally(idx2)})
			return out2
	return []


func on_pointer_moved(l: Control) -> void:
	if l == select_list:
		_select_help()


func _point_enemy(i: int) -> void:
	if i == target_index:
		return
	target_index = i
	play("cursor")
	_show_enemy_target()


func _point_ally(i: int) -> void:
	if i == target_index:
		return
	target_index = i
	play("cursor")
	_place_status_cursor(i)
	_ally_arrow()
	log_label.text = core.party[i].name


func _actor_command(i: int) -> void:
	var b := current_actor()
	match i:
		0:
			play("decision")
			pending = {"kind": "attack"}
			_choose_target("one_enemy", "actor")
		1:
			if not bool(cmd_list.current().get("enabled", true)):
				play("buzzer")
				return
			play("decision")
			_open_select("skill", b)
		2:
			play("decision")
			_commit({"kind": "guard"})
		3:
			if _battle_items().is_empty():
				play("buzzer")
				return
			play("decision")
			_open_select("item", b)


func _battle_items() -> Array:
	var out := []
	var inv: Dictionary = rpg.state.inventory.get("items", {})
	for id in inv:
		if int(inv[id]) <= 0:
			continue
		var rec := record("items", str(id))
		if bool(rec.get("key_item", false)):
			continue
		var ok := str(rec.get("occasion", "always")) in BATTLE_OCCASIONS
		out.append({"text": str(rec.get("name", id)), "right": ":%d" % int(inv[id]), "enabled": ok, "data": str(id), "icon": icon_for(rec)})
	return out


## The list icon for a skill or item record (RPGIcons through the inherited record_icon(): null
## when the record has none or icons are off).
func icon_for(rec: Dictionary) -> Variant:
	return record_icon(rec)


func _open_select(kind: String, b: RPGBattler, keep := false) -> void:
	phase = kind
	var items := []
	if kind == "skill":
		for s in b.skills:
			var rec := record("skills", str(s))
			var cost: Dictionary = rec.get("cost", {})
			var cost_text := ""
			for res in cost:
				cost_text = "%d %s" % [int(cost[res]), res_label(str(res))]
			var ok: bool = str(rec.get("occasion", "always")) in BATTLE_OCCASIONS and rules().can_use(b, {"kind": "skill", "skill": str(s)})
			items.append({"text": str(rec.get("name", s)), "right": cost_text, "enabled": ok, "data": str(s), "icon": icon_for(rec)})
	else:
		items = _battle_items()
	select_list.set_items(items, keep)
	select_list.active = true
	select_win.visible = true
	cmd_win.visible = true
	_select_help()


func _select_help() -> void:
	var it: Dictionary = select_list.current()
	log_win.visible = true
	log_label.text = str(record("skills" if phase == "skill" else "items", str(it.get("data", ""))).get("description", "")) if not it.is_empty() else ""


func _choose_target(scope: String, from_phase: String) -> void:
	_target_return = from_phase
	if scope in ENEMY_SCOPES:
		phase = "target_enemy"
		target_index = -1
		_cycle_enemy(1, false)
	elif scope in ALLY_PICK_SCOPES:
		phase = "target_ally"
		target_index = maxi(0, core.party.find(current_actor()))
		select_win.visible = false
		_place_status_cursor(target_index)
		_ally_arrow()
		log_win.visible = true
		log_label.text = core.party[target_index].name
	else:
		pending["target"] = -1
		_commit(pending)


func _cycle_enemy(dir: int, sound := true) -> void:
	var alive := []
	for i in core.enemies.size():
		if core.enemies[i].is_active():
			alive.append(i)
	if alive.is_empty():
		return
	var pos := alive.find(target_index)
	pos = 0 if pos < 0 and dir > 0 else posmod(pos + dir, alive.size())
	target_index = alive[pos]
	if sound:
		play("cursor")
	_show_enemy_target()


## Points the target arrow at enemy `target_index`.
func _show_enemy_target() -> void:
	var e: RPGBattler = core.enemies[target_index]
	var s: TextureRect = enemy_nodes.get(e)
	if s != null:
		target_arrow.position = Vector2(s.position.x + s.size.x / 2 - 5, maxf(s.position.y - 10, 26))
		target_arrow.set_meta("base_y", target_arrow.position.y)
		target_arrow.visible = true
		target_arrow.queue_redraw()
	log_win.visible = true
	log_label.text = e.name
	select_win.visible = false
	cmd_win.visible = true


func _back_from_target() -> void:
	target_arrow.visible = false
	if _target_return == "actor":
		_show_actor_command(true)
	else:
		_open_select(_target_return, current_actor(), true)


## Stores the current actor's action and moves to the next actor (or ends input).
func _commit(action: Dictionary) -> void:
	target_arrow.visible = false
	var idx: int = inputs[input_pos]
	if not core.set_action(idx, action):
		play("buzzer")
		_show_actor_command(true)
		return
	if core.is_timed():
		# The loop runs this actor's turn next (its action is set, so it no longer needs input).
		_close_timed_input(false)
		return
	input_pos += 1
	if input_pos >= inputs.size():
		_input_done.emit("fight")
	else:
		_show_actor_command()
