@tool
extends HBoxContainer
## Picks a tile as an event graphic ({tile: tile_key}): a thumbnail of the chosen tile and a
## "Choose tile…" button that opens every tile of a tileset as pictures (autotiles show their
## preview variant, like the map palette). Defaults to the tileset of the map being edited.
## Loaded by path (no class_name):
##   var tp = load("res://addons/rpg/editor/forms/rpg_tile_picker.gd").new()
##   tp.setup(data, map_id); tp.set_value("lower_17"); tp.value_changed.connect(...)
## Reads the generated TileSet cache when there is one and never writes it.

signal value_changed(key: String)

## tileset id -> TileSet, kept while the editor runs.
static var _tilesets: Dictionary = {}
## TileSet instance id -> tiles_of() result.
static var _tiles: Dictionary = {}

var data: RPGProjectData
var tileset_id := ""
var _value := ""
var _thumb: TextureRect
var _button: Button
var _popup: PopupPanel
var _sets: OptionButton
var _list: ItemList
var _keys: Array = []


func setup(p_data: RPGProjectData, map_id := "") -> void:
	data = p_data
	tileset_id = ""
	if data != null and map_id != "":
		tileset_id = str(data.map_props(map_id).get("tileset", ""))
	if tileset_id == "" and data != null:
		var recs := data.records("tilesets")
		if not recs.is_empty() and recs[0] is Dictionary:
			tileset_id = str(recs[0].get("id", ""))
	for c in get_children():
		c.queue_free()
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(32, 32)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_thumb)
	_button = Button.new()
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.pressed.connect(open)
	add_child(_button)
	_refresh()


func set_value(key: Variant) -> void:
	_value = str(key) if key != null else ""
	_refresh()


func get_value() -> String:
	return _value


## The TileSet of a tileset record (cached file when present, else built in memory), or null.
func tile_set(id := "") -> TileSet:
	if id == "":
		id = tileset_id
	if id == "" or data == null:
		return null
	if _tilesets.has(id):
		return _tilesets[id]
	var rec := data.record("tilesets", id)
	if rec.is_empty():
		return null
	var ts: TileSet = null
	var cache := RPGTilesetBuilder.cache_path(id)
	if ResourceLoader.exists(cache):
		ts = ResourceLoader.load(cache) as TileSet
	if ts == null:
		ts = RPGTilesetBuilder.build(rec)
	if ts != null:
		_tilesets[id] = ts
	return ts


## [{key, texture}] for every distinct tile key of a TileSet, in atlas order.
static func tiles_of(ts: TileSet) -> Array:
	var out := []
	if ts == null or ts.get_custom_data_layer_by_name("tile_key") < 0:
		return out
	if _tiles.has(ts.get_instance_id()):
		return _tiles[ts.get_instance_id()]
	_tiles[ts.get_instance_id()] = out
	var at_index := {}
	var auto_sources: Array = ts.get_meta(RPGTilesetBuilder.AUTOTILE_SOURCES_META, [RPGTilesetBuilder.SOURCE_AUTOTILE])
	for si in ts.get_source_count():
		var sid := ts.get_source_id(si)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coords := src.get_tile_id(t)
			var td := src.get_tile_data(coords, 0)
			if td == null:
				continue
			var key := str(td.get_custom_data("tile_key"))
			if key == "":
				continue
			var preferred: bool = not auto_sources.has(sid) or coords.x == RPGAutotile.PREVIEW_VARIANT
			if at_index.has(key):
				if preferred and not out[at_index[key]].preferred:
					out[at_index[key]] = {"key": key, "texture": _atlas(src, coords), "preferred": true}
				continue
			at_index[key] = out.size()
			out.append({"key": key, "texture": _atlas(src, coords), "preferred": preferred})
	return out


static func _atlas(src: TileSetAtlasSource, coords: Vector2i) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = src.get_tile_texture_region(coords)
	return at


func texture_for(key: String) -> Texture2D:
	for t in tiles_of(tile_set()):
		if t.key == key:
			return t.texture
	return null


func _refresh() -> void:
	if _button == null:
		return
	_button.text = "Choose tile…" if _value == "" else "%s  (change…)" % _value
	_thumb.texture = texture_for(_value) if _value != "" else null
	_thumb.visible = _thumb.texture != null


func open() -> void:
	if _popup == null:
		_popup = PopupPanel.new()
		var vb := VBoxContainer.new()
		_popup.add_child(vb)
		_sets = OptionButton.new()
		_sets.tooltip_text = "Tileset"
		for r in (data.records("tilesets") if data != null else []):
			if r is Dictionary:
				_sets.add_item("%s (%s)" % [r.get("name", r.get("id", "")), r.get("id", "")])
				_sets.set_item_metadata(_sets.item_count - 1, str(r.get("id", "")))
		_sets.item_selected.connect(func(i: int):
			tileset_id = str(_sets.get_item_metadata(i))
			_fill())
		vb.add_child(_sets)
		_list = ItemList.new()
		_list.custom_minimum_size = Vector2(520, 360)
		_list.icon_mode = ItemList.ICON_MODE_TOP
		_list.max_columns = 0
		_list.fixed_icon_size = Vector2i(32, 32)
		_list.same_column_width = true
		_list.fixed_column_width = 40
		_list.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_list.item_activated.connect(choose)
		vb.add_child(_list)
		var ok := Button.new()
		ok.text = "Choose"
		ok.pressed.connect(func():
			var sel := _list.get_selected_items()
			if not sel.is_empty():
				choose(sel[0]))
		vb.add_child(ok)
		add_child(_popup)
	for i in _sets.item_count:
		if str(_sets.get_item_metadata(i)) == tileset_id:
			_sets.select(i)
	_fill()
	_popup.popup_centered(Vector2i(540, 420))


func _fill() -> void:
	_list.clear()
	_keys.clear()
	for t in tiles_of(tile_set()):
		_list.add_item("", t.texture)
		_list.set_item_tooltip(_list.item_count - 1, t.key)
		_keys.append(t.key)
		if t.key == _value:
			_list.select(_list.item_count - 1)


func choose(i: int) -> void:
	if i < 0 or i >= _keys.size():
		return
	if _popup != null:
		_popup.hide()
	_value = str(_keys[i])
	_refresh()
	value_changed.emit(_value)
