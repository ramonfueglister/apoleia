shader_type spatial;
// Faceted low-poly cumulus. Instances sit on a fixed air-space grid; the weather
// field decides per instance whether and how large the cloud is. Unshaded with
// its own sun model so the tops stay white under the ACES look.
// mode 0: visible cloud. mode 1: shadow proxy (SHADOWS_ONLY instances on the
// cloud layer), moved so its shadow lands just below the cloud as seen by the
// camera; only the weaker cloud sun sees this layer, so the shadow stays lighter
// than tree shadows. mode 2: the same footprint drawn top-down into the water
// cloud-shadow mask.
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_opaque, fog_disabled;
#include "res://shaders/weather_field.gdshaderinc"

uniform int mode = 0;
uniform float cloud_base = 90.0;
uniform vec3 sun_dir = vec3(-0.68, 0.64, 0.36);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 shade_color : source_color = vec3(0.62, 0.69, 0.80);
uniform vec3 storm_color : source_color = vec3(0.41, 0.44, 0.51);
uniform float brightness = 1.0;
uniform vec3 flash_pos;
uniform float flash = 0.0;
uniform float flash_radius = 80.0;
// Shadow placement (world XZ): proxy offset and the part of it removed again for the mask.
uniform vec2 proxy_shift;
uniform vec2 mask_shift;
uniform float shadow_coverage = 0.58;
instance uniform float fade = 1.0;

varying vec3 world_pos;
varying float storm;
varying float grey;
varying float tint;
varying float height01;

float deck_amount(float cover) { return smoothstep(0.55, 0.85, cover); }

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 world_xz = origin.xz + air_drift;
	vec3 field = weather_field(world_xz);
	float deck = deck_amount(field.x);
	// Under a closed deck only the tallest slots survive, as towers on top of it.
	float tower_cover = field.x - 0.62 * deck;
	float h = INSTANCE_CUSTOM.x;
	float presence = smoothstep(h - 0.07, h + 0.07, tower_cover);
	float s = presence * (0.75 + 0.6 * field.x) * (1.0 + 0.45 * deck);
	vec3 local = (VERTEX - origin) * s;
	VERTEX = vec3(world_xz.x, cloud_base + deck * 3.0, world_xz.y) + local;
	if (mode == 1) { VERTEX.xz += proxy_shift; VERTEX.y = cloud_base + local.y * 0.25; }
	if (mode == 2) { VERTEX.xz += proxy_shift + mask_shift; VERTEX.y = cloud_base + local.y * 0.25; }
	world_pos = VERTEX;
	storm = field.z;
	grey = clamp(smoothstep(0.55, 1.0, field.x) * 0.3 + field.y * 0.75 + deck * 0.35, 0.0, 1.0);
	tint = INSTANCE_CUSTOM.y;
	height01 = local.y / max(1.1 * s * length(MODEL_MATRIX[1].xyz), 0.001);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	float dither = bayer4(FRAGCOORD.xy);
	if (mode == 1) {
		ALBEDO = vec3(0.0);
	} else if (mode == 2) {
		ALBEDO = vec3(1.0 - min(shadow_coverage + 0.25 * storm, 0.95));
	} else {
		if (fade < 0.999 && fade < dither) { discard; }
		vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
		vec3 to_camera = INV_VIEW_MATRIX[2].xyz;
		if (dot(n, to_camera) < 0.0) { n = -n; }
		float facing = clamp(dot(n, to_camera), 0.0, 1.0);
		// Soft, broken silhouette instead of a hard cut-out edge.
		if (smoothstep(0.05, 0.3, facing) < dither * 0.85) { discard; }
		vec3 l = normalize(sun_dir);
		float ndl = dot(n, l);
		float lit = smoothstep(-0.2, 0.6, ndl);
		vec3 colour = mix(shade_color * 0.9, sun_color * 1.05, lit);
		colour *= mix(0.62, 1.0, smoothstep(0.05, 0.65, height01));
		// Warm sunlit rim; brighter silver lining when the sun is behind the cloud.
		float back = clamp(-dot(to_camera, l) * 0.5 + 0.5, 0.0, 1.0);
		float rim = pow(1.0 - facing, 2.5) * (clamp(ndl + 0.3, 0.0, 1.0) + back * 0.6);
		colour += rim * sun_color * vec3(1.0, 0.84, 0.62) * 0.4;
		float facet = fract(sin(dot(floor(n * 6.0), vec3(12.9898, 78.233, 37.719)) + tint * 7.0) * 43758.5453);
		colour *= 0.88 + 0.16 * facet;
		colour = mix(colour, vec3(0.30, 0.32, 0.37) * (0.7 + 0.5 * lit), grey * 0.85);
		// Storm: cool slate blue-grey with a faint violet tone; sunlit tops stay warm.
		float storm_amount = smoothstep(0.05, 0.45, storm);
		vec3 slate = storm_color * (0.7 + 0.5 * lit) + sun_color * vec3(1.0, 0.8, 0.6) * 0.16 * lit * smoothstep(0.4, 0.9, height01);
		colour = mix(colour, slate, storm_amount);
		float near_flash = flash * (1.0 - smoothstep(0.0, flash_radius, distance(world_pos.xz, flash_pos.xz)));
		colour += near_flash * vec3(1.7, 1.75, 2.1) * (0.6 + storm) * (1.0 - 0.5 * height01);
		ALBEDO = colour * brightness;
	}
}
