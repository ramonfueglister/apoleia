// Fixed shared grid, vertex displacement and ring-edge parent morph.
// Height rectangles span FIRST to LAST texel centre, including the tile halo.
uniform bool clipmap_enabled=false;
uniform vec2 clipmap_origin=vec2(0.0);
uniform float clipmap_span=1.0;
uniform sampler2D clipmap_height_tex : filter_nearest, repeat_disable;
uniform sampler2D clipmap_parent_height_tex : filter_nearest, repeat_disable;
uniform vec4 clipmap_height_rect=vec4(0.0,0.0,1.0,1.0);
uniform vec4 clipmap_parent_height_rect=vec4(0.0,0.0,1.0,1.0);
uniform float clipmap_morph_start=1.0;
uniform float clipmap_morph_end=2.0;
uniform vec2 clipmap_focus=vec2(0.0);
uniform float clipmap_family_blend=1.0;
uniform float clipmap_parent_grid_step=0.0;
uniform vec2 clipmap_parent_grid_origin=vec2(0.0);
uniform vec4 clipmap_edge_mask=vec4(0.0);
uniform float clipmap_edge_width=0.0;
uniform sampler2D tile_material_tex : filter_linear, repeat_disable;
uniform sampler2D tile_water_tex : filter_nearest, repeat_disable;
uniform vec4 tile_rect=vec4(0.0,0.0,1.0,1.0);

float clipmap_code(vec2 code){return round(code.r*255.0)*256.0+round(code.g*255.0);}
float clipmap_encoded(sampler2D tex,vec4 rect,vec2 p,float scale,float offset) {
    ivec2 last=textureSize(tex,0)-ivec2(1);
    vec2 q=clamp((p-rect.xy)/max(rect.zw,vec2(0.000001)),vec2(0.0),vec2(1.0))*vec2(last);
    ivec2 c=ivec2(min(floor(q),vec2(max(last-ivec2(1),ivec2(0)))));vec2 f=q-vec2(c);
    float a=clipmap_code(texelFetch(tex,clamp(c,ivec2(0),last),0).rg)*scale+offset;
    float b=clipmap_code(texelFetch(tex,clamp(c+ivec2(1,0),ivec2(0),last),0).rg)*scale+offset;
    float d=clipmap_code(texelFetch(tex,clamp(c+ivec2(0,1),ivec2(0),last),0).rg)*scale+offset;
    float e=clipmap_code(texelFetch(tex,clamp(c+ivec2(1),ivec2(0),last),0).rg)*scale+offset;
    return mix(mix(a,b,f.x),mix(d,e,f.x),f.y);
}
float clipmap_source_height(vec2 p){return clipmap_encoded(clipmap_height_tex,clipmap_height_rect,p,0.25,-8192.0);}
float clipmap_parent_grid_height(vec2 p) {
    if(clipmap_parent_grid_step<=0.0)return clipmap_encoded(clipmap_parent_height_tex,clipmap_parent_height_rect,p,0.25,-8192.0);
    float step_size=clipmap_parent_grid_step;
    vec2 parent_origin=clipmap_parent_grid_origin;
    vec2 q=(p-parent_origin)/step_size;vec2 cell=floor(q);vec2 f=fract(q);
    vec2 corner=parent_origin+cell*step_size;
    float a=clipmap_encoded(clipmap_parent_height_tex,clipmap_parent_height_rect,corner,0.25,-8192.0);
    float b=clipmap_encoded(clipmap_parent_height_tex,clipmap_parent_height_rect,corner+vec2(step_size,0.0),0.25,-8192.0);
    float c=clipmap_encoded(clipmap_parent_height_tex,clipmap_parent_height_rect,corner+vec2(0.0,step_size),0.25,-8192.0);
    float d=clipmap_encoded(clipmap_parent_height_tex,clipmap_parent_height_rect,corner+vec2(step_size),0.25,-8192.0);
    return f.x+f.y<1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
float clipmap_ring_height(vec2 p) {
    float radius=max(abs(p.x-clipmap_focus.x),abs(p.y-clipmap_focus.y));
    float morph=smoothstep(clipmap_morph_start,max(clipmap_morph_end,clipmap_morph_start+0.000001),radius);
    if(clipmap_edge_width>0.0) {
        vec2 lower=p-clipmap_origin;
        vec2 upper=clipmap_origin+vec2(clipmap_span)-p;
        vec4 edge=vec4(lower.x,upper.x,lower.y,upper.y);
        vec4 edge_weight=(vec4(1.0)-smoothstep(vec4(0.0),vec4(clipmap_edge_width),edge))*clipmap_edge_mask;
        morph=max(max(edge_weight.x,edge_weight.y),max(edge_weight.z,edge_weight.w));
    }
    return mix(clipmap_parent_grid_height(p),clipmap_source_height(p),clamp(clipmap_family_blend,0.0,1.0)*(1.0-morph));
}
vec3 clipmap_normal(vec2 p) {
    vec2 step_size=clipmap_height_rect.zw/max(vec2(textureSize(clipmap_height_tex,0)-ivec2(1)),vec2(1.0));
    float dx=(clipmap_ring_height(p+vec2(step_size.x,0.0))-clipmap_ring_height(p-vec2(step_size.x,0.0)))*0.001/(2.0*step_size.x);
    float dz=(clipmap_ring_height(p+vec2(0.0,step_size.y))-clipmap_ring_height(p-vec2(0.0,step_size.y)))*0.001/(2.0*step_size.y);
    return normalize(vec3(-dx,1.0,-dz));
}
vec2 clipmap_tile_uv(vec2 p) {
    vec2 size=vec2(textureSize(tile_material_tex,0));
    return ((p-tile_rect.xy)/tile_rect.zw*(size-vec2(1.0))+vec2(0.5))/size;
}
vec4 clipmap_material(vec2 p){return textureLod(tile_material_tex,clipmap_tile_uv(p),0.0);}
float clipmap_water_distance(vec2 p){return clipmap_encoded(tile_water_tex,tile_rect,p,0.125,-4096.0);}
float clipmap_water_kind(vec2 p) {
    if(clipmap_water_distance(p)<=0.0)return 0.0;
    ivec2 size=textureSize(tile_water_tex,0);
    vec2 q=clamp((p-tile_rect.xy)/tile_rect.zw,vec2(0.0),vec2(1.0))*vec2(size-ivec2(1));
    return round(texelFetch(tile_water_tex,clamp(ivec2(round(q)),ivec2(0),size-ivec2(1)),0).b*255.0);
}
