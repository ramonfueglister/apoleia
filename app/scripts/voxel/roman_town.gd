extends RefCounted
## Caesar III's town as Urbek-style voxel lots (urbek_kit.gd): streets of
## basalt paving with raised kerbs and stepping stones, row houses with shops
## (tabernae) under striped awnings, an atrium house (domus), an apartment
## block (insula), a temple, gardens and a market. Every model covers whole
## 10 m lots (40 voxels) and may overhang them by MARGIN voxels; it faces
## +z (south). Grid y 0 and 1 are ground; buildings stand on y = 2.

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const V := Kit.V
const LOT := Kit.LOT
const MARGIN := 6
const FLOOR := 2
const STOREY0 := 14
const STOREY := 12

## When set, the builders keep their voxel grid in `last_grid` and return
## no mesh (the game's roman_buildings.gd makes its own levels of detail).
static var keep_grid := false
static var last_grid: Kit.Grid

## The mesh of a grid whose lot corner sits at (MARGIN, 0, MARGIN): local
## origin at the lot's north-west corner on the ground's base.
static func _done(g: Kit.Grid) -> ArrayMesh:
	if keep_grid:
		last_grid = g
		return null
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

## Grass over [x0, x1) x [z0, z1), two layers: three greens in patches of
## three, tufts on one voxel in twenty, now and then a cluster of flowers.
static func _grass(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, seed: int) -> void:
	_lawn(g, x0, z0, x1, z1, 0, FLOOR, seed)

static func _lawn(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, y0: int, y1: int, seed: int) -> void:
	for z in range(z0, z1):
		for x in range(x0, x1):
			var r := Kit.rnd((x + (z / 3 % 2)) / 3, z / 3, 0, seed) % 100
			var c := Kit.GRASS if r < 55 else (Kit.GRASS_D if r < 85 else Kit.GRASS_L)
			g.box(x, y0, z, x + 1, y1, z + 1, c)
			var t := Kit.rnd(x, z, 1, seed) % 1000
			if t < 50:
				g.put(x, y1, z, Kit.GRASS_D)
			elif t < 58 and x > x0 + 1 and z > z0 + 1 and x < x1 - 2 and z < z1 - 2:
				var f: int = [Kit.FLOWER_Y, Kit.FLOWER_R, Kit.FLOWER_W][Kit.rnd(x, z, 2, seed) % 3]
				g.put(x, y1, z, f)
				g.put(x + 1, y1, z, f)
				g.put(x, y1, z + 1, f)

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
	var gx := m + 4 + Kit.rnd(1, 2, 0, seed) % (LOT - 12)
	var side := 0 if seed % 2 == 0 else LOT - 7
	if seed % 3 != 2:
		if ns:
			_turned(g, m + side, FLOOR, gx, func(t: Kit.Grid) -> void: _group(t, 2, 0, 1, 3 + seed % 3, seed))
		else:
			_group(g, gx, FLOOR, m + side, 3 + seed % 3, seed)
	var lone := m + 3 + Kit.rnd(5, 2, 0, seed) % (LOT - 6)
	if ns:
		_person(g, m + (LOT - 5 if seed % 2 == 0 else 2), FLOOR, lone, seed + 5)
	else:
		_person(g, lone, FLOOR, m + (LOT - 5 if seed % 2 == 0 else 2), seed + 5)
	for k in 1 + seed % 2:
		var along := m + 3 + Kit.rnd(k, 8, 0, seed) % (LOT - 6)
		var across := m + 10 + Kit.rnd(k, 9, 0, seed) % 18
		if ns:
			_person(g, across, 1, along, seed + 11 + k)
		else:
			_person(g, along, 1, across, seed + 11 + k)
	if not ns and seed % 5 == 2:
		_donkey(g, m + 6 + seed % 20, 1, m + 20, seed)
	if ns and seed % 4 == 1:
		_turned(g, m + 11 + (seed / 4) % 2 * 10, 1, m + 6 + seed % 14, func(t: Kit.Grid) -> void: _cart(t, 0, 0, 1, seed))
	elif ns and seed % 5 == 2:
		_turned(g, m + 16, 1, m + 6 + seed % 20, func(t: Kit.Grid) -> void: _donkey(t, 0, 0, 1, seed))
	return _done(g)

## Draws `draw` (along x) into a small grid and copies it turned to run
## along z, its corner at (x, y, z).
static func _turned(g: Kit.Grid, x: int, y: int, z: int, draw: Callable) -> void:
	var t := Kit.Grid.new(Vector3i(20, 16, 8))
	draw.call(t)
	for sz in t.n.z:
		for sy in t.n.y:
			for sx in t.n.x:
				var c := t.at(sx, sy, sz)
				if c != Kit.EMPTY:
					g.put(x + sz, y + sy, z + sx, c)

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
		_fountain(g, m + LOT - 7, FLOOR, m + 1, 6, Kit.LAVA)
		_person(g, m + LOT - 9, FLOOR, m + 3, seed)
	else:
		# a crossroads shrine: a painted niche under a small gable, an altar
		var sx := m + LOT - 7
		var sz := m + 1
		g.box(sx, FLOOR, sz, sx + 5, FLOOR + 3, sz + 3, Kit.STONE)
		g.box(sx, FLOOR + 3, sz, sx + 5, FLOOR + 9, sz + 3, Kit.WHITE)
		g.box(sx + 1, FLOOR + 3, sz + 1, sx + 4, FLOOR + 8, sz + 3, Kit.EMPTY)
		g.box(sx + 1, FLOOR + 3, sz + 1, sx + 4, FLOOR + 8, sz + 2, Kit.POMPEII)
		g.box(sx + 2, FLOOR + 3, sz + 2, sx + 3, FLOOR + 6, sz + 3, Kit.GOLD)
		g.box(sx - 1, FLOOR + 9, sz, sx + 6, FLOOR + 10, sz + 4, Kit.TRIM)
		g.box(sx, FLOOR + 10, sz, sx + 5, FLOOR + 11, sz + 4, Kit.TILE)
		g.box(sx + 1, FLOOR + 11, sz, sx + 4, FLOOR + 12, sz + 4, Kit.TILE)
		g.box(sx + 1, FLOOR, sz + 4, sx + 4, FLOOR + 2, sz + 6, Kit.TRIM)
		g.put(sx + 2, FLOOR + 2, sz + 4, Kit.FRUIT_R)
		_person(g, sx - 3, FLOOR, sz + 5, seed)
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
const TILES_GILT := [Kit.GILT, Kit.GILT_D, Kit.GILT_L, Kit.EAVEG, Kit.RIDGEG]
const TILES_COCCIO := [Kit.COCCIO, Kit.COCCIO_D, Kit.COCCIO_L, Kit.COCCIO_D, Kit.COCCIO_D]
# weathered bronze tiles (the Pantheon's porch)
const TILES_BRONZE := [Kit.ROOFB, Kit.ROOFB, Kit.ROOFB_L, Kit.ROOFB_D, Kit.ROOFB_D]
# Roofs were terracotta (Pliny NH 16.36): fresh, darker and sun-bleached.
const ROOFS := [TILES, TILES, TILES, TILES, TILES, TILES, TILES, TILES, TILES, TILES,
	TILES_DARK, TILES_DARK, TILES_DARK, TILES_DARK, TILES_PALE, TILES_PALE, TILES_PALE]

## A field tile: the cover tiles (imbrices) run down the slope as faint
## lighter ribs every third voxel; a few darker and lighter tiles in short
## runs, as Urbek's. `along` is the eave's direction ("x" or "z").
static func _field(x: int, z: int, h: int, set: Array, seed: int, along := "x") -> int:
	var across := x if along == "x" else z
	if along != "hip" and posmod(across, 3) == 0:
		return set[2]
	# a metal roof (darker tile as the field): ribs only, no odd tiles
	if set[1] == set[0]:
		return set[0]
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
static func _roof(g: Kit.Grid, outer: Rect2i, holes: Array, solid: Array, y: int, mode: String, set: Array, fill: int, seed: int, steep := false, verge := Kit.VERGE) -> int:
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
				t = verge
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
	if o.get("grille", false):
		for k in range(1, w, 2):
			_zb(g, x + k, y, x + k + 1, y + h, zf, 0, 1, Kit.IRON, s)
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
	_zb(g, x, y, x + w, y + 9, zf, -3, -2, Kit.ARCADE, s)
	_zb(g, x + w - 3, y, x + w - 1, y + 7, zf, -3, -2, Kit.DARK, s)
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
		# a tavern (thermopolium): jars sunk into the counter
		for jx in range(x + 1, c1 - 1, 3):
			_zb(g, jx, y + 4, jx + 1, y + 5, zf, -1, 0, Kit.DEEP, s)
			_zb(g, jx + 1, y + 4, jx + 2, y + 5, zf, -1, 0, Kit.AMPHORA, s)
		# tables and stools out front
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
	var c := _grime(wall)
	for x in range(x0, x1, 2):
		if Kit.chance(x, y, zf, seed, 40):
			var n := 4 + Kit.rnd(x, y, 1, seed) % 6
			g.swap(x, y - n, zf, x + 2, y, zf + 1, wall, c)
			g.swap(x, y - n - 2, zf, x + 1, y - n, zf + 1, wall, c)

## The colour rain streaks leave on a wall: grey-brown grime on the pale
## plasters, a darker shade of the colour on the strong ones.
static func _grime(wall: int) -> int:
	return Kit.STREAK if wall in [Kit.CREAM, Kit.WHITE, Kit.OCHRE, Kit.PINK, Kit.LIME] else wall + 1

## Windows across a face layer: `count` evenly spaced over [x0, x1), a
## fifth of them with closed shutters.
static func _window_row(g: Kit.Grid, x0: int, x1: int, y: int, zf: int, count: int, w: int, h: int, o: Dictionary, wall: int, seed: int, s := 1) -> void:
	for i in count:
		var cx := x0 + ((x1 - x0) * (2 * i + 1)) / (2 * count)
		var wo := o.duplicate()
		wo["flowers"] = o.get("flowers", false) and Kit.chance(cx, y, zf, seed, 15)
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
	var g0: int = STOREY0 + o.get("lift", 0)
	var top := y + g0 + STOREY * (storeys - 1)
	var zf := z1 - 1
	var w := x1 - x0
	g.box(x0, y, z0, x1, top, z1, wall)
	if wall == Kit.BRICKFACE:
		# brick facing: a light mortar course every third row
		for yy in range(y + 2, top, 3):
			g.swap(x0, yy, zf, x1, yy + 1, zf + 1, wall, Kit.MORTAR)
			g.swap(x0, yy, z0, x1, yy + 1, z0 + 1, wall, Kit.MORTAR)
	if o.get("timber", false) and storeys >= 2:
		# the top storey in timber framing: dark posts, a beam at the floor
		var tb := y + g0 + STOREY * (storeys - 2)
		for f: int in [zf, z0]:
			g.paint(x0, tb, f, x1, top, f + 1, Kit.TIMBER)
			for x in range(x0, x1, 4):
				g.paint(x, tb, f, x + 1, top, f + 1, Kit.TIMBER_W)
			g.paint(x0, tb, f, x1, tb + 1, f + 1, Kit.TIMBER_W)
	# stone plinth, three courses, one voxel proud, front and back
	g.box(x0, y, zf, x1, y + 3, zf + 2, Kit.STONE)
	g.box(x0, y, z0 - 1, x1, y + 3, z0 + 1, Kit.STONE)
	if wall == Kit.RUBBLE:
		# opus incertum: irregular grey stones, brick at the corners
		for f: int in [zf, z0]:
			for yy in range(y, top):
				for x in range(x0, x1):
					if Kit.rnd((x + (yy / 2) % 2) / 2, yy / 2, f, seed) % 100 < 35:
						g.swap(x, yy, f, x + 1, yy + 1, f + 1, wall, Kit.RUBBLE_D)
		_quoins(g, x0, x1, y + 3, top - 2, zf, Kit.BRICKFACE)
	if wall == Kit.LIME or o.get("dado", false):
		g.paint(x0, y + 3, zf, x1, y + 8, zf + 1, o.get("socle", Kit.SOCLE_R))
	else:
		_weather(g, x0, x1, y + 3, zf, wall, seed)
	# grime under the cornice, rain streaks down from it
	for x in range(x0, x1):
		if Kit.chance(x / 2, top, zf, seed, 65):
			g.swap(x, top - 4 + Kit.rnd(x, 3, zf, seed) % 2, zf, x + 1, top - 2, zf + 1, wall, _grime(wall))
	for x in range(x0, x1):
		if Kit.chance(x, top, zf, seed, 12):
			g.swap(x, top - 3 - Kit.rnd(x, 2, zf, seed) % 16, zf, x + 1, top - 2, zf + 1, wall, _grime(wall))
	_weather(g, x0, x1, y + 3, z0, wall, seed + 1)
	_blotches(g, x0, x1, y + 8, top - 3, zf, wall, seed)
	_blotches(g, x0, x1, y + 8, top - 3, z0, wall, seed + 2)
	if o.get("quoins", false):
		_quoins(g, x0, x1, y + 3, top - 2, zf, Kit.STONE)
	if o.get("dipinti", false) and wall != Kit.BRICKFACE:
		# election notices painted in red letters on the plaster
		var px := x0 + 2 + seed % 5
		for row in 2:
			for k in range(0, mini(14, w - 6), 1):
				if Kit.rnd(px + k, row, zf, seed) % 100 < 60:
					g.swap(px + k, y + 12 - row * 2, zf, px + k + 1, y + 13 - row * 2, zf + 1, wall, Kit.LETTER)
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
		var zg := zf
		if o.get("porch", false):
			# a porch: the ground floor set back four voxels behind columns
			zg = zf - 4
			g.box(x0 + 1, y + 3, zf - 3, x1 - 1, y + g0 - 1, zf + 1, Kit.EMPTY)
			g.box(x0 + 1, y + 2, zf - 3, x1 - 1, y + 3, zf + 1, Kit.PAVE_L)
			for cx in range(x0 + 1, x1 - 2, 8):
				g.box(cx, y + 3, zf - 1, cx + 2, y + g0 - 1, zf + 1, Kit.WHITE)
				g.box(cx, y + g0 - 2, zf - 1, cx + 2, y + g0 - 1, zf + 1, Kit.TRIM)
			g.box(x1 - 3, y + 3, zf - 1, x1 - 1, y + g0 - 1, zf + 1, Kit.WHITE)
			g.box(x0 + 3, y + 3, zf - 2, x0 + 5, y + 5, zf, Kit.POT)
			g.box(x0 + 2, y + 5, zf - 3, x0 + 6, y + 8, zf, Kit.LEAF)
		var dx := x0 + 7 + seed % 3
		_door(g, dx, y + 2 + (1 if zg != zf else 0), zg)
		if x1 - dx > 16:
			# small windows high in the street wall, barred with iron
			_window_row(g, dx + 7, x1 - 2, y + 8, zg, (x1 - dx - 7) / 9, 3, 3, {"grille": true}, wall, seed)
	# upper floors
	var nw := maxi(1, (w - 4) / 10)
	for k in range(1, storeys):
		var base := y + g0 + STOREY * (k - 1)
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
	var h := 0
	if o.get("hip", false) and not front:
		h = _roof(g, Rect2i(x0 - 1, z0 - 2, w + 2, z1 - z0 + 4), [], [Rect2i(x0, z0, w, z1 - z0)], top, "hip", o.get("roof", TILES), wall, seed)
	else:
		h = _gable(g, x0, z0, x1, z1, top, o.get("roof", TILES), wall, seed, front, o.get("steep", false))
	if o.get("tower", false) and w >= 20:
		# a tower room over one end, a storey above the ridge, hipped roof
		var tx0 := x0 + 2 if seed % 2 == 0 else x1 - 14
		var tz1 := z1 - 2
		var tz0 := tz1 - 12
		var tt := top + h + 9
		g.box(tx0, top, tz0, tx0 + 12, tt, tz1, wall)
		g.box(tx0, tt - 2, tz1, tx0 + 12, tt - 1, tz1 + 1, Kit.TRIM)
		_window_row(g, tx0, tx0 + 12, tt - 8, tz1 - 1, 2, 3, 5, {"shutter": shutter}, wall, seed + 9)
		_roof(g, Rect2i(tx0 - 1, tz0 - 1, 14, tz1 - tz0 + 2), [], [Rect2i(tx0, tz0, 12, tz1 - tz0)], tt, "hip", o.get("roof", TILES), wall, seed)
	if false and front and h >= 4:
		# a small window in the gable
		var xc := x0 + w / 2 - 1
		_zb(g, xc, top + h / 2 - 1, xc + 2, top + h / 2 + 1, zf, 0, 1, Kit.EMPTY, 1)
		_zb(g, xc, top + h / 2 - 1, xc + 2, top + h / 2 + 1, zf, -1, 0, Kit.DARK, 1)
		_zb(g, xc - 1, top + h / 2 - 2, xc + 3, top + h / 2 - 1, zf, 0, 2, Kit.TRIM, 1)
	if o.get("wing", false) and w >= 16:
		# a one-storey wing at the back, into the yard: an L-shaped plan
		var wx0 := x0 if seed % 2 == 0 else x1 - w / 2
		var wx1 := wx0 + w / 2
		g.box(wx0, y, z0 - 8, wx1, y + 12, z0, wall)
		g.box(wx0, y, z0 - 9, wx1, y + 2, z0 - 7, Kit.STONE)
		g.paint(wx0 + 2, y + 2, z0 - 8, wx0 + 6, y + 10, z0 - 7, Kit.DOOR_D)
		g.paint(wx1 - 6, y + 6, z0 - 8, wx1 - 3, y + 10, z0 - 7, Kit.GLASS)
		for z in range(z0 - 10, z0):
			var hh := (z - (z0 - 10)) / 3
			for x in range(wx0, wx1):
				g.put(x, y + 12 + hh, z, Kit.EAVE if z == z0 - 10 else _field(x, z, hh + 1, o.get("roof", TILES), seed, "x"))
			if hh > 0:
				g.box(wx0, y + 12, z, wx0 + 1, y + 12 + hh, z + 1, wall)
				g.box(wx1 - 1, y + 12, z, wx1, y + 12 + hh, z + 1, wall)
	# back: a door to the yard, windows with sills and shutters
	var bx := x1 - 7 - seed % 3
	_door(g, bx, y + 2, z0, -1)
	if bx - x0 > 10:
		_window_row(g, x0 + 2, bx - 2, y + 6, z0, 1, 3, 5, {"shutter": shutter}, wall, seed + 3, -1)
	for k in range(1, storeys):
		var base := y + g0 + STOREY * (k - 1)
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
	if seed % 10 == 7:
		# a wooden shed in the corner
		g.box(x1 - 9, FLOOR, z0 + 1, x1 - 2, FLOOR + 6, z0 + 6, Kit.WOOD)
		g.box(x1 - 7, FLOOR, z0 + 6, x1 - 4, FLOOR + 5, z0 + 7, Kit.WOOD_D)
		for z in range(z0, z0 + 8):
			g.box(x1 - 10, FLOOR + 6 + (7 - (z - z0)) / 4, z, x1 - 1, FLOOR + 7 + (7 - (z - z0)) / 4, z + 1, Kit.TILE3 if z > z0 else Kit.EAVE3)
	match seed % 6:
		4:
			# a bakery: lava mills turned by a donkey, a domed oven, sacks
			for k in 2:
				var mx := x0 + 4 + k * 9
				var mz := z0 + depth / 2 - 2
				g.box(mx, FLOOR, mz, mx + 4, FLOOR + 3, mz + 4, Kit.LAVA)
				g.box(mx + 1, FLOOR + 3, mz + 1, mx + 3, FLOOR + 4, mz + 3, Kit.LAVA)
				g.box(mx, FLOOR + 4, mz, mx + 4, FLOOR + 6, mz + 4, Kit.LAVA)
				g.box(mx - 3, FLOOR + 4, mz + 1, mx + 7, FLOOR + 5, mz + 2, Kit.WOOD_D)
			_donkey(g, x0 + 2, FLOOR, z0 + depth / 2 + 3, seed)
			var ox := x0 + 27
			var oz := z0 + depth / 2
			g.box(ox - 3, FLOOR, oz - 3, ox + 3, FLOOR + 3, oz + 3, Kit.BRICK)
			_disc(g, ox, FLOOR + 3, oz, 3, 2, Kit.BRICK)
			_disc(g, ox, FLOOR + 5, oz, 2, 1, Kit.BRICK)
			g.box(ox - 1, FLOOR, oz + 3, ox + 1, FLOOR + 2, oz + 4, Kit.DEEP)
			for k in 12:
				var sx := ox - 1 + Kit.rnd(k, 1, 0, seed) % 2 + k / 5
				g.box(sx, FLOOR + 6 + k, oz - 1, sx + 2 + (1 if k % 3 == 0 else 0), FLOOR + 7 + k, oz + 1, Kit.SMOKE)
			for k in 3:
				g.box(x0 + 3 + 3 * k, FLOOR, z1 - 3, x0 + 5 + 3 * k, FLOOR + 2, z1 - 1, Kit.CLOTH_W)
		5:
			# a fullery: vats of dye and water, cloth on lines
			for k in 6:
				var vx := x0 + 3 + (k % 3) * 7
				var vz := z0 + 2 + (k / 3) * 6
				g.box(vx, FLOOR, vz, vx + 5, FLOOR + 2, vz + 5, Kit.TRIM)
				g.box(vx + 1, FLOOR, vz + 1, vx + 4, FLOOR + 2, vz + 4, [Kit.WATER, Kit.CLOTH_R, Kit.CLOTH_Y, Kit.CLOTH_B, Kit.WATER, Kit.CLOTH_G][k])
				if k % 2 == 0:
					_person(g, vx + 1, FLOOR, vz + 2, seed + k)
			g.box(x0 + 24, FLOOR + 8, z0 + 3, x0 + 25, FLOOR + 9, z1 - 3, Kit.WOOD_D)
			for z in range(z0 + 4, z1 - 4, 3):
				g.box(x0 + 24, FLOOR + 4, z, x0 + 25, FLOOR + 8, z + 2, [Kit.CLOTH_R, Kit.LINEN, Kit.CLOTH_Y, Kit.CLOTH_B][z % 4])
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

# Wall colours by share: pale plasters, Pompeian red, deep ochre, brick.
# Street walls were mostly whitewashed over a red or black socle; a few
# fronts painted in red or ochre, some in brick or rubble work.
const WALLS := [Kit.LIME, Kit.LIME, Kit.LIME, Kit.LIME, Kit.LIME, Kit.LIME, Kit.LIME, Kit.LIME,
	Kit.LIME, Kit.CREAM, Kit.POMPEII, Kit.DOCHRE, Kit.OCHRE, Kit.BRICKFACE, Kit.BRICKFACE,
	Kit.RUBBLE, Kit.RUBBLE, Kit.LIME]
# Shutters were plain wood (weathered dark, brown, bleached), many windows
# had none.
const SHUTTERS := [Kit.WOOD_D, Kit.DOOR, Kit.DOOR_D, Kit.EMPTY, Kit.EMPTY]
# Awnings (vela) of plain linen, unbleached or dyed with madder or ochre;
# a few with a woven band.
const AWNINGS := [[Kit.LINEN, Kit.LINEN], [Kit.CLOTH_R, Kit.CLOTH_R], [Kit.SACK, Kit.SACK],
	[Kit.LINEN, Kit.CLOTH_W], [Kit.CLOTH_R, Kit.CLOTH_R], [Kit.SACK, Kit.LINEN]]

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
		"balcony": storeys >= 2 and r.call(10, 3) == 0, "dado": r.call(11, 10) < 3,
		"dentils": r.call(12, 2) == 0, "string": false, "quoins": r.call(16, 10) < 3,
		"steep": false, "loggia": storeys >= 3 and r.call(18, 4) == 0,
		"timber": r.call(19, 10) == 0, "lift": r.call(20, 5),
		"hip": r.call(21, 7) == 0, "tower": storeys >= 2 and r.call(22, 7) == 0,
		"wing": r.call(23, 4) == 0, "porch": false, "dipinti": r.call(25, 3) == 0,
		"socle": Kit.SOCLE_B if r.call(26, 10) < 3 else Kit.SOCLE_R,
	}

## A street-front lot with one or two row houses (variant `seed`), their
## fronts on the lot's south edge, yards behind.
static func house_lot(seed: int, via := false, low := false) -> ArrayMesh:
	var g := _grid(1, 1, 72)
	var m := MARGIN
	var depth := 24 + 2 * (seed % 3)
	var z1 := m + LOT
	var z0 := z1 - depth
	_paving(g, m, z0, m + LOT, z1, seed)
	_yard(g, m, m, m + LOT, z0 - 1, seed)
	if seed % 4 == 3 and not via:
		# the house stands back behind a one-storey shop wing on one half
		# of the front and a walled court on the other
		var o := _street_front(_options(seed, LOT), via, low)
		_house(g, m, z0 - 4, m + LOT, z1 - 8, o)
		var wx0 := m if seed % 16 < 8 else m + LOT / 2
		var wx1 := wx0 + LOT / 2
		var wall2: int = WALLS[(seed / 3) % WALLS.size()]
		g.box(wx0, FLOOR, z1 - 8, wx1, FLOOR + 14, z1, wall2)
		g.box(wx0, FLOOR, z1 - 1, wx1, FLOOR + 3, z1 + 1, Kit.STONE)
		_shop(g, wx0 + 3, FLOOR + 2, z1 - 1, 12, wall2, {"goods": seed % 4, "awning": AWNINGS[seed % AWNINGS.size()]}, seed)
		for z in range(z1 - 8, z1 + 1):
			var hh := (z1 - z) / 3
			for x in range(wx0, wx1):
				g.put(x, FLOOR + 14 + hh, z, Kit.EAVE if z == z1 else _field(x, z, hh + 1, ROOFS[seed % ROOFS.size()], seed, "x"))
		var cx0 := m + LOT / 2 if wx0 == m else m
		# the court behind a garden wall of 2.5 m with a gate, as in Pompeii
		g.box(cx0, FLOOR, z1 - 1, cx0 + LOT / 2, FLOOR + 10, z1, Kit.LIME)
		g.box(cx0, FLOOR, z1 - 1, cx0 + LOT / 2, FLOOR + 4, z1, Kit.SOCLE_R)
		g.box(cx0, FLOOR + 10, z1 - 1, cx0 + LOT / 2, FLOOR + 11, z1, Kit.TILE)
		g.box(cx0 + 8, FLOOR, z1 - 1, cx0 + 12, FLOOR + 8, z1, Kit.DOOR_D)
		match (seed / 4) % 3:
			1:
				# a bakery: a brick oven with its smoke, two lava mills
				var ox := cx0 + 14
				var oz := z1 - 5
				g.box(ox - 3, FLOOR, oz - 3, ox + 3, FLOOR + 3, oz + 3, Kit.BRICK)
				_disc(g, ox, FLOOR + 3, oz, 3, 2, Kit.BRICK)
				g.box(ox - 1, FLOOR, oz + 2, ox + 1, FLOOR + 2, oz + 3, Kit.DEEP)
				for k in 24:
					var c := Kit.SMOKE_D if k < 8 else (Kit.SMOKE if k < 16 else Kit.SMOKE_L)
					var sx := ox - 1 + k / 6
					g.box(sx, FLOOR + 5 + k, oz - 1, sx + 3, FLOOR + 6 + k, oz + 2, c)
				for k in 2:
					var mx := cx0 + 2 + k * 5
					g.box(mx, FLOOR, z1 - 6, mx + 3, FLOOR + 3, z1 - 3, Kit.LAVA)
					g.box(mx + 1, FLOOR + 3, z1 - 5, mx + 2, FLOOR + 4, z1 - 4, Kit.LAVA)
					g.box(mx, FLOOR + 4, z1 - 6, mx + 3, FLOOR + 6, z1 - 3, Kit.LAVA)
			2:
				# a fullery: vats of colour, cloth on a line
				for k in 3:
					var vx := cx0 + 1 + k * 6
					g.box(vx, FLOOR, z1 - 7, vx + 5, FLOOR + 2, z1 - 3, Kit.TRIM)
					g.box(vx + 1, FLOOR, z1 - 6, vx + 4, FLOOR + 2, z1 - 4, [Kit.CLOTH_R, Kit.CLOTH_Y, Kit.CLOTH_B][k])
				_person(g, cx0 + 8, FLOOR, z1 - 5, seed)
				g.box(cx0 + 1, FLOOR + 10, z1 - 2, cx0 + 19, FLOOR + 11, z1 - 1, Kit.WOOD_D)
				for k in 5:
					g.box(cx0 + 2 + k * 3, FLOOR + 6, z1 - 2, cx0 + 4 + k * 3, FLOOR + 10, z1 - 1, [Kit.CLOTH_R, Kit.LINEN, Kit.CLOTH_Y, Kit.CLOTH_B, Kit.CLOTH_G][k])
			_:
				_tree(g, cx0 + 3, FLOOR, z1 - 6, 3, seed)
				g.box(cx0 + 14, FLOOR, z1 - 5, cx0 + 16, FLOOR + 2, z1 - 3, Kit.POT)
				g.box(cx0 + 13, FLOOR + 2, z1 - 6, cx0 + 17, FLOOR + 5, z1 - 2, Kit.LEAF_L)
	elif seed % 4 < 2:
		_house(g, m, z0, m + LOT, z1, _street_front(_options(seed, LOT), via, low))
	else:
		var a := 16 + 4 * (seed % 3)
		# now and then a passage four voxels wide between the two houses
		var gap := 0
		_house(g, m, z0, m + a - gap, z1, _street_front(_options(seed * 7 + 1, a), via, low))
		_house(g, m + a + gap, z0, m + LOT, z1, _street_front(_options(seed * 7 + 2, LOT - a), via, low))
	return _done(g)

## On the main street the porticoes shade the fronts: no awnings, no
## balconies, taller houses. Houses facing north (`low`) keep to two
## storeys, so the street before them stays in view of the camera.
static func _street_front(o: Dictionary, via: bool, low := false) -> Dictionary:
	if via:
		o["awning"] = []
		o["balcony"] = false
		o["storeys"] = maxi(o["storeys"], 3)
	if low:
		o["storeys"] = mini(o["storeys"], 2)
		o["loggia"] = false
		o["lift"] = 0
		o["tower"] = false
	return o

# --- plants and people ----------------------------------------------------

## A round tree: a trunk, then a crown of a core cube and four offset
## cubes in three greens, chunky like Urbek's trees. `r` is the core's half
## width in voxels (crown about 4r across).
static func _tree(g: Kit.Grid, x: int, y: int, z: int, r: int, seed: int) -> void:
	for dz in range(-r - 1, r + 3):
		for dx in range(-r - 1, r + 3):
			g.swap(x + dx, y - 1, z + dz, x + dx + 1, y, z + dz + 1, Kit.GRASS, Kit.GRASS_D)
			g.swap(x + dx, y - 1, z + dz, x + dx + 1, y, z + dz + 1, Kit.GRASS_L, Kit.GRASS)
	var trunk := r + 4
	g.box(x, y, z, x + 2, y + trunk + r, z + 2, Kit.TRUNK)
	var c := Vector3i(x + 1, y + trunk + r, z + 1)
	g.box(c.x - r, c.y - r, c.z - r, c.x + r, c.y + r + 1, c.z + r, Kit.LEAF)
	var s := maxi(3, (r * 4) / 5)
	var lobes: Array[Vector3i] = [Vector3i(1, -1, 0), Vector3i(-1, 0, 1), Vector3i(0, 1, -1), Vector3i(1, 1, 1)]
	var cols: Array[int] = [Kit.LEAF_D, Kit.LEAF_L, Kit.LEAF, Kit.LEAF_L]
	match seed % 10:
		0, 1, 2, 3:
			# plane tree: broad crown, mottled bark
			cols = [Kit.PLANE, Kit.LEAF_L, Kit.PLANE, Kit.LEAF]
			for yy in range(y, y + trunk + r):
				if Kit.rnd(x, yy, z, seed) % 3 == 0:
					g.put(x + (yy % 2), yy, z + 1, Kit.BARK_L)
		4, 5, 6:
			# olive: silver-grey leaves
			cols = [Kit.OLIVE_D, Kit.OLIVE, Kit.OLIVE_D, Kit.OLIVE]
			g.box(c.x - r, c.y - r, c.z - r, c.x + r, c.y + r + 1, c.z + r, Kit.OLIVE)
	for k in lobes.size():
		var d := lobes[k]
		var j := Vector3i(Kit.rnd(k, 4, 0, seed) % 3 - 1, Kit.rnd(k, 5, 0, seed) % 3 - 1, Kit.rnd(k, 6, 0, seed) % 3 - 1)
		var lc := c + Vector3i(d.x * r * 3 / 4, d.y * r / 2, d.z * r * 3 / 4) + j
		g.box(lc.x - s, lc.y - s, lc.z - s, lc.x + s, lc.y + s, lc.z + s, cols[(k + seed) % 4])
	if seed % 12 == 7:
		# an almond in blossom, pale, in clusters over the outer leaves
		var bloom: int = Kit.BLOSSOM_W
		var e := 2 * r + 4
		for yy in range(c.y - e, c.y + e):
			for zz in range(c.z - e, c.z + e):
				for xx in range(c.x - e, c.x + e):
					var v := g.at(xx, yy, zz)
					if v != Kit.LEAF and v != Kit.LEAF_D and v != Kit.LEAF_L and v != Kit.PLANE:
						continue
					var outer := g.at(xx, yy + 1, zz) == Kit.EMPTY or g.at(xx, yy, zz + 1) == Kit.EMPTY or g.at(xx - 1, yy, zz) == Kit.EMPTY
					if outer and Kit.rnd(xx / 2, yy / 2, zz / 2, seed) % 100 < 42:
						g.put(xx, yy, zz, bloom)

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
## a flat crown in two tiers, each of four overlapping blobs set off by up
## to two voxels, the rim notched, darker below and lighter on top.
static func _pine(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	var h := 16 + seed % 13
	var lean := (seed / 13) % 3 - 1
	g.box(x, y, z, x + 2, y + h / 2, z + 2, Kit.TRUNK)
	g.box(x + lean, y + h / 2, z, x + 2 + lean, y + h, z + 2, Kit.TRUNK)
	var cx := x + 1 + lean
	var cz := z + 1
	for tier in 2:
		var r := 7 - tier * 2
		var ty := y + h + tier * 2
		for k in 4:
			var a := TAU * (k + 0.25 * tier) / 4.0
			var ox := roundi(cos(a) * r * 0.5) + Kit.rnd(k, tier, 1, seed) % 3 - 1
			var oz := roundi(sin(a) * r * 0.5) + Kit.rnd(k, tier, 2, seed) % 3 - 1
			var br := 3 + Kit.rnd(k, tier, 3, seed) % 3
			_disc(g, cx + ox, ty, cz + oz, br, 2, Kit.PINE_D)
			_disc(g, cx + ox, ty + 2, cz + oz, br - 1, 1, Kit.PINE)
		for k in 6:
			var a := TAU * k / 6.0 + seed
			g.box(cx + roundi(cos(a) * (r + 1)), ty, cz + roundi(sin(a) * (r + 1)), cx + roundi(cos(a) * (r + 1)) + 1, ty + 3, cz + roundi(sin(a) * (r + 1)) + 1, Kit.EMPTY)

## A group of `n` people round (x, z), standing close as if talking.
static func _group(g: Kit.Grid, x: int, y: int, z: int, n: int, seed: int) -> void:
	var spots: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 1), Vector2i(1, 3), Vector2i(4, 3), Vector2i(-2, 2), Vector2i(2, -2)]
	for k in mini(n, spots.size()):
		_person(g, x + spots[k].x, y, z + spots[k].y, seed + k * 7)

## A person sitting on something one voxel lower than y + 2.
static func _seated(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	var tunic: int = [Kit.ROBE_W, Kit.ROBE_N, Kit.ROBE_R, Kit.ROBE_O][Kit.rnd(seed, 1, 0, 9) % 4]
	g.box(x, y, z + 1, x + 2, y + 1, z + 2, Kit.SKIN)
	g.box(x, y + 1, z, x + 2, y + 4, z + 1, tunic)
	g.box(x, y + 4, z, x + 2, y + 5, z + 1, Kit.SKIN)
	g.box(x, y + 5, z, x + 2, y + 6, z + 1, Kit.HAIR)

## A person, 1.75 m: legs, tunic, head; standing on y.
static func _person(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	# tunics of wool and linen: off-white, natural brown, madder red,
	# ochre, now and then woad blue
	var tunic: int = [Kit.ROBE_W, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_O, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_B][Kit.rnd(seed, 0, 0, 9) % 8]
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
	g.swap(atrium.position.x - 1, y, atrium.position.y - 1, atrium.end.x + 1, y + 3, atrium.position.y, wall, Kit.DADO)
	for x in range(atrium.position.x + 3, atrium.end.x - 3, 9):
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
	g.box(garden.position.x - 1, top - 1, garden.position.y - 1, garden.end.x + 1, top, garden.position.y, Kit.TRIM)
	g.box(garden.position.x - 1, top - 1, garden.end.y, garden.end.x + 1, top, garden.end.y + 1, Kit.TRIM)
	g.box(garden.position.x - 1, top - 1, garden.position.y - 1, garden.position.x, top, garden.end.y + 1, Kit.TRIM)
	g.box(garden.end.x, top - 1, garden.position.y - 1, garden.end.x + 1, top, garden.end.y + 1, Kit.TRIM)
	for q: Array in [[portico.position.x, portico.position.y - 1, portico.end.x, portico.position.y], [portico.position.x, portico.end.y, portico.end.x, portico.end.y + 1]]:
		g.swap(q[0], y, q[1], q[2], y + 3, q[3], wall, Kit.DADO)
	_roof(g, outer, [atrium, garden.grow(3)], [rooms], top, "hip", TILES if seed % 2 == 0 else TILES_DARK, wall, seed)
	return _done(g)

## A column two voxels square from y to `top`: base, shaft, capital.
static func _column(g: Kit.Grid, x: int, y: int, z: int, top: int, c: int) -> void:
	g.box(x, y, z, x + 2, top, z + 1, c)
	g.box(x, y, z, x + 2, y + 1, z + 1, Kit.TRIM)
	g.box(x, top - 1, z, x + 2, top, z + 1, Kit.TRIM)

## A square fountain basin `s` wide with a jet column in the middle.
## A fountain basin `s` wide of `stone`: marble with a jet in the middle in
## gardens and squares; in the street, as at Pompeii, four slabs of grey
## lava with a spout pillar at the back.
static func _fountain(g: Kit.Grid, x: int, y: int, z: int, s: int, stone := Kit.TRIM) -> void:
	g.box(x, y, z, x + s, y + 2, z + s, stone)
	g.box(x + 1, y, z + 1, x + s - 1, y + 1, z + s - 1, Kit.WATER)
	if stone == Kit.TRIM:
		g.box(x + s / 2 - 1, y, z + s / 2 - 1, x + s / 2 + 1, y + 4, z + s / 2 + 1, Kit.TRIM)
		g.box(x + s / 2 - 1, y + 4, z + s / 2 - 1, x + s / 2 + 1, y + 5, z + s / 2 + 1, Kit.WATER)
	else:
		g.box(x + s / 2 - 1, y, z, x + s / 2 + 1, y + 5, z + 1, stone)
		g.box(x + s / 2 - 1, y + 3, z + 1, x + s / 2 + 1, y + 4, z + 2, Kit.STONE)
		g.put(x + s / 2, y + 2, z + 2, Kit.WATER_L)

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
	# as at Ostia: most faced in thin red brick, some plastered
	var wall: int = [Kit.BRICKFACE, Kit.BRICKFACE, Kit.OCHRE][seed % 3]
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
	if wall == Kit.BRICKFACE:
		# mortar courses, and a flat brick arch over every window
		for yy in range(y + STOREY0, top, 3):
			g.swap(x0, yy, zf, x1, yy + 1, zf + 1, wall, Kit.MORTAR)
		for k in range(1, storeys):
			var base := y + STOREY0 + STOREY * (k - 1)
			for i in 7:
				var cx := x0 + ((x1 - x0) * (2 * i + 1)) / 14
				var wy := base + (9 if k == 1 else 9)
				g.swap(cx - 3, wy, zf, cx + 3, wy + 1, zf + 1, wall, Kit.BRICK_W)
				g.swap(cx - 3, wy, zf, cx + 3, wy + 1, zf + 1, Kit.MORTAR, Kit.BRICK_W)
				g.swap(cx - 1, wy + 1, zf, cx + 1, wy + 2, zf + 1, wall, Kit.BRICK_W)
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
	var stairs := _temple(g, m + 40, m + 8, half, front, cols, rise, 24, false, seed)
	var y := FLOOR
	var az := mini(stairs + 2, m + 74)
	g.box(m + 36, y, az, m + 44, y + 4, az + 4, Kit.STONE)
	g.box(m + 36, y + 4, az, m + 44, y + 5, az + 4, Kit.TRIM)
	g.box(m + 38, y + 5, az + 1, m + 42, y + 6, az + 3, Kit.FRUIT_R)
	if seed == 4:
		# on the hilltop: the precinct closed by porticoes on three sides
		_stoa(g, m, m, m + 10, m + 80, "w", seed)
		_stoa(g, m + 70, m, m + 80, m + 80, "e", seed + 1)
		_stoa(g, m + 10, m, m + 70, m + 6, "n", seed + 2)
	else:
		for p: Vector2i in [Vector2i(m + 4, m + 8), Vector2i(m + 4, m + 30), Vector2i(m + 4, m + 52), Vector2i(m + 72, m + 8), Vector2i(m + 72, m + 30), Vector2i(m + 72, m + 52)]:
			_cypress(g, p.x, FLOOR, p.y, 24 + Kit.rnd(p.x, p.y, 0, seed) % 6, seed + p.y)
	for p: Vector2i in [Vector2i(m + 8, m + 68), Vector2i(m + 68, m + 68)]:
		_statue(g, p.x, y, p.y, seed + p.x)
	for k in 4:
		_person(g, m + 14 + Kit.rnd(k, 8, 0, seed) % 52, FLOOR, m + 66 + Kit.rnd(k, 9, 0, seed) % 10, seed + k)
	return _done(g)

## A figure cast in metal on the townspeople's pattern (legs, tunic, face,
## hair), two wide and seven high, in two values of the metal; a Victory
## with wings rising behind the shoulders.
static func _cast(g: Kit.Grid, x: int, y: int, z: int, drape: int, bare: int, wings: bool) -> void:
	g.box(x, y, z, x + 2, y + 2, z + 1, bare)
	g.box(x, y + 2, z, x + 2, y + 5, z + 1, drape)
	g.box(x, y + 5, z, x + 2, y + 6, z + 1, bare)
	g.box(x, y + 6, z, x + 2, y + 7, z + 1, drape)
	if wings:
		g.box(x - 1, y + 4, z, x, y + 8, z + 1, bare)
		g.box(x + 2, y + 4, z, x + 3, y + 8, z + 1, bare)
		g.put(x - 2, y + 7, z, bare)
		g.put(x + 3, y + 7, z, bare)

## A statue on a pedestal: stone block, bronze figure.
static func _statue(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	g.box(x, y, z, x + 4, y + 6, z + 4, Kit.STONE)
	g.box(x, y + 5, z, x + 4, y + 6, z + 4, Kit.TRIM)
	_cast(g, x + 1, y + 6, z + 2, Kit.BRONZE_D, Kit.BRONZE, false)

## A temple centred on xm, `half` voxels either side, from z0 to its
## front: a podium `rise` high with steps up the front between two walls,
## `cols` columns `col_h` high under a pediment with a relief, two more
## down each side of the porch, the cella behind with a gilt door, an
## entablature with triglyphs, a gable roof along z (terracotta or lead),
## gilt acroteria. Returns the z after the last step.
static func _temple(g: Kit.Grid, xm: int, z0: int, half: int, front: int, cols: int, rise: int, col_h: int, gilt: bool, seed: int) -> int:
	var lead := false
	var y := FLOOR
	var x0 := xm - half
	var x1 := xm + half
	var podium := y + rise
	var stairs := front + 2 * rise
	var marble := Kit.MARBLE
	var roof: Array = TILES_GILT if gilt else TILES
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
	# the cella's side walls run forward to the columns (antae), closing
	# the porch at the sides
	g.box(x0 + 3, podium, cz1, x0 + 5, col_top, front - 3, marble)
	g.box(x1 - 5, podium, cz1, x1 - 3, col_top, front - 3, marble)
	g.box(x0 + 3, podium, front - 6, x0 + 5, col_top, front - 5, Kit.MARBLE_W)
	g.box(x1 - 5, podium, front - 6, x1 - 3, col_top, front - 5, Kit.MARBLE_W)
	g.box(x0 + 1, col_top, z0 + 1, x1 - 1, col_top + 2, front - 1, marble)
	g.box(x0 + 1, col_top + 2, z0 + 1, x1 - 1, col_top + 5, front - 1, Kit.MARBLE_W)
	for x in range(x0 + 2, x1 - 2, 4):
		g.box(x, col_top + 2, front - 2, x + 1, col_top + 5, front - 1, Kit.MARBLE)
		g.box(x + 2, col_top + 3, front - 2, x + 3, col_top + 4, front - 1, Kit.GOLD if lead else Kit.REDWASH)
	for x in range(x0, x1, 2):
		g.box(x, col_top + 5, front - 1, x + 1, col_top + 6, front, Kit.TRIM)
	g.box(x0, col_top + 5, z0, x1, col_top + 6, front - 1, Kit.MARBLE)
	g.box(x0 - 1, col_top + 6, z0 - 1, x1 + 1, col_top + 7, front + 1, Kit.TRIM)
	var ry := col_top + 7
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

## A temple column: a square shaft three voxels across, fluted with a
## darker middle on every face, a base and a capital five across with a
## fringe of leaves under it.
static func _temple_column(g: Kit.Grid, x: int, y: int, z: int, top: int) -> void:
	g.box(x, y, z, x + 3, top, z + 3, Kit.MARBLE)
	g.box(x + 1, y + 1, z + 2, x + 2, top - 3, z + 3, Kit.MARBLE_W)
	g.box(x, y + 1, z + 1, x + 1, top - 3, z + 2, Kit.MARBLE_W)
	g.box(x + 2, y + 1, z + 1, x + 3, top - 3, z + 2, Kit.MARBLE_W)
	g.box(x - 1, y, z - 1, x + 4, y + 1, z + 4, Kit.TRIM)
	g.box(x - 1, top - 3, z - 1, x + 4, top - 2, z + 4, Kit.MARBLE_W)
	g.box(x - 1, top - 2, z - 1, x + 4, top, z + 4, Kit.MARBLE)
	g.box(x - 1, top - 1, z - 1, x + 4, top, z + 4, Kit.TRIM)

# --- gardens and the market -----------------------------------------------

## A public garden on one lot: paths, hedges, a fountain or a statue, an
## umbrella pine, cypresses, round trees, flowers and a visitor.
static func garden(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 44)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	g.box(m, 0, m + 18, m + LOT, FLOOR, m + 22, Kit.PAVE)
	g.box(m + 18, 0, m, m + 22, FLOOR, m + LOT, Kit.PAVE)
	# walled in from the street, 2.5 m of whitewash over a red socle, a gate
	for side: Array in [[m, m + LOT - 1, m + LOT, m + LOT], [m, m, m + 1, m + LOT], [m + LOT - 1, m, m + LOT, m + LOT]]:
		g.box(side[0], FLOOR, side[1], side[2], FLOOR + 10, side[3], Kit.LIME)
		g.box(side[0], FLOOR, side[1], side[2], FLOOR + 3, side[3], Kit.SOCLE_R)
		g.box(side[0], FLOOR + 10, side[1], side[2], FLOOR + 11, side[3], Kit.TILE)
	g.box(m + 17, FLOOR, m + LOT - 1, m + 23, FLOOR + 9, m + LOT, Kit.DOOR_D)
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
	for i in 6:
		_group(g, m + 6 + Kit.rnd(i, 4, 0, seed) % 66, FLOOR, m + 13 + 24 * (i % 3), 3 + i % 3, seed + i)
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
			_figure(g, m + 4, FLOOR, m + 30, Kit.STATUE)
		0:
			# the sweating cone fountain (meta sudans) in a round basin
			_disc(g, m + 20, FLOOR, m + 20, 9, 1, Kit.TRIM)
			_disc(g, m + 20, FLOOR, m + 20, 8, 1, Kit.WATER)
			for k in 12:
				_disc(g, m + 20, FLOOR + k, m + 20, maxi(1, 3 - k / 4), 1, Kit.BRICK if k < 10 else Kit.TRIM)
	if seed % 8 == 4 or seed % 8 == 6:
		_bench(g, m + 4, FLOOR, m + 4)
		g.box(m + 32, FLOOR, m + 32, m + 35, FLOOR + 2, m + 35, Kit.POT)
		g.box(m + 31, FLOOR + 2, m + 31, m + 36, FLOOR + 5, m + 36, Kit.LEAF)
	for k in seed % 3 + 1:
		_person(g, m + 3 + Kit.rnd(k, 6, 0, seed) % 34, FLOOR, m + 3 + Kit.rnd(k, 7, 0, seed) % 34, seed + k)
	return _done(g)

## A stone bench, six voxels long.
static func _bench(g: Kit.Grid, x: int, y: int, z: int) -> void:
	g.box(x, y, z, x + 1, y + 2, z + 2, Kit.STONE)
	g.box(x + 5, y, z, x + 6, y + 2, z + 2, Kit.STONE)
	g.box(x, y + 2, z, x + 6, y + 3, z + 2, Kit.TRIM)

# --- main street, forum, baths ----------------------------------------------

## Pale travertine paving of the main street: slabs 6 x 4, staggered.
static func _via_paving(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, y1: int, seed: int) -> void:
	for z in range(z0, z1):
		var row := z / 4
		for x in range(x0, x1):
			var slab := (x + (row % 2) * 3) / 6
			var c := Kit.VIA_PD if Kit.rnd(slab, row, 2, seed) % 100 < 22 else Kit.VIA_P
			g.box(x, 0, z, x + 1, y1, z + 1, c)

## The main street (via), two lots wide east-west: this is one half, `half`
## 0 the north, 1 the south. A road of pale travertine, a sidewalk of 12
## voxels under a portico with a lead roof, columns every 10 voxels at the
## kerb under a beam; people, carts, litters.
static func via(seed: int, half := 0) -> ArrayMesh:
	var g := _grid(1, 1, 24)
	var m := MARGIN
	var walk0 := m if half == 0 else m + 28
	var road0 := m + 12 if half == 0 else m
	_basalt(g, m, road0, m + LOT, road0 + 28, seed)
	for x in range(m, m + LOT):
		for rz: int in [road0 + 9, road0 + 18]:
			g.put(x, 0, rz, Kit.BASALT_D)
	_paving(g, m, walk0, m + LOT, walk0 + 12, seed)
	var kerb := m + 11 if half == 0 else m + 28
	g.box(m, 0, kerb, m + LOT, FLOOR, kerb + 1, Kit.CURB)
	var zc := m + 8 if half == 0 else m + 30
	for x in range(m + 4, m + LOT, 10):
		g.box(x, FLOOR, zc, x + 2, FLOOR + 13, zc + 2, Kit.WHITE)
		g.box(x - 1, FLOOR, zc - 1, x + 3, FLOOR + 1, zc + 3, Kit.TRIM)
		g.box(x - 1, FLOOR + 12, zc - 1, x + 3, FLOOR + 13, zc + 3, Kit.TRIM)
	g.box(m, FLOOR + 13, zc, m + LOT, FLOOR + 14, zc + 2, Kit.MARBLE)
	var za := m if half == 0 else zc
	var zb := zc + 2 if half == 0 else m + LOT
	for z in range(za, zb):
		var dist := (zb - 1 - z) if half == 0 else (z - za)
		var h := dist / 5
		for x in range(m, m + LOT):
			g.put(x, FLOOR + 14 + h, z, Kit.EAVE if dist == 0 else _field(x, z, h + 1, TILES, seed, "x"))
			if dist == 0 and x % 3 == 0:
				g.put(x, FLOOR + 15, z, Kit.ANTEFIX)
	for k in 3 + seed % 3:
		var x := m + 2 + Kit.rnd(k, 2, 0, seed) % (LOT - 4)
		_person(g, x, FLOOR, walk0 + 2 + Kit.rnd(k, 3, 0, seed) % 5, seed + k)
	for k in 2 + seed % 2:
		_person(g, m + 2 + Kit.rnd(k, 4, 0, seed) % (LOT - 4), 1, road0 + 3 + Kit.rnd(k, 5, 0, seed) % 20, seed + 7 + k)
	match seed % 4:
		1:
			_cart(g, m + 4 + seed % 14, 1, road0 + 6 + (seed / 4) % 2 * 10, seed)
		2:
			_litter(g, m + 10 + seed % 12, 1, road0 + 10, seed)
		3:
			_donkey(g, m + 8 + seed % 20, 1, road0 + 14, seed)
	return _done(g)

## Where the main street crosses a street: pale paving, kerbed corners.
static func via_crossing(seed: int, half := 0) -> ArrayMesh:
	var g := _grid(1, 1, 8)
	var m := MARGIN
	_basalt(g, m, m, m + LOT, m + LOT, seed)
	var z0 := m if half == 0 else m + 28
	for cx in 2:
		var x0 := m + (0 if cx == 0 else LOT - 8)
		_paving(g, x0, z0, x0 + 8, z0 + 12, seed + cx)
		g.box(x0 + (7 if cx == 0 else 0), 0, z0, x0 + (8 if cx == 0 else 1), FLOOR, z0 + 12, Kit.CURB)
		var kz := z0 + 11 if half == 0 else z0
		g.box(x0, 0, kz, x0 + 8, FLOOR, kz + 1, Kit.CURB)
	if seed % 2 == 0:
		_fountain(g, m + LOT - 7, FLOOR, z0 + 2, 6, Kit.LAVA)
	return _done(g)

## A litter carried by four bearers along x.
static func _litter(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	for p: Vector2i in [Vector2i(x, z), Vector2i(x + 7, z), Vector2i(x, z + 4), Vector2i(x + 7, z + 4)]:
		_person(g, p.x, y, p.y, seed + p.x)
	g.box(x - 1, y + 5, z + 1, x + 10, y + 6, z + 4, Kit.WOOD_D)
	g.box(x + 2, y + 6, z + 1, x + 7, y + 10, z + 4, [Kit.CLOTH_R, Kit.CLOTH_B, Kit.CLOTH_Y][seed % 3])
	g.box(x + 2, y + 10, z + 1, x + 7, y + 11, z + 4, Kit.WOOD_D)

## A donkey with panniers and its driver, along x.
static func _donkey(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	g.box(x, y, z, x + 1, y + 3, z + 2, Kit.MULE)
	g.box(x + 4, y, z, x + 5, y + 3, z + 2, Kit.MULE)
	g.box(x, y + 3, z, x + 5, y + 5, z + 2, Kit.MULE)
	g.box(x + 5, y + 4, z, x + 7, y + 6, z + 2, Kit.MULE)
	g.box(x + 1, y + 3, z - 1, x + 4, y + 6, z, Kit.WOOD)
	g.box(x + 1, y + 3, z + 2, x + 4, y + 6, z + 3, Kit.WOOD)
	g.box(x + 1, y + 6, z - 1, x + 4, y + 7, z, Kit.FRUIT_G)
	_person(g, x + 9, y, z, seed)

## A stoa: a covered colonnade `depth` voxels deep over [x0, x1) x [z0, z1).
## A back wall with shop doors, a walkway, a lean-to roof that stops three
## voxels short of the column line, so a marble beam on columns three
## voxels square, every eight, shows along the square. `side` names where
## the back wall is ("w", "e", "s" or "n"); `gap` leaves [gap.x, gap.y) open.
static func _stoa(g: Kit.Grid, x0: int, z0: int, x1: int, z1: int, side: String, seed: int, gap := Vector2i(-1, -1)) -> void:
	var across_z := side == "s" or side == "n"
	var along := x1 - x0 if across_z else z1 - z0
	var depth := z1 - z0 if across_z else x1 - x0
	for u in along:
		if u >= gap.x and u < gap.y:
			continue
		for v in depth:
			var p := Vector2i(x0 + v, z0 + u)
			if side == "e":
				p = Vector2i(x1 - 1 - v, z0 + u)
			elif side == "s":
				p = Vector2i(x0 + u, z1 - 1 - v)
			elif side == "n":
				p = Vector2i(x0 + u, z0 + v)
			g.box(p.x, 0, p.y, p.x + 1, FLOOR, p.y + 1, Kit.PAVE_L if v >= depth - 6 else Kit.BORDER)
			var colline := v >= depth - 3
			if v == 0:
				var door := posmod(u, 12) >= 4 and posmod(u, 12) < 9 and u > 2 and u < along - 3
				g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 18, p.y + 1, Kit.CREAM)
				g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 4, p.y + 1, Kit.DADO)
				if door:
					g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 9, p.y + 1, Kit.DARK)
			if colline:
				if posmod(u, 8) < 3:
					g.box(p.x, FLOOR, p.y, p.x + 1, FLOOR + 13, p.y + 1, Kit.MARBLE)
					g.put(p.x, FLOOR + 12, p.y, Kit.TRIM)
				g.box(p.x, FLOOR + 13, p.y, p.x + 1, FLOOR + 15, p.y + 1, Kit.MARBLE)
				g.put(p.x, FLOOR + 15, p.y, Kit.TRIM)
			elif v < depth - 6:
				var h := (depth - 7 - v) / 3
				g.put(p.x, FLOOR + 16 + h, p.y, Kit.EAVE if v == depth - 7 else _field(p.x, p.y, h + 1, TILES, seed, "x" if across_z else "z"))
				if v == 0:
					g.box(p.x, FLOOR + 18, p.y, p.x + 1, FLOOR + 16 + h, p.y + 1, Kit.CREAM)

## A draped statue on a plinth 4 x 3: the robe flares to four at the hem,
## the body as wide as the shoulders, arms down, a head on top.
static func _figure(g: Kit.Grid, x: int, y: int, z: int, c: int) -> void:
	g.box(x, y, z, x + 4, y + 2, z + 3, Kit.STONE)
	g.box(x, y + 1, z, x + 4, y + 2, z + 3, Kit.TRIM)
	g.box(x, y + 2, z, x + 4, y + 4, z + 2, c)
	g.box(x, y + 4, z, x + 3, y + 8, z + 2, c)
	g.box(x + 1, y + 8, z, x + 3, y + 10, z + 2, c)

## An honorific column: a base 6 x 6, a fluted shaft 4 x 4 and 28 high, a
## capital 5 x 5, a bronze figure 3 x 3 x 7 on top.
static func _honour(g: Kit.Grid, x: int, y: int, z: int) -> void:
	g.box(x - 1, y, z - 1, x + 5, y + 3, z + 5, Kit.STONE)
	g.box(x - 1, y + 2, z - 1, x + 5, y + 3, z + 5, Kit.TRIM)
	g.box(x, y + 3, z, x + 4, y + 31, z + 4, Kit.MARBLE)
	for k in 4:
		g.box(x + k, y + 4, z + 3, x + k + 1, y + 30, z + 4, Kit.MARBLE_W if k % 2 == 1 else Kit.MARBLE)
	g.box(x, y + 31, z, x + 5, y + 32, z + 5, Kit.TRIM)
	g.box(x + 1, y + 32, z + 1, x + 4, y + 35, z + 4, Kit.BRONZE)
	g.box(x + 1, y + 35, z + 1, x + 4, y + 37, z + 3, Kit.BRONZE)
	g.box(x + 2, y + 37, z + 1, x + 3, y + 39, z + 3, Kit.BRONZE)

## An equestrian statue in bronze on a tall pedestal, the horse along z
## facing the square's centre, its rider on top.
static func _equestrian(g: Kit.Grid, x: int, y: int, z: int) -> void:
	g.box(x, y, z, x + 6, y + 8, z + 12, Kit.STONE)
	g.box(x - 1, y + 7, z - 1, x + 7, y + 8, z + 13, Kit.TRIM)
	g.box(x - 1, y, z - 1, x + 7, y + 1, z + 13, Kit.TRIM)
	g.box(x + 1, y + 4, z + 11, x + 5, y + 5, z + 12, Kit.LETTER)
	var b := y + 8
	for leg: Vector2i in [Vector2i(x + 2, z + 2), Vector2i(x + 3, z + 2), Vector2i(x + 2, z + 8), Vector2i(x + 3, z + 8)]:
		g.box(leg.x, b, leg.y, leg.x + 1, b + 4, leg.y + 1, Kit.BRONZE_D)
	g.box(x + 2, b + 4, z + 2, x + 4, b + 7, z + 9, Kit.BRONZE_D)
	g.box(x + 2, b + 6, z + 9, x + 4, b + 9, z + 11, Kit.BRONZE_D)
	g.box(x + 2, b + 8, z + 11, x + 4, b + 10, z + 12, Kit.BRONZE)
	g.box(x + 2, b + 7, z + 1, x + 4, b + 8, z + 2, Kit.BRONZE_D)
	g.box(x + 2, b + 7, z + 4, x + 4, b + 12, z + 6, Kit.BRONZE)
	g.box(x + 1, b + 9, z + 4, x + 5, b + 10, z + 6, Kit.BRONZE)
	g.box(x + 2, b + 12, z + 4, x + 4, b + 14, z + 6, Kit.BRONZE)

## A triumphal arch across z: piers, a round-headed opening, an attic with
## an inscription, a bronze chariot on top. x0 is its west edge.
static func _arch(g: Kit.Grid, x0: int, y: int, z0: int) -> void:
	g.box(x0, y, z0, x0 + 24, y + 28, z0 + 8, Kit.MARBLE)
	g.box(x0 + 6, y, z0, x0 + 18, y + 18, z0 + 8, Kit.EMPTY)
	for o in 12:
		var hh: int = [2, 3, 4, 5, 5, 6, 6, 5, 5, 4, 3, 2][o]
		g.box(x0 + 6 + o, y + 18, z0, x0 + 7 + o, y + 18 + hh, z0 + 8, Kit.EMPTY)
	for x: int in [x0 + 1, x0 + 19]:
		g.box(x, y + 4, z0 + 8, x + 2, y + 24, z0 + 9, Kit.MARBLE_W)
		g.box(x + 2, y + 4, z0 + 8, x + 4, y + 24, z0 + 9, Kit.MARBLE_W)
	g.box(x0 - 1, y + 27, z0 - 1, x0 + 25, y + 28, z0 + 9, Kit.TRIM)
	g.box(x0, y + 28, z0, x0 + 24, y + 35, z0 + 8, Kit.MARBLE)
	g.box(x0 + 4, y + 30, z0 + 8, x0 + 20, y + 33, z0 + 9, Kit.PANEL)
	for x in range(x0 + 5, x0 + 19, 2):
		g.put(x, y + 31, z0 + 8, Kit.GOLD)
		if x % 4 == 1:
			g.put(x, y + 32, z0 + 8, Kit.GOLD)
	g.box(x0 - 1, y + 35, z0 - 1, x0 + 25, y + 36, z0 + 9, Kit.TRIM)
	# a chariot drawn by four horses, a figure in it
	for k in 4:
		var hx := x0 + 4 + k * 4
		g.box(hx, y + 36, z0 + 2, hx + 2, y + 39, z0 + 3, Kit.BRONZE_D)
		g.box(hx, y + 39, z0 + 2, hx + 2, y + 41, z0 + 6, Kit.BRONZE_D)
		g.box(hx, y + 41, z0 + 5, hx + 2, y + 44, z0 + 7, Kit.BRONZE)
		g.box(hx, y + 36, z0 + 5, hx + 2, y + 39, z0 + 6, Kit.BRONZE_D)
	g.box(x0 + 8, y + 36, z0, x0 + 16, y + 40, z0 + 2, Kit.BRONZE)
	g.box(x0 + 11, y + 40, z0, x0 + 13, y + 45, z0 + 1, Kit.GOLD)

## The forum on 5 x 5 lots: slab paving with a border along the colonnades
## and a band up to the temple, colonnades on three sides with shops behind
## and a triumphal arch as the gate to the main street; the Capitolium on a
## high podium; honorific columns, a speakers' platform, statues, benches,
## planters, a well, stalls and many people, the axis to the temple clear.
static func forum(seed: int) -> ArrayMesh:
	var n := 5 * LOT
	var g := _grid(5, 5, 110)
	var m := MARGIN
	var axis := m + n / 2
	for z in range(m, m + n):
		var row := (z - m) / 5
		for x in range(m, m + n):
			var sx := (x - m + (row % 2) * 4)
			var c := Kit.PAVE_J if sx % 8 == 0 or (z - m) % 5 == 0 else (Kit.PAVE if Kit.rnd(sx / 8, row, 0, seed) % 100 < 30 else Kit.PAVE_L)
			if absi(x - axis) < 6:
				c = Kit.BORDER
			g.box(x, 0, z, x + 1, FLOOR, z + 1, c)
	var d := 14
	g.box(m + d, 0, m, m + d + 2, FLOOR, m + n - d, Kit.BORDER)
	g.box(m + n - d - 2, 0, m, m + n - d, FLOOR, m + n - d, Kit.BORDER)
	g.box(m + d, 0, m + n - d - 2, m + n - d, FLOOR, m + n - d, Kit.BORDER)
	_stoa(g, m, m, m + d, m + n, "w", seed)
	_stoa(g, m + n - d, m, m + n, m + n, "e", seed + 1)
	_stoa(g, m + d, m + n - d, m + n - d, m + n, "s", seed + 2, Vector2i(n / 2 - d - 14, n / 2 - d + 14))
	_arch(g, axis - 12, FLOOR, m + n - 10)
	var stairs := _temple(g, axis, m + 6, 31, m + 84, 8, 14, 32, true, seed)
	g.box(axis - 5, FLOOR, stairs + 6, axis + 5, FLOOR + 4, stairs + 11, Kit.STONE)
	g.box(axis - 5, FLOOR + 4, stairs + 6, axis + 5, FLOOR + 5, stairs + 11, Kit.TRIM)
	g.box(axis - 2, FLOOR + 5, stairs + 7, axis + 2, FLOOR + 6, stairs + 10, Kit.FRUIT_R)
	_honour(g, axis - 30, FLOOR, m + 128)
	_equestrian(g, axis + 24, FLOOR, m + 124)
	for x: int in [axis - 30, axis + 27]:
		_cypress(g, x - 2, FLOOR, m + 92, 26, seed + x)
	# speakers' platform with bronze prows, south-west
	var rx := m + 36
	var rz := m + 150
	g.box(rx, FLOOR, rz, rx + 16, FLOOR + 6, rz + 8, Kit.MARBLE)
	g.box(rx, FLOOR, rz, rx + 16, FLOOR + 1, rz + 8, Kit.STONE)
	g.box(rx - 1, FLOOR + 6, rz - 1, rx + 17, FLOOR + 7, rz + 9, Kit.TRIM)
	for x in range(rx, rx + 16, 2):
		g.put(x, FLOOR + 7, rz + 8, Kit.TRIM)
	g.box(rx, FLOOR + 8, rz + 8, rx + 16, FLOOR + 9, rz + 9, Kit.TRIM)
	for x in range(rx + 1, rx + 15, 3):
		g.box(x, FLOOR + 2, rz + 8, x + 2, FLOOR + 5, rz + 10, Kit.BRONZE)
		g.put(x, FLOOR + 2, rz + 10, Kit.BRONZE_D)
	for k in 3:
		g.box(rx + 6, FLOOR, rz - 1 - k, rx + 10, FLOOR + 5 - 2 * k, rz - k, Kit.STEP)
	_person(g, rx + 7, FLOOR + 7, rz + 3, seed)
	for k in 9:
		_person(g, rx + 1 + (k % 5) * 3, FLOOR, rz + 11 + (k / 5) * 3 + k % 2, seed + 40 + k)
	# statues along both sides, planters and benches between them
	for z in range(m + 104, m + n - 24, 16):
		for x: int in [m + d + 6, m + n - d - 9]:
			_figure(g, x, FLOOR, z, Kit.STATUE if (z / 16) % 2 == 0 else Kit.BRONZE)
			g.box(x, FLOOR, z + 7, x + 4, FLOOR + 3, z + 11, Kit.STONE)
			g.box(x, FLOOR + 2, z + 7, x + 4, FLOOR + 3, z + 11, Kit.TRIM)
			g.box(x - 2, FLOOR + 3, z + 5, x + 6, FLOOR + 6, z + 13, Kit.LEAF)
			g.box(x - 1, FLOOR + 6, z + 6, x + 4, FLOOR + 8, z + 11, Kit.LEAF_L)
			g.box(x + 2, FLOOR + 4, z + 9, x + 7, FLOOR + 7, z + 13, Kit.LEAF_D)
	for z in range(m + 112, m + n - 30, 32):
		_bench(g, m + d + 12, FLOOR, z)
		_bench(g, m + n - d - 18, FLOOR, z)
	g.box(m + n - 60, FLOOR, m + 156, m + n - 55, FLOOR + 3, m + 161, Kit.TRIM)
	g.box(m + n - 59, FLOOR + 1, m + 157, m + n - 56, FLOOR + 3, m + 160, Kit.DEEP)
	var k := 0
	for z in range(m + 104, m + n - 40, 26):
		k += 1
		_stall(g, m + n - 62, FLOOR, z, AWNINGS[(k + seed) % AWNINGS.size()], (k + seed) % 4, seed + k)
	for q in 6:
		# people sitting on the temple steps (step j has its top at rise - j)
		_seated(g, axis - 14 + q * 5, FLOOR + 2 + q % 3, m + 84 + 24 - 2 * (q % 3), seed + q)
	_group(g, axis - 4, FLOOR, m + 136, 5, seed + 3)
	_group(g, m + n - 66, FLOOR, m + 120, 4, seed + 5)
	_group(g, m + n - 66, FLOOR, m + 150, 3, seed + 6)
	_group(g, axis + 10, FLOOR, m + 165, 4, seed + 7)
	_group(g, m + 30, FLOOR, m + 110, 3, seed + 8)
	for i in 6:
		_person(g, m + 24 + Kit.rnd(i, 4, 0, seed) % (n - 48), FLOOR, m + 100 + Kit.rnd(i, 5, 0, seed) % (n - 130), seed + i)
	return _done(g)

## Baths (thermae) on 3 x 2 lots: on the east a brick block with
## plastered bands and arched windows, two halls under barrel vaults
## running to the front, their round ends with big half-round windows, a
## ribbed lead dome on a drum over the hot bath, a pedimented porch; on the
## west the exercise yard of sand with a colonnade on two sides and the
## open-air pool in the middle, bathers, trees at the edges.
static func baths(seed: int) -> ArrayMesh:
	var g := _grid(3, 2, 110)
	var m := MARGIN
	var y := FLOOR
	_paving(g, m, m, m + 120, m + 80, seed)
	var x0 := m + 46
	var x1 := m + 118
	var z0 := m + 4
	var z1 := m + 52
	var zf := z1 - 1
	var h := 26
	g.box(x0, y, z0, x1, y + h, z1, Kit.BRICK)
	for xx in range(x0, x1):
		for yy in range(y, y + h):
			if Kit.chance(xx / 3, yy, 1, seed, 9):
				g.put(xx, yy, zf, Kit.BRICK_W)
				if xx - x0 + z0 < z1:
					g.put(x0, yy, xx - x0 + z0, Kit.BRICK_W)
	g.box(x0, y, zf, x1, y + 2, zf + 2, Kit.STONE)
	g.box(x0, y + 12, zf, x1, y + 13, zf + 2, Kit.TRIM)
	g.box(x0, y + h - 2, zf, x1, y + h, zf + 2, Kit.TRIM)
	var c := Vector2i((x0 + x1) / 2, (z0 + z1) / 2)
	for wx in range(x0 + 4, x1 - 8, 12):
		if absi(wx + 3 - c.x) < 10:
			continue
		for wy: int in [y + 3, y + 14]:
			_zb(g, wx, wy, wx + 6, wy + 6, zf, -1, 1, Kit.EMPTY, 1)
			_zb(g, wx + 1, wy + 6, wx + 5, wy + 8, zf, -1, 1, Kit.EMPTY, 1)
			_zb(g, wx, wy, wx + 6, wy + 8, zf, -2, -1, Kit.GLASS, 1)
			g.box(wx - 1, wy - 1, zf, wx + 7, wy, zf + 2, Kit.TRIM)
	# arched windows on the west wall over the yard
	for wz in range(z0 + 6, z1 - 8, 12):
		for wy: int in [y + 3, y + 14]:
			g.box(x0, wy, wz, x0 + 1, wy + 8, wz + 6, Kit.EMPTY)
			g.box(x0 + 1, wy, wz, x0 + 2, wy + 8, wz + 6, Kit.GLASS)
			g.box(x0 - 1, wy - 1, wz - 1, x0 + 1, wy, wz + 7, Kit.TRIM)
	for hall: Vector2i in [Vector2i(x0 + 2, x0 + 22), Vector2i(x1 - 22, x1 - 2)]:
		var xc := (hall.x + hall.y - 1) / 2.0
		var half := (hall.y - hall.x) / 2.0
		for x in range(hall.x, hall.y):
			var t := (x - xc) / half
			var vh := roundi(12.0 * sqrt(maxf(0.0, 1.0 - t * t)))
			for z in range(z0, z1 + 1):
				g.box(x, y + h, z, x + 1, y + h + vh, z + 1, Kit.BRICK)
				g.put(x, y + h + vh, z, Kit.EAVE if vh == 0 else _field(x, z, vh, TILES, seed, "z"))
		var r := 9
		for x in range(hall.x, hall.y):
			for yy in range(y + h, y + h + r):
				var dd := Vector2(x - xc, yy - (y + h)).length()
				if dd < r:
					g.put(x, yy, z1, Kit.TRIM if absi(roundi(x - xc)) == 3 or dd > r - 1.2 else Kit.GLASS)
	var rr := 16
	var drum := y + h + 10
	for z in range(c.y - rr - 1, c.y + rr + 2):
		for x in range(c.x - rr - 1, c.x + rr + 2):
			var dd := Vector2(x - c.x + 0.5, z - c.y + 0.5).length()
			if dd > rr + 0.5:
				continue
			g.box(x, y + h, z, x + 1, drum, z + 1, Kit.BRICK)
			if dd > rr - 1.0:
				g.put(x, drum - 1, z, Kit.TRIM)
			if dd < 2.5:
				g.put(x, drum, z, Kit.DEEP)
				continue
			var dh := roundi(sqrt(maxf(0.0, rr * rr - dd * dd)) * 0.85)
			g.box(x, drum, z, x + 1, drum + dh, z + 1, Kit.COCCIO_D)
			# light lime mortar (cocciopesto), stepped rings as on the Pantheon
			g.put(x, drum + dh, z, Kit.COCCIO_L if dh % 3 == 0 else Kit.COCCIO)
	for k in 12:
		var a := TAU * (k + 0.5) / 12.0
		var px := c.x + roundi(cos(a) * (rr + 0.3))
		var pz := c.y + roundi(sin(a) * (rr + 0.3))
		if pz >= c.y:
			g.box(px - 1, y + h + 2, pz, px + 2, y + h + 8, pz + 1, Kit.GLASS)
	var stairs := _temple(g, c.x, zf - 2, 9, zf + 6, 4, 2, 18, false, seed)
	g.box(c.x - 3, y + 2, zf - 1, c.x + 3, y + 14, zf + 1, Kit.DOOR_D)
	# the exercise yard and its pool, west of the halls
	var yx0 := m + 2
	var yx1 := x0 - 2
	for z in range(m + 2, m + 78):
		for x in range(yx0, yx1):
			g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.YARD)
	_stoa(g, yx0, m + 2, yx0 + 8, m + 78, "w", seed + 3)
	_stoa(g, yx0 + 8, m + 2, yx1, m + 10, "n", seed + 4)
	var px0 := yx0 + 14
	g.box(px0 - 2, 0, m + 22, px0 + 18, FLOOR + 1, m + 66, Kit.MARBLE)
	g.box(px0, 0, m + 24, px0 + 16, FLOOR + 1, m + 64, Kit.EMPTY)
	g.box(px0, 0, m + 24, px0 + 16, 1, m + 64, Kit.POOL)
	for k in 7:
		var bz := m + 27 + k * 5
		var bxx := px0 + 2 + Kit.rnd(k, 1, 0, seed) % 12
		g.box(bxx, 1, bz, bxx + 2, FLOOR + 1, bz + 1, Kit.SKIN)
		g.put(bxx, FLOOR + 1, bz, Kit.HAIR)
	for p: Vector2i in [Vector2i(yx0 + 10, m + 70), Vector2i(yx1 - 6, m + 70), Vector2i(yx1 - 6, m + 14)]:
		_tree(g, p.x, FLOOR, p.y, 4, seed + p.x)
	for i in 12:
		_person(g, yx0 + 10 + Kit.rnd(i, 7, 0, seed) % maxi(1, yx1 - yx0 - 12), FLOOR, m + 14 + Kit.rnd(i, 8, 0, seed) % 60, seed + i)
	for i in 6:
		_person(g, x0 + 4 + Kit.rnd(i, 9, 0, seed) % (x1 - x0 - 8), FLOOR, stairs + 2 + Kit.rnd(i, 10, 0, seed) % 8, seed + 20 + i)
	return _done(g)

# --- the Pantheon -----------------------------------------------------------

## The Pantheon as Hadrian rebuilt it, at the Colosseum's scale (a little
## over a third of the real size) on 3 x 3 lots, its porch to the south (+z;
## the real one faces north, but the camera looks north). A rotunda of
## white stucco over a marble-faced base with three cornices; the dome
## stepped in rings at its foot and covered in gilt bronze tiles up to the
## open oculus with its bronze ring; the block between rotunda and porch
## with a second, higher pediment; the porch of eight grey granite columns
## with two rows of four pink ones behind, white marble bases and capitals,
## Agrippa's bronze inscription on the frieze, the bronze eagle in the
## pediment and a gilt bronze roof; the bronze doors, the niches of Augustus
## and Agrippa, steps and people.
static func pantheon(seed: int) -> ArrayMesh:
	var g := _grid(3, 3, 84)
	var m := MARGIN
	var y := FLOOR
	_paving(g, m, m, m + 120, m + 120, seed)
	var xm := m + 60
	var zc := m + 40
	var rr := 38
	var base := y + 3
	var c1 := base + 24        # first cornice, level with the porch entablature
	var c2 := base + 40        # second cornice
	var top := base + 45       # the drum's crown
	var bt := c1 + 6           # the block's top: its ridge dies into the drum
	_rotunda(g, xm, zc, rr, y, base, [c1, c2, top], seed)
	_dome(g, xm, zc, rr - 2, top, 17, seed)
	# the block between rotunda and porch, its cornices those of the drum
	var bx0 := xm - 26
	var bx1 := xm + 26
	var bz0 := zc + 28
	var bz1 := zc + 50
	g.box(bx0, y, bz0, bx1, base, bz1 + 1, Kit.TRAV)
	g.box(bx0, base, bz0, bx1, bt, bz1, Kit.LIME)
	g.box(bx0, base, bz0, bx1, c1, bz1, Kit.MARBLE)
	for cy: int in [c1 - 2, bt - 2]:
		g.box(bx0 - 1, cy, bz0, bx1 + 1, cy + 2, bz1 + 1, Kit.TRIM)
		g.box(bx0, cy - 1, bz1 - 1, bx1, cy, bz1, Kit.MARBLE_W)
	# its own pediment above the porch roof, and its roof back into the drum
	var r2 := Rect2i(bx0 - 1, bz0, bx1 - bx0 + 2, bz1 - bz0 + 1)
	var h2 := _roof(g, r2, [], [Rect2i(bx0, bz0, bx1 - bx0, bz1 - bz0)], bt, "z", TILES_BRONZE, Kit.LIME, seed, false, Kit.ROOFB_D)
	_pediment(g, bx0 - 1, bx1 + 1, bt, bz1, h2, false)
	# the shade inside the porch: the wall behind the columns
	g.box(xm - 24, base, bz1 - 1, xm + 24, base + 20, bz1, Kit.PORCH)
	# the bronze doors: two leaves with two sunk panels each, a grille of
	# bars over them, jambs and lintel at the door's height; the niches of
	# Augustus and Agrippa
	var dh := 12
	g.box(xm - 6, base, bz1 - 1, xm + 6, base + dh + 4, bz1, Kit.DEEP)
	for lx: int in [xm - 6, xm]:
		g.box(lx, base, bz1 - 1, lx + 6, base + dh, bz1, Kit.BRONZE_D)
		for py: int in [base + 1, base + 7]:
			g.box(lx + 1, py, bz1 - 1, lx + 5, py + 4, bz1, Kit.BRONZE_P)
	for gx in range(xm - 6, xm + 6, 2):
		g.box(gx, base + dh, bz1 - 1, gx + 1, base + dh + 4, bz1, Kit.BRONZE)
	g.box(xm - 6, base + dh, bz1 - 1, xm + 6, base + dh + 1, bz1, Kit.BRONZE)
	g.box(xm - 7, base + dh + 4, bz1 - 1, xm + 7, base + dh + 6, bz1 + 1, Kit.BRONZE)
	g.box(xm - 7, base, bz1 - 1, xm - 6, base + dh + 4, bz1 + 1, Kit.BRONZE)
	g.box(xm + 6, base, bz1 - 1, xm + 7, base + dh + 4, bz1 + 1, Kit.BRONZE)
	for nx: int in [bx0 + 5, bx1 - 11]:
		g.box(nx, base + 2, bz1 - 3, nx + 6, base + 16, bz1, Kit.EMPTY)
		g.box(nx, base + 2, bz1 - 4, nx + 6, base + 16, bz1 - 3, Kit.MARBLE_W)
		g.box(nx + 1, base + 16, bz1 - 3, nx + 5, base + 17, bz1 - 1, Kit.EMPTY)
		g.box(nx, base + 1, bz1 - 3, nx + 6, base + 2, bz1, Kit.TRIM)
		g.box(nx + 2, base + 2, bz1 - 3, nx + 4, base + 4, bz1 - 1, Kit.MARBLE)
		g.box(nx + 2, base + 4, bz1 - 2, nx + 4, base + 12, bz1 - 1, Kit.STATUE)
		g.box(nx + 2, base + 12, bz1 - 2, nx + 4, base + 13, bz1 - 1, Kit.HAIR)
	# the porch: podium and steps, sixteen columns in three rows of 8, 4, 4
	var px0 := xm - 24
	var px1 := xm + 24
	var pz0 := bz1
	var pz1 := bz1 + 20
	g.box(px0 - 1, y, pz0, px1 + 1, base, pz1, Kit.TRAV)
	g.box(px0 - 1, base - 1, pz0, px1 + 1, base, pz1, Kit.STEP)
	g.box(px0, base - 1, pz0, px1, base, pz1 - 4, Kit.PORCH)
	for k in 3:
		g.box(px0 - 1, y, pz1, px1 + 1, base - k, pz1 + 2 + 2 * k, Kit.STEP)
	var col_top := base + 20
	var xs: Array[int] = []
	for i in 8:
		xs.append(px0 + roundi(i * (px1 - px0 - 3) / 7.0))
	for i in 8:
		_porch_column(g, xs[i], base, pz1 - 4, col_top, Kit.GRANITE)
	for row: int in [pz1 - 11, pz1 - 17]:
		for i: int in [0, 2, 5, 7]:
			_porch_column(g, xs[i], base, row, col_top, Kit.GRANITE_P)
	# the ceiling over the aisles, in shade
	g.box(px0, col_top, pz0, px1, col_top + 2, pz1 - 1, Kit.PORCH_D)
	# entablature: architrave, frieze with Agrippa's inscription, cornice
	g.box(px0 - 1, col_top, pz1 - 5, px1 + 1, col_top + 2, pz1, Kit.MARBLE)
	g.box(px0 - 1, col_top + 2, pz0, px1 + 1, col_top + 4, pz1, Kit.MARBLE_W)
	_inscription(g, xm, col_top + 2, pz1, "M·AGRIPPA·L·F·COS·TERTIVM·FECIT")
	g.box(px0 - 2, col_top + 4, pz0, px1 + 2, col_top + 5, pz1 + 1, Kit.TRIM)
	var ry := col_top + 5
	var outer := Rect2i(px0 - 2, pz0, px1 - px0 + 4, pz1 - pz0 + 1)
	var hmax := _roof(g, outer, [], [Rect2i(px0 - 1, pz0, px1 - px0 + 2, pz1 - pz0)], ry, "z", TILES_BRONZE, Kit.MARBLE, seed, false, Kit.ROOFB_D)
	_pediment(g, px0 - 2, px1 + 2, ry, pz1, hmax, true)
	# people on the steps and the square
	for i in 10:
		var px := m + 4 + Kit.rnd(i, 3, 0, seed) % 110
		_person(g, px, FLOOR, pz1 + 7 + Kit.rnd(i, 4, 0, seed) % 3, seed + i)
	for i in 6:
		var a := TAU * Kit.rnd(i, 5, 0, seed) / 65536.0
		if sin(a) > 0.3:
			continue
		_person(g, xm + roundi(cos(a) * (rr + 4)), FLOOR, zc + roundi(sin(a) * (rr + 4)), seed + 30 + i)
	return _done(g)

## The drum: a solid cylinder of radius rr from the plinth (two travertine
## steps) up to the crown; marble slabs to the first cornice, white stucco
## scored as ashlar above it; each cornice two voxels high and one proud.
static func _rotunda(g: Kit.Grid, xm: int, zc: int, rr: int, y: int, base: int, cornices: Array, seed: int) -> void:
	var top: int = cornices[2]
	var c0: int = cornices[0]
	for z in range(zc - rr - 2, zc + rr + 3):
		for x in range(xm - rr - 2, xm + rr + 3):
			var d := Vector2(x - xm + 0.5, z - zc + 0.5).length()
			if d > rr + 1.5:
				continue
			g.box(x, y, z, x + 1, base - 1, z + 1, Kit.TRAV)
			if d > rr + 0.5:
				continue
			g.box(x, base - 1, z, x + 1, base, z + 1, Kit.TRAV)
			if d > rr:
				continue
			g.box(x, base, z, x + 1, top, z + 1, Kit.LIME)
			if d < rr - 1.5:
				continue
			# the face: marble below the first cornice, stucco above, a dark
			# band under every cornice
			for yy in range(base, top):
				var c := Kit.MARBLE if yy < c0 else Kit.LIME
				for cy: int in cornices:
					if yy == cy - (3 if cy != top else 2):
						c = Kit.BAND
				g.put(x, yy, z, c)
	for k in cornices.size():
		var cy: int = cornices[k] - 2 if k < 2 else cornices[k] - 1
		for z in range(zc - rr - 3, zc + rr + 4):
			for x in range(xm - rr - 3, xm + rr + 4):
				var d := Vector2(x - xm + 0.5, z - zc + 0.5).length()
				if d > rr + 2.0 or d < rr - 1.5:
					continue
				g.box(x, cy, z, x + 1, cy + 2, z + 1, Kit.TRIM)
				if d > rr + 1.0:
					g.put(x, cy, z, Kit.EMPTY)

## The dome from the crown: three step rings, each two voxels high and
## two in, with dark risers, then the cap curving up to the oculus in one
## colour, so only the light shades its steps; gilt bronze; the oculus
## open to the dark inside, a bronze ring round it.
static func _dome(g: Kit.Grid, xm: int, zc: int, dr: int, y0: int, rise: int, seed: int) -> void:
	var oculus := 6.5
	var cap := dr - 6.0
	for z in range(zc - dr - 1, zc + dr + 2):
		for x in range(xm - dr - 1, xm + dr + 2):
			var d := Vector2(x - xm + 0.5, z - zc + 0.5).length()
			if d > dr + 0.5:
				continue
			if d < oculus:
				g.box(x, y0 - 6, z, x + 1, y0 - 5, z + 1, Kit.DEEP)
				continue
			var h := 0
			if d > cap:
				h = 2 * (floori((dr + 0.5 - d) / 2.0) + 1)
			else:
				var t := clampf((d - oculus) / (cap - oculus), 0.0, 1.0)
				h = 6 + roundi((rise - 6) * (1.0 - t * t))
			if d < oculus + 1.5:
				g.box(x, y0, z, x + 1, y0 + h + 1, z + 1, Kit.BRONZE_D)
				continue
			g.box(x, y0, z, x + 1, y0 + h, z + 1, Kit.DOME if d > cap else Kit.DOME_C)
	# the oculus shaft down into the dark
	for z in range(zc - 8, zc + 9):
		for x in range(xm - 8, xm + 9):
			var d := Vector2(x - xm + 0.5, z - zc + 0.5).length()
			if d < oculus:
				g.box(x, y0 - 5, z, x + 1, y0 + rise + 2, z + 1, Kit.EMPTY)
			elif d < oculus + 1.0:
				g.box(x, y0 - 5, z, x + 1, y0 + rise - 1, z + 1, Kit.DEEP)

# The pediment's eagle, top row first: wing tips raised, the head turned
# left with its beak (b), the body, the tail and feet.
const EAGLE := [
	"#..b#...#",
	"##.###.##",
	".#######.",
	"..#####..",
	"...#.#...",
]

## A pediment on the face z = zf over [x0, x1) from y, as high as the roof
## behind it (hmax): raking cornices, a recessed tympanum and, on the
## porch's, the bronze eagle in a wreath.
static func _pediment(g: Kit.Grid, x0: int, x1: int, y: int, zf: int, hmax: int, eagle: bool) -> void:
	for x in range(x0, x1):
		var h := mini(x - x0, x1 - 1 - x) / 2
		if h < 1:
			continue
		g.box(x, y, zf - 1, x + 1, y + h, zf, Kit.MARBLE_W)
		g.box(x, y, zf, x + 1, y + h - 1, zf + 1, Kit.EMPTY)
		g.box(x, y + h - 1, zf - 1, x + 1, y + h + 1, zf + 1, Kit.TRIM)
	g.box(x0, y, zf - 1, x1, y + 1, zf + 1, Kit.TRIM)
	if eagle:
		# a small gilt wreath with ribbons falling outward, the bronze
		# eagle drawn over it as a sprite: spread wings wider than its
		# body, head turned left with a gilt beak
		var xm := (x0 + x1) / 2
		var zt := zf - 1
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				if absf(Vector2(dx + 0.5, dy + 0.5).length() - 3.4) < 0.5:
					g.put(xm + dx, y + 5 + dy, zt, Kit.GILT)
		for k in 3:
			g.put(xm - 4 - k, y + 1 + k / 2, zt, Kit.GILT_D)
			g.put(xm + 4 + k, y + 1 + k / 2, zt, Kit.GILT_D)
		for row in EAGLE.size():
			var line: String = EAGLE[row]
			for col in line.length():
				var ch := line[col]
				if ch == ".":
					continue
				g.put(xm - 4 + col, y + 7 - row, zt, Kit.GOLD if ch == "b" else Kit.BRONZE_D)

## A porch column: an unfluted granite shaft three voxels across on a white
## marble base (grey ones lighter on the west, darker on the east), a
## Corinthian capital of white marble: a dark necking, a bell five across,
## a shadow gap and an abacus with its corners standing out.
static func _porch_column(g: Kit.Grid, x: int, y: int, z: int, top: int, shaft: int) -> void:
	g.box(x, y, z, x + 3, top, z + 3, shaft)
	if shaft == Kit.GRANITE:
		# the light from the west: a lit side and a shaded one, a dark
		# necking under the capital
		g.box(x, y + 2, z, x + 1, top - 3, z + 3, Kit.GRANITE_L)
		g.box(x + 2, y + 2, z, x + 3, top - 3, z + 3, Kit.GRANITE_D)
		g.box(x, top - 4, z, x + 3, top - 3, z + 3, Kit.GRANITE_D)
	g.box(x - 1, y, z - 1, x + 4, y + 1, z + 4, Kit.TRIM)
	g.box(x, y + 1, z, x + 3, y + 2, z + 3, Kit.MARBLE)
	# the capital flares: a bell five across, a shadow gap, the abacus
	# with its corners standing out
	g.box(x - 1, top - 3, z - 1, x + 4, top - 2, z + 4, Kit.MARBLE)
	g.box(x, top - 2, z, x + 3, top - 1, z + 3, Kit.MARBLE_W)
	g.box(x - 1, top - 1, z - 1, x + 4, top, z + 4, Kit.TRIM)
	for c: Vector2i in [Vector2i(x - 2, z - 2), Vector2i(x + 4, z - 2), Vector2i(x - 2, z + 4), Vector2i(x + 4, z + 4)]:
		g.put(c.x, top - 1, c.y, Kit.TRIM)

## Bronze letters on the frieze face z = zf, centred on xm: a letter a
## voxel, a dot between words, read as a line of bronze.
static func _inscription(g: Kit.Grid, xm: int, y: int, zf: int, text: String) -> void:
	var x := xm - text.length() / 2
	for ch in text:
		if ch != "·":
			g.box(x, y, zf - 1, x + 1, y + 2, zf, Kit.BRONZE_D)
		x += 1

# --- the Circus Maximus -------------------------------------------------------

const CIRCUS_WALL := 40      # the outer arcades' height on the Palatine side
const CIRCUS_LOW := 24       # and on the Aventine side, which faces the camera
const CIRCUS_STAND := 28     # a stand's depth from the outer face to the arena
# Citizens in light tunics and togas, here and there natural wool and the
# colours of the factions.
const CIRCUS_CROWD := [Kit.ROBE_W, Kit.ROBE_W, Kit.LINEN, Kit.ROBE_R, Kit.ROBE_W, Kit.CLOTH_B, Kit.ROBE_W, Kit.CLOTH_G,
	Kit.LINEN, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_W, Kit.CLOTH_G, Kit.LINEN, Kit.CLOTH_B, Kit.ROBE_N]

## The Circus Maximus in the valley between Palatine and Aventine, pressed
## to 8 x 3 lots like the town's other great buildings: the long arena
## running east and west, the stands on three sides behind three storeys of
## travertine arcades with shops in the lowest, seats rising from a marble
## podium (wooden ones at the top) under a portico, crowds on them; the
## twelve starting gates in a gentle curve between two towers in the west,
## the magistrates' box over the processional gate; the round end in the
## east with the arch of Titus; the spina down the middle with its water
## basins, Augustus' obelisk, the turning posts of three gilt cones, the
## seven eggs and seven dolphins that count the laps, statues; the imperial
## box on the Palatine side; four quadrigae racing anticlockwise. The
## Aventine stand is kept lower than the Palatine one, or from the game's
## camera it would hide the arena.
static func circus(seed: int) -> ArrayMesh:
	var g := _grid(8, 3, 50)
	var m := MARGIN
	var y := FLOOR
	var x0 := m + 2
	var x1 := m + 320
	var z0 := m + 2
	var z1 := m + 118
	var zm := m + 60
	var cx := x1 - 58          # centre of the round end
	var ro := 58.0             # its outer radius
	# the arena's sand (a layer of its own over the ground), the tracks a
	# little darker; everything in the arena stands on it
	for z in range(z0 + CIRCUS_STAND, z1 - CIRCUS_STAND):
		for x in range(x0, x1):
			if x >= cx and Vector2(x - cx + 0.5, z - zm + 0.5).length() > ro:
				continue
			var c := Kit.ARENA
			var lane := absi(z - zm)
			if (lane == 12 or lane == 20) and Kit.chance(x / 3, z, 2, seed, 70):
				c = Kit.ARENA_D
			g.put(x, y, z, c)
	y += 1
	# the stands: for every column its depth s from the outer face
	for z in range(z0, z1):
		for x in range(x0, x1):
			var s := _circus_depth(x, z, cx, zm, z0, z1, ro)
			var along := x
			var seated := true
			if x >= cx:
				along = cx + roundi(atan2(z - zm + 0.5, x - cx + 0.5) * ro)
				# on the round end people sit only where a tread runs straight
				# for three voxels, so the rows stay rows
				seated = (_circus_depth(x - 1, z, cx, zm, z0, z1, ro) == s and _circus_depth(x + 1, z, cx, zm, z0, z1, ro) == s) \
					or (_circus_depth(x, z - 1, cx, zm, z0, z1, ro) == s and _circus_depth(x, z + 1, cx, zm, z0, z1, ro) == s)
			if s < 0 or s >= CIRCUS_STAND:
				continue
			# the wall's height from the Palatine side round to the Aventine
			var wall := CIRCUS_LOW if z > zm else CIRCUS_WALL
			_circus_stand(g, x, z, s, along, wall, y - 1, seed, seated)
	_circus_gates(g, m, zm, y, seed)
	_circus_spina(g, m + 72, m + 248, zm, y, seed)
	_circus_box(g, m + 186, z0, y, seed)
	_titus_arch(g, x1, zm, y)
	# four quadrigae: east along the south track, west along the north one
	_quadriga(g, m + 118, y, zm + 14, 1, Kit.ROBE_R, seed)
	_quadriga(g, m + 136, y, zm + 6, 1, Kit.CLOTH_G, seed + 1)
	_quadriga(g, m + 200, y, zm - 10, -1, Kit.ROBE_B, seed + 2)
	_quadriga(g, m + 182, y, zm - 18, -1, Kit.ROBE_W, seed + 3)
	return _done(g)

## A stand's depth at (x, z) from the outer face: the straight sides, then
## the round end.
static func _circus_depth(x: int, z: int, cx: int, zm: int, z0: int, z1: int, ro: float) -> int:
	if x < cx:
		return mini(z - z0, z1 - 1 - z)
	return floori(ro - Vector2(x - cx + 0.5, z - zm + 0.5).length())

## One column of a stand at depth s from the outer face: the arcaded outer
## wall (three voxels), the portico at the top of the seats, the seats in
## treads of two from the top down to the podium, people on them; the dark
## backs of the arches one voxel behind the wall.
static func _circus_stand(g: Kit.Grid, x: int, z: int, s: int, along: int, wall: int, y: int, seed: int, seated := true) -> void:
	var portico := wall >= 32
	if s < 3:
		for yy in range(y, y + wall):
			g.put(x, yy, z, _circus_face(along, yy - y, wall, s))
		return
	if s == 3:
		for yy in range(y, y + wall):
			if _circus_face(along, yy - y, wall, 2) == Kit.EMPTY:
				g.put(x, yy, z, Kit.ARCH_D)
	if s < 7 and portico:
		# the walkway under the portico roof, columns on its inner edge
		for yy in range(y, y + wall - 8):
			if g.at(x, yy, z) == Kit.EMPTY:
				g.put(x, yy, z, Kit.TRAV)
		g.put(x, y + wall - 8, z, Kit.STEP)
		var roof := y + wall - 1 - (s - 3)
		g.put(x, roof, z, Kit.TILE if s > 3 else Kit.EAVE)
		if s == 6 and posmod(along, 8) < 2:
			g.box(x, y + wall - 7, z, x + 1, roof, z + 1, Kit.MARBLE)
		return
	# seats in treads of two from the podium up to the walkway or the wall
	var treads := (CIRCUS_STAND - (7 if portico else 3)) / 2
	var rise := (wall - (10 if portico else 4) - 8) / float(treads - 1)
	var t := (CIRCUS_STAND - 1 - s) / 2
	var h := 8 + roundi(t * rise)
	var front := (CIRCUS_STAND - 1 - s) % 2 == 0
	if s == CIRCUS_STAND - 1:
		# the podium: marble with a red band, a parapet on top
		g.box(x, y, z, x + 1, y + h, z + 1, Kit.MARBLE)
		g.put(x, y + 5, z, Kit.DADO)
		g.put(x, y + h, z, Kit.TRIM)
		return
	var seat := Kit.SEAT_WOOD if t >= treads - 2 else Kit.SEAT_MID
	for yy in range(y, y + h):
		if g.at(x, yy, z) == Kit.EMPTY:
			g.put(x, yy, z, Kit.SEAT_D)
	g.put(x, y + h - 1, z, seat)
	# aisles every 40, else people on the back half of every tread
	if posmod(along, 40) < 2:
		g.put(x, y + h - 1, z, Kit.STEP)
		return
	if not seated:
		# where the round end's treads step, the crowd is painted on: the
		# treads in faces with a tick of hair, the risers in the runs'
		# colours
		var r2 := Kit.rnd((along + t * 3) / 6, t, 6, seed)
		if front:
			g.put(x, y + h - 1, z, CIRCUS_CROWD[r2 % CIRCUS_CROWD.size()])
		else:
			g.put(x, y + h - 1, z, Kit.HAIR if posmod(along, 3) == 0 else Kit.SKIN)
		return
	if not front:
		# shoulder to shoulder, a run of four to eight in one colour
		var r := Kit.rnd((along + t * 3) / 6, t, 6, seed)
		var c: int = CIRCUS_CROWD[r % CIRCUS_CROWD.size()]
		if Kit.chance(along, h, 5, seed, 6):
			return
		g.put(x, y + h, z, c)
		g.put(x, y + h + 1, z, Kit.HAIR if posmod(along, 3) == 0 else Kit.SKIN)

## The outer face at height yy, s voxels in from its outermost layer, in
## bays of ten: pilasters two wide and the cornices stand one proud (s =
## 0); the wall (s = 1) with arches recessed two, round heads in rows of
## six, four and two under a light archivolt; one storey of arches, two on
## the high side, and above the last cornice an attic with an arched window
## in every bay.
static func _circus_face(along: int, yy: int, wall: int, s: int) -> int:
	var o := posmod(along, 10)
	var two := wall >= 32
	var attic := 30 if two else 16
	if yy == 0:
		return Kit.TRAV_D
	if yy == 14 or yy == 15 or yy == wall - 1 or (two and (yy == 28 or yy == 29)):
		return Kit.TRIM
	if s == 0:
		if yy < attic - 2 and o < 2:
			return Kit.TRAV_W
		return Kit.EMPTY
	var lr := -1
	if yy < 14:
		lr = yy - 1
	elif two and yy < 28:
		lr = yy - 16
	if lr >= 0:
		var open := (lr < 9 and o >= 3 and o < 9) or (lr == 9 and o >= 4 and o < 8)
		if open:
			return Kit.EMPTY
		var ring := (lr == 9 and (o == 3 or o == 8)) or (lr == 10 and o >= 4 and o < 8)
		if ring and s == 1:
			return Kit.TRAV_L
		return Kit.TRAV
	# the attic: an arched window over every arch, recessed one
	var wl := yy - attic - 1
	var win := (wl >= 0 and wl < 4 and o >= 4 and o < 8) or (wl == 4 and o >= 5 and o < 7)
	if win:
		return Kit.EMPTY if s == 1 else Kit.ARCH_D
	if s == 1 and ((wl == 4 and (o == 4 or o == 7)) or (wl == 5 and o >= 5 and o < 7)):
		return Kit.TRAV_L
	return Kit.TRAV

## The starting gates at the west end: a building of 12 gates in a gentle
## curve, six either side of the processional gate, between two towers;
## over the gate the magistrates' box under a red awning.
static func _circus_gates(g: Kit.Grid, m: int, zm: int, y: int, seed: int) -> void:
	var gx0 := m + 2
	var gx1 := m + 20
	var gz0 := m + 2 + CIRCUS_STAND
	var gz1 := m + 118 - CIRCUS_STAND
	for z in range(gz0, gz1):
		# the curve: the gates nearer the middle stand a little further back
		var face := gx1 - roundi(pow((z - zm) / 30.0, 2.0) * 3.0)
		g.box(gx0, y, z, face, y + 18, z + 1, Kit.TRAV)
		g.put(face - 1, y + 17, z, Kit.TRIM)
		var dz := z - zm
		var central := absi(dz) <= 3
		var o := posmod(absi(dz) - 4, 4) if not central else 0
		# the roofs, seen from above: a terracotta roof over every gate
		# between white piers, the processional bay standing higher
		if central:
			g.box(gx0, y + 18, z, face - 2, y + 22, z + 1, Kit.TRAV)
			g.box(gx0, y + 22, z, face - 2, y + 23, z + 1, Kit.TILE)
			g.put(face - 3, y + 21, z, Kit.TRIM)
		elif o == 3 or absi(dz) >= 29:
			g.box(gx0, y + 18, z, face, y + 20, z + 1, Kit.TRIM)
		else:
			for x in range(gx0, face):
				var rh := 1 if o == 1 else 0
				g.box(x, y + 18, z, x + 1, y + 19 + rh, z + 1, Kit.TRAV)
				g.put(x, y + 18 + rh, z, Kit.RIDGE if o == 1 else Kit.TILE)
		var opening := central or o < 3
		if opening and absi(dz) < 29:
			var top := 13 if central else 10
			g.box(face - 3, y, z, face, y + top, z + 1, Kit.DEEP)
			if not central:
				g.box(face - 1, y, z, face, y + top - 1, z + 1, Kit.DOOR_D if o != 1 else Kit.EMPTY)
		elif not central:
			g.put(face - 1, y + 10, z, Kit.STATUE)
	# the towers at both ends: three storeys, on every face one round-headed
	# opening between corner pilasters, cornices, a low attic, a tiled roof
	for tz: int in [gz0 - 6, gz1 - 2]:
		var tx1 := gx1 + 2
		# the tower on the Aventine side as low as its stand, so the gates
		# stay in view
		var th := 44 if tz < zm else 30
		g.box(gx0, y, tz, tx1, y + th, tz + 8, Kit.TRAV)
		for cy: int in ([y + 14, y + 29] if th > 40 else [y + 14]):
			g.box(gx0 - 1, cy, tz - 1, tx1 + 1, cy + 2, tz + 9, Kit.TRIM)
		g.box(gx0 - 1, y + th - 3, tz - 1, tx1 + 1, y + th - 2, tz + 9, Kit.TRIM)
		g.box(gx0 - 1, y + th - 1, tz - 1, tx1 + 1, y + th, tz + 9, Kit.TRIM)
		for px: int in [gx0, tx1 - 2]:
			for pz: int in [tz - 1, tz + 8]:
				g.box(px, y, pz, px + 2, y + th - 3, pz + 1, Kit.TRAV_W)
		for pz: int in [tz, tz + 6]:
			g.box(tx1, y, pz, tx1 + 1, y + th - 3, pz + 2, Kit.TRAV_W)
		for sy: int in ([y + 2, y + 17, y + 31] if th > 40 else [y + 2, y + 17]):
			var xo := (gx0 + tx1) / 2 - 2
			for f: int in [tz + 7, tz]:
				g.box(xo, sy, f, xo + 4, sy + 7, f + 1, Kit.ARCH_D)
				g.box(xo + 1, sy + 7, f, xo + 3, sy + 8, f + 1, Kit.ARCH_D)
				g.box(xo - 1, sy + 7, f, xo, sy + 8, f + 1, Kit.TRAV_L)
				g.box(xo + 4, sy + 7, f, xo + 5, sy + 8, f + 1, Kit.TRAV_L)
				g.box(xo, sy + 8, f, xo + 4, sy + 9, f + 1, Kit.TRAV_L)
			g.box(tx1 - 1, sy, tz + 2, tx1, sy + 7, tz + 6, Kit.ARCH_D)
			g.box(tx1 - 1, sy + 7, tz + 3, tx1, sy + 8, tz + 5, Kit.ARCH_D)
		_roof(g, Rect2i(gx0 - 1, tz - 1, tx1 - gx0 + 2, 10), [], [Rect2i(gx0, tz, tx1 - gx0, 8)], y + th, "hip", TILES, Kit.TRAV, seed)
	# the magistrates' box over the processional gate
	g.box(gx1 - 7, y + 22, zm - 6, gx1 - 3, y + 23, zm + 7, Kit.MARBLE)
	g.box(gx1 - 4, y + 23, zm - 6, gx1 - 3, y + 25, zm + 7, Kit.TRIM)
	g.box(gx1 - 7, y + 30, zm - 7, gx1 - 2, y + 31, zm + 8, Kit.CLOTH_R)
	for pz: int in [zm - 6, zm + 6]:
		g.box(gx1 - 3, y + 23, pz, gx1 - 2, y + 30, pz + 1, Kit.WOOD_D)
	_seated(g, gx1 - 6, y + 23, zm, seed)
	_seated(g, gx1 - 6, y + 23, zm - 3, seed + 1)
	_seated(g, gx1 - 6, y + 23, zm + 3, seed + 2)

## The spina from xa to xb: a low marble barrier with water basins, the
## obelisk in the middle, a turning post at each end, the lap counters,
## statues and columns with gilt Victories.
static func _circus_spina(g: Kit.Grid, xa: int, xb: int, zm: int, y: int, seed: int) -> void:
	g.box(xa, y, zm - 3, xb, y + 3, zm + 3, Kit.MARBLE)
	g.box(xa, y + 2, zm - 3, xb, y + 3, zm + 3, Kit.TRIM)
	var xc := (xa + xb) / 2
	for x in range(xa + 2, xb - 2):
		if absi(x - xc) < 6 or posmod(x - xa, 24) < 4:
			continue
		g.box(x, y + 2, zm - 2, x + 1, y + 3, zm + 2, Kit.POOL)
	# Augustus' obelisk of red granite on its base, a gilt ball on top
	g.box(xc - 3, y + 3, zm - 3, xc + 3, y + 8, zm + 3, Kit.MARBLE)
	g.box(xc - 3, y + 7, zm - 3, xc + 3, y + 8, zm + 3, Kit.TRIM)
	g.box(xc - 1, y + 8, zm - 1, xc + 2, y + 34, zm + 2, Kit.OBELISK)
	g.box(xc - 1, y + 34, zm - 1, xc + 1, y + 38, zm + 1, Kit.OBELISK)
	g.box(xc - 1, y + 38, zm - 1, xc + 1, y + 40, zm + 1, Kit.GOLD)
	for k in 7:
		g.put(xc, y + 11 + k * 3, zm + 1, Kit.GLYPH)
		g.put(xc + 1, y + 12 + k * 3, zm + 1, Kit.GLYPH)
	# the turning posts: three gilt cones on a half-round base, the middle
	# one further out, so the camera sees all three
	for e in 2:
		var out := -1 if e == 0 else 1
		var bx := xa - 1 if e == 0 else xb
		for z in range(zm - 6, zm + 7):
			for k in 7:
				var x := bx + out * k
				if Vector2(k, z - zm + 0.5).length() < 6.5:
					g.box(x, y, z, x + 1, y + 4, z + 1, Kit.MARBLE)
					g.put(x, y + 3, z, Kit.TRIM)
		for c: Vector3i in [Vector3i(1, 0, -5), Vector3i(4, 0, -1), Vector3i(1, 0, 3)]:
			var cx := bx + out * c.x - (1 if out < 0 else 0)
			g.box(cx - 1, y + 4, zm + c.z, cx + 2, y + 9, zm + c.z + 3, Kit.GILT_D)
			g.box(cx - 1, y + 9, zm + c.z, cx + 1, y + 13, zm + c.z + 2, Kit.GOLD)
			g.box(cx - 1, y + 13, zm + c.z, cx, y + 16, zm + c.z + 1, Kit.GOLD)
	# the lap counters: seven white eggs on a bronze beam at the west, seven
	# bronze dolphins at the east
	var ex := xa + 8
	g.box(ex, y + 3, zm - 1, ex + 1, y + 13, zm + 1, Kit.MARBLE)
	g.box(ex + 16, y + 3, zm - 1, ex + 17, y + 13, zm + 1, Kit.MARBLE)
	g.box(ex, y + 13, zm - 1, ex + 17, y + 14, zm + 1, Kit.BRONZE_D)
	for k in 7:
		g.box(ex + 2 + 2 * k, y + 14, zm, ex + 3 + 2 * k, y + 16, zm + 1, Kit.TRIM)
	var dx := xb - 32
	g.box(dx, y + 3, zm - 1, dx + 1, y + 13, zm + 1, Kit.MARBLE)
	g.box(dx + 29, y + 3, zm - 1, dx + 30, y + 13, zm + 1, Kit.MARBLE)
	g.box(dx, y + 13, zm - 1, dx + 30, y + 14, zm + 1, Kit.BRONZE_D)
	for k in 7:
		var fx := dx + 2 + 4 * k
		g.box(fx, y + 14, zm, fx + 3, y + 15, zm + 1, Kit.BRONZE)
		g.put(fx, y + 15, zm, Kit.BRONZE)
		g.put(fx + 2, y + 15, zm, Kit.BRONZE_D)
	# columns with gilt Victories, wings raised (a Y), and statues between
	# the basins
	for sx: int in [xa + 46, xa + 72, xb - 72, xb - 46]:
		g.box(sx, y + 3, zm - 1, sx + 2, y + 18, zm + 1, Kit.MARBLE)
		g.box(sx - 1, y + 18, zm - 2, sx + 3, y + 19, zm + 2, Kit.TRIM)
		_cast(g, sx, y + 19, zm, Kit.GILT_D, Kit.GOLD, true)
	for sx: int in [xa + 34, xa + 60, xb - 60, xb - 38]:
		g.box(sx, y + 3, zm - 2, sx + 4, y + 9, zm + 2, Kit.STONE)
		g.box(sx, y + 8, zm - 2, sx + 4, y + 9, zm + 2, Kit.TRIM)
		_cast(g, sx + 1, y + 9, zm, Kit.GILT_D, Kit.GOLD, false)

## The imperial box on the Palatine side at x: a shrine-like box built into
## the stand, columns, a pediment facing the arena, a gilt roof.
static func _circus_box(g: Kit.Grid, x: int, z0: int, y: int, seed: int) -> void:
	var zf := z0 + CIRCUS_STAND + 1
	g.box(x, y, zf - 12, x + 20, y + 14, zf, Kit.MARBLE)
	g.box(x + 2, y + 14, zf - 10, x + 18, y + 15, zf, Kit.TRIM)
	# the podium's front: two recessed panels in frames, a red band
	for px: int in [x + 2, x + 11]:
		g.box(px, y + 2, zf - 1, px + 7, y + 11, zf, Kit.TRIM)
		g.box(px + 1, y + 3, zf - 1, px + 6, y + 10, zf, Kit.EMPTY)
		g.box(px + 1, y + 3, zf - 2, px + 6, y + 10, zf - 1, Kit.MARBLE_W)
	g.box(x, y + 12, zf - 1, x + 20, y + 13, zf, Kit.DADO)
	for k in 4:
		var cxk := x + 2 + k * 5
		g.box(cxk, y + 15, zf - 2, cxk + 2, y + 25, zf, Kit.MARBLE_W)
	g.box(x + 1, y + 15, zf - 10, x + 19, y + 25, zf - 8, Kit.CLOTH_R)
	g.box(x + 1, y + 25, zf - 10, x + 19, y + 26, zf + 1, Kit.TRIM)
	_roof(g, Rect2i(x, zf - 10, 20, 11), [], [Rect2i(x + 1, zf - 10, 18, 10)], y + 26, "z", TILES_GILT, Kit.MARBLE, seed)
	_pediment(g, x, x + 20, y + 26, zf, 5, false)
	_seated(g, x + 9, y + 15, zf - 4, seed)
	_seated(g, x + 6, y + 15, zf - 5, seed + 1)
	_seated(g, x + 12, y + 15, zf - 5, seed + 2)

## The arch of Titus in the middle of the round end: three passages, an
## attic with its inscription, a bronze quadriga on top.
static func _titus_arch(g: Kit.Grid, x1: int, zm: int, y: int) -> void:
	var ax0 := x1 - 10
	g.box(ax0, y, zm - 15, x1, y + 34, zm + 15, Kit.MARBLE)
	g.box(ax0 - 1, y + 26, zm - 16, x1 + 1, y + 27, zm + 16, Kit.TRIM)
	g.box(ax0 - 1, y + 33, zm - 16, x1 + 1, y + 34, zm + 16, Kit.TRIM)
	for p: Vector2i in [Vector2i(zm - 4, zm + 4), Vector2i(zm - 12, zm - 7), Vector2i(zm + 7, zm + 12)]:
		var top := 22 if p.x == zm - 4 else 14
		g.box(ax0, y, p.x, x1, y + top, p.y, Kit.EMPTY)
		g.box(ax0, y - 1, p.x, x1, y, p.y, Kit.TRAV_D)
	for pz: int in [zm - 15, zm + 14]:
		g.box(ax0 + 1, y, pz, x1 - 1, y + 26, pz + 1, Kit.MARBLE_W)
	g.box(ax0 + 2, y + 28, zm + 14, x1 - 2, y + 32, zm + 15, Kit.MARBLE_W)
	# the bronze quadriga on the attic, driving west into the circus, seen
	# in profile
	g.box(ax0 - 1, y + 34, zm - 5, x1 + 1, y + 35, zm + 5, Kit.STONE)
	_quadriga(g, ax0 - 1, y + 34, zm, -1, Kit.BRONZE, 0, true)

## A quadriga racing along x (dir 1 east, -1 west), the noses of its
## horses at x: four horses abreast at the gallop, every second a voxel
## back, the light car on two wheels, the charioteer in his faction's
## colour with a leather cap and the reins, a little dust behind.
static func _quadriga(g: Kit.Grid, x: int, y: int, z: int, dir: int, colour: int, seed: int, bronze := false) -> void:
	var horses := [Kit.HORSE, Kit.HORSE_D, Kit.HORSE, Kit.HORSE_W]
	if bronze:
		horses = [Kit.BRONZE, Kit.BRONZE_D, Kit.BRONZE, Kit.BRONZE_D]
	for k in 4:
		var hz := z - 4 + k * 2
		var hc: int = horses[(k + seed) % 4]
		var u0 := -(k % 2)
		# body, legs reaching fore and aft, neck up, head forward, tail
		_along(g, x, dir, u0 - 7, u0 - 1, y + 4, y + 6, hz, hz + 2, hc)
		_along(g, x, dir, u0 - 2, u0 - 1, y + 1, y + 4, hz, hz + 1, hc)
		_along(g, x, dir, u0 - 1, u0, y + 1, y + 3, hz + 1, hz + 2, hc)
		_along(g, x, dir, u0 - 7, u0 - 6, y + 1, y + 4, hz, hz + 1, hc)
		_along(g, x, dir, u0 - 8, u0 - 7, y + 2, y + 4, hz + 1, hz + 2, hc)
		_along(g, x, dir, u0 - 2, u0, y + 6, y + 8, hz, hz + 2, hc)
		_along(g, x, dir, u0, u0 + 1, y + 7, y + 8, hz, hz + 2, hc)
		_along(g, x, dir, u0 - 2, u0 - 1, y + 8, y + 9, hz, hz + 1, Kit.HAIR)
		_along(g, x, dir, u0 - 8, u0 - 7, y + 4, y + 6, hz, hz + 1, Kit.HAIR)
	# the car and its wheels, the charioteer leaning forward, the reins
	var car := Kit.BRONZE_D if bronze else Kit.WOOD
	var wheel := Kit.BRONZE_D if bronze else Kit.WOOD_D
	_along(g, x, dir, -12, -9, y + 1, y + 4, z - 2, z + 2, car)
	_along(g, x, dir, -12, -10, y + 1, y + 4, z - 3, z - 2, wheel)
	_along(g, x, dir, -12, -10, y + 1, y + 4, z + 2, z + 3, wheel)
	_along(g, x, dir, -12, -10, y + 4, y + 8, z - 1, z + 1, colour)
	_along(g, x, dir, -11, -9, y + 8, y + 9, z - 1, z + 1, Kit.BRONZE if bronze else Kit.SKIN)
	_along(g, x, dir, -11, -9, y + 9, y + 10, z - 1, z + 1, Kit.BRONZE if bronze else Kit.HELMET)
	_along(g, x, dir, -9, -7, y + 6, y + 7, z, z + 1, Kit.BRONZE_D if bronze else Kit.ROPE)
	if bronze:
		return
	for k in 6:
		var u := -14 - k * 2
		g.put(x + dir * u, y + Kit.rnd(k, 1, 0, seed) % 2, z - 2 + Kit.rnd(k, 2, 0, seed) % 5, Kit.SMOKE_L)

## A box from u0 to u1 along x in the direction dir from x (u negative is
## behind), [ya, yb) high, [za, zb) across.
static func _along(g: Kit.Grid, x: int, dir: int, u0: int, u1: int, ya: int, yb: int, za: int, zb: int, c: int) -> void:
	var a := x + dir * u0
	var b := x + dir * (u1 - 1)
	g.box(mini(a, b), ya, za, maxi(a, b) + 1, yb, zb, c)

# --- river ----------------------------------------------------------------

const RIVER_DROP := 10      # river models sit this many voxels below the town
const RIVER_Z := 58.0       # metres: the river's centre line at x = 0
const RIVER_A := 14.0       # half the southward swing of its bends, metres
const RIVER_L := 240.0      # length of one bend, metres
const QUAY_X := 72.0        # stone quays where |x| is less, banks beyond
const BANK := 7.0           # metres of bank kept clear of houses

## The river's centre line z and half width at x (metres): straight and
## narrow at the bridge (x = 0), bending south and widening either side.
static func river_at(x: float) -> Vector2:
	var c := 1.0 - cos(TAU * x / RIVER_L)
	return Vector2(RIVER_Z + RIVER_A * c, 7.0 + 1.5 * c)

## Whether lot (lx, lz) belongs to the river (water, banks, quays).
static func is_river_lot(lx: int, lz: int) -> bool:
	for k in 5:
		var x := (lx + k / 4.0) * 10.0
		var r := river_at(x)
		if lz * 10.0 < r.x + r.y + BANK and lz * 10.0 + 10.0 > r.x - r.y - BANK:
			return true
	return false

## The river over lot columns [lx0, lx0 + lots) and rows [lz0, lz0 + rows),
## RIVER_DROP voxels below the town: water with a darker band along the
## edges and a few ripples; stone quays with parapets, steps and mooring
## posts near the town centre, sloping banks of mud, reeds and grass with
## trees beyond; the arched bridge of the main north-south street; on the
## north quay warehouses, a treadwheel crane, stacks of amphorae; moored
## boats. Fills only river lots, every column of them.
static func river_strip(lx0: int, lots: int, lz0: int, rows: int) -> ArrayMesh:
	var g := _grid(lots, rows, 40)
	var m := MARGIN
	var top := RIVER_DROP + FLOOR
	for z in range(m, m + rows * LOT):
		var gz := (lz0 * LOT + z - m + 0.5) * V
		for x in range(m, m + lots * LOT):
			var gx := (lx0 * LOT + x - m + 0.5) * V
			if not is_river_lot(floori(gx / 10.0), floori(gz / 10.0)):
				continue
			var r := river_at(gx)
			var e := absf(gz - r.x) - r.y
			# quays on the town side near the centre; on the far bank a
			# stone edge, then grass and trees
			var quay := absf(gx) < QUAY_X and gz < r.x
			if e < 0.0:
				var c := Kit.WATER
				if e > -0.5:
					c = Kit.WATER_D
				elif Kit.rnd((x + z % 3) / 3, z, 0, 31) % 100 < 3:
					c = Kit.WATER_L
				g.box(x, 0, z, x + 1, 2, z + 1, c)
			elif quay:
				# an open quay: a landing 1.75 m lower along the water, then
				# the quay at street level; travertine, wet at the waterline
				var landing := e < 1.5
				var qtop := 6 if landing else top
				g.box(x, 0, z, x + 1, qtop - 1, z + 1, Kit.STONE_W if (x / 3 + z) % 5 == 0 else Kit.STONE)
				g.box(x, 2, z, x + 1, 4, z + 1, Kit.WET)
				g.put(x, 4, z, Kit.ALGAE)
				g.put(x, qtop - 1, z, Kit.PAVE_D if landing else (Kit.PAVE if (x / 4 + z / 4) % 3 else Kit.PAVE_D))
				if landing and e < V and posmod(x, 24) == 5:
					# a mooring stone with its hole
					g.box(x, qtop, z, x + 2, qtop + 2, z + 1, Kit.STONE)
					g.put(x, qtop + 1, z, Kit.DEEP)

			else:
				# an earth bank: mud darkening to the waterline, reed clumps,
				# stones, then grass up to the street level
				var h := clampi(2 + floori(e / V / 2.0), 2, top)
				if h >= top - 1:
					_lawn(g, x, z, x + 1, z + 1, 0, top, x * 7 + z)
				else:
					g.box(x, 0, z, x + 1, h, z + 1, Kit.EARTH)
					g.put(x, h - 1, z, Kit.MUD_D if h <= 3 else Kit.MUD)
					if h <= 4 and Kit.rnd(x / 2, z / 2, 9, 7) % 100 < 3:
						g.box(x - x % 2, h, z - z % 2, x - x % 2 + 2, h + 1, z - z % 2 + 2, Kit.MILL)
				var cell := x / 14
				var clump := Kit.rnd(cell, z / 40, 0, 8) % 100 < 55 and x % 14 < 6 + Kit.rnd(cell, 1, 0, 8) % 7
				if clump and e < 1.4 and Kit.rnd(x, z, 0, 6) % 100 < 55:
					g.box(x, h, z, x + 1, h + 3 + Kit.rnd(x, z, 1, 6) % 3, z + 1, Kit.REED if (x + z) % 3 else Kit.REED_D)
				elif e > 3.0 and e < 6.0 and x % 11 == 0 and z % 11 == 0 and Kit.rnd(x, z, 2, 7) % 100 < 40 and absf(gx - 5.0) > 12.0:
					_tree(g, x, h, z, 4, x * 3 + z)
	# the bridge: lot column 0, as the Pons Fabricius: a near-level deck
	# with a gentle camber on two great round arches with a flood opening
	# over the middle pier, pointed cutwaters upstream, travertine
	var bx0 := m - lx0 * LOT + 10
	if bx0 >= m and bx0 + 20 <= m + lots * LOT:
		var r0 := river_at(5.0)
		var z0 := m + roundi(((r0.x - r0.y - 3.0) / V)) - lz0 * LOT
		var z1 := m + roundi(((r0.x + r0.y + 3.0) / V)) - lz0 * LOT
		var span := z1 - z0
		var mid := (z0 + z1) / 2
		var half := (span - 8) / 2
		for z in range(z0, z1):
			var t := float(z - z0) / span
			var deck := top + roundi(2.0 * sin(PI * t))
			var lo := 0
			# two arches either side of the middle pier (8 voxels wide)
			var u := absi(z - mid) - 4
			if u >= 0 and u < half:
				var a := (u - half / 2.0 + 0.5) / (half / 2.0)
				lo = mini(2 + roundi((half / 2.0) * sqrt(maxf(0.0, 1.0 - a * a))), deck - 3)
			for x in range(bx0, bx0 + 20):
				g.box(x, lo, z, x + 1, deck, z + 1, Kit.TRAV_W if (x + z) % 7 == 0 else Kit.TRAV)
				g.put(x, deck - 1, z, Kit.BASALT_D if (z / 2 + x / 2) % 3 == 0 else Kit.BASALT)
			if lo > 0:
				g.box(bx0, lo, z, bx0 + 20, lo + 1, z + 1, Kit.TRAV_D)
			else:
				g.box(bx0, 2, z, bx0 + 20, 4, z + 1, Kit.WET)
				g.box(bx0, 4, z, bx0 + 20, 5, z + 1, Kit.ALGAE)
			g.box(bx0, deck, z, bx0 + 2, deck + 4, z + 1, Kit.TRAV_L)
			g.box(bx0 + 18, deck, z, bx0 + 20, deck + 4, z + 1, Kit.TRAV_L)
		# the flood opening through the middle pier, and its cutwater
		g.box(bx0, top - 7, mid - 2, bx0 + 20, top - 2, mid + 2, Kit.EMPTY)
		for k in 6:
			g.box(bx0 - 1 - k, 0, mid - 4 + k / 2 + 1, bx0 - k, top - 4, mid + 4 - k / 2 - 1, Kit.TRAV)
		for k in 3:
			var pz := z0 + 10 + Kit.rnd(k, 2, 0, 3) % (span - 20)
			_person(g, bx0 + 4 + Kit.rnd(k, 1, 0, 3) % 12, top + roundi(2.0 * sin(PI * float(pz - z0) / span)), pz, k)
	# trade on the north quay: warehouses, a crane, amphorae, boats
	for w: Vector2i in [Vector2i(-62, -36), Vector2i(-28, -12), Vector2i(16, 40), Vector2i(46, 66)]:
		var wx0 := m + roundi(w.x / V) - lx0 * LOT
		var wx1 := m + roundi(w.y / V) - lx0 * LOT
		if wx0 < m or wx1 > m + lots * LOT:
			continue
		var r := river_at((w.x + w.y) * 0.5)
		var front := m + roundi((r.x - r.y - 2.0) / V) - lz0 * LOT
		_warehouse(g, wx0, wx1, front - 14, front, top, w.x + w.y)
		for k in range(wx0 + 4, wx1 - 6, 14):
			_amphorae(g, k, top, front + 2)
		var bz := m + roundi((r.x - r.y + 1.0) / V) - lz0 * LOT
		_boat(g, wx0 + 4, 2, bz, w.x)
		_boat(g, wx0 + 30, 2, bz + 1, w.x + 1)
	var cxv := m + roundi(-4.0 / V) - lx0 * LOT
	if cxv > m + 20 and cxv < m + lots * LOT - 20:
		var r := river_at(-4.0)
		_crane(g, cxv - 20, top, m + roundi((r.x - r.y - 2.0) / V) - lz0 * LOT)
	return Kit.mesh(g, Vector3(-MARGIN * V, -RIVER_DROP * V, -MARGIN * V))

## A warehouse (horreum) along x, front on z1 - 1 facing the river: two
## storeys of brick, an arcade of shop doors below, small windows above,
## a tiled roof.
static func _warehouse(g: Kit.Grid, x0: int, x1: int, z0: int, z1: int, y: int, seed: int) -> void:
	var top := y + 24
	g.box(x0, y, z0, x1, top, z1, Kit.BRICK)
	for x in range(x0, x1):
		for yy in range(y, top):
			if Kit.chance(x / 3, yy, 2, seed, 10):
				g.put(x, yy, z1 - 1, Kit.BRICK_W)
	for x in range(x0 + 3, x1 - 7, 8):
		_zb(g, x, y, x + 5, y + 8, z1 - 1, -4, 1, Kit.EMPTY, 1)
		_zb(g, x + 1, y + 8, x + 4, y + 9, z1 - 1, -4, 1, Kit.EMPTY, 1)
		_zb(g, x, y - 1, x + 5, y, z1 - 1, -4, 1, Kit.PAVE_L, 1)
		_zb(g, x, y, x + 5, y + 9, z1 - 1, -5, -4, Kit.ARCADE, 1)
		_zb(g, x + 2, y, x + 3, y + 5, z1 - 1, -5, -4, Kit.DARK, 1)
		g.box(x, y, z1 - 4, x + 2, y + 3, z1 - 2, Kit.AMPHORA)
		g.box(x + 3, y, z1 - 4, x + 5, y + 2, z1 - 2, Kit.SACK)
		g.box(x - 1, y + 9, z1 - 1, x + 6, y + 10, z1, Kit.TRIM)
		_zb(g, x + 1, y + 14, x + 4, y + 18, z1 - 1, -1, 1, Kit.EMPTY, 1)
		_zb(g, x + 1, y + 14, x + 4, y + 18, z1 - 1, -2, -1, Kit.GLASS, 1)
	g.box(x0, y + 11, z1 - 1, x1, y + 12, z1 + 1, Kit.TRIM)
	g.box(x0, top - 2, z1 - 1, x1, top - 1, z1 + 1, Kit.TRIM)
	_gable(g, x0, z0, x1, z1, top, TILES_DARK if seed % 2 else TILES, Kit.BRICK, seed)

## Goods on the quay: jars of 2 x 2 x 3 with a neck and a light rim in
## two staggered rows with gaps, a crate, sacks.
static func _amphorae(g: Kit.Grid, x: int, y: int, z: int) -> void:
	for row in 2:
		for k in 3 - row:
			var ax := x + row * 1 + 3 * k + row
			var ay := y + row * 3
			g.box(ax, ay, z + row, ax + 2, ay + 3, z + row + 2, Kit.AMPHORA)
			g.put(ax, ay + 3, z + row, Kit.AMPHORA)
			g.put(ax, ay + 4, z + row, Kit.TRIM)
	g.box(x + 10, y, z, x + 13, y + 3, z + 3, Kit.WOOD)
	g.box(x + 10, y + 3, z, x + 13, y + 4, z + 3, Kit.WOOD_D)
	g.box(x + 10, y, z + 4, x + 12, y + 2, z + 6, Kit.SACK)
	g.box(x + 12, y, z + 4, x + 14, y + 2, z + 6, Kit.SACK)
	g.box(x + 11, y + 2, z + 4, x + 13, y + 3, z + 6, Kit.SACK)

## A river boat along x: a barge loaded with amphorae (seed 0), a rowing
## boat with two rowers (1), or a sailing boat with a tall mast and a
## furled sail (2).
static func _boat(g: Kit.Grid, x: int, y: int, z: int, seed: int) -> void:
	match posmod(seed, 3):
		0:
			g.box(x, y, z, x + 24, y + 2, z + 8, Kit.WOOD)
			g.box(x, y + 2, z, x + 24, y + 3, z + 1, Kit.WOOD_D)
			g.box(x, y + 2, z + 7, x + 24, y + 3, z + 8, Kit.WOOD_D)
			for k in 7:
				for r in 2:
					g.box(x + 2 + 3 * k, y + 2, z + 1 + 3 * r, x + 4 + 3 * k, y + 5, z + 3 + 3 * r, Kit.AMPHORA)
			_person(g, x + 22, y + 2, z + 3, seed)
		1:
			g.box(x, y, z, x + 10, y + 1, z + 4, Kit.WOOD)
			g.box(x, y + 1, z, x + 10, y + 2, z + 1, Kit.WOOD_D)
			g.box(x, y + 1, z + 3, x + 10, y + 2, z + 4, Kit.WOOD_D)
			_seated(g, x + 2, y + 1, z + 1, seed)
			_seated(g, x + 6, y + 1, z + 1, seed + 1)
			g.box(x + 3, y + 2, z - 2, x + 4, y + 3, z + 6, Kit.WOOD_D)
		_:
			g.box(x, y, z, x + 16, y + 2, z + 5, Kit.WOOD)
			g.box(x + 1, y + 2, z, x + 15, y + 3, z + 1, Kit.WOOD_D)
			g.box(x + 1, y + 2, z + 4, x + 15, y + 3, z + 5, Kit.WOOD_D)
			g.box(x + 16, y + 1, z + 1, x + 18, y + 3, z + 4, Kit.WOOD)
			for k in 3:
				g.box(x + 2 + 3 * k, y + 2, z + 1, x + 4 + 3 * k, y + 4, z + 3, Kit.SACK)
			g.box(x + 7, y + 2, z + 2, x + 8, y + 18, z + 3, Kit.WOOD_D)
			g.box(x + 3, y + 16, z + 2, x + 13, y + 17, z + 3, Kit.SAIL)
			g.box(x + 4, y + 15, z + 2, x + 12, y + 16, z + 3, Kit.SAIL)
			_person(g, x + 13, y + 2, z + 2, seed)

## A crane after Vitruvius (10.2) and the Haterii relief: two timbers
## leaning out over the water from the quay edge, held back by stay ropes,
## a pulley block on top, a load hanging from it; at their foot the
## treadwheel, a drum four metres across with men walking inside.
static func _crane(g: Kit.Grid, x: int, y: int, z: int) -> void:
	var tip := Vector3i(x, y + 36, z + 12)
	for foot: Vector3i in [Vector3i(x - 4, y, z), Vector3i(x + 4, y, z)]:
		_line(g, foot, tip, Kit.WOOD_D)
		_line(g, foot + Vector3i(1, 0, 0), tip + Vector3i(1, 0, 0), Kit.WOOD_D)
	g.box(tip.x - 1, tip.y - 1, tip.z - 1, tip.x + 2, tip.y + 2, tip.z + 2, Kit.WOOD)
	for back: Vector3i in [Vector3i(x - 10, y, z - 18), Vector3i(x + 10, y, z - 18)]:
		_line(g, tip, back, Kit.ROPE)
	_line(g, tip, Vector3i(tip.x, y - 2, tip.z), Kit.ROPE)
	g.box(tip.x - 1, y - 4, tip.z - 1, tip.x + 2, y - 1, tip.z + 2, Kit.AMPHORA)
	# the treadwheel behind the timbers, its axle across
	var wc := Vector3i(x, y + 8, z - 8)
	for t in 64:
		var a := TAU * t / 64.0
		var wy := wc.y + roundi(8.0 * sin(a))
		var wz := wc.z + roundi(8.0 * cos(a))
		g.box(x - 3, wy, wz, x - 2, wy + 1, wz + 1, Kit.WOOD_D)
		g.box(x + 2, wy, wz, x + 3, wy + 1, wz + 1, Kit.WOOD_D)
		if t % 4 == 0:
			g.box(x - 2, wy, wz, x + 2, wy + 1, wz + 1, Kit.WOOD)
	for k in 4:
		var a := TAU * k / 8.0
		for r in range(-7, 8):
			g.put(x - 3, wc.y + roundi(r * sin(a)), wc.z + roundi(r * cos(a)), Kit.WOOD)
			g.put(x + 2, wc.y + roundi(r * sin(a)), wc.z + roundi(r * cos(a)), Kit.WOOD)
	g.box(x - 5, wc.y, wc.z, x + 5, wc.y + 1, wc.z + 1, Kit.WOOD_D)
	for k in 2:
		_person(g, x - 2 + k * 2, wc.y - 7, wc.z - 1 + k, k)
	_line(g, Vector3i(x, wc.y, wc.z), tip, Kit.ROPE)

## A line of voxels from a to b.
static func _line(g: Kit.Grid, a: Vector3i, b: Vector3i, c: int) -> void:
	var d := b - a
	var n := maxi(maxi(absi(d.x), absi(d.y)), absi(d.z))
	for k in n + 1:
		var t := float(k) / maxf(1.0, n)
		g.put(roundi(a.x + d.x * t), roundi(a.y + d.y * t), roundi(a.z + d.z * t), c)

# --- necropolis -----------------------------------------------------------

## A lot of tombs along the road out of town, as outside the Porta Ercolano
## at Pompeii or at Isola Sacra: monuments shoulder to shoulder along the
## road edge (`road_east`: the road runs past the lot's east side), 3 to 8 m
## tall: altar tombs on stepped bases, a shrine tomb with a statue, a
## semicircular bench tomb, brick house tombs with a pediment and a white
## inscription; cypresses behind them.
static func tombs(seed: int, road_east := true) -> ArrayMesh:
	var g := _grid(1, 1, 48)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	var edge := m + LOT - 1 if road_east else m
	var inward := -1 if road_east else 1
	var z := m
	var k := 0
	while z < m + LOT - 6:
		var w: int = [10, 8, 12, 9, 10][(seed + k) % 5]
		var d: int = [10, 8, 12, 12, 9][(seed + k) % 5]
		var x0 := edge + inward * (d - 1) if road_east else edge
		var x1 := x0 + d
		var y := FLOOR
		match (seed + k) % 5:
			0:
				# altar tomb on three steps
				for st in 3:
					g.box(x0 + st, y + st, z + st, x1 - st, y + st + 1, z + w - st, Kit.STEP)
				g.box(x0 + 3, y + 3, z + 3, x1 - 3, y + 12, z + w - 3, Kit.MARBLE)
				g.box(x0 + 2, y + 12, z + 2, x1 - 2, y + 13, z + w - 2, Kit.TRIM)
				g.box(x0 + 3, y + 13, z + 3, x0 + 4, y + 15, z + w - 3, Kit.TRIM)
				g.box(x1 - 4, y + 13, z + 3, x1 - 3, y + 15, z + w - 3, Kit.TRIM)
				g.box(x0 + 4, y + 6, z + w - 3, x1 - 4, y + 7, z + w - 2, Kit.LETTER)
			1:
				# shrine tomb: podium, two columns, a statue, a pediment
				g.box(x0, y, z, x1, y + 8, z + w, Kit.TRAV)
				g.box(x0, y + 7, z, x1, y + 8, z + w, Kit.TRIM)
				g.box(x0 + 1, y + 8, z + 1, x1 - 1, y + 9, z + 2, Kit.MARBLE)
				for cz: int in [z + 1, z + w - 2]:
					g.box(x0 + 1, y + 8, cz, x0 + 2, y + 20, cz + 1, Kit.MARBLE)
				g.box(x1 - 3, y + 8, z + 1, x1 - 1, y + 20, z + w - 1, Kit.MARBLE)
				_figure(g, x0 + 3, y + 8, z + w / 2 - 1, Kit.STATUE)
				g.box(x0, y + 20, z, x1, y + 21, z + w, Kit.TRIM)
				_roof(g, Rect2i(x0, z, d, w), [], [Rect2i(x0, z, d, w)], y + 21, "x", TILES, Kit.MARBLE, seed + k)
			2:
				# a semicircular bench (schola) facing the road
				var cz := z + w / 2
				for a in 13:
					var t := PI * a / 12.0
					var bx := (x0 + d / 2) + roundi(cos(t) * 5.0) * -inward
					var bz := cz + roundi(sin(t - PI / 2.0) * 5.0)
					g.box(bx, y, bz, bx + 1, y + 2, bz + 1, Kit.TRAV)
					g.box(bx - inward, y, bz, bx - inward + 1, y + 4, bz + 1, Kit.TRAV)
				g.box(x0 + d / 2 - 1, y, cz - 1, x0 + d / 2 + 1, y + 6, cz + 1, Kit.MARBLE)
			3:
				# brick house tomb: a pediment, a white inscription panel
				g.box(x0, y, z, x1, y + 16, z + w, Kit.BRICKFACE)
				for yy in range(y + 2, y + 16, 3):
					g.swap(x0, yy, z, x1, yy + 1, z + w, Kit.BRICKFACE, Kit.MORTAR)
				g.box(x0 + 2, y + 8, z + w - 1, x1 - 2, y + 11, z + w, Kit.TRIM)
				g.box(x0 + 3, y + 9, z + w - 1, x1 - 3, y + 10, z + w, Kit.LETTER)
				g.box(x0 + 3, y, z + w - 1, x1 - 3, y + 6, z + w, Kit.DOOR_D)
				_roof(g, Rect2i(x0, z, d, w), [], [Rect2i(x0, z, d, w)], y + 16, "z", TILES, Kit.BRICKFACE, seed + k)
			_:
				# a drum on a square base, a cone of earth and grass on top
				g.box(x0, y, z, x1, y + 2, z + w, Kit.STONE)
				_disc(g, x0 + d / 2, y + 2, z + w / 2, mini(d, w) / 2 - 1, 9, Kit.TRAV)
				_disc(g, x0 + d / 2, y + 10, z + w / 2, mini(d, w) / 2 - 1, 1, Kit.TRIM)
				for c in 4:
					_disc(g, x0 + d / 2, y + 11 + c, z + w / 2, mini(d, w) / 2 - 2 - c, 1, Kit.GRASS if c % 2 == 0 else Kit.GRASS_D)
		z += w
		k += 1
	for cz in range(m + 4, m + LOT - 4, 9):
		_cypress(g, (m + 4) if road_east else (m + LOT - 8), FLOOR, cz, 20 + (seed + cz) % 6, seed + cz)
	_person(g, edge + inward * 14, FLOOR, m + 10 + seed % 20, seed)
	return _done(g)

# --- country --------------------------------------------------------------

## A market garden: beds of soil with rows of crops two voxels apart, a
## worn path, a low stone wall, a hut, a gardener.
static func farm(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 24)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	var crops := [Kit.LEAF_L, Kit.FRUIT_R, Kit.LEAF, Kit.FRUIT_Y, Kit.VINE, Kit.LEAF_D]
	for bed in 2:
		var bz0 := m + 3 + bed * 18
		var crop: int = crops[(seed + bed) % crops.size()]
		for z in range(bz0, bz0 + 15):
			for x in range(m + 3, m + LOT - 3):
				g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.SOIL)
				if (z - bz0) % 2 == 0 and x % 3 != 0:
					g.put(x, FLOOR, z, crop if (x + z) % 5 else Kit.LEAF)
	g.box(m + 3, 0, m + 18, m + LOT - 3, FLOOR, m + 21, Kit.PATH)
	for side: Array in [[m, m, m + LOT, m + 1], [m, m, m + 1, m + LOT], [m + LOT - 1, m, m + LOT, m + LOT]]:
		g.box(side[0], FLOOR, side[1], side[2], FLOOR + 2, side[3], Kit.STONE)
	if seed % 2 == 0:
		g.box(m + 30, FLOOR, m + 30, m + 37, FLOOR + 6, m + 37, Kit.WOOD)
		g.box(m + 32, FLOOR, m + 37, m + 34, FLOOR + 5, m + 38, Kit.WOOD_D)
		for z in range(m + 29, m + 39):
			g.box(m + 29, FLOOR + 6 + (38 - z) / 4, z, m + 38, FLOOR + 7 + (38 - z) / 4, z + 1, Kit.TILE3)
	_person(g, m + 10 + seed % 20, FLOOR, m + 19, seed)
	return _done(g)

## A vineyard: rows of posts four voxels apart, vines on them, grass
## between, a worn path.
static func vineyard(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 24)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	for z in range(m + 2, m + LOT - 2, 4):
		for x in range(m + 2, m + LOT - 2):
			g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.SOIL)
			if x % 3 == 0:
				g.box(x, FLOOR, z, x + 1, FLOOR + 4, z + 1, Kit.WOOD_D)
			g.box(x, FLOOR + 3, z, x + 1, FLOOR + 5, z + 1, Kit.VINE if (x + z) % 4 else Kit.LEAF_L)
			if (x + z) % 7 == 0:
				g.put(x, FLOOR + 2, z, Kit.SHUTTER_U)
	g.box(m + 18, 0, m, m + 21, FLOOR, m + LOT, Kit.PATH)
	_person(g, m + 19, FLOOR, m + 6 + seed % 26, seed)
	return _done(g)

## A pasture with sheep, a shepherd and a wooden fence.
static func pasture(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 24)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	for x in range(m, m + LOT):
		if x % 4 == 0:
			g.box(x, FLOOR, m, x + 1, FLOOR + 3, m + 1, Kit.WOOD_D)
	g.box(m, FLOOR + 2, m, m + LOT, FLOOR + 3, m + 1, Kit.WOOD)
	for k in 5 + seed % 3:
		var sx := m + 3 + Kit.rnd(k, 1, 0, seed) % 32
		var sz := m + 4 + Kit.rnd(k, 2, 0, seed) % 30
		g.box(sx, FLOOR + 1, sz, sx + 4, FLOOR + 3, sz + 2, Kit.WOOL)
		g.box(sx, FLOOR, sz, sx + 1, FLOOR + 1, sz + 2, Kit.HAIR)
		g.box(sx + 3, FLOOR, sz, sx + 4, FLOOR + 1, sz + 2, Kit.HAIR)
		g.box(sx + 4, FLOOR + 2, sz, sx + 5, FLOOR + 4, sz + 2, Kit.HAIR)
	_person(g, m + 20, FLOOR, m + 20, seed)
	g.box(m + 22, FLOOR, m + 20, m + 23, FLOOR + 9, m + 21, Kit.WOOD_D)
	_tree(g, m + 30, FLOOR, m + 30, 5, seed)
	return _done(g)

# --- terraces -------------------------------------------------------------

const TERRACE := 14   # voxels a terrace stands above the one below

## The base of a raised lot `level` terraces up: earth under coursed
## stone retaining walls where the neighbour is lower (`walls` bits: 1
## south, 2 west, 4 east), joints every third course, buttresses 2 x 2
## every ten voxels, a pale top course and a low parapet; on the south side
## a flight of stairs up the wall on some, a row of cypresses along the
## top edge. Lot content stands on it at level * TERRACE.
static func terrace(level: int, walls: int, seed: int) -> ArrayMesh:
	var top := level * TERRACE
	var g := _grid(1, 1, top + 28)
	var m := MARGIN
	g.box(m, 0, m, m + LOT, top, m + LOT, Kit.EARTH)
	for side in 3:
		if walls & (1 << side) == 0:
			continue
		var o := Vector2i(0, 1) if side == 0 else (Vector2i(-1, 0) if side == 1 else Vector2i(1, 0))
		for k in LOT:
			var p := Vector2i(m + k, m + LOT - 1) if side == 0 else (Vector2i(m, m + k) if side == 1 else Vector2i(m + LOT - 1, m + k))
			# coursed tuff with a blind arcade, as on the substructures at
			# Praeneste and Terracina: arches seven wide every ten voxels
			var base := top - TERRACE + FLOOR
			var arch := posmod(k, 10) - 2
			var head: int = [5, 4, 3, 3, 3, 4, 5][clampi(arch, 0, 6)]
			for yy in top:
				var joint := yy % 3 == 2 or (k + (yy / 3) * 2) % 6 == 0
				var blind := arch >= 0 and arch <= 6 and yy >= base and yy < top - head
				if blind:
					g.put(p.x, yy, p.y, Kit.EMPTY)
					g.put(p.x - o.x, yy, p.y - o.y, Kit.TUFF_D)
				else:
					g.put(p.x, yy, p.y, Kit.TUFF_D if joint else Kit.TUFF)
			g.put(p.x, top - 1, p.y, Kit.TRIM)
			if k % 8 != 3:
				g.put(p.x, top + 2, p.y, Kit.TRIM)
	if walls & 1:
		if seed % 2 == 0:
			# a flight of stairs up the south wall, rising west to east
			for k in TERRACE:
				var sx := m + 8 + k
				g.box(sx, 0, m + LOT, sx + 1, top - TERRACE + k + 3, m + LOT + 3, Kit.STEP)
			g.box(m + 7, 0, m + LOT, m + 8, top - TERRACE + 5, m + LOT + 3, Kit.COURSE)
		if walls & 8 == 0:
			var x := m + 2 + seed % 4
			while x < m + LOT - 5:
				if Kit.chance(x, top, 0, seed, 70):
					_cypress(g, x, top + 2, m + LOT - 6, 18 + (x + seed) % 6, seed + x)
				x += 6 + Kit.rnd(x, 1, 0, seed) % 5
	return _done(g)


## A garden on a terrace as in a Roman villa: a long canal (euripus) with
## a stone rim between two vine pergolas, lawn and box-edged walks, statues
## at the canal's ends, an oleander, a small tree at the back.
static func terrace_garden(seed: int) -> ArrayMesh:
	var g := _grid(1, 1, 30)
	var m := MARGIN
	_grass(g, m, m, m + LOT, m + LOT, seed)
	g.box(m + 3, 0, m + 15, m + 37, FLOOR, m + 27, Kit.GRAVEL)
	g.box(m + 6, 0, m + 18, m + 34, FLOOR + 1, m + 24, Kit.TRIM)
	g.box(m + 7, 0, m + 19, m + 33, FLOOR + 1, m + 23, Kit.EMPTY)
	g.box(m + 7, 0, m + 19, m + 33, 1, m + 23, Kit.WATER)
	for z: int in [m + 15, m + 26]:
		g.box(m + 3, FLOOR, z, m + 37, FLOOR + 1, z + 1, Kit.BOX)
	for z: int in [m + 12, m + 28]:
		for x in range(m + 5, m + 36, 5):
			g.box(x, FLOOR, z, x + 1, FLOOR + 9, z + 1, Kit.WOOD_D)
		g.box(m + 5, FLOOR + 9, z - 1, m + 36, FLOOR + 10, z + 2, Kit.VINE)
		for x in range(m + 6, m + 35, 3):
			g.box(x, FLOOR + 10, z - 1, x + 2, FLOOR + 11, z + 2, Kit.LEAF)
	_figure(g, m + 1, FLOOR, m + 19, Kit.STATUE)
	_figure(g, m + 35, FLOOR, m + 19, Kit.STATUE)
	g.box(m + 30, FLOOR, m + 3, m + 35, FLOOR + 3, m + 7, Kit.LEAF_D)
	for k in 5:
		g.put(m + 30 + Kit.rnd(k, 1, 0, seed) % 5, FLOOR + 3, m + 3 + Kit.rnd(k, 2, 0, seed) % 4, Kit.BLOSSOM_P)
	_tree(g, m + 8, FLOOR, m + 4, 3, seed)
	_person(g, m + 20, FLOOR, m + 30, seed)
	_seated(g, m + 12, FLOOR + 1, m + 26, seed + 1)
	return _done(g)
