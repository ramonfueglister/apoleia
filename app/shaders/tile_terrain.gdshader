// Tile terrain surface. One MultiMesh instance per tile of the patch; the
// instance mesh holds the tile top (two triangles) and four walls. The vertex
// stage reads the tile data and builds the stepped surface, so no terrain
// geometry is ever built on the CPU.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/coast_steps.gdshaderinc"

uniform vec3 light_dir = vec3(-0.6, 0.67, -0.2); // towards the sun, world
// The slope and wall tones take the SimCity 2000 light of tt_art_light, not
// the sun of the weather (which still lights the tops and the props).
uniform float slope_light = 0.9;                 // SimCity 2000 slope contrast
uniform int house_grid = 2;                      // house blocks per tile side
uniform bool town_props = true;                  // houses are drawn as models at this level
uniform ivec2 prop_origin;                       // the tiles that have them (tile_props.gdshader)
uniform int prop_n = 96;
// Two RGBA16F pixels per tile, prepared by tile_flags_prep.gdshader.
uniform sampler2D flags_tex : filter_nearest, repeat_disable;

varying vec3 world_pos;
varying vec2 tile_uv;
varying flat int part;
varying flat ivec2 tile;
varying flat int water;
varying flat float coast;
varying flat float flat_top;
varying flat float body_level;
varying flat int shore_sides; // land tile: bit k = sea across side k, bit 4 + k = sea at corner k only (sea tile: land_sides);
                              // from bit 16 the steps of the shore round its data tile (cs_steps)
varying flat int cut_tip;     // coast cut: corner at the tip of the wet half, or -1
// Metal allows 31 varying components in all (Godot uses some itself), so
// small flags share an int
varying flat int side_bits;   // bit k: core town tile, no town across side k; bit 4 + k: river tile, water across side k
varying flat int shore_lake;  // 1: that water is a lake
varying flat int wet_tri;     // the wet half of a coast cut tile
varying flat int ground_bits; // landscape of the tile (bits 0-3), of the cut half (4-7), cut corner + 1 (8-10, 0: none)
// Shadows on the water (round K): Urbek's water keeps its light blue in a
// shadow, only a little darker; under our blue ambient light a wall's
// shadow lay on the sea in near black blue (Mac check I + J, Naples).
// Written in fragment(), read in light(): the share of a cast shadow the
// water keeps.
varying float shadow_share;
const float WATER_SHADOW = 0.35;
// The share of the slope tones kept far out, on the sun side and on the
// shade sides (fragment(), round L)
const float FAR_SUN_TONE = 0.3;
const float FAR_SHADE_TONE = 0.6;
// From the 2 km tiles the coast is a line through the 2 km sea distance
// (tt_sea_distance: 0 on a land node, 2 km on the sea nodes beside it), at
// CONTOUR_SD, instead of the tiles' edges (round M: on the map of Europe
// the coasts were staircases of 8 km tiles; Ramon's landscape reference
// draws them smooth; CONTOUR_KM in tile_terrain.gdshaderinc)
const float CONTOUR_SD = 1.0;

// Palette after Urbek (Ramon, 28.10.2026): one flat colour per landscape,
// measured from Urbek screenshots (urbek-landschaft-*.jpg): fresh light
// greens, pale wheat, flat light water. Indexed by G_*. The values
// are darker than they appear: sun, ambient and the filmic tone map lift them
// to the Urbek colours on screen (e.g. meadow shows as #428c34).
const vec3 GROUND_RGB[11] = vec3[](
	vec3(0.325, 0.525, 0.298),  // meadow (Urbek grass, #73af5f on screen)
	vec3(0.451, 0.525, 0.298),  // dry grass (Urbek's yellow grass, #9baf5f)
	vec3(0.631, 0.608, 0.369),  // field (Urbek wheat, #cdc373)
	vec3(0.278, 0.447, 0.282),  // wetland
	vec3(0.400, 0.447, 0.278),  // scrub
	vec3(0.655, 0.580, 0.408),  // sand
	vec3(0.165, 0.300, 0.150),  // forest floor (between the crowns, #2c5e26-#33692c)
	vec3(0.173, 0.302, 0.224),  // conifer forest
	vec3(0.396, 0.561, 0.322),  // alpine meadow
	// rock as far out (#c4b290, light limestone): the grey #9e928a laid the
	// Abruzzo tops at 8 km out like concrete (Kritik r16), and the crests
	// changed colour between the 0.5 and the 1 km tiles
	vec3(0.561, 0.519, 0.413),  // rock
	// snow as far out (#e8e4dc): at the cotton white #f3f6f8 the tone map
	// clipped it, a riser stood 2 % below the flat (Kritik r15, Mont Blanc
	// at 8 km a blank sheet) and the shade fell lavender under the blue sky
	vec3(0.860, 0.845, 0.810)   // snow
);
// Far out (from 1 km tiles) the land stays Urbek green, a touch cooler than
// up close (the painted olive strip, gauntlet refs/gemalt-weit-mittel-nah.png,
// read as a dull military map, the Po plain and Hungary as desert): on screen
// about meadow #70a860 (Urbek's grass, refs urbek-landschaft-03), farmland
// a value lighter #94b862 (as yellow #bcb868 the plains and steppes still
// read as a yellowed map, Kritik r11; with the blue of #84b474 they turned
// mint, Kritik r14), dry grass #b0ba62, forest #407c38, light rock #c4b290
// on the crests, a deep sea #19588c. Open land also takes a flat tint per height band, so hills
// and ranges read as areas and not only by their ramps.
const vec3 GROUND_FAR[11] = vec3[](
	vec3(0.324, 0.506, 0.290),  // meadow
	vec3(0.495, 0.568, 0.300),  // dry grass
	vec3(0.420, 0.556, 0.300),  // field (farmland: a lighter, warmer meadow)
	vec3(0.310, 0.465, 0.290),  // wetland
	vec3(0.400, 0.470, 0.270),  // scrub
	vec3(0.615, 0.564, 0.451),  // sand (the deserts)
	// woods a third darker than the meadow, not half (at #475b30, L 80,
	// against #a3a461, L 156, they out-shouted the ramps about 5:1)
	vec3(0.250, 0.430, 0.200),  // forest
	vec3(0.200, 0.370, 0.230),  // conifer forest
	vec3(0.390, 0.505, 0.290),  // alpine meadow
	vec3(0.561, 0.519, 0.413),  // rock (the lightest land, so the crests show; it had the lowland's value)
	vec3(0.860, 0.845, 0.810)   // snow (#e8e4dc, not cotton white)
);
const vec3 C_HILLS_FAR = vec3(0.290, 0.470, 0.270); // a deeper green
// mountain pasture, a little greyer than the hills; bare rock only on the
// crests (tools/build_tile_terrain.py ROCK_M): the khaki #958e6c here made
// the Apennines a quarry
const vec3 C_MOUNT_FAR = vec3(0.335, 0.440, 0.275);
const vec3 C_SEA_FAR = vec3(0.111, 0.264, 0.424);   // #19588c on screen
const vec3 C_SHORE_FAR = vec3(0.130, 0.302, 0.506); // #24689e
const vec3 C_SAND = vec3(0.804, 0.745, 0.510);   // beach
const vec3 C_BANK = vec3(0.588, 0.549, 0.392);   // river bank
const vec3 C_EARTH = vec3(0.557, 0.498, 0.408);  // walls
const vec3 C_CLIFF = vec3(0.533, 0.514, 0.475);
// Paving in a warm mid grey as Urbek's pavements (about #a8a194 on screen),
// not the near-white cream of before (#cbbca8, the Roman squares at 3 km read
// as blank paper: 63 % of the picture above V 200, Urbek's towns at 155-187)
const vec3 C_PAVED = vec3(0.530, 0.505, 0.455);
const vec3 C_PLAZA = vec3(0.640, 0.620, 0.580);  // travertine squares of the landmarks, #c4bfb3
const vec3 C_STREET = vec3(0.420, 0.404, 0.384); // Roman basalt paving
const vec3 C_ROOF = vec3(0.580, 0.250, 0.190); // terracotta, not salmon or orange
const vec3 C_WALL = vec3(0.686, 0.627, 0.522);
const vec3 C_QUAY_WALL = vec3(0.57, 0.56, 0.53); // a town's bank over its quay (tile_coast_steps.gdshader C_KERB)
const vec3 C_SEA = vec3(0.314, 0.541, 0.824);   // Urbek water, #6db3df on screen
const vec3 C_SHORE = vec3(0.396, 0.643, 0.953);  // sea tiles that touch the land
const vec3 C_INLAND = vec3(0.275, 0.498, 0.780); // rivers and lakes, a little darker than the sea

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
	ivec2 q = ivec2((tile.x - patch_origin.x) * 2, tile.y - patch_origin.y);
	ivec4 a = ivec4(texelFetch(flags_tex, q, 0) + 0.5);
	ivec4 b = ivec4(texelFetch(flags_tex, q + ivec2(1, 0), 0) + 0.5);
	ground_bits = a.x;
	side_bits = a.y & 255;
	shore_lake = (a.y >> 8) & 1;
	water = (a.y >> 9) & 3;
	shore_sides = a.z | (a.w << 11) | (b.x << 22);
	coast = b.y == 2 ? 1.0 : b.y == 1 ? 0.45 : 0.0;
	int cut = (b.z & 7) - 1;
	int lake_cut = (b.z >> 3) - 1;
	if (part != 0) {
		// The ground diagonal and shore steps belong only to the top.
		int ground = ground_bits & 15;
		ground_bits = ground | (ground << 4);
		shore_sides &= water == W_SEA ? 65535 : 15;
	}
	vec4 own = tt_corners_cached(tile);
	if (lake_cut >= 0) { own = vec4(tt_lake_level(tile)); }
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
	// (no coast cuts where the coast line draws the coast: its diagonal edge
	// would stand beside the line)
	cut_tip = cut;
	int split = cut >= 0 ? (cut + 1) & 3 : (abs(own.x - own.z) <= abs(own.y - own.w) ? 0 : 1);
	float cut_level = lake_cut >= 0 ? own.x - tt_water_drop() : cut >= 0 ? tt_cut_level(tile, cut) : 0.0;
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
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

// near palette (Urbek) on the 0.5 km tiles, the painted one from 1 km tiles
float far_share() { return clamp((tile_km - 0.5) / 0.5, 0.0, 1.0); }

// `band`: height band of the tile (0 lowland, 1-2 hills, 3 and up mountains)
vec3 ground_rgb_at(int g, float band) {
	g = clamp(g, 0, 10);
	vec3 far = GROUND_FAR[g];
	bool open = g == G_MEADOW || g == G_DRY_GRASS || g == G_FIELD || g == G_WETLAND || g == G_SCRUB || g == G_ALPINE;
	if (open && band >= 1.0) {
		far = band >= 3.0 ? mix(far, C_MOUNT_FAR, 0.75) : mix(far, C_HILLS_FAR, band >= 2.0 ? 0.8 : 0.5);
	}
	if ((g == G_FOREST || g == G_CONIFER) && band >= 2.0) { far = mix(far, GROUND_FAR[G_CONIFER] * 0.85, 0.6); }
	return mix(GROUND_RGB[g], far, far_share());
}

vec3 ground_rgb(int g) {
	return GROUND_RGB[clamp(g, 0, 10)];
}

// the grain economy from the sim on this palette (fields, paths, roads)
#include "res://shaders/sim_map.gdshaderinc"

// Distance (in tile units) of `uv` from the tile edge on the sides set in
// `mask` (bits 0..3), or from the corners set in bits 4..7.
float side_distance_at(int mask, vec2 uv) {
	float d = 10.0;
	if ((mask & 1) != 0) { d = min(d, uv.y); }
	if ((mask & 2) != 0) { d = min(d, 1.0 - uv.x); }
	if ((mask & 4) != 0) { d = min(d, 1.0 - uv.y); }
	if ((mask & 8) != 0) { d = min(d, uv.x); }
	for (int k = 0; k < 4; k++) {
		if ((mask & (16 << k)) != 0) { d = min(d, length(uv - vec2(CORNER[k]))); }
	}
	return d;
}

float side_distance(int mask) {
	return side_distance_at(mask, tile_uv);
}

// The data tile under this tile, and `uv` (this tile's units) on it.
ivec2 data_tile() {
	return sub_tiles ? tile >> ivec2(1) : tile;
}

vec2 data_uv(vec2 uv) {
	return sub_tiles ? (vec2(tile & ivec2(1)) + uv) * 0.5 : uv;
}

// The sides (bits 0-3) and corners (4-7) of a sea tile whose shore has
// steps in front, so the water measures from their front instead: all of a
// quarter tile in a coast cut's stair.
int stepped_sides() {
	int steps = shore_sides >> 16;
	if ((steps & 4096) != 0) { return 255; }
	int m = 0;
	for (int k = 0; k < 4; k++) {
		if (((steps >> (3 * k)) & 7) != 0) { m |= 1 << k; }
	}
	return m;
}

// Tile units from the front of those steps at `uv`, or 10.
float steps_front(vec2 uv) {
	return cs_steps_front(data_tile(), shore_sides >> 16, data_uv(uv)) * (sub_tiles ? 2.0 : 1.0);
}

// A sea tile with a town's quay (coast_steps.gdshaderinc) along a side.
bool quay_tile() {
	int steps = shore_sides >> 16;
	if (steps == 0 || (steps & 4096) != 0 || water != W_SEA) { return false; }
	for (int k = 0; k < 4; k++) {
		if (((steps >> (3 * k)) & 7) != 0 && cs_quay(data_tile(), k)) { return true; }
	}
	return false;
}

// The wet half of a coast cut with a stair of steps on its diagonal.
bool cut_stair() {
	return ((shore_sides >> 16) & 4096) != 0;
}

// Up close the coast comes in voxel steps, as Urbek's: the beach, the sand
// at the foot of the shore and the shallows are cells of about COAST_CELL_KM
// (1.3 diorama metres), each all sand (or all shallow water) or none, by its
// centre's distance from the shore against a width that wanders along the
// coast, so the waterline has coves of wide sand and bare headlands
// (COAST_BAY_KM across, coast_steps.gdshaderinc). From 2 km tiles the plain
// bands of before (a cell would be a pixel).

// Centre (tile units) of the cell around this pixel, or the pixel far out.
vec2 coast_cell() {
	if (tile_km > 1.0) { return tile_uv; }
	float n = round(tile_km / COAST_CELL_KM);
	return (floor(tile_uv * n) + 0.5) / n;
}

// 0..1 along the coast, the same over a cell (`cell` from coast_cell, `p` the
// pixel's world position)
float coast_wander(vec2 cell, vec2 p) {
	return tt_noise((p + (cell - tile_uv) * tile_km) / COAST_BAY_KM);
}

// Surf along the coast up close, as in Islanders: one thin white line where
// the sea meets the land, breathing a little (Ramon 30.10.2026 "Dezenter":
// Urbek has no surf at all, the second line that drifted out from it went).
// Distance in tiles from the nearest land side or corner (on a coast cut,
// from the diagonal; in front of steps, from their front), less `reach`,
// the sand it breaks on; gone from 2 km tiles, where it would be a
// hairline.
const vec3 C_FOAM = vec3(0.900, 0.955, 1.000);
vec3 shore_foam(vec3 c, vec2 p, float reach) {
	if (tile_km >= 2.0) { return c; }
	float d = 10.0;
	if (wet_tri == 1 && cut_tip >= 0) {
		vec2 tip = vec2(CORNER[cut_tip]);
		d = cut_stair() ? steps_front(tile_uv) : -(abs(tile_uv.x - tip.x) + abs(tile_uv.y - tip.y) - 1.0) * 0.7071;
	} else if (coast >= 1.0) {
		int mask = 0;
		for (int k = 0; k < 4; k++) {
			if (tt_water(tile + SIDE[k]) == W_LAND) { mask |= 1 << k; }
			if (tt_water(tile + SIDE[k] + SIDE[(k + 1) % 4]) == W_LAND) { mask |= 16 << ((k + 1) % 4); }
		}
		d = min(side_distance(mask & ~stepped_sides()), steps_front(tile_uv));
	}
	d -= reach;
	if (d > 1.0) { return c; }
	float aa = fwidth(d) + 1e-4;
	float t = TIME + tt_hash(vec2(tile)) * 0.6; // neighbouring tiles a little out of step
	float band = 0.035 + 0.01 * sin(t * 1.3);
	float surf = 1.0 - smoothstep(band - aa, band + aa, d);
	float fade = 1.0 - smoothstep(1.0, 2.0, tile_km);
	return mix(c, C_FOAM, surf * 0.7 * fade);
}

// The sea by the coast line (CONTOUR_KM on): the shallows' blue at the line,
// fading into the deep blue over a tile (`sd`: tt_sea_distance, km)
vec3 contour_sea_rgb(float sd) {
	float far = far_share();
	float seam = 1.0 - smoothstep(CONTOUR_SD, CONTOUR_SD + tile_km, sd);
	return mix(mix(C_SEA, C_SEA_FAR, far), mix(C_SHORE, C_SHORE_FAR, far), seam);
}

// The land the coast line lays over a sea tile: the landscape of the
// nearest land tile, at the foot of its ramp (band 0, no tone), so it runs
// on into that tile without an edge
vec3 contour_land_rgb(vec2 p) {
	vec2 q = (p - world_min) / tile_km;
	ivec2 t = ivec2(floor(q));
	float best = 1e9;
	int g = G_MEADOW;
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 n = t + ivec2(dx, dz);
			int w = tt_water(n);
			vec2 uv = clamp(q - vec2(n), 0.0, 1.0);
			float d = length(q - vec2(n) - uv);
			if (w != W_SEA && w != W_LAKE && d < best) {
				best = d;
				g = tt_ground_at(n, uv);
			}
		}
	}
	return ground_rgb_at(g, 0.0);
}

// The coast by the line over colour `c`: a sand seam on the land side, about a
// pixel wide (thinner on the map, else islets of a node or two read as
// beige specks, as the one-tile islands did), and the sea beyond the line;
// `aa`: its antialiasing (km), `low` (0..1) where the line may lay the sea
// (see the land tiles)
vec3 contour_shore(vec3 c, float sd, float aa, float px_km, float low) {
	float w = clamp(px_km, 0.25, 0.5);
	float sand = smoothstep(CONTOUR_SD - w - aa, CONTOUR_SD - w + aa, sd);
	float wet = smoothstep(CONTOUR_SD - aa, CONTOUR_SD + aa, sd);
	c = mix(c, C_SAND, sand * 0.85 * low);
	return mix(c, contour_sea_rgb(sd), wet * low);
}

// Rivers by their lines (round N): from the 2 km tiles out the rivers were a
// staircase of tile bands across the map of Europe, as the 4-connected cells
// run; Ramon's landscape reference lets them wind. river_tex (rivers.png,
// tools/build_tile_terrain.py river_line_field) keeps at every 2 km node the
// nearest point of the nearest river line, the line's direction and its bend
// there; each of the 3 x 3 nodes around a pixel draws a short arc through
// its point (straight pieces stood out of every bend as spurs).
uniform sampler2D river_tex : filter_nearest, repeat_disable;
uniform bool river_ready = false;
const float RIVER_REACH = 2.0;     // nodes (RIVER_FIELD_NODES)
const float RIVER_BEND_MAX = 2.5;  // 1 / radius per node step
const float RIVER_ARC = 0.7;       // half an arc, nodes

// Distance (km) from p to the nearest river shown at this zoom (the bake's
// RIVER_RANK: Natural Earth scalerank up to 8 on the 2 km tiles, one less
// each zoom out), 1e3 where none; `rank` its scalerank.
float river_distance(vec2 p, out float rank) {
	float node_km = world_size.x / (grid_size.x - 1.0);
	vec2 g = (p - world_min) / node_km;
	ivec2 c = clamp(ivec2(round(g)), ivec2(1), ivec2(grid_size) - 2);
	float rank_max = 10.0 - round(log2(tile_km / 0.5));
	float best = 1e3;
	rank = 10.0;
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 n = c + ivec2(dx, dz);
			vec4 t = round(texelFetch(river_tex, n, 0) * 255.0);
			float r = mod(t.a, 16.0);
			float k = (floor(t.a / 16.0) - 8.0) / 7.0 * RIVER_BEND_MAX;
			vec2 at = vec2(n) + (t.rg - 128.0) / 127.0 * RIVER_REACH;
			float an = t.b / 256.0 * PI;
			vec2 dir = vec2(cos(an), sin(an));
			vec2 v = g - at;
			float along = dot(v, dir);
			float across = dot(v, vec2(-dir.y, dir.x));
			// an arc across = k along^2 / 2, shorter in a tight bend
			float half_len = clamp(1.0 / max(abs(k), 1e-3), 0.35, RIVER_ARC);
			float a = clamp(along, -half_len, half_len);
			float d = abs(across - 0.5 * k * a * a) / sqrt(1.0 + k * a * k * a);
			d = length(vec2(d, along - a)) * node_km;
			bool shown = t.a > 0.5 && r <= rank_max;
			rank = shown && d < best ? r : rank;
			best = shown ? min(best, d) : best;
		}
	}
	return best;
}

// The river over colour `c` (contour zooms): at least a pixel and a half
// wide, the big rivers (scalerank 4 and less) as wide as the tile bands were
// (no early return before the fetches: texelFetch behind early returns,
// inlined, crashed Apple's Metal compiler, PR #51)
vec3 contour_river(vec2 p, vec3 c, float px_km) {
	float rank;
	float d = river_distance(p, rank);
	float w = rank <= 4.0 ? 0.175 : rank <= 6.0 ? 0.125 : 0.09;
	float half_w = max(w, 0.75 * px_km);
	float aa = 0.5 * px_km;
	float river = (1.0 - smoothstep(half_w - aa, half_w + aa, d)) * (river_ready ? 1.0 : 0.0);
	return mix(c, mix(C_INLAND, C_SHORE_FAR, far_share()), river);
}

// Mountains by the heights (round N): from the 2 km tiles out a tile is one
// level step and its ramp tone, so the Alps at 1500 km were a beige plateau
// of 8 km rock tiles with a few terraces; Ramon's landscape reference draws
// ridges and valleys, rock and snow on the crests and wooded flanks. The
// relief now comes from the 2 km height nodes (height_tex, the diorama
// metres), one tone per node triangle as SimCity 2000 tiles split
// (facets), lit by the art light; rock and snow lie by the node height.
const float RELIEF_EXAG = 1.875;  // height over width of the node facets
const float RELIEF_AMP = 0.9;     // tone per unit of light above the flat
const float ROCK_H = 1150.0;      // diorama metres (Mont Blanc's node 1673, Gran Sasso's 1291)
const float SNOW_H = 1600.0;

// The tone of the node facet under p (1 on the flat)
float contour_relief(vec2 p, vec3 art) {
	float node_km = world_size.x / (grid_size.x - 1.0);
	vec2 g = (p - world_min) / node_km;
	ivec2 i = clamp(ivec2(floor(g)), ivec2(0), ivec2(grid_size) - 2);
	vec2 f = g - vec2(i);
	float h00 = texelFetch(height_tex, i, 0).r;
	float h10 = texelFetch(height_tex, i + ivec2(1, 0), 0).r;
	float h11 = texelFetch(height_tex, i + ivec2(1, 1), 0).r;
	float h01 = texelFetch(height_tex, i + ivec2(0, 1), 0).r;
	// split at the diagonal whose corners are closer in height
	bool split0 = abs(h00 - h11) <= abs(h10 - h01);
	vec2 grad = split0 ? (f.x >= f.y ? vec2(h10 - h00, h11 - h10) : vec2(h11 - h01, h01 - h00))
		: (f.x + f.y <= 1.0 ? vec2(h10 - h00, h01 - h00) : vec2(h11 - h01, h11 - h10));
	grad *= RELIEF_EXAG / (node_km * 1000.0);
	vec3 n = normalize(vec3(-grad.x, 1.0, -grad.y));
	return 1.0 + clamp((dot(n, art) - art.y) * RELIEF_AMP, -0.3, 0.2);
}

// Rock and snow by the node height (frayed a little, so they follow the
// crests and not height lines); a mountain tile (alpine, rock, snow) below
// the rock is wood where the land cover is wooded, else alpine meadow
vec3 contour_mountain(vec2 p, int g, vec3 c, float band) {
	float n = tt_noise(p / 5.0) - 0.5;
	float h = tt_height_m(p, 0.0) + n * 120.0;
	if (g == G_ALPINE || g == G_ROCK || g == G_SNOW) {
		float wood = textureLod(cover_tex, tt_node_uv(p), 0.0).r + n * 0.2;
		c = ground_rgb_at(wood > 0.4 ? G_FOREST : G_ALPINE, band);
	}
	float aa = fwidth(h) * 0.75 + 1.0;
	c = mix(c, ground_rgb_at(G_ROCK, band), smoothstep(ROCK_H - aa, ROCK_H + aa, h));
	return mix(c, ground_rgb_at(G_SNOW, band), smoothstep(SNOW_H - aa, SNOW_H + aa, h));
}

// The landscape's far colour on the map (CONTOUR_KM on): open land and
// woods turn into the hills' and mountains' tones with the height of the
// point itself (`band`: its level less one), not in one step per tile as
// ground_rgb_at's bands, which laid the hills out in tile blocks (round P)
vec3 contour_ground_tone(int g, float band) {
	g = clamp(g, 0, 10);
	vec3 far = GROUND_FAR[g];
	bool open = g == G_MEADOW || g == G_DRY_GRASS || g == G_FIELD || g == G_WETLAND || g == G_SCRUB || g == G_ALPINE;
	if (open) {
		vec3 hills = mix(far, C_HILLS_FAR, mix(0.5, 0.8, smoothstep(1.5, 2.5, band)));
		far = mix(far, hills, smoothstep(0.5, 1.5, band));
		far = mix(far, mix(GROUND_FAR[g], C_MOUNT_FAR, 0.75), smoothstep(2.5, 3.5, band));
	}
	if (g == G_FOREST || g == G_CONIFER) { far = mix(far, GROUND_FAR[G_CONIFER] * 0.85, 0.6 * smoothstep(1.5, 2.5, band)); }
	return far;
}

// The landscape at p on the map (CONTOUR_KM on), from the four tiles around
// it: each weighs by its bilinear share at p, p wandering a little by noise
// (in tiles, so alike at every level), the water tiles nothing; the
// heaviest landscape wins and blends into the next one over about a pixel.
// So the landscapes' borders run round and frayed through the tiles, as in
// Ramon's landscape reference, not along the tiles' edges and diagonals
// (the 8 km mosaic, round P). `g`: the winner; with only water around the
// nearest land tile's (contour_land_rgb). `px_km`: a pixel (km).
vec3 contour_land_soft(vec2 p, float band, float px_km, out int g) {
	vec2 q = (p - world_min) / tile_km - 0.5;
	q += (vec2(tt_noise(q * 0.9), tt_noise(q * 0.9 + 17.3)) - 0.5) * 0.7
		+ (vec2(tt_noise(q * 2.3 + 5.1), tt_noise(q * 2.3 - 8.7)) - 0.5) * 0.3;
	ivec2 i = ivec2(floor(q));
	vec2 f = fract(q);
	int gs[4] = int[](tt_ground(i), tt_ground(i + ivec2(1, 0)), tt_ground(i + ivec2(0, 1)), tt_ground(i + ivec2(1, 1)));
	float ws[4] = float[]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	float best = -1.0;
	float second = 0.0;
	g = G_NONE;
	int g2 = G_NONE;
	for (int k = 0; k < 4; k++) {
		if (gs[k] == G_NONE) { continue; }
		float s = 0.0;
		for (int m = 0; m < 4; m++) { s += gs[m] == gs[k] ? ws[m] : 0.0; }
		if (s > best) {
			if (gs[k] != g) {
				second = max(best, 0.0);
				g2 = g;
			}
			best = s;
			g = gs[k];
		} else if (gs[k] != g && s > second) {
			second = s;
			g2 = gs[k];
		}
	}
	if (g == G_NONE) {
		g = G_MEADOW;
		return contour_land_rgb(p);
	}
	vec3 c = contour_ground_tone(g, band);
	if (g2 != G_NONE) {
		// the weights change by about a tile's share per tile: the blend's
		// width from the pixel's size, not from derivatives (the caller's
		// branches by tile)
		float aa = 1.5 * px_km / tile_km + 1e-4;
		c = mix(contour_ground_tone(g2, band), c, smoothstep(-aa, aa, best - second));
	}
	return c;
}

void fragment() {
	int ground = ground_bits & 15;
	int ground_alt = (ground_bits >> 4) & 15;
	int ground_tip = (ground_bits >> 8) - 1;
	int wall_sides = side_bits & 15;
	int river_sides = side_bits >> 4;
	vec2 p = world_pos.xz;
	vec2 centre = tt_tile_center(tile);
	vec3 art = tt_art_light(INV_VIEW_MATRIX);
	vec3 c;
	float rough = 1.0;
	// the coast line (CONTOUR_KM), its derivatives taken here, outside the
	// branches by tile
	bool contour = tile_km >= CONTOUR_KM;
	float sd = 10.0;
	float ld = 10.0; // and the lakes' shore line (round P)
	if (contour) {
		sd = tt_sea_distance(p);
		ld = tt_lake_distance(p);
	}
	float sd_aa = max(fwidth(sd) * 0.75, 1e-4);
	float ld_aa = max(fwidth(ld) * 0.75, 1e-4);
	float px_km = length(fwidth(p));
	// the rivers and lakes by their lines on the 0.5 and 1 km tiles (round Q)
	vec3 wl = vec3(0.0);
	if (water_lines && part == 0) { wl = tt_water_lines(p); }
	bool sea_px = water == W_SEA; // drawn as sea (sim_muted)
	// the landscape on the map (round P), worked out here once for the land
	// tiles and the land the coast and lake lines lay over the water tiles
	// (one inlined copy of its lookups), only where land is drawn
	float soft_band = max(world_pos.y / level_h - 1.0, 0.0);
	vec3 soft_land = vec3(0.0);
	if (contour && part == 0 && (water != W_SEA || sd < CONTOUR_SD + sd_aa) && (water != W_LAKE || ld > -ld_aa)) {
		int g;
		soft_land = contour_land_soft(p, soft_band, px_km, g);
		soft_land = contour_mountain(p, g, soft_land, soft_band);
	}
	if ((water == W_SEA || water == W_LAKE || wet_tri == 1) && part == 0) {
		// one flat colour per water tile, a lighter one where it touches the
		// land. Up close the shallows are a soft seam that fades into the sea,
		// wide off the coves and narrow off the headlands (Ramon 30.10.2026
		// "Dezenter": the band in voxel steps went; Urbek's water is one calm
		// blue), the wet half of a coast cut lies within it, and in the coves
		// sand lies at the foot of the shore, the surf breaking on it; where
		// the shore comes down in steps (coast_steps.gdshaderinc), at their
		// foot.
		float far = far_share();
		rough = 0.55;
		if (water == W_SEA || (wet_tri == 1 && shore_lake == 0)) {
			bool shallow = wet_tri == 1 || coast >= 1.0;
			float seam = shallow ? 1.0 : 0.0; // how much of the shallows' colour
			float shore_d = 10.0; // tile units from dry land at the cell's centre
			float foot = 0.0;     // the sand's width there
			float reach = 0.0;    // where it ends (on the cell edges)
			if (shallow && tile_km <= 1.0) {
				vec2 cell = coast_cell();
				float wander = coast_wander(cell, p);
				if (wet_tri == 1) {
					vec2 tip = vec2(CORNER[cut_tip]);
					shore_d = cut_stair() ? steps_front(cell) : -(abs(cell.x - tip.x) + abs(cell.y - tip.y) - 1.0) * 0.7071;
					seam = 0.85;
				} else {
					int stepped = stepped_sides();
					float out_d = min(side_distance_at(shore_sides & 255 & ~stepped, tile_uv), steps_front(tile_uv));
					seam = 0.85 * (1.0 - smoothstep(0.03, mix(0.25, 0.6, tt_noise(p / COAST_BAY_KM)), out_d));
					shore_d = min(side_distance_at((shore_sides >> 8) & 255 & ~stepped, cell), steps_front(cell));
				}
				// (none at the foot of a town's quay)
				foot = shore_d < 1.5 && !quay_tile() ? max(0.0, wander * 0.45 - 0.12) : 0.0;
				float n = round(tile_km / COAST_CELL_KM);
				reach = max(0.0, ceil(foot * n - 0.5)) / n;
			}
			c = mix(mix(C_SEA, C_SEA_FAR, far), mix(C_SHORE, C_SHORE_FAR, far), seam);
			if (contour) { c = contour_sea_rgb(sd); }
			c = sim_lanes(p, c, length(fwidth(p)));
			c = shore_foam(c, p, reach);
			if (shore_d < foot) {
				c = C_SAND;
				rough = 1.0;
			}
			// the land the coast line lays over the sea tile, with its sand
			float dry = 1.0 - smoothstep(CONTOUR_SD - sd_aa, CONTOUR_SD + sd_aa, sd);
			if (contour && dry > 0.0) {
				vec3 land = contour_river(p, sim_ways(p, soft_land, px_km), px_km);
				c = mix(contour_shore(land, sd, sd_aa, px_km, 1.0), c, 1.0 - dry);
				rough = dry > 0.5 ? 1.0 : rough;
				sea_px = dry <= 0.5;
			}
		} else {
			c = mix(C_INLAND, C_SHORE_FAR, far); // lakes like the rivers, not deep sea holes
			// by the lake's outline the land runs on over the lake tile (round
			// Q), flat at the level of the shore, the landscape of the land
			// nearest; and the rivers that flow in
			if (water_lines) {
				float wet = max(wl.g, wl.r);
				c = mix(contour_land_rgb(p), c, wet);
				rough = wet > 0.5 ? 0.55 : 1.0;
			}
			// by the lake's shore line the land runs on over the lake tile
			// (flat, at the level of the shore), as on the land tiles
			float dry = smoothstep(-ld_aa, ld_aa, ld);
			if (contour && dry > 0.0) {
				vec3 land = sim_ways(p, soft_land, px_km) * contour_relief(p, art);
				c = mix(c, contour_river(p, land, px_km), dry);
				rough = dry > 0.5 ? 1.0 : rough;
			}
		}
	} else if (part == 0) {
		int town = tt_town(tile);
		// up close a city plan's parcel: its town class (open land and water 0)
		ivec3 plan = tile_km < 0.75 ? cp_texel(cp_parcel(p)) : ivec3(0);
		// Restore the existing river/shore surface under loaded arches.
		// Geometry/corner heights remain untouched: no invented lower water.
		if (cp_verona_bridge_active(cp_parcel(p))) { plan.r = CP_WATER; }
		bool planned = plan.r != CP_NONE;
		if (planned) { town = cp_town(plan.r); }
		// one flat colour per tile; where two landscapes meet, the half towards
		// the corner of the other one takes its colour (cut at the diagonal),
		// in far levels whatever the scale of the tile's own levels; on the
		// map (CONTOUR_KM) soft borders instead
		float band = max((near_scale ? tt_far_level_x(tt_level_metres(body_level)) : body_level) - 1.0, 0.0);
		if (contour) {
			// on the map the landscapes with soft borders and the hills'
			// tones by the height of the point (round P, above)
			band = soft_band;
			c = soft_land;
		} else {
			c = ground_rgb_at(ground, band);
			if (ground_tip >= 0) {
				vec2 tip = vec2(CORNER[ground_tip]);
				float d = (abs(tile_uv.x - tip.x) + abs(tile_uv.y - tip.y) - 1.0) * 0.7071;
				float aa = fwidth(d) * 0.75 + 1e-4;
				c = mix(ground_rgb_at(ground_alt, band), c, smoothstep(-aa, aa, d));
			}
		}
		// inside a town the river banks are paved quays (they were wheat
		// strips through Rome)
		bool quay = water == W_RIVER && tile_km < 2.0 && max(max(tt_town(tile + ivec2(1, 0)), tt_town(tile - ivec2(1, 0))),
				max(tt_town(tile + ivec2(0, 1)), tt_town(tile - ivec2(0, 1)))) >= 2;
		if (quay) {
			c = C_PAVED;
		}
		// the river by its line (round Q), except where a town's houses,
		// quays and bridges stand on its tiles (towns, a city plan's parcels
		// but its open land, its own water among them)
		bool plan_built = planned && plan.r != CP_LAND;
		bool by_line = water_lines && town < 2 && !plan_built && !quay;
		if (planned && town > 0) {
			// its street piece, square or yard (tile_props draws the same on
			// the terraces)
			c = cp_surface(plan, cp_local(p), p, ground_rgb_at(G_MEADOW, band));
		} else if (town > 0) {
			// the houses stand on paved ground (villages on half paved ground up
			// close, on their land farther out); beyond the houses towns are
			// whole roof coloured tiles and villages vanish into the land
			ivec2 pl = tile - prop_origin;
			bool housed = town_props && pl.x >= 0 && pl.y >= 0 && pl.x < prop_n && pl.y < prop_n;
			// one house on each quarter (tile_props); in towns on the ramps
			// too, on a stone terrace, so a hill town steps up in terraces.
			// Paved is the yard under a house and a city core's empty
			// squares; a village's ramps and empty quarters stay its land
			// (Kritik r7: lawn ramps through a town read as green canals,
			// grey paved ramps before that as empty slopes)
			bool built = !sub_tiles || flat_top > 0.5;
			bool yard = sub_tiles && (built || town >= 2) && tt_sub_house(tile, town);
			bool paved = sub_tiles ? yard || (town == 3 && built) : true;
			// the landmarks stand on open travertine squares
			bool plaza = housed && landmark_count > 0 && tt_in_landmark(p);
			// up close a town's quarter without a lot (by the landmarks, the
			// small squares of the core) is a garden with trees
			// (tile_props.gdshaderinc), not an empty paved square (s2: Rome
			// round the Colosseum a desert of paving)
			bool garden = housed && tt_sub_garden(tile, town) && !plaza;
			if (garden) {
				paved = false;
				c = tt_grass(p, ground_rgb_at(G_MEADOW, band) * vec3(0.86, 0.95, 0.82));
				// a clipped hedge round it
				vec2 e = min(tile_uv, 1.0 - tile_uv);
				float aa = fwidth(e.x) + 1e-4;
				c = mix(c, vec3(0.15, 0.3, 0.13), 1.0 - smoothstep(0.035 - aa, 0.035 + aa, min(e.x, e.y)));
			} else if (housed && (sub_tiles || town >= 2)) {
				c = paved ? C_PAVED : town >= 2 ? ground_rgb_at(G_MEADOW, band) : c;
			} else if (town >= 2 && tile_km < 8.0) {
				// (from 8 km tiles a town is one roof coloured tile: a red
				// marker on the map, so they go there)
				c = C_ROOF;
			}
			// streets between the house blocks of towns and cities (the grid of
			// house_grid blocks per tile; half a street on each tile edge; up
			// close the streets lie on the lots' terraces, tile_props)
			if (plaza) { c = C_PLAZA; }
			// slabs on the paved quarters and the squares (travertine slabs larger)
			if (sub_tiles && (plaza || (housed && paved))) {
				c *= tt_paving(p, plaza ? vec2(2.0, 1.5) : vec2(1.2, 0.8));
			}
			if (housed && town >= 2 && built && paved && !plaza && !sub_tiles) {
				vec2 g = tile_uv * float(house_grid);
				vec2 e = abs(g - round(g)) / float(house_grid);
				float d = min(e.x, e.y);
				float aa = fwidth(d) + 1e-4;
				c = mix(c, C_STREET, 1.0 - smoothstep(0.035 - aa, 0.035 + aa, d));
			}
		}
		// the farms' fields from the grain economy, up close
		int land = tt_ground_at(tile, tile_uv);
		float fw_km = length(fwidth(p));
		if (town == 0 && tile_km <= 1.0) { c = sim_fields(p, c, land, tile_km, fw_km); }
		// up close the grass in patches, tufts and flowers (not the field tracks)
		bool grassy = land == G_MEADOW || land == G_FIELD || land == G_DRY_GRASS || land == G_ALPINE || land == G_WETLAND;
		if (tile_km <= 0.5 && town == 0 && grassy && distance(c, SIM_DIRT) > 0.01) { c = tt_grass(p, c); }
		// city wall along the edge of the core
		if (town == 3 && !planned && wall_sides != 0 && (!sub_tiles || flat_top > 0.5)) {
			c = mix(c, C_WALL * 0.82, 1.0 - smoothstep(0.05, 0.08, side_distance(wall_sides)));
		}
		// beach: sand along the sea, on the diagonal of a coast cut; up close
		// in voxel steps, its width wandering from a seam to a cove, and none
		// where a rock headland of the steps of the shore stands in front
		bool shore_cut = cut_tip >= 0 && shore_lake == 0;
		if (body_level <= 2.0 && town == 0 && ((shore_sides & 255) != 0 || shore_cut)) {
			vec2 cell = coast_cell();
			float d = side_distance_at(shore_sides & 255, cell);
			if (shore_cut) {
				vec2 tip = vec2(CORNER[cut_tip]);
				d = (abs(cell.x - tip.x) + abs(cell.y - tip.y) - 1.0) * 0.7071;
			}
			if (tile_km <= 1.0) {
				float width = mix(0.1, 0.5, coast_wander(cell, p));
				int steps = shore_sides >> 16;
				bool rock = steps != 0 && (steps & 4096) == 0 && cs_headland(data_tile(), steps, data_uv(cell), sub_tiles ? width * 0.5 : width);
				// the edge to the grass in cells a quarter as big, frayed into
				// pale patches as Urbek's (a staircase of whole cells along a
				// coast cut's diagonal stood on screen as a row of teeth);
				// once those cells are under ~1.7 px a smooth line, frayed
				// softly, instead of the whole cells' teeth (round K: with
				// the length of fwidth against 0.35 the fine cells never came
				// on at 3 km under the tilted camera, Mac check I + J)
				float n = round(tile_km / COAST_CELL_KM) * 4.0;
				vec2 fu = fwidth(tile_uv);
				float px = max(fu.x, fu.y); // a pixel in tile units
				bool fine_cells = px * n < 0.6;
				vec2 at = fine_cells ? (floor(tile_uv * n) + 0.5) / n : tile_uv;
				d = side_distance_at(shore_sides & 255, at);
				if (shore_cut) {
					vec2 tip = vec2(CORNER[cut_tip]);
					d = (abs(at.x - tip.x) + abs(at.y - tip.y) - 1.0) * 0.7071;
				}
				float fray = fine_cells ? tt_hash(floor((p - world_min) / (tile_km / n)) * 0.37 + 5.1) - 0.5
					: (tt_noise((p - world_min) / (tile_km * 4.0 / n)) - 0.5) * (1.0 - smoothstep(0.15, 0.4, px * n * 0.25));
				d += fray * 0.07;
				width = mix(0.1, 0.5, coast_wander(at, p)); // wandering by the same cells, not in whole cells' jumps
				float aa = fine_cells ? 1e-4 : px;
				float sand = 0.4 * (1.0 - smoothstep(width - 0.025 - aa, width - 0.025 + aa, d))
					+ 0.45 * (1.0 - smoothstep(width + 0.025 - aa, width + 0.025 + aa, d));
				c = !rock ? mix(c, C_SAND, sand) : c;
			} else if (!contour) { // (by the coast line its own seam, below)
				float aa = fwidth(d) + 1e-4;
				c = mix(c, C_SAND, (1.0 - smoothstep(0.26 - aa, 0.26 + aa, d)) * 0.85);
			}
		}
		// the ways people wear and the markets of the grain economy
		c = sim_ways(p, c, fw_km);
		// SimCity 2000 slope tiles come in one clear tone per side, with no
		// gradient, matched to the west-south-west sun: slopes turned west
		// light, east dark, south (the risers the camera sees head on) and
		// north darker, so every step reads as tread and riser (values
		// below); a corner facet takes the darker of its two sides. (Kritik
		// r7: with the risers +5 % lighter, as in round 9, the steps
		// vanished; with the west +18 % and nothing else, hillsides read as
		// striped lawns.) The light itself sees every
		// top as flat (NORMAL below), so this is the only shading: lambert on
		// top of it washed sun-side ramps out like glass and made single
		// shade-side steps black walls.
		vec3 nw = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
		nw = nw.y < 0.0 ? -nw : nw;
		vec2 cam_right = normalize(INV_VIEW_MATRIX[0].xz + vec2(1e-5, 0.0));
		vec2 cam_back = vec2(-cam_right.y, cam_right.x); // towards the camera
		vec2 slope = nw.xz;
		vec2 dir = slope / max(length(slope), 1e-6);
		float fr = dot(dir, cam_right);
		float fb = dot(dir, cam_back);
		// far out slopes turned away from the camera are seen edge on: they
		// fade to the flat tone, else a long step draws a dark crack across
		// the land (gone by north-east and north-west: diagonal steps facing
		// away drew hairlines across the 70 km view); up close they are whole
		// quarter tiles and keep their tone (people critic r18/r19: north
		// ramps measured the flat #76b066, the hills read as paper folds)
		float away = tile_km >= 1.0 ? clamp(1.0 + 2.0 * min(fb, 0.0), 0.0, 1.0) : 1.0;
		// west, east, risers (south), north. From the 1 km tiles the shadow
		// map is off and these tones are all the relief has: 1.6 times the
		// old near tones (west +19 %, east -24 %, risers -16 %; Kritik r9 and
		// the people critic r16: the risers vanished at 70 km). Up close
		// west +22 %, east -22 %, risers -12 %, north -24 % (they were +12 %
		// / -15 %, a sun-facing ramp only 12-14 % above the flat; with north
		// -30 % a shaded north ramp under a cast shadow fell to L 70, Kritik
		// r10)
		vec4 tones = tile_km >= 1.0 ? vec4(0.192, -0.24, -0.16, -0.288) : vec4(0.22, -0.22, -0.12, -0.24);
		float side = fr < 0.0 ? tones.x : tones.y;
		float front = fb > 0.0 ? tones.z : tones.w;
		// continuous in the direction (a blend into the corner tone), so the
		// tone never flips between two sides from pixel to pixel
		float t = abs(fr) - abs(fb);
		float corner = min(side, front);
		float shade = t > 0.0 ? mix(corner, side, smoothstep(0.1, 0.4, t)) : mix(corner, front, smoothstep(0.1, 0.4, -t));
		// up close a gentle ramp a gentler tone (a step is 0.15 km on a 0.25 km
		// quarter, TileTerrain.NEAR_EXAGGERATION): a whole hillside in one hard
		// facet read as folded paper (s2)
		float steep = sub_tiles ? mix(0.4, 1.0, smoothstep(0.25, 0.7, length(slope))) : 1.0;
		// far out (from the 0.5 km tiles) every ramp is a whole tile one
		// level high, so each facet is as steep as the next and the tones
		// above lay the hills out as large pale and dark triangles, the sun
		// side +22 % like glass (Ramon, round L). Urbek has hardly a slope
		// and the landscape reference turns its hillsides only a little
		// lighter or darker: the sun side keeps a third of its tone, the
		// shade sides two thirds, so the steps still read as darker bands
		float far = sub_tiles ? 1.0 : (shade > 0.0 ? FAR_SUN_TONE : FAR_SHADE_TONE);
		// a coastal ramp (0 at the sea, land from 1) fades to the flat tone
		// at its foot, where the land the coast line lays over the sea tile
		// goes on untoned
		float foot = contour ? smoothstep(0.0, 0.6, world_pos.y / level_h) : 1.0;
		float tone = 1.0 + shade * away * steep * far * foot;
		float ramp = flat_top > 0.5 || length(slope) < 0.02 ? 1.0 : tone; // flat tiles never flicker between tones
		// from the 2 km tiles the node facets instead of the tiles' level ramps (round N)
		c *= contour ? contour_relief(p, art) : ramp;
		if (water == W_RIVER && !(contour && river_ready) && !by_line) {
			// a band from the tile centre to each side with water beyond it;
			// at least a boat wide, never more than half a tile
			float half_w = clamp(0.075 / tt_data_km(), 0.06, 0.22);
			// on the data tile (a quarter tile draws its part of the band)
			vec2 q = (sub_tiles ? (tile_uv + vec2(tile & ivec2(1))) * 0.5 : tile_uv) - 0.5;
			// and never thinner than about a pixel and a half, so the big
			// rivers still read on the map of Europe
			half_w = min(max(half_w, 0.75 * length(fwidth(q))), 0.3);
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
			c = mix(c, mix(C_INLAND, C_SHORE_FAR, far_share()), river);
		}
		if (water_lines) {
			// the river with its bank, and a lake by its outline on the low part
			// of a tile that touches the lake's tiles (their corners at its
			// level: never a lake up a slope); a town by the lake keeps its
			// tiles, as by the river
			float lake = 0.0;
			if (wl.g > 0.0 && town < 2 && !plan_built) {
				bool touch = false;
				for (int k = 0; k < 8; k++) {
					ivec2 o = k < 4 ? SIDE[k] : SIDE[k - 4] + SIDE[(k - 3) & 3];
					touch = touch || tt_water(tile + o) == W_LAKE;
				}
				lake = touch ? wl.g * (1.0 - smoothstep(0.35, 0.55, world_pos.y / level_h - body_level)) : 0.0;
			}
			float river = by_line ? wl.r : 0.0;
			c = mix(c, C_BANK, by_line ? wl.b * (1.0 - lake) : 0.0);
			c = mix(c, mix(C_INLAND, C_SHORE_FAR, far_share()), max(river, lake));
			rough = max(river, lake) > 0.5 ? 0.55 : rough;
		}
		// the coast line on the land tiles: their corners at the sea sit at
		// 0 and the land at 1 or higher, so a coastal tile is a ramp up from
		// the sea; the line lays the sea on its low half only (never on the
		// hills: a lake of blue on a slope)
		if (contour && water != W_LAKE) {
			c = contour_river(p, c, px_km); // the rivers by their lines (round N), not the tile bands above
			// the lakes by their shore line (round P), as the sea by the
			// coast line below: on the tile's low part only, the corners at
			// a lake sitting at its level (never a lake up a slope)
			float lake_low = 1.0 - smoothstep(0.35, 0.55, world_pos.y / level_h - body_level);
			float lake = (1.0 - smoothstep(-ld_aa, ld_aa, ld)) * lake_low;
			c = mix(c, mix(C_INLAND, C_SHORE_FAR, far_share()), lake);
			rough = lake > 0.5 ? 0.55 : rough;
			float low = 1.0 - smoothstep(0.35, 0.55, world_pos.y / level_h);
			c = contour_shore(c, sd, sd_aa, px_km, low);
			sea_px = sd > CONTOUR_SD && low > 0.5;
		}
	} else {
		// walls: one darker earth tone (sand at the coast, stone where a town
		// stands over its quay, rock up high), no texture
		float hm = tt_level_metres(world_pos.y / level_h);
		vec3 base = water == W_SEA ? mix(C_SEA, C_SEA_FAR, far_share()) * 0.8 : (coast > 0.0 && body_level <= 3.0) ? C_BANK : C_EARTH;
		if (water == W_LAND && coast >= 1.0 && tile_km <= 0.5 && tt_town(tile) >= 2) { base = C_QUAY_WALL; }
		if (water == W_LAND && hm > 1200.0) { base = C_CLIFF; }
		// lit like the ramps: light on the walls facing the camera, darker
		// the more a wall turns east
		vec2 wn = part >= 1 && part <= 4 ? vec2(SIDE[part - 1]) : vec2(0.0, 1.0);
		float f = dot(wn, normalize(art.xz));
		c = base * mix(0.70, 1.0, smoothstep(-0.8, 0.8, f));
	}
	c = sim_muted(c, sea_px);
	ALBEDO = pow(clamp(c, 0.0, 1.0), vec3(2.2)); // palette is sRGB
	ROUGHNESS = rough;
	shadow_share = rough < 1.0 ? WATER_SHADOW : 1.0; // the water's tops (not its sand)
	// tops and walls are lit as flat ground; the fixed tones above do the relief
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

// Lambert, as diffuse_lambert, with the sun's cast shadow weakened on the
// water (shadow_share)
void light() {
	float shade = LIGHT_IS_DIRECTIONAL ? 1.0 - (1.0 - ATTENUATION) * shadow_share : ATTENUATION;
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * shade * LIGHT_COLOR / PI;
}
