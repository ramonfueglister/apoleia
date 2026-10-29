// Trees and houses on the tile terrain. One MultiMesh per kind; every instance
// is a fixed slot (tile of the prop patch, slot number). A small 2D pass
// (tile_prop_prep.gdshader) decides once per frame from the tile data whether
// each slot shows a prop and where it stands; the vertex stage only reads that,
// so props follow the terrain at every zoom without CPU placement.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/tile_props.gdshaderinc"

uniform int prop_kind = 0;     // 0 broadleaf, 1 conifer, 2 cypress, 3 house (a Roman lot model), 4 stone pine, 5 terrace under a lot on a ramp
uniform ivec2 prop_origin;
uniform int prop_n = 96;
uniform int slots = 4;
uniform int lot_variant = -1;  // houses: which Roman lot model (tile_terrain.gd LOT_KINDS)
uniform int lot_variants = 1;
uniform float prop_scale = 0.4; // world units of a unit prop
uniform sampler2D place_tex : filter_nearest, repeat_disable; // tile_prop_prep output
uniform bool place_ready = false;
uniform int place_tree_w = 300;

varying vec3 tint;
varying float road; // the cross street on a terrace's west strip

// Up close (quarter tiles) every lot stands on a terrace block of the whole
// tile with a street along its south side (Kritik r8: lots butted front to
// back with no street): the lot keeps its width, is SUB_LOT_DEPTH as deep and
// stands at the north side; every CROSS_EVERY-th column a cross street runs
// along the west side, and its lots are SUB_LOT_DEPTH as wide too. (Seen at
// the 30 degree tilt the houses hide the street behind them unless the next
// row stands lower; the cross streets run along the view and stay open.)
const float SUB_LOT_DEPTH = 0.9;
const float SUB_LOT_NORTH = 0.01; // gap behind the lot, tile units
const int CROSS_EVERY = 5;
const float CROSS_STREET = 0.12; // tile units (tile_prop_meshes.gd PLINTH_STREET)
const float TERRACE_STEP_M = 0.25; // a terrace on flat ground stands this high
const vec3 ROAD_RGB = vec3(0.639, 0.596, 0.463); // as the street on the terrace top (PLINTH_ROAD)

float pick(vec4 v, int k) {
	return k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w;
}

void vertex() {
	int id = INSTANCE_ID;
	// a lot model draws one house slot in every block of lot_variants slots,
	// a different one in each block, so all models together fill every slot once
	if (lot_variant >= 0) {
		int pick_k = int(tt_hash(vec2(float(INSTANCE_ID), 7.3)) * float(lot_variants));
		id = INSTANCE_ID * lot_variants + (lot_variant + pick_k) % lot_variants;
	}
	bool house = prop_kind == 3 || prop_kind == 5;
	int slot = id % slots;
	int ti = id / slots;
	ivec2 local = ivec2(ti % prop_n, ti / prop_n);
	ivec2 t = prop_origin + local;
	// placed once per frame by tile_prop_prep.gdshader; the full rule only
	// before that pass has run
	ivec2 px = local * 3 + ivec2(slot % 3, slot / 3) + ivec2(house ? place_tree_w : 0, 0);
	vec4 d = place_ready ? texelFetch(place_tex, px, 0) : tt_prop_place(t, slot, slots, house);
	float r0 = tt_hash3(vec3(vec2(t), float(slot) * 3.17));
	float r1 = tt_hash3(vec3(vec2(t) + 11.3, float(slot) * 1.91));
	float r2 = tt_hash3(vec3(vec2(t) - 4.7, float(slot) * 5.03));
	bool show = d.w >= 0.0 && (house || int(floor(d.w)) == prop_kind);
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
	vec3 v = VERTEX * s;
	road = 0.0;
	float lift = 0.0;
	if (house && sub_tiles) {
		// the terrace block covers the tile: level at its highest corner,
		// its wall down to the lowest; the lot on top, north of the street
		vec4 c = tt_corners_cached(t);
		float hi = max(max(c.x, c.y), max(c.z, c.w));
		float lo = min(min(c.x, c.y), min(c.z, c.w));
		bool cross = ((t.x % CROSS_EVERY) + CROSS_EVERY) % CROSS_EVERY == 0;
		lift = TERRACE_STEP_M * s;
		level = hi;
		if (prop_kind == 5) {
			float wall = (hi - lo) * level_h + lift;
			float off = UV.x * s; // the coping and base rows keep their height
			v = vec3(VERTEX.x * tile_km * 0.1, 0.0, VERTEX.z * tile_km * 0.1);
			v.y = VERTEX.y > 0.5 ? max(off, -0.5 * wall) : -wall + min(off, 0.5 * wall);
			road = cross && UV.y > 0.5 ? 1.0 : 0.0;
			uv = vec2(0.5);
		} else {
			float lot = 10.0 * s / tile_km; // lot width in tile units
			v.z *= SUB_LOT_DEPTH;
			uv.y = SUB_LOT_NORTH + 0.5 * lot * SUB_LOT_DEPTH;
			if (cross) {
				v.x *= SUB_LOT_DEPTH;
				uv.x = CROSS_STREET + 0.01 + 0.5 * lot * SUB_LOT_DEPTH;
			}
		}
		p = world_min + (vec2(t) + uv) * tile_km;
	} else if (house) {
		// a lot stands level at the highest ground under it; on a ramp a
		// stone terrace (prop kind 5) fills the space down to the lowest, as
		// the houses of a hill town stand on retaining walls (they tilted
		// with the ramp before: slanted cards at 22 km)
		vec4 c = tt_corners_cached(t);
		float e = 0.5 * s * 10.0 / tile_km; // half the lot in tile units
		float hi = -1e6, lo = 1e6;
		for (int k = 0; k < 4; k++) {
			vec2 f = clamp(uv + vec2(k == 1 || k == 2 ? e : -e, k >= 2 ? e : -e), 0.0, 1.0);
			float l = tt_level_in_tile(t, c, f);
			hi = max(hi, l);
			lo = min(lo, l);
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
	// hidden slots: all vertices on one point behind the camera, no area
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	tint = prop_kind == 3 ? vec3(0.96 + 0.08 * r1) : prop_kind == 5 ? vec3(1.0) : vec3(0.88 + 0.22 * r1, 0.92 + 0.14 * r2, 0.9 + 0.1 * r0);
	// the sides turned to the SimCity light of the terrain a little lighter
	// (the terrace walls carry their tone per side in the mesh)
	vec3 art = tt_art_light(INV_VIEW_MATRIX);
	float facing = abs(nrm.y) < 0.5 && prop_kind != 5 ? dot(normalize(nrm.xz), normalize(art.xz)) : 0.0;
	tint *= 1.0 + 0.25 * max(facing, 0.0);
}

void fragment() {
	ALBEDO = pow(mix(COLOR.rgb, ROAD_RGB, road) * tint, vec3(2.2)); // vertex colours are sRGB

	ROUGHNESS = 1.0;
}
