@tool
extends RefCounted
## Large pictures shown beside a Database form, as in RPG Maker: an actor's walk sprite (all four
## facings), face and battler; an enemy's battler with its hue; an animation (played with the
## game's battle effects, plus its numbered frame cells); a tileset's sheet. Loaded by path (no
## class_name):
##   const Preview := preload("res://addons/rpg/editor/database/rpg_record_preview.gd")
##   cfg["preview"] = func(rec): return Preview.actor(data, rec)

const WIDTH := 220.0


static func actor(data: RPGProjectData, rec: Dictionary) -> Control:
	var box := _panel()
	var vb: VBoxContainer = box.get_child(0)
	var prof := _profile(data)
	var cs := str(rec.get("charset", ""))
	var tex: Texture2D = RPGResourcePicker.texture("charset", cs) if cs != "" else null
	_caption(vb, "Walk sprite")
	if tex != null:
		# A sheet from an imported pack keeps its own layout (RPGAssets.sheet_profile).
		prof = RPGAssets.sheet_profile("charset", cs, prof)
		var single := RPGCharset.is_single_character(cs, prof)
		var src := RPGCharset.prepared_texture(tex)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var idx := int(rec.get("charset_index", 0)) if typeof(rec.get("charset_index", 0)) in [TYPE_INT, TYPE_FLOAT] else 0
		for facing in ["down", "left", "right", "up"]:
			var ft := RPGCharset.frame_texture(src, idx, facing, 1, prof, single)
			row.add_child(_image(ft, 2.0, WIDTH / 4.0 - 2.0))
		vb.add_child(row)
	else:
		_none(vb)
	_caption(vb, "Face")
	var face := str(rec.get("face", ""))
	var ft2: Texture2D = null
	if face != "":
		var fi: Variant = rec.get("face_index", 0)
		ft2 = RPGFormBuilder.face_texture(data, face, int(fi) if typeof(fi) in [TYPE_INT, TYPE_FLOAT] else 0)
	if ft2 != null:
		vb.add_child(_image(ft2, 2.0, WIDTH))
	else:
		_none(vb)
	var bat := str(rec.get("battler", ""))
	if bat != "":
		_caption(vb, "Battler")
		var bt := RPGResourcePicker.texture("battler", bat)
		if bt != null:
			vb.add_child(_image(bt, 2.0, WIDTH))
		else:
			_none(vb)
	return box


static func enemy(_data: RPGProjectData, rec: Dictionary) -> Control:
	var box := _panel()
	var vb: VBoxContainer = box.get_child(0)
	_caption(vb, "Battler")
	var bat := str(rec.get("battler", ""))
	var bt: Texture2D = RPGResourcePicker.texture("battler", bat) if bat != "" else null
	if bt == null:
		_none(vb)
		return box
	var tr := _image(bt, 3.0, WIDTH)
	var hue := float(rec.get("battler_hue", 0)) if typeof(rec.get("battler_hue", 0)) in [TYPE_INT, TYPE_FLOAT] else 0.0
	if hue != 0.0:
		# As the battle scene shows it.
		tr.self_modulate = Color.from_hsv(fposmod(hue / 360.0, 1.0), 0.35, 1.0)
	vb.add_child(tr)
	return box


## What RPGBattleEffects.play() needs from the game: `data` (the record shown, even unsaved) and
## no `audio` (sounds are not played in the editor).
class PreviewHost extends Node:
	var data: RefCounted
	var audio: Variant = null


class OneRecord extends RefCounted:
	var rec: Dictionary

	func has_record(type: String, id: String) -> bool:
		return type == "animations" and id == str(rec.get("id", ""))

	func record(_type: String, _id: String) -> Dictionary:
		return rec


## An animation: a stage with Play (the battle effect the game shows for it) and the sheet's
## cells numbered as the Frames list counts them.
static func animation(_data: RPGProjectData, rec: Dictionary) -> Control:
	var box := _panel()
	var vb: VBoxContainer = box.get_child(0)
	_caption(vb, "Preview")
	var stage := ColorRect.new()
	stage.name = "Stage"
	stage.color = Color(0.1, 0.11, 0.15)
	stage.custom_minimum_size = Vector2(WIDTH, 150)
	stage.clip_contents = true
	vb.add_child(stage)
	var host := PreviewHost.new()
	host.data = OneRecord.new()
	host.data.rec = rec
	box.add_child(host)
	var play := Button.new()
	play.name = "Play"
	play.text = "▶ Play"
	var sheet := str(rec.get("sheet", ""))
	play.tooltip_text = "Plays it as a battle shows it (sounds are not played here)." if sheet != "" else "No sprite sheet: battles show the built-in '%s' effect for this ID." % RPGBattleEffects.builtin_for(str(rec.get("id", "")))
	play.pressed.connect(func() -> void:
		RPGBattleEffects.play(stage, stage.size / 2.0, str(rec.get("id", "")), host))
	vb.add_child(play)
	var tex: Texture2D = RPGResourcePicker.texture("picture", sheet) if sheet != "" else null
	_caption(vb, "Cells (the numbers the Frames list uses)")
	if tex == null:
		_none(vb)
		return box
	var fw := maxi(1, int(rec.get("frame_width", 96)) if typeof(rec.get("frame_width", 96)) in [TYPE_INT, TYPE_FLOAT] else 96)
	var fh := maxi(1, int(rec.get("frame_height", 96)) if typeof(rec.get("frame_height", 96)) in [TYPE_INT, TYPE_FLOAT] else 96)
	var cols := maxi(1, tex.get_width() / fw)
	var count := cols * maxi(1, tex.get_height() / fh)
	var grid := GridContainer.new()
	grid.name = "Cells"
	grid.columns = 4
	for i in mini(count, 32):
		var cell := VBoxContainer.new()
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
		cell.add_child(_image(at, 1.0, WIDTH / 4.0 - 4.0))
		var n := Label.new()
		n.text = str(i)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(n)
		grid.add_child(cell)
	vb.add_child(grid)
	return box


## A tileset: its sheet (or first sheet) as an image.
static func tileset(_data: RPGProjectData, rec: Dictionary) -> Control:
	var box := _panel()
	var vb: VBoxContainer = box.get_child(0)
	_caption(vb, "Sheet")
	var path := ""
	for sp in RPGValidator.tileset_sheet_paths(rec):
		if str(sp[1]) != "":
			path = str(sp[1])
			break
	var tex: Texture2D = null
	if path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
		tex = load(path) as Texture2D if ResourceLoader.exists(path) else ImageTexture.create_from_image(Image.load_from_file(path))
	if tex == null:
		_none(vb)
		if path != "":
			var l := Label.new()
			l.text = "Not found: %s" % path
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = WIDTH
			l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
			vb.add_child(l)
		return box
	vb.add_child(_image(tex, 1.0, WIDTH))
	return box


static func _profile(data: RPGProjectData) -> String:
	return str(data.profile.get("profile", "rm2k")) if data != null else "rm2k"


static func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = WIDTH + 16
	var vb := VBoxContainer.new()
	p.add_child(vb)
	return p


static func _caption(vb: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(l)


static func _none(vb: VBoxContainer) -> void:
	var l := Label.new()
	l.text = "(none)"
	l.modulate = Color(1, 1, 1, 0.45)
	vb.add_child(l)


## Pixel-art image at an integer zoom, shrunk to fit `max_w`.
static func _image(tex: Texture2D, zoom: float, max_w: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var s := tex.get_size() * zoom
	while s.x > max_w and zoom > 1.0:
		zoom -= 1.0
		s = tex.get_size() * zoom
	if s.x > max_w:
		s *= max_w / s.x
	tr.custom_minimum_size = s
	tr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return tr
