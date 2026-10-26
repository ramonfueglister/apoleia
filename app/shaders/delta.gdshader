shader_type spatial;
// Delta area mask: lagoon water with organic islands and sand rims behind a
// beach arc with inlets. Drawn as a draped grid just above the terrain; land
// that is not lagoon, island or sand is discarded (terrain shows through).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled, blend_mix, depth_draw_never;
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
float h1(float x){return fract(sin(x*127.1+delta_seed*3.7)*43758.5453);}

void fragment() {
    vec2 p=world_position.xz;
    float shore=vertex_shore;          // m, >0 sea (rendered coast)
    if(shore>0.0) discard;             // the sea belongs to water.gdshader
    float land_m=-shore;
    vec2 tangent=vec2(-delta_sea.y,delta_sea.x);
    vec2 q=p-delta_center;
    vec2 local=vec2(dot(q,tangent)/delta_radii.x,dot(q,-delta_sea)/delta_radii.y);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float px_m=max(footprint*1000.0,1.0);
    // Fade the whole effect radially so it never ends at a hard edge.
    float region=1.0-smoothstep(0.75,1.0,length(local*vec2(0.9,1.0)));
    // Barrier spit: light sand band following the rendered coastline,
    // curved with the coast, open at the two outer arm mouths.
    // Continuous 0.5-1 km sand band along the rendered coast.
    float spit_w=max(px_m*2.0,600.0+300.0*wl_noise(p*0.3));
    float spit=(1.0-smoothstep(spit_w*0.6,spit_w,land_m))*region;
    float inlet=min(length(p-delta_inlet_a),length(p-delta_inlet_b));
    spit*=smoothstep(0.35,0.7,inlet);
    // 2-4 small irregular ponds behind the spit, soft-edged, river colour.
    float pond=0.0;
    for(int i=0;i<3;i++){
        float fi=float(i);
        // Lagoons just behind the beach (coast at local.y ~ -0.55), 1-3 km.
        vec2 c=vec2(mix(-0.6,0.6,h1(fi+3.0)),mix(-0.42,-0.22,h1(fi+9.0)));
        vec2 d=(local-c)/vec2(mix(0.22,0.38,h1(fi+15.0)),mix(0.12,0.22,h1(fi+19.0)));
        pond=max(pond,1.0-length(d)+(wl_noise(p*0.9+vec2(fi*5.0))-0.5)*0.5);
    }
    // Spit removed: the beach sand band comes from the land shader (r15/r16).
    float pond_a=smoothstep(0.0,0.12,pond)*region;
    float spit_a=0.0;
    // Marsh: a soft, richer green wash over the delta land between the arms.
    float marsh=(1.0-smoothstep(0.45,0.95,length(local*vec2(0.8,1.0))))*0.45;
    if(pond_a<0.5 && marsh<0.02) discard;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float calm=smoothstep(0.05,0.6,relief);
    vec3 up=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
    ALPHA=1.0;
    if(pond_a<0.5){
        ALBEDO=vec3(0.10,0.17,0.05)*(0.9+0.2*wl_noise(p*0.8));ROUGHNESS=0.95;NORMAL=up;ALPHA=marsh;
    } else if(spit_a>=0.5){
        ALBEDO=vec3(0.60,0.50,0.30)*(0.95+0.08*wl_noise(p*1.7));ROUGHNESS=0.9;NORMAL=up;
    } else {
        WaterSample w=water_shade(p,300.0,8.0,footprint,calm,view_world,vec2(0.0),px_m,0.6,0.0);
        ALBEDO=mix(w.albedo,vec3(0.026,0.15,0.23),0.7);
        EMISSION=w.emission*0.4;ROUGHNESS=w.roughness;
        NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
    }
    SPECULAR=0.04;
}
