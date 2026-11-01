// Blender metre geometry on the existing GPU tree slots. The list stores
// absolute parcel/slot IDs; the current placement texture remains authoritative.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;
uniform sampler2D place_tex : filter_nearest, repeat_disable;
uniform ivec2 prop_origin;
uniform int prop_n = 100;
uniform vec2 world_min;
uniform float tile_km = 0.25;
uniform float level_h = 0.15;
uniform bool native_active = false;
uniform bool olive_model = false;
void vertex() {
	ivec2 t = ivec2(INSTANCE_CUSTOM.xy + 0.5);
	int packed_slot = int(INSTANCE_CUSTOM.z + 0.5);
	int slot = packed_slot % 8;
	int expected_code = packed_slot / 8;
	ivec2 local = t - prop_origin;
	bool show = native_active && all(greaterThanEqual(local, ivec2(0))) && all(lessThan(local, ivec2(prop_n)));
	vec4 d = show ? texelFetch(place_tex, local * 3 + ivec2(slot % 3, slot / 3), 0) : vec4(0.0, 0.0, 0.0, -1.0);
	show = show && d.w >= 0.0 && int(floor(d.w)) == expected_code;
	float a = INSTANCE_CUSTOM.w;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	float size = olive_model ? 1.0 : fract(d.w) * 4.0;
	// The native asset defines adult size. Only original habitat size is
	// retained, uniformly in all axes; no distant 1.8x tree growth.
	vec3 v = VERTEX * (0.0238 * size);
	v.xz = rot * v.xz;
	vec2 p = world_min + (vec2(t) + d.xy) * tile_km;
	vec3 world = vec3(p.x, d.z * level_h, p.y) + v;
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	vec3 n = NORMAL;
	n.xz = rot * n.xz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
