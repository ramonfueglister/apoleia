// Trees and houses on the tile terrain. One MultiMesh for the trees of every
// kind and one per lot model; every instance is a fixed slot (tile of the
// prop patch, slot number). A small 2D pass (tile_prop_prep.gdshader) decides
// once per frame from the tile data whether each slot shows a prop and where
// it stands; the vertex stage only reads that, so props follow the terrain at
// every zoom without CPU placement.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/tile_props.gdshaderinc"

uniform int prop_kind = 0;     // 0 trees (every kind), 3 house (a Roman lot model), 5 terrace under a lot on a ramp
uniform ivec2 prop_origin;
uniform int prop_n = 96;
uniform int slots = 4;
uniform int lot_variant = -1;  // houses: which Roman lot model (tile_terrain.gd LOT_KINDS)
uniform int lot_variants = 1;
uniform float prop_scale = 0.4; // world units of a unit prop
uniform sampler2D place_tex : filter_nearest, repeat_disable; // tile_prop_prep output
uniform bool place_ready = false;
uniform int place_tree_w = 300;
uniform sampler2D town_tex : filter_nearest, repeat_disable; // the patch's town tiles (local index), tile_terrain.gd
uniform int town_count = -1; // how many; -1: every tile of the patch
uniform int lot_start = 0; // a lot model's slots in town_tex
uniform int lot_count = 0;
uniform int town_w = 100;
// The trees' blocks (tile_prop_meshes.gd tree_table): TREE_BLOCKS a kind, in
// the order broadleaf, conifer, cypress, stone pine (place codes 0, 1, 2, 4).
// The tree mesh is unit blocks, UV.x the block's number, each stretched to
// its block of the slot's kind: one tree instance a slot draws every kind.
const int TREE_BLOCKS = 5;
uniform vec3 tree_lo[20];
uniform vec3 tree_hi[20];
uniform vec3 tree_top[20];
uniform vec3 tree_side[20];

varying vec3 tint;
varying float road; // a paved street tile's terrace top
varying float olive; // an olive tree (a small broadleaf, tile_props.gdshaderinc)

// Up close (quarter tiles) every lot stands on a terrace block of the whole
// tile with a street along its south side (Kritik r8: lots butted front to
// back with no street): the lot keeps its width, is SUB_LOT_DEPTH as deep and
// stands at the north side. On a street block (tt_sub_street) the terrace is
// paved and holds no lot.
const float SUB_LOT_DEPTH = 0.9;
const float SUB_LOT_NORTH = 0.01; // gap behind the lot, tile units
const float TERRACE_STEP_M = 0.25; // a terrace on flat ground stands this high
const vec3 ROAD_RGB = vec3(0.639, 0.596, 0.463); // as the street on the terrace top (PLINTH_ROAD)
// an olive crown's grey green on the broadleaf's (Kritik r9: lit #8a9a64,
// shade #5e7048 on screen)
const vec3 OLIVE_TINT = vec3(2.0, 1.09, 1.9);

float pick(vec4 v, int k) {
	return k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w;
}

void vertex() {
	int id = INSTANCE_ID;
	bool house = prop_kind == 3 || prop_kind == 5;
	bool listed = true;
	int slot;
	int ti;
	if (house && town_count >= 0) {
		// the house instances run over the town tiles of the patch only
		// (tile_terrain.gd _update_town_list): the terraces over all their
		// slots, a lot model over the slots it holds
		int e = lot_variant >= 0 ? lot_start + id : id / slots;
		listed = lot_variant >= 0 ? id < lot_count : e < town_count;
		int v = listed ? int(texelFetch(town_tex, ivec2(e % town_w, e / town_w), 0).r + 0.5) : 0;
		ti = lot_variant >= 0 ? v / 16 : v;
		slot = lot_variant >= 0 ? v % 16 : id % slots;
	} else {
		// a lot model draws one house slot in every block of lot_variants
		// slots, a different one in each block, so all models together fill
		// every slot once
		if (lot_variant >= 0) {
			int pick_k = int(tt_hash(vec2(float(INSTANCE_ID), 7.3)) * float(lot_variants));
			id = INSTANCE_ID * lot_variants + (lot_variant + pick_k) % lot_variants;
		}
		slot = id % slots;
		ti = id / slots;
	}
	ivec2 local = ivec2(ti % prop_n, ti / prop_n);
	ivec2 t = prop_origin + local;
	// placed once per frame by tile_prop_prep.gdshader; the full rule only
	// before that pass has run
	ivec2 px = local * 3 + ivec2(slot % 3, slot / 3) + ivec2(house ? place_tree_w : 0, 0);
	vec4 d = !listed ? vec4(0.0, 0.0, 0.0, -1.0) : place_ready ? texelFetch(place_tex, px, 0) : tt_prop_place(t, slot, slots, house);
	bool show = d.w >= 0.0;
	road = 0.0;
	olive = 0.0;
	tint = vec3(1.0);
	if (show) {
		float r0 = tt_hash3(vec3(vec2(t), float(slot) * 3.17));
		float r1 = tt_hash3(vec3(vec2(t) + 11.3, float(slot) * 1.91));
		float r2 = tt_hash3(vec3(vec2(t) - 4.7, float(slot) * 5.03));
		float edge_size = house ? 1.0 : fract(d.w) * 4.0;
		vec2 uv = d.xy;
		float level = d.z;
		vec2 p = world_min + (vec2(t) + uv) * tile_km;
		// the lots fill their slot but for a street (prop_scale); trees vary
		float s = prop_scale * (house ? 1.0 : (0.75 + 0.5 * r0) * edge_size);
		// voxel props keep to the tile grid; a lot shows its front (+z, with the
		// door) to the camera (Kritik r7: turned lots showed blank side walls)
		float a = house ? 0.0 : floor(r2 * 4.0) * 1.5707963;
		mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		vec3 m = VERTEX;
		if (!house) {
			int kind = int(floor(d.w));
			int b = (kind == 4 ? 3 : kind) * TREE_BLOCKS + int(UV.x + 0.5);
			m = mix(tree_lo[b], tree_hi[b], VERTEX);
			// light top, darker sides and underside (tile_prop_meshes.gd _box)
			COLOR = vec4(NORMAL.y > 0.5 ? tree_top[b] : NORMAL.y < -0.5 ? tree_side[b] * 0.6 : tree_side[b], 1.0);
		}
		vec3 v = m * s;
		olive = !house && int(floor(d.w)) == 0 && edge_size < OLIVE_SIZE + 0.05 ? 1.0 : 0.0;
		float lift = 0.0;
		if (house && sub_tiles) {
			// the terrace block covers the tile: level at its highest corner,
			// its wall down to the lowest; the lot on top, north of the street
			vec4 c = tt_corners_cached(t);
			float hi = max(max(c.x, c.y), max(c.z, c.w));
			float lo = min(min(c.x, c.y), min(c.z, c.w));
			bool street = d.w >= STREET_CODE;
			lift = TERRACE_STEP_M * s;
			level = hi;
			if (prop_kind == 5) {
				float wall = (hi - lo) * level_h + lift;
				float off = UV.x * s; // the coping and base rows keep their height
				v = vec3(VERTEX.x * tile_km * 0.1, 0.0, VERTEX.z * tile_km * 0.1);
				// the south face a hair in front of the ground's step below it
				// (tt_corners lowers the ground south of a lot)
				v.z += VERTEX.z > 4.9 ? 0.003 * tile_km : 0.0;
				v.y = VERTEX.y > 0.5 ? max(off, -0.5 * wall) : -wall + min(off, 0.5 * wall);
				road = street && NORMAL.y > 0.5 ? 1.0 : 0.0;
				uv = vec2(0.5);
			} else {
				float lot = 10.0 * s / tile_km; // lot width in tile units
				show = show && !street;
				v.z *= SUB_LOT_DEPTH;
				uv.y = SUB_LOT_NORTH + 0.5 * lot * SUB_LOT_DEPTH;
			}
			p = world_min + (vec2(t) + uv) * tile_km;
		} else if (house) {
			// the lots of a town tile stand level at its highest corner; on a
			// ramp a stone terrace (prop kind 5) fills the space down to the
			// ground, as the houses of a hill town stand on retaining walls (they
			// tilted with the ramp before: slanted cards at 22 km; each lot on its
			// own step drew a town on a slope as a sheared bar code at 70 km,
			// Kritik r9). The terrace fills its lot's whole slot, so the
			// terraces of a town tile join into one podium (one under each lot
			// stood as stilts with the ramp between them at 70 and 120 km,
			// Kritik r10).
			vec4 c = tt_corners_cached(t);
			float fill = prop_kind == 5 ? tile_km / (ceil(sqrt(float(slots))) * s * 10.0) : 1.0;
			v.xz *= fill;
			float e = 0.5 * s * 10.0 / tile_km * fill; // half the lot (or slot) in tile units
			float hi = max(max(c.x, c.y), max(c.z, c.w)), lo = 1e6;
			for (int k = 0; k < 4; k++) {
				vec2 f = clamp(uv + vec2(k == 1 || k == 2 ? e : -e, k >= 2 ? e : -e), 0.0, 1.0);
				lo = min(lo, tt_level_in_tile(t, c, f));
			}
			level = hi;
			if (prop_kind == 5) {
				show = show && hi - lo > 0.01;
				v.y = (VERTEX.y - 1.0) * (hi - lo) * level_h;
			}
		}
		v.xz = rot * v.xz;
		vec3 world = vec3(p.x, level * level_h + lift, p.y) + v;
		vec3 nrm = NORMAL;
		nrm.xz = rot * nrm.xz;
		VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
		tint = prop_kind == 3 ? vec3(0.96 + 0.08 * r1) : prop_kind == 5 ? vec3(1.0) : vec3(0.88 + 0.22 * r1, 0.92 + 0.14 * r2, 0.9 + 0.1 * r0);
		// the sides turned to the SimCity light of the terrain a little lighter
		// (the terrace walls carry their tone per side in the mesh)
		vec3 art = tt_art_light(INV_VIEW_MATRIX);
		float facing = abs(nrm.y) < 0.5 && prop_kind != 5 ? dot(normalize(nrm.xz), normalize(art.xz)) : 0.0;
		tint *= 1.0 + 0.25 * max(facing, 0.0);
	} else {
		// an empty slot costs no more than the lines above: all its vertices
		// on one point behind the camera, no area (most slots are empty)
		VERTEX = vec3(0.0, 0.0, 1.0e6);
	}
}

void fragment() {
	vec3 c = mix(COLOR.rgb, ROAD_RGB, road);
	c *= olive > 0.5 && c.g > c.r ? OLIVE_TINT : vec3(1.0); // the crown, not the trunk
	ALBEDO = pow(c * tint, vec3(2.2)); // vertex colours are sRGB

	ROUGHNESS = 1.0;
}
