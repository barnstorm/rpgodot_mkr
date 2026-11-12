extends SceneTree
## Draws the sample image-backed map's art (CC0, made for the kit): a walled garden, 320×240 px
## (20×15 cells of 16 px), with a pond, flower beds, a bench, an arch over the path and a tree.
## Writes assets/starter/MapImage/garden.png (base) and garden_fg.png (foreground: the arch's
## beam and the tree's crown, which characters walk behind).
##   godot --headless --path . --script res://tools/make_garden_art.gd

const W := 320
const H := 240
const T := 16
const OUT := "res://assets/starter/MapImage"

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261112
	DirAccess.make_dir_recursive_absolute(OUT)
	var base := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var fg := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	_grass(base)
	_path(base)
	_hedges(base)
	_pond(base)
	_beds(base)
	_bench(base, Vector2i(14 * T, 3 * T))
	_arch(base, fg, 8, 11, 10)
	_tree(base, fg, Vector2i(4 * T, 5 * T))
	base.save_png(OUT.path_join("garden.png"))
	fg.save_png(OUT.path_join("garden_fg.png"))
	print("wrote garden.png and garden_fg.png")
	quit()


func _c(hex: String) -> Color:
	return Color.html(hex)


func _speckle(img: Image, r: Rect2i, cols: Array, chance: float) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if rng.randf() < chance:
				img.set_pixel(x, y, cols[rng.randi() % cols.size()])


func _grass(img: Image) -> void:
	img.fill(_c("#5a9a3c"))
	_speckle(img, Rect2i(0, 0, W, H), [_c("#4f8c35"), _c("#68a947"), _c("#5f9f40")], 0.35)
	# Little tufts.
	for i in 140:
		var p := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		img.set_pixelv(p, _c("#7bbd52"))
		img.set_pixelv(p + Vector2i(1, -1), _c("#7bbd52"))
		img.set_pixelv(p + Vector2i(-1, -1), _c("#468030"))


func _path(img: Image) -> void:
	# A flagstone path from the gate (bottom middle) up to the pond.
	var r := Rect2i(9 * T, 9 * T, 2 * T, H - 9 * T)
	img.fill_rect(r, _c("#b8a888"))
	for y in range(r.position.y, r.end.y, 8):
		var off := 0 if (y / 8) % 2 == 0 else 4
		for x in range(r.position.x - off, r.end.x, 8):
			var stone := Rect2i(x + 1, y + 1, 6, 6).intersection(r)
			if stone.size.x > 0:
				img.fill_rect(stone, _c("#cdbf9e") if rng.randf() < 0.5 else _c("#c3b593"))
	_speckle(img, r, [_c("#a8987a")], 0.08)


func _hedges(img: Image) -> void:
	var dark := _c("#2f5e2a")
	var mid := _c("#3d7534")
	var light := _c("#4f8c3f")
	var gate := Rect2i(9 * T, H - T, 2 * T, T)
	for r in [Rect2i(0, 0, W, 2 * T), Rect2i(0, 0, T, H), Rect2i(W - T, 0, T, H), Rect2i(0, H - T, W, T)]:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if gate.has_point(Vector2i(x, y)):
					continue
				var n := rng.randf()
				img.set_pixel(x, y, dark if n < 0.3 else (mid if n < 0.8 else light))
	# A lighter top edge on the back hedge reads as its top; the front face is darker.
	for x in range(T, W - T):
		img.set_pixel(x, 2 * T - 1, _c("#244a20"))
		img.set_pixel(x, 2 * T - 2, _c("#2a5525"))
	# Gate posts.
	for gx in [9 * T - 4, 11 * T]:
		img.fill_rect(Rect2i(gx, H - T - 6, 4, T + 6), _c("#8a8378"))
		img.fill_rect(Rect2i(gx, H - T - 6, 4, 2), _c("#aaa398"))


func _pond(img: Image) -> void:
	var c := Vector2(10 * T, 6 * T)
	var rx := 3.4 * T
	var ry := 2.2 * T
	for y in H:
		for x in W:
			var d := pow((x - c.x) / rx, 2) + pow((y - c.y) / ry, 2)
			if d <= 1.0:
				var col := _c("#3c78b4") if d > 0.55 else _c("#2f67a3")
				if d > 0.82:
					col = _c("#5a91c8")
				img.set_pixel(x, y, col)
			elif d <= 1.18:
				img.set_pixel(x, y, _c("#9a9488") if (x + y) % 5 else _c("#7e786d"))
	# Glints and a lily pad.
	for p in [Vector2i(140, 84), Vector2i(176, 100), Vector2i(150, 108)]:
		img.fill_rect(Rect2i(p, Vector2i(3, 1)), _c("#a8d0f0"))
	img.fill_rect(Rect2i(178, 82, 6, 4), _c("#4c9a3a"))
	img.set_pixel(180, 81, _c("#f0a0c0"))


func _beds(img: Image) -> void:
	var flowers := [_c("#e8d048"), _c("#e86a6a"), _c("#f0f0f0"), _c("#c070e0")]
	for r in [Rect2i(2 * T, 10 * T, 5 * T, 2 * T), Rect2i(13 * T, 10 * T, 5 * T, 2 * T)]:
		img.fill_rect(r, _c("#6b4a2e"))
		img.fill_rect(Rect2i(r.position, Vector2i(r.size.x, 2)), _c("#8a5f3a"))
		_speckle(img, r.grow(-2), [_c("#5b3d24")], 0.3)
		for i in 26:
			var p := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 4), rng.randi_range(r.position.y + 4, r.end.y - 4))
			img.set_pixelv(p + Vector2i(0, 1), _c("#3f7a30"))
			img.set_pixelv(p, flowers[rng.randi() % flowers.size()])


func _bench(img: Image, at: Vector2i) -> void:
	var wood := _c("#9b6a3c")
	var dark := _c("#6e4a28")
	img.fill_rect(Rect2i(at + Vector2i(1, 4), Vector2i(2 * T - 2, 4)), wood)
	img.fill_rect(Rect2i(at + Vector2i(1, 9), Vector2i(2 * T - 2, 3)), wood)
	img.fill_rect(Rect2i(at + Vector2i(1, 8), Vector2i(2 * T - 2, 1)), dark)
	for lx in [3, 2 * T - 5]:
		img.fill_rect(Rect2i(at + Vector2i(lx, 12), Vector2i(2, 4)), dark)


## Posts at cells x0 and x1 on row `row`; the beam spans the row above in the foreground.
func _arch(base: Image, fg: Image, x0: int, x1: int, row: int) -> void:
	var post := _c("#e8e0d0")
	var shade := _c("#b8ae9c")
	for cx in [x0, x1]:
		var r := Rect2i(cx * T + 5, (row - 1) * T + 6, 6, T + 10)
		base.fill_rect(r, post)
		base.fill_rect(Rect2i(r.position + Vector2i(4, 0), Vector2i(2, r.size.y)), shade)
		# Shadow on the ground.
		base.fill_rect(Rect2i(cx * T + 2, row * T + 14, 12, 2), _c("#46782f"))
	# Beam and vines: above the characters walking under it.
	var beam := Rect2i(x0 * T + 2, (row - 1) * T - 2, (x1 - x0 + 1) * T - 4, 9)
	fg.fill_rect(beam, post)
	fg.fill_rect(Rect2i(beam.position.x, beam.end.y - 2, beam.size.x, 2), shade)
	for i in 34:
		var p := Vector2i(rng.randi_range(beam.position.x, beam.end.x - 1), rng.randi_range(beam.position.y - 3, beam.end.y + 3))
		fg.set_pixelv(p, _c("#3f8a34") if rng.randf() < 0.7 else _c("#e86a9a"))
	# The posts' tops too, so a character beside a post is behind its upper part.
	for cx in [x0, x1]:
		fg.fill_rect(Rect2i(cx * T + 5, (row - 1) * T + 6, 6, 8), post)
		fg.fill_rect(Rect2i(cx * T + 9, (row - 1) * T + 6, 2, 8), shade)


## A tree: trunk on the base image at `at` (top-left of its cell), crown in the foreground.
func _tree(base: Image, fg: Image, at: Vector2i) -> void:
	base.fill_rect(Rect2i(at + Vector2i(5, 0), Vector2i(6, T)), _c("#6e4a28"))
	base.fill_rect(Rect2i(at + Vector2i(9, 0), Vector2i(2, T)), _c("#553719"))
	base.fill_rect(Rect2i(at + Vector2i(1, T - 2), Vector2i(14, 3)), _c("#3e6e2b"))
	var c := Vector2(at.x + 8, at.y - 14)
	for y in range(int(c.y) - 26, int(c.y) + 18):
		for x in range(int(c.x) - 26, int(c.x) + 27):
			var d := pow((x - c.x) / 25.0, 2) + pow((y - c.y) / 17.0, 2)
			if d <= 1.0 and x >= 0 and y >= 0 and x < W and y < H:
				var n := rng.randf()
				var col := _c("#2f6a2a") if n < 0.35 else (_c("#3d8034") if n < 0.85 else _c("#58a046"))
				if d > 0.8 and y > c.y:
					col = _c("#24521f")
				fg.set_pixel(x, y, col)
