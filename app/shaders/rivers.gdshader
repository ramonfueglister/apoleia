shader_type spatial;
render_mode cull_disabled, diffuse_burley, blend_mix, depth_draw_never;
#include "model_sampling.gdshaderinc"
#include "water_look.gdshaderinc"
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
varying vec2 river_flow;
varying float river_half_width;
// Authored Color uniforms arrive linearized by Godot. The isolated GPU
// probe verified source_color/raw Color == StandardMaterial; manual decoding
// here double-decoded gray128 to56. Vertex COLOR follows a different path.
void vertex(){
    // Documented cartographic width; source centerline and topology unchanged.
    vec2 side_unit=normalize(NORMAL.xz+vec2(0.000001));
    float side_projection=max(length(vec2(side_unit.x,side_unit.y*projection_vertical_scale)),0.001);
    // Look layer: screen floor grows towards the close views (thin map line
    // far out, broad diorama river near; same curve as LandscapeLook).
    // Thin in the regional view (2-4 px), medium-broad in the close view.
    float floor_px=max(minimum_screen_width_px,mix(1.6,4.0,smoothstep(1800.0,400.0,view_width))+9.0*smoothstep(300.0,90.0,view_width));
    float half_width=max(UV2.y*0.5*0.9,view_width/max(viewport_width,1.0)*floor_px*0.5/side_projection);
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
    if(clipmap_enabled){
        ground=clipmap_surface_height(VERTEX.xz)*0.001*display_height_scale;
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
    float sea_distance=water_distance_at(river_position);
    if(sea_distance>0.0) discard;
    // Streamed/clipmap strips carry the side offset in world units.
    float edge=streamed_river ? abs(river_side)/max(river_half_width,0.000001) : abs(river_side);
    float footprint=max(length(dFdx(river_position)),length(dFdy(river_position)));
    float bank_m=(1.0-edge)*river_half_width*1000.0;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float calm=smoothstep(0.05,0.6,relief);
    // One water body with the sea: same function and shallow palette; the
    // depth eases towards the sea's mouth plume over the last ~3 km.
    float to_sea=1.0-smoothstep(0.0,3000.0,-sea_distance);
    float depth=mix(14.0+(1.0-edge)*16.0,12.0,to_sea);
    WaterSample w=water_shade(river_position,bank_m+3000.0,depth,footprint,calm,view_world,river_flow*0.6,max(footprint*1000.0,1.0),0.0,1.0);
    // Stronger mid-blue than the sea's turquoise rim (reference arms).
    // Muted mid teal-blue like the reference rivers.
    vec3 water=mix(w.albedo,vec3(0.026,0.15,0.23),0.7);
    // Current streaks along the flow direction.
    float along=dot(river_position,river_flow);
    float across=dot(river_position,vec2(-river_flow.y,river_flow.x));
    float streak=smoothstep(0.62,0.9,wl_fnoise(vec2(along*0.9-TIME*0.5,across*6.0),footprint*6.0))*calm*(1.0-edge)*(1.0-to_sea);
    water=mix(water,water*1.12+0.02,streak*0.4);
    // Far views: rivers recede to a thin map blue instead of bright turquoise.
    water=mix(water,vec3(0.06,0.20,0.36),smoothstep(900.0,3500.0,view_width)*0.88);
    // Light sand bank along the outer edge (islands between delta arms).
    float near_view=1.0-smoothstep(600.0,1500.0,view_width);
    ALBEDO=mix(water,vec3(0.66,0.55,0.29),smoothstep(0.80,0.98,edge)*0.7*near_view);
    EMISSION=w.emission*0.5;
    ROUGHNESS=w.roughness;
    SPECULAR=0.04;
    NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
    // Anti-aliased bank: soft coverage over ~1.5 px of the strip edge.
    float aa=max(fwidth(edge)*1.5,0.02);
    ALPHA=1.0-smoothstep(1.0-aa,1.0,edge);
}
