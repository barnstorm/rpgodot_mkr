@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "show_scrolling_text", "schema_version": 1, "category": "message", "label": "Show Scrolling Text",
		"fields": [
			{"key": "text", "kind": "multiline", "default": "", "label": "Text", "required": true},
			{"key": "speed", "kind": "int", "default": 2, "min": 1, "max": 8, "label": "Speed"},
			{"key": "no_fast_forward", "kind": "bool", "default": false, "label": "No fast forward"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Scrolling Text: %s" % str(args.get("text", "")).replace("\n", " / ").left(60)


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(320, 240)
	var lab := RichTextLabel.new()
	lab.bbcode_enabled = true
	lab.fit_content = true
	lab.scroll_active = false
	lab.size = Vector2(300, 10)
	lab.position = Vector2(10, 240)
	lab.add_theme_font_size_override("normal_font_size", 11)
	var parsed := RPGText.expand(str(args.text), ctx.rpg)
	lab.text = "[center]" + parsed.bbcode + "[/center]"
	ctx.ui.root.add_child(bg)
	ctx.ui.root.add_child(lab)
	if ctx.ui.auto_advance:
		lab.position.y = -10000
	var speed := float(args.speed) * 12.0
	while lab.position.y + lab.get_content_height() > 0:
		if ctx.is_cancelled():
			break
		var fast: bool = not args.no_fast_forward and Input.is_action_pressed("rpg_ok")
		lab.position.y -= ctx.tree.root.get_process_delta_time() * speed * (4.0 if fast else 1.0)
		await ctx.tree.process_frame
	lab.queue_free()
	bg.queue_free()
	return RPGResult.cancelled() if ctx.is_cancelled() else RPGResult.ok()
