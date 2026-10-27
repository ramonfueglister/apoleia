// Tile terrain surface. One MultiMesh instance per tile of the patch; the
// instance mesh holds the tile top (two triangles) and four walls. The vertex
// stage reads the tile data and builds the terraced surface, so no terrain
// geometry is ever built on the CPU.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform float grid_line = 0.12;
uniform bool show_fields = true;

varying vec3 world_pos;
varying vec2 tile_uv;
varying flat int part;
varying flat ivec2 tile;
varying flat int water;
varying flat float coast;
varying flat float flat_top;
varying flat float body_level;

const vec3 C_PLAIN = vec3(0.580, 0.592, 0.322);
const vec3 C_GRASS = vec3(0.459, 0.522, 0.275);
const vec3 C_DRY = vec3(0.694, 0.643, 0.380);
const vec3 C_HILL = vec3(0.380, 0.451, 0.271);
const vec3 C_FOREST = vec3(0.306, 0.400, 0.235);
const vec3 C_SAND = vec3(0.847, 0.753, 0.549);
const vec3 C_SAND_DARK = vec3(0.773, 0.694, 0.467);
const vec3 C_ROCK = vec3(0.553, 0.553, 0.455);
const vec3 C_PEAK = vec3(0.859, 0.780, 0.635);
const vec3 C_SNOW = vec3(0.94, 0.94, 0.91);
const vec3 C_WET = vec3(0.408, 0.502, 0.337);
const vec3 C_CROP = vec3(0.729, 0.667, 0.384);
const vec3 C_EARTH = vec3(0.588, 0.463, 0.314);
const vec3 C_CLIFF = vec3(0.502, 0.478, 0.408);
const vec3 C_PAVED = vec3(0.776, 0.729, 0.596);
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
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

vec3 ground_colour(vec2 p, vec4 cov) {
	float n = tt_fbm(p / (6.0 * max(tile_km, 0.5)));
	float n2 = tt_hash(vec2(tile));
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
	c = mix(c, C_CROP, clamp(cov.b * 1.4, 0.0, 0.6) * (0.6 + 0.4 * n2));
	float trees = tt_tree_density(p, cov.r);
	c = mix(c, C_FOREST, 0.15 * cov.r + 0.75 * trees);
	c = mix(c, C_WET, clamp(cov.a * 2.0, 0.0, 0.8));
	c = mix(c, C_HILL, clamp((h - 500.0) / 900.0, 0.0, 1.0) * (1.0 - dry));
	c = mix(c, C_ROCK, clamp((h - 1300.0) / 500.0, 0.0, 1.0));
	c = mix(c, C_PEAK, clamp((h - 1800.0) / 300.0, 0.0, 1.0));
	c = mix(c, C_SNOW, clamp((h - 2050.0) / 150.0, 0.0, 1.0));
	if (body_level <= 2.0) {
		c = mix(c, C_SAND, coast >= 0.99 ? 0.8 : coast * 0.65);
	}
	return c * (0.96 + 0.08 * n2);
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

void fragment() {
	vec2 p = world_pos.xz;
	vec2 centre = tt_tile_center(tile);
	vec3 c;
	float rough = 1.0;
	if (water != W_LAND && part == 0) {
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
		} else {
			c = W_INLAND;
		}
		c *= 0.985 + 0.03 * tt_hash(vec2(tile) + 3.1);
		rough = 0.55;
	} else if (part == 0) {
		vec4 cov = tt_cover(centre);
		int town = tt_town(tile);
		vec3 fc;
		float stripes;
		if (town > 0) {
			c = mix(ground_colour(centre, cov), C_PAVED, 0.75);
		} else if (field(centre, cov, fc, stripes)) {
			c = fc * (1.0 - 0.12 * stripes);
		} else {
			c = ground_colour(centre, cov);
		}
		// tile outline, about one pixel wide at every zoom
		vec2 e = min(tile_uv, 1.0 - tile_uv);
		vec2 fw = fwidth(tile_uv);
		float line = 1.0 - smoothstep(0.0, 1.0, min(e.x / max(fw.x, 1e-5), e.y / max(fw.y, 1e-5)));
		// fade the outline out when tiles get only a few pixels wide
		float fade = smoothstep(5.0, 12.0, 1.0 / max(max(fw.x, fw.y), 1e-5));
		c *= 1.0 - grid_line * line * (flat_top > 0.5 ? 1.0 : 0.7) * fade;
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
	ALBEDO = pow(c, vec3(2.2)); // palette is sRGB
	ROUGHNESS = rough;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = n.z < 0.0 ? -n : n;
}
