extends Node3D
## Apoleia landscape: tile terrain (SimCity 2000 meets EU5), camera and weather.
## World units are model kilometres (x east, z south, y up), mapping-v1.
##
## Controls: mouse wheel / pinch zoom (in towards the cursor, out around the
## middle; fully out the whole Kit 1 map is in view), drag (left or middle
## mouse, two-finger pan) moves the map, WASD or arrow keys pan, +/- zoom.
## Up close it is Urbek's camera: turned 45 degrees to look north-east
## along the tile diagonal, tilted 35 degrees and near-orthographic, so every
## house shows two sides and its roof. Zooming out it turns back to north up
## (between YAW_FROM and YAW_TO) and looks down ever more steeply.
## Weather keys F5-F7 belong to weather_system.gd, 1-3 (the build tools) to
## build_menu.gd, Space, [ ], F8 and F9 (pause, speed, save, load) to
## sim/game_clock.gd; a click on a market square opens its window
## (sim/market_window.gd).
##
## Command line (after --): --view=lon,lat,width start view,
## --snapshot=path.png save one frame and quit, --snapshot-frames=n frames to wait,
## --tour=result.json fly the benchmark tour and save its frame times
## (tour_bench.gd), --tour-passes=n how often, --tour-hide=trees,houses,
## terrain,landmarks,people,shadows without those (what each costs;
## people-draw, people-process: half of people).

const TileTerrain = preload("res://scripts/tile_terrain.gd")
const TourBench = preload("res://scripts/tour_bench.gd")
const WeatherSystem = preload("res://scripts/weather/weather_system.gd")
const PeopleDots = preload("res://scripts/sim/people_dots.gd")
const BuildMenu = preload("res://scripts/build_menu.gd")
const GameClock = preload("res://scripts/sim/game_clock.gd")
const MarketWindow = preload("res://scripts/sim/market_window.gd")
const EARTH_KM := 6371.0088
const MIN_WIDTH := 1.0 # about 4 houses across (Kit 2 scale), people readable as figures
## The whole Kit 1 map in a 16:9 window, from Ireland to the Caspian and
## from the Baltic to Upper Egypt (4800 x 4100 km); max_width() holds it a
## little narrower where the picture would reach past the terrain data.
const MAX_WIDTH := 8000.0
## Zoomed out, the view settles on the Kit 1 map: the pull runs between
## these widths (km).
const MAP_FROM := 700.0
const MAP_TO := 3000.0
## The Kit 1 map (data/region.json), lon, lat, extent in degrees; the data
## is padded around it. Zoomed out it was held to Europe (34-60 N), which cut
## off Africa, Egypt and the Levant.
const MAP := Rect2(-11.0, 21.0, 57.0, 37.0)
const PITCH_TO := 4400.0 # view width (km) from where the view looks down steepest
## Up close the view looks north-east along the tile diagonal as in Urbek and
## Islanders (a view straight north showed every house as a flat front, Ramon
## 29.10.2026); from YAW_FROM it turns back towards north up, reached at
## YAW_TO, so the map of the empire stays north up.
const YAW_CLOSE := 45.0
const YAW_FROM := 40.0
const YAW_TO := 700.0
## Tilt up close: Urbek's square tiles show as diamonds about 0.58 as tall as
## wide, a view about 35 degrees down (measured on its Steam screenshots).
const PITCH_CLOSE := 35.0
## Field of view: near-orthographic up close like Urbek (vertical walls stay
## parallel), wider over the world map.
const FOV_CLOSE := 9.0
const FOV_FAR := 24.0
const FOV_FROM := 12.0 # view width (km) where the view starts to open up
const FOV_TO := 300.0
const ZOOM_STEP := 1.18
const SETTLE := 14.0
## Tilt-shift blur: full up to TILT_FULL km view width, gone from TILT_TO.
## Only a hint at the edges: Urbek has next to none, and stronger it
## smeared the top and bottom of the picture (s2 against Urbek).
const TILT_AMOUNT := 0.03
const TILT_FULL := 6.0
const TILT_TO := 40.0
## Share of the depth from the focus to the top / bottom edge of the
## picture that stays sharp.
const TILT_SHARP := 0.55

var terrain: Node3D
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var environment := Environment.new()
## Miniature look up close (tilt-shift, as in Islanders and Urbek): the
## middle band of the picture sharp, the top and bottom edges softly blurred.
var lens := CameraAttributesPractical.new()
var weather: Node3D
var people: Node3D # the Kit 2 people (sim/people_dots.gd), null when not built
## The sun casts shadows up to 40 km across (the tour can switch them off).
var shadows := true

## Read by weather_system.gd: the ground point in the middle of the view.
var target := Vector2.ZERO
var width := 360.0
var _goal_target := Vector2.ZERO
var _goal_width := 360.0
var _focus_y := 0.0
var _footprint_size := Vector2.ZERO # of the visible ground (km), _footprint_centre
var _dragging := false
var _snapshot_path := ""
var _snapshot_frames := 45
var _bench_frames := 0 # --bench=n: time n frames after the warm-up, print, quit
var _bench_start := 0
var _frame := 0
var _views: Array = [] # --views=lon,lat,w;lon,lat,w: one shot of each into the --snapshot folder
var _tour := ""
var _tour_passes := 2
var _tour_hide := PackedStringArray()
var _view_index := 0

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
			"--tour":
				_tour = value
				var first := TourBench.view_at(0)
				start = first
			"--tour-passes": _tour_passes = int(value)
			"--tour-hide": _tour_hide = value.split(",", false)
			"--views":
				for v in value.split(";"):
					var q := v.split(",")
					_views.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
				start = _views[0]
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
	width = clampf(start.z, MIN_WIDTH, max_width())
	_goal_width = width
	_focus_y = terrain.ground_y(target)
	_place_camera()
	weather = WeatherSystem.new()
	add_child(weather)
	weather.configure(self, camera, sun, environment, Callable(self, "get_displayed_height_range"))
	# Kit 2 people as dots (Rust GDExtension); off when it is not built
	var dots := PeopleDots.new()
	add_child(dots)
	if dots.setup(terrain):
		people = dots
		var clock := GameClock.new()
		add_child(clock)
		clock.setup(dots)
		var markets := MarketWindow.new()
		add_child(markets)
		markets.setup(self, dots.people)
	else:
		dots.queue_free()
	# after the people: its clicks on the map come before theirs
	var build := BuildMenu.new()
	add_child(build)
	build.setup(self, people.people if people != null else null)
	if _tour != "":
		var tour := TourBench.new()
		tour.landscape = self
		tour.out_path = _tour
		tour.passes = _tour_passes
		tour.hide = _tour_hide
		tour.warmup = _snapshot_frames
		add_child(tour)

static func lonlat_to_world(lon: float, lat: float) -> Vector2:
	return Vector2(EARTH_KM * cos(deg_to_rad(41.0)) * deg_to_rad(lon - 19.0), -EARTH_KM * deg_to_rad(lat - 41.0))

# ------------------------------------------------------------------ look

func _setup_look() -> void:
	var world := WorldEnvironment.new()
	world.environment = environment
	world.camera_attributes = lens
	lens.auto_exposure_enabled = false
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, false)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
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
	# Islanders and Urbek shade in a clear cool blue: the fill a little bluer
	# and weaker than the old grey #ccccf2 at 0.85, the sun a little stronger,
	# so lit ground keeps about its palette tone and the shadows fall from
	# about a third to about a fifth of it, bluish rather than grey (round 1
	# at 0.75 still read pale grey).
	environment.ambient_light_color = Color("bcc5ea")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 4.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.08
	environment.ssao_enabled = true
	# contact shade where houses, trees and walls meet the ground; the radius
	# follows the zoom (_update_look), a fixed 0.6 km was wider than a block
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.1
	environment.ssao_power = 1.4
	environment.ssao_light_affect = 0.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("a9c6d3")
	environment.fog_density = 1.0
	environment.fog_depth_curve = 1.4
	# Warm sun from the left of the close view, a little to the front: turned
	# with the camera (YAW_CLOSE), so from the west-north-west, 40 degrees
	# up. The faces the camera sees are lit, slopes and roofs turned away fall
	# into shade, shadows reach out to the right beside what casts them.
	sun.rotation_degrees = Vector3(-40.0, -65.0 - YAW_CLOSE, 0.0)
	sun.light_color = Color("fff0d9")
	sun.light_energy = 2.35
	sun.shadow_enabled = true
	sun.shadow_opacity = 1.0
	# One map over the view only (see _update_look). Urbek's shadows have a
	# soft edge a few pixels wide (its Steam screenshots, the trees on the
	# lawns), not the crisp edge of before: a light PCF blur.
	sun.shadow_blur = 1.5
	# A strong normal offset keeps slopes and ramps free of acne ripples in
	# a map that spans the whole deep view of the far-off camera (counted in
	# texels of the 8192 map: about 3.5 % of a 1 km view); the depth bias
	# stays low, so small things keep their shadows.
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 28.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_fade_start = 0.98
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	add_child(sun)
	_add_vignette()

## A soft darkening towards the corners of the picture, drawn under the HUD,
## as in Islanders: it holds the eye on the middle of the miniature.
func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/vignette.gdshader")
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)

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
	# (set only when it changes: each set re-notifies everything the light
	# touches)
	if sun.shadow_enabled != (shadows and width < 40.0):
		sun.shadow_enabled = shadows and width < 40.0
	# Haze only towards the far edge of the drawn patch.
	var patch_reach: float = terrain.tile_km * TileTerrain.PATCH_N * 0.5
	environment.fog_depth_begin = distance + patch_reach * 0.35
	environment.fog_depth_end = distance + patch_reach * 0.95
	environment.ssao_radius = clampf(width * 0.02, 0.03, 0.6)
	_update_tilt_shift(distance, pitch)

## Depth along the view of the ground at the top and bottom edges of the
## picture (on the focus plane); the blur grows from a sharp band around the
## focus towards both edges, like a tilt-shift photo of a model.
func _update_tilt_shift(distance: float, pitch: float) -> void:
	var amount := TILT_AMOUNT * (1.0 - _zoom_share(width, TILT_FULL, TILT_TO))
	var on := amount > 0.002
	if lens.dof_blur_far_enabled != on:
		lens.dof_blur_far_enabled = on
		lens.dof_blur_near_enabled = on
	if not on:
		return
	var f := deg_to_rad(camera.fov) * 0.5
	var top := distance * sin(pitch) * cos(f) / sin(maxf(pitch - f, 0.05))
	var bottom := distance * sin(pitch) * cos(f) / sin(pitch + f)
	lens.dof_blur_amount = amount
	lens.dof_blur_far_distance = distance + (top - distance) * TILT_SHARP
	lens.dof_blur_far_transition = (top - distance) * (1.0 - TILT_SHARP)
	lens.dof_blur_near_distance = distance - (distance - bottom) * TILT_SHARP
	lens.dof_blur_near_transition = (distance - bottom) * (1.0 - TILT_SHARP)

# ---------------------------------------------------------------- camera

## 0 at or below `from`, 1 at or above `to`, smooth on a log scale.
static func _zoom_share(w: float, from: float, to: float) -> float:
	var t := clampf((log(w) - log(from)) / (log(to) - log(from)), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func fov_for_width(w: float) -> float:
	return lerpf(FOV_CLOSE, FOV_FAR, _zoom_share(w, FOV_FROM, FOV_TO))

func pitch_for_width(w: float) -> float:
	# PITCH_CLOSE up close (Urbek), nearly top-down on the world map.
	var t := clampf((log(w) - log(40.0)) / (log(PITCH_TO) - log(40.0)), 0.0, 1.0)
	return lerpf(PITCH_CLOSE, 72.0, t * t * (3.0 - 2.0 * t))

## Degrees the view is turned from north towards east (YAW_CLOSE up close,
## 0 on the map).
func yaw_for_width(w: float) -> float:
	return YAW_CLOSE * (1.0 - _zoom_share(w, YAW_FROM, YAW_TO))

## 0 up close, 1 on the world map (log width between MAP_FROM and MAP_TO).
func map_share(w: float) -> float:
	var t := clampf((log(w) - log(MAP_FROM)) / (log(MAP_TO) - log(MAP_FROM)), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _distance() -> float:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	return width / (2.0 * tan(deg_to_rad(fov_for_width(width)) * 0.5) * maxf(aspect, 0.1))

func _view_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch_for_width(width)), deg_to_rad(-yaw_for_width(width)), 0.0))

func _place_camera() -> void:
	var basis := _view_basis()
	var distance := _distance()
	camera.fov = fov_for_width(width)
	camera.global_transform = Transform3D(basis, Vector3(target.x, _focus_y, target.y) + basis.z * distance)
	var centre := _footprint_centre(distance)
	var spans := _drawn_spans()
	terrain.update_view(centre, width, spans.x, spans.y)
	_update_look(distance)

## Ground (km) to cover around the middle of the view: x by the terrain,
## the visible ground, a margin, and how far beyond its edge high ground can
## still rise into the picture or cast a shadow into it; y by the trees and
## houses, whose instances all cost vertex work, visible or not: the visible
## ground and high ground as for the terrain, and twice the tallest prop
## each side (a tall house just below the picture reaches up into it at the
## 30 degree view, 1.7 times its height, and its shadow as far).
func _drawn_spans() -> Vector2:
	var around := Rect2(target - Vector2(width, width) * 2.0, Vector2(width, width) * 4.0)
	var relief := maxf(terrain.max_y(around) - _focus_y, 0.0)
	var top := deg_to_rad(pitch_for_width(width) - fov_for_width(width) * 0.5)
	var seen := maxf(_footprint_size.x, _footprint_size.y)
	var rises := 2.0 * relief / tan(maxf(top, 0.15))
	return Vector2(seen * 1.25 + rises, seen + rises + 4.0 * terrain.prop_height_km)

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
	_footprint_size = high - low
	return (low + high) * 0.5

func _ground_under(pixel: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	if ray.y > -0.01: ray.y = -0.01
	var t := (_focus_y - origin.y) / ray.y
	var p := origin + ray * t
	return Vector2(p.x, p.z)

## Keeps the view on the Kit 1 map: anywhere on it up close; zoomed out the
## allowed centres shrink, so the map stays in frame, and once the view is
## wider than the map it sits in the middle. Whatever the zoom, the picture
## stays on the terrain data (18-61 N, 44 W-79 E): beyond its edge there is
## no ground, only a straight cut (it showed through Scandinavia at 61 N).
func _clamp_target(p: Vector2, w: float) -> Vector2:
	var map_min := lonlat_to_world(MAP.position.x, MAP.end.y)
	var area := Rect2(map_min, lonlat_to_world(MAP.end.x, MAP.position.y) - map_min)
	var s := map_share(w)
	var reach := _reach(w)
	var lo := area.position + Vector2(reach.z, reach.x) * s
	var hi := area.end - Vector2(reach.z, reach.y) * s
	var c := Vector2(
		clampf(p.x, lo.x, hi.x) if lo.x <= hi.x else (lo.x + hi.x) * 0.5,
		clampf(p.y, lo.y, hi.y) if lo.y <= hi.y else (lo.y + hi.y) * 0.5)
	var data := Rect2(terrain.world_min, terrain.world_size)
	lo = data.position + Vector2(reach.z, reach.x)
	hi = data.end - Vector2(reach.z, reach.y)
	return Vector2(
		clampf(c.x, lo.x, hi.x) if lo.x <= hi.x else data.get_center().x,
		clampf(c.y, lo.y, hi.y) if lo.y <= hi.y else data.get_center().y)

## How far the visible ground reaches from the middle of the view at width w
## (km, on the focus plane): x to the top edge of the picture (north), y to
## the bottom edge, z sideways at the top corners (the widest part).
func _reach(w: float) -> Vector3:
	var p := deg_to_rad(pitch_for_width(w))
	var f := deg_to_rad(fov_for_width(w)) * 0.5
	var aspect := maxf(get_viewport().get_visible_rect().size.aspect(), 0.1)
	var d := w / (2.0 * tan(f) * aspect)
	var h := d * sin(p)
	var back := d * cos(p)
	var top := maxf(p - f, 0.05)
	return Vector3(h / tan(top) - back, back - h / tan(p + f), h * cos(f) / sin(top) * tan(f) * aspect)

## The widest view whose picture still fits on the terrain data from top to
## bottom: MAX_WIDTH in a 16:9 window would reach past the data's north edge
## (about 7800 km there, 7000 km at 16:10). Pitch and field of view no longer
## change at these widths, so the reach grows in step with the width.
func max_width() -> float:
	var reach := _reach(MAX_WIDTH)
	return minf(MAX_WIDTH, MAX_WIDTH * 0.97 * terrain.world_size.y / (reach.x + reach.y))

func _zoom_at(factor: float, pixel: Vector2) -> void:
	# in towards the cursor, out around the middle: on the tilted view a cursor
	# near the horizon would throw the centre far off the map
	var before := _ground_under(pixel) if factor > 1.0 else _goal_target
	var new_width := clampf(_goal_width / factor, MIN_WIDTH, max_width())
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
	if keys != Vector2.ZERO and not (get_viewport().gui_get_focus_owner() is LineEdit): # typing in the tables' search
		_pan_pixels(-keys.normalized() * 900.0 * delta)
	var k := 1.0 - exp(-SETTLE * delta)
	_goal_width = minf(_goal_width, max_width()) # the window may have changed shape
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
			print(JSON.stringify({"event": "bench", "frame_ms": ms, "level": terrain.level, "width_km": width,
				"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}))
			get_tree().quit()
	elif _snapshot_path != "" and _frame == _snapshot_frames:
		RenderingServer.frame_post_draw.connect(_save_snapshot, CONNECT_ONE_SHOT)

func _save_snapshot() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _snapshot_path
	if not _views.is_empty():
		path = _snapshot_path.path_join("v%d-w%d.png" % [_view_index + 1, int(_views[_view_index].z)])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)
	print(JSON.stringify({"event": "snapshot", "path": path, "level": terrain.level, "tile_km": terrain.tile_km}))
	_view_index += 1
	if _view_index < _views.size():
		var v: Vector3 = _views[_view_index]
		target = lonlat_to_world(v.x, v.y)
		_goal_target = target
		width = clampf(v.z, MIN_WIDTH, max_width())
		_goal_width = width
		_focus_y = terrain.ground_y(target)
		_frame = 0
		return
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
