// The grain economy on the terrain (sim/godot/src/grain_map.rs): fields by
// season around the farms, footpaths worn towards the markets, market
// squares, trade roads and sea lanes. people_dots.gd fills the layers once a
// month: a window of fine tiles (1.5625 km) around the camera and the road
// layer of 25 km cells over the whole map.
//
// Look after Urbek like the terrain (tile_terrain.gdshader, which includes
// this after its palette): one flat colour per parcel, crisp edges, no
// noise, furrows or fades, colours from the terrain palette.
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
// Field parcels: half a terrain tile on a side (250 m up close), on the
// terrain's own grid, so a parcel never cuts a tile.
const float SIM_ROAD_KM = 0.12;  // a paved road at diorama scale (as the houses)
const float SIM_TRACK_KM = 0.07;
const float SIM_PATH_KM = 0.03;  // a worn path
const float SIM_TRAIL_KM = 0.018;


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

// Fields on open land (`land`, the terrain's landscape here). Each fine
// tile farms one block around its middle, as large as its field share, so
// the farmland reads as calm blocks around the villages instead of a
// scatter; inside the block the sown parcels take the season's colour
// (earth, sprouts, green, ripe wheat, stubble), the fallow ones stay
// meadow. `tile_size` is the terrain tile (km), the parcel is half of it.
// From about 8 km of view a block is one colour (the season's, no fallow
// parcels in it); from about 30 km there are no blocks, the farmland is the
// terrain's own.
vec3 sim_fields(vec2 p, vec3 c, int land, float tile_size, float fw_km) {
	if (!sim_map_on || sim_fine_n == 0 || fw_km > 0.02) { return c; }
	if (land != G_FIELD && land != G_MEADOW && land != G_DRY_GRASS) { return c; }
	float size = tile_size * 0.5;
	vec2 cell = floor(p / size);
	vec2 mid = (cell + 0.5) * size;
	vec2 q = (mid - sim_fine_origin) / sim_fine_km;
	vec4 f = sim_fine_at(ivec2(floor(q)));
	// the sim decides where the fields are: farmland it does not farm lies
	// as pasture
	vec3 open_land = land == G_FIELD ? GROUND_RGB[G_MEADOW] : c;
	if (f.r <= 0.0) { return open_land; }
	// rank of the parcel in its tile: the share of the tile nearer the
	// middle (a rounded square), with a little jitter for a ragged edge
	vec2 d = abs(fract(q) - 0.5) * 2.0;
	float r = mix(max(d.x, d.y), length(d) * 0.7071, 0.5);
	if (r * r + (whole ? 0.0 : 0.12 * (sim_hash(cell) - 0.5)) >= f.r) { return open_land; }
	bool whole = fw_km > 0.005;
	if (!whole && sim_hash(cell + 17.3) >= f.g) {
		return GROUND_RGB[G_MEADOW];
	}
	float g = f.b;
	vec3 meadow = GROUND_RGB[G_MEADOW];
	vec3 field = GROUND_RGB[G_FIELD];
	// stubble, ploughed earth, sprouts on the soil, green corn, ripe wheat:
	// sown land never takes the meadow's own green, so it reads as farmland
	return g <= 0.0 ? mix(field, C_EARTH, 0.4) : g < 0.12 ? C_EARTH : g < 0.4 ? mix(C_EARTH, meadow, 0.5) : g < 0.75 ? mix(meadow, field, 0.4) : field;
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

// 1 inside a band of half width w around distance 0, crisp (half a pixel
// of edge).
float sim_band(float d, float w, float fw_km) {
	float aa = fw_km * 0.5 + 1e-5;
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

// Footpaths, market squares and trade roads over the land colour c.
vec3 sim_ways(vec2 p, vec3 c, float fw_km) {
	if (!sim_map_on) { return c; }
	if (sim_fine_n > 0) {
		vec3 w = sim_paths(p);
		// footpaths only up close (about 10 km of view), at least 1.5 px
		if (w.y > 0.0 && fw_km < 0.006) {
			float half_w = max(w.y >= 2.0 ? SIM_PATH_KM : SIM_TRAIL_KM, fw_km * 1.5) * 0.5;
			c = mix(c, C_BANK, sim_band(w.x, half_w, fw_km));
		}
		// a paved square with rows of stalls under red and white awnings
		float sq = 0.16;
		if (w.z < sq + fw_km) {
			vec2 g = fract(p / 0.05);
			vec2 id = floor(p / 0.05);
			bool stall = abs(g.x - 0.5) < 0.3 && abs(g.y - 0.5) < 0.22 && w.z < sq - 0.03 && sim_hash(id) > 0.45;
			vec3 m = stall ? (sim_hash(id + 5.0) < 0.5 ? C_ROOF : C_WALL) : C_PAVED;
			c = mix(c, m, sim_band(w.z, sq, fw_km));
		}
	}
	// trade roads up to a few hundred km of view, only the paved ones from
	// about 100 km: a light travertine band with darker kerbs, at least
	// 2 px, so they read as roads and not as scratches
	if (fw_km < 0.3) {
		vec3 r = sim_roads(p);
		bool road = r.y >= 2.0;
		if (r.y > 0.0 && (road || fw_km < 0.06)) {
			float half_w = max(road ? SIM_ROAD_KM : SIM_TRACK_KM, fw_km * 2.0) * 0.5;
			vec3 top = road ? mix(C_PAVED, vec3(1.0), 0.3) : C_BANK;
			// kerbs only where the road is wide enough to carry them; a thin
			// dark line reads as a crack
			if (half_w > fw_km * 1.9) {
				c = mix(c, C_PAVED * 0.8, sim_band(r.x, half_w + fw_km, fw_km));
			}
			c = mix(c, top, sim_band(r.x, half_w, fw_km));
		}
	}
	return c;
}

// Sea lanes: light dashes along the trade lanes at sea, 8 px on and 6 px
// off at any zoom, up to about 150 km of view (further out they are only
// a grid of lines over the sea).
vec3 sim_lanes(vec2 p, vec3 c, float fw_km) {
	if (!sim_map_on || fw_km > 0.1) { return c; }
	vec3 r = sim_roads(p);
	if (r.y <= 0.0) { return c; }
	float half_w = max(0.05, fw_km * 1.5) * 0.5;
	bool dash = fract(r.z / (fw_km * 14.0)) < 8.0 / 14.0;
	return dash ? mix(c, GROUND_RGB[G_SNOW], sim_band(r.x, half_w, fw_km) * 0.45) : c;
}
