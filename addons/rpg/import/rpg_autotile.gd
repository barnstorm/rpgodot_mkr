@tool
class_name RPGAutotile
extends RefCounted
## Autotile maths and painting helpers (pure code: editor tools and runtime may both use it).
##
## Neighbour mask: 8 bits, N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128. A diagonal only counts when
## both orthogonal neighbours next to it connect ("reduced" mask), which leaves exactly 47
## distinct masks (the standard blob set). Variants are numbered by descending reduced mask, so
## variant 0 is the fully connected centre (mask 255) and variant 46 the isolated tile (mask 0).
## Variant 47 is the profile's palette/preview tile (for 2000/2003 terrain: block tile (0,0)).
##
## Each tile is composed of four quarter tiles (TL, TR, BL, BR). The kind of each quarter only
## depends on its vertical neighbour, horizontal neighbour and the diagonal between them:
##   FILL   both orthogonals and the diagonal connect
##   INNER  both orthogonals connect, the diagonal does not (concave corner)
##   VERT   only the vertical neighbour connects (the border runs vertically: left/right edge)
##   HORZ   only the horizontal neighbour connects (top/bottom edge)
##   OUTER  neither orthogonal connects (convex corner)
##
## Painting contract (TileSets from RPGTilesetBuilder): an autotile cell has custom data
## `autotile` >= 0 (its group). Its atlas coords are (variant, row): painting keeps the row and
## swaps the column for the variant chosen from the neighbours. Groups whose class (TileSet meta
## `rpg_autotile_classes`) is equal connect to each other (all water connects to all water).
## Cells placed with connect=false keep their variant: they are listed in the layer meta
## `rpg_autotile_fixed` (saved with the scene) until painted over or erased.
## If the layer has meta `rpg_map_size` (Vector2i), cells outside the map count as connected,
## as in RPG Maker; otherwise empty / out-of-map cells do not connect.
##
## Blend rows (TileSet meta `rpg_autotile_blend`: {group: {tiles: [16 x [source, row]],
## with: [groups]}}): a group listed there draws a different piece in each FILL quarter whose
## vertical AND horizontal neighbours both hold a group of its `with` list (an outer corner of
## the other group). The 4 quarter bits (TL 1, TR 2, BL 4, BR 8) pick the atlas source and row:
## tiles[bits]; tiles[0] is the group's own row. Blend tiles carry the group's autotile id.
## Used by 2000/2003 water: shallow water next to deep water and deep water next to shallow
## water use ChipSet block C rows 1 and 2 (see RPGChipset2k).
##
## Hidden base layer (VX Ace / MV overlay autotiles; TileSet meta `rpg_overlay_bases`:
## {group: {key: "" | base tile_key, source, coords}}): some autotiles have transparent
## surroundings and RPG Maker draws them over an implicit lower tile (deep sea over sea, a bush
## over the ground). When a TileMapLayer named "Layer1" has a sibling named "Layer1Base" (drawn
## below it; RPGMap.ensure_base_layer), painting such an overlay on Layer1 puts its base on
## Layer1Base: the given base tile (key != ""), otherwise the ground already on the cell (moved
## down), otherwise the most common ground of the 4 orthogonal neighbours. Painting anything
## else clears the base; erasing an overlay brings its base back up to Layer1. For connections
## the two layers count as one: a cell connects when either layer holds a joining group (sea
## under deep sea joins the sea around it, so the shore is not drawn there).
##
## Auto shadows (RPG Maker 2000-style rule, documented choice): light comes from the upper left,
## so a wall casts shadow onto the cell to its right (east). For a non-wall cell C:
##   W is a wall and NW is a wall   -> shadow on the left half of C (TL | BL = 5)
##   W is a wall and NW is not      -> shadow on the bottom-left quarter only (BL = 4)
##   otherwise                      -> no shadow (0)
## "Wall" = any tile layer at that cell has flags & 32. Wall cells never get auto shadow.

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128

const KIND_FILL := 0
const KIND_OUTER := 1
const KIND_VERT := 2
const KIND_HORZ := 3
const KIND_INNER := 4
const KIND_NAMES := ["fill", "outer", "vert", "horz", "inner"]

const VARIANT_COUNT := 47
const PREVIEW_VARIANT := 47
const VARIANT_SLOTS := 48

## Quarter order and shadow bits.
const Q_TL := 0
const Q_TR := 1
const Q_BL := 2
const Q_BR := 3
const SHADOW_TL := 1
const SHADOW_TR := 2
const SHADOW_BL := 4
const SHADOW_BR := 8
const FLAG_STAR := 16
const FLAG_WALL := 32

const FIXED_META := "rpg_autotile_fixed"
const MAP_SIZE_META := "rpg_map_size"
const CLASSES_META := "rpg_autotile_classes"
const BLEND_META := "rpg_autotile_blend"
const OVERLAY_META := "rpg_overlay_bases"
## The layer overlays are painted on, and the hidden layer below it that holds their base.
const TOP_LAYER := "Layer1"
const BASE_LAYER := "Layer1Base"

## Neighbour offsets in bit order.
const OFFSETS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
## The neighbours each quarter touches (vertical, horizontal, diagonal), for TL, TR, BL, BR.
const QUARTER_NEIGHBOURS := [
	[Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, -1)],
	[Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, -1)],
	[Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1)],
	[Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)],
]
const ORTHOGONAL := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static var _variant_masks: PackedInt32Array = PackedInt32Array()
static var _mask_to_variant: PackedInt32Array = PackedInt32Array()


# --- masks and variants ------------------------------------------------------------------------

## Drops diagonal bits whose two adjacent orthogonals are not both set.
static func reduce_mask(mask: int) -> int:
	var m := mask & 0xFF
	if not (m & N and m & E):
		m &= ~NE
	if not (m & S and m & E):
		m &= ~SE
	if not (m & S and m & W):
		m &= ~SW
	if not (m & N and m & W):
		m &= ~NW
	return m


static func _init_tables() -> void:
	if _variant_masks.size() == VARIANT_COUNT:
		return
	var seen := {}
	for m in 256:
		seen[reduce_mask(m)] = true
	var masks: Array = seen.keys()
	masks.sort()
	masks.reverse()
	_variant_masks = PackedInt32Array(masks)
	_mask_to_variant.resize(256)
	for m in 256:
		_mask_to_variant[m] = _variant_masks.find(reduce_mask(m))


## Variant index 0..46 for any 8-bit neighbour mask.
static func variant_for_mask(mask: int) -> int:
	_init_tables()
	return _mask_to_variant[mask & 0xFF]


## Reduced mask of a variant (0..46). Variant 47 (preview) returns 255.
static func mask_for_variant(variant: int) -> int:
	_init_tables()
	if variant < 0 or variant >= VARIANT_COUNT:
		return 255
	return _variant_masks[variant]


static func variant_masks() -> PackedInt32Array:
	_init_tables()
	return _variant_masks.duplicate()


## Quarter kinds [TL, TR, BL, BR] for a neighbour mask.
static func quarter_kinds(mask: int) -> Array[int]:
	var m := reduce_mask(mask)
	return [
		_kind(m & N, m & W, m & NW),
		_kind(m & N, m & E, m & NE),
		_kind(m & S, m & W, m & SW),
		_kind(m & S, m & E, m & SE),
	]


static func _kind(vert: int, horz: int, diag: int) -> int:
	if vert and horz:
		return KIND_FILL if diag else KIND_INNER
	if vert:
		return KIND_VERT
	if horz:
		return KIND_HORZ
	return KIND_OUTER


## Kind of a single quadrant (qx, qy in 0..1) of a mask.
static func quarter_kind(mask: int, q: int) -> int:
	return quarter_kinds(mask)[q]


## Neighbour mask from a predicate `connects(cell: Vector2i) -> bool`.
static func mask_from(cell: Vector2i, connects: Callable) -> int:
	var m := 0
	for i in 8:
		if connects.call(cell + OFFSETS[i]):
			m |= 1 << i
	return reduce_mask(m)


# --- quarter composition helpers ---------------------------------------------------------------

## Pixel offset of quarter q (0 TL, 1 TR, 2 BL, 3 BR) inside a tile.
static func quarter_offset(q: int, tile_size: int) -> Vector2i:
	var h := tile_size / 2
	return Vector2i((q % 2) * h, (q / 2) * h)


## Composes a tile from four quarter source rects (TL, TR, BL, BR) of `src` into `dst` at `at`.
static func compose(src: Image, rects: Array, dst: Image, at: Vector2i) -> void:
	for q in 4:
		var r: Rect2i = rects[q]
		dst.blit_rect(src, r, at + quarter_offset(q, r.size.x * 2))


## Returns a new tile image composed from four quarter rects.
static func compose_image(src: Image, rects: Array) -> Image:
	var r0: Rect2i = rects[0]
	var ts := r0.size.x * 2
	var img := Image.create_empty(ts, ts, false, src.get_format())
	compose(src, rects, img, Vector2i.ZERO)
	return img


# --- TileMapLayer painting ---------------------------------------------------------------------

## Autotile group of the tile at (source_id, atlas_coords) in a TileSet, or -1.
static func tile_group(tile_set: TileSet, source_id: int, atlas_coords: Vector2i) -> int:
	if tile_set == null or not tile_set.has_source(source_id):
		return -1
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(atlas_coords):
		return -1
	var td := src.get_tile_data(atlas_coords, 0)
	if td == null or not _has_layer(tile_set, "autotile"):
		return -1
	return int(td.get_custom_data("autotile"))


static func _has_layer(tile_set: TileSet, layer_name: String) -> bool:
	return tile_set.get_custom_data_layer_by_name(layer_name) >= 0


## Autotile group painted at a cell, or -1 (empty or plain tile).
static func group_of(layer: TileMapLayer, cell: Vector2i) -> int:
	if layer.get_cell_source_id(cell) < 0:
		return -1
	var td := layer.get_cell_tile_data(cell)
	if td == null or not _has_layer(layer.tile_set, "autotile"):
		return -1
	return int(td.get_custom_data("autotile"))


static func group_class(tile_set: TileSet, group: int) -> String:
	if tile_set != null and tile_set.has_meta(CLASSES_META):
		var classes: Array = tile_set.get_meta(CLASSES_META)
		if group >= 0 and group < classes.size():
			return str(classes[group])
	return str(group)


static func _in_map(layer: TileMapLayer, cell: Vector2i) -> bool:
	if not layer.has_meta(MAP_SIZE_META):
		return true
	var size: Vector2i = layer.get_meta(MAP_SIZE_META)
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func _joins(tile_set: TileSet, g: int, group: int) -> bool:
	if g < 0:
		return false
	return g == group or group_class(tile_set, g) == group_class(tile_set, group)


## Whether the cell connects to an autotile of `group` (on `layer`, or on `partner`: the other
## half of a Layer1 / Layer1Base pair).
static func connects(layer: TileMapLayer, cell: Vector2i, group: int, partner: TileMapLayer = null) -> bool:
	if not _in_map(layer, cell):
		return true
	if _joins(layer.tile_set, group_of(layer, cell), group):
		return true
	return partner != null and _joins(layer.tile_set, group_of(partner, cell), group)


static func compute_mask(layer: TileMapLayer, cell: Vector2i, group: int) -> int:
	var partner := partner_of(layer)
	return mask_from(cell, func(c: Vector2i) -> bool: return connects(layer, c, group, partner))


# --- blend rows ----------------------------------------------------------------------------------

## {tiles: [16 x [source, row]], with: [groups]} for a group with blend pieces, else {}.
static func blend_spec(tile_set: TileSet, group: int) -> Dictionary:
	if tile_set == null or group < 0 or not tile_set.has_meta(BLEND_META):
		return {}
	var d: Dictionary = tile_set.get_meta(BLEND_META)
	var spec: Variant = d.get(group, {})
	# A spec without 16 tiles (a cache from another builder version) is ignored.
	if not (spec is Dictionary) or not (spec.get("tiles") is Array) or (spec.tiles as Array).size() < 16:
		return {}
	return spec


## Quarter bits (TL 1, TR 2, BL 4, BR 8) of the FILL quarters of a cell whose vertical and
## horizontal neighbours both hold a group of the blend spec's `with` list (an outer corner of
## the other group, seen from this quarter; the diagonal does not matter).
static func blend_bits(layer: TileMapLayer, cell: Vector2i, mask: int, spec: Dictionary) -> int:
	if spec.is_empty():
		return 0
	var with: Array = spec.get("with", [])
	var kinds := quarter_kinds(mask)
	var bits := 0
	for q in 4:
		if kinds[q] != KIND_FILL:
			continue
		var n: Array = QUARTER_NEIGHBOURS[q]
		if with.has(group_of(layer, cell + n[0])) and with.has(group_of(layer, cell + n[1])):
			bits |= 1 << q
	return bits


## [source, atlas coords] an autotile cell should have: (variant, row) on its source; groups with
## blend rows may move to another row and source.
static func autotile_tile(layer: TileMapLayer, cell: Vector2i, group: int, source_id: int, row: int) -> Array:
	var mask := compute_mask(layer, cell, group)
	var spec := blend_spec(layer.tile_set, group)
	if not spec.is_empty():
		var at: Array = (spec.tiles as Array)[blend_bits(layer, cell, mask, spec)]
		source_id = int(at[0])
		row = int(at[1])
	return [source_id, Vector2i(variant_for_mask(mask), row)]


## Palette tile [source, coords] of the autotile at (source, coords): the preview variant on the
## group's own row (an eyedropper on a blend row gives the plain group back). Plain tiles are
## returned as they are.
static func palette_tile(tile_set: TileSet, source_id: int, coords: Vector2i) -> Array:
	var group := tile_group(tile_set, source_id, coords)
	if group < 0:
		return [source_id, coords]
	var spec := blend_spec(tile_set, group)
	if spec.is_empty():
		return [source_id, Vector2i(PREVIEW_VARIANT, coords.y)]
	var own: Array = (spec.tiles as Array)[0]
	return [int(own[0]), Vector2i(PREVIEW_VARIANT, int(own[1]))]


# --- hidden base layer (overlay autotiles) -------------------------------------------------------

## The other layer of a Layer1 / Layer1Base pair under the same parent, or null.
static func partner_of(layer: TileMapLayer) -> TileMapLayer:
	if layer == null:
		return null
	var p := layer.get_parent()
	if p == null:
		return null
	if layer.name == TOP_LAYER:
		return p.get_node_or_null(BASE_LAYER) as TileMapLayer
	if layer.name == BASE_LAYER:
		return p.get_node_or_null(TOP_LAYER) as TileMapLayer
	return null


## The hidden base layer under `layer` (only Layer1 has one), or null.
static func base_layer_of(layer: TileMapLayer) -> TileMapLayer:
	return partner_of(layer) if layer != null and layer.name == TOP_LAYER else null


## Overlay entry {key, source, coords} of a group, or {} when the group is no overlay.
static func overlay_spec(tile_set: TileSet, group: int) -> Dictionary:
	if tile_set == null or group < 0 or not tile_set.has_meta(OVERLAY_META):
		return {}
	var d: Dictionary = tile_set.get_meta(OVERLAY_META)
	return d.get(group, {})


static func is_overlay(tile_set: TileSet, group: int) -> bool:
	return not overlay_spec(tile_set, group).is_empty()


## Puts the right base under `cell` before `group` is painted on `layer` (see the header).
static func _prepare_base(layer: TileMapLayer, base: TileMapLayer, cell: Vector2i, group: int) -> void:
	var ts := layer.tile_set
	var spec := overlay_spec(ts, group)
	if spec.is_empty():
		if base.get_cell_source_id(cell) >= 0:
			base.erase_cell(cell)
			_set_fixed(base, cell, false)
		return
	if str(spec.get("key", "")) != "":
		var want_group := tile_group(ts, int(spec.source), spec.coords)
		if group_of(base, cell) != want_group or want_group < 0:
			base.set_cell(cell, int(spec.source), spec.coords)
			_set_fixed(base, cell, false)
		return
	var src := layer.get_cell_source_id(cell)
	if src >= 0 and not is_overlay(ts, group_of(layer, cell)):
		base.set_cell(cell, src, layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell))
		_set_fixed(base, cell, is_fixed(layer, cell))
		return
	if base.get_cell_source_id(cell) >= 0:
		return
	var pick := _neighbour_ground(layer, base, cell)
	if not pick.is_empty():
		base.set_cell(cell, int(pick[0]), pick[1])
		_set_fixed(base, cell, false)


## [source, coords] of the most common ground (base, or a non-overlay tile on the top layer) of
## the 4 orthogonal neighbours; [] when there is none. Ties go to the first in N, E, S, W order.
static func _neighbour_ground(layer: TileMapLayer, base: TileMapLayer, cell: Vector2i) -> Array:
	var counts := {}
	var order := []
	for o in ORTHOGONAL:
		var n: Vector2i = cell + o
		var l := base if base.get_cell_source_id(n) >= 0 else layer
		var sid := l.get_cell_source_id(n)
		if sid < 0 or (l == layer and is_overlay(layer.tile_set, group_of(layer, n))):
			continue
		var key := palette_tile(layer.tile_set, sid, l.get_cell_atlas_coords(n))
		var k := str(key)
		if not counts.has(k):
			counts[k] = 0
			order.append(key)
		counts[k] += 1
	var best := []
	var best_n := 0
	for key in order:
		if counts[str(key)] > best_n:
			best = key
			best_n = counts[str(key)]
	return best


static func is_fixed(layer: TileMapLayer, cell: Vector2i) -> bool:
	return layer.has_meta(FIXED_META) and (layer.get_meta(FIXED_META) as Dictionary).has(cell)


static func _set_fixed(layer: TileMapLayer, cell: Vector2i, fixed: bool) -> void:
	var d: Dictionary = layer.get_meta(FIXED_META, {})
	if fixed:
		d[cell] = true
	else:
		d.erase(cell)
	if d.is_empty():
		if layer.has_meta(FIXED_META):
			layer.remove_meta(FIXED_META)
	else:
		layer.set_meta(FIXED_META, d)


## Paints a tile. Autotiles pick their variant from the neighbours and refresh the 8 neighbours;
## with connect=false (Shift) the given atlas coords are placed as-is and kept fixed.
## On Layer1 with a Layer1Base sibling, overlay autotiles get their base (see the header).
static func paint(layer: TileMapLayer, cell: Vector2i, source_id: int, atlas_coords: Vector2i, connect := true) -> void:
	var group := tile_group(layer.tile_set, source_id, atlas_coords)
	var base := base_layer_of(layer)
	if base != null:
		_prepare_base(layer, base, cell, group)
	# Write first so neighbours see this cell, then choose the variant.
	layer.set_cell(cell, source_id, atlas_coords)
	_set_fixed(layer, cell, group >= 0 and not connect)
	if group >= 0 and connect:
		refresh(layer, cell)
	if base != null:
		refresh(base, cell)
	refresh_neighbours(layer, cell)


## Erases a cell and refreshes the neighbours. Erasing an overlay on Layer1 brings its hidden
## base back up (the next erase clears the cell).
static func erase(layer: TileMapLayer, cell: Vector2i) -> void:
	var base := base_layer_of(layer)
	if base != null and base.get_cell_source_id(cell) >= 0:
		layer.set_cell(cell, base.get_cell_source_id(cell), base.get_cell_atlas_coords(cell), base.get_cell_alternative_tile(cell))
		_set_fixed(layer, cell, is_fixed(base, cell))
		base.erase_cell(cell)
		_set_fixed(base, cell, false)
		refresh(layer, cell)
	else:
		layer.erase_cell(cell)
		_set_fixed(layer, cell, false)
	refresh_neighbours(layer, cell)


## Recomputes the variant (and blend row) of an autotile cell (no-op for plain, empty or fixed
## cells).
static func refresh(layer: TileMapLayer, cell: Vector2i) -> void:
	var group := group_of(layer, cell)
	if group < 0 or is_fixed(layer, cell):
		return
	var src := layer.get_cell_source_id(cell)
	var coords := layer.get_cell_atlas_coords(cell)
	var want := autotile_tile(layer, cell, group, src, coords.y)
	if int(want[0]) != src or want[1] != coords:
		layer.set_cell(cell, int(want[0]), want[1], layer.get_cell_alternative_tile(cell))


## Refreshes the 8 neighbours, on the partner layer too (Layer1 / Layer1Base).
static func refresh_neighbours(layer: TileMapLayer, cell: Vector2i) -> void:
	for o in OFFSETS:
		refresh(layer, cell + o)
	var partner := partner_of(layer)
	if partner != null:
		for o in OFFSETS:
			refresh(partner, cell + o)


## Recomputes every autotile cell in a rectangle (e.g. after a fill or a script build), on the
## partner layer too.
static func refresh_rect(layer: TileMapLayer, rect: Rect2i) -> void:
	var partner := partner_of(layer)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			refresh(layer, Vector2i(x, y))
			if partner != null:
				refresh(partner, Vector2i(x, y))


## Paints many cells with one autotile/plain tile, then fixes the variants once (fast fill).
static func paint_cells(layer: TileMapLayer, cells: Array, source_id: int, atlas_coords: Vector2i) -> void:
	var group := tile_group(layer.tile_set, source_id, atlas_coords)
	var base := base_layer_of(layer)
	for c in cells:
		if base != null:
			_prepare_base(layer, base, c, group)
		layer.set_cell(c, source_id, atlas_coords)
		_set_fixed(layer, c, false)
	var todo := {}
	for c in cells:
		todo[c] = true
		for o in OFFSETS:
			todo[c + o] = true
	for c in todo:
		refresh(layer, c)
		if base != null:
			refresh(base, c)


# --- shadows -----------------------------------------------------------------------------------

## True if any of the given tile layers has a wall-flagged tile at the cell.
static func is_wall(layers: Array, cell: Vector2i) -> bool:
	for l in layers:
		var layer := l as TileMapLayer
		if layer == null or layer.get_cell_source_id(cell) < 0:
			continue
		var td := layer.get_cell_tile_data(cell)
		if td != null and _has_layer(layer.tile_set, "flags") and int(td.get_custom_data("flags")) & FLAG_WALL:
			return true
	return false


## Auto shadow quarter mask for a cell (rule in the header comment).
static func auto_shadow_mask(layers: Array, cell: Vector2i) -> int:
	if is_wall(layers, cell):
		return 0
	if not is_wall(layers, cell + Vector2i(-1, 0)):
		return 0
	if is_wall(layers, cell + Vector2i(-1, -1)):
		return SHADOW_TL | SHADOW_BL
	return SHADOW_BL


## Writes a shadow mask into the Shadows layer (source 0, atlas (mask, 0)); 0 erases.
static func set_shadow(shadow_layer: TileMapLayer, cell: Vector2i, mask: int) -> void:
	if mask & 15 == 0:
		shadow_layer.erase_cell(cell)
	else:
		shadow_layer.set_cell(cell, 0, Vector2i(mask & 15, 0))


static func get_shadow(shadow_layer: TileMapLayer, cell: Vector2i) -> int:
	if shadow_layer.get_cell_source_id(cell) < 0:
		return 0
	return shadow_layer.get_cell_atlas_coords(cell).x


## Shadow pen: adds or removes one quarter (bit 1 TL, 2 TR, 4 BL, 8 BR).
static func toggle_shadow_quarter(shadow_layer: TileMapLayer, cell: Vector2i, quarter_bit: int, on: bool) -> void:
	var m := get_shadow(shadow_layer, cell)
	m = (m | quarter_bit) if on else (m & ~quarter_bit)
	set_shadow(shadow_layer, cell, m)


## Recomputes auto shadows for every cell in rect (overwrites what is there).
static func apply_auto_shadows(layers: Array, shadow_layer: TileMapLayer, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			set_shadow(shadow_layer, c, auto_shadow_mask(layers, c))


## After painting or erasing a wall at `cell`, updates the cells whose auto shadow depends on it
## (the cell itself, its east and south-east neighbours).
static func update_auto_shadows_around(layers: Array, shadow_layer: TileMapLayer, cell: Vector2i) -> void:
	for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1)]:
		var c: Vector2i = cell + o
		set_shadow(shadow_layer, c, auto_shadow_mask(layers, c))
