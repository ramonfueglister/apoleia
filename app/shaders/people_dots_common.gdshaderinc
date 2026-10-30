// People dots, shared part: the people record texture and the placement
// rule. people_dots_prep.gdshader runs the rule once per person into a float
// texture (only when the people or the terrain view changed); the dot shader
// (people_dots.gdshaderinc) then only reads that texture.

#include "res://shaders/tile_terrain.gdshaderinc"

uniform sampler2DArray people_tex : filter_nearest, repeat_disable;
uniform int page_side = 64;
uniform float dot_km_per_m = 0.0238; // diorama scale (TileTerrain.DIORAMA_KM_PER_M), for the yards

const float DOT_CELL_HALF_KM = 12.5;    // half a 25 km sim cell
const float DOT_FINE_HALF_KM = 0.78125; // half a 1.5625 km village tile (sim/src/settle.rs)
const float DOT_VILLAGE_KM = 0.8;       // houses of a village within this radius
const float DOT_LOT_KM = 0.5;           // village houses on a grid of lots: a 15 m farmhouse (scripts/voxel/farmhouse.gd) with a lane round it, 2 x 2 field parcels
const float DOT_FAMILY_KM = 0.035;      // members of a household around its house
const float DOT_ROAD = 8192.0;          // sim/src/view.rs ROAD
const float DOT_AT_LOT = 12288.0;       // a farm the player placed (build_menu.gd): its house on the lot under rec.xy, not a village spot

uint dot_hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

vec2 dot_rand2(uint key, uint k) {
	uint a = dot_hash(key * 0x9e3779b9u + k * 0x632be5abu);
	uint b = dot_hash(a ^ 0x5bd1e995u);
	return vec2(float(a & 0xffffu), float(b & 0xffffu)) / 65535.0;
}

ivec2 dot_tile(vec2 p) {
	return ivec2(floor((p - world_min) / tile_km));
}

// The ground's level at p as the terrain draws it (tile_terrain.gdshader
// vertex): each tile cut along the diagonal whose corners are closer in
// level into two flat or sloped triangles, not a bilinear surface, so
// people, houses and crops stand on the ramps and not in them.
float dot_ground_level(vec2 p) {
	ivec2 t = dot_tile(p);
	vec4 k = tt_corners_cached(t);
	vec2 uv = (p - world_min) / tile_km - vec2(t);
	if (abs(k.x - k.z) <= abs(k.y - k.w)) {
		return uv.x >= uv.y ? k.x + (k.y - k.x) * uv.x + (k.z - k.y) * uv.y
			: k.x + (k.z - k.w) * uv.x + (k.w - k.x) * uv.y;
	}
	return uv.x + uv.y <= 1.0 ? k.x + (k.y - k.x) * uv.x + (k.w - k.x) * uv.y
		: k.z + (k.z - k.w) * (uv.x - 1.0) + (k.z - k.y) * (uv.y - 1.0);
}

// Record of a slot: slot = layer * page_side^2 + y * page_side + x, which is
// pixel (x, layer * page_side + y) of the prep texture.
vec4 dot_record(ivec2 px) {
	return texelFetch(people_tex, ivec3(px.x, px.y % page_side, px.y / page_side), 0);
}

// What the sim has of each person's household (ApoleiaPeople.people_looks,
// once a sim week, people_dots.gd): r its share of its need eaten (‰ / 4),
// g its flags (apoleia_sim::grain HOUSE_*, 128 when the sim knows it), by
// the same pixel as the record.
uniform sampler2D person_look_tex : filter_nearest, repeat_disable;
uniform bool has_person_looks = false;
const int DOT_LOOK_HARVEST = 4;
const int DOT_LOOK_SOWING = 8;
const int DOT_LOOK_KNOWN = 128;

// x the share of its need the person's household ate (1 when not known),
// y 1 while its farm's harvest or sowing still wants hands.
vec2 dot_person_look(ivec2 px) {
	if (!has_person_looks) {
		return vec2(1.0, 0.0);
	}
	ivec2 l = ivec2(texelFetch(person_look_tex, px, 0).rg * 255.0 + 0.5);
	if ((l.y & DOT_LOOK_KNOWN) == 0) {
		return vec2(1.0, 0.0);
	}
	return vec2(min(float(l.x) * 0.004, 1.0), (l.y & (DOT_LOOK_HARVEST | DOT_LOOK_SOWING)) != 0 ? 1.0 : 0.0);
}

// Where a member of a household at work on its fields stands, from where
// it stands at home: out on the lot's field parcels (DOT_LOT_KM), the same
// side of the house for the whole household (its key), side by side.
vec2 dot_field_offset(uint key, uint slot) {
	vec2 h = dot_rand2(key, 41u);
	vec2 m = dot_rand2(slot, 43u);
	float a = h.x * 6.2831853 + (m.x - 0.5) * 0.7;
	return vec2(cos(a), sin(a)) * (0.15 + 0.07 * m.y);
}

// First spot on land among up to 16 hashed tries in an area around `c`:
// a square of half-width `r` (r > 0) or a disk of radius -r, eight tries in
// the area, then eight in twice the area.
vec2 dot_land(vec2 c, float r, uint key) {
	vec2 p = c;
	for (uint k = 0u; k < 16u; k++) {
		vec2 h = dot_rand2(key, k);
		float wide = k < 8u ? 1.0 : 2.0;
		if (r > 0.0) {
			p = c + (h - 0.5) * 2.0 * r * wide;
		} else {
			// disk, denser in the middle
			float a = h.x * 6.2831853;
			p = c + vec2(cos(a), sin(a)) * sqrt(h.y) * -r * wide;
		}
		if (tt_water(dot_tile(p)) == W_LAND) {
			return p;
		}
	}
	return p;
}

// Village site: of 16 hashed spots in the village tile the best one on land,
// by cropland and open land (cover_tex: forest, dry, crop, wetland), so
// villages sit at fields and not in the woods or marshes. A tile without
// land (the sim picked it without the fine land data) falls back to land in
// the whole cell.
vec2 dot_village(vec2 c, float r, uint key) {
	vec2 best = c;
	float score = -1.0;
	for (uint k = 0u; k < 16u; k++) {
		vec2 p = c + (dot_rand2(key, k) - 0.5) * 2.0 * r;
		if (tt_water(dot_tile(p)) != W_LAND) {
			continue;
		}
		vec4 cov = tt_cover(p);
		float s = cov.b + 0.4 * (1.0 - cov.r) - 0.5 * cov.a + 0.05 * dot_rand2(key, k + 16u).x;
		if (s > score) {
			score = s;
			best = p;
		}
	}
	return score < 0.0 ? dot_land(c, DOT_CELL_HALF_KM, key) : best;
}

// Centre of the village lot under p (world km). Lots, like the field
// parcels (sim_fields.gdshaderinc), lie on the terrain's tile grid from
// world_min, so a farmhouse and its fields sit on whole tiles.
vec2 dot_lot(vec2 p) {
	return world_min + (floor((p - world_min) / DOT_LOT_KM) + 0.5) * DOT_LOT_KM;
}

// A lot a farmhouse can stand on, by `need`: 0 land (or by a river); 1 also
// open level ground, no ramp and no wood (the lot a whole tile, or 2 x 2
// quarter tiles up close, tile_terrain.gdshaderinc sub_tiles, all flat at
// one level); 2 also no ground rising just south of it, which would hide
// the house from the camera (it always looks north). On the coarser levels
// further out every lot on land counts.
// the lots round a lot: the eight next to it, then the sixteen beyond
const ivec2 DOT_RING[24] = ivec2[](ivec2(1, 0), ivec2(1, 1), ivec2(0, 1), ivec2(-1, 1), ivec2(-1, 0), ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
	ivec2(2, 0), ivec2(2, 1), ivec2(2, 2), ivec2(1, 2), ivec2(0, 2), ivec2(-1, 2), ivec2(-2, 2), ivec2(-2, 1),
	ivec2(-2, 0), ivec2(-2, -1), ivec2(-2, -2), ivec2(-1, -2), ivec2(0, -2), ivec2(1, -2), ivec2(2, -2), ivec2(2, -1));
bool dot_lot_ok(vec2 lot, int need) {
	bool coarse = tile_km > DOT_LOT_KM * 1.01;
	int n = coarse ? 1 : int(round(DOT_LOT_KM / tile_km));
	float lo = 1e9;
	float hi = -1e9;
	for (int j = 0; j < n; j++) {
		for (int i = 0; i < n; i++) {
			ivec2 t = dot_tile(lot + (vec2(float(i), float(j)) + 0.5 - float(n) * 0.5) * tile_km);
			int water = tt_water(t);
			if (water != W_LAND && water != W_RIVER) { return false; }
			int g = tt_ground(t);
			if (need >= 1 && (g == G_FOREST || g == G_CONIFER || g == G_ROCK || g == G_SNOW)) { return false; }
			vec4 k = round(tt_corners_cached(t));
			lo = min(lo, min(min(k.x, k.y), min(k.z, k.w)));
			hi = max(hi, max(max(k.x, k.y), max(k.z, k.w)));
		}
	}
	if (need == 0 || coarse) { return true; }
	if (hi - lo > 0.01) { return false; }
	if (need == 2) {
		for (int i = -1; i <= n; i++) {
			vec4 k = round(tt_corners_cached(dot_tile(lot + (vec2(float(i), float(n)) + 0.5 - float(n) * 0.5) * tile_km)));
			if (max(max(k.x, k.y), max(k.z, k.w)) > hi + 0.01) { return false; }
		}
	}
	return true;
}

// The farmhouse on the lot under p (people_houses.gdshader), the same for
// everything on that lot: its quarter turn and mirror as one matrix on the
// local x, z, and in `size_tint` its size and brightness factors.
mat2 dot_house_turn(vec2 p, out vec2 size_tint) {
	ivec2 lot = ivec2(floor((p - world_min) / DOT_LOT_KM));
	uint key = dot_hash(uint(lot.x) * 0x9e3779b1u ^ uint(lot.y) * 0x85ebca77u);
	vec2 r = dot_rand2(key, 7u);
	// on the tile grid, like the town houses; the front (+z, door and path)
	// to the camera on half the lots, a flank on the others, never the
	// back (sim_fields.gdshaderinc sim_lot_front)
	float a = (r.x < 0.5 ? 0.0 : r.x < 0.75 ? 1.0 : 3.0) * 1.5707963;
	float m = dot_rand2(key, 8u).x < 0.5 ? -1.0 : 1.0;
	size_tint = vec2(0.9 + 0.2 * r.y, 0.94 + 0.12 * r.y); // its path just reaches the lane round the lot
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * mat2(vec2(m, 0.0), vec2(0.0, 1.0));
}

// Where the person in `slot` stands: (offset x, offset z) in km from the
// record's anchor and the height in levels. Records: sim/src/view.rs. A house
// record (`house`) stands on the household's house spot itself, without the
// family spread around it.
vec3 dot_place(vec4 rec, uint slot, bool house) {
	uint key = (uint(rec.w) >> 8u) & 0x3fffu;
	vec2 p;
	bool village = false;
	// a house record with a negative village code is a farm being built
	// (people_houses.gdshader): it stands where its house will
	float code = house ? abs(rec.z) : rec.z;
	if (code < 0.0) {
		// city: the household's house in the city disk
		p = dot_land(rec.xy, rec.z, key);
	} else if (code >= DOT_AT_LOT) {
		// a farm the player placed: exactly on the lot chosen (rec.xy any
		// point on it), so it stands where the build menu showed its ghost
		// (scripts/voxel/farmhouse_ghost.gd); its family round it as in a village
		p = dot_lot(rec.xy);
		village = true;
	} else if (code >= DOT_ROAD) {
		// on the road: anywhere on land in the current cell
		p = dot_land(rec.xy, DOT_CELL_HALF_KM, key);
	} else {
		// the household's village tile (the sim picks it), then its house
		uint vkey = dot_hash((uint(code) - 1u) * 0x2545f491u);
		vec2 v = dot_village(rec.xy, DOT_FINE_HALF_KM, vkey);
		p = dot_land(v, -DOT_VILLAGE_KM, key);
		// on its lot, so houses stand side by side in rows instead of
		// cutting into each other (two on one lot look like one house)
		// (a river is a narrow band on the land tile, so a lot by it counts);
		// the best lot of its own and the two rings round it (each from a
		// hashed start): open, level and in view, else open and level, as a
		// ramp would cut through the farmhouse and its yard
		vec2 lot = dot_lot(p);
		if (dot_lot_ok(lot, 0)) {
			p = lot;
			int start = int(dot_hash(key ^ 0x51ed27u) & 7u);
			bool found = false;
			for (int need = 2; need >= 1 && !found; need--) {
				for (int i = -1; i < 24; i++) {
					int r = i < 8 ? (start + i) & 7 : 8 + ((start * 2 + i) & 15);
					vec2 next = i < 0 ? lot : lot + vec2(DOT_RING[r]) * DOT_LOT_KM;
					if (dot_lot_ok(next, need)) {
						p = next;
						found = true;
						break;
					}
				}
			}
		}
		village = true;
	}
	// the family around its house, one spot per person; in a village the
	// house is drawn (people_houses.gdshader, scripts/voxel/farmhouse.gd), so
	// a quarter of them are in the yard (in front or at the garden beds
	// behind), a third on the lane round the lot, the others out in the
	// fields; never on the fence or in a row
	if (!house) {
		vec2 h = dot_rand2(slot, 99u);
		if (village) {
			vec2 h2 = dot_rand2(slot, 98u);
			vec2 st;
			mat2 turn = dot_house_turn(p, st);
			float m_km = dot_km_per_m * st.x;
			vec2 local; // metres in the farmhouse's frame, front towards +z
			if (h.y < 0.25) {
				// in front of the house (clear of the well, farmhouse.gd _well) or behind it
				local = h2.y < 0.5 ? vec2(h.x * 10.25 - 6.0, 3.9 + 1.9 * h2.x) : vec2((h.x - 0.5) * 7.0, -4.0 - 1.6 * h2.x);
			} else if (h.y < 0.6) {
				// anywhere along the lane, a square round the lot's middle
				float half_lot = DOT_LOT_KM * 0.5 / m_km;
				float along = (h.x * 2.0 - 1.0) * half_lot;
				float across = (h2.x - 0.5) * 0.02 / m_km;
				int side = int(h2.y * 4.0);
				local = side == 0 ? vec2(along, half_lot + across) : side == 1 ? vec2(along, -half_lot + across)
					: side == 2 ? vec2(half_lot + across, along) : vec2(-half_lot + across, along);
			} else {
				float a = h.x * 6.2831853;
				local = vec2(cos(a), sin(a)) * (12.0 + 8.0 * h2.x);
			}
			p += turn * local * m_km;
		} else {
			p += (h - 0.5) * 2.0 * DOT_FAMILY_KM;
		}
	}
	// the dot stands on the ground as the terrain draws it
	return vec3(p - rec.xy, dot_ground_level(p));
}
