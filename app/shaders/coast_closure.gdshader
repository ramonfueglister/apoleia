shader_type spatial;
render_mode cull_disabled, diffuse_burley, depth_draw_always;
#include "res://shaders/terrain_clipmap.gdshaderinc"

// Source-contour closure only: local XZ [0,1], input Y 0=sea foot / 1=top.
// No horizontal contour shift, decorative height or marine fragment discard.
uniform float relief=1.0;
uniform float display_height_scale=12.0;
uniform vec4 shore_color : source_color=vec4(0.769,0.745,0.518,1.0);
uniform vec4 rock_color : source_color=vec4(0.773,0.718,0.616,1.0);
uniform vec4 rock_shadow_color : source_color=vec4(0.533,0.549,0.475,1.0);
varying float coast_top_weight;
varying float coast_source_height;
varying vec2 coast_position;

float coast_grid_vertex(vec2 p) {
    return clipmap_water_kind(p)==1.0 ? 0.0 : clipmap_ring_height(p);
}
float coast_rendered_height(vec2 p) {
    float step_size=clipmap_span/64.0;
    vec2 q=clamp((p-clipmap_origin)/step_size,vec2(0.0),vec2(64.0));
    vec2 cell=min(floor(q),vec2(63.0));vec2 f=q-cell;
    vec2 corner=clipmap_origin+cell*step_size;
    float a=coast_grid_vertex(corner);
    float b=coast_grid_vertex(corner+vec2(step_size,0.0));
    float c=coast_grid_vertex(corner+vec2(0.0,step_size));
    float d=coast_grid_vertex(corner+vec2(step_size));
    return f.x+f.y<1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
void vertex() {
    coast_top_weight=clamp(VERTEX.y,0.0,1.0);
    vec2 p=clipmap_origin+VERTEX.xz*clipmap_span;
    coast_source_height=max(coast_rendered_height(p),0.0);
    VERTEX=vec3(p.x,coast_source_height*0.001*display_height_scale*relief*coast_top_weight,p.y);
    coast_position=p;
    vec2 step_size=tile_rect.zw/vec2(textureSize(tile_water_tex,0)-ivec2(1));
    float dx=clipmap_water_distance(p+vec2(step_size.x,0.0))-clipmap_water_distance(p-vec2(step_size.x,0.0));
    float dz=clipmap_water_distance(p+vec2(0.0,step_size.y))-clipmap_water_distance(p-vec2(0.0,step_size.y));
    vec3 wall_normal=normalize(vec3(dx,0.00001,dz));
    vec3 source_normal=clipmap_normal(p);
    vec3 top_normal=normalize(vec3(source_normal.x,source_normal.y/max(display_height_scale*relief,0.0001),source_normal.z));
    NORMAL=normalize(mix(wall_normal,top_normal,coast_top_weight*0.45));
}
void fragment() {
    float cliff=smoothstep(25.0,180.0,coast_source_height);
    vec3 stone=mix(rock_shadow_color.rgb,rock_color.rgb,0.82);
    float luminance=dot(stone,vec3(0.2126,0.7152,0.0722));
    stone=mix(stone,vec3(luminance),0.20);
    float upper=smoothstep(0.12,0.72,coast_top_weight);
    ALBEDO=mix(shore_color.rgb,stone,cliff*upper)*mix(0.92,1.0,coast_top_weight);
    ROUGHNESS=0.97;
    SPECULAR=0.10;
    ALPHA=1.0;
}
