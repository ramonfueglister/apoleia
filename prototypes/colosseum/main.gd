extends Node3D
## Colosseum prototype: showcase shots and a draw-call benchmark.
## Arguments after `--`:
##   --scene=hero|lods|bench   what to build (default hero)
##   --mode=naive|nodes_lod|multimesh|chunked   bench: one node per colosseum,
##       one node per LOD and colosseum, one MultiMesh at full detail, or
##       MultiMesh chunks with all LODs
##   --count=10000   bench: number of colosseums on a square grid
##   --view=close|far   bench: city view or the whole map
##   --shot=path.png   save a frame;  --out=path.json   append bench result

const Col := preload("res://colosseum_mesh.gd")
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
	env.ambient_light_color = Color("c4cad2")
	env.ambient_light_energy = 0.42
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
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.05
	sun.light_color = Color("fff1de")
	sun.shadow_blur = 1.0
	sun.shadow_enabled = not args.has("noshadow")
	# Crisp contact shadows under ledges, as in Urbek; no acne on voxel faces.
	sun.directional_shadow_max_distance = 260.0 if args.get("scene", "hero") == "bench" else 70.0
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
