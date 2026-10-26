shader_type spatial;
// Delta area mask: lagoon water with organic islands and sand rims behind a
// beach arc with inlets. Drawn as a draped grid just above the terrain; land
// that is not lagoon, island or sand is discarded (terrain shows through).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_look.gdshaderinc"
uniform float relief=1.0;
uniform float view_width=1.0;
uniform vec2 delta_center=vec2(0.0);
uniform vec2 delta_sea=vec2(0.0,1.0);
uniform vec2 delta_radii=vec2(10.0,6.0);
uniform float delta_seed=0.0;
uniform vec2 delta_inlet_a=vec2(0.0);
uniform vec2 delta_inlet_b=vec2(0.0);
varying vec3 world_position;

float d_fbm(vec2 p) {
    return wl_noise(p)*0.5+wl_noise(p*2.1+vec2(3.7,1.9))*0.3+wl_noise(p*4.3+vec2(8.1,5.3))*0.2;
}

void vertex() {
    VERTEX.y=VERTEX.y*relief+0.006;
    world_position=VERTEX;
}
void fragment() {
    vec2 p=world_position.xz;
    float shore=water_distance_at(p);
    if(shore>0.0) discard; // the sea itself belongs to water.gdshader
    float land_m=-shore;
    vec2 tangent=vec2(-delta_sea.y,delta_sea.x);
    vec2 q=p-delta_center;
    vec2 local=vec2(dot(q,tangent)/delta_radii.x,dot(q,-delta_sea)/delta_radii.y);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    vec2 np=p*0.55+vec2(delta_seed);
    // Lagoon body: a noisy ellipse behind the coast.
    float body=1.0-length(local*vec2(1.0,1.0+0.35*sin(local.x*2.3+delta_seed)))-(d_fbm(np*0.45)-0.5)*0.9-(d_fbm(np*1.4)-0.5)*0.25;
    // Islands: organic blobs inside the lagoon, more towards its inner side.
    float island=smoothstep(0.50,0.62,d_fbm(np*1.15+vec2(11.0)))*smoothstep(-0.2,0.5,local.y+0.2);
    float field=body-island*0.9;
    // Beach arc: a band of sand along the open coast, broken at the inlets.
    float px_m=max(footprint*1000.0,1.0);
    float barrier_m=max(px_m*4.0,650.0);
    float inlet=min(length(p-delta_inlet_a),length(p-delta_inlet_b));
    float inlet_open=1.0-smoothstep(0.35,0.75,inlet);
    float barrier=(1.0-smoothstep(barrier_m*0.7,barrier_m,land_m))*(1.0-inlet_open);
    float in_region=smoothstep(-0.25,0.05,1.0-length(local*vec2(0.85,0.9)));
    float water=step(0.0,field)*(1.0-barrier)*in_region;
    water=max(water,inlet_open*step(-0.15,field));
    float rim=max(smoothstep(-0.16,0.0,field)*(1.0-water),barrier*in_region);
    float island_land=(1.0-water)*step(0.0,body)*in_region*(1.0-rim);
    if(water<0.5 && rim<0.05 && island_land<0.5) discard;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float calm=smoothstep(0.05,0.6,relief);
    vec3 sand=vec3(0.74,0.62,0.36)*(0.92+0.12*wl_noise(np*3.0));
    vec3 grass=vec3(0.24,0.33,0.06)*(0.85+0.3*d_fbm(np*2.5));
    if(water>0.5) {
        float edge_m=max(field,0.0)*delta_radii.y*1000.0;
        WaterSample w=water_shade(p,edge_m+400.0,6.0+field*20.0,footprint,calm,view_world,vec2(0.0),px_m,0.6,0.0);
        // Lagoon blue between the river band and the sea's shallow tint.
        ALBEDO=mix(w.albedo,vec3(0.02,0.13,0.32),0.45);
        EMISSION=w.emission*0.5;
        ROUGHNESS=w.roughness;
        NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
    } else if(rim>=0.05) {
        ALBEDO=sand;ROUGHNESS=0.9;
    } else {
        ALBEDO=grass;ROUGHNESS=0.92;
    }
    SPECULAR=0.04;
}
