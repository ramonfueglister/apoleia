shader_type spatial;
// Own sea surface: the zero-height marine plane. Land keeps its terrain
// shader; ownership is the same SDF-based water kind as before.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_look.gdshaderinc"
uniform float relief=0.0;
uniform float view_width=1.0;
uniform float viewport_width=1920.0;
uniform vec2 shading_origin=vec2(0.0);
uniform bool use_display_coast_distance=false;
uniform sampler2D display_coast_distance_tex : filter_nearest, repeat_disable;
uniform vec2 display_coast_world_min=vec2(0.0);
uniform vec2 display_coast_world_size=vec2(1.0);
uniform float shallow_display_span_world=24.0;
varying vec3 world_position;

float display_coast_decode(ivec2 cell) {
    vec2 code=texelFetch(display_coast_distance_tex,clamp(cell,ivec2(0),textureSize(display_coast_distance_tex,0)-ivec2(1)),0).rg;
    return (round(code.r*255.0)*256.0+round(code.g*255.0))*2.0;
}
float display_coast_distance_at(vec2 uv) {
    vec2 q=uv*vec2(textureSize(display_coast_distance_tex,0))-0.5;
    ivec2 cell=ivec2(floor(q));vec2 f=fract(q);
    return mix(mix(display_coast_decode(cell),display_coast_decode(cell+ivec2(1,0)),f.x),mix(display_coast_decode(cell+ivec2(0,1)),display_coast_decode(cell+ivec2(1)),f.x),f.y);
}

void vertex() {
    VERTEX.y=0.0;
    NORMAL=vec3(0.0,1.0,0.0);
    world_position=VERTEX;
}
void fragment() {
    vec2 p=world_position.xz;
    if(water_kind_at(p)!=1.0) discard;
    float distance=water_distance_at(p);
    // Near the contour the exact SDF; further out the graphic sidecar that
    // extends the range beyond the packed 3 km.
    float coast_m=max(distance,0.0);
    vec2 coast_uv=(p-display_coast_world_min)/display_coast_world_size;
    if(use_display_coast_distance && inside_domain(coast_uv)) {
        float far=display_coast_distance_at(coast_uv);
        coast_m=mix(coast_m,max(far,coast_m),smoothstep(1000.0,2500.0,far));
    }
    float depth=max(-model_height_at(p),0.0);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float px_m=max(length(vec2(dFdx(distance),dFdy(distance))),1.0);
    float calm=smoothstep(0.05,0.6,relief);
    float saum_scale=mix(0.22,1.0,smoothstep(0.7,1.0,relief));
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    WaterSample w=water_shade(p,coast_m,depth,footprint,calm,view_world,vec2(0.0),px_m,saum_scale);
    // Crisp shoreline: a thin lighter line exactly at the contour in the map view.
    float edge=1.0-smoothstep(0.0,px_m*1.2,coast_m);
    ALBEDO=mix(w.albedo,w.albedo*1.25+0.05,edge*(1.0-calm)*0.6);
    EMISSION=w.emission;
    ROUGHNESS=w.roughness;
    SPECULAR=0.25;
    NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
}
