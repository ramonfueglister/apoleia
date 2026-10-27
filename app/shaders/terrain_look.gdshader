shader_type spatial;
// Look variant of terrain.gdshader: identical vertex stage (forest layout
// binds terrain.gdshader by hash); fragment adds the reference look.
render_mode cull_disabled, diffuse_burley;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_look.gdshaderinc"
uniform bool streamed_terrain=false;
uniform float terrain_morph_alpha=1.0;
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
    float value=f.x+f.y<1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
    return material_cohort_value_3(p,vec4(value,0.0,0.0,0.0)).x;
}
vec3 fixed_surface_normal_at(vec2 p) {
    vec2 step_size=fixed_surface_world_size/vec2(textureSize(fixed_surface_height_tex,0)-ivec2(1));
    if(terrain_pages)step_size=canonical_grid_spacing;
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
    float value=mix(mix(display_coast_decode(cell),display_coast_decode(cell+ivec2(1,0)),f.x),mix(display_coast_decode(cell+ivec2(0,1)),display_coast_decode(cell+ivec2(1)),f.x),f.y);
    vec2 p=display_coast_world_min+uv*display_coast_world_size;
    return material_cohort_value_4(p,vec4(value,0.0,0.0,0.0)).x;
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
// Shared painted land look; the host supplies its represented surface.
#define LAND_LOOK_HEIGHT(p) (use_fixed_surface ? fixed_surface_height_at(p) : model_height_at(p))
#define LAND_LOOK_WEIGHTS(p) source_surface_weights_at(p)
#include "res://shaders/terrain_land_look.gdshaderinc"
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
    if(clipmap_enabled) {
        VERTEX.xz=clipmap_origin+VERTEX.xz*clipmap_span;
        altitude=clipmap_water_kind(VERTEX.xz)==1.0 ? 0.0 : clipmap_ring_height(VERTEX.xz);
        NORMAL=clipmap_normal(VERTEX.xz);
    } else if(streamed_terrain) {
        altitude=(UV2.x+(VERTEX.y-UV2.x)*terrain_morph_alpha)*1000.0;
    } else if(use_model_mesh) {
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
// Kit 2 map mode "Bevölkerung" (docs/kit2/ARCHITECTURE.md S46). The Rust
// bridge provides the tile slot per 1.5625 km cell (slot + 1, 0 = none) and
// one value texel per slot (population, people per km²); a tile keeps its
// slot until it is split or merged. The colour follows the density and is
// computed here, so a new month only re-uploads the value texture.
uniform bool map_mode_population=false;
// The index is cut into square pages, one array layer each, so a split or
// merge re-uploads only the pages it touches; page (x, y) is layer
// y * map_index_pages_x + x.
uniform sampler2DArray map_index_tex : filter_nearest, repeat_disable;
uniform int map_index_pages_x=1;
uniform sampler2D map_value_tex : filter_nearest, repeat_disable;
uniform vec2 map_index_origin=vec2(0.0);
uniform float map_index_cell=1.5625;
uniform int map_value_width=1024;
// Colour by density (people per km²) on a fixed log scale, so tiles of
// different size compare fairly and colours keep their meaning over time.
uniform float map_density_low=0.3;
uniform float map_density_high=300.0;

vec3 map_srgb_to_linear(vec3 c) {
    return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(0.04045,c));
}
// Same ramp as the browser view: maroon, red-brown, ochre, olive, green.
vec3 map_ramp(float t) {
    vec3 stops[5]=vec3[5](vec3(122,42,40),vec3(138,90,44),vec3(160,138,48),vec3(143,154,53),vec3(95,154,58));
    float x=clamp(t,0.0,1.0)*4.0;
    int a=min(int(floor(x)),3);
    return map_srgb_to_linear(mix(stops[a],stops[a+1],x-float(a))/255.0);
}
int map_tile(ivec2 c) {
    if(any(lessThan(c,ivec2(0)))) return -1;
    ivec3 size=textureSize(map_index_tex,0);
    ivec2 page=c/size.xy;
    int layer=page.y*map_index_pages_x+page.x;
    if(page.x>=map_index_pages_x || layer>=size.z) return -1;
    return int(texelFetch(map_index_tex,ivec3(c-page*size.xy,layer),0).r+0.5)-1;
}
vec3 population_overlay(vec3 ground,vec2 p) {
    if(!map_mode_population) return ground;
    vec2 f=(p-map_index_origin)/map_index_cell;
    ivec2 c=ivec2(floor(f));
    int i=map_tile(c);
    if(i<0) return ground;
    vec2 v=texelFetch(map_value_tex,ivec2(i%map_value_width,i/map_value_width),0).rg;
    float t=log(max(v.g,map_density_low)/map_density_low)/log(map_density_high/map_density_low);
    vec3 col=map_ramp(t);
    // Keep a little of the relief shading under the flat colour.
    float shade=dot(ground,vec3(0.2126,0.7152,0.0722))/0.18;
    col*=mix(1.0,clamp(shade,0.7,1.25),0.35);
    // Thin dark border where the neighbouring cell belongs to another tile,
    // about one screen pixel wide at any zoom.
    vec2 fr=fract(f);
    vec2 px=max(fwidth(f),vec2(1e-6));
    bool edge=(fr.x<px.x && map_tile(c+ivec2(-1,0))!=i) || (fr.x>1.0-px.x && map_tile(c+ivec2(1,0))!=i)
        || (fr.y<px.y && map_tile(c+ivec2(0,-1))!=i) || (fr.y>1.0-px.y && map_tile(c+ivec2(0,1))!=i);
    return edge ? col*0.45 : col;
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
    if(!clipmap_enabled && !use_model_mesh && !marine_surface_only) {
        for(int i=0;i<8;i++) {
            if(i>=active_model_count) break;
            vec4 bounds=active_model_bounds[i];
            if(all(greaterThanEqual(world_position.xz,bounds.xy)) && all(lessThanEqual(world_position.xz,bounds.zw))) discard;
        }
    }
    // The fixed derived world owns material height, including relief=0.
    // Geometry decimation must not recolor the same place when zoom changes.
    // This is the generalized atlas, never a finer raw DEM microtexture.
    float h=clipmap_enabled ? clipmap_source_height(world_position.xz) : (use_fixed_surface ? fixed_surface_height_at(world_position.xz) : canonical_position.y*1000.0);
    float distance=water_distance_at(world_position.xz);
    float edge_aa=max(fwidth(distance)*0.7,0.15);
    float water=smoothstep(-edge_aa,edge_aa,distance);
    vec3 canonical_normal=normalize(cross(dFdy(canonical_position),dFdx(canonical_position)));
    if(canonical_normal.y<0.0) canonical_normal=-canonical_normal;
    vec3 facet_normal=normalize(cross(dFdy(local_render_position),dFdx(local_render_position)));
    if(facet_normal.y<0.0) facet_normal=-facet_normal;
    vec3 smooth_normal=normalize(model_smooth_normal);
    // The land look blurs and edges the fields itself; one tap here.
    vec4 weights=source_surface_weights_at(world_position.xz);
    vec2 detail_material_uv=(world_position.xz-detail_world_min)/detail_world_size;
    float lat=mix(north_lat,south_lat,geo_uv.y);
    bool semantic_surface=clipmap_enabled || use_surface_weights || (use_detail_surface_weights && inside_domain(detail_material_uv));
    // RGBA is FOREST / ROCK / DRY / SHORE; without semantics dry follows latitude.
    if(!semantic_surface) weights.b=1.0-smoothstep(29.0,37.0,lat);
    float footprint=max(length(dFdx(local_render_position.xz)),length(dFdy(local_render_position.xz)));
    vec2 vp=world_position.xz;
    // Lighting and materials follow the fixed represented surface, never the
    // decimated render mesh (which only contributes rock silhouettes).
    vec3 source_normal=clipmap_enabled ? clipmap_normal(world_position.xz) : (use_fixed_surface ? fixed_surface_normal_at(world_position.xz) : canonical_normal);
    LandLook land=land_look(vp,h,weights,source_normal,facet_normal,footprint,relief,view_width,display_height_scale);
    vec3 ground=land.albedo;
    vec3 normal=land.normal;
    if(!semantic_surface) ground=mix(ground,pow(texture(mapped_cover_tex,geo_uv).rgb,vec3(2.2)),0.25);
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
    bool graphic_coast=!clipmap_enabled && use_display_coast_distance && inside_domain(coast_uv) && physical_water_kind!=2.0;
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
    // Packed SDFs saturate around3km. Saturated open ocean must NEVER become
    // shallow water when the overview pixel footprint grows beyond that range.
    float shallow=(1.0-smoothstep(0.0,shallow_span,max(material_distance,0.0)));
    if(!graphic_coast) shallow*=1.0-step(2999.0,distance);
    // Sea has its own surface (water.gdshader). Here only lakes and the
    // anti-aliased land side of the contour need water optics, and only
    // those fragments pay for them.
    float px=max(contour_m_per_px,1.0);
    vec3 sea=vec3(0.0);vec3 water_emission=vec3(0.0);vec3 wave_normal=vec3(0.0,1.0,0.0);
    float wave_amount=0.0;
    if(water>0.001) {
        float depth=physical_water_kind==1.0 ? max(-model_height_at(vp),0.0) : 25.0;
        float saum_scale=physical_water_kind==2.0 ? 0.0 : mix(0.22,1.0,smoothstep(0.7,1.0,relief));
        vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
        WaterSample w=water_shade(vp,max(material_distance,0.0),depth,footprint,smoothstep(0.05,0.6,relief),view_world,vec2(0.0),px,saum_scale,0.0);
        sea=w.albedo;water_emission=w.emission;wave_normal=w.normal;
        wave_amount=smoothstep(0.05,0.6,relief)*(1.0-smoothstep(0.35,1.1,footprint));
    }
    // Wet, darker sand right at the waterline.
    float wet_w=max(px*2.2,260.0);
    float wet=(1.0-smoothstep(0.0,wet_w,max(-material_distance,0.0)))*(1.0-water);
    ground*=mix(1.0,0.78+0.05*sin(TIME*1.3+vp.x*0.7),wet*shore);
    ground=population_overlay(ground,world_position.xz);
    ALBEDO=mix(ground,sea,water);
    EMISSION=water_emission*water;
    ROUGHNESS=mix(0.94,mix(0.70,0.42,wave_amount),water);
    SPECULAR=mix(0.15,mix(0.18,0.34,wave_amount),water);
    AO=mix(land.ao,1.0,water);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(mix(normal,wave_normal,water)),0.0)).xyz);
}
