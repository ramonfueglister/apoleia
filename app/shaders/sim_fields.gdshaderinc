// Where the grain fields lie (sim/godot/src/grain_map.rs, the fine layer):
// shared by the terrain's field colours (sim_map.gdshaderinc) and the crops
// standing on them (people_crops.gdshader), so both agree parcel for parcel.
//
// Fine texel: R share of the tile under fields, G sown share of them, B
// growth (0 bare … 1 ripe), A the ways people wear and the markets (sim_way).

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
// terrain's fragment stage (the village lanes then, sim_fields) crashed Apple's Metal
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

// The ways people wear walking (S127, Ramon 30.10.2026: „jede Strasse
// entsteht emergent durch das Durchlaufen von Leuten. Nach einem Durchgang
// leicht sichtbarer Weg, später immer breiter“), from the way layer
// (sim/godot/src/grain_map.rs): per fine tile the neighbours its way leads
// to, as walked (R, bit k = SIM_DIRS[k]), and its level 0 … 7 (G). A way
// with two ends in a tile bends from the middle of the one edge over the
// tile's middle to the other (a quadratic curve, so the ways join smoothly
// from tile to tile); where it ends or forks, each end runs straight to
// the middle. Each farmhouse of a tile with a way walks to that way from
// its gate (sim_lot_front) along the lanes round the lots (sim_lane): the
// faintest way, as the house's own walks wear it. Half width per level, km
// (sim_ways keeps it ~1.5 px at least).
uniform sampler2D sim_way_tex : filter_nearest, repeat_disable;
// (row, col) steps as grain.rs DIRS, here as (x = col, y = row)
const ivec2 SIM_DIRS[8] = ivec2[](ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(-1, 0), ivec2(1, 0), ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1));
const float SIM_WAY_KM[8] = float[](0.0, 0.006, 0.009, 0.013, 0.018, 0.024, 0.032, 0.042);

// Links and level of window tile t, zero outside the window.
ivec2 sim_way_at(ivec2 t) {
	if (t.x < 0 || t.y < 0 || t.x >= sim_fine_n || t.y >= sim_fine_n) { return ivec2(0); }
	vec2 w = texelFetch(sim_way_tex, t, 0).rg;
	return ivec2(int(w.r * 255.0 + 0.5), int(w.g * 255.0 + 0.5));
}

// Distance from p to the quadratic curve a-b-c (all in tile units), sampled.
float sim_curve(vec2 p, vec2 a, vec2 b, vec2 c) {
	float best = 1e9;
	vec2 last = a;
	for (int k = 1; k <= 6; k++) {
		float t = float(k) / 6.0;
		vec2 q = mix(mix(a, b, t), mix(b, c, t), t);
		vec2 e = q - last;
		float u = clamp(dot(p - last, e) / max(dot(e, e), 1e-9), 0.0, 1.0);
		best = min(best, length(p - last - e * u));
		last = q;
	}
	return best;
}

float sim_segment_to(vec2 p, vec2 a, vec2 b) {
	vec2 e = b - a;
	return length(p - a - e * clamp(dot(p - a, e) / max(dot(e, e), 1e-9), 0.0, 1.0));
}

// How far p (world km) lies outside the nearest way of the worn network,
// km (negative inside it), and that way's level; 1e9 and 0 without one
// near. Without the farmhouses' own lanes (sim_way), so the houses can keep
// off the network (people_dots_common.gdshaderinc dot_lot_way_free) and the
// crops and trees too (people_parcels.gdshader, tile_props.gdshaderinc).
vec2 sim_way_main(vec2 p) {
	if (sim_fine_n == 0) { return vec2(1e9, 0.0); }
	vec2 q = (p - sim_fine_origin) / sim_fine_km;
	ivec2 t = ivec2(floor(q));
	float best = 1e9;
	float level = 0.0;
	// the ways of the tile under p and of its neighbours, which reach to
	// the tile's edges and corners
	for (int k = 0; k < 9; k++) {
		ivec2 c = t + ivec2(k % 3 - 1, k / 3 - 1);
		ivec2 w = sim_way_at(c);
		if (w.y == 0 || w.x == 0) { continue; }
		vec2 mid = vec2(c) + 0.5;
		int ends = bitCount(w.x);
		float d = 1e9;
		if (ends == 2) {
			int i = findLSB(w.x);
			int j = findMSB(w.x);
			d = sim_curve(q, mid + vec2(SIM_DIRS[i]) * 0.5, mid, mid + vec2(SIM_DIRS[j]) * 0.5);
		} else {
			for (int j = 0; j < 8; j++) {
				if ((w.x & (1 << j)) != 0) { d = min(d, sim_segment_to(q, mid, mid + vec2(SIM_DIRS[j]) * 0.5)); }
			}
		}
		float e = d * sim_fine_km - SIM_WAY_KM[min(w.y, 7)];
		if (e < best) { best = e; level = float(min(w.y, 7)); }
	}
	return vec2(best, level);
}

// Whether a worn way runs across the parcel of side `size` (km) with its
// middle at `mid`: its edge nearer the middle than 0.6 parcel, so a corner
// cut counts too. Such a parcel carries no crop, flock or paddock
// (people_parcels.gdshader, people_crop_slab.gdshaderinc crop_slab_under).
bool sim_way_parcel(vec2 mid, float size) {
	return sim_way_main(mid).x < size * 0.6;
}

// Where the way of window tile t passes its middle (tile units): the
// middle itself, or the middle of its curve where it has two ends.
vec2 sim_way_hub(ivec2 t, int links) {
	vec2 mid = vec2(t) + 0.5;
	if (bitCount(links) != 2) { return mid; }
	vec2 a = mid + vec2(SIM_DIRS[findLSB(links)]) * 0.5;
	vec2 c = mid + vec2(SIM_DIRS[findMSB(links)]) * 0.5;
	return 0.25 * (a + c) + 0.5 * mid;
}

// How far p lies from a farmhouse's lane (km): from its gate along the
// lanes round the lots (the lot lines, where no farmhouse stands) to the
// lot corner nearest the hub of its tile's way, then into the hub. Straight
// to the hub it ran over the neighbours' houses (Ramon, 30.10.2026: „ob
// Strassen Gebäude etc. durchschneiden“).
float sim_lane(vec2 p, vec2 gate, vec2 front, vec2 hub) {
	vec2 corner = world_min + round((hub - world_min) / sim_lot_km) * sim_lot_km;
	vec2 bend = front.y != 0.0 ? vec2(corner.x, gate.y) : vec2(gate.x, corner.y);
	return min(min(sim_segment_to(p, gate, bend), sim_segment_to(p, bend, corner)), sim_segment_to(p, corner, hub));
}

// How far p (world km) lies outside the nearest way, km (negative inside
// it), and that way's level: the worn network (sim_way_main) and, up close,
// the lane of each farmhouse of the tile under p to that network.
vec2 sim_way(vec2 p) {
	vec2 w = sim_way_main(p);
	float best = w.x;
	float level = w.y;
	if (sim_fine_n == 0) { return w; }
	ivec2 t = ivec2(floor((p - sim_fine_origin) / sim_fine_km));
	ivec2 here = sim_way_at(t);
	// the farmhouses whose lots lie in the tile (up to 4 x 4 of them)
	if (sim_lots_n > 0 && sim_view_km <= SIM_CROPS_KM && here.y > 0 && here.x != 0) {
		vec2 hub = sim_fine_origin + sim_way_hub(t, here.x) * sim_fine_km;
		vec2 lo_km = sim_fine_origin + vec2(t) * sim_fine_km;
		vec2 lo = floor((lo_km - world_min) / sim_lot_km);
		for (int k = 0; k < 16; k++) {
			vec2 lot = lo + vec2(float(k % 4), float(k / 4));
			vec2 at = world_min + (lot + 0.5) * sim_lot_km;
			bool house = sim_house_lot(at); // the fetch first, not behind the || (Metal, sim_lot_mask)
			vec2 in_tile = (at - lo_km) / sim_fine_km;
			if (!house || any(lessThan(in_tile, vec2(0.0))) || any(greaterThanEqual(in_tile, vec2(1.0)))) { continue; }
			vec2 front = sim_lot_front(lot);
			float e = sim_lane(p, at + front * sim_lot_km * 0.5, front, hub) - SIM_WAY_KM[1];
			if (e < best) { best = e; level = 1.0; }
		}
	}
	return vec2(best, level);
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
