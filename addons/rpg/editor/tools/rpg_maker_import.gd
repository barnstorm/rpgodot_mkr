@tool
extends RefCounted
## Imports a maker's own RPG Maker art and audio from their disk: an RTP install or a project of
## RPG Maker 2000/2003, XP, VX / VX Ace or MV / MZ. Nothing is bundled or downloaded; files are
## copied from the folder the maker picks. Used by Tools > Resources > "Import RPG Maker folder...".
## Preloaded by path (no class_name):
##   const RMImport := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")
##
##   var p := RMImport.plan("C:/.../RPGVXAce/RTP", "vxace_rtp")   # nothing is written
##   # p = {profile, base, pack_id, files: [{src, dst, kind, folder, exists, convert, key_index0}],
##   #      skipped: [{src, reason}], tilesets: [record], warnings: [], evidence: []}
##   var r := RMImport.apply(p)                                     # copy + pack.json + tilesets.json
##
## Layout detection (detect):
##   rm2k  ChipSet / CharSet / FaceSet / Monster folders at the top (2000/2003 RTP or project)
##   mv    an img/ folder (MV and MZ)
##   xp    Graphics/ with Autotiles or Windowskins, or 256 px wide tilesets
##   vx    Graphics/ otherwise (VX and VX Ace; A1-A5/B-E tilesets, Battlebacks1, Faces)
## Picking the Graphics or img folder itself works too: its parent is used, so Audio comes along.
##
## Files go to <asset_root>/<pack_id>/<RPG Kit folder> (RPGAssets.FOLDERS). Tile sheets of the
## later profiles go to Tilesets/ (XP autotiles to Autotiles/); records point at them by res:// path.
## BMP and JPG images are converted to PNG. VX / MV Graphics/System/GameOver.png goes to GameOver/.
## 2000/2003 images whose palette colour 0 is transparent in RPG Maker (CharSet, ChipSet, FaceSet,
## Monster, System, Picture) get that transparency written into the copy (a PNG tRNS chunk; a
## converted BMP keys the colour of palette entry 0), so they are drawn without a background box.
## Side-view actor battlers (2003 BattleCharSet, MV / MZ img/sv_actors) are copied as kind
## "sv_battler" into BattleCharSet/ (2003 sheets keyed like the other 2000/2003 images).
## Folders RPG Kit has no place for (battle animations, side-view enemies, Battlebacks2, ...) and
## unsupported formats (XYZ, encrypted files) are listed in `skipped` with the reason.
## MIDI music (.mid / .midi) is copied like other music: Godot imports it as audio rendered with
## the project's sound bank (Tools > Resources > MIDI sound bank). Each file is read first
## (RPGMidiFile); one that cannot be read is skipped, with the reason.
## Tileset records (rpg/database/tilesets.json) use the shapes the builder reads:
##   rm2k {profile: "rm2k", sheet}            one per ChipSet file
##   xp   {profile: "xp", sheet, autotiles}   a project: one per tileset of Data/Tilesets.rxdata
##                                            (RPGMarshal), with its name, 7 autotiles and its
##                                            passability as tile settings. An RTP (no Data
##                                            folder): one per tileset file; autotiles only where
##                                            the RTP file names clearly pair them (XP_RTP_CODES),
##                                            reported as guesses
##   vx/mv {profile, sheets: {a1..e}}         one per name prefix: Outside_A1..Outside_E -> "outside"

const LICENSE := "RPG Maker RTP / user's own licence — check the RPG Maker EULA before distributing"
const IMAGE_EXT := ["png", "bmp", "jpg", "jpeg"]
const AUDIO_EXT := ["wav", "ogg", "mp3"]
## Folders the profiles do not list but that hold usable files (audio, side-view battlers).
const EXTRA_FOLDERS := {
	"rm2k": {"BattleCharSet": "sv_battler"},
	"xp": {"Audio/BGS": "sound", "Audio/ME": "music"},
	"vx": {"Audio/BGS": "sound", "Audio/ME": "music"},
	"mv": {"audio/bgs": "sound", "audio/me": "music", "img/sv_actors": "sv_battler"},
}
## Kinds without an RPGAssets folder (tile sheets referenced only from tileset records).
const SHEET_FOLDERS := {"tileset": "Tilesets", "autotile": "Autotiles"}
## 2000/2003 kinds RPG Maker draws with palette colour 0 transparent (backdrops, panoramas,
## titles and game over screens are opaque).
const KEYED_2K_KINDS := ["charset", "chipset", "faceset", "battler", "system", "picture", "sv_battler"]
## Where unlisted folders are looked for, and what the known ones hold (for the skip reason).
const ASSET_ROOTS := {"rm2k": [""], "xp": ["Graphics", "Audio"], "vx": ["Graphics", "Audio"], "mv": ["img", "audio"]}
const ANIMATION_HINT := "battle animation sheets are not imported (RPG Kit has no folder for them; to use one in Database > Animations, copy it into the pack's Picture folder and set its frame size)"
const KNOWN_FOLDERS := {
	"battle": ANIMATION_HINT,
	"graphics/animations": ANIMATION_HINT,
	"img/animations": ANIMATION_HINT,
	"battleweapon": "2003 battle weapon graphics are not imported (RPG Kit battles show enemies only)",
	"system2": "2003 battle system graphics are not imported (RPG Kit draws its own battle gauges)",
	"frame": "2003 screen frames are not imported",
	"img/sv_enemies": "side-view enemies are not imported (use the front-view img/enemies)",
	"graphics/battlebacks2": "the upper half of battle backgrounds is not imported (only Battlebacks1 is used)",
	"img/battlebacks2": "the upper half of battle backgrounds is not imported (only battlebacks1 is used)",
	"graphics/titles2": "title frames are not imported (only Titles1 is used)",
	"img/titles2": "title frames are not imported (only titles1 is used)",
	"graphics/icons": "icons are not imported (RPG Kit has no icon folder)",
	"graphics/fogs": "fogs are not imported (RPG Kit has no fog layer)",
	"graphics/transitions": "transition graphics are not imported",
}
const MIDI_EXT := ["mid", "midi"]
## Skip reason of a MIDI file that cannot be read (the parser's message is in the entry's "detail").
const MIDI_REASON := "not a readable MIDI file (it may be damaged; open it in a MIDI editor and save it again)"
const MIDI_SOUND_REASON := "MIDI is used only for music: convert this sound effect to WAV or OGG"
const UNSUPPORTED := {
	"xyz": "XYZ images are not supported: convert them to PNG with an XYZ-to-PNG converter, then import the PNG files",
	"mid": MIDI_SOUND_REASON,
	"midi": MIDI_SOUND_REASON,
	"m4a": "M4A audio is not supported by Godot: use the OGG copy",
	"rpgmvp": "encrypted MV/MZ image",
	"rpgmvo": "encrypted MV/MZ audio",
	"png_": "encrypted MZ image",
	"ogg_": "encrypted MZ audio",
	"wma": "WMA audio is not supported: convert it to OGG",
}


# --- detection -----------------------------------------------------------------------------------

## {profile ("" when unknown), base, evidence: [], warnings: []}.
static func detect(folder: String) -> Dictionary:
	var base := folder.replace("\\", "/").trim_suffix("/")
	var leaf := base.get_file().to_lower()
	if leaf == "graphics" or leaf == "img":
		base = base.get_base_dir()
	var out := {"profile": "", "base": base, "evidence": [], "warnings": []}
	if DirAccess.open(base) == null:
		out.warnings.append("Cannot open %s." % folder)
		return out
	for f in ["ChipSet", "CharSet", "FaceSet", "Monster"]:
		if _dir_ci(base, f) != "":
			out.evidence.append("%s folder" % f)
	if not out.evidence.is_empty():
		out.profile = "rm2k"
		return out
	if _dir_ci(base, "img") != "":
		out.profile = "mv"
		out.evidence.append("img folder (MV / MZ)")
		return out
	var g := _dir_ci(base, "Graphics")
	if g == "":
		out.warnings.append("No RPG Maker layout found: expected ChipSet/CharSet folders (2000/2003), Graphics/ (XP, VX, VX Ace) or img/ (MV, MZ).")
		return out
	for f in ["Autotiles", "Windowskins", "Panoramas"]:
		if _dir_ci(g, f) != "":
			out.evidence.append("Graphics/%s folder (XP)" % f)
	var tiles := _dir_ci(g, "Tilesets")
	var xp_wide := false
	var vx_named := false
	if tiles != "":
		for f in _files(tiles, IMAGE_EXT):
			if _sheet_slot(f.get_file().get_basename()) != "":
				vx_named = true
			elif _image_size(f).x == 256:
				xp_wide = true
	if xp_wide:
		out.evidence.append("256 px wide tilesets (XP)")
	if not out.evidence.is_empty() and not vx_named:
		out.profile = "xp"
		return out
	out.profile = "vx"
	out.evidence.append("Graphics folder" + (" with A1-E tilesets" if vx_named else ""))
	if not vx_named and tiles == "":
		out.warnings.append("No tilesets found; assuming VX / VX Ace.")
	return out


# --- plan ----------------------------------------------------------------------------------------

## A pack id from a folder name: "RPGVXAce RTP" -> "rpgvxace_rtp".
static func suggest_pack_id(folder: String) -> String:
	var d := detect(folder)
	var n := str(d.base).get_file()
	if n.to_lower() == "rtp":
		n = str(d.base).get_base_dir().get_file() + "_rtp"
	var id := ""
	for c in n.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			id += c
		elif not id.ends_with("_") and id != "":
			id += "_"
	id = id.trim_suffix("_")
	if id == "" or not (id[0] >= "a" and id[0] <= "z"):
		id = "rm_" + id
	return id.trim_suffix("_")


## What an import would do. Nothing is written.
static func plan(folder: String, pack_id: String, asset_root := "res://assets", rpg_root := "res://rpg") -> Dictionary:
	var d := detect(folder)
	var p := {"profile": d.profile, "base": d.base, "pack_id": pack_id, "asset_root": asset_root, "rpg_root": rpg_root,
		"files": [], "skipped": [], "tilesets": [], "warnings": d.warnings.duplicate(), "evidence": d.evidence}
	if d.profile == "":
		return p
	if not RPGIds.is_valid(pack_id):
		p.warnings.append("'%s' is not a valid pack name (lowercase letters, digits and _; starts with a letter)." % pack_id)
		return p
	var prof := RPGProfile.load_profile(str(d.profile))
	var sources := {}
	if prof != null:
		for kind in prof.folders:
			sources[str(prof.folders[kind])] = str(kind)
	var extra: Dictionary = EXTRA_FOLDERS.get(d.profile, {})
	for rel in extra:
		sources[rel] = extra[rel]
	var targets := {}
	var rels: Array = sources.keys()
	rels.sort()
	for rel in rels:
		var kind: String = sources[rel]
		var dir := _resolve_ci(str(d.base), rel)
		if dir == "":
			continue
		var folder_name := target_folder(kind)
		if folder_name == "":
			continue
		var exts: Array = AUDIO_EXT if RPGAssets.AUDIO_KINDS.has(kind) else IMAGE_EXT
		if kind == "music":
			exts = AUDIO_EXT + MIDI_EXT
		var d2 := DirAccess.open(dir)
		var names := Array(d2.get_files()) if d2 != null else []
		names.sort()
		for n in names:
			var src := dir.path_join(n)
			var ext := str(n).get_extension().to_lower()
			if not exts.has(ext):
				if UNSUPPORTED.has(ext):
					p.skipped.append({"src": src, "reason": UNSUPPORTED[ext]})
				elif not (ext in ["db", "ini", "txt", "json"]):
					p.skipped.append({"src": src, "reason": "not a %s file" % ("PNG, BMP or JPG image" if exts == IMAGE_EXT else "sound (OGG, WAV, MP3%s)" % (", MIDI" if kind == "music" else ""))})
				continue
			if MIDI_EXT.has(ext):
				var midi := RPGMidiFile.load_file(src)
				if midi.error != "":
					p.skipped.append({"src": src, "reason": MIDI_REASON, "detail": midi.error})
					continue
			var file_kind := kind
			var file_folder := folder_name
			# VX / MV keep the game over screen with the system graphics; it is no window skin.
			if kind == "system" and d.profile in ["vx", "mv"] and str(n).get_basename().to_lower() == "gameover":
				file_kind = "gameover"
				file_folder = target_folder("gameover")
			# VX / MV keep icons, balloons, damage digits and the like next to the window skin. Only
			# Window* images are window skins; the rest would only clutter the Window style list.
			elif kind == "system" and d.profile in ["vx", "mv"] and not str(n).get_basename().to_lower().begins_with("window"):
				p.skipped.append({"src": src, "reason": "system graphic the kit does not use (only Window images are window skins)"})
				continue
			var to_png := exts == IMAGE_EXT and ext != "png"
			var out_name := str(n).get_basename() + ".png" if to_png else str(n)
			var dst := asset_root.path_join(pack_id).path_join(file_folder).path_join(out_name)
			if targets.has(dst.to_lower()):
				p.skipped.append({"src": src, "reason": "same name as %s" % str(targets[dst.to_lower()]).get_file()})
				continue
			targets[dst.to_lower()] = src
			p.files.append({"src": src, "dst": dst, "kind": file_kind, "folder": file_folder, "exists": FileAccess.file_exists(dst),
				"convert": to_png, "key_index0": d.profile == "rm2k" and KEYED_2K_KINDS.has(file_kind)})
	_plan_unlisted_folders(p, sources.keys())
	if p.files.is_empty():
		p.warnings.append("No images or sounds found in the expected folders.")
	_plan_music_summary(p)
	_plan_tilesets(p, prof)
	_plan_window_skin_hint(p, rpg_root)
	var proj: Dictionary = RPGJson.load_or(rpg_root.path_join("profile.json"), {})
	var proj_profile := str(proj.get("profile", "rm2k"))
	if proj_profile != str(d.profile):
		p.warnings.append("Your project uses the '%s' profile but these files are '%s'. Tilesets keep their own profile; characters, faces and windows are drawn the project's way." % [proj_profile, d.profile])
	return p


## Lists the files of RPG Maker folders the import does not read (battle animations, side-view
## battlers, ...) in p.skipped, so nothing is left out silently.
static func _plan_unlisted_folders(p: Dictionary, read_rels: Array) -> void:
	var read := {}
	for rel in read_rels:
		read[str(rel).to_lower()] = true
	for root_rel in ASSET_ROOTS.get(str(p.profile), []):
		var root := str(p.base) if root_rel == "" else _resolve_ci(str(p.base), root_rel)
		var dr := DirAccess.open(root) if root != "" else null
		if dr == null:
			continue
		var subs := Array(dr.get_directories())
		subs.sort()
		for sub in subs:
			var rel := str(sub) if root_rel == "" else "%s/%s" % [root_rel, sub]
			if read.has(rel.to_lower()) or str(sub).begins_with("$") or str(sub).begins_with("."):
				continue
			var reason := str(KNOWN_FOLDERS.get(rel.to_lower(), ""))
			if reason == "":
				reason = "%s is not imported: RPG Kit has no folder for it" % rel
			for f in _files(root.path_join(sub), IMAGE_EXT + AUDIO_EXT + ["mid", "midi", "xyz", "avi", "mpg", "webm", "ogv"]):
				p.skipped.append({"src": f, "reason": reason})


## One note on the MIDI music (2000/2003 and XP RTPs are mostly MIDI): it is rendered with the
## project's sound bank when Godot imports it; unreadable files are counted.
static func _plan_music_summary(p: Dictionary) -> void:
	var midi := 0
	var music := 0
	for f in p.files:
		if str(f.kind) == "music":
			music += 1
			if MIDI_EXT.has(str(f.src).get_extension().to_lower()):
				midi += 1
	var broken := 0
	for s in p.skipped:
		if str(s.reason) == MIDI_REASON:
			broken += 1
	if midi > 0:
		p.warnings.append("%d of %d music file(s) are MIDI: Godot renders them to audio when it imports them, with the project's sound bank (%s). To change the bank, use Tools > Resources > MIDI sound bank; the music is then rendered again." % [midi, music, sound_bank_label()])
	if broken > 0:
		p.warnings.append("%d MIDI file(s) cannot be read and are skipped (see the skipped list)." % broken)


## The bank MIDI is rendered with: the project setting, or the default (gm.dls on Windows, else the
## built-in instruments).
static func sound_bank_label() -> String:
	var path := RPGMidiRenderer.bank_path_for("")
	return "built-in instruments" if path == "builtin" else path.get_file()


## Later makers name their window skin differently from the project's choice ("system").
static func _plan_window_skin_hint(p: Dictionary, rpg_root: String) -> void:
	if str(p.profile) == "rm2k":
		return
	var skins := []
	for f in p.files:
		if str(f.kind) != "system":
			continue
		var n := str(f.dst).get_file().get_basename()
		if str(p.profile) == "xp" or n.to_lower() == "window":
			skins.append(n)
	if skins.is_empty():
		return
	var sys: Dictionary = RPGJson.load_or(rpg_root.path_join("database/system.json"), {}).get("system", {})
	var current := str(sys.get("window_skin", "system"))
	for n in skins:
		if n.to_lower() == current.to_lower() or ("%s/%s" % [p.pack_id, n]).to_lower() == current.to_lower():
			return
	p.warnings.append("Window skin: to use %s, pick it in Database > System (Window style); the project uses '%s'." % [" or ".join(PackedStringArray(skins.slice(0, 3))), current])


## RPG Kit folder for an asset kind.
static func target_folder(kind: String) -> String:
	if SHEET_FOLDERS.has(kind):
		return SHEET_FOLDERS[kind]
	return RPGAssets.folder_for(kind)


static func _plan_tilesets(p: Dictionary, prof: RPGProfile) -> void:
	var existing := {}
	for r in RPGJson.load_or(str(p.rpg_root).path_join("database/tilesets.json"), {}).get("records", []):
		if r is Dictionary:
			existing[str(r.get("id", ""))] = true
			existing["sig:" + signature(r)] = str(r.get("id", ""))
	var profile_id := str(p.profile)
	if profile_id == "mv" and _plan_mv_tilesets(p, existing):
		return
	if profile_id == "xp" and _plan_xp_tilesets(p, existing):
		return
	var first_new: int = p.tilesets.size()
	var groups := {}
	var order := []
	for f in p.files:
		var kind := str(f.kind)
		var base := str(f.dst).get_file().get_basename()
		if profile_id == "rm2k" and kind == "chipset":
			var w := _check_size(str(f.src), RPGChipset2k.SHEET_SIZE)
			_add_record(p, existing, base, {"profile": "rm2k", "sheet": f.dst}, w)
		elif profile_id == "xp" and kind == "tileset":
			_add_record(p, existing, base, {"profile": "xp", "sheet": f.dst, "autotiles": []},
				"" if _image_size(str(f.src)).x == 256 else "%s is not 256 px wide" % str(f.src).get_file())
		elif (profile_id == "vx" or profile_id == "mv") and kind == "tileset":
			var slot := _sheet_slot(base)
			if slot == "":
				p.warnings.append("%s is not named like an A1-A5 or B-E sheet; copied, but in no tileset." % str(f.src).get_file())
				continue
			var prefix := base.substr(0, base.length() - slot.length()).trim_suffix("_").trim_suffix("-").strip_edges()
			if prefix == "":
				prefix = str(p.pack_id)
			if not groups.has(prefix):
				groups[prefix] = {}
				order.append(prefix)
			groups[prefix][slot.to_lower()] = f
	for prefix in order:
		var sheets := {}
		var notes := []
		for slot in groups[prefix]:
			var f: Dictionary = groups[prefix][slot]
			sheets[slot] = f.dst
			var want := RPGTilesheetVX.sheet_size(prof, slot, prof.tile_size if prof != null else 32)
			var s := _image_size(str(f.src))
			if s != Vector2i.ZERO and s != want:
				notes.append("%s is %dx%d, expected %dx%d" % [str(f.src).get_file(), s.x, s.y, want.x, want.y])
		_add_record(p, existing, prefix, {"profile": profile_id, "sheets": sheets}, "; ".join(PackedStringArray(notes)))
	if profile_id == "xp":
		_guess_xp_autotiles(p, first_new)


## RPG Maker XP RTP autotile name codes ("001-G_Water01" -> "g") whose tilesets the file names
## name clearly: the code is the start of the tileset name ("001-Grassland01", "021-SnowTown01").
## Other RTP codes (G2, Sa, T, St, B, CE, CF, CI, CW) and the uncoded autotiles (Ocean, Tree,
## Wall, ...) do not say which tilesets they belong to, so they are left for the maker to pick.
const XP_RTP_CODES := {"g": ["grassland"], "sn": ["snowfield", "snowtown"]}


## RTP fallback (no Data/Tilesets.rxdata): fills the autotiles of the XP records added since
## `first` where XP_RTP_CODES pairs them by file name, and says which were guessed and which
## tilesets have none.
static func _guess_xp_autotiles(p: Dictionary, first: int) -> void:
	var by_code := {}
	var code_re := RegEx.create_from_string("^\\d+-([A-Za-z][A-Za-z0-9]*)_")
	var autos := []
	for f in p.files:
		if str(f.kind) == "autotile":
			autos.append(str(f.dst))
	autos.sort()
	for dst in autos:
		var m := code_re.search(str(dst).get_file().get_basename())
		if m != null:
			var code := m.get_string(1).to_lower()
			if not by_code.has(code):
				by_code[code] = []
			by_code[code].append(dst)
	var stem_re := RegEx.create_from_string("^\\d+-([A-Za-z]+?)\\d*$")
	var guessed := []
	var without := []
	for i in range(first, p.tilesets.size()):
		var rec: Dictionary = p.tilesets[i].record
		if str(rec.get("profile", "")) != "xp" or not (rec.get("autotiles", []) as Array).is_empty():
			continue
		var sm := stem_re.search(str(rec.get("sheet", "")).get_file().get_basename())
		var stem := sm.get_string(1).to_lower() if sm != null else ""
		var picked := []
		for code in XP_RTP_CODES:
			if not (stem in XP_RTP_CODES[code]) or not by_code.has(code):
				continue
			var all: Array = by_code[code]
			picked = all.slice(0, RPGTilesheetXP.AUTOTILE_SLOTS)
			var note := "%s <- %s" % [rec.id, ", ".join(PackedStringArray(picked.map(func(x): return str(x).get_file().get_basename())))]
			if all.size() > picked.size():
				note += " (%s left out: 7 slots)" % ", ".join(PackedStringArray(all.slice(picked.size()).map(func(x): return str(x).get_file().get_basename())))
			guessed.append(note)
		if picked.is_empty():
			without.append(str(rec.id))
		else:
			rec["autotiles"] = picked
	if not guessed.is_empty():
		p.warnings.append("XP autotiles guessed from the RTP file names, since there is no Data/Tilesets.rxdata here: %s. Check them in Database > Tilesets." % "; ".join(PackedStringArray(guessed)))
	if not without.is_empty():
		var shown := ", ".join(PackedStringArray(without.slice(0, 8))) + ("" if without.size() <= 8 else " and %d more" % (without.size() - 8))
		p.warnings.append("%d XP tileset(s) are added without autotiles: %s. RPG Maker XP keeps each tileset's autotiles in Data/Tilesets.rxdata, which this folder does not have, and the file names do not say which belong together. Pick up to 7 per tileset in Database > Tilesets (the files are in %s/Autotiles)." % [without.size(), shown, str(p.pack_id)])


## XP project: one record per RPG::Tileset of Data/Tilesets.rxdata (Ruby Marshal), with its name,
## tileset file, autotile files and passability. Returns false when there is no such file (an
## RTP) or it cannot be read (with a warning); the caller then makes one record per file.
static func _plan_xp_tilesets(p: Dictionary, existing: Dictionary) -> bool:
	var data_dir := _resolve_ci(str(p.base), "Data")
	var path := ""
	var dd := DirAccess.open(data_dir) if data_dir != "" else null
	if dd != null:
		for f in dd.get_files():
			if f.to_lower() == "tilesets.rxdata":
				path = data_dir.path_join(f)
	if path == "":
		return false
	var r := RPGMarshal.parse_file(path)
	if r.error != "" or not (r.value is Array):
		p.warnings.append("Data/Tilesets.rxdata could not be read (%s); tilesets are made one per file instead." % (r.error if r.error != "" else "not a list of tilesets"))
		return false
	var sheets := {}
	var autos := {}
	for f in p.files:
		var base := str(f.dst).get_file().get_basename().to_lower()
		if str(f.kind) == "tileset":
			sheets[base] = f
		elif str(f.kind) == "autotile":
			autos[base] = str(f.dst)
	for e in r.value:
		if RPGMarshal.class_of(e) != "RPG::Tileset":
			continue
		var file := str(e.get("@tileset_name", ""))
		var label := str(e.get("@name", "")).strip_edges()
		if file == "":
			continue
		if label == "":
			label = file
		if not sheets.has(file.to_lower()):
			p.warnings.append("Tileset '%s' uses %s, which is not in Graphics/Tilesets; not added." % [label, file])
			continue
		var autotiles := []
		var missing := []
		var names: Variant = e.get("@autotile_names", [])
		for i in RPGTilesheetXP.AUTOTILE_SLOTS:
			var n := ""
			if names is Array and i < (names as Array).size() and names[i] != null:
				n = str(names[i])
			if n == "":
				autotiles.append("")
			elif autos.has(n.to_lower()):
				autotiles.append(autos[n.to_lower()])
			else:
				autotiles.append("")
				missing.append(n)
		while not autotiles.is_empty() and autotiles[-1] == "":
			autotiles.pop_back()
		var before: int = p.tilesets.size()
		_add_record(p, existing, label, {"profile": "xp", "sheet": sheets[file.to_lower()].dst, "autotiles": autotiles},
			"" if missing.is_empty() else "autotile(s) not in Graphics/Autotiles: %s" % ", ".join(PackedStringArray(missing)), file)
		if p.tilesets.size() > before:
			p.tilesets[-1]["tiles"] = xp_tiles(e)
	return true


## RPG Maker XP tile settings of one RPG::Tileset -> RPG Kit tile settings {tile_key: {passage,
## flags, terrain}}. XP tile ids: autotile s (0..6) at 48 * (s + 1) (one setting for its 48
## shapes), tileset tile i at 384 + i. @passages bits 0x1/0x2/0x4/0x8 block down/left/right/up,
## 0x40 bush, 0x80 counter; @priorities > 0 draws above characters (the kit's star flag, given
## only to tiles that block nothing, since star tiles never block); @terrain_tags 0..7. tile_0
## (the eraser) keeps its default.
static func xp_tiles(e: Dictionary) -> Dictionary:
	var pas := RPGMarshal.table(e.get("@passages"))
	if pas.is_empty():
		return {}
	var pri := RPGMarshal.table(e.get("@priorities"))
	var ter := RPGMarshal.table(e.get("@terrain_tags"))
	var values: PackedInt32Array = pas.values
	var ids := {}
	for s in RPGTilesheetXP.AUTOTILE_SLOTS:
		ids["autotile_%d" % s] = 48 * (s + 1)
	for i in range(1, maxi(0, values.size() - 384)):
		ids["tile_%d" % i] = 384 + i
	var out := {}
	for key in ids:
		var id: int = ids[key]
		if id >= values.size():
			continue
		var f := values[id]
		var passage := (~f) & 15
		var flags := 0
		if f & 0x40:
			flags |= RPGMovement.FLAG_BUSH
		if f & 0x80:
			flags |= RPGMovement.FLAG_COUNTER
		if not pri.is_empty() and id < (pri.values as PackedInt32Array).size() and int(pri.values[id]) > 0 and passage == 15:
			flags |= RPGMovement.FLAG_STAR
		var terrain := 0
		if not ter.is_empty() and id < (ter.values as PackedInt32Array).size():
			terrain = int(ter.values[id]) & 7
		out[key] = {"passage": passage, "flags": flags, "terrain": terrain}
	return out


## `id_hint` names the id when the label has no Latin letters (MV's Japanese tileset names).
static func _add_record(p: Dictionary, existing: Dictionary, label: String, fields: Dictionary, warning: String, id_hint := "") -> void:
	var sig := signature(fields)
	if existing.has("sig:" + sig):
		p.warnings.append("Tileset '%s' is already in tilesets.json as '%s'; not added again." % [label, existing["sig:" + sig]])
		return
	var base_id := _id_from(label)
	if id_hint != "" and RegEx.create_from_string("[A-Za-z]").search(label) == null:
		base_id = _id_from(id_hint)
	var id := _unique_id(base_id, existing)
	existing[id] = true
	var rec := {"id": id, "name": label.replace("_", " ").capitalize() if label == label.to_lower() else label,
		"notes": "Imported from an RPG Maker folder (pack '%s')." % p.pack_id, "custom": {}}
	rec.merge(fields)
	p.tilesets.append({"record": rec, "warning": warning})
	if warning != "":
		p.warnings.append("Tileset '%s': %s." % [id, warning])


static func _id_from(label: String) -> String:
	var id := ""
	for c in label.to_snake_case().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			id += c
		elif not id.ends_with("_"):
			id += "_"
	id = id.strip_edges().trim_suffix("_").trim_prefix("_")
	if id == "" or not (id[0] >= "a" and id[0] <= "z"):
		id = "tileset_" + id
	return id.trim_suffix("_")


static func _unique_id(id: String, taken: Dictionary) -> String:
	if not taken.has(id):
		return id
	var i := 2
	while taken.has("%s_%d" % [id, i]):
		i += 1
	return "%s_%d" % [id, i]


## Name prefix of a tileset's most telling sheet ("SF_Outside_B" -> "SF_Outside"), or "".
static func _sheet_prefix(sheets: Dictionary) -> String:
	for slot in ["b", "a5", "a4", "a3", "a2", "a1", "c", "d", "e"]:
		if sheets.has(slot):
			var base := str(sheets[slot]).get_file().get_basename()
			var s := _sheet_slot(base)
			if s != "":
				return base.substr(0, base.length() - s.length()).trim_suffix("_").trim_suffix("-").strip_edges()
	return ""


## "Outside_A2" -> "A2", "TileB" -> "B", "World_A1" -> "A1"; "" when it is not a sheet name.
static func _sheet_slot(base: String) -> String:
	var m := RegEx.create_from_string("(?:^|[_\\- ]|[a-z])(A[1-5]|[B-E])$").search(base)
	if m == null:
		return ""
	return m.get_string(1).to_upper()


## Profile + sheet paths: two records with the same signature use the same images.
static func signature(rec: Dictionary) -> String:
	var paths := RPGTilesetBuilder.record_sheet_paths(rec)
	var keys := paths.keys()
	keys.sort()
	var parts := PackedStringArray([str(rec.get("profile", "rm2k"))])
	for k in keys:
		parts.append("%s=%s" % [k, paths[k]])
	return "|".join(parts)


# --- apply ---------------------------------------------------------------------------------------

## Copies the chosen files, writes pack.json (when the pack has none) and adds the chosen tileset
## records. `files` / `tilesets` are lists of dst paths / record ids to include (null = all).
## Existing files are skipped and listed in `conflicts` unless their dst is in `overwrite`.
## Returns {copied: [], conflicts: [], errors: [], records_added: [ids], pack_json: path or "",
##          keyed: [dst paths whose palette colour 0 was made transparent]}.
## MV / MZ keep their tilesets in data/Tilesets.json (plain JSON): one record per RPG Maker
## tileset, with its exact sheets (MV's "SF Outside" also uses Outside_A1/A2) and RPG Maker's own
## passability, which apply() writes as tile settings. Returns false when there is no such file.
static func _plan_mv_tilesets(p: Dictionary, existing: Dictionary) -> bool:
	var data_dir := _resolve_ci(str(p.base), "data")
	var path := ""
	var dd := DirAccess.open(data_dir) if data_dir != "" else null
	if dd != null:
		for f in dd.get_files():
			if f.to_lower() == "tilesets.json":
				path = data_dir.path_join(f)
	if path == "":
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Array):
		p.warnings.append("data/Tilesets.json could not be read; tilesets are grouped by file name instead.")
		return false
	var by_name := {}
	for f in p.files:
		if str(f.kind) == "tileset":
			by_name[str(f.dst).get_file().get_basename().to_lower()] = f
	var slots := ["a1", "a2", "a3", "a4", "a5", "b", "c", "d", "e"]
	for e in raw:
		if not (e is Dictionary) or not (e.get("tilesetNames") is Array):
			continue
		var names: Array = e.tilesetNames
		var sheets := {}
		var missing := []
		for i in mini(names.size(), slots.size()):
			var n := str(names[i])
			if n == "":
				continue
			if by_name.has(n.to_lower()):
				sheets[slots[i]] = by_name[n.to_lower()].dst
			else:
				missing.append(n)
		if sheets.is_empty():
			continue
		var label := str(e.get("name", "")).strip_edges()
		if label == "":
			label = "tileset_%d" % int(e.get("id", 0))
		var before: int = p.tilesets.size()
		_add_record(p, existing, label, {"profile": "mv", "sheets": sheets},
			"" if missing.is_empty() else "%s not found" % ", ".join(PackedStringArray(missing)), _sheet_prefix(sheets))
		if p.tilesets.size() > before:
			p.tilesets[-1]["tiles"] = mv_flags_to_tiles(e.get("flags", []), sheets.keys())
	return true


## RPG Maker MV/MZ tile flags -> RPG Kit tile settings {tile_key: {passage, flags, terrain}} for
## the sheets present. MV bits: 0x1/0x2/0x4/0x8 block down/left/right/up, 0x10 star, 0x20 ladder,
## 0x40 bush, 0x80 counter, 0x100 damage floor, terrain tag in bits 12-15. Tile ids: B 0, C 256,
## D 512, E 768, A5 1536, autotile kinds of 48 ids from A1 2048, A2 2816, A3 4352, A4 5888.
static func mv_flags_to_tiles(flags: Array, sheet_slots: Array) -> Dictionary:
	var out := {}
	var ranges := [["b", 0, 256, 1], ["c", 256, 256, 1], ["d", 512, 256, 1], ["e", 768, 256, 1], ["a5", 1536, 128, 1],
		["a1", 2048, 16, 48], ["a2", 2816, 32, 48], ["a3", 4352, 32, 48], ["a4", 5888, 48, 48]]
	for r in ranges:
		if not sheet_slots.has(r[0]):
			continue
		for i in int(r[2]):
			var id: int = int(r[1]) + i * int(r[3])
			if id >= flags.size():
				break
			var f := int(flags[id])
			var kf := 0
			# MV stores passage per autotile shape. Wall tops (A4) are open on shape 0 and closed on
			# their outer edges on the edge shapes (47 = a lone tile, closed all round): the kit
			# keeps one passage per kind, so mark those kinds edge-blocking (RPGMovement).
			if int(r[3]) == 48 and id + 47 < flags.size() and (int(flags[id + 47]) & 15) != (f & 15):
				kf |= RPGTilesetBuilder.FLAG_EDGE
			if f & 0x10:
				kf |= RPGMovement.FLAG_STAR
			if f & 0x20:
				kf |= RPGMovement.FLAG_LADDER
			if f & 0x40:
				kf |= RPGMovement.FLAG_BUSH
			if f & 0x80:
				kf |= RPGMovement.FLAG_COUNTER
			if f & 0x100:
				kf |= RPGMovement.FLAG_DAMAGE
			out["%s_%d" % [r[0], i]] = {"passage": (~f) & 15, "flags": kf, "terrain": (f >> 12) & 15}
	return out


static func apply(p: Dictionary, files: Variant = null, tilesets: Variant = null, overwrite: Array = []) -> Dictionary:
	var res := {"copied": [], "conflicts": [], "errors": [], "records_added": [], "pack_json": "", "keyed": []}
	if str(p.get("profile", "")) == "" or not RPGIds.is_valid(str(p.get("pack_id", ""))):
		res.errors.append("Nothing to import.")
		return res
	var pack_dir := str(p.asset_root).path_join(str(p.pack_id))
	for f in p.files:
		if files is Array and not (files as Array).has(f.dst):
			continue
		if FileAccess.file_exists(f.dst) and not overwrite.has(f.dst):
			res.conflicts.append(f.dst)
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(f.dst).get_base_dir()))
		var err := OK
		var keyed := false
		if f.convert:
			var img := Image.load_from_file(str(f.src))
			if img != null and not img.is_empty() and bool(f.get("key_index0", false)) and str(f.src).get_extension().to_lower() == "bmp":
				var key: Variant = bmp_palette_key(FileAccess.get_file_as_bytes(str(f.src)))
				if key is Color:
					img = key_colour(img, key)
					keyed = true
			err = ERR_FILE_CORRUPT if img == null or img.is_empty() else img.save_png(ProjectSettings.globalize_path(f.dst))
		elif bool(f.get("key_index0", false)):
			var keyed_png := png_key_index0(FileAccess.get_file_as_bytes(str(f.src)))
			if keyed_png.is_empty():
				err = DirAccess.copy_absolute(str(f.src), ProjectSettings.globalize_path(f.dst))
			else:
				var out := FileAccess.open(str(f.dst), FileAccess.WRITE)
				if out == null:
					err = FileAccess.get_open_error()
				else:
					out.store_buffer(keyed_png)
					out.close()
					keyed = true
		else:
			err = DirAccess.copy_absolute(str(f.src), ProjectSettings.globalize_path(f.dst))
		if keyed and err == OK:
			res.keyed.append(f.dst)
		if err != OK:
			res.errors.append("Cannot copy %s (error %d)." % [str(f.src).get_file(), err])
		else:
			res.copied.append(f.dst)
	if not res.copied.is_empty() and not FileAccess.file_exists(pack_dir.path_join("pack.json")):
		var manifest := {"schema_version": 1, "name": str(p.pack_id), "license": LICENSE, "profile": p.profile,
			"author": "", "source": "Imported by the maker from their own RPG Maker %s folder" % _profile_name(str(p.profile)),
			"attribution": "", "notes": "Copied from the maker's disk; RPG Kit does not include these files."}
		if RPGJson.save_file(pack_dir.path_join("pack.json"), manifest) == OK:
			res.pack_json = pack_dir.path_join("pack.json")
	var chosen := []
	var tiles_for := {}
	for t in p.tilesets:
		var rec: Dictionary = t.record
		if t.get("tiles") is Dictionary and not (t.tiles as Dictionary).is_empty():
			tiles_for[rec.id] = t.tiles
		if tilesets is Array and not (tilesets as Array).has(rec.id):
			continue
		var missing := []
		for path in RPGTilesetBuilder.record_sheet_paths(rec).values():
			if not FileAccess.file_exists(str(path)):
				missing.append(str(path).get_file())
		if not missing.is_empty():
			res.errors.append("Tileset '%s' not added: %s not in the project." % [rec.id, ", ".join(PackedStringArray(missing))])
			continue
		chosen.append(rec)
	if not chosen.is_empty():
		var path := str(p.rpg_root).path_join("database/tilesets.json")
		var file: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "records": []})
		var recs: Array = file.get("records", [])
		var taken := {}
		for r in recs:
			if r is Dictionary:
				taken[str(r.get("id", ""))] = true
				taken["sig:" + signature(r)] = true
		for rec in chosen:
			if taken.has("sig:" + signature(rec)):
				continue
			var r2: Dictionary = rec.duplicate(true)
			r2.id = _unique_id(str(rec.id), taken)
			taken[r2.id] = true
			recs.append(r2)
			res.records_added.append(r2.id)
			# RPG Maker's own passability (MV/MZ), as tile settings; never over the maker's own.
			var ov := str(p.rpg_root).path_join("tileset_overrides/%s.json" % r2.id)
			if tiles_for.has(rec.id) and not FileAccess.file_exists(ov):
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ov.get_base_dir()))
				RPGJson.save_file(ov, {"schema_version": 1, "source": "RPG Maker data/Tilesets.json", "tiles": tiles_for[rec.id]})
		file["records"] = recs
		var err := RPGJson.save_file(path, file)
		if err != OK:
			res.errors.append("Cannot write %s (error %d)." % [path, err])
			res.records_added.clear()
	return res


## One-paragraph report of an apply() result.
static func describe(p: Dictionary, r: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Copied %d file(s) into %s/." % [r.copied.size(), str(p.asset_root).path_join(str(p.pack_id)).trim_prefix("res://")])
	if not r.records_added.is_empty():
		lines.append("Added %d tileset record(s): %s." % [r.records_added.size(), ", ".join(PackedStringArray(r.records_added))])
	if r.pack_json != "":
		lines.append("Wrote pack.json (licence: check the RPG Maker EULA before distributing).")
	if not (r.get("keyed", []) as Array).is_empty():
		lines.append("Made palette colour 0 transparent in %d 2000/2003 image(s), as RPG Maker draws them." % r.keyed.size())
	if not r.conflicts.is_empty():
		lines.append("%d existing file(s) left unchanged." % r.conflicts.size())
	if not p.skipped.is_empty():
		# Grouped by reason, so a long list of MIDI files reads as one line.
		var counts := {}
		var order := []
		for s in p.skipped:
			var why := str(s.reason)
			if why.begins_with("same name as"):
				why = "same name as another file in the list"
			if not counts.has(why):
				counts[why] = 0
				order.append(why)
			counts[why] += 1
		lines.append("%d file(s) skipped:" % p.skipped.size())
		for why in order:
			lines.append("  %d x %s" % [counts[why], why])
	for e in r.errors:
		lines.append(str(e))
	return "\n".join(lines)


static func _profile_name(id: String) -> String:
	return {"rm2k": "2000/2003", "xp": "XP", "vx": "VX / VX Ace", "mv": "MV / MZ"}.get(id, id)


# --- files ---------------------------------------------------------------------------------------

## Case-insensitive lookup of a relative folder path ("Graphics/Characters"); "" when missing.
static func _resolve_ci(base: String, rel: String) -> String:
	var cur := base
	for part in rel.split("/", false):
		cur = _dir_ci(cur, part)
		if cur == "":
			return ""
	return cur


static func _dir_ci(parent: String, child: String) -> String:
	var d := DirAccess.open(parent)
	if d == null:
		return ""
	for sub in d.get_directories():
		if sub.to_lower() == child.to_lower():
			return parent.path_join(sub)
	return ""


static func _files(dir: String, exts: Array) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			if exts.has(f.get_extension().to_lower()):
				out.append(dir.path_join(f))
	out.sort()
	return out


static func _image_size(path: String) -> Vector2i:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return img.get_size() if img != null and not img.is_empty() else Vector2i.ZERO


static func _check_size(path: String, want: Vector2i) -> String:
	var s := _image_size(path)
	return "" if s == want or s == Vector2i.ZERO else "%s is %dx%d, expected %dx%d" % [path.get_file(), s.x, s.y, want.x, want.y]


# --- palette transparency (2000/2003) ------------------------------------------------------------

const PNG_SIGNATURE := [137, 80, 78, 71, 13, 10, 26, 10]
static var _crc_table: PackedInt64Array = PackedInt64Array()


## The PNG with palette index 0 made transparent (a tRNS chunk after PLTE), as RPG Maker
## 2000/2003 draws it. Empty when `png` is not an indexed PNG or already has a tRNS chunk.
static func png_key_index0(png: PackedByteArray) -> PackedByteArray:
	if png.size() < 33 or Array(png.slice(0, 8)) != PNG_SIGNATURE or png[25] != 3:
		return PackedByteArray()
	var pos := 8
	var plte_end := -1
	while pos + 12 <= png.size():
		var n := (png[pos] << 24) | (png[pos + 1] << 16) | (png[pos + 2] << 8) | png[pos + 3]
		var type := png.slice(pos + 4, pos + 8).get_string_from_ascii()
		if type == "tRNS":
			return PackedByteArray()
		if type == "PLTE":
			plte_end = pos + 12 + n
		if type == "IDAT" or type == "IEND":
			break
		pos += 12 + n
	if plte_end < 0 or plte_end > png.size():
		return PackedByteArray()
	var body := "tRNS".to_ascii_buffer()
	body.append(0)
	var crc := crc32(body)
	var out := png.slice(0, plte_end)
	out.append_array(PackedByteArray([0, 0, 0, 1]))
	out.append_array(body)
	out.append_array(PackedByteArray([(crc >> 24) & 255, (crc >> 16) & 255, (crc >> 8) & 255, crc & 255]))
	out.append_array(png.slice(plte_end))
	return out


## Colour of palette entry 0 of a BMP with 8 or fewer bits per pixel, or null for a true-colour BMP.
static func bmp_palette_key(bmp: PackedByteArray) -> Variant:
	if bmp.size() < 30 or bmp[0] != 0x42 or bmp[1] != 0x4D:
		return null
	var header := bmp.decode_u32(14)
	var bpp := bmp.decode_u16(24) if header == 12 else bmp.decode_u16(28)
	var at := 14 + header
	if bpp > 8 or at + 3 > bmp.size():
		return null
	return Color8(bmp[at + 2], bmp[at + 1], bmp[at])


## RGBA8 copy of `img` with every pixel of colour `key` made transparent.
static func key_colour(img: Image, key: Color) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.r8 == key.r8 and c.g8 == key.g8 and c.b8 == key.b8:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out


## CRC-32 (the PNG / zlib polynomial) of `data`.
static func crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if c & 1 else (c >> 1)
			_crc_table[i] = c
	var crc := 0xFFFFFFFF
	for b in data:
		crc = _crc_table[(crc ^ b) & 255] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF
