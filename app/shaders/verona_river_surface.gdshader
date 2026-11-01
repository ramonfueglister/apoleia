shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/verona_river.gdshaderinc"
uniform sampler2D corner_tex : filter_nearest, repeat_disable;
uniform ivec2 corner_origin;
uniform ivec2 corner_size;
uniform vec2 world_min;
uniform float level_h;
varying vec2 river_xz;
varying float cache_valid;
float ground(vec2 p) {
 vec2 g=(p-world_min)/.25; ivec2 t=ivec2(floor(g)); vec2 u=fract(g);
 ivec2 px=t-corner_origin;
 if(any(lessThan(px,ivec2(0))) || any(greaterThanEqual(px,corner_size))) {return 0.0;}
 vec4 c=texelFetch(corner_tex,px,0);
 float h;
 if(abs(c.x-c.z)<=abs(c.y-c.w)) {
 h=u.x>=u.y ? c.x+(c.y-c.x)*u.x+(c.z-c.y)*u.y : c.x+(c.w-c.x)*u.y+(c.z-c.w)*u.x;
 }else{
 h=u.x+u.y<=1.0 ? c.x+(c.y-c.x)*u.x+(c.w-c.x)*u.y : c.z+(c.w-c.z)*(1.0-u.x)+(c.y-c.z)*(1.0-u.y);
 }
 return h*level_h;
}
void vertex(){
 river_xz=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
 ivec2 px=ivec2(floor((river_xz-world_min)/.25))-corner_origin;
 cache_valid=all(greaterThanEqual(px,ivec2(0))) && all(lessThan(px,corner_size)) ? 1.0 : 0.0;
 if(COLOR.r>.5 && cache_valid>.5){VERTEX.y=ground(river_xz); }
}
void fragment(){
 float d=vr_distance(river_xz);
 if(d>.077 || !verona_river_active || cache_valid<.999){discard;}
 ALBEDO=COLOR.g>.5 ? vec3(.275,.498,.780) : vec3(.39,.31,.21);
 ROUGHNESS=1.0;
}
