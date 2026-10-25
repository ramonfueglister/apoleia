shader_type spatial;
render_mode cull_disabled;
uniform bool height_packed=true;
uniform sampler2D elevation_tex : filter_linear, repeat_disable;
uniform sampler2D mapped_cover_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D water_tex : filter_linear, repeat_disable;
uniform sampler2D water_distance_tex: filter_nearest, repeat_disable;
uniform vec2 world_size;
uniform vec2 world_min;
uniform float relief = 0.0;
uniform float view_width=1.0;
uniform float north_lat = 59.0;
uniform float south_lat = 24.0;
varying vec2 geo_uv;
instance uniform vec4 patch_bounds=vec4(0.0,0.0,1.0,1.0);
varying float altitude;
varying vec3 world_position;
float material_noise(vec2 p) {return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
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
float sample_height(vec2 p) {
    vec2 uv=(p-world_min)/world_size;
    float kind=texelFetch(water_tex,clamp(ivec2(floor(uv*vec2(textureSize(water_tex,0)))),ivec2(0),textureSize(water_tex,0)-ivec2(1)),0).r*255.0;
    return kind==1.0?0.0:bilinear_height(uv);
}
float reflectance_variation(vec2 p) {
    vec2 c=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(material_noise(c),material_noise(c+vec2(1.0,0.0)),f.x),mix(material_noise(c+vec2(0.0,1.0)),material_noise(c+vec2(1.0,1.0)),f.x),f.y);
}
void vertex() {
    vec2 patch_size=patch_bounds.zw*world_size;
    VERTEX.xz=world_min+(patch_bounds.xy+VERTEX.xz*patch_bounds.zw)*world_size;
    geo_uv=(VERTEX.xz-world_min)/world_size;
    altitude=sample_height(VERTEX.xz);
    // Child vertices begin on the exact triangle of their parent surface.
    vec2 step_size=patch_size/12.0;
    vec2 grid_origin=world_min;
    vec2 cell=floor((VERTEX.xz-grid_origin)/step_size);
    vec2 corner=grid_origin+cell*step_size;
    vec2 f=clamp((VERTEX.xz-corner)/step_size,vec2(0.0),vec2(1.0));
    float a=sample_height(corner);
    float b=sample_height(corner+vec2(step_size.x,0.0));
    float c=sample_height(corner+vec2(0.0,step_size.y));
    float d=sample_height(corner+step_size);
    float parent_height=f.x+f.y<1.0?a+(b-a)*f.x+(c-a)*f.y:d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
    float morph=smoothstep(0.11,0.22,max(patch_size.x,patch_size.y)/view_width);
    altitude=mix(parent_height,altitude,morph);
    VERTEX.y=altitude*0.001*relief-UV2.y*0.06*relief;
    world_position=VERTEX;
}
void fragment() {
    float h=bilinear_height(geo_uv);
    float distance=bilinear_water(geo_uv);
    float aa=max(fwidth(distance)*0.7,0.1);
    float water=smoothstep(-aa,aa,distance);
    float lat=mix(north_lat,south_lat,geo_uv.y);
    vec3 mapped=texture(mapped_cover_tex,geo_uv).rgb;
    // Ground reflectance is continuous at viewing distances below the cover grid.
    // Source cover still controls the unchanged tree candidate mask, not this cosmetic field.
    vec3 base=mix(vec3(0.43,0.51,0.29),vec3(0.58,0.52,0.34),1.0-smoothstep(29.0,37.0,lat));
    vec3 land=mix(base,mapped,mix(0.035,1.0,smoothstep(100.0,600.0,view_width)));
    float broad=reflectance_variation(world_position.xz*5.0)*0.65+reflectance_variation(world_position.xz*13.0)*0.35;
    land*=0.91+broad*0.18;
    // Small material variation changes reflectance only, never source geometry.
    float grain=material_noise(floor(world_position.xz*500.0));
    float footprint=max(length(dFdx(world_position.xz)),length(dFdy(world_position.xz)));
    float detail_weight=1.0-smoothstep(0.002,0.015,footprint);
    land*=mix(1.0,0.97+grain*0.06,detail_weight);
    float ground=reflectance_variation(world_position.xz*80.0);
    land*=mix(1.0,0.94+ground*0.12,detail_weight);
    land=mix(land,land*vec3(1.10,1.01,0.92),smoothstep(0.45,0.8,ground)*0.25*detail_weight);
    vec3 n=normalize(cross(dFdy(world_position),dFdx(world_position)));
    if(n.y<0.0) n=-n;
    float slope=1.0-n.y;
    float rock=max(smoothstep(1600.0,2700.0,h),smoothstep(0.14,0.48,slope));
    land=mix(land,vec3(0.64,0.63,0.54),rock*0.82);
    land=mix(land,vec3(0.87,0.86,0.79),smoothstep(3200.0,4400.0,h)*0.7);
    vec3 sea=vec3(0.055,0.24,0.37);
    vec3 shallow=vec3(0.13,0.40,0.46);
    float edge=exp(-max(-h,0.0)/90.0);
    sea=mix(sea,shallow,edge*0.75);
    ALBEDO=pow(mix(land,sea,water),vec3(2.2));
    ROUGHNESS=0.95;
    NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
