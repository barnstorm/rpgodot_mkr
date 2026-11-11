extends Node2D
## One enemy's HP bar (enemy_gauges plugin), a child of the battle scene's battler_node(enemy):
## its origin is the bottom centre of the enemy's image. The bar drains smoothly to the new HP;
## the part just lost stays a moment in the drain colour, then shrinks. It fades in and out with
## the "show" setting, and fades away once the enemy is knocked out.

## Seconds the bar takes to slide to a new value, and the pause before the lost part drains.
const SLIDE_SECONDS := 0.25
const DRAIN_DELAY := 0.35
const DRAIN_SECONDS := 0.45
## "targeted" mode: seconds the bar stays after a hit.
const AFTER_HIT_SECONDS := 1.4
const FADE_SECONDS := 0.18

var plugin: Object
var scene: Node
var battler: Object
var style: Dictionary = {}
## Shown and lagging ratios (0..1) and the opacity drawn now.
var shown_ratio := 1.0
var drain_ratio := 1.0
var alpha := 0.0
var _last_hp := -1
var _since_hit := 99.0
var _drain_wait := 0.0
var _label: Label = null


func setup(p_plugin: Object, p_scene: Node, p_battler: Object) -> void:
	plugin = p_plugin
	scene = p_scene
	battler = p_battler
	style = plugin.gauge_style()
	name = "HPGauge"
	shown_ratio = ratio()
	drain_ratio = shown_ratio
	_last_hp = hp()
	alpha = 1.0 if wanted() else 0.0
	if str(style.get("numbers", "none")) != "none":
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 8)
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_label.add_theme_constant_override("outline_size", 3)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if plugin.rpg != null and plugin.rpg.ui != null and plugin.rpg.ui.get("ui_theme") is Theme:
			_label.theme = plugin.rpg.ui.ui_theme
		add_child(_label)
	_refresh_label()
	queue_redraw()


func hp() -> int:
	var res: String = battler.life_resource
	return int(battler.get_resource(res))


func max_hp() -> int:
	var rules: Object = scene.rules() if scene != null and scene.has_method("rules") else null
	if rules != null:
		return maxi(1, int(rules.max_resource(battler, rules.life_resource())))
	return maxi(1, hp())


func ratio() -> float:
	return clampf(float(hp()) / float(max_hp()), 0.0, 1.0)


## Whether the settings want the bar on screen now.
func wanted() -> bool:
	if battler == null or battler.hidden:
		return false
	if battler.is_dead() and drain_ratio <= 0.001:
		return false
	match plugin.show_mode():
		"targeted":
			return targeted() or _since_hit < AFTER_HIT_SECONDS
		"defeated":
			return plugin.was_defeated(battler.id)
	return true


## True while the player is choosing this enemy as a target.
func targeted() -> bool:
	if scene == null or str(scene.get("phase")) != "target_enemy" or scene.get("core") == null:
		return false
	var i: int = int(scene.target_index)
	return i >= 0 and i < scene.core.enemies.size() and scene.core.enemies[i] == battler


func _process(delta: float) -> void:
	if battler == null:
		return
	var now := hp()
	if now != _last_hp:
		if now < _last_hp:
			_drain_wait = DRAIN_DELAY
		_since_hit = 0.0
		_last_hp = now
	_since_hit += delta
	var target := ratio()
	# The front edge slides; the drain part waits, then follows.
	shown_ratio = move_toward(shown_ratio, target, delta / SLIDE_SECONDS)
	if drain_ratio < shown_ratio:
		drain_ratio = shown_ratio
	elif _drain_wait > 0.0:
		_drain_wait -= delta
	else:
		drain_ratio = move_toward(drain_ratio, shown_ratio, delta / DRAIN_SECONDS)
	alpha = move_toward(alpha, 1.0 if wanted() else 0.0, delta / FADE_SECONDS)
	_refresh_label()
	queue_redraw()


func _refresh_label() -> void:
	if _label == null:
		return
	var h := hp()
	match str(style.get("numbers", "none")):
		"value":
			_label.text = str(h)
		"value_max":
			_label.text = "%d/%d" % [h, max_hp()]
		"percent":
			_label.text = "%d%%" % roundi(100.0 * ratio())
	var w := float(style.get("width", 40))
	_label.size = Vector2(maxf(w, 40.0), 11)
	_label.position = Vector2(-_label.size.x / 2.0, _bar_top() - 10.0)
	_label.modulate.a = alpha


## Bar top relative to the origin: just under the image, kept above the command windows.
func _bar_top() -> float:
	var h := float(style.get("height", 4))
	var floor_y := 160.0
	if scene != null and "FIELD_H" in scene:
		floor_y = float(scene.FIELD_H)
	var origin_y: float = get_parent().position.y if get_parent() is Node2D else 0.0
	return minf(1.0, floor_y - 2.0 - h - origin_y)


## The bar's colour: healthy colour down to half, then towards the low colour.
func fill_colour(r: float) -> Color:
	var full: Color = style.get("full", Color.GREEN)
	var low: Color = style.get("low", Color.RED)
	return full if r >= 0.5 else low.lerp(full, clampf(r * 2.0, 0.0, 1.0))


func _draw() -> void:
	if alpha <= 0.0:
		return
	var w := float(style.get("width", 40))
	var h := float(style.get("height", 4))
	var top := _bar_top()
	var outer := Rect2(-w / 2.0 - 1.0, top - 1.0, w + 2.0, h + 2.0)
	var back: Color = style.get("back", Color(0, 0, 0, 0.8))
	draw_rect(outer, Color(back, back.a * alpha))
	var inner := Rect2(-w / 2.0, top, w, h)
	var drain: Color = style.get("drain", Color(1, 0.9, 0.5))
	if drain_ratio > shown_ratio:
		draw_rect(Rect2(inner.position, Vector2(round(w * drain_ratio), h)), Color(drain, drain.a * alpha))
	var fc := fill_colour(shown_ratio)
	var fw := round(w * shown_ratio)
	if fw > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fw, h)), Color(fc, fc.a * alpha))
		# A lighter top line gives the bar some depth.
		draw_rect(Rect2(inner.position, Vector2(fw, 1.0)), Color(fc.lightened(0.35), fc.a * alpha * 0.9))
