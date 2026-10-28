extends RefCounted
## Caesar III's town as Urbek-style voxel lots (urbek_kit.gd): streets of
## basalt paving with raised kerbs and stepping stones, row houses with shops
## (tabernae) under striped awnings, an atrium house (domus), an apartment
## block (insula), a temple, gardens and a market. Every model covers whole
## 10 m lots (40 voxels) and may overhang them by MARGIN voxels; it faces
## +z (south). Grid y 0 and 1 are ground; buildings stand on y = 2.

const Kit := preload("res://urbek_kit.gd")
const V := Kit.V
const LOT := Kit.LOT
const MARGIN := 6
const FLOOR := 2
const STOREY0 := 14
const STOREY := 12

## The mesh of a grid whose lot corner sits at (MARGIN, 0, MARGIN): local
## origin at the lot's north-west corner on the ground's base.
static func _done(g: Kit.Grid) -> ArrayMesh:
	return Kit.mesh(g, Vector3(-MARGIN * V, 0.0, -MARGIN * V))

static func _grid(lots_x: int, lots_z: int, height: int) -> Kit.Grid:
	return Kit.Grid.new(Vector3i(lots_x * LOT + 2 * MARGIN, height, lots_z * LOT + 2 * MARGIN))

## Fills x [x0, x1), y [y0, y1) on the layers a .. b - 1 voxels out from
## the face layer zf (negative: into the wall); s is the face's outward z.
static func _zb(g: Kit.Grid, x0: int, y0: int, x1: int, y1: int, zf: int, a: int, b: int, c: int, s: int) -> void:
	var p := zf + s * a
	var q := zf + s * (b - 1)
	g.box(x0, y0, mini(p, q), x1, y1, maxi(p, q) + 1, c)

static func _zp(g: Kit.Grid, x0: int, y0: int, x1: int, y1: int, zf: int, a: int, b: int, c: int, s: int) -> void:
	var p := zf + s * a
	var q := zf + s * (b - 1)
	g.paint(x0, y0, mini(p, q), x1, y1, maxi(p, q) + 1, c)

# --- ground ---------------------------------------------------------------

## Grass over [x0, x1) x [z0, z1), two layers, in calm patches of 6.
static func _grass(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, seed: int) -> void:
	for z in range(z0, z1):
		for x in range(x0, x1):
			var r := Kit.rnd((x + (z / 6 % 2) * 3) / 6, z / 6, 0, seed) % 100
			var c := Kit.GRASS_D if r < 20 else (Kit.GRASS_L if r < 32 else Kit.GRASS)
			g.box(x, 0, z, x + 1, FLOOR, z + 1, c)

## Paving of square slabs (4 voxels, staggered rows), a few a shade off.
static func _paving(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, seed: int) -> void:
	for z in range(z0, z1):
		var row := z / 4
		for x in range(x0, x1):
			var slab := (x + (row % 2) * 2) / 4
			var r := Kit.rnd(slab, row, 7, seed) % 100
			var c := Kit.PAVE_D if r < 10 else (Kit.PAVE_L if r < 20 else Kit.PAVE)
			g.box(x, 0, z, x + 1, FLOOR, z + 1, c)

## Beaten earth with a few darker patches.
static func _earth(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, seed: int) -> void:
	for z in range(z0, z1):
		for x in range(x0, x1):
			g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.EARTH_D if Kit.chance(x / 3, 1, z / 3, seed, 15) else Kit.EARTH)

## Basalt road surface, one voxel lower than the kerbs: stones of 3 x 3,
## staggered, a few a shade off.
static func _basalt(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, seed: int) -> void:
	for z in range(z0, z1):
		var row := z / 3
		for x in range(x0, x1):
			var stone := (x + (row % 3)) / 3
			var r := Kit.rnd(stone, row, 3, seed) % 100
			var c := Kit.BASALT_D if r < 15 else (Kit.BASALT_L if r < 25 else Kit.BASALT)
			g.put(x, 0, z, c)

## A street lot: `ns` false runs east-west. Road 24 voxels (6 m) between
## sidewalks of 8 (2 m) with kerb stones; Pompeii's stepping stones on some,
## a mule cart on others, people on the sidewalks.
static func street(ns: bool, seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 12)
	var m := MARGIN
	_basalt(g, m, m, m + LOT, m + LOT, seed)
	for side in 2:
		var a := m + (0 if side == 0 else LOT - 8)
		var k := a + (7 if side == 0 else 0)
		if ns:
			_paving(g, a, m, a + 8, m + LOT, seed + side)
			g.box(k, 0, m, k + 1, FLOOR, m + LOT, Kit.CURB)
		else:
			_paving(g, m, a, m + LOT, a + 8, seed + side)
			g.box(m, 0, k, m + LOT, FLOOR, k + 1, Kit.CURB)
	if seed % 4 == 0:
		for k in 3:
			var s := m + 11 + k * 7
			if ns:
				g.box(s, 0, m + 18, s + 4, FLOOR, m + 22, Kit.BASALT_L)
			else:
				g.box(m + 18, 0, s, m + 22, FLOOR, s + 4, Kit.BASALT_L)
	elif seed % 4 == 1 and not ns:
		_cart(g, m + 6 + seed % 10, 1, m + 11 + (seed / 4) % 2 * 10, seed)
	for k in 2 + seed % 3:
		var along := m + 3 + Kit.rnd(k, 2, 0, seed) % (LOT - 6)
		var across := m + 1 + Kit.rnd(k, 3, 0, seed) % 4 + (0 if k % 2 == 0 else LOT - 7)
		if ns:
			_person(g, across, FLOOR, along, seed + k)
		else:
			_person(g, along, FLOOR, across, seed + k)
	return _done(g)

## A crossing: basalt cross, sidewalk corners with kerbs; every second one
## has a fountain on a corner, as at Pompeii.
static func crossing(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 8)
	var m := MARGIN
	_basalt(g, m, m, m + LOT, m + LOT, seed)
	for cz in 2:
		for cx in 2:
			var x0 := m + (0 if cx == 0 else LOT - 8)
			var z0 := m + (0 if cz == 0 else LOT - 8)
			_paving(g, x0, z0, x0 + 8, z0 + 8, seed + cx + 2 * cz)
			var kx := x0 + (7 if cx == 0 else 0)
			var kz := z0 + (7 if cz == 0 else 0)
			g.box(kx, 0, z0, kx + 1, FLOOR, z0 + 8, Kit.CURB)
			g.box(x0, 0, kz, x0 + 8, FLOOR, kz + 1, Kit.CURB)
	if seed % 2 == 0:
		_fountain(g, m + LOT - 7, FLOOR, m + 1, 6)
		_person(g, m + LOT - 9, FLOOR, m + 3, seed)
	return _done(g)

## A mule cart along x with a load of amphorae, the mule at +x.
static func _cart(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	g.box(x, y + 2, z, x + 7, y + 3, z + 4, Kit.WOOD)
	g.box(x, y + 3, z, x + 7, y + 4, z + 1, Kit.WOOD_D)
	g.box(x, y + 3, z + 3, x + 7, y + 4, z + 4, Kit.WOOD_D)
	g.box(x + 2, y, z - 1, x + 5, y + 3, z, Kit.WOOD_D)
	g.box(x + 2, y, z + 4, x + 5, y + 3, z + 5, Kit.WOOD_D)
	for k in 3:
		g.box(x + 1 + 2 * k, y + 3, z + 1, x + 2 + 2 * k, y + 6, z + 3, Kit.AMPHORA if (k + seed) % 3 else Kit.BREAD)
	g.box(x + 7, y + 3, z + 1, x + 9, y + 4, z + 3, Kit.WOOD_D)
	g.box(x + 9, y + 3, z + 1, x + 14, y + 6, z + 3, Kit.MULE)
	g.box(x + 9, y, z + 1, x + 10, y + 3, z + 3, Kit.MULE)
	g.box(x + 13, y, z + 1, x + 14, y + 3, z + 3, Kit.MULE)
	g.box(x + 14, y + 5, z + 1, x + 16, y + 7, z + 3, Kit.MULE)
	g.put(x + 14, y + 7, z + 1, Kit.MULE)
	_person(g, x + 10, y, z + 5, seed + 3)

# --- roofs ----------------------------------------------------------------

const TILES := [Kit.TILE, Kit.TILE_D, Kit.TILE_L, Kit.EAVE, Kit.RIDGE]
const TILES_PALE := [Kit.TILE2, Kit.TILE2_D, Kit.TILE2_L, Kit.EAVE2, Kit.RIDGE2]
const TILES_DARK := [Kit.TILE3, Kit.TILE3_D, Kit.TILE3_L, Kit.EAVE3, Kit.RIDGE3]
const TILES_OLD := [Kit.TILE4, Kit.TILE4_D, Kit.TILE4_L, Kit.EAVE4, Kit.RIDGE4]
const TILES_LICHEN := [Kit.TILE5, Kit.TILE5_D, Kit.TILE5_L, Kit.EAVE5, Kit.RIDGE5]
const TILES_LEAD := [Kit.LEAD, Kit.LEAD_D, Kit.LEAD_L, Kit.EAVEL, Kit.RIDGEL]
# Roof colours a town shows, by share: fresh terracotta half, then dark,
# sun-bleached, old and lichened tiles.
const ROOFS := [TILES, TILES, TILES, TILES, TILES, TILES, TILES, TILES, TILES, TILES,
	TILES_DARK, TILES_DARK, TILES_DARK, TILES_DARK, TILES_PALE, TILES_PALE, TILES_PALE,
	TILES_OLD, TILES_OLD, TILES_LICHEN]

## A field tile: the cover tiles (imbrices) run down the slope as faint
## lighter ribs every third voxel; a few darker and lighter tiles in short
## runs, as Urbek's. `along` is the eave's direction ("x" or "z").
static func _field(x: int, z: int, h: int, set: Array, seed: int, along := "x") -> int:
	var across := x if along == "x" else z
	if along != "hip" and posmod(across, 3) == 0:
		return set[2]
	var r := Kit.rnd((x + (z % 3)) / 3, z, h, seed) % 100
	if r < 5:
		return set[1]
	if r < 8:
		return set[2]
	return set[0]

## A tiled roof as a height field over `outer` (grid x, z): every column
## rises one voxel for every two in from the eaves (`mode` "x": ridge along
## x, eaves north and south; "z": ridge along z; "hip": eaves all round)
## and from the courtyard openings `holes`. The top voxel is a tile from
## `set` (field, darker, lighter, eave board, ridge); under it, inside the
## `solid` rects, the roof fills with `fill` (gable ends show it), elsewhere
## the roof is a single overhanging layer. Returns the highest step.
static func _roof(g: Kit.Grid, outer: Rect2i, holes: Array, solid: Array, y: int, mode: String, set: Array, fill: int, seed: int, steep := false) -> int:
	var w := outer.size.x
	var d := outer.size.y
	var hs := PackedInt32Array()
	hs.resize(w * d)
	var hmax := 0
	for z in d:
		for x in w:
			var p := outer.position + Vector2i(x, z)
			var dist := 1 << 20
			if mode != "z":
				dist = mini(dist, mini(z, d - 1 - z))
			if mode != "x":
				dist = mini(dist, mini(x, w - 1 - x))
			var open := false
			for r: Rect2i in holes:
				if r.has_point(p):
					open = true
					break
				var dx := maxi(maxi(r.position.x - p.x, p.x - r.end.x + 1), 0)
				var dz := maxi(maxi(r.position.y - p.y, p.y - r.end.y + 1), 0)
				dist = mini(dist, maxi(dx, dz) - 1)
			var h := -1 if open else ((dist * 2) / 3 if steep else dist / 2)
			hs[x + z * w] = h
			hmax = maxi(hmax, h)
	for z in d:
		for x in w:
			var h := hs[x + z * w]
			if h < 0:
				continue
			var p := outer.position + Vector2i(x, z)
			var ridge := true
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				var nx := x + o.x
				var nz := z + o.y
				if nx >= 0 and nz >= 0 and nx < w and nz < d and hs[nx + nz * w] > h:
					ridge = false
					break
			var t: int = set[3] if h == 0 else (set[4] if ridge else _field(p.x, p.y, h, set, seed, "x" if mode == "x" else ("z" if mode == "z" else "hip")))
			# a dark verge board along the gable edges of a ridge along z
			if mode == "z" and h > 0 and (z == 0 or z == d - 1):
				t = Kit.VERGE
			g.put(p.x, y + h, p.y, t)
			if h > 0:
				for r: Rect2i in solid:
					if r.has_point(p):
						g.box(p.x, y, p.y, p.x + 1, y + h, p.y + 1, fill)
						break
	return hmax

## Gable roof over the walls [x0, x1) x [z0, z1) topping out at y: the
## ridge along x with eaves two voxels out front and back, or, `front`, the
## ridge along z with the gable over the street front and verges one out.
## 27 degrees, or 34 when `steep`. A row of ridge tiles on top. Returns the
## highest step.
static func _gable(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, y: int, set: Array, fill: int, seed: int, front := false, steep := false) -> int:
	var walls := [Rect2i(x0, z0, x1 - x0, z1 - z0)]
	if front:
		var hz := _roof(g, Rect2i(x0, z0 - 1, x1 - x0, z1 - z0 + 2), [], walls, y, "z", set, fill, seed, steep)
		var xc := x0 + (x1 - x0 - 1) / 2
		g.box(xc, y + hz + 1, z0 - 1, xc + 1 + (x1 - x0 + 1) % 2, y + hz + 2, z1 + 1, set[4])
		return hz
	var outer := Rect2i(x0, z0 - 2, x1 - x0, z1 - z0 + 4)
	var hmax := _roof(g, outer, [], walls, y, "x", set, fill, seed, steep)
	var zc := outer.position.y + (outer.size.y - 1) / 2
	g.box(x0, y + hmax + 1, zc, x1, y + hmax + 2, zc + 1 + (outer.size.y + 1) % 2, set[4])
	return hmax

# --- facades --------------------------------------------------------------

## A window `w` x `h` from (x, y) in the face layer zf facing s: recessed
## one voxel onto dark glass, a sill one voxel out, a light lintel; shutters
## open either side, or closed over the glass; a flower box when asked.
static func _window(g: Kit.Grid, x: int, y: int, zf: int, w: int, h: int, o: Dictionary, s := 1) -> void:
	var shutter: int = o.get("shutter", Kit.EMPTY)
	var closed: bool = o.get("closed", false) and shutter != Kit.EMPTY
	_zb(g, x, y, x + w, y + h, zf, 0, 1, Kit.EMPTY, s)
	_zb(g, x, y, x + w, y + h, zf, -1, 0, shutter if closed else Kit.GLASS, s)
	if closed:
		_zb(g, x + w / 2, y, x + w / 2 + 1, y + h, zf, -1, 0, Kit.WOOD_D, s)
	_zb(g, x - 1, y - 1, x + w + 1, y, zf, 0, 2, Kit.TRIM, s)
	_zp(g, x - 1, y + h, x + w + 1, y + h + 1, zf, 0, 1, Kit.TRIM, s)
	if shutter != Kit.EMPTY and not closed:
		_zp(g, x - 2, y, x, y + h, zf, 0, 1, shutter, s)
		_zp(g, x + w, y, x + w + 2, y + h, zf, 0, 1, shutter, s)
	if o.get("flowers", false):
		_zb(g, x, y, x + w, y + 1, zf, 1, 2, Kit.POT, s)
		for k in w:
			var f: int = [Kit.FLOWER_R, Kit.LEAF, Kit.FLOWER_P, Kit.LEAF_L][(k + x) % 4]
			g.put(x + k, y + 1, zf + s, f)

## A plank door, 4 wide, recessed one voxel in a light frame, steps out.
static func _door(g: Kit.Grid, x: int, y: int, zf: int, s := 1, h := 9) -> void:
	_zb(g, x, y, x + 4, y + h, zf, 0, 1, Kit.EMPTY, s)
	for k in 4:
		_zb(g, x + k, y, x + k + 1, y + h, zf, -1, 0, Kit.DOOR if k % 2 == 0 else Kit.DOOR_D, s)
	_zp(g, x - 1, y, x, y + h, zf, 0, 1, Kit.TRIM, s)
	_zp(g, x + 4, y, x + 5, y + h, zf, 0, 1, Kit.TRIM, s)
	_zb(g, x - 1, y + h, x + 5, y + h + 1, zf, 0, 2, Kit.TRIM, s)
	_zb(g, x - 1, y - 2, x + 5, y, zf, 1, 2, Kit.STEP, s)
	_zb(g, x - 1, y - 2, x + 5, y - 1, zf, 2, 3, Kit.STEP, s)

## Goods along x from x0 to x1 at row y on layer z.
static func _goods(g: Kit.Grid, x0: int, x1: int, y: int, z: int, kind: int, seed: int) -> void:
	match kind:
		0: # fruit and vegetables in baskets
			for x in range(x0, x1 - 1, 3):
				g.box(x, y, z, x + 2, y + 1, z + 1, Kit.WOOD)
				var f: int = [Kit.FRUIT_R, Kit.FRUIT_Y, Kit.FRUIT_G][Kit.rnd(x, y, z, seed) % 3]
				g.box(x, y + 1, z, x + 2, y + 2, z + 1, f)
		1: # amphorae
			for x in range(x0, x1 - 1, 3):
				g.box(x, y, z, x + 2, y + 3, z + 1, Kit.AMPHORA)
				g.put(x, y + 3, z, Kit.AMPHORA)
		2: # bolts of cloth
			for x in range(x0, x1 - 2, 3):
				var c: int = [Kit.CLOTH_R, Kit.CLOTH_B, Kit.CLOTH_Y, Kit.CLOTH_W, Kit.CLOTH_G][Kit.rnd(x, y, z, seed) % 5]
				g.box(x, y, z, x + 3, y + 1 + Kit.rnd(x, 1, z, seed) % 2, z + 1, c)
		_: # loaves
			for x in range(x0, x1, 2):
				g.put(x, y, z, Kit.BREAD)

## A shop front: an opening `w` wide and 9 high, three voxels deep, a
## counter with goods, a shelf at the back, a beam over it and a striped
## awning on two poles.
static func _shop(g: Kit.Grid, x: int, y: int, zf: int, w: int, wall: int, o: Dictionary, seed: int, s := 1) -> void:
	_zb(g, x, y, x + w, y + 9, zf, -2, 2, Kit.EMPTY, s)
	_zb(g, x, y - 2, x + w, y, zf, -2, 1, Kit.PAVE_D, s)
	_zb(g, x, y - 2, x + w, y - 1, zf, 1, 2, Kit.STEP, s)
	_zb(g, x, y, x + w, y + 9, zf, -3, -2, Kit.DARK, s)
	var kind: int = o.get("goods", 0)
	_zb(g, x, y + 4, x + w, y + 5, zf, -2, -1, Kit.WOOD_D, s)
	_goods(g, x + 1, x + w - 1, y + 5, zf - 2 * s, kind, seed + 1)
	var c1 := x + w - 4
	_zb(g, x, y, c1, y + 4, zf, -1, 1, wall, s)
	_zb(g, x, y + 4, c1, y + 5, zf, -1, 2, Kit.TRIM, s)
	_goods(g, x + 1, c1 - 1, y + 5, zf, kind, seed)
	_zb(g, x - 1, y + 9, x + w + 1, y + 10, zf, 0, 2, Kit.WOOD_D, s)
	var cloth: Array = o.get("awning", [])
	if kind == 3:
		# a tavern: tables and stools out front
		for t in 2:
			var tx := x + 1 + t * (w / 2)
			_zb(g, tx + 1, y - 2, tx + 2, y + 1, zf, 3, 4, Kit.WOOD_D, s)
			_zb(g, tx, y + 1, tx + 3, y + 2, zf, 2, 5, Kit.WOOD, s)
			_zb(g, tx - 2, y - 2, tx - 1, y, zf, 3, 4, Kit.WOOD_D, s)
			_zb(g, tx + 4, y - 2, tx + 5, y, zf, 3, 4, Kit.WOOD_D, s)
			g.put(tx + 1, y + 2, zf + 3 * s, Kit.AMPHORA)
	if cloth.is_empty():
		# a painted sign over the shop shows the trade
		var sx := x + w / 2 - 3
		_zb(g, sx, y + 10, sx + 6, y + 12, zf, 0, 2, Kit.CLOTH_W, s)
		var icon: int = [Kit.FRUIT_R, Kit.AMPHORA, Kit.CLOTH_B, Kit.BREAD][kind % 4]
		g.box(sx + 2, y + 10, zf + s, sx + 4, y + 12, zf + s + 1, icon)
		return
	for off in range(2, 7):
		var yy := y + 10 - (off - 2) / 2
		for xx in range(x - 1, x + w + 1):
			g.put(xx, yy, zf + s * off, cloth[((xx - x + 1) / 2) % 2])
	for xx in range(x - 1, x + w + 1):
		g.put(xx, y + 7, zf + s * 6, cloth[((xx - x + 1) / 2) % 2])
	_zb(g, x - 1, y - 2, x, y + 7, zf, 6, 7, Kit.WOOD_D, s)
	_zb(g, x + w, y - 2, x + w + 1, y + 7, zf, 6, 7, Kit.WOOD_D, s)

## A wooden balcony on row y along the face, three voxels deep, with
## brackets, posts, a rail and pots of flowers.
static func _balcony(g: Kit.Grid, x0: int, x1: int, y: int, zf: int, seed: int, s := 1) -> void:
	_zb(g, x0, y, x1, y + 1, zf, 1, 4, Kit.WOOD, s)
	for x in range(x0, x1, 3):
		_zb(g, x, y - 1, x + 1, y, zf, 1, 3, Kit.WOOD_D, s)
	for x in range(x0, x1, 2):
		_zb(g, x, y + 1, x + 1, y + 4, zf, 3, 4, Kit.WOOD_D, s)
	_zb(g, x0, y + 4, x1, y + 5, zf, 3, 4, Kit.WOOD, s)
	_zb(g, x0, y + 1, x0 + 1, y + 5, zf, 1, 4, Kit.WOOD_D, s)
	_zb(g, x1 - 1, y + 1, x1, y + 5, zf, 1, 4, Kit.WOOD_D, s)
	for x in range(x0 + 2, x1 - 2, 5):
		if Kit.chance(x, y, zf, seed, 60):
			g.put(x, y + 1, zf + 2 * s, Kit.POT)
			g.put(x, y + 2, zf + 2 * s, [Kit.FLOWER_R, Kit.LEAF_L, Kit.FLOWER_P, Kit.FLOWER_Y][Kit.rnd(x, 0, 0, seed) % 4])

## Weathering on a face layer: darker plaster along the foot, ragged at
## the top; streaks running down from sills.
static func _weather(g: Kit.Grid, x0: int, x1: int, y: int, zf: int, wall: int, seed: int) -> void:
	for x in range(x0, x1):
		var h := 1 + Kit.rnd(x / 2, 0, zf, seed) % 3
		g.swap(x, y, zf, x + 1, y + h, zf + 1, wall, wall + 1)

static func _streaks(g: Kit.Grid, x0: int, x1: int, y: int, zf: int, wall: int, seed: int) -> void:
	for x in range(x0, x1):
		if Kit.chance(x, y, zf, seed, 22):
			var n := 2 + Kit.rnd(x, y, 1, seed) % 4
			g.swap(x, y - n, zf, x + 1, y, zf + 1, wall, wall + 1)

## Windows across a face layer: `count` evenly spaced over [x0, x1), a
## fifth of them with closed shutters.
static func _window_row(g: Kit.Grid, x0: int, x1: int, y: int, zf: int, count: int, w: int, h: int, o: Dictionary, wall: int, seed: int, s := 1) -> void:
	for i in count:
		var cx := x0 + ((x1 - x0) * (2 * i + 1)) / (2 * count)
		var wo := o.duplicate()
		wo["flowers"] = o.get("flowers", false) and Kit.chance(cx, y, zf, seed, 35)
		wo["closed"] = Kit.chance(cx, y, zf, seed + 1, 20)
		_window(g, cx - w / 2, y, zf, w, h, wo, s)
		_streaks(g, cx - w / 2, cx - w / 2 + w, y - 1, zf, wall, seed)

## Corner stones up both edges of a face: courses of two rows, three and
## two voxels long in turn.
static func _quoins(g: Kit.Grid, x0: int, x1: int, y0: int, y1: int, zf: int, c: int) -> void:
	for y in range(y0, y1, 2):
		var n := 3 if (y / 2) % 2 == 0 else 2
		g.paint(x0, y, zf, x0 + n, mini(y + 2, y1), zf + 1, c)
		g.paint(x1 - n, y, zf, x1, mini(y + 2, y1), zf + 1, c)

## Aged plaster on a face: a few blotches a shade darker, a patch where
## the plaster is gone and the brick shows.
static func _blotches(g: Kit.Grid, x0: int, x1: int, y0: int, y1: int, zf: int, wall: int, seed: int) -> void:
	if x1 - x0 < 10 or y1 - y0 < 8:
		return
	for k in 3:
		var w := 4 + Kit.rnd(k, 1, zf, seed) % 5
		var h := 3 + Kit.rnd(k, 2, zf, seed) % 4
		var x := x0 + Kit.rnd(k, 3, zf, seed) % maxi(1, x1 - x0 - w)
		var y := y0 + Kit.rnd(k, 4, zf, seed) % maxi(1, y1 - y0 - h)
		g.swap(x, y, zf, x + w, y + h, zf + 1, wall, wall + 1)
	if Kit.chance(x0, y0, zf, seed, 45):
		var x := x0 + 1 + Kit.rnd(5, 5, zf, seed) % maxi(1, x1 - x0 - 5)
		var y := y0 + Kit.rnd(6, 6, zf, seed) % maxi(1, y1 - y0 - 3)
		g.swap(x, y, zf, x + 3, y + 2, zf + 1, wall, Kit.BRICK)
		g.swap(x + 1, y + 2, zf, x + 2, y + 3, zf + 1, wall, Kit.BRICK)

# --- row houses -----------------------------------------------------------

## A row house over [x0, x1) x [z0, z1), front face at z1 - 1, back at z0.
## Keys of `o`: storeys, wall, roof (tile set), front (gable to the
## street), shutter, win (window size), shop (width, 0 = none), goods,
## awning (two cloth colours), balcony, dado, dentils, string, quoins, seed.
static func _house(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, o: Dictionary) -> void:
	var seed: int = o.get("seed", 0)
	var storeys: int = o.get("storeys", 2)
	var wall: int = o.get("wall", Kit.CREAM)
	var y := FLOOR
	var top := y + STOREY0 + STOREY * (storeys - 1)
	var zf := z1 - 1
	var w := x1 - x0
	g.box(x0, y, z0, x1, top, z1, wall)
	# stone plinth, three courses, one voxel proud, front and back
	g.box(x0, y, zf, x1, y + 3, zf + 2, Kit.STONE)
	g.box(x0, y, z0 - 1, x1, y + 3, z0 + 1, Kit.STONE)
	if o.get("dado", false):
		g.paint(x0, y + 3, zf, x1, y + 7, zf + 1, Kit.REDWASH)
		_weather(g, x0, x1, y + 3, zf, Kit.REDWASH, seed)
	else:
		_weather(g, x0, x1, y + 3, zf, wall, seed)
	_weather(g, x0, x1, y + 3, z0, wall, seed + 1)
	_blotches(g, x0, x1, y + 8, top - 3, zf, wall, seed)
	_blotches(g, x0, x1, y + 8, top - 3, z0, wall, seed + 2)
	if o.get("quoins", false):
		_quoins(g, x0, x1, y + 3, top - 2, zf, Kit.STONE)
	var shutter: int = o.get("shutter", Kit.EMPTY)
	var size: Vector2i = [Vector2i(3, 5), Vector2i(4, 6), Vector2i(4, 7)][o.get("win", 1)]
	# ground floor: a shop, or a door and windows
	var shop: int = o.get("shop", 0)
	if shop > 0:
		var sx := x0 + (w - shop) / 2 + (1 if w - shop > 8 else 0)
		_shop(g, sx, y + 2, zf, shop, wall, o, seed)
		if sx - x0 >= 8:
			_door(g, x0 + 2, y + 2, zf)
	else:
		var dx := x0 + 3 + seed % 3
		_door(g, dx, y + 2, zf)
		if x1 - dx > 16:
			_window_row(g, dx + 7, x1 - 2, y + 6, zf, (x1 - dx - 7) / 9, 3, 5, {"shutter": shutter}, wall, seed)
	# upper floors
	var nw := maxi(1, (w - 4) / 10)
	for k in range(1, storeys):
		var base := y + STOREY0 + STOREY * (k - 1)
		if o.get("balcony", false) and k == 1:
			_window_row(g, x0, x1, base + 1, zf, nw, 4, 8, {"shutter": shutter}, wall, seed + k)
			_balcony(g, x0 + 1, x1 - 1, base, zf, seed)
		elif o.get("loggia", false) and k == storeys - 1:
			_loggia(g, x0, x1, base, top - 2, zf, seed)
		else:
			_window_row(g, x0, x1, base + 9 - size.y, zf, nw, size.x, size.y, {"shutter": shutter, "flowers": true}, wall, seed + k)
			if o.get("string", false):
				g.box(x0, base - 1, zf + 1, x1, base, zf + 2, Kit.TRIM)
	# cornice: a light band, beam ends over it, then the eaves
	g.box(x0, top - 2, zf + 1, x1, top - 1, zf + 2, Kit.TRIM)
	g.box(x0, top - 2, z0 - 1, x1, top - 1, z0, Kit.TRIM)
	var front: bool = o.get("front", false)
	if o.get("dentils", false) and not front:
		for x in range(x0, x1, 2):
			g.put(x, top - 1, zf + 1, Kit.WOOD_D)
	var h := _gable(g, x0, z0, x1, z1, top, o.get("roof", TILES), wall, seed, front, o.get("steep", false))
	if front and h >= 4:
		# a small window in the gable
		var xc := x0 + w / 2 - 1
		_zb(g, xc, top + h / 2 - 1, xc + 2, top + h / 2 + 1, zf, 0, 1, Kit.EMPTY, 1)
		_zb(g, xc, top + h / 2 - 1, xc + 2, top + h / 2 + 1, zf, -1, 0, Kit.DARK, 1)
		_zb(g, xc - 1, top + h / 2 - 2, xc + 3, top + h / 2 - 1, zf, 0, 2, Kit.TRIM, 1)
	# back: a door to the yard, windows with sills and shutters
	var bx := x1 - 7 - seed % 3
	_door(g, bx, y + 2, z0, -1)
	if bx - x0 > 10:
		_window_row(g, x0 + 2, bx - 2, y + 6, z0, 1, 3, 5, {"shutter": shutter}, wall, seed + 3, -1)
	for k in range(1, storeys):
		var base := y + STOREY0 + STOREY * (k - 1)
		_window_row(g, x0, x1, base + 4, z0, maxi(1, (w - 6) / 12), 3, 5, {"shutter": shutter, "flowers": true}, wall, seed + 5 + k, -1)

## An open loggia on the top floor: the front set back four voxels behind
## light columns, a door and pots of plants inside.
static func _loggia(g: Kit.Grid, x0: int, x1: int, y0: int, y1: int, zf: int, seed: int) -> void:
	g.box(x0 + 1, y0, zf - 3, x1 - 1, y1, zf + 1, Kit.EMPTY)
	g.box(x0 + 1, y0 - 1, zf - 3, x1 - 1, y0, zf + 1, Kit.PAVE_L)
	for x in range(x0 + 1, x1 - 1, 7):
		g.box(x, y0, zf, x + 2, y1, zf + 1, Kit.WHITE)
		g.box(x, y1 - 1, zf, x + 2, y1, zf + 1, Kit.TRIM)
	g.box(x1 - 3, y0, zf, x1 - 1, y1, zf + 1, Kit.WHITE)
	g.box(x0 + 1, y0, zf, x1 - 1, y0 + 2, zf + 1, Kit.TRIM)
	var dx := (x0 + x1) / 2 - 2
	g.box(dx, y0, zf - 4, dx + 4, y0 + 8, zf - 3, Kit.DOOR_D)
	for k in 3:
		var px := x0 + 4 + k * 9 + seed % 3
		if px + 2 < x1 - 2:
			g.box(px, y0, zf - 2, px + 2, y0 + 2, zf, Kit.POT)
			g.box(px - 1, y0 + 2, zf - 3, px + 3, y0 + 5, zf, Kit.LEAF if k % 2 == 0 else Kit.LEAF_L)

## A back yard over [x0, x1) x [z0, z1): grass, an earth path, a low wall
## with a tile coping, always something green: a fruit tree, a vegetable
## bed and a small tree, a cypress by the jars, or a vine pergola.
static func _yard(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, seed: int) -> void:
	_grass(g, x0, z0, x1, z1, seed)
	var px := x1 - 7 - seed % 3
	for z in range(z0, z1):
		g.box(px, 0, z, px + 4, FLOOR, z + 1, Kit.EARTH_D if (z / 2) % 3 == 0 else Kit.EARTH)
	for side: Array in [[x0, z0, x1, z0 + 1], [x0, z0, x0 + 1, z1], [x1 - 1, z0, x1, z1]]:
		g.box(side[0], FLOOR, side[1], side[2], FLOOR + 5, side[3], Kit.WHITE)
		g.box(side[0], FLOOR + 5, side[1], side[2], FLOOR + 6, side[3], Kit.TILE)
	var depth := z1 - z0
	if depth < 8:
		return
	match seed % 4:
		0:
			_tree(g, x0 + 9, FLOOR, z0 + depth / 2 - 1, 5, seed)
		1:
			for z in range(z0 + 2, z1 - 2, 2):
				g.box(x0 + 3, 0, z, x0 + 13, FLOOR, z + 1, Kit.EARTH_D)
				for x in range(x0 + 3, x0 + 13, 2):
					g.put(x, FLOOR, z, Kit.LEAF_L if (x + z) % 4 else Kit.FRUIT_R)
			_tree(g, x0 + 18, FLOOR, z0 + depth / 2 - 1, 4, seed)
		2:
			g.box(x0 + 3, FLOOR, z0 + 2, x0 + 5, FLOOR + 3, z0 + 4, Kit.AMPHORA)
			g.box(x0 + 6, FLOOR, z0 + 2, x0 + 8, FLOOR + 3, z0 + 4, Kit.AMPHORA)
			_cypress(g, x0 + 12, FLOOR, z0 + 3, 22, seed)
			_cypress(g, x0 + 18, FLOOR, z0 + 4, 18, seed + 1)
		_:
			for p: Vector2i in [Vector2i(x0 + 3, z0 + 2), Vector2i(x0 + 14, z0 + 2), Vector2i(x0 + 3, z1 - 3), Vector2i(x0 + 14, z1 - 3)]:
				g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 9, p.y + 1, Kit.WOOD_D)
			g.box(x0 + 3, FLOOR + 9, z0 + 2, x0 + 15, FLOOR + 10, z1 - 2, Kit.LEAF)
			for x in range(x0 + 4, x0 + 14, 3):
				g.box(x, FLOOR + 10, z0 + 3, x + 2, FLOOR + 11, z1 - 3, Kit.LEAF_L)
			g.box(x0 + 7, FLOOR, z0 + 5, x0 + 11, FLOOR + 3, z1 - 5, Kit.WOOD)
			for k in 3:
				g.box(x0 + 20 + 3 * k, FLOOR + 6, z0 + depth / 2, x0 + 22 + 3 * k, FLOOR + 9, z0 + depth / 2 + 1, Kit.LINEN if k % 2 == 0 else Kit.CLOTH_B)
			g.box(x0 + 19, FLOOR + 9, z0 + depth / 2, x0 + 30, FLOOR + 10, z0 + depth / 2 + 1, Kit.WOOD_D)

const WALLS := [Kit.CREAM, Kit.OCHRE, Kit.PINK, Kit.WHITE, Kit.CREAM, Kit.OCHRE, Kit.WHITE]
const SHUTTERS := [Kit.SHUTTER_G, Kit.SHUTTER_B, Kit.SHUTTER_U, Kit.SHUTTER_O, Kit.EMPTY]
const AWNINGS := [[Kit.CLOTH_R, Kit.CLOTH_W], [Kit.CLOTH_B, Kit.CLOTH_W], [Kit.CLOTH_G, Kit.CLOTH_Y],
	[Kit.CLOTH_Y, Kit.CLOTH_R], [Kit.CLOTH_G, Kit.CLOTH_W], [Kit.CLOTH_B, Kit.CLOTH_Y]]

## The house options of variant `seed`.
static func _options(seed: int, width: int) -> Dictionary:
	var r := func(k: int, n: int) -> int: return Kit.rnd(seed, k, 11, 5) % n
	var storeys: int = [1, 2, 2, 2, 3, 3, 3, 4][r.call(1, 8)]
	var shop := 0
	if r.call(2, 3) > 0 and width >= 16:
		shop = mini(width - 6, 12 + 2 * r.call(3, 3))
	return {
		"seed": seed, "storeys": storeys, "wall": WALLS[r.call(4, WALLS.size())],
		"roof": ROOFS[r.call(5, ROOFS.size())], "front": r.call(14, 20) < 7,
		"shutter": SHUTTERS[r.call(6, SHUTTERS.size())], "win": r.call(15, 3),
		"shop": shop, "goods": r.call(7, 4), "awning": AWNINGS[r.call(8, AWNINGS.size())] if r.call(9, 4) > 0 else [],
		"balcony": storeys >= 2 and r.call(10, 3) == 0, "dado": r.call(11, 3) == 0,
		"dentils": r.call(12, 2) == 0, "string": r.call(13, 10) < 8, "quoins": r.call(16, 10) < 3,
		"steep": r.call(17, 10) < 3, "loggia": storeys >= 3 and r.call(18, 4) == 0,
	}

## A street-front lot with one or two row houses (variant `seed`), their
## fronts on the lot's south edge, yards behind.
static func house_lot(seed: int, via := false) -> ArrayMesh:
	var g := _grid(1, 1, 72)
	var m := MARGIN
	var depth := 24 + 2 * (seed % 3)
	var z1 := m + LOT
	var z0 := z1 - depth
	_paving(g, m, z0, m + LOT, z1, seed)
	_yard(g, m, m, m + LOT, z0 - 1, seed)
	if seed % 4 < 2:
		_house(g, m, z0, m + LOT, z1, _street_front(_options(seed, LOT), via))
	else:
		var a := 16 + 4 * (seed % 3)
		_house(g, m, z0, m + a, z1, _street_front(_options(seed * 7 + 1, a), via))
		_house(g, m + a, z0, m + LOT, z1, _street_front(_options(seed * 7 + 2, LOT - a), via))
	return _done(g)

## On the main street the porticoes shade the fronts: no awnings, no
## balconies, taller houses.
static func _street_front(o: Dictionary, via: bool) -> Dictionary:
	if via:
		o["awning"] = []
		o["balcony"] = false
		o["storeys"] = maxi(o["storeys"], 3)
	return o

# --- plants and people ----------------------------------------------------

## A round tree: a trunk, then a crown of a core cube and four offset
## cubes in three greens, chunky like Urbek's trees. `r` is the core's half
## width in voxels (crown about 4r across).
static func _tree(g: Kit.Grid, x: int, y: int, z: int, r: int, seed: int) -> void:
	var trunk := r + 4
	g.box(x, y, z, x + 2, y + trunk + r, z + 2, Kit.TRUNK)
	var c := Vector3i(x + 1, y + trunk + r, z + 1)
	g.box(c.x - r, c.y - r, c.z - r, c.x + r, c.y + r + 1, c.z + r, Kit.LEAF)
	var s := maxi(3, (r * 4) / 5)
	var lobes: Array[Vector3i] = [Vector3i(1, -1, 0), Vector3i(-1, 0, 1), Vector3i(0, 1, -1), Vector3i(1, 1, 1)]
	var cols: Array[int] = [Kit.LEAF_D, Kit.LEAF_L, Kit.LEAF, Kit.LEAF_L]
	for k in lobes.size():
		var d := lobes[k]
		var j := Vector3i(Kit.rnd(k, 4, 0, seed) % 3 - 1, Kit.rnd(k, 5, 0, seed) % 3 - 1, Kit.rnd(k, 6, 0, seed) % 3 - 1)
		var lc := c + Vector3i(d.x * r * 3 / 4, d.y * r / 2, d.z * r * 3 / 4) + j
		g.box(lc.x - s, lc.y - s, lc.z - s, lc.x + s, lc.y + s, lc.z + s, cols[(k + seed) % 4])

## A cypress: a narrow column of dark green, `h` voxels high, tapering.
static func _cypress(g: Kit.Grid, x: int, y: int, z: int, h: int, seed: int) -> void:
	g.box(x + 1, y, z + 1, x + 3, y + 2, z + 3, Kit.TRUNK)
	var t1 := y + 2 + h * 2 / 3
	g.box(x, y + 2, z, x + 4, t1, z + 4, Kit.CYPRESS)
	g.box(x + 1, y + 3, z - 1, x + 3, t1 - 2, z + 5, Kit.CYPRESS_D)
	g.box(x - 1, y + 4, z + 1, x + 5, t1 - 4 + seed % 3, z + 3, Kit.CYPRESS_D)
	g.box(x + 1, t1, z + 1, x + 3, y + 2 + h, z + 3, Kit.CYPRESS)
	g.box(x, t1, z + 1, x + 4, t1 + 3, z + 3, Kit.CYPRESS)

## A round slab `h` high and `r` voxels in radius.
static func _disc(g: Kit.Grid, cx: int, y: int, cz: int, r: int, h: int, c: int) -> void:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r + r:
				g.box(cx + dx, y, cz + dz, cx + dx + 1, y + h, cz + dz + 1, c)

## An umbrella pine, Rome's tree: a tall trunk, leaning a little, under
## a flat crown of one to three offset discs in two greens.
static func _pine(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	var h := 16 + seed % 13
	var lean := (seed / 13) % 3 - 1
	g.box(x, y, z, x + 2, y + h / 2, z + 2, Kit.TRUNK)
	g.box(x + lean, y + h / 2, z, x + 2 + lean, y + h, z + 2, Kit.TRUNK)
	var r := 6 + seed % 4
	var cx := x + 1 + lean
	_disc(g, cx, y + h, z + 1, r + 2, 2, Kit.PINE_D)
	for k in 1 + (seed / 5) % 3:
		var ox := Kit.rnd(k, 1, 0, seed) % 9 - 4
		var oz := Kit.rnd(k, 2, 0, seed) % 7 - 3
		_disc(g, cx + ox, y + h + 1 + k % 2, z + 1 + oz, r - 1 - k, 2, Kit.PINE if k % 2 == 0 else Kit.PINE_D)
	_disc(g, cx, y + h + 3, z + 1, r - 2, 1, Kit.PINE)

## A person, 1.75 m: legs, tunic, head; standing on y.
static func _person(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	var tunic: int = [Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_B, Kit.CLOTH_Y, Kit.ROBE_W, Kit.CLOTH_G][Kit.rnd(seed, 0, 0, 9) % 6]
	g.box(x, y, z, x + 2, y + 2, z + 1, Kit.SKIN)
	g.box(x, y + 2, z, x + 2, y + 5, z + 1, tunic)
	g.box(x, y + 5, z, x + 2, y + 6, z + 1, Kit.SKIN)
	g.box(x, y + 6, z, x + 2, y + 7, z + 1, Kit.HAIR)

# --- domus ----------------------------------------------------------------

## An atrium house on 2 x 2 lots: one storey round an atrium with its pool
## and a peristyle garden behind, a ring of tiled roofs sloping in to both;
## on the street two shops either side of a framed entrance.
static func domus(seed: int) -> ArrayMesh:
	var g := _grid(2, 2, 40)
	var m := MARGIN
	var x0 := m + 2
	var x1 := m + 78
	var z0 := m + 4
	var z1 := m + 80
	var zf := z1 - 1
	var y := FLOOR
	var top := y + 16
	var wall: int = [Kit.CREAM, Kit.WHITE, Kit.OCHRE][seed % 3]
	_paving(g, m, m, m + 80, m + 80, seed)
	var atrium := Rect2i(m + 32, m + 50, 16, 14)
	var garden := Rect2i(m + 20, m + 14, 40, 20)
	var portico := garden.grow(6)
	# rooms: everything but the open courts and the portico round the garden
	for z in range(z0, z1):
		for x in range(x0, x1):
			var p := Vector2i(x, z)
			if atrium.has_point(p) or portico.has_point(p):
				continue
			g.box(x, y, z, x + 1, top, z + 1, wall)
	_grass(g, garden.position.x, garden.position.y, garden.end.x, garden.end.y, seed)
	# garden: paths in a cross, hedges, a fountain, two trees, flowers
	var gc := garden.get_center()
	g.box(garden.position.x, 0, gc.y - 2, garden.end.x, FLOOR, gc.y + 2, Kit.PAVE)
	g.box(gc.x - 2, 0, garden.position.y, gc.x + 2, FLOOR, garden.end.y, Kit.PAVE)
	for q: Rect2i in [Rect2i(garden.position.x + 1, garden.position.y + 1, gc.x - 3 - garden.position.x, gc.y - 3 - garden.position.y),
			Rect2i(gc.x + 3, garden.position.y + 1, garden.end.x - gc.x - 4, gc.y - 3 - garden.position.y),
			Rect2i(garden.position.x + 1, gc.y + 3, gc.x - 3 - garden.position.x, garden.end.y - gc.y - 4),
			Rect2i(gc.x + 3, gc.y + 3, garden.end.x - gc.x - 4, garden.end.y - gc.y - 4)]:
		g.box(q.position.x, FLOOR, q.position.y, q.end.x, FLOOR + 2, q.position.y + 1, Kit.HEDGE)
		g.box(q.position.x, FLOOR, q.end.y - 1, q.end.x, FLOOR + 2, q.end.y, Kit.HEDGE)
		g.box(q.position.x, FLOOR, q.position.y, q.position.x + 1, FLOOR + 2, q.end.y, Kit.HEDGE)
		g.box(q.end.x - 1, FLOOR, q.position.y, q.end.x, FLOOR + 2, q.end.y, Kit.HEDGE)
		for k in 4:
			g.put(q.position.x + 2 + Kit.rnd(k, q.position.x, 0, seed) % maxi(1, q.size.x - 4), FLOOR, q.position.y + 2 + Kit.rnd(k, q.position.y, 1, seed) % maxi(1, q.size.y - 4), [Kit.FLOWER_R, Kit.FLOWER_Y, Kit.FLOWER_P][k % 3])
	_fountain(g, gc.x - 4, FLOOR, gc.y - 4, 8)
	_tree(g, garden.position.x + 5, FLOOR, garden.position.y + 4, 4, seed)
	_cypress(g, garden.end.x - 8, FLOOR, garden.position.y + 3, 22, seed)
	# portico: paving, columns round the garden under the eaves
	for z in range(portico.position.y, portico.end.y):
		for x in range(portico.position.x, portico.end.x):
			if not garden.has_point(Vector2i(x, z)):
				g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.PAVE_L if (x / 3 + z / 3) % 2 == 0 else Kit.PAVE)
	for x in range(garden.position.x, garden.end.x, 5):
		_column(g, x, y, garden.position.y - 1, top, Kit.WHITE)
		_column(g, x, y, garden.end.y, top, Kit.WHITE)
	for z in range(garden.position.y + 4, garden.end.y - 2, 5):
		_column(g, garden.position.x - 1, y, z, top, Kit.WHITE)
		_column(g, garden.end.x, y, z, top, Kit.WHITE)
	# doorways into the rooms round the courts
	for x in range(portico.position.x + 3, portico.end.x - 4, 8):
		g.box(x, y, portico.position.y - 1, x + 4, y + 10, portico.position.y, Kit.DARK)
		g.box(x, y, portico.end.y, x + 4, y + 10, portico.end.y + 1, Kit.DARK)
	# atrium: pool with a rim, doorways
	g.box(atrium.position.x, 0, atrium.position.y, atrium.end.x, FLOOR, atrium.end.y, Kit.PAVE_L)
	g.box(atrium.position.x + 3, 0, atrium.position.y + 3, atrium.end.x - 3, FLOOR + 1, atrium.end.y - 3, Kit.TRIM)
	g.box(atrium.position.x + 4, 0, atrium.position.y + 4, atrium.end.x - 4, FLOOR, atrium.end.y - 4, Kit.WATER)
	for x in range(atrium.position.x + 2, atrium.end.x - 3, 6):
		g.box(x, y, atrium.position.y - 1, x + 3, y + 10, atrium.position.y, Kit.DARK)
	# street front: red dado, two shops, the entrance between pilasters
	g.paint(x0, y, zf, x1, y + 6, zf + 1, Kit.REDWASH)
	_weather(g, x0, x1, y, zf, Kit.REDWASH, seed)
	g.box(x0, y, zf, x1, y + 1, zf + 2, Kit.STONE)
	var ex := (x0 + x1) / 2 - 3
	_zb(g, ex, y + 1, ex + 6, y + 12, zf, -2, 1, Kit.EMPTY, 1)
	for k in 6:
		g.box(ex + k, y + 1, zf - 2, ex + k + 1, y + 12, zf - 1, Kit.DOOR if k % 2 == 0 else Kit.DOOR_D)
	g.box(ex - 3, y, zf + 1, ex - 1, top - 2, zf + 2, Kit.TRIM)
	g.box(ex + 7, y, zf + 1, ex + 9, top - 2, zf + 2, Kit.TRIM)
	g.box(ex - 4, y + 12, zf, ex + 10, y + 13, zf + 2, Kit.TRIM)
	g.box(ex - 2, y + 13, zf, ex + 8, y + 14, zf + 2, Kit.TRIM)
	g.box(ex, y + 14, zf, ex + 6, y + 15, zf + 2, Kit.TRIM)
	g.box(ex - 1, y, zf + 2, ex + 7, y + 1, zf + 3, Kit.STEP)
	var o := {"goods": seed % 4, "awning": AWNINGS[seed % AWNINGS.size()]}
	_shop(g, x0 + 6, y + 1, zf, 14, wall, o, seed)
	o = {"goods": (seed + 1) % 4, "awning": AWNINGS[(seed + 2) % AWNINGS.size()]}
	_shop(g, x1 - 20, y + 1, zf, 14, wall, o, seed + 7)
	for x in range(x0 + 2, x1 - 3, 9):
		if x + 3 < x0 + 22 or (x > ex - 6 and x < ex + 10) or x + 3 > x1 - 22:
			continue
		g.box(x, y + 10, zf, x + 2, y + 13, zf + 1, Kit.GLASS)
	g.box(x0, top - 2, zf + 1, x1, top - 1, zf + 2, Kit.TRIM)
	# roofs: one ring round both courts, eaves out to the street and in
	var outer := Rect2i(x0 - 1, z0 - 2, x1 - x0 + 2, z1 - z0 + 4)
	var rooms := Rect2i(x0, z0, x1 - x0, z1 - z0)
	_roof(g, outer, [atrium, garden], [rooms], top, "hip", TILES if seed % 2 == 0 else TILES_OLD, wall, seed)
	return _done(g)

## A column two voxels square from y to `top`: base, shaft, capital.
static func _column(g: Kit.Grid, x: int, y: int, z: int, top: int, c: int) -> void:
	g.box(x, y, z, x + 2, top, z + 1, c)
	g.box(x, y, z, x + 2, y + 1, z + 1, Kit.TRIM)
	g.box(x, top - 1, z, x + 2, top, z + 1, Kit.TRIM)

## A square fountain basin `s` wide with a jet column in the middle.
static func _fountain(g: Kit.Grid, x: int, y: int, z: int, s: int) -> void:
	g.box(x, y, z, x + s, y + 2, z + s, Kit.TRIM)
	g.box(x + 1, y, z + 1, x + s - 1, y + 1, z + s - 1, Kit.WATER)
	g.box(x + s / 2 - 1, y, z + s / 2 - 1, x + s / 2 + 1, y + 4, z + s / 2 + 1, Kit.TRIM)
	g.box(x + s / 2 - 1, y + 4, z + s / 2 - 1, x + s / 2 + 1, y + 5, z + s / 2 + 1, Kit.WATER)

# --- insula ---------------------------------------------------------------

## An apartment block on 2 x 1 lots: four or five storeys, brick shops
## with arched openings below, plastered flats above with a long wooden
## balcony, windows in rows, a gable roof and, at one end, a roof terrace
## with a vine pergola, pots and washing.
static func insula(seed: int) -> ArrayMesh:
	var g := _grid(2, 1, 96)
	var m := MARGIN
	var x0 := m + 1
	var x1 := m + 79
	var z0 := m + 6
	var z1 := m + 40
	var zf := z1 - 1
	var y := FLOOR
	var storeys := 4 + seed % 3
	var top := y + STOREY0 + STOREY * (storeys - 1)
	var wall: int = [Kit.OCHRE, Kit.PINK, Kit.CREAM][seed % 3]
	_paving(g, m, m, m + 80, m + 40, seed)
	g.box(x0, y, z0, x1, top, z1, wall)
	g.box(x0, y, z0, x1, y + STOREY0, z1, Kit.BRICK)
	for x in range(x0, x1):
		for yy in range(y, y + STOREY0):
			if Kit.chance(x / 3, yy, 0, seed, 10):
				g.put(x, yy, zf, Kit.BRICK_W)
				g.put(x, yy, z0, Kit.BRICK_W)
	g.box(x0, y, zf, x1, y + 2, zf + 2, Kit.STONE)
	_quoins(g, x0, x1, y + STOREY0, top - 2, zf, Kit.BRICK)
	_blotches(g, x0, x1, y + STOREY0 + 2, top - 3, zf, wall, seed)
	# six shops, arched: an opening 9 wide with a stepped round head
	var bay := (x1 - x0) / 6
	for i in 6:
		var sx := x0 + i * bay + (bay - 9) / 2
		var o := {"goods": (seed + i) % 4, "awning": AWNINGS[(seed + i) % AWNINGS.size()] if (i + seed) % 3 == 0 else []}
		_shop(g, sx, y + 1, zf, 9, Kit.BRICK, o, seed + i)
		_zb(g, sx + 1, y + 10, sx + 8, y + 11, zf, -2, 1, Kit.EMPTY, 1)
		_zb(g, sx + 2, y + 11, sx + 7, y + 12, zf, -2, 1, Kit.EMPTY, 1)
		_zb(g, sx + 1, y + 10, sx + 8, y + 12, zf, -3, -2, Kit.DARK, 1)
		g.box(sx - 1, y + 12, zf, sx + 10, y + 13, zf + 1, Kit.BRICK_W)
		g.box(sx - 1, y + 10, zf, sx, y + 12, zf + 1, Kit.BRICK_W)
		g.box(sx + 9, y + 10, zf, sx + 10, y + 12, zf + 1, Kit.BRICK_W)
	g.box(x0, y + STOREY0 - 1, zf + 1, x1, y + STOREY0, zf + 2, Kit.TRIM)
	var shutter: int = SHUTTERS[seed % SHUTTERS.size()]
	for k in range(1, storeys):
		var base := y + STOREY0 + STOREY * (k - 1)
		if k == 1:
			_window_row(g, x0, x1, base + 1, zf, 7, 4, 8, {"shutter": shutter}, wall, seed + k)
			_balcony(g, x0 + 2, x1 - 2, base, zf, seed)
		else:
			_window_row(g, x0, x1, base + 3, zf, 7, 4, 6, {"shutter": shutter, "flowers": true}, wall, seed + k)
			g.box(x0, base - 1, zf + 1, x1, base, zf + 2, Kit.TRIM)
		_window_row(g, x0, x1, base + 3, z0, 6, 3, 5, {"shutter": shutter}, wall, seed + 9 + k, -1)
	_weather(g, x0, x1, y + STOREY0, zf, wall, seed)
	g.box(x0, top - 2, zf + 1, x1, top - 1, zf + 2, Kit.TRIM)
	for x in range(x0, x1, 2):
		g.put(x, top - 1, zf + 1, Kit.WOOD_D)
	# roof over all but one end, which is a terrace
	var tx := x1 - 16 if seed % 2 == 0 else x0 + 16
	var rx0 := x0 if seed % 2 == 0 else tx
	var rx1 := tx if seed % 2 == 0 else x1
	_gable(g, rx0, z0, rx1, z1, top, ROOFS[seed % ROOFS.size()], wall, seed)
	var ax0 := tx if seed % 2 == 0 else x0
	var ax1 := x1 if seed % 2 == 0 else tx
	g.box(ax0, top, z0, ax1, top + 1, z1, Kit.PAVE)
	for side: Array in [[ax0, z0, ax1, z0 + 1], [ax0, zf, ax1, z1], [ax0, z0, ax0 + 1, z1], [ax1 - 1, z0, ax1, z1]]:
		g.box(side[0], top + 1, side[1], side[2], top + 4, side[3], wall)
		g.box(side[0], top + 4, side[1], side[2], top + 5, side[3], Kit.TRIM)
	for p: Vector2i in [Vector2i(ax0 + 3, z0 + 4), Vector2i(ax1 - 4, z0 + 4), Vector2i(ax0 + 3, z0 + 18), Vector2i(ax1 - 4, z0 + 18)]:
		g.box(p.x, top + 1, p.y, p.x + 1, top + 10, p.y + 1, Kit.WOOD_D)
	g.box(ax0 + 3, top + 10, z0 + 4, ax1 - 3, top + 11, z0 + 19, Kit.LEAF)
	for x in range(ax0 + 4, ax1 - 4, 3):
		g.box(x, top + 11, z0 + 5, x + 2, top + 12, z0 + 18, Kit.LEAF_L)
	for k in 4:
		var px := ax0 + 2 + k * 3
		g.box(px, top + 1, zf - 3, px + 2, top + 3, zf - 1, Kit.POT)
		g.box(px, top + 3, zf - 3, px + 2, top + 4, zf - 1, [Kit.FLOWER_R, Kit.LEAF_L, Kit.FLOWER_Y, Kit.LEAF][k])
	g.box(ax0 + 2, top + 7, z0 + 24, ax1 - 2, top + 8, z0 + 25, Kit.WOOD_D)
	for k in 4:
		g.box(ax0 + 3 + 3 * k, top + 4, z0 + 24, ax0 + 5 + 3 * k, top + 7, z0 + 25, Kit.LINEN if k % 2 == 0 else Kit.CLOTH_R)
	return _done(g)

# --- temple ---------------------------------------------------------------

## A temple on 2 x 2 lots, in variants: four, six or eight columns, three
## podium heights, terracotta or lead roof; a paved precinct with an altar,
## cypresses, statues and people.
static func temple(seed: int) -> ArrayMesh:
	var g := _grid(2, 2, 80)
	var m := MARGIN
	var cols: int = [6, 4, 8][seed % 3]
	var half: int = [23, 17, 27][seed % 3]
	var rise: int = [8, 10, 12][(seed / 3) % 3]
	var front := m + 74 - 2 * rise
	_paving(g, m, m, m + 80, m + 80, seed)
	var stairs := _temple(g, m + 40, m + 8, half, front, cols, rise, 24, seed % 2 == 1, seed)
	var y := FLOOR
	var az := mini(stairs + 2, m + 74)
	g.box(m + 36, y, az, m + 44, y + 4, az + 4, Kit.STONE)
	g.box(m + 36, y + 4, az, m + 44, y + 5, az + 4, Kit.TRIM)
	g.box(m + 38, y + 5, az + 1, m + 42, y + 6, az + 3, Kit.FRUIT_R)
	for p: Vector2i in [Vector2i(m + 4, m + 8), Vector2i(m + 4, m + 30), Vector2i(m + 4, m + 52), Vector2i(m + 72, m + 8), Vector2i(m + 72, m + 30), Vector2i(m + 72, m + 52)]:
		_cypress(g, p.x, FLOOR, p.y, 24 + Kit.rnd(p.x, p.y, 0, seed) % 6, seed + p.y)
	for p: Vector2i in [Vector2i(m + 8, m + 68), Vector2i(m + 68, m + 68)]:
		_statue(g, p.x, y, p.y, seed + p.x)
	for k in 4:
		_person(g, m + 14 + Kit.rnd(k, 8, 0, seed) % 52, FLOOR, m + 66 + Kit.rnd(k, 9, 0, seed) % 10, seed + k)
	return _done(g)

## A statue on a pedestal: stone block, bronze figure.
static func _statue(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	g.box(x, y, z, x + 4, y + 6, z + 4, Kit.STONE)
	g.box(x, y + 5, z, x + 4, y + 6, z + 4, Kit.TRIM)
	g.box(x + 1, y + 6, z + 1, x + 3, y + 14, z + 3, Kit.BRONZE)
	g.box(x + (seed % 2) * 3, y + 11, z + 1, x + 1 + (seed % 2) * 3, y + 13, z + 3, Kit.BRONZE)

## A temple centred on xm, `half` voxels either side, from z0 to its
## front: a podium `rise` high with steps up the front between two walls,
## `cols` columns `col_h` high under a pediment with a relief, two more
## down each side of the porch, the cella behind with a gilt door, an
## entablature with triglyphs, a gable roof along z (terracotta or lead),
## gilt acroteria. Returns the z after the last step.
static func _temple(g: Kit.Grid, xm: int, z0: int, half: int, front: int, cols: int, rise: int, col_h: int, lead: bool, seed: int) -> int:
	var y := FLOOR
	var x0 := xm - half
	var x1 := xm + half
	var podium := y + rise
	var stairs := front + 2 * rise
	var marble := Kit.MARBLE
	var roof: Array = TILES_LEAD if lead else TILES
	g.box(x0, y, z0, x1, podium, front, Kit.STONE)
	g.box(x0 - 1, y, z0 - 1, x1 + 1, y + 1, front + 1, Kit.STONE_W)
	g.box(x0 - 1, podium - 1, z0 - 1, x1 + 1, podium, front + 1, Kit.TRIM)
	for k in rise:
		g.box(x0 + 3, y, front, x1 - 3, y + rise - k, front + 2 + 2 * k, Kit.STEP)
	g.box(x0, y, front, x0 + 3, podium, stairs, Kit.STONE)
	g.box(x1 - 3, y, front, x1, podium, stairs, Kit.STONE)
	g.box(x0, podium - 1, front, x0 + 3, podium, stairs, Kit.TRIM)
	g.box(x1 - 3, podium - 1, front, x1, podium, stairs, Kit.TRIM)
	var cz1 := front - 16
	var col_top := podium + col_h
	g.box(x0 + 3, podium, z0 + 2, x1 - 3, col_top, cz1, marble)
	for x in range(x0 + 3, x1 - 3, 6):
		g.box(x, podium, cz1, x + 2, col_top, cz1 + 1, Kit.MARBLE_W)
	var dh := col_h * 2 / 3
	g.box(xm - 4, podium, cz1 - 1, xm + 4, podium + dh, cz1 + 1, Kit.EMPTY)
	g.box(xm - 4, podium, cz1 - 2, xm + 4, podium + dh, cz1 - 1, Kit.DOOR_D)
	g.box(xm - 1, podium, cz1 - 2, xm + 1, podium + dh, cz1 - 1, Kit.GOLD)
	var xs: Array[int] = []
	for i in cols:
		xs.append(x0 + 2 + (i * (x1 - x0 - 7)) / (cols - 1))
	for x in xs:
		_temple_column(g, x, podium, front - 4, col_top)
	_temple_column(g, xs[0], podium, front - 10, col_top)
	_temple_column(g, xs[cols - 1], podium, front - 10, col_top)
	g.box(x0 + 1, col_top, z0 + 1, x1 - 1, col_top + 2, front - 1, marble)
	g.box(x0 + 1, col_top + 2, z0 + 1, x1 - 1, col_top + 3, front - 1, Kit.MARBLE_W)
	for x in range(x0 + 2, x1 - 2, 4):
		g.box(x, col_top + 2, front - 2, x + 2, col_top + 3, front - 1, Kit.GOLD if lead else Kit.REDWASH)
	g.box(x0, col_top + 3, z0, x1, col_top + 4, front, Kit.TRIM)
	var ry := col_top + 4
	var outer := Rect2i(x0 - 1, z0 - 1, x1 - x0 + 2, front - z0 + 2)
	var hmax := _roof(g, outer, [], [Rect2i(x0, z0, x1 - x0, front - z0)], ry, "z", roof, marble, seed)
	var field := Kit.SHUTTER_U if lead else Kit.REDWASH
	for x in range(x0 + 2, x1 - 2):
		var h := mini(x - outer.position.x, outer.end.x - 1 - x) / 2
		if h >= 2:
			g.box(x, ry, front - 2, x + 1, ry + h - 1, front - 1, field)
			g.box(x, ry, front - 1, x + 1, ry + h - 1, front, Kit.EMPTY)
	g.box(xm - 1, ry, front - 1, xm + 1, ry + mini(hmax - 2, 5), front, marble)
	g.box(xm - 6, ry, front - 1, xm - 3, ry + 2, front, marble)
	g.box(xm + 3, ry, front - 1, xm + 6, ry + 2, front, marble)
	g.box(xm - 1, ry + hmax + 1, front - 1, xm + 1, ry + hmax + 3, front + 1, Kit.GOLD)
	g.box(x0 - 1, ry + 1, front - 1, x0 + 1, ry + 3, front + 1, Kit.GOLD)
	g.box(x1 - 1, ry + 1, front - 1, x1 + 1, ry + 3, front + 1, Kit.GOLD)
	return stairs

## A temple column, three voxels across with the corners cut, a square
## base and capital.
static func _temple_column(g: Kit.Grid, x: int, y: int, z: int, top: int) -> void:
	g.box(x, y, z + 1, x + 3, top, z + 2, Kit.MARBLE)
	g.box(x + 1, y, z, x + 2, top, z + 3, Kit.MARBLE)
	g.box(x + 1, y, z + 2, x + 2, top, z + 3, Kit.MARBLE_W)
	g.box(x - 1, y, z - 1, x + 4, y + 1, z + 4, Kit.TRIM)
	g.box(x - 1, top - 1, z - 1, x + 4, top, z + 4, Kit.TRIM)
	g.box(x, top - 2, z, x + 3, top - 1, z + 3, Kit.MARBLE)

# --- gardens and the market -----------------------------------------------

## A public garden on one lot: paths, hedges, a fountain or a statue, an
## umbrella pine, cypresses, round trees, flowers and a visitor.
static func garden(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 44)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	g.box(m, 0, m + 18, m + LOT, FLOOR, m + 22, Kit.PAVE)
	g.box(m + 18, 0, m, m + 22, FLOOR, m + LOT, Kit.PAVE)
	g.box(m, FLOOR, m + LOT - 1, m + 16, FLOOR + 2, m + LOT, Kit.HEDGE)
	g.box(m + 24, FLOOR, m + LOT - 1, m + LOT, FLOOR + 2, m + LOT, Kit.HEDGE)
	if seed % 2 == 0:
		_fountain(g, m + 16, FLOOR, m + 16, 8)
	else:
		g.box(m + 18, FLOOR, m + 18, m + 22, FLOOR + 5, m + 22, Kit.STONE)
		g.box(m + 19, FLOOR + 5, m + 19, m + 21, FLOOR + 13, m + 21, Kit.BRONZE)
	match seed % 4:
		0, 2:
			_pine(g, m + 7, FLOOR, m + 7, seed)
			_cypress(g, m + 30, FLOOR, m + 4, 22, seed)
			_cypress(g, m + 34, FLOOR, m + 26, 18, seed + 1)
			_tree(g, m + 7, FLOOR, m + 29, 4, seed)
		_:
			_tree(g, m + 7, FLOOR, m + 7, 5, seed)
			_tree(g, m + 30, FLOOR, m + 8, 4, seed + 3)
			_pine(g, m + 29, FLOOR, m + 28, seed + 1)
			_cypress(g, m + 4, FLOOR, m + 28, 20, seed)
	for k in 8:
		g.put(m + 2 + Kit.rnd(k, 0, 1, seed) % 14, FLOOR, m + 24 + Kit.rnd(k, 0, 2, seed) % 14, [Kit.FLOWER_R, Kit.FLOWER_Y, Kit.FLOWER_P][k % 3])
	_person(g, m + 24, FLOOR, m + 21, seed)
	return _done(g)

## A market square on 2 x 2 lots: paving, stalls under striped awnings in
## loose rows (some places empty), goods on the ground, a fountain, a pine,
## people.
static func market(seed: int) -> ArrayMesh:
	var g := _grid(2, 2, 44)
	var m := MARGIN
	_paving(g, m, m, m + 80, m + 80, seed)
	var k := 0
	for row in 3:
		for col in 4:
			k += 1
			if Kit.chance(row, col, 0, seed, 25):
				continue
			var x := m + 4 + col * 19 + Kit.rnd(row, col, 1, seed) % 5 - 2
			var z := m + 6 + row * 24 + Kit.rnd(row, col, 2, seed) % 5 - 2
			_stall(g, x, FLOOR, z, AWNINGS[(k + seed) % AWNINGS.size()], (k + seed) % 4, seed + k)
			if Kit.chance(row, col, 3, seed, 50):
				g.box(x + 14, FLOOR, z + 1, x + 16, FLOOR + 3, z + 3, Kit.AMPHORA)
				g.box(x + 14, FLOOR, z + 4, x + 16, FLOOR + 1, z + 6, Kit.WOOD)
				g.box(x + 14, FLOOR + 1, z + 4, x + 16, FLOOR + 2, z + 6, [Kit.FRUIT_R, Kit.FRUIT_Y, Kit.FRUIT_G][k % 3])
	_fountain(g, m + 36, FLOOR, m + 34, 8)
	_pine(g, m + 70, FLOOR, m + 70, seed)
	for i in 18:
		_person(g, m + 3 + Kit.rnd(i, 4, 0, seed) % 74, FLOOR, m + 15 + 24 * (i % 3) + Kit.rnd(i, 5, 0, seed) % 5, seed + i)
	return _done(g)

## A market stall: a table with goods under an awning on four poles.
static func _stall(g: Kit.Grid, x: int, y: int, z: int, cloth: Array, goods: int, seed: int) -> void:
	g.box(x, y, z, x + 12, y + 4, z + 4, Kit.WOOD_D)
	g.box(x, y + 4, z, x + 12, y + 5, z + 4, Kit.WOOD)
	_goods(g, x + 1, x + 11, y + 5, z + 2, goods, seed)
	_goods(g, x + 1, x + 11, y + 5, z + 1, goods, seed + 3)
	for p: Vector2i in [Vector2i(x, z - 1), Vector2i(x + 11, z - 1), Vector2i(x, z + 6), Vector2i(x + 11, z + 6)]:
		g.box(p.x, y, p.y, p.x + 1, y + 10, p.y + 1, Kit.WOOD_D)
	for zz in range(z - 2, z + 8):
		var yy := y + 10 + mini(zz - z + 2, z + 7 - zz) / 3
		for xx in range(x - 1, x + 13):
			g.put(xx, yy, zz, cloth[((xx - x + 1) / 2) % 2])
	g.box(x + 2, y, z + 5, x + 4, y + 3, z + 7, Kit.AMPHORA)

## A paved plaza lot: variant 0 bare (under big buildings), 1 to 3 with
## people, 4 a statue, 5 a fountain with benches, 6 a tree with a bench,
## 7 a stall.
static func plaza(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 40)
	var m := MARGIN
	_paving(g, m, m, m + LOT, m + LOT, seed)
	if seed == 0:
		return _done(g)
	match seed % 8:
		4:
			_statue(g, m + 18, FLOOR, m + 18, seed)
		5:
			_fountain(g, m + 14, FLOOR, m + 14, 12)
			for b: Vector2i in [Vector2i(m + 6, m + 18), Vector2i(m + 30, m + 18)]:
				_bench(g, b.x, FLOOR, b.y)
		6:
			_tree(g, m + 18, FLOOR, m + 16, 5, seed)
			_bench(g, m + 14, FLOOR, m + 26)
		7:
			_stall(g, m + 14, FLOOR, m + 16, AWNINGS[seed % AWNINGS.size()], seed % 4, seed)
	for k in seed % 3 + 1:
		_person(g, m + 3 + Kit.rnd(k, 6, 0, seed) % 34, FLOOR, m + 3 + Kit.rnd(k, 7, 0, seed) % 34, seed + k)
	return _done(g)

## A stone bench, six voxels long.
static func _bench(g: Kit.Grid, x: int, y: int, z: int) -> void:
	g.box(x, y, z, x + 1, y + 2, z + 2, Kit.STONE)
	g.box(x + 5, y, z, x + 6, y + 2, z + 2, Kit.STONE)
	g.box(x, y + 2, z, x + 6, y + 3, z + 2, Kit.TRIM)

# --- main street, forum, baths ----------------------------------------------

## The main street (via) on one lot, east-west: a basalt road 16 voxels
## wide between sidewalks of 12 under porticoes, columns every 10 voxels at
## the kerb under a beam, a low tiled roof rising to the house fronts.
static func via(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 24)
	var m := MARGIN
	_basalt(g, m, m, m + LOT, m + LOT, seed)
	_paving(g, m, m, m + LOT, m + 12, seed)
	_paving(g, m, m + 28, m + LOT, m + LOT, seed + 1)
	g.box(m, 0, m + 11, m + LOT, FLOOR, m + 12, Kit.CURB)
	g.box(m, 0, m + 28, m + LOT, FLOOR, m + 29, Kit.CURB)
	for side in 2:
		var zc := m + 8 if side == 0 else m + 30
		for x in range(m + 4, m + LOT, 10):
			g.box(x, FLOOR, zc, x + 2, FLOOR + 13, zc + 2, Kit.WHITE)
			g.box(x - 1, FLOOR, zc - 1, x + 3, FLOOR + 1, zc + 3, Kit.TRIM)
			g.box(x - 1, FLOOR + 12, zc - 1, x + 3, FLOOR + 13, zc + 3, Kit.TRIM)
		g.box(m, FLOOR + 13, zc, m + LOT, FLOOR + 14, zc + 2, Kit.WOOD_D)
		var za := m if side == 0 else zc
		var zb := zc + 2 if side == 0 else m + LOT
		for z in range(za, zb):
			var dist := (zb - 1 - z) if side == 0 else (z - za)
			var h := dist / 5
			for x in range(m, m + LOT):
				var t: int = Kit.EAVE if dist == 0 else _field(x, z, h + 1, TILES, seed, "x")
				g.put(x, FLOOR + 14 + h, z, t)
	for k in 3 + seed % 3:
		var x := m + 2 + Kit.rnd(k, 2, 0, seed) % (LOT - 4)
		_person(g, x, FLOOR, m + 2 + Kit.rnd(k, 3, 0, seed) % 5 + (0 if k % 2 == 0 else 28), seed + k)
	if seed % 3 == 1:
		_cart(g, m + 6 + seed % 12, 1, m + 14 + (seed / 3) % 2 * 6, seed)
	return _done(g)

## A stoa: a covered colonnade `depth` voxels deep over [x0, x1) x [z0, z1):
## a back wall with shop doors, a row of columns along the inner edge, a
## tiled lean-to roof falling inwards. `side` names where the back wall is:
## "w", "e" or "s"; `gap` leaves an opening [gap.x, gap.y) along it.
static func _stoa(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, side: String, seed: int, gap := Vector2i(-1, -1)) -> void:
	var along := z1 - z0 if side != "s" else x1 - x0
	var depth := x1 - x0 if side != "s" else z1 - z0
	for u in along:
		var open := u >= gap.x and u < gap.y
		for v in depth:
			var p := Vector2i(x0 + v, z0 + u)
			if side == "e":
				p = Vector2i(x1 - 1 - v, z0 + u)
			elif side == "s":
				p = Vector2i(x0 + u, z1 - 1 - v)
			if open:
				continue
			g.box(p.x, 0, p.y, p.x + 1, FLOOR, p.y + 1, Kit.PAVE_D)
			var h := (depth - 1 - v) / 4
			if v == 0:
				var door := posmod(u, 12) >= 4 and posmod(u, 12) < 9
				g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 16, p.y + 1, Kit.DARK if door and u > 2 and u < along - 3 else Kit.CREAM)
				g.box(p.x, FLOOR + 9 if door else FLOOR + 16, p.y, p.x + 1, FLOOR + 16, p.y + 1, Kit.CREAM)
			elif v >= depth - 3 and v < depth - 1 and posmod(u, 10) < 2:
				g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 14, p.y + 1, Kit.WHITE)
				g.box(p.x, FLOOR + 13, p.y, p.x + 1, FLOOR + 14, p.y + 1, Kit.TRIM)
			if v >= depth - 3:
				g.put(p.x, FLOOR + 14, p.y, Kit.WOOD_D)
			g.put(p.x, FLOOR + 15 + h, p.y, Kit.EAVE if v == depth - 1 else _field(p.x, p.y, h + 1, TILES, seed, "x" if side == "s" else "z"))
			if v == 0:
				g.box(p.x, FLOOR + 16, p.y, p.x + 1, FLOOR + 15 + h + 1, p.y + 1, Kit.CREAM)

## The forum on 5 x 5 lots: a paved square closed by colonnades on three
## sides with shops behind them and a gate to the main street in the south;
## the Capitolium on a high podium at the north end; an altar, statues, a
## fountain, a few stalls and many people.
static func forum(seed: int) -> ArrayMesh:
	var n := 5 * LOT
	var g := _grid(5, 5, 110)
	var m := MARGIN
	for z in range(m, m + n):
		for x in range(m, m + n):
			var slab := ((x - m) / 8 + (z - m) / 8) % 2
			var r := Kit.rnd((x - m) / 8, (z - m) / 8, 0, seed) % 100
			g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.PAVE_L if slab == 0 else (Kit.PAVE_D if r < 30 else Kit.PAVE))
	var d := 14
	_stoa(g, m, m, m + d, m + n, "w", seed)
	_stoa(g, m + n - d, m, m + n, m + n, "e", seed + 1)
	_stoa(g, m + d, m + n - d, m + n - d, m + n, "s", seed + 2, Vector2i(n / 2 - d - 14, n / 2 - d + 14))
	var stairs := _temple(g, m + n / 2, m + 6, 31, m + 84, 8, 14, 32, false, seed)
	g.box(m + n / 2 - 5, FLOOR, stairs + 6, m + n / 2 + 5, FLOOR + 4, stairs + 11, Kit.STONE)
	g.box(m + n / 2 - 5, FLOOR + 4, stairs + 6, m + n / 2 + 5, FLOOR + 5, stairs + 11, Kit.TRIM)
	g.box(m + n / 2 - 2, FLOOR + 5, stairs + 7, m + n / 2 + 2, FLOOR + 6, stairs + 10, Kit.FRUIT_R)
	for x: int in [m + 40, m + n - 44]:
		_statue(g, x, FLOOR, m + 120, seed + x)
		_cypress(g, x - 8, FLOOR, m + 60, 26, seed + x)
	_fountain(g, m + n / 2 - 6, FLOOR, m + 150, 12)
	var k := 0
	for z in range(m + 104, m + n - 30, 22):
		for x: int in [m + 18, m + n - 32]:
			k += 1
			_stall(g, x, FLOOR, z, AWNINGS[(k + seed) % AWNINGS.size()], (k + seed) % 4, seed + k)
	for i in 34:
		_person(g, m + 20 + Kit.rnd(i, 4, 0, seed) % (n - 40), FLOOR, m + 96 + Kit.rnd(i, 5, 0, seed) % (n - 120), seed + i)
	return _done(g)

## Baths (thermae) on 3 x 2 lots: a brick block with plastered bands and
## big arched windows, barrel-vaulted halls either side, a drum with a
## stepped dome over the hot bath in the middle, a pedimented porch to the
## street, a forecourt with a pool, plane trees and bathers.
static func baths(seed: int) -> ArrayMesh:
	var g := _grid(3, 2, 120)
	var m := MARGIN
	var y := FLOOR
	_paving(g, m, m, m + 120, m + 80, seed)
	var x0 := m + 6
	var x1 := m + 114
	var z0 := m + 6
	var z1 := m + 56
	var zf := z1 - 1
	var h := 28
	g.box(x0, y, z0, x1, y + h, z1, Kit.BRICK)
	for xx in range(x0, x1):
		for yy in range(y, y + h):
			if Kit.chance(xx / 3, yy, 1, seed, 9):
				g.put(xx, yy, zf, Kit.BRICK_W)
	g.box(x0, y, zf, x1, y + 2, zf + 2, Kit.STONE)
	g.box(x0, y + 13, zf, x1, y + 14, zf + 2, Kit.TRIM)
	g.box(x0, y + h - 2, zf, x1, y + h, zf + 2, Kit.TRIM)
	# arched windows, two rows
	for wx in range(x0 + 5, x1 - 10, 14):
		if wx > m + 44 and wx < m + 70:
			continue
		for wy: int in [y + 3, y + 15]:
			_zb(g, wx, wy, wx + 8, wy + 8, zf, -1, 1, Kit.EMPTY, 1)
			_zb(g, wx + 1, wy + 8, wx + 7, wy + 9, zf, -1, 1, Kit.EMPTY, 1)
			_zb(g, wx + 2, wy + 9, wx + 6, wy + 10, zf, -1, 1, Kit.EMPTY, 1)
			_zb(g, wx, wy, wx + 8, wy + 10, zf, -2, -1, Kit.GLASS, 1)
			_zb(g, wx + 3, wy, wx + 5, wy + 10, zf, -2, -1, Kit.TRIM, 1)
			g.box(wx - 1, wy - 1, zf, wx + 9, wy, zf + 2, Kit.TRIM)
	# barrel vaults over the side halls (along x), tiles on the curve
	for hall: Vector2i in [Vector2i(x0, m + 44), Vector2i(m + 76, x1)]:
		var zc := (z0 + z1 - 1) / 2.0
		var half := (z1 - z0) / 2.0 + 1.0
		for z in range(z0 - 1, z1 + 1):
			var t := (z - zc) / half
			var vh := roundi(12.0 * sqrt(maxf(0.0, 1.0 - t * t)))
			for x in range(hall.x, hall.y):
				g.box(x, y + h, z, x + 1, y + h + vh, z + 1, Kit.BRICK)
				g.put(x, y + h + vh, z, Kit.EAVE if vh == 0 else _field(x, z, vh, TILES, seed, "x"))
	# drum and dome in the middle
	var c := Vector2i(m + 60, (z0 + z1) / 2)
	var r := 22
	var drum := y + h + 12
	for z in range(c.y - r - 1, c.y + r + 2):
		for x in range(c.x - r - 1, c.x + r + 2):
			var dd := Vector2(x - c.x + 0.5, z - c.y + 0.5).length()
			if dd > r + 0.5:
				continue
			g.box(x, y + h, z, x + 1, drum, z + 1, Kit.BRICK)
			if dd > r - 1.0:
				g.put(x, drum - 1, z, Kit.TRIM)
			if dd < 3.0:
				g.put(x, drum, z, Kit.DEEP)
				continue
			var dh := roundi(sqrt(maxf(0.0, r * r - dd * dd)) * 0.8)
			g.box(x, drum, z, x + 1, drum + dh, z + 1, Kit.LEAD_D)
			var ang := atan2(z - c.y, x - c.x)
			var rib := fposmod(ang * 12.0 / TAU, 1.0) < 0.1
			g.put(x, drum + dh, z, Kit.RIDGEL if rib else (Kit.LEAD_L if dh < 6 else Kit.LEAD))
	g.box(c.x - 2, drum + roundi(r * 0.8) - 2, c.y - 2, c.x + 2, drum + roundi(r * 0.8) + 2, c.y + 2, Kit.EMPTY)
	for k in 12:
		var a := TAU * (k + 0.5) / 12.0
		var px := c.x + roundi(cos(a) * (r + 0.3))
		var pz := c.y + roundi(sin(a) * (r + 0.3))
		if pz >= c.y:
			g.box(px - 1, y + h + 3, pz, px + 2, y + h + 9, pz + 1, Kit.GLASS)
	# porch with a pediment over the entrance
	var stairs := _temple(g, c.x, zf - 2, 13, zf + 14, 4, 2, 22, false, seed)
	g.box(c.x - 4, y, zf - 1, c.x + 4, y + 16, zf + 1, Kit.DOOR_D)
	# forecourt: pool, trees, bathers
	var pz0 := maxi(stairs + 2, m + 66)
	for q: Vector2i in [Vector2i(m + 12, pz0), Vector2i(m + 84, pz0)]:
		g.box(q.x, 0, q.y, q.x + 24, FLOOR + 1, q.y + 10, Kit.TRIM)
		g.box(q.x + 1, 0, q.y + 1, q.x + 23, FLOOR, q.y + 9, Kit.WATER)
	for p: Vector2i in [Vector2i(m + 4, m + 64), Vector2i(m + 110, m + 64)]:
		_tree(g, p.x, FLOOR, p.y, 5, seed + p.x)
	for i in 12:
		_person(g, m + 8 + Kit.rnd(i, 7, 0, seed) % 104, FLOOR, m + 62 + Kit.rnd(i, 8, 0, seed) % 14, seed + i)
	return _done(g)
