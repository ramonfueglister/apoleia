extends RefCounted
## The Roman town's buildings for the game: voxel models in Urbek's craft
## (0.25 m voxels, 40 to a 10 m lot) built by roman_town.gd and
## roman_colosseum.gd, which are kept in step with prototypes/colosseum.
## Every mesh is in metres with vertex colours, its footprint centred on the
## origin and the building's floor at y = 0 (the lot's own ground layers are
## left out; the terrain is the ground). The front faces +z (south).
##
## Levels of detail: 0 is the full model; 1 is light, for thousands of
## instances at 8 to 22 km: 1 m voxels by weighted majority, people and
## other small things gone, a few hundred triangles a lot; 2 is coarser
## still (2.5 m voxels). Meshes are cached in user://. Worker threads may
## call in while the main thread keeps running frames (meshes go through
## the rendering server); models are built one at a time.

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Town := preload("res://scripts/voxel/roman_town.gd")
const Colosseum := preload("res://scripts/voxel/roman_colosseum.gd")

const LOD_FACTORS := [1, 4, 10]
const CACHE_DIR := "user://roman_buildings_v5"

## Lot archetypes: number of variants and footprint in 10 m lots.
const ARCHETYPES := {
	"house": [32, Vector2i(1, 1)], "domus": [3, Vector2i(2, 2)], "insula": [6, Vector2i(2, 1)],
	"temple": [6, Vector2i(2, 2)], "garden": [4, Vector2i(1, 1)], "market": [4, Vector2i(2, 2)],
}
## Landmarks and their footprints in lots.
const LANDMARKS := {"colosseum": Vector2i(8, 7), "forum": Vector2i(5, 5), "baths": Vector2i(3, 2), "pantheon": Vector2i(3, 3), "circus": Vector2i(8, 3)}

# Voxels too small to keep at the light levels: people and their clothes.
const SMALL := [Kit.SKIN, Kit.HAIR, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_B, Kit.ROBE_N, Kit.ROBE_O, Kit.HELMET, Kit.SHIELD]

## The mesh of variant `variant` of lot archetype `kind` at level `lod`.
static func lot_mesh(kind: String, variant: int, lod := 0) -> ArrayMesh:
	return _cached("%s_%d" % [kind, variant], lod, func() -> Kit.Grid: return _lot_grid(kind, variant))

## The mesh of landmark `name` ("colosseum", "forum", "baths", "pantheon",
## "circus") at level `lod`.
static func landmark_mesh(name: String, lod := 0) -> ArrayMesh:
	return _cached(name, lod, func() -> Kit.Grid: return _landmark_grid(name))

## Footprint in 10 m lots of a lot archetype or a landmark.
static func footprint(kind: String) -> Vector2i:
	if ARCHETYPES.has(kind):
		return ARCHETYPES[kind][1]
	return LANDMARKS.get(kind, Vector2i.ONE)

# roman_town.gd hands its grids over through static state, so builds take
# turns.
static var _lock := Mutex.new()

static func _cached(key: String, lod: int, build: Callable) -> ArrayMesh:
	var path := "%s/%s_%d.res" % [CACHE_DIR, key, lod]
	if ResourceLoader.exists(path):
		var mesh: ArrayMesh = load(path)
		if mesh != null:
			if mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, Kit.material())
			return mesh
	_lock.lock()
	var g: Kit.Grid = build.call()
	if g == null:
		_lock.unlock()
		return null
	# Centred on the full model, so the coarse levels sit exactly on it.
	var lo := Vector3(-g.n.x * 0.5, 0.0, -g.n.z * 0.5) * Kit.V
	var f: int = LOD_FACTORS[clampi(lod, 0, LOD_FACTORS.size() - 1)]
	if f > 1:
		# Cells start on the lot's edge, so neighbouring lots meet cleanly.
		var pad := (f - Town.MARGIN % f) % f
		g = _coarse(g, f, pad)
		lo -= Vector3(pad, 0, pad) * Kit.V
	var mesh := Kit.mesh(g, lo, Kit.V * f)
	_lock.unlock()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	ResourceSaver.save(mesh, path)
	return mesh

## A lot model's grid from its floor up (the lot's ground layers left out),
## with the margin its overhangs reach into; the lot sits in the middle.
static func _lot_grid(kind: String, variant: int) -> Kit.Grid:
	Town.keep_grid = true
	match kind:
		"house": Town.house_lot(variant)
		"domus": Town.domus(variant)
		"insula": Town.insula(variant)
		"temple": Town.temple(variant)
		"garden": Town.garden(variant)
		"market": Town.market(variant)
		_:
			Town.keep_grid = false
			return null
	Town.keep_grid = false
	return _without_ground(Town.last_grid, Town.FLOOR)

static func _landmark_grid(name: String) -> Kit.Grid:
	match name:
		"colosseum":
			return _without_ground(Colosseum.grid(), Colosseum.GROUND)
		"forum", "baths", "pantheon", "circus":
			Town.keep_grid = true
			match name:
				"forum": Town.forum(0)
				"baths": Town.baths(0)
				"pantheon": Town.pantheon(0)
				"circus": Town.circus(0)
			Town.keep_grid = false
			return _without_ground(Town.last_grid, Town.FLOOR)
	return null

## The grid from layer `floor` up, so the building stands on y = 0.
static func _without_ground(g: Kit.Grid, floor: int) -> Kit.Grid:
	var out := Kit.Grid.new(Vector3i(g.n.x, g.n.y - floor, g.n.z))
	for z in g.n.z:
		for y in range(floor, g.n.y):
			var src := g.n.x * (y + g.n.y * z)
			var dst := out.n.x * ((y - floor) + out.n.y * z)
			for x in g.n.x:
				out.g[dst + x] = g.g[src + x]
	return out

## A coarser grid, `f` voxels to a side and shifted by `pad` voxels in x
## and z: a cell is solid where at least a quarter of it is, or where
## something raised (a roof, an awning) covers three quarters of its plan.
## Where voxels open to the sky cover half its plan, it takes the colour
## most of them have, so roofs stay roofs; otherwise the colour most of it
## has. People and other small things are dropped first.
static var _small := PackedByteArray()

# Voxels above the floor from which a thin cover counts (beds and paving
# below it do not).
const RAISED := 4

static func _coarse(g: Kit.Grid, f: int, pad: int) -> Kit.Grid:
	if _small.is_empty():
		_small.resize(256)
		for c: int in SMALL:
			_small[c] = 1
	var out := Kit.Grid.new(Vector3i(ceili((g.n.x + pad) / float(f)), ceili(g.n.y / float(f)), ceili((g.n.z + pad) / float(f))))
	var weight := PackedInt32Array()
	weight.resize(256)
	var sky := PackedInt32Array()
	sky.resize(256)
	var column := PackedByteArray()
	column.resize(f * f)
	for cz in out.n.z:
		for cy in out.n.y:
			for cx in out.n.x:
				weight.fill(0)
				sky.fill(0)
				column.fill(0)
				var solid := 0
				var open := 0
				var covered := 0
				for sz in f:
					for sy in f:
						for sx in f:
							var x := cx * f + sx - pad
							var y := cy * f + sy
							var z := cz * f + sz - pad
							var c := g.at(x, y, z)
							if c == Kit.EMPTY or _small[c] == 1:
								continue
							solid += 1
							weight[c] += 1
							var above := g.at(x, y + 1, z)
							if above == Kit.EMPTY or _small[above] == 1:
								sky[c] += 1
								open += 1
							if y >= RAISED and column[sx + f * sz] == 0:
								column[sx + f * sz] = 1
								covered += 1
				if solid * 4 < f * f * f and covered * 4 < f * f * 3:
					continue
				var votes := sky if open * 2 >= f * f else weight
				var best := 0
				for c in range(1, 256):
					if votes[c] > votes[best]:
						best = c
				out.put(cx, cy, cz, best)
	return out
