// Tile terrain (SimCity 2000 tiles at every zoom): shared data access and tile rules.
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
uniform sampler2D levels_tex : filter_nearest, repeat_disable; // baked corner levels (8 bit)
uniform bool levels_ready = false;
uniform ivec2 levels_origin;   // first corner in levels_tex (near levels: a window around the patch)
uniform bool near_scale = false; // levels on the near scale (NEAR_STEPS_M), else LEVEL_STEPS_M
uniform sampler2D ground_tex : filter_nearest, repeat_disable; // landscape per tile, two per byte
uniform bool ground_ready = false;
uniform ivec2 patch_origin;    // first tile of the drawn patch
uniform int patch_n = 256;
// Up close the tiles are quarters of the 0.5 km data tiles (tile_terrain.gd,
// SUB_KM): one house per tile, as in Urbek. tile_sub_prep.gdshader cuts their
// cells, landscapes and corner levels from the data tiles into sub_tex, a
// window around the patch; the cells, landscapes and levels below read it.
uniform bool sub_tiles = false;
uniform sampler2D sub_tex : filter_nearest, repeat_disable; // r cell, g landscape, b level of corner c00
uniform ivec2 sub_origin;      // first quarter tile in sub_tex

// Size of the tiles the data (cells, landscapes, levels) belongs to.
float tt_data_km() {
	return sub_tiles ? tile_km * 2.0 : tile_km;
}

// The sub_tex texel of quarter tile t, or false outside the window.
bool tt_sub_texel(ivec2 t, out vec4 v) {
	ivec2 q = t - sub_origin;
	ivec2 n = textureSize(sub_tex, 0);
	if (!sub_tiles || q.x < 0 || q.y < 0 || q.x >= n.x || q.y >= n.y) { return false; }
	v = texelFetch(sub_tex, q, 0);
	return true;
}

const int W_LAND = 0;
const int W_SEA = 1;
const int W_LAKE = 2;
const int W_RIVER = 3;
// landscape of a tile (tools/build_tile_terrain.py, GROUND): one colour each
const int G_MEADOW = 0;
const int G_DRY_GRASS = 1;
const int G_FIELD = 2;
const int G_WETLAND = 3;
const int G_SCRUB = 4;
const int G_SAND = 5;
const int G_FOREST = 6;
const int G_CONIFER = 7;
const int G_ALPINE = 8;
const int G_ROCK = 9;
const int G_SNOW = 10;
const int G_NONE = 15; // water

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

// Cell of data tile t (the quarter tiles: tt_cell).
int tt_data_cell(ivec2 t) {
	if (t.x < 0 || t.y < 0 || t.x >= cells_size.x || t.y >= cells_size.y) {
		return W_SEA;
	}
	int b = int(texelFetch(cells_tex, ivec2(t.x >> 1, t.y), 0).r * 255.0 + 0.5);
	return (t.x & 1) == 0 ? (b & 15) : (b >> 4);
}

int tt_cell(ivec2 t) {
	if (sub_tiles) {
		vec4 v;
		return tt_sub_texel(t, v) ? int(v.r + 0.5) : tt_data_cell(t >> ivec2(1));
	}
	return tt_data_cell(t);
}

int tt_water(ivec2 t) {
	return tt_cell(t) & 3;
}

// The SimCity 2000 light of the slope and wall tones (towards the light,
// world, unit length): from the left of the screen and from behind the
// camera, so the faces turned to the camera are the lit ones at any camera
// angle, as in SimCity 2000 and Urbek. `inv_view` is INV_VIEW_MATRIX.
vec3 tt_art_light(mat4 inv_view) {
	vec3 r = inv_view[0].xyz;
	vec3 u = inv_view[1].xyz;
	vec3 b = inv_view[2].xyz;
	vec2 right = normalize(r.xz + vec2(1e-5, 0.0));
	vec2 back = normalize(b.xz - u.xz + vec2(0.0, 1e-5)); // screen down, also top-down
	vec2 h = -0.45 * right + 0.53 * back;
	return normalize(vec3(h.x, 0.72, h.y));
}

// Stone paving up close, as Urbek's paved squares and pavements: slabs of
// `size` diorama metres (1 diorama metre = 0.0238 km) in staggered rows,
// dark joints and a slight tone per slab; a factor for the colour. It fades
// out before the slabs shrink to a few pixels, so farther out the paving is
// one calm tone again. p in world km.
float tt_paving(vec2 p, vec2 size) {
	vec2 q = p / (0.0238 * size);
	float row = floor(q.y);
	q.x += 0.5 * mod(row, 2.0);
	vec2 w = max(fwidth(q), vec2(1e-5));
	float fade = 1.0 - smoothstep(0.1, 0.25, max(w.x, w.y));
	if (fade <= 0.0) { return 1.0; }
	vec2 e = (0.5 - abs(fract(q) - 0.5)) / w; // pixels to the nearest joint
	float joint = 1.0 - smoothstep(0.4, 1.2, min(e.x, e.y));
	float slab = tt_hash(floor(q) + 0.37) - 0.5;
	return 1.0 + fade * (0.09 * slab - 0.14 * joint);
}

// Urbek's grass up close is never one flat tone: soft patches of a deeper,
// richer green, dark tufts of a voxel or two and now and then a flower
// (Ramon 29.10.2026: our meadow one flat green, a third of the picture).
// The grass colour c at p (world km) with them; gone before it would
// shimmer. Cells in diorama metres (0.0238 km), wrapped so the hash keeps
// its precision far from the origin.
vec3 tt_grass(vec2 p, vec3 c) {
	vec2 q = mod(p / 0.0238, 4096.0);
	vec2 w = max(fwidth(q), vec2(1e-5));
	float px = max(w.x, w.y); // metres a pixel
	// patches about 6 m across: down to a deeper, more saturated green
	float blot = tt_noise(q / 6.0) * 0.7 + tt_noise(q / 2.3 + 31.7) * 0.3;
	float deep = smoothstep(0.35, 0.75, blot) * (1.0 - smoothstep(0.15, 0.3, px));
	c *= mix(vec3(1.0), vec3(0.72, 0.86, 0.66), deep);
	float fine = 1.0 - smoothstep(0.08, 0.2, px);
	if (fine <= 0.0) { return c; }
	// tufts: a square of 0.4 m in some cells of 0.7 m, more in the patches
	vec2 cq = q / 0.7;
	vec2 cell = floor(cq);
	float r = tt_hash(cell + 0.73);
	vec2 at = vec2(tt_hash(cell + 3.1), tt_hash(cell - 5.3)) * 0.4;
	vec2 in_cell = fract(cq) - at;
	bool inside = all(greaterThanEqual(in_cell, vec2(0.0))) && all(lessThan(in_cell, vec2(0.57)));
	if (inside && r < 0.08 + 0.1 * deep) {
		c = mix(c, c * vec3(0.6, 0.7, 0.55), fine);
	} else if (inside && r > 0.996) {
		// a flower: white, yellow or pink
		float k = tt_hash(cell + 9.9);
		vec3 bloom = k < 0.4 ? vec3(0.86, 0.85, 0.8) : k < 0.75 ? vec3(0.9, 0.78, 0.3) : vec3(0.86, 0.55, 0.66);
		c = mix(c, bloom, fine);
	}
	return c;
}

int tt_ground(ivec2 t) {
	if (sub_tiles) {
		vec4 v;
		if (tt_sub_texel(t, v)) { return int(v.g + 0.5); }
		t = t >> ivec2(1);
	}
	if (!ground_ready || t.x < 0 || t.y < 0 || t.x >= cells_size.x || t.y >= cells_size.y) {
		return G_NONE;
	}
	int b = int(texelFetch(ground_tex, ivec2(t.x >> 1, t.y), 0).r * 255.0 + 0.5);
	return (t.x & 1) == 0 ? (b & 15) : (b >> 4);
}

// Two landscapes meet in a tile like the coast does: when both sides at a
// corner and the tile across that corner share another, stronger landscape,
// the half of the tile towards that corner takes it (cut at the diagonal). Returns the
// corner (0..3) or -1; `alt` is the landscape of that half.
int tt_ground_cut(ivec2 t, int g, out int alt) {
	alt = g;
	if (g == G_NONE) { return -1; }
	const ivec2 SIDES[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
	// only the stronger landscape spills over (snow over rock over wood over
	// open land), as only the water cuts into the land at the coast; cutting
	// both sides of a staircase would leave teeth instead of one diagonal
	const int RANK[11] = int[](0, 1, 4, 5, 3, 2, 7, 8, 6, 9, 10);
	for (int k = 0; k < 4; k++) {
		ivec2 a = SIDES[(k + 3) & 3];
		ivec2 b = SIDES[k];
		int ga = tt_ground(t + a);
		if (ga == g || ga == G_NONE || RANK[clamp(ga, 0, 10)] < RANK[clamp(g, 0, 10)]) { continue; }
		if (tt_ground(t + b) == ga && tt_ground(t + a + b) == ga) {
			alt = ga;
			return k;
		}
	}
	return -1;
}

// Landscape at a point of tile t (uv 0..1 in the tile).
int tt_ground_at(ivec2 t, vec2 uv) {
	int g = tt_ground(t);
	int alt;
	int k = tt_ground_cut(t, g, alt);
	if (k >= 0) {
		vec2 tip = vec2(float(k == 1 || k == 2), float(k >= 2));
		if (abs(uv.x - tip.x) + abs(uv.y - tip.y) < 1.0) { return alt; }
	}
	return g;
}

int tt_town(ivec2 t) {
	return tt_cell(t) >> 2;
}

// Share of a town tile's house blocks that hold a house (by town class).
float tt_house_share(int town) {
	return town >= 2 ? 1.0 : town == 1 ? 0.15 : 0.0; // towns fully built (Kritik r7: no bare lawn)
}

// Quarter tiles: a quarter is one block of its data tile's 2 x 2 grid and
// holds a house where the data tile has one there (the same count of houses
// as the 0.5 km tiles show).
bool tt_sub_house(ivec2 t, int town) {
	int k = (t.x & 1) + 2 * (t.y & 1);
	int count = town == 3 ? 4 : max(int(round(tt_house_share(town) * 4.0)), town > 0 ? 1 : 0);
	int rank = (k * 3 + int(tt_hash(vec2(t >> ivec2(1))) * 4.0)) % 4;
	return rank < count;
}

// Display relief at a tile corner. The baked relief rises at most
// m_per_level per tile_km (tools/build_tile_terrain.py, sc2k_relief), so the
// rounded levels of neighbouring corners differ by at most one.
float tt_corner_height(ivec2 c) {
	// blurred, so level contours run as long clean lines (as in SimCity 2000)
	// instead of single-tile bumps and pits; the blur only lowers slopes
	vec2 uv = tt_node_uv(tt_corner_pos(c));
	float h = textureLod(relief_tex, uv, height_lod + 1.5).r;
	// the blur must not lift the land next to the water: cap it with the sharp
	// water envelope, which rises one level per tile from every shore
	return shore_ready ? min(h, textureLod(shore_tex, uv, 0.0).r) : h;
}

// The far levels' rising height scale (tools/build_tile_terrain.py
// LEVEL_STEPS_M): the heights where the count reaches 0, 1, 2, ... levels,
// 600 m per level above the last (LEVEL_BEYOND_M).
const float LEVEL_STEPS_M[12] = float[](100.0, 250.0, 450.0, 700.0, 1000.0, 1300.0, 1600.0, 1900.0, 2200.0, 2500.0, 2900.0, 3400.0);
const float LEVEL_BEYOND_M = 600.0;
float tt_far_level_x(float m) {
	if (m <= LEVEL_STEPS_M[0]) { return 0.0; }
	for (int k = 1; k < 12; k++) {
		if (m < LEVEL_STEPS_M[k]) {
			return float(k - 1) + (m - LEVEL_STEPS_M[k - 1]) / (LEVEL_STEPS_M[k] - LEVEL_STEPS_M[k - 1]);
		}
	}
	return 11.0 + (m - LEVEL_STEPS_M[11]) / LEVEL_BEYOND_M;
}

// The near levels' scale (tools/build_tile_terrain.py NEAR_STEPS_M) at 0.5 km
// tiles, twice the metres at 1 km: 20 m levels in the lowlands, so Rome's
// hills and gentle land show as terraces, 50 m above 120 m, 60 m above 420 m
// (at 1 km tiles 240 m levels above 840 m, tools NEAR_BEYOND_M per level).
const float NEAR_STEPS_M[13] = float[](0.0, 20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 170.0, 220.0, 270.0, 320.0, 370.0, 420.0);
float tt_near_beyond_m() { return tt_data_km() < 1.0 ? 60.0 : 120.0; }
float tt_near_level_x(float metres) {
	float m = max(metres, 0.0) * (0.5 / tt_data_km());
	for (int k = 1; k < 13; k++) {
		if (m < NEAR_STEPS_M[k]) {
			return float(k - 1) + (m - NEAR_STEPS_M[k - 1]) / (NEAR_STEPS_M[k] - NEAR_STEPS_M[k - 1]);
		}
	}
	return 12.0 + (m - NEAR_STEPS_M[12]) / tt_near_beyond_m();
}

float tt_level_x(float metres) {
	return !levels_ready ? max(metres, 0.0) / m_per_level : near_scale ? tt_near_level_x(metres) : tt_far_level_x(metres);
}

// Metres of a height in levels (the inverse of tt_level_x).
float tt_level_metres(float x) {
	if (!levels_ready) { return x * m_per_level; }
	x = max(x, 0.0);
	if (near_scale) {
		float m = x >= 12.0 ? NEAR_STEPS_M[12] + (x - 12.0) * tt_near_beyond_m()
			: mix(NEAR_STEPS_M[int(floor(x))], NEAR_STEPS_M[min(int(floor(x)) + 1, 12)], fract(x));
		return m * (tt_data_km() / 0.5);
	}
	if (x >= 11.0) { return LEVEL_STEPS_M[11] + (x - 11.0) * LEVEL_BEYOND_M; }
	int k = int(floor(x));
	return mix(LEVEL_STEPS_M[k], LEVEL_STEPS_M[k + 1], fract(x));
}

// Rome's landmarks (tile_terrain.gd): their blocks (world x0, z0, x1, z1) are
// flat at their own level up close, and carry no houses.
uniform vec4 landmark_rects[8];
uniform float landmark_levels[8];
uniform int landmark_count = 0;

bool tt_in_landmark(vec2 p) {
	for (int k = 0; k < landmark_count; k++) {
		vec4 r = landmark_rects[k];
		if (p.x > r.x && p.y > r.y && p.x < r.z && p.y < r.w) { return true; }
	}
	return false;
}

// p within m (km) of a landmark block: a house there would reach into it
bool tt_near_landmark(vec2 p, float m) {
	for (int k = 0; k < landmark_count; k++) {
		vec4 r = landmark_rects[k];
		if (p.x > r.x - m && p.y > r.y - m && p.x < r.z + m && p.y < r.w + m) { return true; }
	}
	return false;
}

float tt_landmark_level(vec2 p, float l) {
	for (int k = 0; k < landmark_count; k++) {
		vec4 r = landmark_rects[k];
		if (p.x >= r.x && p.y >= r.y && p.x <= r.z && p.y <= r.w) { return landmark_levels[k]; }
	}
	return l;
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
	return max(round(tt_level_x(metres)), 1.0);
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
	if (sub_tiles) {
		vec4 v;
		// beyond the window: the data corner below (only the margin of a far view)
		float l = tt_sub_texel(c, v) ? v.b : round(texelFetch(levels_tex, (c >> ivec2(1)) - levels_origin, 0).r * 255.0);
		return landmark_count > 0 ? tt_landmark_level(tt_corner_pos(c), l) : l;
	}
	if (levels_ready) {
		// baked with the same rules (tools/build_tile_terrain.py, corner_levels
		// and near_corner_levels), shores and lakes included
		ivec2 q = c - levels_origin;
		ivec2 n = textureSize(levels_tex, 0);
		if (q.x < 0 || q.y < 0 || q.x >= n.x || q.y >= n.y) { return 0.0; }
		float l = round(texelFetch(levels_tex, q, 0).r * 255.0);
		return landmark_count > 0 ? tt_landmark_level(tt_corner_pos(c), l) : l;
	}
	ivec2 nb[4] = ivec2[](c, c - ivec2(1, 0), c - ivec2(0, 1), c - ivec2(1, 1));
	bool shore = false;
	float lake = 1.0e6;
	for (int k = 0; k < 4; k++) {
		int w = tt_water(nb[k]);
		shore = shore || w == W_SEA;
		if (w == W_LAKE) { lake = min(lake, tt_lake_level(nb[k])); }
	}
	float l = max(1.0, tt_clean_level(c, round(tt_corner_x(c))));
	// corners at the sea or a lake sit at the water line: the shore ramps in
	return shore ? 0.0 : min(l, lake);
}

// SimCity 2000 shore: the water lies a little below the land, so the land
// ends in a low earth edge.
uniform float water_drop = 0.3; // levels
float tt_water_drop() {
	return water_drop;
}

// Coast cut of a land tile: with the sea (or a lake) on two neighbouring sides
// and on the diagonal between them, the half of the tile on that side is
// water too (cut along the tile diagonal), so a staircase of water tiles
// reads as a 45-degree coast, as in SimCity 2000. Returns the corner at the
// tip of the wet half (0..3), or -1.
// nb: tt_cell of the side neighbours (N, E, S, W), which the caller often has.
int tt_coast_cut_nb(ivec2 t, int cell, int nb[4]) {
	if ((cell & 3) != W_LAND || (cell >> 2) >= 2) {
		return -1;
	}
	const ivec2 S[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
	for (int k = 0; k < 4; k++) {
		int a = nb[k] & 3;
		int b = nb[(k + 1) & 3] & 3;
		bool wet = (a == W_SEA || a == W_LAKE) && b == a;
		bool rest_dry = (nb[(k + 2) & 3] & 3) != a && (nb[(k + 3) & 3] & 3) != a;
		if (wet && rest_dry && tt_water(t + S[k] + S[(k + 1) & 3]) == a) {
			return (k + 1) & 3;
		}
	}
	return -1;
}

int tt_coast_cut(ivec2 t) {
	int nb[4] = int[](tt_cell(t + ivec2(0, -1)), tt_cell(t + ivec2(1, 0)), tt_cell(t + ivec2(0, 1)), tt_cell(t + ivec2(-1, 0)));
	return tt_coast_cut_nb(t, tt_cell(t), nb);
}

// Lake corner cut, the coast cut turned round: a lake tile at a corner of its
// lake (land on two neighbouring sides and on the diagonal between them, the
// lake on the other two) is land on the half towards that corner, so a lake
// of a few tiles has 45-degree corners and not the outline of a box. Not
// where those land tiles are cut themselves (a staircase shore), which would
// draw the shore twice. Returns the corner at the tip of the wet half, or -1.
int tt_lake_corner_cut(ivec2 t, int nb[4]) {
	const ivec2 S[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
	for (int k = 0; k < 4; k++) {
		int a = nb[k] & 3;
		int b = nb[(k + 1) & 3] & 3;
		bool dry = (a == W_LAND || a == W_RIVER) && (b == W_LAND || b == W_RIVER);
		bool rest_wet = (nb[(k + 2) & 3] & 3) == W_LAKE && (nb[(k + 3) & 3] & 3) == W_LAKE;
		int d = tt_water(t + S[k] + S[(k + 1) & 3]);
		if (dry && rest_wet && (d == W_LAND || d == W_RIVER)
				&& tt_coast_cut(t + S[k]) < 0 && tt_coast_cut(t + S[(k + 1) & 3]) < 0) {
			return (k + 3) & 3;
		}
	}
	return -1;
}

// Level of the water in the wet half of a cut tile (tip corner a).
float tt_cut_level(ivec2 t, int a) {
	const ivec2 S[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
	ivec2 n = t + S[a];
	return tt_water(n) == W_LAKE ? tt_lake_level(n) - tt_water_drop() : -tt_water_drop();
}

// Quarter tile t holds a lot (a house on its terrace block, or a paved
// street block: tile_props.gdshader). The corners are the data corners
// (tt_land_corner), not tt_corners, which lowers the tiles south of the lots.
bool tt_sub_lot(ivec2 t) {
	int cell = tt_cell(t);
	int town = cell >> 2;
	if ((cell & 3) != W_LAND || town == 0 || !tt_sub_house(t, town)) { return false; }
	// now and then a small paved square in the city core (the lot models
	// bring their own gardens)
	if (town == 3 && tt_hash(vec2(t) * 1.91 + 0.7) < 0.06) { return false; }
	// a village house only on a flat quarter (a town's lots stand on terraces)
	if (town < 2) {
		vec4 q = vec4(tt_land_corner(t), tt_land_corner(t + ivec2(1, 0)), tt_land_corner(t + ivec2(1, 1)), tt_land_corner(t + ivec2(0, 1)));
		if (max(max(q.x, q.y), max(q.z, q.w)) - min(min(q.x, q.y), min(q.z, q.w)) >= 0.01) { return false; }
	}
	// the whole house off the landmark blocks
	return !tt_near_landmark(world_min + (vec2(t) + 0.5) * tile_km, 0.45 * tile_km);
}

// Levels of the four corners (c00, c10, c11, c01) of tile t.
vec4 tt_corners(ivec2 t) {
	int w = tt_water(t);
	if (w == W_SEA) {
		return vec4(-tt_water_drop());
	}
	if (w == W_LAKE) {
		return vec4(tt_lake_level(t) - tt_water_drop());
	}
	vec4 l = vec4(
		tt_land_corner(t),
		tt_land_corner(t + ivec2(1, 0)),
		tt_land_corner(t + ivec2(1, 1)),
		tt_land_corner(t + ivec2(0, 1)));
	// up close the ground south of a lot is level with the lot's lowest corner
	// along their side, so the lot's terrace wall shows to the camera as a
	// whole rectangle; it was a triangle wherever the ground fell sideways
	// (Kritik r9). The neighbours' walls (tile_terrain.gdshader) close the step.
	if (sub_tiles && w == W_LAND && l.x != l.y && tt_sub_lot(t - ivec2(0, 1)) && !tt_sub_lot(t)) {
		l.xy = vec2(min(l.x, l.y));
	}
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

// ------------------------------------------------- quarter tiles (sub_tex)
// Evaluated by tile_sub_prep.gdshader on the data tiles (sub_tiles off).

// Cell of quarter tile s. The quarter at the tip of a coast cut data tile is
// water, and the rule cuts the two beside it again, so the coast keeps its
// 45-degree line through the data tile.
int tt_sub_cell(ivec2 s) {
	ivec2 t = s >> ivec2(1);
	int cell = tt_cell(t);
	int cut = tt_coast_cut(t);
	const ivec2 C[4] = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(0, 1));
	const ivec2 S[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
	if (cut >= 0 && (s & ivec2(1)) == C[cut]) { return tt_water(t + S[cut]); }
	return cell;
}

// Landscape of quarter tile s: the quarter at the tip of a split data tile
// takes the other landscape, so the split stays one diagonal as well.
int tt_sub_ground(ivec2 s) {
	ivec2 t = s >> ivec2(1);
	int g = tt_ground(t);
	const ivec2 C[4] = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(0, 1));
	int cut = tt_coast_cut(t);
	if (cut >= 0) { return (s & ivec2(1)) == C[cut] ? G_NONE : g; }
	int wet = tt_water(t);
	if (wet == W_SEA || wet == W_LAKE) { return g; }
	int alt;
	int k = tt_ground_cut(t, g, alt);
	return k >= 0 && (s & ivec2(1)) == C[k] ? alt : g;
}

// Level of quarter corner s (its tile's corner c00). The data corners keep
// their level; a corner between two or four of them takes the highest, so
// every data ramp becomes a flat quarter on the upper terrace and a quarter
// ramp below it (SimCity 2000 terraces: three quarters of the tiles are flat),
// and next to the water the lowest, so the shore stays at the water line.
float tt_sub_corner(ivec2 s) {
	ivec2 p = s >> ivec2(1);
	ivec2 o = s & ivec2(1);
	float a = tt_land_corner(p);
	float lo = a;
	float hi = a;
	if (o.x == 1) { float b = tt_land_corner(p + ivec2(1, 0)); lo = min(lo, b); hi = max(hi, b); }
	if (o.y == 1) { float b = tt_land_corner(p + ivec2(0, 1)); lo = min(lo, b); hi = max(hi, b); }
	if (o.x == 1 && o.y == 1) { float b = tt_land_corner(p + ivec2(1, 1)); lo = min(lo, b); hi = max(hi, b); }
	if (lo == hi) { return a; }
	for (int k = 0; k < 4; k++) {
		int w = tt_sub_cell(s - ivec2(k & 1, k >> 1)) & 3;
		if (w == W_SEA || w == W_LAKE) { return lo; }
	}
	return hi;
}
