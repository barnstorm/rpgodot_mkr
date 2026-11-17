@tool
class_name RPGTimerDisplay
extends Control
## The on-screen countdown of the game's timers (RPG Maker 2003 style): digits cut from the
## System graphic (theme class "RPGWindow", icons timer_0 .. timer_11, 10 is the colon) or, for
## windowskins without that strip, plain text. One of these lives with the map HUD and one in the
## battle scene; each draws every timer whose Control Timer Set marked it visible, at its corner.


## The game state whose timers are drawn (RPGGameState).
var state: Object = null
## The RPG service (for the project's asset profile and, on the map copy, "a battle is on": the
## battle screen draws its own display, so the map one steps aside).
var service: Object = null
## True for the map copy: hide while a battle runs (the battle scene has its own display).
var yield_to_battle := false

## What was last drawn ("id:seconds:position" per timer), so only changes repaint.
var _drawn := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchors_preset = Control.PRESET_FULL_RECT


func _process(_delta: float) -> void:
	if state == null or not is_instance_valid(state):
		return
	var sig := ""
	for id in ["1", "2"]:
		var t: Dictionary = state.timer(id)
		if bool(t.get("visible", false)):
			sig += "%s:%d:%s;" % [id, state.timer_seconds(id), t.get("position", "top_right")]
	if sig != _drawn:
		_drawn = sig
		queue_redraw()


func _draw() -> void:
	if state == null or not is_instance_valid(state):
		return
	if yield_to_battle and service != null and is_instance_valid(service):
		var b: Variant = service.get("battle")
		if b != null and b is Object and is_instance_valid(b) and b.valid():
			return
	for id in ["1", "2"]:
		var t: Dictionary = state.timer(id)
		if not bool(t.get("visible", false)):
			continue
		_draw_strip(format_seconds(state.timer_seconds(id)), str(t.get("position", "top_right")))


## "m:ss", capped at 99:59 the way the classic display is.
static func format_seconds(seconds: int) -> String:
	var s := clampi(seconds, 0, 5999)
	return "%d:%02d" % [s / 60, s % 60]


## One timer's readout at a corner of the 320x240 screen.
func _draw_strip(text: String, position: String) -> void:
	var size := get_parent_area_size()
	if size.x <= 0.0:
		size = Vector2(320, 240)
	if _digit_icons():
		var icons := []
		for ch in text:
			icons.append(get_theme_icon("timer_10" if ch == ":" else "timer_%s" % ch, "RPGWindow"))
		var w := icons.size() * 8.0
		var at := _corner(size, position, Vector2(w, 16))
		for icon in icons:
			if icon != null:
				draw_texture_rect(icon, Rect2(at, Vector2(8, 16)), false)
			at.x += 8.0
		return
	var font: Font = get_theme_font("font")
	var fs := font.get_height(12)
	var pos := _corner(size, position, Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, fs))
	var shadow := get_theme_color("shadow", "RPGWindow") if has_theme_color("shadow", "RPGWindow") else Color.BLACK
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, shadow)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		get_theme_color("text_0", "RPGWindow") if has_theme_color("text_0", "RPGWindow") else Color.WHITE)


func _corner(area: Vector2, position: String, item: Vector2) -> Vector2:
	var at := Vector2(4, 4)
	match position:
		"top_left":
			at = Vector2(4, 4)
		"bottom_left":
			at = Vector2(4, maxf(4.0, area.y - 4.0 - item.y))
		"bottom_right":
			at = Vector2(maxf(4.0, area.x - 4.0 - item.x), maxf(4.0, area.y - 4.0 - item.y))
		_:
			at = Vector2(maxf(4.0, area.x - 4.0 - item.x), 4)
	return at


## The timer strip is cut from the System graphic's top rows, which only an RPG Maker 2000/2003
## skin has; VX/XP/MV skins fall back to text.
func _digit_icons() -> bool:
	if service == null or not is_instance_valid(service):
		return true
	var data: Variant = service.get("data")
	if data == null or not data is Object or not is_instance_valid(data):
		return true
	var profile: Variant = data.get("profile") if "profile" in data else {}
	var id := str(profile.get("profile", "rm2k")) if profile is Dictionary else "rm2k"
	return id == "rm2k"
