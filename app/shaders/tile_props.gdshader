// Trees and houses on the tile terrain. One MultiMesh per kind; every instance
// is a fixed slot (tile of the prop patch, slot number). A small 2D pass
// (tile_prop_prep.gdshader) decides once per frame from the tile data whether
// each slot shows a prop and where it stands; the vertex stage only reads that,
// so props follow the terrain at every zoom without CPU placement.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/tile_props.gdshaderinc"

uniform int prop_kind = 0;     // 0 broadleaf, 1 conifer, 2 cypress, 3 house, 4 stone pine
uniform ivec2 prop_origin;
uniform int prop_n = 96;
uniform int slots = 4;
uniform float prop_scale = 0.4; // world units of a unit prop
uniform sampler2D place_tex : filter_nearest, repeat_disable; // tile_prop_prep output
uniform bool place_ready = false;
uniform int place_tree_w = 300;

varying vec3 tint;

float pick(vec4 v, int k) {
	return k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w;
}

void vertex() {
	int id = INSTANCE_ID;
	int slot = id % slots;
	int ti = id / slots;
	ivec2 local = ivec2(ti % prop_n, ti / prop_n);
	ivec2 t = prop_origin + local;
	// placed once per frame by tile_prop_prep.gdshader; the full rule only
	// before that pass has run
	ivec2 px = local * 3 + ivec2(slot % 3, slot / 3) + ivec2(prop_kind == 3 ? place_tree_w : 0, 0);
	vec4 d = place_ready ? texelFetch(place_tex, px, 0) : tt_prop_place(t, slot, slots, prop_kind == 3);
	float r0 = tt_hash3(vec3(vec2(t), float(slot) * 3.17));
	float r1 = tt_hash3(vec3(vec2(t) + 11.3, float(slot) * 1.91));
	float r2 = tt_hash3(vec3(vec2(t) - 4.7, float(slot) * 5.03));
	bool show = d.w >= 0.0 && (prop_kind == 3 || int(floor(d.w)) == prop_kind);
	float edge_size = prop_kind == 3 ? 1.0 : fract(d.w) * 4.0;
	int town = int(d.w);
	vec2 uv = d.xy;
	float level = d.z;
	vec2 p = world_min + (vec2(t) + uv) * tile_km;
	// houses leave room for the streets of their block grid
	float s = prop_scale * (prop_kind == 3 ? (0.62 + 0.12 * r0) : (0.75 + 0.5 * r0) * edge_size);
	float a = floor(r2 * 4.0) * 1.5707963; // voxel props keep to the tile grid
	// houses stand square to the streets: in towns and villages half of them
	// turn their gable to the camera; in the city core every ridge runs
	// north-south and the houses of a block join into a row (below), so the
	// camera sees gable fronts and both roof slopes, light and dark, as in
	// Urbek, not one orange slab per house
	if (prop_kind == 3) {
		float turn = town == 3 || fract(r2 * 7.31) < 0.5 ? 1.0 : 0.0;
		a = (turn + 2.0 * floor(r2 * 2.0)) * 1.5707963;
	}
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec3 v = VERTEX * s;
	// houses of their own width and depth (the windows stretch with them)
	if (prop_kind == 3) {
		float r3 = tt_hash3(vec3(vec2(t) + 3.1, float(slot) * 2.31));
		v.x *= 0.9 + 0.25 * r3;
		v.z *= 0.9 + 0.2 * fract(r3 * 5.7);
		// city core: each house as long as its block, so the houses of a
		// street join into one row (an insula of a few houses)
		if (town == 3) { v.x = VERTEX.x * 0.92 * tile_km / ceil(sqrt(float(slots))); }
	}
	// in towns two to three storeys, in the city core insulae of up to four
	// (lower than Rome's temples and the Colosseum)
	if (prop_kind == 3) { v.y *= 1.0 + (town == 3 ? 1.0 : town == 2 ? 0.5 : 0.0) * r1; }
	// on a ramp the walls reach down to the lowest ground under the house, as
	// a house on a hillside stands on its lower storey
	if (prop_kind == 3 && VERTEX.y < 0.01) {
		vec4 c = tt_corners_cached(t);
		float slope = max(abs(c.y - c.x), abs(c.z - c.w)) + max(abs(c.w - c.x), abs(c.z - c.y));
		v.y -= slope * 0.5 * s / tile_km * level_h;
	}
	v.xz = rot * v.xz;
	vec3 world = vec3(p.x, level * level_h, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = rot * nrm.xz;
	// hidden slots: all vertices on one point behind the camera, no area
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	tint = prop_kind == 3 ? vec3(0.94 + 0.12 * r1) : vec3(0.88 + 0.22 * r1, 0.92 + 0.14 * r2, 0.9 + 0.1 * r0);
	// every house its own plaster (marked by alpha 0.5): cream, ochre or lime white
	// and its own roof: terracotta, a darker red brown or a faded ochre
	// (the roof slopes are marked by alpha 0.8)
	if (prop_kind == 3 && COLOR.a > 0.7 && COLOR.a < 0.9) {
		float k = fract(r0 * 3.71 + r1 * 1.37);
		tint *= k < 0.5 ? vec3(1.0) : k < 0.8 ? vec3(0.86, 0.79, 0.80) : vec3(1.04, 1.03, 0.92);
	}
	if (prop_kind == 3 && COLOR.a < 0.65) {
		float k = fract(r0 * 7.31 + r2 * 3.17);
		tint *= k < 0.4 ? vec3(1.0) : k < 0.75 ? vec3(0.98, 0.91, 0.78) : vec3(0.99, 1.0, 1.06);
	}
	// the sides turned to the SimCity light of the terrain a little lighter
	vec3 art = tt_art_light(INV_VIEW_MATRIX);
	float facing = abs(nrm.y) < 0.5 ? dot(normalize(nrm.xz), normalize(art.xz)) : 0.0;
	tint *= 1.0 + 0.25 * max(facing, 0.0);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb * tint, vec3(2.2)); // vertex colours are sRGB

	ROUGHNESS = 1.0;
}
