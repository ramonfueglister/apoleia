shader_type spatial;
// Delta lagoon landscape (reference near view): a sand barrier beach along
// the rendered coast, behind it a belt of winding lagoon water with organic
// islands (sand rims, marsh green) that thins out inland. The arms are river
// ribbons drawn over this mask (render priority), so they cut the barrier as
// inlets and run through the islands as channels. Draped grid just above the
// terrain; plain land is discarded, so terrain and trees show through.
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
    float region=1.0-smoothstep(0.7,1.0,length(local*vec2(0.85,1.0)));
    if(region<=0.0) discard;
    // Barrier beach: 0.55-0.85 km of sand along the rendered coast.
    float bw=max(px_m*3.0,550.0+300.0*d_fbm(p*0.4+vec2(delta_seed)));
    float barrier=(1.0-smoothstep(bw-max(px_m,40.0),bw,land_m))*region;
    // Lagoon belt behind it: deepest in front of the centre, shallow at the
    // flanks, bias 1 at the barrier .. 0 at the inland end.
    float belt_km=delta_radii.y*mix(0.35,0.9,1.0-clamp(abs(local.x),0.0,1.0));
    float behind=max(land_m-bw,0.0)*0.001/max(belt_km,0.1);
    float bias=(1.0-smoothstep(0.0,1.0,behind))*region;
    // Organic islands: domain-warped noise (features ~1-2 km); more water
    // near the barrier, single ponds inland.
    vec2 warp=vec2(d_fbm(p*0.45+vec2(delta_seed,1.7)),d_fbm(p*0.45+vec2(5.2,delta_seed)))-0.5;
    float n=d_fbm(p*0.9+warp*2.2+vec2(delta_seed*0.37));
    float thr=mix(0.70,0.32,bias);
    float aa=max(fwidth(n)*0.8,0.004);
    float lagoon=smoothstep(thr-aa,thr+aa,n)*smoothstep(0.0,0.08,bias)*(1.0-barrier);
    // Wet sand rim on the island side of every lagoon edge (>= ~1.5 px).
    float rim_w=max(fwidth(n)*1.6,0.025);
    float rim=smoothstep(thr-aa-rim_w,thr-aa,n)*(1.0-smoothstep(thr-aa,thr+aa,n))*smoothstep(0.0,0.08,bias)*(1.0-barrier);
    // Marsh: richer green on the islands and the delta plain.
    float marsh=(bias*0.55+(1.0-smoothstep(0.5,0.95,length(local*vec2(0.8,1.0))))*0.2)*region;
    float cover=max(max(lagoon,rim),max(barrier,marsh));
    if(cover<0.01) discard;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float calm=smoothstep(0.05,0.6,relief);
    WaterSample w=water_shade(p,300.0,8.0,footprint,calm,view_world,vec2(0.0),px_m,0.6,0.0);
    // Lagoon water like the rivers (reference #2d7b8c), lighter turquoise
    // in the shallows along the island edges.
    float shallow=1.0-smoothstep(thr+aa,thr+0.09,n);
    vec3 water=mix(vec3(0.012,0.086,0.108),vec3(0.040,0.130,0.135),shallow*0.6);
    water=mix(w.albedo,water,0.92);
    vec3 col=vec3(0.17,0.19,0.05)*(0.9+0.2*wl_noise(p*0.8));
    col=mix(col,vec3(0.48,0.40,0.24),rim);
    col=mix(col,water,lagoon);
    col=mix(col,vec3(0.55,0.40,0.20)*(0.95+0.08*wl_noise(p*1.7)),barrier);
    ALBEDO=col;
    ALPHA=max(max(lagoon,rim),barrier)+marsh*0.6*(1.0-max(max(lagoon,rim),barrier));
    EMISSION=w.emission*0.4*lagoon;
    ROUGHNESS=mix(0.92,w.roughness,lagoon);
    vec3 up=vec3(0.0,1.0,0.0);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(mix(up,w.normal,lagoon)),0.0)).xyz);
    SPECULAR=0.04;
}
