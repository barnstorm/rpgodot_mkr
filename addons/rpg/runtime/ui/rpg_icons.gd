@tool
class_name RPGIcons
extends RefCounted
## Icons of items, weapons, armour, skills and states, cut from an icon sheet laid out like
## RPG Maker VX/MV's IconSet: square icons, 16 per row, index 0 at the top left. Index 0 (and
## below) means "no icon".
##
## The sheet is the System image named by System "icon_sheet" (for example "IconSet" from an
## imported VX/MV project). Without one, the starter set made by tools/generate_icons.gd is used:
## IconSet32 (32 px) for an MV/MZ project, IconSet24 (24 px) for VX/VX Ace, XP and 2000/2003.
## The icon size is the sheet width / 16.
##
##   RPGIcons.texture(64)            -> icon 64 at the sheet's own size (AtlasTexture), or null
##   RPGIcons.texture(64, 24)        -> icon 64, 24 px (the starter set of that size, else scaled)
##   RPGIcons.for_record(rec)        -> the icon of a database record (rec.icon), or null
##   RPGIcons.icon_index(rec)        -> rec.icon as an int (0 for old data without one)
##   RPGIcons.enabled()              -> System "show_icons" (default true)
##   RPGIcons.entries()              -> the starter icons.json list: [{index, name, category}]
##   RPGIcons.find("potion_red")     -> 64 (index by name, -1 when unknown)
##
## The runtime service calls use_project() when it boots; editors pass the sheet themselves
## (sheet_icon). clear_cache() drops the textures (RPGService.release_caches calls it).

const COLUMNS := 16
const INDEX_FILE := "res://assets/starter/icons.json"
## Starter sheets by icon size (RPGAssets names: pack/name).
const STARTER_SHEETS := {24: "starter/IconSet24", 32: "starter/IconSet32"}
const STARTER_DIR := "/starter/System/IconSet"

## The project whose System settings are read (a weak reference: never keeps it alive).
static var _project: WeakRef = null
## "sheet|size|index" -> AtlasTexture
static var _icons: Dictionary = {}
## "sheet|size" -> Texture2D: a sheet scaled to another icon size
static var _scaled: Dictionary = {}
## icons.json entries (loaded once)
static var _entries: Array = []


## The project to read System "icon_sheet" / "show_icons" and the asset profile from.
static func use_project(p: RPGProjectData) -> void:
	_project = weakref(p) if p != null else null
	_icons.clear()
	_scaled.clear()


## The project set with use_project(), else the running game's (the RPG autoload), else null.
static func project() -> RPGProjectData:
	if _project != null:
		var p: Variant = _project.get_ref()
		if p is RPGProjectData:
			return p
	var ml := Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		var svc := (ml as SceneTree).root.get_node_or_null("RPG")
		if svc != null and svc.get("data") is RPGProjectData:
			return svc.data
	return null


## Drops every cached icon texture (call after a sheet changed, and when the game quits).
static func clear_cache() -> void:
	_icons.clear()
	_scaled.clear()
	_entries.clear()


## System "show_icons" (default true): false draws the menus without icons, as before.
static func enabled(p: RPGProjectData = null) -> bool:
	if p == null:
		p = project()
	return p == null or bool(p.system.get("show_icons", true))


## The starter sheet for an asset profile ("mv" -> 32 px, anything else -> 24 px).
static func default_sheet(profile_id: String) -> String:
	return STARTER_SHEETS[32] if profile_id == "mv" else STARTER_SHEETS[24]


## The sheet a project uses: System "icon_sheet" when that image exists, else the starter sheet
## for its profile.
static func sheet_name(p: RPGProjectData = null) -> String:
	if p == null:
		p = project()
	if p == null:
		return STARTER_SHEETS[24]
	var own := str(p.system.get("icon_sheet", "")).strip_edges()
	if own != "" and RPGAssets.find("system", own) != "":
		return own
	return default_sheet(str(p.profile.get("profile", "rm2k")))


## Icon `index` of the project's sheet, `size` px square (0: the sheet's own size); null for
## index <= 0, an index past the sheet, or a missing sheet.
static func texture(index: int, size := 0) -> Texture2D:
	if index <= 0:
		return null
	return sheet_icon(sheet_name(), index, size)


## The icon of a database record (items, weapons, armour, skills, states), or null.
static func for_record(rec: Dictionary) -> Texture2D:
	return texture(icon_index(rec))


## A record's icon index. Old data stored the icon sheet's name in "icon" (or nothing): that
## reads as 0, no icon; a whole number in text ("12") still counts; "icon_index" is read too.
static func icon_index(rec: Dictionary) -> int:
	var v: Variant = rec.get("icon", 0)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return maxi(0, int(v))
	if v is String and (v as String).strip_edges().is_valid_int():
		return maxi(0, (v as String).strip_edges().to_int())
	var alt: Variant = rec.get("icon_index", 0)
	if typeof(alt) in [TYPE_INT, TYPE_FLOAT]:
		return maxi(0, int(alt))
	return 0


## Icon `index` of a named sheet (an RPGAssets "system" name), `size` px (0: its own size).
static func sheet_icon(sheet: String, index: int, size := 0) -> Texture2D:
	if index <= 0 or sheet == "":
		return null
	var key := "%s|%d|%d" % [sheet, size, index]
	if _icons.has(key):
		return _icons[key]
	var tex := RPGAssets.load_texture("system", sheet)
	var cell := cell_size(tex)
	if cell <= 0 or index >= count(tex):
		return null
	var src: Texture2D = tex
	if size > 0 and size != cell:
		src = _sheet_at(sheet, tex, cell, size)
		cell = size
	if src == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = src
	at.region = Rect2((index % COLUMNS) * cell, (index / COLUMNS) * cell, cell, cell)
	_icons[key] = at
	return at


## RichTextLabel BBCode for icon `index` of the project's sheet, drawn `size` px square (message
## code \I[n]); "" for no icon or a sheet that is not an imported resource.
static func bbcode(index: int, size := 12, p: RPGProjectData = null) -> String:
	if index <= 0:
		return ""
	var sheet := sheet_name(p)
	var path := RPGAssets.find("system", sheet)
	var tex := RPGAssets.load_texture("system", sheet)
	var cell := cell_size(tex)
	if path == "" or cell <= 0 or index >= count(tex) or not ResourceLoader.exists(path):
		return ""
	return "[img width=%d height=%d region=%d,%d,%d,%d]%s[/img]" % [size, size, (index % COLUMNS) * cell, (index / COLUMNS) * cell, cell, cell, path]


## The icon size of a sheet texture (width / 16), 0 for none.
static func cell_size(tex: Texture2D) -> int:
	if tex == null:
		return 0
	return tex.get_width() / COLUMNS


## How many icons a sheet texture holds.
static func count(tex: Texture2D) -> int:
	var cell := cell_size(tex)
	if cell <= 0:
		return 0
	return COLUMNS * (tex.get_height() / cell)


## Number of icons in the project's sheet.
static func sheet_count(sheet := "") -> int:
	return count(RPGAssets.load_texture("system", sheet if sheet != "" else sheet_name()))


## A sheet at another icon size: the starter set drawn at that size when the sheet is a starter
## sheet, else a scaled copy (made once).
static func _sheet_at(sheet: String, tex: Texture2D, cell: int, size: int) -> Texture2D:
	if RPGAssets.find("system", sheet).contains(STARTER_DIR) and STARTER_SHEETS.has(size):
		var own := RPGAssets.load_texture("system", STARTER_SHEETS[size])
		if cell_size(own) == size:
			return own
	var key := "%s|%d" % [sheet, size]
	if _scaled.has(key):
		return _scaled[key]
	var img := RPGAssets.texture_image(tex)
	if img == null:
		return null
	var whole := size % cell == 0
	img.resize(img.get_width() * size / cell, img.get_height() * size / cell, Image.INTERPOLATE_NEAREST if whole else Image.INTERPOLATE_BILINEAR)
	var out := ImageTexture.create_from_image(img)
	_scaled[key] = out
	return out


# --- names (starter icons.json) -------------------------------------------------------------

## The starter set's [{index, name, category}] list ([] when icons.json is missing).
static func entries() -> Array:
	if _entries.is_empty() and FileAccess.file_exists(INDEX_FILE):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_FILE))
		if j is Dictionary and j.get("icons") is Array:
			for e in j.icons:
				if e is Dictionary:
					_entries.append({"index": int(e.get("index", 0)), "name": str(e.get("name", "")), "category": str(e.get("category", ""))})
	return _entries


## Index of a starter icon by name, -1 when unknown.
static func find(icon_name: String) -> int:
	for e in entries():
		if e.name == icon_name:
			return e.index
	return -1


## The starter name of an index ("" when unknown).
static func name_of(index: int) -> String:
	for e in entries():
		if e.index == index:
			return e.name
	return ""


## True when `sheet` is one of the starter sheets (so icons.json names apply to it).
static func is_starter_sheet(sheet: String) -> bool:
	return RPGAssets.find("system", sheet).contains(STARTER_DIR)
