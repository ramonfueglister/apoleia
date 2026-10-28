extends RefCounted
## A Roman farmhouse (casa rustica) as a voxel model in the Urbek style of
## the colosseum prototype: plastered walls on a stone plinth with stone
## corners, a beam under the eaves, a plank door and small dark windows, a
## hipped roof of terracotta tiles with darker rows and hip ridges, a
## lean-to shed with hay on one side and a woodpile on the other. Metres,
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
const BOUNDS_LO := Vector3(-5.75, 0.0, -4.0)
const BOUNDS_HI := Vector3(7.5, 5.75, 5.0)
const CACHE := "user://farmhouse_v1_%s.res"

# Palette (sRGB): plaster, stone, terracotta and wood after Caesar III with
# Urbek's brightness, like the colosseum. 0 is empty.
const PALETTE := [
	Color(0, 0, 0), Color("e6d8c0"), Color("d8c8aa"), Color("cfc3ab"), Color("b8483a"),
	Color("9a4434"), Color("7a3a2c"), Color("7a5236"), Color("3a2c24"), Color("dcb87e"),
	Color("4a3426"), Color("a5835f"), Color("4d7c3a"), Color("3f6b32")]
enum { EMPTY, PLASTER, PLASTER_LOW, STONE, ROOF, ROOF_DARK, RIDGE, WOOD, WINDOW, STRAW,
	WOOD_DARK, BEAM, LEAF, LEAF_DARK }

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
			return STONE if ax < HALF_X + 0.125 and az < HALF_Z + 0.125 else EMPTY
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
		# small windows high in the wall: two at the front and back, one on
		# each end
		var win_y := p.y >= 1.875 and p.y < 2.5
		if win_y and az >= HALF_Z - 0.25 and absf(ax - 2.75) < 0.375:
			return WINDOW
		if win_y and ax >= HALF_X - 0.25 and az < 0.375:
			return WINDOW
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
		return WOOD if posmod(int(floor((p.x + p.z) / 0.25)), 2) == 0 else WOOD_DARK
	if p.z >= 1.5:
		# open front, with posts at the corners
		return WOOD_DARK if p.x >= x1 - 0.25 else EMPTY
	# hay inside
	if p.y < 1.25 and p.x < 6.25 and p.z > -1.5:
		return STRAW
	return EMPTY

## Woodpile against the -x end and a shrub by the front corner.
static func _yard(p: Vector3) -> int:
	if p.x >= -5.75 and p.x < -HALF_X - 0.125 and p.z >= -2.0 and p.z < 0.75 and p.y < 1.0:
		return WOOD if posmod(int(floor(p.y / 0.25)) + int(floor(p.z / 0.25)), 2) == 0 else WOOD_DARK
	var s := Vector3(-3.5, 0.6, 4.25)
	var d := Vector2(p.x - s.x, p.z - s.z).length()
	if p.y < 1.25 and d < 0.75 - 0.3 * maxf(0.0, p.y - 0.6):
		return LEAF if p.y >= 0.75 else LEAF_DARK
	return EMPTY

## The levels of detail, nearest first, scaled to the unit house. Built
## once and kept in user://.
static func lods(unit_m: float) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for v: float in LOD_VOXELS:
		var path := CACHE % str(v)
		var mesh: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
		if mesh == null:
			mesh = VoxelMesh.build(sample, BOUNDS_LO, BOUNDS_HI, v, FINE, PALETTE, 1.0 / unit_m)
			ResourceSaver.save(mesh, path)
		out.append(mesh)
	return out
