// Where a tree or house slot stands (tile_props.gdshader). Shared by the
// per-frame placement pass (tile_prop_prep.gdshader) and, as a fallback, the
// prop vertex shader. Needs tile_terrain.gdshaderinc first.

// the farms' fields and lots (set on the placement pass by people_dots.gd)
#include "res://shaders/sim_fields.gdshaderinc"

// The ground level at uv (0..1) in tile t with corner levels c, on the
// tile's own triangles (split as in tile_terrain.gdshader).
float tt_level_in_tile(ivec2 t, vec4 c, vec2 uv) {
	int cut = tt_coast_cut(t);
	if (cut >= 0 ? (cut & 1) == 1 : abs(c.x - c.z) <= abs(c.y - c.w)) {
		return uv.x >= uv.y
			? c.x + (c.y - c.x) * uv.x + (c.z - c.y) * uv.y
			: c.x + (c.w - c.x) * uv.y + (c.z - c.w) * uv.x;
	}
	return uv.x + uv.y <= 1.0
		? c.x + (c.y - c.x) * uv.x + (c.w - c.x) * uv.y
		: c.z + (c.w - c.z) * (1.0 - uv.x) + (c.y - c.z) * (1.0 - uv.y);
}

// Up close every STREET_EVERY-th row and CROSS_EVERY-th column of a town is a
// street a whole quarter tile wide where lots stand on both sides of it (the
// strip in front of each lot hid behind the roofs of the next row, Kritik r9;
// at the town's edge the street would be an empty paved square). The terrace
// stays, paved, and holds no lot (tile_props.gdshader, code + STREET_CODE).
const int CROSS_EVERY = 5;
const int STREET_EVERY = 3;
const float STREET_CODE = 8.0;

// bit 0: a cross street (runs north-south), bit 1: a row street (east-west)
int tt_sub_street_dir(ivec2 t) {
	if (cp_kind(t) != CP_NONE) { return 0; } // a plan draws its own streets (cp_street)
	bool cross = ((t.x % CROSS_EVERY) + CROSS_EVERY) % CROSS_EVERY == 0
		&& tt_sub_lot(t - ivec2(1, 0)) && tt_sub_lot(t + ivec2(1, 0));
	bool row = ((t.y % STREET_EVERY) + STREET_EVERY) % STREET_EVERY == 0
		&& tt_sub_lot(t - ivec2(0, 1)) && tt_sub_lot(t + ivec2(0, 1));
	return (cross ? 1 : 0) + (row ? 2 : 0);
}
bool tt_sub_street(ivec2 t) {
	return tt_sub_street_dir(t) != 0;
}

// Up close olive groves stand in the open land around the towns of the warm
// south, on every ramp and every other flat 0.5 km tile within OLIVE_RING
// data tiles of a town (Kritik r9: the cleared ring was a third to half bare
// lawn), in rows. Code: a broadleaf of size OLIVE_SIZE (tile_props.gdshader
// tints its crown).
const int OLIVE_RING = 2;
const float OLIVE_SIZE = 0.6;

bool tt_olive_grove(ivec2 dt, bool ramp) {
	if (!ramp && tt_hash(vec2(dt) * 0.71 + 3.3) >= 0.5) { return false; }
	for (int j = -OLIVE_RING; j <= OLIVE_RING; j++) {
		for (int i = -OLIVE_RING; i <= OLIVE_RING; i++) {
			if ((tt_data_cell(dt + ivec2(i, j)) >> 2) >= 2) { return true; }
		}
	}
	return false;
}

// Up close single trees and bushes stand about the open land, as in Urbek
// (Ramon 29.10.2026: whole hillsides and pastures of bare lawn): on the
// ramps, where no field ever lies, and on the parcels the farms leave as
// pasture (sim_parcel), never on a sown or fallow parcel or a farmhouse's
// lot. Beyond the crops (SIM_CROPS_KM) only the ramps keep theirs.
const float SCATTER_TREE = 0.09; // share of the slots with a tree
const float SCATTER_BUSH = 0.0; // and with a bush (s4: little trees read as saplings, sizes all over the place)
bool tt_scatter_free(vec2 at, bool ramp, bool field) {
	if (!sim_map_on || sim_fine_n == 0) { return !field; }
	if (sim_house_lot(at)) { return false; }
	if (ramp) { return true; }
	if (sim_view_km > SIM_CROPS_KM) { return false; }
	float size = tt_data_km() * 0.5;
	vec4 f;
	return sim_parcel(floor((at - world_min) / size), size, f) == 0;
}

// One slot of tile t: xy the spot in the tile (0..1), z its level, w the code:
// < 0 empty; trees kind + 0.25 * size (0.7..1); houses the town class (plus
// STREET_CODE on a street block up close), or on a city plan's parcel
// CP_CODE + its kind.
vec4 tt_prop_place(ivec2 t, int slot, int slots, bool house) {
	float code = -1.0;
	int cell = tt_cell(t);
	int water = cell & 3;
	int town = cell >> 2;
	// the city plan's parcel of this slot: up close the quarter itself, on
	// the 0.5 km tiles the slot's quarter of a tile any of whose quarters
	// has a plan (tile_terrain.gd lists their lots)
	int plan = CP_NONE;
	bool planned = house && cp_planned_tile(t);
	if (planned) {
		plan = sub_tiles ? cp_kind(t) : slots == 4 ? cp_kind(t * 2 + ivec2(slot % 2, slot / 2)) : CP_LAND;
	}
	vec2 centre = tt_tile_center(t);
	float r0 = tt_hash3(vec3(vec2(t), float(slot) * 3.17));
	float r1 = tt_hash3(vec3(vec2(t) + 11.3, float(slot) * 1.91));
	float r2 = tt_hash3(vec3(vec2(t) - 4.7, float(slot) * 5.03));
	// houses also on a river tile where the bake put a town there (from 4 km
	// tiles: tools/build_tile_terrain.py TOWN_ON_RIVER_KM)
	bool show = water == W_LAND || (house && water == W_RIVER && town > 0);
	float edge_size = 1.0;
	vec2 uv;
	if (house) {
		// house blocks on the street grid of the town tile (house_grid^2 = slots)
		int side = int(ceil(sqrt(float(slots))));
		float share = tt_house_share(town);
		if (planned) {
			// a plan's lot or its terrace; the tombs outside stand on the land
			show = show && slot < 4 && (cp_on_terrace(plan) || cp_has_lot(plan));
			show = show && (!sub_tiles || slot == 0);
			uv = sub_tiles ? vec2(0.5) : (vec2(float(slot % 2), float(slot / 2)) + 0.5) * 0.5;
		} else if (sub_tiles) {
			// one house on a flat quarter (a hill town steps up in terraces;
			// tt_sub_house decides which quarters hold one)
			// (in towns on ramps too, on a terrace: tile_props.gdshader)
			show = show && slot == 0 && tt_sub_lot(t);
			uv = vec2(0.5); // the lots line up into streets
		} else {
			// beyond the quarter tiles the villages' ring keeps no houses (Kritik
			// r8: lone lots on the wheat around Rome at 22 km)
			int count = town >= 2 ? max(int(round(share * float(slots))), 1) : 0;
			show = show && slot < count;
			show = show && !(town == 3 && tt_hash3(vec3(vec2(t), float(slot) + 9.1)) < 0.06);
			int cell_k = town == 3 ? slot : (slot * 7 + int(tt_hash(vec2(t)) * float(slots))) % slots;
			vec2 sub = vec2(float(cell_k % side), float(cell_k / side));
			uv = (sub + 0.5) / float(side);
		}
		// the whole house off the landmark blocks (its centre was not enough:
		// houses reached into the Pantheon)
		show = show && !tt_near_landmark(world_min + (vec2(t) + uv) * tile_km, 0.45 * tile_km / (sub_tiles ? 1.0 : float(side)));
	} else {
		show = show && (town == 0 || tt_sub_garden(t, town));
		// no trees on a plan's streets, lots or tombs (its gardens bring theirs)
		show = show && !(sub_tiles && cp_kind(t) != CP_NONE && cp_kind(t) != CP_LAND);
		uv = vec2(0.5);
	}
	if (!house && show) {
		// slots on a jittered grid, so a dense wood covers the tile evenly
		int side = int(ceil(sqrt(float(slots))));
		vec2 g = vec2(float(slot % side), float(slot / side));
		uv = (g + 0.2 + 0.6 * vec2(r1, r2)) / float(side) * 0.9 + 0.05;
		// trees stand on the forest tiles (and forest halves of a split tile),
		// single ones now and then on open grassland
		vec2 at = world_min + (vec2(t) + uv) * tile_km;
		int land = tt_ground_at(t, uv);
		bool wood = land == G_FOREST || land == G_CONIFER;
		bool open = land == G_MEADOW || land == G_DRY_GRASS || land == G_ALPINE || land == G_SCRUB;
		// open land: small groves of a few trees around one spot of the data
		// tile, as in Urbek (no single trees: they read as specks)
		bool field = land == G_FIELD;
		// a town's garden quarter: cypresses, stone pines and a broadleaf or
		// two inside its hedge, clear of the landmarks
		bool garden = town > 0;
		if (garden) {
			uv = (g + 0.3 + 0.4 * vec2(r1, r2)) / float(side) * 0.7 + 0.15;
			at = world_min + (vec2(t) + uv) * tile_km;
			wood = false;
			open = false;
			field = false;
		}
		bool grove = false;
		bool olive = false;
		bool ramp = false;
		if (sub_tiles) {
			vec4 q = tt_corners_cached(t);
			ramp = max(max(q.x, q.y), max(q.z, q.w)) - min(min(q.x, q.y), min(q.z, q.w)) > 0.01;
		}
		if (open && sub_tiles) {
			ivec2 dt = sub_tiles ? t >> ivec2(1) : t;
			vec2 here = world_min + (vec2(t) + 0.5) * tile_km;
			olive = tt_latitude(here) < 44.5 && tt_height_m(here, height_lod) < 700.0 && tt_olive_grove(dt, ramp);
		}
		if (olive) {
			// in rows: the slots on a plain grid
			uv = (g + 0.5) / float(side) * 0.9 + 0.05;
		} else if (open || field) {
			ivec2 dt = sub_tiles ? t >> ivec2(1) : t;
			vec2 duv = sub_tiles ? (vec2(t & ivec2(1)) + uv) * 0.5 : uv;
			float gh = tt_hash(vec2(dt) * 0.613 + 7.1);
			vec2 spot = 0.3 + 0.4 * vec2(tt_hash(vec2(dt) + 1.7), tt_hash(vec2(dt) - 2.9));
			grove = gh < (open ? 0.07 : 0.03) && length(duv - spot) < 0.3; // three to seven trees
		}
		// up close a wood keeps the density of the 0.5 km tiles (about 2 of
		// the 4 slots of a quarter), so the ground shows between the crowns
		bool thin = sub_tiles && tt_hash3(vec3(vec2(t) * 0.37, float(slot) + 0.5)) > 0.6;
		float rs = tt_hash3(vec3(vec2(t) * 0.91, float(slot) + 4.4));
		bool scatter = sub_tiles && (open || field) && !olive && !grove && rs < SCATTER_TREE + SCATTER_BUSH
			&& tt_scatter_free(at, ramp, field);
		bool bush = scatter && rs >= SCATTER_TREE;
		bool planted = garden && rs < 0.6 && !tt_near_landmark(at, 0.06);
		show = show && (wood || grove || olive || scatter || planted) && (olive || scatter || planted || !thin);
		// a lone tree smaller than in a wood, about as tall as a one-storey
		// house, as Urbek's (Ramon on s3: Urbek's trees are much smaller
		// against its fields and houses); kept in the middle of its quarter,
		// clear of the fields round it
		if (scatter) { uv = 0.5 + (uv - 0.5) * 0.4; }
		edge_size = olive ? OLIVE_SIZE : bush ? mix(0.25, 0.35, r0) : scatter ? 0.75 : planted ? 0.75 : mix(0.85, 1.0, r0);
		float h = tt_height_m(at, height_lod);
		float lat = tt_latitude(at);
		show = show && h < 1400.0;
		float conifer_p = land == G_CONIFER ? 0.9 : clamp((lat - 50.0) / 4.0, 0.0, 1.0);
		// stone pines and cypresses in the warm lowlands, more of them in open land
		bool south = lat < 44.5 && h < 700.0;
		float pine_p = south ? (wood ? 0.12 : 0.45) : 0.0;
		int kind = olive || bush ? 0
			: planted ? (r1 < 0.4 ? 2 : r1 < 0.65 ? 4 : 0)
			: r0 < conifer_p ? 1
			: (south && r0 < conifer_p + pine_p) ? 4
			: (south && r0 < conifer_p + pine_p + 0.1) ? 2 : 0;
		code = float(kind) + 0.25 * edge_size;
	}
	vec4 c = show ? tt_corners_cached(t) : vec4(0.0);
	if (house) { code = planned ? CP_CODE + float(plan) : float(town) + (sub_tiles && show && tt_sub_street(t) ? STREET_CODE : 0.0); }
	if (!show) { return vec4(0.0, 0.0, 0.0, -1.0); }
	// on the tile's own triangles (split as in tile_terrain.gdshader), so
	// trees stand on steep two-level tiles too instead of leaving bare holes
	// nothing in the wet half of a coast cut tile; the dry half keeps its split
	int cut = tt_coast_cut(t);
	if (cut >= 0) {
		vec2 tip = vec2(float(cut == 1 || cut == 2), float(cut >= 2));
		if (abs(uv.x - tip.x) + abs(uv.y - tip.y) < 1.1) { return vec4(0.0, 0.0, 0.0, -1.0); }
	}
	return vec4(uv, tt_level_in_tile(t, c, uv), code);
}
