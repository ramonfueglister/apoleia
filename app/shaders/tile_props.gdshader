// Trees and houses on the tile terrain. One MultiMesh per kind; every instance
// is a fixed slot (tile of the prop patch, slot number). The vertex stage
// decides from the tile data whether the slot shows a prop and where it stands,
// so props follow the terrain at every zoom without CPU placement.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform int prop_kind = 0;     // 0 broadleaf, 1 conifer, 2 cypress, 3 house, 4 stone pine
uniform ivec2 prop_origin;
uniform int prop_n = 96;
uniform int slots = 4;
uniform float prop_scale = 0.4; // world units of a unit prop

varying vec3 tint;

float pick(vec4 v, int k) {
	return k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w;
}

void vertex() {
	int id = INSTANCE_ID;
	int slot = id % slots;
	int ti = id / slots;
	ivec2 t = prop_origin + ivec2(ti % prop_n, ti / prop_n);
	int cell = tt_cell(t);
	int water = cell & 3;
	int town = cell >> 2;
	vec2 centre = tt_tile_center(t);
	float r0 = tt_hash3(vec3(vec2(t), float(slot) * 3.17));
	float r1 = tt_hash3(vec3(vec2(t) + 11.3, float(slot) * 1.91));
	float r2 = tt_hash3(vec3(vec2(t) - 4.7, float(slot) * 5.03));
	bool show = water == W_LAND;
	float edge_size = 1.0;
	vec2 uv;
	if (prop_kind == 3) {
		// house blocks on the street grid of the town tile (house_grid^2 = slots)
		int side = int(ceil(sqrt(float(slots))));
		float share = town == 3 ? 1.0 : town == 2 ? 0.6 : town == 1 ? 0.15 : 0.0;
		int count = max(int(round(share * float(slots))), town > 0 ? 1 : 0);
		show = show && slot < count;
		int cell_k = town == 3 ? slot : (slot * 7 + int(tt_hash(vec2(t)) * float(slots))) % slots;
		vec2 sub = vec2(float(cell_k % side), float(cell_k / side));
		uv = (sub + 0.5) / float(side) + (vec2(r1, r2) - 0.5) * 0.03;
	} else {
		show = show && town == 0;
		vec4 cov = tt_cover(centre);
		float density = tt_tree_density(centre, cov.r);
		// single trees mostly where the wood thins out, few in open land
		float edge = smoothstep(0.0, 0.25, density) * (1.0 - smoothstep(0.5, 0.9, density));
		float lone = 0.015 + 0.10 * cov.g * 0.3 + 0.35 * edge;
		float n = floor(density * float(slots) + tt_hash(vec2(t) * 0.913) * 0.8);
		bool lone_tree = slot == slots - 1 && tt_hash(vec2(t) * 1.37 + 2.0) < lone;
		show = show && (float(slot) < n || lone_tree);
		edge_size = mix(0.7, 1.0, smoothstep(0.15, 0.7, density)); // smaller at the wood edge
		float h = tt_height_m(centre, height_lod);
		float lat = tt_latitude(centre);
		show = show && h < 1400.0 && cov.g < 0.7;
		float conifer_p = clamp((h - 700.0) / 700.0, 0.0, 1.0) + clamp((lat - 50.0) / 4.0, 0.0, 1.0);
		// stone pines and cypresses in the warm lowlands, more of them in open land
		bool south = lat < 44.5 && h < 700.0;
		float pine_p = south ? 0.12 + 0.35 * (1.0 - smoothstep(0.2, 0.7, density)) : 0.0;
		int kind = r0 < conifer_p ? 1
			: (south && r0 < conifer_p + pine_p) ? 4
			: (south && r0 < conifer_p + pine_p + 0.1) ? 2 : 0;
		show = show && kind == prop_kind;
		// slots on a jittered grid, so a dense wood covers the tile evenly
		int side = int(ceil(sqrt(float(slots))));
		vec2 g = vec2(float(slot % side), float(slot / side));
		uv = (g + 0.2 + 0.6 * vec2(r1, r2)) / float(side) * 0.9 + 0.05;
	}
	vec4 c = show ? tt_corners(t) : vec4(0.0);
	if (prop_kind != 3 && max(max(c.x, c.y), max(c.z, c.w)) - min(min(c.x, c.y), min(c.z, c.w)) > 1.5) {
		show = false;
	}
	float level = mix(mix(c.x, c.y, uv.x), mix(c.w, c.z, uv.x), uv.y);
	vec2 p = world_min + (vec2(t) + uv) * tile_km;
	float s = prop_scale * (prop_kind == 3 ? (0.85 + 0.3 * r0) : (0.75 + 0.5 * r0) * edge_size);
	float a = prop_kind == 3 ? floor(r2 * 4.0) * 1.5707963 : r2 * 6.2831853;
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
