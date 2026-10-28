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
## still (2.5 m voxels). Meshes are cached in user://.

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Town := preload("res://scripts/voxel/roman_town.gd")
const Colosseum := preload("res://scripts/voxel/roman_colosseum.gd")

const LOD_FACTORS := [1, 4, 10]
const CACHE_DIR := "user://roman_buildings_v1"

## Lot archetypes: number of variants and footprint in 10 m lots.
const ARCHETYPES := {
	"house": [32, Vector2i(1, 1)], "domus": [3, Vector2i(2, 2)], "insula": [6, Vector2i(2, 1)],
	"temple": [6, Vector2i(2, 2)], "garden": [4, Vector2i(1, 1)], "market": [4, Vector2i(2, 2)],
}
## Landmarks and their footprints in lots.
const LANDMARKS := {"colosseum": Vector2i(8, 7), "forum": Vector2i(5, 5), "baths": Vector2i(3, 2)}

# Voxels too small to keep at the light levels: people and their clothes.
const SMALL := [Kit.SKIN, Kit.HAIR, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_B, Kit.ROBE_N, Kit.ROBE_O, Kit.HELMET, Kit.SHIELD]

## The mesh of variant `variant` of lot archetype `kind` at level `lod`.
static func lot_mesh(kind: String, variant: int, lod := 0) -> ArrayMesh:
	return _cached("%s_%d" % [kind, variant], lod, func() -> Kit.Grid: return _lot_grid(kind, variant))

## The mesh of landmark `name` ("colosseum", "forum", "baths") at level `lod`.
static func landmark_mesh(name: String, lod := 0) -> ArrayMesh:
	return _cached(name, lod, func() -> Kit.Grid: return _landmark_grid(name))

## Footprint in 10 m lots of a lot archetype or a landmark.
static func footprint(kind: String) -> Vector2i:
	if ARCHETYPES.has(kind):
		return ARCHETYPES[kind][1]
	return LANDMARKS.get(kind, Vector2i.ONE)

static func _cached(key: String, lod: int, build: Callable) -> ArrayMesh:
	var path := "%s/%s_%d.res" % [CACHE_DIR, key, lod]
	if ResourceLoader.exists(path):
		var mesh: ArrayMesh = load(path)
		if mesh != null:
			if mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, Kit.material())
			return mesh
	var g: Kit.Grid = build.call()
	if g == null:
		return null
	var f: int = LOD_FACTORS[clampi(lod, 0, LOD_FACTORS.size() - 1)]
	if f > 1:
		g = _coarse(g, f)
	var mesh := Kit.mesh(g, Vector3(-g.n.x * 0.5, 0.0, -g.n.z * 0.5) * Kit.V * f, Kit.V * f)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	ResourceSaver.save(mesh, path)
	return mesh

## A lot model's grid with its ground layers left out, cropped to the lot
## and its overhangs, centred.
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
		"forum", "baths":
			Town.keep_grid = true
			if name == "forum":
				Town.forum(0)
			else:
				Town.baths(0)
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

## A coarser grid, `f` voxels to a side: a cell is solid where at least a
## quarter of it is, in the colour that covers most of it, upper layers
## counting double so roofs keep their tiles; people and other small
## things dropped first.
static var _small := PackedByteArray()

static func _coarse(g: Kit.Grid, f: int) -> Kit.Grid:
	if _small.is_empty():
		_small.resize(256)
		for c: int in SMALL:
			_small[c] = 1
	var out := Kit.Grid.new(Vector3i(ceili(g.n.x / float(f)), ceili(g.n.y / float(f)), ceili(g.n.z / float(f))))
	var weight := PackedInt32Array()
	weight.resize(256)
	for cz in out.n.z:
		for cy in out.n.y:
			for cx in out.n.x:
				weight.fill(0)
				var solid := 0
				for sz in f:
					for sy in f:
						for sx in f:
							var c := g.at(cx * f + sx, cy * f + sy, cz * f + sz)
							if c == Kit.EMPTY or _small[c] == 1:
								continue
							solid += 1
							weight[c] += 1 << sy
				if solid * 4 < f * f * f:
					continue
				var best := 0
				for c in range(1, 256):
					if weight[c] > weight[best]:
						best = c
				out.put(cx, cy, cz, best)
	return out
