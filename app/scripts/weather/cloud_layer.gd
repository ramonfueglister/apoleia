extends Node3D
## Own bounded density volume. Fixed world weather and 3D density are shared
## across zooms. The top proxy plane covers every viewport aspect ratio.
const CLOUD_SHADER = preload("res://shaders/cloud_layer.gdshader")
const WEATHER_TEXTURE = preload("res://assets/weather/cloud_weather.png")
const STRUCTURE_TEXTURE = preload("res://assets/weather/cloud_structure.png")
const NOISE_PATH = "res://assets/weather/cloud_noise_scale192.rgba8"

@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply_enabled()
# Own decorative world-space animation speed, not a physical wind model.
@export_range(0.0, 0.1, 0.0001) var drift_speed: float = 0.04
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
@export var cloud_base_height: float = 7.2
@export var cloud_world_margin_fraction: float = 0.15
@export var cast_cloud_shadows: bool = false
@export var cloud_clearance: float = 1.1
@export var cloud_volume_height: float = 38.0
var _volume_bottom: float = 7.2
var _noise_texture: ImageTexture3D
var _moment_textures: Array[ImageTexture3D] = []
var _height_range_provider: Callable
var _altitude_floor: float = 7.2
var _last_height_range: Dictionary = {}
var landscape_camera: Camera3D
var landscape_sun: DirectionalLight3D
var world_bounds: Rect2
var configured := false
var _elapsed := 0.0
var _capture_time_locked := false
var _layers: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _plane_mesh: PlaneMesh
var _sun_direction := Vector3(-0.45, 0.78, 0.43)

func configure(world_rect: Rect2, camera: Camera3D = null, options: Dictionary = {}) -> void:
	world_bounds = world_rect
	landscape_camera = camera if camera != null else _find_camera()
	landscape_sun = options.get("sun_light") as DirectionalLight3D
	_altitude_floor = float(options.get("altitude", _altitude_floor))
	cloud_volume_height = maxf(float(options.get("volume_height", cloud_volume_height)), 0.1)
	cloud_base_height = _altitude_floor
	cloud_clearance = maxf(float(options.get("clearance", cloud_clearance)), 0.0)
	var provider: Variant = options.get("height_range_provider", Callable())
	if typeof(provider) != TYPE_CALLABLE:
		push_error("Cloud height_range_provider must be a Callable")
		return
	_height_range_provider = provider
	if str(options.get("altitude_unit", options.get("altitudeunit", "godot_world_y"))) != "godot_world_y":
		push_error("Cloud altitude contract requires godot_world_y")
		return
	drift_speed = float(options.get("drift_speed", drift_speed))
	opacity = float(options.get("opacity", opacity))
	cast_cloud_shadows = bool(options.get("shadow_casting", cast_cloud_shadows))
	cloud_world_margin_fraction = float(options.get("margin_fraction", cloud_world_margin_fraction))
	_sun_direction = options.get("sun_direction", _sun_direction)
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		push_error("CloudLayer requires positive world bounds")
		return
	_build_layers()
	configured = true
	_sync_camera_coverage()
	_update_drift_uniforms()
	_apply_enabled()

## The camera owner calls this before computing clipping. Values are already
## displayed Godot Y from the provider; never multiply by a terrain scale here.
func get_display_altitude() -> float:
	var altitude := _altitude_floor
	if _height_range_provider.is_valid():
		var supplied: Variant = _height_range_provider.call()
		if supplied is Dictionary:
			_last_height_range = supplied
			var upper := float(supplied.get("natural_max_y", supplied.get("terrain_max_y", altitude - cloud_clearance)))
			if is_finite(upper):
				altitude = maxf(altitude, upper + cloud_clearance)
	_volume_bottom = altitude
	cloud_base_height = _volume_bottom + cloud_volume_height
	return cloud_base_height

func set_clouds_enabled(value: bool) -> void:
	enabled = value

func _ready() -> void:
	_apply_enabled()

func _process(delta: float) -> void:
	if not configured or not enabled:
		return
	_sync_camera_coverage()
	if not _capture_time_locked:
		_elapsed += maxf(delta, 0.0)
	_update_drift_uniforms()

func set_capture_time(seconds: float) -> void:
	_capture_time_locked = true
	_elapsed = maxf(seconds, 0.0)
	_sync_camera_coverage()
	_update_drift_uniforms()

func resume_live_drift() -> void:
	_capture_time_locked = false

func _update_drift_uniforms() -> void:
	for material in _materials:
		material.set_shader_parameter("cloud_drift", Vector2(1.0, 0.28).normalized() * _elapsed * drift_speed)
		material.set_shader_parameter("cloud_density_multiplier", opacity)
		material.set_shader_parameter("cloud_sun_direction", landscape_sun.global_basis.z.normalized() if landscape_sun != null else _sun_direction)
		if landscape_sun != null:
			var color := landscape_sun.light_color.srgb_to_linear()
			material.set_shader_parameter("cloud_sun_color", Vector3(color.r, color.g, color.b))
			material.set_shader_parameter("cloud_sun_energy", landscape_sun.light_energy)

func _sync_camera_coverage() -> void:
	if landscape_camera == null or _plane_mesh == null:
		return
	var viewport_size := Vector2(landscape_camera.get_viewport().get_visible_rect().size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	get_display_altitude()
	var forward := -landscape_camera.global_basis.z.normalized()
	_materials[0].set_shader_parameter("cloud_ray_direction", forward)
	_materials[0].set_shader_parameter("cloud_bottom", _volume_bottom)
	_materials[0].set_shader_parameter("cloud_top", cloud_base_height)
	# Intersect all four viewport corner rays with the actual cloud altitude.
	# This handles oblique and portrait views without a square-width heuristic.
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		var origin := landscape_camera.project_ray_origin(corner)
		var direction := landscape_camera.project_ray_normal(corner)
		if absf(direction.y) < 0.001:
			return
		var hit := origin + direction * ((cloud_base_height - origin.y) / direction.y)
		minimum = minimum.min(Vector2(hit.x, hit.z))
		maximum = maximum.max(Vector2(hit.x, hit.z))
	var span := (maximum - minimum).max(Vector2(0.01, 0.01))
	_plane_mesh.size = span * (1.0 + 2.0 * cloud_world_margin_fraction)
	var center := (minimum + maximum) * 0.5
	_layers[0].position = Vector3(center.x, cloud_base_height, center.y)
	# Zoom removes only unresolved fine detail; it never replaces the weather
	# field, positions, scale or optical-depth law with another cloud layout.
	var world_per_pixel := landscape_camera.size / viewport_size.y
	var footprint := world_per_pixel / maxf(absf(forward.y), 0.05) * 1.05
	_materials[0].set_shader_parameter("cloud_shape_lod", clampf(log(maxf(footprint / 0.5, 1.0)) / log(2.0), 0.0, 3.0))
	_materials[0].set_shader_parameter("cloud_erosion_lod", clampf(log(maxf(footprint * 1.6 / 0.5, 1.0)) / log(2.0), 0.0, 3.0))

func _find_camera() -> Camera3D:
	var ancestor := get_parent()
	while ancestor != null:
		var found := ancestor.find_children("*", "Camera3D", true, false)
		if not found.is_empty():
			return found[0] as Camera3D
		ancestor = ancestor.get_parent()
	return get_viewport().get_camera_3d() if is_inside_tree() else null

func _build_layers() -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()
	_materials.clear()
	_plane_mesh = PlaneMesh.new()
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter("cloud_weather", WEATHER_TEXTURE)
	material.set_shader_parameter("cloud_structure", STRUCTURE_TEXTURE)
	material.set_shader_parameter("cloud_noise", _load_noise_texture())
	if _moment_textures.is_empty():
		for level in range(1,4):
			_moment_textures.append(_load_moment_texture(level))
	for level in range(1,4):
		material.set_shader_parameter("cloud_moments" + str(level), _moment_textures[level-1])
	material.set_shader_parameter("cloud_origin", world_bounds.get_center())
	var layer := MeshInstance3D.new()
	layer.name = "CloudDensityVolume"
	layer.mesh = _plane_mesh
	layer.material_override = material
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(layer)
	_layers.append(layer)
	_materials.append(material)

func _load_noise_texture() -> ImageTexture3D:
	if _noise_texture != null:
		return _noise_texture
	var file := FileAccess.open(NOISE_PATH, FileAccess.READ)
	if file == null:
		push_error("Own cloud scalar-noise resource missing")
		return null
	var side := file.get_32()
	if side < 4 or side > 256 or file.get_length() != 4 + side * side * side * 4:
		push_error("Invalid own cloud scalar-noise dimensions")
		return null
	var slices: Array[Image] = []
	for index in range(side):
		slices.append(Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, file.get_buffer(side * side * 4)))
	_noise_texture = ImageTexture3D.new()
	var result := _noise_texture.create(Image.FORMAT_RGBA8, side, side, side, false, slices)
	if result != OK:
		push_error("Could not upload own cloud density noise: " + str(result))
	return _noise_texture

func _apply_enabled() -> void:
	visible = enabled
	set_process(enabled and configured)

func _load_moment_texture(level: int) -> ImageTexture3D:
	var file := FileAccess.open("res://assets/weather/cloud_moments_lod%d.rgba16f" % level, FileAccess.READ)
	if file == null:
		push_error("Cloud moment resource missing")
		return null
	var side := file.get_32()
	if side != 192 / int(pow(2,level)) or file.get_length() != 4+side*side*side*8:
		push_error("Invalid cloud moment dimensions")
		return null
	var slices: Array[Image] = []
	for index in range(side):
		slices.append(Image.create_from_data(side,side,false,Image.FORMAT_RGBAH,file.get_buffer(side*side*8)))
	var texture := ImageTexture3D.new()
	if texture.create(Image.FORMAT_RGBAH,side,side,side,false,slices) != OK:
		push_error("Could not upload cloud moment resource")
		return null
	return texture
