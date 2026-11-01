extends Node3D
## Inspect the actual GLB in the project renderer. Drag to orbit; wheel to zoom.
var camera: Camera3D
var azimuth := 42.0
var elevation := 30.0
var framing := 13.8
var target := Vector3(0.5, 3.8, 0.0)
var capture_path := ""

func _ready() -> void:
	get_window().title = "Apoleia · Taverna · 3D-Modell"
	get_window().size = Vector2i(1400, 1400)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().use_taa = true
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		if arg.begins_with("--angle="):
			azimuth = float(arg.trim_prefix("--angle="))
	var model: PackedScene = load("res://assets/buildings/taverna/taverna.glb")
	if model == null:
		push_error("Taverna GLB could not be loaded")
		get_tree().quit(1)
		return
	add_child(model.instantiate())
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("dcd5c5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8e0eb")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_radius = 0.65
	env.ssao_intensity = 1.7
	env.ssao_power = 1.35
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.position = Vector3(-7, 14, 9)
	add_child(key)
	key.look_at(Vector3.ZERO)
	key.light_color = Color("fff5e7")
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 55.0
	key.shadow_blur = 2.0
	key.light_angular_distance = 2.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("d9d0bc")
	floor_mat.roughness = 1.0
	floor_mesh.material = floor_mat
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.035
	add_child(floor_node)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 150.0
	add_child(camera)
	camera.current = true
	_update_camera()
	if capture_path.is_empty():
		var canvas := CanvasLayer.new()
		var help := Label.new()
		help.text = "TAVERNA  /  APOLEIA\nZiehen: drehen · Mausrad: Zoom · R: Ansicht zurücksetzen · Esc: schliessen"
		help.position = Vector2(28, 25)
		help.add_theme_color_override("font_color", Color("4a4135"))
		help.add_theme_font_size_override("font_size", 16)
		canvas.add_child(help)
		add_child(canvas)
	else:
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(capture_path)
		print("TAVERNA_CAPTURE ", capture_path, " error=", error)
		get_tree().quit(0 if error == OK else 1)

func _update_camera() -> void:
	var a := deg_to_rad(azimuth)
	var e := deg_to_rad(elevation)
	camera.position = target + Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e)) * 28.0
	camera.size = framing
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		azimuth -= event.relative.x * 0.3
		elevation = clampf(elevation + event.relative.y * 0.2, 10.0, 80.0)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			framing = maxf(7.0, framing - 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			framing = minf(24.0, framing + 0.6)
		_update_camera()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_R:
			azimuth = 42.0
			elevation = 30.0
			framing = 13.8
			_update_camera()
