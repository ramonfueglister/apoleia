shader_type spatial;
// Opaque copy of canopy.gdshader for full-weight clipmap forest tiles
// (tile_forest.gd): no ALPHA write, so crowns skip the alpha-hash discard
// path (cheap depth prepass, early-Z/HSR); cones are outward-wound
// (landscape_style _outward_triangle), so back faces are culled. Fading tiles
// keep canopy.gdshader. Keep both in sync.
render_mode cull_back, world_vertex_coords, diffuse_burley;
#include "res://shaders/terrain_clipmap.gdshaderinc"
uniform float relief=1.0;
// Expanded meshes arrive encoded unit normals; instanced uniform scale does not.
uniform bool normalize_instanced_normals=false;
instance uniform float representation_weight=1.0;
instance uniform float residency_weight=1.0;
uniform bool stream_ground=false;
uniform sampler2D ground_vertices : filter_nearest, repeat_disable;
uniform float terrain_morph_alpha=1.0;
uniform float display_height_scale=12.0;
varying float crown_up;
void vertex(){
    if(normalize_instanced_normals) NORMAL=normalize(NORMAL);
    crown_up=NORMAL.y;
    if(clipmap_enabled){
        // Clipmap tiles store the settled ground per instance in
        // INSTANCE_CUSTOM (r metres, a=1); morphing cells sample it again.
        vec2 root=MODEL_MATRIX[3].xz;
        float ground=INSTANCE_CUSTOM.a>0.5 && clipmap_cell_settled(root) ? INSTANCE_CUSTOM.r : clipmap_surface_height(root);
        VERTEX.y+=ground*0.001*display_height_scale;
    }else if(stream_ground){
        vec4 a=texelFetch(ground_vertices,ivec2(0,INSTANCE_ID),0);
        vec4 b=texelFetch(ground_vertices,ivec2(1,INSTANCE_ID),0);
        vec4 c=texelFetch(ground_vertices,ivec2(2,INSTANCE_ID),0);
        vec2 u=b.xy-a.xy;vec2 v=c.xy-a.xy;vec2 d=MODEL_MATRIX[3].xz-a.xy;
        float det=u.x*v.y-u.y*v.x;
        vec2 bc=vec2(d.x*v.y-d.y*v.x,u.x*d.y-u.y*d.x)/det;
        float ya=a.z+(a.w-a.z)*terrain_morph_alpha;
        float yb=b.z+(b.w-b.z)*terrain_morph_alpha;
        float yc=c.z+(c.w-c.z)*terrain_morph_alpha;
        VERTEX.y+=(ya+(yb-ya)*bc.x+(yc-ya)*bc.y)*display_height_scale;
    }
    VERTEX.y*=relief;
}
void fragment(){
    vec3 leaf=mix(COLOR.rgb/12.92,pow((COLOR.rgb+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),COLOR.rgb));
    float upper=clamp(crown_up*0.5+0.5,0.0,1.0);
    // Warmer olive crowns as in the reference.
    ALBEDO=leaf*vec3(0.80,0.72,0.50)*mix(0.90,1.04,upper);
    ROUGHNESS=0.96;
    SPECULAR=0.12;
    AO=mix(0.80,1.0,upper);
}
