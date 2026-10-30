extends RefCounted
## The pieces the city plans need beyond the Roman town's lots
## (docs/kit2/CITY_PLANS.md, drawn by tile_terrain.gd): the city wall in
## pieces that join like Urbek's walls, its gate, and the public buildings
## of a town on a single lot, since nearly every one in the plans has one
## parcel (a lot of 10 m, voxel/roman_town.gd). Same craft as the town:
## 0.25 m voxels, a lot in the middle of a grid with margins, the front
## +z (south, towards the camera).
##
## The city wall is drawn in pieces (`wall(variant)`): 0 an arm from the
## parcel's middle east to its edge, 1 a longer arm east that tile_terrain.gd
## turns an eighth to run to the parcel's corner (the plans' walls step
## diagonally as often as straight; drawn diagonally in voxels they were a
## staircase that read as a fence of white bars), 2 a tower. tile_terrain.gd
## sets one turned arm for each neighbour on the wall and a tower where it
## turns or ends; arms run three voxels past the lot, so those of
## neighbouring parcels meet across the street between the lots
## (tile_terrain.gd LOT_SHARE), the diagonal ones two voxels past the corner.

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Town := preload("res://scripts/voxel/roman_town.gd")
const LOT := Kit.LOT
const M := Town.MARGIN
const FLOOR := Town.FLOOR
const C := M + LOT / 2 # the lot's middle

const WALL_VARIANTS := 3
const WALL_HALF := 5 # half the wall's thickness (2.5 m)
const WALL_TOP := FLOOR + 28 # the walk on top, 7 m
const REACH := 3 # voxels past the lot edge
const DIAG_END := 33 # the diagonal arm: to the parcel's corner (21.75 voxels times the root of two) and two on
const DIAG_C := DIAG_END + WALL_HALF + 1 # the middle of its larger grid

## A piece of the city wall: ashlar courses, a walk with a parapet and
## merlons on both faces; or a tower with a tiled roof.
static func wall(variant: int) -> ArrayMesh:
	if variant == 1:
		# a grid centred on the arm's start like a lot's, large enough for it
		var d := Kit.Grid.new(Vector3i(2 * DIAG_C, 64, 2 * DIAG_C))
		_wall_run(d, Vector2(1.0, 0.0), float(DIAG_END), DIAG_C)
		return Town._done(d)
	var g := Town._grid(1, 1, 64)
	if variant == 2:
		_tower(g, C, C, 8, FLOOR + 42, variant)
	else:
		_wall_run(g, Vector2(1.0, 0.0), float(LOT / 2 + REACH))
	return Town._done(g)

## The wall from the grid's middle `c` along `dir` for `end` voxels across x;
## the middle is covered round, so arms join at any angle.
static func _wall_run(g: Kit.Grid, dir: Vector2, end: float, c := C) -> void:
	var u := dir.normalized()
	var length := end * dir.length()
	var half := float(WALL_HALF)
	for z in g.n.z:
		for x in g.n.x:
			var p := Vector2(x + 0.5 - c, z + 0.5 - c)
			var along := p.dot(u)
			var across := absf(p.x * u.y - p.y * u.x)
			var inside := across < half and along > -half and along < length
			if not inside:
				continue
			g.box(x, FLOOR, z, x + 1, WALL_TOP, z + 1, Kit.TRAV_C)
			for y in range(FLOOR + 3, WALL_TOP, 4):
				g.put(x, y, z, Kit.TRAV_CW)
			g.box(x, FLOOR, z, x + 1, FLOOR + 2, z + 1, Kit.COURSE)
			if across >= half - 1.0 and along > -half + 1.0:
				# parapet and merlons on both faces
				g.box(x, WALL_TOP, z, x + 1, WALL_TOP + 2, z + 1, Kit.TRAV_C)
				g.put(x, WALL_TOP + 2, z, Kit.TRIM)
				if posmod(int(floor(along)), 5) < 3:
					g.box(x, WALL_TOP + 3, z, x + 1, WALL_TOP + 6, z + 1, Kit.TRAV_C)
			else:
				g.put(x, WALL_TOP - 1, z, Kit.PAVE_D)

## A square tower of half width h round (x, z) up to `top`: courses, slit
## windows on the faces to the camera, a hipped tile roof.
static func _tower(g: Kit.Grid, x: int, z: int, h: int, top: int, seed: int) -> void:
	g.box(x - h, FLOOR, z - h, x + h, top, z + h, Kit.TRAV_C)
	for y in range(FLOOR + 3, top, 4):
		g.paint(x - h, y, z - h, x + h, y + 1, z + h, Kit.TRAV_CW)
	g.paint(x - h, FLOOR, z - h, x + h, FLOOR + 2, z + h, Kit.COURSE)
	g.box(x - h - 1, top - 2, z - h - 1, x + h + 1, top, z + h + 1, Kit.TRIM)
	for y: int in [WALL_TOP - 8, top - 9]:
		for o: int in [-h / 2, h / 2 - 1]:
			g.box(x + o, y, z + h - 1, x + o + 2, y + 5, z + h, Kit.DARK)
			g.box(x + h - 1, y, z + o, x + h, y + 5, z + o + 2, Kit.DARK)
	var outer := Rect2i(x - h - 1, z - h - 1, 2 * h + 2, 2 * h + 2)
	Town._roof(g, outer, [], [Rect2i(x - h, z - h, 2 * h, 2 * h)], top, "hip", Town.TILES, Kit.TRAV_C, seed, true)

## A city gate: the wall runs east and west, the street north and south
## through an arched passage between two towers, a gallery of arches above
## it (Turin's Porta Palatina, Trier's Porta Nigra in small).
static func gate(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 64)
	var end := float(LOT / 2 + REACH)
	_wall_run(g, Vector2(1.0, 0.0), end)
	_wall_run(g, Vector2(-1.0, 0.0), end)
	var half := 7 # half the passage
	var body_top := WALL_TOP + 4
	g.box(C - half - 2, FLOOR, C - WALL_HALF - 1, C + half + 2, body_top, C + WALL_HALF + 1, Kit.TRAV_C)
	for y in range(FLOOR + 3, body_top, 4):
		g.paint(C - half - 2, y, C - WALL_HALF - 1, C + half + 2, y + 1, C + WALL_HALF + 1, Kit.TRAV_CW)
	# the passage and its round arch, the voussoirs a lighter stone
	var spring := FLOOR + 16
	g.box(C - half, FLOOR, C - WALL_HALF - 1, C + half, spring, C + WALL_HALF + 1, Kit.EMPTY)
	for dx in range(-half, half):
		var e := float(dx) + 0.5
		var rise := int(sqrt(maxf(float(half * half) - e * e, 0.0)))
		g.box(C + dx, spring, C - WALL_HALF - 1, C + dx + 1, spring + rise, C + WALL_HALF + 1, Kit.EMPTY)
		g.box(C + dx, spring + rise, C + WALL_HALF, C + dx + 1, spring + rise + 1, C + WALL_HALF + 1, Kit.TRAV_L)
	g.box(C - half - 2, body_top - 1, C - WALL_HALF - 1, C + half + 2, body_top, C + WALL_HALF + 2, Kit.TRIM)
	# the gallery over the passage: arched windows on the street front
	for k in 3:
		var wx := C - half + 1 + k * 5
		g.box(wx, spring + half + 3, C + WALL_HALF, wx + 3, spring + half + 9, C + WALL_HALF + 1, Kit.DARK)
		g.box(wx, spring + half + 2, C + WALL_HALF + 1, wx + 3, spring + half + 3, C + WALL_HALF + 2, Kit.TRIM)
	for x: int in [C - half - 8, C + half + 8]:
		_tower(g, x, C, 6, FLOOR + 44, seed + x)
	# a sentry on the walk, a carter in the passage
	Town._person(g, C + half + 14, WALL_TOP, C - 1, seed)
	Town._person(g, C - 2, FLOOR, C + WALL_HALF + 4, seed + 3)
	return Town._done(g)

# --- public buildings on one lot -------------------------------------------

## A temple on a podium in its paved precinct: four columns before the
## cella, pediment and tile roof (roman_town.gd _temple), cypresses behind.
static func temple(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 60)
	Town._paving(g, M, M, M + LOT, M + LOT, seed)
	var rise: int = [5, 6][seed % 2]
	var front := M + LOT - 3 - 2 * rise
	Town._temple(g, C, M + 3, 11, front, 4, rise, 20, seed % 2 == 1, seed)
	for p: Vector2i in [Vector2i(M + 1, M + 2), Vector2i(M + LOT - 5, M + 2), Vector2i(M + 1, M + 16)]:
		Town._cypress(g, p.x, FLOOR, p.y, 20 + Kit.rnd(p.x, p.y, 0, seed) % 5, seed + p.y)
	Town._statue(g, M + 2, FLOOR, M + LOT - 7, seed)
	g.box(M + LOT - 8, FLOOR, M + LOT - 6, M + LOT - 4, FLOOR + 4, M + LOT - 2, Kit.STONE)
	g.box(M + LOT - 8, FLOOR + 4, M + LOT - 6, M + LOT - 4, FLOOR + 5, M + LOT - 2, Kit.TRIM)
	g.box(M + LOT - 7, FLOOR + 5, M + LOT - 5, M + LOT - 5, FLOOR + 6, M + LOT - 3, Kit.FRUIT_R)
	Town._person(g, M + LOT - 11, FLOOR, M + LOT - 4, seed)
	return Town._done(g)

## A theatre: the cavea in a half circle at the back, open to the camera,
## the orchestra, a low stage and a stage front of columns, an arcade
## round the outside.
static func theatre(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 48)
	Town._paving(g, M, M, M + LOT, M + LOT, seed)
	var zc := M + 27 # middle of the half circle
	var outer := 19.5
	var inner := 6.5
	for z in range(M, zc + 1):
		for x in range(M, M + LOT):
			var d := Vector2(x + 0.5 - C, z + 0.5 - zc).length()
			if d > outer:
				continue
			if d < inner:
				g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.MARBLE)
				continue
			if d > outer - 1.5:
				# the outer wall, arches in it
				var arch := posmod(int(atan2(z - zc, x - C) * 12.0), 3) == 0
				g.box(x, FLOOR, z, x + 1, FLOOR + 22, z + 1, Kit.TRAV_C)
				if arch:
					g.box(x, FLOOR + 3, z, x + 1, FLOOR + 9, z + 1, Kit.ARCH_D)
					g.box(x, FLOOR + 12, z, x + 1, FLOOR + 17, z + 1, Kit.ARCH_D)
				g.put(x, FLOOR + 22, z, Kit.TRIM)
				continue
			# seats rising a voxel for every voxel out, a gangway halfway
			var row := int(d - inner)
			var top := FLOOR + 1 + row * 18 / int(outer - inner)
			var c := Kit.SEAT if row % 2 == 0 else Kit.SEAT_D
			if row == 6:
				c = Kit.SEAT_HI
			g.box(x, FLOOR, z, x + 1, top, z + 1, c)
	# stairs up the cavea, darker
	for a: float in [-0.55, 0.0, 0.55]:
		for r in range(int(inner), int(outer) - 1):
			var x := C + int(round(sin(a) * r))
			var z := zc - int(round(cos(a) * r))
			var top := FLOOR + 1 + (r - int(inner)) * 18 / int(outer - inner)
			g.box(x, FLOOR, z, x + 1, top, z + 1, Kit.STEP)
	# the stage and its front of columns, low enough to see the seats
	g.box(M + 3, FLOOR, zc + 1, M + LOT - 3, FLOOR + 4, zc + 7, Kit.WOOD)
	g.box(M + 3, FLOOR, zc + 7, M + LOT - 3, FLOOR + 4, zc + 8, Kit.TRAV)
	g.box(M + 2, FLOOR, zc + 8, M + LOT - 2, FLOOR + 12, zc + 11, Kit.CREAM)
	for x in range(M + 3, M + LOT - 3, 4):
		Town._column(g, x, FLOOR + 4, zc + 7, FLOOR + 12, Kit.MARBLE)
	for x: int in [C - 2, M + 9, M + LOT - 12]:
		g.box(x, FLOOR, zc + 10, x + 4, FLOOR + 8, zc + 11, Kit.DOOR_D)
	g.box(M + 2, FLOOR + 12, zc + 7, M + LOT - 2, FLOOR + 13, zc + 11, Kit.TRIM)
	for k in 5:
		Town._person(g, M + 8 + Kit.rnd(k, 1, 0, seed) % 24, FLOOR + 6, zc - 9 - Kit.rnd(k, 2, 0, seed) % 3, seed + k)
	Town._person(g, C + 2, FLOOR + 4, zc + 3, seed + 9)
	return Town._done(g)

## An amphitheatre: seats round an oval of sand, an outer wall of two
## tiers of arches with a cornice.
static func amphitheatre(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 40)
	var ax := 19.5
	var az := 17.0
	for z in range(M, M + LOT):
		for x in range(M, M + LOT):
			var u := Vector2((x + 0.5 - C) / ax, (z + 0.5 - C) / az)
			var e := u.length() # 1 on the outer wall
			if e > 1.0:
				continue
			if e < 0.45:
				g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.ARENA if Kit.chance(x / 2, z / 2, 0, seed, 80) else Kit.ARENA_D)
				continue
			if e < 0.5:
				g.box(x, FLOOR, z, x + 1, FLOOR + 4, z + 1, Kit.TRAV) # the podium wall round the arena
				g.put(x, FLOOR + 4, z, Kit.TRIM)
				continue
			if e > 0.93:
				var arch := posmod(int(atan2(u.y, u.x) * 16.0), 2) == 0
				g.box(x, FLOOR, z, x + 1, FLOOR + 24, z + 1, Kit.TRAV)
				if arch:
					g.box(x, FLOOR + 2, z, x + 1, FLOOR + 9, z + 1, Kit.ARCH_D)
					g.box(x, FLOOR + 12, z, x + 1, FLOOR + 19, z + 1, Kit.ARCH_D)
				g.put(x, FLOOR + 10, z, Kit.TRIM)
				g.put(x, FLOOR + 24, z, Kit.TRIM)
				continue
			var row := int((e - 0.5) / 0.43 * 9.0)
			g.box(x, FLOOR, z, x + 1, FLOOR + 5 + row * 2, z + 1, Kit.SEAT if row % 2 == 0 else Kit.SEAT_D)
	# the gates at the ends of the long axis
	for x: int in [M, M + LOT - 3]:
		g.box(x, FLOOR, C - 3, x + 3, FLOOR + 12, C + 3, Kit.ARCH_D)
	for k in 8:
		var t := float(k) / 8.0 * TAU
		var x := C + int(cos(t) * 13.0)
		var z := C + int(sin(t) * 11.0)
		Town._person(g, x, FLOOR + 10, z, seed + k)
	Town._person(g, C - 3, FLOOR, C, seed + 20)
	Town._person(g, C + 3, FLOOR, C + 1, seed + 21)
	return Town._done(g)

## Baths: a brick block of halls under tile roofs with a lead dome over the
## hot room and big arched windows, a court with a pool in front, the
## furnace's smoke.
static func baths(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 72)
	Town._paving(g, M, M, M + LOT, M + LOT, seed)
	var z1 := M + 24
	var top := FLOOR + 26
	g.box(M + 1, FLOOR, M + 2, M + LOT - 1, top, z1, Kit.BRICKFACE)
	for y in range(FLOOR + 2, top, 3):
		g.paint(M + 1, y, M + 2, M + LOT - 1, y + 1, z1, Kit.BRICKFACE_W)
	g.box(M + 1, top - 1, M + 2, M + LOT - 1, top, z1 + 1, Kit.TRIM)
	# big arched windows of the halls on the front
	for x in range(M + 4, M + LOT - 6, 8):
		g.box(x, FLOOR + 8, z1 - 1, x + 4, FLOOR + 18, z1, Kit.GLASS)
		g.box(x + 1, FLOOR + 18, z1 - 1, x + 3, FLOOR + 19, z1, Kit.GLASS)
		g.box(x - 1, FLOOR + 7, z1, x + 5, FLOOR + 8, z1 + 1, Kit.TRIM)
	g.box(C - 3, FLOOR, z1 - 1, C + 3, FLOOR + 9, z1, Kit.DOOR_D)
	Town._gable(g, M + 1, M + 2, M + LOT - 1, z1, top, Town.TILES, Kit.BRICKFACE, seed)
	# the hot room's dome on a drum
	var dz := M + 12
	Town._disc(g, C, top, dz, 8, 6, Kit.BRICKFACE)
	g.paint(C - 9, top + 5, dz - 9, C + 9, top + 6, dz + 9, Kit.TRIM)
	for k in 7:
		Town._disc(g, C, top + 6 + k, dz, maxi(1, 8 - k * k / 5), 1, Kit.LEAD if k % 2 == 0 else Kit.LEAD_L)
	# the court: a pool with a rim, benches, bathers
	g.box(M + 6, 0, z1 + 4, M + LOT - 6, FLOOR, M + LOT - 3, Kit.TRAV)
	g.box(M + 7, 0, z1 + 5, M + LOT - 7, FLOOR, M + LOT - 4, Kit.POOL)
	g.box(M + 6, FLOOR, z1 + 4, M + LOT - 6, FLOOR + 1, z1 + 5, Kit.TRAV)
	g.box(M + 6, FLOOR, M + LOT - 4, M + LOT - 6, FLOOR + 1, M + LOT - 3, Kit.TRAV)
	for k in 3:
		Town._person(g, M + 4 + k * 13, FLOOR, z1 + 2 + k % 2, seed + k)
	# the furnace at the back corner and its smoke
	var fx := M + LOT - 6
	g.box(fx, top, M + 3, fx + 3, top + 10, M + 6, Kit.BRICK)
	for k in 12:
		var c := Kit.SMOKE_D if k < 4 else (Kit.SMOKE if k < 8 else Kit.SMOKE_L)
		g.box(fx + k / 4, top + 10 + k, M + 3, fx + 3 + k / 4, top + 11 + k, M + 6, c)
	return Town._done(g)

## A basilica (any hall of the town: court, curia, palace): a nave along x
## above two aisles, clerestory windows, tile roofs, a porch of columns on
## the street front with steps.
static func basilica(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 64)
	Town._paving(g, M, M, M + LOT, M + LOT, seed)
	var wall: int = [Kit.CREAM, Kit.BRICKFACE, Kit.STUCCO][seed % 3]
	var z0 := M + 4
	var z1 := M + 28
	var aisle := FLOOR + 18
	var nave := FLOOR + 28
	g.box(M + 1, FLOOR, z0, M + LOT - 1, aisle, z1, wall)
	g.box(M + 1, FLOOR, z0 + 6, M + LOT - 1, nave, z1 - 6, wall)
	g.box(M + 1, FLOOR, z0, M + LOT - 1, FLOOR + 2, z1, Kit.COURSE)
	for x in range(M + 4, M + LOT - 4, 5):
		g.box(x, aisle + 3, z1 - 7, x + 2, aisle + 8, z1 - 6, Kit.GLASS) # clerestory
		g.box(x, FLOOR + 6, z1 - 1, x + 2, FLOOR + 13, z1, Kit.DARK)
	g.box(M + 1, nave - 1, z0 + 6, M + LOT - 1, nave, z1 - 5, Kit.TRIM)
	g.box(M + 1, aisle - 1, z0, M + LOT - 1, aisle, z1 + 1, Kit.TRIM)
	Town._roof(g, Rect2i(M, z1 - 6, LOT, 7), [], [], aisle, "x", Town.TILES, wall, seed)
	Town._roof(g, Rect2i(M, z0 - 1, LOT, 7), [], [], aisle, "x", Town.TILES, wall, seed)
	Town._gable(g, M + 1, z0 + 6, M + LOT - 1, z1 - 6, nave, Town.TILES, wall, seed)
	# the porch: columns on steps, a lean-to roof
	g.box(M + 2, 0, z1, M + LOT - 2, FLOOR + 1, M + LOT - 2, Kit.STEP)
	g.box(M + 2, FLOOR + 1, z1, M + LOT - 2, FLOOR + 2, z1 + 6, Kit.STEP)
	for x in range(M + 3, M + LOT - 4, 5):
		Town._column(g, x, FLOOR + 2, z1 + 5, FLOOR + 15, Kit.MARBLE)
	g.box(M + 2, FLOOR + 15, z1, M + LOT - 2, FLOOR + 16, z1 + 7, Kit.TRIM)
	Town._roof(g, Rect2i(M + 2, z1 - 3, LOT - 4, 11), [], [], FLOOR + 16, "x", Town.TILES, wall, seed)
	g.box(C - 3, FLOOR + 2, z1 - 1, C + 3, FLOOR + 12, z1, Kit.DOOR_D)
	for k in 4:
		Town._person(g, M + 5 + k * 9, FLOOR + 2, z1 + 2 + k % 3, seed + k)
	return Town._done(g)

## Warehouses (horrea, a harbour's quay): a brick store of arched doors
## round a court, jars and sacks before it.
static func horrea(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 48)
	Town._paving(g, M, M, M + LOT, M + LOT, seed)
	Town._warehouse(g, M + 1, M + LOT - 1, M + 3, M + 30, FLOOR, seed)
	Town._amphorae(g, M + 4, FLOOR, M + 33)
	Town._person(g, M + 26, FLOOR, M + 34, seed)
	return Town._done(g)

## A stretch of a circus or a stadium along x: the sand track with the low
## spina in the middle, stands on both sides behind a podium wall.
static func circus(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 36)
	var lo := M - REACH
	var hi := M + LOT + REACH
	for z in range(M, M + LOT):
		var d := absi(z * 2 + 1 - 2 * C) / 2 # from the middle
		for x in range(lo, hi):
			if d < 2:
				g.box(x, FLOOR, z, x + 1, FLOOR + 3, z + 1, Kit.TRAV)
				g.put(x, FLOOR + 3, z, Kit.TRIM)
			elif d < 12:
				g.box(x, 0, z, x + 1, FLOOR, z + 1, Kit.ARENA if Kit.chance(x / 2, z / 2, 1, seed, 80) else Kit.ARENA_D)
			elif d < 13:
				g.box(x, FLOOR, z, x + 1, FLOOR + 4, z + 1, Kit.TRAV)
			else:
				# the stands on the camera's side stay low, so the track shows
				var row := d - 13 if z < C else mini(d - 13, 2)
				g.box(x, FLOOR, z, x + 1, FLOOR + 4 + row * 2, z + 1, Kit.SEAT if row % 2 == 0 else Kit.SEAT_D)
				if d == 19 and z < C:
					g.box(x, FLOOR, z, x + 1, FLOOR + 20, z + 1, Kit.TRAV_C)
					g.put(x, FLOOR + 20, z, Kit.TRIM)
	# on the spina an obelisk or a column with a statue
	if seed % 2 == 0:
		g.box(C - 1, FLOOR + 3, C - 1, C + 1, FLOOR + 22, C + 1, Kit.GRANITE)
		g.put(C - 1, FLOOR + 22, C - 1, Kit.GILT)
	else:
		g.box(C - 1, FLOOR + 3, C - 1, C + 1, FLOOR + 14, C + 1, Kit.MARBLE)
		Town._figure(g, C - 2, FLOOR + 14, C - 1, Kit.STATUE)
	for k in 6:
		Town._person(g, lo + 4 + k * 7, FLOOR + 6 + (k % 3) * 2, C - 15 - k % 3, seed + k)
	return Town._done(g)

## The forum of a small town on one lot: paving, a portico along the back,
## a statue on a plinth, townspeople.
static func forum(seed: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 40)
	Town._paving(g, M, M, M + LOT, M + LOT, seed)
	Town._stoa(g, M, M, M + LOT, M + 10, "n", seed)
	if seed % 2 == 0:
		Town._statue(g, C - 2, FLOOR, C + 4, seed)
	else:
		Town._fountain(g, C - 4, FLOOR, C + 2, 8)
	for k in 5:
		Town._person(g, M + 3 + Kit.rnd(k, 3, 0, seed) % 34, FLOOR, M + 14 + Kit.rnd(k, 4, 0, seed) % 22, seed + k)
	return Town._done(g)

# --- houses along the streets ----------------------------------------------

## A street parcel holds its street and the houses along it (Ramon,
## 2026-10-30: drawn as pavement alone, half of Rome was grey). The
## carriageway runs in a band of 16 voxels round the parcel's middle
## (city_plan.gdshaderinc CP_HALF); in the eight cells round that band,
## out to the parcel's edge, stand houses facing the street. A piece is one
## cell: a row house on the north side facing south (`street_row`), a
## corner house in the north-west or north-east corner facing south
## (`street_corner_w`, `street_corner_e`), a walled court in the north-west
## corner (`street_court`); tile_terrain.gd _plan_street turns each into
## place. Variants come in three bands (ROW_BANDS, CORNER_BANDS): houses
## as tall as a big town's (two to four storeys), a small town's (two at
## most), and one-storey shops under a roof falling to the street for the
## street's near side as the camera sees it (the houses there would hide
## the street: a wall hides as much ground behind it as it is high).
const ROW_OUT := 4 # the parcel's edge, C - 43.5 / 2 (tile_terrain.gd LOT_SHARE)
const ROW_IN := C - 8 # where the street's band begins
const NEAR_DEPTH := 9 # the shops on the near side
const ROW_BANDS := [0, 3, 5, 8] # tall 0..2, small 3..4, shops 5..7
const CORNER_BANDS := [0, 2, 4, 6]
const ROW_VARIANTS := 8
const CORNER_VARIANTS := 6
const COURT_VARIANTS := 2

static func street_row(variant: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 72)
	_street_house(g, ROW_IN, C + 8, variant * 7 + 3, _band(ROW_BANDS, variant))
	return Town._done(g)

static func street_corner_w(variant: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 72)
	_street_house(g, ROW_OUT, ROW_IN, variant * 11 + 5, _band(CORNER_BANDS, variant))
	return Town._done(g)

static func street_corner_e(variant: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 72)
	_street_house(g, C + 8, 2 * C - ROW_OUT, variant * 13 + 9, _band(CORNER_BANDS, variant))
	return Town._done(g)

## A walled court in the corner between two rows: a yard with its tree,
## bed or pergola (roman_town.gd _yard).
static func street_court(variant: int) -> ArrayMesh:
	var g := Town._grid(1, 1, 64)
	Town._yard(g, ROW_OUT, ROW_OUT, ROW_IN, ROW_IN, variant * 5 + 2)
	return Town._done(g)

## The band of variant v: 0 tall, 1 small, 2 shops.
static func _band(bands: Array, v: int) -> int:
	return 2 if v >= bands[2] else 1 if v >= bands[1] else 0

## A house over [x0, x1) in the parcel's northern cells, its front on the
## street's band: a shop below where it is wide enough, no wing into the
## yard (the cell ends at the parcel's edge). Or the shops (band 2).
static func _street_house(g: Kit.Grid, x0: int, x1: int, seed: int, band: int) -> void:
	if band == 2:
		_shops(g, x0, x1, seed)
		return
	var o := Town._street_front(Town._options(seed, maxi(x1 - x0, 16)), false, band == 1)
	if band == 0:
		o["storeys"] = maxi(o["storeys"], 2)
	o["wing"] = false
	o["tower"] = false
	Town._house(g, x0, ROW_OUT, x1, ROW_IN, o)

## One-storey shops (tabernae) over [x0, x1), NEAR_DEPTH deep, under a tile
## roof falling to the street: eaves at three metres, so the camera sees
## the street over them.
static func _shops(g: Kit.Grid, x0: int, x1: int, seed: int) -> void:
	var z0 := ROW_OUT
	var z1 := ROW_OUT + NEAR_DEPTH
	var wall: int = Town.WALLS[seed % Town.WALLS.size()]
	var roof: Array = Town.ROOFS[seed % Town.ROOFS.size()]
	var eave := FLOOR + 12
	g.box(x0, FLOOR, z0, x1, eave, z1, wall)
	g.box(x0, FLOOR, z1 - 1, x1, FLOOR + 3, z1 + 1, Kit.STONE)
	var w := x1 - x0
	var o := {"goods": seed % 4, "awning": []} # a sign, no awning: it would hide the street
	if w >= 16:
		Town._shop(g, x0 + 1, FLOOR + 2, z1 - 1, w / 2 - 2, wall, o, seed)
		o["goods"] = (seed + 1) % 4
		Town._shop(g, x0 + w / 2 + 1, FLOOR + 2, z1 - 1, w / 2 - 2, wall, o, seed + 1)
	else:
		Town._shop(g, x0 + 2, FLOOR + 2, z1 - 1, w - 4, wall, o, seed)
	# the roof: from the eaves over the street up to the back wall
	for z in range(z0 - 1, z1 + 1):
		var hh := (z1 - z) / 3
		for x in range(x0 - 1, x1 + 1):
			g.put(x, eave + hh, z, Kit.EAVE if z == z1 else Town._field(x, z, hh + 1, roof, seed, "x"))
		if hh > 0 and z >= z0:
			g.box(x0, eave, z, x0 + 1, eave + hh, z + 1, wall)
			g.box(x1 - 1, eave, z, x1, eave + hh, z + 1, wall)
