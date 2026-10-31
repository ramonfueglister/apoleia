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
## still (2.5 m voxels).
##
## Meshes are cached in user:// per model and level under a key: a hash of
## the model's voxels, the colours they use and the mesher. A start loads
## them while the voxel scripts are unchanged. After a change the first call
## rebuilds the voxels of every model met before, on all cores, and meshes
## again only those whose key changed, all their levels at once; a model
## met for the first time is built with its levels the same way. Worker
## threads may call in while the main thread keeps running frames (meshes go
## through the rendering server); calls take turns.

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Town := preload("res://scripts/voxel/roman_town.gd")
const Colosseum := preload("res://scripts/voxel/roman_colosseum.gd")
const Arena := preload("res://scripts/voxel/roman_arena.gd")
const Landmarks := preload("res://scripts/voxel/roman_landmarks.gd")
const Verona := preload("res://scripts/voxel/verona_landmarks.gd")
const City := preload("res://scripts/voxel/roman_city.gd")

const LOD_FACTORS := [1, 4, 10]
const CACHE_DIR := "user://roman_buildings"
const INDEX := CACHE_DIR + "/index.json"

## Lot archetypes: number of variants and footprint in 10 m lots.
const ARCHETYPES := {
	"house": [32, Vector2i(1, 1)], "domus": [3, Vector2i(2, 2)], "insula": [6, Vector2i(2, 1)],
	"temple": [6, Vector2i(2, 2)], "garden": [4, Vector2i(1, 1)], "market": [4, Vector2i(2, 2)],
	"plaza": [8, Vector2i(1, 1)], "tombs": [5, Vector2i(1, 1)],
	# the city plans' pieces (roman_city.gd)
	"plan_wall": [City.WALL_VARIANTS, Vector2i(1, 1)], "plan_gate": [2, Vector2i(1, 1)],
	"plan_temple": [2, Vector2i(1, 1)], "plan_theatre": [1, Vector2i(1, 1)],
	"plan_amphitheatre": [1, Vector2i(1, 1)], "plan_baths": [1, Vector2i(1, 1)],
	"plan_basilica": [3, Vector2i(1, 1)], "plan_horrea": [1, Vector2i(1, 1)],
	"plan_circus": [2, Vector2i(1, 1)], "plan_forum": [2, Vector2i(1, 1)],
	"street_row": [City.ROW_VARIANTS, Vector2i(1, 1)], "street_corner_w": [City.CORNER_VARIANTS, Vector2i(1, 1)],
	"street_corner_e": [City.CORNER_VARIANTS, Vector2i(1, 1)], "street_court": [City.COURT_VARIANTS, Vector2i(1, 1)],
}
## Landmarks and their footprints in lots. The arena, the circus, the
## theatre and the baths are Rome's at the diorama scale by the landmark rule
## (roman_arena.gd, roman_landmarks.gd, SCALE.md); the forum and the
## Pantheon are the town's older models; the Colosseum stays for the menu.
const LANDMARKS := {"arena": Vector2i(4, 3), "colosseum": Vector2i(8, 7), "forum": Vector2i(5, 5), "baths": Vector2i(4, 2), "pantheon": Vector2i(3, 3), "circus": Vector2i(7, 2), "theatre": Vector2i(2, 3), "verona_arena": Vector2i(3, 3), "verona_theatre": Vector2i(3, 2), "verona_capitolium": Vector2i(2, 2), "verona_forum": Vector2i(2, 4), "verona_basilica": Vector2i(2, 3), "verona_baths": Vector2i(3, 2)}
## The landmarks built by the rule's scripts.
const DIORAMA := ["arena", "circus", "theatre", "baths"]

# Voxels too small to keep at the light levels: people and their clothes.
const SMALL := [Kit.SKIN, Kit.HAIR, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_B, Kit.ROBE_N, Kit.ROBE_O, Kit.HELMET, Kit.SHIELD]

## The mesh of variant `variant` of lot archetype `kind` at level `lod`.
static func lot_mesh(kind: String, variant: int, lod := 0) -> ArrayMesh:
	return _mesh("%s_%d" % [kind, variant], lod)

## The mesh of landmark `name` ("arena", "colosseum", "forum", "baths",
## "pantheon", "circus", "theatre") at level `lod`.
static func landmark_mesh(name: String, lod := 0) -> ArrayMesh:
	return _mesh(name, lod)

## Builds whatever the cache lacks for these lots ([kind, variant] pairs)
## and landmarks in one go on all cores, so the calls after it only load.
## Optional: without it a first start builds model by model.
static func prepare(lots: Array, landmarks: Array) -> void:
	var models := {}
	for lot: Array in lots:
		models["%s_%d" % [lot[0], lot[1]]] = true
	for name: String in landmarks:
		models[name] = true
	_lock.lock()
	_open()
	var todo := {}
	for model: String in models:
		for lod: int in _levels(model):
			if not _current("%s_%d" % [model, lod], model):
				todo[model] = _levels(model)
	todo.merge(_stale())
	if not todo.is_empty():
		_bake(todo)
	_lock.unlock()

## Footprint in 10 m lots of a lot archetype or a landmark.
static func footprint(kind: String) -> Vector2i:
	if ARCHETYPES.has(kind):
		return ARCHETYPES[kind][1]
	return LANDMARKS.get(kind, Vector2i.ONE)

static var _lock := Mutex.new()
static var _opened := false
# File name ("house_4_1") -> {"key": its content key, "code": the voxel
# scripts it was last checked against}.
static var _index := {}
# Meshes made or loaded this session, by file name.
static var _meshes := {}
# Fingerprints of the voxel scripts (town models, the Colosseum, the
# landmarks by the rule) and of the mesher.
static var _code_town := ""
static var _code_colosseum := ""
static var _code_arena := ""
static var _code_verona := ""
static var _mesher := ""

static func _mesh(model: String, lod: int) -> ArrayMesh:
	lod = clampi(lod, 0, LOD_FACTORS.size() - 1)
	var name := "%s_%d" % [model, lod]
	_lock.lock()
	_open()
	if not _meshes.has(name):
		if not _current(name, model):
			var todo := _stale()
			var levels: Array = todo.get(model, _levels(model))
			if lod not in levels:
				levels.append(lod)
			todo[model] = levels
			_bake(todo)
		if not _meshes.has(name):
			var mesh: ArrayMesh = load(_path(name)) if ResourceLoader.exists(_path(name)) else null
			if mesh == null:
				# lost or broken file: build it again
				_bake({model: [lod]}, true)
			else:
				if mesh.get_surface_count() > 0:
					mesh.surface_set_material(0, Kit.material())
				_meshes[name] = mesh
	var out: ArrayMesh = _meshes.get(name)
	_lock.unlock()
	return out

static func _path(name: String) -> String:
	return "%s/%s.res" % [CACHE_DIR, name]

static func _code(model: String) -> String:
	if model.begins_with("verona_"):
		return _code_verona
	if model in DIORAMA:
		return _code_arena
	return _code_colosseum if model == "colosseum" else _code_town

## The levels a model gets built with: all for lots, the two the terrain
## draws for landmarks (more on demand).
static func _levels(model: String) -> Array:
	return [0, 1] if LANDMARKS.has(model) else range(LOD_FACTORS.size())

static func _current(name: String, model: String) -> bool:
	var entry: Dictionary = _index.get(name, {})
	return entry.get("code", "") == _code(model) and ResourceLoader.exists(_path(name))

## The models met before whose files are out of date or gone, with the
## levels they have.
static func _stale() -> Dictionary:
	var models := {}
	for name: String in _index:
		var model := name.left(name.rfind("_"))
		if not _current(name, model):
			models[model] = true
	var out := {}
	for name: String in _index:
		var model := name.left(name.rfind("_"))
		if models.has(model):
			var levels: Array = out.get(model, _levels(model))
			var lod := int(name.substr(name.rfind("_") + 1))
			if lod not in levels:
				levels.append(lod)
			out[model] = levels
	return out

static func _open() -> void:
	if _opened:
		return
	_opened = true
	var kit := _source(Kit)
	var own := _source(load("res://scripts/voxel/roman_buildings.gd"))
	_code_town = (_source(Town) + _source(City) + kit + own).md5_text()
	_code_colosseum = (_source(Colosseum) + kit + own).md5_text()
	_code_arena = (_source(Arena) + _source(Landmarks) + _source(Colosseum) + kit + own).md5_text()
	_code_verona = (_source(Verona) + _source(Arena) + _source(Colosseum) + kit + own).md5_text()
	# The mesher and the coarse levels: their code (from the line that
	# starts them to the end) and the constants they use.
	var mesher := kit.substr(maxi(kit.find("\nstatic func mesh_arrays("), 0)) + own.substr(maxi(own.find("\nstatic func _coarse("), 0))
	_mesher = (mesher + str(LOD_FACTORS) + str(SMALL) + str(RAISED) + str(Kit.V) + str(Kit.AO)).md5_text()
	var text := FileAccess.get_file_as_string(INDEX)
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	_index = data if data is Dictionary else {}
	# Caches of the old layout, one folder per version.
	var user := DirAccess.open("user://")
	if user != null:
		for folder in user.get_directories():
			var old := DirAccess.open("user://" + folder) if folder.begins_with("roman_buildings_v") else null
			if old != null:
				for file in old.get_files():
					old.remove(file)
				user.remove(folder)

# A script's text; empty in an export, where the cache is then trusted.
static func _source(script: GDScript) -> String:
	return script.source_code

static func _save_index() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var file := FileAccess.open(INDEX, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_index, "\t", true))

class Job:
	var model: String
	var levels: Array
	var grid: Kit.Grid
	var keys := {}

	func _init(m: String, l: Array) -> void:
		model = m
		levels = l

class Part:
	var job: Job
	var lod: int
	var arrays: Array

	func _init(j: Job, l: int) -> void:
		job = j
		lod = l

## Builds the voxels of models {model: [levels]} on all cores and meshes the
## levels whose key changed (all of them with `force`); the main thread
## makes the meshes and files.
static func _bake(todo: Dictionary, force := false) -> void:
	# tables the threads share, filled first
	Kit._colours()
	_small_table()
	var jobs: Array[Job] = []
	for model: String in todo:
		jobs.append(Job.new(model, todo[model]))
	_parallel(jobs.size(), func(i: int) -> void: _make_grid(jobs[i]))
	var parts: Array[Part] = []
	for job in jobs:
		for lod: int in job.levels:
			var name := "%s_%d" % [job.model, lod]
			if job.grid == null:
				_index.erase(name)
				continue
			var entry: Dictionary = _index.get(name, {})
			if not force and entry.get("key", "") == job.keys[lod] and ResourceLoader.exists(_path(name)):
				# same voxels, colours and mesher: the file stands
				entry["code"] = _code(job.model)
				_index[name] = entry
			else:
				parts.append(Part.new(job, lod))
	_parallel(parts.size(), func(i: int) -> void: _make_arrays(parts[i]))
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for part in parts:
		var name := "%s_%d" % [part.job.model, part.lod]
		var mesh := Kit.mesh_from(part.arrays)
		ResourceSaver.save(mesh, _path(name))
		_meshes[name] = mesh
		_index[name] = {"key": part.job.keys[part.lod], "code": _code(part.job.model)}
	_save_index()

# Runs fn(0) .. fn(n - 1) on the worker threads and waits for them; in the
# calling thread alone unless that is the main thread, as a worker must not
# wait on workers.
static func _parallel(n: int, fn: Callable) -> void:
	if n > 1 and OS.get_thread_caller_id() == OS.get_main_thread_id():
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(fn, n))
	else:
		for i in n:
			fn.call(i)

static func _make_grid(job: Job) -> void:
	job.grid = _grid(job.model)
	if job.grid == null:
		return
	var g := job.grid
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(g.g)
	var used := PackedStringArray()
	for c: int in Kit.COLOURS:
		if g.g.has(c):
			used.append("%d %s" % [c, str(Kit.COLOURS[c])])
	var content := "%s %s %s %s" % [h.finish().hex_encode(), str(g.n), ",".join(used), _mesher]
	for lod: int in job.levels:
		job.keys[lod] = ("%s %d" % [content, LOD_FACTORS[lod]]).md5_text()

static func _make_arrays(part: Part) -> void:
	var g := part.job.grid
	# Centred on the full model, so the coarse levels sit exactly on it.
	var lo := Vector3(-g.n.x * 0.5, 0.0, -g.n.z * 0.5) * Kit.V
	var f: int = LOD_FACTORS[part.lod]
	if f > 1:
		# Cells start on the lot's edge, so neighbouring lots meet cleanly.
		var pad := (f - Town.MARGIN % f) % f
		g = _coarse(g, f, pad)
		lo -= Vector3(pad, 0, pad) * Kit.V
	part.arrays = Kit.mesh_arrays(g, lo, Kit.V * f)

## The voxels of a model ("house_4", "colosseum"), null if there is none.
static func _grid(model: String) -> Kit.Grid:
	if LANDMARKS.has(model):
		return _landmark_grid(model)
	var cut := model.rfind("_")
	if cut < 0 or not ARCHETYPES.has(model.left(cut)):
		return null
	return _lot_grid(model.left(cut), int(model.substr(cut + 1)))

## A lot model's grid from its floor up (the lot's ground layers left out),
## with the margin its overhangs reach into; the lot sits in the middle.
static func _lot_grid(kind: String, variant: int) -> Kit.Grid:
	var build: Callable
	match kind:
		"house": build = func() -> void: Town.house_lot(variant)
		"domus": build = func() -> void: Town.domus(variant)
		"insula": build = func() -> void: Town.insula(variant)
		"temple": build = func() -> void: Town.temple(variant)
		"garden": build = func() -> void: Town.garden(variant)
		"market": build = func() -> void: Town.market(variant)
		"plaza": build = func() -> void: Town.plaza(variant)
		"tombs": build = func() -> void: Town.tombs(variant, true)
		"plan_wall": build = func() -> void: City.wall(variant)
		"plan_gate": build = func() -> void: City.gate(variant)
		"plan_temple": build = func() -> void: City.temple(variant)
		"plan_theatre": build = func() -> void: City.theatre(variant)
		"plan_amphitheatre": build = func() -> void: City.amphitheatre(variant)
		"plan_baths": build = func() -> void: City.baths(variant)
		"plan_basilica": build = func() -> void: City.basilica(variant)
		"plan_horrea": build = func() -> void: City.horrea(variant)
		"plan_circus": build = func() -> void: City.circus(variant)
		"plan_forum": build = func() -> void: City.forum(variant)
		"street_row": build = func() -> void: City.street_row(variant)
		"street_corner_w": build = func() -> void: City.street_corner_w(variant)
		"street_corner_e": build = func() -> void: City.street_corner_e(variant)
		"street_court": build = func() -> void: City.street_court(variant)
		_: return null
	return _without_ground(Town.grid_of(build), Town.FLOOR)

static func _landmark_grid(name: String) -> Kit.Grid:
	if name.begins_with("verona_"):
		return _without_ground(Verona.grid(name.trim_prefix("verona_")), Verona.GROUND)
	var build: Callable
	match name:
		"arena": return _without_ground(Arena.grid(), Arena.GROUND)
		"colosseum": return _without_ground(Colosseum.grid(), Colosseum.GROUND)
		"forum": build = func() -> void: Town.forum(0)
		"baths": return _without_ground(Landmarks.baths(), Landmarks.GROUND)
		"theatre": return _without_ground(Landmarks.theatre(), Landmarks.GROUND)
		"pantheon": build = func() -> void: Town.pantheon(0)
		"circus": return _without_ground(Landmarks.circus(), Landmarks.GROUND)
		_: return null
	return _without_ground(Town.grid_of(build), Town.FLOOR)

## The grid from layer `floor` up, so the building stands on y = 0.
static func _without_ground(g: Kit.Grid, floor: int) -> Kit.Grid:
	var out := Kit.Grid.new(Vector3i(g.n.x, g.n.y - floor, g.n.z))
	var layers := PackedByteArray()
	for z in g.n.z:
		var layer := g.n.x * g.n.y * z
		layers.append_array(g.g.slice(layer + g.n.x * floor, layer + g.n.x * g.n.y))
	out.g = layers
	return out

static var _small := PackedByteArray()

static func _small_table() -> void:
	if _small.is_empty():
		var small := PackedByteArray()
		small.resize(256)
		for c: int in SMALL:
			small[c] = 1
		_small = small

# Voxels above the floor from which a thin cover counts (beds and paving
# below it do not).
const RAISED := 4

## A coarser grid, `f` voxels to a side and shifted by `pad` voxels in x
## and z: a cell is solid where at least a quarter of it is, or where
## something raised (a roof, an awning) covers three quarters of its plan.
## Where voxels open to the sky cover half its plan, it takes the colour
## most of them have, so roofs stay roofs; otherwise the colour most of it
## has (the lowest colour index on a tie). People and other small things are
## dropped first.
static func _coarse(g: Kit.Grid, f: int, pad: int) -> Kit.Grid:
	var nx := g.n.x
	var ny := g.n.y
	var nz := g.n.z
	var src := g.g
	var small := _small
	var rows := g.rows()
	var out := Kit.Grid.new(Vector3i(ceili((nx + pad) / float(f)), ceili(ny / float(f)), ceili((nz + pad) / float(f))))
	var weight := PackedInt32Array()
	weight.resize(256)
	var sky := PackedInt32Array()
	sky.resize(256)
	var column := PackedByteArray()
	column.resize(f * f)
	# colours met in the cell, to vote among and to clear
	var seen := PackedByteArray()
	for cz in out.n.z:
		var z0 := cz * f - pad
		for cy in out.n.y:
			var y0 := cy * f
			for cx in out.n.x:
				var x0 := cx * f - pad
				var solid := 0
				var open := 0
				var covered := 0
				for z in range(maxi(z0, 0), mini(z0 + f, nz)):
					for y in range(y0, mini(y0 + f, ny)):
						if rows[y + ny * z] == 0:
							continue
						var row := nx * (y + ny * z)
						for x in range(maxi(x0, 0), mini(x0 + f, nx)):
							var c := src[row + x]
							if c == Kit.EMPTY or small[c] == 1:
								continue
							if weight[c] == 0:
								seen.append(c)
							solid += 1
							weight[c] += 1
							var above := src[row + x + nx] if y + 1 < ny else Kit.EMPTY
							if above == Kit.EMPTY or small[above] == 1:
								sky[c] += 1
								open += 1
							if y >= RAISED:
								var k := x - x0 + f * (z - z0)
								if column[k] == 0:
									column[k] = 1
									covered += 1
				if solid == 0:
					continue
				if solid * 4 >= f * f * f or covered * 4 >= f * f * 3:
					var votes := sky if open * 2 >= f * f else weight
					var best := 0
					for c: int in seen:
						if votes[c] > votes[best] or (votes[c] == votes[best] and c < best):
							best = c
					out.put(cx, cy, cz, best)
				for c: int in seen:
					weight[c] = 0
					sky[c] = 0
				seen.clear()
				column.fill(0)
	return out
