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
// Direct sunlight sees the warm lit crown colour, ambient (shade) the cool
// albedo; set in fragment(), used in light().
varying vec3 crown_warm;
const vec3 CROWN_BACKLIGHT=vec3(0.09,0.11,0.13);
void vertex(){
    if(normalize_instanced_normals) NORMAL=normalize(NORMAL);
    crown_up=NORMAL.y;
    // Close views: crowns 25 % wider about their root, so groves close into
    // masses like the reference near view (a117124 A/B: crown share nah
    // 0.115 -> 0.125, no measurable cost; in the mid view it went too dark,
    // 0.148 against 0.131, so it fades out by ~380 km).
    // Mid view (b6c8e1a, 450 km): crown share 0.107 against 0.164 with the
    // dark share already on the reference (0.133 / 0.131); the reference
    // crowns there are wider and lighter (82.9 % in v 0.3-0.42, ours 61 %).
    // 20 % wider up to ~700 km, lighter in fragment().
    float crown_width=mix(1.25,mix(1.2,1.0,smoothstep(600.0,900.0,view_width)),smoothstep(220.0,380.0,view_width));
    VERTEX.xz=MODEL_MATRIX[3].xz+(VERTEX.xz-MODEL_MATRIX[3].xz)*crown_width;
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
    // 2c4cfcf: our shaded bands were yellower than the reference (mid
    // #2e4323 against #2e4332); bluer overall (0.76) turned the lit faces
    // slate (515f650). Coolness now comes from the underside and the
    // backlight; the albedo only a little bluer than before (0.66).
    vec3 tinted=leaf*vec3(0.61,0.70,0.70);
    // 5b44221 crop: the reference crowns are a saturated mid green with a
    // lighter top; ours grey-green (desaturated 35 %, flat top).
    tinted=mix(tinted,vec3(dot(tinted,vec3(0.2126,0.7152,0.0722))),0.15);
    float top=smoothstep(0.15,0.65,crown_up);
    // 2ef82ce bands (nah): ours #102b13 / #25421f / #425d2d against the
    // reference #1b3028 / #2e4332 / #4b5c38, green equal, blue 10-20 and red
    // ~9 too low, most in the shade. Red and blue only (v and the band split
    // stay): about 2x blue on the walls, 1.4x on the lit tops.
    // 903029a: bands below v 0.42 on the reference, but the lit parts went
    // slate (#657a56 against #5c7f73: red +9, green -5; lit band blue +8).
    // Tops: red back, a little more green; walls a little less cool.
    // 35305b1: still slate where lit (land only #637a53 against #5e723d,
    // blue +22): the reference shade is cool, its sunlit side yellow-green.
    // The cool shift now stays in the ambient term; light() gives the
    // direct sun the warm colour (red 1.0, green 0.88, blue 0.8 of tinted).
    vec3 cool=mix(vec3(1.35,1.0,1.85),vec3(1.02,1.07,1.4),top);
    tinted*=cool;
    // a117124 / de679e4 lit, land only: nah #5f7745, mittel #60784d against
    // #5e723d / #5d723f, blue 8-14 high.
    crown_warm=vec3(1.0,0.88,0.72)/cool;
    // Close views: deeper crowns, so the dense groves carry the dark share
    // of the reference near view (measured r29: 0.133 against 0.161) while
    // the mid view (0.141 against 0.132) stays as it is.
    // r11 (closed hill carpets): crown share mittel 0.136 / nah 0.155, but
    // dark share 0.155 / 0.173 against 0.131 / 0.165; 28 % of the mid crown
    // pixels in v 0.2-0.3 (reference 17 %). Mid crowns ~10 % lighter, near
    // crowns a little less deep.
    float near_crowns=1.0-0.12*(1.0-smoothstep(150.0,320.0,view_width));
    float mid_view=smoothstep(280.0,400.0,view_width)*(1.0-smoothstep(600.0,900.0,view_width));
    near_crowns*=1.0+0.27*mid_view;
    // 3d27516 (r11): dark shares on the reference in all three views, but
    // the mid carpets read blue-grey: v 0.3-0.42 band #435c43 against
    // #485e3b, lit land-only #607950 against #5d723f. Warmer mid crowns
    // (ambient and direct alike; the near view is on target).
    // 4da4ca4: warm green on the reference, but green x0.95 lowered v and
    // the mid dark share rose to 0.147 (0.131): green stays.
    vec3 mid_warm=mix(vec3(1.0),vec3(1.08,1.0,0.72),mid_view);
    // Lighter tops over the steep gumdrop walls.
    ALBEDO=tinted*mix(0.86,1.12,top)*near_crowns*mid_warm;
    ROUGHNESS=0.96;
    SPECULAR=0.12;
    // Sun-averted faces: the reference keeps them a mid green (#2e4332,
    // about 0.3 of the lit side); ours fell to near black (#152917 on 18 %
    // of the crown pixels at 190 km, reference 1 %). Backlight wraps the
    // direct light round the crown; the ground and its shadows are unchanged.
    // 0.22 overshot (2c4cfcf: dark share nah 0.102, mittel 0.089 against
    // 0.165 / 0.131, near-black 6.8 %); half of it, a little cooler.
    BACKLIGHT=CROWN_BACKLIGHT;
    AO=mix(0.90,1.0,upper);
#ifdef CANOPY_FADE
    ALPHA=clamp(representation_weight*residency_weight,0.0,1.0);
    ALPHA_HASH_SCALE=1.0;
#endif
}
// Lambert with Godot's backlight term (as the built-in path; burley differs
// by under 1 % at these view and sun angles; the 0.12 specular on 0.96
// roughness is dropped). LIGHT_COLOR carries energy * PI.
void light(){
    float nl=clamp(dot(NORMAL,LIGHT),0.0,1.0);
    DIFFUSE_LIGHT+=ATTENUATION*LIGHT_COLOR/PI*(nl*crown_warm+(1.0-nl)*CROWN_BACKLIGHT);
}
