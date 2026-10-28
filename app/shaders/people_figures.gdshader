// The people up close: a small low-poly figure (people_dots.gd _figure_mesh,
// 1 unit = 1.7 m, drawn at diorama scale like the houses and trees) at the
// spot the placement pass gave each person. Only the people near the camera
// are drawn: ApoleiaPeople.near lists their slots into `list_tex`, one
// instance per entry. Tunic colour by colour mode (as the dots), people on
// the road bob as they walk.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

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

// undyed wool, linen and brown: tunics when the dots are not coloured by group
const vec3 TUNICS[6] = vec3[](vec3(0.62, 0.55, 0.42), vec3(0.78, 0.74, 0.64), vec3(0.45, 0.33, 0.22),
	vec3(0.55, 0.28, 0.2), vec3(0.4, 0.42, 0.35), vec3(0.7, 0.62, 0.45));

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
	vec2 r = dot_rand2(uint(slot), 31u);
	float a = r.x * 6.2831853;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	float s = figure_scale * (0.92 + 0.12 * r.y) * (slot == selected_slot ? 1.4 : 1.0);
	vec3 v = VERTEX * s;
	v.xz = rot * v.xz;
	// on the road: a step every half second
	float lift = kind >= 2u ? abs(sin(TIME * 6.0 + r.y * 6.2831853)) * 0.05 * s : 0.0;
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
		tunic = pow(TUNICS[int(r.y * 5.999)], vec3(2.2));
	} else {
		tunic = palette[colour_mode == 3 ? int((w >> 2u) & 3u) : int((w >> 4u) & 15u)];
	}
	// the mesh marks the tunic with alpha 0; legs and head keep their colour
	colour = COLOR.a < 0.5 ? tunic : pow(COLOR.rgb, vec3(2.2));
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}
