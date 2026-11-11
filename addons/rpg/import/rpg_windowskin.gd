@tool
class_name RPGWindowSkin
extends RefCounted
## RPG Maker 2000/2003 System graphic (160x80) -> Godot Theme.
##
## Layout (verified: EasyRPG wiki "System graphics technical details"):
##   (0,0)   32x32  window background (wallpaper), stretched (or tiled with tile_background)
##   (32,0)  32x32  window frame; its centre holds the "more" arrows: up (40,8) 16x8,
##                  down (40,16) 16x8 (the arrow positions inside the centre are an assumption)
##   (64,0)  32x32  command cursor frame 1, (96,0) frame 2 (2-frame blink)
##   (128,0) 8x8 x4 shop arrows: up, same, down, equipped
##   (0,32)  menu background colour (top-left pixel), (16,32) font shadow colour (top-left pixel)
##   (32,32) 8x16 x12 timer digits
##   (0,48) 10 x 16x16 font colour swatches 0..9, (0,64) swatches 10..19
## Frame and cursor are 9-sliced with 8 px borders. Text colour n = average of swatch n.
##
## Later makers' window skins are recognised by size and redrawn into that layout first
## (to_2k_layout), so the theme is built the same way:
##   192x128 RPG Maker XP Windowskin: background (0,0) 128x128, frame (128,0) 64x64 with the
##           scroll arrows in its centre (up (152,16), down (152,40), 16x8), cursor (128,64)
##           32x32. XP keeps no text colours in the skin: its fixed colours are used.
##   128x128 RPG Maker VX / VX Ace Window: background (0,0) 64x64 stretched, pattern (0,64)
##           64x64 tiled over it, frame (64,0) 64x64 (arrows up (88,16), down (88,40), 16x8),
##           cursor (64,64) 32x32, text colours n = 0..31 as 8x8 swatches from (64,96), 8 a row.
##   192x192 RPG Maker MV / MZ Window: the VX layout at 1.5x (frame (96,0) 96x96, ...).
## The frame is scaled to 32x32 (8 px corners, as in 2000), the background gets the makers'
## window opacity (192/255) and the RPG Kit text colours are taken by meaning: 0 normal,
## 1 system, 3 disabled, 4 crisis, 5 knocked out, 9 power up (VX: 0, 16, 7, 17, 18, 24).
## The background tone RPG Maker VX Ace applies from its database is not in the image.
##
## Theme contents: PanelContainer/Panel "panel" = background + frame; Label font_color (colour 0)
## and font_shadow_color; Button: normal empty, focus/hover/pressed = cursor; ItemList cursor and
## selected = cursor. Custom type "RPGWindow": colours text_0..text_19, shadow, menu_background;
## icons arrow_up, arrow_down, cursor_1, cursor_2, shop_up, shop_same, shop_down, shop_equipped;
## styleboxes background, frame, cursor, cursor_2.

const SIZE := Vector2i(160, 80)
const BORDER := 8
const PANEL_SIZE := 96
const XP_SIZE := Vector2i(192, 128)
const VX_SIZE := Vector2i(128, 128)
const MV_SIZE := Vector2i(192, 192)
const BACK_OPACITY := 192.0 / 255.0
## RPG Kit text colour slot -> VX / MV text colour index (other slots use the same index).
const VX_COLOUR_SLOTS := {0: 0, 1: 16, 3: 7, 4: 17, 5: 18, 9: 24}
## RPG Maker XP's fixed text colours (Window_Base): normal, system, disabled, crisis,
## knockout, then the \c[1..7] colours; per RPG Kit slot.
const XP_COLOURS := {
	0: Color8(255, 255, 255), 1: Color8(192, 224, 255), 2: Color8(128, 128, 255), 3: Color8(160, 160, 160),
	4: Color8(255, 255, 64), 5: Color8(255, 64, 0), 6: Color8(255, 128, 128), 7: Color8(128, 255, 255),
	8: Color8(255, 128, 255), 9: Color8(128, 255, 128), 10: Color8(255, 255, 128), 11: Color8(192, 192, 192),
}


static func make_theme(texture: Texture2D, tile_background := false) -> Theme:
	if texture == null:
		return fallback_theme()
	var img := texture.get_image()
	if img == null:
		return fallback_theme()
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fmt := skin_format(img.get_size())
	if fmt != "rm2k" and fmt != "":
		img = to_2k_layout(img, fmt)
	elif img.get_size() != SIZE:
		push_warning("RPGWindowSkin: a window skin should be 160x80 (2000/2003), 192x128 (XP), 128x128 (VX) or 192x192 (MV/MZ), got %s." % img.get_size())
		if img.get_width() < SIZE.x or img.get_height() < SIZE.y:
			return fallback_theme()
	img = _key(img)
	var tex := ImageTexture.create_from_image(img)

	var theme := Theme.new()
	var panel := _panel_style(img, tile_background)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PopupPanel", panel)

	var cursor := _nine(tex, Rect2(64, 0, 32, 32))
	var cursor2 := _nine(tex, Rect2(96, 0, 32, 32))
	var colours := font_colours(img)
	var shadow := img.get_pixel(16, 32)
	if shadow.a == 0.0:
		shadow = Color(0, 0, 0, 1)
	for t in ["Label", "Button", "RichTextLabel", "ItemList"]:
		var cname := "default_color" if t == "RichTextLabel" else "font_color"
		theme.set_color(cname, t, colours[0])
		theme.set_color("font_shadow_color", t, shadow)
		theme.set_constant("shadow_offset_x", t, 1)
		theme.set_constant("shadow_offset_y", t, 1)
	for c in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(c, "Button", colours[0])
	theme.set_color("font_disabled_color", "Button", colours[3] if colours.size() > 3 else Color(0.5, 0.5, 0.5))
	theme.set_stylebox("normal", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "Button", cursor)
	theme.set_stylebox("hover", "Button", cursor)
	theme.set_stylebox("pressed", "Button", cursor)
	theme.set_stylebox("hover_pressed", "Button", cursor)
	theme.set_stylebox("panel", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor", "ItemList", cursor)
	theme.set_stylebox("cursor_unfocused", "ItemList", cursor)
	theme.set_stylebox("selected", "ItemList", cursor)
	theme.set_stylebox("selected_focus", "ItemList", cursor)

	var w := "RPGWindow"
	for i in colours.size():
		theme.set_color("text_%d" % i, w, colours[i])
	theme.set_color("shadow", w, shadow)
	theme.set_color("menu_background", w, img.get_pixel(0, 32))
	theme.set_icon("arrow_up", w, _atlas(tex, Rect2(40, 8, 16, 8)))
	theme.set_icon("arrow_down", w, _atlas(tex, Rect2(40, 16, 16, 8)))
	theme.set_icon("cursor_1", w, _atlas(tex, Rect2(64, 0, 32, 32)))
	theme.set_icon("cursor_2", w, _atlas(tex, Rect2(96, 0, 32, 32)))
	var shop := ["shop_up", "shop_same", "shop_down", "shop_equipped"]
	for i in 4:
		theme.set_icon(shop[i], w, _atlas(tex, Rect2(128 + i * 8, 0, 8, 8)))
	for i in 12:
		theme.set_icon("timer_%d" % i, w, _atlas(tex, Rect2(32 + i * 8, 32, 8, 16)))
	var bg := StyleBoxTexture.new()
	bg.texture = tex
	bg.region_rect = Rect2(0, 0, 32, 32)
	if tile_background:
		bg.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		bg.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	theme.set_stylebox("background", w, bg)
	theme.set_stylebox("frame", w, _nine(tex, Rect2(32, 0, 32, 32), false))
	theme.set_stylebox("cursor", w, cursor)
	theme.set_stylebox("cursor_2", w, cursor2)
	theme.set_meta("rpg_system_texture", tex)
	return theme


## "rm2k", "xp", "vx" or "mv" for a window skin of that maker's size, "" for any other size.
static func skin_format(size: Vector2i) -> String:
	match size:
		SIZE:
			return "rm2k"
		XP_SIZE:
			return "xp"
		VX_SIZE:
			return "vx"
		MV_SIZE:
			return "mv"
	return ""


## Redraws an XP, VX or MV window skin (RGBA8) as a 160x80 2000/2003 System graphic: background,
## frame with its arrows, cursor (both blink frames), shadow and menu colours, text colours.
static func to_2k_layout(src: Image, fmt: String) -> Image:
	var out := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var k := 1.5 if fmt == "mv" else 1.0
	var bg_rect := Rect2i(0, 0, 128, 128)
	var pattern_rect := Rect2i()
	var frame_rect := Rect2i(128, 0, 64, 64)
	var cursor_rect := Rect2i(128, 64, 32, 32)
	var up_rect := Rect2i(152, 16, 16, 8)
	var down_rect := Rect2i(152, 40, 16, 8)
	if fmt != "xp":
		bg_rect = _scaled(Rect2i(0, 0, 64, 64), k)
		pattern_rect = _scaled(Rect2i(0, 64, 64, 64), k)
		frame_rect = _scaled(Rect2i(64, 0, 64, 64), k)
		cursor_rect = _scaled(Rect2i(64, 64, 32, 32), k)
		up_rect = _scaled(Rect2i(88, 16, 16, 8), k)
		down_rect = _scaled(Rect2i(88, 40, 16, 8), k)
	# Background (0,0) 32x32, with the maker's window opacity.
	var bg := _resized(src.get_region(bg_rect), Vector2i(32, 32))
	if pattern_rect.size != Vector2i.ZERO:
		bg.blend_rect(_resized(src.get_region(pattern_rect), Vector2i(32, 32)), Rect2i(0, 0, 32, 32), Vector2i.ZERO)
	var sum := Color(0, 0, 0, 0)
	for y in 32:
		for x in 32:
			var c := bg.get_pixel(x, y)
			sum += c
			c.a *= BACK_OPACITY
			bg.set_pixel(x, y, c)
	out.blit_rect(bg, Rect2i(0, 0, 32, 32), Vector2i(0, 0))
	# Frame (32,0) 32x32: 8 px corners; its centre holds the up/down arrows at 2000's places.
	out.blit_rect(_resized(src.get_region(frame_rect), Vector2i(32, 32)), Rect2i(0, 0, 32, 32), Vector2i(32, 0))
	out.fill_rect(Rect2i(40, 8, 16, 16), Color(0, 0, 0, 0))
	out.blit_rect(_resized(src.get_region(up_rect), Vector2i(16, 8)), Rect2i(0, 0, 16, 8), Vector2i(40, 8))
	out.blit_rect(_resized(src.get_region(down_rect), Vector2i(16, 8)), Rect2i(0, 0, 16, 8), Vector2i(40, 16))
	# Cursor (64,0) and its blink frame (96,0): the later makers blink by opacity, not by frame.
	var cursor := _resized(src.get_region(cursor_rect), Vector2i(32, 32))
	out.blit_rect(cursor, Rect2i(0, 0, 32, 32), Vector2i(64, 0))
	out.blit_rect(cursor, Rect2i(0, 0, 32, 32), Vector2i(96, 0))
	# Menu background colour (0,32) and text shadow colour (16,32).
	out.set_pixel(0, 32, Color(sum.r / 1024.0, sum.g / 1024.0, sum.b / 1024.0, 1.0))
	out.set_pixel(16, 32, Color(0, 0, 0, 1))
	# Text colour swatches (0,48), 10 a row.
	for i in 20:
		var c2: Color = XP_COLOURS.get(i, Color.WHITE)
		if fmt != "xp":
			var n: int = VX_COLOUR_SLOTS.get(i, i)
			c2 = src.get_pixel(int((64 + (n % 8) * 8 + 4) * k), int((96 + (n / 8) * 8 + 4) * k))
			c2.a = 1.0
		out.fill_rect(Rect2i((i % 10) * 16, 48 + (i / 10) * 16, 16, 16), c2)
	return out


static func _scaled(r: Rect2i, k: float) -> Rect2i:
	return Rect2i(roundi(r.position.x * k), roundi(r.position.y * k), roundi(r.size.x * k), roundi(r.size.y * k))


static func _resized(img: Image, size: Vector2i) -> Image:
	if img.get_size() == size:
		return img
	var out := img.duplicate() as Image
	out.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR if out.get_width() < size.x * 2 else Image.INTERPOLATE_LANCZOS)
	return out


## 20 text colours: average opaque colour of each 16x16 swatch.
static func font_colours(img: Image) -> Array[Color]:
	var out: Array[Color] = []
	for i in 20:
		var o := Vector2i((i % 10) * 16, 48 + (i / 10) * 16)
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for y in 16:
			for x in 16:
				var c := img.get_pixel(o.x + x, o.y + y)
				if c.a > 0.5:
					sum += c
					n += 1
		out.append(Color(sum.r / n, sum.g / n, sum.b / n, 1.0) if n > 0 else Color.WHITE)
	return out


## Without a System graphic: blue gradient window, white frame, light cursor.
static func fallback_theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.12, 0.16, 0.42, 0.95)
	panel.border_color = Color(0.92, 0.92, 0.98)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(BORDER)
	for t in ["PanelContainer", "Panel", "PopupPanel"]:
		theme.set_stylebox("panel", t, panel)
	var cursor := StyleBoxFlat.new()
	cursor.bg_color = Color(1, 1, 1, 0.18)
	cursor.border_color = Color(1, 1, 1, 0.85)
	cursor.set_border_width_all(1)
	cursor.set_corner_radius_all(2)
	cursor.set_content_margin_all(2)
	for t in ["Label", "Button", "ItemList"]:
		theme.set_color("font_color", t, Color.WHITE)
		theme.set_color("font_shadow_color", t, Color(0, 0, 0, 0.8))
		theme.set_constant("shadow_offset_x", t, 1)
		theme.set_constant("shadow_offset_y", t, 1)
	theme.set_stylebox("normal", "Button", StyleBoxEmpty.new())
	for s in ["focus", "hover", "pressed", "hover_pressed"]:
		theme.set_stylebox(s, "Button", cursor)
	theme.set_stylebox("panel", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor", "ItemList", cursor)
	theme.set_stylebox("selected", "ItemList", cursor)
	theme.set_stylebox("selected_focus", "ItemList", cursor)
	var w := "RPGWindow"
	var defaults := [Color.WHITE, Color(0.6, 0.8, 1.0), Color(0.6, 1.0, 0.6), Color(1.0, 0.5, 0.5), Color(1.0, 0.85, 0.3)]
	for i in 20:
		theme.set_color("text_%d" % i, w, defaults[i] if i < defaults.size() else Color.WHITE)
	theme.set_color("shadow", w, Color(0, 0, 0, 0.8))
	theme.set_stylebox("cursor", w, cursor)
	return theme


## Panel: background (stretched or tiled) under the 9-sliced frame, pre-rendered at 96x96 and
## used as a 9-slice with 8 px margins (centre stretched).
static func _panel_style(img: Image, tile_background: bool) -> StyleBoxTexture:
	var s := PANEL_SIZE
	var out := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var bg := img.get_region(Rect2i(0, 0, 32, 32))
	if tile_background:
		for y in range(0, s, 32):
			for x in range(0, s, 32):
				out.blit_rect(bg, Rect2i(0, 0, 32, 32), Vector2i(x, y))
	else:
		bg.resize(s - 4, s - 4, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(bg, Rect2i(Vector2i.ZERO, bg.get_size()), Vector2i(2, 2))
	var frame := img.get_region(Rect2i(32, 0, 32, 32))
	var b := BORDER
	var mid := 32 - 2 * b
	# corners
	out.blend_rect(frame, Rect2i(0, 0, b, b), Vector2i(0, 0))
	out.blend_rect(frame, Rect2i(32 - b, 0, b, b), Vector2i(s - b, 0))
	out.blend_rect(frame, Rect2i(0, 32 - b, b, b), Vector2i(0, s - b))
	out.blend_rect(frame, Rect2i(32 - b, 32 - b, b, b), Vector2i(s - b, s - b))
	# edges, tiled
	for x in range(b, s - b, mid):
		var wpx := mini(mid, s - b - x)
		out.blend_rect(frame, Rect2i(b, 0, wpx, b), Vector2i(x, 0))
		out.blend_rect(frame, Rect2i(b, 32 - b, wpx, b), Vector2i(x, s - b))
	for y in range(b, s - b, mid):
		var hpx := mini(mid, s - b - y)
		out.blend_rect(frame, Rect2i(0, b, b, hpx), Vector2i(0, y))
		out.blend_rect(frame, Rect2i(32 - b, b, b, hpx), Vector2i(s - b, y))
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(out)
	sb.set_texture_margin_all(b)
	sb.set_content_margin_all(b)
	return sb


static func _nine(tex: Texture2D, region: Rect2, margins := true) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.region_rect = region
	sb.set_texture_margin_all(BORDER)
	if margins:
		sb.set_content_margin_all(4)
	else:
		sb.draw_center = false
		sb.set_content_margin_all(BORDER)
	return sb


static func _atlas(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region
	return at


## When the graphic has no alpha: key out the most common colour of the frame's centre (the
## transparent colour of frame, cursor and arrows in indexed originals).
static func _key(img: Image) -> Image:
	if img.detect_alpha() != Image.ALPHA_NONE:
		return img
	var counts := {}
	for y in range(8, 24):
		for x in range(40, 56):
			var c := img.get_pixel(x, y).to_html()
			counts[c] = int(counts.get(c, 0)) + 1
	var best := ""
	for c in counts:
		if best == "" or counts[c] > counts[best]:
			best = c
	var key := Color.html(best)
	for y in range(0, 32):
		for x in range(32, 160):
			if img.get_pixel(x, y).is_equal_approx(key):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img
