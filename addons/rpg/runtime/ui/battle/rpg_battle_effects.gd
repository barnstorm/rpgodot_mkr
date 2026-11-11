class_name RPGBattleEffects
extends RefCounted
## Battle animations for skills, items and attacks (the `animation` field of a skill, item or
## weapon). If the Animations database has a record with that ID and a sprite sheet, its frames
## are played: frame_width x frame_height cells, left to right then top to bottom, at `fps`, with
## optional `flashes` and `sounds` per frame. Otherwise a built-in procedural effect is drawn,
## picked from the name: slash, fire, ice, thunder, heal, or a generic hit burst.
## Effects never block: play() returns their length so the caller can wait if it wants to.

const BUILTIN := ["hit", "slash", "fire", "ice", "thunder", "heal"]


## Which built-in effect a free-text animation name maps to.
static func builtin_for(anim_id: String) -> String:
	var n := anim_id.to_lower()
	for pair in [["heal", ["heal", "cure", "recover", "restore", "potion"]], ["fire", ["fire", "flame", "burn", "blaze"]],
			["ice", ["ice", "frost", "freeze", "snow"]], ["thunder", ["thunder", "bolt", "spark", "lightning", "shock"]],
			["slash", ["slash", "sword", "strike", "cut", "blade"]]]:
		for word in pair[1]:
			if n.contains(word):
				return pair[0]
	return "hit"


## Plays an effect centred on `at` inside `parent`. Returns its duration in seconds.
static func play(parent: Control, at: Vector2, anim_id: String, rpg: Node = null) -> float:
	if parent == null or not parent.is_inside_tree():
		return 0.0
	if rpg != null and anim_id != "" and rpg.data != null and rpg.data.has_record("animations", anim_id):
		var rec: Dictionary = rpg.data.record("animations", anim_id)
		var d := _play_sheet(parent, at, rec, rpg)
		if d > 0.0:
			return d
	match builtin_for(anim_id):
		"slash": return _slash(parent, at)
		"fire": return _particles(parent, at, [Color(1, 0.85, 0.3), Color(1, 0.45, 0.1), Color(0.9, 0.15, 0.05)], -1.0, 0.55)
		"ice": return _particles(parent, at, [Color(0.85, 0.95, 1), Color(0.5, 0.8, 1), Color(0.3, 0.55, 1)], 1.0, 0.5)
		"heal": return _particles(parent, at, [Color(0.75, 1, 0.75), Color(0.4, 1, 0.55), Color(1, 1, 0.8)], -1.0, 0.65)
		"thunder": return _thunder(parent, at)
	return _burst(parent, at)


static func _layer(parent: Control) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = parent.size
	parent.add_child(c)
	return c


static func _slash(parent: Control, at: Vector2) -> float:
	var c := _layer(parent)
	for i in 3:
		var l := Line2D.new()
		l.width = 2.0
		l.default_color = Color(1, 1, 1, 0.95)
		var off := Vector2((i - 1) * 7, (i - 1) * -3)
		l.points = PackedVector2Array([at + off + Vector2(-16, -16), at + off + Vector2(-16, -16)])
		c.add_child(l)
		var t := l.create_tween()
		t.tween_interval(i * 0.05)
		t.tween_method(func(k: float): l.points = PackedVector2Array([at + off + Vector2(-16, -16), at + off + Vector2(-16, -16).lerp(Vector2(16, 16), k)]), 0.0, 1.0, 0.12)
		t.tween_property(l, "modulate:a", 0.0, 0.18)
	_free_after(c, 0.5)
	return 0.4


static func _particles(parent: Control, at: Vector2, colours: Array, dir: float, seconds: float) -> float:
	var c := _layer(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)   # deterministic per position, so screenshots and tests repeat
	for i in 16:
		var p := ColorRect.new()
		var s := rng.randf_range(2.0, 4.0)
		p.size = Vector2(s, s)
		p.color = colours[i % colours.size()]
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var start := at + Vector2(rng.randf_range(-14, 14), rng.randf_range(-6, 10) * -dir)
		p.position = start
		p.modulate.a = 0.0
		c.add_child(p)
		var t := p.create_tween()
		t.tween_interval(rng.randf_range(0.0, seconds * 0.4))
		t.tween_property(p, "modulate:a", 1.0, 0.05)
		t.parallel().tween_property(p, "position", start + Vector2(rng.randf_range(-6, 6), dir * rng.randf_range(14, 26)), seconds * 0.6)
		t.tween_property(p, "modulate:a", 0.0, 0.12)
	_free_after(c, seconds + 0.3)
	return seconds


static func _thunder(parent: Control, at: Vector2) -> float:
	var c := _layer(parent)
	var l := Line2D.new()
	l.width = 2.0
	l.default_color = Color(1, 1, 0.55)
	var pts := PackedVector2Array()
	var y := at.y - 60.0
	var x := at.x
	var flip := 1.0
	while y < at.y:
		pts.append(Vector2(x, y))
		y += 9.0
		x += 6.0 * flip
		flip = -flip
	pts.append(at)
	l.points = pts
	c.add_child(l)
	var flash := ColorRect.new()
	flash.size = parent.size
	flash.color = Color(1, 1, 0.8, 0.35)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(flash)
	var t := c.create_tween()
	t.tween_property(flash, "color:a", 0.0, 0.15)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.35)
	_free_after(c, 0.5)
	return 0.35


static func _burst(parent: Control, at: Vector2) -> float:
	var c := _layer(parent)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		var l := Line2D.new()
		l.width = 1.5
		l.default_color = Color(1, 1, 0.85)
		l.points = PackedVector2Array([at + d * 3, at + d * 6])
		c.add_child(l)
		var t := l.create_tween()
		t.tween_method(func(k: float): l.points = PackedVector2Array([at + d * (3 + 8 * k), at + d * (6 + 12 * k)]), 0.0, 1.0, 0.16)
		t.tween_property(l, "modulate:a", 0.0, 0.1)
	_free_after(c, 0.4)
	return 0.26


## Sprite-sheet animation from the Animations database.
static func _play_sheet(parent: Control, at: Vector2, rec: Dictionary, rpg: Node) -> float:
	var sheet := str(rec.get("sheet", ""))
	if sheet == "":
		return 0.0
	var tex: Texture2D = RPGAssets.load_texture("picture", sheet)
	if tex == null:
		return 0.0
	var fw := maxi(1, int(rec.get("frame_width", 96)))
	var fh := maxi(1, int(rec.get("frame_height", 96)))
	var cols := maxi(1, tex.get_width() / fw)
	var count := maxi(1, cols * maxi(1, tex.get_height() / fh))
	var frames: Array = rec.get("frames", [])
	var order: Array = []
	for f in frames:
		order.append(int(f) if not (f is Dictionary) else int(f.get("cell", 0)))
	if order.is_empty():
		for i in count:
			order.append(i)
	var fps := maxf(1.0, float(rec.get("fps", 12.0)))
	var c := _layer(parent)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	var r := TextureRect.new()
	r.texture = atlas
	r.size = Vector2(fw, fh)
	r.position = at - Vector2(fw, fh) / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	var set_frame := func(i: int) -> void:
		var cell: int = clampi(int(order[clampi(i, 0, order.size() - 1)]), 0, count - 1)
		atlas.region = Rect2((cell % cols) * fw, (cell / cols) * fh, fw, fh)
	set_frame.call(0)
	var duration := order.size() / fps
	var t := c.create_tween()
	t.tween_method(func(k: float): set_frame.call(int(k)), 0.0, float(order.size()) - 0.001, duration)
	for s in rec.get("sounds", []):
		if s is Dictionary and rpg.audio != null:
			c.get_tree().create_timer(int(s.get("frame", 0)) / fps).timeout.connect(func(): rpg.audio.play_se(s.get("sound")))
	for fl in rec.get("flashes", []):
		if fl is Dictionary:
			var col: Array = fl.get("color", [255, 255, 255, 170])
			var rect := ColorRect.new()
			rect.size = parent.size
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.color = Color8(int(col[0]), int(col[1]), int(col[2]), 0)
			c.add_child(rect)
			var ft := rect.create_tween()
			ft.tween_interval(int(fl.get("frame", 0)) / fps)
			ft.tween_property(rect, "color:a", int(col[3]) / 255.0 if col.size() > 3 else 0.6, 0.04)
			ft.tween_property(rect, "color:a", 0.0, 0.2)
	_free_after(c, duration + 0.4)
	return duration


static func _free_after(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())
