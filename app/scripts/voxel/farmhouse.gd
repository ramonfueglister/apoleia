extends RefCounted
## A Roman farmhouse (casa rustica) as a voxel model in the Urbek style of
## the colosseum prototype: plastered walls on a stone plinth with stone
## corners, a beam under the eaves, a plank door and small dark windows
## with shutters, under terracotta tiles with darker rows and ridges. Four
## builds (VARIANTS), so a village is not one house repeated: a hipped-roof
## house with a lean-to shed with hay on one end; a long house under a
## gable roof with a portico of plastered columns along its front; the
## hipped-roof house with a plank barn as a wing in front, its open door
## showing the hay inside; and a two-storey house with an outside stone
## stair to its upper floor and a vine pergola over the yard. Around each a woodpile, a vegetable garden and a
## fruit tree at the back, an earth path to the gate and a wooden
## fence round the yard (it fits a 15 m yard when turned); outside the fence,
## on the rest of the 21 m lot, two cypresses at the front corners, an olive
## tree and a haystack. Metres,
## origin at ground centre of the main house, front towards +z. Built at
## three voxel sizes for the levels of detail (VoxelMesh), scaled to the
## unit house of the terrain (1 unit = TileTerrain.HOUSE_M).

const VoxelMesh = preload("res://scripts/voxel/voxel_mesh.gd")

const VARIANTS := 4 # people_houses.gdshader picks one per lot
const HALF_X := 4.5
const HALF_Z := 3.25
const LONG_X := 5.75 # the long house
const LONG_Z := 2.75
const PORCH_Z := 4.75 # front edge of its portico
const PORCH_X := 4.375
const COLUMNS: Array[float] = [-4.0, -1.25, 1.25, 4.0]
const BARN_X := -4.5 # middle of the barn wing, its walls 2 m either side
const BARN_Z := Vector2(1.5, 6.0) # back and front of the barn
const BARN_WALL := 2.75
const TALL_X := 3.75 # the two-storey house
const TALL_Z := 3.0
const TALL_WALL := 6.5
const UPPER := 3.5 # its upper floor
const STAIR_X := Vector2(1.0, 5.5) # its outside stair along the front: the landing's inner end, the foot
const TALL_WINS: Array[float] = [-2.25, 2.25] # windows on the back
const TALL_FRONT_DOWN: Array[float] = [-2.25] # on the front beside the door, below and above
const TALL_FRONT_UP: Array[float] = [-0.5, -2.5]
const WINS_HOUSE: Array[float] = [1.625, 3.25] # windows from the middle of the front: four and the door
const WINS_LONG: Array[float] = [2.5, 4.5]
const ENDS_HOUSE: Array[float] = [1.5] # windows from the middle of each end
const ENDS_LONG: Array[float] = [1.25]
const WALL := 4.75 # tall enough that the roof does not swallow the house from above (round 17: 4 m read as 60 % roof)
const EAVES := 0.5
const PITCH := 0.42 # roof rise per metre (about 23 degrees)
const LOD_VOXELS := [0.125, 0.25, 0.5, 1.0]
const FINE := 0.125
const BOUNDS_LO := Vector3(-10.0, -0.125, -10.0) # the voxel layer -0.125..0.125 holds the path, flush with the ground
const BOUNDS_HI := Vector3(10.0, 8.25, 11.0)
const PATH_END := 11.0 # the path runs on through the gate to the village lane round the lot (people_dots_common.gdshaderinc DOT_LOT_KM)
const FENCE_LO := Vector2(-7.125, -6.375) # x, z of the fence line, on voxel middles
const FENCE_HI := Vector2(7.375, 6.375)
const CACHE := "user://farmhouse_v35_%d_%s.res"
static var _variant := 0 # the build sample() draws

# Palette (sRGB): plaster, stone, terracotta and wood after Caesar III with
# Urbek's brightness, like the colosseum. 0 is empty.
# The palette of the town buildings (prototypes/colosseum/city_buildings.gd,
# after Caesar III): cream plaster, red terracotta with lighter treads on the
# roof steps (TOPS), green or brown shutters. people_houses.gdshader turns
# the plaster cream, pink or ochre and the shutters green or brown per farm.
const PALETTE := [
	Color(0, 0, 0), Color("f0dbb0"), Color("dcc59a"), Color("d6ccb4"), Color("ad5a44"),
	Color("9c4a38"), Color("c4664c"), Color("7a5232"), Color("3b2b20"), Color("d9bf6a"),
	Color("5e3f28"), Color("6e4a32"), Color("5f9a3e"), Color("44772f"), Color("c49a64"),
	Color("5e4128"), Color("b59a6c"), Color("6e4a30"), Color("d2452f"), Color("b5a586"),
	Color("5f7f46"), Color("24482c"), Color("31603a"), Color("4d683f"), Color("34482b"),
	Color("5a4632"), Color("c09447"), Color("cebc97"), Color("8f6a2e"),
	Color("ad5a44"), Color("9c4a38"), Color("ad5a44"), Color("9c4a38"),
	Color("ad5a44"), Color("9c4a38"), Color("ad5a44"), Color("9c4a38"),
	Color("4a8c3a"), Color("33505e"), Color("3e792e"), Color("2f5f24"),
	# the workshops (_workshop), each craft in colours of its own
	Color("8c8478"), Color("ff8a2a"), Color("3d3d42"), Color("6e4a32"), Color("ad5a44"), Color("5a5a60"),
	Color("a0563a"), Color("2e211a"), Color("c4704a"), Color("b8653f"),
	Color("7a5232"), Color("e8dcc0"), Color("b5452f"), Color("d1a54a"), Color("4f6f9c"), Color("ebe3cf"),
	Color("9a7a4e")]
enum { EMPTY, PLASTER, PLASTER_LOW, STONE, ROOF, ROOF_DARK, RIDGE, WOOD, WINDOW, STRAW,
	WOOD_DARK, BEAM, LEAF, LEAF_DARK, LOG, FENCE, EARTH, SOIL, FRUIT, PLINTH, SHUTTER,
	CYPRESS_DARK, CYPRESS, OLIVE, OLIVE_DARK, OLIVE_TRUNK, HAY, PLASTER_SHADE, HAY_DARK,
	ROOF_E, ROOF_DARK_E, ROOF_W, ROOF_DARK_W, ROOF_S, ROOF_DARK_S, ROOF_N, ROOF_DARK_N,
	LOT_GRASS, WATER, CABBAGE, CABBAGE_DARK,
	SMITH_STONE, SMITH_FIRE, SMITH_IRON, SMITH_WOOD, SMITH_ROOF, SMITH_TOOLS,
	POT_KILN, POT_DARK, POT_JAR, POT_JAR_MORE,
	WEAVE_WOOD, WEAVE_WARP, WEAVE_CLOTH, WEAVE_CLOTH_2, WEAVE_CLOTH_3, WEAVE_WOOL, SCAFFOLD }
# The workshop of a craft household (Ramon 29.10.2026: "alles sichtbar
# grafisch"): every build carries all three outside the fence, each on a
# spot of its own (a voxel holds one colour, so they cannot share one), and
# people_houses.gdshader shows the one of the household's craft (smith,
# potter, weaver; the house record's rec.w) and more of its goods the
# busier it is (SMITH_TOOLS, POT_JAR_MORE, WEAVE_CLOTH_2 and _3,
# WEAVE_WOOL). Each is drawn on the spot WORKSHOP_LO..HI (x, z) and moved
# by its offset: the smithy front right, the pottery front left, the
# weaving in the middle behind the house.
const WORKSHOP_LO := Vector2(2.5, 7.25)
const WORKSHOP_HI := Vector2(6.5, 10.25)
const WORKSHOP_AT: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(-9.0, 0.0), Vector2(-4.5, -17.25)]
# roof tiles by the way their slope faces (+x, -x, +z, -z; _tile), so
# people_houses.gdshader can light each slope by where it faces once the
# house is turned
# the lit treads darker than they show: sun and tone map lift them
const TOPS := {ROOF: Color("b45a42"), ROOF_DARK: Color("a34c3a"),
	ROOF_E: Color("b45a42"), ROOF_DARK_E: Color("a34c3a"), ROOF_W: Color("b45a42"), ROOF_DARK_W: Color("a34c3a"),
	ROOF_S: Color("b45a42"), ROOF_DARK_S: Color("a34c3a"), ROOF_N: Color("b45a42"), ROOF_DARK_N: Color("a34c3a")}

## What fills point p (metres) in the build _variant.
static func sample(p: Vector3) -> int:
	var c := EMPTY
	if _variant == 1:
		c = _long_house(p)
		if c == EMPTY:
			c = _portico(p)
	elif _variant == 3:
		c = _tall_house(p)
		if c == EMPTY:
			c = _stair(p)
		if c == EMPTY:
			c = _pergola(p)
	else:
		c = _house(p)
		if c == EMPTY:
			c = _barn(p) if _variant == 2 else _shed(p)
	return c if c != EMPTY else _yard(p)

## A roof tile on a slope facing `dir` (0 +x, 1 -x, 2 +z, 3 -z), in one of
## the darker rows or not.
static func _tile(dir: int, dark: bool) -> int:
	return ROOF_E + dir * 2 + (1 if dark else 0)

## p moved to the middle of its cube of edge e: the trees and the haystack
## keep the chunky blocks of Urbek's props at any voxel size.
static func _snap(p: Vector3, e: float) -> Vector3:
	return ((p / e).floor() + Vector3(0.5, 0.5, 0.5)) * e

## The walls of a house of half extents hx, hz up to WALL: plaster on a
## stone plinth, stone corners, a beam under the eaves, the plank door in
## the middle of the front and windows with wooden shutters either side
## and a stone sill, at the distances `wins` from the middle of the front
## and back and `ends` from the middle of each end, so no wall is blank
## (round 17: small windows left the facades blank planes).
static func _walls(p: Vector3, hx: float, hz: float, wins: Array[float], ends: Array[float]) -> int:
	var ax := absf(p.x)
	var az := absf(p.z)
	if p.y < 0.375:
		return PLINTH if ax < hx + 0.125 and az < hz + 0.125 else EMPTY
	if ax >= hx or az >= hz:
		return EMPTY
	var outer := ax >= hx - 0.25 or az >= hz - 0.25
	if not outer:
		return PLASTER
	# stone corners, every other course standing out
	if ax >= hx - 0.5 and az >= hz - 0.5:
		return STONE
	if p.y >= WALL - 0.25:
		return BEAM
	# the shade of the eaves on the wall, baked in so it shows in any light
	if p.y >= WALL - 0.5:
		return PLASTER_SHADE
	# plank door in the middle of the front, set back one block, and a
	# side door in the middle of each end (a flank turned to the camera
	# read as a back wall without one, round 20)
	if p.z > 0.0 and az >= hz - 0.25 and absf(p.x) < 0.625 and p.y < 2.625:
		return EMPTY if az >= hz - 0.125 else (WOOD if int(floor(p.x / 0.25)) % 2 == 0 else WOOD_DARK)
	if ax >= hx - 0.25 and az < 0.5 and p.y < 2.625:
		return EMPTY if ax >= hx - 0.125 else (WOOD if int(floor(p.z / 0.25)) % 2 == 0 else WOOD_DARK)
	var win_y := p.y >= 1.875 and p.y < 3.125
	var sill := p.y >= 1.75 and p.y < 1.875
	if (win_y or sill) and az >= hz - 0.25:
		for w: float in wins:
			var k := absf(ax - w)
			if k < 0.625:
				return STONE if sill else (WINDOW if k < 0.375 else SHUTTER)
	if (win_y or sill) and ax >= hx - 0.25:
		for w: float in ends:
			var k := absf(az - w)
			if k < 0.625:
				return STONE if sill else (WINDOW if k < 0.375 else SHUTTER)
	return PLASTER_LOW if p.y < 0.875 else PLASTER

static func _house(p: Vector3) -> int:
	var ax := absf(p.x)
	var az := absf(p.z)
	if p.y < WALL:
		return _walls(p, HALF_X, HALF_Z, WINS_HOUSE, ENDS_HOUSE)
	return _hip_roof(p, HALF_X, HALF_Z, WALL)

## A hipped roof over the eaves of a house of half extents hx > hz with
## its walls up to `base`: hips and ridge darker, tile rows (imbrices)
## running down each slope.
static func _hip_roof(p: Vector3, hx: float, hz: float, base: float) -> int:
	var ax := absf(p.x)
	var az := absf(p.z)
	var dx := hx + EAVES - ax
	var dz := hz + EAVES - az
	if dx < 0.0 or dz < 0.0:
		return EMPTY
	var top := base + PITCH * minf(dx, dz)
	if p.y >= top:
		return EMPTY
	if absf(dx - dz) < 0.2 or p.y >= base + PITCH * (hz + EAVES) - 0.25:
		return RIDGE
	var along := p.z if dx < dz else p.x
	var dir := (0 if p.x > 0.0 else 1) if dx < dz else (2 if p.z > 0.0 else 3)
	return _tile(dir, posmod(int(floor(along / 0.25)), 3) == 0)

## The two-storey house: on a stone plinth, the ground floor with the door
## and a window, a stone string course, the upper floor with its own door
## off the landing of the outside stair and two windows, under a hipped
## roof; seen from above it stands taller than its neighbours.
static func _tall_house(p: Vector3) -> int:
	if p.y >= TALL_WALL:
		return _hip_roof(p, TALL_X, TALL_Z, TALL_WALL)
	var ax := absf(p.x)
	var az := absf(p.z)
	if p.y < 0.375:
		return PLINTH if ax < TALL_X + 0.125 and az < TALL_Z + 0.125 else EMPTY
	if ax >= TALL_X or az >= TALL_Z:
		return EMPTY
	if ax < TALL_X - 0.25 and az < TALL_Z - 0.25:
		return PLASTER
	if ax >= TALL_X - 0.5 and az >= TALL_Z - 0.5:
		return STONE
	if p.y >= TALL_WALL - 0.25:
		return BEAM
	if p.y >= TALL_WALL - 0.5:
		return PLASTER_SHADE
	if p.y >= UPPER - 0.25 and p.y < UPPER:
		return STONE # the string course between the floors
	var upper := p.y >= UPPER
	var front := p.z > 0.0 and az >= TALL_Z - 0.25
	# plank doors set back one block: below in the middle, above off the landing
	var door := (absf(p.x - 1.5) < 0.5 and p.y < UPPER + 2.25) if upper else (absf(p.x) < 0.625 and p.y < 2.625)
	if front and door:
		return EMPTY if az >= TALL_Z - 0.125 else (WOOD if int(floor(p.x / 0.25)) % 2 == 0 else WOOD_DARK)
	var lo := UPPER + 0.75 if upper else 1.875
	if p.y >= lo - 0.125 and p.y < lo + 1.25:
		var sill := p.y < lo
		var wins: Array[float] = TALL_WINS
		if front:
			wins = TALL_FRONT_UP if upper else TALL_FRONT_DOWN
		var k := 1.0e6
		if az >= TALL_Z - 0.25:
			for w: float in wins:
				k = minf(k, absf(p.x - w))
		if ax >= TALL_X - 0.25:
			k = minf(k, az) # one window in the middle of each end
		if k < 0.625:
			return STONE if sill else (WINDOW if k < 0.375 else SHUTTER)
	return PLASTER_LOW if p.y < 0.875 else PLASTER

## The two-storey house's outside stair: a solid flight of stone steps
## along the front from beyond the +x corner up to a landing at the upper
## door, the treads a lighter stone, a dark cellar door under the landing.
static func _stair(p: Vector3) -> int:
	if p.y < 0.0 or p.z < TALL_Z or p.z >= TALL_Z + 1.0 or p.x < STAIR_X.x or p.x >= STAIR_X.y:
		return EMPTY
	var top := UPPER if p.x < 2.0 else UPPER - 0.25 * (floorf((p.x - 2.0) / 0.25) + 1.0)
	if p.y >= top:
		return EMPTY
	if p.x < 2.0 and p.z >= TALL_Z + 0.75 and absf(p.x - 1.5) < 0.375 and p.y < 1.75:
		return WINDOW
	return STONE if p.y >= top - 0.125 else PLINTH

## A vine pergola on the -x side of the yard in front: four dark posts and
## two beams carrying a roof of vine leaves with gaps, so the yard shows
## through in patches.
static func _pergola(p: Vector3) -> int:
	if p.y < 0.0 or p.y >= 3.0 or p.x < -6.5 or p.x >= -3.75 or p.z < 3.25 or p.z >= 6.0:
		return EMPTY
	var post_x := absf(p.x + 6.25) < 0.125 or absf(p.x + 4.0) < 0.125
	var post_z := absf(p.z - 3.5) < 0.125 or absf(p.z - 5.75) < 0.125
	if p.y < 2.5:
		return WOOD_DARK if post_x and post_z else EMPTY
	if p.y < 2.75:
		return WOOD_DARK if post_z else EMPTY
	var v := Vector3i((p / 0.5).floor())
	if posmod(v.x * 3 + v.z * 5, 7) < 2:
		return EMPTY
	return LEAF if posmod(v.x + v.z * 2, 5) != 0 else LEAF_DARK

## The long house: four windows along the front, a gable roof with its
## ridge along the house, the end walls carried up as plaster gables under
## a rim of tiles.
static func _long_house(p: Vector3) -> int:
	var ax := absf(p.x)
	var az := absf(p.z)
	if p.y < WALL:
		return _walls(p, LONG_X, LONG_Z, WINS_LONG, ENDS_LONG)
	var dz := LONG_Z + EAVES - az
	if dz < 0.0 or ax >= LONG_X + 0.125:
		return EMPTY
	var top := WALL + PITCH * dz
	if p.y >= top:
		return EMPTY
	if p.y >= WALL + PITCH * (LONG_Z + EAVES) - 0.25:
		return RIDGE
	if ax >= LONG_X - 0.25 and az < LONG_Z and p.y < top - 0.375:
		return PLASTER
	return _tile(2 if p.z > 0.0 else 3, posmod(int(floor(p.x / 0.25)), 3) == 0)

## The portico along the long house's front: a stone floor one step up,
## plastered columns under a beam and a lean-to roof of tiles.
static func _portico(p: Vector3) -> int:
	if absf(p.x) >= PORCH_X or p.z < LONG_Z or p.z >= PORCH_Z:
		return EMPTY
	if p.y < 0.25:
		return PLINTH
	var roof := 3.5 - 0.3 * (p.z - LONG_Z)
	if p.y >= roof:
		return EMPTY
	if p.y >= roof - 0.25:
		return _tile(2, posmod(int(floor(p.x / 0.25)), 3) == 0)
	if p.z < PORCH_Z - 0.5:
		return EMPTY
	if p.y >= roof - 0.5:
		return BEAM
	for c: float in COLUMNS:
		if absf(p.x - c) < 0.25:
			return PLASTER_LOW if p.y < 0.5 else PLASTER
	return EMPTY

## A plank barn as a wing in front of the hipped-roof house: stone plinth,
## brown planks, a gable roof with its ridge running to the front and a
## wide open door in the front gable with the hay inside.
static func _barn(p: Vector3) -> int:
	var dx := absf(p.x - BARN_X)
	if p.z < BARN_Z.x or p.z >= BARN_Z.y + 0.125 or dx >= 2.375:
		return EMPTY
	var top := BARN_WALL + 0.5 * (2.375 - dx)
	if p.y >= top:
		return EMPTY
	var inside := dx < 2.0 and p.z < BARN_Z.y
	if p.y >= top - 0.375 or not inside:
		if p.y < BARN_WALL - 0.25 and not inside:
			return EMPTY # under the eaves
		if p.y >= BARN_WALL + 0.5 * 2.375 - 0.25:
			return RIDGE
		return _tile(0 if p.x > BARN_X else 1, posmod(int(floor(p.z / 0.25)), 3) == 0)
	var front := p.z >= BARN_Z.y - 0.25
	var end := front or p.z < BARN_Z.x + 0.25
	if not end and dx < 1.75:
		# the hay, seen through the door, and the dark barn over it (a
		# barn full to the roof read as a lit panel, round 18)
		return STRAW if p.y < 1.0 else WINDOW
	if p.y < 0.375:
		return PLINTH
	if dx >= 1.75 and end:
		return WOOD_DARK # corner posts
	if front and dx < 1.0 and p.y < 2.25:
		return EMPTY # the open door
	var along := p.x if end else p.z
	return WOOD if posmod(int(floor(along / 0.5)), 2) == 0 else WOOD_DARK

## Lean-to shed on the +x end: plank walls, open front with hay, a roof
## sloping away from the house.
static func _shed(p: Vector3) -> int:
	var x0 := HALF_X
	var x1 := 7.0
	if p.x < x0 or p.x >= x1 + 0.25 or p.z < -3.25 or p.z >= 0.75:
		return EMPTY
	var roof := 3.375 - 0.3 * (p.x - x0) # high enough at the wall to hide the end window behind it
	if p.y >= roof:
		return EMPTY
	if p.y >= roof - 0.25:
		return _tile(0, posmod(int(floor(p.z / 0.25)), 3) == 0)
	if p.x >= x1 or p.z < -3.0:
		return WOOD if posmod(int(floor((p.x + p.z) / 0.5)), 2) == 0 else WOOD_DARK
	if p.z >= 0.5:
		# open front, with posts at the corners
		return WOOD_DARK if p.x >= x1 - 0.25 else EMPTY
	# hay inside
	if p.y < 1.25 and p.x < 6.25 and p.z > -2.25:
		return STRAW
	return EMPTY

## Woodpile against the -x end, a shrub by the front corner, the garden
## beds at the back, the path to the gate, a well on the forecourt of
## stamped earth, the kept grass of the yard and the fence.
static func _yard(p: Vector3) -> int:
	# a low stack of logs against the end wall beside the side door, the
	# cut ends showing in rows (a plain block read as a crate, a checker
	# of ends as a glitch, round 20)
	if p.x >= -5.5 and p.x < -HALF_X - 0.125 and p.z >= -2.75 and p.z < -0.75 and p.y < 0.75:
		return WOOD if p.y >= 0.5 else (LOG if posmod(int(floor(p.z / 0.25)), 4) != 0 else WOOD_DARK)
	var s := Vector3(-3.5, 0.6, 4.25)
	var q := _snap(p, 0.25)
	var d := Vector2(q.x - s.x, q.z - s.z).length()
	if _variant == 0 and q.y < 1.25 and d < 0.75 - 0.3 * maxf(0.0, q.y - 0.6):
		return LEAF if q.y >= 0.75 else LEAF_DARK
	var tree := _tree(q)
	if tree != EMPTY:
		return tree
	tree = _workshop(p)
	if tree != EMPTY:
		return tree
	tree = _lot(p)
	if tree != EMPTY:
		return tree
	# earth path from the door through the gate to the lane, flush with the ground
	if p.y < 0.125 and absf(p.x) < 0.625 and p.z >= HALF_Z and p.z < PATH_END:
		return EARTH
	var well := _well(p)
	if well != EMPTY:
		return well
	# vegetable beds behind the house: rows of dark round cabbages on
	# brown soil, the soil showing between them
	var scaffold := _scaffold(p)
	if scaffold != EMPTY:
		return scaffold
	if p.z >= -5.75 and p.z < -4.0 and absf(p.x) < 3.5 and p.y >= 0.0 and p.y < 0.5:
		if p.y < 0.125:
			return SOIL
		var lx := fposmod(p.x + 3.5, 0.625)
		var lz := fposmod(p.z + 5.75, 0.625)
		if p.y < 0.375:
			if lx >= 0.125 and lx < 0.5 and lz >= 0.125 and lz < 0.5:
				return CABBAGE if p.y >= 0.25 else CABBAGE_DARK
			return EMPTY
		return CABBAGE if lx >= 0.25 and lx < 0.375 and lz >= 0.25 and lz < 0.375 else EMPTY
	# inside the fence the yard is kept grass, a shade fresher than the
	# pasture round it, and stamped earth on the forecourt beside the path
	# (the threshing floor), flush with the ground like the path
	if p.y < 0.125 and p.x > FENCE_LO.x and p.x < FENCE_HI.x and p.z > FENCE_LO.y and p.z < FENCE_HI.y:
		var forecourt := p.x >= 1.0 and p.x < 6.5 and p.z >= HALF_Z + 0.25 and p.z < 6.0
		return EARTH if forecourt else LOT_GRASS
	if p.y < 0.0:
		return EMPTY # the rest of the sunk layer is the terrain's
	return _fence(p)

## A scaffold of poles and planks half a metre round the walls of the
## build's house, shown only while the farm is being built
## (people_houses.gdshader); it takes only the air the rest leaves free.
static func _scaffold(at: Vector3) -> int:
	var half := Vector2(LONG_X, LONG_Z) if _variant == 1 else Vector2(TALL_X, TALL_Z) if _variant == 3 else Vector2(HALF_X, HALF_Z)
	var top := 7.25 if _variant == 3 else 5.5
	if at.y < 0.125 or at.y >= top:
		return EMPTY
	var p := _snap(at, 0.25)
	var d := Vector2(absf(p.x), absf(p.z)) - half # outside the wall
	var ring := maxf(d.x, d.y) >= 0.25 and maxf(d.x, d.y) < 0.75 and minf(d.x, d.y) < 0.75
	if not ring:
		return EMPTY
	# poles at the corners and every metre and a half along the sides
	var on_x := d.y >= 0.25 # along a long side (x varies)
	var along := p.x if on_x else p.z
	var pole := (absf(d.x - 0.375) < 0.25 and absf(d.y - 0.375) < 0.25) \
		or (fposmod(along + 0.125, 1.5) < 0.25 and absf((d.y if on_x else d.x) - 0.375) < 0.25)
	if pole and absf((d.y if on_x else d.x) - 0.375) < 0.125:
		return SCAFFOLD
	# planks round it every two metres
	if fposmod(p.y, 2.0) >= 1.75:
		return SCAFFOLD
	return EMPTY

## A well on the forecourt in quarter-metre blocks: a low stone curb six
## blocks across with its corners cut and dark water inside, two posts and
## a little gable roof of tiles over it, so it reads as a well and not as
## a block of stone.
static func _well(p: Vector3) -> int:
	if p.y < 0.0 or p.y >= 2.0 or p.x < 4.5 or p.x >= 6.0 or p.z < 4.25 or p.z >= 5.75:
		return EMPTY
	var bx := int(floor((p.x - 4.5) / 0.25))
	var bz := int(floor((p.z - 4.25) / 0.25))
	var by := int(floor(p.y / 0.25))
	var end := bx == 0 or bx == 5
	if by == 7:
		return RIDGE if bz == 2 or bz == 3 else EMPTY
	if by == 6:
		return _tile(3 if bz < 3 else 2, bz == 0 or bz == 5) if bz >= 1 and bz <= 4 else EMPTY
	if by >= 2:
		return WOOD_DARK if end and (bz == 2 or bz == 3) else EMPTY # the posts
	if end and (bz == 0 or bz == 5):
		return EMPTY
	if bx >= 2 and bx <= 3 and bz >= 2 and bz <= 3:
		return WATER if by == 0 else EMPTY
	return PLINTH

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

## The three workshops on one spot (WORKSHOP_LO..HI, x and z), in quarter
## metre blocks: a smithy under a lean-to roof (stone hearth with glowing
## coals and a chimney, an anvil on a stump, a bench of finished tools), a
## potter's domed kiln with its dark mouth and rows of jars, and a weaver's
## upright loom with red cloth on it, a line of cloths hung to dry and
## bales of wool.
static func _workshop(at: Vector3) -> int:
	if at.y < 0.0 or at.y >= 3.25:
		return EMPTY
	for k in WORKSHOP_AT.size():
		var p := _snap(at, 0.25) - Vector3(WORKSHOP_AT[k].x, 0.0, WORKSHOP_AT[k].y)
		if p.x < WORKSHOP_LO.x or p.x >= WORKSHOP_HI.x or p.z < WORKSHOP_LO.y or p.z >= WORKSHOP_HI.y:
			continue
		return _smithy(p) if k == 0 else _pottery(p) if k == 1 else _weavery(p)
	return EMPTY

static func _inside(p: Vector3, lo: Vector3, hi: Vector3) -> bool:
	return p.x >= lo.x and p.x < hi.x and p.y >= lo.y and p.y < hi.y and p.z >= lo.z and p.z < hi.z

static func _smithy(p: Vector3) -> int:
	# the lean-to: four posts and a tiled roof stepping down away from the house
	var roof := 2.75 - 0.25 * floorf((p.z - 7.25) / 1.0)
	for post: Vector2 in [Vector2(2.75, 7.5), Vector2(6.0, 7.5), Vector2(2.75, 9.75), Vector2(6.0, 9.75)]:
		if absf(p.x - post.x - 0.125) < 0.125 and absf(p.z - post.y - 0.125) < 0.125 and p.y < roof:
			return SMITH_WOOD
	if p.x >= 2.5 and p.x < 6.5 and p.y >= roof and p.y < roof + 0.25 and not (p.x >= 3.5 and p.x < 4.0 and p.z >= 9.25):
		return SMITH_ROOF
	# hearth with its coals, the chimney through the roof
	if _inside(p, Vector3(3.0, 0.0, 9.0), Vector3(4.5, 1.0, 10.0)):
		return SMITH_STONE
	if _inside(p, Vector3(3.25, 1.0, 9.25), Vector3(3.5, 1.25, 9.75)) or _inside(p, Vector3(4.0, 1.0, 9.25), Vector3(4.25, 1.25, 9.75)):
		return SMITH_FIRE
	if _inside(p, Vector3(3.5, 1.0, 9.25), Vector3(4.0, 3.25, 9.75)):
		return SMITH_STONE
	# the anvil on a stump
	if _inside(p, Vector3(4.75, 0.0, 8.0), Vector3(5.25, 0.5, 8.5)):
		return SMITH_WOOD
	if _inside(p, Vector3(4.5, 0.5, 8.0), Vector3(5.5, 0.75, 8.5)):
		return SMITH_IRON
	# a bench of finished tools by the right post
	if _inside(p, Vector3(5.25, 0.0, 8.75), Vector3(6.0, 0.5, 9.5)):
		return SMITH_WOOD
	if _inside(p, Vector3(5.25, 0.5, 8.75), Vector3(6.0, 0.75, 9.5)) and posmod(int(floor(p.z / 0.25)), 2) == 0:
		return SMITH_TOOLS
	return EMPTY

static func _pottery(p: Vector3) -> int:
	# the kiln: a stepped dome of brick, its mouth to the front
	var d := Vector2(absf(p.x - 3.75), absf(p.z - 8.75))
	var r := 1.25 if p.y < 0.75 else 1.0 if p.y < 1.25 else 0.75 if p.y < 1.75 else 0.5 if p.y < 2.0 else 0.0
	if d.x < r and d.y < r and d.x + d.y < r * 1.5:
		if p.z >= 9.5 and d.x < 0.375 and p.y < 0.75:
			return POT_DARK
		return POT_KILN
	# jars in rows on the ground, a lighter rim on top
	if p.x >= 5.25 and p.x < 6.25 and p.z >= 7.5 and p.z < 10.0 and p.y < 0.75:
		var jx := fposmod(p.x - 5.25, 0.5)
		var jz := fposmod(p.z - 7.5, 0.5)
		if jx < 0.25 and jz < 0.25:
			var row := int(floor((p.z - 7.5) / 0.5))
			var k := POT_JAR if row < 2 else POT_JAR_MORE
			return k if p.y < 0.5 else (k if row % 2 == 0 else EMPTY)
	return EMPTY

static func _weavery(p: Vector3) -> int:
	# the loom: two uprights, a beam, the warp above and the cloth below
	if (absf(p.x - 2.875) < 0.125 or absf(p.x - 4.875) < 0.125) and p.z >= 9.25 and p.z < 9.5 and p.y < 2.25:
		return WEAVE_WOOD
	if p.x >= 2.75 and p.x < 5.0 and p.z >= 9.25 and p.z < 9.5 and p.y >= 2.0 and p.y < 2.25:
		return WEAVE_WOOD
	if p.x >= 3.0 and p.x < 4.75 and p.z >= 9.25 and p.z < 9.5 and p.y >= 0.5 and p.y < 2.0:
		return WEAVE_CLOTH if p.y < 1.25 else (WEAVE_WARP if posmod(int(floor(p.x / 0.25)), 2) == 0 else EMPTY)
	# the drying line between two posts, three cloths hung on it
	if (absf(p.x - 2.625) < 0.125 or absf(p.x - 6.125) < 0.125) and absf(p.z - 7.875) < 0.125 and p.y < 1.75:
		return WEAVE_WOOD
	if p.x >= 2.5 and p.x < 6.25 and absf(p.z - 7.875) < 0.125 and p.y >= 1.5 and p.y < 1.75:
		return WEAVE_WOOD
	if absf(p.z - 7.875) < 0.125 and p.y >= 0.5 and p.y < 1.5:
		if p.x >= 2.875 and p.x < 3.625:
			return WEAVE_CLOTH
		if p.x >= 3.875 and p.x < 4.625:
			return WEAVE_CLOTH_2
		if p.x >= 4.875 and p.x < 5.625:
			return WEAVE_CLOTH_3
	# bales of wool
	if p.x >= 5.25 and p.x < 6.25 and p.z >= 8.5 and p.z < 9.75 and p.y < (0.75 if p.z < 9.25 else 0.5):
		return WEAVE_WOOL
	return EMPTY

const OLIVE_CLUMPS: Array[Vector4] = [Vector4(-0.75, 0.25, 1.5, 2.75), Vector4(0.75, -0.25, 1.75, 3.25), Vector4(0.25, 0.75, 2.0, 3.5)]

## Outside the fence: a cypress in either front corner of the lot (clear of
## the house front), an olive tree in one back corner and a haystack in the
## other. Each in colours of its own, so people_houses.gdshader can leave
## them out by farm.
static func _lot(at: Vector3) -> int:
	if at.y < 0.0:
		return EMPTY
	# cypresses: a slim dark spindle (a fifth as wide as tall, no taller
	# than 1.7 eaves), widest low down and drawn in to a point, in the
	# finest blocks so the taper shows
	var p := at
	var cz := absf(p.z - 8.75)
	var cx := absf(absf(p.x) - 8.75)
	if cx < 0.625 and cz < 0.625:
		var r := 0.375 if p.y < 0.5 else 0.625 if p.y < 2.0 else 0.5 if p.y < 3.25 else 0.375 if p.y < 4.5 else 0.25 if p.y < 5.5 else 0.125 if p.y < 6.0 else 0.0
		if cx < r and cz < r and cx + cz < r * 1.5:
			return CYPRESS_DARK if p.y < 1.0 else CYPRESS
		return EMPTY
	# an olive tree: a crooked grey trunk and a wide crown of three uneven
	# clumps, silver-green, darker underneath
	var o := Vector2(p.x - 8.0, p.z + 8.0)
	if p.y < 1.75:
		if absf(o.x - 0.25 * floorf(p.y / 0.75)) < 0.25 and absf(o.y) < 0.25:
			return OLIVE_TRUNK
	# the crown in half-metre blocks
	var c := _snap(at, 0.5)
	var co := Vector2(c.x - 8.0, c.z + 8.0)
	for clump: Vector4 in OLIVE_CLUMPS: # x, z, bottom, top
		var d := Vector2(absf(co.x - clump.x), absf(co.y - clump.y))
		var r := 1.0 if c.y < clump.w - 0.5 else 0.625
		if c.y >= clump.z and c.y < clump.w and d.x < r and d.y < r and d.x + d.y < r * 1.5:
			return OLIVE_DARK if c.y < clump.z + 0.5 else OLIVE
	# a haystack: a stepped dome of golden hay in half-metre blocks, six
	# wide at the foot, with a darker band where it is tied, so it stands
	# apart from the wheat
	var hx := absf(c.x + 8.0)
	var hz := absf(c.z + 8.0)
	var hr := 1.5 if c.y < 1.0 else 1.0 if c.y < 1.5 else 0.5 if c.y < 2.0 else 0.0
	if maxf(hx, hz) + 0.5 * minf(hx, hz) < hr:
		return HAY_DARK if c.y >= 1.0 and c.y < 1.5 else HAY
	return EMPTY

## The levels of detail of one build, nearest first, scaled to the unit
## house. Built once and kept in user://.
static func lods(unit_m: float, variant: int) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for level in LOD_VOXELS.size():
		out.append(lod(unit_m, variant, level))
	return out

## One level of detail of one build (LOD_VOXELS), built once and kept in
## user:// like lods().
static func lod(unit_m: float, variant: int, level: int) -> ArrayMesh:
	var v: float = LOD_VOXELS[level]
	var path := CACHE % [variant, str(v)]
	var mesh: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
	if mesh == null:
		_variant = variant
		mesh = VoxelMesh.build(sample, BOUNDS_LO, BOUNDS_HI, v, FINE, PALETTE, 1.0 / unit_m, TOPS)
		ResourceSaver.save(mesh, path)
	return mesh
