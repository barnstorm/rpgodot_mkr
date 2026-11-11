@tool
class_name RPGCharset
extends RefCounted
## CharSet / FaceSet frame rectangles and SpriteFrames (pure code).
##
## RPG Maker 2000/2003 CharSet: 288x256 = 4 x 2 characters; each character is 3 frames x 4
## directions of 24x32 px (EasyRPG wiki "Media file format specifications": 288x256, 8
## characters in two rows of four, 3x4 grid, 24x32 frames; it also lists 72x128 one-character
## and 24x32 single-frame sheets, which are handled here).
## Direction rows: up, right, down, left (from the rm2k profile "directions"; this order is the
## common 2000/2003 convention, not stated on the wiki page; it is data in rm2k.json, so a fix is a
## one-line change). Columns: frame 0 = step A, 1 = standing, 2 = step B. Walk pattern 0,1,2,1.
## FaceSet: 192x192 = 4 x 4 faces of 48x48, index row-major.
## XP (xp.json): one character per file, 4 frames x 4 directions (rows down, left, right, up),
##   frame size = sheet size / 4; idle frame 0, walk pattern 0,1,2,3.
## VX/VX Ace and MV/MZ (vx.json, mv.json): 4 x 2 characters of 3 frames x 4 directions (rows down,
##   left, right, up), frame size = sheet size / (12, 8). A file name whose leading sign
##   characters ("!" and "$", in any order) include "$" holds one character (3 x 4 frames);
##   "!" alone marks an object and does not change the layout. Faces: 4 x 2 per sheet,
##   96x96 (VX) or 144x144 (MV), from the profile's faceset cell.
##
## Transparency: 2000/2003 sheets use palette index 0 as transparent. If an image has no alpha
## at all, the colour of its top-left pixel is keyed out (key_transparency).

const DEFAULT_DIRECTIONS := ["up", "right", "down", "left"]
const FACINGS := ["down", "left", "right", "up"]
const WALK_FPS := 6.0

static var _frames_cache: Dictionary = {}


static func _profile(profile: Variant) -> RPGProfile:
	if profile is RPGProfile:
		return profile
	if profile is String and profile != "":
		return RPGProfile.load_profile(profile)
	return RPGProfile.load_profile("rm2k")


## True when a file name marks a one-character sheet (`$` prefix, VX and later).
static func is_single_character(file_name: String, profile: Variant = null) -> bool:
	var p := _profile(profile)
	var prefix := str(p.sheet("charset").get("single_prefix", "")) if p else ""
	if prefix == "":
		return false
	var f := file_name.get_file()
	# Leading sign characters: "$" (one character) and "!" (object), in any order.
	var i := 0
	while i < f.length() and (f[i] == "!" or f[i] == "$"):
		if f.substr(i).begins_with(prefix):
			return true
		i += 1
	return f.begins_with(prefix)


## Number of characters on a sheet.
static func character_count(profile: Variant, sheet_size: Vector2i, single := false) -> int:
	var layout := _layout(profile, sheet_size, single)
	return layout.chars.x * layout.chars.y


static func _layout(profile: Variant, sheet_size: Vector2i, single: bool) -> Dictionary:
	var p := _profile(profile)
	var s: Dictionary = p.sheet("charset") if p else {}
	var chars := Vector2i(4, 2)
	if s.has("characters"):
		chars = Vector2i(int(s.characters[0]), int(s.characters[1]))
	var frames := int(s.get("frames", 3))
	var dirs: Array = s.get("directions", DEFAULT_DIRECTIONS)
	var cell := Vector2i.ZERO
	if s.has("cell"):
		cell = Vector2i(int(s.cell[0]), int(s.cell[1]))
	if single:
		chars = Vector2i.ONE
	# 2000/2003 also accepts one-character (72x128) and single-frame (24x32) sheets.
	if cell != Vector2i.ZERO and sheet_size == cell * Vector2i(frames, dirs.size()):
		chars = Vector2i.ONE
	elif cell != Vector2i.ZERO and sheet_size == cell:
		return {"chars": Vector2i.ONE, "frames": 1, "dirs": dirs, "cell": cell, "single_frame": true}
	if cell == Vector2i.ZERO or chars == Vector2i.ONE:
		cell = Vector2i(sheet_size.x / (chars.x * frames), sheet_size.y / (chars.y * dirs.size()))
	return {"chars": chars, "frames": frames, "dirs": dirs, "cell": cell, "single_frame": false}


## Pixel rect of one frame. facing: down/left/right/up; frame: 0..frames-1.
static func frame_rect(profile: Variant, sheet_size: Vector2i, index: int, facing: String, frame: int, single := false) -> Rect2i:
	var l := _layout(profile, sheet_size, single)
	var cell: Vector2i = l.cell
	if l.single_frame:
		return Rect2i(Vector2i.ZERO, cell)
	var chars: Vector2i = l.chars
	var idx := clampi(index, 0, chars.x * chars.y - 1)
	var row: int = maxi(0, (l.dirs as Array).find(facing))
	var f := clampi(frame, 0, int(l.frames) - 1)
	var cx := idx % chars.x
	var cy := idx / chars.x
	var x := (cx * int(l.frames) + f) * cell.x
	var y := (cy * (l.dirs as Array).size() + row) * cell.y
	return Rect2i(x, y, cell.x, cell.y)


## Size of one frame.
static func frame_size(profile: Variant, sheet_size: Vector2i, single := false) -> Vector2i:
	return _layout(profile, sheet_size, single).cell


## Face rect on a FaceSet (2000/2003: 4x4 faces of 48x48).
static func face_rect(profile: Variant, sheet_size: Vector2i, index: int) -> Rect2i:
	var p := _profile(profile)
	var s: Dictionary = p.sheet("faceset") if p else {}
	var cell := Vector2i(48, 48)
	if s.has("cell"):
		cell = Vector2i(int(s.cell[0]), int(s.cell[1]))
	var cols := maxi(1, sheet_size.x / cell.x)
	var rows := maxi(1, sheet_size.y / cell.y)
	var i := clampi(index, 0, cols * rows - 1)
	return Rect2i((i % cols) * cell.x, (i / cols) * cell.y, cell.x, cell.y)


## Copy of the image with the top-left colour made transparent when the image has no alpha.
static func key_transparency(img: Image) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	if out.detect_alpha() != Image.ALPHA_NONE:
		return out
	var key := out.get_pixel(0, 0)
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).is_equal_approx(key):
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out


## Texture with keyed transparency (returns the input when it already has alpha).
static func prepared_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var img := texture.get_image()
	if img == null:
		return texture
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	if img.detect_alpha() != Image.ALPHA_NONE:
		return texture
	return ImageTexture.create_from_image(key_transparency(img))


## Atlas texture of one frame.
static func frame_texture(texture: Texture2D, index: int, facing: String, frame: int, profile: Variant = null, single := false) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = texture
	at.region = Rect2(frame_rect(profile, Vector2i(texture.get_width(), texture.get_height()), index, facing, frame, single))
	return at


## SpriteFrames for character `index`: walk_down/left/right/up (pattern from the profile,
## 0,1,2,1 for 2000/2003) and idle_down/left/right/up plus "idle" (= idle_down).
static func make_sprite_frames(texture: Texture2D, index: int, profile: Variant = null, single := false) -> SpriteFrames:
	var key := "%s:%d:%s" % [texture.get_rid(), index, str(single)]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var p := _profile(profile)
	var s: Dictionary = p.sheet("charset") if p else {}
	var pattern: Array = s.get("walk_pattern", [0, 1, 2, 1])
	var idle := int(s.get("idle_frame", 1))
	var tex := prepared_texture(texture)
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for facing in FACINGS:
		var walk: String = "walk_" + facing
		sf.add_animation(walk)
		sf.set_animation_speed(walk, WALK_FPS)
		sf.set_animation_loop(walk, true)
		for f in pattern:
			sf.add_frame(walk, frame_texture(tex, index, facing, int(f), p, single))
		var still: String = "idle_" + facing
		sf.add_animation(still)
		sf.set_animation_loop(still, false)
		sf.add_frame(still, frame_texture(tex, index, facing, idle, p, single))
	sf.add_animation("idle")
	sf.set_animation_loop("idle", false)
	sf.add_frame("idle", frame_texture(tex, index, "down", idle, p, single))
	_frames_cache[key] = sf
	return sf


static func clear_cache() -> void:
	_frames_cache.clear()
