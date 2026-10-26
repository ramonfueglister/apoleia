shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "model_sampling.gdshaderinc"
#include "water_appearance.gdshaderinc"
uniform float relief=0.0;
uniform float view_width=1.0;
uniform float viewport_width=1920.0;
uniform float minimum_screen_width_px=1.6;
uniform float projection_vertical_scale=1.0;
uniform float surface_overlay_offset_world=0.004;
uniform vec4 river_color : source_color = vec4(0.157,0.431,0.529,1.0);
uniform vec4 river_edge_color : source_color = vec4(0.392,0.561,0.553,1.0);
uniform vec4 river_bank_color : source_color = vec4(0.710,0.678,0.486,1.0);
varying vec2 river_position;
varying float signed_distance_world;
varying float dynamic_half_width;
void vertex(){
    // NORMAL.xz carries the source segment's horizontal unit cross direction.
    float side_projection=max(length(vec2(NORMAL.x,NORMAL.z*projection_vertical_scale)),0.001);
    dynamic_half_width=max(UV2.y*0.5,view_width/max(viewport_width,1.0)*minimum_screen_width_px*0.5/side_projection);
    signed_distance_world=UV2.x;
    river_position=VERTEX.xz;
    VERTEX.y=VERTEX.y*relief+surface_overlay_offset_world;
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment(){
    // UV2.x is MODEL DISTANCE, never normalized by the enclosing mesh width.
    // Both source/world width and current view/pitch therefore remain effective.
    float edge=abs(signed_distance_world)/max(dynamic_half_width,0.0000001);
    if(edge>1.0 || water_distance_at(river_position)>0.0) discard;
    vec3 water;vec3 normal;float roughness;float specular;
    float pixel=max(length(dFdx(river_position)),length(dFdy(river_position)));
    water_appearance(river_position,max(dynamic_half_width-abs(signed_distance_world),0.0)*1000.0,0.0,0.0,3,relief,view_width,pixel,TIME,water,normal,roughness,specular);
    float bank=smoothstep(0.72,1.0,edge);
    ALBEDO=mix(water,river_bank_color.rgb,bank*0.68);
    NORMAL=normalize((VIEW_MATRIX*vec4(normal,0.0)).xyz);
    ROUGHNESS=roughness;
    SPECULAR=specular;
}
