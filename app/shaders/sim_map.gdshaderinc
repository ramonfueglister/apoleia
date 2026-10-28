// The grain economy on the terrain (sim/godot/src/grain_map.rs): fields by
// season around the farms, footpaths worn towards the markets, market
// squares, trade roads and sea lanes. people_dots.gd fills the layers once a
// month: a window of fine tiles (1.5625 km) around the camera and the road
// layer of 25 km cells over the whole map.
//
// Fine texel: R share of the tile under fields, G sown share of them, B
// growth (0 bare … 1 ripe), A footpath level (bits 0-1), its next step
// towards the market + 1 (bits 2-5) and market tile (bit 6).
// Road texel: R level (1 track, 2 road; at sea a lane), G the neighbours it
// joins (bit k = SIM_DIRS[k]).

uniform bool sim_map_on = false;
uniform sampler2D sim_fine_tex : filter_nearest, repeat_disable;
uniform vec2 sim_fine_origin;      // world km of the window's first texel corner
uniform float sim_fine_km = 1.5625;
uniform int sim_fine_n = 0;
uniform sampler2D sim_road_tex : filter_nearest, repeat_disable;
uniform vec2 sim_cell_origin;      // world km of the grid's corner
uniform float sim_cell_km = 25.0;
uniform ivec2 sim_cell_n = ivec2(0);

// (row, col) steps as grain.rs DIRS, here as (x = col, y = row)
const ivec2 SIM_DIRS[8] = ivec2[](ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(-1, 0), ivec2(1, 0), ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1));
// Parcels per fine tile side: about 130 m, a few hectares, like the
// centuriated strips of a Roman farm.
const float SIM_PARCELS = 12.0;
const float SIM_ROAD_KM = 0.12;  // a paved road at diorama scale (as the houses)
const float SIM_TRACK_KM = 0.07;
const float SIM_PATH_KM = 0.03;  // a worn path
const float SIM_TRAIL_KM = 0.018;

const vec3 SIM_EARTH = vec3(0.56, 0.43, 0.29);
const vec3 SIM_SPROUT = vec3(0.5, 0.58, 0.32);
const vec3 SIM_GREEN = vec3(0.42, 0.55, 0.26);
const vec3 SIM_RIPE = vec3(0.82, 0.71, 0.4);
const vec3 SIM_STUBBLE = vec3(0.74, 0.68, 0.5);
const vec3 SIM_FALLOW = vec3(0.55, 0.56, 0.36); // grazed, weedy
const vec3 SIM_TRACK = vec3(0.66, 0.56, 0.4);
const vec3 SIM_ROAD = vec3(0.7, 0.67, 0.6);
const vec3 SIM_KERB = vec3(0.45, 0.42, 0.37);

float sim_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Fine texel at window tile t, zero outside the window.
vec4 sim_fine_at(ivec2 t) {
	if (t.x < 0 || t.y < 0 || t.x >= sim_fine_n || t.y >= sim_fine_n) { return vec4(0.0); }
	return texelFetch(sim_fine_tex, t, 0);
}

int sim_byte(float v) {
	return int(v * 255.0 + 0.5);
}

float sim_segment(vec2 p, vec2 a, vec2 b) {
	vec2 e = b - a;
	return length(p - a - e * clamp(dot(p - a, e) / dot(e, e), 0.0, 1.0));
}

// How far along the segment from a the point nearest p lies (in units of p).
float sim_along(vec2 p, vec2 a, vec2 b) {
	vec2 e = b - a;
	return clamp(dot(p - a, e) / dot(e, e), 0.0, 1.0) * length(e);
}

// Fields on the fine tile under p: parcels by hash up to the tile's field
// share; sown parcels by growth (earth, sprouts, green, ripe), the others
// fallow; furrows along one side, a dark balk between parcels.
vec3 sim_fields(vec2 p, vec3 c) {
	if (!sim_map_on || sim_fine_n == 0) { return c; }
	vec2 q = (p - sim_fine_origin) / sim_fine_km;
	vec4 f = sim_fine_at(ivec2(floor(q)));
	if (f.r <= 0.0) { return c; }
	vec2 pq = q * SIM_PARCELS;
	vec2 cell = floor(pq);
	vec2 uv = pq - cell;
	if (sim_hash(cell) >= f.r) { return c; }
	vec3 col;
	if (sim_hash(cell + 17.3) < f.g) {
		float g = f.b;
		col = g <= 0.0 ? SIM_STUBBLE : g < 0.15 ? mix(SIM_EARTH, SIM_SPROUT, g / 0.15)
			: g < 0.7 ? mix(SIM_SPROUT, SIM_GREEN, (g - 0.15) / 0.55) : mix(SIM_GREEN, SIM_RIPE, (g - 0.7) / 0.3);
	} else {
		// fallow is grazed: closer to the land around it
		col = mix(c, SIM_FALLOW, 0.45);
	}
	col *= 0.95 + 0.1 * sim_hash(cell + 3.1);
	// furrows
	float u = sim_hash(cell + 9.7) < 0.5 ? uv.x : uv.y;
	float fu = fract(u * 9.0);
	float fw = fwidth(u * 9.0);
	col *= 1.0 - 0.1 * (1.0 - smoothstep(0.0, fw + 0.15, abs(fu - 0.5) - 0.3)) * (1.0 - smoothstep(0.3, 0.6, fw));
	// balks
	vec2 e = min(uv, 1.0 - uv);
	vec2 ew = fwidth(uv);
	float balk = 1.0 - smoothstep(0.0, 1.0, min(e.x / max(ew.x, 1e-5), e.y / max(ew.y, 1e-5)) * 0.6);
	col = mix(col, col * 0.7, balk * (1.0 - smoothstep(0.2, 0.5, max(ew.x, ew.y))));
	// further out the parcels fade to a soft tint before they shimmer
	float px = 1.0 / max(max(ew.x, ew.y), 1e-5);
	return mix(c, col, mix(0.35, 1.0, smoothstep(10.0, 24.0, px)) * smoothstep(2.0, 5.0, px));
}

// Distance to the footpaths on and through the fine tile under p (km) and
// their level; markets: distance to the square.
vec3 sim_paths(vec2 p) {
	vec2 q = (p - sim_fine_origin) / sim_fine_km;
	ivec2 t = ivec2(floor(q));
	float best = 1e9;
	float level = 0.0;
	float market = 1e9;
	for (int k = -1; k < 8; k++) {
		ivec2 n = k < 0 ? t : t + SIM_DIRS[k];
		int a = sim_byte(sim_fine_at(n).a);
		if ((a & 64) != 0) {
			vec2 d = abs(q - (vec2(n) + 0.5)) * sim_fine_km;
			market = min(market, max(d.x, d.y));
		}
		int lv = a & 3;
		int step = (a >> 2) & 15;
		if (lv == 0 || step == 0) { continue; }
		ivec2 to = n + SIM_DIRS[step - 1];
		// only the paths that touch this tile
		if (k >= 0 && to != t) { continue; }
		float d = sim_segment(q, vec2(n) + 0.5, vec2(to) + 0.5) * sim_fine_km;
		if (d < best) {
			best = d;
			level = float(lv);
		}
	}
	return vec3(best, level, market);
}

// Distance to the trade roads (or sea lanes) near p, km, the level and
// how far along its segment the nearest point lies, km.
vec3 sim_roads(vec2 p) {
	if (sim_cell_n.x == 0) { return vec3(1e9, 0.0, 0.0); }
	vec2 q = (p - sim_cell_origin) / sim_cell_km;
	ivec2 c = ivec2(floor(q));
	float best = 1e9;
	float level = 0.0;
	float along = 0.0;
	// the cell's own roads and those of its four neighbours (their
	// diagonals pass the cell's corners)
	const ivec2 NB[5] = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 5; i++) {
		ivec2 n = c + NB[i];
		if (n.x < 0 || n.y < 0 || n.x >= sim_cell_n.x || n.y >= sim_cell_n.y) { continue; }
		vec4 r = texelFetch(sim_road_tex, n, 0);
		int lv = sim_byte(r.r);
		if (lv == 0) { continue; }
		int mask = sim_byte(r.g);
		for (int k = 0; k < 8; k++) {
			if ((mask & (1 << k)) == 0) { continue; }
			vec2 a = vec2(n) + 0.5;
			vec2 b = vec2(n + SIM_DIRS[k]) + 0.5;
			float d = sim_segment(q, a, b) * sim_cell_km;
			if (d < best) {
				best = d;
				level = float(lv);
				along = sim_along(q, a, b) * sim_cell_km;
			}
		}
	}
	return vec3(best, level, along);
}

// Footpaths, market squares and trade roads over the land colour c.
vec3 sim_ways(vec2 p, vec3 c, float fw_km) {
	if (!sim_map_on) { return c; }
	if (sim_fine_n > 0) {
		vec3 w = sim_paths(p);
		if (w.y > 0.0) {
			float half_w = max(w.y >= 2.0 ? SIM_PATH_KM : SIM_TRAIL_KM, fw_km * 0.6) * 0.5;
			float aa = fw_km;
			c = mix(c, SIM_TRACK * (w.y >= 2.0 ? 0.95 : 1.05), (1.0 - smoothstep(half_w, half_w + aa, w.x)) * (w.y >= 2.0 ? 0.9 : 0.6));
		}
		// a paved square with rows of stalls under coloured awnings
		float sq = 0.16;
		if (w.z < sq + fw_km) {
			vec3 m = SIM_ROAD;
			vec2 g = fract(p / 0.05);
			vec2 id = floor(p / 0.05);
			float stall = step(abs(g.x - 0.5), 0.3) * step(abs(g.y - 0.5), 0.22) * step(w.z, sq - 0.03) * step(0.45, sim_hash(id));
			vec3 awning = sim_hash(id + 5.0) < 0.5 ? vec3(0.78, 0.3, 0.22) : vec3(0.88, 0.84, 0.72);
			m = mix(m, awning, stall);
			c = mix(c, m, 1.0 - smoothstep(sq, sq + fw_km, w.z));
		}
	}
	vec3 r = sim_roads(p);
	if (r.y > 0.0) {
		bool road = r.y >= 2.0;
		float half_w = max(road ? SIM_ROAD_KM : SIM_TRACK_KM, fw_km * (road ? 3.0 : 2.0)) * 0.5;
		float aa = fw_km;
		float on = 1.0 - smoothstep(half_w, half_w + aa, r.x);
		// up close paved with kerbs; on the map a dark line that reads on green
		float map = smoothstep(0.02, 0.1, fw_km);
		vec3 near_col = road ? mix(SIM_ROAD, SIM_KERB, smoothstep(half_w * 0.7, half_w * 0.75 + aa, r.x)) : SIM_TRACK;
		vec3 far_col = road ? vec3(0.42, 0.3, 0.2) : vec3(0.55, 0.42, 0.28);
		c = mix(c, mix(near_col, far_col, map), on);
	}
	return c;
}

// Sea lanes: dashes along the trade lanes at sea.
vec3 sim_lanes(vec2 p, vec3 c, float fw_km) {
	if (!sim_map_on) { return c; }
	vec3 r = sim_roads(p);
	if (r.y <= 0.0) { return c; }
	float half_w = max(0.05, fw_km * 1.4) * 0.5;
	float dash = step(0.45, fract(r.z / max(1.5, fw_km * 10.0)));
	float on = (1.0 - smoothstep(half_w, half_w + fw_km, r.x)) * dash;
	return mix(c, vec3(0.9, 0.95, 0.97), on * 0.7);
}
