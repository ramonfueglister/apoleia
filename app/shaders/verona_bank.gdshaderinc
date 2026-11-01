// Local shoreline design only. Coordinates are existing quarter parcels;
// this centreline is the renderer's existing 0.5km river-band geometry.
uniform bool verona_bank_active = false;
vec2 vb_closest_segment(vec2 p, vec2 a, vec2 b) {
	vec2 e = b - a;
	return a + e * clamp(dot(p-a,e)/dot(e,e),0.0,1.0);
}
vec2 vb_nearest(vec2 q) {
	vec2 a = vb_closest_segment(q,vec2(18455.0,6914.0),vec2(18456.0,6915.0));
	vec2 b = vb_closest_segment(q,vec2(18456.0,6915.0),vec2(18458.0,6915.0));
	return distance(q,a) < distance(q,b) ? a : b;
}
float vb_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
vec3 vb_ground_colour(vec2 p, vec3 original, float river_d_km) {
	if (!verona_bank_active) { return original; }
	vec2 q = (p-world_min)/0.25;
	vec2 centre = vb_nearest(q);
	if (q.x < 18455.08 || q.x > 18457.85 || q.y < centre.y || q.y > 6916.0) { return original; }
	float dry = river_d_km - 0.075;
	if (dry < 0.003 || dry > 0.10) { return original; }
	float ends = smoothstep(18455.08,18455.33,q.x)*(1.0-smoothstep(18457.60,18457.85,q.x));
	vec2 metre = (p-(world_min+vec2(18455.0,6914.0)*0.25))/0.0238;
	float cell = floor(metre.x*0.8);
	float f = fract(metre.x*0.8); f=f*f*(3.0-2.0*f);
	float wander=mix(vb_hash(vec2(cell,3.7)),vb_hash(vec2(cell+1.0,3.7)),f);
	float width = 0.039+0.026*wander;
	float fray=(vb_hash(floor(metre/0.32))-0.5)*0.003;
	float edge = 1.0-smoothstep(width-0.003+fray,width+0.005+fray,dry);
	float shore = smoothstep(0.003,0.010,dry);
	float pixels = length(fwidth(metre));
	float detail = 1.0-smoothstep(0.025,0.13,pixels);
	// Isolated small pebbles in fine earth, not a continuous joint network.
	// Their coverage fades before sub-pixel grains can shimmer.
	vec2 grid=metre/0.095;
	vec2 base=floor(grid); vec2 uv=fract(grid);
	float first=10.0; float shade=0.5;
	for (int y=-1;y<=1;y++) {
		for (int x=-1;x<=1;x++) {
			vec2 cell_id=base+vec2(float(x),float(y));
			vec2 jitter=vec2(vb_hash(cell_id),vb_hash(cell_id+vec2(17.3,5.1)));
			float distance_to=length(vec2(float(x),float(y))+0.15+0.7*jitter-uv);
			if (distance_to<first) { first=distance_to;shade=jitter.x; }
		}
	}
	vec2 soil_grid=metre/0.75;
	vec2 soil_base=floor(soil_grid); vec2 soil_uv=fract(soil_grid);
	soil_uv=soil_uv*soil_uv*(3.0-2.0*soil_uv);
	float soil_noise=mix(mix(vb_hash(soil_base),vb_hash(soil_base+vec2(1.0,0.0)),soil_uv.x),
		mix(vb_hash(soil_base+vec2(0.0,1.0)),vb_hash(soil_base+vec2(1.0)),soil_uv.x),soil_uv.y);
	float loose= smoothstep(0.23,0.48,soil_noise);
	float radius=0.19+0.16*shade;
	float aa=max(0.035,pixels/0.095*0.45);
	float pebble=(1.0-smoothstep(radius-aa,radius+aa,first))*loose;
	vec3 earth=mix(vec3(0.62,0.58,0.48),vec3(0.68,0.64,0.54),soil_noise);
	vec3 stone=mix(vec3(0.73,0.70,0.61),vec3(0.82,0.79,0.70),shade);
	vec3 gravel=mix(earth,stone,pebble*detail);
	// When individual grains vanish, retain their subdued average tone.
	gravel=mix(gravel,mix(earth,vec3(0.76,0.73,0.64),0.23*loose),1.0-detail);
	return mix(original,gravel,edge*shore*ends*0.93);
}
