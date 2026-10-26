#include "res://shaders/terrain_clipmap.gdshaderinc"
uniform bool terrain_pages=false;
uniform vec4 context_height_page=vec4(0.,0.,1.,1.);
uniform vec4 fine_height_page=vec4(0.,0.,1.,1.);
uniform vec4 context_associated_role_page=vec4(0.,0.,1.,1.);
uniform vec4 fine_associated_role_page=vec4(0.,0.,1.,1.);
uniform vec4 local_associated_role_page=vec4(0.,0.,1.,1.);
uniform vec4 context_water_distance_page=vec4(0.,0.,1.,1.);
uniform vec4 fine_water_distance_page=vec4(0.,0.,1.,1.);
uniform vec4 local_water_distance_page=vec4(0.,0.,1.,1.);
uniform vec4 context_surface_weights_page=vec4(0.,0.,1.,1.);
uniform vec4 fine_surface_weights_page=vec4(0.,0.,1.,1.);
uniform vec4 local_surface_weights_page=vec4(0.,0.,1.,1.);
vec2 page_uv(vec2 p,vec2 legacy,vec4 page){return terrain_pages ? (p-page.xy)/page.zw : legacy;}
// Canonical generalized model sampling. No geometric noise or source invention.
// Main and detail domains are separate: core textures must never stretch over context.
uniform bool height_packed = true;
uniform sampler2D elevation_tex : filter_nearest, repeat_disable;
uniform bool use_detail_elevation = false;
uniform bool detail_height_packed = true;
uniform sampler2D detail_elevation_tex : filter_nearest, repeat_disable;
uniform vec2 world_size = vec2(1.0);
uniform vec2 world_min = vec2(0.0);
uniform vec2 detail_world_size = vec2(1.0);
uniform vec2 detail_world_min = vec2(0.0);
uniform sampler2D water_tex : filter_nearest, repeat_disable;
uniform sampler2D water_distance_tex : filter_nearest, repeat_disable;
uniform bool use_water_distance = true;
uniform bool use_detail_water = false;
uniform sampler2D detail_water_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_water_distance_tex : filter_nearest, repeat_disable;
uniform bool use_detail_water_distance = true;
uniform bool use_water_tile = false;
uniform bool use_water_tile_distance = false;
uniform sampler2D water_tile_tex : filter_nearest, repeat_disable;
uniform sampler2D water_tile_distance_tex : filter_nearest, repeat_disable;
uniform vec2 water_tile_world_min=vec2(0.0);
uniform vec2 water_tile_world_size=vec2(1.0);

// V2 domains are fixed geography, never camera-activated caches.
uniform bool use_c2_domains=false;
uniform vec2 fine_inner_world_min=vec2(0.0);
uniform vec2 fine_inner_world_size=vec2(1.0);
uniform vec2 local_inner_world_min=vec2(0.0);
uniform vec2 local_inner_world_size=vec2(1.0);
uniform sampler2D local_surface_weights_tex : filter_linear_mipmap, repeat_disable;
uniform bool use_surface_weights=false;
uniform sampler2D surface_weights_tex : filter_linear_mipmap, repeat_disable;
uniform bool use_detail_surface_weights=false;
uniform sampler2D detail_surface_weights_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 surface_world_min=vec2(0.0);
uniform vec2 surface_world_size=vec2(1.0);

float c2_smoother(float t) {t=clamp(t,0.0,1.0);return t*t*t*(t*(6.0*t-15.0)+10.0);}
float c2_domain_weight(vec2 p,vec2 outer_min,vec2 outer_size,vec2 inner_min,vec2 inner_size) {
    vec2 outer_max=outer_min+outer_size,inner_max=inner_min+inner_size;
    return c2_smoother((p.x-outer_min.x)/(inner_min.x-outer_min.x))*c2_smoother((outer_max.x-p.x)/(outer_max.x-inner_max.x))*c2_smoother((p.y-outer_min.y)/(inner_min.y-outer_min.y))*c2_smoother((outer_max.y-p.y)/(outer_max.y-inner_max.y));
}
vec2 source_domain_weights(vec2 p) {
    return vec2(c2_domain_weight(p,detail_world_min,detail_world_size,fine_inner_world_min,fine_inner_world_size),c2_domain_weight(p,water_tile_world_min,water_tile_world_size,local_inner_world_min,local_inner_world_size));
}

#include "res://shaders/terrain_material_pages.gdshaderinc"

bool inside_domain(vec2 uv) { return all(greaterThanEqual(uv,vec2(0.0))) && all(lessThanEqual(uv,vec2(1.0))); }
float decode_model_height(sampler2D tex, ivec2 cell, bool packed) {
    vec2 code=texelFetch(tex,clamp(cell,ivec2(0),textureSize(tex,0)-ivec2(1)),0).rg;
    return packed ? (round(code.r*255.0)*256.0+round(code.g*255.0))*0.25-8192.0 : code.r;
}
float bilinear_model_height(sampler2D tex,vec2 uv,bool packed) {
    vec2 p=uv*vec2(textureSize(tex,0))-0.5;
    ivec2 c=ivec2(floor(p));vec2 f=fract(p);
    return mix(mix(decode_model_height(tex,c,packed),decode_model_height(tex,c+ivec2(1,0),packed),f.x),mix(decode_model_height(tex,c+ivec2(0,1),packed),decode_model_height(tex,c+ivec2(1,1),packed),f.x),f.y);
}
float model_height_at(vec2 p) {
    if(clipmap_enabled)return clipmap_water_kind(p)==1.0 ? -clipmap_bathymetry(p) : clipmap_source_height(p);
    vec2 uv=(p-detail_world_min)/detail_world_size;
    if(use_c2_domains) return material_cohort_value_0(p,vec4(mix(bilinear_model_height(elevation_tex,page_uv(p,(p-world_min)/world_size,context_height_page),height_packed),bilinear_model_height(detail_elevation_tex,page_uv(p,uv,fine_height_page),detail_height_packed),source_domain_weights(p).x),0.0,0.0,0.0)).x;
    if(use_detail_elevation && inside_domain(uv)) return material_cohort_value_0(p,vec4(bilinear_model_height(detail_elevation_tex,page_uv(p,uv,fine_height_page),detail_height_packed),0.0,0.0,0.0)).x;
    return material_cohort_value_0(p,vec4(bilinear_model_height(elevation_tex,page_uv(p,(p-world_min)/world_size,context_height_page),height_packed),0.0,0.0,0.0)).x;
}
// Canonical source normal: differentiate composed H, including C2 weights.
vec3 source_model_normal_at(vec2 p,float step_model) {
    float dx=(model_height_at(p+vec2(step_model,0.0))-model_height_at(p-vec2(step_model,0.0)))*0.001/(2.0*step_model);
    float dz=(model_height_at(p+vec2(0.0,step_model))-model_height_at(p-vec2(0.0,step_model)))*0.001/(2.0*step_model);
    return normalize(vec3(-dx,1.0,-dz));
}
float sample_water_kind(sampler2D tex,vec2 uv) {
    return floor(texelFetch(tex,clamp(ivec2(floor(uv*vec2(textureSize(tex,0)))),ivec2(0),textureSize(tex,0)-ivec2(1)),0).r*255.0+0.5);
}
float decode_model_distance(sampler2D tex,ivec2 cell) {
    vec2 code=texelFetch(tex,clamp(cell,ivec2(0),textureSize(tex,0)-ivec2(1)),0).rg;
    return (round(code.r*255.0)*256.0+round(code.g*255.0))*0.125-4096.0;
}
// Quadratic B-spline (3x3) near the contour instead of bilinear: removes the
// texel staircase of the coast; C1-smooth, slightly rounds sub-texel corners.
float bilinear_model_distance(sampler2D tex,vec2 uv) {
    vec2 p=uv*vec2(textureSize(tex,0))-0.5;
    ivec2 c0=ivec2(floor(p));vec2 f=fract(p);
    float linear=mix(mix(decode_model_distance(tex,c0),decode_model_distance(tex,c0+ivec2(1,0)),f.x),mix(decode_model_distance(tex,c0+ivec2(0,1)),decode_model_distance(tex,c0+ivec2(1,1)),f.x),f.y);
    // Smoothing only matters near the contour; far fields stay bilinear.
    // Blended over 1200..1600 m so the switch leaves no contour step.
    if(abs(linear)>1600.0) return linear;
    ivec2 c=ivec2(round(p));vec2 t=p-vec2(c)+0.5;
    vec3 wx=vec3(0.5*(1.0-t.x)*(1.0-t.x),0.5+t.x*(1.0-t.x),0.5*t.x*t.x);
    vec3 wy=vec3(0.5*(1.0-t.y)*(1.0-t.y),0.5+t.y*(1.0-t.y),0.5*t.y*t.y);
    float d=0.0;
    for(int y=0;y<3;y++) {
        float row=wx.x*decode_model_distance(tex,c+ivec2(-1,y-1))+wx.y*decode_model_distance(tex,c+ivec2(0,y-1))+wx.z*decode_model_distance(tex,c+ivec2(1,y-1));
        d+=wy[y]*row;
    }
    return mix(d,linear,smoothstep(1200.0,1600.0,abs(linear)));
}
// Classification-cell fallback cannot recover a subcell coastline. Vector SDF
// takes precedence; domains never borrow or stretch the other domain's SDF.
float classified_water_distance(sampler2D tex,vec2 uv,vec2 extent) {
    vec2 dimensions=vec2(textureSize(tex,0));
    vec2 cell_position=uv*dimensions;
    vec2 cell=floor(cell_position);
    bool wet=sample_water_kind(tex,uv)>0.5;
    float closest=4096.0;
    for(int y=-1;y<=1;y++) {
        for(int x=-1;x<=1;x++) {
            vec2 neighbor=cell+vec2(float(x),float(y));
            bool other=sample_water_kind(tex,(neighbor+0.5)/dimensions)>0.5;
            if(other!=wet) {
                vec2 to_box=max(abs(cell_position-(neighbor+0.5))-0.5,vec2(0.0));
                closest=min(closest,length(to_box*extent/dimensions)*1000.0);
            }
        }
    }
    return wet ? closest : -closest;
}
float water_distance_at(vec2 p) {
    if(clipmap_enabled)return clipmap_water_distance(p);
    if(use_c2_domains) {
        vec2 w=source_domain_weights(p);
        float parent=mix(bilinear_model_distance(water_distance_tex,page_uv(p,(p-world_min)/world_size,context_water_distance_page)),bilinear_model_distance(detail_water_distance_tex,page_uv(p,(p-detail_world_min)/detail_world_size,fine_water_distance_page)),w.x);
        return material_cohort_value_1(p,vec4(mix(parent,bilinear_model_distance(water_tile_distance_tex,page_uv(p,(p-water_tile_world_min)/water_tile_world_size,local_water_distance_page)),w.y),0.0,0.0,0.0)).x;
    }
    vec2 tile_uv=(p-water_tile_world_min)/water_tile_world_size;
    if(use_water_tile_distance && inside_domain(tile_uv)) return material_cohort_value_1(p,vec4(bilinear_model_distance(water_tile_distance_tex,page_uv(p,tile_uv,local_water_distance_page)),0.0,0.0,0.0)).x;
    vec2 uv=(p-detail_world_min)/detail_world_size;
    if(use_detail_water && inside_domain(uv)) {
        if(use_detail_water_distance) return material_cohort_value_1(p,vec4(bilinear_model_distance(detail_water_distance_tex,page_uv(p,uv,fine_water_distance_page)),0.0,0.0,0.0)).x;
        return material_cohort_value_1(p,vec4(classified_water_distance(detail_water_tex,uv,detail_world_size),0.0,0.0,0.0)).x;
    }
    uv=(p-world_min)/world_size;
    if(use_water_distance) return material_cohort_value_1(p,vec4(bilinear_model_distance(water_distance_tex,page_uv(p,uv,context_water_distance_page)),0.0,0.0,0.0)).x;
    return material_cohort_value_1(p,vec4(classified_water_distance(water_tex,uv,world_size),0.0,0.0,0.0)).x;
}
float water_kind_at(vec2 p) {
    if(clipmap_enabled)return clipmap_water_kind(p);
    if(use_c2_domains) {
        if(water_distance_at(p)<=0.0) return 0.0;
        vec2 w=source_domain_weights(p);
        // The smooth SDF owns the land/water contour; the class texture only
        // tells sea (1) from inland water (2). A class texel still marked
        // land inside the SDF water is sea (no class-texture staircase).
        float kind=w.y>0.0 ? material_cohort_value_5(p,vec4(sample_water_kind(water_tile_tex,page_uv(p,(p-water_tile_world_min)/water_tile_world_size,local_associated_role_page)),0.0,0.0,0.0)).x
            : (w.x>0.0 ? material_cohort_value_5(p,vec4(sample_water_kind(detail_water_tex,page_uv(p,(p-detail_world_min)/detail_world_size,fine_associated_role_page)),0.0,0.0,0.0)).x
            : material_cohort_value_5(p,vec4(sample_water_kind(water_tex,page_uv(p,(p-world_min)/world_size,context_associated_role_page)),0.0,0.0,0.0)).x);
        return kind<0.5 ? 1.0 : kind;
    }
    vec2 tile_uv=(p-water_tile_world_min)/water_tile_world_size;
    if(use_water_tile && inside_domain(tile_uv)) return material_cohort_value_5(p,vec4(sample_water_kind(water_tile_tex,page_uv(p,tile_uv,local_associated_role_page)),0.0,0.0,0.0)).x;
    vec2 uv=(p-detail_world_min)/detail_world_size;
    if(use_detail_water && inside_domain(uv)) return material_cohort_value_5(p,vec4(sample_water_kind(detail_water_tex,page_uv(p,uv,fine_associated_role_page)),0.0,0.0,0.0)).x;
    return material_cohort_value_5(p,vec4(sample_water_kind(water_tex,page_uv(p,(p-world_min)/world_size,context_associated_role_page)),0.0,0.0,0.0)).x;
}

float terrain_height_at(vec2 p) {
    return water_kind_at(p)==1.0 ? 0.0 : model_height_at(p);
}

vec4 source_surface_weights_at(vec2 p) {
    if(clipmap_enabled)return clipmap_material(p);
    vec2 uv=(p-surface_world_min)/surface_world_size;
    vec2 fine_uv=(p-detail_world_min)/detail_world_size;
    vec4 result=use_surface_weights ? texture(surface_weights_tex,page_uv(p,uv,context_surface_weights_page)) : vec4(0.0);
    if(use_c2_domains) {
        vec2 w=source_domain_weights(p);
        return material_cohort_value_2(p,mix(mix(result,texture(detail_surface_weights_tex,page_uv(p,fine_uv,fine_surface_weights_page)),w.x),texture(local_surface_weights_tex,page_uv(p,(p-water_tile_world_min)/water_tile_world_size,local_surface_weights_page)),w.y));
    }
    if(use_detail_surface_weights && inside_domain(fine_uv)) result=texture(detail_surface_weights_tex,page_uv(p,fine_uv,fine_surface_weights_page));
    return material_cohort_value_2(p,result);
}
// Semantic fields are sampled explicitly at base level. Hardware color
// mip/filtering above is a separate render footprint, not a source-field API.
vec4 bilinear_surface_data(sampler2D tex,vec2 uv) {
    vec2 q=uv*vec2(textureSize(tex,0))-0.5;ivec2 c=ivec2(floor(q));vec2 f=fract(q);
    ivec2 last=textureSize(tex,0)-ivec2(1);
    return mix(mix(texelFetch(tex,clamp(c,ivec2(0),last),0),texelFetch(tex,clamp(c+ivec2(1,0),ivec2(0),last),0),f.x),mix(texelFetch(tex,clamp(c+ivec2(0,1),ivec2(0),last),0),texelFetch(tex,clamp(c+ivec2(1,1),ivec2(0),last),0),f.x),f.y);
}
vec4 source_surface_weights_base_at(vec2 p) {
    if(clipmap_enabled)return clipmap_material(p);
    vec2 fine_uv=(p-detail_world_min)/detail_world_size;
    vec4 result=use_surface_weights ? bilinear_surface_data(surface_weights_tex,page_uv(p,(p-surface_world_min)/surface_world_size,context_surface_weights_page)) : vec4(0.0);
    if(use_c2_domains) {
        vec2 w=source_domain_weights(p);
        return material_cohort_value_2(p,mix(mix(result,bilinear_surface_data(detail_surface_weights_tex,page_uv(p,fine_uv,fine_surface_weights_page)),w.x),bilinear_surface_data(local_surface_weights_tex,page_uv(p,(p-water_tile_world_min)/water_tile_world_size,local_surface_weights_page)),w.y));
    }
    if(use_detail_surface_weights && inside_domain(fine_uv))result=bilinear_surface_data(detail_surface_weights_tex,page_uv(p,fine_uv,fine_surface_weights_page));
    return material_cohort_value_2(p,result);
}
float source_surface_rock_at(vec2 p) {
    if(clipmap_enabled)return clipmap_material(p).g;
    if(use_c2_domains)return source_surface_weights_base_at(p).g;
    vec2 uv=(p-surface_world_min)/surface_world_size;
    vec2 fine_uv=(p-detail_world_min)/detail_world_size;
    float result=use_surface_weights ? textureLod(surface_weights_tex,page_uv(p,uv,context_surface_weights_page),0.0).g : 0.0;
    if(use_c2_domains) {
        vec2 w=source_domain_weights(p);
        return mix(mix(result,textureLod(detail_surface_weights_tex,page_uv(p,fine_uv,fine_surface_weights_page),0.0).g,w.x),textureLod(local_surface_weights_tex,page_uv(p,(p-water_tile_world_min)/water_tile_world_size,local_surface_weights_page),0.0).g,w.y);
    }
    if(use_detail_surface_weights && inside_domain(fine_uv)) result=textureLod(detail_surface_weights_tex,page_uv(p,fine_uv,fine_surface_weights_page),0.0).g;
    return result;
}
