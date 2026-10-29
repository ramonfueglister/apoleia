extends Node3D
## Apoleia landscape: tile terrain (SimCity 2000 meets EU5), camera and weather.
## World units are model kilometres (x east, z south, y up), mapping-v1.
##
## Controls: mouse wheel / pinch zoom (in towards the cursor, out around the
## middle; fully out the view settles over Europe), drag (left or middle
## mouse, two-finger pan) moves the map, WASD or arrow keys pan, +/- zoom.
## The view always looks north and never turns (turning made the map swim).
## Up close it is Urbek's camera: tilted 30 degrees and near-orthographic.
## Weather keys F5-F7 belong to weather_system.gd.
##
## Command line (after --): --view=lon,lat,width start view,
## --snapshot=path.png save one frame and quit, --snapshot-frames=n frames to wait.

const TileTerrain = preload("res://scripts/tile_terrain.gd")
const WeatherSystem = preload("res://scripts/weather/weather_system.gd")
const EARTH_KM := 6371.0088
const MIN_WIDTH := 2.0 # about 8 houses across (Kit 2 scale), Urbek's closest view
const MAX_WIDTH := 4400.0 # all of Europe, Lisbon to Moscow
## Zoomed out, the view settles on Europe (EU5 map): the pull runs between
## these widths (km).
const MAP_FROM := 700.0
const MAP_TO := 3000.0
const EUROPE := Rect2(-12.0, 34.0, 54.0, 26.0) # lon, lat, extent in degrees
const MAP := Rect2(-11.0, 21.0, 57.0, 37.0) # the playable map (the data is padded)
## Field of view: near-orthographic up close like Urbek (vertical walls stay
## parallel), wider over the world map.
const FOV_CLOSE := 9.0
const FOV_FAR := 24.0
const FOV_FROM := 12.0 # view width (km) where the view starts to open up
const FOV_TO := 300.0
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
var _goal_target := Vector2.ZERO
var _goal_width := 360.0
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
			"--snapshot": _snapshot_path = value
			"--snapshot-frames": _snapshot_frames = int(value)
			"--bench": _bench_frames = int(value)
	terrain = TileTerrain.new()
	add_child(terrain)
	if not terrain.load_data():
		get_tree().quit(1)
		return
	_setup_look()
	camera.fov = fov_for_width(start.z)
	camera.near = 0.05
	camera.far = 20000.0
	add_child(camera)
	camera.current = true
	target = lonlat_to_world(start.x, start.y)
	_goal_target = target
	width = clampf(start.z, MIN_WIDTH, MAX_WIDTH)
	_goal_width = width
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
	# A cool sky fill under a warm sun, a third of the light on open ground:
	# shade about half as light as the lit ground and slightly blue, as in
	# Urbek; the fill as red as it is green, so shade on grass turns grey
	# rather than teal (meadow #73af60 in the sun); the filmic
	# curve keeps the lit colours where the terrain palette expects them
	# (AgX washed the map out).
	environment.ambient_light_color = Color("ccccf2")
	environment.ambient_light_energy = 0.85
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
	# Warm sun from the left of the north-up view, a little to the front
	# (west-south-west, 40 degrees up): the faces the camera sees are lit,
	# slopes and roofs turned east fall into shade, shadows reach out to the
	# right beside what casts them.
	sun.rotation_degrees = Vector3(-40.0, -65.0, 0.0)
	sun.light_color = Color("fff0d9")
	sun.light_energy = 2.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 1.0
	# Hard shadows as in Urbek: one map over the view only (see _update_look),
	# no blur and no dithered soft filter, so every house, tree and figure
	# casts a crisp shadow from its foot.
	sun.shadow_blur = 0.0
	# A strong normal offset keeps slopes and ramps free of acne ripples in
	# a map that spans the whole deep view of the far-off camera; the depth
	# bias stays low, so small things keep their shadows.
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 14.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_fade_start = 0.98
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	add_child(sun)

func _update_look(distance: float) -> void:
	terrain.set_light_dir(sun.global_transform.basis.z)
	# The near-orthographic camera stands far back (3.6 view widths); shadows
	# must cover only the view, or the shadow map spreads over kilometres of
	# empty air and shadow edges turn to steps. Godot fits the directional
	# shadow from the camera's near plane, so the near plane moves up to just
	# before the nearest ground in view: the bottom edge of the picture meets
	# the focus plane half a view width (0.485 at 30 degrees) nearer, and ground
	# raised by h there comes h / sin(pitch) nearer still. The far end lies a
	# little past the top of the picture, so the shadows fade out only beyond it.
	var pitch := deg_to_rad(pitch_for_width(width))
	var relief: float = maxf(get_displayed_height_range().max_y - _focus_y, 0.0)
	var aspect := maxf(get_viewport().get_visible_rect().size.aspect(), 0.1)
	var half := width * 0.5 / aspect / tan(maxf(pitch, 0.2))
	camera.near = maxf(0.05, distance - half - width * 0.06 - relief / maxf(sin(pitch), 0.2))
	sun.directional_shadow_max_distance = distance + half + width * 0.26
	# no shadow map beyond 40 km across: the terrain's own shading carries
	# the relief there, and nothing small enough to cast a shadow is drawn
	sun.shadow_enabled = width < 40.0
	# Haze only towards the far edge of the drawn patch.
	var patch_reach: float = terrain.tile_km * TileTerrain.PATCH_N * 0.5
	environment.fog_depth_begin = distance + patch_reach * 0.35
	environment.fog_depth_end = distance + patch_reach * 0.95

# ---------------------------------------------------------------- camera

## 0 at or below `from`, 1 at or above `to`, smooth on a log scale.
static func _zoom_share(w: float, from: float, to: float) -> float:
	var t := clampf((log(w) - log(from)) / (log(to) - log(from)), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func fov_for_width(w: float) -> float:
	return lerpf(FOV_CLOSE, FOV_FAR, _zoom_share(w, FOV_FROM, FOV_TO))

func pitch_for_width(w: float) -> float:
	# 30 degrees up close (SimCity 2000), nearly top-down on the world map.
	var t := clampf((log(w) - log(40.0)) / (log(MAX_WIDTH) - log(40.0)), 0.0, 1.0)
	return lerpf(30.0, 72.0, t * t * (3.0 - 2.0 * t))

## 0 up close, 1 on the world map (log width between MAP_FROM and MAP_TO).
func map_share(w: float) -> float:
	var t := clampf((log(w) - log(MAP_FROM)) / (log(MAP_TO) - log(MAP_FROM)), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _distance() -> float:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	return width / (2.0 * tan(deg_to_rad(fov_for_width(width)) * 0.5) * maxf(aspect, 0.1))

func _view_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch_for_width(width)), 0.0, 0.0))

func _place_camera() -> void:
	var basis := _view_basis()
	var distance := _distance()
	camera.fov = fov_for_width(width)
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

## Keeps the view on the map: anywhere in the data up close; zoomed out the
## allowed centres shrink to Europe, so the whole continent stays in frame.
func _clamp_target(p: Vector2, w: float) -> Vector2:
	var map_min := lonlat_to_world(MAP.position.x, MAP.end.y)
	var all := Rect2(map_min, lonlat_to_world(MAP.end.x, MAP.position.y) - map_min)
	var eu_min := lonlat_to_world(EUROPE.position.x, EUROPE.end.y)
	var eu := Rect2(eu_min, lonlat_to_world(EUROPE.end.x, EUROPE.position.y) - eu_min)
	var s := map_share(w)
	var area := Rect2(all.position.lerp(eu.position, s), all.size.lerp(eu.size, s))
	var aspect := maxf(get_viewport().get_visible_rect().size.aspect(), 0.1)
	var half := Vector2(w, w / aspect) * 0.5 * s
	var lo := area.position + half
	var hi := area.end - half
	return Vector2(
		clampf(p.x, lo.x, hi.x) if lo.x <= hi.x else area.get_center().x,
		clampf(p.y, lo.y, hi.y) if lo.y <= hi.y else area.get_center().y)

func _zoom_at(factor: float, pixel: Vector2) -> void:
	# in towards the cursor, out around the middle: on the tilted view a cursor
	# near the horizon would throw the centre far off the map
	var before := _ground_under(pixel) if factor > 1.0 else _goal_target
	var new_width := clampf(_goal_width / factor, MIN_WIDTH, MAX_WIDTH)
	# keep the ground point under the cursor in place
	var k := new_width / _goal_width
	_goal_target = _clamp_target(before + (_goal_target - before) * k, new_width)
	_goal_width = new_width

func _pan_pixels(delta: Vector2) -> void:
	var scale := width / maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var basis := _view_basis()
	var right := Vector2(basis.x.x, basis.x.z).normalized()
	var down := Vector2(basis.z.x, basis.z.z).normalized()
	var pitch := deg_to_rad(pitch_for_width(width))
	var move := -right * delta.x * scale - down * delta.y * scale / maxf(sin(pitch), 0.3)
	_goal_target = _clamp_target(_goal_target + move, _goal_width)
	target = _clamp_target(target + move, width)

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
	_goal_target = _clamp_target(_goal_target, _goal_width)
	target = _clamp_target(target, width)
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
