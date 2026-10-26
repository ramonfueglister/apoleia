shader_type spatial;
render_mode cull_disabled, diffuse_burley, depth_draw_always;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_appearance.gdshaderinc"

// Dedicated marine surface; terrain and inland/river callers share the same
// optical library. Source bathymetry is independent of the flat water plane.
uniform float relief=0.0;
uniform float view_width=1.0;
uniform bool use_display_coast_distance=false;
uniform sampler2D display_coast_distance_tex : filter_nearest, repeat_disable;
uniform vec2 display_coast_world_min=vec2(0.0);
uniform vec2 display_coast_world_size=vec2(1.0);
varying vec2 water_position;

float ocean_coast_decode(ivec2 c) {
    vec2 code=texelFetch(display_coast_distance_tex,clamp(c,ivec2(0),textureSize(display_coast_distance_tex,0)-ivec2(1)),0).rg;
    return (round(code.r*255.0)*256.0+round(code.g*255.0))*2.0;
}
float ocean_coast_distance(vec2 p) {
    vec2 uv=(p-display_coast_world_min)/display_coast_world_size;
    if(clipmap_enabled || !use_display_coast_distance || !inside_domain(uv))return max(water_distance_at(p),0.0);
    vec2 q=uv*vec2(textureSize(display_coast_distance_tex,0))-0.5;
    ivec2 c=ivec2(floor(q));vec2 f=fract(q);
    float d=mix(mix(ocean_coast_decode(c),ocean_coast_decode(c+ivec2(1,0)),f.x),mix(ocean_coast_decode(c+ivec2(0,1)),ocean_coast_decode(c+ivec2(1)),f.x),f.y);
    return material_cohort_value_4(p,vec4(d,0.0,0.0,0.0)).x;
}
void vertex() {
    if(clipmap_enabled)VERTEX.xz=clipmap_origin+VERTEX.xz*clipmap_span;
    water_position=VERTEX.xz;
    VERTEX.y=0.0;
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment() {
    if(water_kind_at(water_position)!=1.0)discard;
    // Solid marine pixels use the depth-writing alpha colour pass. This avoids
    // the Metal Forward+ opaque EQUAL/prepass mismatch while retaining the
    // source mask, depth testing and actual water depth for later effects.
    ALPHA=1.0;
    float distance=water_distance_at(water_position);
    float depth=max(-model_height_at(water_position),0.0);
    float pixel=max(length(dFdx(water_position)),length(dFdy(water_position)));
    vec3 color;vec3 normal;float roughness;float specular;
    water_appearance(water_position,distance,ocean_coast_distance(water_position),depth,1,relief,view_width,pixel,TIME,color,normal,roughness,specular);
    vec3 sky_radiance;float fresnel;
    vec3 view_direction=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    water_environment_reflection(normal,view_direction,1,relief,view_width,sky_radiance,fresnel);
    ALBEDO=color*(1.0-fresnel);
    EMISSION=sky_radiance*fresnel;
    NORMAL=normalize((VIEW_MATRIX*vec4(normal,0.0)).xyz);
    ROUGHNESS=roughness;
    SPECULAR=specular;
}
