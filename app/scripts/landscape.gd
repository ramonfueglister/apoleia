extends Node3D
## Apoleia landscape: tile terrain (SimCity 2000 meets EU5), camera and weather.
## World units are model kilometres (x east, z south, y up), mapping-v1.
##
## Controls: mouse wheel / pinch zoom towards the cursor, drag (left or middle
## mouse, two-finger pan) moves the map, WASD or arrow keys pan, Q/E turn the
## view by 90 degrees, +/- zoom. Weather keys F5-F7 belong to weather_system.gd.
##
## Command line (after --): --view=lon,lat,width[,turns] start view,
## --snapshot=path.png save one frame and quit, --snapshot-frames=n frames to wait.

const TileTerrain = preload("res://scripts/tile_terrain.gd")
const WeatherSystem = preload("res://scripts/weather/weather_system.gd")
const EARTH_KM := 6371.0088
const MIN_WIDTH := 4.0 # about 17 houses across (Kit 2 scale)
const MAX_WIDTH := 3600.0
const FOV := 24.0
const ZOOM_STEP := 1.18
const SETTLE := 14.0

var terrain: Node3D
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var environment := Environment.new()
var weather: Node3D

## Read by weather_system.gd: the ground point in the middle of the view.
var target := Vector2.ZERO
var width := 360.0
var yaw_turns := 0 # quarter turns away from the default south-east view
var _goal_target := Vector2.ZERO
var _goal_width := 360.0
var _yaw := 45.0
var _focus_y := 0.0
var _dragging := false
var _snapshot_path := ""
var _snapshot_frames := 45
var _bench_frames := 0 # --bench=n: time n frames after the warm-up, print, quit
var _bench_start := 0
var _frame := 0

func _ready() -> void:
	var start := Vector3(12.6, 41.9, 360.0) # Rome and the Tyrrhenian coast
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1) if "=" in arg else ""
		match key:
			"--view":
				var parts := value.split(",")
				if parts.size() >= 3:
					start = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				if parts.size() >= 4:
					yaw_turns = int(parts[3])
			"--snapshot": _snapshot_path = value
			"--snapshot-frames": _snapshot_frames = int(value)
			"--bench": _bench_frames = int(value)
	terrain = TileTerrain.new()
	add_child(terrain)
	if not terrain.load_data():
		get_tree().quit(1)
		return
	_setup_look()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 20000.0
	add_child(camera)
	camera.current = true
	target = lonlat_to_world(start.x, start.y)
	_goal_target = target
	width = clampf(start.z, MIN_WIDTH, MAX_WIDTH)
	_goal_width = width
	_yaw = 45.0 + 90.0 * yaw_turns
	_focus_y = terrain.ground_y(target)
	_place_camera()
	weather = WeatherSystem.new()
	add_child(weather)
	weather.configure(self, camera, sun, environment, Callable(self, "get_displayed_height_range"))

static func lonlat_to_world(lon: float, lat: float) -> Vector2:
	return Vector2(EARTH_KM * cos(deg_to_rad(41.0)) * deg_to_rad(lon - 19.0), -EARTH_KM * deg_to_rad(lat - 41.0))

# ------------------------------------------------------------------ look

func _setup_look() -> void:
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1d5a8c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c4d4e6")
	# low ambient and a filmic curve keep the colours deep and the shade sides
	# dark (AgX and a strong sky fill washed the map out)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 4.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.0
	environment.adjustment_contrast = 1.08
	environment.ssao_enabled = true
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 0.6
	environment.ssao_power = 1.4
	environment.ssao_light_affect = 0.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("a9c6d3")
	environment.fog_density = 1.0
	environment.fog_depth_curve = 1.4
	# Warm sun from the upper left of the default view (west-north-west).
	sun.rotation_degrees = Vector3(-48.0, -106.0, 0.0)
	sun.light_color = Color("fff1de")
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _update_look(distance: float) -> void:
	terrain.set_light_dir(sun.global_transform.basis.z)
	sun.directional_shadow_max_distance = distance * 2.2
	# Haze only towards the far edge of the drawn patch.
	var patch_reach: float = terrain.tile_km * TileTerrain.PATCH_N * 0.5
	environment.fog_depth_begin = distance + patch_reach * 0.35
	environment.fog_depth_end = distance + patch_reach * 0.95

# ---------------------------------------------------------------- camera

func pitch_for_width(w: float) -> float:
	# 30 degrees up close (SimCity 2000), steeper towards the world map.
	var t := clampf((log(w) - log(40.0)) / (log(3500.0) - log(40.0)), 0.0, 1.0)
	return lerpf(30.0, 62.0, t * t * (3.0 - 2.0 * t))

func _distance() -> float:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	return width / (2.0 * tan(deg_to_rad(FOV) * 0.5) * maxf(aspect, 0.1))

func _view_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch_for_width(width)), deg_to_rad(_yaw), 0.0))

func _place_camera() -> void:
	var basis := _view_basis()
	var distance := _distance()
	camera.global_transform = Transform3D(basis, Vector3(target.x, _focus_y, target.y) + basis.z * distance)
	terrain.update_view(target, _footprint_centre(distance), width)
	_update_look(distance)

## Middle of the visible ground: the four screen corner rays meet the focus
## plane (far rays capped), the centre of their hull in the tile frame.
func _footprint_centre(distance: float) -> Vector2:
	var size := get_viewport().get_visible_rect().size
	var low := Vector2(INF, INF)
	var high := -low
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var origin := camera.project_ray_origin(corner)
		var ray := camera.project_ray_normal(corner)
		var t := distance * 3.0
		if ray.y < -0.001: t = minf((_focus_y - origin.y) / ray.y, t)
		var p := origin + ray * t
		low = low.min(Vector2(p.x, p.z))
		high = high.max(Vector2(p.x, p.z))
	return (low + high) * 0.5

func _ground_under(pixel: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	if ray.y > -0.01: ray.y = -0.01
	var t := (_focus_y - origin.y) / ray.y
	var p := origin + ray * t
	return Vector2(p.x, p.z)

func _clamp_target(p: Vector2) -> Vector2:
	return p.clamp(terrain.world_min, terrain.world_min + terrain.world_size)

func _zoom_at(factor: float, pixel: Vector2) -> void:
	var before := _ground_under(pixel)
	var new_width := clampf(_goal_width / factor, MIN_WIDTH, MAX_WIDTH)
	# keep the ground point under the cursor in place
	var k := new_width / _goal_width
	_goal_target = _clamp_target(before + (_goal_target - before) * k)
	_goal_width = new_width

func _pan_pixels(delta: Vector2) -> void:
	var scale := width / maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var basis := _view_basis()
	var right := Vector2(basis.x.x, basis.x.z).normalized()
	var down := Vector2(basis.z.x, basis.z.z).normalized()
	var pitch := deg_to_rad(pitch_for_width(width))
	var move := -right * delta.x * scale - down * delta.y * scale / maxf(sin(pitch), 0.3)
	_goal_target = _clamp_target(_goal_target + move)
	target = _clamp_target(target + move)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / ZOOM_STEP, event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan_pixels(event.relative)
	elif event is InputEventPanGesture:
		_pan_pixels(-event.delta * 12.0)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: yaw_turns -= 1
			KEY_E: yaw_turns += 1
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD: _zoom_at(ZOOM_STEP * ZOOM_STEP, get_viewport().get_visible_rect().size * 0.5)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom_at(1.0 / (ZOOM_STEP * ZOOM_STEP), get_viewport().get_visible_rect().size * 0.5)

func _process(delta: float) -> void:
	var keys := Vector2(
		Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if keys != Vector2.ZERO:
		_pan_pixels(-keys.normalized() * 900.0 * delta)
	var k := 1.0 - exp(-SETTLE * delta)
	target = target.lerp(_goal_target, k)
	width = exp(lerpf(log(width), log(_goal_width), k))
	_yaw = lerpf(_yaw, 45.0 + 90.0 * yaw_turns, k)
	_focus_y = lerpf(_focus_y, terrain.ground_y(target), k)
	_place_camera()
	_frame += 1
	if _bench_frames > 0:
		if _frame == _snapshot_frames:
			_bench_start = Time.get_ticks_usec()
		elif _frame == _snapshot_frames + _bench_frames:
			var ms := (Time.get_ticks_usec() - _bench_start) / 1000.0 / _bench_frames
			print(JSON.stringify({"event": "bench", "frame_ms": ms, "level": terrain.level, "width_km": width}))
			get_tree().quit()
	elif _snapshot_path != "" and _frame == _snapshot_frames:
		RenderingServer.frame_post_draw.connect(_save_snapshot, CONNECT_ONE_SHOT)

func _save_snapshot() -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_snapshot_path.get_base_dir())
	image.save_png(_snapshot_path)
	print(JSON.stringify({"event": "snapshot", "path": _snapshot_path, "level": terrain.level, "tile_km": terrain.tile_km}))
	get_tree().quit()

# ------------------------------------------------- weather height provider

## Displayed height range of the visible ground (world y), for the weather.
func get_displayed_height_range() -> Dictionary:
	var half := Vector2(width, width) * 0.6
	var top: float = terrain.max_y(Rect2(target - half, half * 2.0))
	return {"min_y": 0.0, "max_y": top, "natural_max_y": top}

## Ground height under a world point, for lightning strikes.
func _render_height(p: Vector2) -> float:
	return terrain.ground_y(p)
