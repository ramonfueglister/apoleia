shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "model_sampling.gdshaderinc"
#include "water_look.gdshaderinc"
uniform float relief=0.0;
uniform float display_height_scale=1.0;
uniform float view_width=1.0;
uniform float viewport_width=1920.0;
uniform float minimum_screen_width_px=1.6;
// Runtime supplies sin(camera elevation) for the fixed-azimuth projection.
uniform float projection_vertical_scale=1.0;
// Depth-overlay guard above measured CPU/Float32 transport residual; this is
// neither surveyed water elevation nor a change to the source centreline.
uniform float surface_overlay_offset_world=0.004;
uniform bool use_model_mesh=false;
uniform vec4 river_color : source_color = vec4(0.157,0.431,0.529,1.0);
uniform vec4 river_edge_color : source_color = vec4(0.392,0.561,0.553,1.0);
uniform vec4 river_bank_color : source_color = vec4(0.710,0.678,0.486,1.0);
varying vec2 river_position;
varying float river_side;
varying vec2 river_flow;
varying float river_half_width;
// Authored Color uniforms arrive linearized by Godot. The isolated GPU
// probe verified source_color/raw Color == StandardMaterial; manual decoding
// here double-decoded gray128 to56. Vertex COLOR follows a different path.
void vertex(){
    // Documented cartographic width; source centerline and topology unchanged.
    float side_projection=max(length(vec2(NORMAL.x,NORMAL.z*projection_vertical_scale)),0.001);
    float half_width=max(UV2.y*0.5,view_width/max(viewport_width,1.0)*minimum_screen_width_px*0.5/side_projection);
    // CPU-supported strips already have their final source-bound X/Z edges.
    // Only the centreline fallback expands here, with the same pixel contract.
    if(!use_model_mesh) VERTEX.xz+=NORMAL.xz*UV2.x*half_width;
    river_position=VERTEX.xz;
    river_flow=normalize(vec2(-NORMAL.z,NORMAL.x)+vec2(0.0001));
    river_half_width=half_width;
    river_side=UV2.x;
    // CPU mesh river bases are already in displayed-world height, before relief.
    // Only the raw raster fallback needs the explicit display mapping here.
    float ground=use_model_mesh ? VERTEX.y : terrain_height_at(VERTEX.xz)*0.001*display_height_scale;
    VERTEX.y=ground*relief+surface_overlay_offset_world;
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment(){
    float sea_distance=water_distance_at(river_position);
    if(sea_distance>0.0) discard;
    float edge=abs(river_side);
    float footprint=max(length(dFdx(river_position)),length(dFdy(river_position)));
    float bank_m=(1.0-edge)*river_half_width*1000.0;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float calm=smoothstep(0.05,0.6,relief);
    // Same optics as the sea; flow along the river line, no surf bands.
    WaterSample w=water_shade(river_position,bank_m+400.0,9.0+(1.0-edge)*22.0,footprint,calm,view_world,river_flow*0.6,max(footprint*1000.0,1.0),0.0);
    vec3 water=mix(w.albedo,river_color.rgb,0.55);
    // Current streaks along the flow direction.
    float along=dot(river_position,river_flow);
    float across=dot(river_position,vec2(-river_flow.y,river_flow.x));
    float streak=smoothstep(0.62,0.9,wl_fnoise(vec2(along*0.9-TIME*0.5,across*6.0),footprint*6.0))*calm*(1.0-edge);
    water=mix(water,water*1.18+0.03,streak*0.5);
    // Far views: rivers recede to a thin map blue instead of bright turquoise.
    water=mix(water,vec3(0.06,0.20,0.36),smoothstep(900.0,3500.0,view_width)*0.88);
    // No per-strip edge tint: strips overlap at joints and would show seams.
    ALBEDO=water;
    EMISSION=w.emission*0.6*(1.0-smoothstep(0.8,1.0,edge));
    ROUGHNESS=w.roughness;
    SPECULAR=0.04;
    NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
}
