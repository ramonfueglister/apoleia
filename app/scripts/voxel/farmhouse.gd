extends RefCounted
## A Roman farmhouse (casa rustica) as a voxel model in the Urbek style of
## the colosseum prototype: plastered walls on a stone plinth with stone
## corners, a beam under the eaves, a plank door and small dark windows, a
## hipped roof of terracotta tiles with darker rows and hip ridges, a
## lean-to shed with hay on one side and a woodpile on the other, a
## vegetable garden and a fruit tree at the back, an earth path to the gate and a wooden
## fence round the yard (it fits a 15 m yard when turned); outside the fence,
## on the rest of the 21 m lot, two cypresses at the front corners, an olive
## tree and a haystack. Metres,
## origin at ground centre of the main house, front towards +z. Built at
## three voxel sizes for the levels of detail (VoxelMesh), scaled to the
## unit house of the terrain (1 unit = TileTerrain.HOUSE_M).

const VoxelMesh = preload("res://scripts/voxel/voxel_mesh.gd")

const HALF_X := 4.5
const HALF_Z := 3.25
const WALL := 3.5
const EAVES := 0.5
const PITCH := 0.5 # roof rise per metre (about 27 degrees)
const LOD_VOXELS := [0.25, 0.5, 1.0]
const FINE := 0.125
const BOUNDS_LO := Vector3(-10.0, -0.125, -10.0) # the voxel layer -0.125..0.125 holds the path, flush with the ground
const BOUNDS_HI := Vector3(10.0, 6.75, 11.0)
const PATH_END := 11.0 # the path runs on through the gate to the village lane round the lot (people_dots_common.gdshaderinc DOT_LOT_KM)
const FENCE_LO := Vector2(-7.125, -6.375) # x, z of the fence line, on voxel middles
const FENCE_HI := Vector2(7.375, 6.375)
const CACHE := "user://farmhouse_v15_%s.res"

# Palette (sRGB): plaster, stone, terracotta and wood after Caesar III with
# Urbek's brightness, like the colosseum. 0 is empty.
# The palette of the town buildings (prototypes/colosseum/city_buildings.gd,
# after Caesar III): cream plaster, red terracotta with lighter treads on the
# roof steps (TOPS), green or brown shutters. people_houses.gdshader turns
# the plaster cream, pink or ochre and the shutters green or brown per farm.
const PALETTE := [
	Color(0, 0, 0), Color("f0dbb0"), Color("dcc59a"), Color("d6ccb4"), Color("b3563f"),
	Color("a84c38"), Color("8c372f"), Color("7a5232"), Color("3b2b20"), Color("d9bf6a"),
	Color("5e3f28"), Color("6e4a32"), Color("5f9a3e"), Color("44772f"), Color("c49a64"),
	Color("8a6a46"), Color("b59a6c"), Color("7d6a48"), Color("d2452f"), Color("b5a586"),
	Color("5f7f46"), Color("1f4228"), Color("2a5534"), Color("667f4c"), Color("52663d"),
	Color("75695a"), Color("dcc06c")]
enum { EMPTY, PLASTER, PLASTER_LOW, STONE, ROOF, ROOF_DARK, RIDGE, WOOD, WINDOW, STRAW,
	WOOD_DARK, BEAM, LEAF, LEAF_DARK, LOG, FENCE, EARTH, SOIL, FRUIT, PLINTH, SHUTTER,
	CYPRESS_DARK, CYPRESS, OLIVE, OLIVE_DARK, OLIVE_TRUNK, HAY }
# the lit treads darker than they show: sun and tone map lift them
const TOPS := {ROOF: Color("b8553c"), ROOF_DARK: Color("a54a36")}

## What fills point p (metres).
static func sample(p: Vector3) -> int:
	var c := _house(p)
	if c != EMPTY:
		return c
	c = _shed(p)
	if c != EMPTY:
		return c
	return _yard(p)

static func _house(p: Vector3) -> int:
	var ax := absf(p.x)
	var az := absf(p.z)
	if p.y < WALL:
		if p.y < 0.375:
			return PLINTH if ax < HALF_X + 0.125 and az < HALF_Z + 0.125 else EMPTY
		if ax >= HALF_X or az >= HALF_Z:
			return EMPTY
		var outer := ax >= HALF_X - 0.25 or az >= HALF_Z - 0.25
		if not outer:
			return PLASTER
		# stone corners, every other course standing out
		if ax >= HALF_X - 0.5 and az >= HALF_Z - 0.5:
			return STONE
		if p.y >= WALL - 0.25:
			return BEAM
		# plank door in the middle of the front, set back one block
		if p.z > 0.0 and az >= HALF_Z - 0.25 and absf(p.x) < 0.625 and p.y < 2.375:
			return EMPTY if az >= HALF_Z - 0.125 else (WOOD if int(floor(p.x / 0.25)) % 2 == 0 else WOOD_DARK)
		# small windows high in the wall, with wooden shutters either side:
		# two at the front and back, one on each end
		var win_y := p.y >= 1.625 and p.y < 2.5
		if win_y and az >= HALF_Z - 0.25:
			var k := absf(ax - 2.75)
			if k < 0.25:
				return WINDOW
			if k < 0.5:
				return SHUTTER
		if win_y and ax >= HALF_X - 0.25:
			if az < 0.25:
				return WINDOW
			if az < 0.5:
				return SHUTTER
		return PLASTER_LOW if p.y < 0.875 else PLASTER
	# hipped roof over the eaves
	var dx := HALF_X + EAVES - ax
	var dz := HALF_Z + EAVES - az
	if dx < 0.0 or dz < 0.0:
		return EMPTY
	var top := WALL + PITCH * minf(dx, dz)
	if p.y >= top:
		return EMPTY
	# hips and ridge darker, tile rows (imbrices) running down each slope
	if absf(dx - dz) < 0.2 or p.y >= WALL + PITCH * (HALF_Z + EAVES) - 0.25:
		return RIDGE
	var along := p.z if dx < dz else p.x
	return ROOF_DARK if posmod(int(floor(along / 0.25)), 3) == 0 else ROOF

## Lean-to shed on the +x end: plank walls, open front with hay, a roof
## sloping away from the house.
static func _shed(p: Vector3) -> int:
	var x0 := HALF_X
	var x1 := 7.0
	if p.x < x0 or p.x >= x1 + 0.25 or p.z < -2.5 or p.z >= 1.75:
		return EMPTY
	var roof := 2.75 - 0.3 * (p.x - x0)
	if p.y >= roof:
		return EMPTY
	if p.y >= roof - 0.25:
		return ROOF_DARK if posmod(int(floor(p.z / 0.25)), 3) == 0 else ROOF
	if p.x >= x1 or p.z < -2.25:
		return WOOD if posmod(int(floor((p.x + p.z) / 0.5)), 2) == 0 else WOOD_DARK
	if p.z >= 1.5:
		# open front, with posts at the corners
		return WOOD_DARK if p.x >= x1 - 0.25 else EMPTY
	# hay inside
	if p.y < 1.25 and p.x < 6.25 and p.z > -1.5:
		return STRAW
	return EMPTY

## Woodpile against the -x end, a shrub by the front corner, the garden
## beds at the back, the path to the gate and the fence.
static func _yard(p: Vector3) -> int:
	# a stack of logs, cut ends showing, bark on top
	if p.x >= -5.75 and p.x < -HALF_X - 0.125 and p.z >= -2.0 and p.z < 0.75 and p.y < 1.0:
		return WOOD if p.y >= 0.75 else LOG
	var s := Vector3(-3.5, 0.6, 4.25)
	var d := Vector2(p.x - s.x, p.z - s.z).length()
	if p.y < 1.25 and d < 0.75 - 0.3 * maxf(0.0, p.y - 0.6):
		return LEAF if p.y >= 0.75 else LEAF_DARK
	var tree := _tree(p)
	if tree != EMPTY:
		return tree
	tree = _lot(p)
	if tree != EMPTY:
		return tree
	# earth path from the door through the gate to the lane, flush with the ground
	if p.y < 0.125 and absf(p.x) < 0.625 and p.z >= HALF_Z and p.z < PATH_END:
		return EARTH
	if p.y < 0.0:
		return EMPTY # the rest of the sunk layer is the terrain's
	# vegetable beds behind the house: small bushy plants in rows on dark soil
	if p.z >= -5.75 and p.z < -4.0 and absf(p.x) < 3.5 and p.y < 0.625:
		if p.y < 0.125:
			return SOIL
		var plant := posmod(int(floor(p.x / 0.5)), 2) == 0 and posmod(int(floor((p.z + 5.75) / 0.5)), 2) == 0
		if not plant:
			return EMPTY
		return LEAF if p.y >= 0.375 else LEAF_DARK
	return _fence(p)

## A fruit tree in the back corner of the yard: a trunk and a round crown
## of blocks, darker underneath, with red fruit on its outside.
static func _tree(p: Vector3) -> int:
	var dx := absf(p.x - 5.75)
	var dz := absf(p.z + 5.0)
	if p.y < 2.25:
		return WOOD_DARK if dx < 0.25 and dz < 0.25 else EMPTY
	var r := 1.125 if p.y < 4.0 else 0.625
	if p.y >= 4.5 or dx >= r or dz >= r or dx + dz >= r * 1.6:
		return EMPTY
	var v := Vector3i((p / 0.25).floor())
	var shell := dx >= r - 0.25 or dz >= r - 0.25 or dx + dz >= r * 1.6 - 0.35 or p.y >= 4.25
	if shell and posmod(v.x * 7 + v.y * 3 + v.z * 5, 9) == 0:
		return FRUIT
	return LEAF_DARK if p.y < 2.75 else LEAF

## Posts every two metres and one rail round the lot, a gate gap at the path.
static func _fence(p: Vector3) -> int:
	if p.y >= 1.0:
		return EMPTY
	var on_x := (absf(p.z - FENCE_LO.y) < 0.125 or absf(p.z - FENCE_HI.y) < 0.125) and p.x >= FENCE_LO.x - 0.125 and p.x < FENCE_HI.x + 0.125
	var on_z := (absf(p.x - FENCE_LO.x) < 0.125 or absf(p.x - FENCE_HI.x) < 0.125) and p.z >= FENCE_LO.y - 0.125 and p.z < FENCE_HI.y + 0.125
	if not on_x and not on_z:
		return EMPTY
	if on_x and p.z > 0.0 and absf(p.x) < 1.0:
		return EMPTY # gate
	# a post on every eighth quarter metre, a rail one block high at hip
	# height, both on whole voxels of the finest level
	var along := p.x - BOUNDS_LO.x if on_x else p.z - BOUNDS_LO.z
	var post := posmod(int(floor(along / 0.25)), 8) == 4
	var rail := p.y >= 0.375 and p.y < 0.625
	return FENCE if post or rail else EMPTY

const OLIVE_CLUMPS: Array[Vector4] = [Vector4(-0.75, 0.25, 1.5, 2.75), Vector4(0.75, -0.25, 1.75, 3.25), Vector4(0.25, 0.75, 2.0, 3.5)]

## Outside the fence: a cypress in either front corner of the lot (clear of
## the house front), an olive tree in one back corner and a haystack in the
## other. Each in colours of its own, so people_houses.gdshader can leave
## them out by farm.
static func _lot(p: Vector3) -> int:
	if p.y < 0.0:
		return EMPTY
	# cypresses: a slim dark crown down to the ground (a sixth as wide as
	# tall), tapering to a point
	var cz := absf(p.z - 8.75)
	var cx := absf(absf(p.x) - 8.75)
	if cx < 0.5 and cz < 0.5:
		var r := 0.375 if p.y < 0.5 else 0.5 if p.y < 3.5 else 0.375 if p.y < 5.0 else 0.25 if p.y < 6.25 else 0.125 if p.y < 6.75 else 0.0
		if cx < r and cz < r and cx + cz < r * 1.5:
			return CYPRESS_DARK if p.y < 1.0 else CYPRESS
		return EMPTY
	# an olive tree: a crooked grey trunk and a wide crown of three uneven
	# clumps, silver-green, darker underneath
	var o := Vector2(p.x - 8.0, p.z + 8.0)
	if p.y < 1.75:
		if absf(o.x - 0.25 * floorf(p.y / 0.75)) < 0.25 and absf(o.y) < 0.25:
			return OLIVE_TRUNK
	for clump: Vector4 in OLIVE_CLUMPS: # x, z, bottom, top
		var d := Vector2(absf(o.x - clump.x), absf(o.y - clump.y))
		var r := 1.0 if p.y < clump.w - 0.5 else 0.625
		if p.y >= clump.z and p.y < clump.w and d.x < r and d.y < r and d.x + d.y < r * 1.5:
			return OLIVE_DARK if p.y < clump.z + 0.5 else OLIVE
	# a haystack: a round stack of straw, narrowing to a top
	var hd := Vector2(p.x + 8.0, p.z + 8.25).length()
	var hr := 1.375 - maxf(0.0, p.y - 1.0) * 0.6
	if p.y < 2.75 and hd < hr:
		return HAY
	return EMPTY

## The levels of detail, nearest first, scaled to the unit house. Built
## once and kept in user://.
static func lods(unit_m: float) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for v: float in LOD_VOXELS:
		var path := CACHE % str(v)
		var mesh: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
		if mesh == null:
			mesh = VoxelMesh.build(sample, BOUNDS_LO, BOUNDS_HI, v, FINE, PALETTE, 1.0 / unit_m, TOPS)
			ResourceSaver.save(mesh, path)
		out.append(mesh)
	return out
