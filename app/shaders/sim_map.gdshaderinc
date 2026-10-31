// The grain economy on the terrain (sim/godot/src/grain_map.rs): fields by
// season around the farms, the ways people wear walking (S127), market
// squares, trade roads and sea lanes. people_dots.gd fills the layers once a
// month: a window of fine tiles (1.5625 km) around the camera and the road
// layer of 25 km cells over the whole map.
//
// Look after Urbek like the terrain (tile_terrain.gdshader, which includes
// this after its palette): one flat colour per parcel, crisp edges, no
// noise, furrows or fades, colours from the terrain palette.
//
// Fine texel (sim_fields.gdshaderinc): A way level (bits 0-1 and 7), its
// next step towards the market + 1 (bits 2-5) and market tile (bit 6).
// Road texel: R level (1 track, 2 road; at sea a lane), G the neighbours it
// joins (bit k = SIM_DIRS[k]); drawn only at sea (sim_lanes): on land the
// wagons wear the fine layer's ways (S127).

#include "res://shaders/sim_fields.gdshaderinc"

uniform sampler2D sim_road_tex : filter_nearest, repeat_disable;
uniform vec2 sim_cell_origin;      // world km of the grid's corner
uniform float sim_cell_km = 25.0;
uniform ivec2 sim_cell_n = ivec2(0);
// the regions coloured by a column of the markets (sim_tables.gd): RGB the
// class colour, A bit 0 coloured, bits 1-4 a border to the north, east,
// south and west
uniform sampler2D sim_region_tex : filter_nearest, repeat_disable;
uniform bool sim_regions_on = false;



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

// Further out (beyond the crops, to SIM_FIELDS_KM) the fields are those
// of the near view, only smaller (round J, 30.10.2026): the same long
// fields of sim_strip, sown or fallow and with the crop as up close
// (sim_parcel, sim_crop_kind), in the colours of the crops on their slabs
// (people_crops.gdshader): the fallow a straw sheet, a sown field its rows
// along the field over the soil. The rows (SIM_FAR_ROWS a parcel) show
// while they are at least SIM_FAR_ROW_PX on screen and blend into the
// field's mean colour below; a grass margin of SLAB_GAP a side, half a
// pixel at least, parts one field from the next as the slabs' edges do up
// close. (Before, a square of 3 x 3 parcels took one flat colour of its
// own and the fallow lay as grass: zooming out past the crops shuffled
// the fields, and neighbours ran together into blotches.)
const float SIM_FAR_PARCEL_KM = 0.25; // as the parcels up close
const float SIM_FAR_ROWS = 3.0;       // rows a parcel (12 up close, people_crops.gdshader crop_rows)
const float SIM_FAR_ROW_PX = 4.0;     // rows in full from this spacing on screen, gone at half of it
const float SIM_FAR_GAP = 0.04;       // people_crop_slab.gdshaderinc SLAB_GAP
// the crops' colours (people_crops.gdshader)
const vec3 SIM_SOIL = vec3(0.34, 0.24, 0.18);
const vec3 SIM_SOIL_DRY = vec3(0.46, 0.34, 0.25);
const vec3 SIM_SPROUT = vec3(0.28, 0.5, 0.2);
const vec3 SIM_GRAIN_GREEN[2] = vec3[](vec3(0.2, 0.43, 0.15), vec3(0.32, 0.48, 0.18)); // wheat, barley
const vec3 SIM_RIPE[2] = vec3[](vec3(0.68, 0.64, 0.36), vec3(0.72, 0.68, 0.46));
const vec3 SIM_FALLOW = vec3(0.62, 0.6, 0.32);
const vec3 SIM_STUBBLE = vec3(0.62, 0.54, 0.38);
const vec3 SIM_FURROW = vec3(0.26, 0.18, 0.13);
const vec3 SIM_LEAVES = vec3(0.2, 0.42, 0.17);
const vec3 SIM_VINE = vec3(0.24, 0.44, 0.18);
const vec3 SIM_VINE_BARE = vec3(0.42, 0.3, 0.2);

// Whether the parcel `cell` belongs to field `strip` (sim_strip).
bool sim_same_field(vec2 cell, vec3 strip) {
	return all(equal(sim_strip(cell), strip));
}

// The far field colour at p of parcel `cell` (side `size` km) in `state`
// (1 fallow, 2 sown) with growth g; `fw_km` the size of a pixel there and
// `pasture` the ground round the fields.
vec3 sim_far_field(vec2 p, vec2 cell, float size, int state, float g, float fw_km, vec3 pasture) {
	vec3 strip = sim_strip(cell);
	vec2 at = (p - world_min) / size - cell; // 0..1 in the parcel
	// the grass margin on the sides where another field (or none) begins
	float gap = max(SIM_FAR_GAP, 0.5 * fw_km / size);
	float aa = 0.5 * fw_km / size + 1e-5;
	float edge = 10.0;
	if (at.x < gap * 2.0 && !sim_same_field(cell - vec2(1.0, 0.0), strip)) { edge = min(edge, at.x); }
	if (at.x > 1.0 - gap * 2.0 && !sim_same_field(cell + vec2(1.0, 0.0), strip)) { edge = min(edge, 1.0 - at.x); }
	if (at.y < gap * 2.0 && !sim_same_field(cell - vec2(0.0, 1.0), strip)) { edge = min(edge, at.y); }
	if (at.y > 1.0 - gap * 2.0 && !sim_same_field(cell + vec2(0.0, 1.0), strip)) { edge = min(edge, 1.0 - at.y); }
	float grass = 1.0 - smoothstep(gap - aa, gap + aa, edge);
	if (state == 1) { return mix(SIM_FALLOW, pasture, grass); }
	// the soil and its rows by crop and growth, as people_crops.gdshader
	float pick = sim_hash(strip.xy * 1.37 + strip.z * 19.1 + 5.1); // sim_crop_kind
	int kind = pick < 0.4 ? SIM_WHEAT : pick < 0.6 ? SIM_BARLEY : pick < 0.85 ? SIM_BEANS : SIM_VINES;
	vec3 soil = SIM_SOIL;
	vec3 row = SIM_FURROW;
	float w = 0.5; // share of the row spacing
	if (kind == SIM_WHEAT || kind == SIM_BARLEY) {
		if (g <= 0.0) { soil = SIM_STUBBLE; row = SIM_STUBBLE * 0.85; w = 0.35; }
		else if (g < 0.12) { row = SIM_FURROW; }
		else if (g < 0.4) { row = SIM_SPROUT; }
		else if (g < 0.75) { row = SIM_GRAIN_GREEN[kind]; w = 0.6; }
		else { soil = SIM_RIPE[kind]; row = mix(SIM_RIPE[kind], vec3(1.0, 0.95, 0.7), 0.3); w = 0.6; }
	} else if (kind == SIM_BEANS) {
		if (g >= 0.12) { row = g < 0.4 ? SIM_SPROUT : g < 0.75 ? SIM_LEAVES : mix(SIM_LEAVES, SIM_RIPE[0], 0.3); }
		w = g < 0.4 ? 0.5 : 0.6;
	} else {
		soil = SIM_SOIL_DRY;
		row = g < 0.12 ? SIM_VINE_BARE : SIM_VINE;
	}
	// the rows run along the field (sim_strip z: 0 long along x)
	float across = (strip.z < 0.5 ? at.y : at.x) * SIM_FAR_ROWS;
	float d = abs(fract(across) - 0.5);
	float raa = 0.5 * fw_km / size * SIM_FAR_ROWS + 1e-5;
	float on = 1.0 - smoothstep(w * 0.5 - raa, w * 0.5 + raa, d);
	float spacing_px = size / SIM_FAR_ROWS / max(fw_km, 1e-6);
	float show = smoothstep(SIM_FAR_ROW_PX * 0.5, SIM_FAR_ROW_PX, spacing_px);
	vec3 mean = mix(soil, row, w);
	vec3 c = mix(mean, mix(soil, row, on), show);
	return mix(c, pasture, grass);
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
// edges. Further out the same fields lie flat on the ground in their crops'
// colours (sim_far_field), so the farmland still reads as fields round the
// towns at 20-30 km. From SIM_FIELDS_KM the farmland is the terrain's own.
const vec3 SIM_DIRT = vec3(0.3, 0.28, 0.225); // #888068 on screen: Urbek's field tracks (r11 Fix 5)
const vec3 SIM_TRACK_RGB = vec3(0.42, 0.37, 0.29); // the ways people wear (sim_ways)
// per way level: up to which view width it is drawn (the faint ones up
// close only) and how much of the bare earth shows
const float SIM_WAY_SHOW_KM[8] = float[](0.0, 6.0, 10.0, 16.0, 25.0, 40.0, 40.0, 40.0);
const float SIM_WAY_ALPHA[8] = float[](0.0, 0.35, 0.5, 0.65, 0.8, 0.9, 1.0, 1.0);
const vec3 SIM_VERGE_RGB = vec3(0.55, 0.7, 0.45); // the grass along them, paler than the meadow
const float SIM_VERGE_KM = 0.016;                  // its width, a third of the lane's as Urbek's

// Whether the parcel with its middle at `mid` carries a slab up close, as
// people_crop_slab.gdshaderinc crop_open (which needs the people's
// helpers): open land outside the towns, no farmhouse lot, flat, not at
// the foot of a ramp, not under trees; a field the player built on any land.
bool sim_slab_open(vec2 mid) {
	ivec2 t = ivec2(floor((mid - world_min) / tile_km));
	bool built = (sim_built(mid) & SIM_B_FIELD) != 0;
	if (tt_town(t) != 0 || tt_water(t) != W_LAND) { return false; }
	int land = tt_ground_at(t, fract((mid - world_min) / tile_km));
	if (land != G_FIELD && land != G_MEADOW && land != G_DRY_GRASS && !built) { return false; }
	vec4 front = tt_corners_cached(t + ivec2(0, 1));
	if (max(max(front.x, front.y), max(front.z, front.w)) > tt_corners_cached(t).x + 0.01) { return false; }
	return !sim_house_lot(mid) && sim_flat(mid) && (built || !sim_no_field(mid, land));
}

// `fw_km`: the size of a pixel at p (km).
vec3 sim_fields(vec2 p, vec3 c, int land, float tile_size, float fw_km) {
	if (!sim_map_on || sim_fine_n == 0 || sim_view_km > SIM_FIELDS_KM) { return c; }
	bool built = (sim_built(p) & SIM_B_FIELD) != 0; // a field the player built, on any land
	if (land != G_FIELD && land != G_MEADOW && land != G_DRY_GRASS && !built) { return c; }
	vec3 meadow = GROUND_RGB[G_MEADOW];
	vec3 pasture = land == G_FIELD ? meadow : c; // farmland the sim does not farm
	if (!sim_flat(p)) { return pasture; }
	float data_km = sub_tiles ? tile_size * 2.0 : tile_size;
	bool near = sim_view_km <= SIM_CROPS_KM;
	if (near && sim_house_lot(p)) { return pasture; } // the farmhouse's yard
	float size = near ? data_km * 0.5 : SIM_FAR_PARCEL_KM;
	vec2 cell = floor((p - world_min) / size);
	// inside the square of crops the slabs stand on dirt: the strips between
	// them read as Urbek's field tracks (r11: on meadow the fields lay on
	// the lawn like rugs, with no track to them); the parcel as
	// people_parcels.gdshader worked it out, not for every pixel again
	bool crops = near && all(greaterThanEqual(p, sim_crop_box.xy)) && all(lessThan(p, sim_crop_box.zw));
	int code;
	float growth;
	float level;
	if (crops && sim_parcel_baked(cell, code, growth, level)) {
		if ((code & SIM_P_STATE) == 0 || (code & SIM_P_NO_FIELD) != 0) { return pasture; }
		return (code & SIM_P_OPEN) != 0 ? SIM_DIRT : meadow;
	}
	vec4 f;
	int state = sim_parcel(cell, size, f);
	if (state == 0 || (!built && sim_no_field(world_min + (cell + 0.5) * size, land))) { return pasture; }
	if (crops) { return sim_slab_open(world_min + (cell + 0.5) * size) ? SIM_DIRT : meadow; }
	return sim_far_field(p, cell, size, state, f.b, fw_km, pasture);
}

// Distance from p to the market square on or next to the fine tile under
// p (km), large without one.
float sim_market_sq(vec2 p) {
	vec2 q = (p - sim_fine_origin) / sim_fine_km;
	ivec2 t = ivec2(floor(q));
	float market = 1e9;
	for (int k = -1; k < 8; k++) {
		ivec2 n = k < 0 ? t : t + SIM_DIRS[k];
		if ((sim_byte(sim_fine_at(n).a) & 64) != 0) {
			vec2 d = abs(q - (vec2(n) + 0.5)) * sim_fine_km;
			market = min(market, max(d.x, d.y));
		}
	}
	return market;
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
// The map coloured by region, as EU5's map modes: one flat colour per
// region over the land, its border a darker line of at least 1.5 px.
vec3 sim_regions(vec2 p, vec3 c, float fw_km) {
	vec2 g = (p - sim_cell_origin) / sim_cell_km;
	ivec2 cell = ivec2(floor(g));
	if (cell.x < 0 || cell.y < 0 || cell.x >= sim_cell_n.x || cell.y >= sim_cell_n.y) { return c; }
	vec4 t = texelFetch(sim_region_tex, cell, 0);
	int bits = sim_byte(t.a);
	if ((bits & 1) == 0) { return c; }
	vec3 tint = pow(t.rgb, vec3(2.2)); // sRGB texel, linear terrain colour
	c = mix(c, tint, 0.7);
	vec2 f = fract(g);
	float edge = 1e9;
	if ((bits & 2) != 0) { edge = min(edge, f.y); }
	if ((bits & 4) != 0) { edge = min(edge, 1.0 - f.x); }
	if ((bits & 8) != 0) { edge = min(edge, 1.0 - f.y); }
	if ((bits & 16) != 0) { edge = min(edge, f.x); }
	float half_w = max(fw_km * 1.5, 0.4) / sim_cell_km;
	float aa = fw_km / sim_cell_km;
	return mix(c, tint * 0.45, 1.0 - smoothstep(half_w - aa, half_w + aa, edge));
}

vec3 sim_ways(vec2 p, vec3 c, float fw_km) {
	if (sim_regions_on) { c = sim_regions(p, c, fw_km); }
	if (!sim_map_on) { return c; }
	// none in the towns: their streets and squares are the terrain's (r11: a
	// footpath ran across the Forum, a market lay by the Tiber as a decal)
	bool town = tt_town(ivec2(floor((p - world_min) / tile_km))) > 0;
	if (sim_fine_n > 0 && !town) {
		// the ways people wear walking (S127, sim_way): a faint track of
		// trodden grass after the first walks, then ever wider bare earth
		// with a paler verge, as Urbek's farm tracks (#8a7e64 by a verge
		// #66ac5c); up close only for the faint ones, the wide ones further
		vec2 w = sim_way(p);
		int lv = int(w.y);
		if (lv > 0 && sim_view_km <= SIM_WAY_SHOW_KM[lv]) {
			float lift = max(fw_km * 0.7 - SIM_WAY_KM[lv], 0.0); // at least ~1.5 px wide
			float d = w.x - lift;
			if (lv >= 4) {
				c = mix(c, mix(c, SIM_VERGE_RGB, 0.6), sim_band(d, SIM_VERGE_KM, fw_km));
			}
			c = mix(c, SIM_TRACK_RGB, SIM_WAY_ALPHA[lv] * sim_band(d, 0.0, fw_km));
		}
		// a paved square; further out than the standing stalls show
		// (people_trips.gd SQUARES_KM) rows of stalls under red and white
		// awnings painted on it
		float msq = sim_market_sq(p);
		float sq = 0.16;
		if (msq < sq + fw_km) {
			vec2 g = fract(p / 0.05);
			vec2 id = floor(p / 0.05);
			bool stall = sim_view_km > 10.0 && abs(g.x - 0.5) < 0.3 && abs(g.y - 0.5) < 0.22 && msq < sq - 0.03 && sim_hash(id) > 0.45;
			vec3 m = stall ? (sim_hash(id + 5.0) < 0.5 ? C_ROOF : C_WALL) : C_PAVED;
			c = mix(c, m, sim_band(msq, sq, fw_km));
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
