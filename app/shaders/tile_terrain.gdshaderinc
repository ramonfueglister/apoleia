// Tile terrain (SimCity 2000 meets EU5): shared data access and tile rules.
// Used by tile_terrain.gdshader and tile_props.gdshader; tile_terrain.gd sets
// the same uniforms on all materials and mirrors the height rule on the CPU
// (ground_y) for the camera and the weather.
// World units are model kilometres: x east, z south, y up.

uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable; // metres, 2 km nodes
uniform sampler2D relief_tex : filter_linear_mipmap, repeat_disable; // slope-limited metres (shape)
uniform sampler2D cover_tex : filter_linear_mipmap, repeat_disable;  // forest, dry, crop, wetland
uniform sampler2D aux_tex : filter_nearest, repeat_disable;          // sea distance, lake level hi/lo
uniform sampler2D shore_tex : filter_linear, repeat_disable;          // highest land next to the water (metres)
uniform bool shore_ready = false;
uniform sampler2D cells_tex : filter_nearest, repeat_disable;        // two cells per byte
uniform vec2 world_min;
uniform vec2 world_size;
uniform vec2 grid_size;        // node grid (5163, 2392)
uniform ivec2 cells_size;      // unpacked cells at this level
uniform float tile_km = 2.0;
uniform float level_h = 0.36;  // world units per height level
uniform float m_per_level = 110.0;
uniform float height_lod = 0.0;
uniform float relief_smooth = 0.0; // 0 tile steps (near) .. 1 smooth relief map (far)
uniform ivec2 patch_origin;    // first tile of the drawn patch
uniform int patch_n = 256;

const int W_LAND = 0;
const int W_SEA = 1;
const int W_LAKE = 2;
const int W_RIVER = 3;

float tt_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float tt_hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float tt_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(tt_hash(i), tt_hash(i + vec2(1.0, 0.0)), f.x), mix(tt_hash(i + vec2(0.0, 1.0)), tt_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float tt_fbm(vec2 p) {
	return tt_noise(p) * 0.57 + tt_noise(p * 2.03 + 17.1) * 0.29 + tt_noise(p * 4.1 - 9.3) * 0.14;
}

vec2 tt_node_uv(vec2 p) {
	return ((p - world_min) / world_size * (grid_size - 1.0) + 0.5) / grid_size;
}

float tt_height_m(vec2 p, float lod) {
	return textureLod(height_tex, tt_node_uv(p), lod).r;
}

vec4 tt_cover(vec2 p) {
	return textureLod(cover_tex, tt_node_uv(p), height_lod);
}

// World position of a tile corner (integer corner coordinates on the tile grid).
vec2 tt_corner_pos(ivec2 c) {
	return world_min + vec2(c) * tile_km;
}

vec2 tt_tile_center(ivec2 t) {
	return world_min + (vec2(t) + 0.5) * tile_km;
}

int tt_cell(ivec2 t) {
	if (t.x < 0 || t.y < 0 || t.x >= cells_size.x || t.y >= cells_size.y) {
		return W_SEA;
	}
	int b = int(texelFetch(cells_tex, ivec2(t.x >> 1, t.y), 0).r * 255.0 + 0.5);
	return (t.x & 1) == 0 ? (b & 15) : (b >> 4);
}

int tt_water(ivec2 t) {
	return tt_cell(t) & 3;
}

int tt_town(ivec2 t) {
	return tt_cell(t) >> 2;
}

// Display relief at a tile corner. The baked relief rises at most
// m_per_level per tile_km (tools/build_tile_terrain.py, sc2k_relief), so the
// rounded levels of neighbouring corners differ by at most one.
float tt_corner_height(ivec2 c) {
	// blurred, so level contours run as long clean lines (as in SimCity 2000)
	// instead of single-tile bumps and pits; the blur only lowers slopes
	// (the smooth far relief keeps more of the ridges, so it stays crisp)
	vec2 uv = tt_node_uv(tt_corner_pos(c));
	float h = textureLod(relief_tex, uv, height_lod + mix(1.5, 0.3, relief_smooth)).r;
	// the blur must not lift the land next to the water: cap it with the sharp
	// water envelope, which rises one level per tile from every shore
	return shore_ready ? min(h, textureLod(shore_tex, uv, 0.0).r) : h;
}

// SimCity 2000 rule: the level belongs to the corner, not to the tile, so
// neighbouring land tiles share their corners and form one surface of flat
// tiles and one-level ramps. Corners at the sea sit at sea level, so the coast
// ramps into the water; walls only remain at rivers and lakes.
// Flat water level of a lake tile (levels). The baked lake level lives on the
// 2 km nodes, so look at a few nodes around the tile and keep the lake's value.
float tt_lake_level(ivec2 t) {
	vec2 p = tt_tile_center(t);
	float metres = -1000.0;
	for (int k = 0; k < 5; k++) {
		vec2 o = k == 0 ? vec2(0.0) : vec2(k == 1 ? 1.0 : k == 2 ? -1.0 : 0.0, k == 3 ? 1.0 : k == 4 ? -1.0 : 0.0) * 1.0;
		vec4 a = textureLod(aux_tex, tt_node_uv(p + o), 0.0);
		float m = (a.g * 255.0 * 256.0 + a.b * 255.0) - 1000.0;
		if (a.g + a.b > 0.0) { metres = metres < -999.0 ? m : min(metres, m); }
	}
	// small lakes between the nodes: the bake pinned their nodes in the envelope
	if (metres < -999.0 && shore_ready) { metres = textureLod(shore_tex, tt_node_uv(p), 0.0).r; }
	float x = max(metres, 0.0) / m_per_level;
	return max(mix(round(x), x, relief_smooth), 1.0);
}

float tt_corner_x(ivec2 c) {
	return max(tt_corner_height(c), 0.0) / m_per_level;
}

// Removes ridges and pits one corner wide: a corner above both neighbours
// along one axis (and not below either along the other) drops a level, and
// the other way round. Otherwise a plain right at a level boundary shows
// single-tile bumps and notches instead of clean terraces (SimCity 2000).
float tt_clean_level(ivec2 c, float l) {
	vec2 ax = vec2(round(tt_corner_x(c - ivec2(1, 0))), round(tt_corner_x(c + ivec2(1, 0))));
	vec2 az = vec2(round(tt_corner_x(c - ivec2(0, 1))), round(tt_corner_x(c + ivec2(0, 1))));
	float hx = max(ax.x, ax.y), lx = min(ax.x, ax.y);
	float hz = max(az.x, az.y), lz = min(az.x, az.y);
	if ((l > hx && l >= hz) || (l > hz && l >= hx)) { return l - 1.0; }
	if ((l < lx && l <= lz) || (l < lz && l <= lx)) { return l + 1.0; }
	return l;
}

float tt_land_corner(ivec2 c) {
	ivec2 nb[4] = ivec2[](c, c - ivec2(1, 0), c - ivec2(0, 1), c - ivec2(1, 1));
	bool shore = false;
	float lake = 1.0e6;
	for (int k = 0; k < 4; k++) {
		int w = tt_water(nb[k]);
		shore = shore || w == W_SEA;
		if (w == W_LAKE) { lake = min(lake, tt_lake_level(nb[k])); }
	}
	// far out the steps melt into a smooth relief (EU5 map); up close they are tiles
	float x = tt_corner_x(c);
	float l = max(1.0, mix(tt_clean_level(c, round(x)), x, relief_smooth));
	// corners at the sea or a lake sit at the water line: the shore ramps in
	return shore ? 0.0 : min(l, lake);
}

// Levels of the four corners (c00, c10, c11, c01) of tile t.
vec4 tt_corners(ivec2 t) {
	int w = tt_water(t);
	if (w == W_SEA) {
		return vec4(0.0);
	}
	if (w == W_LAKE) {
		return vec4(tt_lake_level(t));
	}
	vec4 l = vec4(
		tt_land_corner(t),
		tt_land_corner(t + ivec2(1, 0)),
		tt_land_corner(t + ivec2(1, 1)),
		tt_land_corner(t + ivec2(0, 1)));
	// river tiles keep the land shape; the river is a narrow band drawn on top
	return l;
}

// The corners of every tile in the drawn patch, computed once per frame by
// tile_corner_prep.gdshader (a small 2D pass) instead of once per vertex.
// Tiles outside that texture fall back to the full rule.
uniform sampler2D corner_tex : filter_nearest, repeat_disable;
uniform ivec2 corner_origin;
uniform ivec2 corner_size = ivec2(0);

vec4 tt_corners_cached(ivec2 t) {
	ivec2 q = t - corner_origin;
	if (q.x >= 0 && q.y >= 0 && q.x < corner_size.x && q.y < corner_size.y) {
		return texelFetch(corner_tex, q, 0);
	}
	return tt_corners(t);
}

// Clumped woods: land cover forest share through a noisy threshold. The noise
// is anchored in the world, so woods keep their place across zoom levels.
float tt_tree_density(vec2 p, float forest) {
	return smoothstep(0.5, 0.95, forest + (tt_fbm(p / 9.0) - 0.5) * 0.5);
}

// Distance to the coast in km (bilinear over the 2 km nodes).
float tt_sea_distance(vec2 p) {
	vec2 g = (p - world_min) / world_size * (grid_size - 1.0);
	ivec2 i = ivec2(floor(g));
	vec2 f = fract(g);
	float a = texelFetch(aux_tex, i, 0).r;
	float b = texelFetch(aux_tex, i + ivec2(1, 0), 0).r;
	float c = texelFetch(aux_tex, i + ivec2(0, 1), 0).r;
	float d = texelFetch(aux_tex, i + ivec2(1, 1), 0).r;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y) * 255.0 * 2.0;
}

// Bilinear share of sea nodes (x) and lake nodes (y) at p, 0 dry .. 1 wet:
// its 0.5 contour is a smooth shoreline for the far relief map.
vec2 tt_water_share(vec2 p) {
	vec2 g = (p - world_min) / world_size * (grid_size - 1.0);
	ivec2 i = ivec2(floor(g));
	vec2 f = fract(g);
	vec2 w[4];
	for (int k = 0; k < 4; k++) {
		vec4 a = texelFetch(aux_tex, i + ivec2(k & 1, k >> 1), 0);
		w[k] = vec2(a.r > 0.0 ? 1.0 : 0.0, a.g + a.b > 0.0 ? 1.0 : 0.0);
	}
	return mix(mix(w[0], w[1], f.x), mix(w[2], w[3], f.x), f.y);
}

float tt_latitude(vec2 p) {
	return 41.0 - degrees(p.y / 6371.0088);
}
