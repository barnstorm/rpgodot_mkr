extends SceneTree
## Generates the CC0 starter pack (assets/starter/) procedurally:
##   godot --headless --path <project> --script res://tools/generate_starter_assets.gd
## then run `--import`. Terrain 0 (grass) is seamless base ground; the other terrains carry their
## own border. Everything here is original, authored by this project (CC0-1.0).
## The ChipSet follows the 2000/2003 layout exactly as RPGChipset2k decodes it.

const OUT := "res://assets/starter"
const T := 16

# --- palette -------------------------------------------------------------------------------------
var P := {
	"ink": Color("1a1c2c"), "void": Color("17141f"), "void2": Color("231d2e"),
	"g0": Color("24552e"), "g1": Color("3b7d3a"), "g2": Color("5ca546"), "g3": Color("94d05e"),
	"dg0": Color("173c26"), "dg1": Color("25583a"), "dg2": Color("3a7a46"), "dg3": Color("5c9c50"),
	"d0": Color("4e3022"), "d1": Color("7a4e30"), "d2": Color("a87444"), "d3": Color("cc9a62"),
	"s0": Color("a8884e"), "s1": Color("d8bc78"), "s2": Color("efdca2"),
	"st0": Color("343846"), "st1": Color("565c6e"), "st2": Color("8088a0"), "st3": Color("b4bccc"),
	"br0": Color("3e1c1c"), "br1": Color("7c3428"), "br2": Color("a8523a"), "br3": Color("c8765a"),
	"w0": Color("3e2414"), "w1": Color("6e4224"), "w2": Color("9c6636"), "w3": Color("c48e52"),
	"wa0": Color("1c3c84"), "wa1": Color("2a5cb4"), "wa2": Color("3f82da"), "wa3": Color("8cc6f4"), "foam": Color("e4f4ff"),
	"dp0": Color("0e1c48"), "dp1": Color("16306e"), "dp2": Color("22468e"),
	"sn0": Color("8c9cc4"), "sn1": Color("c4d2ec"), "sn2": Color("eef4fc"),
	"cp0": Color("5c1022"), "cp1": Color("98202e"), "cp2": Color("c63c44"), "gold": Color("e8b844"), "gold0": Color("a87820"),
	"r0": Color("5e1818"), "r1": Color("9a2c26"), "r2": Color("c84a36"), "r3": Color("e8765a"),
	"pl0": Color("a8987a"), "pl1": Color("d8ccb0"), "pl2": Color("f0e8d4"),
	"win0": Color("3a6a9c"), "win1": Color("7cb8e4"), "win2": Color("d4ecfc"),
	"skin": Color("f2c8a0"), "skin2": Color("d49a74"),
	"white": Color("f4f4f4"), "grey": Color("a0a4b0"), "black": Color("101018"),
	"red": Color("d03838"), "yellow": Color("f0d040"), "orange": Color("e88030"),
	"purple": Color("7a3ca8"), "purple2": Color("a866d0"), "pink": Color("f08cb0"),
	"lava0": Color("8a1c0c"), "lava1": Color("d8401a"), "lava2": Color("f88c28"), "lava3": Color("ffe070"),
	"sw0": Color("2c2438"), "sw1": Color("4a3a5c"), "sw2": Color("6a5a3c"), "sw3": Color("8ca050"),
}


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--vehicles"):
		# Only (re)write the vehicles sheet.
		_save(_charset_vehicles(), "CharSet/vehicles.png")
		quit()
		return
	for d in ["", "ChipSet", "CharSet", "FaceSet", "System", "Monster", "Backdrop", "Title", "Sound", "Music"]:
		DirAccess.make_dir_recursive_absolute(OUT.path_join(d))
	_write_pack_json()
	_save(_chipset(), "ChipSet/town.png")
	_save(_charset_people(), "CharSet/hero.png")
	_save(_charset_objects(), "CharSet/objects.png")
	_save(_charset_vehicles(), "CharSet/vehicles.png")
	_save(_faceset(), "FaceSet/hero_face.png")
	_save(_system(), "System/system.png")
	_save(_slime(), "Monster/slime.png")
	_save(_bat(), "Monster/bat.png")
	_save(_goblin(), "Monster/goblin.png")
	_save(_backdrop(), "Backdrop/grass.png")
	_save(_title(), "Title/title.png")
	_sounds()
	_music()
	print("Starter pack written to ", OUT)
	quit()


func _save(img: Image, rel: String) -> void:
	var err := img.save_png(OUT.path_join(rel))
	if err != OK:
		push_error("save failed %s: %d" % [rel, err])


# --- small drawing helpers -----------------------------------------------------------------------

func _img(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


func _hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(x0, x1 + 1):
		_px(img, x, y, c)


func _vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		_px(img, x, y, c)


func _disc(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


## Disc lit from the upper left: 4 shades + optional dither noise.
func _shaded(img: Image, cx: float, cy: float, rx: float, ry: float, pal: Array, seed := 0) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var lit := -(dx * 0.6 + dy * 0.8) + (1.0 - d2) * 0.6 + (_n(x, y, seed) - 0.5) * 0.5
			var i := 0
			if lit > 0.75:
				i = 3
			elif lit > 0.25:
				i = 2
			elif lit > -0.3:
				i = 1
			_px(img, x, y, pal[i])


func _n(x: int, y: int, seed: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791 + 12345)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


## Outline: every transparent pixel next to an opaque one (4-neighbour) inside rect gets `c`.
func _outline(img: Image, r: Rect2i, c: Color) -> void:
	var src := img.duplicate() as Image
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if r.has_point(q) and src.get_pixelv(q).a > 0.5:
					img.set_pixel(x, y, c)
					break


func _blit(dst: Image, src: Image, at: Vector2i) -> void:
	dst.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)


func _blend(dst: Image, src: Image, at: Vector2i) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)


func _flip_h(img: Image) -> Image:
	var o := img.duplicate() as Image
	o.flip_x()
	return o


# --- materials (seamless at 16 px) ---------------------------------------------------------------

func _mat(name: String, x: int, y: int, f := 0) -> Color:
	var mx := posmod(x, 16)
	var my := posmod(y, 16)
	var n := _n(mx, my, name.hash() & 0xFFFF)
	match name:
		"grass", "dgrass":
			var p := "g" if name == "grass" else "dg"
			var tufts := [Vector2i(3, 3), Vector2i(11, 6), Vector2i(6, 11), Vector2i(13, 13)]
			for t in tufts:
				if (mx == t.x and my == t.y) or (mx == t.x + 2 and my == t.y):
					return P[p + "3"]
				if mx == t.x + 1 and my == t.y + 1:
					return P[p + "2"]
				if (mx == t.x or mx == t.x + 2) and my == t.y + 1:
					return P[p + "0"]
			if n < 0.12:
				return P[p + "0"]
			if n > 0.85:
				return P[p + "2"]
			return P[p + "1"]
		"dirt":
			for t in [Vector2i(4, 4), Vector2i(12, 10), Vector2i(7, 13)]:
				if mx == t.x and my == t.y:
					return P.d3
				if mx == t.x + 1 and my == t.y + 1:
					return P.d1
			if n < 0.15:
				return P.d1
			if n > 0.9:
				return P.d3
			return P.d2
		"sand":
			if n < 0.08:
				return P.s0
			if n > 0.88:
				return P.s2
			return P.s1
		"stone":
			var off := 4 if (my / 8) % 2 == 1 else 0
			var lx := posmod(mx + off, 8)
			var ly := my % 8
			if lx == 7 or ly == 7:
				return P.st1
			if lx == 0 or ly == 0:
				return P.st3
			return P.st2 if n > 0.12 else P.st1
		"brick":
			var off2 := 4 if (my / 4) % 2 == 1 else 0
			var bx := posmod(mx + off2, 8)
			var by := my % 4
			if by == 3 or bx == 7:
				return P.br0
			if by == 0:
				return P.br3
			return P.br2 if n > 0.3 else P.br1
		"wood":
			var py := my % 4
			var seam := 4 if (my / 4) % 2 == 0 else 12
			if py == 3 or mx == seam:
				return P.w0
			if py == 0:
				return P.w3
			return P.w1 if n < 0.25 else P.w2
		"cobble":
			var cx := posmod(mx + (3 if (my / 5) % 2 else 0), 6)
			var cy := my % 5
			if cx == 5 or cy == 4:
				return P.st0
			if cx == 0 and cy == 0:
				return P.st1
			if cy == 0 or cx == 0:
				return P.st3
			return P.st2
		"carpet":
			var dx := absi(mx - 8)
			var dy := absi(my - 8)
			if dx + dy == 6:
				return P.gold
			if dx + dy == 2:
				return P.cp2
			return P.cp1 if n > 0.1 else P.cp0
		"snow":
			if n > 0.93:
				return P.sn0
			if n < 0.3:
				return P.sn1
			return P.sn2
		"farm":
			var fy := my % 4
			if fy == 0 and posmod(mx + (my / 4) * 2, 5) == 2:
				return P.g2
			if fy == 0:
				return P.d2
			if fy == 1:
				return P.d1
			return P.d0 if n < 0.7 else P.d1
		"hedge":
			var hx := posmod(mx + ((my / 4) % 2) * 2, 4)
			var hy := my % 4
			if hx + hy <= 1:
				return P.g2
			if hx + hy >= 5:
				return P.dg0
			return P.g0 if n < 0.3 else P.dg2
		"void":
			return P.void2 if n > 0.9 else P.void
		"water", "deep":
			var base := "wa" if name == "water" else "dp"
			var wy := my % 8
			var wx := posmod(mx + f * 2 + (my / 8) * 6, 16)
			if wy == 2 and wx >= 2 and wx <= 5:
				return P.wa3 if name == "water" else P.wa1
			if wy == 3 and (wx == 1 or wx == 6):
				return P[base + "2"] if name == "water" else P.dp2
			if n < 0.1:
				return P[base + "0"]
			return P[base + "1"] if name == "water" else P.dp1
		"rock":
			var rx := posmod(mx + (my / 5) * 3, 7)
			if rx == 0:
				return P.d0
			return P.d1 if n < 0.4 else P.st1
	return Color.MAGENTA


func _darker(c: Color, k := 0.35) -> Color:
	return c.darkened(k)


# --- quarter-tile shapes (shared by generator and decoder conventions) ---------------------------

const OUTER := 1
const VERT := 2
const HORZ := 3
const INNER := 4
const FILL := 0


## Signed distance (px) of a pixel to the patch border inside a quadrant of a given kind.
## u = distance from the cell's outer vertical edge, v = from the outer horizontal edge.
func _shape_d(kind: int, u: float, v: float, b: float, r: float) -> float:
	match kind:
		FILL:
			return 99.0
		VERT:
			return u - b
		HORZ:
			return v - b
		OUTER:
			var cx := u - b
			var cy := v - b
			if cx < r and cy < r:
				return r - Vector2(r - cx, r - cy).length()
			return minf(cx, cy)
		INNER:
			return maxf(u - b, v - b)
	return 99.0


## Draws a 16x16 tile where quadrant q has kind kinds[q].
## inside/outside: material names; style: {b, r, edge, rim, bank}
func _shape_tile(img: Image, at: Vector2i, kinds: Array, inside: String, outside: String, style: Dictionary, f := 0) -> void:
	var b: float = style.get("b", 2.0)
	var r: float = style.get("r", 3.0)
	for ly in 16:
		for lx in 16:
			var qx := lx / 8
			var qy := ly / 8
			var kind: int = kinds[qy * 2 + qx]
			var u := (lx if qx == 0 else 15 - lx) + 0.5
			var v := (ly if qy == 0 else 15 - ly) + 0.5
			var d := _shape_d(kind, u, v, b, r)
			var X := at.x + lx
			var Y := at.y + ly
			var c: Color
			if outside == inside:
				d = 99.0
			if d < 0.0:
				if outside == "":
					c = Color(0, 0, 0, 0)
				else:
					c = _mat(outside, X, Y, f)
					if d >= -1.0 and style.has("bank"):
						c = style.bank
			elif d < 1.0:
				c = style.edge if style.has("edge") else _darker(_mat(inside, X, Y, f))
			elif d < 2.0 and style.has("rim"):
				c = style.rim
			else:
				c = _mat(inside, X, Y, f)
			img.set_pixel(X, Y, c)


## Terrain autotile block (48x64) in the XP-style 3x4 layout.
func _terrain_block(img: Image, origin: Vector2i, inside: String, outside: String, style: Dictionary) -> void:
	for ty in 4:
		for tx in 3:
			var kinds := []
			for q in 4:
				var qx := q % 2
				var qy := q / 2
				var kind := FILL
				if ty == 0:
					kind = [OUTER, FILL, INNER][tx]
				else:
					var h := (tx != 0) if qx == 0 else (tx != 2)
					var vv := (ty != 1) if qy == 0 else (ty != 3)
					if h and vv:
						kind = FILL
					elif vv:
						kind = VERT
					elif h:
						kind = HORZ
					else:
						kind = OUTER
				kinds.append(kind)
			_shape_tile(img, origin + Vector2i(tx * T, ty * T), kinds, inside, outside, style)


## Water block: column = frame; rows = OUTER, VERT, HORZ, INNER (all four quadrants alike).
func _water_block(img: Image, origin: Vector2i, inside: String, outside: String, style: Dictionary) -> void:
	var rows := [OUTER, VERT, HORZ, INNER]
	for f in 3:
		var st := style.duplicate()
		st.b = 3.0 if f != 1 else 2.6
		for ry in 4:
			_shape_tile(img, origin + Vector2i(f * T, ry * T), [rows[ry], rows[ry], rows[ry], rows[ry]], inside, outside, st, f)


# --- ChipSet -------------------------------------------------------------------------------------

func _chipset() -> Image:
	var img := _img(480, 256)
	var shore_a := {"b": 3.0, "r": 4.0, "edge": P.foam, "rim": P.wa2, "bank": P.g0}
	var shore_b := {"b": 3.0, "r": 2.0, "edge": P.st3, "rim": P.wa0, "bank": P.st0}
	_water_block(img, Vector2i(0, 0), "water", "grass", shore_a)
	_water_block(img, Vector2i(48, 0), "water", "cobble", shore_b)
	# Block C, as in the RPG Maker RTP: row 0 shallow fill, rows 1..2 deep/shallow transition art
	# (reserved), row 3 deep fill. The tiles are drawn at their former rows (2, 0, 1) and then
	# moved, so the pixels match the starter sheet made before the rows were corrected.
	for f in 3:
		_shape_tile(img, Vector2i(f * T, 64), [OUTER, OUTER, OUTER, OUTER], "deep", "water", {"b": 3.0, "r": 4.0, "edge": P.wa1}, f)
		_shape_tile(img, Vector2i(f * T, 80), [VERT, VERT, HORZ, HORZ], "deep", "water", {"b": 3.0, "r": 4.0, "edge": P.wa1}, f)
		_shape_tile(img, Vector2i(f * T, 96), [FILL, FILL, FILL, FILL], "water", "", {}, f)
		_shape_tile(img, Vector2i(f * T, 112), [FILL, FILL, FILL, FILL], "deep", "", {}, f)
	var c_rows := img.get_region(Rect2i(0, 64, 48, 48))
	img.blit_rect(c_rows, Rect2i(0, 32, 48, 16), Vector2i(0, 64))
	img.blit_rect(c_rows, Rect2i(0, 0, 48, 32), Vector2i(0, 80))
	_animated_tiles(img)
	# Terrain autotiles 0..11.
	var terrains := [
		["grass", "grass", {}],  # seamless base ground
		["dirt", "grass", {"b": 2.0, "r": 3.0, "edge": P.d1, "bank": P.g0}],
		["sand", "grass", {"b": 2.0, "r": 3.0, "edge": P.s0, "bank": P.g0}],
		["stone", "void", {"b": 1.0, "r": 1.0, "edge": P.st0}],
		["brick", "void", {"b": 1.0, "r": 1.0, "edge": P.ink, "rim": P.br3}],
		["wood", "void", {"b": 1.0, "r": 1.0, "edge": P.w0}],
		["dgrass", "grass", {"b": 2.0, "r": 4.0, "edge": P.dg0}],
		["cobble", "grass", {"b": 2.0, "r": 3.0, "edge": P.st0, "bank": P.g0}],
		["carpet", "wood", {"b": 2.0, "r": 1.0, "edge": P.gold0, "rim": P.gold}],
		["snow", "grass", {"b": 2.0, "r": 4.0, "edge": P.sn0, "bank": P.g0}],
		["farm", "grass", {"b": 2.0, "r": 2.0, "edge": P.d0, "bank": P.g0}],
		["hedge", "grass", {"b": 1.0, "r": 4.0, "edge": P.ink, "rim": P.g1, "bank": P.g0}],
	]
	for i in 12:
		var t: Array = terrains[i]
		_terrain_block(img, RPGChipset2k.terrain_origin(i), t[0], t[1], t[2])
	_lower_tiles(img)
	_upper_tiles(img)
	return img


func _tile(img: Image, rect: Rect2i, mat: String) -> void:
	for y in rect.size.y:
		for x in rect.size.x:
			img.set_pixel(rect.position.x + x, rect.position.y + y, _mat(mat, x, y))


func _animated_tiles(img: Image) -> void:
	for f in 4:
		# anim_0 waterfall
		var o := RPGChipset2k.anim_frame_rect(0, f).position
		for y in 16:
			for x in 16:
				var s := posmod(y - f * 4 + (x % 3) * 5, 16)
				var c: Color = P.wa1
				if x % 4 == 0:
					c = P.wa0
				elif s < 3:
					c = P.wa3
				elif s < 6:
					c = P.wa2
				if y >= 13 and _n(x, y + f, 7) > 0.4:
					c = P.foam
				img.set_pixel(o.x + x, o.y + y, c)
		# anim_1 lava
		o = RPGChipset2k.anim_frame_rect(1, f).position
		for y in 16:
			for x in 16:
				var v := sin((x + f * 2) * 0.8) + cos((y - f) * 0.7) + _n(x, y, 3) * 0.6
				var c2: Color = P.lava1
				if v > 1.3:
					c2 = P.lava3
				elif v > 0.6:
					c2 = P.lava2
				elif v < -0.9:
					c2 = P.lava0
				img.set_pixel(o.x + x, o.y + y, c2)
		# anim_2 campfire on dirt
		o = RPGChipset2k.anim_frame_rect(2, f).position
		_tile(img, Rect2i(o, Vector2i(16, 16)), "dirt")
		var tmp := _img(16, 16)
		_rect(tmp, 3, 12, 10, 2, P.w1)
		_rect(tmp, 5, 11, 6, 1, P.w2)
		var flick: int = [0, 1, 0, -1][f]
		_disc(tmp, 8 + flick * 0.5, 9, 4, 4, P.lava1)
		_disc(tmp, 8 - flick * 0.5, 8 - absi(flick), 2.6, 4.0, P.lava2)
		_disc(tmp, 8, 9, 1.4, 2.0, P.lava3)
		_px(tmp, 8 + flick, 2 + f % 2, P.lava2)
		_outline(tmp, Rect2i(0, 0, 16, 16), P.ink)
		img.blend_rect(tmp, Rect2i(0, 0, 16, 16), o)


func _lower_tiles(img: Image) -> void:
	var L := func(i: int) -> Rect2i: return RPGChipset2k.lower_rect(i)
	var t := _img(16, 16)
	# 0 grass, 1 red flowers, 2 yellow flowers, 3 tall grass, 4 grass + stones, 5 dirt
	_tile(img, L.call(0), "grass")
	for i in [1, 2]:
		_tile(img, L.call(i), "grass")
		var petal: Color = P.red if i == 1 else P.yellow
		var centre: Color = P.yellow if i == 1 else P.orange
		for p in [Vector2i(4, 4), Vector2i(11, 7), Vector2i(5, 12), Vector2i(12, 13)]:
			var o: Vector2i = L.call(i).position + p
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				_px(img, o.x + d.x, o.y + d.y, petal)
			_px(img, o.x, o.y, centre)
			_px(img, o.x, o.y + 2, P.g0)
	_tile(img, L.call(3), "grass")
	var o3: Vector2i = L.call(3).position
	for x in range(0, 16, 2):
		var hgt := 6 + int(_n(x, 0, 9) * 5)
		_vline(img, o3.x + x, o3.y + 15 - hgt, o3.y + 15, P.g0)
		_vline(img, o3.x + x + 1, o3.y + 16 - hgt, o3.y + 15, P.g2)
		_px(img, o3.x + x + 1, o3.y + 15 - hgt, P.g3)
	_tile(img, L.call(4), "grass")
	t = _img(16, 16)
	_shaded(t, 5, 6, 2.5, 2.0, [P.st0, P.st1, P.st2, P.st3], 1)
	_shaded(t, 11, 11, 3.0, 2.2, [P.st0, P.st1, P.st2, P.st3], 2)
	_outline(t, Rect2i(0, 0, 16, 16), P.ink)
	img.blend_rect(t, Rect2i(0, 0, 16, 16), L.call(4).position)
	_tile(img, L.call(5), "dirt")
	# 6 stone stairs, 7 wooden stairs
	for i in [6, 7]:
		var o: Vector2i = L.call(i).position
		var top: Color = P.st3 if i == 6 else P.w3
		var front: Color = P.st1 if i == 6 else P.w1
		var mid: Color = P.st2 if i == 6 else P.w2
		for s in 4:
			_rect(img, o.x, o.y + s * 4, 16, 1, top)
			_rect(img, o.x, o.y + s * 4 + 1, 16, 2, mid)
			_rect(img, o.x, o.y + s * 4 + 3, 16, 1, front.darkened(0.3))
		_vline(img, o.x, o.y, o.y + 15, P.ink)
		_vline(img, o.x + 15, o.y, o.y + 15, P.ink)
	# 8 bridge horizontal (planks run vertically), 9 bridge vertical
	var o8: Vector2i = L.call(8).position
	for y in 16:
		for x in 16:
			var c: Color = P.w2 if x % 4 != 3 else P.w0
			if (x % 4 == 0):
				c = P.w3
			if y <= 1 or y >= 14:
				c = P.w1 if (y == 1 or y == 14) else P.w0
			img.set_pixel(o8.x + x, o8.y + y, c)
	var o9: Vector2i = L.call(9).position
	for y in 16:
		for x in 16:
			img.set_pixel(o9.x + x, o9.y + y, img.get_pixel(o8.x + y, o8.y + x))
	# 10 doormat on wood, 11 wood floor
	_tile(img, L.call(10), "wood")
	var o10: Vector2i = L.call(10).position
	_rect(img, o10.x + 2, o10.y + 4, 12, 8, P.cp1)
	_rect(img, o10.x + 3, o10.y + 5, 10, 6, P.cp2)
	_hline(img, o10.x + 2, o10.x + 13, o10.y + 11, P.cp0)
	for x in range(3, 13, 2):
		_px(img, o10.x + x, o10.y + 7, P.gold)
	_tile(img, L.call(11), "wood")
	# 12 interior wall top, 13 wall face, 14 wall face + window, 15 wall face + shelf
	var o12: Vector2i = L.call(12).position
	_rect(img, o12.x, o12.y, 16, 16, Color("3c3450"))
	for x in range(0, 16, 4):
		_px(img, o12.x + x + (2 if (x / 4) % 2 else 0), o12.y + 6, Color("4c4466"))
	_hline(img, o12.x, o12.x + 15, o12.y + 15, Color("5c5478"))
	for i in [13, 14, 15]:
		_wall_face(img, L.call(i).position)
	var o14: Vector2i = L.call(14).position
	_rect(img, o14.x + 3, o14.y + 2, 10, 8, P.w0)
	_rect(img, o14.x + 4, o14.y + 3, 8, 6, P.win1)
	_rect(img, o14.x + 4, o14.y + 3, 3, 2, P.win2)
	_vline(img, o14.x + 7, o14.y + 3, o14.y + 8, P.w1)
	_hline(img, o14.x + 4, o14.x + 11, o14.y + 6, P.w1)
	var o15: Vector2i = L.call(15).position
	_rect(img, o15.x + 1, o15.y + 1, 14, 11, P.w0)
	for s in 2:
		var yy := o15.y + 2 + s * 5
		var cols := [P.red, P.win0, P.g2, P.gold, P.purple, P.d3]
		for b in 6:
			_rect(img, o15.x + 2 + b * 2, yy + (b % 2), 2, 4 - (b % 2), cols[(b + s * 3) % cols.size()])
		_hline(img, o15.x + 1, o15.x + 14, yy + 4, P.w2)
	# 16 stone floor, 17 cracked stone floor
	_tile(img, L.call(16), "stone")
	_tile(img, L.call(17), "stone")
	var o17: Vector2i = L.call(17).position
	for p in [Vector2i(3, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(5, 5), Vector2i(10, 9), Vector2i(11, 10), Vector2i(11, 11), Vector2i(12, 12)]:
		_px(img, o17.x + p.x, o17.y + p.y, P.st0)
	# 18 cliff face, 19 dungeon stone wall face
	_tile(img, L.call(18), "rock")
	var o18: Vector2i = L.call(18).position
	_hline(img, o18.x, o18.x + 15, o18.y, P.g2)
	_hline(img, o18.x, o18.x + 15, o18.y + 1, P.g0)
	var o19: Vector2i = L.call(19).position
	for y in 16:
		for x in 16:
			var off := 4 if (y / 5) % 2 else 0
			var c: Color = P.st2
			if y % 5 == 4 or posmod(x + off, 8) == 7:
				c = P.st0
			elif y % 5 == 0:
				c = P.st3
			img.set_pixel(o19.x + x, o19.y + y, c)
	# 20 sand + shell, 21 snow, 22 farmland crops, 23 poison swamp (damage floor)
	_tile(img, L.call(20), "sand")
	var o20: Vector2i = L.call(20).position
	t = _img(16, 16)
	_disc(t, 9, 9, 3, 2.5, P.pink)
	_vline(t, 8, 7, 11, P.r3)
	_vline(t, 10, 7, 11, P.r3)
	_outline(t, Rect2i(0, 0, 16, 16), P.d1)
	img.blend_rect(t, Rect2i(0, 0, 16, 16), o20)
	_tile(img, L.call(21), "snow")
	_tile(img, L.call(22), "farm")
	var o22: Vector2i = L.call(22).position
	for p in [Vector2i(3, 1), Vector2i(11, 1), Vector2i(7, 5), Vector2i(3, 9), Vector2i(11, 9), Vector2i(7, 13)]:
		_px(img, o22.x + p.x, o22.y + p.y, P.g2)
		_px(img, o22.x + p.x - 1, o22.y + p.y - 1, P.g3)
		_px(img, o22.x + p.x + 1, o22.y + p.y - 1, P.g3)
	var o23: Vector2i = L.call(23).position
	for y in 16:
		for x in 16:
			var n := _n(x, y, 23)
			var c: Color = P.sw1
			if n < 0.2:
				c = P.sw0
			elif n > 0.9:
				c = P.sw3
			elif n > 0.75:
				c = P.sw2
			img.set_pixel(o23.x + x, o23.y + y, c)
	for p in [Vector2i(4, 5), Vector2i(11, 11)]:
		_disc(img, o23.x + p.x, o23.y + p.y, 1.6, 1.6, P.purple2)
		_px(img, o23.x + p.x - 1, o23.y + p.y - 1, P.white)


func _wall_face(img: Image, o: Vector2i) -> void:
	for y in 16:
		for x in 16:
			var c: Color = P.pl1
			if y >= 11:
				c = P.w2 if y != 11 else P.w3
				if y == 15:
					c = P.w0
				elif x % 4 == 3 and y > 11:
					c = P.w1
			elif _n(x, y, 13) < 0.1:
				c = P.pl0
			elif y == 0:
				c = P.pl0
			img.set_pixel(o.x + x, o.y + y, c)


func _upper_tiles(img: Image) -> void:
	var U := func(i: int) -> Vector2i: return RPGChipset2k.upper_rect(i).position
	# 0 empty: left transparent.
	# 1 + 7: round tree (16x32)
	var tree := _img(16, 32)
	_disc(tree, 8, 29.5, 6, 2.2, Color(0, 0, 0, 0.3))
	_rect(tree, 6, 17, 4, 12, P.w1)
	_vline(tree, 6, 17, 28, P.w0)
	_vline(tree, 9, 18, 28, P.w2)
	_px(tree, 5, 28, P.w1)
	_px(tree, 10, 28, P.w1)
	var leaves := [P.g0, P.g1, P.g2, P.g3]
	_shaded(tree, 8, 12, 7.4, 7.0, leaves, 11)
	_shaded(tree, 4.5, 16, 3.5, 3.0, leaves, 12)
	_shaded(tree, 11.5, 16.5, 3.5, 3.0, leaves, 13)
	_shaded(tree, 8, 5.5, 4.5, 3.5, leaves, 14)
	_outline_opaque(tree, P.ink)
	_blit(img, tree.get_region(Rect2i(0, 0, 16, 16)), U.call(1))
	_blit(img, tree.get_region(Rect2i(0, 16, 16, 16)), U.call(7))
	# 2 + 8: pine tree
	var pine := _img(16, 32)
	_disc(pine, 8, 29.5, 5, 2.0, Color(0, 0, 0, 0.3))
	_rect(pine, 7, 22, 3, 7, P.w1)
	_vline(pine, 7, 22, 28, P.w0)
	for tier in 4:
		var top := 2 + tier * 5
		var hgt := 8
		for yy in hgt:
			var half := int(1 + (yy + tier) * 0.75)
			for xx in range(8 - half, 8 + half):
				var c: Color = P.dg1
				if xx < 8 - half + 2:
					c = P.dg3
				elif xx >= 8 + half - 2:
					c = P.dg0
				elif _n(xx, yy + top, 5) > 0.7:
					c = P.dg2
				_px(pine, xx, top + yy, c)
	_outline_opaque(pine, P.ink)
	_blit(img, pine.get_region(Rect2i(0, 0, 16, 16)), U.call(2))
	_blit(img, pine.get_region(Rect2i(0, 16, 16, 16)), U.call(8))
	# 3,4,5 roof top row; 9,10,11 roof bottom row
	for col in 3:
		for row in 2:
			var o: Vector2i = U.call([3, 4, 5][col] + row * 6)
			for y in 16:
				for x in 16:
					var gy := y + row * 16
					var sx := posmod(x + (2 if (gy / 4) % 2 else 0), 4)
					var c: Color = P.r2
					if gy % 4 == 3:
						c = P.r0
					elif sx == 3:
						c = P.r1
					elif gy % 4 == 0 and sx < 2:
						c = P.r3
					if row == 0 and y < 2:
						c = P.r0 if y == 0 else P.r1
					if row == 1 and y >= 13:
						c = P.w0 if y == 13 else (P.w1 if y == 14 else Color(0, 0, 0, 0.45))
					if col == 0 and x == 0 or col == 2 and x == 15:
						c = P.ink
					img.set_pixel(o.x + x, o.y + y, c)
	# 6 bush
	var bush := _img(16, 16)
	_disc(bush, 8, 13.5, 6, 2, Color(0, 0, 0, 0.3))
	_shaded(bush, 8, 9, 6.5, 5.5, leaves, 21)
	_outline_opaque(bush, P.ink)
	_blit(img, bush, U.call(6))
	# 12 fence horizontal, 13 fence vertical
	var fh := _img(16, 16)
	_rect(fh, 0, 6, 16, 2, P.w2)
	_rect(fh, 0, 10, 16, 2, P.w2)
	_hline(fh, 0, 15, 8, P.w0)
	_hline(fh, 0, 15, 12, P.w0)
	for px in [2, 12]:
		_rect(fh, px, 3, 2, 11, P.w3)
		_vline(fh, px + 1, 4, 13, P.w1)
	_outline(fh, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, fh, U.call(12))
	var fv := _img(16, 16)
	_rect(fv, 7, 0, 2, 16, P.w2)
	_vline(fv, 8, 0, 15, P.w1)
	_rect(fv, 6, 4, 4, 3, P.w3)
	_rect(fv, 6, 12, 4, 3, P.w3)
	_outline(fv, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, fv, U.call(13))
	# 14 signpost
	var sg := _img(16, 16)
	_rect(sg, 7, 8, 2, 8, P.w1)
	_rect(sg, 2, 2, 12, 7, P.w3)
	_hline(sg, 2, 13, 8, P.w1)
	_hline(sg, 4, 11, 4, P.w0)
	_hline(sg, 4, 9, 6, P.w0)
	_outline(sg, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, sg, U.call(14))
	# 15,16,17 house wall left/mid/right; 21 window; 22 door frame; 23 shop sign; 35 inn sign
	for i in [15, 16, 17, 21, 22, 23, 35]:
		_house_wall(img, U.call(i), i == 15, i == 17)
	var o21: Vector2i = U.call(21)
	_rect(img, o21.x + 3, o21.y + 3, 10, 8, P.w0)
	_rect(img, o21.x + 4, o21.y + 4, 8, 6, P.win1)
	_rect(img, o21.x + 4, o21.y + 4, 3, 2, P.win2)
	_vline(img, o21.x + 7, o21.y + 4, o21.y + 9, P.w1)
	_hline(img, o21.x + 2, o21.x + 13, o21.y + 11, P.w2)
	var o22: Vector2i = U.call(22)
	_rect(img, o22.x + 2, o22.y + 1, 12, 15, P.w1)
	_rect(img, o22.x + 3, o22.y + 2, 10, 14, P.black)
	_hline(img, o22.x + 3, o22.x + 12, o22.y + 2, Color("2c2030"))
	for i in [23, 35]:
		var o: Vector2i = U.call(i)
		_rect(img, o.x + 3, o.y + 2, 10, 9, P.w0)
		_rect(img, o.x + 4, o.y + 3, 8, 7, P.w3)
		if i == 23:
			_disc(img, o.x + 8, o.y + 7, 2.4, 2.4, P.red)
			_rect(img, o.x + 7, o.y + 3, 2, 2, P.grey)
			_px(img, o.x + 7, o.y + 6, P.white)
		else:
			_rect(img, o.x + 5, o.y + 6, 6, 2, P.white)
			_rect(img, o.x + 5, o.y + 5, 2, 1, P.white)
			_rect(img, o.x + 7, o.y + 5, 4, 1, P.win0)
			_vline(img, o.x + 5, o.y + 4, o.y + 8, P.w0)
			_vline(img, o.x + 10, o.y + 6, o.y + 8, P.w0)
	# 18 barrel
	var br := _img(16, 16)
	_disc(br, 8, 14.5, 5.5, 1.5, Color(0, 0, 0, 0.3))
	for y in range(3, 15):
		var w := 5 if y in [3, 14] else 6
		for x in range(8 - w, 8 + w):
			var c: Color = P.w2
			if x < 8 - w + 2:
				c = P.w3
			elif x > 8 + w - 3:
				c = P.w1
			if x % 3 == 0:
				c = c.darkened(0.15)
			if y in [5, 12]:
				c = P.grey if x < 8 + w - 2 else P.st1
			_px(br, x, y, c)
	_rect(br, 4, 3, 8, 1, P.w1)
	_outline_opaque(br, P.ink)
	_blit(img, br, U.call(18))
	# 19 crate
	var cr := _img(16, 16)
	_rect(cr, 2, 3, 12, 12, P.w2)
	_rect(cr, 2, 3, 12, 2, P.w3)
	for d in 10:
		_px(cr, 3 + d, 5 + d, P.w1)
		_px(cr, 12 - d, 5 + d, P.w1)
	_rect(cr, 2, 3, 1, 12, P.w1)
	_rect(cr, 13, 3, 1, 12, P.w0)
	_outline_opaque(cr, P.ink)
	_blit(img, cr, U.call(19))
	# 20 rock
	var rk := _img(16, 16)
	_disc(rk, 8, 13.5, 6, 1.8, Color(0, 0, 0, 0.3))
	_shaded(rk, 8, 10, 6, 4.5, [P.st0, P.st1, P.st2, P.st3], 31)
	_outline_opaque(rk, P.ink)
	_blit(img, rk, U.call(20))
	# 24,25,26 shop counter left/mid/right
	for k in 3:
		var o: Vector2i = U.call(24 + k)
		for y in range(3, 16):
			for x in 16:
				var c: Color
				if y <= 7:
					c = P.w3 if y > 3 else P.pl2
					if y == 7:
						c = P.w1
				else:
					c = P.w1 if (x % 8 != 0) else P.w0
					if y == 15:
						c = P.w0
				if (k == 0 and x == 0) or (k == 2 and x == 15):
					c = P.ink
				img.set_pixel(o.x + x, o.y + y, c)
		if k == 0:
			_hline(img, o.x, o.x + 15, o.y + 2, Color(0, 0, 0, 0))
		img.set_pixel(o.x + (0 if k == 0 else 15), o.y + 3, P.ink)
		_hline(img, o.x + (1 if k == 0 else 0), o.x + (14 if k == 2 else 15), o.y + 2, P.ink)
	# 27 + 33 bed (16x32)
	var bed := _img(16, 32)
	_rect(bed, 1, 1, 14, 5, P.w1)
	_rect(bed, 2, 2, 12, 2, P.w3)
	_rect(bed, 2, 6, 12, 25, P.w0)
	_rect(bed, 3, 6, 10, 5, P.white)
	_hline(bed, 3, 12, 10, P.grey)
	_rect(bed, 2, 11, 12, 17, P.win0)
	_rect(bed, 3, 12, 10, 15, P.wa2)
	_hline(bed, 2, 13, 11, P.win1)
	_rect(bed, 1, 27, 14, 4, P.w1)
	_hline(bed, 1, 14, 27, P.w3)
	_outline_opaque(bed, P.ink)
	_blit(img, bed.get_region(Rect2i(0, 0, 16, 16)), U.call(27))
	_blit(img, bed.get_region(Rect2i(0, 16, 16, 16)), U.call(33))
	# 28 table
	var tb := _img(16, 16)
	_rect(tb, 1, 3, 14, 7, P.w3)
	_hline(tb, 1, 14, 9, P.w1)
	_rect(tb, 2, 10, 2, 5, P.w1)
	_rect(tb, 12, 10, 2, 5, P.w1)
	_hline(tb, 2, 13, 4, P.pl2)
	_outline(tb, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, tb, U.call(28))
	# 29 chair
	var ch := _img(16, 16)
	_rect(ch, 4, 1, 8, 7, P.w2)
	_rect(ch, 5, 2, 6, 1, P.w3)
	_rect(ch, 3, 8, 10, 3, P.w3)
	_rect(ch, 4, 11, 2, 4, P.w1)
	_rect(ch, 10, 11, 2, 4, P.w1)
	_outline(ch, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, ch, U.call(29))
	# 30 bookshelf
	var bs := _img(16, 16)
	_rect(bs, 1, 0, 14, 16, P.w0)
	var bcols := [P.red, P.win0, P.g2, P.gold, P.purple, P.d3, P.wa2]
	for s in 3:
		for b in 6:
			var hh := 3 + (b + s) % 2
			_rect(bs, 2 + b * 2, 1 + s * 5 + (4 - hh), 2, hh, bcols[(b * 3 + s) % bcols.size()])
		_hline(bs, 1, 14, 5 + s * 5, P.w2)
	_outline(bs, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, bs, U.call(30))
	# 31 potted plant
	var pp := _img(16, 16)
	_rect(pp, 5, 10, 6, 5, P.orange)
	_rect(pp, 4, 10, 8, 1, P.d3)
	_vline(pp, 10, 11, 14, P.d1)
	_shaded(pp, 8, 6, 4.5, 4.5, leaves, 41)
	_outline_opaque(pp, P.ink)
	_blit(img, pp, U.call(31))
	# 32 lamp top (star) + 38 lamp post
	var lamp := _img(16, 32)
	_rect(lamp, 7, 12, 2, 18, P.st1)
	_vline(lamp, 7, 12, 29, P.st2)
	_rect(lamp, 5, 28, 6, 3, P.st1)
	_rect(lamp, 5, 4, 6, 7, P.yellow)
	_rect(lamp, 6, 5, 4, 5, P.lava3)
	_rect(lamp, 4, 3, 8, 1, P.st0)
	_rect(lamp, 5, 2, 6, 1, P.st1)
	_rect(lamp, 4, 11, 8, 1, P.st0)
	_outline_opaque(lamp, P.ink)
	_blit(img, lamp.get_region(Rect2i(0, 0, 16, 16)), U.call(32))
	_blit(img, lamp.get_region(Rect2i(0, 16, 16, 16)), U.call(38))
	# 34 dresser
	var dr := _img(16, 16)
	_rect(dr, 1, 2, 14, 13, P.w2)
	_hline(dr, 1, 14, 2, P.w3)
	for k in 3:
		_hline(dr, 2, 13, 5 + k * 3, P.w0)
		_px(dr, 8, 4 + k * 3, P.gold)
	_outline(dr, Rect2i(0, 0, 16, 16), P.ink)
	_blit(img, dr, U.call(34))
	# 36 haystack
	var hs := _img(16, 16)
	_shaded(hs, 8, 10, 7, 5.5, [P.s0, P.d3, P.s1, P.s2], 51)
	for x in range(3, 14, 3):
		_vline(hs, x, 7, 13, P.s0)
	_outline_opaque(hs, P.ink)
	_blit(img, hs, U.call(36))
	# 37 log pile
	var lg := _img(16, 16)
	for p in [Vector2(4.5, 12), Vector2(11.5, 12), Vector2(8, 7.5)]:
		_disc(lg, p.x, p.y, 3.4, 3.4, P.w1)
		_disc(lg, p.x, p.y, 2.2, 2.2, P.w3)
		_px(lg, int(p.x), int(p.y), P.w2)
	_outline_opaque(lg, P.ink)
	_blit(img, lg, U.call(37))


func _outline_opaque(img: Image, c: Color) -> void:
	_outline(img, Rect2i(Vector2i.ZERO, img.get_size()), c)


func _house_wall(img: Image, o: Vector2i, left: bool, right: bool) -> void:
	for y in 16:
		for x in 16:
			var c: Color = P.pl1
			if _n(x, y, 77) < 0.08:
				c = P.pl0
			if y <= 1:
				c = P.w1 if y == 1 else P.w0
			if y >= 13:
				c = P.st2 if y == 13 else P.st1
				if y == 15 or posmod(x + (y % 2) * 3, 6) == 0:
					c = P.st0
			if (left and x <= 1) or (right and x >= 14):
				c = P.w1 if (x == 1 or x == 14) else P.w0
			img.set_pixel(o.x + x, o.y + y, c)


# --- characters ------------------------------------------------------------------------------------

const PEOPLE := [
	{"name": "hero", "hair": "d1", "hair_style": "spiky", "top": "wa1", "bottom": "d0", "accent": "red", "shoes": "w0"},
	{"name": "mage", "hair": "purple2", "hair_style": "wizard", "top": "purple", "bottom": "purple", "accent": "gold", "shoes": "w0", "robe": true},
	{"name": "villager", "hair": "w1", "hair_style": "short", "top": "g1", "bottom": "d1", "accent": "w0", "shoes": "w0"},
	{"name": "shopkeeper", "hair": "black", "hair_style": "short", "top": "g0", "bottom": "w0", "accent": "white", "shoes": "w0", "apron": true, "mustache": true},
	{"name": "innkeeper", "hair": "orange", "hair_style": "long", "top": "cp1", "bottom": "cp0", "accent": "white", "shoes": "w0", "apron": true},
	{"name": "guard", "hair": "w1", "hair_style": "helmet", "top": "st2", "bottom": "st1", "accent": "red", "shoes": "st0", "spear": true},
	{"name": "old_man", "hair": "white", "hair_style": "bald", "top": "s0", "bottom": "w1", "accent": "w0", "shoes": "w0", "beard": true, "robe": true},
	{"name": "child", "hair": "yellow", "hair_style": "cap", "top": "orange", "bottom": "wa0", "accent": "red", "shoes": "w0", "child": true},
]
const ROW_ORDER := ["up", "right", "down", "left"]


func _col(k: String) -> Color:
	return P[k]


func _charset_people() -> Image:
	var sheet := _img(288, 256)
	for i in PEOPLE.size():
		var cx := (i % 4) * 72
		var cy := (i / 4) * 128
		for row in 4:
			for f in 3:
				var fr := _draw_person(PEOPLE[i], ROW_ORDER[row], f)
				_blit(sheet, fr, Vector2i(cx + f * 24, cy + row * 32))
	return sheet


func _draw_person(p: Dictionary, facing: String, f: int) -> Image:
	if facing == "right":
		return _flip_h(_draw_person(p, "left", f))
	var img := _img(24, 32)
	var child: bool = p.get("child", false)
	var body_h := 6 if child else 8
	var leg_h := 3 if child else 5
	var feet := 30
	var shoe_y := feet - 1
	var leg_y := shoe_y - leg_h
	var body_y := leg_y - body_h
	var head_y := body_y - 11
	var skin: Color = P.skin
	var hair := _col(p.hair)
	var top := _col(p.top)
	var top_dark := top.darkened(0.3)
	var bottom := _col(p.bottom)
	var shoes := _col(p.shoes)
	var accent := _col(p.accent)
	var robe: bool = p.get("robe", false)
	var side := facing == "left"
	var step: int = [1, 0, -1][f]  # frame 0 left foot forward, 2 right foot forward
	# shadow
	_disc(img, 12, feet + 0.5, 6, 1.5, Color(0, 0, 0, 0.25))
	# legs
	if not robe:
		if side:
			var front_x := 9 if f != 1 else 10
			var back_x := 13 if f != 1 else 12
			_rect(img, back_x, leg_y, 3, leg_h, bottom.darkened(0.25))
			_rect(img, back_x, shoe_y, 3, 2, shoes.darkened(0.2))
			_rect(img, front_x, leg_y, 3, leg_h, bottom)
			_rect(img, front_x - 1, shoe_y, 4, 2, shoes)
		else:
			var lift_l := 1 if step < 0 else 0
			var lift_r := 1 if step > 0 else 0
			_rect(img, 8, leg_y, 3, leg_h - lift_l, bottom)
			_rect(img, 8, shoe_y - lift_l, 3, 2, shoes)
			_rect(img, 13, leg_y, 3, leg_h - lift_r, bottom)
			_rect(img, 13, shoe_y - lift_r, 3, 2, shoes)
	else:
		var sway := 0 if f == 1 else step
		_rect(img, 7, body_y + 2, 10, feet - 1 - body_y - 2, top)
		_rect(img, 7 + (1 if sway > 0 else 0), shoe_y, 3, 2, shoes)
		_rect(img, 14 - (1 if sway < 0 else 0), shoe_y, 3, 2, shoes)
		_hline(img, 7, 16, feet - 2, top_dark)
		_rect(img, 7, body_y + 2, 10, feet - 1 - body_y - 2, top)
		_hline(img, 7, 16, feet - 2, top_dark)
	# torso
	if side:
		_rect(img, 8, body_y, 8, body_h, top)
		_vline(img, 15, body_y, body_y + body_h - 1, top_dark)
	else:
		_rect(img, 7, body_y, 10, body_h, top)
		_vline(img, 16, body_y, body_y + body_h - 1, top_dark)
		_hline(img, 7, 16, body_y + body_h - 1, top_dark)
	if p.get("apron", false) and facing != "up":
		if side:
			_rect(img, 8, body_y + 2, 3, body_h - 1, P.white)
		else:
			_rect(img, 9, body_y + 2, 6, body_h - 1 + (2 if not child else 0), P.white)
			_hline(img, 7, 16, body_y + 2, P.white)
	if not robe and not p.get("apron", false):
		_hline(img, 7 if not side else 8, 16 if not side else 15, body_y + body_h - 2, accent)
	if p.name == "hero" and facing != "up":
		_hline(img, 8 if not side else 9, 15, body_y, accent)
		if side:
			_rect(img, 15, body_y + 1, 2, 3, accent)
	if p.name == "hero" and facing == "up":
		_rect(img, 9, body_y, 6, body_h - 1, accent)
	# arms
	if side:
		var ax: int = [9, 11, 13][f]
		_rect(img, ax, body_y + 1, 3, body_h - 3, top_dark if facing == "left" else top)
		_rect(img, ax, body_y + body_h - 2, 3, 2, skin)
	else:
		var la := body_y + 1 + (1 if step > 0 else 0)
		var ra := body_y + 1 + (1 if step < 0 else 0)
		_rect(img, 5, la, 2, body_h - 3, top)
		_rect(img, 5, la + body_h - 3, 2, 2, skin)
		_rect(img, 17, ra, 2, body_h - 3, top_dark)
		_rect(img, 17, ra + body_h - 3, 2, 2, skin.darkened(0.1))
	# head
	_rect(img, 7, head_y, 10, 11, skin)
	_rect(img, 6, head_y + 1, 12, 9, skin)
	_vline(img, 17, head_y + 1, head_y + 9, P.skin2)
	_hline(img, 7, 16, head_y + 10, P.skin2)
	var style: String = p.hair_style
	# hair / headwear
	match style:
		"spiky", "short", "long", "cap":
			_rect(img, 6, head_y, 12, 4, hair)
			_rect(img, 7, head_y - 1, 10, 1, hair)
			if facing == "up":
				_rect(img, 6, head_y, 12, 10, hair)
			elif side:
				_rect(img, 11, head_y, 7, 8, hair)
				_rect(img, 6, head_y, 4, 3, hair)
			else:
				_rect(img, 6, head_y + 3, 2, 4, hair)
				_rect(img, 16, head_y + 3, 2, 4, hair)
			if style == "spiky":
				for sx in [7, 10, 13, 16]:
					_px(img, sx, head_y - 2, hair)
					_px(img, sx - 1, head_y - 1, hair)
				_px(img, 9, head_y - 3, hair)
				_px(img, 13, head_y - 3, hair)
			if style == "long":
				if facing == "up":
					_rect(img, 6, head_y, 12, 14, hair)
				elif side:
					_rect(img, 12, head_y, 6, 14, hair)
				else:
					_rect(img, 5, head_y + 2, 3, 12, hair)
					_rect(img, 16, head_y + 2, 3, 12, hair)
			if style == "cap":
				var capc: Color = P.red
				_rect(img, 6, head_y - 1, 12, 4, capc)
				_hline(img, 7, 16, head_y - 2, capc)
				if facing == "down":
					_hline(img, 6, 17, head_y + 3, capc.darkened(0.3))
				elif side:
					_hline(img, 3, 9, head_y + 3, capc.darkened(0.3))
		"wizard":
			var hat: Color = P.purple
			_rect(img, 6, head_y, 12, 4, hair)
			if facing == "up":
				_rect(img, 6, head_y, 12, 10, hair)
			elif side:
				_rect(img, 11, head_y, 7, 9, hair)
			for k in 7:
				var w := 1 + k
				_hline(img, 12 - w, 11 + w, head_y - 6 + k, hat if k % 3 != 2 else hat.lightened(0.15))
			_px(img, 13, head_y - 7, hat)
			_px(img, 14, head_y - 8, P.gold)
			_hline(img, 3, 20, head_y + 1, hat.darkened(0.3))
			_hline(img, 7, 16, head_y, P.gold)
		"helmet":
			var hm: Color = P.st2
			_rect(img, 6, head_y - 1, 12, 5, hm)
			_hline(img, 7, 16, head_y - 2, hm)
			_hline(img, 6, 17, head_y + 3, P.st1)
			_hline(img, 8, 11, head_y - 1, P.st3)
			if facing == "up":
				_rect(img, 6, head_y, 12, 10, hm)
				_hline(img, 6, 17, head_y + 9, P.st1)
			elif side:
				_rect(img, 12, head_y, 6, 9, hm)
			else:
				_vline(img, 11, head_y + 3, head_y + 6, P.st1)
				_px(img, 12, head_y - 3, P.red)
				_px(img, 11, head_y - 3, P.red)
		"bald":
			if facing == "up":
				_rect(img, 6, head_y + 3, 12, 6, hair)
			elif side:
				_rect(img, 13, head_y + 3, 5, 5, hair)
			else:
				_rect(img, 6, head_y + 3, 2, 5, hair)
				_rect(img, 16, head_y + 3, 2, 5, hair)
			_hline(img, 9, 14, head_y + 1, skin.lightened(0.2))
	# face
	var eye: Color = P.ink
	if facing == "down":
		_rect(img, 9, head_y + 5, 1, 2, eye)
		_rect(img, 14, head_y + 5, 1, 2, eye)
		_px(img, 8, head_y + 7, P.pink)
		_px(img, 15, head_y + 7, P.pink)
	elif side:
		_rect(img, 8, head_y + 5, 1, 2, eye)
		_px(img, 6, head_y + 7, P.pink)
	if p.get("beard", false) and facing != "up":
		if side:
			_rect(img, 6, head_y + 7, 5, 5, hair)
		else:
			_rect(img, 8, head_y + 7, 8, 5, hair)
			_hline(img, 9, 14, head_y + 12, hair)
	if p.get("mustache", false) and facing == "down":
		_hline(img, 10, 13, head_y + 8, hair)
	elif p.get("mustache", false) and side:
		_hline(img, 6, 8, head_y + 8, hair)
	if p.get("spear", false):
		var sx2 := 20 if not side else 4
		if facing == "up":
			sx2 = 4
		_vline(img, sx2, head_y - 6, feet - 1, P.w2)
		_rect(img, sx2 - 1, head_y - 9, 3, 3, P.st3)
		_px(img, sx2, head_y - 10, P.st3)
	_outline_opaque(img, P.ink)
	return img


func _charset_objects() -> Image:
	var sheet := _img(288, 256)
	for idx in 4:
		var cx := (idx % 4) * 72
		var cy := (idx / 4) * 128
		for row in 4:
			var stage: int = {"down": 0, "left": 1, "right": 2, "up": 3}[ROW_ORDER[row]]
			var fr: Image
			match idx:
				0: fr = _door(stage)
				1: fr = _chest(stage)
				2: fr = _sign()
				3: fr = _pot()
			for f in 3:
				_blit(sheet, fr, Vector2i(cx + f * 24, cy + row * 32))
	return sheet


## Vehicles sheet (2000/2003 CharSet layout): 0 boat, 1 ship, 2 airship. Rows follow ROW_ORDER;
## the three frames bob on the water or turn the airship's propeller.
func _charset_vehicles() -> Image:
	var sheet := _img(288, 256)
	for idx in 3:
		var cx := (idx % 4) * 72
		var cy := (idx / 4) * 128
		for row in 4:
			for f in 3:
				var fr := _vehicle(idx, ROW_ORDER[row], f)
				_blit(sheet, fr, Vector2i(cx + f * 24, cy + row * 32))
	return sheet


func _vehicle(kind: int, facing: String, f: int) -> Image:
	var img := _img(24, 32)
	var side := facing == "left" or facing == "right"
	var bob: int = [0, 1, 0][f]
	if kind == 2:
		# Airship: shadow on the ground, balloon and gondola above it.
		_disc(img, 12, 30, 8, 2, Color(0, 0, 0, 0.35))
		var by := 8 + bob
		if side:
			_shaded(img, 12, by, 11, 6, [P.r0, P.r1, P.r2, P.r3], 3)
			_hline(img, 2, 21, by, P.r0)
			_rect(img, 7, by + 7, 10, 4, P.w1)
			_hline(img, 7, 16, by + 7, P.w3)
			var px := 2 if facing == "right" else 20
			_vline(img, px, by + 6 + f, by + 10 - f, P.st3)
		else:
			_shaded(img, 12, by, 8, 8, [P.r0, P.r1, P.r2, P.r3], 3)
			_vline(img, 12, by - 7, by + 7, P.r0)
			_rect(img, 8, by + 8, 8, 4, P.w1)
			_hline(img, 8, 15, by + 8, P.w3)
			_hline(img, 12 - (2 if f != 1 else 4), 12 + (2 if f != 1 else 4), by + 13, P.st3)
		_outline_opaque(img, P.ink)
		return img
	# Boat and ship: hull on the water with a little wake.
	var big := kind == 1
	var wy := 26 + bob
	_hline(img, 2, 21, wy + 4, P.foam)
	if side:
		var x0 := 2 if big else 4
		var x1 := 21 if big else 19
		_rect(img, x0, wy - 3, x1 - x0 + 1, 5, P.w1)
		_hline(img, x0, x1, wy - 3, P.w3)
		_hline(img, x0 + 1, x1 - 1, wy + 1, P.w0)
		var bow := x1 if facing == "right" else x0
		_px(img, bow, wy - 4, P.w2)
		if big:
			_vline(img, 12, wy - 22, wy - 4, P.w0)
			_rect(img, 6, wy - 20, 13, 11, P.pl2)
			_hline(img, 6, 18, wy - 20, P.pl1)
			_rect(img, 11, wy - 25, 3, 3, P.red)
		else:
			_rect(img, 10, wy - 6, 4, 3, P.w2)
	else:
		var hw := 6 if big else 4
		_rect(img, 12 - hw, wy - 10, hw * 2, 13, P.w1)
		_rect(img, 12 - hw + 1, wy - 9, hw * 2 - 2, 11, P.w2)
		var tip := wy - 12 if facing == "up" else wy + 3
		_hline(img, 12 - hw + 2, 12 + hw - 3, tip, P.w1)
		if big:
			_vline(img, 12, wy - 24, wy - 4, P.w0)
			_rect(img, 5, wy - 21, 14, 9, P.pl2)
			_hline(img, 5, 18, wy - 21, P.pl1)
			_rect(img, 11, wy - 27, 3, 3, P.red)
		else:
			_hline(img, 12 - hw + 1, 12 + hw - 2, wy - 4, P.w0)
	_outline_opaque(img, P.ink)
	return img


## Door sprite (24x32): fills the door-frame opening (tile x 3..12, y 2..15 -> sprite x 7..16,
## y 18..31). stage 0 closed .. 3 open.
func _door(stage: int) -> Image:
	var img := _img(24, 32)
	var w: int = [10, 7, 4, 2][stage]
	var x0 := 7
	_rect(img, x0, 18, 10, 14, P.black)
	for y in range(18, 32):
		for x in range(x0, x0 + w):
			var c: Color = P.w2 if (x - x0) % 3 != 2 else P.w1
			if y == 18:
				c = P.w3
			_px(img, x, y, c)
	if w >= 4:
		_hline(img, x0, x0 + w - 1, 21, P.w0)
		_hline(img, x0, x0 + w - 1, 28, P.w0)
		_px(img, x0 + w - 2, 25, P.gold)
	_vline(img, x0 + w - 1, 18, 31, P.w0)
	if stage == 3:
		_rect(img, x0 + 2, 19, 8, 13, Color("2c2030"))
		_rect(img, x0, 18, 2, 14, P.w1)
	return img


func _chest(stage: int) -> Image:
	var img := _img(24, 32)
	_disc(img, 12, 30.5, 7, 1.5, Color(0, 0, 0, 0.3))
	# body
	_rect(img, 5, 22, 14, 8, P.w1)
	_rect(img, 5, 22, 14, 1, P.w3)
	_vline(img, 5, 22, 29, P.gold0)
	_vline(img, 18, 22, 29, P.gold0)
	_hline(img, 5, 18, 29, P.w0)
	if stage == 0:
		_rect(img, 5, 17, 14, 6, P.w2)
		_hline(img, 5, 18, 17, P.w3)
		_hline(img, 5, 18, 22, P.gold0)
		_rect(img, 11, 21, 2, 3, P.gold)
	else:
		var lid: int = [0, 4, 2, 1][stage]
		_rect(img, 6, 21, 12, 2, P.black)
		if stage == 3:
			_rect(img, 7, 20, 10, 2, P.gold)
			_px(img, 9, 19, P.yellow)
			_px(img, 13, 19, P.yellow)
		_rect(img, 5, 21 - lid - 4, 14, lid + 1, P.w2)
		_hline(img, 5, 18, 21 - lid - 4, P.w3)
		_hline(img, 5, 18, 21 - 3, P.gold0)
	_outline_opaque(img, P.ink)
	return img


func _sign() -> Image:
	var img := _img(24, 32)
	_disc(img, 12, 30.5, 4, 1.2, Color(0, 0, 0, 0.3))
	_rect(img, 11, 23, 2, 8, P.w1)
	_rect(img, 5, 16, 14, 8, P.w3)
	_hline(img, 5, 18, 23, P.w1)
	_hline(img, 7, 16, 18, P.w0)
	_hline(img, 7, 13, 20, P.w0)
	_outline_opaque(img, P.ink)
	return img


func _pot() -> Image:
	var img := _img(24, 32)
	_disc(img, 12, 30.5, 6, 1.4, Color(0, 0, 0, 0.3))
	_shaded(img, 12, 25, 6, 5, [P.d0, P.d1, P.orange, P.d3], 61)
	_rect(img, 9, 18, 6, 3, P.d1)
	_hline(img, 8, 15, 18, P.d3)
	_hline(img, 7, 16, 25, P.d0)
	_outline_opaque(img, P.ink)
	return img


func _faceset() -> Image:
	var sheet := _img(192, 192)
	for i in PEOPLE.size():
		_blit(sheet, _face(PEOPLE[i]), Vector2i((i % 4) * 48, (i / 4) * 48))
	return sheet


func _face(p: Dictionary) -> Image:
	var img := _img(48, 48)
	var top := _col(p.top)
	var bg := top.lightened(0.55)
	for y in 48:
		for x in 48:
			img.set_pixel(x, y, bg.lerp(top.lightened(0.3), y / 60.0))
	var hair := _col(p.hair)
	var skin: Color = P.skin
	var style: String = p.hair_style
	# shoulders
	_disc(img, 24, 50, 18, 10, top)
	_disc(img, 24, 52, 12, 9, top.darkened(0.2))
	if p.get("apron", false):
		_rect(img, 18, 42, 12, 6, P.white)
	if p.name == "hero":
		_disc(img, 24, 41, 9, 3, _col(p.accent))
	if style == "long":
		_rect(img, 10, 14, 28, 26, hair)
	# head
	_disc(img, 24, 25, 12, 14, skin)
	_disc(img, 27, 28, 9, 10, skin)
	_disc(img, 31, 31, 4, 6, P.skin2)
	_disc(img, 24, 25, 11, 13, skin)
	match style:
		"spiky", "short", "long", "cap":
			_disc(img, 24, 15, 13, 8, hair)
			_rect(img, 11, 14, 4, 12, hair)
			_rect(img, 33, 14, 4, 12, hair)
			if style == "spiky":
				for k in 5:
					var sx := 13 + k * 5
					for d in 5:
						_rect(img, sx + d / 2, 4 + d, 3 - d / 3, 1, hair)
			if style == "cap":
				_disc(img, 24, 13, 13, 7, P.red)
				_rect(img, 10, 16, 28, 3, P.red.darkened(0.3))
		"wizard":
			_disc(img, 24, 15, 13, 7, hair)
			for k in 14:
				_hline(img, 24 - k, 24 + k, k - 2, P.purple)
			_rect(img, 4, 12, 40, 3, P.purple.darkened(0.3))
			_rect(img, 10, 11, 28, 1, P.gold)
		"helmet":
			_disc(img, 24, 15, 14, 9, P.st2)
			_rect(img, 10, 16, 28, 3, P.st1)
			_rect(img, 22, 16, 4, 9, P.st1)
			_disc(img, 19, 10, 3, 2, P.st3)
		"bald":
			_rect(img, 11, 18, 4, 9, hair)
			_rect(img, 33, 18, 4, 9, hair)
			_disc(img, 20, 15, 4, 2, skin.lightened(0.25))
	# eyes
	for ex in [18, 29]:
		_rect(img, ex, 24, 3, 5, P.ink)
		_px(img, ex + 1, 25, P.white)
		_hline(img, ex - 1, ex + 3, 21, hair.darkened(0.2) if style != "bald" else P.grey)
	_disc(img, 15, 31, 2, 1.2, P.pink)
	_disc(img, 33, 31, 2, 1.2, P.pink)
	if p.get("beard", false):
		_disc(img, 24, 36, 9, 7, hair)
		_hline(img, 21, 27, 33, P.skin2)
	elif p.get("mustache", false):
		_rect(img, 19, 32, 10, 2, hair)
	else:
		_hline(img, 22, 26, 34, P.skin2.darkened(0.3))
	_outline(img, Rect2i(0, 0, 48, 48), P.ink)
	# frame
	for i in 48:
		img.set_pixel(i, 0, P.ink)
		img.set_pixel(i, 47, P.ink)
		img.set_pixel(0, i, P.ink)
		img.set_pixel(47, i, P.ink)
	return img


# --- System graphic --------------------------------------------------------------------------------

func _system() -> Image:
	var img := _img(160, 80)
	# (0,0) window background: vertical blue gradient
	for y in 32:
		for x in 32:
			var k := y / 31.0
			img.set_pixel(x, y, Color("2c3c9c").lerp(Color("101850"), k))
	# (32,0) frame: 2px light border with rounded corners, transparent centre, arrows inside
	var fo := Vector2i(32, 0)
	for y in 32:
		for x in 32:
			var edge := mini(mini(x, 31 - x), mini(y, 31 - y))
			var c := Color(0, 0, 0, 0)
			if edge == 0:
				c = P.ink
			elif edge == 1:
				c = P.white
			elif edge == 2:
				c = P.grey
			# rounded corners
			var cx := mini(x, 31 - x)
			var cy := mini(y, 31 - y)
			if cx + cy < 2:
				c = Color(0, 0, 0, 0)
			elif cx + cy == 2 and edge <= 1:
				c = P.ink
			img.set_pixel(fo.x + x, fo.y + y, c)
	for k in 4:
		_hline(img, 48 - k - 1, 47 + k, 9 + k, P.white)
		_hline(img, 48 - k - 1, 47 + k, 22 - k, P.white)
	# (64,0),(96,0) cursor frames
	for fr in 2:
		var co := Vector2i(64 + fr * 32, 0)
		for y in 32:
			for x in 32:
				var edge := mini(mini(x, 31 - x), mini(y, 31 - y))
				var c := Color(0, 0, 0, 0)
				if edge == 0:
					c = Color("f8e070") if fr == 0 else Color("f0f0f0")
				elif edge == 1:
					c = Color("c89830") if fr == 0 else Color("a0a8c0")
				elif edge >= 2:
					c = Color(1, 1, 1, 0.22 if fr == 0 else 0.12)
				if mini(x, 31 - x) + mini(y, 31 - y) < 1:
					c = Color(0, 0, 0, 0)
				img.set_pixel(co.x + x, co.y + y, c)
	# (128,0) shop arrows: up, same, down, equipped
	var arrows := [[P.g3, "up"], [P.white, "same"], [P.red, "down"], [P.gold, "eq"]]
	for i in 4:
		var o := Vector2i(128 + i * 8, 0)
		var c: Color = arrows[i][0]
		match arrows[i][1]:
			"up":
				for k in 3:
					_hline(img, o.x + 3 - k, o.x + 4 + k, o.y + 2 + k, c)
				_rect(img, o.x + 3, o.y + 5, 2, 2, c)
			"down":
				_rect(img, o.x + 3, o.y + 1, 2, 2, c)
				for k in 3:
					_hline(img, o.x + 1 + k, o.x + 6 - k, o.y + 3 + k, c)
			"same":
				_hline(img, o.x + 1, o.x + 6, o.y + 3, c)
				_hline(img, o.x + 1, o.x + 6, o.y + 5, c)
			"eq":
				_disc(img, o.x + 4, o.y + 4, 2.6, 2.6, c)
				_px(img, o.x + 3, o.y + 3, P.white)
	# (0,32) menu background colour, (16,32) font shadow colour
	_rect(img, 0, 32, 16, 16, Color("101850"))
	_rect(img, 16, 32, 16, 16, Color("000000"))
	# (32,32) timer digits 0..9, separator, space (8x16)
	for d in 10:
		var rows: Array = RPGTilesetBuilder.DIGITS[d]
		for ry in 5:
			for rx in 3:
				if int(rows[ry]) & (4 >> rx):
					_rect(img, 32 + d * 8 + 1 + rx * 2, 32 + 3 + ry * 2, 2, 2, P.white)
	_rect(img, 112 + 3, 32 + 5, 2, 2, P.white)
	_rect(img, 112 + 3, 32 + 10, 2, 2, P.white)
	# (128,32) airship shadow (2 frames)
	_disc(img, 136, 40, 6, 3, Color(0, 0, 0, 0.5))
	_disc(img, 152, 40, 5, 2.5, Color(0, 0, 0, 0.5))
	# (0,48),(0,64) 20 font colour swatches with a light-to-dark vertical gradient
	var swatches := [
		"f8f8f8", "a0d0ff", "80ff80", "ff8080", "ffd060", "c0c0c0", "ffa040", "c080ff", "60e0e0", "ff80c0",
		"d0d0a0", "80a0ff", "a0ff40", "ff6040", "f0f080", "909090", "ffc0a0", "e0a0ff", "a0f0c0", "ffffff",
	]
	for i in 20:
		var base := Color(swatches[i])
		var o := Vector2i((i % 10) * 16, 48 + (i / 10) * 16)
		for y in 16:
			for x in 16:
				img.set_pixel(o.x + x, o.y + y, base.lightened(0.15).lerp(base.darkened(0.15), y / 15.0))
	return img


# --- battlers, backdrop, title ---------------------------------------------------------------------

func _slime() -> Image:
	var img := _img(48, 40)
	_disc(img, 24, 37, 18, 3, Color(0, 0, 0, 0.3))
	_shaded(img, 24, 26, 18, 13, [Color("1c6a5a"), Color("2ca080"), Color("5cd0a0"), Color("b8f8d8")], 71)
	_disc(img, 15, 20, 4, 3, Color("e8fff4"))
	for ex in [18, 30]:
		_rect(img, ex, 24, 3, 6, P.ink)
		_px(img, ex + 1, 25, P.white)
	_hline(img, 21, 27, 33, Color("12403a"))
	_outline_opaque(img, P.ink)
	return img


func _bat() -> Image:
	var img := _img(64, 40)
	var wing := Color("5a2c7a")
	var wing2 := Color("8a4cb0")
	for side in [-1, 1]:
		for k in 22:
			var x: int = 32 + side * (6 + k)
			var top := 12 + int(abs(k - 8) * 0.4)
			var bottom := 22 + int(sin(k * 0.55) * 4.0) - k / 4
			_vline(img, x, top, bottom, wing if k % 7 != 0 else wing2)
	_shaded(img, 32, 22, 8, 9, [Color("2c1438"), Color("4a2462"), Color("6c3c8c"), Color("9c70c0")], 81)
	_rect(img, 26, 11, 3, 5, Color("4a2462"))
	_rect(img, 35, 11, 3, 5, Color("4a2462"))
	_rect(img, 28, 20, 2, 2, P.yellow)
	_rect(img, 34, 20, 2, 2, P.yellow)
	_px(img, 30, 27, P.white)
	_px(img, 33, 27, P.white)
	_outline_opaque(img, P.ink)
	return img


func _goblin() -> Image:
	var img := _img(48, 64)
	var skin := Color("6cae3c")
	var skin_d := Color("3c7a28")
	_disc(img, 24, 61, 14, 2.5, Color(0, 0, 0, 0.3))
	# legs and body
	_rect(img, 16, 44, 6, 14, Color("5a3a22"))
	_rect(img, 27, 44, 6, 14, Color("5a3a22"))
	_rect(img, 15, 56, 8, 4, P.w0)
	_rect(img, 26, 56, 8, 4, P.w0)
	_shaded(img, 24, 38, 11, 10, [Color("5a3018"), Color("7a4a26"), Color("9a6634"), Color("b8844a")], 91)
	_rect(img, 14, 44, 20, 3, Color("3a2414"))
	# arms + club
	_rect(img, 9, 32, 5, 12, skin_d)
	_rect(img, 34, 30, 5, 12, skin)
	_rect(img, 38, 10, 5, 26, P.w1)
	_disc(img, 40.5, 12, 5, 6, P.w2)
	_px(img, 39, 9, P.w3)
	# head
	_shaded(img, 24, 20, 11, 10, [skin_d, Color("4e902e"), skin, Color("a0d868")], 92)
	for s in [-1, 1]:
		for k in 6:
			_vline(img, 24 + s * (11 + k), 16 + k / 2, 20, skin)
	_rect(img, 18, 18, 4, 3, P.yellow)
	_rect(img, 27, 18, 4, 3, P.yellow)
	_px(img, 20, 19, P.ink)
	_px(img, 28, 19, P.ink)
	_hline(img, 19, 29, 25, Color("2a4a18"))
	_px(img, 21, 26, P.white)
	_px(img, 27, 26, P.white)
	_outline_opaque(img, P.ink)
	return img


func _backdrop() -> Image:
	var img := _img(320, 160)
	for y in 160:
		var sky := Color("6cb4f0").lerp(Color("d8eefc"), clampf(y / 70.0, 0.0, 1.0))
		for x in 320:
			img.set_pixel(x, y, sky)
	# clouds
	for c in [Vector3(60, 22, 1.0), Vector3(200, 14, 1.3), Vector3(270, 34, 0.8)]:
		for k in 4:
			_disc(img, c.x + k * 9 * c.z, c.y + (k % 2) * 3, 11 * c.z, 6 * c.z, Color("f8fcff"))
	# far hills
	for x in 320:
		var h1 := 70 + int(sin(x * 0.025) * 8 + sin(x * 0.07) * 3)
		for y in range(h1, 160):
			img.set_pixel(x, y, Color("7cb0a0"))
		var h2 := 86 + int(sin(x * 0.04 + 1.0) * 7 + cos(x * 0.11) * 3)
		for y in range(h2, 160):
			img.set_pixel(x, y, Color("4c9a50"))
	# field
	for y in range(100, 160):
		for x in 320:
			var k := (y - 100) / 60.0
			var c := Color("6cbc4c").lerp(Color("3c8a34"), k)
			if _n(x, y, 101) < 0.06:
				c = c.darkened(0.25)
			if (x + y * 3) % 23 == 0 and _n(x, y, 102) > 0.5:
				c = Color("a4dc6a")
			img.set_pixel(x, y, c)
	# path
	for y in range(100, 160):
		var half := 6 + (y - 100) * 0.9
		var cx := 160 + sin(y * 0.05) * 10
		for x in range(int(cx - half), int(cx + half)):
			if x >= 0 and x < 320:
				img.set_pixel(x, y, P.d2 if _n(x, y, 103) > 0.15 else P.d1)
	return img


const FONT5x7 := {
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}


func _text(img: Image, s: String, x: int, y: int, scale: int, c: Color, shadow: Color) -> void:
	for pass_i in 2:
		var cx := x
		for ch in s:
			var g: Array = FONT5x7.get(ch, FONT5x7[" "])
			for ry in 7:
				for rx in 5:
					if g[ry][rx] == "1":
						var off := scale if pass_i == 0 else 0
						_rect(img, cx + rx * scale + off, y + ry * scale + off, scale, scale, shadow if pass_i == 0 else c.lerp(c.darkened(0.35), ry / 6.0))
			cx += 6 * scale


func _title() -> Image:
	var img := _img(320, 240)
	for y in 240:
		var c := Color("141838").lerp(Color("c86a5a"), clampf((y - 40) / 150.0, 0.0, 1.0))
		for x in 320:
			img.set_pixel(x, y, c)
	for i in 70:
		var sx := int(_n(i, 0, 201) * 320)
		var sy := int(_n(i, 1, 201) * 120)
		img.set_pixel(sx, sy, Color(1, 1, 0.9, 0.5 + _n(i, 2, 201) * 0.5))
	_disc(img, 284, 34, 14, 14, Color("fff0c8"))
	_disc(img, 290, 30, 12, 12, Color("f8d8b0").lerp(Color("141838"), 0.2))
	# mountains
	for x in 320:
		var h := 150 + int(-abs(sin(x * 0.018)) * 50 + sin(x * 0.07) * 6)
		for y in range(h, 240):
			img.set_pixel(x, y, Color("3a2a4c"))
		var h2 := 178 + int(sin(x * 0.03 + 2) * 10)
		for y in range(h2, 240):
			img.set_pixel(x, y, Color("221a30"))
	# castle silhouette
	var cc := Color("120e1c")
	_rect(img, 40, 140, 56, 50, cc)
	for tx in [36, 64, 92]:
		_rect(img, tx, 120, 12, 70, cc)
		for k in 7:
			_hline(img, tx + 6 - k, tx + 5 + k, 112 + k, cc)
	for bx in range(40, 96, 6):
		_rect(img, bx, 136, 3, 4, cc)
	for wnd in [Vector2i(41, 140), Vector2i(69, 132), Vector2i(97, 140), Vector2i(55, 160), Vector2i(80, 160)]:
		_rect(img, wnd.x, wnd.y, 2, 4, Color("f8c860"))
	_rect(img, 0, 200, 320, 40, Color("140f1c"))
	# title text
	_text(img, "RPG KIT", 160 - (7 * 6 * 5) / 2, 64, 5, Color("f8d870"), Color("2a1430"))
	_text(img, "STARTER PACK", 160 - (12 * 6 * 2) / 2, 112, 2, Color("e8eaf8"), Color("1a1030"))
	return img


# --- audio -----------------------------------------------------------------------------------------

const RATE := 22050


func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


## Adds a tone to buf. wave: square|tri|sine|saw|noise. Frequency slides f0 -> f1.
func _tone(buf: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, wave: String, vol: float, duty := 0.5, attack := 0.005, release := 0.05) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	var lfsr := 0x7FFF
	var noise_v := 0.0
	var noise_step := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var k := float(i) / maxf(1.0, n - 1)
		var f := lerpf(f0, f1, k)
		phase = fmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if phase < duty else -1.0
			"tri":
				s = 4.0 * absf(phase - 0.5) - 1.0
			"sine":
				s = sin(phase * TAU)
			"saw":
				s = phase * 2.0 - 1.0
			"noise":
				noise_step += f / RATE
				if noise_step >= 1.0:
					noise_step -= 1.0
					var bit := (lfsr ^ (lfsr >> 1)) & 1
					lfsr = (lfsr >> 1) | (bit << 14)
					noise_v = 1.0 if lfsr & 1 else -1.0
				s = noise_v
		var env := 1.0
		if t < attack:
			env = t / attack
		var rem := dur - t
		if rem < release:
			env *= maxf(0.0, rem / release)
		buf[idx] += s * vol * env


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _write_wav(buf: PackedFloat32Array, rel: String, eight_bit: bool, loop := false) -> void:
	var w := AudioStreamWAV.new()
	w.mix_rate = RATE
	w.stereo = false
	var data := PackedByteArray()
	if eight_bit:
		w.format = AudioStreamWAV.FORMAT_8_BITS
		data.resize(buf.size())
		for i in buf.size():
			var v := int(round(clampf(buf[i], -1.0, 1.0) * 127.0))
			data[i] = v & 0xFF
	else:
		w.format = AudioStreamWAV.FORMAT_16_BITS
		data.resize(buf.size() * 2)
		for i in buf.size():
			var v2 := int(round(clampf(buf[i], -1.0, 1.0) * 32767.0))
			data.encode_s16(i * 2, v2)
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	var path := OUT.path_join(rel)
	var err := w.save_to_wav(path)
	if err != OK:
		push_error("wav save failed %s" % rel)
	if loop:
		_write_loop_import(path)


## Pre-seeds the .import file so music imports with forward looping (Godot keeps existing params).
func _write_loop_import(path: String) -> void:
	var imp := path + ".import"
	if FileAccess.file_exists(imp):
		var txt := FileAccess.get_file_as_string(imp)
		if txt.contains("edit/loop_mode=2"):
			return
		var re := RegEx.create_from_string("edit/loop_mode=\\d+")
		txt = re.sub(txt, "edit/loop_mode=2")
		var re2 := RegEx.create_from_string("edit/loop_end=-?\\d+")
		txt = re2.sub(txt, "edit/loop_end=-1")
		var f0 := FileAccess.open(imp, FileAccess.WRITE)
		f0.store_string(txt)
		return
	var f := FileAccess.open(imp, FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"wav\"\ntype=\"AudioStreamWAV\"\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=2\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=2\n")


func _sounds() -> void:
	var b: PackedFloat32Array
	# step
	b = _buf(0.09)
	_tone(b, 0, 0.08, 2200, 900, "noise", 0.35, 0.5, 0.002, 0.06)
	_tone(b, 0, 0.05, 120, 80, "tri", 0.3)
	_write_wav(b, "Sound/step.wav", false)
	# door_open: creak + thud
	b = _buf(0.5)
	for k in 6:
		_tone(b, k * 0.045, 0.05, 260 - k * 18, 230 - k * 18, "square", 0.12, 0.3, 0.003, 0.02)
	_tone(b, 0.32, 0.16, 1500, 300, "noise", 0.35, 0.5, 0.002, 0.12)
	_tone(b, 0.32, 0.14, 90, 50, "tri", 0.4)
	_write_wav(b, "Sound/door_open.wav", false)
	# chest_open
	b = _buf(0.6)
	_tone(b, 0, 0.08, 400, 300, "noise", 0.2, 0.5, 0.002, 0.05)
	for k in 4:
		_tone(b, 0.1 + k * 0.07, 0.2, _midi(76 + [0, 4, 7, 12][k]), _midi(76 + [0, 4, 7, 12][k]), "square", 0.16, 0.25, 0.003, 0.15)
	_write_wav(b, "Sound/chest_open.wav", false)
	# inn_rest jingle
	b = _buf(2.6)
	var inn := [[67, 0.0], [71, 0.25], [74, 0.5], [79, 0.75], [78, 1.1], [79, 1.35]]
	for nt in inn:
		_tone(b, nt[1], 0.3 if nt[1] < 1.3 else 1.1, _midi(nt[0]), _midi(nt[0]), "square", 0.16, 0.25, 0.005, 0.2)
	_tone(b, 1.35, 1.1, _midi(55), _midi(55), "tri", 0.3, 0.5, 0.01, 0.5)
	_tone(b, 1.35, 1.1, _midi(62), _midi(62), "tri", 0.2, 0.5, 0.01, 0.5)
	_write_wav(b, "Sound/inn_rest.wav", false)
	# cursor
	b = _buf(0.05)
	_tone(b, 0, 0.04, 1320, 1320, "square", 0.18, 0.5, 0.001, 0.02)
	_write_wav(b, "Sound/cursor.wav", false)
	# decision
	b = _buf(0.14)
	_tone(b, 0, 0.05, 880, 880, "square", 0.18, 0.5, 0.001, 0.01)
	_tone(b, 0.05, 0.08, 1320, 1320, "square", 0.18, 0.5, 0.001, 0.05)
	_write_wav(b, "Sound/decision.wav", false)
	# cancel
	b = _buf(0.14)
	_tone(b, 0, 0.05, 660, 660, "square", 0.18, 0.5, 0.001, 0.01)
	_tone(b, 0.05, 0.08, 440, 440, "square", 0.18, 0.5, 0.001, 0.05)
	_write_wav(b, "Sound/cancel.wav", false)
	# buzzer
	b = _buf(0.28)
	_tone(b, 0, 0.26, 110, 100, "square", 0.22, 0.5, 0.002, 0.04)
	_tone(b, 0, 0.26, 116, 104, "saw", 0.12, 0.5, 0.002, 0.04)
	_write_wav(b, "Sound/buzzer.wav", false)
	# save
	b = _buf(0.7)
	for k in 5:
		_tone(b, k * 0.07, 0.3, _midi(72 + [0, 7, 12, 16, 19][k]), _midi(72 + [0, 7, 12, 16, 19][k]), "sine", 0.22, 0.5, 0.003, 0.25)
	_write_wav(b, "Sound/save.wav", false)
	# battle_start
	b = _buf(0.9)
	_tone(b, 0, 0.6, 300, 4000, "noise", 0.25, 0.5, 0.05, 0.3)
	for k in 6:
		_tone(b, k * 0.08, 0.1, _midi(60 + k * 4), _midi(60 + k * 4), "square", 0.14, 0.5, 0.002, 0.04)
	_tone(b, 0.5, 0.35, _midi(84), _midi(72), "square", 0.16, 0.25, 0.002, 0.2)
	_write_wav(b, "Sound/battle_start.wav", false)
	# attack: slash
	b = _buf(0.2)
	_tone(b, 0, 0.18, 6000, 800, "noise", 0.35, 0.5, 0.003, 0.12)
	_write_wav(b, "Sound/attack.wav", false)
	# damage: thump
	b = _buf(0.25)
	_tone(b, 0, 0.22, 900, 200, "noise", 0.35, 0.5, 0.001, 0.15)
	_tone(b, 0, 0.2, 160, 50, "square", 0.25, 0.5, 0.001, 0.12)
	_write_wav(b, "Sound/damage.wav", false)
	# heal: shimmer
	b = _buf(0.8)
	for k in 8:
		var m: int = 72 + [0, 4, 7, 12, 16, 19, 24, 28][k]
		_tone(b, k * 0.06, 0.3, _midi(m), _midi(m) * 1.01, "sine", 0.18, 0.5, 0.003, 0.25)
	_write_wav(b, "Sound/heal.wav", false)
	# escape: quick descending patter
	b = _buf(0.6)
	for k in 6:
		_tone(b, k * 0.08, 0.05, 1800, 600, "noise", 0.2, 0.5, 0.002, 0.03)
		_tone(b, k * 0.08, 0.06, _midi(84 - k * 3), _midi(82 - k * 3), "square", 0.1, 0.25, 0.002, 0.03)
	_write_wav(b, "Sound/escape.wav", false)
	# level_up
	b = _buf(1.2)
	var lv := [60, 64, 67, 72, 67, 72, 76]
	for k in lv.size():
		var d := 0.09 if k < 6 else 0.5
		_tone(b, k * 0.09, d, _midi(lv[k]), _midi(lv[k]), "square", 0.16, 0.25, 0.003, 0.08 if k < 6 else 0.35)
	_tone(b, 0.54, 0.6, _midi(48), _midi(48), "tri", 0.3, 0.5, 0.005, 0.4)
	_write_wav(b, "Sound/level_up.wav", false)
	# victory jingle
	b = _buf(1.8)
	var vic := [[72, 0.0, 0.12], [72, 0.15, 0.12], [76, 0.3, 0.12], [79, 0.45, 0.3], [77, 0.8, 0.15], [79, 0.98, 0.7]]
	for nt in vic:
		_tone(b, nt[1], nt[2], _midi(nt[0]), _midi(nt[0]), "square", 0.16, 0.25, 0.003, 0.08)
		_tone(b, nt[1], nt[2], _midi(nt[0] - 12), _midi(nt[0] - 12), "tri", 0.2, 0.5, 0.003, 0.08)
	_write_wav(b, "Sound/victory.wav", false)
	# game_over
	b = _buf(2.8)
	var go := [[69, 0.0, 0.4], [68, 0.45, 0.4], [67, 0.9, 0.4], [64, 1.35, 1.3]]
	for nt in go:
		_tone(b, nt[1], nt[2], _midi(nt[0]), _midi(nt[0]) * (0.97 if nt[0] == 64 else 1.0), "square", 0.15, 0.5, 0.01, 0.2)
		_tone(b, nt[1], nt[2], _midi(nt[0] - 24), _midi(nt[0] - 24), "tri", 0.25, 0.5, 0.01, 0.2)
	_write_wav(b, "Sound/game_over.wav", false)


## Song: bpm, melody [[midi, eighths]...] (-1 = rest), bass roots per bar (int or [a, b] for half
## bars), drums: bool.
func _song(rel: String, bpm: float, melody: Array, bass: Array, drums: bool, lead_duty := 0.25) -> void:
	var eighth := 60.0 / bpm / 2.0
	var bars := bass.size()
	var total := bars * 8 * eighth
	var b := _buf(total)
	var t := 0.0
	for nt in melody:
		var dur: float = nt[1] * eighth
		if nt[0] >= 0:
			_tone(b, t, dur * 0.92, _midi(nt[0]), _midi(nt[0]), "square", 0.13, lead_duty, 0.004, minf(0.08, dur * 0.4))
			# soft echo an octave down for body
			_tone(b, t, dur * 0.92, _midi(nt[0] - 12), _midi(nt[0] - 12), "square", 0.04, 0.5, 0.004, minf(0.08, dur * 0.4))
		t += dur
	for bar in bars:
		var roots: Array = bass[bar] if bass[bar] is Array else [bass[bar], bass[bar]]
		for e in 8:
			var root: int = roots[0] if e < 4 else roots[1]
			var pat: int = [0, 12, 7, 12][e % 4]
			var bt := (bar * 8 + e) * eighth
			_tone(b, bt, eighth * 0.85, _midi(root + pat), _midi(root + pat), "tri", 0.28, 0.5, 0.003, 0.03)
			if drums:
				if e % 4 == 0:
					_tone(b, bt, 0.08, 150, 50, "sine", 0.3, 0.5, 0.001, 0.06)
				elif e % 4 == 2:
					_tone(b, bt, 0.07, 5000, 2000, "noise", 0.12, 0.5, 0.001, 0.05)
				else:
					_tone(b, bt, 0.025, 9000, 9000, "noise", 0.05, 0.5, 0.001, 0.02)
	# keep the loop seam clean
	for i in mini(64, b.size()):
		b[b.size() - 1 - i] *= float(i) / 64.0
	_write_wav(b, rel, true, true)


func _music() -> void:
	_song("Music/title.wav", 112, [
		[79, 3], [76, 1], [72, 2], [76, 2], [74, 3], [79, 1], [83, 4],
		[81, 3], [79, 1], [76, 2], [72, 2], [77, 2], [76, 2], [74, 4],
		[79, 3], [76, 1], [72, 2], [84, 2], [83, 2], [81, 2], [79, 4],
		[77, 2], [81, 2], [79, 2], [74, 2], [72, 6], [-1, 2],
	], [48, 43, 45, 41, 48, 43, [41, 43], 48], false, 0.5)
	_song("Music/town.wav", 132, [
		[69, 1], [72, 1], [77, 2], [76, 1], [74, 1], [72, 2], [70, 1], [69, 1], [67, 2], [72, 4],
		[74, 1], [72, 1], [69, 2], [74, 1], [77, 1], [74, 2], [70, 2], [74, 2], [72, 4],
		[69, 1], [72, 1], [77, 2], [79, 1], [77, 1], [76, 2], [74, 1], [72, 1], [70, 2], [67, 4],
		[70, 2], [74, 2], [72, 2], [76, 2], [77, 4], [-1, 4],
	], [41, 36, 38, 34, 41, 36, [34, 36], 41], true)
	_song("Music/field.wav", 140, [
		[62, 1], [66, 1], [69, 2], [74, 3], [73, 1], [71, 1], [69, 1], [64, 2], [69, 4],
		[66, 1], [71, 1], [74, 2], [78, 3], [76, 1], [74, 2], [71, 2], [67, 4],
		[69, 1], [74, 1], [78, 2], [76, 2], [74, 2], [73, 2], [76, 2], [69, 4],
		[71, 2], [74, 2], [73, 2], [76, 2], [74, 6], [-1, 2],
	], [38, 45, 47, 43, 38, 45, [43, 45], 38], true)
	_song("Music/battle.wav", 160, [
		[76, 1], [76, 1], [81, 1], [76, 1], [79, 2], [77, 1], [76, 1], [77, 2], [72, 2], [69, 2], [72, 2],
		[79, 1], [79, 1], [83, 1], [79, 1], [77, 2], [76, 1], [74, 1], [76, 2], [80, 2], [83, 4],
		[81, 2], [76, 1], [81, 1], [84, 2], [83, 1], [81, 1], [77, 2], [81, 2], [77, 2], [72, 2],
		[74, 2], [77, 2], [76, 2], [80, 2], [81, 4], [69, 2], [-1, 2],
	], [45, 41, 43, 40, 45, 41, [38, 40], 45], true, 0.5)
	_song("Music/victory.wav", 150, [
		[72, 1], [76, 1], [79, 1], [84, 3], [79, 2], [81, 2], [77, 2], [81, 1], [84, 3],
		[83, 2], [79, 2], [74, 1], [79, 1], [83, 2], [84, 6], [-1, 2],
		[77, 2], [81, 2], [84, 4], [79, 2], [76, 2], [72, 4],
		[74, 2], [79, 2], [83, 2], [86, 2], [84, 6], [-1, 2],
	], [48, 41, 43, 48, 41, 48, 43, 48], true)
	_song("Music/inn.wav", 116, [
		[71, 2], [74, 2], [79, 4], [78, 2], [76, 2], [71, 4],
		[72, 2], [76, 2], [79, 2], [76, 2], [74, 4], [69, 4],
		[71, 2], [74, 2], [79, 3], [81, 1], [79, 2], [78, 2], [76, 4],
		[76, 2], [72, 2], [74, 2], [78, 2], [79, 6], [-1, 2],
	], [43, 40, 36, 38, 43, 40, [36, 38], 43], false, 0.5)


# --- manifest ---------------------------------------------------------------------------------------

func _write_pack_json() -> void:
	var tiles := {
		"water_a": {"passage": 0}, "water_b": {"passage": 0}, "water_c": {"passage": 0},
		"terrain_4": {"passage": 0, "flags": 32},
		"terrain_11": {"passage": 0},
		"anim_0": {"passage": 0}, "anim_1": {"passage": 0, "flags": 8}, "anim_2": {"passage": 0},
		"lower_3": {"flags": 1},
		"lower_12": {"passage": 0}, "lower_13": {"passage": 0, "flags": 32}, "lower_14": {"passage": 0, "flags": 32},
		"lower_15": {"passage": 0, "flags": 32}, "lower_18": {"passage": 0, "flags": 32}, "lower_19": {"passage": 0, "flags": 32},
		"lower_23": {"flags": 8},
		"upper_1": {"passage": 15, "flags": 16}, "upper_2": {"passage": 15, "flags": 16}, "upper_32": {"passage": 15, "flags": 16},
		"upper_22": {"passage": 15},
	}
	for i in [3, 4, 5, 9, 10, 11, 15, 16, 17, 21, 23, 35]:
		tiles["upper_%d" % i] = {"passage": 0, "flags": 32}
	for i in [6, 7, 8, 12, 13, 14, 18, 19, 20, 27, 28, 29, 30, 31, 33, 34, 36, 37, 38]:
		tiles["upper_%d" % i] = {"passage": 0}
	for i in [24, 25, 26]:
		tiles["upper_%d" % i] = {"passage": 0, "flags": 2}
	var manifest := {
		"schema_version": 1,
		"name": "RPG Kit Starter Pack",
		"author": "RPG Kit contributors",
		"license": "CC0-1.0",
		"source": "Generated by tools/generate_starter_assets.gd (procedural, original work)",
		"attribution": "RPG Kit Starter Pack by RPG Kit contributors, dedicated to the public domain (CC0 1.0). No attribution required.",
		"profile": "rm2k",
		"chipsets": {"town": {"tiles": tiles}},
	}
	RPGJson.save_file(OUT.path_join("pack.json"), manifest)
