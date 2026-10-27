shader_type spatial;
// Faceted low-poly cumulus clusters (flattened ellipsoids). Instances sit on a
// fixed air-space grid; the weather field decides whether and how large each
// cluster is. Own soft lighting: white tops, light blue-grey shade, facets only
// as gentle brightness steps. Opaque (no inner faces show through); only the
// silhouette is softened by an ordered dither. Shadows come from
// weather_proxy.gdshader, so this transparent material never casts.
// The cluster mesh winds inward, so cull_front keeps only the outer surface;
// with depth written, translucent rain banks never show inner facets.
render_mode unshaded, world_vertex_coords, cull_front, blend_mix, depth_draw_always, fog_disabled;
#include "res://shaders/weather_placement.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.68, 0.64, 0.36);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 shade_color : source_color = vec3(0.76, 0.82, 0.90);
// Linear targets, calibrated against the ACES look (0.5 linear already reads near white).
uniform vec3 storm_color : source_color = vec3(0.27, 0.30, 0.345);
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
	vec3 centre = vec3(origin.x + air_drift.x, cloud_base, origin.z + air_drift.y);
	// Whole clusters shrink away near the camera instead of a dithered cut.
	float keep = view_keep(centre, 3.4 * info.x * length(MODEL_MATRIX[0].xyz), CAMERA_POSITION_WORLD, smoothstep(0.55, 0.85, info.y));
	// Tier cross-fade (zoom) also shrinks instead of dithering.
	VERTEX = centre + (VERTEX - centre) * keep * smoothstep(0.0, 1.0, fade);
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
	float dither = bayer4(FRAGCOORD.xy);
	// Close to the camera fair clouds dissolve (their shadows stay); storm fronts stay.
	vec3 to_camera = INV_VIEW_MATRIX[2].xyz;
	vec3 flat_n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	if (dot(flat_n, to_camera) < 0.0) { flat_n = -flat_n; }
	// Facets stay readable but soft: flat normal pulled towards the cluster normal.
	// Mostly flat facets: clear light/dark steps like the reference.
	vec3 n = normalize(mix(flat_n, normalize(smooth_normal), 0.15));
	vec3 l = normalize(sun_dir);
	float wrap = clamp((dot(n, l) + 0.35) / 1.35, 0.0, 1.0);
	vec3 colour = mix(shade_color, sun_color, smoothstep(0.15, 0.85, wrap));
	// Slightly bluer belly.
	colour = mix(colour, shade_color * vec3(0.94, 0.97, 1.02), smoothstep(0.35, 0.0, height01) * 0.5);
	float facing = clamp(dot(n, to_camera), 0.0, 1.0);
	// Light shining through the thin rim, strongest with the sun behind the cloud.
	float back = clamp(-dot(to_camera, l) * 0.5 + 0.5, 0.0, 1.0);
	colour += pow(1.0 - facing, 3.0) * sun_color * vec3(1.0, 0.9, 0.75) * (0.12 + 0.3 * back);
	// Rain: grey tops, darker slate bellies.
	vec3 rain_grey = vec3(0.15, 0.16, 0.18) * mix(0.65, 1.0, smoothstep(0.0, 0.6, height01)) * (0.8 + 0.4 * wrap);
	colour = mix(colour, rain_grey, grey);
	float storm_amount = smoothstep(0.02, 0.25, storm);
	vec3 slate = storm_color * (0.7 + 0.6 * wrap) + sun_color * vec3(1.0, 0.6, 0.38) * 0.5 * smoothstep(0.45, 1.0, wrap) * smoothstep(0.35, 0.95, height01) + pow(1.0 - facing, 3.0) * sun_color * vec3(1.0, 0.6, 0.4) * 0.18 * wrap;
	colour = mix(colour, slate, storm_amount);
	float near_flash = flash * (1.0 - smoothstep(0.0, flash_radius, distance(world_pos.xz, flash_pos.xz)));
	colour += near_flash * vec3(1.4, 1.45, 1.8) * (0.6 + storm);
	ALBEDO = colour * brightness;
	// Soft silhouette; rain banks are see-through (0.55-0.8) with frayed edges.
	float rim = smoothstep(0.02, 0.35, facing);
	float body = mix(1.0, mix(0.45, 0.7, rim), grey * (1.0 - storm_amount));
	ALPHA = mix(rim, 1.0, storm_amount * 0.7) * body;
}
