shader_type spatial;
// Opaque stand-ins for the transparent clouds. mode 1: shadow proxy on the cloud
// layer (SHADOWS_ONLY), moved so the shadow lands just below the cloud as seen by
// the camera; only the weaker cloud sun sees this layer, so the shadow stays
// lighter than tree shadows. mode 2: the same footprint drawn top-down into the
// water cloud-shadow mask (1 = full sun).
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_opaque, fog_disabled;
#include "res://shaders/weather_placement.gdshaderinc"

uniform int mode = 1;
// Per cluster: the ground point the cloud covers as seen from the view camera
// (works for any projection), plus a small screen-down "peek" offset.
uniform vec3 view_camera;
uniform vec2 sun_xz;          // sun direction xz / sun direction y
uniform vec2 peek;
uniform float ground_y = 0.0;
uniform float mask_darkness = 0.5;

varying float amount;
varying float storm;

void vertex() {
	vec4 info;
	vec3 p = place_cluster(VERTEX, MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM, info);
	amount = step(0.001, info.x);
	storm = info.w;
	// Flat proxy just above the cloud base keeps the cast shape compact.
	p.y = cloud_base + (p.y - cloud_base) * 0.25;
	vec2 centre = MODEL_MATRIX[3].xz + air_drift;
	float keep = view_keep(vec3(centre.x, cloud_base, centre.y), 3.4 * info.x * length(MODEL_MATRIX[0].xyz), view_camera, smoothstep(0.55, 0.85, info.y));
	p.xz = centre + (p.xz - centre) * keep;
	p.y = cloud_base + (p.y - cloud_base) * keep;
	float t = (view_camera.y - ground_y) / max(view_camera.y - cloud_base, 1.0);
	vec2 land = view_camera.xz + (centre - view_camera.xz) * t + peek;
	p.xz += land - centre;
	// Shadow proxies sit on the cloud layer, so they move up the sun ray.
	if (mode == 1) { p.xz += sun_xz * (cloud_base - ground_y); }
	VERTEX = p;
}

void fragment() {
	if (amount < 0.3) { discard; }
	// Mask: 1 = no cloud; light under fair clouds, dense under storm fronts.
	ALBEDO = mode == 2 ? vec3(1.0 - min(mask_darkness + 0.6 * storm, 0.9)) : vec3(0.0);
}
