shader_type spatial;
// Own sea surface: the zero-height marine plane. Land keeps its terrain
// shader; ownership is the same SDF-based water kind as before.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_look.gdshaderinc"
uniform float relief=0.0;
uniform float view_width=1.0;
uniform float viewport_width=1920.0;
uniform vec2 shading_origin=vec2(0.0);
uniform bool use_display_coast_distance=false;
uniform sampler2D display_coast_distance_tex : filter_nearest, repeat_disable;
uniform vec2 display_coast_world_min=vec2(0.0);
uniform vec2 display_coast_world_size=vec2(1.0);
uniform float shallow_display_span_world=24.0;
uniform vec4 river_mouths[32];
uniform int river_mouth_count=0;
varying vec3 world_position;

float display_coast_decode(ivec2 cell) {
    vec2 code=texelFetch(display_coast_distance_tex,clamp(cell,ivec2(0),textureSize(display_coast_distance_tex,0)-ivec2(1)),0).rg;
    return (round(code.r*255.0)*256.0+round(code.g*255.0))*2.0;
}
float display_coast_distance_at(vec2 uv) {
    vec2 q=uv*vec2(textureSize(display_coast_distance_tex,0))-0.5;
    ivec2 cell=ivec2(floor(q));vec2 f=fract(q);
    return mix(mix(display_coast_decode(cell),display_coast_decode(cell+ivec2(1,0)),f.x),mix(display_coast_decode(cell+ivec2(0,1)),display_coast_decode(cell+ivec2(1)),f.x),f.y);
}

void vertex() {
    // Clipmap rings stream the same marine plane around the camera.
    if(clipmap_enabled)VERTEX.xz=clipmap_origin+VERTEX.xz*clipmap_span;
    VERTEX.y=0.0;
    NORMAL=vec3(0.0,1.0,0.0);
    world_position=VERTEX;
}
void fragment() {
    vec2 p=world_position.xz;
    if(water_kind_at(p)!=1.0) discard;
    // Solid marine pixels use the depth-writing alpha colour pass; avoids the
    // Metal Forward+ opaque EQUAL/prepass mismatch.
    ALPHA=1.0;
    float distance=water_distance_at(p);
    // Near the contour the exact SDF; further out the graphic sidecar that
    // extends the range beyond the packed 3 km.
    float coast_m=max(distance,0.0);
    vec2 coast_uv=(p-display_coast_world_min)/display_coast_world_size;
    // The coarse sidecar only extends the range far out; the exact SDF owns
    // the whole visible saum (no quantised contour bands).
    if(!clipmap_enabled && use_display_coast_distance && inside_domain(coast_uv)) {
        float far=display_coast_distance_at(coast_uv);
        coast_m=mix(coast_m,max(far,coast_m),smoothstep(2600.0,3200.0,coast_m));
    }
    float depth=max(-model_height_at(p),0.0);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float px_m=max(length(vec2(dFdx(distance),dFdy(distance))),1.0);
    // Continental views: calm, hairline coast; close views: full saum.
    float calm=1.0-smoothstep(1500.0,4000.0,view_width)*0.85;
    float saum_scale=1.0-smoothstep(700.0,2600.0,view_width)*0.85;
    vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    float mouth=0.0;
    for(int i=0;i<32;i++) {
        if(i>=river_mouth_count) break;
        float d=length(p-river_mouths[i].xy);
        mouth=max(mouth,1.0-smoothstep(0.0,river_mouths[i].z,d));
    }
    WaterSample w=water_shade(p,coast_m,depth,footprint,calm,view_world,vec2(0.0),px_m,saum_scale,mouth);
    // Crisp shoreline: a thin lighter line exactly at the contour in the map view.
    float edge=1.0-smoothstep(0.0,px_m*1.2,coast_m);
    ALBEDO=mix(w.albedo,w.albedo*1.25+0.05,edge*(1.0-saum_scale)*0.6);
    // Reference calibration (h~207 s0.80-0.83 v0.52-0.55): slightly darker,
    // and less saturated in the continental view where AgX pushes chroma.
    float far_sea=smoothstep(800.0,2800.0,view_width);
    ALBEDO*=mix(1.04,1.12,far_sea);
    ALBEDO=mix(ALBEDO,vec3(dot(ALBEDO,vec3(0.2126,0.7152,0.0722))),0.10+far_sea*0.06);
    // Close views: shallow water as a broad, even ramp like the reference
    // near view (open #185585 -> #1f708d -> teal #2f7b8c -> #528f94 at the
    // beach). Shallowness comes from the bathymetry (0-100 m, ~10-20 km off
    // flat coasts) and, inside ~3.5 km, the coast distance (the clipmap
    // distance saturates at ~4 km). The bathymetry is 25 m codes on a
    // 0.5-1 km grid; a 4-tap blur over about two texels hides its squares,
    // and faint per-triangle tone steps keep the low-poly seabed. Targets
    // are linear albedo, fitted to the reference through the open sea's
    // screen gain.
    float near_sea=(1.0-smoothstep(250.0,800.0,view_width))*(1.0-mouth*0.6);
    if(near_sea>0.0) {
        float shelf_id;
        wl_facet_center(p,2.2,shelf_id);
        float texel=clipmap_enabled ? tile_rect.z/max(float(textureSize(tile_water_tex,0).x-1),1.0) : 0.5;
        // 8 taps: a diagonal ring at ~1 texel and an axis ring at ~2.6
        // texels. The 25 m codes stepped visibly with the 4-tap ring (a soft
        // contour ~20 km off the Lazio coast in the close view).
        float shelf_d=0.0;
        for(int k=0;k<8;k++) {
            vec2 o=k<4 ? vec2(k==0||k==3 ? 0.9 : -0.9,k<2 ? 0.9 : -0.9) : vec2(k==4 ? 2.6 : (k==5 ? -2.6 : 0.0),k==6 ? 2.6 : (k==7 ? -2.6 : 0.0));
            shelf_d+=clipmap_enabled ? clipmap_bathymetry(p+o*texel) : max(-model_height_at(p+o*texel),0.0);
        }
        // Smooth at both ends (no contour line where the shelf ends); open
        // sea from ~75 m, i.e. ~10 km off flat coasts (measured: the drop
        // came late at 10-15 km with a linear ramp to 100 m).
        float shelf_deep=mix(75.0,40.0,smoothstep(250.0,800.0,view_width));
        float s_depth=1.0-smoothstep(2.0,shelf_deep,shelf_d*0.125);
        float s=max(s_depth,(1.0-smoothstep(0.0,3500.0,coast_m))*0.9);
        vec3 c=mix(vec3(0.0085,0.040,0.107),vec3(0.0098,0.0704,0.121),smoothstep(0.0,0.5,s));
        c=mix(c,vec3(0.0203,0.0861,0.119),smoothstep(0.4,0.9,s));
        // Light water right at the beach; only a hairline in the mid view
        // (measured #9db8ad at 0.5 km there).
        float beach=1.0-smoothstep(0.0,max(px_m*2.0,800.0),coast_m);
        c=mix(c,vec3(0.060,0.120,0.135),beach*mix(0.85,0.35,smoothstep(200.0,500.0,view_width)));
        c*=1.0+(shelf_id-0.5)*0.05*smoothstep(0.1,0.4,s);
        c=mix(c*w.tone,water_foam_tint.rgb,w.foam*0.6);
        ALBEDO=mix(ALBEDO,c,near_sea);
    }
    EMISSION=w.emission;
    ROUGHNESS=w.roughness;
    // Sun glints come from water_look; the engine lobe would form a blob.
    SPECULAR=0.04;
    NORMAL=normalize((VIEW_MATRIX*vec4(w.normal,0.0)).xyz);
}
