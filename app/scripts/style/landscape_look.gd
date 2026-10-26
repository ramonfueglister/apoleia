# Visual look layer (tonemapping, AO, haze, sun). Kept apart from
# landscape_style.gd, whose file hash keys the fixed forest mesh cache.
extends RefCounted

static var _environment: Environment

static func configure_environment(environment: Environment, sun: DirectionalLight3D) -> void:
    _environment = environment
    environment.background_color = Color("9fc2d6")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("c9dbe6")
    environment.ambient_light_energy = 0.42
    environment.tonemap_mode = Environment.TONE_MAPPER_ACES
    environment.tonemap_exposure = 0.9
    environment.tonemap_white = 6.0
    environment.adjustment_enabled = true
    environment.adjustment_saturation = 0.98
    environment.adjustment_contrast = 1.04
    # Forward+ only; soft contact darkening under crowns and in valleys.
    environment.ssao_enabled = true
    environment.ssao_radius = 0.6
    environment.ssao_intensity = 1.6
    environment.ssao_power = 1.4
    environment.ssao_detail = 0.4
    environment.ssao_light_affect = 0.15
    # Aerial perspective: light depth haze towards the upper (far) screen edge.
    environment.fog_enabled = true
    environment.fog_mode = Environment.FOG_MODE_DEPTH
    environment.fog_light_color = Color("b9d3e2")
    environment.fog_light_energy = 1.0
    environment.fog_sun_scatter = 0.08
    environment.fog_density = 0.0
    environment.fog_depth_curve = 1.6
    environment.fog_aerial_perspective = 0.0
    sun.light_color = Color("fff0d6")
    sun.light_energy = 1.55
    sun.light_angular_distance = 1.2
    sun.shadow_blur = 1.6
    sun.shadow_opacity = 0.82

static func update_view(_sun: DirectionalLight3D, _view_width: float, camera_distance: float, half_view_height: float, elevation_degrees: float) -> void:
    if not _environment or half_view_height <= 0.0: return
    # Ortho camera: ground depth grows from bottom to top of the screen.
    var spread = half_view_height / maxf(tan(deg_to_rad(elevation_degrees)), 0.2)
    _environment.fog_depth_begin = maxf(camera_distance - spread * 0.1, 0.0)
    _environment.fog_depth_end = camera_distance + spread * 2.2
    # Strongest haze at oblique regional views, almost none in the flat map.
    var oblique = clampf((70.0 - elevation_degrees) / 30.0, 0.0, 1.0)
    _environment.fog_density = lerpf(0.0, 0.16, oblique)

# Display-only river widening; source centrelines stay unchanged.
const RIVER_WIDTH_SCALE = 2.6

# Screen-width floor: thin map lines far out, broad diorama rivers up close.
static func river_minimum_px(view_width: float) -> float:
    var near = clampf((log(1800.0) - log(maxf(view_width, 1.0))) / (log(1800.0) - log(300.0)), 0.0, 1.0)
    return lerpf(1.6, 9.0, near * near)

static func terrain_parameters() -> Dictionary:
    return {
        "open_color": Color("9aa341"),
        "meadow_color": Color("8f9e3b"),
        "forest_ground_color": Color("3f6227"),
        "dry_color": Color("c6ad66"),
        "rock_color": Color("b2a58e"),
        "rock_shadow_color": Color("8a7d6a"),
        "snow_color": Color("f1efe8"),
        "shore_color": Color("e6d6a2"),
        "look_olive_color": Color("737f33"),
        "look_ochre_color": Color("c2a95c"),
        "look_lime_color": Color("a9ad46"),
        "sea_deep_color": Color("123f78"),
        "sea_open_color": Color("1d5596"),
        "sea_shallow_color": Color("3b93a6"),
        "sea_foam_color": Color("eef6f2"),
        "sea_sky_color": Color("6f9fc4"),
    }

static func water_parameters() -> Dictionary:
    return {
        "river_color": Color("2b8fa6"),
        "river_edge_color": Color("4fb2b8"),
        "river_bank_color": Color("c9bd86"),
        "minimum_screen_width_px": 2.2,
        "surface_overlay_offset_world": 0.004,
    }
