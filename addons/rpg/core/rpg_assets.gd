@tool
class_name RPGAssets
extends RefCounted
## Finds assets by kind and name across every pack under res://assets/<pack>/<Folder>/.
## Works in the editor and in exported games: in an export DirAccess lists `x.png.import`,
## `x.wav.import` or `x.remap` instead of the source file, so those suffixes are stripped and the
## original path is returned (load() resolves the remap).
##
##   RPGAssets.find("charset", "hero")        -> "res://assets/starter/CharSet/hero.png"
##   RPGAssets.find("charset", "starter/hero") -> same, but only in pack "starter"
##   RPGAssets.list("sound")                   -> ["attack", "battle_start", ...]
##   RPGAssets.load_texture("faceset", "hero_face")
##   RPGAssets.load_audio("sound", "cursor")
##   RPGAssets.scan_packs()                    -> pack reports (see scan_packs)
##
## Names match case-insensitively, with or without extension. When two packs have the same name,
## the pack that sorts first wins (use "pack/name" to pick one).
##
## Music can also be MIDI (.mid / .midi, as RPG Maker 2000/2003 and XP use): the editor imports it
## as an AudioStreamWAV rendered with the project's sound bank (addons/rpg/import/midi), so it loads
## like any other stream, also in exported games. An OGG, WAV or MP3 with the same name wins.

const ASSETS_ROOT := "res://assets"
const IMAGE_EXTS: Array[String] = ["png"]
const AUDIO_EXTS: Array[String] = ["wav", "ogg", "mp3"]
## Music only: rendered to audio at import (see the class notes).
const MIDI_EXTS: Array[String] = ["mid", "midi"]
const MUSIC_EXTS: Array[String] = ["wav", "ogg", "mp3", "mid", "midi"]
const MIDI_RENDERER := "res://addons/rpg/import/midi/rpg_midi_renderer.gd"
## RPG Maker 2000/2003 folder names per kind (the default profile).
const FOLDERS := {
	"charset": "CharSet",
	"faceset": "FaceSet",
	"chipset": "ChipSet",
	"system": "System",
	"picture": "Picture",
	"music": "Music",
	"sound": "Sound",
	"battler": "Monster",
	"backdrop": "Backdrop",
	"panorama": "Panorama",
	"title": "Title",
	"gameover": "GameOver",
	## Side-view actor battlers: 2003 BattleCharSet sheets (144x384) and MV/MZ img/sv_actors
	## sheets (576x384) share one folder; the battle scene tells them apart by size.
	"sv_battler": "BattleCharSet",
}
const AUDIO_KINDS: Array[String] = ["music", "sound"]

## kind -> {lower_name -> path}, kind -> Array of display names (ordered)
static var _index: Dictionary = {}
static var _names: Dictionary = {}
static var _textures: Dictionary = {}
static var _audio: Dictionary = {}
static var root := ASSETS_ROOT
## pack -> profile id from its pack.json ("" when it declares none)
static var _pack_profiles: Dictionary = {}


## Drops every cached lookup and resource (call after packs are added or regenerated).
static func clear_cache() -> void:
	_index.clear()
	_names.clear()
	_textures.clear()
	_audio.clear()
	_pack_profiles.clear()


static func kinds() -> Array:
	return FOLDERS.keys()


static func folder_for(kind: String) -> String:
	return str(FOLDERS.get(kind, ""))


static func extensions_for(kind: String) -> Array[String]:
	if kind == "music":
		return MUSIC_EXTS
	return AUDIO_EXTS if AUDIO_KINDS.has(kind) else IMAGE_EXTS


## Pack folder names under the assets root, sorted.
static func packs() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append(sub)
	out.sort()
	return out


## Returns the res:// path of an asset, or "" if not found.
static func find(kind: String, asset_name: String) -> String:
	if asset_name == "":
		return ""
	if asset_name.begins_with("res://"):
		return asset_name if _exists(asset_name) else ""
	var pack := ""
	var n := asset_name
	if n.contains("/"):
		pack = n.get_slice("/", 0)
		n = n.substr(pack.length() + 1)
	var key := _strip_ext(n, kind).to_lower()
	if pack != "":
		var files := _pack_files(pack, kind)
		return files.get(key, "")
	_ensure(kind)
	return _index[kind].get(key, "")


## The asset profile ("rm2k", "vx", ...) declared in a pack's pack.json, or "".
static func pack_profile(pack: String) -> String:
	if not _pack_profiles.has(pack):
		var p := ""
		var path := root.path_join(pack).path_join("pack.json")
		if FileAccess.file_exists(path):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if j is Dictionary:
				p = str(j.get("profile", ""))
		_pack_profiles[pack] = p
	return _pack_profiles[pack]


## The profile to slice a sheet with: its pack's declared profile (so imported RPG Maker VX
## characters and faces keep their layout in a 2000-style project), else `fallback`.
static func sheet_profile(kind: String, asset_name: String, fallback: String) -> String:
	var path := find(kind, asset_name)
	var prefix := root + "/"
	if path.begins_with(prefix):
		var p := pack_profile(path.substr(prefix.length()).get_slice("/", 0))
		if p != "":
			return p
	return fallback


## Every asset name of a kind (first pack wins on duplicates), sorted case-insensitively.
static func list(kind: String) -> Array:
	_ensure(kind)
	return _names[kind].duplicate()


static func load_texture(kind: String, asset_name: String) -> Texture2D:
	var path := find(kind, asset_name)
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		# Not imported yet (e.g. a freshly generated file in a headless run).
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_textures[path] = tex
	return tex


## Image of an asset (decompressed, RGBA8), or null.
static func load_image(kind: String, asset_name: String) -> Image:
	var tex := load_texture(kind, asset_name)
	return texture_image(tex)


static func texture_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Loads an audio stream. Music WAVs are set to loop forward when they have no loop of their own.
static func load_audio(kind: String, asset_name: String) -> AudioStream:
	var path := find(kind, asset_name)
	if path == "":
		return null
	if _audio.has(path):
		return _audio[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null and FileAccess.file_exists(path):
		match path.get_extension().to_lower():
			"wav":
				s = AudioStreamWAV.load_from_file(path)
			"ogg":
				s = AudioStreamOggVorbis.load_from_file(path)
			"mp3":
				s = AudioStreamMP3.load_from_file(path)
			"mid", "midi":
				s = _render_midi(path)
	if s != null and kind == "music":
		_ensure_loop(s)
	if s != null:
		_audio[path] = s
	return s


## A MIDI file the editor has not imported yet (a headless run, a file copied a moment ago):
## rendered now with the project's sound bank. This takes seconds; imported files never get here.
static func _render_midi(path: String) -> AudioStream:
	if not ResourceLoader.exists(MIDI_RENDERER):
		return null
	push_warning("RPG assets: %s is not imported yet; rendering it now (open the project in the editor to import it once)." % path.get_file())
	var res: Dictionary = load(MIDI_RENDERER).render_file(path)
	if res.error != "":
		push_warning("RPG assets: %s: %s" % [path.get_file(), res.error])
	return res.stream


static func _ensure_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
		apply_loop_points(s)
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true


## RPG Maker loop points: OGG music carries LOOPSTART and LOOPLENGTH (in samples) as Vorbis
## comments. Sets loop_offset to LOOPSTART; when the loop ends clearly before the end of the file,
## its end (seconds) is kept as meta "rpg_loop_end" for the player (RPGAudio jumps back there).
## Returns {start, length} in samples, or {} for a file without the tags.
static func apply_loop_points(s: AudioStream) -> Dictionary:
	if not (s is AudioStreamOggVorbis):
		return {}
	var ogg := s as AudioStreamOggVorbis
	ogg.set_meta("rpg_loop_checked", true)
	var lp := ogg_loop_tags(ogg)
	if lp.is_empty():
		return {}
	var rate := 44100.0
	if ogg.packet_sequence != null and ogg.packet_sequence.sampling_rate > 0:
		rate = ogg.packet_sequence.sampling_rate
	var start := int(lp.start)
	ogg.loop_offset = start / rate
	var length := int(lp.get("length", 0))
	if length > 0:
		var end_s := (start + length) / rate
		if end_s < ogg.get_length() - 0.05:
			ogg.set_meta("rpg_loop_end", end_s)
		elif ogg.has_meta("rpg_loop_end"):
			ogg.remove_meta("rpg_loop_end")
	return lp


## {start, length} from an OGG stream's LOOPSTART / LOOPLENGTH comments ({} without them). Godot
## keeps the comments in `tags` (imported streams too); the comment header packet is read when not.
static func ogg_loop_tags(ogg: AudioStreamOggVorbis) -> Dictionary:
	var tags := {}
	var raw: Variant = ogg.get("tags")
	if raw is Dictionary:
		for k in raw:
			tags[str(k).to_lower()] = str(raw[k])
	if not tags.has("loopstart") and ogg.packet_sequence != null:
		for page in ogg.packet_sequence.packet_data.slice(0, 3):
			for pkt in page:
				var c := vorbis_comments(pkt)
				if not c.is_empty():
					tags = c
					break
	if not tags.has("loopstart") or not str(tags.loopstart).strip_edges().is_valid_int():
		return {}
	var out := {"start": maxi(0, str(tags.loopstart).strip_edges().to_int())}
	if str(tags.get("looplength", "")).strip_edges().is_valid_int():
		out["length"] = maxi(0, str(tags.looplength).strip_edges().to_int())
	return out


## Parses a Vorbis comment header packet (byte 3, "vorbis", vendor string, then KEY=value
## entries). Returns {lower-case key: value}, or {} when `packet` is not a comment header.
static func vorbis_comments(packet: PackedByteArray) -> Dictionary:
	var out := {}
	if packet.size() < 15 or packet[0] != 3 or packet.slice(1, 7).get_string_from_ascii() != "vorbis":
		return out
	var pos := 7
	var vendor := packet.decode_u32(pos)
	pos += 4 + vendor
	if pos + 4 > packet.size():
		return out
	var n := packet.decode_u32(pos)
	pos += 4
	for i in n:
		if pos + 4 > packet.size():
			break
		var l := packet.decode_u32(pos)
		pos += 4
		if pos + l > packet.size():
			break
		var entry := packet.slice(pos, pos + l).get_string_from_utf8()
		pos += l
		var eq := entry.find("=")
		if eq > 0:
			out[entry.substr(0, eq).to_lower()] = entry.substr(eq + 1)
	return out


# --- index -------------------------------------------------------------------------------------

static func _ensure(kind: String) -> void:
	if _index.has(kind):
		return
	var map := {}
	var names := []
	for pack in packs():
		var files := _pack_files(pack, kind)
		for key in files:
			if not map.has(key):
				map[key] = files[key]
				names.append(str(files[key]).get_file().get_basename())
	names.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	_index[kind] = map
	_names[kind] = names


## {lower_name -> res path} for one pack and kind.
static func _pack_files(pack: String, kind: String) -> Dictionary:
	var out := {}
	var folder := folder_for(kind)
	if folder == "":
		return out
	var pack_path := root.path_join(pack)
	var sub := _find_dir_ci(pack_path, folder)
	if sub == "":
		return out
	var exts := extensions_for(kind)
	var d := DirAccess.open(sub)
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	for f in files:
		var fn := _source_name(f)
		var ext := fn.get_extension().to_lower()
		if not exts.has(ext):
			continue
		var key := fn.get_basename().to_lower()
		# A rendered OGG / WAV / MP3 next to a MIDI file of the same name wins over the MIDI.
		if not out.has(key) or (MIDI_EXTS.has(str(out[key]).get_extension().to_lower()) and not MIDI_EXTS.has(ext)):
			out[key] = sub.path_join(fn)
	return out


## Strips export suffixes: "a.png.import" -> "a.png", "a.png.remap" -> "a.png".
static func _source_name(f: String) -> String:
	if f.ends_with(".import"):
		return f.trim_suffix(".import")
	if f.ends_with(".remap"):
		return f.trim_suffix(".remap")
	return f


## Case-insensitive sub-directory lookup; returns the full path or "".
static func _find_dir_ci(parent: String, child: String) -> String:
	var d := DirAccess.open(parent)
	if d == null:
		return ""
	var want := child.to_lower()
	for sub in d.get_directories():
		if sub.to_lower() == want:
			return parent.path_join(sub)
	return ""


static func _strip_ext(n: String, kind: String) -> String:
	var ext := n.get_extension().to_lower()
	if ext != "" and (extensions_for(kind).has(ext) or ext == "bmp"):
		return n.get_basename()
	return n


static func _exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


# --- pack scanning (importer rules: report candidates, never guess) ----------------------------

## Scans every pack folder and returns one report per pack:
##   {path, name, manifest (Dictionary or null), license_verified: bool, license: String,
##    profile_candidates: Array[String], conflicts: Array[String], warnings: Array[String]}
## profile_candidates comes from folder names, image sizes and pack.json. When more than one
## profile fits, or the manifest disagrees with the evidence, every candidate is reported and the
## conflict is listed: the caller asks the user instead of guessing.
static func scan_packs() -> Array:
	var out := []
	for pack in packs():
		out.append(scan_pack(root.path_join(pack)))
	return out


static func scan_pack(pack_path: String) -> Dictionary:
	var report := {
		"path": pack_path,
		"name": pack_path.get_file(),
		"manifest": null,
		"license_verified": false,
		"license": "",
		"profile_candidates": [],
		"conflicts": [],
		"warnings": [],
	}
	var manifest_path := pack_path.path_join("pack.json")
	if FileAccess.file_exists(manifest_path):
		var r := RPGJson.parse_file(manifest_path)
		if r.ok and r.data is Dictionary:
			report.manifest = r.data
			report.name = str(r.data.get("name", report.name))
			report.license = str(r.data.get("license", ""))
			report.license_verified = report.license != ""
			if report.license == "":
				report.warnings.append("pack.json has no license: marked \"license unverified\".")
		else:
			report.warnings.append("pack.json is not valid JSON: %s" % r.error)
	else:
		report.warnings.append("No pack.json: license unverified.")

	var evidence := _profile_evidence(pack_path)
	var candidates: Array = []
	for p in evidence:
		if evidence[p].size() > 0:
			candidates.append(p)
	var declared := ""
	if report.manifest is Dictionary:
		declared = str(report.manifest.get("profile", ""))
	if declared != "":
		if candidates.is_empty():
			candidates.append(declared)
		elif not candidates.has(declared):
			report.conflicts.append("pack.json declares profile '%s' but the files look like %s: choose one." % [declared, ", ".join(candidates)])
			candidates.push_front(declared)
		elif candidates.size() > 1:
			candidates.erase(declared)
			report.conflicts.append("Files also match %s: confirm the declared profile '%s'." % [", ".join(candidates), declared])
			candidates.push_front(declared)
	elif candidates.size() > 1:
		report.conflicts.append("Several profiles match (%s): choose one." % ", ".join(candidates))
	if candidates.is_empty():
		report.warnings.append("No known profile matches this pack.")
	report.profile_candidates = candidates
	for p in evidence:
		for e in evidence[p]:
			if str(e).begins_with("!"):
				report.warnings.append(str(e).substr(1))
	return report


## profile -> Array of evidence strings ("!" prefix = mismatch warning, not evidence).
static func _profile_evidence(pack_path: String) -> Dictionary:
	var ev := {"rm2k": [], "xp": [], "vx": [], "mv": []}
	# RPG Maker 2000/2003: ChipSet / CharSet / FaceSet folders with fixed sheet sizes.
	var chip := _find_dir_ci(pack_path, "ChipSet")
	if chip != "":
		for f in _images_in(chip):
			var s := _image_size(f)
			if s == Vector2i(480, 256):
				ev.rm2k.append("ChipSet %s is 480x256" % f.get_file())
			elif s != Vector2i.ZERO:
				ev.rm2k.append("!ChipSet %s is %dx%d, expected 480x256" % [f.get_file(), s.x, s.y])
	var chars := _find_dir_ci(pack_path, "CharSet")
	if chars != "":
		for f in _images_in(chars):
			var s := _image_size(f)
			if s == Vector2i(288, 256) or s == Vector2i(72, 128) or s == Vector2i(24, 32):
				ev.rm2k.append("CharSet %s fits the 2000/2003 layout" % f.get_file())
	var faces := _find_dir_ci(pack_path, "FaceSet")
	if faces != "":
		for f in _images_in(faces):
			if _image_size(f) == Vector2i(192, 192):
				ev.rm2k.append("FaceSet %s is 192x192" % f.get_file())
	# Later profiles keep assets under Graphics/ (XP, VX) or img/ (MV/MZ).
	var graphics := _find_dir_ci(pack_path, "Graphics")
	var tilesets := ""
	if graphics != "":
		tilesets = _find_dir_ci(graphics, "Tilesets")
		if _find_dir_ci(graphics, "Autotiles") != "":
			ev.xp.append("Graphics/Autotiles folder")
	var img_dir := _find_dir_ci(pack_path, "img")
	if img_dir != "":
		var t := _find_dir_ci(img_dir, "tilesets")
		if t != "":
			tilesets = t
	if tilesets == "":
		tilesets = _find_dir_ci(pack_path, "Tilesets")
	if tilesets != "":
		for f in _images_in(tilesets):
			var s := _image_size(f)
			var base := f.get_file().get_basename()
			var is_vx_name := base.contains("_A1") or base.contains("_A2") or base.contains("_A5") or base.ends_with("_B") or base.begins_with("A") and base.length() <= 3
			if s.x == 256:
				ev.xp.append("Tileset %s is 256 px wide" % f.get_file())
			if s == Vector2i(512, 384) or s == Vector2i(512, 512) or (is_vx_name and s.x == 512):
				ev.vx.append("Tileset %s matches VX sizes" % f.get_file())
			if s == Vector2i(768, 576) or s == Vector2i(768, 768) or (is_vx_name and s.x == 768):
				ev.mv.append("Tileset %s matches MV/MZ sizes" % f.get_file())
	return ev


static func _images_in(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		var fn := _source_name(f)
		if fn.get_extension().to_lower() in ["png", "bmp"]:
			var p := dir_path.path_join(fn)
			if not out.has(p):
				out.append(p)
	out.sort()
	return out


static func _image_size(path: String) -> Vector2i:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return Vector2i(tex.get_width(), tex.get_height())
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return img.get_size()
	return Vector2i.ZERO
