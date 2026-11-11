@tool
class_name RPGAutotileLayout
extends RefCounted
## Quarter-tile layouts of the autotile blocks used by the XP, VX/VX Ace and MV/MZ profiles.
## Original code written for this project from public descriptions of the sheet formats.
##
## Every autotile cell is drawn from four quarter tiles (TL, TR, BL, BR). RPGAutotile turns a
## neighbour mask into one quarter KIND per quadrant (fill, outer, vert, horz, inner); a layout
## says where in its block the quarter of that kind and quadrant sits. Results are in HALF-TILE
## units relative to the block's top-left corner (multiply by tile_size / 2 for pixels).
##
## "Edge" words used below: a quarter has a horizontal edge when its horizontal neighbour does not
## connect (kinds VERT and OUTER), and a vertical edge when its vertical neighbour does not
## connect (kinds HORZ and OUTER). qx/qy are the quadrant (0 left/top, 1 right/bottom).
##
## LAYOUT_XP  (3 x 4 tiles; RPG Maker XP autotile file)
##   tile (0,0) palette tile, (1,0) unused, (2,0) four inner (concave) corners,
##   tiles (0..2, 1..3) a 3x3 patch: corners outer, sides edges, (1,2) the centre fill.
##   XP picks the patch tile from the WHOLE cell, then takes each quarter from its own quadrant:
##     patch column: E connects, W not -> 0 (left side) | both -> 1 | W connects, E not -> 2
##                   neither -> 0 for the left quarters, 2 for the right ones
##     patch row:    S connects, N not -> 1 (top side)  | both -> 2 | N connects, S not -> 3
##                   neither -> 1 for the top quarters, 3 for the bottom ones
##   An INNER quarter (both orthogonals connect, the diagonal does not) comes from tile (2,0).
##   So a left-edge cell is the whole left patch tile, a corridor is split between two tiles.
##   (The 2000/2003 terrain decoder in RPGChipset2k uses a per-quarter variant of this.)
## LAYOUT_FLOOR  (2 x 3 tiles = 4 x 6 half tiles; VX/MV A1 water, A2 floors, A4 wall tops)
##   tile (0,0) palette tile, tile (1,0) four inner corners, tiles (0..1, 1..2) a 2x2 patch
##   whose border is the outline and whose middle is the fill.
##   INNER  (2+qx, qy)
##   other  x = horizontal edge ? (0 | 3) : (2 | 1)     y = vertical edge ? (2 | 5) : (4 | 3)
##          (first value for qx/qy = 0, second for 1; the fill takes the crossed middle
##          quarters so neighbouring cells continue the texture).
## LAYOUT_WALL  (2 x 2 tiles = 4 x 4 half tiles; VX/MV A3 and the A4 wall sides)
##   no inner corners (diagonals are ignored):
##   x = horizontal edge ? (0 | 3) : (2 | 1)     y = vertical edge ? (0 | 3) : (2 | 1)
## LAYOUT_WATERFALL  (2 x 1 tiles = 4 x 2 half tiles; VX/MV A1 waterfalls)
##   only left/right connections count:  x = horizontal edge ? (0 | 3) : (2 | 1),  y = qy
## LAYOUT_SINGLE  (1 x 1 tile; XP 32x32 "autotiles"): every variant is the tile itself.
##
## Variant 47 (RPGAutotile.PREVIEW_VARIANT) is the palette tile: block tile (0,0) for XP and
## floor layouts, the isolated shape (variant 46) for wall and waterfall layouts.

const LAYOUT_XP := "xp"
const LAYOUT_FLOOR := "floor"
const LAYOUT_WALL := "wall"
const LAYOUT_WATERFALL := "waterfall"
const LAYOUT_SINGLE := "single"

const LAYOUTS: Array[String] = [LAYOUT_XP, LAYOUT_FLOOR, LAYOUT_WALL, LAYOUT_WATERFALL, LAYOUT_SINGLE]


## Block size in tiles.
static func block_tiles(layout: String) -> Vector2i:
	match layout:
		LAYOUT_XP:
			return Vector2i(3, 4)
		LAYOUT_FLOOR:
			return Vector2i(2, 3)
		LAYOUT_WALL:
			return Vector2i(2, 2)
		LAYOUT_WATERFALL:
			return Vector2i(2, 1)
	return Vector2i(1, 1)


static func _h_edge(kind: int) -> bool:
	return kind == RPGAutotile.KIND_VERT or kind == RPGAutotile.KIND_OUTER


static func _v_edge(kind: int) -> bool:
	return kind == RPGAutotile.KIND_HORZ or kind == RPGAutotile.KIND_OUTER


## Half-tile cell (relative to the block) of the quarter of `kind` for quadrant q (0 TL, 1 TR,
## 2 BL, 3 BR).
## Not used for LAYOUT_XP, whose choice depends on the whole cell (see xp_cell).
static func quarter_cell(layout: String, kind: int, q: int) -> Vector2i:
	var qx := q % 2
	var qy := q / 2
	match layout:
		LAYOUT_FLOOR:
			if kind == RPGAutotile.KIND_INNER:
				return Vector2i(2 + qx, qy)
			var fx := (3 if qx else 0) if _h_edge(kind) else (1 if qx else 2)
			var fy := (5 if qy else 2) if _v_edge(kind) else (3 if qy else 4)
			return Vector2i(fx, fy)
		LAYOUT_WALL:
			var wx := (3 if qx else 0) if _h_edge(kind) else (1 if qx else 2)
			var wy := (3 if qy else 0) if _v_edge(kind) else (1 if qy else 2)
			return Vector2i(wx, wy)
		LAYOUT_WATERFALL:
			var hx := (3 if qx else 0) if _h_edge(kind) else (1 if qx else 2)
			return Vector2i(hx, qy)
	return Vector2i(qx, qy)


## The four half-tile cells [TL, TR, BL, BR] of a variant (0..46, or 47 for the palette tile).
static func variant_cells(layout: String, variant: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if variant == RPGAutotile.PREVIEW_VARIANT:
		if layout in [LAYOUT_XP, LAYOUT_FLOOR, LAYOUT_SINGLE]:
			for q in 4:
				out.append(Vector2i(q % 2, q / 2))
			return out
		variant = RPGAutotile.VARIANT_COUNT - 1
	var mask := RPGAutotile.mask_for_variant(variant)
	var kinds := RPGAutotile.quarter_kinds(mask)
	for q in 4:
		if layout == LAYOUT_XP:
			out.append(xp_cell(mask, kinds[q], q))
		else:
			out.append(quarter_cell(layout, kinds[q], q))
	return out


## LAYOUT_XP half-tile cell for quadrant q of a cell with (reduced) neighbour mask `mask`.
static func xp_cell(mask: int, kind: int, q: int) -> Vector2i:
	var qx := q % 2
	var qy := q / 2
	if kind == RPGAutotile.KIND_INNER:
		return Vector2i(4 + qx, qy)
	var w := mask & RPGAutotile.W != 0
	var e := mask & RPGAutotile.E != 0
	var n := mask & RPGAutotile.N != 0
	var s := mask & RPGAutotile.S != 0
	var col := 1
	if w and not e:
		col = 2
	elif e and not w:
		col = 0
	elif not w and not e:
		col = qx * 2
	var row := 2
	if n and not s:
		row = 3
	elif s and not n:
		row = 1
	elif not n and not s:
		row = 1 + qy * 2
	return Vector2i(col * 2 + qx, row * 2 + qy)


## Pixel rects [TL, TR, BL, BR] of a variant for a block at `origin` (pixels) and tile size.
static func variant_rects(layout: String, variant: int, origin: Vector2i, tile_size: int) -> Array[Rect2i]:
	var h := tile_size / 2
	var out: Array[Rect2i] = []
	for c in variant_cells(layout, variant):
		out.append(Rect2i(origin + c * h, Vector2i(h, h)))
	return out
