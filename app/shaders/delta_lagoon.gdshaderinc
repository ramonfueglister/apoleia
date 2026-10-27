// Display deltas (reference near view): a sand barrier beach along the coast,
// behind it a belt of winding lagoon water with organic islands (sand rims,
// marsh green) that thins out inland. Evaluated on the land surface with the
// exact tile coast distance, so the barrier sits on the rendered coast at
// every zoom (the former draped mesh classified land by the coarse height
// tiles and put the Po barrier 8-10 km inland). The river arms are ribbons
// drawn over the land, so they cut the barrier as inlets and run through the
// islands as channels. Needs wl_noise (water_look.gdshaderinc).
uniform int delta_count=0;
// xy centre, zw unit direction towards the sea (model units, km).
uniform vec4 delta_frame[6];
// x radius along the coast, y radius inland (km), z seed.
uniform vec4 delta_shape[6];

struct DeltaMask {float barrier;float lagoon;float rim;float marsh;float shallow;};

float dl_fbm(vec2 p) {
    return wl_noise(p)*0.5+wl_noise(p*2.1+vec2(3.7,1.9))*0.3+wl_noise(p*4.3+vec2(8.1,5.3))*0.2;
}

// land_m: metres inland from the coast (0 on water); px_m: metres per pixel
// across the contour.
DeltaMask delta_mask(vec2 p,float land_m,float px_m,float view_width) {
    DeltaMask m;
    m.barrier=0.0;m.lagoon=0.0;m.rim=0.0;m.marsh=0.0;m.shallow=0.0;
    for(int i=0;i<6;i++) {
        if(i>=delta_count) break;
        vec2 sea=delta_frame[i].zw;
        vec2 tangent=vec2(-sea.y,sea.x);
        vec2 q=p-delta_frame[i].xy;
        vec2 radii=delta_shape[i].xy;
        float seed=delta_shape[i].z;
        vec2 local=vec2(dot(q,tangent)/radii.x,dot(q,-sea)/radii.y);
        // Radial fade, so the effect never ends at a hard edge.
        float region=1.0-smoothstep(0.7,1.0,length(local*vec2(0.85,1.0)));
        if(region<=0.0) continue;
        // Barrier beach: 0.55-0.85 km of sand along the coast, >= 3 px.
        float bw=max(px_m*3.0,550.0+300.0*dl_fbm(p*0.4+vec2(seed)));
        m.barrier=(1.0-smoothstep(bw-max(px_m,40.0),bw,land_m))*region;
        // Lagoon belt behind it, deepest in front of the centre. The tile
        // coast distance saturates at ~4 km, so the belt stays within 3.4 km.
        float belt_m=min(radii.y*mix(350.0,900.0,1.0-clamp(abs(local.x),0.0,1.0)),3400.0-bw);
        float behind=max(land_m-bw,0.0)/max(belt_m,100.0);
        float bias=(1.0-smoothstep(0.0,1.0,behind))*region;
        // Organic islands: domain-warped noise (features ~1-2 km); more water
        // near the barrier, single ponds inland. Fades out where islands
        // would fall below a few pixels.
        vec2 warp=vec2(dl_fbm(p*0.45+vec2(seed,1.7)),dl_fbm(p*0.45+vec2(5.2,seed)))-0.5;
        float n=dl_fbm(p*0.9+warp*2.2+vec2(seed*0.37));
        float thr=mix(0.70,0.32,bias);
        float aa=max(fwidth(n)*0.8,0.004);
        float detail=(1.0-smoothstep(350.0,800.0,view_width))*smoothstep(0.0,0.08,bias)*(1.0-m.barrier);
        m.lagoon=smoothstep(thr-aa,thr+aa,n)*detail;
        // Wet sand rim on the island side of every lagoon edge (>= ~1.5 px).
        float rim_w=max(fwidth(n)*1.6,0.025);
        m.rim=smoothstep(thr-aa-rim_w,thr-aa,n)*(1.0-smoothstep(thr-aa,thr+aa,n))*detail;
        m.shallow=1.0-smoothstep(thr+aa,thr+0.09,n);
        // Marsh: richer green on the islands and the delta plain.
        m.marsh=(bias*0.75+(1.0-smoothstep(0.5,0.95,length(local*vec2(0.8,1.0))))*0.25)*region;
        break;
    }
    return m;
}
