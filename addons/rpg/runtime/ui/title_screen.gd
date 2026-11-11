extends "res://addons/rpg/runtime/ui/rpg_ui_screen.gd"
## Default title screen: New Game, Continue (disabled without saves), Options, Quit.
## Shows system.json "title_image" (Title folder) or a gradient with the project name, and plays
## the system title music. Options open inline; the other commands emit chosen(choice).

signal chosen(choice: String)

const CHOICES := ["new_game", "continue", "options", "quit"]

var list: Control
var has_saves := false
var _t := 0.0
var _name_label: Label


func _build() -> void:
	var sys: Dictionary = rpg.data.system if rpg and rpg.data else {}
	var img := str(sys.get("title_image", ""))
	var tex: Texture2D = rpg.ui.load_texture("title", img) if rpg and rpg.ui and img != "" else null
	if tex != null:
		full_rect_texture(tex)
	else:
		full_rect_texture(gradient_texture(Color(0.04, 0.05, 0.16), Color(0.02, 0.02, 0.05), Color(0.2, 0.12, 0.35)))
		_stars()
		var title := str(sys.get("title", ""))
		if title == "" and rpg and rpg.data:
			title = str(rpg.data.project.get("name", "")) if rpg.data.project.get("name", "") != "" else "RPG"
		_name_label = make_label(self, Vector2(0, 52), title, 24, Color(1, 0.95, 0.8), W, HORIZONTAL_ALIGNMENT_CENTER)
		_name_label.size.y = 34
		_name_label.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.25))
		_name_label.add_theme_constant_override("outline_size", 6)
		_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		_name_label.add_theme_constant_override("shadow_offset_y", 2)
	has_saves = _any_save()
	var win := make_window(Rect2(112, 150, 96, 16 + CHOICES.size() * ROW))
	list = make_list(win, Rect2(6, 8, 84, CHOICES.size() * ROW))
	list.set_items([
		{"text": term("new_game", "New Game")},
		{"text": term("continue", "Continue"), "enabled": has_saves},
		{"text": term("options", "Options")},
		{"text": term("quit", "Quit")},
	])
	if has_saves:
		list.select(1)
	var music: Variant = system_music("title")
	if music != null and rpg and rpg.audio:
		rpg.audio.play_bgm(music)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)


func _any_save() -> bool:
	if rpg == null or rpg.saves == null:
		return false
	for i in range(1, rpg.saves.MAX_SLOTS + 1):
		if rpg.saves.exists(i):
			return true
	return false


func _stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var s := ColorRect.new()
		s.size = Vector2.ONE * (2 if rng.randf() < 0.15 else 1)
		s.position = Vector2(rng.randi_range(0, W - 1), rng.randi_range(0, 140))
		s.color = Color(1, 1, 1, rng.randf_range(0.25, 0.9))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)


func _update(delta: float) -> void:
	_t += delta
	if _name_label:
		_name_label.position.y = 52 + sin(_t * 1.6) * 2.0


func handle_action(a: String) -> void:
	match a:
		"up", "down":
			if list.move(0, -1 if a == "up" else 1):
				play("cursor")
		"ok":
			choose(CHOICES[list.index])


## Picks a command as if the player pressed OK on it.
func choose(choice: String) -> void:
	if not input_enabled:
		return
	if choice == "continue" and not has_saves:
		play("buzzer")
		return
	play("decision")
	if choice == "options":
		input_enabled = false
		var node := open_sub("options")
		if node != null and node.has_signal("closed"):
			await node.closed
			close_sub(node)
		input_enabled = true
		return
	input_enabled = false
	chosen.emit(choice)
