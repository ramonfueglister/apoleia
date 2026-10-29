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
// Fine texel (sim_fields.gdshaderinc): A footpath level (bits 0-1), its next
// step towards the market + 1 (bits 2-5) and market tile (bit 6).
// Road texel: R level (1 track, 2 road; at sea a lane), G the neighbours it
// joins (bit k = SIM_DIRS[k]).

#include "res://shaders/sim_fields.gdshaderinc"

uniform sampler2D sim_road_tex : filter_nearest, repeat_disable;
uniform vec2 sim_cell_origin;      // world km of the grid's corner
uniform float sim_cell_km = 25.0;
uniform ivec2 sim_cell_n = ivec2(0);

// (row, col) steps as grain.rs DIRS, here as (x = col, y = row)
const ivec2 SIM_DIRS[8] = ivec2[](ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(-1, 0), ivec2(1, 0), ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1));
const float SIM_ROAD_KM = 0.12;  // a paved road at diorama scale (as the houses)
const float SIM_TRACK_KM = 0.07;
const float SIM_PATH_KM = 0.03;  // a worn path
const float SIM_TRAIL_KM = 0.018;


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

// The flat colour of parcel `cell` from afar or outside the square of
// crops: a few close tones, so the farmland reads as a fine quilt round the
// villages (the painted mid view, refs/gemalt-weit-mittel-nah.png) and not
// as large blotches of yellow on green. Fallow is stubble or grazed grass,
// half and half; the sown parcels each a little ahead or behind the
// season: freshly tilled soil, young green, the olive of growing grain,
// beans and vines, and Urbek's wheat yellow only once ripe.
const float SIM_FAR_PARCEL_KM = 0.25; // as the parcels up close, so the quilt keeps its grain from 8 to 40 km
vec3 sim_parcel_rgb(int state, vec2 cell, vec4 f, vec3 pasture) {
	if (state == 0) { return pasture; }
	vec3 field = GROUND_RGB[G_FIELD];          // #cdc373 on screen
	vec3 stubble = field * 0.9;                // #b9ad6b
	vec3 young = GROUND_RGB[G_ALPINE];         // #86bb6a
	vec3 olive = mix(GROUND_RGB[G_DRY_GRASS], GROUND_RGB[G_SCRUB], 0.5); // #8f9f55
	vec3 soil = vec3(0.42, 0.27, 0.18);        // #8a5a3c
	float h = sim_hash(cell + 3.7);
	if (state == 1) { return h < 0.5 ? stubble : young; }
	float g = clamp(f.b + (h - 0.5) * 0.6, 0.0, 1.0);
	int kind = sim_crop_kind(cell);
	if (g < 0.1) { return soil; }
	if (kind == SIM_VINES || kind == SIM_BEANS) { return olive; }
	return g < 0.45 ? young : g < 0.8 ? olive : field;
}

// Fields on open land (`land`, the terrain's landscape here), on the
// terrain's own grid so a parcel never cuts a tile (sim_parcel), on flat
// tiles only: the ramps between the terraces stay grass (SimCity 2000
// farms only on flat ground, and a parcel colour split by the ramp's two
// triangles reads as broken glass). Each parcel is one flat colour.
// Up close (to SIM_CROPS_KM of view) a parcel is half a data tile, a
// quarter tile of the drawn terrain, and a sown or fallow one is grass
// round the raised slab of crops or stubble that stands on it
// (people_crops.gdshader), so the farmland is a mosaic of slabs with grass
// edges. Further out a parcel is SIM_FAR_PARCEL_KM in the colours of
// sim_parcel_rgb, so the farmland still reads as fields round the towns
// at 20-30 km. From SIM_FIELDS_KM the farmland is the terrain's own.
vec3 sim_fields(vec2 p, vec3 c, int land, float tile_size) {
	if (!sim_map_on || sim_fine_n == 0 || sim_view_km > SIM_FIELDS_KM) { return c; }
	if (land != G_FIELD && land != G_MEADOW && land != G_DRY_GRASS) { return c; }
	vec3 meadow = GROUND_RGB[G_MEADOW];
	vec3 pasture = land == G_FIELD ? meadow : c; // farmland the sim does not farm
	if (!sim_flat(p)) { return pasture; }
	float data_km = sub_tiles ? tile_size * 2.0 : tile_size;
	bool near = sim_view_km <= SIM_CROPS_KM;
	if (near && sim_house_lot(p)) { return pasture; } // the farmhouse's yard
	float size = near ? data_km * 0.5 : SIM_FAR_PARCEL_KM;
	vec2 cell = floor((p - world_min) / size);
	if (!near) {
		// from afar two parcels make one field, side by side across or
		// along by the block, so the quilt is of long fields and not of
		// single squares
		vec2 block = floor(cell * 0.5);
		cell = sim_hash(block + 9.1) < 0.5 ? vec2(block.x * 2.0, cell.y) : vec2(cell.x, block.y * 2.0);
	}
	vec4 f;
	int state = sim_parcel(cell, size, f);
	// inside the square of crops the slabs stand on meadow
	bool crops = near && all(greaterThanEqual(p, sim_crop_box.xy)) && all(lessThan(p, sim_crop_box.zw));
	return crops && state != 0 ? meadow : sim_parcel_rgb(state, cell, f, pasture);
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
		// footpaths only up close (10 km of view), at least 1.5 px
		if (w.y > 0.0 && sim_view_km <= 10.0) {
			float half_w = max(w.y >= 2.0 ? SIM_PATH_KM : SIM_TRAIL_KM, fw_km * 1.5) * 0.5;
			c = mix(c, C_PAVED * 0.96, sim_band(w.x, half_w, fw_km));
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
	// the village lanes round the farmhouse lots, earth with a darker edge
	float lane = sim_lane(p);
	if (lane < SIM_LANE_KM + fw_km) {
		c = mix(c, C_BANK * 0.82, sim_band(lane, SIM_LANE_KM + fw_km, fw_km));
		c = mix(c, C_BANK * vec3(1.02, 0.94, 0.9), sim_band(lane, SIM_LANE_KM, fw_km));
	}
	// trade roads up to 100 km of view: a light paved band with a darker
	// edge, at least 3 px, so they read as roads and not as scratches;
	// further out the map is calm
	if (sim_view_km < 100.0) {
		vec3 r = sim_roads(p);
		if (r.y > 0.0) {
			bool road = r.y >= 2.0;
			float half_w = max(road ? SIM_ROAD_KM : SIM_TRACK_KM, fw_km * 3.0) * 0.5;
			vec3 top = road ? mix(C_PAVED, vec3(1.0), 0.15) : C_PAVED;
			c = mix(c, C_BANK * 0.75, sim_band(r.x, half_w + fw_km, fw_km));
			c = mix(c, top, sim_band(r.x, half_w, fw_km));
		}
	}
	return c;
}

// Sea lanes: light dashes along the trade lanes at sea, 8 px on and 6 px
// off at any zoom, up to about 150 km of view (further out they are only
// a grid of lines over the sea).
vec3 sim_lanes(vec2 p, vec3 c, float fw_km) {
	if (!sim_map_on || sim_view_km > 150.0) { return c; }
	vec3 r = sim_roads(p);
	if (r.y <= 0.0) { return c; }
	float half_w = max(0.05, fw_km * 1.5) * 0.5;
	bool dash = fract(r.z / (fw_km * 14.0)) < 8.0 / 14.0;
	return dash ? mix(c, GROUND_RGB[G_SNOW], sim_band(r.x, half_w, fw_km) * 0.45) : c;
}
