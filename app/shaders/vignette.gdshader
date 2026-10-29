// Soft vignette over the 3D view (under the HUD): the corners a little
// darker and cooler, the middle untouched.
shader_type canvas_item;

uniform float strength = 0.34;
uniform vec3 tint = vec3(0.16, 0.20, 0.32);

void fragment() {
	vec2 q = SCREEN_UV - 0.5;
	// screen units, so the darkening follows the frame (strongest in the corners)
	float v = smoothstep(0.55, 1.15, length(q) * 1.6);
	COLOR = vec4(tint, v * strength);
}
