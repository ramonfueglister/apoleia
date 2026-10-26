class_name PolyWaterStyle
extends RefCounted
## Original material-only interpretation of the approved four-scale study.
## No IO, source fields, node creation, camera/LOD ownership or geometry changes.

const REVISION = "diorama-water-r7"
const SHADER_INCLUDE = "res://shaders/water_appearance.gdshaderinc"

static func parameters() -> Dictionary:
    # Godot source_color uniforms convert these authored sRGB colours once.
    # Do not manually gamma-decode these Colors in the shader or caller.
    return {
        "water_style_deep": Color("0f3f78"),
        "water_style_basin": Color("1b5fa3"),
        "water_style_shelf": Color("3fa7b5"),
        "water_style_shoal": Color("76bbb5"),
        "water_style_inland": Color("216b96"),
        "water_style_river": Color("2f819a"),
        "water_style_edge_light": Color("c2d9c8"),
        "water_style_wave_strength": 0.30,
        "water_style_surface_strength": 0.035,
        "water_style_shore_accent": 0.42,
    }

static func apply_to(material: ShaderMaterial) -> void:
    assert(material != null and material.shader != null)
    var values = parameters()
    for name in values:
        material.set_shader_parameter(name, values[name])

static func contract() -> Dictionary:
    return {
        "revision": REVISION,
        "status": "implemented; native visual and performance validation pending",
        "coordinate_units": "world_xz/view_width/footprint: model kilometres; signed/display coast and positive bathymetry: source metres; time: seconds",
        "roles": {0:"land (caller must retain ground)",1:"marine",2:"inland water",3:"explicit actual river"},
        "bathymetry": "max(-owner composed source model height,0), before zero-height marine vertices, without display Y scale",
        "inland_depth": "none; lake bank colour is a declared graphic distance proxy, river has no depth proxy",
        "source_ownership": "caller supplies composed resident child/parent scalars; this library has no sampler or source IO",
        "footprint": "caller supplies conservative max screen derivative length of model-world XZ, including isometric foreshortening",
        "normal": "unit world-space Y-up; caller transforms with VIEW_MATRIX at w=0",
        "flat": "relief=0 returns Y-up normal, roughness1/specular0 and stable geographic depth colours",
        "animation": "decorative world-anchored material waves; no physical wave-speed claim",
        "geometry": "unchanged; no displacement, bounds, coastline, water role, picking or streaming mutations",
        "colour": "source_color uniforms already linearized; no additional gamma decode",
    }
