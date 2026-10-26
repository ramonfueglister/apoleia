shader_type spatial;
// Closed low cloud deck for overcast, rain and storm: a jittered low-poly grid
// snapped to world cells. Thickness, holes and ragged edges come from the
// weather field, so the deck breaks up where cover drops. Same modes as
// weather_cloud.gdshader (0 visible, 1 dithered shadow proxy, 2 water mask).
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;
#include "res://shaders/weather_field.gdshaderinc"

uniform int mode = 0;
uniform float cloud_base = 90.0;
uniform vec2 deck_origin;      // world-cell index of the grid corner
uniform float deck_cell = 16.0;
uniform float deck_thickness = 10.0;
uniform vec3 sun_dir = vec3(-0.68, 0.64, 0.36);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 shade_color : source_color = vec3(0.62, 0.69, 0.80);
uniform vec3 storm_color : source_color = vec3(0.34, 0.36, 0.43);
uniform float brightness = 1.0;
uniform vec3 flash_pos;
uniform float flash = 0.0;
uniform float flash_radius = 80.0;
uniform vec2 proxy_shift;
uniform vec2 mask_shift;
uniform float shadow_coverage = 0.58;
instance uniform float fade = 1.0;

varying vec3 world_pos;
varying float amount;
varying float storm;
varying float grey;
varying float height01;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void vertex() {
	vec2 index = deck_origin + VERTEX.xz;
	vec2 jitter = hash2(index) - 0.5;
	vec2 world_xz = (index + jitter * 0.75) * deck_cell;
	vec3 field = weather_field(world_xz);
	amount = smoothstep(0.55, 0.85, field.x);
	float bump = 0.45 + 0.55 * hash2(index + 17.0).x;
	float top = amount * deck_thickness * bump;
	vec3 p = vec3(world_xz.x, cloud_base + top, world_xz.y);
	if (mode == 1) { p.xz += proxy_shift; p.y = cloud_base; }
	if (mode == 2) { p.xz += proxy_shift + mask_shift; p.y = cloud_base; }
	world_pos = p;
	storm = field.z;
	grey = clamp(0.35 + field.y * 0.55, 0.0, 1.0);
	height01 = bump;
	VERTEX = p;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	float dither = bayer4(FRAGCOORD.xy);
	// Ragged, dithered deck edge where cover falls off.
	if (smoothstep(0.08, 0.35, amount) < dither) { discard; }
	if (mode == 1) {
		if (dither > shadow_coverage + 0.3 * storm) { discard; }
		ALBEDO = vec3(0.0);
	} else if (mode == 2) {
		ALBEDO = vec3(1.0 - min((shadow_coverage + 0.3 * storm) * smoothstep(0.08, 0.35, amount), 0.95));
	} else {
		if (fade < 0.999 && fade < dither) { discard; }
		vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
		vec3 to_camera = INV_VIEW_MATRIX[2].xyz;
		if (dot(n, to_camera) < 0.0) { n = -n; }
		vec3 l = normalize(sun_dir);
		float lit = smoothstep(-0.3, 0.7, dot(n, l));
		vec3 colour = mix(shade_color * 0.85, sun_color, lit) * mix(0.82, 1.0, height01);
		colour = mix(colour, vec3(0.34, 0.36, 0.41) * (0.75 + 0.45 * lit), grey);
		float storm_amount = smoothstep(0.05, 0.45, storm);
		colour = mix(colour, storm_color * (0.72 + 0.45 * lit), storm_amount);
		float near_flash = flash * (1.0 - smoothstep(0.0, flash_radius, distance(world_pos.xz, flash_pos.xz)));
		colour += near_flash * vec3(1.5, 1.55, 1.9) * (0.5 + storm);
		ALBEDO = colour * brightness;
	}
}
