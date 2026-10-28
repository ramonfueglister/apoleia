extends Node3D
## Colosseum prototype: showcase shots and a draw-call benchmark.
## Arguments after `--`:
##   --scene=hero|lods|bench   what to build (default hero)
##   --mode=naive|nodes_lod|multimesh|chunked   bench: one node per colosseum,
##       three LOD nodes per colosseum, one MultiMesh at full detail, or
##       MultiMesh chunks with three LODs
##   --count=10000   bench: number of colosseums on a square grid
##   --view=close|far   bench: city view or the whole map
##   --shot=path.png   save a frame;  --out=path.json   append bench result

const Col := preload("res://colosseum_mesh.gd")
const SPACING := 20.0
const CHUNK := 4                         # chunk = CHUNK x CHUNK colosseums
const LOD_RANGES := [0.0, 90.0, 300.0, 6000.0]
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
	meshes = [Col.lod0(), Col.lod1(), Col.lod2()]
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
	env.ambient_light_color = Color("a9bfd8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.95
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
	sun.light_energy = 1.1
	sun.light_color = Color("fff1de")
	sun.shadow_blur = 1.5
	sun.shadow_enabled = not args.has("noshadow")
	sun.directional_shadow_max_distance = 260.0
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

## Urbek-like camera: narrow perspective, 45 degrees around, pitched down.
func _camera(target: Vector3, distance: float, fov := 30.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 8000.0
	add_child(cam)
	var dir := Vector3(1, 0.95, 1).normalized()
	cam.look_at_from_position(target + dir * distance, target)

func _hero() -> void:
	_ground(400.0, Color("7ea24a"))
	var plaza := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(22, 0.12, 19)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("b8a184")
	box.material = pm
	plaza.mesh = box
	add_child(plaza)
	_add(meshes[0], Transform3D.IDENTITY)
	_camera(Vector3(0, 1.2, 0), float(args.get("dist", "42")))
	if args.has("elev"):
		# Straight side view, orthographic: checks proportions.
		var cam: Camera3D = get_children().filter(func(c): return c is Camera3D)[0]
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 12.0
		cam.look_at_from_position(Vector3(0, 3.5, 40), Vector3(0, 3.5, 0))

func _lods() -> void:
	_ground(400.0, Color("7ea24a"))
	for i in 3:
		_add(meshes[i], Transform3D(Basis(), Vector3((i - 1) * 15.0, 0, -(i - 1) * 15.0)))
	_camera(Vector3(0, 1.5, 0), 62.0)
	# Orthographic, so the three LODs are compared at the same size.
	var cam: Camera3D = get_children().filter(func(c): return c is Camera3D)[0]
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 34.0

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
				for lod in 3:
					var mi := MeshInstance3D.new()
					mi.mesh = meshes[lod]
					mi.transform = xf
					mi.visibility_range_begin = LOD_RANGES[lod]
					mi.visibility_range_end = LOD_RANGES[lod + 1]
					if lod == 2:
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
				for lod in 3:
					var mmi := _multimesh(meshes[lod], local)
					mmi.position = centre
					mmi.visibility_range_begin = LOD_RANGES[lod]
					mmi.visibility_range_end = LOD_RANGES[lod + 1]
					# The far LOD casts no shadow: it is too small to matter.
					if lod == 2:
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mmi)
	if args.get("view", "far") == "close":
		_camera(Vector3.ZERO, 120.0)
	else:
		_camera(Vector3.ZERO, extent * 1.25)

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
