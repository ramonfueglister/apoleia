extends RefCounted
## Caesar III's town buildings as Urbek-style voxel models, on the
## colosseum's 0.5 m grid and through its mesher (flat colours, baked corner
## occlusion, no downward faces). Every model is drawn in its own grid with
## the front facing +z (south); the city turns them in 90 degree steps.
## Proportions follow Urbek: a storey is 3 m (6 voxels), a small house is
## 7 x 9 m, a tree 5 to 7 m.

const Col := preload("res://colosseum_mesh.gd")
const V := 0.5

const PALETTE := [
	Color(0, 0, 0), Color("ebdfc8"), Color("ecc9b2"), Color("e6c690"), Color("f4f0e8"),
	Color("dcd5ca"), Color("b3563f"), Color("44527a"), Color("5a4232"), Color("c9bca4"),
	Color("d9ccb2"), Color("b8a58a"), Color("3f6fa0"), Color("b8483a"), Color("efe3cc"),
	Color("7ea24a"), Color("4d7c3a"), Color("5f9a3c"), Color("3f6b32"), Color("6b4a32"),
	Color("4a90c8"), Color("c9962e"), Color("b0802f"), Color("c8372a"), Color("f2ebdd"),
	Color("d9553a"), Color("e8c040"), Color("cfc3ab"), Color("b5a68c"), Color("f7f3ea"),
	Color("3d5c8c"), Color("b8613f"), Color("5f7f46"), Color("9a5a3a"), Color("a89c88"),
	Color("dfd4c0")]
enum { EMPTY, PLASTER, PLASTER_PINK, PLASTER_OCHRE, MARBLE, MARBLE_SHADE, ROOF, WINDOW, DOOR,
	STONE, PAVE, PAVE_DARK, MOSAIC_BLUE, MOSAIC_RED, MOSAIC_CREAM, GRASS, HEDGE, LEAF, LEAF_DARK,
	TRUNK, WATER, GOLD, BRONZE, AWNING_RED, AWNING_WHITE, FLOWER_RED, FLOWER_YELLOW, ROAD,
	ROAD_EDGE, COLUMN, ROOF_BLUE, ROOF_OLD, SHUTTER_GREEN, SHUTTER_BROWN, COBBLE, SIDEWALK }
# Top faces that differ from the sides: tile roofs show a dark riser and a
# lit tread on every step, Urbek's striped roofs.
const TOP := {ROOF: Color("cf6a4c"), ROOF_OLD: Color("c9784e"), ROOF_BLUE: Color("5079b0"),
	WATER: Color("5aa2d6"), GOLD: Color("e6bc58")}

## A voxel grid with box drawing; meshes through the colosseum's mesher.
class Grid:
	var n: Vector3i
	var g := PackedByteArray()

	func _init(size: Vector3i) -> void:
		n = size
		g.resize(n.x * n.y * n.z)

	func put(x: int, y: int, z: int, c: int) -> void:
		if x >= 0 and y >= 0 and z >= 0 and x < n.x and y < n.y and z < n.z:
			g[x + n.x * (y + n.y * z)] = c

	## Fills [x0, x1) x [y0, y1) x [z0, z1).
	func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, c: int) -> void:
		for z in range(maxi(z0, 0), mini(z1, n.z)):
			for y in range(maxi(y0, 0), mini(y1, n.y)):
				for x in range(maxi(x0, 0), mini(x1, n.x)):
					g[x + n.x * (y + n.y * z)] = c

	## Centred on x and z, standing on y = `floor_y` metres.
	func mesh(palette: Array, top: Dictionary, floor_y := 0.0) -> ArrayMesh:
		return Col._mesh({"grid": g, "n": n, "v": 0.5, "lo": Vector3(-n.x * 0.25, floor_y, -n.z * 0.25),
			"palette": palette, "top": top})

static func _done(g: Grid, floor_y := 0.0) -> ArrayMesh:
	return g.mesh(PALETTE, TOP, floor_y)

## Stepped tile roof over [x0, x1) x [z0, z1) from row y: each layer half a
## metre up and one metre in (about 27 degrees), the eaves one voxel out.
## `gable` steps only in x and closes both ends with marble pediments.
static func _roof(g: Grid, x0: int, z0: int, x1: int, z1: int, y: int, tile := ROOF, gable := false) -> int:
	var a := x0 - 1
	var b := x1 + 1
	var c := z0 if gable else z0 - 1
	var d := z1 if gable else z1 + 1
	var layer := 0
	while a < b and c < d:
		g.box(a, y + layer, c, b, y + layer + 1, d, tile)
		if gable:
			g.box(a, y + layer, c, b, y + layer + 1, c + 1, MARBLE)
			g.box(a, y + layer, d - 1, b, y + layer + 1, d, MARBLE)
		a += 2
		b -= 2
		if not gable:
			c += 2
			d -= 2
		layer += 1
	return y + layer

## A recessed opening in a wall facing +z or -z at z_face: the face voxels
## go, the voxels one step in take `inner`.
static func _hole_z(g: Grid, x0: int, x1: int, y0: int, y1: int, z_face: int, inward: int, inner: int) -> void:
	g.box(x0, y0, z_face, x1, y1, z_face + 1, EMPTY)
	g.box(x0, y0, z_face + inward, x1, y1, z_face + inward + 1, inner)

static func _hole_x(g: Grid, z0: int, z1: int, y0: int, y1: int, x_face: int, inward: int, inner: int) -> void:
	g.box(x_face, y0, z0, x_face + 1, y1, z1, EMPTY)
	g.box(x_face + inward, y0, z0, x_face + inward + 1, y1, z1, inner)

## A row of 2-voxel windows with a light sill on all four walls of the box
## [x0, x1) x [z0, z1), every 4 voxels, leaving out `skip` (x range) on the
## front for a door.
static func _windows(g: Grid, x0: int, z0: int, x1: int, z1: int, y: int, h: int, skip := Vector2i(-1, -1)) -> void:
	for x in range(x0 + 2, x1 - 3, 4):
		if not (x + 2 > skip.x and x < skip.y):
			_hole_z(g, x, x + 2, y, y + h, z1 - 1, -1, WINDOW)
			g.box(x, y - 1, z1 - 1, x + 2, y, z1, MARBLE)
		_hole_z(g, x, x + 2, y, y + h, z0, 1, WINDOW)
		g.box(x, y - 1, z0, x + 2, y, z0 + 1, MARBLE)
	for z in range(z0 + 2, z1 - 3, 4):
		_hole_x(g, z, z + 2, y, y + h, x1 - 1, -1, WINDOW)
		g.box(x1 - 1, y - 1, z, x1, y, z + 2, MARBLE)
		_hole_x(g, z, z + 2, y, y + h, x0, 1, WINDOW)
		g.box(x0, y - 1, z, x0 + 1, y, z + 2, MARBLE)

const WALLS := [PLASTER, PLASTER_PINK, PLASTER_OCHRE, PLASTER]
const ROOFS := [ROOF, ROOF_OLD, ROOF, ROOF_OLD]
const SHUTTERS := [SHUTTER_GREEN, SHUTTER_BROWN]

## A white cornice line round the top of the walls, under the eaves.
static func _cornice(g: Grid, x0: int, z0: int, x1: int, z1: int, y: int) -> void:
	g.box(x0, y - 1, z0, x1, y, z1, MARBLE)

## Windows with coloured shutters on the front and back walls, every 6
## voxels; balconies with flowers in front of every other one when asked.
static func _shuttered(g: Grid, x0: int, z0: int, x1: int, z1: int, y: int, h: int, shutter: int, balcony := false) -> void:
	var k := 0
	for x in range(x0 + 2, x1 - 3, 6):
		for face in [[z1 - 1, -1, z1], [z0, 1, z0 - 1]]:
			_hole_z(g, x + 1, x + 3, y, y + h, face[0], face[1], WINDOW)
			g.box(x, y, face[0], x + 1, y + h, face[0] + 1, shutter)
			g.box(x + 3, y, face[0], x + 4, y + h, face[0] + 1, shutter)
			if balcony and k % 2 == 0:
				g.box(x, y - 1, face[2], x + 4, y, face[2] + 1, DOOR)
				g.box(x, y, face[2], x + 1, y + 1, face[2] + 1, FLOWER_RED)
				g.box(x + 3, y, face[2], x + 4, y + 1, face[2] + 1, LEAF)
		k += 1

## Domus: one or two storeys of plaster on a stone plinth, a door, windows
## with sills, a hipped tile roof. Variants 0-1 one storey, 2-3 two.
static func house(variant: int) -> ArrayMesh:
	var w := 14 if variant % 2 == 0 else 16
	var d := 18
	var storeys := 1 if variant < 2 else 2
	var h := 1 + 6 * storeys
	var g := Grid.new(Vector3i(w + 4, h + w / 4 + 3, d + 4))
	var x0 := 2
	var z0 := 2
	var x1 := x0 + w
	var z1 := z0 + d
	var cx := (x0 + x1) / 2
	g.box(x0, 0, z0, x1, 1, z1, STONE)
	g.box(x0, 1, z0, x1, h, z1, WALLS[variant % 4])
	for st in storeys:
		var skip := Vector2i(cx - 2, cx + 2) if st == 0 else Vector2i(-1, -1)
		_windows(g, x0, z0, x1, z1, 1 + st * 6 + 2, 2 if storeys == 1 else 3, skip)
	_hole_z(g, cx - 1, cx + 1, 1, 5, z1 - 1, -1, DOOR)
	_cornice(g, x0, z0, x1, z1, h)
	_roof(g, x0, z0, x1, z1, h, ROOFS[variant])
	return _done(g)

## Insula: three or four storeys, shops with striped awnings on the ground
## floor, a light band at every floor, windows above.
static func insula(variant: int) -> ArrayMesh:
	var w := 24
	var d := 30
	var storeys := 3 + variant % 2
	var h := 1 + 6 * storeys
	var g := Grid.new(Vector3i(w + 4, h + 10, d + 6))
	var x0 := 2
	var z0 := 2
	var x1 := x0 + w
	var z1 := z0 + d
	g.box(x0, 0, z0, x1, 1, z1, STONE)
	g.box(x0, 1, z0, x1, h, z1, WALLS[(variant + 2) % 4])
	for st in range(1, storeys):
		g.box(x0, st * 6 + 1, z0, x1, st * 6 + 2, z1, MARBLE_SHADE)
		_shuttered(g, x0, z0, x1, z1, st * 6 + 3, 3, SHUTTERS[(variant + st) % 2], st == 1)
		for z in range(z0 + 3, z1 - 3, 5):
			_hole_x(g, z, z + 2, st * 6 + 3, st * 6 + 6, x1 - 1, -1, WINDOW)
			_hole_x(g, z, z + 2, st * 6 + 3, st * 6 + 6, x0, 1, WINDOW)
	for k in w / 6:
		var x := x0 + 1 + k * 6
		_hole_z(g, x, x + 4, 1, 5, z1 - 1, -1, DOOR)
		for i in 4:
			g.box(x + i, 5, z1, x + i + 1, 6, z1 + 2, AWNING_RED if (i + variant) % 2 == 0 else AWNING_WHITE)
	_hole_z(g, x0 + w / 2 - 1, x0 + w / 2 + 1, 1, 5, z0, 1, DOOR)
	_cornice(g, x0, z0, x1, z1, h)
	_roof(g, x0, z0, x1, z1, h, ROOFS[variant])
	return _done(g)

## Villa with a peristyle: four wings round a courtyard garden with a pool,
## columns carrying the inner eaves, an entrance passage on the front.
static func villa() -> ArrayMesh:
	var s := 40
	var wing := 10
	var h := 8
	var g := Grid.new(Vector3i(s + 4, h + 10, s + 4))
	var x0 := 2
	var z0 := 2
	var x1 := x0 + s
	var z1 := z0 + s
	var ix0 := x0 + wing
	var ix1 := x1 - wing
	var iz0 := z0 + wing
	var iz1 := z1 - wing
	var cx := (x0 + x1) / 2
	var cz := (z0 + z1) / 2
	g.box(x0, 0, z0, x1, 1, z1, STONE)
	g.box(x0, 1, z0, x1, h, z1, PLASTER_PINK)
	_windows(g, x0, z0, x1, z1, 3, 3, Vector2i(cx - 3, cx + 3))
	g.box(ix0, 1, iz0, ix1, h, iz1, EMPTY)
	g.box(ix0, 0, iz0, ix1, 1, iz1, PAVE)
	g.box(ix0 + 3, 0, iz0 + 3, ix1 - 3, 1, iz1 - 3, GRASS)
	for x in range(ix0 + 1, ix1 - 1, 3):
		g.box(x, 1, iz0 + 2, x + 1, h, iz0 + 3, COLUMN)
		g.box(x, 1, iz1 - 3, x + 1, h, iz1 - 2, COLUMN)
	for z in range(iz0 + 1, iz1 - 1, 3):
		g.box(ix0 + 2, 1, z, ix0 + 3, h, z + 1, COLUMN)
		g.box(ix1 - 3, 1, z, ix1 - 2, h, z + 1, COLUMN)
	# Pool with a stone rim, hedges and flower beds round it.
	g.box(cx - 5, 1, cz - 4, cx + 5, 2, cz + 4, MARBLE)
	g.box(cx - 4, 1, cz - 3, cx + 4, 2, cz + 3, EMPTY)
	g.box(cx - 4, 0, cz - 3, cx + 4, 1, cz + 3, WATER)
	for corner in [Vector2i(ix0 + 4, iz0 + 4), Vector2i(ix1 - 7, iz0 + 4), Vector2i(ix0 + 4, iz1 - 7), Vector2i(ix1 - 7, iz1 - 7)]:
		g.box(corner.x, 1, corner.y, corner.x + 3, 2, corner.y + 3, HEDGE)
		g.box(corner.x + 1, 1, corner.y + 1, corner.x + 2, 2, corner.y + 2, FLOWER_RED)
	# Entrance through the front wing.
	g.box(cx - 2, 1, iz1, cx + 2, 6, z1, EMPTY)
	g.box(cx - 2, 0, iz1, cx + 2, 1, z1, PAVE)
	_cornice(g, x0, z0, x1, z1, h)
	# Four hipped roofs reaching over the colonnade.
	_roof(g, x0, z0, x1, iz0 + 2, h)
	_roof(g, x0, iz1 - 2, x1, z1, h)
	_roof(g, x0, iz0, ix0 + 2, iz1, h)
	_roof(g, ix1 - 2, iz0, x1, iz1, h)
	return _done(g)

## Temple on a podium with front steps: six columns in two rows at the
## front, columns down the sides, marble cella and entablature, a gabled
## roof with pediments. Variant 1 has the blue roof of Neptune's temples.
static func temple(variant: int) -> ArrayMesh:
	var w := 28
	var d := 46
	var g := Grid.new(Vector3i(w + 4, 34, d + 4))
	var x0 := 2
	var z0 := 2
	var x1 := x0 + w
	var z1 := z0 + d
	var front := z1 - 8
	var cx := (x0 + x1) / 2
	g.box(x0, 0, z0, x1, 4, front, MARBLE_SHADE)
	g.box(x0, 3, z0, x1, 4, front, MARBLE)
	for k in 4:
		g.box(x0 + 3, 0, front + 2 * k, x1 - 3, 4 - k, front + 2 * k + 2, MARBLE)
	g.box(x0 + 5, 4, z0 + 4, x1 - 5, 20, front - 10, MARBLE)
	_hole_z(g, cx - 2, cx + 2, 4, 14, front - 11, -1, DOOR)
	for i in 6:
		var x := x0 + 1 + roundi(i * (w - 4) / 5.0)
		g.box(x, 4, front - 3, x + 2, 20, front - 1, COLUMN)
		g.box(x, 4, front - 8, x + 2, 20, front - 6, COLUMN)
		g.box(x, 4, z0 + 1, x + 2, 20, z0 + 3, COLUMN)
	for z in range(z0 + 6, front - 8, 5):
		g.box(x0 + 1, 4, z, x0 + 3, 20, z + 2, COLUMN)
		g.box(x1 - 3, 4, z, x1 - 1, 20, z + 2, COLUMN)
	g.box(x0, 20, z0, x1, 22, front, MARBLE)
	g.box(x0, 20, z0, x1, 21, front, MARBLE_SHADE)
	_roof(g, x0, z0, x1, front, 22, ROOF_BLUE if variant == 1 else ROOF, true)
	# Gilded acroteria on the ridge ends.
	g.box(cx - 1, 29, z0, cx + 1, 31, z0 + 1, GOLD)
	g.box(cx - 1, 29, front - 1, cx + 1, 31, front, GOLD)
	return _done(g)

## Round building: plinth, a ring of columns round a marble drum with
## arched openings, cornice; a stepped tile cone with a lantern (market),
## or a golden dome (shrine).
static func rotunda(gold: bool) -> ArrayMesh:
	var n := 36
	var r := 16.0
	var g := Grid.new(Vector3i(n, 34, n))
	var c := n / 2.0
	for z in n:
		for x in n:
			var p := Vector2(x + 0.5 - c, z + 0.5 - c)
			var dist := p.length()
			var a := fposmod(atan2(p.y, p.x) / TAU * 24.0, 1.0)
			if dist <= r:
				g.box(x, 0, z, x + 1, 1, z + 1, STONE)
			if dist <= r - 1.0:
				g.box(x, 1, z, x + 1, 2, z + 1, MARBLE_SHADE)
			if dist <= r - 1.0 and dist > r - 2.2 and a < 0.3:
				g.box(x, 2, z, x + 1, 13, z + 1, COLUMN)
			if dist <= r - 3.0:
				g.box(x, 2, z, x + 1, 13, z + 1, MARBLE)
				# Openings in every other bay of the drum, dark inside.
				if dist > r - 4.0 and fposmod(a * 0.5 + 0.25, 1.0) < 0.22:
					g.box(x, 2, z, x + 1, 9, z + 1, EMPTY)
				elif dist > r - 5.0 and dist <= r - 4.0 and fposmod(a * 0.5 + 0.25, 1.0) < 0.3:
					g.box(x, 2, z, x + 1, 9, z + 1, DOOR)
			if dist <= r - 0.6:
				g.box(x, 13, z, x + 1, 14, z + 1, MARBLE)
	var top := 14
	if gold:
		var rd := r - 3.0
		for y in int(rd):
			var ry := sqrt(maxf(0.0, rd * rd - y * y))
			for z in n:
				for x in n:
					if Vector2(x + 0.5 - c, z + 0.5 - c).length() <= ry:
						g.put(x, top + y, z, GOLD)
		top += int(rd)
	else:
		var rr := r - 0.6
		while rr > 2.0:
			for z in n:
				for x in n:
					if Vector2(x + 0.5 - c, z + 0.5 - c).length() <= rr:
						g.put(x, top, z, ROOF)
			rr -= 1.6
			top += 1
	g.box(int(c) - 1, top, int(c) - 1, int(c) + 1, top + 2, int(c) + 1, MARBLE)
	g.box(int(c) - 1, top + 2, int(c) - 1, int(c) + 1, top + 3, int(c) + 1, GOLD)
	return _done(g)

## Round fountain: stone basin with a marble rim, a column with a bowl and
## a jet of water.
static func fountain() -> ArrayMesh:
	var n := 12
	var g := Grid.new(Vector3i(n, 8, n))
	for z in n:
		for x in n:
			var dist := Vector2(x + 0.5 - 6.0, z + 0.5 - 6.0).length()
			if dist <= 5.6:
				g.put(x, 0, z, STONE)
				if dist > 4.4:
					g.box(x, 1, z, x + 1, 3, z + 1, MARBLE)
				else:
					g.put(x, 1, z, WATER)
			if dist <= 2.0:
				g.put(x, 5, z, MARBLE)
			if dist <= 1.2:
				g.put(x, 6, z, WATER)
	g.box(5, 2, 5, 7, 5, 7, MARBLE)
	g.box(5, 6, 5, 7, 8, 7, WATER)
	return _done(g)

## A statue on a pedestal: bronze (variant 0) or marble, one arm raised.
static func statue(variant: int) -> ArrayMesh:
	var g := Grid.new(Vector3i(6, 12, 6))
	var m := BRONZE if variant == 0 else MARBLE
	g.box(1, 0, 1, 5, 4, 5, MARBLE_SHADE)
	g.box(1, 4, 1, 5, 5, 5, MARBLE)
	g.box(2, 5, 2, 4, 9, 4, m)
	g.box(2, 9, 2, 3, 10, 3, m)
	g.box(4, 7, 2, 5, 11, 3, m)
	return _done(g)

## Garden plot, 8 m: hedged flower beds round a path cross and a pedestal.
static func garden() -> ArrayMesh:
	var g := Grid.new(Vector3i(16, 4, 16))
	g.box(0, 0, 0, 16, 1, 16, GRASS)
	g.box(7, 0, 0, 9, 1, 16, PAVE)
	g.box(0, 0, 7, 16, 1, 9, PAVE)
	var beds := [[1, 1, FLOWER_RED], [10, 1, FLOWER_YELLOW], [1, 10, FLOWER_YELLOW], [10, 10, FLOWER_RED]]
	for b in beds:
		g.box(b[0], 1, b[1], b[0] + 5, 2, b[1] + 5, HEDGE)
		g.box(b[0] + 1, 1, b[1] + 1, b[0] + 4, 2, b[1] + 4, b[2])
	g.box(7, 1, 7, 9, 3, 9, MARBLE)
	return _done(g, -0.4)

## Cypress, about 7 m: a narrow column of dark foliage.
static func cypress() -> ArrayMesh:
	var g := Grid.new(Vector3i(3, 16, 3))
	g.box(1, 0, 1, 2, 2, 2, TRUNK)
	g.box(0, 2, 0, 3, 13, 3, LEAF_DARK)
	g.box(1, 13, 1, 2, 15, 2, LEAF_DARK)
	for y in [2, 11, 12]:
		for corner in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
			g.put(corner.x, y, corner.y, EMPTY)
	return _done(g)

## Broadleaf tree, about 5.5 m: a blocky crown in two greens.
static func tree(variant: int) -> ArrayMesh:
	var g := Grid.new(Vector3i(9, 12, 9))
	var a := LEAF if variant == 0 else LEAF_DARK
	var b := LEAF_DARK if variant == 0 else LEAF
	g.box(4, 0, 4, 5, 5, 5, TRUNK)
	g.box(1, 5, 1, 8, 9, 8, a)
	g.box(2, 9, 2, 7, 11, 7, a)
	g.box(0, 6, 2, 2, 8, 5, b)
	g.box(5, 7, 6, 8, 10, 9, b)
	for corner in [Vector2i(1, 1), Vector2i(7, 1), Vector2i(1, 7), Vector2i(7, 7)]:
		g.box(corner.x, 5, corner.y, corner.x + 1, 6, corner.y + 1, EMPTY)
		g.box(corner.x, 8, corner.y, corner.x + 1, 9, corner.y + 1, EMPTY)
	return _done(g)

## Plaza tile, 8 m: Caesar III's mosaic paving, a red diamond in a blue one
## on cream, with a stone border.
static func mosaic() -> ArrayMesh:
	var g := Grid.new(Vector3i(16, 1, 16))
	for z in 16:
		for x in 16:
			var m := absf(x - 7.5) + absf(z - 7.5)
			var c := MOSAIC_CREAM
			if x == 0 or z == 0 or x == 15 or z == 15:
				c = PAVE_DARK
			elif m < 3.5:
				c = MOSAIC_RED
			elif m >= 5.5 and m < 7.5:
				c = MOSAIC_BLUE
			g.put(x, 0, z, c)
	return _done(g, -0.4)

## Street tile, 8 m: grey cobbles between kerbs and light sidewalks; turned
## for streets running the other way.
static func street() -> ArrayMesh:
	var g := Grid.new(Vector3i(16, 1, 16))
	g.box(0, 0, 0, 16, 1, 16, COBBLE)
	g.box(0, 0, 0, 3, 1, 16, SIDEWALK)
	g.box(13, 0, 0, 16, 1, 16, SIDEWALK)
	g.box(3, 0, 0, 4, 1, 16, ROAD_EDGE)
	g.box(12, 0, 0, 13, 1, 16, ROAD_EDGE)
	return _done(g, -0.4)

## Crossing tile, 8 m: cobbles with sidewalk corners.
static func crossing() -> ArrayMesh:
	var g := Grid.new(Vector3i(16, 1, 16))
	g.box(0, 0, 0, 16, 1, 16, COBBLE)
	for c in [Vector2i(0, 0), Vector2i(13, 0), Vector2i(0, 13), Vector2i(13, 13)]:
		g.box(c.x, 0, c.y, c.x + 3, 1, c.y + 3, SIDEWALK)
	return _done(g, -0.4)
