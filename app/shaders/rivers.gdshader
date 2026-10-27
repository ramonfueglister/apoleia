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
varying float river_symbolic;
varying float river_base_width;
// Height range of the rendered 65-grid cell around p (clipmap path).
float river_cell_range(vec2 p){
    float step_size=clipmap_span/64.0;
    vec2 q=clamp((p-clipmap_origin)/step_size,vec2(0.0),vec2(64.0));
    vec2 corner=clipmap_origin+min(floor(q),vec2(63.0))*step_size;
    float a=clipmap_surface_vertex(corner);
    float b=clipmap_surface_vertex(corner+vec2(step_size,0.0));
    float c=clipmap_surface_vertex(corner+vec2(0.0,step_size));
    float d=clipmap_surface_vertex(corner+vec2(step_size));
    return max(max(a,b),max(c,d))-min(min(a,b),min(c,d));
}
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
    float floor_px=max(minimum_screen_width_px,mix(1.6,4.0,smoothstep(1800.0,400.0,view_width))+6.0*smoothstep(450.0,150.0,view_width));
    float half_width=max(UV2.y*0.5*0.9,view_width/max(viewport_width,1.0)*floor_px*0.5/side_projection);
    // CPU-supported strips already have their final source-bound X/Z edges.
    // Only the centreline fallback expands here, with the same pixel contract.
    if(!use_model_mesh) VERTEX.xz+=NORMAL.xz*UV2.x*half_width;
    river_position=VERTEX.xz;
    river_flow=normalize(vec2(-NORMAL.z,NORMAL.x)+vec2(0.0001));
    river_half_width=half_width;
    river_symbolic=UV2.y;
    // Clipmap strips carry the unwidened source width in UV.y; 0 elsewhere.
    river_base_width=UV.y;
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
    if(clipmap_enabled){
        // On coarse levels (16 km cells in the far view) the ribbon quads cut
        // across the terrain triangles' creases and dip under the convex ones,
        // which broke far rivers into pieces. Move the vertex towards the
        // camera along its view ray by the local cell relief: same screen
        // position, only the depth changes. Close views keep the exact surface.
        float pull=river_cell_range(VERTEX.xz)*0.001*display_height_scale*relief/max(projection_vertical_scale,0.3);
        pull*=smoothstep(300.0,1200.0,view_width);
        vec3 eye=(inverse(MODEL_MATRIX)*vec4(INV_VIEW_MATRIX[3].xyz,1.0)).xyz;
        VERTEX+=normalize(eye-VERTEX)*pull;
    }
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment(){
    // Zoom-dependent size filter on the unwidened source width, so a river
    // shows or hides as a whole; the far view keeps scalerank <= 7 (Tevere).
    float rank_width=river_base_width>0.0 ? river_base_width : river_symbolic/(use_model_mesh ? 1.0 : 1.6);
    if(rank_width<mix(0.0,0.025,smoothstep(500.0,1800.0,view_width))) discard;
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
    // Opaque mid teal-blue (reference #2d6f8f range), not the pale sky sheen.
    // Reference rivers ~#307884: teal (h185-194), v~0.5.
    // Reference #297377-#377a86 on screen; the lit albedo shows ~35 % brighter.
    vec3 water=mix(w.albedo,vec3(0.0136,0.095,0.102),0.97);
    // Current streaks along the flow direction.
    float along=dot(river_position,river_flow);
    float across=dot(river_position,vec2(-river_flow.y,river_flow.x));
    float streak=smoothstep(0.62,0.9,wl_fnoise(vec2(along*0.9-TIME*0.5,across*6.0),footprint*6.0))*calm*(1.0-edge)*(1.0-to_sea);
    water=mix(water,water*1.12+0.02,streak*0.4);
    // Far views: rivers recede to a thin map blue instead of bright turquoise.
    water=mix(water,vec3(0.02,0.08,0.16),smoothstep(700.0,2500.0,view_width)*0.9);
    // Light sand bank along the outer edge (islands between delta arms).
    float near_view=1.0-smoothstep(600.0,1500.0,view_width);
    // Bank tint only at the very edge (overlapping arm strips showed it as
    // bright stripes inside the water).
    ALBEDO=mix(water,vec3(0.66,0.55,0.29),smoothstep(0.93,1.0,edge)*0.35*near_view);
    EMISSION=vec3(0.0);
    ROUGHNESS=w.roughness;
    SPECULAR=0.04;
    NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
    // Anti-aliased bank: soft coverage over ~1.5 px of the strip edge.
    float aa=max(fwidth(edge)*0.8,0.005);
    ALPHA=1.0-smoothstep(1.0-aa,1.0,edge);
}
