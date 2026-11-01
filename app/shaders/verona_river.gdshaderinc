// Fixed audited Verona reach. Local coordinates avoid large-world precision loss.
uniform bool verona_river_active = false;
uniform vec2 vr_origin;
uniform vec4 vr_bounds;
uniform vec4 vr_end_dirs;
uniform int vr_count = 0;
uniform vec4 vr_segments[64];
float vr_distance(vec2 world) {
 vec2 p=world-vr_origin;
 if (p.x<vr_bounds.x || p.y<vr_bounds.y || p.x>vr_bounds.z || p.y>vr_bounds.w) { return 10000.0; }
 if(dot(p-vr_segments[0].xy,vr_end_dirs.xy)<0.0 || dot(p-vr_segments[vr_count-1].zw,vr_end_dirs.zw)>0.0) {return 10000.0;}
 float d=10000.0;
 for(int i=0;i<64;i++) {
  if(i>=vr_count) { break; }
  vec2 a=vr_segments[i].xy; vec2 e=vr_segments[i].zw-a;
  d=min(d,length(p-a-e*clamp(dot(p-a,e)/dot(e,e),0.0,1.0)));
  // Match the mesh's miter join instead of cutting a circular hole in it.
  if(i+1<vr_count) {
   vec2 joint=vr_segments[i].zw;
   vec2 before=normalize(e);
   vec2 after=normalize(vr_segments[i+1].zw-vr_segments[i+1].xy);
   vec2 v=p-joint;
   if(dot(v,before)>0.0 && dot(v,after)<0.0) {
    float side_a=abs(before.x*v.y-before.y*v.x);
    float side_b=abs(after.x*v.y-after.y*v.x);
    d=min(d,max(side_a,side_b));
   }
  }
 }
 return d;
}
