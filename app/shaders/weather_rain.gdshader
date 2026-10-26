shader_type spatial;
// Rain veils: crossed vertical quads under rain cells with procedural streaks.
// The quad hangs from the cloud base towards sea level and tapers downwards;
// it follows the rain field, not individual puffs, so it also hangs under decks.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/weather_field.gdshaderinc"

uniform float cloud_base = 90.0;
uniform float now = 0.0;
uniform vec3 rain_color : source_color = vec3(0.34, 0.38, 0.46);
uniform float strength = 1.0;
instance uniform float fade = 1.0;

varying float amount;
varying float seed;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 world_xz = origin.xz + air_drift;
	vec3 field = weather_field(world_xz);
	amount = smoothstep(0.2, 0.6, field.y) * INSTANCE_CUSTOM.z;
	seed = INSTANCE_CUSTOM.y;
	vec3 side = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 0.0)).xyz * 0.55 * mix(1.0, 0.45, -VERTEX.y);
	vec3 world = vec3(world_xz.x, cloud_base * (1.0 + VERTEX.y), world_xz.y) + side * step(0.001, amount);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	if (amount < 0.01) { discard; }
	float x = UV.x * 22.0 + seed * 31.0;
	float column = floor(x);
	float r = fract(sin(column * 12.9898 + seed * 78.233) * 43758.5453);
	float line = 1.0 - smoothstep(0.06, 0.2, abs(fract(x) - 0.5));
	float dash = smoothstep(0.0, 0.25, fract(UV.y * 5.0 - now * (1.6 + r) + r * 9.0)) * step(0.35, r + 0.2);
	// Streaks run out towards the ground at different lengths.
	float reach = 0.35 + 0.35 * r;
	float edge = pow(sin(3.14159 * UV.x), 1.5) * smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(reach * 0.6, reach, UV.y));
	ALBEDO = rain_color;
	ALPHA = clamp((0.2 + 0.5 * line * dash) * edge * amount * fade * strength, 0.0, 0.7);
}
