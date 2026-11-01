// Shared bounded channel surface for terrain, banks and vegetation roots.
uniform bool verona_river_active = false;
uniform vec2 vr_origin;
uniform vec4 vr_bounds;
uniform vec4 vr_end_dirs;
uniform int vr_count = 0;
uniform vec4 vr_segments[64];
uniform vec2 vr_runs[64];
uniform sampler2D vr_profile : filter_nearest, repeat_disable;
uniform sampler2D vr_corners : filter_nearest, repeat_disable;
uniform ivec2 vr_corner_origin;
uniform ivec2 vr_corner_size;
uniform vec2 vr_world_min;
uniform float vr_level_h;
uniform sampler2D vr_grid_mask : filter_nearest, repeat_disable;
uniform ivec2 vr_grid_origin;
uniform sampler2D vr_protected : filter_nearest, repeat_disable;
uniform ivec2 vr_protected_origin;
const float VR_GRID=.025;
bool vr_is_protected(vec2 p) {
 vec2 g=(p-vr_world_min)/.25;
 // Both sides of an atlas boundary are protected; world-float rounding must
 // not lower the shared edge of a building parcel.
 ivec2 lo=ivec2(floor(g-vec2(.0012)))-vr_protected_origin;
 ivec2 hi=ivec2(floor(g+vec2(.0012)))-vr_protected_origin;
 ivec2 size=textureSize(vr_protected,0);
 for(int y=0;y<2;y++) {for(int x=0;x<2;x++) {
  ivec2 q=ivec2(x==0 ? lo.x : hi.x,y==0 ? lo.y : hi.y);
  if(all(greaterThanEqual(q,ivec2(0))) && all(lessThan(q,size)) && texelFetch(vr_protected,q,0).r>.5){return true;}
 }}
 return false;
}
float vr_ground(vec2 p) {
 vec2 g=(p-vr_world_min)/.25;ivec2 tile=ivec2(floor(g));vec2 u=fract(g);
 ivec2 q=tile-vr_corner_origin;
 if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,vr_corner_size))) {return 0.0;}
 vec4 c=texelFetch(vr_corners,q,0);float h;
 if(abs(c.x-c.z)<=abs(c.y-c.w)) {h=u.x>=u.y ? c.x+(c.y-c.x)*u.x+(c.z-c.y)*u.y : c.x+(c.w-c.x)*u.y+(c.z-c.w)*u.x;}
 else {h=u.x+u.y<=1.0 ? c.x+(c.y-c.x)*u.x+(c.w-c.x)*u.y : c.z+(c.w-c.z)*(1.0-u.x)+(c.y-c.z)*(1.0-u.y);}
 return h*vr_level_h;
}
// x signed distance, y profile station. Invalid points have distance 10000.
vec2 vr_sample(vec2 world) {
 vec2 p=world-vr_origin;
 if(vr_count==0 || p.x<vr_bounds.x || p.y<vr_bounds.y || p.x>vr_bounds.z || p.y>vr_bounds.w) {return vec2(10000.0,0.0);}
 if(dot(p-vr_segments[0].xy,vr_end_dirs.xy)<0.0 || dot(p-vr_segments[vr_count-1].zw,vr_end_dirs.zw)>0.0) {return vec2(10000.0,0.0);}
 float best=10000.0;float station=0.0;float sign_side=1.0;
 for(int i=0;i<64;i++) {
  if(i>=vr_count) {break;}
  vec2 a=vr_segments[i].xy;vec2 e=vr_segments[i].zw-a;
  float t=clamp(dot(p-a,e)/dot(e,e),0.0,1.0);
  float d=length(p-a-e*t);
  float side=(e.x*(p-a).y-e.y*(p-a).x)<0.0 ? -1.0 : 1.0;
  if(d<best) {best=d;station=mix(vr_runs[i].x,vr_runs[i].y,t);sign_side=side;}
  if(i+1<vr_count) {
   vec2 before=normalize(e);vec2 after=normalize(vr_segments[i+1].zw-vr_segments[i+1].xy);
   vec2 v=p-vr_segments[i].zw;
   if(dot(v,before)>0.0 && dot(v,after)<0.0) {
    float edge=max(abs(before.x*v.y-before.y*v.x),abs(after.x*v.y-after.y*v.x));
    if(edge<best) {best=edge;station=vr_runs[i].y;sign_side=side;}
   }
  }
 }
 return vec2(best*sign_side,station);
}
vec3 vr_values(float station) {
 int n=textureSize(vr_profile,0).x;
 int i=clamp(int(floor(station)),0,n-1);
 return mix(texelFetch(vr_profile,ivec2(i,0),0).rgb,texelFetch(vr_profile,ivec2(min(i+1,n-1),0),0).rgb,fract(station));
}
float vr_distance(vec2 p) {return abs(vr_sample(p).x);}
float vr_radius(vec2 sample_point) {
 vec3 values=vr_values(sample_point.y);
 return sample_point.x<0.0 ? values.y : values.z;
}
bool vr_inside(vec2 p) {
 if(!verona_river_active || vr_count==0) {return false;}
 vec2 local=p-vr_origin;
 ivec2 q=ivec2(floor(local/VR_GRID))-vr_grid_origin;
 if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,textureSize(vr_grid_mask,0)))) {return false;}
 if(texelFetch(vr_grid_mask,q,0).r<.5) {return false;}
 // The uploaded cell mask already defines spatial coverage; the expensive
 // nearest-profile search is only needed for heights, not terrain cutout.
 if(local.x<vr_bounds.x || local.y<vr_bounds.y || local.x>vr_bounds.z || local.y>vr_bounds.w) {return false;}
 if(dot(local-vr_segments[0].xy,vr_end_dirs.xy)<0.0 || dot(local-vr_segments[vr_count-1].zw,vr_end_dirs.zw)>0.0) {return false;}
 return !vr_is_protected(p);
}
float vr_raw_height(vec2 p,float old_height) {
 if(!verona_river_active || vr_is_protected(p)) {return old_height;}
 vec2 s=vr_sample(p);vec3 values=vr_values(s.y);
 float radius=s.x<0.0 ? values.y : values.z;
 float u=clamp((abs(s.x)-.0875)/max(radius-.0875,.001),0.0,1.0);
 float blend=u*u*(3.0-2.0*u);
 return min(old_height,mix(values.x,old_height,blend));
}

// Exactly the same centre-fan triangles as the uploaded regular shore mesh.
float vr_corrected_height(vec2 p,float old_height) {
 if(!vr_inside(p)) {return old_height;}
 vec2 cell=floor((p-vr_origin)/VR_GRID);
 vec2 base=vr_origin+cell*VR_GRID;vec2 q=(p-base)/VR_GRID;
 vec2 a;vec2 b;
 if(q.y<=q.x && q.y<=1.0-q.x){a=vec2(0,0);b=vec2(1,0);}
 else if(q.x>=q.y && q.x>=1.0-q.y){a=vec2(1,0);b=vec2(1,1);}
 else if(q.y>=q.x && q.y>=1.0-q.x){a=vec2(1,1);b=vec2(0,1);}
 else {a=vec2(0,1);b=vec2(0,0);}
 vec2 centre=vec2(.5);vec2 e=a-centre;vec2 f=b-centre;vec2 delta=q-centre;
 float det=e.x*f.y-e.y*f.x;
 float u=(delta.x*f.y-delta.y*f.x)/det;
 float v=(e.x*delta.y-e.y*delta.x)/det;
 vec2 pa=base+a*VR_GRID;vec2 pb=base+b*VR_GRID;vec2 pc=base+centre*VR_GRID;
 float ha=vr_raw_height(pa,vr_ground(pa));float hb=vr_raw_height(pb,vr_ground(pb));float hc=vr_raw_height(pc,vr_ground(pc));
 return hc+(ha-hc)*u+(hb-hc)*v;
}
