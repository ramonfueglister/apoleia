// Where the grain fields lie (sim/godot/src/grain_map.rs, the fine layer):
// shared by the terrain's field colours (sim_map.gdshaderinc) and the crops
// standing on them (people_crops.gdshader), so both agree parcel for parcel.
//
// Fine texel: R share of the tile under fields, G sown share of them, B
// growth (0 bare … 1 ripe), A footpaths and markets (sim_map.gdshaderinc).

uniform bool sim_map_on = false;
uniform sampler2D sim_fine_tex : filter_nearest, repeat_disable;
uniform vec2 sim_fine_origin;      // world km of the window's first texel corner
uniform float sim_fine_km = 1.5625;
uniform int sim_fine_n = 0;
uniform float sim_view_km = 30.0;  // view width: what is drawn (fields, crops, paths, roads, lanes)
uniform sampler2D sim_lot_tex : filter_nearest, repeat_disable; // lots with a farmhouse (people_lots.gdshader)
uniform vec2 sim_lot_origin;       // lot index (from world_min) of the mask's first pixel
uniform int sim_lots_n = 0;        // lots per side of the mask, 0 without one
uniform float sim_lot_km = 0.5;    // people_dots_common.gdshaderinc DOT_LOT_KM

// View width up to which the parcels are single and the crops stand on
// them as plants; up to 30 km the fields are whole blocks of one colour.
const float SIM_CROPS_KM = 8.0;
const float SIM_FIELDS_KM = 40.0;

float sim_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Fine texel at window tile t, zero outside the window.
vec4 sim_fine_at(ivec2 t) {
	if (t.x < 0 || t.y < 0 || t.x >= sim_fine_n || t.y >= sim_fine_n) { return vec4(0.0); }
	return texelFetch(sim_fine_tex, t, 0);
}

// The crop of a sown parcel, so the farmland is a patchwork: 0 wheat,
// 1 barley (both a closed sheet), 2 vegetables and beans in rows, 3 vines;
// rows run east-west or north-south.
const int SIM_WHEAT = 0;
const int SIM_BARLEY = 1;
const int SIM_BEANS = 2;
const int SIM_VINES = 3;
int sim_crop_kind(vec2 cell) {
	float pick = sim_hash(cell + 5.1);
	return pick < 0.4 ? SIM_WHEAT : pick < 0.6 ? SIM_BARLEY : pick < 0.85 ? SIM_BEANS : SIM_VINES;
}

bool sim_crop_rows_ns(vec2 cell) {
	return sim_hash(cell + 9.7) < 0.5;
}

// Whether a farmhouse stands on the lot under p (world km); its house,
// garden and yard are kept free of fields. The mask is kept only while the
// crops stand.
bool sim_house_lot(vec2 p) {
	if (sim_lots_n == 0 || sim_view_km > SIM_CROPS_KM) { return false; }
	vec2 lot = floor((p - world_min) / sim_lot_km) - sim_lot_origin;
	if (lot.x < 0.0 || lot.y < 0.0 || lot.x >= float(sim_lots_n) || lot.y >= float(sim_lots_n)) { return false; }
	return texelFetch(sim_lot_tex, ivec2(lot), 0).a > 0.5;
}

// A flat tile under p (no ramp): the crops stand only on flat ground, the
// ramps carry their colour (sim_map.gdshaderinc), as their rows and slabs
// cannot fold with the ramp's triangles.
bool sim_flat(vec2 p) {
	vec4 r = round(tt_corners_cached(ivec2(floor((p - world_min) / tile_km))));
	return max(max(r.x, r.y), max(r.z, r.w)) - min(min(r.x, r.y), min(r.z, r.w)) < 0.01;
}

// The side of its lot a farmhouse faces, where its path leaves the gate:
// the quarter turn of people_dots_common.gdshaderinc dot_house_turn (the
// same hash, kept apart as the terrain does not include that file).
uint sim_lot_hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}
vec2 sim_lot_front(vec2 lot) {
	uint key = sim_lot_hash(uint(int(lot.x)) * 0x9e3779b1u ^ uint(int(lot.y)) * 0x85ebca77u);
	uint a = sim_lot_hash(key * 0x9e3779b9u + 7u * 0x632be5abu);
	int q = int(floor(float(a & 0xffffu) / 65535.0 * 4.0)) % 4;
	return q == 0 ? vec2(0.0, 1.0) : q == 1 ? vec2(-1.0, 0.0) : q == 2 ? vec2(0.0, -1.0) : vec2(1.0, 0.0);
}

// Village lanes run on the lot lines, which are parcel lines too (a lot is
// 2 x 2 parcels), so they pass between the fields: between neighbouring
// farmhouse lots (the streets of a village) and along the side each
// farmhouse faces, where its path meets them; no ring round a lone farm
// (graph paper). Distance (km) from p to the nearest lane, large without one.
const float SIM_LANE_KM = 0.013; // half width
bool sim_lane_between(vec2 lot, vec2 dir) {
	bool here = sim_house_lot(world_min + (lot + 0.5) * sim_lot_km);
	bool there = sim_house_lot(world_min + (lot + dir + 0.5) * sim_lot_km);
	return (here && (there || sim_lot_front(lot) == dir)) || (there && sim_lot_front(lot + dir) == -dir);
}
float sim_lane(vec2 p) {
	if (sim_lots_n == 0 || sim_view_km > SIM_CROPS_KM) { return 1e9; }
	vec2 q = (p - world_min) / sim_lot_km;
	vec2 f = fract(q);
	vec2 lot = floor(q);
	vec2 side = vec2(f.x < 0.5 ? -1.0 : 1.0, f.y < 0.5 ? -1.0 : 1.0);
	vec2 d = min(f, 1.0 - f) * sim_lot_km;
	float best = 1e9;
	if (sim_lane_between(lot, vec2(side.x, 0.0))) { best = d.x; }
	if (sim_lane_between(lot, vec2(0.0, side.y))) { best = min(best, d.y); }
	return best;
}

// The parcel `cell` (of side `size` km): 0 not farmed, 1 fallow, 2 sown;
// `f` is its fine texel. Each fine tile farms one block around its middle,
// as large as its field share (a rounded square, with a little jitter for a
// ragged edge), so the farmland reads as calm blocks around the villages;
// from afar (`whole`) a fine tile with a quarter or more in fields is one
// whole field block, so the blocks join into a patchwork without meadow
// strips between them, and has no fallow parcels.
int sim_parcel(vec2 cell, float size, bool whole, out vec4 f) {
	vec2 q = (world_min + (cell + 0.5) * size - sim_fine_origin) / sim_fine_km;
	f = sim_fine_at(ivec2(floor(q)));
	if (f.r <= 0.0) { return 0; }
	if (whole) { return f.r >= 0.25 ? 2 : 0; }
	vec2 d = abs(fract(q) - 0.5) * 2.0;
	float r = mix(max(d.x, d.y), length(d) * 0.7071, 0.5);
	if (r * r + 0.12 * (sim_hash(cell) - 0.5) >= f.r) { return 0; }
	if (sim_hash(cell + 17.3) >= f.g) { return 1; }
	return 2;
}
