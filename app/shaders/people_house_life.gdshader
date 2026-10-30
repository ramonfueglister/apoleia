// What the simulation has at each village house, beside the house
// (people_house_life.gd, Ramon 30.10.2026 "Wuselfaktor": only what the sim
// has): smoke from the roof where the household has food to cook, a tent
// instead of the farmhouse for a tent household, sheaves in the yard while
// its farm's harvest wants hands and seed sacks while its sowing does, its
// farm's sheep round the yard and its pigs in a pen. One instance per
// house of the house list (people_houses.gdshader: the nearest first), the
// spot from the house placement pass; what the house has from `look_tex`
// (ApoleiaPeople.house_looks, RGBA8 by house slot as the house texture:
// share eaten ‰ / 4, flags, sheep, pigs). The mesh is in metres about the
// house's middle, its front +z, turned and sized with the house (1 house
// unit = 10 m); UV.x the part: smoke puffs 0-2, sheep 3-10, pigs 11-13,
// the pen 14, the tent 15, sheaves 16, seed sacks 17.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform sampler2D place_tex : filter_nearest, repeat_disable;
uniform sampler2D list_tex : filter_nearest, repeat_disable;
uniform int list_w = 128;
uniform sampler2D look_tex : filter_nearest, repeat_disable;
uniform float km_per_m = 0.0238; // the house's scale (TileTerrain.HOUSE_M units of DIORAMA_KM_PER_M)
const int COOKS = 1;
const int TENT = 2;
const int HARVEST = 4;
const int SOWING = 8;
const int SHEEP_MAX = 8;
const vec3 CHIMNEY = vec3(1.5, 6.2, -0.6); // above the roof of the main house (farmhouse.gd), metres
const vec3 HOUSE_LIGHT = vec3(-0.63, 0.72, 0.294); // as people_houses.gdshader

varying vec3 colour;
varying vec3 art_light;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	int id = int(texelFetch(list_tex, ivec2(INSTANCE_ID % list_w, INSTANCE_ID / list_w), 0).r);
	int per = page_side * page_side;
	int in_page = id % per;
	ivec2 px = ivec2(in_page % page_side, (id / per) * page_side + in_page / page_side);
	vec4 rec = dot_record(px);
	vec4 place = texelFetch(place_tex, px, 0);
	ivec4 look = ivec4(texelFetch(look_tex, px, 0) * 255.0 + 0.5);
	int flags = look.g;
	vec2 p = rec.xy + place.xy - 32.0;
	vec2 st;
	mat2 turn = dot_house_turn(p, st);
	int part = int(UV.x + 0.5);
	float seed = h1(float(id) * 0.37 + 1.0);
	bool tent = (flags & TENT) != 0;
	bool show = rec.z > 0.0 && place.a > 0.5; // no building sites
	vec3 v = VERTEX;
	if (part <= 2) {
		// a puff rises from the chimney, drifts with the wind, grows and is gone
		float t = fract(TIME * 0.22 + float(part) / 3.0 + seed);
		float size = sin(t * PI) * (0.8 + t * 1.6);
		v = v * size + CHIMNEY + vec3(t * 2.5, t * 9.0, t * 0.8);
		show = show && (flags & COOKS) != 0 && !tent;
	} else if (part <= 10) {
		int k = part - 3;
		float a = (float(k) / float(SHEEP_MAX) + seed) * TAU;
		float r = 10.5 + h1(float(k) + seed * 7.0) * 3.0;
		float graze = sin(TIME * 0.15 + float(k) * 1.7) * 0.8; // slowly round the yard
		vec2 at = vec2(cos(a + graze * 0.05), sin(a + graze * 0.05)) * r;
		float face = a + PI * 0.5 + (h1(float(k) * 3.1) - 0.5);
		mat2 m = mat2(vec2(cos(face), -sin(face)), vec2(sin(face), cos(face)));
		if (v.z > 0.45 && v.y > 0.45) { v.y -= 0.25 * max(sin(TIME * 0.7 + float(k)), 0.0); } // the head down to the grass
		v.xz = m * v.xz;
		v.xz += at;
		show = show && k < min(look.b, SHEEP_MAX) && !tent;
	} else if (part <= 13) {
		int k = part - 11;
		v.xz += vec2(-9.5 + float(k) * 1.6, -7.0 + h1(float(k) + seed) * 1.5) + vec2(sin(TIME * 0.3 + float(k) * 2.0) * 0.5, 0.0);
		show = show && k < look.a && !tent;
	} else if (part == 14) {
		show = show && look.a > 0 && !tent;
	} else if (part == 15) {
		show = show && tent;
	} else if (part == 16) {
		show = show && (flags & HARVEST) != 0 && !tent;
	} else {
		show = show && (flags & SOWING) != 0 && !tent;
	}
	v *= km_per_m * st.x;
	v.xz = turn * v.xz;
	vec3 world = vec3(p.x, place.z * level_h, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = turn * nrm.xz;
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	colour = pow(COLOR.rgb, vec3(2.2)) * COLOR.a; // sRGB, the alpha the voxel corner shading
	art_light = normalize((VIEW_MATRIX * vec4(HOUSE_LIGHT, 0.0)).xyz);
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float shadow = dot(NORMAL, LIGHT) > 0.05 ? ATTENUATION : 1.0;
		DIFFUSE_LIGHT += max(dot(NORMAL, art_light), 0.0) * shadow * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
