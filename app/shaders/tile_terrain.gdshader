// Tile terrain surface. One MultiMesh instance per tile of the patch; the
// instance mesh holds the tile top (two triangles) and four walls. The vertex
// stage reads the tile data and builds the stepped surface, so no terrain
// geometry is ever built on the CPU.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform float grid_line = 0.12;
uniform bool show_fields = false; // patchwork fields (off: SimCity 2000 tiles are plain)
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
varying flat int land_sides;  // sea tile: bit k = land across side k
varying flat int wall_sides;  // core town tile: bit k = no town across side k
varying flat int river_sides; // river tile: bit k = water across side k

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
const vec3 W_DEEP = vec3(0.094, 0.282, 0.502);
const vec3 W_MID = vec3(0.133, 0.384, 0.612);
const vec3 W_SHALLOW = vec3(0.204, 0.549, 0.675);
const vec3 W_LAGOON = vec3(0.329, 0.659, 0.690);
const vec3 W_INLAND = vec3(0.247, 0.510, 0.651);

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
	water = tt_water(tile);
	vec4 own = tt_corners(tile);
	body_level = min(min(own.x, own.y), min(own.z, own.w));
	flat_top = float(max(max(own.x, own.y), max(own.z, own.w)) - body_level < 0.01);
	vec2 cpos;
	float level;
	if (part == 0) {
		cpos = vec2(tile + CORNER[role]);
		level = pick(own, role);
		tile_uv = vec2(CORNER[role]);
	} else {
		int w = part - 1;
		ivec4 e = WALL[w];
		bool b_side = role == 1 || role == 2;
		int ok = b_side ? e.y : e.x;
		int nk = b_side ? e.w : e.z;
		cpos = vec2(tile + CORNER[ok]);
		float top = pick(own, ok);
		vec4 other = tt_corners(tile + SIDE[w]);
		float bottom = min(top, pick(other, nk));
		level = role <= 1 ? top : bottom;
		tile_uv = vec2(b_side ? 1.0 : 0.0, role <= 1 ? 0.0 : 1.0);
	}
	world_pos = vec3(world_min.x + cpos.x * tile_km, level * level_h, world_min.y + cpos.y * tile_km);
	// coast flags: land next to the sea gets a beach, sea next to land a lagoon tint
	coast = 0.0;
	for (int k = 0; k < 4; k++) {
		int n1 = tt_water(tile + SIDE[k]);
		int n2 = tt_water(tile + SIDE[k] * 2);
		if (water == W_SEA) {
			if (n1 != W_SEA) { coast = 1.0; }
		} else {
			if (n1 == W_SEA) { coast = 1.0; }
			else if (n2 == W_SEA) { coast = max(coast, 0.45); }
		}
	}
	land_sides = 0;
	wall_sides = 0;
	river_sides = 0;
	bool core = water == W_LAND && tt_town(tile) == 3;
	for (int k = 0; k < 4; k++) {
		int nc = tt_cell(tile + SIDE[k]);
		if (water == W_SEA && (nc & 3) != W_SEA) { land_sides |= 1 << k; }
		if (core && ((nc & 3) != W_LAND || (nc >> 2) < 2)) { wall_sides |= 1 << k; }
		if (water == W_RIVER && (nc & 3) != W_LAND) { river_sides |= 1 << k; }
	}
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

vec3 ground_colour(vec2 p, vec4 cov) {
	float n = tt_fbm(p / (6.0 * max(tile_km, 0.5)));
	float lat = tt_latitude(p);
	float h = tt_height_m(p, height_lod);
	float dry = cov.g;
	vec3 c = mix(C_PLAIN, C_GRASS, 0.35 + 0.65 * n);
	if (lat < 37.5) {
		c = mix(c, C_DRY, clamp(dry * 1.2, 0.0, 1.0));
		c = mix(c, C_SAND_DARK, clamp((dry - 0.6) * 2.0, 0.0, 1.0));
	} else {
		c = mix(c, C_DRY, clamp(dry * 1.1, 0.0, 0.85));
	}
	c = mix(c, C_CROP, clamp(cov.b * 1.4, 0.0, 0.6) * 0.5);
	float trees = tt_tree_density(p, cov.r);
	// dark floor under drawn trees; without trees (far levels) a lighter wood green
	vec3 wood = mix(C_FOREST, vec3(0.294, 0.420, 0.212), smoothstep(1.0, 2.0, tile_km));
	c = mix(c, wood, 0.15 * cov.r + 0.75 * trees);
	c = mix(c, C_WET, clamp(cov.a * 2.0, 0.0, 0.8));
	c = mix(c, C_HILL, clamp((h - 500.0) / 900.0, 0.0, 1.0) * (1.0 - dry));
	// rock caps, the same on ramps and flat tops so slopes do not read as walls
	float rock = clamp((h - 1250.0) / 400.0, 0.0, 1.0);
	c = mix(c, C_ROCK, rock);
	c = mix(c, C_SNOW, clamp((h - 1750.0) / 200.0, 0.0, 1.0));
	if (body_level <= 2.0) {
		c = mix(c, C_SAND, coast >= 0.99 ? 0.8 : coast * 0.65);
	}
	return c;
}

// Roman farmland patchwork on open, low, flat land: colour and stripes.
bool field(vec2 p, vec4 cov, out vec3 colour, out float stripes) {
	colour = vec3(0.0);
	stripes = 0.0;
	if (!show_fields || tile_km > 1.0 || flat_top < 0.5 || coast > 0.0) { return false; }
	float open_land = cov.b + 0.6 * (1.0 - cov.r - cov.g) + 0.3 * cov.g;
	if (open_land < 0.3 || tt_tree_density(p, cov.r) > 0.05 || tt_height_m(p, height_lod) > 700.0 || cov.a > 0.3 || tt_latitude(p) < 33.0) { return false; }
	vec2 block = floor(p / 1.0);
	float hsh = tt_hash(block * 1.731 + 0.37);
	float farm = smoothstep(0.25, 0.6, cov.b * 1.5 + 0.4 * tt_fbm(p / 3.0));
	if (hsh > farm * 0.65) { return false; }
	int k = int(hsh * 997.0) % 5;
	vec3 cols[5] = vec3[](vec3(0.745, 0.682, 0.384), vec3(0.635, 0.635, 0.337), vec3(0.698, 0.627, 0.408), vec3(0.573, 0.596, 0.314), vec3(0.776, 0.714, 0.424));
	colour = cols[k];
	bool along_x = int(hsh * 7919.0) % 2 == 0;
	float u = along_x ? tile_uv.x : tile_uv.y;
	float s = fract(u * 4.0);
	float w = fwidth(u * 4.0) * 1.2;
	stripes = 1.0 - smoothstep(0.0, w + 0.06, abs(s - 0.5) - 0.44);
	return true;
}

// Smooth surface normal of the relief at p (world), for the far relief map.
vec3 relief_normal(vec2 p) {
	float e = tile_km * 0.75;
	float lod = height_lod + 0.3;
	float hx = textureLod(relief_tex, tt_node_uv(p + vec2(e, 0.0)), lod).r - textureLod(relief_tex, tt_node_uv(p - vec2(e, 0.0)), lod).r;
	float hz = textureLod(relief_tex, tt_node_uv(p + vec2(0.0, e)), lod).r - textureLod(relief_tex, tt_node_uv(p - vec2(0.0, e)), lod).r;
	float k = level_h / m_per_level / (2.0 * e);
	return normalize(vec3(-hx * k, 1.0, -hz * k));
}

// Distance (in tile units) from the tile edge on the sides set in `mask`.
float side_distance(int mask) {
	float d = 10.0;
	if ((mask & 1) != 0) { d = min(d, tile_uv.y); }
	if ((mask & 2) != 0) { d = min(d, 1.0 - tile_uv.x); }
	if ((mask & 4) != 0) { d = min(d, 1.0 - tile_uv.y); }
	if ((mask & 8) != 0) { d = min(d, tile_uv.x); }
	return d;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 centre = tt_tile_center(tile);
	// far out the colour follows the ground, not the tile, so the map is smooth
	float far = smoothstep(1.0, 2.0, tile_km);
	vec2 cp = p; // ground colour follows the land smoothly, no per-tile patches
	vec3 c;
	float rough = 1.0;
	if ((water == W_SEA || water == W_LAKE) && part == 0) {
		if (water == W_SEA) {
			float d_km = tt_sea_distance(p);
			d_km = max(d_km, coast > 0.5 ? 0.0 : tile_km * 1.5);
			c = d_km <= 1.2 ? mix(W_LAGOON, W_SHALLOW, d_km / 1.2)
				: d_km <= 8.0 ? mix(W_SHALLOW, W_MID, (d_km - 1.2) / 6.8)
				: mix(W_MID, W_DEEP, clamp((d_km - 8.0) / 40.0, 0.0, 1.0));
			// light wave dashes, anchored to the tile grid
			vec2 q = p / (tile_km * 0.5);
			vec2 cell = floor(q);
			vec2 f = fract(q);
			float r = tt_hash(cell + floor(TIME * 0.15 + tt_hash(cell) * 7.0));
			float dash = step(0.82, r) * (1.0 - smoothstep(0.0, 0.05, abs(f.y - 0.5))) * step(0.2, f.x) * step(f.x, 0.55);
			c = mix(c, vec3(0.86, 0.93, 0.92), dash * 0.5 * (coast > 0.5 ? 1.2 : 0.6));
			// surf: a bright line along the shore with a softer second band
			if (land_sides != 0) {
				float d = side_distance(land_sides);
				float pulse = 0.5 + 0.5 * sin(TIME * 1.3 + tt_hash(vec2(tile)) * 6.28);
				float foam = 1.0 - smoothstep(0.06, 0.12, d);
				foam = max(foam, (1.0 - smoothstep(0.02, 0.05, abs(d - 0.22 - 0.05 * pulse))) * 0.45);
				c = mix(c, C_FOAM, foam * (1.0 - far));
			}
		} else {
			c = W_INLAND;
		}
		c *= 0.985 + 0.03 * tt_hash(vec2(tile) + 3.1);
		rough = 0.55;
	} else if (part == 0) {
		vec4 cov = tt_cover(cp);
		int town = tt_town(tile);
		vec3 fc;
		float stripes;
		if (town > 0) {
			c = mix(ground_colour(centre, cov), C_PAVED, 0.75);
			// streets between the house blocks
			vec2 g = abs(fract(tile_uv * float(house_grid)) - 0.5);
			float street = 1.0 - smoothstep(0.38, 0.43, max(g.x, g.y));
			if (town >= 2) { c = mix(c, C_STREET, 1.0 - street); }
			// city wall along the edge of the core
			if (wall_sides != 0) {
				c = mix(c, C_WALL * 0.82, 1.0 - smoothstep(0.05, 0.08, side_distance(wall_sides)));
			}
		} else {
			c = ground_colour(cp, cov);
		}
		// ramps: a touch of bare earth, as on SimCity 2000 slope tiles
		if (flat_top < 0.5 && town == 0) {
			c = mix(c, C_SLOPE, 0.22);
		}
		// slope shading: ramps facing the sun bright, the others dark
		vec3 nw = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
		nw = nw.y < 0.0 ? -nw : nw;
		if (relief_smooth > 0.0) {
			// far out: smooth per-pixel normal from the relief instead of the
			// flat tile facets, so the relief map has no triangle sawtooth
			nw = normalize(mix(nw, relief_normal(p), relief_smooth));
		}
		// SimCity 2000 slope tiles come in two clear tones: sun side light,
		// shade side dark, with no gradient in between
		float lit = dot(nw, light_dir) - light_dir.y;
		float aa_l = fwidth(lit) + 0.02;
		float tone = mix(0.80, 1.0, smoothstep(-0.05 - aa_l, -0.05 + aa_l, lit));
		tone = mix(tone, 1.13, smoothstep(0.05 - aa_l, 0.05 + aa_l, lit));
		float smooth_tone = clamp(1.0 + 1.8 * lit, 0.6, 1.3); // crisp hillshade (EU5 map)
		c *= mix(mix(1.0, tone, mix(1.0, 0.6, far)), smooth_tone, relief_smooth);
		// tile outline, about one pixel wide at every zoom
		vec2 e = min(tile_uv, 1.0 - tile_uv);
		vec2 fw = fwidth(tile_uv);
		float line = 1.0 - smoothstep(0.0, 1.0, min(e.x / max(fw.x, 1e-5), e.y / max(fw.y, 1e-5)));
		// fade the outline out when tiles get only a few pixels wide
		float fade = smoothstep(5.0, 12.0, 1.0 / max(max(fw.x, fw.y), 1e-5));
		c *= 1.0 - grid_line * line * (flat_top > 0.5 ? 1.0 : 0.3) * fade * (1.0 - relief_smooth);
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
	n = n.z < 0.0 ? -n : n;
	if (relief_smooth > 0.0 && part == 0 && water == W_LAND) {
		n = normalize(mix(n, (VIEW_MATRIX * vec4(relief_normal(world_pos.xz), 0.0)).xyz, relief_smooth));
	}
	NORMAL = n;
}
