// Tile terrain surface. One MultiMesh instance per tile of the patch; the
// instance mesh holds the tile top (two triangles) and four walls. The vertex
// stage reads the tile data and builds the stepped surface, so no terrain
// geometry is ever built on the CPU.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform float grid_line = 0.04; // faint: a diorama, not a spreadsheet
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
varying float shallow;        // sea: 0 where the water meets dry land .. 1 one tile out
varying flat int cut_tip;     // coast cut: corner at the tip of the wet half, or -1
varying flat int wall_sides;  // core town tile: bit k = no town across side k
varying flat int river_sides; // river tile: bit k = water across side k
varying flat int shore_lake;  // 1: that water is a lake
varying flat int wet_tri;     // the wet half of a coast cut tile

const vec3 C_PLAIN = vec3(0.494, 0.600, 0.290);
const vec3 C_GRASS = vec3(0.392, 0.545, 0.251);
const vec3 C_DRY = vec3(0.706, 0.655, 0.388);
const vec3 C_HILL = vec3(0.353, 0.475, 0.255);
const vec3 C_FOREST = vec3(0.216, 0.318, 0.165);
const vec3 C_SAND = vec3(0.847, 0.753, 0.549);
const vec3 C_SAND_DARK = vec3(0.773, 0.694, 0.467);
const vec3 C_ROCK = vec3(0.612, 0.584, 0.506);
const vec3 C_PEAK = vec3(0.859, 0.780, 0.635);
const vec3 C_SNOW = vec3(0.945, 0.957, 0.965);
const vec3 C_WET = vec3(0.408, 0.502, 0.337);
const vec3 C_CROP = vec3(0.698, 0.659, 0.365);
const vec3 C_EARTH = vec3(0.588, 0.463, 0.314);
const vec3 C_SLOPE = vec3(0.600, 0.490, 0.290); // ramps: a touch of bare earth
const vec3 C_CLIFF = vec3(0.502, 0.478, 0.408);
const vec3 C_PAVED = vec3(0.776, 0.729, 0.596);
const vec3 C_STREET = vec3(0.612, 0.573, 0.494);
const vec3 C_WALL = vec3(0.686, 0.627, 0.522);
const vec3 C_FOAM = vec3(0.93, 0.96, 0.95);
const vec3 W_MID = vec3(0.133, 0.384, 0.612);
const vec3 W_SHALLOW = vec3(0.204, 0.549, 0.675);
const vec3 W_LAGOON = vec3(0.329, 0.659, 0.690);
const vec3 W_OPEN = vec3(0.110, 0.325, 0.553);
const vec3 W_INLAND = vec3(0.247, 0.510, 0.651);

const ivec2 CORNER[4] = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(0, 1));
const ivec2 SIDE[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
// wall w: own corners (a, b) and the matching corners of the neighbour
const ivec4 WALL[4] = ivec4[](ivec4(0, 1, 3, 2), ivec4(1, 2, 0, 3), ivec4(2, 3, 1, 0), ivec4(3, 0, 2, 1));

float pick(vec4 v, int k) {
	return k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w;
}

// 1 where corner c of the tile grid touches dry land (a land or river tile,
// but not the tip of a coast cut, which is water), else 0. Interpolated over
// the water tiles it gives a shore band built from the tiles themselves, so
// it follows the staircase and the 45-degree cuts exactly.
float dry_corner(ivec2 c) {
	int dry = 0;
	ivec2 last = c;
	for (int k = 0; k < 4; k++) {
		ivec2 t = c - ivec2(1 - (k & 1), 1 - (k >> 1));
		if (tt_water(t) != W_SEA) {
			dry++;
			last = t;
		}
	}
	if (dry == 1) {
		int cut = tt_coast_cut(last);
		if (cut >= 0 && last + CORNER[cut] == c) { return 0.0; }
	}
	return dry > 0 ? 1.0 : 0.0;
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
	shallow = 1.0;
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
		if (water == W_SEA || wet_tri == 1) { shallow = 1.0 - dry_corner(tile + CORNER[k]); }
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
	shore_lake = lake_near ? 1 : 0;
	shore_sides = 0;
	wall_sides = 0;
	river_sides = 0;
	bool core = water == W_LAND && (cell >> 2) == 3;
	for (int k = 0; k < 4; k++) {
		if (water != W_SEA && (nc[k] & 3) == W_SEA) { shore_sides |= 1 << k; }
		if (core && ((nc[k] & 3) != W_LAND || (nc[k] >> 2) < 2)) { wall_sides |= 1 << k; }
		if (water == W_RIVER && (nc[k] & 3) != W_LAND) { river_sides |= 1 << k; }
	}
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

// Colour of a land tile: one colour per tile, as in SimCity 2000, from the
// land cover and height at its centre (the data mip that matches the tile).
vec3 tile_colour(vec2 centre, vec4 cov, float h, float trees) {
	float n = tt_fbm(centre / (6.0 * tile_km));
	float lat = tt_latitude(centre);
	float dry = cov.g;
	vec3 c = mix(C_PLAIN, C_GRASS, 0.35 + 0.65 * n);
	if (lat < 37.5) {
		c = mix(c, C_DRY, clamp(dry * 1.2, 0.0, 1.0));
		c = mix(c, C_SAND_DARK, clamp((dry - 0.6) * 2.0, 0.0, 1.0));
	} else {
		c = mix(c, C_DRY, clamp(dry * 1.1, 0.0, 0.85));
	}
	c = mix(c, C_CROP, clamp(cov.b * 1.4, 0.0, 0.6) * 0.5);
	c = mix(c, C_FOREST, 0.15 * cov.r + 0.75 * trees);
	c = mix(c, C_WET, clamp(cov.a * 2.0, 0.0, 0.8));
	c = mix(c, C_HILL, clamp((h - 500.0) / 900.0, 0.0, 1.0) * (1.0 - dry));
	// the tile height is a mean over the tile: far out the peaks average lower;
	// the snow line climbs to the south and stays off dry high plateaus
	float lower = 60.0 * height_lod;
	float snow_line = 1600.0 - 2.0 * lower + max(45.0 - lat, 0.0) * 70.0 + 500.0 * dry;
	c = mix(c, C_ROCK, clamp((h - 1100.0 + lower) / 350.0, 0.0, 1.0));
	c = mix(c, C_SNOW, clamp((h - snow_line) / 180.0, 0.0, 1.0));
	// a touch of variation from tile to tile, like hand-laid diorama tiles
	return c * (0.975 + 0.05 * tt_hash(vec2(tile) * 0.731 + 3.1));
}

// How sharply a pattern of `cells` per tile can be drawn: 1 while a cell
// spans several pixels, 0 once it would shimmer.
float pattern_detail(float cells) {
	vec2 fw = fwidth(tile_uv) * cells;
	return 1.0 - smoothstep(0.15, 0.3, max(fw.x, fw.y));
}

// Wood far out, where no tree props are drawn: round crowns on a jittered
// grid, lit from the sun side, as on the SimCity 2000 forest tiles.
vec3 forest_crowns(vec3 floor_c, float trees, float h) {
	float k = tile_km >= 4.0 ? 2.0 : 3.0;
	vec2 q = tile_uv * k;
	vec2 cell = floor(q);
	vec2 id = vec2(tile) * k + cell;
	float r = 0.36 + 0.1 * tt_hash(id + 7.7);
	vec2 o = (vec2(tt_hash(id), tt_hash(id + 3.3)) - 0.5) * (0.9 - 2.0 * r) ;
	vec2 d = fract(q) - 0.5 - o;
	bool tree = tt_hash(id * 1.37 + 0.5) < trees * 1.15;
	// conifers in the mountains: darker and bluer
	float conifer = smoothstep(700.0, 1100.0, h);
	vec3 dark = mix(vec3(0.165, 0.271, 0.129), vec3(0.122, 0.231, 0.161), conifer);
	vec3 light = mix(vec3(0.365, 0.522, 0.212), vec3(0.259, 0.420, 0.243), conifer);
	vec2 sun = normalize(light_dir.xz);
	float dist = length(d);
	float aa = fwidth(dist) + 1e-4;
	float crown = tree ? 1.0 - smoothstep(r - aa, r + aa, dist) : 0.0;
	float shine = clamp(dot(d / r, sun) * 0.8 + 0.35, 0.0, 1.0);
	vec3 crown_c = mix(dark, light, shine * (1.0 - smoothstep(0.55, 1.0, dist / r) * 0.6));
	vec3 ground = floor_c * 0.78;
	vec3 c = mix(ground, crown_c, crown);
	// the average of the pattern once crowns get smaller than a few pixels
	vec3 mean_c = mix(ground, mix(dark, light, 0.45), min(trees * 1.15, 1.0) * 0.55);
	return mix(mean_c, c, pattern_detail(k));
}

// Town far out, where no house props are drawn: red roofs on a block grid,
// a ridge across each roof with a sun and a shade side, as the houses up close.
vec3 town_roofs(vec3 ground_c, int town) {
	float k = tile_km >= 16.0 ? 1.0 : tile_km >= 4.0 ? 2.0 : 3.0;
	vec2 q = tile_uv * k;
	vec2 cell = floor(q);
	vec2 id = vec2(tile) * k + cell;
	float share = town == 3 ? 0.95 : town == 2 ? 0.7 : 0.35;
	bool roof = tt_hash(id * 0.917 + 1.9) < share;
	vec2 f = fract(q) - 0.5;
	float inset = 0.32 + 0.06 * tt_hash(id + 5.1);
	vec2 e = abs(f) - inset;
	float aa = fwidth(f.x) + 1e-4;
	float m = roof ? 1.0 - smoothstep(-aa, aa, max(e.x, e.y)) : 0.0;
	bool along_x = tt_hash(id + 2.2) < 0.5;
	float side = along_x ? f.y : f.x;
	vec2 sun = normalize(light_dir.xz);
	float lit = (along_x ? -sun.y : -sun.x) * side < 0.0 ? 1.0 : 0.0;
	vec3 roof_c = vec3(0.74, 0.37, 0.23) * mix(0.82, 1.08, lit) * (0.92 + 0.16 * tt_hash(id + 9.4));
	// a village is a few houses on the grass, a city a paved block
	vec3 street = mix(ground_c, C_PAVED, town == 3 ? 0.7 : town == 2 ? 0.45 : 0.12);
	vec3 c = mix(street, roof_c, m);
	vec3 mean_c = mix(street, vec3(0.74, 0.37, 0.23) * 0.95, share * 0.5);
	return mix(mean_c, c, pattern_detail(k));
}

// Sea colour: a shore band one tile wide, built from the tiles (`shallow`),
// then one calm blue, as in SimCity 2000. Nothing comes from the finer coast
// data, so islets smaller than a tile leave no halo, at every zoom.
vec3 sea_colour() {
	vec3 c = mix(W_LAGOON, W_SHALLOW, smoothstep(0.0, 0.5, shallow));
	return mix(c, W_OPEN, smoothstep(0.4, 1.0, shallow));
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
	vec2 p = world_pos.xz;
	vec2 centre = tt_tile_center(tile);
	vec3 c;
	float rough = 1.0;
	if ((water == W_SEA || water == W_LAKE || wet_tri == 1) && part == 0) {
		if (water == W_SEA || (wet_tri == 1 && shore_lake == 0)) {
			c = sea_colour();
			// light wave dashes, anchored to the tile grid
			vec2 q = p / (tile_km * 0.5);
			vec2 cell = floor(q);
			vec2 f = fract(q);
			float r = tt_hash(cell + floor(TIME * 0.15 + tt_hash(cell) * 7.0));
			float dash = step(0.82, r) * (1.0 - smoothstep(0.0, 0.05, abs(f.y - 0.5))) * step(0.2, f.x) * step(f.x, 0.55);
			c = mix(c, vec3(0.86, 0.93, 0.92), dash * 0.5 * (coast > 0.5 ? 1.2 : 0.6) * pattern_detail(2.0));
		} else {
			c = W_INLAND;
		}
		rough = 0.55;
	} else if (part == 0) {
		vec4 cov = tt_cover(centre);
		float h = tt_height_m(centre, height_lod);
		bool props = tile_km < 1.5; // trees and houses are drawn as models
		// far out the colour reads the cover a little wider than the tile, so
		// woods and fields form calm patches instead of single-tile specks
		vec4 cov_c = props ? cov : textureLod(cover_tex, tt_node_uv(centre), height_lod + 0.7);
		float trees = tt_tree_density(centre, cov_c.r);
		int town = tt_town(tile);
		c = tile_colour(centre, cov_c, h, props ? trees : 0.0);
		if (town > 0 && props) {
			c = mix(c, C_PAVED, 0.75);
			// streets between the house blocks
			vec2 g = abs(fract(tile_uv * float(house_grid)) - 0.5);
			float street = 1.0 - smoothstep(0.38, 0.43, max(g.x, g.y));
			if (town >= 2) { c = mix(c, C_STREET, 1.0 - street); }
		} else if (town > 0) {
			c = town_roofs(c, town);
		} else if (trees > 0.12 && !props && h < 1400.0) {
			c = forest_crowns(c, trees, h);
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
		// ramps: a touch of bare earth, as on SimCity 2000 slope tiles
		if (flat_top < 0.5 && town == 0) {
			c = mix(c, C_SLOPE, 0.22);
		}
		// SimCity 2000 slope tiles come in two clear tones: sun side light,
		// shade side dark, with no gradient in between
		vec3 nw = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
		nw = nw.y < 0.0 ? -nw : nw;
		float lit = dot(nw, light_dir) - light_dir.y;
		float aa_l = fwidth(lit) + 0.02;
		float tone = mix(0.80, 1.0, smoothstep(-0.05 - aa_l, -0.05 + aa_l, lit));
		tone = mix(tone, 1.13, smoothstep(0.05 - aa_l, 0.05 + aa_l, lit));
		c *= flat_top > 0.5 ? 1.0 : tone; // flat tiles never flicker between tones
		// tile outline, about one pixel wide at every zoom
		vec2 e = min(tile_uv, 1.0 - tile_uv);
		vec2 fw = fwidth(tile_uv);
		float line = 1.0 - smoothstep(0.0, 1.0, min(e.x / max(fw.x, 1e-5), e.y / max(fw.y, 1e-5)));
		// fade the outline out when tiles get only a few pixels wide
		float fade = smoothstep(5.0, 12.0, 1.0 / max(max(fw.x, fw.y), 1e-5));
		c *= 1.0 - grid_line * line * (flat_top > 0.5 ? 1.0 : 0.3) * fade;
		if (water == W_RIVER) {
			// a band from the tile centre to each side with water beyond it;
			// at least a boat wide, never more than half a tile
			float half_w = clamp(0.075 / tile_km, 0.06, 0.22);
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
			c = mix(c, C_SAND_DARK, bank * 0.6);
			c = mix(c, W_INLAND * (0.97 + 0.06 * tt_hash(vec2(tile))), river);
		}
	} else {
		// walls: earth, sand at the coast, rock in the mountains; strata per level
		float hm = world_pos.y / level_h * m_per_level;
		vec3 base = water == W_SEA ? W_MID * 0.8 : (coast > 0.0 && body_level <= 3.0) ? C_SAND_DARK : C_EARTH;
		if (water == W_LAND && hm > 1200.0) { base = C_CLIFF; }
		float strata = fract(world_pos.y / level_h);
		float sw = fwidth(world_pos.y / level_h);
		base *= 1.0 - 0.1 * (1.0 - smoothstep(0.0, sw * 1.5 + 0.02, min(strata, 1.0 - strata)));
		c = base;
	}
	ALBEDO = pow(clamp(c, 0.0, 1.0), vec3(2.2)); // palette is sRGB
	ROUGHNESS = rough;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = n.z < 0.0 ? -n : n;
}
