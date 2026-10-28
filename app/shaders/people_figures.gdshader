// The people up close: a small low-poly figure (people_dots.gd _figure_mesh,
// 1 unit = 1.7 m, drawn at diorama scale like the houses and trees) at the
// spot the placement pass gave each person. Only the people near the camera
// are drawn: ApoleiaPeople.near lists their slots into `list_tex`, one
// instance per entry. Tunic colour by colour mode (as the dots), people on
// the road bob as they walk.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform sampler2D place_tex : filter_nearest, repeat_disable; // people_dots_prep output
uniform sampler2D list_tex : filter_nearest, repeat_disable;  // slots to draw (float)
uniform int list_w = 128;
uniform float figure_scale = 0.04; // world units of the unit figure (1.7 m at diorama scale)
uniform int colour_mode = 0;
uniform vec3 palette[16];
uniform int selected_slot = -1;
uniform vec3 selected_colour : source_color = vec3(1.0, 0.9, 0.1);

varying vec3 colour;

// undyed wool, linen, madder red, woad blue and browns: clothes when the
// people are not coloured by group (sRGB)
const vec3 TUNICS[8] = vec3[](vec3(0.66, 0.58, 0.44), vec3(0.84, 0.8, 0.7), vec3(0.5, 0.36, 0.24),
	vec3(0.62, 0.27, 0.2), vec3(0.36, 0.42, 0.56), vec3(0.46, 0.48, 0.36), vec3(0.74, 0.64, 0.42), vec3(0.56, 0.44, 0.38));
const vec3 SCARVES[4] = vec3[](vec3(0.88, 0.84, 0.74), vec3(0.7, 0.36, 0.28), vec3(0.42, 0.48, 0.62), vec3(0.78, 0.7, 0.5));
// part codes in the vertex alpha (people_dots.gd FIG_*)
const float LEG_L = 0.2;
const float LEG_R = 0.4;
const float ARM_L = 0.6;
const float ARM_R = 0.8;
const float HAIR = 0.9;

// rotates p about the horizontal x axis through height `pivot`
vec3 swing(vec3 p, float pivot, float angle) {
	float c = cos(angle), s = sin(angle);
	vec2 q = vec2(p.y - pivot, p.z);
	return vec3(p.x, pivot + c * q.x - s * q.y, s * q.x + c * q.y);
}

bool part(float a, float code) {
	return abs(a - code) < 0.05;
}

void vertex() {
	int id = INSTANCE_ID;
	int slot = int(texelFetch(list_tex, ivec2(id % list_w, id / list_w), 0).r);
	int per = page_side * page_side;
	int in_page = slot % per;
	ivec2 px = ivec2(in_page % page_side, (slot / per) * page_side + in_page / page_side);
	vec4 rec = dot_record(px);
	vec4 place = texelFetch(place_tex, px, 0);
	uint w = uint(rec.w);
	uint kind = w & 3u;
	bool female = ((w >> 22u) & 1u) == 1u;
	bool child = ((w >> 23u) & 1u) == 1u;
	vec2 r = dot_rand2(uint(slot), 31u);
	vec2 r2 = dot_rand2(uint(slot), 37u);
	bool walking = kind >= 2u;
	float a_code = COLOR.a;
	vec3 v = VERTEX;
	// a long dress on women: the tunic hem goes down to the ankles
	if (female && a_code < 0.05 && v.y < 0.5) {
		v.y = 0.07;
		v.xz *= 1.25;
	}
	// walking: legs and arms swing; standing: arms hang with a slight sway
	float phase = TIME * (walking ? 7.0 : 1.3) + r.y * 6.2831853;
	float leg = walking ? 0.45 * sin(phase) : 0.0;
	float arm = walking ? 0.5 * sin(phase) : 0.06 * sin(phase);
	if (part(a_code, LEG_L)) v = swing(v, 0.47, leg);
	if (part(a_code, LEG_R)) v = swing(v, 0.47, -leg);
	if (part(a_code, ARM_L)) v = swing(v, 0.79, -arm);
	if (part(a_code, ARM_R)) v = swing(v, 0.79, arm);
	// people standing about turn now and then; walkers face their way
	float a = r.x * 6.2831853 + (walking ? 0.0 : floor(TIME * 0.05 + r2.x * 8.0) * 2.1);
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	float s = figure_scale * (child ? 0.62 : (female ? 0.94 : 1.0) * (0.94 + 0.1 * r2.y)) * (slot == selected_slot ? 1.4 : 1.0);
	v *= s;
	v.xz = rot * v.xz;
	float lift = walking ? abs(sin(phase)) * 0.025 * s : 0.0;
	vec2 p = rec.xy + place.xy - 32.0;
	vec3 world = vec3(p.x, place.z * level_h + lift, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = rot * nrm.xz;
	bool show = rec.z != 0.0 && place.a > 0.5;
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	vec3 tunic;
	if (slot == selected_slot) {
		tunic = selected_colour;
	} else if (colour_mode == 0) {
		tunic = pow(TUNICS[int(r.y * 7.999)], vec3(2.2));
	} else {
		tunic = palette[colour_mode == 3 ? int((w >> 2u) & 3u) : int((w >> 4u) & 15u)];
	}
	vec3 own = pow(COLOR.rgb, vec3(2.2));
	if (part(a_code, HAIR) && female) {
		own = pow(SCARVES[int(r2.x * 3.999)], vec3(2.2));
	}
	colour = a_code < 0.05 ? tunic : own;
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}
