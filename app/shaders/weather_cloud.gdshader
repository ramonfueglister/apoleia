shader_type spatial;
// Faceted low-poly cumulus. Instances sit on a fixed air-space grid; the weather
// field decides per instance whether and how large the cloud is. Unshaded with
// its own sun model so the tops stay white under the ACES look; real directional
// shadows come from separate SHADOWS_ONLY instances of the same multimesh.
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_opaque, fog_disabled;
#include "res://shaders/weather_field.gdshaderinc"

uniform float cloud_base = 90.0;
uniform float size_boost = 1.0;
uniform vec3 sun_dir = vec3(-0.68, 0.64, 0.36);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 shade_color : source_color = vec3(0.62, 0.69, 0.80);
uniform vec3 storm_color : source_color = vec3(0.24, 0.22, 0.30);
uniform float brightness = 1.0;
uniform vec3 flash_pos;
uniform float flash = 0.0;
uniform float flash_radius = 80.0;
instance uniform float fade = 1.0;

varying vec3 world_pos;
varying float storm;
varying float grey;
varying float tint;
varying float height01;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 world_xz = origin.xz + air_drift;
	vec3 field = weather_field(world_xz);
	float h = INSTANCE_CUSTOM.x;
	float presence = smoothstep(h - 0.07, h + 0.07, field.x);
	// Dense cover widens and flattens the cells into a closed, low deck.
	float s = presence * (0.6 + 0.55 * field.x + 1.0 * field.x * field.x) * size_boost;
	float flat_deck = 1.0 - 0.45 * smoothstep(0.6, 1.0, field.x);
	VERTEX = vec3(world_xz.x, cloud_base, world_xz.y) + (VERTEX - origin) * vec3(s, s * flat_deck, s);
	world_pos = VERTEX;
	height01 = (VERTEX.y - cloud_base) / max(1.1 * s * flat_deck * length(MODEL_MATRIX[1].xyz), 0.001);
	storm = field.z;
	grey = clamp(smoothstep(0.55, 1.0, field.x) * 0.55 + field.y * 0.45, 0.0, 1.0);
	tint = INSTANCE_CUSTOM.y;
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	if (fade < 0.999 && fade < bayer4(FRAGCOORD.xy)) { discard; }
	vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	vec3 to_camera = INV_VIEW_MATRIX[2].xyz;
	if (dot(n, to_camera) < 0.0) { n = -n; }
	float ndl = dot(n, normalize(sun_dir));
	float lit = smoothstep(-0.2, 0.6, ndl);
	float under = smoothstep(0.15, -0.55, n.y);
	vec3 colour = mix(shade_color * 0.9, sun_color * 1.05, lit);
	// Blue-grey belly, bright crown.
	colour *= mix(0.62, 1.0, smoothstep(0.05, 0.65, height01));
	colour = mix(colour, shade_color * 0.8, under * 0.7);
	// Warm sunlit rim, as on the reference cumulus.
	float rim = pow(1.0 - clamp(dot(n, to_camera), 0.0, 1.0), 3.0) * clamp(ndl + 0.3, 0.0, 1.0);
	colour += rim * sun_color * vec3(1.0, 0.82, 0.58) * 0.35;
	// Per-facet tone so the low-poly read survives at small sizes.
	float facet = fract(sin(dot(floor(n * 6.0), vec3(12.9898, 78.233, 37.719)) + tint * 7.0) * 43758.5453);
	colour *= 0.88 + 0.16 * facet;
	colour = mix(colour, vec3(0.19, 0.205, 0.245) * (0.75 + 0.45 * lit), grey);
	colour = mix(colour, storm_color * (0.8 + 0.6 * lit), smoothstep(0.05, 0.45, storm));
	float near_flash = flash * (1.0 - smoothstep(0.0, flash_radius, distance(world_pos.xz, flash_pos.xz)));
	colour += near_flash * vec3(1.6, 1.65, 2.0) * (0.5 + storm);
	ALBEDO = colour * brightness;
}
