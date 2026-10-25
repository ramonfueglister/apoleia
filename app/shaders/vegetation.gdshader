shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
uniform float visible_weight=1.0;
uniform float relief=1.0;
instance uniform float residency_weight=1.0;
void vertex(){VERTEX.y*=relief;}
void fragment(){ALBEDO=pow(COLOR.rgb,vec3(2.2)); ROUGHNESS=1.0; ALPHA=visible_weight*residency_weight; ALPHA_HASH_SCALE=1.0;}
