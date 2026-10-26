shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "model_sampling.gdshaderinc"
#include "water_appearance.gdshaderinc"
uniform bool streamed_river=false;
uniform float terrain_morph_alpha=1.0;
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
varying vec2 flow_tangent;
varying float flow_station;
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
    river_side=UV2.x;
    river_half_width=half_width;flow_tangent=vec2(NORMAL.z,-NORMAL.x);flow_station=UV.x;
    // CPU mesh river bases are already in displayed-world height, before relief.
    // Only the raw raster fallback needs the explicit display mapping here.
    float ground=use_model_mesh ? VERTEX.y : terrain_height_at(VERTEX.xz)*0.001*display_height_scale;
    if(clipmap_enabled){
        ground=clipmap_ring_height(VERTEX.xz)*0.001*display_height_scale;
    }else if(streamed_river){
        float ya=CUSTOM0.x+(CUSTOM0.y-CUSTOM0.x)*terrain_morph_alpha;
        float yb=CUSTOM0.z+(CUSTOM0.w-CUSTOM0.z)*terrain_morph_alpha;
        float yc=CUSTOM1.x+(CUSTOM1.y-CUSTOM1.x)*terrain_morph_alpha;
        ground=(ya*CUSTOM1.z+yb*CUSTOM1.w+yc*(1.0-CUSTOM1.z-CUSTOM1.w))*display_height_scale;
    }
    VERTEX.y=ground*relief+surface_overlay_offset_world;
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment(){
    if(water_distance_at(river_position)>0.0) discard;
    float edge=streamed_river ? abs(river_side)/max(river_half_width,0.000001) : abs(river_side);
    if(edge>1.0)discard;
    vec3 water; // Shared appearance palette replaces the old duplicate edge gradient.
    vec3 water_normal;float water_roughness;float water_specular;
    float pixel=max(length(dFdx(river_position)),length(dFdy(river_position)));
    water_river_appearance(river_position,flow_station,flow_tangent,streamed_river ? river_side : river_side*river_half_width,river_half_width,relief,view_width,pixel,TIME,water,water_normal,water_roughness,water_specular);
    vec3 sky_radiance;float fresnel;
    vec3 view_direction=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    water_environment_reflection(water_normal,view_direction,3,relief,view_width,sky_radiance,fresnel);
    float bank=smoothstep(0.72,1.0,edge);
    ALBEDO=mix(water*(1.0-fresnel),river_bank_color.rgb,bank*0.68);
    EMISSION=sky_radiance*fresnel*(1.0-bank);
    NORMAL=normalize((VIEW_MATRIX*vec4(water_normal,0.0)).xyz);
    ROUGHNESS=water_roughness;
    SPECULAR=water_specular;
}
