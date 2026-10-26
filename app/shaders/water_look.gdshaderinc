// Shared stylised water optics for sea (water.gdshader), lakes
// (terrain_look.gdshader) and rivers (rivers.gdshader). Units: model km,
// depths and coast distances in metres.
//
// Weather hooks (declared in project.godot [shader_globals], neutral
// defaults): wind direction/strength, storm, cloud shadow mask, lightning.
global uniform vec2 weather_wind_dir;
global uniform float weather_wind_strength;
global uniform float weather_storm;
global uniform sampler2D weather_cloud_shadow;
global uniform vec4 weather_cloud_shadow_rect;
global uniform float weather_lightning;

uniform vec4 water_deep_tint : source_color = vec4(0.07,0.25,0.47,1.0);
uniform vec4 water_open_tint : source_color = vec4(0.11,0.35,0.60,1.0);
uniform vec4 water_shallow_tint : source_color = vec4(0.20,0.60,0.66,1.0);
uniform vec4 water_seabed_tint : source_color = vec4(0.62,0.66,0.52,1.0);
uniform vec4 water_foam_tint : source_color = vec4(0.94,0.97,0.96,1.0);
uniform vec4 water_sky_zenith : source_color = vec4(0.36,0.58,0.82,1.0);
uniform vec4 water_sky_horizon : source_color = vec4(0.78,0.88,0.94,1.0);
uniform vec4 water_sun_tint : source_color = vec4(1.0,0.93,0.78,1.0);
// Direction towards the light, world space (set from the sun each frame).
uniform vec3 water_sun_dir=vec3(-0.68,0.64,0.36);
uniform float water_facet_size=1.4;
uniform float water_glitter=1.0;

float wl_hash(vec2 p) {p=fract(p*vec2(233.34,851.73));p+=dot(p,p+23.45);return fract(p.x*p.y);}
float wl_noise(vec2 p) {
    vec2 c=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(wl_hash(c),wl_hash(c+vec2(1,0)),f.x),mix(wl_hash(c+vec2(0,1)),wl_hash(c+vec2(1)),f.x),f.y);
}
// Value noise faded to its mean once a cell is below pixel size.
float wl_fnoise(vec2 p,float px) {return mix(wl_noise(p),0.5,smoothstep(0.25,0.75,px));}

vec2 wl_wind() {
    float l=length(weather_wind_dir);
    return l>0.001 ? weather_wind_dir/l : vec2(0.7071,-0.7071);
}
float wl_wind_strength() {return clamp(weather_wind_strength,0.0,1.0);}

// Stylised wave height: a directional swell plus scrolled detail octaves.
// p in model km.
float wl_wave(vec2 p,float footprint,float t,vec2 flow) {
    vec2 w=wl_wind();
    // Wave height: global weather only slightly; the front's local storm
    // (darker water, whitecaps, no glints) is applied in water_shade.
    float storm=clamp(weather_storm,0.0,1.0)*0.3;
    float strength=0.6+0.8*wl_wind_strength()+0.8*storm;
    float along=dot(p,w);
    float swell=sin(along*0.55-t*0.9+wl_noise(p*0.08)*6.0)*0.5+0.5;
    swell=mix(swell,0.5,smoothstep(0.3,1.0,footprint*0.55/6.2832));
    vec2 drift=w*t*0.35+flow*t;
    float d1=wl_fnoise(p*0.45-drift*0.45,footprint*0.45);
    float d2=wl_fnoise(p*1.25-drift*1.1+vec2(5.2,1.3),footprint*1.25);
    float d3=wl_fnoise(p*3.1-drift*2.4+vec2(2.7,8.4),footprint*3.1);
    return (swell*0.40+d1*0.32+d2*0.18+d3*0.10)*strength;
}
vec3 wl_normal(vec2 p,float footprint,float t,vec2 flow,float amount) {
    float e=0.12;
    float h0=wl_wave(p,footprint,t,flow);
    float hx=wl_wave(p+vec2(e,0.0),footprint,t,flow);
    float hz=wl_wave(p+vec2(0.0,e),footprint,t,flow);
    return normalize(vec3(-(hx-h0)/e*0.22*amount,1.0,-(hz-h0)/e*0.22*amount));
}
// Triangle lattice: centroid of the low-poly facet containing p (model km).
vec2 wl_facet_center(vec2 p,float size,out float facet_id) {
    vec2 q=vec2(p.x-p.y*0.57735,p.y*1.1547)/size;
    vec2 c=floor(q);vec2 f=fract(q);
    bool upper=f.x+f.y>1.0;
    vec2 centroid_q=c+(upper ? vec2(2.0/3.0) : vec2(1.0/3.0));
    facet_id=wl_hash(c*1.37+(upper ? vec2(0.5,0.25) : vec2(0.0)));
    vec2 centroid=vec2(centroid_q.x+centroid_q.y*0.5,centroid_q.y*0.866025)*size;
    return centroid;
}

struct WaterSample {vec3 albedo;vec3 emission;vec3 normal;float roughness;float foam;};

// coast_m: distance to the shore (m, >=0 in water). depth: water depth (m).
// view_world: unit vector from surface towards the camera. calm: 0 far map
// (static, cartographic) .. 1 close views (fully animated).
// mouth: 0..1 inside a river mouth radius (no surf, sediment-shallow plume).
WaterSample water_shade(vec2 p,float coast_m,float depth,float footprint,float calm,vec3 view_world,vec2 flow,float px_m,float saum_scale,float mouth) {
    WaterSample s;
    float t=TIME;
    // Cloud shadow mask (1 = full sun), only inside weather_cloud_shadow_rect.
    float sun_mask=1.0;float cloud_density=0.0;
    if(weather_cloud_shadow_rect.z>0.0) {
        vec2 uv=(p-weather_cloud_shadow_rect.xy)/weather_cloud_shadow_rect.zw;
        if(all(greaterThanEqual(uv,vec2(0.0))) && all(lessThanEqual(uv,vec2(1.0)))) {sun_mask=texture(weather_cloud_shadow,uv).r;cloud_density=1.0-sun_mask;}
    }
    // Storm acts locally under the front's clouds, not over the whole sea.
    float storm=clamp(weather_storm,0.0,1.0)*cloud_density;
    float anim=calm*(1.0-smoothstep(0.35,1.1,footprint));
    // Effective depth: bathymetry is coarse, so the shore distance also
    // bounds it; gives a continuous shelf towards every coast.
    // Narrow, patchy saum: a noise term breaks the uniform halo and lets
    // sand show through in the shallowest patches.
    float patch=wl_fnoise(p*0.55,footprint*0.55)*0.6+wl_fnoise(p*1.7+vec2(3.3,1.1),footprint*1.7)*0.4;
    // Turquoise is bound to the shore distance only (a narrow band of a few
    // km), never to the shelf depth: shallow seas like the Adriatic stay deep
    // blue up to the coast. eff is a pseudo-depth for the colour ramp.
    // saum_scale 1 close .. ~0.15 continental: the band shrinks to a hairline
    // of about one pixel instead of growing with the pixel footprint.
    float far_view=clamp((1.0-saum_scale)/0.85,0.0,1.0);
    // Width in metres (~2.5 km, patchy): broad gradient in the close view,
    // a few pixels in the regional view, a hairline far out.
    // Close view: broad soft turquoise -> teal -> blue (~6 km, patchy).
    // Clipmap water distance is encoded to +-4096 m and saturates beyond:
    // keep the gradient inside ~3.3 km and treat saturated texels as open sea.
    float saum_w=mix(max(3800.0*(0.7+0.4*patch),px_m*1.5),px_m*1.2,far_view);
    float eff=2.0+90.0*pow(smoothstep(0.0,saum_w,coast_m),0.85)+coast_m*0.002;
    eff=coast_m>3900.0 ? 200.0 : eff;
    eff=mix(eff,min(eff,12.0+coast_m*0.004),mouth*0.75);
    // Beer-Lambert style absorption: seabed -> turquoise -> blue -> navy.
    vec3 col=mix(water_seabed_tint.rgb,water_shallow_tint.rgb,1.0-exp(-eff/5.0));
    col=mix(col,water_open_tint.rgb,smoothstep(6.0,85.0,eff));
    // Mostly uniform open sea; bathymetry only a faint deepening.
    col=mix(col,water_deep_tint.rgb,smoothstep(500.0,3600.0,depth)*0.25);
    // Narrow teal strip right at the beach.
    col=mix(col,water_shallow_tint.rgb*1.08,(1.0-smoothstep(0.0,max(px_m*5.0,700.0),coast_m))*0.55*(1.0-mouth*0.5));
    // Facets (low-poly surface) with smooth detail between them.
    float facet_id;
    vec2 centre=wl_facet_center(p,water_facet_size,facet_id);
    float facet_px=footprint/water_facet_size;
    float facet_amount=anim*(1.0-smoothstep(0.25,0.6,facet_px));
    vec3 n_detail=wl_normal(p,footprint,t,flow,anim);
    vec3 n_facet=wl_normal(centre,0.0,t,flow,1.6);
    float tilt=(facet_id-0.5)*0.05;
    n_facet=normalize(n_facet+vec3(tilt,0.0,-tilt*0.7));
    // Crisp low-contrast facets (reference): flat per-triangle normals.
    vec3 n=normalize(mix(n_detail,n_facet,facet_amount*0.8));
    // Facet tone: faint per-triangle brightness steps.
    col*=1.0+(facet_id-0.5)*0.05*facet_amount;
    col*=1.0+(wl_wave(p,footprint,t,flow)-0.5)*0.10*anim;
    // Caustic-like light web in very shallow water.
    float shallow=1.0-smoothstep(2.0,16.0,eff);
    float c1=wl_fnoise(p*2.3+vec2(t*0.12,t*0.05),footprint*2.3);
    float c2=wl_fnoise(p*2.7-vec2(t*0.07,t*0.11)+vec2(3.1,7.7),footprint*2.7);
    float caustic=pow(1.0-abs(c1-c2),9.0)*shallow*anim;
    col+=vec3(0.10,0.14,0.12)*caustic;
    // Storm: darker, greyer water.
    col=mix(col,col*vec3(0.62,0.68,0.72),storm*0.6);
    // Sky reflection via Fresnel.
    vec3 r=reflect(-view_world,n);
    vec3 sky=mix(water_sky_horizon.rgb,water_sky_zenith.rgb,clamp(r.y*1.4,0.0,1.0));
    sky=mix(sky,vec3(0.45,0.50,0.56),storm*0.7);
    float fres=0.03+0.97*pow(1.0-clamp(dot(n,view_world),0.0,1.0),5.0);
    float sheen=clamp(fres*mix(0.35,0.9,anim),0.0,0.45);
    // Stylised glitter path: the light is mirrored in front of the camera so
    // the sun trail is visible; it follows the sun's azimuth and elevation.
    vec3 l=normalize(vec3(water_sun_dir.x,max(water_sun_dir.y,0.08),-abs(water_sun_dir.z)-0.35));
    float rl=max(dot(r,l),0.0);
    // Core path from the smooth detail normal: soft, no flat-white facets.
    float rd=max(dot(reflect(-view_world,n_detail),l),0.0);
    float glint_core=pow(rd,900.0)*0.35;
    // Small soft points at facet centres, not whole white triangles.
    float dot_mask=1.0-smoothstep(0.0,water_facet_size*0.14,length(p-centre));
    float sparkle=step(0.95,fract(facet_id*13.7+t*0.45))*pow(rl,160.0)*dot_mask;
    float broad=pow(rd,320.0)*0.05;
    float glitter=(glint_core*2.2+sparkle*1.4*facet_amount+broad)*anim*water_glitter*sun_mask*(1.0-storm*0.8);
    // Sun glare: broad warm sheen along the true mirror direction of the sun
    // (not mirrored into the frame like the trail above), so it only shows in
    // backlight and widens as the sun sinks. A softened normal keeps it in
    // the far view, where the wave detail has faded to its mean.
    vec3 l_sun=normalize(vec3(water_sun_dir.x,max(water_sun_dir.y,0.02),water_sun_dir.z));
    float low_sun=1.0-smoothstep(0.10,0.70,l_sun.y);
    vec3 n_soft=normalize(mix(vec3(0.0,1.0,0.0),n_detail,0.35));
    float glare_rd=max(dot(reflect(-view_world,n_soft),l_sun),0.0);
    float glare=pow(glare_rd,mix(48.0,9.0,low_sun))*mix(0.25,1.0,low_sun)*water_glitter*sun_mask*(1.0-storm*0.9);
    vec3 glare_tint=mix(water_sun_tint.rgb,vec3(1.0,0.74,0.42),low_sun);
    // Surf: permanent shore foam plus 2-3 bands running towards the coast.
    float foam_w=max(px_m*1.1,80.0)*mix(0.45,1.0,saum_scale);
    float shore=1.0-smoothstep(foam_w*0.3,foam_w,coast_m);
    float band_span=max(px_m*14.0,1500.0)*mix(0.5,1.0,saum_scale);
    float bands=0.0;
    for(int k=0;k<3;k++) {
        float phase=fract(t*0.07+float(k)/3.0+wl_noise(p*0.15+float(k))*0.25);
        float pos=band_span*(1.0-phase);
        float line=exp(-abs(coast_m-pos)/(foam_w*0.45));
        bands+=line*smoothstep(0.0,0.25,phase)*(1.0-smoothstep(0.7,1.0,phase))*0.40;
    }
    float whitecap=smoothstep(0.78,0.95,wl_wave(p,footprint,t,flow)/(0.6+0.8*wl_wind_strength()+0.8*storm))*storm*anim;
    // One soft, narrow foam line (slow breathing); surf bands are off.
    float foam=clamp(shore*0.55*(1.0-far_view*0.7)*(0.8+0.2*sin(t*1.2+c1*8.0))+bands*anim*saum_scale*0.0+whitecap*0.6,0.0,1.0);
    foam*=1.0-mouth;
    foam*=1.0-smoothstep(1.2,3.5,footprint)*0.7;
    col=mix(col,water_foam_tint.rgb,foam*0.85);
    s.albedo=col*mix(0.80,1.0,sun_mask);
    s.emission=sky*sheen*0.25+water_sun_tint.rgb*glitter*0.45+glare_tint*glare*0.55+vec3(0.55,0.62,0.75)*clamp(weather_lightning,0.0,1.0)*0.35;
    s.normal=n;
    s.roughness=mix(0.75,0.45,anim);
    s.foam=foam;
    return s;
}
