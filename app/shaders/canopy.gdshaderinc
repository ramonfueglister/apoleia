// Shared crown body of canopy.gdshader (alpha-hash fade, both faces) and
// canopy_opaque.gdshader (full-weight clipmap tiles, back faces culled).
#include "res://shaders/terrain_clipmap.gdshaderinc"
#include "res://shaders/delta_lagoon.gdshaderinc"
uniform float relief=1.0;
// Expanded meshes arrive encoded unit normals; instanced uniform scale does not.
uniform bool normalize_instanced_normals=false;
instance uniform float representation_weight=1.0;
instance uniform float residency_weight=1.0;
uniform bool stream_ground=false;
uniform sampler2D ground_vertices : filter_nearest, repeat_disable;
uniform float terrain_morph_alpha=1.0;
uniform float display_height_scale=12.0;
// Set per clipmap tile with the other camera uniforms (clipmap_terrain.gd).
uniform float view_width=400.0;
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
        // No crowns in the delta lagoons (terrain_look draws water there;
        // the forest layout does not know them): collapse the crown.
        if(delta_count>0 && view_width<575.0 && delta_inside(root) && delta_lagoon_at(root,max(-clipmap_water_distance(root),0.0),view_width)>0.5) VERTEX=vec3(0.0);
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
    // Reference crowns: deep, slightly bluish green (h~100, s~0.36).
    // Reference crowns ~#2c3e2c: cool blue-green, low saturation.
    // 2c4cfcf: our shaded bands are yellower than the reference (mid
    // #2e4323 against #2e4332, dark #1b2c16 against #1b3028): bluer.
    vec3 tinted=leaf*vec3(0.60,0.69,0.76);
    tinted=mix(tinted,vec3(dot(tinted,vec3(0.2126,0.7152,0.0722))),0.35);
    // Close views: deeper crowns, so the dense groves carry the dark share
    // of the reference near view (measured r29: 0.133 against 0.161) while
    // the mid view (0.141 against 0.132) stays as it is.
    float near_crowns=1.0-0.18*(1.0-smoothstep(150.0,320.0,view_width));
    ALBEDO=tinted*mix(0.90,1.04,upper)*near_crowns;
    ROUGHNESS=0.96;
    SPECULAR=0.12;
    // Sun-averted faces: the reference keeps them a mid green (#2e4332,
    // about 0.3 of the lit side); ours fell to near black (#152917 on 18 %
    // of the crown pixels at 190 km, reference 1 %). Backlight wraps the
    // direct light round the crown; the ground and its shadows are unchanged.
    // 0.22 overshot (2c4cfcf: dark share nah 0.102, mittel 0.089 against
    // 0.165 / 0.131, near-black 6.8 %); half of it, a little cooler.
    BACKLIGHT=vec3(0.09,0.11,0.13);
    AO=mix(0.90,1.0,upper);
#ifdef CANOPY_FADE
    ALPHA=clamp(representation_weight*residency_weight,0.0,1.0);
    ALPHA_HASH_SCALE=1.0;
#endif
}
