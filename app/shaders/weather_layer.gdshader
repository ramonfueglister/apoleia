shader_type spatial;
// Continental view (no 3D clouds there): a flat, translucent cloud layer at the
// cloud base, only where the weather field forms banks or fronts (rain/storm).
// Fair weather leaves it empty, so the far view stays as calm as the reference.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/weather_field.gdshaderinc"

uniform float cloud_base = 90.0;
uniform vec3 storm_color : source_color = vec3(0.24, 0.245, 0.29);
uniform vec3 rain_color : source_color = vec3(0.62, 0.65, 0.70);
uniform float layer_fade = 1.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec3 field = weather_field(world_xz);
	float detail = texture(weather_noise, (world_xz - air_drift) / (noise_period * 0.17)).r;
	float body = smoothstep(0.3, 0.7, field.x + (detail - 0.5) * 0.25);
	if (body < 0.01) { discard; }
	float storm = smoothstep(0.05, 0.4, field.z);
	ALBEDO = mix(rain_color * (0.85 + 0.3 * detail), storm_color, storm);
	ALPHA = body * mix(0.32, 0.6, max(storm, field.y)) * layer_fade;
}
