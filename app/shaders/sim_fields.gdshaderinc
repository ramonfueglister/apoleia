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
uniform vec4 sim_crop_box;         // world km (min x, min y, max x, max y) of the square where the crops stand (people_dots.gd _update_crops)
// The parcels of that square worked out once each (people_parcels.gdshader)
// instead of for every vertex of their crops and every pixel of their
// ground: parcel `cell` at texel cell mod sim_parcel_n.
uniform sampler2D sim_parcel_tex : filter_nearest, repeat_disable;
uniform int sim_parcel_n = 0;      // texels per side, 0 without them

// View width up to which the parcels are single and the crops stand on
// them as plants; up to 40 km the fields are whole blocks of one colour.
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

// Up close the parcels lie in fields of three to five by one or two, as
// Urbek's long fields (Ramon 29.10.2026 on s3: "die felder sehn extrem
// müllig aus", a chessboard of single parcels; s4 with 3-6 by 2-3 they
// dwarfed the trees and houses): east-west or north-south by block of 6 x 6
// parcels, the rows of a block in bands of one or two, each band cut at its
// own length and offset. The parcels of a field share
// their crop and whether they lie fallow, and their slabs join into one
// (people_parcels.gdshader). xy the field's id, z its axis (0 long along x,
// 1 along y).
vec3 sim_strip(vec2 cell) {
	vec2 block = floor(cell / 6.0);
	float axis = sim_hash(block + 41.3) < 0.5 ? 0.0 : 1.0;
	vec2 c = axis < 0.5 ? cell : cell.yx;
	float wide = 1.0 + floor(sim_hash(block + 3.9) * 2.0);
	float band = floor((c.y + floor(sim_hash(block + 8.3) * wide)) / wide);
	float len = 3.0 + floor(sim_hash(vec2(band, 7.7) + axis) * 3.0);
	float off = floor(sim_hash(vec2(band, 13.1) + axis) * len);
	return vec3(floor((c.x + off) / len), band, axis);
}

// The crop of a sown parcel, so the farmland is a patchwork: 0 wheat,
// 1 barley (both in unbroken rows, ripe a closed sheet), 2 vegetables and
// beans in rows of clumps, 3 vines. One crop a field.
const int SIM_WHEAT = 0;
const int SIM_BARLEY = 1;
const int SIM_BEANS = 2;
const int SIM_VINES = 3;
int sim_crop_kind(vec2 cell) {
	vec3 strip = sim_strip(cell);
	float pick = sim_hash(strip.xy * 1.37 + strip.z * 19.1 + 5.1);
	return pick < 0.4 ? SIM_WHEAT : pick < 0.6 ? SIM_BARLEY : pick < 0.85 ? SIM_BEANS : SIM_VINES;
}

// Ground the terrain gives to trees or a town, where no field lies (r11:
// slabs under olive rows and groves, fields inside Rome at 22 km): the data
// tile of a grove (tile_props.gdshaderinc tt_prop_place: open land, fewer
// on field land), up close an olive grove (tt_olive_grove: flat open land
// in the warm lowlands within two data tiles of a town) and the data tiles
// next to a town. Keep in step with tile_props.gdshaderinc. `land` is the
// terrain's landscape at p.
bool sim_no_field(vec2 p, int land) {
	ivec2 dt = ivec2(floor((p - world_min) / tt_data_km()));
	if (tt_hash(vec2(dt) * 0.613 + 7.1) < (land == G_FIELD ? 0.03 : 0.07)) { return true; }
	bool olive = sub_tiles && land != G_FIELD && tt_hash(vec2(dt) * 0.71 + 3.3) < 0.5
		&& tt_latitude(p) < 44.5 && tt_height_m(p, height_lod) < 700.0;
	int ring = olive ? 2 : 1;
	for (int j = -ring; j <= ring; j++) {
		for (int i = -ring; i <= ring; i++) {
			if ((tt_data_cell(dt + ivec2(i, j)) >> 2) >= 2) { return true; }
		}
	}
	return false;
}

// The lot mask's texel under p (world km), zero outside the mask: A a
// farmhouse on the lot (people_lots.gdshader), R, G, B what the player
// built there (sim_built). people_dots.gd keeps it round the view up to
// SIM_FIELDS_KM. Branch free: always one fetch (clamped), masked after.
// With the fetch behind early returns, its dozen inlined copies in the
// terrain's fragment stage (sim_lane, sim_fields) crashed Apple's Metal
// compiler (MTLCompilerService, LLVM fatal error; Godot:
// XPC_ERROR_CONNECTION_INTERRUPTED) and the terrain pipeline was never built.
vec4 sim_lot_mask(vec2 p) {
	vec2 lot = floor((p - world_min) / sim_lot_km) - sim_lot_origin;
	bool inside = sim_lots_n > 0 && sim_view_km <= SIM_FIELDS_KM
		&& all(greaterThanEqual(lot, vec2(0.0))) && all(lessThan(lot, vec2(float(sim_lots_n))));
	vec4 m = texelFetch(sim_lot_tex, clamp(ivec2(lot), ivec2(0), ivec2(max(sim_lots_n - 1, 0))), 0);
	return inside ? m : vec4(0.0);
}

// Whether a farmhouse stands on the lot under p (world km); its house,
// garden and yard are kept free of fields. The houses are in the mask only
// while the crops stand.
bool sim_house_lot(vec2 p) {
	vec4 m = sim_lot_mask(p); // first, not behind the && (Metal, above)
	return sim_view_km <= SIM_CROPS_KM && m.a > 0.5;
}

// What the player built on the parcel under p (world km), from the lot
// mask (build_menu.gd _built_bits): SIM_B_FIELD a finished field on its
// lot (state land, S116), farmed whatever the farms' blocks round the fine
// tiles' middles (sim_parcel), so it reads as a field and not as a zone
// laid over the ground; SIM_B_ROAD a road the player built crosses the
// parcel, which then carries no field; from SIM_B_SIDES four bits -x, -y,
// +x, +y: a road runs along that side, and the slab keeps its width free
// (people_crop_slab.gdshaderinc crop_box_of). Each lot holds a field bit
// and five bits for each of its four parcels (the quarter x + 2 y).
const int SIM_B_FIELD = 1;
const int SIM_B_ROAD = 2;
const int SIM_B_SIDES = 4;
const float SIM_ROAD_HALF_KM = 0.048; // road_view.gd ROAD_KM / 2: four diorama metres
int sim_built(vec2 p) {
	vec4 m = sim_lot_mask(p);
	int v = int(m.r * 255.0 + 0.5) | (int(m.g * 255.0 + 0.5) << 8) | (int(m.b * 255.0 + 0.5) << 16);
	vec2 q = fract((p - world_min) / sim_lot_km);
	int k = (q.x < 0.5 ? 0 : 1) + (q.y < 0.5 ? 0 : 2);
	return (v & 1) | (((v >> (1 + 5 * k)) & 31) << 1);
}

// Whether nothing grows at p (world km) as the player built there: a field
// lot, a parcel a road crosses, or within `reach` km of a road along a
// parcel's side (the trees, tile_props.gdshaderinc).
bool sim_built_clear(vec2 p, float reach) {
	int b = sim_built(p);
	float size = sim_lot_km * 0.5;
	vec2 at = fract((p - world_min) / size) * size;
	int sides = b / SIM_B_SIDES;
	bool by_road = ((sides & 1) != 0 && at.x < reach) || ((sides & 2) != 0 && at.y < reach)
		|| ((sides & 4) != 0 && size - at.x < reach) || ((sides & 8) != 0 && size - at.y < reach);
	return (b & (SIM_B_FIELD | SIM_B_ROAD)) != 0 || by_road;
}

// A flat tile under p (no ramp): the crops stand only on flat ground, the
// ramps carry their colour (sim_map.gdshaderinc), as their rows and slabs
// cannot fold with the ramp's triangles. The corners as they are, not
// rounded: a ramp over several tiles has corners a fraction of a level
// apart, and a slab on one cut a corner off (round 18).
bool sim_flat(vec2 p) {
	vec4 r = tt_corners_cached(ivec2(floor((p - world_min) / tile_km)));
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
	float u = float(a & 0xffffu) / 65535.0;
	return u < 0.5 ? vec2(0.0, 1.0) : u < 0.75 ? vec2(-1.0, 0.0) : vec2(1.0, 0.0);
}

// Village lanes run on the lot lines, which are parcel lines too (a lot is
// 2 x 2 parcels), so they pass between the fields: between neighbouring
// farmhouse lots (the streets of a village) and along the side each
// farmhouse faces, where its path meets them; no ring round a lone farm
// (graph paper). A street of the village runs on along its line for one
// more lot as a track between the fields, so it does not end blind at the
// village's edge (round 17: a lane ran into a wheat slab). Distance (km)
// from p to the nearest lane, large without one.
const float SIM_LANE_KM = 0.024; // half width (round 19: 0.013 read as a thin line at 3 km; s3: Urbek's farm tracks are wide)
bool sim_lot_house(vec2 lot) {
	return sim_house_lot(world_min + (lot + 0.5) * sim_lot_km);
}
// Field tracks: through the farmland a track runs on every SIM_TRACK_EVERY-th
// lot line, a stretch now and then left out, as the net of farm tracks
// between Urbek's fields (s3: 13 % of Urbek's farmland picture are tracks,
// ours had none). Only where the fine tile under the stretch is farmed.
const float SIM_TRACK_EVERY = 3.0;
bool sim_track_between(vec2 lot, vec2 dir) {
	vec2 e = dir.yx; // along the line
	float line = dot(lot + max(dir, vec2(0.0)), abs(dir)); // the line's index across it
	if (mod(line, SIM_TRACK_EVERY) != 0.0) { return false; }
	float along = dot(lot, abs(e));
	if (sim_hash(vec2(line, along) * 0.73 + abs(dir.x) * 5.3) > 0.8) { return false; }
	vec2 mid = world_min + (lot + max(dir, vec2(0.0)) * abs(dir) + abs(e) * 0.5) * sim_lot_km;
	vec2 q = (mid - sim_fine_origin) / sim_fine_km;
	return sim_fine_at(ivec2(floor(q))).r > 0.0 && tt_town(ivec2(floor((mid - world_min) / tile_km))) == 0;
}
// Whether a lane runs on the line between lot (index from world_min) and lot + dir.
bool sim_lane_between(vec2 lot, vec2 dir) {
	if (sim_track_between(lot, dir)) { return true; }
	bool here = sim_lot_house(lot);
	bool there = sim_lot_house(lot + dir);
	if (here || there) {
		return (here && (there || sim_lot_front(lot) == dir)) || (there && sim_lot_front(lot + dir) == -dir);
	}
	vec2 e = dir.yx; // along the line
	return (sim_lot_house(lot + e) && sim_lot_house(lot + e + dir)) || (sim_lot_house(lot - e) && sim_lot_house(lot - e + dir));
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

// What people_parcels.gdshader worked out for parcel `cell`, in the code
// of its red channel (SIM_P_*), its growth (the fine texel's blue) and the
// ground level at its middle; false outside the square it covers.
const int SIM_P_STATE = 3;     // sim_parcel: 0 not farmed, 1 fallow, 2 sown
const int SIM_P_OPEN = 4;      // people_crop_slab.gdshaderinc crop_open
const int SIM_P_BY_FARM = 8;   // next to a farmhouse lot (fenced)
const int SIM_P_NO_FIELD = 16; // sim_no_field
const int SIM_P_LANES = 32;    // people_crop_slab.gdshaderinc crop_lanes, five bits from here
// The sides (bits -x, -y, +x, +y, as SIM_P_LANES) where the slab runs on
// into a parcel of its field (sim_strip): baked into the B channel above
// the ground level (B = whole levels + 128 x sides, below 2048 and so exact
// in a half float), read back into the code from this bit.
const int SIM_P_JOIN = 2048;
bool sim_parcel_baked(vec2 cell, out int code, out float growth, out float level) {
	vec2 q = cell - floor((sim_crop_box.xy - world_min) / (tt_data_km() * 0.5) + 0.5);
	if (sim_parcel_n == 0 || any(lessThan(q, vec2(0.0))) || any(greaterThanEqual(q, vec2(float(sim_parcel_n))))) {
		return false;
	}
	vec4 t = texelFetch(sim_parcel_tex, ivec2(mod(cell, float(sim_parcel_n))), 0);
	float sides = floor((t.b + 0.5) / 128.0);
	code = int(t.r + 0.5) + int(sides) * SIM_P_JOIN;
	growth = t.g;
	level = t.b - sides * 128.0 + t.a;
	return true;
}

// The parcel `cell` (of side `size` km): 0 not farmed, 1 fallow, 2 sown;
// `f` is its fine texel. Each fine tile farms one block around its middle,
// as large as its field share but never more than SIM_BLOCK_MAX of it (a
// rounded square, with a little jitter for a ragged edge), so the farmland
// reads as calm blocks around the villages with pasture between them
// (round 17: blocks that filled their tiles ran together into one quilt).
// A field lot the player built is farmed all over, sown as its fine tile
// (fallow where nobody farms there); a parcel one of the player's roads
// crosses is not (sim_built).
const float SIM_BLOCK_MAX = 0.55;
int sim_parcel(vec2 cell, float size, out vec4 f) {
	vec2 mid = world_min + (cell + 0.5) * size;
	int built = sim_built(mid);
	vec2 q = (mid - sim_fine_origin) / sim_fine_km;
	f = sim_fine_at(ivec2(floor(q)));
	if ((built & SIM_B_ROAD) != 0) { return 0; }
	if ((built & SIM_B_FIELD) == 0) {
		if (f.r <= 0.0) { return 0; }
		vec2 d = abs(fract(q) - 0.5) * 2.0;
		float r = mix(max(d.x, d.y), length(d) * 0.7071, 0.5);
		if (r * r + 0.12 * (sim_hash(cell) - 0.5) >= min(f.r, SIM_BLOCK_MAX)) { return 0; }
	}
	vec3 strip = sim_strip(cell); // a strip lies fallow or sown as a whole
	if (sim_hash(strip.xy * 0.91 + strip.z * 7.3 + 17.3) >= f.g) { return 1; }
	return 2;
}
