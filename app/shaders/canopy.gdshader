shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_burley;
uniform float relief=1.0;
instance uniform float representation_weight=1.0;
instance uniform float residency_weight=1.0;
varying float crown_up;
void vertex(){ crown_up=NORMAL.y; VERTEX.y*=relief; }
void fragment(){
    vec3 leaf=mix(COLOR.rgb/12.92,pow((COLOR.rgb+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),COLOR.rgb));
    float upper=clamp(crown_up*0.5+0.5,0.0,1.0);
    ALBEDO=leaf*mix(0.90,1.04,upper);
    ROUGHNESS=0.96;
    SPECULAR=0.12;
    AO=mix(0.80,1.0,upper);
    ALPHA=clamp(representation_weight*residency_weight,0.0,1.0);
    ALPHA_HASH_SCALE=1.0;
}
