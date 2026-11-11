extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default game over screen: system.json "gameover_image" (GameOver folder) or large text on a
## dark red fade, with the game over jingle played once. Any key or click (after a short pause)
## emits closed.

signal closed()

const MIN_TIME := 0.8

var _t := 0.0
var _hint: Label


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(W, H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var sys: Dictionary = rpg.data.system if rpg and rpg.data else {}
	var img := str(sys.get("gameover_image", ""))
	var tex: Texture2D = rpg.ui.load_texture("gameover", img) if rpg and rpg.ui and img != "" else null
	if tex != null:
		full_rect_texture(tex)
	else:
		full_rect_texture(gradient_texture(Color(0, 0, 0), Color(0, 0, 0), Color(0.28, 0.02, 0.04)))
		var l := make_label(self, Vector2(0, 92), term("game_over", "Game Over"), 28, Color(0.95, 0.85, 0.85), W, HORIZONTAL_ALIGNMENT_CENTER)
		l.size.y = 40
		l.add_theme_color_override("font_outline_color", Color(0.35, 0, 0))
		l.add_theme_constant_override("outline_size", 6)
	_hint = make_label(self, Vector2(0, 210), "Press a button", SMALL, Color(1, 1, 1, 0.7), W, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.visible = false
	# As in MV's Scene_Gameover: music and background sound stop and the game over jingle plays
	# once (the defeat jingle when the System has no game over one).
	var music: Variant = system_music("game_over")
	if music == null:
		music = system_music("defeat")
	if rpg and rpg.audio:
		rpg.audio.stop_bgm()
		if rpg.audio.has_method("stop_bgs"):
			rpg.audio.stop_bgs()
		if music != null:
			rpg.audio.play_me(music)
		else:
			play("game_over")
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)
	if auto_mode():
		close.call_deferred()


func _update(delta: float) -> void:
	_t += delta
	if _hint and _t >= MIN_TIME:
		_hint.visible = int(_t * 2) % 2 == 0


func handle_action(a: String) -> void:
	if (a == "ok" or a == "cancel") and _t >= MIN_TIME:
		play("decision")
		close()


func close() -> void:
	if not input_enabled:
		return
	input_enabled = false
	closed.emit()
