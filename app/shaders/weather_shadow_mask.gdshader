shader_type canvas_item;
// Top-down cloud-shadow mask for shaders that do their own sun term (water
// glitter). 1 = full sun. Smooth cover approximation of the cloud field, offset
// along the sun; the exact cloud outlines arrive as real directional shadows.
#include "res://shaders/weather_field.gdshaderinc"

uniform vec4 ground_rect;
uniform vec2 shadow_shift;

void fragment() {
	vec2 ground = ground_rect.xy + UV * ground_rect.zw;
	vec3 field = weather_field(ground + shadow_shift);
	float mask = 1.0 - 0.85 * smoothstep(0.35, 0.75, field.x);
	COLOR = vec4(mask, mask, mask, 1.0);
}
