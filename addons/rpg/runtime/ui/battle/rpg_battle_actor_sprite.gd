extends Control
## One actor in a side-view battle. It draws the actor's battle graphic, facing left, and plays
## motions (idle, step forward, attack, skill, item, damage, guard, victory, dead...).
##
## The graphic comes from resolve(), first match wins:
##   1. the actor's side-view battler (record "sv_battler", or one stored by Change Actor Graphic in
##      the actor's look), from the "sv_battler" asset kind (BattleCharSet folder):
##      - an RPG Maker MV/MZ sheet (img/sv_actors, 576x384): 9 x 6 cells of 64x64. Motion n sits in
##        column block n / 6 (3 frames wide) and row n % 6, in MOTIONS order (walk, wait, chant,
##        guard, damage, evade / thrust, swing, missile, skill, spell, item / escape, victory,
##        dying, abnormal, sleep, dead). Checked against Actor1_1.png of the MV sample data.
##      - an RPG Maker 2003 BattleCharSet (144x384): 3 frames x 8 rows of 48x48. The "A" file holds
##        the general poses and a companion "B" file (same name, last letter B) the attacks and
##        item use (see POSES_2K3). Worked out by looking at the 2003 RTP sheets, not from a spec.
##   2. the actor's walk sprite (CharSet), facing left; works in every project.
##   3. a plain placeholder figure.
##
## The sprite is placed by its feet (`home`, in the parent's coordinates); `offset` moves it from
## there (stepping forward is a negative x offset).

## Motion names (RPG Maker MV order: the index is the MV sheet position).
const MOTIONS := ["walk", "wait", "chant", "guard", "damage", "evade", "thrust", "swing", "missile",
	"skill", "spell", "item", "escape", "victory", "dying", "abnormal", "sleep", "dead"]
## Motions that play once and then return to the base (idle) motion; the rest loop.
const ONE_SHOT := ["damage", "evade", "thrust", "swing", "missile", "skill", "spell", "item"]
## 2003 BattleCharSet poses: motion -> [file "a" or "b", row]. The A file's rows: 0 skill use,
## 1 defending, 2 damaged, 3 dead, 4 bad status, 5 victory, 6 idle, 7 walking; the B file's: 0 and
## 1 attacks (right / left hand), 2 item.
const POSES_2K3 := {
	"walk": ["a", 7], "wait": ["a", 6], "chant": ["a", 0], "guard": ["a", 1], "damage": ["a", 2],
	"evade": ["a", 6], "thrust": ["b", 0], "swing": ["b", 0], "missile": ["b", 1], "skill": ["a", 0],
	"spell": ["a", 0], "item": ["b", 2], "escape": ["a", 7], "victory": ["a", 5], "dying": ["a", 4],
	"abnormal": ["a", 4], "sleep": ["a", 4], "dead": ["a", 3],
}
## Without a B file: attacks fall back to the idle pose and item use to skill use.
const POSES_2K3_NO_B := {"thrust": ["a", 6], "swing": ["a", 6], "missile": ["a", 6], "item": ["a", 0]}
## Walk sprite (CharSet): motion -> [facing, mode]; mode "still" (standing frame), "walk"
## (stepping), "step" (one stride frame).
const CHARSET_POSES := {
	"walk": ["left", "walk"], "wait": ["left", "still"], "chant": ["left", "walk"], "guard": ["left", "still"],
	"damage": ["left", "still"], "evade": ["left", "step"], "thrust": ["left", "walk"], "swing": ["left", "walk"],
	"missile": ["left", "walk"], "skill": ["left", "walk"], "spell": ["left", "walk"], "item": ["left", "walk"],
	"escape": ["right", "walk"], "victory": ["down", "walk"], "dying": ["left", "still"],
	"abnormal": ["left", "still"], "sleep": ["left", "still"], "dead": ["left", "still"],
}
const PATTERN := [0, 1, 2, 1]
const FRAME_SECONDS := 0.15
const ONE_SHOT_FRAME_SECONDS := 0.12
## Screen width each maker paints battle graphics for (as the battle scene's BATTLER_SCREEN).
const SCREEN_WIDTH := {"rm2k": 320.0, "xp": 640.0, "vx": 544.0, "mv": 816.0}

## "mv", "2k3", "charset" or "none".
var kind := "none"
var actor_id := ""
## The motion being drawn, and the looping motion it returns to.
var motion := "wait"
var base_motion := "wait"
var home := Vector2.ZERO:
	set(v):
		home = v
		_place()
var offset := Vector2.ZERO:
	set(v):
		offset = v
		_place()
## Pixel scale of the sheet on the 320x240 stage (native_k: the maker's own proportions).
var scale_k := 1.0
var native_k := 1.0
## The visible figure within a cell, in sheet pixels (measured from the idle frame).
var figure_box := Rect2(0, 0, 16, 24)

var info: Dictionary = {}
var tex_rect: TextureRect
var _atlas: AtlasTexture
var _t := 0.0
var _step := 0
var _held := false        ## a looping motion played on purpose (step forward, escape...)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect = TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex_rect)
	_atlas = AtlasTexture.new()


# --- graphic lookup ------------------------------------------------------------------------------

## The battle graphic for an actor. `look`: the actor's look (RPGGameState.actor_look plus
## "sv_battler"); `project_profile`: the project's asset profile ("rm2k", "mv"...).
## Returns {kind, texture, texture_b, cell: Vector2i, index, profile, single, name, screen}.
static func resolve(look: Dictionary, project_profile := "rm2k") -> Dictionary:
	for n in [str(look.get("sv_battler", "")), str(look.get("battler", ""))]:
		if n == "" or RPGAssets.find("sv_battler", n) == "":
			continue
		var tex := RPGAssets.load_texture("sv_battler", n)
		var layout := sheet_layout(tex)
		if layout == "":
			continue
		var prof := RPGAssets.sheet_profile("sv_battler", n, "")
		if layout == "mv":
			return {"kind": "mv", "texture": tex, "texture_b": null, "cell": Vector2i(tex.get_width() / 9, tex.get_height() / 6),
				"name": n, "screen": SCREEN_WIDTH.get(prof if prof in ["mv", "vx", "xp"] else "mv", 816.0)}
		var b := companion_b(n)
		var tex_b: Texture2D = RPGCharset.prepared_texture(RPGAssets.load_texture("sv_battler", b)) if b != "" else null
		return {"kind": "2k3", "texture": RPGCharset.prepared_texture(tex), "texture_b": tex_b,
			"cell": Vector2i(tex.get_width() / 3, tex.get_height() / 8), "name": n, "screen": 320.0}
	var cs := str(look.get("charset", ""))
	if cs != "":
		var ctex := RPGCharset.prepared_texture(RPGAssets.load_texture("charset", cs))
		if ctex != null:
			var cprof := RPGAssets.sheet_profile("charset", cs, project_profile)
			var single := RPGCharset.is_single_character(cs, cprof)
			return {"kind": "charset", "texture": ctex, "texture_b": null, "name": cs, "profile": cprof, "single": single,
				"index": int(look.get("charset_index", 0)),
				"cell": RPGCharset.frame_size(cprof, Vector2i(ctex.get_size()), single), "screen": SCREEN_WIDTH.get(cprof, 320.0)}
	return {"kind": "none", "texture": _placeholder(), "texture_b": null, "cell": Vector2i(16, 24), "name": "", "screen": 320.0}


## "mv" (9 x 6 square cells), "2k3" (3 x 8 square cells) or "" for a sheet of another shape.
static func sheet_layout(tex: Texture2D) -> String:
	if tex == null:
		return ""
	var w := tex.get_width()
	var h := tex.get_height()
	if w % 9 == 0 and h % 6 == 0 and w / 9 == h / 6 and w > 0:
		return "mv"
	if w % 3 == 0 and h % 8 == 0 and w / 3 == h / 8 and w > 0:
		return "2k3"
	return ""


## The 2003 "B" file that goes with an "A" BattleCharSet ("Male Fighter A" -> "Male Fighter B"),
## or "" when there is none.
static func companion_b(sheet_name: String) -> String:
	if sheet_name == "":
		return ""
	var last := sheet_name.right(1)
	if last != "A" and last != "a":
		return ""
	var b := sheet_name.left(sheet_name.length() - 1) + ("B" if last == "A" else "b")
	return b if RPGAssets.find("sv_battler", b) != "" else ""


static func _placeholder() -> Texture2D:
	var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	var body := Color(0.55, 0.7, 0.95)
	for y in 24:
		for x in 16:
			var head := Vector2(x + 0.5 - 8, y + 0.5 - 5).length() < 4.5
			var torso := y >= 9 and y < 22 and absf(x + 0.5 - 8) < 5.0 - (y - 9) * 0.1
			if head or torso:
				img.set_pixel(x, y, body if not (x == 5 and y == 4) else Color.BLACK)
	return ImageTexture.create_from_image(img)


# --- setup and drawing ---------------------------------------------------------------------------

## Uses a resolve() result; `stage_width` is the battle stage width (320).
func setup(p_info: Dictionary, stage_width := 320.0) -> void:
	info = p_info
	kind = str(info.get("kind", "none"))
	native_k = minf(1.0, stage_width / float(info.get("screen", stage_width)))
	figure_box = measure_figure()
	_atlas.atlas = info.get("texture")
	tex_rect.texture = _atlas
	set_scale_k(native_k)
	_show(motion, 0)


## Draws the sheet at `k` stage pixels per sheet pixel (the battle scene evens out mixed sources).
func set_scale_k(k: float) -> void:
	scale_k = k
	var cell: Vector2i = info.get("cell", Vector2i(16, 24))
	# Pixel art grows with whole pixels; shrunk sheets are filtered (the UI is scaled up again on
	# larger screens, where they come out near 1:1).
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if scale_k >= 0.999 else CanvasItem.TEXTURE_FILTER_LINEAR
	size = (Vector2(cell) * scale_k).round()
	tex_rect.size = size
	tex_rect.pivot_offset = size / 2.0
	_place()


## The visible figure (opaque pixels of the idle frame) in sheet pixels, within its cell; the whole
## cell when it cannot be measured.
func measure_figure() -> Rect2:
	var cell: Vector2i = info.get("cell", Vector2i(16, 24))
	var full := Rect2(Vector2.ZERO, Vector2(cell))
	var src := frame_source("wait", 1)
	var tex: Texture2D = src[0]
	if tex == null:
		return full
	var img := RPGAssets.texture_image(tex)
	if img == null:
		return full
	var r: Rect2i = Rect2i(src[1]).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return full
	var used := img.get_region(r).get_used_rect()
	return Rect2(used) if used.size.x > 0 and used.size.y > 0 else full


## Height and width of the visible figure on the stage.
func figure_height() -> float:
	return figure_box.size.y * scale_k


func figure_width() -> float:
	return figure_box.size.x * scale_k


## The visible figure's rectangle in the parent's coordinates (overlap checks, mouse).
func figure_rect() -> Rect2:
	return Rect2(position + figure_box.position * scale_k, figure_box.size * scale_k)


func _place() -> void:
	# The feet (bottom of the visible figure) stand on `home`, centred on it.
	var feet := Vector2(figure_box.position.x + figure_box.size.x / 2.0, figure_box.end.y) * scale_k
	position = (home + offset - feet).round()


## Top-centre of the figure, in the parent's coordinates (popups, the target arrow).
func point() -> Vector2:
	return home + offset - Vector2(0, figure_height() * 0.8)


## Sets the looping motion shown when nothing else plays (wait, guard, dying, dead...).
func set_base(m: String) -> void:
	if not MOTIONS.has(m):
		m = "wait"
	if base_motion == m:
		return
	base_motion = m
	if not _held and not ONE_SHOT.has(motion):
		_start(m)


## Plays a motion: a one-shot motion (attack, damage...) returns to the base motion when done;
## a looping one (walk, escape, victory) stays until clear_motion() or another play_motion().
func play_motion(m: String) -> void:
	if not MOTIONS.has(m):
		return
	_held = not ONE_SHOT.has(m)
	_start(m)


## Back to the base motion.
func clear_motion() -> void:
	_held = false
	_start(base_motion)


func is_playing_one_shot() -> bool:
	return ONE_SHOT.has(motion)


func _start(m: String) -> void:
	motion = m
	_t = 0.0
	_step = 0
	_show(m, 0)


func _process(delta: float) -> void:
	if kind == "":
		return
	_t += delta
	var one := ONE_SHOT.has(motion)
	var period := ONE_SHOT_FRAME_SECONDS if one else FRAME_SECONDS
	if _t < period:
		return
	_t -= period
	_step += 1
	if one and _step >= 3:
		_held = false
		_start(base_motion)
		return
	_show(motion, _step)


## Frame index (0..2) at animation step `step`: one-shot motions run 0,1,2; loops 0,1,2,1.
static func frame_at(m: String, step: int) -> int:
	if ONE_SHOT.has(m):
		return clampi(step, 0, 2)
	return PATTERN[posmod(step, PATTERN.size())]


## Source rectangle on the sheet for motion `m`, frame `f`; returns [texture, rect].
func frame_source(m: String, f: int) -> Array:
	var cell: Vector2i = info.get("cell", Vector2i(16, 24))
	match kind:
		"mv":
			var i := MOTIONS.find(m)
			return [info.texture, Rect2((i / 6 * 3 + f) * cell.x, (i % 6) * cell.y, cell.x, cell.y)]
		"2k3":
			var pose: Array = POSES_2K3.get(m, ["a", 6])
			var tex: Texture2D = info.texture
			if pose[0] == "b":
				if info.get("texture_b") is Texture2D:
					tex = info.texture_b
				else:
					pose = POSES_2K3_NO_B.get(m, ["a", 6])
			return [tex, Rect2(f * cell.x, int(pose[1]) * cell.y, cell.x, cell.y)]
		"charset":
			var cp: Array = CHARSET_POSES.get(m, ["left", "still"])
			var fr := 1
			match str(cp[1]):
				"walk":
					fr = f
				"step":
					fr = 0
			var tex2: Texture2D = info.texture
			return [tex2, Rect2(RPGCharset.frame_rect(info.get("profile", "rm2k"), Vector2i(tex2.get_size()), int(info.get("index", 0)), str(cp[0]), fr, bool(info.get("single", false))))]
	var t: Texture2D = info.get("texture")
	return [t, Rect2(Vector2.ZERO, t.get_size() if t != null else Vector2.ONE)]


func _show(m: String, step: int) -> void:
	if info.is_empty() or info.get("texture") == null:
		return
	var src := frame_source(m, frame_at(m, step))
	_atlas.atlas = src[0]
	_atlas.region = src[1]
	tex_rect.queue_redraw()
	# A walk sprite or placeholder has no lying-down pose: knocked out, it lies on its side, dimmed.
	var flat := m == "dead" and (kind == "charset" or kind == "none")
	tex_rect.rotation = -PI / 2.0 if flat else 0.0
	tex_rect.position = Vector2(0, size.y * 0.3) if flat else Vector2.ZERO
	var tint := Color.WHITE
	if kind == "charset" or kind == "none":
		match m:
			"dead":
				tint = Color(0.75, 0.6, 0.6)
			"dying", "abnormal", "sleep":
				tint = Color(0.85, 0.85, 1.0)
			"guard":
				tint = Color(0.8, 0.9, 1.15)
	tex_rect.self_modulate = tint
