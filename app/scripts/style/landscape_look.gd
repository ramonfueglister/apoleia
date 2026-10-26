# Visual look layer (tonemapping, AO, haze, sun). Kept apart from
# landscape_style.gd, whose file hash keys the fixed forest mesh cache.
extends RefCounted

static var _environment: Environment

static func configure_environment(environment: Environment, sun: DirectionalLight3D) -> void:
    _environment = environment
    environment.background_color = Color("9fc2d6")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    # Cool fill so shadow sides stay light and readable (reference p10).
    environment.ambient_light_color = Color("b9cfe8")
    environment.ambient_light_energy = 0.85
    # Crisp, saturated look (reference): AgX keeps saturation in the
    # highlights better than ACES at this exposure.
    environment.tonemap_mode = Environment.TONE_MAPPER_AGX
    environment.tonemap_exposure = 1.18
    environment.tonemap_white = 4.0
    environment.adjustment_enabled = true
    environment.adjustment_saturation = 0.86
    environment.adjustment_contrast = 1.10
    environment.glow_enabled = false
    # Forward+ only; soft contact darkening under crowns and in valleys.
    environment.ssao_enabled = true
    # Small, light AO: contact shading without dark smudged halos.
    environment.ssao_radius = 0.35
    environment.ssao_intensity = 0.5
    environment.ssao_power = 1.4
    environment.ssao_detail = 0.4
    environment.ssao_light_affect = 0.15
    # Aerial perspective: light depth haze towards the upper (far) screen edge.
    environment.fog_enabled = true
    environment.fog_mode = Environment.FOG_MODE_DEPTH
    environment.fog_light_color = Color("9fb8c9")
    environment.fog_light_energy = 1.0
    environment.fog_sun_scatter = 0.08
    environment.fog_density = 0.0
    environment.fog_depth_curve = 1.6
    environment.fog_aerial_perspective = 0.0
    sun.rotation_degrees = Vector3(-40.0, -62.0, 0.0)
    sun.light_color = Color("ffe9c8")
    sun.light_energy = 1.92
    sun.light_angular_distance = 0.0
    sun.shadow_blur = 0.25
    sun.shadow_opacity = 0.6

static func update_view(sun: DirectionalLight3D, view_width: float, camera_distance: float, fov_degrees: float, elevation_degrees: float) -> void:
    # No crowns are drawn beyond ~1600 model units; terrain casts no shadow.
    sun.shadow_enabled = view_width < 1700.0
    if not _environment or camera_distance <= 0.0: return
    _environment.ssao_enabled = view_width < 1700.0
    # Perspective: depth of the upper screen edge relative to the focus.
    var a = deg_to_rad(elevation_degrees)
    var top = sin(a) / maxf(sin(a - deg_to_rad(fov_degrees) * 0.5), 0.05)
    # Aerial perspective only at the very top of the frame: clear and
    # saturated deep into the view like the reference.
    _environment.fog_depth_begin = camera_distance * maxf(top * 0.95, 1.1)
    _environment.fog_depth_end = camera_distance * maxf(top * 1.6, 1.5)
    var oblique = clampf((50.0 - elevation_degrees) / 14.0, 0.0, 1.0)
    _environment.fog_density = lerpf(0.0, 0.04, oblique)

# Vertical exaggeration: one parameter for the medium/close views (low,
# gentle hills), easing to the regional/continental value further out.
const CLOSE_HEIGHT_SCALE = 7.0
const FAR_HEIGHT_SCALE = 14.0

static func display_height_scale(view_width: float) -> float:
    return lerpf(CLOSE_HEIGHT_SCALE, FAR_HEIGHT_SCALE, smoothstep(600.0, 4500.0, view_width))

# Display-only river widening; source centrelines stay unchanged.
const RIVER_WIDTH_SCALE = 1.6

# Screen-width floor: thin map lines far out, broad diorama rivers up close.
static func river_minimum_px(view_width: float) -> float:
    var near = clampf((log(1800.0) - log(maxf(view_width, 1.0))) / (log(1800.0) - log(300.0)), 0.0, 1.0)
    return lerpf(1.6, 15.0, near * near)

static func terrain_parameters() -> Dictionary:
    return {
        "open_color": Color("b4a248"),
        "meadow_color": Color("9a9341"),
        "forest_ground_color": Color("4f5f2c"),
        "dry_color": Color("b8a066"),
        "rock_color": Color("a89a82"),
        "rock_shadow_color": Color("6f6555"),
        "snow_color": Color("f1efe8"),
        "shore_color": Color("e6d6a2"),
        "shore_display_span_world": 4.5,
        "look_olive_color": Color("7c7a35"),
        "look_ochre_color": Color("bb9c55"),
        "look_lime_color": Color("b6a84a"),
        # Painted land look (terrain_land_look.gdshaderinc).
        "land_grass_color": Color("7a8538"),
        "land_lime_color": Color("98953e"),
        "land_olive_color": Color("5a682c"),
        "land_ochre_color": Color("a2884f"),
        "land_forest_floor_color": Color("405425"),
        "land_dry_color": Color("ab9462"),
        "land_rock_light_color": Color("b09c86"),
        "land_rock_dark_color": Color("62554a"),
        "land_snow_color": Color("f2efe9"),
        "land_valley_tint": Color("9db3b8"),
        "land_facet_tilt": 0.22,
        "sea_deep_color": Color("1d497e"),
        "sea_open_color": Color("235483"),
        "sea_shallow_color": Color("48909b"),
        "sea_foam_color": Color("eef6f2"),
        "sea_sky_color": Color("6f9fc4"),
    }

static func water_parameters() -> Dictionary:
    return {
        "river_color": Color("1f6aa6"),
        "river_edge_color": Color("4fb2b8"),
        "river_bank_color": Color("c9bd86"),
        "minimum_screen_width_px": 2.2,
        "surface_overlay_offset_world": 0.004,
    }

static func water_look_parameters() -> Dictionary:
    return {
        "water_deep_tint": Color("123c6a"),
        "water_open_tint": Color("17467a"),
        "water_shallow_tint": Color("4fa3a8"),
        "water_seabed_tint": Color("9fae8a"),
        "water_foam_tint": Color("eef6f2"),
        "water_sky_zenith": Color("3f6690"),
        "water_sky_horizon": Color("8eaabd"),
        "water_sun_tint": Color("fff0d0"),
        "water_facet_size": 1.4,
        "water_glitter": 0.08,
    }
