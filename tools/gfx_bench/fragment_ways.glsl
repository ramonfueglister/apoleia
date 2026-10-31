
uniform vec2 view_min;
uniform vec2 view_size;

void fragment() {
	vec2 p = view_min + UV * view_size;
	float fw = length(fwidth(p));
	vec3 c = GROUND_RGB[G_MEADOW];
	c = sim_ways(p, c, fw);
	COLOR = vec4(c, 1.0);
}
