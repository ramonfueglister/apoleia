shader_type spatial;
render_mode cull_disabled;
uniform bool height_packed=true;
uniform sampler2D elevation_tex: filter_linear, repeat_disable;
uniform sampler2D water_tex: filter_linear, repeat_disable;
uniform sampler2D water_distance_tex: filter_nearest, repeat_disable;
uniform vec2 world_size;
uniform vec2 world_min;
uniform float relief=0.0;
uniform float view_width=1.0;
uniform float viewport_width=1920.0;
varying vec2 geo_uv;
float decode_water(ivec2 cell) {
    vec2 code=texelFetch(water_distance_tex,clamp(cell,ivec2(0),textureSize(water_distance_tex,0)-ivec2(1)),0).rg;
    return (round(code.r*255.0)*256.0+round(code.g*255.0))*0.125-4096.0;
}
float bilinear_water(vec2 uv) {
    vec2 p=uv*vec2(textureSize(water_distance_tex,0))-0.5;ivec2 c=ivec2(floor(p));vec2 f=fract(p);
    return mix(mix(decode_water(c),decode_water(c+ivec2(1,0)),f.x),mix(decode_water(c+ivec2(0,1)),decode_water(c+ivec2(1,1)),f.x),f.y);
}
float decode_height(ivec2 cell) {
    vec2 code=texelFetch(elevation_tex,clamp(cell,ivec2(0),textureSize(elevation_tex,0)-ivec2(1)),0).rg;
    return height_packed?(round(code.r*255.0)*256.0+round(code.g*255.0))*0.25-8192.0:code.r;
}
float bilinear_height(vec2 uv) {
    vec2 p=uv*vec2(textureSize(elevation_tex,0))-0.5;
    ivec2 c=ivec2(floor(p)); vec2 f=fract(p);
    return mix(mix(decode_height(c),decode_height(c+ivec2(1,0)),f.x),mix(decode_height(c+ivec2(0,1)),decode_height(c+ivec2(1,1)),f.x),f.y);
}
void vertex(){
    float half_width=max(UV2.y*0.5,view_width/viewport_width*0.40);
    VERTEX.xz+=NORMAL.xz*UV2.x*half_width;
    geo_uv=(VERTEX.xz-world_min)/world_size;
    float kind=texelFetch(water_tex,clamp(ivec2(floor(geo_uv*vec2(textureSize(water_tex,0)))),ivec2(0),textureSize(water_tex,0)-ivec2(1)),0).r*255.0;
    float height=kind==1.0?0.0:bilinear_height(geo_uv);
    VERTEX.y=height*0.001*relief+0.0002;
    NORMAL=vec3(0.0,1.0,0.0);
}
void fragment(){
    float distance=bilinear_water(geo_uv);
    if(distance>0.0) discard;
    ALBEDO=pow(vec3(0.12,0.34,0.40),vec3(2.2));
    ROUGHNESS=0.85;
}
