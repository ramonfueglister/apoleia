// Steps of the shore up close (coast_steps.gdshaderinc). One instance per
// side of a sea tile in front of open land or a town and per coast cut
// (TileTerrain._update_coast_list, INSTANCE_CUSTOM: data tile x, y and the
// side, or 4 + the corner of a cut's wet half); the instance mesh holds
// CS_CELLS columns of two blocks, the rock headland (on a cut the stair,
// sand where it has no headland) at the land's level and the sand ledge half
// way down, each a top, a front and two side walls (tile_prop_meshes.gd
// coast_steps_template); in front of a town the ledge is its quay, a path
// just below the town on a stone kerb. The vertex stage sizes them; an
// empty block folds to a point. Lit as the tiles: flat ground, with the
// SimCity 2000 wall tones of tile_terrain.gdshader.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/coast_steps.gdshaderinc"

const vec3 C_ROCK = vec3(0.6, 0.57, 0.5);       // limestone, as the dry-stone walls (people_crops)
const vec3 C_SAND = vec3(0.804, 0.745, 0.510);  // the beach (tile_terrain.gdshader)
const vec3 C_BANK = vec3(0.588, 0.549, 0.392);  // the coast's walls (tile_terrain.gdshader)
const vec3 C_PATH = vec3(0.70, 0.66, 0.58);     // the quay's path (Urbek: beige)
const vec3 C_KERB = vec3(0.57, 0.56, 0.53);     // and its kerb (Urbek: grey stone)

varying vec3 world_pos;
varying flat int tier;      // 0 headland, 1 ledge
varying flat int face;      // 0 top, 1 front, 2 and 3 the sides
varying flat vec2 wall_n;   // outward normal of a wall (world xz)
varying flat float shade;   // 0..1, one per block
varying flat int rock;      // a headland
varying flat int quay;      // a town's quay

void vertex() {
	ivec2 s = ivec2(INSTANCE_CUSTOM.xy + 0.5);
	int k = int(INSTANCE_CUSTOM.z + 0.5);
	bool cut = k >= 4; // the columns run along side k of the tile either way
	k &= 3;
	int col = int(VERTEX.x + 0.5);
	tier = int(VERTEX.y + 0.5);
	face = int(VERTEX.z + 0.5) >> 2;
	int corner = int(VERTEX.z + 0.5) & 3;
	ivec2 depth = cut ? cs_depth_cut(s, k, col, cs_cut_bits(s, k)) : cs_depth(s, k, col, cs_side(s, k));
	rock = tier == 0 && depth.x > (cut ? 1 : 0) ? 1 : 0;
	quay = !cut && cs_quay(s, k) ? 1 : 0;
	float n = float(CS_CELLS);
	float out_to = float(tier == 0 ? depth.x : depth.y) / n;
	// a cut's stair a little above the land's edge level, over the half
	// cells of the diagonal (where the land lies at that level too)
	float top = tier == 1 ? (quay == 1 ? -0.2 : -0.5) * tt_water_drop() : cut ? 0.02 : 0.0;
	float bottom = -tt_water_drop();
	float a0 = float(col) / n;
	float a1 = float(col + 1) / n;
	// (along the side, out from it, level)
	vec3 q;
	if (face == 0) {
		q = vec3(corner == 0 || corner == 3 ? a0 : a1, corner >= 2 ? out_to : 0.0, top);
	} else if (face == 1) {
		q = vec3(corner == 0 || corner == 3 ? a0 : a1, out_to, corner < 2 ? top : bottom);
	} else {
		q = vec3(face == 2 ? a0 : a1, corner == 1 || corner == 2 ? out_to : 0.0, corner < 2 ? top : bottom);
	}
	if (out_to <= 0.0) { q = vec3(a0, 0.0, bottom); } // no block: a point
	vec2 a = vec2(CS_CORNER[k]);
	vec2 e = vec2(CS_CORNER[(k + 1) & 3]) - a;
	// out from side k into the sea tile, or on a cut from the diagonal
	// ((CS_CELLS - col) cells in from side k) out towards side k
	vec2 outward = cut ? vec2(CS_SIDE[k]) : -vec2(CS_SIDE[k]);
	vec2 base = cut ? -vec2(CS_SIDE[k]) * (float(CS_CELLS - col) / n) : vec2(0.0);
	vec2 uv = vec2(s) + a + base + e * q.x + outward * q.y;
	world_pos = vec3(world_min.x + uv.x * tt_data_km(), q.z * level_h, world_min.y + uv.y * tt_data_km());
	wall_n = face == 1 ? outward : face == 2 ? -e : e;
	shade = tt_hash(vec2(s) * 1.7 + vec2(float(k * CS_CELLS + col), float(tier) * 3.1) * 0.37);
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec3 art = tt_art_light(INV_VIEW_MATRIX);
	// rock blocks a little lighter or darker each; sand on the ledge and on a
	// cut's stair over earth walls; a quay's path on its kerb
	vec3 c = rock == 1 ? C_ROCK * (0.9 + 0.18 * shade) : face == 0 ? C_SAND * (0.94 + 0.08 * shade) : C_BANK * (0.95 + 0.1 * shade);
	if (quay == 1) { c = (face == 0 ? C_PATH : C_KERB) * (0.97 + 0.06 * shade); }
	if (face != 0) {
		// lit like the tiles' walls: light facing the camera, darker the more
		// a wall turns east
		c *= mix(0.70, 1.0, smoothstep(-0.8, 0.8, dot(wall_n, normalize(art.xz))));
	}
	ALBEDO = pow(clamp(c, 0.0, 1.0), vec3(2.2)); // palette is sRGB
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
