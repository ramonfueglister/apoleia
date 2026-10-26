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
uniform vec4 land_dry_color : source_color = vec4(0.76,0.66,0.43,1.0);
uniform vec4 land_sand_color : source_color = vec4(0.77,0.69,0.47,1.0);
uniform vec4 land_rock_light_color : source_color = vec4(0.80,0.73,0.66,1.0);
uniform vec4 land_rock_dark_color : source_color = vec4(0.52,0.46,0.42,1.0);
uniform vec4 land_snow_color : source_color = vec4(0.95,0.94,0.91,1.0);
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
// Micro hills: cell size (km) and slope gain.
uniform float land_micro_size=2.0;
uniform float land_micro_height=0.9;
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
// Quintic gradient noise in [0,1]; no value-noise cell plateaus.
float land_gnoise(vec2 p) {
    vec2 i=floor(p),f=fract(p);
    vec2 u=f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 ga=land_hash2(i)*2.0-1.0,gb=land_hash2(i+vec2(1,0))*2.0-1.0;
    vec2 gc=land_hash2(i+vec2(0,1))*2.0-1.0,gd=land_hash2(i+vec2(1,1))*2.0-1.0;
    float a=dot(ga,f),b=dot(gb,f-vec2(1,0)),c=dot(gc,f-vec2(0,1)),d=dot(gd,f-vec2(1,1));
    return clamp(0.5+0.85*mix(mix(a,b,u.x),mix(c,d,u.x),u.y),0.0,1.0);
}
// Footprint-filtered fbm: an octave fades to its mean once a period spans
// less than about two pixels, so nothing shimmers or speckles.
float land_fbm(vec2 p,float footprint,int octaves) {
    float n=0.0,a=0.5,w=0.0,f=1.0;
    mat2 r=mat2(vec2(0.8,0.6),vec2(-0.6,0.8));
    for(int i=0;i<4;i++) {
        if(i>=octaves) break;
        float fade=1.0-smoothstep(0.25,0.6,footprint*f);
        n+=a*mix(0.5,land_gnoise(p),fade);w+=a;
        p=r*p*2.03+vec2(3.7,1.9);f*=2.03;a*=0.5;
    }
    return n/w;
}
vec3 land_display_normal(vec3 n,float scale) {
    return normalize(vec3(n.x,n.y/max(scale,0.00001),n.z));
}

// Micro hills: a jittered field of small six-sided low-poly mounds. Each
// mound is a hexagonal pyramid (six planar faces, so every face has one
// clear lit or shaded value); gaps between mounds get contact darkening.
// Returns the world-space slope (xz) of the face and, in .z, the gap AO.
vec4 land_micro_hills(vec2 p,float size,float density,out float hill_id) {
    vec2 q=p/size;
    vec2 c=floor(q);
    float m1=9.0,m2=9.0;vec2 g1=vec2(0.0);hill_id=0.0;
    const vec2 D0=vec2(1.0,0.0),D1=vec2(0.5,0.866025),D2=vec2(-0.5,0.866025);
    for(int y=-1;y<=1;y++) {
        for(int x=-1;x<=1;x++) {
            vec2 n=c+vec2(float(x),float(y));
            vec2 hsh=land_hash2(n*1.37+vec2(11.0,3.0));
            if(land_hash(n+vec2(7.0,9.0))>density) continue;
            vec2 d=q-(n+0.2+0.6*hsh);
            float r=0.55+0.35*land_hash(n+vec2(2.0,5.0));
            float a0=dot(d,D0),a1=dot(d,D1),a2=dot(d,D2);
            float m=max(abs(a0),max(abs(a1),abs(a2)))/r;
            vec2 g=abs(a0)>=abs(a1)&&abs(a0)>=abs(a2) ? D0*sign(a0) : (abs(a1)>=abs(a2) ? D1*sign(a1) : D2*sign(a2));
            g/=r;
            if(m<m1) {m2=m1;m1=m;g1=g;hill_id=hsh.x;} else if(m<m2) m2=m;
        }
    }
    float inside=step(m1,1.0);
    float gap=1.0-smoothstep(0.0,0.18,m2-m1)*smoothstep(0.55,0.95,m1);
    float rim=smoothstep(0.75,1.05,m1);
    // Slope of h=1-m in world units (height in "size" units).
    vec2 slope_xz=-g1/size*inside;
    return vec4(slope_xz,clamp(gap*(1.0-rim*0.6)+rim*0.0,0.0,1.0)*inside,inside);
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

vec4 land_cover_at(vec2 p) {
    vec2 uv=((p-land_cover_world_min)/land_cover_spacing+0.5)/land_cover_size;
    return texture(land_cover_tex,uv);
}
// Only the selected source is sampled (?: evaluates one operand).
#define LAND_FIELDS(q) (use_land_cover ? land_cover_at(q) : LAND_LOOK_WEIGHTS(q))

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

LandLook land_look(vec2 p,float h,vec4 weights,vec3 source_normal,vec3 facet_normal,float footprint,float rel,float vw,float dhs) {
    // Cost tiers by pixel footprint (km per pixel): every detail stage is
    // skipped by branch, not just faded, once it is below pixel scale.
    LandLook o;
    float scale=dhs*max(rel,0.00001);
    vec3 smooth_n=land_display_normal(source_normal,scale);
    float slope=1.0-land_display_normal(source_normal,dhs).y;
    // Far view: the camera's relief fade or simply a large pixel footprint.
    float overview=max(1.0-smoothstep(0.7,1.0,rel),smoothstep(0.7,1.3,footprint));
    bool near=footprint<1.0;

    // Material fields: one domain-warped tap of the coarse atlas; up close
    // quantised to the fine triangle and blurred by a small ring, so no
    // texel or bilinear diamond ever shows.
    float edge=land_gnoise(p/5.5+vec2(2.2,5.1))-0.5;
    vec2 pw=p+vec2(land_gnoise(p/3.1+vec2(4.4,1.3)),land_gnoise(p/3.1+vec2(8.2,6.6)))*2.2-1.1;
    float tri_size=exp2(floor(log2(max(footprint*5.0,0.05))));
    if(footprint<0.6) pw=land_tri_centroid(pw,tri_size);
    // Fields: R forest, G bare/rock, B dry, A snow (land cover), or the
    // source material weights (FOREST/ROCK/DRY/SHORE) without it.
    vec4 soft=LAND_FIELDS(pw);
    if(footprint<0.5) {
        float r=1.8;
        soft=(soft*1.5+LAND_FIELDS(pw+vec2(r,0.0))+LAND_FIELDS(pw+vec2(-0.5*r,0.866*r))+LAND_FIELDS(pw+vec2(-0.5*r,-0.866*r)))/4.5;
    }
    float forest=smoothstep(0.42,0.58,soft.r+edge*0.30);
    float dry=smoothstep(0.55,0.85,soft.b+edge*0.25);
    // Bare land below the tree line is sand/steppe, not rock.
    float sand=use_land_cover ? smoothstep(0.35,0.65,soft.g+edge*0.2)*(1.0-smoothstep(900.0,1300.0,h)) : 0.0;

    // Neighbourhood relief from the represented height (near only).
    // Relief position (h minus its 4.5 km ring mean) is precomputed in the
    // land-cover texture: no extra height fetches here.
    float crest=use_land_cover ? (soft.a*255.0-128.0)*3.2 : 0.0;

    // Calm golden plains: two broad colour masses, no strokes or grain.
    float macro=land_fbm(p/120.0+vec2(3.1,7.7),footprint/120.0,2);
    float meso=land_fbm(p/22.0+vec2(1.9,4.2)+(macro-0.5)*2.0,footprint/22.0,2);
    vec3 grass=land_grass_color.rgb;
    grass=mix(grass,land_lime_color.rgb,smoothstep(0.45,0.70,meso)*0.7);
    grass=mix(grass,land_ochre_color.rgb,smoothstep(0.55,0.80,macro*0.6+meso*0.4)*0.6);
    grass=mix(grass,land_olive_color.rgb,smoothstep(0.50,0.66,(1.0-meso)*0.6+(1.0-macro)*0.4)*0.85);
    if(footprint<1.2) {
        float patch=land_fbm(p/6.0+vec2(5.5,2.4)+(meso-0.5)*1.4,footprint/6.0,2);
        float f=1.0-smoothstep(0.6,1.2,footprint);
        grass=mix(grass,land_ochre_color.rgb*1.05,smoothstep(0.50,0.80,patch)*0.40*f);
        grass=mix(grass,land_olive_color.rgb,smoothstep(0.50,0.22,patch)*0.45*f);
    }
    // Hill country: dark fir-green flanks on the golden ground.
    float hill_country=clamp(smoothstep(0.035,0.16,slope)*0.75+smoothstep(250.0,900.0,h)*0.35+smoothstep(20.0,160.0,crest)*0.2,0.0,1.0);
    grass=mix(grass,land_hill_color.rgb,hill_country*0.9);
    // Settleable valley floors: flat ground below its surroundings reads as
    // bright meadow, never as dark forest floor.
    float valley_floor=(1.0-smoothstep(0.015,0.05,slope))*smoothstep(30.0,140.0,-crest)*smoothstep(150.0,350.0,h);
    grass=mix(grass,mix(land_lime_color.rgb,land_grass_color.rgb,0.4),valley_floor*0.9);
    hill_country*=1.0-valley_floor;
    vec3 floor_tone=land_forest_floor_color.rgb;
    vec3 ground=mix(grass,floor_tone,forest*mix(0.55,0.9,hill_country)*(1.0-overview*0.55)*(1.0-valley_floor*0.8));
    ground=mix(ground,land_dry_color.rgb,dry*0.6*(1.0-hill_country*0.6));
    ground=mix(ground,land_sand_color.rgb,sand*0.9);
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
        ground=mix(ground,parcel,0.55*field_fade);

    }

    // Rock only on real crests and high ground; narrow ridges.
    // Atlas heights are log-compressed (H0 1900 m): the real tree line at
    // ~1900 m sits near 1320 m here. Below it slopes stay green.
    float above_trees=smoothstep(1250.0,1450.0,h);
    float ridge_zone=smoothstep(650.0,1000.0,h);
    float rock_field=max(smoothstep(45.0,170.0,crest)*ridge_zone,smoothstep(1350.0,1750.0,h));
    rock_field=max(rock_field,smoothstep(0.62,0.85,slope)*smoothstep(1100.0,1350.0,h));
    rock_field=max(rock_field,soft.g*above_trees);
    float rock=smoothstep(0.40,0.62,rock_field+edge*0.25);

    // Normals: stable facet lattice on the represented form (near only).
    vec3 n=smooth_n;
    float fid=0.5;
    if(near && rel>0.001) {
        float fv=1.0-smoothstep(0.30,0.9,footprint/land_facet_size*2.0);
        vec3 hill_facet=land_cell_facet(smooth_n,p,land_facet_size,fid);
        n=normalize(mix(smooth_n,hill_facet,land_facet_strength*mix(0.45,1.0,smoothstep(0.02,0.18,slope))*fv*rel));
        ground*=1.0+(fid-0.5)*0.10*fv*(1.0-rock);
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
    float hills_amount=smoothstep(0.1,0.5,hill_country)*(1.0-rock)*rel;
    n=normalize(mix(n,vec3(0.0,1.0,0.0),0.30*hills_amount));
    float vis=1.0-smoothstep(land_micro_size/9.0,land_micro_size/4.0,footprint);
    if(hills_amount*vis>0.001) {
        float hid;
        vec4 mh=land_micro_hills(p+vec2(31.0,17.0),land_micro_size,0.5+0.45*hills_amount,hid);
        vec2 ms=mh.xy*vis*land_micro_height*hills_amount;
        n=normalize(n+vec3(-ms.x,0.0,-ms.y));
        ground*=1.0-mh.z*vis*0.45*hills_amount;
        ground*=1.0+(hid-0.5)*0.08*mh.w*vis*hills_amount;
    }
    // Fine flat-shaded triangles (about 5 px) up close: tilt and tint.
    if(footprint<0.6) {
        float lvl=log2(max(footprint*5.0,0.05));
        float l0=floor(lvl),fr=lvl-l0;
        vec3 tri=mix(land_fine_tri(p,exp2(l0)),land_fine_tri(p,exp2(l0+1.0)),smoothstep(0.2,0.8,fr));
        float fade=1.0-smoothstep(0.35,0.6,footprint);
        n=normalize(n+vec3(tri.x,0.0,tri.y)*land_fine_tilt*(1.0-rock*0.5)*rel*fade);
        ground*=1.0+tri.z*land_fine_tint*fade;
    }

    // Rock: warm lit faces, dark brown-grey shaded faces.
    float sun_side=clamp(dot(rock_facet,normalize(vec3(-0.676,0.643,-0.360))),0.0,1.0);
    vec3 stone=mix(land_rock_dark_color.rgb,land_rock_light_color.rgb,clamp(0.15+0.85*sun_side*sun_side*rel+0.5*(1.0-rel)+0.2*(rfid-0.5),0.0,1.0));
    ground=mix(ground,stone,rock);
    ground=mix(ground,land_snow_color.rgb,smoothstep(2500.0,3000.0,h+edge*250.0)*0.85);

    // Valley occlusion with a cool tint.
    float cavity=smoothstep(0.0,240.0,-crest)*(1.0-overview);
    ground=mix(ground,ground*land_valley_tint.rgb,cavity*land_cavity_strength);

    // Crown hand-off: clipmap crowns end at view_width 2048; the forest tone
    // is complete there (crown colour x forest share), so zooming out
    // leaves no gap between drawn trees and painted forest.
    float crown_cut=smoothstep(1400.0,2048.0,vw);
    ground=mix(ground,land_forest_floor_color.rgb*0.92,clamp(soft.r,0.0,1.0)*crown_cut*(1.0-rock));
    // Weit view: the map must stay three-dimensional. Painted hillshade
    // from the atlas normal at full display exaggeration (independent of the
    // camera's relief fade), slopes keep their dark green structure, high
    // ranges read as pale grey-white rock.
    if(overview>0.0) {
        // Weit: no per-pixel facet noise; large forms only. Forest share as
        // clear dark green areas, uplands green, shading from the large atlas
        // normal plus the precomputed ridge/valley position (channel A).
        float far_forest=smoothstep(0.12,0.45,soft.r);
        ground=mix(ground,vec3(0.26,0.36,0.23),far_forest*overview*0.8*(1.0-rock));
        float upland=smoothstep(300.0,800.0,h);
        ground=mix(ground,mix(land_hill_color.rgb,land_forest_floor_color.rgb,0.3),upland*overview*0.45);
        ground*=mix(vec3(1.0),vec3(0.680,0.660,0.560),overview);
        vec3 shade_n=land_display_normal(source_normal,dhs*0.15);
        vec3 sun=normalize(vec3(-0.676,0.643,-0.360));
        float lit=dot(shade_n,sun);
        float side=clamp(dot(normalize(shade_n.xz+vec2(0.0001)),normalize(sun.xz))*length(shade_n.xz)*8.0,-1.0,1.0);
        float ridge=clamp(crest/250.0,-1.0,1.0);
        float shade=1.0+0.9*(lit-0.643)+0.18*max(ridge,0.0)*side-0.16*max(-ridge,0.0);
        ground*=mix(1.0,clamp(shade,0.62,1.3),overview);
        // High ranges: pale grey-beige rock above ~1800 m real (~1250 m
        // compressed), shaded by side; only the highest summits white.
        float alpine=smoothstep(1100.0,1350.0,h);
        vec3 belt=mix(vec3(0.60,0.56,0.47),vec3(0.88,0.87,0.84),smoothstep(1550.0,1850.0,h));
        belt*=mix(0.62,1.12,clamp(0.5+0.5*side*max(ridge,0.3)+(lit-0.643),0.0,1.0));
        ground=mix(ground,belt,alpine*overview*0.92);
    }
    o.albedo=ground;
#ifdef LAND_LOOK_DEBUG_FLOOR
    o.albedo=mix(o.albedo,vec3(1.0,0.0,1.0),valley_floor);
#endif
    o.normal=n;
    o.ao=1.0-forest*0.18-cavity*0.25;
    return o;
}
