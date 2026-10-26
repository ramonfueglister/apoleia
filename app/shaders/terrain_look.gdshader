shader_type spatial;
// Look variant of terrain.gdshader: identical vertex stage (forest layout
// binds terrain.gdshader by hash); fragment adds the reference look.
render_mode cull_disabled, diffuse_burley;
#include "res://shaders/model_sampling.gdshaderinc"
uniform sampler2D mapped_cover_tex : filter_linear_mipmap, repeat_disable;
uniform bool use_model_mesh=false;
uniform bool use_fixed_surface=false;
uniform sampler2D fixed_surface_height_tex : filter_nearest, repeat_disable;
uniform vec2 fixed_surface_world_min=vec2(0.0);
uniform vec2 fixed_surface_world_size=vec2(1.0);
uniform bool marine_surface_only=false;
uniform int active_model_count=0;
uniform vec4 active_model_bounds[8];
uniform vec2 shading_origin=vec2(0.0);
uniform float relief=0.0;
// Explicit V9 display mapping; canonical/source heights remain unchanged.
uniform float display_height_scale=1.0;
uniform float patch_cells=24.0;
uniform float view_width=1.0;
uniform float viewport_width=1920.0;
uniform float north_lat=59.0;
uniform float south_lat=24.0;
uniform vec4 open_color : source_color = vec4(0.537,0.600,0.314,1.0);
uniform vec4 meadow_color : source_color = vec4(0.643,0.667,0.412,1.0);
uniform vec4 forest_ground_color : source_color = vec4(0.345,0.424,0.239,1.0);
uniform vec4 dry_color : source_color = vec4(0.718,0.631,0.416,1.0);
uniform vec4 rock_color : source_color = vec4(0.737,0.702,0.608,1.0);
uniform vec4 rock_shadow_color : source_color = vec4(0.533,0.549,0.475,1.0);
uniform vec4 snow_color : source_color = vec4(0.867,0.851,0.765,1.0);
uniform vec4 shore_color : source_color = vec4(0.722,0.690,0.514,1.0);
uniform vec4 water_deep_color : source_color = vec4(0.082,0.302,0.467,1.0);
uniform vec4 water_mid_color : source_color = vec4(0.106,0.392,0.533,1.0);
uniform vec4 water_shallow_color : source_color = vec4(0.271,0.561,0.600,1.0);
uniform float shore_band_m=22.0;
uniform float shallow_band_m=240.0;
uniform float shore_screen_width_px=0.9;
uniform float shallow_screen_width_px=0.5;
// Separate render-distance sidecar. Physical water classification and its
// precise, short-range SDF remain authoritative for the coastline itself.
uniform bool use_display_coast_distance=false;
uniform sampler2D display_coast_distance_tex : filter_nearest, repeat_disable;
uniform vec2 display_coast_world_min=vec2(0.0);
uniform vec2 display_coast_world_size=vec2(1.0);
// Appearance-only compact kernel; source/base-level G and CPU ownership stay exact.
uniform float material_transition_radius_world=0.6;
uniform float material_transition_strength=1.0;
// Diagnostic baseline0 / product correction1; physical SDF/role never change.
uniform float coast_extension_strength=1.0;
uniform float shore_display_span_world=4.6;
uniform float shallow_display_span_world=24.0;
uniform float surface_detail_strength=0.075;
uniform float model_facet_strength=0.88;
uniform float cartographic_relief_strength=0.23;
uniform float water_variation_strength=0.028;
// Look layer (landscape_look.gd): intra-class colour variation and sea optics.
uniform vec4 look_olive_color : source_color = vec4(0.49,0.54,0.21,1.0);
uniform vec4 look_ochre_color : source_color = vec4(0.76,0.66,0.36,1.0);
uniform vec4 look_lime_color : source_color = vec4(0.69,0.74,0.30,1.0);
uniform vec4 sea_deep_color : source_color = vec4(0.059,0.247,0.471,1.0);
uniform vec4 sea_open_color : source_color = vec4(0.106,0.373,0.639,1.0);
uniform vec4 sea_shallow_color : source_color = vec4(0.247,0.655,0.710,1.0);
uniform vec4 sea_foam_color : source_color = vec4(0.93,0.96,0.95,1.0);
uniform vec4 sea_sky_color : source_color = vec4(0.50,0.71,0.86,1.0);
uniform float look_variation_strength=1.0;
uniform float look_facet_floor=0.45;
uniform float look_cavity_strength=0.30;
instance uniform vec4 patch_bounds=vec4(0.0,0.0,1.0,1.0);
varying vec2 geo_uv;
varying vec3 world_position;
varying vec3 canonical_position;
varying vec3 local_render_position;
varying vec3 model_smooth_normal;

float hash21(vec2 p) {p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float surface_noise(vec2 p) {
    vec2 c=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(c),hash21(c+vec2(1,0)),f.x),mix(hash21(c+vec2(0,1)),hash21(c+vec2(1)),f.x),f.y);
}
float filtered_surface_noise(vec2 p,float pixel_span) {
    return mix(surface_noise(p),0.5,smoothstep(0.25,0.75,pixel_span));
}
float material_facets(vec2 p) {
    vec2 c=floor(p),f=fract(p);
    float a=hash21(c),b=hash21(c+vec2(1,0)),d=hash21(c+vec2(1)),e=hash21(c+vec2(0,1));
    return f.x+f.y<1.0 ? a+(b-a)*f.x+(e-a)*f.y : d+(e-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
float look_fbm(vec2 p,float footprint) {
    // Three octaves, each faded to its mean once it is below pixel scale.
    float n=0.0,a=0.5,f=1.0;
    for(int i=0;i<3;i++) {n+=a*filtered_surface_noise(p*f+vec2(float(i)*17.3,float(i)*9.1),footprint*f);f*=2.07;a*=0.5;}
    return n/0.875;
}
float wave_height(vec2 p,float footprint,float t) {
    float a=filtered_surface_noise(p*0.42+vec2(t*0.031,t*0.018),footprint*0.42);
    float b=filtered_surface_noise(p*1.13+vec2(-t*0.047,t*0.039)+vec2(5.2,1.3),footprint*1.13);
    float c=filtered_surface_noise(p*2.9+vec2(t*0.071,-t*0.023)+vec2(2.7,8.4),footprint*2.9);
    return a*0.55+b*0.30+c*0.15;
}
// Atlas samples are vertices of one fixed triangle grid, not pixel-centre DEM
// values. CPU uses the same SW/NE cell diagonal and source-equivalent metres.
float fixed_surface_height_at(vec2 p) {
    vec2 dimensions=vec2(textureSize(fixed_surface_height_tex,0)-ivec2(1));
    vec2 q=clamp((p-fixed_surface_world_min)/fixed_surface_world_size,vec2(0.0),vec2(1.0))*dimensions;
    ivec2 cell=ivec2(min(floor(q),dimensions-vec2(1.0)));
    vec2 f=q-vec2(cell);
    float a=decode_model_height(fixed_surface_height_tex,cell,true);
    float b=decode_model_height(fixed_surface_height_tex,cell+ivec2(1,0),true);
    float c=decode_model_height(fixed_surface_height_tex,cell+ivec2(0,1),true);
    float d=decode_model_height(fixed_surface_height_tex,cell+ivec2(1),true);
    return f.x+f.y<1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
vec3 fixed_surface_normal_at(vec2 p) {
    vec2 step_size=fixed_surface_world_size/vec2(textureSize(fixed_surface_height_tex,0)-ivec2(1));
    float dx=(fixed_surface_height_at(p+vec2(step_size.x,0))-fixed_surface_height_at(p-vec2(step_size.x,0)))*0.001/(2.0*step_size.x);
    float dz=(fixed_surface_height_at(p+vec2(0,step_size.y))-fixed_surface_height_at(p-vec2(0,step_size.y)))*0.001/(2.0*step_size.y);
    return normalize(vec3(-dx,1.0,-dz));
}
float display_coast_decode(ivec2 cell) {
    vec2 code=texelFetch(display_coast_distance_tex,clamp(cell,ivec2(0),textureSize(display_coast_distance_tex,0)-ivec2(1)),0).rg;
    return (round(code.r*255.0)*256.0+round(code.g*255.0))*2.0;
}
float display_coast_distance_at(vec2 uv) {
    vec2 q=uv*vec2(textureSize(display_coast_distance_tex,0))-0.5;
    ivec2 cell=ivec2(floor(q));vec2 f=fract(q);
    return mix(mix(display_coast_decode(cell),display_coast_decode(cell+ivec2(1,0)),f.x),mix(display_coast_decode(cell+ivec2(0,1)),display_coast_decode(cell+ivec2(1)),f.x),f.y);
}
// Authored Color uniforms arrive linearized by Godot. The isolated GPU
// probe verified source_color/raw Color == StandardMaterial; manual decoding
// here double-decoded gray128 to56. Vertex COLOR follows a different path.
vec4 display_material_weights_at(vec2 p) {
    vec4 center=source_surface_weights_at(p);
    float r=material_transition_radius_world;
    vec4 filtered=(center*4.0+source_surface_weights_at(p+vec2(r,0.0))+source_surface_weights_at(p-vec2(r,0.0))+source_surface_weights_at(p+vec2(0.0,r))+source_surface_weights_at(p-vec2(0.0,r)))*0.125;
    return mix(center,filtered,material_transition_strength);
}
// Nonnegative C1 continuation. Unlike crossfading two offset distance fields,
// this cannot reduce a growing short distance merely as its source weight fades.
// The cap is the supplied physical SDF's3km transport range, not new geography.
float extended_display_coast_distance(float short_distance,float long_distance) {
    float cap=3000.0;
    float x=clamp((long_distance-(cap-500.0))/1000.0,0.0,1.0);
    float extension=long_distance<cap+500.0 ? 500.0*x*x : long_distance-cap;
    return short_distance+max(extension,0.0);
}

void vertex() {
    float altitude;
    if(use_model_mesh) {
        altitude=water_kind_at(VERTEX.xz)==1.0 ? 0.0 : VERTEX.y*1000.0;
    } else {
        vec2 patch_size=patch_bounds.zw*world_size;
        VERTEX.xz=world_min+(patch_bounds.xy+VERTEX.xz*patch_bounds.zw)*world_size;
        if(use_fixed_surface) {
            altitude=fixed_surface_height_at(VERTEX.xz);
            NORMAL=fixed_surface_normal_at(VERTEX.xz);
        } else {
        altitude=terrain_height_at(VERTEX.xz);
        vec2 step_size=patch_size/(patch_cells*0.5);
        vec2 cell=floor((VERTEX.xz-world_min)/step_size);
        vec2 corner=world_min+cell*step_size;
        vec2 f=clamp((VERTEX.xz-corner)/step_size,vec2(0.0),vec2(1.0));
        float a=terrain_height_at(corner),b=terrain_height_at(corner+vec2(step_size.x,0));
        float c=terrain_height_at(corner+vec2(0,step_size.y)),d=terrain_height_at(corner+step_size);
        float parent=f.x+f.y<1.0?a+(b-a)*f.x+(c-a)*f.y:d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
        altitude=mix(parent,altitude,smoothstep(0.11,0.22,max(patch_size.x,patch_size.y)/view_width));
        }
    }
    if(marine_surface_only) {altitude=0.0;NORMAL=vec3(0,1,0);}
    geo_uv=(VERTEX.xz-world_min)/world_size;
    canonical_position=vec3(VERTEX.x-shading_origin.x,altitude*0.001,VERTEX.z-shading_origin.y);
    VERTEX.y=altitude*0.001*display_height_scale*relief-((use_model_mesh || marine_surface_only) ? 0.0 : UV2.y*0.06*display_height_scale*relief);
    // Runtime supplies a geographic, zoom-independent gradient of the same
    // represented surface. Inverse transpose handles the separate Y mapping.
    model_smooth_normal=relief<0.00001 ? vec3(0,1,0) : normalize(vec3(NORMAL.x,NORMAL.y/max(display_height_scale*relief,0.00001),NORMAL.z));
    // Keep every vertex/shadow consumer in the same displayed coordinate
    // system, not just the custom fragment-lighting varying.
    NORMAL=model_smooth_normal;
    world_position=VERTEX;
    local_render_position=vec3(VERTEX.x-shading_origin.x,VERTEX.y,VERTEX.z-shading_origin.y);
}
void fragment() {
    // Exclusive physical ownership: one zero-height ocean plane, one land /
    // inland surface. No coincident ocean triangles from overlapping terrain.
    float physical_water_kind=water_kind_at(world_position.xz);
    if(marine_surface_only) {
        if(physical_water_kind!=1.0) discard;
    } else if(physical_water_kind==1.0) discard;
    // Canonical TIN owns its footprint. Raster fallback must not draw a second
    // different surface through block edges while neighboring blocks stream.
    if(!use_model_mesh && !marine_surface_only) {
        for(int i=0;i<8;i++) {
            if(i>=active_model_count) break;
            vec4 bounds=active_model_bounds[i];
            if(all(greaterThanEqual(world_position.xz,bounds.xy)) && all(lessThanEqual(world_position.xz,bounds.zw))) discard;
        }
    }
    // The fixed derived world owns material height, including relief=0.
    // Geometry decimation must not recolor the same place when zoom changes.
    // This is the generalized atlas, never a finer raw DEM microtexture.
    float h=use_fixed_surface ? fixed_surface_height_at(world_position.xz) : canonical_position.y*1000.0;
    float distance=water_distance_at(world_position.xz);
    float edge_aa=max(fwidth(distance)*0.7,0.15);
    float water=smoothstep(-edge_aa,edge_aa,distance);
    vec3 canonical_normal=normalize(cross(dFdy(canonical_position),dFdx(canonical_position)));
    if(canonical_normal.y<0.0) canonical_normal=-canonical_normal;
    vec3 facet_normal=normalize(cross(dFdy(local_render_position),dFdx(local_render_position)));
    if(facet_normal.y<0.0) facet_normal=-facet_normal;
    vec3 smooth_normal=normalize(model_smooth_normal);
    vec2 material_uv=(world_position.xz-surface_world_min)/surface_world_size;
    vec4 weights=display_material_weights_at(world_position.xz);
    float fixed_rock_channel=source_surface_rock_at(world_position.xz);
    vec2 detail_material_uv=(world_position.xz-detail_world_min)/detail_world_size;
    float lat=mix(north_lat,south_lat,geo_uv.y);
    bool semantic_surface=use_surface_weights || (use_detail_surface_weights && inside_domain(detail_material_uv));
    float dry=semantic_surface?weights.b:(1.0-smoothstep(29.0,37.0,lat));
    // RGBA is FOREST / ROCK / DRY / SHORE. Alpha was incorrectly used as
    // meadow evidence in V10, leaving inland plains with no green role.
    // This is a declared graphic interpretation of canonical low open land,
    // not a climate/moisture dataset or a new geographic texture.
    float low_open=(1.0-smoothstep(250.0,1150.0,h))*(1.0-dry);
    vec3 ground=mix(open_color.rgb,meadow_color.rgb,low_open*0.85);
    ground=mix(ground,dry_color.rgb,dry);
    ground=mix(ground,forest_ground_color.rgb,weights.r*0.94);
    if(!semantic_surface) {
        vec3 mapped=pow(texture(mapped_cover_tex,geo_uv).rgb,vec3(2.2));
        ground=mix(ground,mapped,0.36);
    }
    float footprint=max(length(dFdx(local_render_position.xz)),length(dFdy(local_render_position.xz)));
    // Look layer: multi-scale variation inside each material class
    // (lime <-> olive <-> ochre); classes themselves stay source-bound.
    vec2 vp=world_position.xz;
    float n_macro=look_fbm(vp/210.0+vec2(3.1,7.7),footprint/210.0);
    float n_meso=look_fbm(vp/38.0+vec2(1.9,4.2),footprint/38.0);
    float n_micro=look_fbm(vp/7.5,footprint/7.5);
    float open_land=(1.0-weights.r)*(1.0-dry*0.6);
    vec3 varied=mix(look_olive_color.rgb,look_lime_color.rgb,smoothstep(0.30,0.72,n_meso*0.65+n_macro*0.35));
    ground=mix(ground,varied,0.55*open_land*(1.0-dry)*look_variation_strength);
    float ochre=smoothstep(0.56,0.82,n_macro*0.55+n_meso*0.45)*(1.0-weights.r)*look_variation_strength;
    ground=mix(ground,look_ochre_color.rgb,ochre*mix(0.40,0.18,1.0-smoothstep(0.7,1.0,relief)));
    ground=mix(ground,forest_ground_color.rgb*0.82,weights.r*0.35);
    ground*=1.0+(n_micro-0.5)*0.22*look_variation_strength;
    // Overview (reduced relief): slightly deeper, greener land as in the reference.
    float overview=1.0-smoothstep(0.7,1.0,relief);
    ground=mix(ground,ground*vec3(0.80,0.86,0.86),overview);
    // Fine grass grain in the close views.
    ground*=1.0+(filtered_surface_noise(vp/1.1,footprint/1.1)-0.5)*0.20*(1.0-weights.r)*relief;
    // Faint triangle facets on open ground (low-poly read), pixel-filtered.
    float facet_px=footprint/2.2;
    ground*=1.0+(material_facets(vp/2.2)-0.5)*0.10*(1.0-smoothstep(0.3,0.8,facet_px))*relief;
    // V8 lighting follows the actual retained-feature triangle surface used
    // by the renderer and CPU picking. No detached 2km DEM normal texture.
    // Material ownership uses the same fixed atlas gradient and base-level G
    // as CPU forest representation, including the flat endpoint. Screen LOD
    // may filter appearance but cannot change which material owns a place.
    vec3 source_normal=use_fixed_surface ? fixed_surface_normal_at(world_position.xz) : canonical_normal;
    // Material hierarchy follows the FIXED represented form, not the much
    // shallower canonical source and not the camera's temporary relief fade.
    // CPU forest priority uses this same inverse transpose and fixed factor.
    vec3 fixed_display_normal=normalize(vec3(source_normal.x,source_normal.y/max(display_height_scale,0.00001),source_normal.z));
    float represented_slope=1.0-fixed_display_normal.y;
    float rock=max(fixed_rock_channel,max(smoothstep(0.06,0.25,represented_slope),smoothstep(1250.0,2700.0,h)*0.85));
    // Smooth plains and long lower hills; hard, directed faces on supported
    // rock/high relief. No global full-facet override and no detached DEM bump.
    float hard_face=max(smoothstep(0.28,0.75,rock),smoothstep(0.12,0.42,1.0-smooth_normal.y)*0.60);
    vec3 normal=normalize(mix(smooth_normal,facet_normal,hard_face*model_facet_strength));
    // The regular 2km transport triangles are not authored rock facets. Use
    // the same fixed atlas gradient already needed for material ownership.
    // Planar macroflanks retain their direction; raster-cell edges no longer
    // receive an independent hard lighting discontinuity. Geometry is intact.
    if(use_fixed_surface) normal=normalize(vec3(source_normal.x,source_normal.y/max(display_height_scale*relief,0.00001),source_normal.z));
    // Light low-poly facetting everywhere, stronger on rock faces.
    normal=normalize(mix(normal,facet_normal,clamp(max(look_facet_floor,hard_face)*relief,0.0,1.0)));
    float aspect=clamp(dot(source_normal,normalize(vec3(-0.58,0.65,0.49))),0.0,1.0);
    // A few coherent facet values follow actual slope/aspect and source zones;
    // only reflectance is discretized, never positions or canonical heights.
    vec3 stone=mix(rock_shadow_color.rgb,rock_color.rgb,0.82);
    // Canonical rock above still governs fixed forest priority; only visible
    // reflectance uses the spatially bounded appearance-filtered G channel.
    // Local neighbourhood mean on the fixed surface: crests vs. hollows.
    float around=h;
    if(use_fixed_surface) {
        float r=6.0;
        around=(fixed_surface_height_at(vp+vec2(r,0))+fixed_surface_height_at(vp-vec2(r,0))+fixed_surface_height_at(vp+vec2(0,r))+fixed_surface_height_at(vp-vec2(0,r)))*0.25;
    }
    // Rock on crests, peaks and steep high ground; green in valleys and on
    // lower flanks. The blocky semantic G channel is not shown.
    float crest_rock=smoothstep(40.0,220.0,h-around)*smoothstep(500.0,1100.0,h);
    float visible_rock=max(max(crest_rock,smoothstep(0.55,0.85,represented_slope)*smoothstep(900.0,1500.0,h)),smoothstep(1900.0,2900.0,h)*0.9);
    // Crisp rock/grass boundary and per-facet stone tone (low-poly read).
    float rock_v=smoothstep(0.38,0.62,visible_rock);
    // Clear lit/shadow sides per facet (sun from WSW), as in the reference.
    float sun_side=clamp(dot(facet_normal,normalize(vec3(-0.68,0.64,0.36))),0.0,1.0);
    stone*=mix(0.62,1.18,sun_side*sun_side*relief+(1.0-relief)*0.6);
    ground=mix(ground,stone,rock_v);
    ground=mix(ground,snow_color.rgb,smoothstep(3300.0,4300.0,h)*0.85);
    // Cavity darkening in valleys and hollows, from the same fixed surface.
    if(use_fixed_surface) {
        float cavity=smoothstep(0.0,260.0,around-h)-smoothstep(0.0,420.0,h-around)*0.35;
        ground*=1.0-look_cavity_strength*cavity;
    }
    // Actual directional light now uses represented_normal; no second baked
    // directional darkening competes with the sun or suppresses slope contrast.
    // Regional lowland variation is semantic, not a free cloud texture.
    // Source SDF derivatives give metres per screen pixel perpendicular to
    // the actual contour, including isometric foreshortening and aspect.
    // Neither shoreline nor source distance moves; only material width does.
    float contour_m_per_px=max(length(vec2(dFdx(distance),dFdy(distance))),0.001);
    float shore_span=min(max(shore_band_m,contour_m_per_px*shore_screen_width_px),1800.0);
    float shallow_span=min(max(shallow_band_m,contour_m_per_px*shallow_screen_width_px),1000.0);
    float material_distance=distance;
    vec2 coast_uv=(world_position.xz-display_coast_world_min)/display_coast_world_size;
    bool graphic_coast=use_display_coast_distance && inside_domain(coast_uv) && physical_water_kind!=2.0;
    if(graphic_coast) {
        float coast_distance=display_coast_distance_at(coast_uv);
        // Preserve the exact existing contour close to zero; the sidecar only
        // extends its range. No zero-contour or physical role is displaced.
        float exact_weight=1.0-smoothstep(1000.0,2000.0,coast_distance);
        float baseline_distance=mix(coast_distance,abs(distance),exact_weight);
        float unsigned_distance=mix(baseline_distance,extended_display_coast_distance(abs(distance),coast_distance),coast_extension_strength);
        material_distance=(physical_water_kind==1.0 ? 1.0 : -1.0)*unsigned_distance;
        shore_span=max(shore_display_span_world*1000.0,contour_m_per_px*shore_screen_width_px);
        shallow_span=max(shallow_display_span_world*1000.0,contour_m_per_px*shallow_screen_width_px);
    }
    // The final ground/sea mix applies (1-water) once. Applying it here too
    // suppressed the real shoreline color twice (confirmed frozen-scene A/B).
    float shore=(1.0-smoothstep(graphic_coast ? shore_span*0.2 : 0.0,shore_span,max(-material_distance,0.0)));
    ground=mix(ground,shore_color.rgb,shore*(graphic_coast ? (0.85+weights.a*0.15) : (0.60+weights.a*0.15)));
    float carto=clamp(dot(source_normal,normalize(vec3(-0.45,0.78,0.4))),0.0,1.0);
    ground*=mix(1.0,0.82+carto*0.29,cartographic_relief_strength*(1.0-relief));
    // Packed SDFs saturate around3km. Saturated open ocean must NEVER become
    // shallow water when the overview pixel footprint grows beyond that range.
    float shallow=(1.0-smoothstep(0.0,shallow_span,max(material_distance,0.0)));
    if(!graphic_coast) shallow*=1.0-step(2999.0,distance);
    float bathymetry=model_height_at(world_position.xz);
    float depth=water_kind_at(world_position.xz)==1.0 ? max(-bathymetry,0.0) : 30.0;
    float coast_m=max(material_distance,0.0);
    // Depth ramp: navy abyss -> open blue -> broad turquoise shelf/saum.
    vec3 sea=mix(sea_open_color.rgb,sea_deep_color.rgb,smoothstep(600.0,3800.0,depth)*0.55);
    float shelf_t=1.0-smoothstep(15.0,140.0,depth);
    // Broad saum up close, only a thin lighter rim in the overview.
    float saum_scale=mix(0.22,1.0,smoothstep(0.7,1.0,relief));
    float saum=1.0-smoothstep(0.0,shallow_span*0.62*saum_scale,coast_m);
    // Steep island flanks drop off fast: no broad turquoise halo there.
    if(physical_water_kind==1.0) saum*=1.0-smoothstep(90.0,500.0,depth)*0.85;
    float core=1.0-smoothstep(0.0,shallow_span*0.16,coast_m);
    // Patchy outer edge so the shelf colour does not read as a uniform halo.
    float saum_edge=look_fbm(vp/14.0,footprint/14.0);
    float turq=clamp(max(pow(saum,1.4)*(0.70+0.45*saum_edge),shelf_t*0.55*saum_scale)+core*0.30,0.0,1.0);
    if(!graphic_coast) turq*=1.0-step(2999.0,distance);
    if(physical_water_kind==2.0) turq*=saum_scale;
    if(physical_water_kind==1.0) turq*=1.0-smoothstep(150.0,900.0,depth)*0.55;
    sea=mix(sea,sea_shallow_color.rgb,turq);
    // Animated waves; damped in the flat overview (relief ~ 0) and filtered
    // away once wavelengths drop below pixel size.
    float wave_amount=smoothstep(0.05,0.6,relief)*(1.0-smoothstep(0.35,1.1,footprint));
    float t=TIME;
    vec2 wp=world_position.xz/9.0;
    float wfp=footprint/9.0;
    float e=0.08;
    float w0=wave_height(wp,wfp,t);
    float wx=wave_height(wp+vec2(e,0.0),wfp,t);
    float wz=wave_height(wp+vec2(0.0,e),wfp,t);
    vec3 wave_normal=normalize(vec3(-(wx-w0)/e*0.20*wave_amount,1.0,-(wz-w0)/e*0.20*wave_amount));
    float mottled=(w0-0.5)*wave_amount;
    sea*=1.0+mottled*0.30;
    // Low-poly water facets and broad tonal drift, as in the reference.
    float sea_facet_px=footprint/5.0;
    sea*=1.0+(material_facets(vp/5.0+vec2(t*0.02,0.0))-0.5)*0.16*(1.0-smoothstep(0.3,0.8,sea_facet_px));
    sea*=1.0+(look_fbm(vp/160.0,footprint/160.0)-0.5)*0.22;
    // Fresnel-like sky sheen from the wave slopes.
    float fres=pow(1.0-clamp(dot(wave_normal,normalize(vec3(0.0,0.58,0.81))),0.0,1.0),3.0);
    sea=mix(sea,sea_sky_color.rgb,clamp(fres*0.6*wave_amount,0.0,0.10));
    // Thin animated surf line from the coast SDF.
    float px=max(contour_m_per_px,1.0);
    float foam_w=max(px*1.7,120.0);
    float surf=1.0-smoothstep(foam_w*0.35,foam_w,coast_m);
    float ring_phase=fract(t*0.11+w0*0.6);
    float ring_pos=foam_w*(1.2+ring_phase*3.0);
    float ring=exp(-abs(coast_m-ring_pos)/(foam_w*0.35))*(1.0-ring_phase)*0.55*wave_amount;
    float foam=clamp(surf*(0.72+0.28*sin(t*1.7+w0*9.0))+ring,0.0,1.0)*(1.0-smoothstep(1.2,3.5,footprint));
    if(physical_water_kind==2.0) foam*=0.35;
    sea=mix(sea,sea_foam_color.rgb,foam*0.85);
    ALBEDO=mix(ground,sea,water);
    ROUGHNESS=mix(0.94,mix(0.70,0.42,wave_amount),water);
    SPECULAR=mix(0.15,mix(0.18,0.34,wave_amount),water);
    AO=1.0-weights.r*0.12*(1.0-water);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(mix(normal,wave_normal,water)),0.0)).xyz);
}
