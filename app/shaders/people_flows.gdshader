// What the dealers carried between the markets (people_flows.gd): flat
// ribbons over the land in the colour of the good, with dashes running
// from the market the goods came from to the one they went to. UV.x is km
// along the arc, UV.y across (-1 … 1).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float dash_km = 10.0; // one dash and its gap
uniform float speed = 0.6;    // dashes a second

void fragment() {
	float run = fract(UV.x / dash_km - TIME * speed);
	float dash = smoothstep(0.0, 0.08, run) * (1.0 - smoothstep(0.5, 0.58, run));
	float edge = 1.0 - smoothstep(0.75, 1.0, abs(UV.y));
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * mix(0.7, 1.15, dash);
	ALPHA = edge * mix(0.55, 0.95, dash);
}
