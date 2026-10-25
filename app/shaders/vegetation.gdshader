shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_burley;
uniform float visible_weight=1.0;
uniform float relief=1.0;
uniform float canopy_ambient_occlusion=0.20;
uniform float leaf_warmth=0.06;
instance uniform float residency_weight=1.0;
instance uniform float representation_weight=1.0;
varying float crown_up;
void vertex(){ crown_up=NORMAL.y; VERTEX.y*=relief; }
void fragment(){
    // Mesh colors are authored in sRGB; material lighting operates in linear.
    vec3 leaf=mix(COLOR.rgb/12.92,pow((COLOR.rgb+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),COLOR.rgb));
    float upper=clamp(crown_up*0.5+0.5,0.0,1.0);
    ALBEDO=leaf*mix(vec3(0.92,0.97,0.94),vec3(1.0+leaf_warmth,1.015,0.95),upper);
    ROUGHNESS=0.94;
    SPECULAR=0.14;
    AO=1.0-canopy_ambient_occlusion*(1.0-upper);
    ALPHA=clamp(visible_weight*residency_weight*representation_weight,0.0,1.0);
    ALPHA_HASH_SCALE=1.0;
}
