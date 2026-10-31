// The figures' shadows on the ground: a flat strip from each figure's feet
// away from the sun, as long as the sun throws it (`shadow_dir`, per unit
// height, people_dots.gd from the scene's sun), that darkens whatever lies
// under it. The sun's shadow map is too coarse for a body this thin, so
// without it the people look pasted on the grass; the houses' shadows are
// as dark. One instance per figure, placed as people_figures.gdshader
// places them (keep the two in step).
shader_type spatial;
render_mode skip_vertex_transform, unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/people_day.gdshaderinc"

uniform sampler2D place_tex : filter_nearest, repeat_disable; // people_dots_prep output
uniform sampler2D list_tex : filter_nearest, repeat_disable;  // slots to draw (float)
uniform int list_w = 128;
uniform float figure_scale = 0.04;
uniform vec2 shadow_dir = vec2(1.08, -0.5); // ground run of the shadow per unit height (world x, z)
// what the shadow leaves of the light: as dark as a house's shadow on the grass, a little cool
const vec3 SHADE = vec3(0.6, 0.62, 0.68);

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
	uint job = (w >> 4u) & 15u;
	bool female = ((w >> 22u) & 1u) == 1u;
	bool child = ((w >> 23u) & 1u) == 1u;
	vec2 r = dot_rand2(uint(slot), 31u);
	vec2 r2 = dot_rand2(uint(slot), 37u);
	bool playing = child && kind == 0u && r2.x < 0.7;
	float s = figure_scale * (child ? 0.62 : (female ? 0.94 : 1.0) * (0.94 + 0.1 * r2.y));
	vec2 p = rec.xy + place.xy - 32.0;
	float level = place.z;
	// where the person is at this hour (people_day.gdshaderinc); a figure
	// in the house or lying down throws no strip, one sitting a short one
	DayNow day = day_now(uint(slot), (w >> 8u) & 0x3fffu, kind, job, female, child, dot_person_look(px), dot_person_flags(px), dot_person_away(px));
	if (day.pose == DAY_SIT) {
		s *= 0.6;
		playing = false;
	}
	if (day.moved) {
		p += day.offset;
		level = dot_ground_level(p);
	}
	if (playing) {
		float way = r.y < 0.5 ? 1.0 : -1.0;
		float turn = r.x * 6.2831853 + TIME * (0.6 + 0.4 * r2.y) * way;
		p += figure_scale * (1.2 + 1.5 * r2.y) * vec2(cos(turn), sin(turn));
	}
	// the strip: UV.x along it (0 under the feet, 1 at the head's shadow),
	// UV.y across (-1 … 1); body-wide at the feet, head-wide at the end
	vec2 along = shadow_dir;
	vec2 across = normalize(vec2(-along.y, along.x));
	float t = UV.x;
	float half_w = mix(0.17, 0.09, t);
	vec2 ground = p + s * (along * mix(-0.08, 0.95, t) + across * UV.y * half_w);
	vec3 world = vec3(ground.x, level * level_h + 0.02 * s, ground.y);
	bool show = rec.z != 0.0 && place.a > 0.5 && !day.inside && day.pose != DAY_LIE;
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
}

void fragment() {
	ALBEDO = SHADE;
}
