shader_type spatial;
// Faceted low-poly cumulus clusters (flattened ellipsoids). Instances sit on a
// fixed air-space grid; the weather field decides whether and how large each
// cluster is. Own soft lighting: white tops, light blue-grey shade, facets only
// as gentle brightness steps; translucent rims. Shadows come from
// weather_proxy.gdshader, so this transparent material never casts.
render_mode unshaded, world_vertex_coords, blend_mix, depth_draw_always, cull_back, fog_disabled;
#include "res://shaders/weather_placement.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.68, 0.64, 0.36);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 shade_color : source_color = vec3(0.76, 0.82, 0.90);
// Linear targets, calibrated against the ACES look (0.5 linear already reads near white).
uniform vec3 storm_color : source_color = vec3(0.24, 0.245, 0.29);
uniform float brightness = 1.0;
uniform vec3 flash_pos;
uniform float flash = 0.0;
uniform float flash_radius = 80.0;
instance uniform float fade = 1.0;

varying vec3 world_pos;
varying vec3 smooth_normal;
varying float storm;
varying float grey;
varying float height01;

void vertex() {
	vec4 info;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - origin;
	VERTEX = place_cluster(VERTEX, origin, INSTANCE_CUSTOM, info);
	world_pos = VERTEX;
	smooth_normal = NORMAL;
	storm = info.w;
	grey = clamp(info.z * 1.5, 0.0, 0.92);
	height01 = local.y / max(1.2 * length(MODEL_MATRIX[1].xyz), 0.001);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	if (fade < 0.999 && fade < bayer4(FRAGCOORD.xy)) { discard; }
	vec3 to_camera = INV_VIEW_MATRIX[2].xyz;
	vec3 flat_n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	if (dot(flat_n, to_camera) < 0.0) { flat_n = -flat_n; }
	// Facets stay readable but soft: flat normal pulled towards the cluster normal.
	vec3 n = normalize(mix(flat_n, normalize(smooth_normal), 0.55));
	vec3 l = normalize(sun_dir);
	float wrap = clamp((dot(n, l) + 0.55) / 1.55, 0.0, 1.0);
	vec3 colour = mix(shade_color, sun_color, smoothstep(0.15, 0.85, wrap));
	// Slightly bluer belly.
	colour = mix(colour, shade_color * vec3(0.94, 0.97, 1.02), smoothstep(0.35, 0.0, height01) * 0.5);
	float facing = clamp(dot(n, to_camera), 0.0, 1.0);
	// Light shining through the thin rim, strongest with the sun behind the cloud.
	float back = clamp(-dot(to_camera, l) * 0.5 + 0.5, 0.0, 1.0);
	colour += pow(1.0 - facing, 3.0) * sun_color * vec3(1.0, 0.9, 0.75) * (0.12 + 0.3 * back);
	colour = mix(colour, vec3(0.21, 0.225, 0.25) * (0.75 + 0.5 * wrap), grey);
	float storm_amount = smoothstep(0.02, 0.25, storm);
	vec3 slate = storm_color * (0.7 + 0.6 * wrap) + sun_color * vec3(1.0, 0.55, 0.38) * 0.18 * wrap * smoothstep(0.4, 0.95, height01);
	colour = mix(colour, slate, storm_amount);
	float near_flash = flash * (1.0 - smoothstep(0.0, flash_radius, distance(world_pos.xz, flash_pos.xz)));
	colour += near_flash * vec3(1.4, 1.45, 1.8) * (0.6 + storm);
	ALBEDO = colour * brightness;
	// Translucent rims; grey rain banks are thinner overall.
	ALPHA = mix(0.7, 1.0, smoothstep(0.08, 0.5, facing)) * mix(1.0, 0.82, grey) * fade;
}
