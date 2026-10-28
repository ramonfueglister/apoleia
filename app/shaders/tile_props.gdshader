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
	float s = prop_scale * (prop_kind == 3 ? (0.85 + 0.3 * r0) : (0.75 + 0.5 * r0) * edge_size);
	float a = floor(r2 * 4.0) * 1.5707963; // voxel props keep to the tile grid
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec3 v = VERTEX * s;
	if (prop_kind == 3) { v.y *= 0.8 + 0.6 * r1 * float(town >= 2); }
	v.xz = rot * v.xz;
	vec3 world = vec3(p.x, level * level_h, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = rot * nrm.xz;
	// hidden slots: all vertices on one point behind the camera, no area
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	tint = prop_kind == 3 ? vec3(0.94 + 0.12 * r1) : vec3(0.88 + 0.22 * r1, 0.92 + 0.14 * r2, 0.9 + 0.1 * r0);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb * tint, vec3(2.2)); // vertex colours are sRGB

	ROUGHNESS = 1.0;
}
