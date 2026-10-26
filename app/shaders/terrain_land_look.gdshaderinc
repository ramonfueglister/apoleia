// Painted low-poly land look, shared by every terrain path (fixed surface,
// clipmap). Appearance only: no height, coastline or material ownership moves.
//
// The host defines, before including this file:
//   LAND_LOOK_HEIGHT(p)   represented height in metres at world xz p
//   LAND_LOOK_WEIGHTS(p)  vec4 FOREST / ROCK / DRY / SHORE weights at p
// and calls land_look() for land fragments. Lighting stays with the engine;
// the result carries albedo, a world-space display normal and AO.

uniform vec4 land_grass_color : source_color = vec4(0.62,0.61,0.27,1.0);
uniform vec4 land_lime_color : source_color = vec4(0.72,0.69,0.31,1.0);
uniform vec4 land_olive_color : source_color = vec4(0.45,0.49,0.21,1.0);
uniform vec4 land_ochre_color : source_color = vec4(0.74,0.63,0.37,1.0);
uniform vec4 land_forest_floor_color : source_color = vec4(0.33,0.40,0.18,1.0);
uniform vec4 land_dry_color : source_color = vec4(0.76,0.66,0.43,1.0);
uniform vec4 land_rock_light_color : source_color = vec4(0.80,0.73,0.66,1.0);
uniform vec4 land_rock_dark_color : source_color = vec4(0.52,0.46,0.42,1.0);
uniform vec4 land_snow_color : source_color = vec4(0.95,0.94,0.91,1.0);
uniform vec4 land_valley_tint : source_color = vec4(0.62,0.70,0.72,1.0);
// Lattice size of the painted facets on hills and on rock (world units, km).
uniform float land_facet_size=2.4;
uniform float land_rock_facet_size=3.6;
uniform float land_facet_strength=0.85;
uniform float land_facet_tilt=0.10;
// Spacing used to differentiate LAND_LOOK_HEIGHT (atlas vertex spacing).
uniform float land_normal_step=2.0;
uniform float land_cavity_strength=0.42;
uniform float land_grain_strength=1.0;

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
// Domain-warped fbm: soft, irregular, brush-like colour masses.
float land_paint(vec2 p,float footprint) {
    vec2 q=vec2(land_fbm(p+vec2(1.7,9.2),footprint,2),land_fbm(p+vec2(8.3,2.8),footprint,2))-0.5;
    return land_fbm(p+q*1.6,footprint,3);
}
vec3 land_display_normal(vec3 n,float scale) {
    return normalize(vec3(n.x,n.y/max(scale,0.00001),n.z));
}
// Three-tap gradient around a facet centroid (one facet, one normal).
vec3 land_source_normal(vec2 p,float s) {
    float a=LAND_LOOK_HEIGHT(p+vec2(-0.5*s,-0.289*s));
    float b=LAND_LOOK_HEIGHT(p+vec2(0.5*s,-0.289*s));
    float c=LAND_LOOK_HEIGHT(p+vec2(0.0,0.577*s));
    float dx=(b-a)*0.001/s;
    float dz=(c-(a+b)*0.5)*0.001/(0.866*s);
    return normalize(vec3(-dx,1.0,-dz));
}
// Stable triangle facets in world space: the represented form's normal,
// taken once at the centroid of a slightly warped triangle lattice, plus a
// small per-facet tilt. Independent of mesh LOD, so it never stripes.
vec3 land_facet_normal(vec2 p,float size,float scale,out float facet_id) {
    vec2 w=vec2(land_gnoise(p/(size*5.0)+vec2(4.1,7.3)),land_gnoise(p/(size*5.0)+vec2(9.6,1.2)))-0.5;
    vec2 q=p/size+w*0.5;
    // Skewed lattice -> near-equilateral triangles.
    vec2 s=vec2(q.x+q.y*0.57735,q.y*1.1547);
    vec2 cell=floor(s),f=fract(s);
    float upper=step(1.0,f.x+f.y);
    vec2 cs=cell+mix(vec2(1.0/3.0),vec2(2.0/3.0),upper);
    vec2 cq=vec2(cs.x-cs.y*0.5,cs.y*0.866025);
    vec2 centroid=(cq-w*0.5)*size;
    facet_id=land_hash(cell*vec2(1.0,1.0)+vec2(upper*17.0,upper*31.0));
    vec3 n=land_display_normal(land_source_normal(centroid,max(land_normal_step,size*0.5)),scale);
    vec2 tilt=land_hash2(cell+vec2(upper*5.0,upper*11.0))-0.5;
    return normalize(n+vec3(tilt.x,0.0,tilt.y)*land_facet_tilt*2.0);
}

LandLook land_look(vec2 p,float h,vec4 weights,vec3 source_normal,vec3 facet_normal,float footprint,float rel,float vw,float dhs) {
    LandLook o;
    float scale=dhs*max(rel,0.00001);
    vec3 smooth_n=land_display_normal(source_normal,scale);
    // Form at the fixed display factor decides material, not the zoom fade.
    float slope=1.0-land_display_normal(source_normal,dhs).y;
    float near=1.0-smoothstep(0.35,1.6,footprint);
    float overview=1.0-smoothstep(0.7,1.0,rel);

    // Soft material fields: a small ring blur plus a noise-displaced edge
    // removes the raster cells without moving zones.
    float edge=land_fbm(p/6.5+vec2(2.2,5.1),footprint/6.5,2)-0.5;
    vec4 soft=weights;
    if(footprint<4.0) {
        float r=2.2;
        soft=(weights*1.5+LAND_LOOK_WEIGHTS(p+vec2(r,0.0))+LAND_LOOK_WEIGHTS(p+vec2(-0.5*r,0.866*r))+LAND_LOOK_WEIGHTS(p+vec2(-0.5*r,-0.866*r)))/4.5;
    }
    float forest=smoothstep(0.30,0.80,soft.r+edge*0.40);
    float dry=smoothstep(0.15,0.85,soft.b+edge*0.35);

    // Painted meadow: three scales of warped colour masses.
    float macro=land_fbm(p/140.0+vec2(3.1,7.7),footprint/140.0,3);
    float meso=land_paint(p/26.0+vec2(1.9,4.2),footprint/26.0);
    float micro=land_fbm(p/4.2+vec2(6.3,0.7),footprint/4.2,2);
    vec3 grass=land_grass_color.rgb;
    grass=mix(grass,land_olive_color.rgb,smoothstep(0.42,0.70,1.0-macro)*0.55);
    grass=mix(grass,land_lime_color.rgb,smoothstep(0.46,0.70,meso*0.6+micro*0.4)*0.8);
    grass=mix(grass,land_olive_color.rgb,smoothstep(0.52,0.74,(1.0-meso)*0.5+(1.0-micro)*0.5)*0.6);
    grass=mix(grass,land_ochre_color.rgb,smoothstep(0.56,0.80,macro*0.45+meso*0.3+micro*0.25)*0.7);
    // Small painted patches: light dry tufts and darker olive meadow.
    float patch=land_fbm(p/7.0+vec2(5.5,2.4)+(meso-0.5)*1.4,footprint/7.0,2);
    float patch_fade=1.0-smoothstep(0.6,1.6,footprint);
    grass=mix(grass,land_lime_color.rgb*1.06,smoothstep(0.58,0.72,patch)*0.55*patch_fade);
    grass=mix(grass,land_olive_color.rgb,smoothstep(0.42,0.30,patch)*0.45*patch_fade);
    // Far views keep only the broad masses.
    grass=mix(grass,mix(land_grass_color.rgb,land_olive_color.rgb,0.25),overview*0.35);

    // Forest floor: darker olive under groves, broad and soft.
    float hilly=smoothstep(150.0,700.0,h);
    // Closed, dark forest floor under the crowns; lighter in the plains.
    vec3 floor_tone=land_forest_floor_color.rgb*mix(1.08,0.92,micro);
    vec3 ground=mix(grass,floor_tone,forest*mix(0.62,0.88,hilly)*(1.0-overview*0.55));
    ground=mix(ground,land_dry_color.rgb*mix(0.92,1.06,micro),dry*0.9);

    // Brush grain: short directed strokes, only while they are resolved.
    float stroke_fade=1.0-smoothstep(0.2,0.55,footprint);
    if(stroke_fade>0.0) {
        float ang=meso*6.0+0.6;
        mat2 rot=mat2(vec2(cos(ang),sin(ang)),vec2(-sin(ang),cos(ang)));
        vec2 sp=rot*p;
        float stroke=land_gnoise(vec2(sp.x/2.4,sp.y/0.55));
        float grain=land_gnoise(p/0.9+vec2(2.0,3.0));
        ground*=1.0+((stroke-0.5)*0.20+(grain-0.5)*0.10)*stroke_fade*land_grain_strength*(1.0-forest*0.5);
    }
    // Medium-scale tonal mottling that stays visible further out.
    ground*=1.0+(micro-0.5)*0.16*(1.0-overview*0.7);

    // Neighbourhood relief: valleys vs. crests from the represented height.
    float around=h,around_far=h;
    if(footprint<3.5) {
        // One three-tap ring between hollow and valley scale.
        float r=4.5;
        around=(LAND_LOOK_HEIGHT(p+vec2(r,0))+LAND_LOOK_HEIGHT(p+vec2(-0.5*r,0.866*r))+LAND_LOOK_HEIGHT(p+vec2(-0.5*r,-0.866*r)))/3.0;
        around_far=around;
    }
    float crest=(h-around)*0.6+(h-around_far)*0.4;

    // Rock: crests, steep high flanks, high ground; soft noisy boundary.
    float rock_field=max(max(smoothstep(30.0,190.0,crest)*smoothstep(450.0,900.0,h),smoothstep(0.55,0.85,slope)*smoothstep(800.0,1400.0,h)),smoothstep(1800.0,2700.0,h));
    rock_field=max(rock_field,soft.g*smoothstep(600.0,1200.0,h));
    float rock=smoothstep(0.40,0.62,rock_field+edge*0.22);

    // Facets: stable lattice normals on hills, larger planes on rock.
    float facet_visible=1.0-smoothstep(0.30,0.9,footprint/land_facet_size*2.0);
    float fid=0.5;
    vec3 hill_facet=smooth_n;
    if(facet_visible>0.0 && rel>0.001) hill_facet=land_facet_normal(p,land_facet_size,scale,fid);
    float rfid=0.5;
    vec3 rock_facet=facet_normal;
    if(rock>0.001) {
        rock_facet=normalize(mix(land_facet_normal(p,land_rock_facet_size,scale,rfid),facet_normal,0.6));
    }
    float hill_amount=land_facet_strength*mix(0.45,1.0,smoothstep(0.02,0.18,slope))*facet_visible*rel;
    vec3 n=normalize(mix(smooth_n,hill_facet,hill_amount));
    n=normalize(mix(n,rock_facet,rock*rel*(1.0-smoothstep(0.6,2.0,footprint))));
    // Per-facet tone, as a painter would vary each plane slightly.
    ground*=1.0+(fid-0.5)*0.15*facet_visible*(1.0-rock);

    // Clear lit and shaded pyramid sides (sun from WSW), as in the reference.
    float sun_side=clamp(dot(rock_facet,normalize(vec3(-0.68,0.64,0.36))),0.0,1.0);
    vec3 stone=mix(land_rock_dark_color.rgb,land_rock_light_color.rgb,clamp(0.25+0.75*sun_side*sun_side*rel+0.5*(1.0-rel)+0.25*(rfid-0.5),0.0,1.0));
    ground=mix(ground,stone,rock);
    ground=mix(ground,land_snow_color.rgb,smoothstep(3200.0,4200.0,h+edge*300.0)*0.9);

    // Soft valley occlusion with a cool tint; crests catch a little light.
    float cavity=smoothstep(0.0,240.0,-crest)*(1.0-overview);
    float ridge_light=smoothstep(0.0,260.0,crest)*(1.0-rock)*(1.0-overview);
    ground=mix(ground,ground*land_valley_tint.rgb,cavity*land_cavity_strength);
    ground*=1.0+ridge_light*0.06;

    // Overview: forests read as broad deeper green zones, open land greener
    // and a touch darker, as on the reference map.
    float far_forest=smoothstep(0.1,0.95,soft.r);
    ground=mix(ground,mix(ground,vec3(dot(ground,vec3(0.3,0.59,0.11))),0.10)*vec3(0.98,1.02,1.08),overview);
    ground=mix(ground,land_forest_floor_color.rgb*vec3(0.80,1.0,0.95),far_forest*overview*0.45*(1.0-rock));
    // High mountains stay bright, rose-white peaks in the map view.
    ground=mix(ground,mix(land_rock_light_color.rgb,land_snow_color.rgb,0.55),smoothstep(1700.0,2900.0,h)*overview*0.8);
    // Overview: relief survives as a soft painted hillshade, zones stay calm.
    float carto=clamp(dot(source_normal,normalize(vec3(-0.45,0.78,0.4))),0.0,1.0);
    vec3 relief_n=land_display_normal(source_normal,dhs*0.35);
    float shade=clamp(dot(relief_n,normalize(vec3(-0.62,0.62,0.48))),0.0,1.0);
    ground*=mix(1.0,0.70+shade*0.42,overview*0.55);
    ground*=mix(1.0,0.86+carto*0.2,overview*0.3);

    o.albedo=ground;
    o.normal=n;
    o.ao=1.0-forest*0.18-cavity*0.25;
    return o;
}
