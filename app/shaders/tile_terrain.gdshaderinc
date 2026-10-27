// Tile terrain (SimCity 2000 meets EU5): shared data access and tile rules.
// Used by tile_terrain.gdshader and tile_props.gdshader; tile_terrain.gd sets
// the same uniforms on all materials and mirrors the height rule on the CPU
// (ground_y) for the camera and the weather.
// World units are model kilometres: x east, z south, y up.

uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable; // metres, 2 km nodes
uniform sampler2D relief_tex : filter_linear_mipmap, repeat_disable; // slope-limited metres (shape)
uniform sampler2D cover_tex : filter_linear_mipmap, repeat_disable;  // forest, dry, crop, wetland
uniform sampler2D aux_tex : filter_nearest, repeat_disable;          // sea distance, lake level hi/lo
uniform sampler2D cells_tex : filter_nearest, repeat_disable;        // two cells per byte
uniform vec2 world_min;
uniform vec2 world_size;
uniform vec2 grid_size;        // node grid (5163, 2392)
uniform ivec2 cells_size;      // unpacked cells at this level
uniform float tile_km = 2.0;
uniform float level_h = 0.36;  // world units per height level
uniform float m_per_level = 110.0;
uniform float height_lod = 0.0;
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
	return textureLod(relief_tex, tt_node_uv(tt_corner_pos(c)), height_lod).r;
}

// SimCity 2000 rule: the level belongs to the corner, not to the tile, so
// neighbouring land tiles share their corners and form one surface of flat
// tiles and one-level ramps. Corners at the sea sit at sea level, so the coast
// ramps into the water; walls only remain at rivers and lakes.
float tt_land_corner(ivec2 c) {
	bool shore = tt_water(c) == W_SEA || tt_water(c - ivec2(1, 0)) == W_SEA
		|| tt_water(c - ivec2(0, 1)) == W_SEA || tt_water(c - ivec2(1, 1)) == W_SEA;
	float l = round(max(tt_corner_height(c), 0.0) / m_per_level);
	return shore ? 0.0 : max(1.0, l);
}

float tt_lake_level(ivec2 t) {
	vec4 a = textureLod(aux_tex, tt_node_uv(tt_tile_center(t)), 0.0);
	float metres = (a.g * 255.0 * 256.0 + a.b * 255.0) - 1000.0;
	return max(round(max(metres, 0.0) / m_per_level), 1.0) - 0.75;
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
	if (w == W_RIVER) {
		// the water follows the land a little below the banks: no walls,
		// only a thin bank edge, and rivers run down slopes like rapids
		return max(l - 0.08, vec4(0.02));
	}
	return l;
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

float tt_latitude(vec2 p) {
	return 41.0 - degrees(p.y / 6371.0088);
}
