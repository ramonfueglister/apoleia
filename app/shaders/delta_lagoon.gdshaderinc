// Display deltas (reference near view): a sand barrier beach along the coast,
// behind it a belt of winding lagoon water with organic islands (sand rims,
// marsh green) that thins out inland. Evaluated on the land surface with the
// exact tile coast distance, so the barrier sits on the rendered coast at
// every zoom (the former draped mesh classified land by the coarse height
// tiles and put the Po barrier 8-10 km inland). The river arms are ribbons
// drawn over the land, so they cut the barrier as inlets and run through the
// islands as channels. Self-contained (terrain_look and the canopy vertex
// shader, which keeps crowns out of the lagoon water).
uniform int delta_count=0;
// xy mouth on the tile coast, zw unit direction towards the sea (model
// units, km).
uniform vec4 delta_frame[6];
// x lagoon radius along the coast, y inland (km), z seed.
uniform vec4 delta_shape[6];

struct DeltaMask {float barrier;float lagoon;float rim;float marsh;float shallow;};
// Derivative-free part, shared by the fragment mask and the canopy vertex
// test. region 0: outside every delta.
struct DeltaField {float region;float barrier;float bias;float n;float thr;float radial;};

float dl_hash(vec2 p) {p=fract(p*vec2(233.34,851.73));p+=dot(p,p+23.45);return fract(p.x*p.y);}
float dl_noise(vec2 p) {
    vec2 c=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(dl_hash(c),dl_hash(c+vec2(1,0)),f.x),mix(dl_hash(c+vec2(0,1)),dl_hash(c+vec2(1)),f.x),f.y);
}
float dl_fbm(vec2 p) {
    return dl_noise(p)*0.5+dl_noise(p*2.1+vec2(3.7,1.9))*0.3+dl_noise(p*4.3+vec2(8.1,5.3))*0.2;
}

// land_m: metres inland from the coast (0 on water); px_m: metres per pixel
// across the contour.
DeltaField delta_field(vec2 p,float land_m,float px_m) {
    DeltaField f;
    f.region=0.0;f.barrier=0.0;f.bias=0.0;f.n=0.0;f.thr=1.0;f.radial=0.0;
    for(int i=0;i<6;i++) {
        if(i>=delta_count) break;
        vec2 sea=delta_frame[i].zw;
        vec2 tangent=vec2(-sea.y,sea.x);
        vec2 radii=delta_shape[i].xy;
        float seed=delta_shape[i].z;
        // Ellipse centred a little inland of the mouth.
        vec2 q=p-delta_frame[i].xy+sea*radii.y*0.55;
        vec2 local=vec2(dot(q,tangent)/radii.x,dot(q,-sea)/radii.y);
        // Radial fade, so the effect never ends at a hard edge.
        float region=1.0-smoothstep(0.7,1.0,length(local*vec2(0.85,1.0)));
        if(region<=0.0) continue;
        f.region=region;
        // The tile coast distance saturates at ~4 km; beyond ~3 km it
        // continues as the distance from the coast line through the mouth.
        float line_m=dot(delta_frame[i].xy-p,sea)*1000.0;
        float inland_m=land_m>0.0 ? mix(land_m,max(land_m,line_m),smoothstep(2800.0,3600.0,land_m)) : 0.0;
        // Barrier beach: 1.0-1.6 km of sand along the coast, >= 3 px (the
        // reference near view shows a broad spit).
        float bw=max(px_m*3.0,1000.0+600.0*dl_fbm(p*0.4+vec2(seed)));
        f.barrier=(1.0-smoothstep(bw-max(px_m,40.0),bw,land_m))*region;
        // Lagoon belt behind it, deepest in front of the centre.
        float belt_m=radii.y*mix(350.0,900.0,1.0-clamp(abs(local.x),0.0,1.0));
        float behind=max(inland_m-bw,0.0)/max(belt_m,100.0);
        f.bias=(1.0-smoothstep(0.0,1.0,behind))*region;
        // Organic islands: rounded blobs of ~2-4 km between winding channels
        // (two smooth octaves, rotated against the noise grid, domain-warped;
        // the third octave made ragged, angular edges). About half water
        // behind the barrier, single ponds inland.
        vec2 warp=vec2(dl_fbm(p*0.3+vec2(seed,1.7)),dl_fbm(p*0.3+vec2(5.2,seed)))-0.5;
        vec2 r=mat2(vec2(0.80,0.60),vec2(-0.60,0.80))*(p*0.5+warp*1.8)+vec2(seed*0.37);
        f.n=dl_noise(r)*0.68+dl_noise(mat2(vec2(0.28,-0.96),vec2(0.96,0.28))*r*2.1+vec2(4.1,2.7))*0.32;
        f.thr=mix(0.70,0.47,f.bias);
        f.radial=1.0-smoothstep(0.5,0.95,length(local*vec2(0.8,1.0)));
        break;
    }
    return f;
}

DeltaMask delta_mask(vec2 p,float land_m,float px_m,float view_width) {
    DeltaMask m;
    m.barrier=0.0;m.lagoon=0.0;m.rim=0.0;m.marsh=0.0;m.shallow=0.0;
    DeltaField f=delta_field(p,land_m,px_m);
    if(f.region<=0.0) return m;
    m.barrier=f.barrier;
    float aa=max(fwidth(f.n)*0.8,0.004);
    // Fades out where islands would fall below a few pixels.
    float detail=(1.0-smoothstep(350.0,800.0,view_width))*smoothstep(0.0,0.08,f.bias)*(1.0-f.barrier);
    m.lagoon=smoothstep(f.thr-aa,f.thr+aa,f.n)*detail;
    // Thin wet sand rim on the island side of every lagoon edge (~1 px; a
    // wider rim turned the small islands into sand).
    float rim_w=max(fwidth(f.n)*1.0,0.010);
    m.rim=smoothstep(f.thr-aa-rim_w,f.thr-aa,f.n)*(1.0-smoothstep(f.thr-aa,f.thr+aa,f.n))*detail;
    m.shallow=1.0-smoothstep(f.thr+aa,f.thr+0.09,f.n);
    // Marsh: richer green on the islands and the delta plain.
    m.marsh=(f.bias*0.85+f.radial*0.3)*f.region;
    return m;
}

// Cheap pre-test: p inside any delta region.
bool delta_inside(vec2 p) {
    for(int i=0;i<6;i++) {
        if(i>=delta_count) break;
        vec2 sea=delta_frame[i].zw;vec2 radii=delta_shape[i].xy;
        vec2 q=p-delta_frame[i].xy+sea*radii.y*0.55;
        vec2 local=vec2(dot(q,vec2(-sea.y,sea.x))/radii.x,dot(q,-sea)/radii.y);
        if(dot(local*vec2(0.85,1.0),local*vec2(0.85,1.0))<1.0) return true;
    }
    return false;
}

// Lagoon water at p (0/1, no anti-aliasing), for vertex shaders.
float delta_lagoon_at(vec2 p,float land_m,float view_width) {
    if(delta_count==0) return 0.0;
    DeltaField f=delta_field(p,land_m,1.0);
    if(f.region<=0.0) return 0.0;
    return step(f.thr,f.n)*step(0.04,f.bias)*step(f.barrier,0.5)*(1.0-step(575.0,view_width));
}
