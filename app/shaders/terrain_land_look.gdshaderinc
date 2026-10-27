// Painted low-poly land look, shared by every terrain path (fixed surface,
// clipmap). Appearance only: no height, coastline or material ownership moves.
//
// The host defines, before including this file:
//   LAND_LOOK_WEIGHTS(p)  vec4 FOREST / ROCK / DRY / SHORE weights at p
// (fallback when no land-cover texture is bound). No height fetches here.
// and calls land_look() for land fragments. Lighting stays with the engine;
// the result carries albedo, a world-space display normal and AO.

uniform vec4 land_grass_color : source_color = vec4(0.62,0.61,0.27,1.0);
uniform vec4 land_lime_color : source_color = vec4(0.72,0.69,0.31,1.0);
uniform vec4 land_olive_color : source_color = vec4(0.45,0.49,0.21,1.0);
uniform vec4 land_hill_color : source_color = vec4(0.37,0.48,0.15,1.0);
uniform vec4 land_ochre_color : source_color = vec4(0.74,0.63,0.37,1.0);
uniform vec4 land_forest_floor_color : source_color = vec4(0.33,0.40,0.18,1.0);
// Closed forest ground from land cover, all distances (crown colour).
uniform vec4 land_forest_ground_color : source_color = vec4(0.208,0.322,0.161,1.0);
// Shading-only relief exaggeration (geometry stays flat): near, mid, far.
uniform vec3 land_shade_relief=vec3(2.0,2.5,2.0);
uniform vec4 land_dry_color : source_color = vec4(0.76,0.66,0.43,1.0);
uniform vec4 land_sand_color : source_color = vec4(0.77,0.69,0.47,1.0);
uniform vec4 land_rock_light_color : source_color = vec4(0.80,0.73,0.66,1.0);
uniform vec4 land_rock_dark_color : source_color = vec4(0.52,0.46,0.42,1.0);
uniform vec4 land_snow_color : source_color = vec4(0.95,0.94,0.91,1.0);
// Weit colours (sRGB authored, linearised by source_color).
uniform vec4 land_far_forest_color : source_color = vec4(0.259,0.361,0.231,1.0);
uniform vec4 land_alp_color : source_color = vec4(0.541,0.604,0.314,1.0);
uniform vec4 land_far_rock_color : source_color = vec4(0.824,0.784,0.706,1.0);
uniform vec4 land_far_peak_color : source_color = vec4(0.933,0.922,0.894,1.0);
uniform vec4 land_far_rock_shade_color : source_color = vec4(0.478,0.455,0.502,1.0);
uniform vec4 land_far_dry_color : source_color = vec4(0.553,0.573,0.341,1.0);
uniform vec4 land_forest_stipple_dark : source_color = vec4(0.231,0.333,0.196,1.0);
uniform vec4 land_forest_stipple_light : source_color = vec4(0.420,0.541,0.271,1.0);
// Tileable RGBA noise (generated at startup by landscape_look.gd, mipmapped):
// a few fetches replace per-pixel hash noise. Features are ~8 texels.
uniform sampler2D land_noise_tex : filter_linear_mipmap, repeat_enable;
vec4 land_tnoise(vec2 p,float feature_km) {return texture(land_noise_tex,p/(feature_km*32.0));}
// Atlas height compression (r6: global h = H0*ln(1+h_real/H0)). The look
// works in real metres expressed on the H0 1900 reference curve its
// thresholds were tuned on (tree line ~1320, snow ~2000 there).
uniform float land_h0=800.0;
// Knee compression (atlas r7): real up to land_knee, land_h0 acts as H1 above.
uniform float land_knee=0.0;
// Perf A/B: constant albedo, early return (uniform branch).
uniform bool land_look_stub=false;
uniform vec4 land_valley_tint : source_color = vec4(0.62,0.70,0.72,1.0);
// Lattice size of the painted facets on hills and on rock (world units, km).
uniform float land_facet_size=2.4;
uniform float land_rock_facet_size=3.6;
uniform float land_facet_strength=0.85;
uniform float land_facet_tilt=0.10;
uniform float land_cavity_strength=0.42;
// Real land cover at the 2 km display nodes (R forest, G bare, B dry, A snow).
uniform bool use_land_cover=false;
uniform sampler2D land_cover_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 land_cover_world_min=vec2(0.0);
uniform float land_cover_spacing=2.0;
uniform vec2 land_cover_size=vec2(1.0);
uniform float land_fine_tilt=0.22;
uniform float land_fine_tint=0.13;

struct LandLook {
    vec3 albedo;
    vec3 normal;
    float ao;
};

float land_hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*vec3(0.1031,0.1030,0.0973));
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
vec2 land_hash2(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*vec3(0.1031,0.1030,0.0973));
    q+=dot(q,q.yzx+33.33);
    return fract((q.xx+q.yz)*q.zy);
}
vec3 land_display_normal(vec3 n,float scale) {
    return normalize(vec3(n.x,n.y/max(scale,0.00001),n.z));
}


// Fine flat-shaded triangles sized to ~5 px: a constant tilt and tint per
// triangle, two neighbouring power-of-two lattices crossfaded by footprint.
// Centroid of the fine triangle containing p (same lattice as land_fine_tri).
vec2 land_tri_centroid(vec2 p,float size) {
    vec2 q=p/size;
    vec2 sk=vec2(q.x+q.y*0.57735,q.y*1.1547);
    vec2 cell=floor(sk),f=fract(sk);
    vec2 cs=cell+mix(vec2(1.0/3.0),vec2(2.0/3.0),step(1.0,f.x+f.y));
    return vec2(cs.x-cs.y*0.5,cs.y*0.866025)*size;
}
vec3 land_fine_tri(vec2 p,float size) {
    vec2 q=p/size;
    vec2 sk=vec2(q.x+q.y*0.57735,q.y*1.1547);
    vec2 cell=floor(sk);vec2 f=fract(sk);
    float upper=step(1.0,f.x+f.y);
    vec2 id=cell*vec2(1.0,1.0)+vec2(upper*0.5,upper*0.25);
    vec2 t=land_hash2(id+vec2(5.3,1.7))-0.5;
    return vec3(t,land_hash(id+vec2(9.1,4.4))-0.5);
}

// bias: the far view samples calmer (blurrier) land cover.
vec4 land_cover_at(vec2 p,float bias) {
    // Quintic (smootherstep) weights through one bilinear fetch: thresholded
    // fields get round contours instead of bilinear diamond steps.
    vec2 q=(p-land_cover_world_min)/land_cover_spacing;
    vec2 i=floor(q),f=q-i;
    f=f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 uv=(i+f+0.5)/land_cover_size;
    return texture(land_cover_tex,uv,bias);
}
// Paradox-style forest mask on the land-cover grid (tools/build_forest_mask.py):
// the same mask places the groves, so the painted forest floor sits under
// them at every distance. Same quintic weights as land_cover_at.
uniform bool use_forest_mask=false;
uniform sampler2D forest_mask_tex : filter_linear_mipmap, repeat_disable;
float forest_mask_at(vec2 p,float bias) {
    vec2 q=(p-land_cover_world_min)/land_cover_spacing;
    vec2 i=floor(q),f=q-i;
    f=f*f*f*(f*(f*6.0-15.0)+10.0);
    return texture(forest_mask_tex,(i+f+0.5)/land_cover_size,bias).r;
}
// Only the selected source is sampled (?: evaluates one operand).
#define LAND_FIELDS(q) (use_land_cover ? land_cover_at(q,cover_bias) : LAND_LOOK_WEIGHTS(q))

// Cheap facets: one hash per cell of a warped triangle lattice tilts the
// represented normal by a constant amount (no height fetches).
vec3 land_cell_facet(vec3 n,vec2 p,float size,out float facet_id) {
    vec2 q=p/size;
    vec2 sk=vec2(q.x+q.y*0.57735,q.y*1.1547);
    vec2 cell=floor(sk);
    float upper=step(1.0,fract(sk.x)+fract(sk.y));
    vec2 hsh=land_hash2(cell+vec2(upper*17.0,upper*31.0));
    facet_id=hsh.x;
    vec2 tilt=hsh-0.5;
    return normalize(n+vec3(tilt.x,0.0,tilt.y)*land_facet_tilt*2.0);
}

// Hard class edge with ~1.5 px anti-aliasing (crisp painted boundaries).
float land_edge(float v,float threshold) {
    return clamp((v-threshold)/max(fwidth(v)*1.5,1e-4)+0.5,0.0,1.0);
}

LandLook land_look(vec2 p,float h,vec4 weights,vec3 source_normal,vec3 facet_normal,float footprint,float rel,float vw,float dhs) {
    // Real height, then the reference curve used by every threshold below.
    float h_real=h>0.0 ? (land_knee>0.0 ? (h<=land_knee ? h : land_knee+land_h0*(exp((h-land_knee)/land_h0)-1.0)) : land_h0*(exp(h/land_h0)-1.0)) : h;
    h=h_real>0.0 ? 1900.0*log(1.0+h_real/1900.0) : h_real;
    if(land_look_stub) {LandLook st;st.albedo=vec3(0.30,0.33,0.16);st.normal=land_display_normal(source_normal,dhs*max(rel,0.00001));st.ao=1.0;return st;}
    // Cost tiers by pixel footprint (km per pixel): every detail stage is
    // skipped by branch, not just faded, once it is below pixel scale.
    LandLook o;
    float scale=dhs*max(rel,0.00001);
    float shade_k=mix(mix(land_shade_relief.x,land_shade_relief.y,smoothstep(0.25,0.6,footprint)),land_shade_relief.z,smoothstep(0.7,1.3,footprint));
    vec3 smooth_n=land_display_normal(source_normal,scale*shade_k);
    float slope=1.0-land_display_normal(source_normal,dhs).y;
    // Far view: the camera's relief fade or simply a large pixel footprint.
    // From the smaller screen footprint: at the oblique camera the vertical
    // footprint is much larger and pulled far-view tones into mid views.
    float ofoot=max(min(length(dFdx(p)),length(dFdy(p))),0.001);
    float overview=max(1.0-smoothstep(0.7,1.0,rel),smoothstep(0.7,1.3,ofoot));
    bool near=min(footprint,max(min(length(dFdx(p)),length(dFdy(p))),0.001))<1.0;

    // Material fields: one domain-warped tap of the coarse atlas; up close
    // quantised to the fine triangle and blurred by a small ring, so no
    // texel or bilinear diamond ever shows.
    // Edge noise and warp fade out before they alias in the far view.
    float noise_fade=1.0-smoothstep(0.4,1.2,footprint);
    // Full-resolution land cover everywhere: ridge (A) and forest (R) stay crisp far out.
    float cover_bias=0.0;
    // Colour is constant per fine facet up close: sample at its centroid.
    float tri_size=exp2(floor(log2(max(footprint*5.0,0.05))));
    vec2 pc=footprint<0.6 ? land_tri_centroid(p,tri_size) : p;
    // Colour masses from the smooth position: centroid-quantised sampling
    // turned their edges into triangle staircases.
    vec4 nz=land_tnoise(p,4.5);          // R edge, G/B warp, A patch
    vec4 nm=land_tnoise(p+vec2(37.0,11.0),22.0); // R meso
    vec4 nM=land_tnoise(p+vec2(5.0,73.0),120.0); // R macro
    float edge=(nz.r-0.5)*noise_fade;
    // The warp is low-frequency (3 km): keep it at every distance, otherwise
    // the 2 km land-cover texels show as blocks once it fades out.
    // Plus a fine 300 m warp octave (from the same fetch at another scale
    // would cost a fetch; reuse the patch channel instead).
    vec2 pw=p+(nz.gb*2.0-1.0)*1.6+(vec2(nz.a,nz.r)-0.5)*0.6;
    // Fields: R forest, G bare/rock, B dry, A snow (land cover), or the
    // source material weights (FOREST/ROCK/DRY/SHORE) without it.
    vec4 soft=LAND_FIELDS(pw);
    // The groves stand at unwarped positions: read the mask at p, not pw.
    float fmask=use_forest_mask ? forest_mask_at(p,cover_bias) : soft.r;
    float forest=land_edge(soft.r+edge*0.30,0.5);
    // Dry/crop land: in mid and near views only light speckles (0.3-0.5 km)
    // within the dry zone, not continuous beige plates.
    float dry_zone=land_edge(soft.b+edge*0.25,0.7);
    float speck=land_tnoise(p+vec2(53.0,29.0),0.4).r;
    float sfade=1.0-smoothstep(0.3,0.9,max(min(length(dFdx(p)),length(dFdy(p))),0.001)/0.4*2.0);
    // Where the speckles are not resolved (mid), the dry tone is weak.
    float dry=mix(dry_zone,dry_zone*mix(0.3,land_edge(speck,0.62),sfade),1.0-overview);
    // Bare land below the tree line is sand/steppe, not rock.
    float sand=use_land_cover ? land_edge(soft.g+edge*0.2,0.5)*(1.0-smoothstep(900.0,1300.0,h)) : 0.0;

    // Neighbourhood relief from the represented height (near only).
    // Relief position (h minus its 4.5 km ring mean) is precomputed in the
    // land-cover texture: no extra height fetches here.
    float crest=use_land_cover ? (soft.a*255.0-128.0)*3.2 : 0.0;

    // Calm golden plains: two broad colour masses, no strokes or grain.
    float macro=nM.r;
    float meso=nm.r;
    vec3 grass=land_grass_color.rgb;
    float var_amt=mix(1.0,0.25,overview);
    // Mid views: bright patches half as strong and finer (patch noise, not meso).
    float midv=smoothstep(0.2,0.45,footprint)*(1.0-overview);
    grass=mix(grass,land_lime_color.rgb,smoothstep(0.45,0.70,mix(meso,nz.a,midv))*0.4*var_amt*mix(1.0,0.4,midv));
    grass=mix(grass,land_ochre_color.rgb,smoothstep(0.55,0.80,macro*0.6+meso*0.4)*0.6*var_amt*mix(0.4,1.0,overview));
    grass=mix(grass,land_olive_color.rgb,smoothstep(0.50,0.66,(1.0-meso)*0.6+(1.0-macro)*0.4)*0.85*var_amt);
    if(footprint<1.2) {
        float patch=nz.a;
        float f=1.0-smoothstep(0.6,1.2,footprint);
        grass=mix(grass,land_ochre_color.rgb*1.05,smoothstep(0.55,0.80,patch)*0.25*f);
        grass=mix(grass,land_olive_color.rgb,smoothstep(0.50,0.22,patch)*0.45*f);
    }
    // Hill country: dark fir-green flanks on the golden ground.
    float hill_country=clamp(smoothstep(0.035,0.16,slope)*0.75+smoothstep(250.0,900.0,h)*0.35+smoothstep(20.0,160.0,crest)*0.2,0.0,1.0);
    // Near hill ground a touch warmer (towards grassland), less cool green.
    // Hill ground close to meadow; the forest look comes from the forest ground.
    grass=mix(grass,mix(land_hill_color.rgb,land_olive_color.rgb,0.35*(1.0-smoothstep(0.3,0.8,footprint))),hill_country*mix(0.35,0.9,overview));
    // Settleable valley floors: flat ground below its surroundings reads as
    // bright meadow, never as dark forest floor.
    float valley_floor=land_edge((1.0-smoothstep(0.015,0.05,slope))*smoothstep(30.0,140.0,-crest)*smoothstep(150.0,350.0,h),0.5);
    grass=mix(grass,mix(land_lime_color.rgb,land_grass_color.rgb,0.4),valley_floor*0.9);
    hill_country*=1.0-valley_floor;
    vec3 floor_tone=land_forest_floor_color.rgb;
    vec3 ground=mix(grass,floor_tone,forest*mix(0.6,0.92,hill_country)*(1.0-overview*0.55)*(1.0-valley_floor*0.8));
    ground=mix(ground,land_dry_color.rgb,dry*0.6*(1.0-hill_country*0.6));
    // Fine darker grass patches (100-300 m): grass structure instead of
    // large bright plates; faded once below ~2 px.
    float gfoot_any=max(min(length(dFdx(p)),length(dFdy(p))),0.001);
    if(gfoot_any<0.12) {
        float gp=land_tnoise(p+vec2(71.0,7.0),0.2).r;
        ground*=1.0-0.09*land_edge(gp,0.62)*(1.0-smoothstep(0.05,0.12,gfoot_any))*(1.0-forest);
    }
    // Fine meadow speckles (~80 m) for the closest zooms.
    float gfoot=max(min(length(dFdx(p)),length(dFdy(p))),0.001);
    if(gfoot<0.04) {
        float g=land_tnoise(p+vec2(17.0,91.0),0.08).r;
        ground*=1.0+(land_edge(g,0.6)-0.4)*0.10*(1.0-smoothstep(0.015,0.04,gfoot));
    }
    ground=mix(ground,land_sand_color.rgb,sand*0.9);
    // Closed forest ground from the forest share, crisp edged, every distance.
    // Only where forest is really dense; ragged edges and small clearings
    // from 1-2 km noise, still crisp.
    float frayed=soft.r+(nz.a-0.5)*0.35+(nm.r-0.5)*0.15;
    float forest_ground=land_edge(smoothstep(0.50,0.85,frayed),0.5);
    // Forest mask: the floor follows the forest masses, edges frayed only a
    // little (copse spots at mask 0.42 keep plain ground).
    if(use_forest_mask) forest_ground=land_edge(fmask+(nz.a-0.5)*0.12+(nm.r-0.5)*0.05,0.5);
    // Near: crowns carry the dark, the ground only hints at the forest.
    float fg_strength=mix(mix(0.45,0.6,smoothstep(0.25,0.5,footprint)),0.85,overview);
    ground=mix(ground,land_forest_ground_color.rgb,forest_ground*fg_strength*(1.0-valley_floor));
    // Field mosaic on open plains: jittered rectangular parcels, each a
    // slightly different meadow/crop tone; parcel seams a touch lighter.
    float field_fade=(1.0-smoothstep(0.35,0.7,footprint))*(1.0-hill_country)*(1.0-forest)*(1.0-sand);
    if(field_fade>0.01) {
        // One orientation per 30 km block: a continuously varying angle bent
        // the parcels into contour-like waves.
        float ang=(land_hash(floor(p/30.0))-0.5)*1.2;
        mat2 fr=mat2(vec2(cos(ang),sin(ang)),vec2(-sin(ang),cos(ang)));
        vec2 fq=(fr*p)/vec2(2.2,1.4);
        vec2 fc=floor(fq);
        vec2 fh=land_hash2(fc+vec2(3.0,8.0));
        vec3 parcel=mix(land_lime_color.rgb,land_olive_color.rgb,step(0.55,fh.x));
        parcel=mix(parcel,land_ochre_color.rgb,step(0.78,fh.y)*smoothstep(0.2,0.6,soft.b+0.3));
        ground=mix(ground,parcel,0.06*field_fade);
        // Irregular darker grass patches (0.5-2 km) from the existing noise
        // fetch, hard-edged: meadow, not a parcel quilt.
        ground*=1.0-0.10*land_edge(nz.a*0.6+nm.r*0.4,0.62)*field_fade;

    }

    // Altitude zones in real metres (thresholds on the H0 1900 reference
    // curve: 1900 m real = 1260, 2000 = 1302, 2500 = 1597, 3000 = 1810).
    // Forest/meadow from land cover up to the tree line; alpine pasture
    // 2000-2500 m; rock only on summits (relief channel well above the ring
    // mean) from ~2500 m, and on very sharp crests from ~1350 m real.
    float alp=smoothstep(1260.0,1302.0,h)*(1.0-smoothstep(1560.0,1640.0,h));
    ground=mix(ground,land_alp_color.rgb,alp*0.85*(1.0-forest*0.5));
    float above_trees=smoothstep(1260.0,1302.0,h);
    float rock_field=smoothstep(1560.0,1640.0,h)*smoothstep(60.0,140.0,crest);
    rock_field=max(rock_field,smoothstep(200.0,280.0,crest)*smoothstep(1000.0,1060.0,h));
    rock_field=max(rock_field,smoothstep(1780.0,1840.0,h));
    // Mid zoom: the high Alps as a closed light rock massif (real > ~1900 m).
    rock_field=max(rock_field,smoothstep(1220.0,1300.0,h)*smoothstep(0.2,0.45,footprint));
    float rock=land_edge(rock_field+edge*0.25,0.5);

    // Normals: stable facet lattice on the represented form (near only).
    vec3 n=smooth_n;
    float fid=0.5;
    if(near && rel>0.001) {
        // Facets ~1.25 km near, ~3 km mid; tilt exaggerated like the shading
        // normal so flat geometry still shows lit/shaded triangles. Only on
        // slopes (of the exaggerated shading normal); plains stay calm.
        // Visibility from the smaller screen footprint: at the oblique camera
        // the vertical footprint is several times larger and hid the facets.
        float ffoot=max(min(length(dFdx(p)),length(dFdy(p))),0.001);
        float fsize=mix(0.6,3.0,smoothstep(0.2,0.6,ffoot));
        float fv=1.0-smoothstep(0.45,1.1,ffoot/fsize*2.0);
        float sslope=smoothstep(0.004,0.04,1.0-smooth_n.y);
        vec3 hill_facet=land_cell_facet(smooth_n,p,fsize,fid);
        hill_facet=normalize(vec3(hill_facet.x*shade_k,hill_facet.y,hill_facet.z*shade_k));
        n=normalize(mix(smooth_n,hill_facet,land_facet_strength*sslope*fv*rel));
        ground*=1.0+(fid-0.5)*0.40*fv*(1.0-rock)*mix(0.35,1.0,sslope);
        // No mesh-triangle normal here: clipmap parent tiles have km-sized
        // triangles, which showed as dark blocks. Facets come from the
        // stable world lattice above only.
    }
    float rfid=0.5;
    vec3 rock_facet=facet_normal;
    if(rock>0.001 && footprint<1.5) {
        rock_facet=land_cell_facet(normalize(mix(smooth_n,facet_normal,0.6)),p,land_rock_facet_size,rfid);
        n=normalize(mix(n,rock_facet,rock*rel*(1.0-smoothstep(0.6,1.5,footprint))));
    }
    // Micro hills: lighting only, in hill country, never on plains or rock.
    // Small faceted hills (~1.1 km) over hill and mountain country; the big
    // 2 km forms are flattened a little so the eye reads the small ones.
    // Small hills come from the real 0.5 km relief of the near clipmap levels.
    // Fine flat-shaded triangles (about 5 px) up close: tilt and tint.
    if(footprint<1.0) {
        // Size from the smaller screen footprint so the triangles stay about
        // equilateral on screen (no horizontal hatching at grazing angles).
        float fmin=max(min(length(dFdx(p)),length(dFdy(p))),0.001);
        float lvl=log2(max(fmin*5.0,0.05));
        float l0=floor(lvl),fr=lvl-l0;
        vec3 tri=land_fine_tri(p,exp2(l0));
        float fade=1.0-smoothstep(0.6,1.0,footprint);
        n=normalize(n+vec3(tri.x,0.0,tri.y)*land_fine_tilt*(1.0-rock*0.5)*rel*fade);
        // Calm flat ground (+-5 %), strong tone only on slopes.
        ground*=1.0+tri.z*land_fine_tint*fade*mix(0.26,1.0,smoothstep(0.05,0.10,slope));
    }

    // Rock: warm lit faces, dark brown-grey shaded faces.
    float sun_side=clamp(dot(rock_facet,normalize(vec3(-0.676,0.643,-0.360))),0.0,1.0);
    vec3 stone=mix(land_rock_dark_color.rgb,land_rock_light_color.rgb,clamp(0.15+0.85*sun_side*sun_side*rel+0.5*(1.0-rel)+0.2*(rfid-0.5),0.0,1.0));
    float mid_fp=smoothstep(0.2,0.4,footprint)*(1.0-smoothstep(1.0,1.4,footprint));
    // Strong lit/shaded facet contrast on rock (lit light grey-beige,
    // shaded clearly dark).
    stone*=mix(1.0,0.62,mid_fp*sun_side)*mix(0.72,1.08,sun_side);
    ground=mix(ground,stone,rock);
    // Snow/ice only from land cover (bare/snow) above ~3000 m real.
    ground=mix(ground,land_snow_color.rgb,land_edge(soft.g*smoothstep(1780.0,1840.0,h),0.3)*0.85);

    // Painted lift of shaded hill and forest flanks (albedo, not ambient).
    float lit_n=dot(n,normalize(vec3(-0.676,0.643,-0.360)));
    // Compress the flank contrast: lit flanks a bit darker, shaded ones lighter.
    float flank=max(hill_country,forest)*(1.0-rock)*(1.0-overview);
    ground*=mix(1.0,clamp(0.86+0.55*(1.0-clamp(lit_n,0.0,1.0)),0.86,1.3),flank);
    // Near meadow: shaded facet sides stay light (no mid-tone carpet); the
    // contrast comes from brighter sunlit sides instead.
    float meadow_near=(1.0-forest_ground)*(1.0-rock)*(1.0-smoothstep(0.3,0.6,footprint));
    // Near meadow warmer yellow-green (reference #939346).
    ground*=mix(vec3(1.0),vec3(1.38,1.12,1.0),meadow_near*(1.0-hill_country*0.5));
    float sl=clamp(lit_n,0.0,1.0);
    ground*=mix(1.0,mix(1.0+0.45*(0.6-sl),1.0+0.35*(sl-0.6),step(0.6,sl)),meadow_near);
    // Shaded sides of meadow and forest ground: cool blue-green, desaturated.
    float shade_amt=(1.0-clamp(lit_n/0.6,0.0,1.0))*(1.0-rock)*(1.0-overview);
    vec3 cool=ground*vec3(0.88,0.97,1.05);
    cool=mix(cool,vec3(dot(cool,vec3(0.3,0.59,0.11))),0.18);
    ground=mix(ground,cool,shade_amt);
    // Valley occlusion with a cool tint.
    float cavity=smoothstep(0.0,240.0,-crest)*(1.0-overview);
    ground=mix(ground,ground*land_valley_tint.rgb,cavity*land_cavity_strength);

    // Crown hand-off: clipmap crowns end at view_width 2048; the forest tone
    // is complete there (crown colour x forest share), so zooming out
    // leaves no gap between drawn trees and painted forest.
    float crown_cut=smoothstep(1400.0,2048.0,vw);
    ground=mix(ground,land_forest_floor_color.rgb*0.92,clamp(fmask,0.0,1.0)*crown_cut*(1.0-rock));
    // Weit view: the map must stay three-dimensional. Painted hillshade
    // from the atlas normal at full display exaggeration (independent of the
    // camera's relief fade), slopes keep their dark green structure, high
    // ranges read as pale grey-white rock.
    if(overview>0.0) {
        // Weit: no per-pixel facet noise; large forms only. Forest share as
        // clear dark green areas, uplands green, shading from the large atlas
        // normal plus the precomputed ridge/valley position (channel A).
        float far_forest=smoothstep(0.35,0.75,fmask)*0.9;
        float upland=smoothstep(300.0,800.0,h);
        ground=mix(ground,mix(land_hill_color.rgb,land_forest_floor_color.rgb,0.3),upland*overview*0.45);
        ground=mix(ground,land_forest_stipple_light.rgb,smoothstep(300.0,500.0,h)*(1.0-smoothstep(1000.0,1200.0,h))*overview*0.35);
        ground*=mix(vec3(1.0),vec3(1.420,1.160,1.060),overview);
        // Plain colour from real land cover: crop/dry land calm tan-olive.
        float far_dry=smoothstep(0.3,0.7,soft.b)*(1.0-upland);
        ground=mix(ground,land_far_dry_color.rgb,far_dry*overview*0.75);
        // Northern plains (Pannonia, north Balkans) a little greener.
        float north=smoothstep(-300.0,-600.0,p.y);
        ground=mix(ground,ground*vec3(0.92,1.02,0.95),north*overview*(1.0-upland));
        // Planar far slopes: the hillshade normal is quantised (posterised
        // gradient), so each flank reads as one flat lit or shaded plane.
        vec3 shade_n=land_display_normal(source_normal,dhs*0.25);
        vec2 grad=shade_n.xz/max(shade_n.y,0.2);
        grad=(floor(grad/0.06)+0.5)*0.06;
        shade_n=normalize(vec3(grad.x,1.0,grad.y));
        vec3 sun=normalize(vec3(-0.676,0.643,-0.360));
        float lit=dot(shade_n,sun);
        float side=clamp(dot(normalize(shade_n.xz+vec2(0.0001)),normalize(sun.xz))*length(shade_n.xz)*8.0,-1.0,1.0);
        float ridge=clamp(crest/250.0,-1.0,1.0);
        float alpine_zone=smoothstep(900.0,1100.0,h);
        // Ridge/valley per pixel with hard edges: sunlit crest sides brighter, valleys darker.
        float crest_on=land_edge(crest,40.0),valley_on=land_edge(-crest,40.0);
        float shade=1.0+2.4*(lit-0.643)+0.30*mix(0.5,1.0,alpine_zone)*crest_on*max(side,0.0)-0.20*crest_on*max(-side,0.0)-0.22*valley_on;
        // Dense forest darkest on shaded flanks.
        float shadow_side=clamp(0.5-side*0.5+(0.643-lit)*2.0,0.0,1.0);
        // Mountain forest stippled like painted crowns (pixel-scale noise).
        float stipple=land_tnoise(p+vec2(91.0,13.0),max(footprint*0.2,0.05)).r;
        vec3 crowns=mix(land_forest_stipple_dark.rgb,land_forest_stipple_light.rgb,land_edge(stipple,0.66-0.18*clamp(side,0.0,1.0)));
        ground=mix(ground,mix(crowns,land_far_forest_color.rgb,shadow_side*0.5),far_forest*mix(0.6,1.0,shadow_side)*overview*(1.0-rock));
        ground*=mix(1.0,clamp(shade,0.45,1.5),overview);
        // Pixel-sharp grain on far plains (+-5 %).
        ground*=1.0+(land_hash(floor(p/max(footprint,0.05)))-0.5)*0.32*overview*(1.0-upland*0.5);
        // High ranges: pale grey-beige rock above ~1800 m real (~1250 m
        // compressed), shaded by side; only the highest summits white.
        // Real ranges only: high plateaus (Meseta, Anatolia) stay land.
        // Rock massif from real land cover (bare/snow share) on high ground.
        // Real > ~1900 m (1260 on the reference curve): pale rock belt.
        float alpine=max(smoothstep(1050.0,1150.0,h),smoothstep(0.08,0.20,soft.g)*smoothstep(1000.0,1100.0,h));
        vec3 belt=mix(land_far_rock_color.rgb,land_far_peak_color.rgb,smoothstep(1720.0,1800.0,h)*max(0.5,smoothstep(0.1,0.3,soft.g)));
        belt=mix(land_far_rock_shade_color.rgb,belt,clamp(0.5+0.6*side*max(ridge,0.3)+1.5*(lit-0.643),0.0,1.0));
        ground=mix(ground,belt,alpine*overview*overview*0.92);
    }
    // Weit: only real ranges read as relief; lowland and hill country calm.
    n=normalize(mix(n,vec3(0.0,1.0,0.0),0.7*overview*(1.0-smoothstep(250.0,350.0,h))));
    o.albedo=ground;
#ifdef LAND_LOOK_DEBUG_FLOOR
    o.albedo=mix(o.albedo,vec3(1.0,0.0,1.0),valley_floor);
#endif
    o.normal=n;
    o.ao=1.0-forest*0.18-cavity*0.25;
    return o;
}
