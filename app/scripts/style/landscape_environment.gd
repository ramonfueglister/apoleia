class_name LandscapeEnvironment
extends RefCounted
## Diorama art direction; world distances are model kilometres.

static func configure(environment: Environment, sun: DirectionalLight3D) -> void:
    var sky_material = ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("789dbd")
    sky_material.sky_horizon_color = Color("d6dfda")
    sky_material.ground_bottom_color = Color("7d8360")
    sky_material.ground_horizon_color = Color("bec8b3")
    sky_material.sky_energy_multiplier = 0.55
    var sky = Sky.new()
    sky.sky_material = sky_material
    environment.sky = sky
    environment.background_mode = Environment.BG_SKY
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_energy = 0.48
    environment.tonemap_mode = Environment.TONE_MAPPER_ACES
    environment.tonemap_exposure = 0.78
    environment.ssao_enabled = true
    environment.ssao_radius = 0.22
    environment.ssao_intensity = 0.85
    environment.ssao_power = 1.25
    environment.ssao_detail = 0.35
    environment.ssao_light_affect = 0.25
    environment.ssao_ao_channel_affect = 0.55
    environment.fog_enabled = true
    environment.fog_light_color = Color("b9cdd1")
    environment.fog_light_energy = 0.45
    environment.fog_sun_scatter = 0.12
    environment.fog_density = 0.00008
    environment.fog_height = 0.0
    environment.fog_height_density = 0.002
    environment.fog_aerial_perspective = 0.30
    environment.fog_sky_affect = 0.0
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    sun.light_color = Color("fff1d8")
    sun.light_energy = 1.15
    sun.light_angular_distance = 0.65
    sun.shadow_enabled = true
    sun.shadow_bias = 0.025
    sun.shadow_normal_bias = 0.18
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    sun.directional_shadow_blend_splits = true

static func update_view(environment: Environment, sun: DirectionalLight3D, view_width: float, camera_distance: float, relief: float = 1.0) -> void:
    sun.directional_shadow_max_distance = maxf(camera_distance + view_width * 1.3, 2.0)
    sun.shadow_blur = 1.4
    environment.ssao_enabled = relief > 0.05 and view_width < 1700.0
    # Aerial perspective remains faint; the flat overview retains its palette.
    environment.fog_density = lerpf(0.000015, 0.00010, clampf(relief, 0.0, 1.0))
