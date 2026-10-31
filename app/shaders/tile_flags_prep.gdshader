// Tile-local terrain flags, evaluated for two pixels per drawn tile instead
// of once per mesh vertex. The two RGBA16F pixels contain only integers up
// to 2047 (11 bits), which half floats represent exactly. Geometry, palette
// and landscape rules are unchanged. The unused part of the fixed-size
// viewport skips the tile queries when the drawn patch is small.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/coast_steps.gdshaderinc"

uniform ivec2 flags_origin;
uniform int flags_n = 0;
const ivec2 SIDE[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));

// A land tile with the sea on all four sides: a one tile island gets no
// light lagoon ring (a big pale square around a speck of land).
bool lone_land(ivec2 t) {
	for (int k = 0; k < 4; k++) {
		if (tt_water(t + SIDE[k]) != W_SEA) { return false; }
	}
	return true;
}

void fragment() {
	ivec2 pixel = ivec2(FRAGCOORD.xy);
	ivec2 q = ivec2(pixel.x / 2, pixel.y);
	if (q.x >= flags_n || q.y >= flags_n) {
		COLOR = vec4(0.0);
	} else {
		ivec2 tile = flags_origin + q;
		int part = 0; // cache the top; the vertex stage removes top-only flags for walls
		int cell = tt_cell(tile);
		int water = cell & 3;
		int nc[4];
		for (int k = 0; k < 4; k++) { nc[k] = tt_cell(tile + SIDE[k]); }
		int lake_cut = !sub_tiles && !water_lines && water == W_LAKE && tile_km < CONTOUR_KM ? tt_lake_corner_cut(tile, nc) : -1;
		if (lake_cut >= 0) { water = W_LAND; }
		int cut = lake_cut >= 0 ? lake_cut : tile_km >= CONTOUR_KM ? -1 : tt_coast_cut_nb(tile, cell, nc);
		float coast;
		int shore_lake;
		int ground_bits;
		int shore_sides;
		int side_bits;
		// coast flags: land next to the sea gets a beach, sea next to land a lagoon tint
		coast = 0.0;
		// sea tile: bit k = land across side k, bit 4 + k = land at corner k only;
		// bits 8 + k and 12 + k: that land is open country dry up to the edge (not
		// the wet half of a coast cut, a river mouth or a town's quay), so sand
		// can lie at its foot
		int land_sides = 0;
		bool lake_near = water == W_LAKE;
		for (int k = 0; k < 4; k++) {
			int n1 = nc[k] & 3;
			lake_near = lake_near || n1 == W_LAKE;
			int n2 = tt_water(tile + SIDE[k] * 2);
			if (water == W_SEA) {
				if (n1 != W_SEA && !lone_land(tile + SIDE[k])) { land_sides |= 1 << k; }
			} else {
				if (n1 == W_SEA) { coast = 1.0; }
				else if (n2 == W_SEA) { coast = max(coast, 0.45); }
			}
		}
		if (water == W_SEA) {
			for (int k = 0; k < 4; k++) {
				int a = (k + 3) & 3; // the sides at corner k: k - 1 and k
				ivec2 d = tile + SIDE[a] + SIDE[k];
				if ((land_sides & ((1 << a) | (1 << k))) == 0 && tt_water(d) != W_SEA && !lone_land(d)) { land_sides |= 16 << k; }
			}
			for (int k = 0; k < 4; k++) {
				if ((land_sides & (1 << k)) != 0 && nc[k] < 8 && (nc[k] & 3) == W_LAND && tt_coast_cut(tile + SIDE[k]) < 0) { land_sides |= 256 << k; }
				ivec2 d = tile + SIDE[(k + 3) & 3] + SIDE[k];
				int dc = (land_sides & (16 << k)) != 0 ? tt_cell(d) : W_SEA;
				if (dc < 8 && (dc & 3) == W_LAND && tt_coast_cut(d) < 0) { land_sides |= 4096 << k; }
			}
			coast = land_sides != 0 ? 1.0 : 0.0;
		}
		shore_lake = lake_near ? 1 : 0;
		int ground = lake_cut >= 0 ? tt_ground(tile + SIDE[(lake_cut + 1) & 3]) : tt_ground(tile);
		int ground_alt = ground;
		int ground_tip = -1;
		// (on the map the landscapes' borders are drawn soft: contour_land_soft)
		if (water != W_SEA && water != W_LAKE && part == 0 && cut < 0 && tile_km < CONTOUR_KM) {
			ground_tip = tt_ground_cut(tile, ground, ground_alt);
		}
		ground_bits = ground | (ground_alt << 4) | ((ground_tip + 1) << 8);
		shore_sides = water == W_SEA ? land_sides : 0; // the shallows of a sea tile measure from the land
		int wall_sides = 0;
		int river_sides = 0;
		// (a city plan draws its own wall: city_plan.gdshaderinc)
		bool core = water == W_LAND && (cell >> 2) == 3 && !cp_planned_tile(tile);
		for (int k = 0; k < 4; k++) {
			if (water != W_SEA && (nc[k] & 3) == W_SEA) { shore_sides |= 1 << k; }
			if (core && ((nc[k] & 3) != W_LAND || (nc[k] >> 2) < 2)) { wall_sides |= 1 << k; }
			// quarter tiles draw the river of their data tile
			int rn = sub_tiles ? tt_data_cell((tile >> ivec2(1)) + SIDE[k]) : nc[k];
			if (water == W_RIVER && (rn & 3) != W_LAND) { river_sides |= 1 << k; }
		}
		side_bits = wall_sides | (river_sides << 4);
		if (water != W_SEA && part == 0) {
			for (int k = 0; k < 4; k++) {
				int a = (k + 3) & 3; // the sides at corner k: k - 1 and k
				bool open = (shore_sides & ((1 << a) | (1 << k))) == 0;
				if (open && tt_water(tile + SIDE[a] + SIDE[k]) == W_SEA) { shore_sides |= 16 << k; }
			}
		}
		// up close the steps of the shore round the data tile
		if (part == 0 && tile_km <= 0.5 && (shore_sides & 15) != 0) {
			shore_sides |= cs_steps(sub_tiles ? tile >> ivec2(1) : tile) << 16;
		}
		if ((pixel.x & 1) == 0) {
			COLOR = vec4(float(ground_bits), float(side_bits | (shore_lake << 8) | (water << 9)),
				float(shore_sides & 2047), float((shore_sides >> 11) & 2047));
		} else {
			COLOR = vec4(float(shore_sides >> 22), coast >= 1.0 ? 2.0 : coast > 0.0 ? 1.0 : 0.0,
				float((cut + 1) | ((lake_cut + 1) << 3)), 0.0);
		}
	}
}
