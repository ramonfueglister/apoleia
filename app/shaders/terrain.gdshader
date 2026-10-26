shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://shaders/model_sampling.gdshaderinc"
#include "res://shaders/water_appearance.gdshaderinc"
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
uniform float surface_detail_strength=0.22;
uniform float model_facet_strength=0.88;
uniform float cartographic_relief_strength=0.23;
uniform float water_variation_strength=0.028;
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
    vec2 material_uv=(world_position.xz-surface_world_min)/surface_world_size;
    vec4 weights=display_material_weights_at(world_position.xz);
    float fixed_rock_channel=source_surface_rock_at(world_position.xz);
    vec2 detail_material_uv=(world_position.xz-detail_world_min)/detail_world_size;
    float lat=mix(north_lat,south_lat,geo_uv.y);
    bool semantic_surface=clipmap_enabled || use_surface_weights || (use_detail_surface_weights && inside_domain(detail_material_uv));
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
    // Geography owns material classes; three appearance scales vary their reflectance.
    float footprint=max(length(dFdx(local_render_position.xz)),length(dFdy(local_render_position.xz)));
    float macro=filtered_surface_noise(world_position.xz/20.0+vec2(7.1,13.4),footprint/20.0)-0.5;
    float meso=filtered_surface_noise(world_position.xz/2.0+vec2(23.7,4.3),footprint/2.0)-0.5;
    float micro=filtered_surface_noise(world_position.xz/0.16,footprint/0.16)-0.5;
    float variation=macro*0.16+meso*0.11+micro*0.035;
    vec3 warm_meadow=meadow_color.rgb*vec3(1.12,1.07,0.85);
    vec3 olive_meadow=open_color.rgb*vec3(0.90,1.04,0.85);
    ground=mix(ground,mix(olive_meadow,warm_meadow,clamp(0.5+macro*0.75+meso*0.4,0.0,1.0)),(1.0-dry)*(1.0-weights.r)*0.48);
    ground*=1.0+variation;
    // V8 lighting follows the actual retained-feature triangle surface used
    // by the renderer and CPU picking. No detached 2km DEM normal texture.
    // Material ownership uses the same fixed atlas gradient and base-level G
    // as CPU forest representation, including the flat endpoint. Screen LOD
    // may filter appearance but cannot change which material owns a place.
    vec3 source_normal=clipmap_enabled ? clipmap_normal(world_position.xz) : (use_fixed_surface ? fixed_surface_normal_at(world_position.xz) : canonical_normal);
    // Material hierarchy follows the FIXED represented form, not the much
    // shallower canonical source and not the camera's temporary relief fade.
    // CPU forest priority uses this same inverse transpose and fixed factor.
    vec3 fixed_display_normal=normalize(vec3(source_normal.x,source_normal.y/max(display_height_scale,0.00001),source_normal.z));
    float represented_slope=1.0-fixed_display_normal.y;
    float rock=max(fixed_rock_channel,max(smoothstep(0.06,0.25,represented_slope),smoothstep(1250.0,2700.0,h)*0.85));
    // Smooth plains and long lower hills; hard, directed faces on supported
    // rock/high relief. No global full-facet override and no detached DEM bump.
    float hard_face=max(0.24,max(smoothstep(0.28,0.75,rock),smoothstep(0.12,0.42,1.0-smooth_normal.y)*0.60));
    vec3 normal=normalize(mix(smooth_normal,facet_normal,hard_face*model_facet_strength));
    // The regular 2km transport triangles are not authored rock facets. Use
    // the same fixed atlas gradient already needed for material ownership.
    // Planar macroflanks retain their direction; raster-cell edges no longer
    // receive an independent hard lighting discontinuity. Geometry is intact.
    if(use_fixed_surface || clipmap_enabled) {
        vec3 terrain_normal=normalize(vec3(source_normal.x,source_normal.y/max(display_height_scale*relief,0.00001),source_normal.z));
        normal=normalize(mix(terrain_normal,facet_normal,hard_face*0.72*relief));
    }
    float aspect=clamp(dot(source_normal,normalize(vec3(-0.58,0.65,0.49))),0.0,1.0);
    // A few coherent facet values follow actual slope/aspect and source zones;
    // only reflectance is discretized, never positions or canonical heights.
    float stone_facet=material_facets(world_position.xz/1.4);
    vec3 stone=mix(rock_shadow_color.rgb,rock_color.rgb,0.68+stone_facet*0.24);
    stone*=1.0+meso*0.085;
    // Canonical rock above still governs fixed forest priority; only visible
    // reflectance uses the spatially bounded appearance-filtered G channel.
    float visible_rock=max(weights.g,max(smoothstep(0.06,0.25,represented_slope),smoothstep(1250.0,2700.0,h)*0.85));
    ground=mix(ground,stone,mix(rock,visible_rock,material_transition_strength));
    ground=mix(ground,snow_color.rgb,smoothstep(3650.0,4650.0,h+macro*160.0)*0.88);
    // Actual directional light now uses represented_normal; no second baked
    // directional darkening competes with the sun or suppresses slope contrast.
    // Regional lowland variation is semantic, not a free cloud texture.
    // Source SDF derivatives give metres per screen pixel perpendicular to
    // the actual contour, including isometric foreshortening and aspect.
    // Neither shoreline nor source distance moves; only material width does.
    float contour_m_per_px=max(length(vec2(dFdx(distance),dFdy(distance))),0.001);
    float shore_span=min(max(max(shore_band_m,140.0),contour_m_per_px*1.15),1800.0);
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
        // Long-range coastal distance is for water depth, not a 4.6 km sand
        // strip at every zoom. Keep the existing physical/screen-width bound.
        shore_span=min(max(max(shore_band_m,140.0),contour_m_per_px*1.15),1800.0);
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
    float shelf=water_kind_at(world_position.xz)==1.0?1.0-smoothstep(30.0,1800.0,max(-bathymetry,0.0)):0.0;
    vec3 sea=mix(water_deep_color.rgb,water_mid_color.rgb,clamp(shelf*0.55+shallow*0.40,0.0,1.0));
    // Native reference transects separate a narrow teal core from a long,
    // weak blue transition. The full graphic extent and palette stay fixed.
    // Cubic smoothstep reaches half at half its full support: core full3.6 /
    // half1.8 model units; long full24 / half12. No radius/diameter ambiguity.
    float teal_profile=shallow;
    if(graphic_coast) {
        float teal_core=1.0-smoothstep(0.0,shallow_span*0.15,max(material_distance,0.0));
        teal_profile=max(teal_core,shallow*0.24);
    }
    sea=mix(sea,water_shallow_color.rgb,teal_profile*0.67);
    float water_var=filtered_surface_noise(world_position.xz*0.012+vec2(4.7,8.1),footprint*0.012)*0.6+filtered_surface_noise(world_position.xz*5.0,footprint*5.0)*0.4;
    sea*=1.0+(water_var-0.5)*water_variation_strength;
    vec3 water_normal;float water_roughness;float water_specular;
    water_appearance(world_position.xz,distance,physical_water_kind==1.0 ? abs(material_distance) : abs(distance),max(-bathymetry,0.0),int(physical_water_kind),relief,view_width,footprint,TIME,sea,water_normal,water_roughness,water_specular);
    vec3 water_reflected_radiance;
    float water_reflectance;
    vec3 world_view_direction=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    water_environment_reflection(water_normal,world_view_direction,
        int(physical_water_kind),relief,view_width,
        water_reflected_radiance,water_reflectance);
    ALBEDO=mix(ground,sea*(1.0-water_reflectance),water);
    EMISSION=water_reflected_radiance*water_reflectance*water;
    ROUGHNESS=mix(0.94,water_roughness,water);
    SPECULAR=mix(0.15,water_specular,water);
    // Bounded source-height concavity adds soft valley/floor occlusion.
    float cavity=0.0;
    if(view_width<1600.0 && !marine_surface_only) {
        vec2 cavity_step=vec2(2.0,1.2);
        float surrounding=(model_height_at(world_position.xz+cavity_step)+model_height_at(world_position.xz-cavity_step))*0.5;
        cavity=smoothstep(30.0,340.0,surrounding-max(h,0.0))*relief;
    }
    AO=1.0-(weights.r*0.23+cavity*0.20)*(1.0-water);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(mix(normal,water_normal,water)),0.0)).xyz);
}
