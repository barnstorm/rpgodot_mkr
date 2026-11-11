@tool
extends RefCounted
## Resource manager file actions for the Tools window: import files into a pack's asset folder,
## delete unused files, and load previews. Preloaded by path (no class_name):
##   const ResourceFiles := preload("res://addons/rpg/editor/tools/rpg_resource_files.gd")

const Deploy := preload("res://addons/rpg/editor/tools/rpg_deploy.gd")
## Import types in menu order: [label, RPGAssets kind]. The folder comes from RPGAssets.FOLDERS.
const TYPES := [
	["CharSet (walk sprites)", "charset"],
	["ChipSet (map tiles)", "chipset"],
	["FaceSet (faces)", "faceset"],
	["Monster (battlers)", "battler"],
	["Backdrop (battle backgrounds)", "backdrop"],
	["Music", "music"],
	["Sound", "sound"],
	["System (window skins)", "system"],
	["Title", "title"],
	["Picture", "picture"],
	["Panorama", "panorama"],
]
const IMAGE_EXT := ["png", "webp", "jpg", "jpeg", "bmp"]
## Every audio file type the kit plays; MIDI only as music (rendered with the sound bank at import).
const AUDIO_EXT := ["wav", "ogg", "mp3", "mid", "midi"]
const SOUND_EXT := ["wav", "ogg", "mp3"]
## Pack that imported files go to unless another pack is picked.
const DEFAULT_PACK := "project"


static func folder_for(kind: String) -> String:
	return RPGAssets.folder_for(kind)


static func allowed_extensions(kind: String) -> Array:
	if kind == "music":
		return AUDIO_EXT
	return SOUND_EXT if RPGAssets.AUDIO_KINDS.has(kind) else IMAGE_EXT


## Destination path of one imported file.
static func target_path(source: String, kind: String, pack := DEFAULT_PACK, asset_root := "res://assets") -> String:
	return asset_root.path_join(pack).path_join(folder_for(kind)).path_join(source.get_file())


## Copies files into <asset_root>/<pack>/<Folder>/. Existing files are left alone unless
## `overwrite` is true; they are listed in `conflicts` so the window can ask first.
## Returns {copied: [paths], conflicts: [paths], errors: [messages]}.
static func import_files(sources: PackedStringArray, kind: String, pack := DEFAULT_PACK, asset_root := "res://assets", overwrite := false) -> Dictionary:
	var res := {"copied": [], "conflicts": [], "errors": []}
	if folder_for(kind) == "":
		res.errors.append("Unknown asset type '%s'." % kind)
		return res
	if not RPGIds.is_valid(pack):
		res.errors.append("'%s' is not a valid pack name (lowercase letters, digits and _)." % pack)
		return res
	var exts := allowed_extensions(kind)
	for src in sources:
		var ext := src.get_extension().to_lower()
		if not exts.has(ext):
			res.errors.append("%s: a %s file must be %s." % [src.get_file(), folder_for(kind), ", ".join(PackedStringArray(exts))])
			continue
		if not FileAccess.file_exists(src):
			res.errors.append("%s does not exist." % src)
			continue
		var dst := target_path(src, kind, pack, asset_root)
		if FileAccess.file_exists(dst) and not overwrite:
			res.conflicts.append(dst)
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst.get_base_dir()))
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
		if err != OK:
			res.errors.append("Cannot copy %s (error %d)." % [src.get_file(), err])
		else:
			res.copied.append(dst)
	return res


## Deletes an asset file the project does not use (and its .import file). A used file is refused
## and `used_by` names where. `trash` moves it to the system trash instead of removing it.
## Returns {ok, message, used_by}.
static func delete_asset(data: RPGProjectData, path: String, asset_root := "res://assets", trash := true) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "%s does not exist." % path, "used_by": []}
	var used := Deploy.where_used(data, path, asset_root)
	if not used.is_empty():
		return {"ok": false, "message": "%s is used by %s. Remove those uses first." % [path.get_file(), ", ".join(PackedStringArray(used))], "used_by": used}
	var g := ProjectSettings.globalize_path(path)
	var err: Error = OS.move_to_trash(g) if trash else DirAccess.remove_absolute(g)
	if err != OK and trash:
		err = DirAccess.remove_absolute(g)
	if err != OK:
		return {"ok": false, "message": "Cannot delete %s (error %d)." % [path.get_file(), err], "used_by": []}
	if FileAccess.file_exists(path + ".import"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".import"))
	return {"ok": true, "message": "Deleted %s%s." % [path.get_file(), " (moved to the trash)" if trash else ""], "used_by": []}


## A texture for previewing, also for files the editor has not imported yet.
static func load_preview_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t != null:
			return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


static func load_preview_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var s := load(path) as AudioStream
		if s != null:
			return s
	var g := ProjectSettings.globalize_path(path)
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(g)
		"wav":
			return AudioStreamWAV.load_from_file(g)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(g)
			return s
		"mid", "midi":
			# Not imported yet: render it now (takes a few seconds).
			return RPGMidiRenderer.render_file(path).stream
	return null


## Asks the editor to rescan files after an import or delete (no-op outside the editor).
static func rescan() -> void:
	RPGAssets.clear_cache()
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ei: Object = Engine.get_singleton("EditorInterface")
		ei.get_resource_filesystem().scan()
