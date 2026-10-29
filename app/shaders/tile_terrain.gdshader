// Tile terrain surface. One MultiMesh instance per tile of the patch; the
// instance mesh holds the tile top (two triangles) and four walls. The vertex
// stage reads the tile data and builds the stepped surface, so no terrain
// geometry is ever built on the CPU.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform vec3 light_dir = vec3(-0.6, 0.67, -0.2); // towards the sun, world
// The slope and wall tones take the SimCity 2000 light of tt_art_light, not
// the sun of the weather (which still lights the tops and the props).
uniform float slope_light = 0.9;                 // SimCity 2000 slope contrast
uniform int house_grid = 2;                      // house blocks per tile side
uniform bool town_props = true;                  // houses are drawn as models at this level
uniform ivec2 prop_origin;                       // the tiles that have them (tile_props.gdshader)
uniform int prop_n = 96;

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
	vec3(0.439, 0.420, 0.396),  // rock
	vec3(0.953, 0.965, 0.973)   // snow
);
// Far out (from 1 km tiles) the land takes the palette of the
// painted far view (gauntlet refs/gemalt-weit-mittel-nah.png): olive lowland,
// dark green forest, light rock, a deep sea; on screen e.g. lowland #9aa35a,
// forest #4f7a35, sea #1d5e93. Open land also takes a flat tint per height
// band, so hills and ranges read as areas and not only by their ramps.
const vec3 GROUND_FAR[11] = vec3[](
	vec3(0.455, 0.478, 0.286),  // meadow
	vec3(0.520, 0.486, 0.294),  // dry grass
	vec3(0.592, 0.549, 0.337),  // field
	vec3(0.388, 0.447, 0.290),  // wetland
	vec3(0.485, 0.447, 0.308),  // scrub
	vec3(0.615, 0.564, 0.451),  // sand
	vec3(0.262, 0.316, 0.184),  // forest (olive like the painted strip, #56683c, not #4f7b36)
	vec3(0.220, 0.290, 0.200),  // conifer forest
	vec3(0.408, 0.447, 0.294),  // alpine meadow
	vec3(0.510, 0.472, 0.375),  // rock (the painted crests, #a89c78 on screen; Kritik r8)
	vec3(0.860, 0.845, 0.810)   // snow (#e8e4dc, not cotton white)
);
const vec3 C_HILLS_FAR = vec3(0.379, 0.425, 0.265); // #849252
// mountain pasture, a little darker than the hills (#7c8550); bare rock only
// on the crests (tools/build_tile_terrain.py ROCK_M): the khaki #958e6c here
// made the Apennines a quarry
const vec3 C_MOUNT_FAR = vec3(0.356, 0.388, 0.259);
const vec3 C_SEA_FAR = vec3(0.111, 0.264, 0.424);   // #19588c on screen
const vec3 C_SHORE_FAR = vec3(0.130, 0.302, 0.506); // #24689e
const vec3 C_SAND = vec3(0.804, 0.745, 0.510);   // beach
const vec3 C_BANK = vec3(0.588, 0.549, 0.392);   // river bank
const vec3 C_EARTH = vec3(0.557, 0.498, 0.408);  // walls
const vec3 C_CLIFF = vec3(0.533, 0.514, 0.475);
const vec3 C_PAVED = vec3(0.655, 0.608, 0.490);
const vec3 C_PLAZA = vec3(0.750, 0.720, 0.660);  // travertine squares of the landmarks, #e6dfcf
const vec3 C_STREET = vec3(0.420, 0.404, 0.384); // Roman basalt paving
const vec3 C_ROOF = vec3(0.580, 0.250, 0.190); // terracotta, not salmon or orange
const vec3 C_WALL = vec3(0.686, 0.627, 0.522);
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

// A land tile with the sea on all four sides: a one tile island gets no
// light lagoon ring (a big pale square around a speck of land).
bool lone_land(ivec2 t) {
	for (int k = 0; k < 4; k++) {
		if (tt_water(t + SIDE[k]) != W_SEA) { return false; }
	}
	return true;
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
	// a lake tile at a corner of its lake is land on that half, at the level
	// of the shore around it (tt_lake_corner_cut)
	int lake_cut = !sub_tiles && water == W_LAKE ? tt_lake_corner_cut(tile, nc) : -1;
	if (lake_cut >= 0) {
		water = W_LAND;
		own = vec4(tt_lake_level(tile));
	}
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
	int cut = lake_cut >= 0 ? lake_cut : tt_coast_cut_nb(tile, cell, nc);
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
	// coast flags: land next to the sea gets a beach, sea next to land a lagoon tint
	coast = 0.0;
	bool lake_near = water == W_LAKE;
	for (int k = 0; k < 4; k++) {
		int n1 = nc[k] & 3;
		lake_near = lake_near || n1 == W_LAKE;
		int n2 = tt_water(tile + SIDE[k] * 2);
		if (water == W_SEA) {
			if (n1 != W_SEA && !lone_land(tile + SIDE[k])) { coast = 1.0; }
		} else {
			if (n1 == W_SEA) { coast = 1.0; }
			else if (n2 == W_SEA) { coast = max(coast, 0.45); }
		}
	}
	if (water == W_SEA && coast < 1.0) {
		for (int k = 0; k < 4; k++) {
			ivec2 d = tile + SIDE[k] + SIDE[(k + 1) & 3];
			if (tt_water(d) != W_SEA && !lone_land(d)) { coast = 1.0; }
		}
	}
	shore_lake = lake_near ? 1 : 0;
	int ground = lake_cut >= 0 ? tt_ground(tile + SIDE[(lake_cut + 1) & 3]) : tt_ground(tile);
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
	vec3 art = tt_art_light(INV_VIEW_MATRIX);
	vec3 c;
	float rough = 1.0;
	if ((water == W_SEA || water == W_LAKE || wet_tri == 1) && part == 0) {
		// one flat colour per water tile, a lighter one where it touches the land
		float far = far_share();
		if (water == W_SEA || (wet_tri == 1 && shore_lake == 0)) {
			c = coast >= 1.0 || wet_tri == 1 ? mix(C_SHORE, C_SHORE_FAR, far) : mix(C_SEA, C_SEA_FAR, far);
			c = sim_lanes(p, c, length(fwidth(p)));
		} else {
			c = mix(C_INLAND, C_SHORE_FAR, far); // lakes like the rivers, not deep sea holes
		}
		rough = 0.55;
	} else if (part == 0) {
		int town = tt_town(tile);
		// one flat colour per tile; where two landscapes meet, the half towards
		// the corner of the other one takes its colour (cut at the diagonal)
		// in far levels whatever the scale of the tile's own levels
		float band = max((near_scale ? tt_far_level_x(tt_level_metres(body_level)) : body_level) - 1.0, 0.0);
		c = ground_rgb_at(ground, band);
		if (ground_tip >= 0) {
			vec2 tip = vec2(CORNER[ground_tip]);
			float d = (abs(tile_uv.x - tip.x) + abs(tile_uv.y - tip.y) - 1.0) * 0.7071;
			float aa = fwidth(d) * 0.75 + 1e-4;
			c = mix(ground_rgb_at(ground_alt, band), c, smoothstep(-aa, aa, d));
		}
		// inside a town the river banks are paved quays (they were wheat
		// strips through Rome)
		if (water == W_RIVER && tile_km < 2.0 && max(max(tt_town(tile + ivec2(1, 0)), tt_town(tile - ivec2(1, 0))),
				max(tt_town(tile + ivec2(0, 1)), tt_town(tile - ivec2(0, 1)))) >= 2) {
			c = C_PAVED;
		}
		if (town > 0) {
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
			if (housed && (sub_tiles || town >= 2)) {
				c = paved ? C_PAVED : town >= 2 ? ground_rgb_at(G_MEADOW, band) : c;
			} else if (town >= 2 && tile_km < 8.0) {
				// (from 8 km tiles a town is one roof coloured tile: a red
				// marker on the map, so they go there)
				c = C_ROOF;
			}
			// streets between the house blocks of towns and cities (the grid of
			// house_grid blocks per tile; half a street on each tile edge; up
			// close the streets lie on the lots' terraces, tile_props)
			// the landmarks stand on open travertine squares
			bool plaza = housed && landmark_count > 0 && tt_in_landmark(p);
			if (plaza) { c = C_PLAZA; }
			if (housed && town >= 2 && built && paved && !plaza && !sub_tiles) {
				vec2 g = tile_uv * float(house_grid);
				vec2 e = abs(g - round(g)) / float(house_grid);
				float d = min(e.x, e.y);
				float aa = fwidth(d) + 1e-4;
				c = mix(c, C_STREET, 1.0 - smoothstep(0.035 - aa, 0.035 + aa, d));
			}
		}
		// the farms' fields from the grain economy, up close
		if (town == 0 && tile_km <= 1.0) { c = sim_fields(p, c, tt_ground_at(tile, tile_uv), tile_km); }
		// city wall along the edge of the core
		if (town == 3 && wall_sides != 0 && (!sub_tiles || flat_top > 0.5)) {
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
		// footpaths, markets and trade roads from the grain economy
		c = sim_ways(p, c, length(fwidth(p)));
		// SimCity 2000 slope tiles come in one clear tone per side, with no
		// gradient, matched to the west-south-west sun: slopes turned west
		// light (+12 %), east dark (-15 %), south (the risers the camera sees
		// head on) -10 % and north -18 %, so every step reads as tread and
		// riser; a corner facet takes the darker of its two sides (south-west
		// -10 %, south-east -15 %). Slopes turned away fade to the flat tone
		// as they turn edge on. (Kritik r7: with the risers +5 % lighter, as in
		// round 9, the steps vanished; with the west +18 % and nothing else,
		// hillsides read as striped lawns.) The light itself sees every
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
		// slopes turned away from the camera are seen edge on: they fade to
		// the flat tone, else a long step draws a dark crack across the land
		// (gone by north-east and north-west: diagonal steps facing away drew
		// hairlines across the 70 km view)
		float away = clamp(1.0 + 2.0 * min(fb, 0.0), 0.0, 1.0);
		// from the 1 km tiles the shadow map is off and these tones are all
		// the relief has: 1.6 times as strong (west +19 %, east -24 %, risers
		// -16 %), so lit and shaded sides differ by half (Kritik r9 and the
		// people critic r16: the risers vanished at 70 km, ratio 1.05 to 1.2)
		float amp = tile_km >= 1.0 ? 1.6 : 1.0;
		float side = (fr < 0.0 ? 0.12 : -0.15) * amp;
		float front = (fb > 0.0 ? -0.10 : -0.18) * amp;
		// continuous in the direction (a blend into the corner tone), so the
		// tone never flips between two sides from pixel to pixel
		float t = abs(fr) - abs(fb);
		float corner = min(side, front);
		float shade = t > 0.0 ? mix(corner, side, smoothstep(0.1, 0.4, t)) : mix(corner, front, smoothstep(0.1, 0.4, -t));
		float tone = 1.0 + shade * away;
		c *= flat_top > 0.5 || length(slope) < 0.02 ? 1.0 : tone; // flat tiles never flicker between tones
		if (water == W_RIVER) {
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
	} else {
		// walls: one darker earth tone (sand at the coast, rock up high), no texture
		float hm = tt_level_metres(world_pos.y / level_h);
		vec3 base = water == W_SEA ? mix(C_SEA, C_SEA_FAR, far_share()) * 0.8 : (coast > 0.0 && body_level <= 3.0) ? C_BANK : C_EARTH;
		if (water == W_LAND && hm > 1200.0) { base = C_CLIFF; }
		// lit like the ramps: light on the walls facing the camera, darker
		// the more a wall turns east
		vec2 wn = part >= 1 && part <= 4 ? vec2(SIDE[part - 1]) : vec2(0.0, 1.0);
		float f = dot(wn, normalize(art.xz));
		c = base * mix(0.70, 1.0, smoothstep(-0.8, 0.8, f));
	}
	ALBEDO = pow(clamp(c, 0.0, 1.0), vec3(2.2)); // palette is sRGB
	ROUGHNESS = rough;
	// tops and walls are lit as flat ground; the fixed tones above do the relief
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
