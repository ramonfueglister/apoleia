extends Node3D
## Colosseum prototype: showcase shots and a draw-call benchmark.
## Arguments after `--`:
##   --scene=hero|lods|bench|city   what to build (default hero); city is the
##       colosseum in a Roman town of Caesar III buildings
##   --width=m --tx=m --tz=m   hero/city: view width and centre
##   --mode=naive|nodes_lod|multimesh|chunked   bench: one node per colosseum,
##       one node per LOD and colosseum, one MultiMesh at full detail, or
##       MultiMesh chunks with all LODs
##   --count=10000   bench: number of colosseums on a square grid
##   --view=close|far   bench: city view or the whole map
##   --shot=path.png   save a frame;  --out=path.json   append bench result

const Col := preload("res://colosseum_mesh.gd")
const City := preload("res://city_buildings.gd")
const SPACING := 90.0
const CHUNK := 4                         # chunk = CHUNK x CHUNK colosseums
const LOD_RANGES: Array = Col.LOD_RANGES
const WARMUP := 40
const FRAMES := 120

var args := {}
var meshes: Array[ArrayMesh] = []
var material := Col.material()
var frame := 0
var times: Array[float] = []
var cpu_ms: Array[float] = []
var gpu_ms: Array[float] = []
var last_us := 0
var build_ms := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var t0 := Time.get_ticks_usec()
	meshes = Col.lods()
	for m in meshes:
		m.surface_set_material(0, material)
	print("triangles per LOD: ", meshes.map(func(m): return Col.triangles(m)))
	_environment()
	match args.get("scene", "hero"):
		"hero": _hero()
		"lods": _lods()
		"bench": _bench()
		"city": _city()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	last_us = Time.get_ticks_usec()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8aa9b8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Urbek-like light: cool sky fill in the shadows, soft occlusion, a
	# warm sun, colours kept bright rather than filmic-washed.
	env.ambient_light_color = Color("8fa6c8")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.92
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.ssao_enabled = args.get("scene", "hero") != "bench"
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -25, 0) # high, from the south: tops brightest, facade lit, east returns in shade
	sun.light_energy = 1.05
	sun.light_color = Color("fff1de")
	sun.shadow_blur = 0.6
	sun.shadow_opacity = 0.7
	sun.shadow_enabled = not args.has("noshadow")
	# Crisp contact shadows under ledges, as in Urbek; no acne on voxel faces.
	sun.name = "Sun"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	add_child(sun)

func _ground(size: float, colour: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	plane.material = m
	var g := MeshInstance3D.new()
	g.mesh = plane
	add_child(g)

## The game's camera up close: north up (never turned), tilted 30 degrees
## down like Urbek, nearly orthographic. `width` is the ground width across
## the picture.
func _camera(target: Vector3, width: float, fov := 10.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.far = 400000.0
	add_child(cam)
	var distance := width / (2.0 * tan(deg_to_rad(fov) * 0.5))
	# Shadows reach over the whole view, as in the game camera.
	var sun: DirectionalLight3D = get_node_or_null("Sun")
	if sun:
		sun.directional_shadow_max_distance = distance + width * 1.6
	var dir := Basis.from_euler(Vector3(deg_to_rad(-30.0), 0.0, 0.0)).z
	cam.look_at_from_position(target + dir * distance, target)

func _hero() -> void:
	_ground(400.0, Color("7ea24a"))
	_plaza()
	_add(meshes[0], Transform3D.IDENTITY)
	_camera(Vector3(0, 4.0, 0), float(args.get("width", "120")))
	if args.has("elev"):
		# Straight side view, orthographic: checks proportions.
		var cam: Camera3D = get_children().filter(func(c): return c is Camera3D)[0]
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 40.0
		cam.look_at_from_position(Vector3(0, 10.0, 200), Vector3(0, 10.0, 0))

## Test-scene context in Urbek's proportions (storey 3 m, trees 5-8 m,
## people 1.8 m): a paved plaza with a path cross, trees, benches, market
## stalls, people, and a ring of town houses beyond.
func _plaza() -> void:
	var ax := Col.A + 9.0
	var bz := Col.B + 9.0
	var tiles := {Color("d9ccb2"): [], Color("cbbda0"): [], Color("b8a58a"): []}
	var keys := tiles.keys()
	for x in range(-int(ax / 2.0), int(ax / 2.0)):
		for z in range(-int(bz / 2.0), int(bz / 2.0)):
			var key: Color = keys[2] if (absi(x) < 2 or absi(z) < 2) else keys[(x + z) & 1]
			tiles[key].append(Vector3(x * 2.0 + 1.0, 0.1, z * 2.0 + 1.0))
	for colour in keys:
		_boxes(tiles[colour], Vector3(2, 0.2, 2), colour)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Cypresses and round trees alternate in a ring, off the paths.
	for i in 40:
		var t := TAU * (i + 0.5) / 40.0
		var base := Vector3(cos(t) * (Col.A + 5.0), 0.2, sin(t) * (Col.B + 5.0))
		if absf(base.x) < 5.0 or absf(base.z) < 5.0:
			continue
		if i % 2 == 0:
			_cypress(base, rng.randf_range(6.0, 8.0), i)
		else:
			_round_tree(base, rng.randf_range(5.0, 6.5), i)
	# Benches along the paths, stalls at the corners, people everywhere.
	for s in [-1, 1]:
		for k in range(int(Col.A) + 3, int(ax) - 1, 4):
			_seat(Vector3(s * k, 0.2, 2.6), 0.0)
		for k in range(int(Col.B) + 3, int(bz) - 1, 4):
			_seat(Vector3(2.6, 0.2, s * k), PI * 0.5)
	var awnings := [[Color("c8372a"), Color("f2ebdd")], [Color("e0b03a"), Color("f2ebdd")], [Color("3f6fa0"), Color("f2ebdd")]]
	var n := 0
	for corner in [Vector3(-ax + 6, 0.2, -bz + 5), Vector3(ax - 6, 0.2, -bz + 5), Vector3(-ax + 6, 0.2, bz - 5), Vector3(ax - 6, 0.2, bz - 5)]:
		for j in 3:
			_stall(corner + Vector3((j - 1) * 3.0, 0, 0), awnings[n % awnings.size()])
			n += 1
	var robes := [Color("e8e0d0"), Color("b8483a"), Color("6f7f9a"), Color("c9a050"), Color("8a6a50")]
	for i in 160:
		var p := Vector3(rng.randf_range(-ax, ax), 0.2, rng.randf_range(-bz, bz))
		var e := Vector2(p.x / (Col.A + 1.5), p.z / (Col.B + 1.5)).length()
		if e < 1.0:
			continue
		_person(p, robes[i % robes.size()])
	# Town houses beyond the plaza: 2-4 storeys, stepped tile roofs.
	var walls := [Color("eadfc6"), Color("e6c9a8"), Color("d9b48c"), Color("f0e2c8"), Color("cfb8a0")]
	for side in [0, 2, 3]: # no row in front (south), it would hide the facade
		var along := ax * 2.0 if side < 2 else bz * 2.0
		var k := -along * 0.5
		while k < along * 0.5 - 10.0:
			var w := rng.randf_range(9.0, 13.0)
			var d := rng.randf_range(10.0, 13.0)
			var storeys := rng.randi_range(2, 4)
			var c := Vector3(k + w * 0.5, 0, -bz - 8.0 - d * 0.5) if side == 0 else \
				Vector3(k + w * 0.5, 0, bz + 8.0 + d * 0.5) if side == 1 else \
				Vector3(-ax - 8.0 - d * 0.5, 0, k + w * 0.5) if side == 2 else Vector3(ax + 8.0 + d * 0.5, 0, k + w * 0.5)
			var size := Vector2(w, d) if side < 2 else Vector2(d, w)
			_house(c, size, storeys, walls[rng.randi() % walls.size()])
			k += w + rng.randf_range(0.0, 3.0)

## Urbek town house: storeys of 3 m, a window every 3 m, a stepped tile roof
## of 0.5 m layers (about 27 degrees).
func _house(c: Vector3, size: Vector2, storeys: int, wall: Color) -> void:
	var h := storeys * 3.0
	_boxes([c + Vector3(0, h * 0.5, 0)], Vector3(size.x, h, size.y), wall)
	_boxes([c + Vector3(0, 0.3, 0)], Vector3(size.x + 0.2, 0.6, size.y + 0.2), wall.darkened(0.15))
	var windows := []
	for st in storeys:
		var y := st * 3.0 + 1.6
		for x in range(1, int(size.x / 3.0)):
			var px := -size.x * 0.5 + x * size.x / int(size.x / 3.0)
			windows.append(c + Vector3(px, y, size.y * 0.5 + 0.05))
			windows.append(c + Vector3(px, y, -size.y * 0.5 - 0.05))
	_boxes(windows, Vector3(1.0, 1.5, 0.2), Color("3a4560"))
	var windows_z := []
	for st in storeys:
		var y := st * 3.0 + 1.6
		for z in range(1, int(size.y / 3.0)):
			var pz := -size.y * 0.5 + z * size.y / int(size.y / 3.0)
			windows_z.append(c + Vector3(size.x * 0.5 + 0.05, y, pz))
			windows_z.append(c + Vector3(-size.x * 0.5 - 0.05, y, pz))
	_boxes(windows_z, Vector3(0.2, 1.5, 1.0), Color("3a4560"))
	var roof := [Color("c86a50"), Color("b85c44")]
	var layer := 0
	var depth := size.y + 0.6
	while depth > 0.4:
		_boxes([c + Vector3(0, h + 0.25 + layer * 0.5, 0)], Vector3(size.x + 0.6, 0.5, depth), roof[layer % 2])
		depth -= 2.0
		layer += 1

func _person(at: Vector3, robe: Color) -> void:
	_boxes([at + Vector3(0, 0.65, 0)], Vector3(0.5, 1.3, 0.35), robe)
	_boxes([at + Vector3(0, 1.55, 0)], Vector3(0.35, 0.4, 0.35), Color("d9a27a"))

func _cypress(base: Vector3, h: float, i: int) -> void:
	var greens := [Color("3f6b32"), Color("4d7c3a"), Color("5b8b42")]
	_boxes([base + Vector3(0, 0.5, 0)], Vector3(0.5, 1.0, 0.5), Color("6b4a32"))
	var layers := 6
	for k in layers:
		var w := lerpf(2.0, 0.75, float(k) / layers)
		_boxes([base + Vector3(0, 1.0 + (h - 1.0) * (k + 0.5) / layers, 0)], Vector3(w, (h - 1.0) / layers, w), greens[(i + k) % greens.size()])

## Urbek-like deciduous tree: trunk and a crown of stacked, offset cubes.
func _round_tree(base: Vector3, h: float, i: int) -> void:
	var greens := [Color("5f9a3c"), Color("6fae45"), Color("4f8a34")]
	_boxes([base + Vector3(0, h * 0.25, 0)], Vector3(0.5, h * 0.5, 0.5), Color("6b4a32"))
	_boxes([base + Vector3(0, h * 0.72, 0)], Vector3(4.0, h * 0.45, 4.0), greens[i % 3])
	_boxes([base + Vector3(0.5, h * 0.95, -0.5)], Vector3(2.5, h * 0.15, 2.5), greens[(i + 1) % 3])
	_boxes([base + Vector3(-1.0, h * 0.62, 1.0)], Vector3(2.0, h * 0.3, 2.0), greens[(i + 2) % 3])

func _seat(at: Vector3, rot: float) -> void:
	var b := Basis(Vector3.UP, rot)
	_boxes([at + b * Vector3(0, 0.25, 0)], Vector3(1.0, 0.08, 0.3), Color("8a5a36"), rot)
	for x in [-0.4, 0.4]:
		_boxes([at + b * Vector3(x, 0.12, 0)], Vector3(0.1, 0.25, 0.3), Color("4a4a4a"), rot)

## Market stall: counter, posts and a striped awning.
func _stall(at: Vector3, stripes: Array) -> void:
	_boxes([at + Vector3(0, 0.35, 0)], Vector3(1.8, 0.7, 0.8), Color("9a6a40"))
	for x in [-0.85, 0.85]:
		_boxes([at + Vector3(x, 0.9, -0.35)], Vector3(0.1, 1.8, 0.1), Color("6b4a32"))
	for k in 6:
		_boxes([at + Vector3(-0.75 + k * 0.3, 1.85 - 0.04 * (k % 2), 0.05)], Vector3(0.3, 0.12, 1.3), stripes[k % 2])
	for k in 5:
		_boxes([at + Vector3(-0.6 + k * 0.3, 0.78, 0.1)], Vector3(0.2, 0.15, 0.2), [Color("d9553a"), Color("e8c040"), Color("6fae45")][k % 3])

func _boxes(at: Array, size: Vector3, colour: Color, rot := 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	box.material = m
	for p: Vector3 in at:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.position = p
		mi.rotation.y = rot
		add_child(mi)

# ------------------------------------------------------------------ town

const CELL := 8.0
## Street lines in cells of 8 m on each axis, and the plaza round the
## colosseum (cells -7..6 by -6..5); everything between is a town block.
const ROAD_X := [-18, -13, -8, -1, 0, 7, 12, 17]
const ROAD_Z := [-17, -12, -7, -1, 0, 6, 11, 16]
const PLAZA := Rect2i(-7, -6, 14, 12)

var _town_meshes := {}
var _town_xfs := {}
var _rng := RandomNumberGenerator.new()

func _town_mesh(key: String) -> ArrayMesh:
	if not _town_meshes.has(key):
		var m: ArrayMesh
		if key.begins_with("h") and key.substr(1).is_valid_int():
			m = City.house(int(key.substr(1)))
		match key:
			"stall0", "stall1": m = City.stall(int(key.right(1)))
			"paving": m = City.paving()
			"insula0", "insula1", "insula2": m = City.insula(int(key.right(1)))
			"villa": m = City.villa()
			"temple0", "temple1": m = City.temple(int(key.right(1)))
			"market": m = City.rotunda(false)
			"shrine": m = City.rotunda(true)
			"fountain": m = City.fountain()
			"statue0", "statue1": m = City.statue(int(key.right(1)))
			"garden": m = City.garden()
			"cypress": m = City.cypress()
			"tree0", "tree1": m = City.tree(int(key.right(1)))
			"mosaic": m = City.mosaic()
			"street": m = City.street()
			"crossing": m = City.crossing()
		m.surface_set_material(0, material)
		_town_meshes[key] = m
	return _town_meshes[key]

## Places a model; `facing` in degrees turns its front (+z, south) about y:
## 0 south, 90 east, 180 north, 270 west.
func _put(key: String, x: float, z: float, facing := 0.0) -> void:
	_town_mesh(key)
	_town_xfs.get_or_add(key, []).append(Transform3D(Basis(Vector3.UP, deg_to_rad(facing)), Vector3(x, 0, z)))

func _intervals(roads: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in roads.size() - 1:
		if roads[i + 1] - roads[i] > 1:
			out.append(Vector2i(roads[i] + 1, roads[i + 1] - 1))
	return out

func _city() -> void:
	_rng.seed = 11
	_ground(4000.0, Color("7ea24a"))
	_add(meshes[0], Transform3D.IDENTITY)
	# Paving: mosaic on the plaza, streets with kerbs, plain crossings.
	for cz in range(ROAD_Z[0], ROAD_Z[-1] + 1):
		for cx in range(ROAD_X[0], ROAD_X[-1] + 1):
			var x := (cx + 0.5) * CELL
			var z := (cz + 0.5) * CELL
			if PLAZA.has_point(Vector2i(cx, cz)):
				_put("mosaic" if (cx + cz) % 2 == 0 else "paving", x, z)
			elif cx in ROAD_X and cz in ROAD_Z:
				_put("crossing", x, z)
			elif cx in ROAD_X:
				_put("street", x, z)
			elif cz in ROAD_Z:
				_put("street", x, z, 90.0)
	var xs := _intervals(ROAD_X)
	var zs := _intervals(ROAD_Z)
	for iz in zs.size():
		for ix in xs.size():
			var plaza := ix in [2, 3] and iz in [2, 3]
			if plaza:
				continue
			var r := Rect2(xs[ix].x * CELL, zs[iz].x * CELL, (xs[ix].y - xs[ix].x + 1) * CELL, (zs[iz].y - zs[iz].x + 1) * CELL)
			var ring := ix >= 1 and ix <= 4 and iz >= 1 and iz <= 4
			if ring and iz == 1 and ix in [2, 3]:
				_civic(r, "temple%d" % (ix - 2))
			elif ring and ix == 1 and iz == 2:
				_civic(r, "shrine")
			elif ring and ix == 4 and iz == 2:
				_civic(r, "market")
			elif ring and iz == 3 and ix in [1, 4]:
				_park(r)
			elif ring and iz == 4:
				_insulae(r)
			elif ring:
				_terraces(r)
			else:
				var roll := _rng.randf()
				if roll < 0.62:
					_terraces(r)
				elif roll < 0.78:
					_villa(r)
				elif roll < 0.9:
					_insulae(r)
				else:
					_park(r)
	# Market stalls along the plaza's south and north edges.
	for k in range(-5, 5):
		if k in [-1, 0]:
			continue
		_put("stall%d" % (posmod(k, 2)), k * 8.0 + 4.0, PLAZA.end.y * CELL - 4.0, 0.0)
		_put("stall%d" % (posmod(k + 1, 2)), k * 8.0 + 4.0, PLAZA.position.y * CELL + 4.0, 180.0)
	# Townsfolk on the plaza and the streets.
	var robes := [Color("e8e0d0"), Color("b8483a"), Color("6f7f9a"), Color("c9a050"), Color("8a6a50")]
	for i in 260:
		var cx: int = ROAD_X[_rng.randi() % ROAD_X.size()] if i % 2 == 0 else _rng.randi_range(ROAD_X[0], ROAD_X[-1])
		var cz: int = _rng.randi_range(ROAD_Z[0], ROAD_Z[-1]) if i % 2 == 0 else ROAD_Z[_rng.randi() % ROAD_Z.size()]
		var p := Vector3((cx + _rng.randf()) * CELL, 0.1, (cz + _rng.randf()) * CELL)
		if Vector2(p.x / (Col.A + 2.0), p.z / (Col.B + 2.0)).length() > 1.0:
			_person(p, robes[i % robes.size()])
	for key in _town_xfs:
		var list: Array[Transform3D] = []
		list.assign(_town_xfs[key])
		add_child(_multimesh(_town_meshes[key], list))
	var tx := float(args.get("tx", "0"))
	var tz := float(args.get("tz", "0"))
	_camera(Vector3(tx, 4.0, tz), float(args.get("width", "230")))
	print("town: ", _town_xfs.keys().map(func(k): return "%s %d" % [k, _town_xfs[k].size()]))

## Side of the block nearest to p, as a facing angle.
func _facing(r: Rect2, p: Vector2) -> float:
	var d := [r.end.y - p.y, r.end.x - p.x, p.y - r.position.y, p.x - r.position.x]
	var best := 0
	for i in 4:
		if d[i] < d[best]:
			best = i
	return [0.0, 90.0, 180.0, 270.0][best]

## Row houses of mixed sizes along all four streets of a block, touching
## like Caesar III's dense quarters; the yard inside gets gardens and trees.
func _terraces(r: Rect2) -> void:
	var deepest := 0.0
	for spec in City.HOUSE_TYPES:
		deepest = maxf(deepest, spec[1] * 0.5)
	# South and north rows run the full width, east and west rows fill in.
	for side in 4:
		var along := r.size.x if side % 2 == 0 else r.size.y - 2.0 * deepest
		var start := r.position.x if side % 2 == 0 else r.position.y + deepest
		var cursor := 0.0
		while true:
			var t := _rng.randi_range(0, City.HOUSE_TYPES.size() - 1)
			var spec: Array = City.HOUSE_TYPES[t]
			var wm: float = spec[0] * 0.5
			var dm: float = spec[1] * 0.5
			if cursor + wm > along + 0.01:
				break
			var a := start + cursor + wm * 0.5
			match side:
				0: _put("h%d" % t, a, r.end.y - dm * 0.5, 0.0)
				1: _put("h%d" % t, r.end.x - dm * 0.5, a, 90.0)
				2: _put("h%d" % t, a, r.position.y + dm * 0.5, 180.0)
				3: _put("h%d" % t, r.position.x + dm * 0.5, a, 270.0)
			cursor += wm
	var yard := r.grow(-deepest)
	if yard.size.x > 6.0 and yard.size.y > 6.0:
		var c := yard.get_center()
		_put("garden", c.x, c.y)
		_put("tree%d" % _rng.randi_range(0, 1), c.x + yard.size.x * 0.3, c.y)
		_put("cypress", c.x - yard.size.x * 0.3, c.y)

## Small houses on lots of about 11 m, each facing its nearest street; the
## inner lots are gardens with trees.
func _houses(r: Rect2) -> void:
	var nx := maxi(1, floori(r.size.x / 10.5))
	var nz := maxi(1, floori(r.size.y / 10.5))
	for j in nz:
		for i in nx:
			var c := r.position + Vector2((i + 0.5) * r.size.x / nx, (j + 0.5) * r.size.y / nz)
			var inner := i > 0 and i < nx - 1 and j > 0 and j < nz - 1
			if inner:
				_put("garden", c.x, c.y)
				_put("tree%d" % (i % 2), c.x + 3.0, c.y - 3.0)
				continue
			_put("h%d" % _rng.randi_range(0, City.HOUSE_TYPES.size() - 1), c.x, c.y, _facing(r, c))
			if _rng.randf() < 0.35:
				_put("cypress", c.x + 4.6, c.y + 4.6)

## Insulae shoulder to shoulder on the south and north streets, row houses
## on the side streets between them.
func _insulae(r: Rect2) -> void:
	var n := maxi(1, floori(r.size.x / 12.5))
	for i in n:
		var x := r.position.x + (i + 0.5) * r.size.x / n
		_put("insula%d" % _rng.randi_range(0, 2), x, r.end.y - 8.0, 0.0)
		_put("insula%d" % _rng.randi_range(0, 2), x, r.position.y + 8.0, 180.0)
	var gap := r.size.y - 32.0
	if gap >= 6.0:
		var c := r.get_center()
		_put("h%d" % _rng.randi_range(0, City.HOUSE_TYPES.size() - 1), r.position.x + 5.0, c.y, 270.0)
		_put("h%d" % _rng.randi_range(0, City.HOUSE_TYPES.size() - 1), r.end.x - 5.0, c.y, 90.0)

func _villa(r: Rect2) -> void:
	var c := r.get_center()
	_put("villa", c.x, c.y, _facing(r, c + Vector2(0, 1)))
	for k in range(int(r.position.x) + 2, int(r.end.x) - 1, 4):
		_put("cypress", k, r.position.y + 2.0)
		_put("cypress", k, r.end.y - 2.0)
	_put("tree0", r.position.x + 3.0, c.y)
	_put("tree1", r.end.x - 3.0, c.y)

func _park(r: Rect2) -> void:
	var c := r.get_center()
	for d in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
		_put("garden", c.x + d.x, c.y + d.y)
	_put("fountain", c.x, c.y)
	for k in 12:
		var t := TAU * (k + 0.5) / 12.0
		var p := c + Vector2(cos(t) * (r.size.x * 0.5 - 3.0), sin(t) * (r.size.y * 0.5 - 3.0))
		_put("tree%d" % (k % 2) if k % 3 else "cypress", p.x, p.y)

## A civic block: mosaic paving, the building facing the colosseum, statues
## on both sides of its front, cypress rows along the side streets.
func _civic(r: Rect2, key: String) -> void:
	for z in range(int(r.position.y / CELL), int(r.end.y / CELL)):
		for x in range(int(r.position.x / CELL), int(r.end.x / CELL)):
			_put("mosaic", (x + 0.5) * CELL, (z + 0.5) * CELL)
	var c := r.get_center()
	# Face the colosseum: the block side nearest to it.
	var face := _facing(r, c - c.normalized() * 1000.0)
	_put(key, c.x, c.y, face)
	var front := Vector2(sin(deg_to_rad(face)), cos(deg_to_rad(face)))
	var side := Vector2(front.y, -front.x)
	var half := 12.0
	for s in [-1.0, 1.0]:
		var p: Vector2 = c + front * half + side * s * 9.0
		_put("statue%d" % int(s > 0), p.x, p.y, face)
		var f: Vector2 = c + front * half + side * s * 4.5
		if key in ["market", "shrine"]:
			_put("fountain", f.x, f.y)
	for k in range(int(r.position.y) + 3, int(r.end.y) - 2, 5):
		_put("cypress", r.position.x + 2.0, k)
		_put("cypress", r.end.x - 2.0, k)
	if key == "market":
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			_put("stall%d" % (k % 2), c.x + cos(a) * 12.5, c.y + sin(a) * 12.5, 90.0 - rad_to_deg(a))

func _lods() -> void:
	_ground(400.0, Color("7ea24a"))
	var half := (meshes.size() - 1) * 0.5
	for i in meshes.size():
		_add(meshes[i], Transform3D(Basis(), Vector3((i - half) * 85.0, 0, 0)))
	_camera(Vector3(0, 4.0, 0), 360.0)
	# Orthographic, so the three LODs are compared at the same size.
	var cam: Camera3D = get_children().filter(func(c): return c is Camera3D)[0]
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 90.0 * meshes.size()

func _add(mesh: Mesh, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	add_child(mi)

func _grid(count: int) -> Array[Transform3D]:
	var side := int(ceil(sqrt(count)))
	var out: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in count:
		var p := Vector3((i % side - side * 0.5) * SPACING, 0, (i / side - side * 0.5) * SPACING)
		out.append(Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5), p))
	return out

func _multimesh(mesh: Mesh, xfs: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi

func _bench() -> void:
	var count := int(args.get("count", "10000"))
	var xfs := _grid(count)
	var extent := sqrt(count) * SPACING
	_ground(extent + 200.0, Color("7ea24a"))
	match args.get("mode", "chunked"):
		"naive":
			for xf in xfs:
				_add(meshes[0], xf)
		"nodes_lod":
			# One node per LOD and colosseum, switched by visibility range.
			for xf in xfs:
				for lod in meshes.size():
					var mi := MeshInstance3D.new()
					mi.mesh = meshes[lod]
					mi.transform = xf
					mi.visibility_range_begin = LOD_RANGES[lod]
					mi.visibility_range_end = LOD_RANGES[lod + 1]
					if lod == meshes.size() - 1:
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mi)
		"multimesh":
			add_child(_multimesh(meshes[0], xfs))
		"chunked":
			var chunks := {}
			for xf in xfs:
				var key := Vector2i(floori(xf.origin.x / (SPACING * CHUNK)), floori(xf.origin.z / (SPACING * CHUNK)))
				chunks.get_or_add(key, [] as Array[Transform3D]).append(xf)
			for key in chunks:
				var list: Array[Transform3D] = chunks[key]
				var centre := Vector3((key.x + 0.5) * SPACING * CHUNK, 0, (key.y + 0.5) * SPACING * CHUNK)
				var local: Array[Transform3D] = []
				for xf in list:
					local.append(Transform3D(xf.basis, xf.origin - centre))
				for lod in meshes.size():
					var mmi := _multimesh(meshes[lod], local)
					mmi.position = centre
					mmi.visibility_range_begin = LOD_RANGES[lod]
					mmi.visibility_range_end = LOD_RANGES[lod + 1]
					# The far LOD casts no shadow: it is too small to matter.
					if lod == meshes.size() - 1:
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mmi)
	if args.get("view", "far") == "close":
		_camera(Vector3.ZERO, 360.0)
	else:
		_camera(Vector3.ZERO, extent * 1.6)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - last_us) / 1000.0
	last_us = now
	frame += 1
	if frame > WARMUP:
		times.append(dt)
		var vp := get_viewport().get_viewport_rid()
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if frame == WARMUP + FRAMES:
		_finish()

func _median(a: Array[float]) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]

func _finish() -> void:
	var info := {
		"scene": args.get("scene", "hero"), "mode": args.get("mode", ""), "count": int(args.get("count", "0")),
		"view": args.get("view", ""),
		"frame_ms": snappedf(_median(times), 0.01),
		"render_cpu_ms": snappedf(_median(cpu_ms), 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"nodes": get_tree().get_node_count(),
		"build_ms": snappedf(build_ms, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
	}
	print(JSON.stringify(info))
	if args.has("out"):
		var f := FileAccess.open(args["out"], FileAccess.READ_WRITE if FileAccess.file_exists(args["out"]) else FileAccess.WRITE)
		f.seek_end()
		f.store_line(JSON.stringify(info))
	if args.has("shot"):
		get_viewport().get_texture().get_image().save_png(args["shot"])
	get_tree().quit()
