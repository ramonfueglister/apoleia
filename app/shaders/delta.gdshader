shader_type spatial;
// Delta area mask: lagoon water with organic islands and sand rims behind a
// beach arc with inlets. Drawn as a draped grid just above the terrain; land
// that is not lagoon, island or sand is discarded (terrain shows through).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_look.gdshaderinc"
uniform float relief=1.0;
uniform float display_height_scale=7.0;
uniform float view_width=1.0;
uniform vec2 delta_center=vec2(0.0);
uniform vec2 delta_sea=vec2(0.0,1.0);
uniform vec2 delta_radii=vec2(10.0,6.0);
uniform float delta_seed=0.0;
uniform vec2 delta_inlet_a=vec2(0.0);
uniform vec2 delta_inlet_b=vec2(0.0);
varying vec3 world_position;
varying float vertex_shore;

float d_fbm(vec2 p) {
    return wl_noise(p)*0.5+wl_noise(p*2.1+vec2(3.7,1.9))*0.3+wl_noise(p*4.3+vec2(8.1,5.3))*0.2;
}

void vertex() {
    // Lift above the streamed terrain (its LOD heights differ slightly from
    // the CPU sample used to drape this grid); delta land is near sea level.
    VERTEX.y=VERTEX.y*display_height_scale*relief+0.12;
    world_position=VERTEX;
    vertex_shore=UV.x;
}
float seg_dist(vec2 p,vec2 a,vec2 b){vec2 ab=b-a;float t=clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0);return length(p-a-ab*t);}
float h1(float x){return fract(sin(x*127.1+delta_seed*3.7)*43758.5453);}

void fragment() {
    vec2 p=world_position.xz;
    float shore=vertex_shore;          // m, >0 sea (rendered coast)
    if(shore>0.0) discard;             // the sea belongs to water.gdshader
    float land_m=-shore;
    vec2 tangent=vec2(-delta_sea.y,delta_sea.x);
    vec2 q=p-delta_center;
    // u along the coast, v inland; the coast lies near v=-0.55.
    vec2 local=vec2(dot(q,tangent)/delta_radii.x,dot(q,-delta_sea)/delta_radii.y);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float px_m=max(footprint*1000.0,1.0);
    // Lagoon body: smooth ellipse with a very low-frequency wobble.
    float wobble=(wl_noise(p*0.25+vec2(delta_seed))-0.5)*0.45+(wl_noise(p*0.7+vec2(3.0))-0.5)*0.12;
    float body=1.0-length(local*vec2(1.0,1.15))+wobble;
    // 3-6 large smooth islands as metaballs inside the lagoon.
    float meta=0.0;
    for(int i=0;i<6;i++){
        float fi=float(i);
        vec2 c=vec2(mix(-0.65,0.65,h1(fi+1.0)),mix(-0.25,0.55,h1(fi+7.0)));
        float r=mix(0.13,0.24,h1(fi+13.0));
        vec2 d=(local-c)/r;
        meta+=1.0/(1.0+dot(d,d)*dot(d,d));
    }
    float island=smoothstep(0.42,0.52,meta+(wl_noise(p*0.6)-0.5)*0.08);
    // 3 channels from the river end (inland apex) to the coast inlets.
    vec2 apex=vec2(0.0,0.95);
    float ch=1e9;
    for(int i=0;i<3;i++){
        float fi=float(i);
        vec2 end=vec2(mix(-0.7,0.7,fi*0.5)+(h1(fi+21.0)-0.5)*0.15,-0.6);
        vec2 mid=mix(apex,end,0.5)+vec2((h1(fi+31.0)-0.5)*0.35,0.0);
        ch=min(ch,min(seg_dist(local,apex,mid),seg_dist(local,mid,end)));
    }
    float channel=1.0-smoothstep(0.035,0.055,ch);
    float in_lagoon=smoothstep(-0.02,0.02,body);
    // Barrier spit: continuous sand arc along the rendered coast, open only
    // where the two outer channels reach the sea.
    float barrier_m=max(px_m*3.0,900.0);
    float barrier=(1.0-smoothstep(barrier_m*0.75,barrier_m,land_m))*smoothstep(-0.15,0.1,1.0-abs(local.x)*0.95);
    float inlet=min(length(p-delta_inlet_a),length(p-delta_inlet_b));
    barrier*=smoothstep(0.5,0.9,inlet);
    float water=in_lagoon*(1.0-island)*(1.0-barrier);
    water=max(water,channel*smoothstep(-0.25,0.0,body)*(1.0-barrier*0.0));
    // Sand rim around islands and the lagoon shore.
    float rim_island=smoothstep(0.36,0.42,meta)*(1.0-island)*in_lagoon;
    float rim_body=smoothstep(-0.06,0.0,body)*(1.0-in_lagoon);
    float sand=max(max(barrier,rim_island*(1.0-channel)),rim_body);
    float green=island*in_lagoon*(1.0-channel);
    if(water<0.5 && sand<0.5 && green<0.5) discard;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float calm=smoothstep(0.05,0.6,relief);
    vec2 np=p*0.55+vec2(delta_seed);
    vec3 sand_c=vec3(0.72,0.60,0.36)*(0.94+0.08*wl_noise(np*1.5));
    vec3 grass=vec3(0.13,0.21,0.04)*(0.9+0.2*wl_noise(np*0.8));
    vec3 up=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
    if(water>=0.5) {
        WaterSample w=water_shade(p,400.0+max(body,0.0)*2000.0,8.0+max(body,0.0)*20.0,footprint,calm,view_world,vec2(0.0),px_m,0.6,0.0);
        ALBEDO=mix(w.albedo,vec3(0.025,0.12,0.22),0.6);
        EMISSION=w.emission*0.5;
        ROUGHNESS=w.roughness;
        NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
    } else if(sand>=0.5) {
        ALBEDO=sand_c;ROUGHNESS=0.9;NORMAL=up;
    } else {
        ALBEDO=grass;ROUGHNESS=0.92;NORMAL=up;
    }
    SPECULAR=0.04;
}
