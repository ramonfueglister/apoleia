// A house for every village household (sim/src/view.rs Houses), drawn with
// the house mesh and look of the tile terrain (tile_props.gdshader) at the
// household's house spot. One MultiMesh instance per house slot; the record
// comes from the house texture array (ApoleiaPeople.sync_houses, only changed
// pages), the spot from the house placement pass (people_dots_prep.gdshader
// with `houses`), which runs only when houses or the terrain view change.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform sampler2D place_tex : filter_nearest, repeat_disable; // house placement pass
uniform float prop_scale = 0.24; // world units of the unit house (tile_terrain.gd HOUSE_M)

varying vec3 tint;

void vertex() {
	int id = INSTANCE_ID;
	int per = page_side * page_side;
	int in_page = id % per;
	ivec2 px = ivec2(in_page % page_side, (id / per) * page_side + in_page / page_side);
	vec4 rec = dot_record(px);
	vec4 place = texelFetch(place_tex, px, 0);
	uint key = uint(rec.w) >> 8u;
	vec2 r = dot_rand2(key, 7u);
	float a = floor(r.x * 4.0) * 1.5707963; // on the tile grid, like the town houses
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec3 v = VERTEX * prop_scale * (0.85 + 0.3 * r.y);
	v.xz = rot * v.xz;
	vec2 p = rec.xy + place.xy - 32.0;
	vec3 world = vec3(p.x, place.z * level_h, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = rot * nrm.xz;
	bool show = rec.z != 0.0 && place.a > 0.5;
	// empty slots: all vertices on one point behind the camera, no area
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	tint = vec3(0.94 + 0.12 * r.y);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb * tint, vec3(2.2)); // vertex colours are sRGB
	ROUGHNESS = 1.0;
}
