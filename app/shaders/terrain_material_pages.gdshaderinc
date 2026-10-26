// Display-only material cohort. Canonical source/veto and layout records are unchanged.
uniform bool material_cohort=false;
uniform float material_alpha0=1.0;
uniform float material_alpha1=1.0;
uniform float material_progress=1.0;
uniform vec4 material_edges[4];
uniform vec4 material_edge_pairs[4];
uniform vec4 material_edge_bands=vec4(0.0);
uniform vec4 material_corners[4];
uniform vec4 material_corner_pairs[4];
uniform vec2 canonical_grid_spacing=vec2(2.0);
uniform sampler2DArray parent_context_height_tex : filter_nearest, repeat_disable;
uniform vec4 parent_context_height_rect[17];
uniform vec2 parent_context_height_size[17];
uniform sampler2DArray parent_fine_height_tex : filter_nearest, repeat_disable;
uniform vec4 parent_fine_height_rect[17];
uniform vec2 parent_fine_height_size[17];
uniform sampler2DArray parent_context_water_distance_tex : filter_nearest, repeat_disable;
uniform vec4 parent_context_water_distance_rect[17];
uniform vec2 parent_context_water_distance_size[17];
uniform sampler2DArray parent_fine_water_distance_tex : filter_nearest, repeat_disable;
uniform vec4 parent_fine_water_distance_rect[17];
uniform vec2 parent_fine_water_distance_size[17];
uniform sampler2DArray parent_local_water_distance_tex : filter_nearest, repeat_disable;
uniform vec4 parent_local_water_distance_rect[17];
uniform vec2 parent_local_water_distance_size[17];
uniform sampler2DArray parent_context_surface_weights_tex : filter_nearest, repeat_disable;
uniform vec4 parent_context_surface_weights_rect[17];
uniform vec2 parent_context_surface_weights_size[17];
uniform sampler2DArray parent_fine_surface_weights_tex : filter_nearest, repeat_disable;
uniform vec4 parent_fine_surface_weights_rect[17];
uniform vec2 parent_fine_surface_weights_size[17];
uniform sampler2DArray parent_local_surface_weights_tex : filter_nearest, repeat_disable;
uniform vec4 parent_local_surface_weights_rect[17];
uniform vec2 parent_local_surface_weights_size[17];
uniform sampler2DArray parent_coast_distance_tex : filter_nearest, repeat_disable;
uniform vec4 parent_coast_distance_rect[17];
uniform vec2 parent_coast_distance_size[17];
uniform sampler2DArray parent_fixed_atlas_tex : filter_nearest, repeat_disable;
uniform vec4 parent_fixed_atlas_rect[17];
uniform vec2 parent_fixed_atlas_size[17];

vec4 cohort_fetch(sampler2DArray tex,ivec2 cell,vec2 size,int layer){return texelFetch(tex,ivec3(clamp(cell,ivec2(0),ivec2(size)-ivec2(1)),layer),0);}
vec4 cohort_linear(sampler2DArray tex,vec2 p,vec4 rect,vec2 size,int layer){
    vec2 q=(p-rect.xy)/rect.zw*size-0.5;ivec2 c=ivec2(floor(q));vec2 f=fract(q);
    return mix(mix(cohort_fetch(tex,c,size,layer),cohort_fetch(tex,c+ivec2(1,0),size,layer),f.x),mix(cohort_fetch(tex,c+ivec2(0,1),size,layer),cohort_fetch(tex,c+ivec2(1),size,layer),f.x),f.y);
}
float cohort_code(vec4 value){return round(value.r*255.0)*256.0+round(value.g*255.0);}
float cohort_encoded(sampler2DArray tex,vec2 p,vec4 rect,vec2 size,int layer,float scale,float offset,bool vertex_grid){
    vec2 q=(p-rect.xy)/rect.zw*(vertex_grid?size-vec2(1.0):size)-(vertex_grid?vec2(0.0):vec2(0.5));
    if(vertex_grid)q=clamp(q,vec2(0.0),size-vec2(1.0));
    ivec2 c=ivec2(floor(q));if(vertex_grid)c=min(c,ivec2(size)-ivec2(2));vec2 f=q-vec2(c);
    float a=cohort_code(cohort_fetch(tex,c,size,layer))*scale+offset;
    float b=cohort_code(cohort_fetch(tex,c+ivec2(1,0),size,layer))*scale+offset;
    float d=cohort_code(cohort_fetch(tex,c+ivec2(1),size,layer))*scale+offset;
    float e=cohort_code(cohort_fetch(tex,c+ivec2(0,1),size,layer))*scale+offset;
    if(vertex_grid)return f.x+f.y<1.0?a+(b-a)*f.x+(e-a)*f.y:d+(e-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
    return mix(mix(a,b,f.x),mix(e,d,f.x),f.y);
}
float cohort_role(sampler2DArray tex,vec2 p,vec4 rect,vec2 size,int layer){
    ivec2 c=ivec2(floor((p-rect.xy)/rect.zw*size));return round(cohort_fetch(tex,c,size,layer).b*255.0);
}

float cohort_edge_weight(vec2 p,int i){
    vec4 edge=material_edges[i];float band=material_edge_bands[i];if(band<=0.0)return 0.0;
    float normal=edge.x<0.5?p.x:p.y;float along=edge.x<0.5?p.y:p.x;
    if(along<edge.z || along>edge.w)return 0.0;
    return c2_smoother(1.0-abs(normal-edge.y)/band);
}
// Capacity: host parent + 4 edges*2 endpoints + 4 corners*2 = 17. Host child is slot -1.
// Runtime loop bound prevents driver inlining all edge/parent combinations per tap.
uniform int material_layer_count=17;
struct CohortWeights { mat4 first; vec2 last; int role_layer; };
float cohort_weight(CohortWeights w,int slot){return slot<16?w.first[slot/4][slot%4]:w.last[slot-16];}
CohortWeights cohort_add(CohortWeights w,int layer,float amount){
    int slot=layer+1;
    if(slot<16)w.first[slot/4][slot%4]+=amount;else w.last[slot-16]+=amount;
    return w;
}
CohortWeights cohort_add_pair(CohortWeights w,vec4 pair,float amount){
    float a=clamp(pair.z+(pair.w-pair.z)*material_progress,0.0,1.0);
    w=cohort_add(w,int(pair.x),amount*(1.0-a));
    return cohort_add(w,int(pair.y),amount*a);
}
int cohort_pair_role(vec4 pair){
    float a=pair.z+(pair.w-pair.z)*material_progress;
    return int(a<1.0?pair.x:pair.y);
}
CohortWeights cohort_weights(vec2 p){
    CohortWeights w;w.first=mat4(0.0);w.last=vec2(0.0);w.role_layer=-1;
    vec4 base=vec4(0.0,-1.0,material_alpha0,material_alpha1);
    int ix=-1;int iz=-1;float wx=0.0;float wz=0.0;
    for(int i=0;i<4;i++){
        float v=cohort_edge_weight(p,i);
        if(material_edges[i].x<0.5){if(v>wx){wx=v;ix=i;}}
        else if(v>wz){wz=v;iz=i;}
    }
    vec4 ex=ix>=0?material_edge_pairs[ix]:base;
    vec4 ez=iz>=0?material_edge_pairs[iz]:base;
    vec4 corner=base;
    if(ix>=0 && iz>=0){
        vec2 location=vec2(material_edges[ix].y,material_edges[iz].y);
        for(int i=0;i<4;i++)if(all(equal(location,material_corners[i].xy)))corner=material_corner_pairs[i];
    }
    w=cohort_add_pair(w,base,(1.0-wx)*(1.0-wz));
    w=cohort_add_pair(w,ex,wx*(1.0-wz));
    w=cohort_add_pair(w,ez,(1.0-wx)*wz);
    w=cohort_add_pair(w,corner,wx*wz);
    // Categorical role uses the common corner at an actual two-edge intersection.
    w.role_layer=cohort_pair_role(wx>0.0 && wz>0.0?corner:wx>0.0?ex:wz>0.0?ez:base);
    return w;
}
vec4 cohort_raw_0(int layer,vec2 p,vec4 child){
    if(layer<0)return child;
    vec2 w=source_domain_weights(p);
    return vec4(mix(cohort_encoded(parent_context_height_tex,p,parent_context_height_rect[layer],parent_context_height_size[layer],layer,0.25,-8192.0,false),cohort_encoded(parent_fine_height_tex,p,parent_fine_height_rect[layer],parent_fine_height_size[layer],layer,0.25,-8192.0,false),w.x),0.0,0.0,0.0);
}
vec4 material_cohort_value_0(vec2 p,vec4 child){
    if(!material_cohort)return child;
    CohortWeights w=cohort_weights(p);
    vec4 value=child*cohort_weight(w,0);
    for(int layer=0;layer<material_layer_count;layer++){
        float weight=cohort_weight(w,layer+1);
        if(weight>0.0)value+=cohort_raw_0(layer,p,child)*weight;
    }
    return value;
}
vec4 cohort_raw_1(int layer,vec2 p,vec4 child){
    if(layer<0)return child;
    vec2 w=source_domain_weights(p);
    return vec4(mix(mix(cohort_encoded(parent_context_water_distance_tex,p,parent_context_water_distance_rect[layer],parent_context_water_distance_size[layer],layer,0.125,-4096.0,false),cohort_encoded(parent_fine_water_distance_tex,p,parent_fine_water_distance_rect[layer],parent_fine_water_distance_size[layer],layer,0.125,-4096.0,false),w.x),cohort_encoded(parent_local_water_distance_tex,p,parent_local_water_distance_rect[layer],parent_local_water_distance_size[layer],layer,0.125,-4096.0,false),w.y),0.0,0.0,0.0);
}
vec4 material_cohort_value_1(vec2 p,vec4 child){
    if(!material_cohort)return child;
    CohortWeights w=cohort_weights(p);
    vec4 value=child*cohort_weight(w,0);
    for(int layer=0;layer<material_layer_count;layer++){
        float weight=cohort_weight(w,layer+1);
        if(weight>0.0)value+=cohort_raw_1(layer,p,child)*weight;
    }
    return value;
}
vec4 cohort_raw_2(int layer,vec2 p,vec4 child){
    if(layer<0)return child;
    vec2 w=source_domain_weights(p);
    return mix(mix(cohort_linear(parent_context_surface_weights_tex,p,parent_context_surface_weights_rect[layer],parent_context_surface_weights_size[layer],layer),cohort_linear(parent_fine_surface_weights_tex,p,parent_fine_surface_weights_rect[layer],parent_fine_surface_weights_size[layer],layer),w.x),cohort_linear(parent_local_surface_weights_tex,p,parent_local_surface_weights_rect[layer],parent_local_surface_weights_size[layer],layer),w.y);
}
vec4 material_cohort_value_2(vec2 p,vec4 child){
    if(!material_cohort)return child;
    CohortWeights w=cohort_weights(p);
    vec4 value=child*cohort_weight(w,0);
    for(int layer=0;layer<material_layer_count;layer++){
        float weight=cohort_weight(w,layer+1);
        if(weight>0.0)value+=cohort_raw_2(layer,p,child)*weight;
    }
    return value;
}
vec4 cohort_raw_3(int layer,vec2 p,vec4 child){
    if(layer<0)return child;
    vec2 w=source_domain_weights(p);
    return vec4(cohort_encoded(parent_fixed_atlas_tex,p,parent_fixed_atlas_rect[layer],parent_fixed_atlas_size[layer],layer,0.25,-8192.0,true),0.0,0.0,0.0);
}
vec4 material_cohort_value_3(vec2 p,vec4 child){
    if(!material_cohort)return child;
    CohortWeights w=cohort_weights(p);
    vec4 value=child*cohort_weight(w,0);
    for(int layer=0;layer<material_layer_count;layer++){
        float weight=cohort_weight(w,layer+1);
        if(weight>0.0)value+=cohort_raw_3(layer,p,child)*weight;
    }
    return value;
}
vec4 cohort_raw_4(int layer,vec2 p,vec4 child){
    if(layer<0)return child;
    vec2 w=source_domain_weights(p);
    return vec4(cohort_encoded(parent_coast_distance_tex,p,parent_coast_distance_rect[layer],parent_coast_distance_size[layer],layer,2.0,0.0,false),0.0,0.0,0.0);
}
vec4 material_cohort_value_4(vec2 p,vec4 child){
    if(!material_cohort)return child;
    CohortWeights w=cohort_weights(p);
    vec4 value=child*cohort_weight(w,0);
    for(int layer=0;layer<material_layer_count;layer++){
        float weight=cohort_weight(w,layer+1);
        if(weight>0.0)value+=cohort_raw_4(layer,p,child)*weight;
    }
    return value;
}
vec4 cohort_raw_5(int layer,vec2 p,vec4 child){
    if(layer<0)return child;
    vec2 w=source_domain_weights(p);
    return vec4(w.y>0.0?cohort_role(parent_local_water_distance_tex,p,parent_local_water_distance_rect[layer],parent_local_water_distance_size[layer],layer):w.x>0.0?cohort_role(parent_fine_water_distance_tex,p,parent_fine_water_distance_rect[layer],parent_fine_water_distance_size[layer],layer):cohort_role(parent_context_water_distance_tex,p,parent_context_water_distance_rect[layer],parent_context_water_distance_size[layer],layer),0.0,0.0,0.0);
}
vec4 material_cohort_value_5(vec2 p,vec4 child){
    if(!material_cohort)return child;
    CohortWeights w=cohort_weights(p);
    return cohort_raw_5(w.role_layer,p,child);
}
