@tool
class_name RPGProfile
extends RefCounted
## Asset profile descriptor (see spec "Asset profiles"). Profiles live in
## res://addons/rpg/core/profiles/<id>.json and fix the tile size, folder conventions,
## sheet sizes and the sound role -> file name map. Usable in editor and exported games
## (keep *.json in the export filter).
##
##   var p := RPGProfile.load_profile("rm2k")   # or RPGProfile.load("rm2k")
##   p.tile_size            -> 16
##   p.folder("charset")    -> "CharSet"
##   p.sheet_size("charset") -> Vector2i(288, 256)
##   p.sound_role("door_open") -> "door_open"
##   p.decoders              -> {sheet kind: note} for the kinds this addon decodes
##   p.limitations           -> known gaps of the decoders (shown to the user, not enforced)
## A profile's status is "supported" only when its decoders pass their fixtures
## (tests/suites/test_import.gd for rm2k, tests/suites/test_profiles.gd for xp/vx/mv).

const PROFILE_DIR := "res://addons/rpg/core/profiles"
const DEFAULT_PROFILE := "rm2k"
const SOUND_ROLES: Array[String] = [
	"step", "door_open", "chest_open", "inn_rest", "cursor", "decision", "cancel", "buzzer",
	"save", "battle_start", "attack", "damage", "heal", "escape", "level_up", "victory", "game_over",
]
## Asset kinds RPGAssets understands, in a stable order.
const KINDS: Array[String] = [
	"charset", "faceset", "chipset", "system", "picture", "music", "sound", "battler",
	"backdrop", "panorama", "title", "gameover",
]

static var _cache: Dictionary = {}

var id := ""
var display_name := ""
var version := 0
var status := "planned"
var tile_size := 16
var folders: Dictionary = {}
var sheets: Dictionary = {}
var sound_roles: Dictionary = {}
var music_roles: Dictionary = {}
var extensions: Dictionary = {}
var decoders: Dictionary = {}
var limitations: Array = []
var data: Dictionary = {}


## Loads (and caches) a profile by id. Returns null when the descriptor is missing or invalid.
static func load_profile(profile_name: String) -> RPGProfile:
	var key := profile_name.strip_edges().to_lower()
	if key == "":
		key = DEFAULT_PROFILE
	if _cache.has(key):
		return _cache[key]
	var path := PROFILE_DIR.path_join(key + ".json")
	var r := RPGJson.parse_file(path)
	if not r.ok or not (r.data is Dictionary):
		push_error("RPGProfile: cannot load '%s': %s" % [key, r.error])
		return null
	var p := RPGProfile.new()
	p._setup(r.data)
	_cache[key] = p
	return p


## Alias of load_profile (the name the design notes use).
static func load(profile_name: String) -> RPGProfile:
	return load_profile(profile_name)


## Ids of every profile descriptor shipped with the addon.
static func available() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(PROFILE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		var fn := f.trim_suffix(".remap").trim_suffix(".import")
		if fn.ends_with(".json"):
			var pid := fn.get_basename()
			if not out.has(pid):
				out.append(pid)
	out.sort()
	return out


static func clear_cache() -> void:
	_cache.clear()


func _setup(d: Dictionary) -> void:
	data = d
	id = str(d.get("id", ""))
	display_name = str(d.get("name", id))
	version = int(d.get("version", 0))
	status = str(d.get("status", "planned"))
	tile_size = int(d.get("tile_size", 16))
	folders = d.get("folders", {})
	sheets = d.get("sheets", {})
	sound_roles = d.get("sound_roles", {})
	music_roles = d.get("music_roles", {})
	extensions = d.get("extensions", {})
	decoders = d.get("decoders", {})
	limitations = d.get("limitations", [])


func is_supported() -> bool:
	return status == "supported"


## True when the addon decodes sheets of `kind` for this profile (see "decoders").
func decodes(kind: String) -> bool:
	return decoders.has(kind)


## Folder name (relative to a pack root) holding assets of `kind`, or "" if the profile has none.
func folder(kind: String) -> String:
	return str(folders.get(kind, ""))


## Sheet descriptor for a kind ({} when unknown).
func sheet(kind: String) -> Dictionary:
	var s: Variant = sheets.get(kind, {})
	return s if s is Dictionary else {}


## Fixed sheet size for a kind, or Vector2i.ZERO if the kind has no fixed size.
func sheet_size(kind: String) -> Vector2i:
	var s := sheet(kind)
	if s.has("size"):
		return Vector2i(int(s.size[0]), int(s.size[1]))
	return Vector2i.ZERO


func image_extensions() -> PackedStringArray:
	return PackedStringArray(extensions.get("image", ["png"]))


func audio_extensions() -> PackedStringArray:
	return PackedStringArray(extensions.get("audio", ["wav", "ogg", "mp3"]))


## Candidate file names (without extension) for a sound role. A role entry may be a string or a
## list of names; the first one that exists in a pack wins (RPGAssets.find).
## The profile's names come first (RPG Maker's RTP: "Open1"); the role's own name ("door_open",
## as the starter pack names its files) is always the last resort, so a VX/MV-style project
## without the RTP still finds the starter sounds.
func sound_candidates(role: String) -> PackedStringArray:
	var v: Variant = sound_roles.get(role, null)
	var out := PackedStringArray()
	if v is String:
		out.append(v)
	elif v is Array:
		out.append_array(PackedStringArray(v))
	if not out.has(role):
		out.append(role)
	return out


## File name for a sound role: the first candidate that exists in the project's assets (the
## profile's first name when none does; "" when the profile does not map the role and no file is
## named after it).
func sound_role(role: String) -> String:
	var c := sound_candidates(role)
	for f in c:
		if RPGAssets.find("sound", f) != "":
			return f
	if c.size() > 1:
		return c[0]
	return ""


## Alias for sound_role.
func sound_file(role: String) -> String:
	return sound_role(role)


func music_role(role: String) -> String:
	return str(music_roles.get(role, ""))
