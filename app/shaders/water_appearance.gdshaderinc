// Own material-only water interpretation, revision diorama-water-r7.
// No source sampling, ownership/discard, vertex motion, or LOD selection here.
// Model X/Z, view width and pixel footprint: 1 unit = 1 kilometre.
// Distances and positive bathymetry: source metres, never display-Y scaled.
uniform vec4 water_style_deep : source_color = vec4(0.058824,0.247059,0.470588,1.0);
uniform vec4 water_style_basin : source_color = vec4(0.105882,0.372549,0.639216,1.0);
uniform vec4 water_style_shelf : source_color = vec4(0.247059,0.654902,0.709804,1.0);
uniform vec4 water_style_shoal : source_color = vec4(0.462745,0.733333,0.709804,1.0);
uniform vec4 water_style_inland : source_color = vec4(0.129412,0.419608,0.588235,1.0);
uniform vec4 water_style_river : source_color = vec4(0.184314,0.505882,0.603922,1.0);
uniform vec4 water_style_edge_light : source_color = vec4(0.760784,0.850980,0.784314,1.0);
uniform float water_style_wave_strength : hint_range(0.0,1.0) = 0.30;
uniform float water_style_surface_strength : hint_range(0.0,0.1) = 0.035;
uniform float water_style_shore_accent : hint_range(0.0,0.8) = 0.42;

// Fade an existing world-space band before it becomes subpixel. The band does
// not grow or move with zoom, and flat-map relief disables every wave normal.
float water_band_visibility(float wavelength_world, float pixel_world) {
    float pixels_per_cycle = wavelength_world / max(pixel_world, 0.00001);
    return smoothstep(2.5, 7.0, pixels_per_cycle);
}

// Three fixed analytic bands, not texture noise or new surveyed water shape.
// The phase warp makes short, broad wave faces rather than parallel ruled lines.
// Returned gradient is a material normal slope; it NEVER displaces geometry.
void water_wave_band(vec2 p, vec2 direction, float wavelength, float seconds,
        float rate, out float value, out vec2 gradient) {
    vec2 across = vec2(-direction.y, direction.x);
    float k = 6.28318530718 / wavelength;
    float lateral = dot(p, across) * k * 0.27;
    float phase = dot(p, direction) * k + 0.72 * sin(lateral) - seconds * rate;
    float s = sin(phase);
    value = s * (0.65 + 0.35 * abs(s));
    gradient = cos(phase) * (0.65 + 0.70 * abs(s)) *
        (direction + across * (0.72 * 0.27 * cos(lateral)));
}

// Four-corner deterministic field. Analytic derivatives give finite wave faces
// in both directions, rather than infinitely repeating sine crests. No sampler.
float water_hash(vec2 p) {
    vec3 q=fract(vec3(p.x,p.y,p.x)*0.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
void water_face(vec2 p,out float value,out vec2 gradient) {
    vec2 cell=floor(p);
    vec2 f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    vec2 du=6.0*f*(1.0-f);
    float a=water_hash(cell);
    float b=water_hash(cell+vec2(1.0,0.0));
    float c=water_hash(cell+vec2(0.0,1.0));
    float d=water_hash(cell+vec2(1.0,1.0));
    value=mix(mix(a,b,u.x),mix(c,d,u.x),u.y)*2.0-1.0;
    gradient=vec2(mix(b-a,d-c,u.y)*du.x,
        mix(c-a,d-b,u.x)*du.y)*2.0;
}
// The short axis is filtered first; unresolved pieces disappear instead of
// becoming a ruled line. Drift is fixed in model space, independent of zoom.
float water_face_visibility(float scale_world,float pixel_world) {
    return smoothstep(1.8,4.0,scale_world/max(pixel_world,0.00001));
}
void water_short_faces(vec2 p,float scale_world,float seconds,float offset,
        out float value,out vec2 gradient) {
    float turn=offset>30.0 ? -0.18 : (offset>10.0 ? 0.24 : 0.0);
    vec2 along=normalize(vec2(0.936,0.352)+vec2(-0.352,0.936)*turn);
    vec2 across=vec2(-along.y,along.x);
    // Continuous world field, deliberately NOT per-cell zeroed envelopes.
    // Slow nonperiodic curvature and coverage remove the visible woven grid.
    vec2 q=vec2(dot(p,along)*0.25,dot(p,across)*0.60)/scale_world+vec2(offset);
    float field;vec2 field_gradient;
    water_face(q,field,field_gradient);
    vec2 field_g=along*field_gradient.x*0.25+across*field_gradient.y*0.60;
    float phase=dot(p,along)*6.28318530718/scale_world+field*2.8-seconds*0.22;
    float t=clamp((field+0.15)/0.80,0.0,1.0);
    float envelope=t*t*(3.0-2.0*t);
    float envelope_derivative=6.0*t*(1.0-t)/0.80;
    float sv=sin(phase);float cv=cos(phase);
    value=sv*envelope;
    gradient=cv*envelope*(along+field_g*(2.8/6.28318530718))+
        sv*field_g*(envelope_derivative/6.28318530718);
}

// Decorative submerged material, NOT extra terrain, surveyed rocks or depth.
// The real source depth gates visibility. Opaque optical compositing avoids
// another render pass, depth buffer sampling and transparent sorting.
vec3 water_shallow_bed(vec2 world_xz,float depth,float pixel_world) {
    float sand;vec2 sand_g;
    water_face(world_xz/0.8+vec2(31.7,14.2),sand,sand_g);
    vec3 bottom=vec3(0.26,0.36,0.27)*(1.0+sand*0.075);
    // Sparse small polygonal mineral patches, not kilometre-wide dark blobs.
    // These are submerged decorative material, never terrain geometry.
    float rock_scale=0.45;
    float visible=water_face_visibility(rock_scale,pixel_world);
    if (visible>0.0) {
        vec2 q=world_xz/rock_scale;
        vec2 id=floor(q);vec2 f=fract(q)-0.5;
        float h=water_hash(id+vec2(19.2,63.1));
        float h2=water_hash(id+vec2(71.3,5.7));
        f-=vec2(h-0.5,h2-0.5)*0.18;
        vec2 axis=normalize(vec2(h2-0.5,0.75));
        vec2 local=vec2(dot(f,axis),dot(f,vec2(-axis.y,axis.x)));
        float polygon=max(abs(local.y),abs(local.x)*0.8660254+abs(local.y)*0.5);
        float radius=mix(0.14,0.28,h2);
        float aa=max(pixel_world/rock_scale*0.7,0.018);
        float shape=1.0-smoothstep(radius-aa,radius+aa,polygon);
        float occupancy=smoothstep(0.72,0.84,h);
        float facet=step(0.0,local.x+local.y*0.35);
        vec3 mineral=mix(vec3(0.065,0.145,0.135),vec3(0.11,0.20,0.175),facet);
        bottom=mix(bottom,mineral,shape*occupancy*visible);
    }
    vec3 transmittance=exp(-depth*vec3(0.026,0.010,0.007));
    return bottom*transmittance+water_style_shelf.rgb*(1.0-transmittance);
}

void water_appearance(
        vec2 world_xz,
        float signed_coast_distance_m,
        float display_coast_distance_m,
        float bathymetry_m,
        int water_role,
        float relief_weight,
        float view_width_world,
        float world_units_per_pixel,
        float time_seconds,
        out vec3 linear_rgb,
        out vec3 world_normal,
        out float roughness,
        out float specular) {
    // Caller alone decides physical ownership. Role0 is safe and non-destructive
    // if accidentally evaluated, but it is not intended to colour terrain.
    linear_rgb = water_style_deep.rgb;
    world_normal = vec3(0.0,1.0,0.0);
    roughness = 1.0;
    specular = 0.0;
    if (water_role == 0) return;

    float relief_amount = clamp(relief_weight,0.0,1.0);
    float regional = (1.0-smoothstep(2400.0,6500.0,view_width_world))*relief_amount;
    float close_detail = (1.0-smoothstep(360.0,1400.0,view_width_world))*relief_amount;
    float pixel_world = max(world_units_per_pixel,0.00001);
    float coastal_m = max(display_coast_distance_m,0.0);
    float physical_m = max(signed_coast_distance_m,0.0);

    if (water_role == 1) {
        // Both inputs are already composed by the resident child/parent caller.
        // Physical SDF saturates at3km: never use its saturation as bathymetry.
        float depth=max(bathymetry_m,0.0);
        // Distinct optical ranges: blue basin, turquoise shallow shelf, pale
        // shoal. Source depth governs the shelf; distance adds a limited bank
        // transition and is never interpreted as a fabricated deep seabed.
        float basin=1.0-exp(-depth/850.0);
        linear_rgb=mix(water_style_basin.rgb,water_style_deep.rgb,basin);
        float shallow=exp(-depth/80.0);
        float near_shelf=1.0-smoothstep(1000.0,14000.0,coastal_m);
        float shelf=clamp(shallow*0.88+near_shelf*exp(-depth/150.0)*0.12,0.0,1.0);
        linear_rgb=mix(linear_rgb,water_style_shelf.rgb,shelf);
        float shoal=(1.0-smoothstep(0.0,1800.0,physical_m))*
            (1.0-smoothstep(5.0,100.0,depth));
        float bank=1.0-smoothstep(0.0,320.0,physical_m);
        linear_rgb=mix(linear_rgb,water_style_shoal.rgb,max(shoal*0.74,bank*0.38));
        // Static low-contrast broad colour facets are a graphic treatment,
        // not surveyed rocks, caustics or new bathymetry. They remain anchored
        // across zoom and fade before their small edge transitions alias.
        float bed;vec2 bed_gradient;
        water_face(world_xz/6.4+vec2(8.7,29.3),bed,bed_gradient);
        float bed_visibility=water_band_visibility(6.4*0.35,pixel_world);
        float facets=mix(bed,round(bed*3.0)/3.0,0.32);
        linear_rgb*=1.0+facets*bed_visibility*(0.045+0.13*shelf);
        float bottom_visibility=exp(-depth/75.0)*(1.0-smoothstep(100.0,180.0,depth))*
            close_detail*water_face_visibility(0.8,pixel_world)*
            (1.0-smoothstep(350.0,2400.0,physical_m));
        if (bottom_visibility>0.002) {
            vec3 bottom=water_shallow_bed(world_xz,depth,pixel_world);
            linear_rgb=mix(linear_rgb,bottom,bottom_visibility*0.48);
        }

    } else if (water_role == 2) {
        // Appearance-only distance-to-bank proxy, NOT an inland depth estimate.
        float bank = 1.0-smoothstep(40.0,850.0,physical_m);
        linear_rgb = mix(water_style_inland.rgb,water_style_shelf.rgb,bank*0.35);
    } else {
        // Role3 is supplied only by the actual river caller. The marine SDF
        // can be negative under a river, so it must not define river width/depth.
        linear_rgb = water_style_river.rgb;
    }

    // Same palette/depth geography at every zoom. Only surface-detail energy
    // changes smoothly, never a separate water layout or camera-dependent UV.
    float detail = max(regional*0.42,close_detail);
    if (detail <= 0.00001) return;

    float a0=water_face_visibility(0.90,pixel_world)*detail;
    float a1=water_face_visibility(0.22,pixel_world)*close_detail;
    float a2=water_face_visibility(0.075,pixel_world)*close_detail;
    float v0=0.0;float v1=0.0;float v2=0.0;
    vec2 g0=vec2(0.0);vec2 g1=vec2(0.0);vec2 g2=vec2(0.0);
    if (a0>0.0) water_short_faces(world_xz,0.90,time_seconds,3.7,v0,g0);
    if (a1>0.0) water_short_faces(world_xz,0.22,time_seconds,19.2,v1,g1);
    if (a2>0.0) water_short_faces(world_xz,0.075,time_seconds,43.8,v2,g2);
    float role_energy=water_role==1 ? 1.0 : (water_role==2 ? 0.46 : 0.20);
    vec2 slope=(g0*a0*0.30+g1*a1*0.28+g2*a2*0.12)*
        water_style_wave_strength*role_energy;
    world_normal=normalize(vec3(-slope.x,1.0,-slope.y));
    float surface_value=(v0*a0*0.50+v1*a1*0.35+v2*a2*0.15)*role_energy;
    linear_rgb*=1.0+surface_value*water_style_surface_strength;

    if (water_role==1 && close_detail>0.0) {
        float edge_width_m=clamp(pixel_world*1000.0*0.65,60.0,180.0);
        float runup=45.0+24.0*sin(time_seconds*0.55+world_xz.x*0.7+world_xz.y*0.43);
        float edge=1.0-smoothstep(edge_width_m*0.15,edge_width_m,abs(physical_m-runup));
        float broken=0.40+0.60*smoothstep(-0.45,0.55,v0+v1*0.35);
        linear_rgb=mix(linear_rgb,water_style_edge_light.rgb,
            edge*broken*close_detail*water_style_shore_accent);
    }
    // Broad PBR highlights come from the actual scene light/view; there is no
    // screen-painted sun stripe. Coarse footprints raise roughness so broad
    // waves remain legible without glitter or a sparkling subpixel surface.
    float resolved=water_face_visibility(0.22,pixel_world)*close_detail;
    roughness=mix(0.86,water_role==1 ? 0.42 : 0.48,detail);
    roughness+=water_role==1 ? (1.0-resolved)*detail*0.12 : 0.0;
    specular=(water_role==1 ? 0.55 : 0.38)*detail;

}

// River-only addition. Distances are model kilometres; stationing is cumulative
// along the ORIGINAL polyline, never restarted at a segment/block boundary.
// Positive motion follows data order, which is NOT evidence of downstream flow.
void water_river_appearance(
        vec2 world_xz,
        float flow_distance_world,
        vec2 flow_tangent_world_xz,
        float bank_coordinate_world,
        float half_width_world,
        float relief_weight,
        float view_width_world,
        float world_units_per_pixel,
        float time_seconds,
        out vec3 linear_rgb,
        out vec3 world_normal,
        out float roughness,
        out float specular) {
    linear_rgb = water_style_river.rgb;
    world_normal = vec3(0.0,1.0,0.0);
    roughness = 1.0;
    specular = 0.0;
    float tangent_length = length(flow_tangent_world_xz);
    // Missing stationing must be represented by a zero tangent by the caller.
    // Calm fallback avoids arbitrary world-wind motion or segment phase resets.
    if (tangent_length <= 0.00001 || half_width_world <= 0.00001) return;
    float relief_amount = clamp(relief_weight,0.0,1.0);
    float regional = (1.0-smoothstep(2400.0,6500.0,view_width_world))*relief_amount;
    float close_detail = (1.0-smoothstep(360.0,1400.0,view_width_world))*relief_amount;
    float detail = max(regional*0.42,close_detail);
    if (detail <= 0.00001) return;

    vec2 tangent = flow_tangent_world_xz/tangent_length;
    vec2 across = vec2(-tangent.y,tangent.x);
    vec2 river_coordinate = vec2(flow_distance_world,bank_coordinate_world);
    float v0;float v1;
    vec2 g0;vec2 g1;
    water_wave_band(river_coordinate,vec2(1.0,0.0),1.85,time_seconds,0.095,v0,g0);
    water_wave_band(river_coordinate,vec2(1.0,0.0),0.72,time_seconds,0.145,v1,g1);
    float a0 = water_band_visibility(1.85,world_units_per_pixel)*detail;
    float a1 = water_band_visibility(0.72,world_units_per_pixel)*close_detail;
    // Keep material motion off the bank. Width/classification and bank colour
    // remain caller-owned; this only damps the decorative surface perturbation.
    float bank_fraction = abs(bank_coordinate_world)/half_width_world;
    float bank_energy = 1.0-smoothstep(0.55,1.0,bank_fraction);
    vec2 local_slope = (g0*a0*0.040+g1*a1*0.018)*
        water_style_wave_strength*0.24*bank_energy;
    vec2 slope = tangent*local_slope.x+across*local_slope.y;
    world_normal = normalize(vec3(-slope.x,1.0,-slope.y));
    linear_rgb *= 1.0+(v0*a0*0.70+v1*a1*0.30)*
        0.24*bank_energy*water_style_surface_strength;
    roughness = mix(0.94,0.46,detail);
    specular = 0.38*detail;
}

// Optional surface reflection, separate from the existing directional-light
// specular lobe. Own analytic daytime sky, NOT a sampled scene/environment.
// VIEW must be transformed to WORLD space by the caller, including orthographic
// cameras. Apply reflected_radiance * reflectance as EMISSION, and remove the
// same reflectance from water ALBEDO. No source, geometry or global light edits.
void water_environment_reflection(
        vec3 world_normal,
        vec3 world_view_direction,
        int water_role,
        float relief_weight,
        float view_width_world,
        out vec3 reflected_radiance,
        out float reflectance) {
    reflected_radiance=vec3(0.0);
    reflectance=0.0;
    float surface=(1.0-smoothstep(1400.0,4800.0,view_width_world))*
        clamp(relief_weight,0.0,1.0);
    if (water_role==0 || surface<=0.00001) return;
    vec3 n=normalize(world_normal);
    vec3 v=normalize(world_view_direction);
    float facing=clamp(dot(n,v),0.0,1.0);
    float grazing=1.0-facing;
    float fresnel=0.025+0.975*grazing*grazing*grazing*grazing*grazing;
    vec3 reflected=reflect(-v,n);
    // Broad soft horizon and cool upper sky deliberately have no small light
    // sources. The actual scene sun continues to use the renderer's PBR path.
    vec3 horizon=mix(water_style_edge_light.rgb,vec3(0.72,0.81,0.87),0.70);
    vec3 zenith=vec3(0.24,0.44,0.68);
    float sky_height=smoothstep(0.02,0.88,max(reflected.y,0.0));
    reflected_radiance=mix(horizon,zenith,sky_height);
    // Warm direct sun glints are evaluated by the Forward+ scene light.
    float role_weight=water_role==1 ? 1.0 : (water_role==2 ? 0.68 : 0.40);
    reflectance=min(fresnel,0.58)*surface*role_weight;
}
