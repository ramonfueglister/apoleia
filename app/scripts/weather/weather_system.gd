extends Node3D
## Weather states, moving weather cells, faceted clouds with real sun shadows,
## rain veils, lightning and time of day. The existing look is never replaced:
## its values are read once after LandscapeLook.configure_environment and only
## modulated per frame. With weather off every touched value returns to that base.
## World units are model kilometres; weather time can run faster than real time.

const CloudMeshes = preload("res://scripts/weather/cloud_meshes.gd")
const CLOUD_SHADER = preload("res://shaders/weather_cloud.gdshader")
const RAIN_SHADER = preload("res://shaders/weather_rain.gdshader")
const PROXY_SHADER = preload("res://shaders/weather_proxy.gdshader")
# Low resolution on purpose: bilinear sampling softens the shadow edges on water.
const MASK_SIZE := 160
# Thin bluish-white core with a soft glow towards the ribbon edges (UV.x 0..1 across).
const BOLT_CODE = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;\nuniform float glow = 1.0;\nvoid fragment() { float c = 1.0 - abs(UV.x * 2.0 - 1.0); ALBEDO = mix(vec3(0.35, 0.45, 0.9), vec3(2.2, 2.3, 2.8), smoothstep(0.7, 0.95, c)) * c * glow; }\n"

const STATES: Array[String] = ["clear", "fair", "overcast", "rain", "storm"]
# cover, noise amplitude, rain, storm (see weather_field.gdshaderinc)
const STATE_FIELD := {
	"clear": Vector4(0.0, 0.08, 0.0, 0.0),
	# Fair: grouped cumulus fields with clear high-pressure gaps.
	"fair": Vector4(0.02, 0.7, 0.0, 0.0),
	"overcast": Vector4(0.68, 0.35, 0.10, 0.0),
	"rain": Vector4(0.5, 0.45, 0.70, 0.0),
	# Storms are local: fair background plus one or two large storm cells.
	"storm": Vector4(0.04, 0.45, 0.0, 0.0),
}
# How many cumulus clusters a state shows next to its banks.
const STATE_PUFFS := {"clear": 1.0, "fair": 1.0, "overcast": 0.35, "rain": 0.0, "storm": 0.3}
const STATE_BANK_GREY := {"clear": 0.0, "fair": 0.0, "overcast": 0.55, "rain": 1.0, "storm": 0.6}
const STATE_WIND := {"clear": 0.45, "fair": 0.6, "overcast": 0.8, "rain": 0.9, "storm": 1.0}
# Desired weather cells per kind (0 cumulus cluster, 1 rain front, 2 storm cell).
const STATE_CELLS := {"clear": [0, 0, 0], "fair": [2, 0, 0], "overcast": [2, 1, 0], "rain": [0, 4, 0], "storm": [0, 0, 1]}
const AUTO_WEIGHTS := {"fair": 0.55, "clear": 0.2, "overcast": 0.12, "rain": 0.08, "storm": 0.05}
const TIMES: Array[String] = ["morning", "noon", "evening"]
# Sun rotation, sun colour factor, sun energy factor, ambient tint, ambient factor, fog tint.
const TIME_LOOK := {
	# Warm low sun against a cooler blue ambient; terrain colours are kept.
	# Warmth mostly in highlights and glitter: mildly saturated sun, ambient kept.
	"morning": [Vector3(-17.0, 72.0, 0.0), Color(1.0, 0.88, 0.80), 1.2, Color(0.92, 0.95, 1.04), 1.0, Color(1.0, 0.95, 0.94)],
	# Low sun behind-left of the default view: backlight and golden glitter on the sea.
	"evening": [Vector3(-18.0, -160.0, 0.0), Color(1.0, 0.84, 0.62), 1.45, Color(0.95, 0.97, 1.04), 1.05, Color(1.04, 0.95, 0.88)],
}
const WIND_SPEED := 3.0
const NOISE_PERIOD := 1100.0
const FINE_CELL := 50.0
const COARSE_CELL := 160.0
const FINE_SCALE := Vector2(6.0, 22.0)
const COARSE_SCALE := Vector2(10.0, 28.0)
const CLOUD_HEIGHT := 1.2 * 0.85 * 1.3 # mesh height * vertical scale * field growth
const TRANSITION_SECONDS := 30.0

var enabled := true
var auto_weather := true
# Start clear (the reference look); automatic weather brings clouds in later.
var state := "clear"
var time_of_day := 0.5
var day_cycle_seconds := 0.0
var time_scale := 1.0
var weather_time := 0.0
var drift := Vector2.ZERO
var wind_dir := Vector2(1.0, -0.15).normalized()
var wind_strength := 0.6
var cells: Array = []
var cloud_base := 90.0
var local_weather := Vector3.ZERO
var lightning := 0.0

var _landscape: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _height_provider: Callable
var _base := {}
var _written_fog := -1.0
var _fog_base := 0.0
var _rng := RandomNumberGenerator.new()
var _noise_image: Image
var _noise_texture: ImageTexture
var _cloud_material: ShaderMaterial
var _cloud_shadow_material: ShaderMaterial
var _cloud_mask_material: ShaderMaterial
var _rain_material: ShaderMaterial
var _mask_viewport: SubViewport
var _mask_root: Node3D
var _mask_camera: Camera3D
# Second, parallel sun that carries the share of sunlight clouds can block.
var _cloud_sun: DirectionalLight3D
var _sun_caster_mask := 0xFFFFFFFF
var _fine: RefCounted
var _coarse: RefCounted
var _field_from := Vector4.ZERO
var _field_to := Vector4.ZERO
var _wind_from := 0.6
var _wind_to := 0.6
var _transition := 1.0
var _puff_from := "fair"
var _phase_left := 0.0
var _front_timer := 0.0
var _lightning_timer := 0.0
var _bolt: MeshInstance3D
var _bolt_frames := 0
var _flash_light: OmniLight3D
var _flash_pos := Vector3.ZERO
var _shadow_rect := Vector4.ZERO
var _altitude_ready := false
var _prewarmed := false
var _spawn_front := false
var _capture_dir := ""
var _capture_frames := 0
var _capture_every := 2
var _frame := 0
var configured := false
# Diagnostics: --weather-debug=no-sun,no-mask,no-clouds,no-rain
var _debug := ""
# Camera-agnostic view on the ground (works for orthographic and perspective).
var _ground_rect := Rect2()
var _ground_width := 1000.0
var _forward := Vector3(0.0, -0.6, -0.8)

func configure(landscape: Node3D, camera: Camera3D, sun: DirectionalLight3D, environment: Environment, height_provider: Callable) -> void:
	_landscape = landscape
	_camera = camera
	_sun = sun
	_environment = environment
	_height_provider = height_provider
	_capture_base()
	var seed := 1
	var start_state := ""
	var snapshot := false
	var spawn_front := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var key := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		if "=" in key:
			value = key.get_slice("=", 1)
			key = key.get_slice("=", 0)
		match key:
			"--weather":
				if value in ["off", "none"]: enabled = false
				elif value in STATES: start_state = value
			"--time":
				if value in TIMES: time_of_day = TIMES.find(value) * 0.5
			"--weather-seed": seed = int(value)
			"--weather-debug": _debug = value
			"--day-cycle": day_cycle_seconds = float(value)
			"--weather-timescale": time_scale = maxf(float(value), 0.0)
			"--weather-front": spawn_front = true
			"--weather-capture": _capture_dir = value
			"--weather-capture-frames": _capture_frames = int(value)
			"--clouds-disabled": enabled = false
			"--clouds-enabled": enabled = true
			"--snapshot": snapshot = true
	_rng.seed = seed
	# Snapshots without --weather stay in the clear reference state.
	if snapshot and start_state == "": start_state = "clear"
	if start_state != "":
		auto_weather = false
		state = start_state
	_build_noise(seed)
	_cloud_material = _material(CLOUD_SHADER, -1)
	_cloud_shadow_material = _material(PROXY_SHADER, 1)
	_cloud_mask_material = _material(PROXY_SHADER, 2)
	_rain_material = _material(RAIN_SHADER, -1)
	_build_shadow_mask()
	_fine = CloudMeshes.CloudTier.new(CloudMeshes, self, FINE_CELL, FINE_SCALE, seed * 31 + 3, _cloud_material, _cloud_shadow_material, _rain_material)
	_coarse = CloudMeshes.CloudTier.new(CloudMeshes, self, COARSE_CELL, COARSE_SCALE, seed * 31 + 11, _cloud_material, _cloud_shadow_material, null)
	_fine.add_mask(_mask_root, _cloud_mask_material)
	_coarse.add_mask(_mask_root, _cloud_mask_material)
	_build_cloud_sun()
	_build_lightning()
	_field_from = STATE_FIELD[state]
	_field_to = _field_from
	_puff_from = state
	_wind_from = STATE_WIND[state]
	_wind_to = _wind_from
	# First clouds drift in only after a while.
	_phase_left = _rng.randf_range(60.0, 120.0)
	_front_timer = _rng.randf_range(60.0, 120.0)
	_spawn_front = spawn_front
	if _capture_dir != "": DirAccess.make_dir_recursive_absolute(_capture_dir)
	configured = true
	_apply_enabled()

func _earth_km() -> float:
	return 6371008.8 * 0.001

func _capture_base() -> void:
	_base = {
		"sun_rotation": _sun.rotation_degrees,
		"sun_color": _sun.light_color,
		"sun_energy": _sun.light_energy,
		"ambient_color": _environment.ambient_light_color,
		"ambient_energy": _environment.ambient_light_energy,
		"fog_color": _environment.fog_light_color,
		"saturation": _environment.adjustment_saturation,
	}
	_fog_base = _environment.fog_density

func _build_noise(seed: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	_noise_image = noise.get_seamless_image(256, 256, false, false, 0.1, true)
	_noise_image.convert(Image.FORMAT_L8)
	_noise_texture = ImageTexture.create_from_image(_noise_image)

func _material(shader: Shader, mode: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	if mode >= 0: material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("weather_noise", _noise_texture)
	material.set_shader_parameter("noise_period", NOISE_PERIOD)
	material.set_shader_parameter("earth_km", _earth_km())
	return material

## Top-down render of the shadow proxies (own world) for shaders with their own
## sun term; 1 = full sun. Feeds weather_cloud_shadow / weather_cloud_shadow_rect.
func _build_shadow_mask() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.size = Vector2i(MASK_SIZE, MASK_SIZE)
	_mask_viewport.own_world_3d = true
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_root = Node3D.new()
	_mask_viewport.add_child(_mask_root)
	_mask_camera = Camera3D.new()
	_mask_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_mask_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_mask_camera.near = 1.0
	_mask_camera.far = 6000.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.WHITE
	_mask_camera.environment = environment
	_mask_camera.current = true
	_mask_root.add_child(_mask_camera)
	add_child(_mask_viewport)
	RenderingServer.global_shader_parameter_set("weather_cloud_shadow", _mask_viewport.get_texture())

func _build_cloud_sun() -> void:
	_sun_caster_mask = _sun.shadow_caster_mask
	_cloud_sun = DirectionalLight3D.new()
	_cloud_sun.shadow_enabled = true
	# Only the cloud proxies cast into this light's shadow map: re-rendering every
	# forest caster here doubled the shadow cost.
	_cloud_sun.shadow_caster_mask = CloudMeshes.CLOUD_SHADOW_LAYER
	_cloud_sun.visible = false
	_sun.get_parent().add_child(_cloud_sun)

## Splits the sun: the main light ignores cloud proxies, the cloud sun (share
## `strength`) is blocked only by them, so a cloud shadow removes that share.
## Tree shadows then darken only the main share, so the split is used only
## while clouds can be in view.
func _split_sun(strength: float) -> void:
	if state == "clear" and cells.is_empty():
		_sun.shadow_caster_mask = _sun_caster_mask
		_cloud_sun.visible = false
		return
	var energy := _sun.light_energy
	_sun.shadow_caster_mask = _sun_caster_mask & ~CloudMeshes.CLOUD_SHADOW_LAYER
	_sun.light_energy = energy * (1.0 - strength)
	_cloud_sun.visible = true
	_cloud_sun.global_transform = _sun.global_transform
	_cloud_sun.light_energy = energy * strength
	for property in ["light_color", "light_angular_distance", "shadow_bias", "shadow_normal_bias", "shadow_opacity", "directional_shadow_mode", "directional_shadow_max_distance", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3", "directional_shadow_blend_splits", "light_specular"]:
		_cloud_sun.set(property, _sun.get(property))
	# Soft, blurred cloud shadows; tree shadows keep the main sun's settings.
	_cloud_sun.shadow_blur = 6.0

func _build_lightning() -> void:
	_bolt = MeshInstance3D.new()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BOLT_CODE
	material.shader = shader
	_bolt.material_override = material
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(0.82, 0.86, 1.0)
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	add_child(_flash_light)

# --- Public API -----------------------------------------------------------

func is_active() -> bool:
	return configured and enabled

## Highest displayed cloud Y of the active zoom tier, for camera clipping and near fade.
func get_display_altitude() -> float:
	return cloud_base + (FINE_SCALE.y if _ground_width < 1850.0 else COARSE_SCALE.y) * CLOUD_HEIGHT

func set_weather(name: String, automatic: bool = false) -> void:
	auto_weather = automatic
	_begin_transition(name)

func set_enabled(value: bool) -> void:
	enabled = value
	_apply_enabled()

## CPU mirror of weather_field(): x cover, y rain, z storm.
func sample_field(p: Vector2) -> Vector3:
	var n := _noise_at((p - drift) / NOISE_PERIOD)
	var climate := _climate(p)
	var f := _current_field()
	var cover := clampf(f.x + (n - 0.5) * f.y * 2.0, 0.0, 1.0) * climate
	var rain := f.z * smoothstep(0.45, 0.85, cover)
	var storm := f.w * smoothstep(0.5, 0.9, cover)
	var cell_climate := minf(climate * 1.2, 1.0)
	for cell in cells:
		var local: Vector2 = p - cell.pos
		var axis: Vector2 = cell.axis
		var d := Vector2(local.dot(axis) / cell.ra, local.dot(Vector2(-axis.y, axis.x)) / cell.rc).length()
		var b: float = _cell_strength(cell) * (1.0 - smoothstep(0.35, 1.0, d)) * (0.55 + 0.9 * n) * cell_climate
		cover += b * (0.6 if cell.kind == 0 else (1.6 if cell.kind == 2 else 1.0))
		if cell.kind >= 1: rain += b * 0.9 * smoothstep(0.2, 0.6, b)
		if cell.kind == 2: storm += b * smoothstep(0.3, 0.8, b)
	return Vector3(clampf(cover, 0.0, 1.0), clampf(rain, 0.0, 1.0), clampf(storm, 0.0, 1.0))

func describe() -> Dictionary:
	return {"enabled": enabled, "auto": auto_weather, "state": state, "time_of_day": time_of_day, "local": [local_weather.x, local_weather.y, local_weather.z], "cells": cells.size(), "cloud_base": cloud_base, "fine_slots": _fine.slot_count if _fine else 0, "coarse_slots": _coarse.slot_count if _coarse else 0, "focus": [_focus().x, _focus().y], "ground_width": _ground_width, "forward": [_forward.x, _forward.z], "cell_list": cells.map(func(c): return [c.kind, snappedf(c.pos.x, 0.1), snappedf(c.pos.y, 0.1), snappedf(c.ra, 0.1), snappedf(c.rc, 0.1), snappedf(_cell_strength(c), 0.01)])}

# --- Field helpers ----------------------------------------------------------

func _climate(p: Vector2) -> float:
	var lat := 41.0 - rad_to_deg(p.y / _earth_km())
	return lerpf(0.15, 1.0, smoothstep(30.0, 37.0, lat)) * lerpf(1.0, 1.5, smoothstep(44.0, 54.0, lat))

func _noise_at(uv: Vector2) -> float:
	var size := _noise_image.get_size()
	var p := Vector2(fposmod(uv.x, 1.0) * size.x - 0.5, fposmod(uv.y, 1.0) * size.y - 0.5)
	var i := Vector2i(p.floor())
	var f := p - Vector2(i)
	var a := _noise_image.get_pixel(posmod(i.x, size.x), posmod(i.y, size.y)).r
	var b := _noise_image.get_pixel(posmod(i.x + 1, size.x), posmod(i.y, size.y)).r
	var c := _noise_image.get_pixel(posmod(i.x, size.x), posmod(i.y + 1, size.y)).r
	var d := _noise_image.get_pixel(posmod(i.x + 1, size.x), posmod(i.y + 1, size.y)).r
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

func _current_field() -> Vector4:
	return _field_from.lerp(_field_to, smoothstep(0.0, 1.0, _transition))

func _cell_strength(cell: Dictionary) -> float:
	return cell.strength * clampf(cell.age / 40.0, 0.0, 1.0) * clampf((cell.life - cell.age) / 40.0, 0.0, 1.0)

# --- Weather cells and states ----------------------------------------------

func _focus() -> Vector2:
	return _landscape.get("target") if _landscape else Vector2.ZERO

func _region_radius() -> float:
	return clampf(_ground_width * 1.2, 500.0, 3000.0)

func _prewarm_cells() -> void:
	var wanted: Array = STATE_CELLS[state]
	for kind in 3:
		for k in wanted[kind]: _spawn_cell(kind, false, 0.0)
	for cell in cells: cell.age = _rng.randf_range(40.0, cell.life * 0.5)
	# Fair weather starts with a cumulus group in view.
	for cell in cells:
		if cell.kind == 0 and state == "fair":
			cell.pos = _focus() - _apparent_offset(cloud_base) * 0.5
			cell.ra = maxf(_ground_width * 0.7, 120.0)
			cell.rc = maxf(_ground_width * 0.9, 150.0)
			break
	# A storm starts as one front over part of the view; the rest stays bright.
	for cell in cells:
		if cell.kind == 2:
			# Placed so the front appears on the right of the view, not above it.
			# Far side of the view, right half: the foreground stays sunny.
			var away := Vector2(_forward.x, _forward.z).normalized()
			cell.pos = _focus() + away * _ground_width * 0.15 + Vector2(-away.y, away.x) * _ground_width * 0.3
			cell.ra = maxf(_ground_width * 0.6, 60.0)
			cell.rc = maxf(_ground_width * 0.75, 90.0)
			break

func _spawn_cell(kind: int, upwind: bool, distance: float) -> void:
	if cells.size() >= 16: return
	var radius := _region_radius()
	var across := Vector2(-wind_dir.y, wind_dir.x)
	var pos := _focus()
	if upwind:
		var d := distance if distance > 0.0 else radius * 0.9
		pos += -wind_dir * d + across * (_rng.randf_range(-0.6, 0.6) * radius if distance <= 0.0 else 0.0)
	else:
		pos += Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * radius
	var cell := {"kind": kind, "pos": pos, "axis": wind_dir, "age": 0.0, "speed": _rng.randf_range(0.8, 1.0)}
	match kind:
		0:
			var r := _rng.randf_range(180.0, 320.0)
			cell.merge({"ra": r, "rc": r * _rng.randf_range(0.8, 1.3), "strength": _rng.randf_range(0.45, 0.7), "life": _rng.randf_range(500.0, 900.0)})
		1:
			cell.merge({"ra": _rng.randf_range(140.0, 220.0), "rc": _rng.randf_range(450.0, 750.0), "strength": _rng.randf_range(0.8, 1.0), "life": _rng.randf_range(600.0, 1000.0)})
		_:
			var r := _rng.randf_range(200.0, 340.0)
			cell.merge({"ra": r, "rc": r * _rng.randf_range(0.8, 1.2), "strength": _rng.randf_range(0.9, 1.0), "life": _rng.randf_range(300.0, 600.0)})
	cells.append(cell)

func _update_cells(dt: float) -> void:
	var focus := _focus()
	var radius := _region_radius()
	for cell in cells:
		cell.age += dt
		cell.pos += wind_dir * WIND_SPEED * wind_strength * cell.speed * 0.9 * dt
	cells = cells.filter(func(c): return c.age < c.life and (c.pos - focus).length() < radius * 2.5)
	var wanted: Array = STATE_CELLS[state]
	for kind in 3:
		var have := cells.filter(func(c): return c.kind == kind and not c.get("transient", false)).size()
		if have < wanted[kind]: _spawn_cell(kind, true, 0.0)
	if auto_weather and state in ["fair", "clear"]:
		_front_timer -= dt
		if _front_timer <= 0.0:
			_front_timer = _rng.randf_range(90.0, 180.0)
			_spawn_cell(1 if _rng.randf() < 0.7 else 2, true, 0.0)
			if not cells.is_empty(): cells[-1]["transient"] = true

func _begin_transition(name: String) -> void:
	_puff_from = state
	_field_from = _current_field()
	_wind_from = lerpf(_wind_from, _wind_to, smoothstep(0.0, 1.0, _transition))
	state = name
	_field_to = STATE_FIELD[name]
	_wind_to = STATE_WIND[name]
	_transition = 0.0
	print(JSON.stringify({"event": "weather_state", "state": state, "auto": auto_weather}))

func _pick_auto_state() -> String:
	var r := _rng.randf()
	for name in AUTO_WEIGHTS:
		r -= AUTO_WEIGHTS[name]
		if r <= 0.0: return name
	return "fair"

# --- Frame update -------------------------------------------------------------

func _process(delta: float) -> void:
	if not configured: return
	_frame += 1
	var dt := delta * time_scale
	if day_cycle_seconds > 0.0: time_of_day = 0.5 - 0.5 * cos(TAU * Time.get_ticks_msec() / 1000.0 / day_cycle_seconds)
	if not enabled:
		# Time-of-day light stays active without weather; no cloud shadows.
		local_weather = Vector3.ZERO
		_apply_look()
		_sun.shadow_caster_mask = _sun_caster_mask
		_sun.light_energy += _cloud_sun.light_energy if _cloud_sun.visible else 0.0
		_cloud_sun.visible = false
		_publish_globals(Vector3.ZERO)
		return
	_update_ground_view()
	_update_altitude(delta)
	if not _prewarmed:
		# Deferred until the landscape has applied its start view.
		_prewarmed = true
		_prewarm_cells()
		if _spawn_front: _spawn_cell(1, true, 600.0)
	weather_time += dt
	_transition = minf(_transition + dt / TRANSITION_SECONDS, 1.0)
	if auto_weather:
		_phase_left -= dt
		if _phase_left <= 0.0:
			_phase_left = _rng.randf_range(120.0, 240.0)
			_begin_transition("fair" if state == "clear" else _pick_auto_state())
	wind_strength = lerpf(_wind_from, _wind_to, smoothstep(0.0, 1.0, _transition))
	var heading := 0.25 * sin(weather_time / 300.0)
	wind_dir = Vector2(1.0, -0.15).normalized().rotated(heading)
	drift += wind_dir * WIND_SPEED * wind_strength * dt
	_update_cells(dt)
	var focus := _focus()
	var spread := _ground_width * 0.25
	var sampled := Vector3.ZERO
	for offset in [Vector2.ZERO, Vector2(spread, 0), Vector2(-spread, 0), Vector2(0, spread), Vector2(0, -spread)]:
		sampled += sample_field(focus + offset) * 0.2
	local_weather = sampled if _frame <= 2 else local_weather.lerp(sampled, clampf(delta * 1.5, 0.0, 1.0))
	_apply_look()
	_update_tiers()
	_upload_uniforms()
	_update_lightning(delta)
	_publish_globals(local_weather)
	_capture()
	if _debug != "":
		if "no-sun" in _debug:
			_sun.shadow_caster_mask = _sun_caster_mask
			_sun.light_energy += _cloud_sun.light_energy if _cloud_sun.visible else 0.0
			_cloud_sun.visible = false
		if "no-mask" in _debug: _mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if "no-clouds" in _debug:
			for mmi in _fine.visual + _coarse.visual: mmi.visible = false
		if "no-rain" in _debug and _fine.rain_instance: _fine.rain_instance.visible = false
		# Stills: one strike in the storm front, held visible.
		if "bolt" in _debug:
			var front := cells.filter(func(c): return c.kind == 2)
			if _frame == 20 and not front.is_empty(): _strike(front[0].pos + Vector2(0.0, -front[0].ra * 0.2), _ground_width)
			if _frame > 20:
				_bolt_frames = 2
				lightning = maxf(lightning, 0.25)
		if _frame == 30: print("WEATHERDEBUG ", JSON.stringify(describe()))
	if _frame == 50 and OS.get_environment("WEATHER_MASK_DUMP") != "":
		_mask_viewport.get_texture().get_image().save_png(OS.get_environment("WEATHER_MASK_DUMP"))

## Ground footprint from the camera rays through the viewport corners and edges.
func _update_ground_view() -> void:
	var size := get_viewport().get_visible_rect().size
	var points := [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), size, Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5)]
	var hits: Array[Vector2] = []
	var reach := maxf(_camera.far, 1.0)
	for point in points:
		var origin := _camera.project_ray_origin(point)
		var normal := _camera.project_ray_normal(point)
		var t := reach if normal.y > -0.02 else minf(-origin.y / normal.y, reach)
		var hit := origin + normal * t
		hits.append(Vector2(hit.x, hit.z))
	_ground_width = maxf(hits[4].distance_to(hits[5]), 1.0)
	# Rays towards the horizon reach the far plane; beyond a few view widths the
	# haze hides clouds anyway, so clamp the area to keep the slot count small.
	var focus := _focus()
	var limit := Rect2(focus - Vector2(_ground_width * 1.4, _ground_width * 1.6), Vector2(_ground_width * 2.8, _ground_width * 2.4))
	var rect := Rect2(hits[0].clamp(limit.position, limit.end), Vector2.ZERO)
	for hit in hits: rect = rect.expand(hit.clamp(limit.position, limit.end))
	_ground_rect = rect
	_forward = -_camera.global_basis.z.normalized()

## Ground point that a point at height y covers on screen (along the central view ray).
func _apparent_offset(y: float) -> Vector2:
	return Vector2(_forward.x, _forward.z) * (y / maxf(-_forward.y, 0.1))

func _update_altitude(delta: float) -> void:
	var target_base := cloud_base
	if _height_provider.is_valid():
		var bounds: Dictionary = _height_provider.call()
		# Below the highest peaks: clouds may wrap mountain tops, like the reference.
		target_base = float(bounds.get("natural_max_y", 80.0)) * 0.6 + 4.0
	cloud_base = target_base if not _altitude_ready else lerpf(cloud_base, target_base, clampf(delta * 3.0, 0.0, 1.0))
	_altitude_ready = true

func _time_look() -> Array:
	var noon := [_base.sun_rotation, Color(1, 1, 1), 1.0, Color(1, 1, 1), 1.0, Color(1, 1, 1)]
	var from: Array = TIME_LOOK.morning if time_of_day < 0.5 else noon
	var to: Array = noon if time_of_day < 0.5 else TIME_LOOK.evening
	var t := time_of_day * 2.0 if time_of_day < 0.5 else (time_of_day - 0.5) * 2.0
	var q := Quaternion.from_euler(_euler(from[0])).slerp(Quaternion.from_euler(_euler(to[0])), t)
	return [q, from[1].lerp(to[1], t), lerpf(from[2], to[2], t), from[3].lerp(to[3], t), lerpf(from[4], to[4], t), from[5].lerp(to[5], t)]

func _euler(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))

## Values this system wrote last frame. Anything that differs now was changed by
## the landscape look (or the user) and becomes the new base, so weather and time
## of day always modulate the current base instead of a stale copy.
var _written := {}

func _read_look() -> Dictionary:
	return {"sun_rotation": _sun.rotation_degrees, "sun_color": _sun.light_color, "sun_energy": _sun.light_energy + (_cloud_sun.light_energy if _cloud_sun and _cloud_sun.visible else 0.0), "ambient_color": _environment.ambient_light_color, "ambient_energy": _environment.ambient_light_energy, "fog_color": _environment.fog_light_color, "saturation": _environment.adjustment_saturation}

func _rebase() -> void:
	if _written.is_empty(): return
	var now := _read_look()
	for key in now:
		var changed: bool = not (now[key].is_equal_approx(_written[key]) if now[key] is Vector3 or now[key] is Color else is_equal_approx(now[key], _written[key]))
		if changed: _base[key] = now[key]

func _apply_look() -> void:
	_rebase()
	var look := _time_look()
	var w := local_weather
	# Darkness under fronts comes from their shadows; global dimming stays mild.
	var state_rain := _current_field().z
	# Rain dims the whole scene (overcast sky); storm fronts stay local.
	var dim := clampf(maxf((w.x - 0.6) * 0.5, 0.0) + w.y * 0.3 + state_rain * 0.6, 0.0, 0.55)
	_sun.quaternion = look[0]
	var sun_color: Color = _base.sun_color * look[1]
	_sun.light_color = sun_color.lerp(Color(0.80, 0.82, 0.86), dim * 0.4)
	_sun.light_energy = _base.sun_energy * look[2] * (1.0 - 0.9 * dim)
	var ambient: Color = _base.ambient_color * look[3]
	_environment.ambient_light_color = ambient.lerp(Color(0.72, 0.76, 0.82), dim * 0.5)
	_environment.ambient_light_energy = _base.ambient_energy * look[4] * (1.0 - 0.35 * dim)
	var fog: Color = _base.fog_color * look[5]
	fog = fog.lerp(Color(0.58, 0.61, 0.65), clampf(state_rain * 1.2, 0.0, 1.0))
	_environment.fog_light_color = fog
	# LandscapeLook rewrites fog_density per view; only scale its latest value.
	if not is_equal_approx(_environment.fog_density, _written_fog): _fog_base = _environment.fog_density
	_written_fog = _fog_base * (1.0 + state_rain * 2.5) + state_rain * 0.04
	_environment.fog_density = _written_fog
	_environment.adjustment_saturation = _base.saturation * (1.0 - 0.1 * w.y - 0.55 * state_rain)
	# Cloud shadows darken by about 25-30 %; more under storm fronts.
	_split_sun(clampf(0.75 + 0.15 * w.z, 0.0, 0.9))
	_written = _read_look()

func _restore_look() -> void:
	if _base.is_empty(): return
	_sun.rotation_degrees = _base.sun_rotation
	_sun.light_color = _base.sun_color
	_sun.light_energy = _base.sun_energy
	_environment.ambient_light_color = _base.ambient_color
	_environment.ambient_light_energy = _base.ambient_energy
	_environment.fog_light_color = _base.fog_color
	if is_equal_approx(_environment.fog_density, _written_fog): _environment.fog_density = _fog_base
	_written_fog = -1.0
	_environment.adjustment_saturation = _base.saturation
	_written = {}
	_sun.shadow_caster_mask = _sun_caster_mask
	if _cloud_sun: _cloud_sun.visible = false

func _update_tiers() -> void:
	var view_width := _ground_width
	# Fade clouds out up close and whenever the camera comes near the cloud layer.
	var clearance := _camera.global_position.y - get_display_altitude()
	var near_fade := smoothstep(0.0, 10.0, clearance)
	var fine_fade := near_fade * (1.0 - smoothstep(1500.0, 2200.0, view_width))
	var coarse_fade := smoothstep(1500.0, 2200.0, view_width)
	var rain_fade := 1.0 - smoothstep(1300.0, 1800.0, view_width)
	var fine_on := view_width < 2200.0
	var coarse_on := view_width > 1500.0
	_fine.set_fade(fine_fade, fine_on and view_width < 1850.0, rain_fade if fine_on else 0.0)
	_coarse.set_fade(coarse_fade, coarse_on and view_width >= 1850.0, 0.0)
	if not fine_on: _fine.set_visible(false)
	if not coarse_on: _coarse.set_visible(false)
	var footprint := _ground_rect
	var sun_dir := _sun.global_basis.z.normalized()
	var top := get_display_altitude()
	var region := footprint.merge(Rect2(footprint.position - _apparent_offset(top), footprint.size))
	region.position -= drift
	# Stylised shadow placement: the shadow lands where the cloud appears over the
	# ground, offset a little away from the sun and down-screen so it peeks out,
	# instead of 100+ km away as the true geometry of the high layer would give.
	var sun_xz := Vector2(sun_dir.x, sun_dir.z) / maxf(sun_dir.y, 0.12)
	var toward_camera := -Vector2(_forward.x, _forward.z).normalized()
	var peek := -sun_xz.normalized() * view_width * 0.03 + toward_camera * view_width * 0.03
	var side := maxf(footprint.size.x, footprint.size.y) * 1.1
	var centre := footprint.get_center()
	_shadow_rect = Vector4(centre.x - side * 0.5, centre.y - side * 0.5, side, side)
	_mask_camera.size = side
	_mask_camera.position = Vector3(centre.x, 3000.0, centre.y)
	# Clouds closer to the camera than this dissolve (perspective near zoom).
	var focus_distance := _camera.global_position.distance_to(Vector3(_focus().x, cloud_base, _focus().y))
	_cloud_material.set_shader_parameter("near_fade_distance", focus_distance * 0.7)
	var cluster_scale := clampf(_ground_width / 1400.0, 0.2, 0.6)
	_cloud_material.set_shader_parameter("near_cull_distance", focus_distance * lerpf(0.0, 0.6, smoothstep(0.2, 0.6, _current_field().z)))
	for material in [_cloud_material, _cloud_shadow_material, _cloud_mask_material]:
		material.set_shader_parameter("cluster_scale", cluster_scale)
	for material in [_cloud_shadow_material, _cloud_mask_material]:
		material.set_shader_parameter("view_camera", _camera.global_position)
		material.set_shader_parameter("sun_xz", sun_xz)
		material.set_shader_parameter("peek", peek)
	var puffs := lerpf(STATE_PUFFS.get(_puff_from, 1.0), STATE_PUFFS[state], smoothstep(0.0, 1.0, _transition))
	var bank_grey := lerpf(STATE_BANK_GREY.get(_puff_from, 0.0), STATE_BANK_GREY[state], smoothstep(0.0, 1.0, _transition))
	for material in [_cloud_material, _cloud_shadow_material, _cloud_mask_material]:
		material.set_shader_parameter("puff_amount", puffs)
		material.set_shader_parameter("bank_grey", bank_grey)
	_cloud_mask_material.set_shader_parameter("mask_darkness", 0.22)
	_rain_material.set_shader_parameter("strength", lerpf(1.25, 0.5, smoothstep(700.0, 1600.0, view_width)))
	if fine_on: _fine.ensure(region.grow(FINE_SCALE.y * 1.8))
	if coarse_on: _coarse.ensure(region.grow(COARSE_SCALE.y * 1.8))

func _upload_uniforms() -> void:
	var shape: Array[Vector4] = []
	var param: Array[Vector4] = []
	for cell in cells:
		shape.append(Vector4(cell.pos.x, cell.pos.y, cell.ra, cell.rc))
		param.append(Vector4(cell.axis.x, cell.axis.y, _cell_strength(cell), cell.kind))
	while shape.size() < 16:
		shape.append(Vector4(0, 0, 1, 1))
		param.append(Vector4(1, 0, 0, 0))
	var field := _current_field()
	var sun_dir := _sun.global_basis.z.normalized()
	var sun_color := _sun.light_color
	var ambient := _environment.ambient_light_color
	for material in [_cloud_material, _cloud_shadow_material, _cloud_mask_material, _rain_material]:
		material.set_shader_parameter("air_drift", drift)
		material.set_shader_parameter("weather_state", field)
		material.set_shader_parameter("cell_shape", shape)
		material.set_shader_parameter("cell_param", param)
		material.set_shader_parameter("cell_count", cells.size())
		material.set_shader_parameter("cloud_base", cloud_base)
	_rain_material.set_shader_parameter("now", weather_time / maxf(time_scale, 0.001) if time_scale > 0.0 else 0.0)
	# Light blue-grey undersides: shade follows the ambient hue, not its energy.
	# Shaded sides at about 60-70 % of the lit tops, blue-grey.
	var shade := Color(0.60, 0.66, 0.76) * ambient / maxf(maxf(ambient.r, ambient.g), ambient.b)
	var sun_height := clampf(sun_dir.y / 0.64, 0.85, 1.0)
	for material in [_cloud_material]:
		material.set_shader_parameter("sun_dir", sun_dir)
		material.set_shader_parameter("sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b) / maxf(maxf(sun_color.r, sun_color.g), sun_color.b))
		material.set_shader_parameter("shade_color", Vector3(shade.r, shade.g, shade.b))
		material.set_shader_parameter("brightness", sun_height)

# --- Lightning ----------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	lightning = maxf(lightning - delta * 3.0, 0.0)
	if _bolt_frames > 0:
		_bolt_frames -= 1
		if _bolt_frames == 0: _bolt.visible = false
	_flash_light.visible = lightning > 0.02
	_flash_light.light_energy = 6.0 * lightning
	for material in [_cloud_material]:
		material.set_shader_parameter("flash", lightning)
		material.set_shader_parameter("flash_pos", _flash_pos)
		material.set_shader_parameter("flash_radius", maxf(_ground_width * 0.08, 30.0))
	_lightning_timer -= delta
	if _lightning_timer > 0.0: return
	_lightning_timer = 0.35
	var view_width := _ground_width
	if view_width > 2500.0: return
	var footprint := _ground_rect
	var best := Vector2.ZERO
	var best_storm := 0.0
	for k in 4:
		var p := footprint.position + Vector2(_rng.randf(), _rng.randf()) * footprint.size
		var storm := sample_field(p).z
		if storm > best_storm:
			best_storm = storm
			best = p
	if best_storm > 0.3 and _rng.randf() < best_storm * 0.6: _strike(best, view_width)

func _strike(p: Vector2, view_width: float) -> void:
	var ground := 0.0
	if _landscape.has_method("_render_height"): ground = float(_landscape.call("_render_height", p))
	var top := cloud_base + 2.0
	# About three pixels wide at the strike's distance, for any projection.
	var pixel := view_width / maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var width := pixel * 1.3
	var points := PackedVector3Array()
	var x := 0.0
	var steps := 10
	for k in steps + 1:
		var y := lerpf(top, ground, float(k) / steps)
		points.append(Vector3(p.x + x, y, p.y))
		x += _rng.randf_range(-1.0, 1.0) * (top - ground) * 0.06
	# Main channel plus two short branches; ribbons are wide for the glow.
	var paths := [points]
	for branch in 2:
		var start := _rng.randi_range(2, steps - 4)
		var path := PackedVector3Array([points[start]])
		var bx := 0.0
		for k in range(1, 4):
			bx += _rng.randf_range(0.4, 1.0) * (1.0 if branch == 0 else -1.0) * (top - ground) * 0.07
			path.append(Vector3(points[start].x + bx, lerpf(points[start].y, ground, float(k) / 6.0), points[start].z))
		paths.append(path)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for path in paths:
		var scale := 1.0 if path == points else 0.6
		for k in path.size() - 1:
			var a: Vector3 = path[k]
			var b: Vector3 = path[k + 1]
			var w := width * 4.0 * scale * (1.0 - 0.4 * float(k) / path.size())
			vertices.append_array([a + Vector3(-w, 0, 0), a + Vector3(w, 0, 0), b + Vector3(w, 0, 0), a + Vector3(-w, 0, 0), b + Vector3(w, 0, 0), b + Vector3(-w, 0, 0)])
			uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_bolt.mesh = mesh
	_bolt.visible = true
	_bolt_frames = 3
	_flash_pos = Vector3(p.x, top, p.y)
	_flash_light.position = Vector3(p.x, ground + (top - ground) * 0.3, p.y)
	_flash_light.omni_range = maxf(top - ground, 20.0) * 1.4
	lightning = 1.0

# --- Globals, input, capture ---------------------------------------------------

func _publish_globals(w: Vector3) -> void:
	RenderingServer.global_shader_parameter_set("weather_wind_dir", wind_dir)
	# Capped at 0.7 for now: the water shader applies wind globally to normals and
	# Fresnel, which paled the whole sea in storms. Lift once the water thread makes
	# that local via storm_local.
	RenderingServer.global_shader_parameter_set("weather_wind_strength", minf(wind_strength, 0.7) if enabled else 0.0)
	RenderingServer.global_shader_parameter_set("weather_storm", w.z)
	RenderingServer.global_shader_parameter_set("weather_wetness", w.y)
	RenderingServer.global_shader_parameter_set("weather_lightning", lightning if enabled else 0.0)
	RenderingServer.global_shader_parameter_set("weather_cloud_shadow_rect", _shadow_rect if enabled else Vector4.ZERO)

func _apply_enabled() -> void:
	if not configured: return
	_fine.set_visible(enabled)
	_coarse.set_visible(enabled)
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	if not enabled:
		_restore_look()
		_bolt.visible = false
		_flash_light.visible = false
		lightning = 0.0
		_publish_globals(Vector3.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	if not configured or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F5:
			var order: Array[String] = ["auto"] + STATES
			var current := "auto" if auto_weather else state
			var next := order[(order.find(current) + 1) % order.size()]
			if next == "auto": set_weather("fair", true)
			else: set_weather(next, false)
		KEY_F6:
			time_of_day = fmod(round(time_of_day * 2.0) * 0.5 + 0.5, 1.5)
			day_cycle_seconds = 0.0
			print(JSON.stringify({"event": "weather_time", "time": TIMES[int(round(time_of_day * 2.0))]}))
		KEY_F7:
			set_enabled(not enabled)
			print(JSON.stringify({"event": "weather_enabled", "enabled": enabled}))

func _capture() -> void:
	if _capture_dir == "" or _capture_frames <= 0 or _frame % _capture_every != 0: return
	_capture_frames -= 1
	var image := get_viewport().get_texture().get_image()
	image.save_jpg(_capture_dir.path_join("w_%05d.jpg" % _frame), 0.92)
