extends Control
## A styled damage popup (enemy_gauges plugin). The battle scene puts its origin on the
## battler's popup point; it pops in (grows past its size and settles), rises, waits and fades,
## then frees itself.
##   damage         white number
##   critical       a bigger number in the critical colour with a tag above it, and a small shake
##   miss           the miss text, drifting sideways
##   heal           a green number (with +), rising gently
##   resource_up / resource_down / slip   smaller numbers in blue / violet / purple

const BASE_SIZE := 14

var style := ""
## Pixels the popup rises; smaller for front-view party rows (17 px apart).
var rise := 12.0


static func make(p_style: String, text: String, cfg: Dictionary, rpg: Node = null, small := false) -> Control:
	var p: Control = load("res://addons/rpg/extensions/enemy_gauges/damage_popup.gd").new()
	p.style = p_style
	p.rise = 4.0 if small else 12.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.name = "Popup_" + p_style
	var theme: Variant = rpg.ui.ui_theme if rpg != null and rpg.ui != null and rpg.ui.get("ui_theme") is Theme else null
	var size_px := BASE_SIZE
	var col: Color = cfg.get("damage", Color.WHITE)
	var shown := text
	match p_style:
		"critical":
			size_px = BASE_SIZE + 4
			col = cfg.get("critical", Color(1, 0.77, 0.25))
		"miss":
			size_px = BASE_SIZE - 2
			col = cfg.get("miss", Color(0.75, 0.75, 0.78))
			shown = str(cfg.get("miss_text", "Miss"))
		"heal":
			col = cfg.get("heal", Color(0.47, 1, 0.55))
			if bool(cfg.get("heal_sign", true)) and not shown.begins_with("+"):
				shown = "+" + shown
		"resource_up":
			size_px = BASE_SIZE - 2
			col = Color(0.45, 0.75, 1.0)
		"resource_down":
			size_px = BASE_SIZE - 2
			col = Color(0.8, 0.6, 1.0)
		"slip":
			size_px = BASE_SIZE - 2
			col = Color(0.85, 0.55, 1.0)
	if small:
		size_px = maxi(10, size_px - 3)
	var main := _label(shown, size_px, col, theme)
	p.add_child(main)
	if p_style == "critical":
		var tag := _label(str(cfg.get("critical_text", "Critical!")), 9, col.lerp(Color(1, 0.35, 0.25), 0.5), theme)
		tag.position.y -= size_px - 2
		p.add_child(tag)
	return p


static func _label(text: String, size_px: int, col: Color, theme: Variant) -> Label:
	var l := Label.new()
	l.text = text
	if theme is Theme:
		l.theme = theme
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(80, size_px + 6)
	l.position = -l.size / 2.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	pivot_offset = Vector2.ZERO
	var t := create_tween()
	match style:
		"miss":
			modulate.a = 0.0
			t.set_parallel(true)
			t.tween_property(self, "modulate:a", 1.0, 0.12)
			t.tween_property(self, "position:x", position.x + 10.0, 0.6).set_ease(Tween.EASE_OUT)
			t.tween_property(self, "position:y", position.y - rise * 0.5, 0.6).set_ease(Tween.EASE_OUT)
			t.set_parallel(false)
			t.tween_property(self, "modulate:a", 0.0, 0.3)
		"heal":
			scale = Vector2(0.6, 0.6)
			t.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(self, "position:y", position.y - rise * 1.3, 0.7).set_ease(Tween.EASE_OUT)
			t.tween_property(self, "modulate:a", 0.0, 0.3)
		_:
			# Pop: grow past full size, settle, hop up, hold, fade.
			var big := 1.9 if style == "critical" else 1.5
			scale = Vector2(big, big)
			t.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if style == "critical":
				for dx in [3.0, -3.0, 2.0, 0.0]:
					t.tween_property(self, "position:x", position.x + dx, 0.03)
			t.tween_property(self, "position:y", position.y - rise, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			t.tween_property(self, "position:y", position.y - rise * 0.6, 0.12).set_ease(Tween.EASE_IN)
			t.tween_interval(0.45)
			t.tween_property(self, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)
