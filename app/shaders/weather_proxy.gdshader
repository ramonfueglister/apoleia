shader_type spatial;
// Opaque stand-ins for the transparent clouds. mode 1: shadow proxy on the cloud
// layer (SHADOWS_ONLY), moved so the shadow lands just below the cloud as seen by
// the camera; only the weaker cloud sun sees this layer, so the shadow stays
// lighter than tree shadows. mode 2: the same footprint drawn top-down into the
// water cloud-shadow mask (1 = full sun).
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_opaque, fog_disabled;
#include "res://shaders/weather_placement.gdshaderinc"

uniform int mode = 1;
uniform vec2 proxy_shift;
uniform vec2 mask_shift;
uniform float mask_darkness = 0.5;

varying float amount;

void vertex() {
	vec4 info;
	vec3 p = place_cluster(VERTEX, MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM, info);
	amount = step(0.001, info.x);
	// Flat proxy just above the cloud base keeps the cast shape compact.
	p.y = cloud_base + (p.y - cloud_base) * 0.25;
	p.xz += proxy_shift;
	if (mode == 2) { p.xz += mask_shift; }
	VERTEX = p;
}

void fragment() {
	if (amount < 0.3) { discard; }
	ALBEDO = mode == 2 ? vec3(1.0 - mask_darkness) : vec3(0.0);
}
