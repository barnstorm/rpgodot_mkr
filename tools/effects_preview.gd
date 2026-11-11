extends SceneTree
## Renders the built-in battle effects side by side into tools/shots/effects.png.
##   godot --path . --script res://tools/effects_preview.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 240)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.32, 0.2)
	bg.size = Vector2(960, 240)
	root.add_child(bg)
	var layer := Control.new()
	layer.size = Vector2(960, 240)
	layer.scale = Vector2(3, 3)
	root.add_child(layer)
	layer.size = Vector2(320, 80)
	var font := ThemeDB.fallback_font
	var names := RPGBattleEffects.BUILTIN
	for i in names.size():
		var at := Vector2(27 + i * 53, 40)
		var l := Label.new()
		l.text = names[i]
		l.position = Vector2(at.x - 20, 62)
		l.add_theme_font_size_override("font_size", 8)
		layer.add_child(l)
		RPGBattleEffects.play(layer, at, names[i])
	for i in 9:
		await process_frame
	await create_timer(0.12).timeout
	var out := "res://tools/shots/effects.png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out))
	print("saved ", out)
	quit(0)
