// Tile terrain surface. One MultiMesh instance per tile of the patch; the
// instance mesh holds the tile top (two triangles) and four walls. The vertex
// stage reads the tile data and builds the stepped surface, so no terrain
// geometry is ever built on the CPU.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform vec3 light_dir = vec3(-0.6, 0.67, -0.2); // towards the sun, world
uniform float slope_light = 0.9;                 // SimCity 2000 slope contrast
uniform int house_grid = 2;                      // house blocks per tile side

varying vec3 world_pos;
varying vec2 tile_uv;
varying flat int part;
varying flat ivec2 tile;
varying flat int water;
varying flat float coast;
varying flat float flat_top;
varying flat float body_level;
varying flat int shore_sides; // land tile: bit k = sea across side k, bit 4 + k = sea at corner k only
varying flat int cut_tip;     // coast cut: corner at the tip of the wet half, or -1
// Metal allows 31 varying components in all (Godot uses some itself), so
// small flags share an int
varying flat int side_bits;   // bit k: core town tile, no town across side k; bit 4 + k: river tile, water across side k
varying flat int shore_lake;  // 1: that water is a lake
varying flat int wet_tri;     // the wet half of a coast cut tile
varying flat int ground_bits; // landscape of the tile (bits 0-3), of the cut half (4-7), cut corner + 1 (8-10, 0: none)

// Palette after Urbek (Ramon, 28.10.2026): one flat colour per landscape,
// saturated greens, pale wheat, flat light water. Indexed by G_*. The values
// are darker than they appear: sun, ambient and the filmic tone map lift them
// to the Urbek colours on screen (e.g. meadow shows as #428c34).
const vec3 GROUND_RGB[11] = vec3[](
	vec3(0.224, 0.408, 0.188),  // meadow
	vec3(0.439, 0.475, 0.235),  // dry grass (Mediterranean)
	vec3(0.600, 0.624, 0.345),  // field
	vec3(0.259, 0.357, 0.235),  // wetland
	vec3(0.510, 0.455, 0.306),  // scrub
	vec3(0.655, 0.580, 0.408),  // sand
	vec3(0.141, 0.294, 0.149),  // forest
	vec3(0.110, 0.255, 0.188),  // conifer forest
	vec3(0.333, 0.439, 0.235),  // alpine meadow
	vec3(0.439, 0.420, 0.396),  // rock
	vec3(0.953, 0.965, 0.973)   // snow
);
const vec3 C_SAND = vec3(0.804, 0.745, 0.510);   // beach
const vec3 C_BANK = vec3(0.588, 0.549, 0.392);   // river bank
const vec3 C_EARTH = vec3(0.557, 0.498, 0.408);  // walls
const vec3 C_CLIFF = vec3(0.533, 0.514, 0.475);
const vec3 C_PAVED = vec3(0.655, 0.608, 0.490);
const vec3 C_ROOF = vec3(0.655, 0.333, 0.271);
const vec3 C_WALL = vec3(0.686, 0.627, 0.522);
const vec3 C_SEA = vec3(0.282, 0.490, 0.722);
const vec3 C_SHORE = vec3(0.369, 0.596, 0.839);  // sea tiles that touch the land
const vec3 C_INLAND = vec3(0.341, 0.557, 0.839);

const ivec2 CORNER[4] = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(0, 1));
const ivec2 SIDE[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
// wall w: own corners (a, b) and the matching corners of the neighbour
const ivec4 WALL[4] = ivec4[](ivec4(0, 1, 3, 2), ivec4(1, 2, 0, 3), ivec4(2, 3, 1, 0), ivec4(3, 0, 2, 1));

float pick(vec4 v, int k) {
	return k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w;
}

void vertex() {
	int id = INSTANCE_ID;
	tile = patch_origin + ivec2(id % patch_n, id / patch_n);
	part = int(VERTEX.x + 0.5);
	int role = int(VERTEX.y + 0.5);
	int cell = tt_cell(tile);
	water = cell & 3;
	int nc[4];
	for (int k = 0; k < 4; k++) { nc[k] = tt_cell(tile + SIDE[k]); }
	vec4 own = tt_corners_cached(tile);
	body_level = min(min(own.x, own.y), min(own.z, own.w));
	// flat by the rounded levels, so tiles keep their flat/ramp look while the
	// steps melt into the smooth relief
	vec4 rl = round(own);
	flat_top = float(max(max(rl.x, rl.y), max(rl.z, rl.w)) - min(min(rl.x, rl.y), min(rl.z, rl.w)) < 0.01);
	vec2 cpos;
	float level;
	// SimCity 2000 split: the top is cut along the diagonal whose corners are
	// closer in level, so a single raised or lowered corner makes one flat and
	// one sloped triangle instead of a folded pair. A coast cut forces the
	// diagonal and lowers the half at its tip to the water.
	int cut = tt_coast_cut_nb(tile, cell, nc);
	cut_tip = cut;
	int split = cut >= 0 ? (cut + 1) & 3 : (abs(own.x - own.z) <= abs(own.y - own.w) ? 0 : 1);
	float cut_level = cut >= 0 ? tt_cut_level(tile, cut) : 0.0;
	wet_tri = 0;
	if (part == 0) {
		// two separate triangles (roles 0..2 and 3..5), so the wet half can
		// sit lower than the dry one
		int tri = role / 3;
		int j = role - 3 * tri;
		int k = ((tri == 0 ? j : (j == 0 ? 0 : j + 1)) + split) & 3;
		cpos = vec2(tile + CORNER[k]);
		level = pick(own, k);
		tile_uv = vec2(CORNER[k]);
		// the second triangle's tip is corner split + 3
		if (cut >= 0 && tri == 1) {
			level = cut_level;
			wet_tri = 1;
		}
	} else if (part <= 4) {
		int w = part - 1;
		ivec4 e = WALL[w];
		bool b_side = role == 1 || role == 2;
		int ok = b_side ? e.y : e.x;
		int nk = b_side ? e.w : e.z;
		cpos = vec2(tile + CORNER[ok]);
		float top = pick(own, ok);
		// the sides of the wet half are water: no wall
		if (cut >= 0 && (w == cut || w == ((cut + 3) & 3))) { top = cut_level; }
		vec4 other = tt_corners_cached(tile + SIDE[w]);
		float bottom = min(top, pick(other, nk));
		level = role <= 1 ? top : bottom;
		tile_uv = vec2(b_side ? 1.0 : 0.0, role <= 1 ? 0.0 : 1.0);
	} else {
		// coast cut: the earth edge along the diagonal down to the water
		bool b_side = role == 1 || role == 2;
		int k = (split + (b_side ? 2 : 0)) & 3;
		cpos = vec2(tile + CORNER[k]);
		float top = cut >= 0 ? pick(own, k) : 0.0;
		level = role <= 1 || cut < 0 ? top : min(top, cut_level);
		tile_uv = vec2(b_side ? 1.0 : 0.0, role <= 1 ? 0.0 : 1.0);
		if (cut < 0) { cpos = vec2(tile); level = own.x; } // no cut: nothing drawn
	}
	world_pos = vec3(world_min.x + cpos.x * tile_km, level * level_h, world_min.y + cpos.y * tile_km);
	// coast flags: land next to the sea gets a beach, sea next to land a lagoon tint
	coast = 0.0;
	bool lake_near = water == W_LAKE;
	for (int k = 0; k < 4; k++) {
		int n1 = nc[k] & 3;
		lake_near = lake_near || n1 == W_LAKE;
		int n2 = tt_water(tile + SIDE[k] * 2);
		if (water == W_SEA) {
			if (n1 != W_SEA) { coast = 1.0; }
		} else {
			if (n1 == W_SEA) { coast = 1.0; }
			else if (n2 == W_SEA) { coast = max(coast, 0.45); }
		}
	}
	if (water == W_SEA && coast < 1.0) {
		for (int k = 0; k < 4; k++) {
			if (tt_water(tile + SIDE[k] + SIDE[(k + 1) & 3]) != W_SEA) { coast = 1.0; }
		}
	}
	shore_lake = lake_near ? 1 : 0;
	int ground = tt_ground(tile);
	int ground_alt = ground;
	int ground_tip = -1;
	if (water != W_SEA && water != W_LAKE && part == 0 && cut < 0) {
		ground_tip = tt_ground_cut(tile, ground, ground_alt);
	}
	ground_bits = ground | (ground_alt << 4) | ((ground_tip + 1) << 8);
	shore_sides = 0;
	int wall_sides = 0;
	int river_sides = 0;
	bool core = water == W_LAND && (cell >> 2) == 3;
	for (int k = 0; k < 4; k++) {
		if (water != W_SEA && (nc[k] & 3) == W_SEA) { shore_sides |= 1 << k; }
		if (core && ((nc[k] & 3) != W_LAND || (nc[k] >> 2) < 2)) { wall_sides |= 1 << k; }
		if (water == W_RIVER && (nc[k] & 3) != W_LAND) { river_sides |= 1 << k; }
	}
	side_bits = wall_sides | (river_sides << 4);
	if (water != W_SEA && part == 0) {
		for (int k = 0; k < 4; k++) {
			int a = (k + 3) & 3; // the sides at corner k: k - 1 and k
			bool open = (shore_sides & ((1 << a) | (1 << k))) == 0;
			if (open && tt_water(tile + SIDE[a] + SIDE[k]) == W_SEA) { shore_sides |= 16 << k; }
		}
	}
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

vec3 ground_rgb(int g) {
	return GROUND_RGB[clamp(g, 0, 10)];
}

// Distance (in tile units) from the tile edge on the sides set in `mask`
// (bits 0..3), or from the corners set in bits 4..7.
float side_distance(int mask) {
	float d = 10.0;
	if ((mask & 1) != 0) { d = min(d, tile_uv.y); }
	if ((mask & 2) != 0) { d = min(d, 1.0 - tile_uv.x); }
	if ((mask & 4) != 0) { d = min(d, 1.0 - tile_uv.y); }
	if ((mask & 8) != 0) { d = min(d, tile_uv.x); }
	for (int k = 0; k < 4; k++) {
		if ((mask & (16 << k)) != 0) { d = min(d, length(tile_uv - vec2(CORNER[k]))); }
	}
	return d;
}

void fragment() {
	int ground = ground_bits & 15;
	int ground_alt = (ground_bits >> 4) & 15;
	int ground_tip = (ground_bits >> 8) - 1;
	int wall_sides = side_bits & 15;
	int river_sides = side_bits >> 4;
	vec2 p = world_pos.xz;
	vec2 centre = tt_tile_center(tile);
	vec3 c;
	float rough = 1.0;
	if ((water == W_SEA || water == W_LAKE || wet_tri == 1) && part == 0) {
		// one flat colour per water tile, a lighter one where it touches the land
		if (water == W_SEA || (wet_tri == 1 && shore_lake == 0)) {
			c = coast >= 1.0 || wet_tri == 1 ? C_SHORE : C_SEA;
		} else {
			c = C_INLAND;
		}
		rough = 0.55;
	} else if (part == 0) {
		bool props = tile_km < 1.5; // trees and houses are drawn as models
		int town = tt_town(tile);
		// one flat colour per tile; where two landscapes meet, the half towards
		// the corner of the other one takes its colour (cut at the diagonal)
		c = ground_rgb(ground);
		if (ground_tip >= 0) {
			vec2 tip = vec2(CORNER[ground_tip]);
			float d = (abs(tile_uv.x - tip.x) + abs(tile_uv.y - tip.y) - 1.0) * 0.7071;
			float aa = fwidth(d) * 0.75 + 1e-4;
			c = mix(ground_rgb(ground_alt), c, smoothstep(-aa, aa, d));
		}
		if (town > 0) {
			// up close the houses stand on paved ground; far out towns are roof
			// coloured tiles and villages vanish into the land around them
			c = props ? mix(c, C_PAVED, town == 1 ? 0.5 : 1.0)
				: mix(c, C_ROOF, town == 3 ? 1.0 : town == 2 ? 0.6 : 0.0);
		}
		// city wall along the edge of the core
		if (town == 3 && wall_sides != 0) {
			c = mix(c, C_WALL * 0.82, 1.0 - smoothstep(0.05, 0.08, side_distance(wall_sides)));
		}
		// beach: a strip of sand along the sea, on the diagonal of a coast cut
		if (body_level <= 2.0 && town == 0) {
			float d = side_distance(shore_sides & 255);
			if (cut_tip >= 0 && shore_lake == 0) {
				vec2 tip = vec2(CORNER[cut_tip]);
				d = (abs(tile_uv.x - tip.x) + abs(tile_uv.y - tip.y) - 1.0) * 0.7071;
			}
			float aa = fwidth(d) + 1e-4;
			c = mix(c, C_SAND, (1.0 - smoothstep(0.26 - aa, 0.26 + aa, d)) * 0.85);
		}
		// SimCity 2000 slope tiles come in two clear tones: sun side a little
		// light, shade side dark, with no gradient in between. The light itself
		// sees every top as flat (NORMAL below), so this is the only shading:
		// lambert on top of it washed sun-side ramps out like glass and made
		// single shade-side steps black walls.
		vec3 nw = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
		nw = nw.y < 0.0 ? -nw : nw;
		float lit = dot(nw, light_dir) - light_dir.y;
		float aa_l = fwidth(lit) + 0.02;
		float tone = mix(0.80, 0.97, smoothstep(-0.05 - aa_l, -0.05 + aa_l, lit));
		tone = mix(tone, 1.05, smoothstep(0.05 - aa_l, 0.05 + aa_l, lit));
		c *= flat_top > 0.5 ? 1.0 : tone; // flat tiles never flicker between tones
		if (water == W_RIVER) {
			// a band from the tile centre to each side with water beyond it;
			// at least a boat wide, never more than half a tile
			float half_w = clamp(0.075 / tile_km, 0.06, 0.22);
			// and never thinner than about a pixel and a half, so the big
			// rivers still read on the map of Europe
			half_w = min(max(half_w, 0.75 * length(fwidth(tile_uv))), 0.3);
			vec2 q = tile_uv - 0.5;
			const vec2 MID[4] = vec2[](vec2(0.0, -0.5), vec2(0.5, 0.0), vec2(0.0, 0.5), vec2(-0.5, 0.0));
			int m = river_sides;
			bool bend = m == 3 || m == 6 || m == 12 || m == 9;
			float d = 10.0;
			if (bend) {
				// a turn cuts the corner: straight from one side to the other,
				// so the 4-connected staircase reads as a diagonal river
				int a = m == 9 ? 3 : (m == 3 ? 0 : m == 6 ? 1 : 2);
				vec2 p0 = MID[a];
				vec2 p1 = MID[(a + 1) % 4];
				vec2 e = p1 - p0;
				d = length(q - p0 - e * clamp(dot(q - p0, e) / dot(e, e), 0.0, 1.0));
			} else {
				d = length(q);
				for (int k = 0; k < 4; k++) {
					if ((m & (1 << k)) != 0) {
						vec2 e = MID[k];
						d = min(d, length(q - e * clamp(dot(q, e) / dot(e, e), 0.0, 1.0)));
					}
				}
			}
			float aa = fwidth(d) * 1.2;
			float bank = 1.0 - smoothstep(half_w + 0.02, half_w + 0.02 + aa, d);
			float river = 1.0 - smoothstep(half_w, half_w + aa, d);
			c = mix(c, C_BANK, bank);
			c = mix(c, C_INLAND, river);
		}
	} else {
		// walls: one darker earth tone (sand at the coast, rock up high), no texture
		float hm = world_pos.y / level_h * m_per_level;
		vec3 base = water == W_SEA ? C_SEA * 0.8 : (coast > 0.0 && body_level <= 3.0) ? C_BANK : C_EARTH;
		if (water == W_LAND && hm > 1200.0) { base = C_CLIFF; }
		c = base;
	}
	ALBEDO = pow(clamp(c, 0.0, 1.0), vec3(2.2)); // palette is sRGB
	ROUGHNESS = rough;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	n = n.z < 0.0 ? -n : n;
	// tops are lit as flat ground (the slope tones above do the relief); walls
	// keep their own facing
	NORMAL = part == 0 ? normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) : n;
}
