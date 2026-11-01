extends "res://scripts/debug/verona_city_check.gd"
## Controlled shadow diagnosis in the actual game; normal renderer required.
## godot --path app --script res://scripts/debug/verona_shadows_check.gd

const DIAGNOSTICS := [
	{"name": "baseline", "normal_bias": 28.0, "shadows": true, "ssao": true},
	{"name": "normal-2", "normal_bias": 2.0, "shadows": true, "ssao": true},
	{"name": "sun-shadows-off", "normal_bias": 28.0, "shadows": false, "ssao": true},
	{"name": "ssao-off", "normal_bias": 28.0, "shadows": true, "ssao": false},
]
const SURFACE_DIAGNOSTICS := [
	{"name": "plain-light", "normal_bias": 28.0, "shadows": false, "ssao": false},
	{"name": "depth-32", "normal_bias": 28.0, "shadows": true, "ssao": true, "depth_16": false},
	{"name": "unshaded", "normal_bias": 28.0, "shadows": false, "ssao": false, "unshaded": true},
	{"name": "flat-albedo", "normal_bias": 28.0, "shadows": false, "ssao": false, "unshaded": true, "textures": false},
]
const EDGE_DIAGNOSTICS := [
	{"name": "baseline", "normal_bias": 28.0, "shadows": true, "ssao": true},
	{"name": "msaa-4", "normal_bias": 28.0, "shadows": true, "ssao": true, "msaa": Viewport.MSAA_4X},
	{"name": "msaa-4-normal-2", "normal_bias": 2.0, "shadows": true, "ssao": true, "msaa": Viewport.MSAA_4X},
]
var surface_shader: Shader
var surface_code: String
var sample_target := TARGET

func view(width_km: float) -> void:
	game.target = sample_target
	game._goal_target = sample_target
	game.width = width_km
	game._goal_width = width_km
	game._focus_y = terrain.ground_y(sample_target)
	game._place_camera()

func capture(config: Dictionary, width_km: float) -> void:
	root.msaa_3d = config.get("msaa", Viewport.MSAA_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(8192, config.get("depth_16", true))
	var code := surface_code
	if config.get("unshaded", false):
		code = code.replace("render_mode cull_disabled, diffuse_burley;", "render_mode unshaded, cull_disabled;")
	if not config.get("textures", true):
		code = code.replace("has_texture ? texture(base_texture, UV).rgb : vec3(1.0)", "vec3(1.0)")
	if surface_shader.code != code:
		surface_shader.code = code
	game.shadows = config.shadows
	game.sun.shadow_normal_bias = config.normal_bias
	game.environment.ssao_enabled = config.ssao
	view(width_km)
	for i in range(60):
		if phase == "perf":
			await RenderingServer.frame_post_draw
		else:
			await process_frame
	var rows: Array = []
	var previous := Time.get_ticks_usec()
	var previous_drawn := Engine.get_frames_drawn()
	for i in range(SAMPLES):
		if phase == "perf":
			await RenderingServer.frame_post_draw
		else:
			await process_frame
		var now := Time.get_ticks_usec()
		var drawn := Engine.get_frames_drawn()
		rows.append({"frame_ms": (now - previous) / 1000.0,
			"rendered_frames": drawn - previous_drawn,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		previous = now
		previous_drawn = drawn
	var result: Dictionary = config.duplicate()
	result.width_km = width_km
	result.target = [sample_target.x, sample_target.y]
	result.depth_bias = game.sun.shadow_bias
	result.blur = game.sun.shadow_blur
	result.terrain_level = terrain.level
	result.sun_shadows_enabled = game.sun.shadow_enabled
	result.camera_transform = str(game.camera.global_transform)
	result.samples = rows
	for key in ["frame_ms", "process_ms", "draws", "primitives"]:
		result[key] = {"median": pct(rows, key, .5), "p95": pct(rows, key, .95)}
	if phase != "perf":
		await RenderingServer.frame_post_draw
		var path: String = output.path_join("%s-%s.png" % [config.name, str(width_km)])
		check(root.get_texture().get_image().save_png(path) == OK, "Screenshot failed: " + path)
		result.screenshot = path
	report.views.append(result)
	save()
	print("VERONA_SHADOW_VIEW ", config.name, " width=", width_km, " frame=", result.frame_ms)

func run() -> void:
	phase = "diagnose"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
	output = ProjectSettings.globalize_path("res://../build/verona-shadows/" + phase)
	DirAccess.make_dir_recursive_absolute(output)
	report.test = "verona_shadows_check"
	report.phase = phase
	root.size = Vector2i(1440, 1000)
	if phase == "perf":
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = Landscape.instantiate()
	root.add_child(game)
	surface_shader = load("res://shaders/city_building.gdshader")
	surface_code = surface_shader.code
	while game._frame < 5:
		await process_frame
	game.set_process_unhandled_input(false)
	terrain = game.terrain
	var clock = game.get_node_or_null("GameClock")
	check(clock != null, "Paused GameClock is required")
	if clock:
		clock.paused = true
		clock._apply()
	report.renderer = RenderingServer.get_video_adapter_name()
	report.window = [1440, 1000]
	report.clock_paused = clock != null and clock.paused
	report.weather = game.weather.describe()
	report.vsync = DisplayServer.window_get_vsync_mode()
	report.shipped_settings = {"msaa": root.msaa_3d, "normal_bias": game.sun.shadow_normal_bias}
	report.atlas_before = digest(terrain.plans._atlas)
	view(12.0)
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var pending := false
		for spec in terrain._series.entries:
			if spec.city == "verona" and not terrain._series.instances.has(spec.id):
				pending = true
		if not pending:
			break
	for spec in terrain._series.entries:
		if spec.city == "verona":
			check(terrain._series.instances.has(spec.id), "Missing model: " + str(spec.id))
	check(DisplayServer.get_name() != "headless", "Normal renderer required")
	if phase in ["final", "clear", "perf"]:
		check(root.msaa_3d == Viewport.MSAA_4X, "Production MSAA must be 4x")
		check(is_equal_approx(game.sun.shadow_normal_bias, 2.0), "Production normal bias must be 2")
		# ABBA ordering makes first-use pipeline/host-load effects visible.
		var widths: Array = [1.5, 5.0, 60.0] if phase == "perf" else WIDTHS
		for width_km: float in widths:
			for index in [0, 1, 1, 0]:
				var config: Dictionary = EDGE_DIAGNOSTICS[0 if index == 0 else 2].duplicate()
				config.name = "baseline" if index == 0 else "final"
				await capture(config, width_km)
		if phase != "perf":
			# Same two configurations in Rome's residential/monument district.
			var site: Dictionary = terrain._series.entries.filter(func(s): return s.id == "domus")[0]
			var r: Array = site.rect
			sample_target = terrain.world_min + (Vector2(r[0], r[1]) + Vector2(r[2], r[3]) * .5) * terrain.plans.parcel_km
			view(12.0)
			for i in range(180):
				await process_frame
			for index in [0, 1]:
				var config: Dictionary = EDGE_DIAGNOSTICS[0 if index == 0 else 2].duplicate()
				config.name = "rome-baseline" if index == 0 else "rome-final"
				await capture(config, 3.0)
	else:
		var cases := SURFACE_DIAGNOSTICS if phase == "surface" else EDGE_DIAGNOSTICS if phase == "edges" else DIAGNOSTICS
		for config: Dictionary in cases:
			await capture(config, 1.5)
	surface_shader.code = surface_code
	report.loader_failures = terrain._series.failures
	check(terrain._series.failures.is_empty(), "Model loader failed")
	report.atlas_after = digest(terrain.plans._atlas)
	check(report.atlas_before == report.atlas_after, "Atlas changed")
	save()
	print("VERONA_SHADOW_DONE ", output, " failures=", report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
