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
    // Crisp shoreline: a faint lighter line exactly at the contour in the
    // map view (was much lighter than the reference: 1 px #65a3bd against
    // #286e94 in the far view).
    float edge=1.0-smoothstep(0.0,px_m*1.2,coast_m);
    ALBEDO=mix(w.albedo,w.albedo*1.12+0.01,edge*(1.0-saum_scale)*0.5);
    // Mid view: blue, gently lighter towards the coast, no turquoise saum
    // (reference #1e7097 at 0.5 km, #257197 at 1 km, #1d6392 at ~4 km,
    // #1b5b8d open; ours had a pale 1-3 px rim, #77b6cb / #59a2be).
    float mid_sea=smoothstep(250.0,450.0,view_width)*(1.0-smoothstep(900.0,1600.0,view_width));
    if(mid_sea>0.0) {
        // 903029a at 450 km: open sea #1a5488 against #1b598b, and the
        // lighter coastal band ended within ~6 px (4 px #226491, 10 px
        // #1c5789) where the reference fades over ~30 px (#257197, #1f6595,
        // 20 px #1b5f90). The coast distance saturates at ~3 km, so the
        // shelf depth carries the wide part of the band.
        // a117124: close (4 px #246993 against #257197) but 4-14 px a step
        // dark and short, red 3-5 high throughout.
        vec3 open=mix(water_open_tint.rgb,water_deep_tint.rgb,smoothstep(500.0,3600.0,depth)*0.25)*w.tone*vec3(0.93,1.12,1.05);
        float near=1.0-smoothstep(0.0,4000.0,coast_m);
        float band=max(near*near*(3.0-2.0*near),(1.0-smoothstep(40.0,500.0,depth))*0.6);
        // Keep the open sea's facet and wave tone steps.
        float texture_tone=clamp(dot(w.albedo,vec3(1.0))/max(dot(open,vec3(1.0)),0.0001),0.85,1.15);
        vec3 c=open*mix(vec3(1.0),vec3(1.0,1.6,1.2),band)*mix(texture_tone,1.0,near);
        ALBEDO=mix(ALBEDO,mix(c,water_foam_tint.rgb,w.foam*0.4),mid_sea);
    }
    // Reference calibration (h~207 s0.80-0.83 v0.52-0.55): slightly darker,
    // and less saturated in the continental view where AgX pushes chroma.
    float far_sea=smoothstep(800.0,2800.0,view_width);
    // Far and mid views: the reference sea brightens over the shelves and
    // towards the coasts over tens of km (v 0.50-0.52 open, 0.58-0.64 near
    // the coasts, Adriatic ~0.57; ours was a flat 0.51). The tile coast
    // distance ends at ~4 km, so the bathymetry carries this ramp.
    // r9: far median v 0.57 against 0.52-0.55 and blotchy deep basins, so
    // only the shelves and slopes (under ~1600 m) and a smaller gain.
    float shelf_light=(1.0-smoothstep(150.0,1600.0,depth))*smoothstep(300.0,700.0,view_width);
    // 903029a far view: open basins #194d81 against #175788 (green and blue
    // low), shelves 6-14 px #195a93 against #165e90 / #17598c (blue high):
    // the deep sea greener and lighter, the shelves a little less blue.
    // a117124: open sea beyond 30 px #1c598c against #175689 (a little
    // light and red); 10-14 px on the reference; the lighter edge at 2-6 px
    // (#176698, #176294, #165e91) missing, ours flat #175990. The coast
    // distance saturates at ~3 km (under 2 px here), so the edge uses it
    // only below 2.9 km and otherwise the shallow shelf (under ~120 m).
    vec3 far_gain=mix(vec3(0.70,1.19,1.06),vec3(0.93,1.0,0.95)*1.20,shelf_light);
    float far_rim=max((1.0-smoothstep(0.0,2900.0,coast_m))*(1.0-step(2900.0,coast_m)),(1.0-smoothstep(20.0,120.0,depth))*0.6);
    far_gain*=mix(vec3(1.0),vec3(0.95,1.22,1.06),far_rim);
    ALBEDO*=mix(1.04,1.12,far_sea)*mix(vec3(1.0+0.20*shelf_light),far_gain,far_sea);
    ALBEDO=mix(ALBEDO,vec3(dot(ALBEDO,vec3(0.2126,0.7152,0.0722))),(0.10+far_sea*0.06)*(1.0-0.5*shelf_light));
    // Close views: shallow water as a broad, even ramp like the reference
    // near view (open #185585 -> #1f708d -> teal #2f7b8c -> #528f94 at the
    // beach). Shallowness comes from the bathymetry (0-100 m, ~10-20 km off
    // flat coasts) and, inside ~3.5 km, the coast distance (the clipmap
    // distance saturates at ~4 km). The bathymetry is 25 m codes on a
    // 0.5-1 km grid; a 4-tap blur over about two texels hides its squares,
    // and faint per-triangle tone steps keep the low-poly seabed. Targets
    // are linear albedo, fitted to the reference through the open sea's
    // screen gain.
    // Teal ramp for the near view only; the mid view reference is blue
    // up to the coast (#1e7097 at 0.5 km, #257197 at 1 km).
    float near_sea=(1.0-smoothstep(220.0,520.0,view_width))*(1.0-mouth*0.6);
    if(near_sea>0.0) {
        float shelf_id;
        wl_facet_center(p,2.2,shelf_id);
        // At most 0.6 km: the far part of the close view lies on coarse
        // tiles (2 km texels), where taps 5 km out averaged open-sea depth
        // into the coast, so the teal band ended mid-frame (b757b7f, 190 km:
        // #31618a up to the far coast against the reference #38828e).
        float tile_texel=clipmap_enabled ? tile_rect.z/max(float(textureSize(tile_water_tex,0).x-1),1.0) : 0.5;
        float texel=min(tile_texel,0.6);
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
        // 515f650 at 190 km: teal flat out to 10 px, falling only at 20-30
        // px; the reference falls from 4 to 10 px (~0.4-1.1 km).
        float shelf_deep=mix(45.0,40.0,smoothstep(250.0,800.0,view_width));
        float s_depth=1.0-smoothstep(2.0,shelf_deep,shelf_d*0.125);
        // Coarse tiles store the coast as a texel water share (0 to 4 km
        // within one texel), so the band spans at least ~2 texels there.
        float s=max(s_depth,(1.0-smoothstep(0.0,max(1400.0,tile_texel*2200.0),coast_m))*0.9);
        // Mid and teal stops a little greener and brighter (measured 2-5 km
        // #327387, 10 km #216a86 against #2f7b8c and #1f708d).
        // Deep stop ~10 % lighter (b757b7f 20-30 px off the coast #165685 /
        // #135383 against the reference #1c648a / #1c5d8a).
        vec3 c=mix(vec3(0.0095,0.045,0.112),vec3(0.0090,0.0770,0.130),smoothstep(0.0,0.5,s));
        c=mix(c,vec3(0.0190,0.0950,0.122),smoothstep(0.4,0.9,s));
        // Light water right at the beach; only a hairline in the mid view
        // (measured #9db8ad at 0.5 km there).
        // b757b7f at 190 km: light for 1 px only (#588893, then #347a89);
        // the reference fades over ~5 px (#5b8f8e, #498a8f, #40868e,
        // #38828e, #2a7a8d at 6 px), lighter and greener.
        // 5b44221: 2-4 px still a step dark (#3a7c8a / #2b7887 against
        // #498a8f / #38828e): a little wider.
        float beach=1.0-smoothstep(0.0,max(px_m*6.5,1300.0),coast_m);
        c=mix(c,vec3(0.062,0.150,0.158),beach*mix(0.85,0.08,smoothstep(200.0,450.0,view_width)));
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
