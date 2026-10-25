shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "model_sampling.gdshaderinc"
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
    river_side=UV2.x;
    // CPU mesh river bases are already in displayed-world height, before relief.
    // Only the raw raster fallback needs the explicit display mapping here.
    float ground=use_model_mesh ? VERTEX.y : terrain_height_at(VERTEX.xz)*0.001*display_height_scale;
    VERTEX.y=ground*relief+surface_overlay_offset_world;
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment(){
    if(water_distance_at(river_position)>0.0) discard;
    float edge=abs(river_side);
    vec3 water=mix(river_color.rgb,river_edge_color.rgb,smoothstep(0.48,0.90,edge)*0.65);
    ALBEDO=mix(water,river_bank_color.rgb,smoothstep(0.93,1.0,edge)*0.42);
    ROUGHNESS=0.72;
    SPECULAR=0.22;
}
